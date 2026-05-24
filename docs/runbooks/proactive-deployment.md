# Runbook: Proactive Deployment Config Generation

**Use when:** You want to deploy a new LLM inference workload using `kubellm generate`, or you need to review/debug a proactively generated config before approving the PR.

---

## Step 1: Write a good intent description

The intent parser works best with specific descriptions. Include:

| What to specify | Example |
|---|---|
| Model name or family | `Llama 3.1 70B`, `Mistral 7B Instruct`, `Qwen 2.5 32B` |
| Runtime (optional, inferred if not given) | `vLLM`, `KServe`, `Ray Serve` |
| GPU type and count | `2 A100 80GB`, `4 H100`, `1 A10G` |
| Scaling behavior | `autoscaling`, `fixed 2 replicas`, `scale to zero` |
| Caching requirement | `with model caching`, `no caching` |
| Namespace (optional) | `in namespace inference-prod` |
| Special requirements | `with HuggingFace private repo`, `tensor parallel` |

**Good intents:**
```bash
kubellm generate "deploy Llama 3.1 70B on 2 A100 80GB with model caching and HPA on GPU memory"
kubellm generate "deploy Mistral 7B on a single A10G, fixed 2 replicas, inference namespace"
kubellm generate "KServe InferenceService for Qwen 2.5 32B on 2 H100, scale to zero after 10 minutes idle"
```

**Weak intents (will produce LOW confidence output):**
```bash
kubellm generate "deploy a big model"              # no model, no hardware
kubellm generate "deploy llama fast"               # no GPU, no runtime
```

---

## Step 2: Run the generator

```bash
# Preview only — no PR, prints config to stdout
kubellm generate "deploy Llama 3.1 70B on 2 A100s with autoscaling"

# Generate and open draft PR
kubellm generate \
  --pr \
  --repo your-org/infra-repo \
  --base main \
  "deploy Llama 3.1 70B on 2 A100s with autoscaling"
```

**Output you'll see before PR creation:**
```
[intent]    Parsed: model=llama3.1-70b, runtime=vllm, gpu=A100×2, autoscaling=HPA
[cluster]   Found 3 nodes with label gpu=true, A100 80GB confirmed
[math]      VRAM required: ~170 GiB | Available: 2×80 GiB = 160 GiB
[math]      Adjusting gpu_memory_utilization to 0.90 (tight fit, noted in PR)
[knowledge] Applied: startupProbe window=240s (XLARGE tier), memory=48Gi
[validate]  kubeconform: PASS | helm template: PASS
[pr]        Draft PR opened: feat(vllm): deploy llama3-70b with GPU autoscaling
```

---

## Step 3: Review the generated PR

Open the draft PR. Review in this order:

### 3a. Check resource math

The PR body includes a resource math table:

```markdown
## Resource Math
| Resource       | Calculated | Configured |
|---|---|---|
| VRAM required  | ~170 GiB   | 2× A100 80GB (160 GiB usable) |
| gpu_memory_utilization | 0.90 | 0.90 |
| CPU request    | 8 cores    | 8 |
| Memory request | 32 GiB     | 32Gi |
| PVC size       | 200 GiB    | 200Gi |
```

Verify:
- VRAM calculation looks right for the model size
- `gpu_memory_utilization` is not >0.95 (leaves no headroom for KV cache spikes)
- Memory request is realistic for the runtime overhead

### 3b. Check probe windows

Find `startupProbe` in the generated values:
```yaml
startupProbe:
  failureThreshold: 240
  periodSeconds: 10
  # Total window: 40 minutes — appropriate for 70B model on 2 A100s
```

If the window looks too short for your hardware (slower GPU, slower network storage), increase `failureThreshold` before approving.

### 3c. Check GPU scheduling config

```yaml
nodeSelector:
  gpu: "true"
tolerations:
  - key: "nvidia.com/gpu"
    operator: "Exists"
    effect: "NoSchedule"
```

Verify the `nodeSelector` label matches your actual GPU node labels:
```bash
kubectl get nodes --show-labels | grep gpu
```

### 3d. Check PVC config (if model caching is enabled)

```yaml
volumes:
  - name: model-cache
    persistentVolumeClaim:
      claimName: vllm-model-cache
volumeMounts:
  - name: model-cache
    mountPath: /root/.cache/huggingface
```

Verify the storage class is available in your cluster:
```bash
kubectl get storageclass
```

---

## Step 4: Approve or request changes

**Approve (if everything looks correct):**
```bash
kubellm approve --source-type proactive --source-id <intent_id>
# or approve via GitHub PR review
```

**Request config changes before approving:**
- Edit the branch directly and push your changes
- Or comment on the PR with specific changes needed
- The PR will remain draft until explicitly marked ready

---

## Step 5: Monitor the deployment

After the PR merges and GitOps deploys:

```bash
# Watch pod startup (model loading takes time)
kubectl get pod -n inference -w

# Check logs during startup
kubectl logs -n inference <pod-name> -f

# Verify endpoint after Ready
kubellm verify --source-type proactive --source-id <intent_id>
```

If the pod is stuck in `ContainerCreating` or `Init:0/1` for > 5 minutes:
```bash
kubectl describe pod -n inference <pod-name>
# Look for: image pull progress, PVC mounting, init container logs
```

---

## Common proactive mode issues

| Issue | Cause | Fix |
|---|---|---|
| `gpu_memory_utilization` capped at 0.90 | VRAM tight for model size | Use larger GPU or smaller model |
| `cluster_context: gpu_nodes_not_found` | No nodes with GPU label | Add GPU nodes or fix node labels |
| `validation: storage_class_not_found` | Storage class in config doesn't exist | Add `--storage-class <name>` flag |
| `confidence: LOW` | Intent too vague | Add model name, GPU type, GPU count |
| PR body missing resource math | VRAM calculation failed | File a bug; run with `--verbose` for details |
