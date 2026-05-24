# KubeLLM

> The AI-native infrastructure engineer for LLM/GPU workloads on Kubernetes.

---

## What is KubeLLM?

KubeLLM is two products sharing one engine:

### Proactive Mode — "Cursor for Infrastructure"
Describe what you want to deploy. KubeLLM generates the production-ready Helm values, validates them against your live cluster state (GPU capacity, node labels, taints, PVC availability), and opens a GitOps PR.

```bash
kubellm generate "deploy Llama 3.1 70B on 2 A100s with autoscaling and model caching"
```

```
→ Checks live cluster: 2 A100 nodes available, gpu=true label confirmed
→ Generates: values-llama3-70b.yaml with startupProbe, readinessProbe,
             PVC mount, nodeSelector, toleration, HPA config
→ Validates: kubeconform PASS, helm template PASS
→ Opens draft PR: "feat(vllm): deploy llama3-70b with GPU autoscaling"
→ PR includes: resource math, cost estimate, rollback plan
```

### Reactive Mode — "AI SRE on Call"
When an LLM inference workload fails, KubeLLM diagnoses it, finds the root cause with evidence, and opens a safe fix PR.

```bash
kubellm scan --namespace inference --workload vllm-llama3
```

```
→ Detects: pod restarted 9 times, startup probe failing
→ Evidence: logs show model still loading at probe timeout
→ Root cause: startupProbe.failureThreshold too low for 70B model load time
→ Confidence: HIGH (3 independent sources)
→ Opens draft PR: "fix(vllm): increase startupProbe window for 70B model"
→ After merge: verifies endpoint health at /v1/chat/completions
```

**Neither mode ever directly mutates your production cluster.**

---

## Why KubeLLM?

### The problem with deploying LLMs on Kubernetes

Running self-hosted LLM inference on Kubernetes is operationally hard in ways no existing tool addresses:

| Problem | Why it's hard |
|---|---|
| Write the right Helm values for vLLM | Startup probes, GPU nodeSelector, tolerations, model cache PVC, HPA — 20+ fields to get right |
| GPU pod stuck in `Pending` | Wrong node selector, missing toleration, insufficient GPU — hard to diagnose from events alone |
| vLLM killed before model loads | Startup probe window too short for large model load time |
| Model cache PVC not mounted | Repeated cold starts or silent startup failure |
| `OOMKilled` at runtime | Memory limit wrong for model + KV cache size |
| Endpoint healthy but inference fails | Pod Ready ≠ model endpoint actually works |
| Map live cluster state to GitHub | Find the exact Helm values file in a large monorepo |

Generic Kubernetes tools (K8sGPT, HolmesGPT, Copilot) understand Kubernetes. They do not understand vLLM startup behavior, GPU scheduling constraints, model cache requirements, or KServe InferenceService lifecycle.

KubeLLM is the first tool built specifically around LLM/GPU inference operational patterns.

---

## How it works — full flow

```
PROACTIVE MODE                          REACTIVE MODE
──────────────                          ─────────────
Natural language intent                 Cluster event / alert
        ↓                                       ↓
Intent Parser                           Cluster Watcher Agent
(NL → DeploymentIntent)                 (detects unhealthy pods)
        ↓                                       ↓
Config Generator                        Evidence Collection
(DeploymentIntent + cluster state       (events, logs, node state,
 + knowledge library → YAML)            GPU state, PVC state)
        ↓                                       ↓
                    ┌───────────────────────────┘
                    ↓
            Safety Agent (policy gate)
            allow / require_approval / block
                    ↓
            GitOps Fix Agent (shared)
            find file → patch/generate → validate → PR
                    ↓
            Human approves PR
                    ↓
            GitOps deploys (ArgoCD/Flux)
                    ↓
            Verification Agent (shared)
            pod health + endpoint health confirmed
```

---

## Agent architecture

| Agent | Mode | Role |
|---|---|---|
| Intent Parser | Proactive | Natural language → structured `DeploymentIntent` |
| Config Generator | Proactive | `DeploymentIntent` + cluster state → Helm/YAML/Kustomize |
| Knowledge Library | Proactive | Best-practice config injection (probes, resources, GPU) |
| Cluster Watcher | Reactive | Pod/event/node health monitoring |
| GPU Scheduler Agent | Reactive | GPU requests, node selectors, taints, capacity |
| Model Runtime Agent | Reactive | vLLM/KServe/Ray/Triton log analysis |
| Autoscaling Agent | Reactive | HPA/KEDA/Prometheus scaling checks |
| Safety Agent | Both | Policy gate — every action checked before execution |
| GitOps Fix Agent | Both | File location → patch/config → validation → PR |
| Verification Agent | Both | Post-deploy endpoint + pod health confirmation |

---

## Safety model

| Action | Policy |
|---|---|
| Read pods, events, logs, nodes, PVCs | Always allowed |
| Generate config / report | Always allowed |
| Open draft GitHub PR | Allowed |
| Deploy new workload (proactive) | Draft PR + approval |
| Change memory/CPU limits | Draft PR + approval if cost impact |
| Change GPU replica count | Require approval |
| Modify Kubernetes secrets | **Blocked** |
| Delete any workload | **Blocked** |
| `kubectl apply` to production | **Blocked** |

---

## Quickstart

### Prerequisites
- Python 3.11+
- `kubectl` configured against your cluster
- GitHub App or PAT with PR write access
- `kubeconform` and `helm` installed

### Install
```bash
git clone https://github.com/OfficialAbhinavSingh/KubeLLM.git
cd KubeLLM
pip install -e ".[dev]"
```

### Proactive — generate a deployment config
```bash
kubellm generate \
  "deploy Mistral 7B on a single A10G with model caching and readiness probe"

# With PR generation
kubellm generate --pr --repo your-org/infra-repo \
  "deploy vLLM with KServe, 4 H100s, HPA on token throughput"
```

### Reactive — scan and fix
```bash
# Scan for failures
kubellm scan --namespace inference --workload vllm-llama3

# Fix an incident
kubellm fix --incident <id> --repo your-org/infra-repo --branch fix/<slug>
```

---

## Supported LLM runtimes

| Runtime | Proactive config gen | Reactive diagnosis |
|---|---|---|
| vLLM | Yes — V0 | Yes — V0 |
| KServe | Yes — V1 | Yes — V1 |
| Ray Serve / KubeRay | Planned V2 | Planned V2 |
| Triton | Planned V2 | Planned V2 |
| Custom model servers | Partial | Partial |

---

## Roadmap

| Version | Scope |
|---|---|
| **V0** | vLLM proactive config gen + reactive diagnosis, CLI, GitOps PR, 5 failure scenarios |
| **V1** | KServe support, GitHub App, approval UI, Slack, Prometheus integration |
| **V2** | Ray Serve/Triton, ArgoCD/Flux awareness, multi-cluster, incident timeline UI |
| **V3** | GPU cost optimization agent, autoscaling intelligence, runbook learning, enterprise self-hosted |

---

## Project structure

```
src/intent/       # NL → DeploymentIntent (proactive entry point)
src/config_gen/   # Config generation from intent + cluster state
src/knowledge/    # Best-practice library for inference runtimes
src/agents/       # LangGraph multi-agent graph
src/safety/       # Policy engine, audit log, approval workflow
src/api/          # FastAPI backend
src/integrations/ # Kubernetes, GitHub, Slack, Prometheus
infra/            # Helm chart — in-cluster read-only agent
docs/             # Architecture, ADRs, runbooks
```

See `CLAUDE.md` for full repo map and development rules.

---

## License

Apache 2.0 — see [LICENSE](LICENSE).
