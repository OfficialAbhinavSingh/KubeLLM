# Skill: Generate Deployment Config (Proactive Mode)

Use this skill when asked to "generate a config", "create a deployment", "write Helm values", "deploy X model", or anything involving creating new infrastructure for an LLM workload.

---

## When to use

- User describes a model they want to deploy
- User asks to "create a vLLM deployment for X"
- User provides a natural language deployment intent
- User asks to "write the Helm values for Y on Z GPUs"

---

## Protocol

### 1. Parse the intent — extract these fields

Extract explicitly from the user's input. Do not invent values for missing fields — use knowledge library defaults instead.

| Field | Extract from | Default if missing |
|---|---|---|
| `model_name` | User input | REQUIRED — ask if missing |
| `runtime` | User input | Infer from model + context; default `vllm` |
| `gpu_type` | User input | REQUIRED — ask if missing |
| `gpu_count` | User input | Minimum viable for model size (see GPU math) |
| `autoscaling` | User input | HPA on `gpu_memory_utilization` if mentioned |
| `model_cache` | User input | `enabled: true` if not specified |
| `namespace` | User input | `inference` (default namespace) |
| `replicas` | User input | 1 if no autoscaling specified |

**Emit the parsed intent as structured output before proceeding:**
```json
{
  "model_name": "meta-llama/Meta-Llama-3.1-70B-Instruct",
  "runtime": "vllm",
  "gpu_type": "A100",
  "gpu_count": 2,
  "autoscaling": {"type": "hpa", "metric": "gpu_memory_utilization"},
  "model_cache": {"enabled": true, "size": "200Gi"},
  "namespace": "inference",
  "confidence": "high"
}
```

### 2. GPU memory math — do this before generating config

```
model_vram_gib = parameters_billions * dtype_bytes / 1_073_741_824
# float16 = 2 bytes, int8 = 1 byte, bfloat16 = 2 bytes

kv_cache_gib = model_vram_gib * 0.20   (20% overhead)
system_gib = 2

total_required = model_vram_gib + kv_cache_gib + system_gib

gpu_available_gib = gpu_count * gpu_vram_gib * 0.95  (5% driver overhead)

if total_required > gpu_available_gib:
    # Flag in PR: VRAM tight, adjust gpu_memory_utilization
    gpu_memory_utilization = (gpu_available_gib / total_required) * 0.95
else:
    gpu_memory_utilization = 0.90  (default safe value)
```

**Common GPU VRAM values:**
| GPU | VRAM |
|---|---|
| A10G | 24 GiB |
| A100 40GB | 40 GiB |
| A100 80GB | 80 GiB |
| H100 80GB | 80 GiB |
| H100 NVL 94GB | 94 GiB |
| RTX 4090 | 24 GiB |

### 3. Apply knowledge library defaults

**Startup probe windows (NEVER use Kubernetes defaults for vLLM):**
| Model size | failureThreshold | periodSeconds | Total window |
|---|---|---|---|
| ≤7B | 30 | 10 | 5 min |
| 7B–30B | 60 | 10 | 10 min |
| 30B–70B | 120 | 10 | 20 min |
| 70B+ | 240 | 10 | 40 min |

**GPU scheduling (always include both):**
```yaml
nodeSelector:
  nvidia.com/gpu.present: "true"   # adjust to actual cluster label
tolerations:
  - key: "nvidia.com/gpu"
    operator: "Exists"
    effect: "NoSchedule"
```

**Memory limits (vLLM):**
```
memory_request = total_required_gib * 1.2  (20% buffer)
memory_limit = memory_request * 1.5
```

### 4. Generate the Helm values file

Generate a complete `values.yaml`. Never leave production-critical fields empty or at Kubernetes defaults. Required fields for every vLLM deployment:

```yaml
# Required — fill from intent
replicaCount: <N>
image:
  repository: vllm/vllm-openai
  tag: latest   # pin to specific version in production

# Required — model config
vllm:
  model: "<model_name>"
  dtype: "float16"
  gpu_memory_utilization: <calculated>
  tensor_parallel_size: <gpu_count>
  max_model_len: 4096   # adjust per model context window

# Required — GPU scheduling
nodeSelector:
  <gpu_label_key>: "<gpu_label_value>"
tolerations:
  - key: "nvidia.com/gpu"
    operator: "Exists"
    effect: "NoSchedule"

resources:
  requests:
    nvidia.com/gpu: <gpu_count>
    memory: "<memory_request>Gi"
    cpu: "8"
  limits:
    nvidia.com/gpu: <gpu_count>
    memory: "<memory_limit>Gi"
    cpu: "16"

# Required — probes (NEVER use defaults for vLLM)
startupProbe:
  httpGet:
    path: /health
    port: 8000
  failureThreshold: <from knowledge library>
  periodSeconds: 10

readinessProbe:
  httpGet:
    path: /health
    port: 8000
  initialDelaySeconds: 5
  periodSeconds: 10
  failureThreshold: 3

livenessProbe:
  httpGet:
    path: /health
    port: 8000
  initialDelaySeconds: 60
  periodSeconds: 30
  failureThreshold: 3

# Required if model caching enabled
persistence:
  enabled: true
  storageClass: "standard"
  size: "<model_size_gib * 1.2>Gi"
  mountPath: /root/.cache/huggingface

# Required if HuggingFace private model
env:
  - name: HF_TOKEN
    valueFrom:
      secretKeyRef:
        name: hf-token-secret   # reference only — never value
        key: token
```

### 5. Validate before presenting

Run mentally through this checklist before presenting the config:

- [ ] startupProbe window appropriate for model size tier
- [ ] GPU count matches tensor_parallel_size
- [ ] Memory request includes KV cache buffer
- [ ] Model cache PVC size ≥ model size × 1.2
- [ ] HF_TOKEN is a secretKeyRef, never a raw value
- [ ] nodeSelector label is realistic (not invented)
- [ ] HPA metric is a real Prometheus metric (not invented)

### 6. Present with resource summary

Always present the generated config alongside a resource summary:

```
Model: Llama 3.1 70B (float16)
VRAM required: ~170 GiB
GPU configured: 2× A100 80GB = 160 GiB usable
gpu_memory_utilization: 0.90 (tight — see note in config)
Startup probe window: 40 minutes (appropriate for 70B)
Model cache PVC: 200 GiB
Estimated cost: ~$X.XX/hr (at standard GPU cloud rates)
```

---

## What NOT to do

- Do not use Kubernetes default probe values for vLLM (they will kill the pod before model loads)
- Do not invent GPU node labels — note in the config that the user must verify their label
- Do not generate HuggingFace token values — always use `secretKeyRef`
- Do not skip the GPU memory math — wrong `gpu_memory_utilization` causes CUDA OOM
- Do not set `tensor_parallel_size` > `gpu_count` — this will crash vLLM
- Do not open a non-draft PR for proactive configs — all proactive PRs require approval
