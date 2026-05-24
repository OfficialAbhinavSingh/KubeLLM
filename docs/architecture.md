# KubeLLM — System Architecture

**Version:** 2.0 (Dual-Mode: Proactive + Reactive)
**Status:** MVP design
**Last updated:** 2026-05-24

---

## 1. System overview

KubeLLM is a dual-mode AI infrastructure system for LLM/GPU workloads on Kubernetes.

- **Proactive Mode:** Natural language → validated Helm/YAML config → GitOps PR
- **Reactive Mode:** Failure detection → root cause analysis → safe fix → GitOps PR

Both modes share a common engine: the Safety Agent, GitOps Fix Agent, Validation Pipeline, and Verification Agent. No mode ever writes to a production cluster.

```
╔════════════════════════════════════════════════════════════════╗
║                        ENTRY POINTS                           ║
╠═══════════════════════════╦════════════════════════════════════╣
║   PROACTIVE MODE           ║   REACTIVE MODE                   ║
║                            ║                                   ║
║  kubellm generate "..."    ║  kubellm scan / AlertManager      ║
║         ↓                  ║         ↓                         ║
║   Intent Parser            ║   Cluster Watcher Agent           ║
║   (NL → DeploymentIntent)  ║   (pod/event/node health)        ║
║         ↓                  ║         ↓                         ║
║   Config Generator         ║   Evidence Collection             ║
║   + Knowledge Library      ║   (GPU/log/PVC/node agents)      ║
╚═══════════════╦════════════╩══════════════╦═══════════════════╝
                ║                           ║
                ╚══════════╦════════════════╝
                           ↓
              ┌────────────────────────┐
              │     Safety Agent       │
              │  (policy gate — always)│
              │  allow/approve/block   │
              └────────────┬───────────┘
                           ↓
              ┌────────────────────────┐
              │   GitOps Fix Agent     │
              │  (shared — both modes) │
              │  locate → patch/gen →  │
              │  validate → open PR    │
              └────────────┬───────────┘
                           ↓
              ┌────────────────────────┐
              │   Human Approval       │
              │  (GitHub PR review)    │
              └────────────┬───────────┘
                           ↓
              ┌────────────────────────┐
              │   GitOps Deploy        │
              │  (ArgoCD / Flux)       │
              └────────────┬───────────┘
                           ↓
              ┌────────────────────────┐
              │  Verification Agent    │
              │  (shared — both modes) │
              │  pod health + endpoint │
              └────────────────────────┘
```

---

## 2. Proactive Mode — Config Generation Pipeline

### 2.1 Intent Parser (`src/intent/`)

Converts natural language input into a structured `DeploymentIntent` model.

**Input:**
```
"deploy Llama 3.1 70B on 2 A100s with autoscaling and model caching"
```

**Output (`DeploymentIntent`):**
```python
DeploymentIntent(
    model_name="meta-llama/Meta-Llama-3.1-70B-Instruct",
    runtime=RuntimeType.VLLM,
    gpu_type="A100",
    gpu_count=2,
    autoscaling=AutoscalingConfig(
        type=ScalingType.HPA,
        metric="gpu_memory_utilization",
        min_replicas=1,
        max_replicas=4,
    ),
    model_cache=ModelCacheConfig(
        enabled=True,
        storage_class="standard",
        size="200Gi",
    ),
    namespace=None,   # resolved from cluster context
)
```

**LLM usage:** One structured extraction call. Output is validated against `DeploymentIntent` schema. Any fields that cannot be reliably extracted are left as `None` and filled by defaults from `src/knowledge/`.

### 2.2 Config Generator (`src/config_gen/`)

Takes `DeploymentIntent` + live cluster state and produces a complete, production-ready configuration.

**Steps:**
1. **Cluster context resolution** — query live cluster for available GPU nodes, labels, taints, available storage classes, existing namespaces
2. **Resource math** — compute required GPU memory for the model size + KV cache, validate against available GPU
3. **Knowledge injection** — apply best-practice defaults from `src/knowledge/` (probe windows, resource ratios, HPA settings)
4. **Config assembly** — render final Helm values or raw YAML
5. **Annotation** — add `kubellm.io/intent`, `kubellm.io/generated-at`, `kubellm.io/confidence` labels

**GPU resource math (vLLM example):**
```
Model size (parameters × dtype bytes) = base VRAM
KV cache overhead = base VRAM × 0.2 (configurable)
System overhead = 2 GiB
Total required = base + KV cache + system

Example: Llama 70B in float16
= 70B × 2 bytes = 140 GiB
+ 28 GiB KV cache
+ 2 GiB system
= ~170 GiB → requires 2× A100 80GB (160 GiB usable with NVLink)
```

If required VRAM > available: generate config with reduced `gpu_memory_utilization` and a PR comment explaining the constraint.

### 2.3 Knowledge Library (`src/knowledge/`)

Static best-practice configurations, organized by runtime and model size tier.

**Structure:**
```
src/knowledge/
├── vllm/
│   ├── probes.py          # startupProbe / readinessProbe windows by model size
│   ├── resources.py       # CPU/memory ratios for vLLM containers
│   ├── gpu_config.py      # tensor_parallel_size, gpu_memory_utilization defaults
│   └── hpa.py             # HPA metrics and thresholds for vLLM
├── kserve/
│   ├── probes.py
│   ├── resources.py
│   └── inference_service.py
├── common/
│   ├── pvc.py             # Model cache PVC configs
│   ├── gpu_scheduling.py  # nodeSelector + toleration patterns
│   └── secrets.py         # Secret reference patterns (never values)
└── registry.py            # Lookup: (runtime, model_size_tier) → defaults
```

**Probe window defaults (vLLM):**
```python
STARTUP_PROBE_WINDOWS = {
    ModelSizeTier.SMALL:   {"failureThreshold": 30,  "periodSeconds": 10},  # ≤ 7B
    ModelSizeTier.MEDIUM:  {"failureThreshold": 60,  "periodSeconds": 10},  # 7B–30B
    ModelSizeTier.LARGE:   {"failureThreshold": 120, "periodSeconds": 10},  # 30B–70B
    ModelSizeTier.XLARGE:  {"failureThreshold": 240, "periodSeconds": 10},  # 70B+
}
```

This prevents the #1 vLLM failure mode (startup probe too aggressive) from happening at all when deploying via KubeLLM.

---

## 3. Reactive Mode — Diagnosis Pipeline

### 3.1 Cluster Watcher Agent (`src/agents/cluster_watcher/`)

Polls Kubernetes API or receives webhook triggers. Detects unhealthy inference workloads.

**Triggers:**
- Scheduled poll (default: 60s)
- Prometheus AlertManager webhook
- Manual `kubellm scan` CLI call

**Output:** `IncidentDraft` with initial failure signals

### 3.2 Evidence Collection Agents

| Agent | Checks |
|---|---|
| `gpu_scheduler/` | GPU requests, node selectors, taints, device plugin health |
| `model_runtime/` | vLLM/KServe/Ray/Triton log patterns, probe config vs load time |
| `autoscaling/` | HPA/KEDA config, cold start latency, scaling metrics |

Each agent independently scores evidence and returns `EvidenceItem[]`.

### 3.3 Root Cause Engine (`src/agents/root_cause/`)

Aggregates evidence from all collection agents. Runs deterministic rules from `src/agents/model_runtime/rules.py`. Computes confidence score via `src/core/confidence.py`.

**Confidence gate:**
```
≥3 independent sources → HIGH  → draft PR (auto-approve if policy allows)
2 sources              → MEDIUM → draft PR (require approval)
<2 sources             → LOW   → GitHub Issue only, no PR
```

---

## 4. Shared Engine

### 4.1 Safety Agent (`src/agents/safety/`)

**Always the last node before any external write.** Applies the policy table from `src/safety/policy.py`.

Policy is evaluated on every action, not just on first approval. Approved actions expire after 24h.

**Complete policy table:**

| Action | Policy |
|---|---|
| Read cluster (pods/events/logs/nodes/PVCs) | `ALLOW` |
| Generate report or config | `ALLOW` |
| Open draft GitHub PR | `ALLOW` |
| Proactive new workload deployment | `REQUIRE_APPROVAL` |
| Increase startupProbe threshold | `PR_ONLY` |
| Change memory/CPU limits (≤2x) | `PR_ONLY` |
| Change memory/CPU limits (>2x) | `PR + APPROVAL` |
| Change GPU replica count | `REQUIRE_APPROVAL` |
| Change node selector / tolerations | `REQUIRE_APPROVAL` |
| Modify Kubernetes Secrets | `BLOCK` |
| Delete any workload | `BLOCK` |
| `kubectl apply` to production | `BLOCK` |
| Rollback live deployment | `REQUIRE_APPROVAL` |
| Modify RBAC / NetworkPolicy | `SENIOR_APPROVAL` |

### 4.2 GitOps Fix Agent (`src/agents/gitops_fix/`)

**Proactive path:** Takes generated config → creates branch → opens PR
**Reactive path:** Locates source file → generates minimal patch → opens PR

Both paths share:
- Branch naming: `fix/<workload>-<slug>-<incident_id_short>` (reactive) or `feat/<workload>-<slug>` (proactive)
- Validation pipeline: `kubeconform` → `helm template` → `kustomize build`
- PR body template (see Section 5)
- Always opens as **draft**

### 4.3 Verification Agent (`src/agents/verification/`)

Post-merge health check. Runs after GitOps reconciliation is detected.

**Checks:**
1. Pod status → Running, Ready=True
2. No new warning events
3. Restart count stable
4. `GET /health` → 200
5. `GET /v1/models` → expected model present
6. `POST /v1/chat/completions` with test prompt → valid response

**Output:** `VerificationResult` closes the incident. Failure triggers re-open.

---

## 5. PR Body Template (both modes)

```markdown
## Type
PROACTIVE_DEPLOY | REACTIVE_FIX

## Intent / Root Cause
<For proactive: what was requested and why this config was generated>
<For reactive: specific root cause in one sentence>

## Evidence / Validation Inputs
- <item 1>
- <item 2>

## Files Changed
- `<path>` — <description>

## Resource Math (proactive only)
| Resource | Calculated | Configured |
|---|---|---|
| VRAM required | 170 GiB | 2× A100 80GB |
| CPU request | 8 cores | 8 |
| Memory request | 32 GiB | 32Gi |

## Risk Level
LOW | MEDIUM | HIGH

## Validation
- kubeconform: PASS
- helm template: PASS
- kustomize build: N/A

## Expected Impact
<what changes after this PR is merged>

## Cost Impact
<GPU hours/month delta if applicable>

## Rollback Plan
```bash
git revert <sha>
# or
helm rollback <release> <revision>
```

## Agent Confidence
HIGH | MEDIUM

## Approval Status
- [ ] Human reviewer approved
```

---

## 6. Data Model

### deployment_intents (proactive mode)

| Field | Type | Description |
|---|---|---|
| id | UUID | |
| raw_input | text | Original natural language |
| parsed_intent | jsonb | `DeploymentIntent` model dump |
| cluster_context | jsonb | Cluster state at parse time |
| generated_config | text | Final Helm values / YAML |
| pr_id | UUID | FK → pull_requests |
| status | enum | `draft`, `pr_opened`, `deployed`, `failed` |
| created_at | timestamp | |

### incidents (reactive mode)

| Field | Type | Description |
|---|---|---|
| id | UUID | |
| cluster_id | string | |
| namespace | string | |
| workload_name | string | |
| runtime_type | enum | `vllm`, `kserve`, `ray_serve`, `triton`, `custom` |
| status | enum | `open`, `pr_opened`, `approved`, `merged`, `resolved`, `false_positive` |
| failure_type | string | e.g. `startup_probe_failure`, `gpu_pending` |
| severity | enum | `low`, `medium`, `high`, `critical` |
| confidence | enum | `low`, `medium`, `high` |
| root_cause_summary | text | |
| created_at | timestamp | |

### pull_requests (shared)

| Field | Type | Description |
|---|---|---|
| id | UUID | |
| source_type | enum | `proactive`, `reactive` |
| source_id | UUID | FK → deployment_intents or incidents |
| repo | string | |
| branch | string | |
| pr_url | string | |
| status | enum | `draft`, `open`, `merged`, `closed` |
| validation_status | enum | `pass`, `fail`, `skipped` |
| created_at | timestamp | |
| merged_at | timestamp | |

### audit_events (shared — hash-chained)

| Field | Type | Description |
|---|---|---|
| id | UUID | |
| source_type | enum | `proactive`, `reactive` |
| source_id | UUID | |
| actor | string | `agent:<name>` or `human:<handle>` |
| event_type | string | |
| message | text | |
| metadata_json | jsonb | |
| created_at | timestamp | |
| hash | string | SHA256 tamper-evident |
| previous_hash | string | Chain link |

---

## 7. Technology stack

| Layer | Technology |
|---|---|
| Backend API | FastAPI + Python 3.11+ |
| Agent orchestration | LangGraph (state machine) |
| LLM calls | Anthropic Claude (structured extraction, PR body generation) |
| Database | PostgreSQL (incidents, intents, audit) |
| Task queue | Redis + ARQ (async agent jobs) |
| Kubernetes reads | `kubernetes` Python client (read-only) |
| Config validation | `kubeconform`, `helm`, `kustomize` |
| Data models | Pydantic v2 |
| Frontend | Next.js / React (chat UI + approval inbox) |
| In-cluster agent | Helm chart (read-only ClusterRole) |
| CI | GitHub Actions (lint, test, kubeconform on PRs) |

---

## 8. Failure scenario catalogue (reactive mode)

| ID | Scenario | Runtime | Confidence |
|---|---|---|---|
| S1 | Startup probe too aggressive for model load | vLLM | High |
| S2 | GPU pod stuck Pending (node selector) | All | High |
| S3 | GPU pod stuck Pending (missing toleration) | All | High |
| S4 | Model cache PVC missing / not mounted | vLLM, KServe | High |
| S5 | Container OOMKilled | All | High |
| S6 | Inference endpoint unhealthy (pod Ready ≠ model healthy) | All | Medium |
| S7 | HF token missing / wrong secret ref | vLLM, KServe | Medium |
| S8 | KEDA / HPA misconfigured | All | Medium |
| S9 | CUDA OOM / KV cache pressure | vLLM | Medium |
| S10 | Image pull failure (large model image) | All | High |

---

## 9. Scalability design

### Multi-cluster
Each cluster gets one read-only in-cluster agent. Agents report to the shared KubeLLM control plane. The control plane is stateless except for the database, allowing horizontal scaling.

### Multi-tenant
Each `cluster_id` is scoped to a `tenant_id`. Policy, approval rules, and audit logs are fully tenant-isolated.

### Config generation at scale
The knowledge library (`src/knowledge/`) is static, versioned, and cached in memory. Config generation is CPU-bound, not I/O-bound. Scales horizontally with the API layer.

### LLM call budget
- Intent parsing: 1 LLM call per `kubellm generate` invocation
- PR body generation: 1 LLM call per PR
- RCA summary: 1 LLM call per incident
- All rules, confidence scoring, validation: zero LLM calls (deterministic)

This keeps costs predictable and prevents runaway LLM spend under load.
