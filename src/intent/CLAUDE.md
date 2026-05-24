# src/intent/ — Natural Language Intent Parser

**Role:** Entry point for Proactive Mode. Converts a natural language deployment description into a structured, typed `DeploymentIntent` model.

## What lives here

```
src/intent/
├── parser.py          # Main parse_intent(text: str) → DeploymentIntent
├── extractor.py       # LLM-backed field extraction with validation
├── models.py          # DeploymentIntent and all sub-models (Pydantic v2)
├── validator.py       # Schema-level validation of extracted intent
└── tests/
    └── test_parser.py
```

## Critical rules

### 1. One LLM call maximum

`extractor.py` makes exactly one structured LLM call using tool/function calling to extract all `DeploymentIntent` fields in a single pass. No chained prompts, no follow-up clarification calls, no streaming.

If a field cannot be extracted with confidence, it must be set to `None` in `DeploymentIntent`. Downstream modules (`config_gen/`) apply knowledge library defaults for `None` fields. The extractor never invents a value — it extracts or leaves `None`.

### 2. All outputs are Pydantic v2 models

`DeploymentIntent` is the canonical contract between `src/intent/` and `src/config_gen/`. It must be a valid, serializable Pydantic model. No raw dicts passed downstream.

```python
class DeploymentIntent(BaseModel):
    model_name: str                          # e.g. "meta-llama/Meta-Llama-3.1-70B-Instruct"
    runtime: RuntimeType                     # vllm | kserve | ray_serve | triton
    gpu_type: GPUType | None                 # A100 | H100 | A10G | ...
    gpu_count: int | None                    # number of GPUs
    gpu_memory_gib: int | None               # per-GPU VRAM in GiB (from GPUType registry)
    autoscaling: AutoscalingConfig | None    # HPA/KEDA config or None
    model_cache: ModelCacheConfig | None     # PVC config or None
    namespace: str | None                    # target namespace or None
    replicas: int | None                     # fixed replicas or None (use autoscaling)
    hf_token_required: bool                  # whether model needs HF auth
    tensor_parallel: bool                    # whether to use tensor parallelism
    raw_input: str                           # original user text (always set)
    extraction_confidence: float             # 0.0–1.0, from LLM extraction
```

### 3. Confidence threshold gate

`parser.py` must check `extraction_confidence` before returning:

- `>= 0.7` → return `DeploymentIntent` normally
- `0.5–0.7` → return with `confidence_warning: True`, caller decides whether to proceed
- `< 0.5` → raise `IntentExtractionError` with a message listing which fields are missing

Do not proceed to config generation with `extraction_confidence < 0.5`. The Config Generator will produce an unsafe config with too many defaulted fields.

### 4. Never call the cluster from this module

`src/intent/` is a pure transformation: text → structured model. It has no Kubernetes client dependency. Cluster context (validating that the requested GPU type actually exists in the cluster) is the responsibility of `src/config_gen/cluster_validator.py`.

### 5. GPUType registry is the source of truth for VRAM

```python
GPU_VRAM_GIB = {
    GPUType.A10G:    24,
    GPUType.A100_40: 40,
    GPUType.A100_80: 80,
    GPUType.H100_80: 80,
    GPUType.H100_NVL: 94,
    GPUType.RTX_4090: 24,
}
```

When the user says "A100", assume A100 80GB unless "40GB" is explicitly stated. Log the assumption in `extraction_confidence` metadata.

## Testing requirements

`tests/unit/test_intent/test_parser.py` must cover:
- Full intent extraction (all fields present in input)
- Partial intent (some fields missing → None)
- Ambiguous GPU type (A100 without size specification)
- Private model (HF token detection)
- Invalid input (empty string, non-deployment query)
- Confidence threshold gating

No integration tests call the real LLM — use `pytest-mock` to stub `extractor.py`.
