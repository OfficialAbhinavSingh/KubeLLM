# src/config_gen/ — Config Generator

**Role:** Takes a validated `DeploymentIntent` and live cluster context, produces a complete, production-ready Helm values file or raw YAML. This is the core of Proactive Mode.

## What lives here

```
src/config_gen/
├── generator.py         # Main generate(intent, cluster_ctx) → GeneratedConfig
├── cluster_validator.py # Validates intent against live cluster state
├── gpu_math.py          # VRAM calculation, gpu_memory_utilization, tensor parallel
├── renderer.py          # DeploymentSpec → Helm values YAML or raw YAML
├── models.py            # GeneratedConfig, DeploymentSpec, ClusterContext (Pydantic v2)
└── tests/
    └── test_generator.py
```

## The generation pipeline

```python
def generate(intent: DeploymentIntent, cluster_ctx: ClusterContext) -> GeneratedConfig:
    # 1. Validate intent against cluster
    cluster_validator.validate(intent, cluster_ctx)  # raises if GPU not available

    # 2. GPU memory math
    vram_calc = gpu_math.calculate(intent)

    # 3. Build DeploymentSpec from intent + math + knowledge defaults
    spec = DeploymentSpec(
        model_name=intent.model_name,
        runtime=intent.runtime,
        gpu_count=intent.gpu_count,
        gpu_memory_utilization=vram_calc.gpu_memory_utilization,
        tensor_parallel_size=intent.gpu_count if intent.tensor_parallel else 1,
        startup_probe=knowledge.get_probe_config(intent.runtime, vram_calc.model_size_tier),
        resources=knowledge.get_resource_config(intent.runtime, vram_calc),
        node_selector=cluster_ctx.gpu_node_selector,    # from actual cluster labels
        tolerations=knowledge.get_gpu_tolerations(),
        pvc=knowledge.get_pvc_config(vram_calc.model_size_gib) if intent.model_cache else None,
        hpa=knowledge.get_hpa_config(intent.runtime) if intent.autoscaling else None,
        hf_token_ref="hf-token-secret" if intent.hf_token_required else None,
    )

    # 4. Render to YAML
    raw_yaml = renderer.render(spec)

    # 5. Return with resource summary for PR body
    return GeneratedConfig(
        spec=spec,
        raw_yaml=raw_yaml,
        vram_calc=vram_calc,
        cluster_ctx=cluster_ctx,
        confidence=ConfigConfidence.MEDIUM,  # always MEDIUM until first deployment confirms
    )
```

## Critical rules

### 1. Cluster validator runs before any config is generated

`cluster_validator.py` checks:
- GPU node count ≥ `intent.gpu_count`
- GPU node selector label exists and is correct
- Requested storage class exists
- Namespace exists (or will be created — flag this)

If validation fails: raise `ClusterValidationError` with specific reason. Do not generate a config for a cluster that cannot support it.

### 2. gpu_memory_utilization is always calculated, never defaulted

```python
# gpu_math.py
def calculate(intent: DeploymentIntent) -> VRAMCalculation:
    model_params_b = get_parameter_count(intent.model_name)  # from model registry
    dtype_bytes = DTYPE_BYTES[intent.dtype]  # float16=2, int8=1, bfloat16=2

    model_vram_gib = (model_params_b * 1e9 * dtype_bytes) / (1024**3)
    kv_cache_gib = model_vram_gib * 0.20
    system_gib = 2.0
    total_required_gib = model_vram_gib + kv_cache_gib + system_gib

    gpu_available_gib = intent.gpu_count * intent.gpu_memory_gib * 0.95

    if total_required_gib > gpu_available_gib:
        # Tight fit — reduce utilization and flag in PR
        gpu_memory_utilization = (gpu_available_gib / total_required_gib) * 0.95
        tight_fit = True
    else:
        gpu_memory_utilization = 0.90
        tight_fit = False

    return VRAMCalculation(
        model_vram_gib=model_vram_gib,
        total_required_gib=total_required_gib,
        gpu_available_gib=gpu_available_gib,
        gpu_memory_utilization=gpu_memory_utilization,
        tight_fit=tight_fit,
        model_size_tier=classify_model_size(model_params_b),
    )
```

### 3. Node selector comes from cluster, not from hardcoded defaults

`cluster_validator.py` reads actual node labels from the cluster via `src/integrations/kubernetes_client.py`. The `nodeSelector` in the generated config uses the label that the cluster's GPU nodes actually have — not a guess.

```python
# cluster_validator.py
def get_gpu_node_selector(cluster_ctx: ClusterContext) -> dict[str, str]:
    gpu_labels = ["nvidia.com/gpu.present", "gpu", "node-role.kubernetes.io/gpu"]
    for label in gpu_labels:
        if label in cluster_ctx.gpu_node_labels:
            return {label: cluster_ctx.gpu_node_labels[label]}
    raise ClusterValidationError("No GPU label found on cluster nodes")
```

### 4. GeneratedConfig confidence is always MEDIUM

Generated configs are always `ConfigConfidence.MEDIUM` on first generation. They become `HIGH` only after the Verification Agent confirms a successful deployment. This is enforced in `models.py`:

```python
class GeneratedConfig(BaseModel):
    confidence: ConfigConfidence = ConfigConfidence.MEDIUM  # never HIGH on generation
    ...
```

The Safety Agent requires `REQUIRE_APPROVAL` for all `MEDIUM` confidence proactive configs. This cannot be overridden without a policy change.

### 5. No LLM calls in this module

`src/config_gen/` is fully deterministic. No LLM calls. The LLM was used in `src/intent/` to extract the intent. Config generation is math + knowledge library + template rendering.

If you find yourself wanting to ask the LLM "what should the memory limit be?", that information belongs in `src/knowledge/` as a deterministic rule.

## Testing requirements

All tests use fixture `DeploymentIntent` and `ClusterContext` objects — no real cluster calls.

Required test cases:
- Standard generation (Llama 70B, 2×A100 80GB) — full output validation
- Tight VRAM fit — verify `gpu_memory_utilization` reduced correctly
- Missing GPU nodes — verify `ClusterValidationError` raised
- Tensor parallel enabled — verify `tensor_parallel_size = gpu_count`
- Model cache disabled — verify no PVC in output
- HF token required — verify `secretKeyRef`, never raw value
