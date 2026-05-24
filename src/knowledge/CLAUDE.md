# src/knowledge/ — Best-Practice Config Library

**Role:** Deterministic, versioned library of production-safe defaults for LLM inference runtimes. Every default is sourced from a real failure pattern in the reactive system.

## What lives here

```
src/knowledge/
├── registry.py          # Main lookup: get_defaults(runtime, model_size_tier, gpu_type)
├── vllm/
│   ├── probes.py        # startupProbe / readiness / liveness windows by model tier
│   ├── resources.py     # CPU/memory ratios for vLLM containers
│   ├── gpu_config.py    # tensor_parallel, gpu_memory_utilization, quantization
│   └── hpa.py           # HPA metric, target utilization, min/max replicas
├── kserve/
│   ├── probes.py
│   ├── resources.py
│   └── inference_service.py   # InferenceService spec defaults
├── common/
│   ├── pvc.py           # Model cache PVC size, storage class, mount paths
│   ├── gpu_scheduling.py  # nodeSelector patterns, tolerations
│   └── secrets.py       # Secret reference patterns
└── tests/
    └── test_coverage.py # Asserts every failure type has a knowledge entry
```

## The coupling rule (enforced by test)

**Every failure type in `src/agents/model_runtime/rules.py` must have a corresponding entry in this library that prevents it.**

`tests/unit/test_knowledge_coverage.py` auto-discovers all `FailureType` enum values and asserts each has a corresponding knowledge entry. This test will fail if you add a new failure type without updating the knowledge library, and vice versa.

```python
# test_knowledge_coverage.py
def test_all_failure_types_have_knowledge_entry():
    for failure_type in FailureType:
        assert knowledge.registry.has_prevention_for(failure_type), \
            f"FailureType.{failure_type.name} has no knowledge library entry. " \
            f"Add the prevention default to src/knowledge/ before adding the rule."
```

## Current entries and their failure type source

| Knowledge entry | Prevents reactive FailureType |
|---|---|
| `vllm.probes.STARTUP_PROBE_WINDOWS` | `startup_probe_failure` |
| `common.gpu_scheduling.GPU_TOLERATIONS` | `gpu_pending_toleration` |
| `common.gpu_scheduling.GPU_NODE_SELECTOR_LABELS` | `gpu_pending_node_selector` |
| `vllm.resources.MEMORY_RATIO` | `oom_killed` |
| `common.pvc.MODEL_CACHE_MOUNT_PATH` | `pvc_not_mounted` |
| `vllm.gpu_config.GPU_MEMORY_UTILIZATION_DEFAULT` | `cuda_oom` |

## Rules for this module

### 1. All values are constants — no computation

`src/knowledge/` contains only constants and simple lookup functions. No GPU math, no LLM calls, no cluster queries. Those belong in `src/config_gen/`.

```python
# Good — pure constant lookup
STARTUP_PROBE_WINDOWS = {
    ModelSizeTier.SMALL:  ProbeConfig(failureThreshold=30,  periodSeconds=10),
    ModelSizeTier.MEDIUM: ProbeConfig(failureThreshold=60,  periodSeconds=10),
    ModelSizeTier.LARGE:  ProbeConfig(failureThreshold=120, periodSeconds=10),
    ModelSizeTier.XLARGE: ProbeConfig(failureThreshold=240, periodSeconds=10),
}

# Bad — computation belongs in config_gen/
def get_probe(model_params: float) -> ProbeConfig:
    tier = classify(model_params)  # this belongs in config_gen
    return STARTUP_PROBE_WINDOWS[tier]
```

### 2. Adding a new runtime requires all sub-modules

When adding a new runtime (e.g., Triton), create:
- `src/knowledge/triton/probes.py`
- `src/knowledge/triton/resources.py`
- `src/knowledge/triton/model_repository.py`

And register in `registry.py`. Incomplete runtime entries will cause `ConfigGenerator` to fall back to unsafe Kubernetes defaults.

### 3. Versioning

When a new major version of vLLM or KServe changes default behavior (e.g., a new health check path), update the knowledge library in the same PR that updates the failure rules. Tag the change in the commit message: `knowledge(vllm): update probe path for vllm>=0.5`.

### 4. Secret values are never in this library

`common/secrets.py` contains only the pattern for referencing secrets, never any values:

```python
# secrets.py — pattern only
HF_TOKEN_SECRET_REF = {
    "name": "hf-token-secret",
    "key": "token",
}
# Users create the actual secret manually. This library never touches it.
```

## Model size tier classification

```python
class ModelSizeTier(Enum):
    SMALL  = "small"   # ≤ 7B parameters
    MEDIUM = "medium"  # 7B – 30B
    LARGE  = "large"   # 30B – 70B
    XLARGE = "xlarge"  # 70B+

def classify_model_size(params_billions: float) -> ModelSizeTier:
    if params_billions <= 7:   return ModelSizeTier.SMALL
    if params_billions <= 30:  return ModelSizeTier.MEDIUM
    if params_billions <= 70:  return ModelSizeTier.LARGE
    return ModelSizeTier.XLARGE
```
