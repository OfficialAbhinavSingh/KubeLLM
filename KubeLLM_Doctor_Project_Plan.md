# KubeLLM Doctor — Project Plan & Execution Documentation

**Version:** 1.0  
**Project Type:** AI SRE Agent / Kubernetes / LLM Inference Reliability  
**Finalized Idea:** AI SRE agent for LLM/GPU inference workloads running on Kubernetes  
**Primary Goal:** Help teams diagnose and safely fix failures in vLLM, KServe, Ray Serve, Triton, and GPU-backed Kubernetes inference workloads through evidence-backed GitOps PRs.

---

## 1. Executive Summary

**KubeLLM Doctor** is an AI SRE agent for companies running LLM inference workloads on Kubernetes. It monitors inference workloads such as **vLLM, KServe, Ray Serve, Triton, KubeRay, and custom model servers**, detects failures, identifies root causes, generates safe GitOps fixes, opens GitHub PRs, and verifies recovery after deployment.

The product is not a generic Kubernetes pod fixer. It focuses on a sharper and higher-value niche:

> **LLM/GPU inference reliability on Kubernetes.**

The main use case:

```text
Inference pod fails
        ↓
Agent collects Kubernetes + GPU + model-runtime evidence
        ↓
Agent identifies root cause
        ↓
Agent maps the live workload back to GitHub manifests / Helm / Kustomize
        ↓
Agent generates a safe patch
        ↓
Agent opens a PR with evidence, risk level, validation, and rollback plan
        ↓
Human approves
        ↓
GitOps deploys
        ↓
Agent verifies inference endpoint recovery
```

The first version should be built as a **read-only scanner + GitOps PR generator**, not a production-mutating bot.

---

## 2. Why This Idea Was Chosen

We discussed multiple agentic infrastructure ideas:

### 2.1 AI Agent Firewall / Control Tower

**Concept:** A security/control layer for AI agents that decides what agents are allowed to read, write, send, delete, merge, deploy, or approve.

**Why it is valuable:**

- Companies are starting to give AI agents access to tools like GitHub, Slack, Gmail, Jira, cloud consoles, databases, and internal files.
- Enterprises need permission control, audit logs, approval workflows, redaction, and rollback.
- It is a large market but broad, competitive, and harder to scope for a first MVP.

**How it still connects to this project:**

KubeLLM Doctor should include a mini version of this idea as the **Safety & Approval Agent**:

- Block secret changes.
- Require approval for high-risk Kubernetes/GPU changes.
- Never patch production live by default.
- Log every decision.
- Generate rollback plans.

### 2.2 Generic Kubernetes PodFix AI

**Concept:** AI agent that diagnoses and fixes Kubernetes pod issues like `CrashLoopBackOff`, `ImagePullBackOff`, `OOMKilled`, and `Pending`.

**Why it is too basic:**

- Existing tools like K8sGPT, HolmesGPT, Robusta, Botkube, Komodor, and Datadog Bits AI already solve parts of this.
- Generic pod fixing is crowded and easy to copy.
- Many tools can already explain Kubernetes errors.

### 2.3 Final Direction: KubeLLM Doctor

**Final niche:**

> **AI SRE agent for LLM/GPU inference workloads on Kubernetes.**

This is stronger because:

- GPU failures are expensive.
- LLM inference infra is newer and harder than normal web services.
- Kubernetes + GPU + model runtime + autoscaling + GitOps creates complex failure modes.
- Existing generic Kubernetes AI tools are broad, but not deeply optimized for inference-specific issues.

---

## 3. Problem Statement

Companies running self-hosted or private LLM inference on Kubernetes face repeated operational problems:

| Problem | Why it matters |
|---|---|
| GPU pod stuck in `Pending` | GPU node selector, taints, tolerations, or capacity may be wrong. |
| vLLM keeps restarting | Startup/readiness probe may kill the server before model loading finishes. |
| GPU OOM / KV cache pressure | Causes latency spikes, failed requests, and wasted expensive GPU time. |
| Slow cold starts | Large models, image pulls, and poor model cache strategy delay recovery. |
| Bad autoscaling | GPU pods scale too late or waste money when idle. |
| Model cache PVC not mounted | Model download repeats or startup fails. |
| `/health` passes but inference fails | Pod health does not always mean model endpoint health. |
| Live cluster state does not map to GitHub | Engineers waste time finding the correct Helm/Kustomize file. |
| Risky production fixes | Blind `kubectl edit` creates drift and can break GitOps. |

### Core pain

> Teams want to run self-hosted LLM inference, but they do not want every vLLM/Kubernetes/GPU issue to require a senior infra engineer.

---

## 4. Market Evidence & Sources

This project is supported by real technical adoption trends:

1. **vLLM officially documents Kubernetes deployment**, including GPU deployment and troubleshooting for startup/readiness probe failures.  
   Source: [vLLM Kubernetes deployment docs](https://docs.vllm.ai/en/stable/deployment/k8s/)

2. **Kubernetes supports GPU scheduling through device plugins**, and GPUs are exposed as schedulable resources like `nvidia.com/gpu`.  
   Source: [Kubernetes GPU scheduling docs](https://kubernetes.io/docs/tasks/manage-gpus/scheduling-gpus/)

3. **NVIDIA provides an official Kubernetes device plugin** that exposes GPU count, tracks GPU health, and enables GPU containers in Kubernetes.  
   Source: [NVIDIA Kubernetes Device Plugin](https://github.com/NVIDIA/k8s-device-plugin)

4. **NVIDIA GPU Operator adds GPU infrastructure complexity**, including drivers, CDI, DCGM telemetry, device plugin configuration, and GPU operator components.  
   Source: [NVIDIA GPU Operator documentation](https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/latest/getting-started.html)

5. **KServe lists real enterprise adopters**, showing that production ML model serving on Kubernetes is real.  
   Source: [KServe adopters](https://kserve.github.io/website/docs/community/adopters)

6. **Datadog already has Kubernetes remediation with PR generation**, validating that the market wants AI-assisted Kubernetes remediation.  
   Source: [Datadog Bits AI Kubernetes Remediation](https://docs.datadoghq.com/containers/bits_ai_kubernetes_remediation/)

---

## 5. Competitive Landscape

### 5.1 K8sGPT

**What it solves:**  
Scans Kubernetes clusters and explains common issues in simple English.

**Gap:**  
Mostly diagnosis. Not deeply specialized in LLM inference, GPU scheduling, vLLM startup failures, model cache, inference endpoint validation, or GitOps PR workflows.

### 5.2 HolmesGPT

**What it solves:**  
Broad AI SRE investigation across Kubernetes, logs, metrics, observability tools, GitHub, databases, and more.

**Gap:**  
Very broad. The opportunity is to be narrower and deeper for LLM/GPU inference workloads.

### 5.3 Robusta

**What it solves:**  
Alert enrichment. Adds pod logs, graphs, events, and possible remediation to Prometheus alerts.

**Gap:**  
Strong alert context, but less focused on inference-specific repair PRs and post-fix inference validation.

### 5.4 Botkube

**What it solves:**  
ChatOps for Kubernetes through Slack/Teams.

**Gap:**  
Great for asking questions, but the opportunity is automated detection → root cause → safe PR → verification.

### 5.5 Komodor / Klaudia

**What it solves:**  
Commercial Kubernetes troubleshooting and autonomous AI SRE workflows.

**Gap:**  
Broad enterprise platform. Hard to beat broadly. Better to focus on smaller teams and inference-specific failures.

### 5.6 Datadog Bits AI Kubernetes Remediation

**What it solves:**  
Detects Kubernetes workload issues, suggests remediations, and can create GitHub PRs from Datadog context.

**Gap:**  
Datadog-centered. Our opportunity is to be vendor-neutral, GitOps-native, self-hostable, and deeply focused on vLLM/KServe/Ray Serve/Triton inference workloads.

---

## 6. Unique Positioning

### Generic tools say:

> “Your pod failed readiness probe.”

### KubeLLM Doctor should say:

> “Your vLLM server is being killed before model loading finishes. Logs show model loading still in progress, but startupProbe only allows 60 seconds. Increase the startup probe window to 300 seconds. I opened a PR in `helm/values-prod.yaml` with validation and rollback.”

### Positioning statement

> **KubeLLM Doctor is an AI SRE agent for LLM inference on Kubernetes. It diagnoses vLLM/KServe/Ray Serve/Triton/GPU failures, generates safe GitOps PRs, and verifies recovery — without directly touching production.**

### Differentiators

| Differentiator | Why it matters |
|---|---|
| LLM/GPU-specific diagnosis | Normal Kubernetes tools do not deeply understand inference runtime issues. |
| GitOps-first repairs | Avoids dangerous live production mutation. |
| Evidence-backed PRs | Human reviewers get exact root cause, logs, validation, and rollback. |
| Inference endpoint validation | Checks actual model response, not just pod status. |
| Safety approval agent | High-risk actions require approval or are blocked. |
| Vendor-neutral | Can work with Prometheus, Grafana, GitHub, ArgoCD, Flux, Kubernetes, and logs. |
| Self-hostable future | Important for AI and enterprise infrastructure teams. |

---

## 7. Target Customer Profile

### Best first customers

Do not start with very large companies first. Start with smaller and mid-size teams that feel the pain but do not have massive internal platform teams.

**Ideal customer:**

- AI SaaS startup or MLOps/platform team.
- 5–50 engineers.
- 1–10 DevOps/SRE/platform engineers.
- Running or planning self-hosted LLM inference.
- Uses Kubernetes, GitHub, Helm/Kustomize, and preferably GitOps.
- Has GPU spend or production inference workload.
- Uses vLLM, KServe, Ray Serve, Triton, or custom model servers.
- Wants safety, audit, and approval before automation changes production.

### Buyer personas

| Buyer | What they care about |
|---|---|
| CTO | Reliability, speed, cost, avoiding infra bottlenecks. |
| Head of AI Infrastructure | Inference uptime, GPU utilization, stable deployments. |
| Platform Engineering Lead | Reducing repetitive debugging work. |
| SRE Manager | Lower MTTR and better post-incident evidence. |
| MLOps Engineer | Easier deployment and debugging of model-serving workloads. |
| DevOps Lead | Safer Kubernetes operations and GitOps consistency. |

---

## 8. Real Company Target List

These are **research-based target categories and companies**, not guaranteed buyers. They are relevant because public information indicates involvement with AI inference, Kubernetes, GPUs, KServe, vLLM, Ray Serve, or GPU platforms.

### Tier 1: Design Partner Targets

| Company | Why relevant | Approach angle |
|---|---|---|
| Fireworks AI | Public case studies show high-performance AI inference using GPU infrastructure and Kubernetes/EKS. | “Reliability agent for GPU inference workloads.” |
| Baseten | Provides model deployment infrastructure and has vLLM deployment examples. | “Inference reliability scanner for teams deploying custom vLLM containers.” |
| Anyscale | Ray Serve and Ray Serve LLM are directly related to scalable model serving. | “KubeRay/Ray Serve failure diagnosis and GitOps fixes.” |
| RunPod | GPU pods, serverless GPU endpoints, and GPU infrastructure. | “Debug GPU pod failures and inference endpoint reliability.” |
| CoreWeave | GPU cloud and Kubernetes infrastructure. | “Partner/add-on for customers running GPU inference on Kubernetes.” |
| Yotta Shakti Cloud | Indian GPU cloud focused on AI workloads. | “India-focused inference reliability layer for private AI deployments.” |
| Sarvam AI | Indian LLM company with inference optimization focus. | “Reliability tooling for Indian-language model inference stacks.” |
| Fractal AI | AI consulting and enterprise AI deployment experience. | “Use KubeLLM Doctor in client AI-infra projects.” |

### Tier 2: KServe ecosystem targets

Use KServe adopter list as a lead source. It includes companies and organizations using KServe in production or providing deployment/integration options.

Examples from the KServe adopter page include enterprise/cloud/product ecosystem names such as AWS, AT&T, Bloomberg, AMD, and others.

Approach:

> “We are building a KServe/vLLM/Ray Serve failure diagnosis and GitOps repair agent. We are looking for design partners already running model-serving workloads on Kubernetes.”

### Tier 3: Easier early channels

These may be easier than direct enterprise sales:

- AI consulting agencies.
- MLOps consultancies.
- Kubernetes service providers.
- GPU cloud providers.
- Indian AI deployment companies.
- Startups building private LLM deployments for enterprises.

---

## 9. Outreach Strategy

### 9.1 Do not sell the full product first

Offer a **free read-only LLM Inference Reliability Audit**.

This lowers friction because the company does not need to give write access.

### 9.2 Audit offer

**Offer:**

> “We run a read-only scanner against your manifests or non-production cluster and return a report of failure risks in your LLM inference stack.”

### 9.3 Audit deliverable

```text
KubeLLM Reliability Report

1. Workloads detected
2. vLLM/KServe/Ray Serve/Triton configuration review
3. GPU scheduling risks
4. Probe/startup/readiness risks
5. PVC/model-cache risks
6. Autoscaling issues
7. Inference endpoint health risks
8. GitOps file mapping issues
9. Suggested PR patches
10. Risk score and next actions
```

### 9.4 Outreach message

```text
Hi <Name>,

I’m building KubeLLM Doctor, an AI SRE agent for teams running vLLM, KServe, Ray Serve, Triton, or GPU-backed inference workloads on Kubernetes.

It detects failures like GPU pod Pending, startup probes killing vLLM before model load, bad node selectors/tolerations, model cache/PVC issues, and autoscaling misconfigurations. It then generates a safe GitOps PR with evidence and rollback instead of directly touching production.

I noticed <Company> works around AI inference / Kubernetes / GPU infrastructure. I’m looking for 3 design partners and offering a free read-only inference reliability audit. No production write access needed.

Would you be open to a 20-minute call to see if this matches any real pain your team has?
```

### 9.5 Discovery call questions

Ask these instead of asking “Would you use this?”

1. Are you running vLLM, KServe, Triton, Ray Serve, KubeRay, or custom model servers?
2. Is inference running on Kubernetes, ECS, bare metal, serverless GPU, or managed endpoints?
3. What was your last inference or GPU incident?
4. How often do pods fail due to probes, OOM, model loading, image pull, or scheduling?
5. How do you map a broken live deployment back to GitHub/Helm/Kustomize?
6. Who fixes inference incidents today?
7. How long does diagnosis usually take?
8. Would your team allow an AI agent to open a PR if it never patched production directly?
9. What actions must be blocked or approval-gated?
10. What evidence would make your SRE team trust an AI-generated fix?

---

## 10. MVP Scope

### 10.1 MVP promise

> **Connect Kubernetes + GitHub. When an LLM inference workload fails, KubeLLM Doctor identifies the root cause and opens a safe PR with evidence.**

### 10.2 MVP should support

| Area | MVP scope |
|---|---|
| Runtime | vLLM first |
| Kubernetes objects | Pod, Deployment, StatefulSet, Service, Events, Node, PVC |
| GPU checks | `nvidia.com/gpu`, node labels, taints, tolerations, GPU node capacity |
| Failure types | Startup probe failure, readiness probe failure, Pending, OOMKilled, model cache/PVC issue, missing GPU scheduling config |
| GitOps | GitHub PR generation against YAML/Helm values |
| Validation | kubeconform, YAML validation, optional `kubectl --dry-run=server` |
| Output | PR with root cause, evidence, patch, risk, rollback |
| UI | Simple dashboard or CLI + GitHub PR comments |
| Safety | Read-only cluster access initially; no live patching |

### 10.3 MVP should not support yet

Avoid these in v1:

- Full Datadog/Grafana replacement.
- All Kubernetes failure types.
- All ML serving platforms at once.
- Automatic production mutation.
- Cloud-provider-specific auto-fixes.
- Multi-tenant SaaS complexity before validation.
- Advanced GPU cost optimization.
- Complex dashboards before the PR workflow works.

---

## 11. First Failure Scenarios to Implement

### Scenario 1: vLLM startup probe too aggressive

**Problem:** vLLM model takes longer to load than the startup probe window. Kubernetes kills the container before it finishes startup.

**Detection evidence:**

- Container restart count increasing.
- Events show startup probe failure.
- Logs show model loading still in progress.
- No GPU scheduling error.
- No image pull error.

**Fix:**

- Increase startupProbe window in Helm/YAML.
- Optionally separate startupProbe from readinessProbe.
- PR includes explanation and rollback.

### Scenario 2: GPU pod stuck in Pending

**Problem:** Pod requests GPU but cannot schedule.

**Detection evidence:**

- Pod Pending.
- Events show no suitable node / taint / insufficient GPU.
- Pod requests `nvidia.com/gpu`.
- Node labels do not match nodeSelector.
- Required toleration missing.

**Fix:**

- Add correct nodeSelector.
- Add toleration for GPU nodes.
- Or report insufficient GPU capacity.

### Scenario 3: Model cache PVC missing or not mounted

**Problem:** Model cannot load or reloads slowly because PVC is missing, wrong, or not mounted.

**Detection evidence:**

- Logs show missing model path or repeated model download.
- Pod volumeMounts do not match expected path.
- PVC not bound or storage class issue.

**Fix:**

- Add/fix PVC reference.
- Fix volumeMount path.
- If secret/model access token missing, generate a human-action issue instead of inventing secret values.

### Scenario 4: CPU memory OOMKilled

**Problem:** Container is killed because memory limit is too low for model runtime.

**Detection evidence:**

- Last termination reason `OOMKilled`.
- Container memory limit is too low.
- Usage data available from metrics if present.

**Fix:**

- Suggest memory request/limit increase.
- Require approval if cost impact is significant.

### Scenario 5: Inference endpoint not actually healthy

**Problem:** Pod is running, but model endpoint is failing.

**Detection evidence:**

- Kubernetes Ready may be true.
- `/v1/models`, `/health`, `/v1/chat/completions`, or model-specific route fails.
- Service endpoints may be present but inference request fails.

**Fix:**

- Identify runtime/config mismatch.
- Validate actual inference after deployment, not just pod status.

---

## 12. Multi-Agent Architecture

### 12.1 Agent roles

```text
Cluster Watcher Agent
  Detects unhealthy pods, events, rollout failures, node issues.

GPU Scheduler Agent
  Checks GPU requests, node selectors, taints, tolerations, device plugin state, node capacity.

Model Runtime Agent
  Reads vLLM/KServe/Ray/Triton logs and identifies model loading, CUDA, tokenizer, endpoint, and runtime errors.

Autoscaling Agent
  Checks HPA/KEDA/Prometheus-based scaling, min/max replicas, cold starts, queue/token metrics.

GitOps Fix Agent
  Maps live workload to GitHub manifests, Helm values, or Kustomize overlays and creates patches.

Safety & Approval Agent
  Applies allow/block/approval policies before any action.

Verification Agent
  After merge/deploy, checks pod health, endpoint health, latency, and recovery evidence.
```

### 12.2 High-level architecture

```text
Kubernetes Cluster
  ├── Read-only KubeLLM Agent
  │     ├── Pods
  │     ├── Events
  │     ├── Logs
  │     ├── Nodes
  │     ├── PVCs
  │     └── Metrics
  │
  ↓

KubeLLM Control Plane
  ├── Incident Store
  ├── Root Cause Engine
  ├── Policy Engine
  ├── Agent Orchestrator
  ├── Audit Log
  └── Approval Queue

  ↓

GitHub Integration
  ├── Find manifest / Helm values / Kustomize overlay
  ├── Generate patch
  ├── Validate patch
  └── Open PR

  ↓

Slack / UI / GitHub PR
  ├── Alert summary
  ├── Risk score
  ├── Evidence
  ├── Approval request
  └── Recovery verification
```

---

## 13. Safety & Governance Model

### 13.1 Default action policy

| Action | Default decision |
|---|---|
| Read pod status | Allow |
| Read events/logs | Allow |
| Read node labels/taints | Allow |
| Read deployment/service/PVC | Allow |
| Generate report | Allow |
| Open GitHub PR | Allow |
| Increase startupProbe threshold | PR only |
| Change memory limits | PR + approval if cost impact |
| Change GPU replicas | Require approval |
| Change node selector/toleration | Require approval |
| Modify secrets | Block |
| Delete workload | Block |
| Patch production live object | Block by default |
| Rollback deployment live | Require approval |
| Change RBAC/network policy | Senior approval |

### 13.2 Every PR should include

```text
Root cause
Evidence
Files changed
Risk level
Validation result
Expected impact
Cost impact if any
Rollback plan
Commands/checks run
Agent confidence
Human approval status
```

### 13.3 Trust rule

The product should never claim full certainty when evidence is incomplete.

Use confidence levels:

- High confidence: multiple evidence sources match.
- Medium confidence: likely cause but missing one signal.
- Low confidence: report only, no auto-generated patch.

---

## 14. Technical Stack Recommendation

### Backend

- Python + FastAPI
- PostgreSQL for incidents, actions, audit logs
- Redis or Postgres queue for workers
- Kubernetes Python client
- GitHub App integration
- Pydantic models for structured agent output

### Agent layer

- LangGraph or custom state-machine orchestration
- Tool-based agents, not free-form shell access
- Structured JSON outputs
- Policy check before tool execution

### Kubernetes tools

- Kubernetes Python client
- `kubectl` optional for local validation
- `kubeconform` for schema validation
- `helm template` for Helm validation
- `kustomize build` for Kustomize validation
- `conftest` / OPA optional for policy validation

### Observability inputs

Start minimal:

- Kubernetes events
- Pod logs
- Pod/deployment YAML
- Node labels/taints/capacity
- Metrics-server if available

Add later:

- Prometheus
- Grafana
- Datadog
- Loki
- OpenTelemetry
- ArgoCD/Flux

### Frontend

- React / Next.js dashboard
- Incident list
- Incident timeline
- Approval inbox
- Policy configuration
- PR/evidence view

### Deployment

- Helm chart
- In-cluster read-only agent
- Control plane local/dev first
- Later SaaS and self-hosted options

---

## 15. Data Model Draft

### incidents

```text
id
cluster_id
namespace
workload_name
runtime_type
status
failure_type
severity
created_at
updated_at
root_cause_summary
confidence
```

### evidence_items

```text
id
incident_id
source_type
source_name
content_summary
raw_ref
created_at
```

### action_requests

```text
id
incident_id
action_type
risk_level
decision
requires_approval
approved_by
approved_at
status
created_at
```

### audit_events

```text
id
incident_id
actor
event_type
message
metadata_json
created_at
hash
previous_hash
```

### pull_requests

```text
id
incident_id
repo
branch
pr_url
status
validation_status
created_at
merged_at
```

---

## 16. Execution Plan

### Week 1: Finalize prototype scope and broken demo repo

**Goal:** Build a reproducible demo environment.

Tasks:

- Create GitHub repo with vLLM Kubernetes manifests.
- Add Helm or Kustomize setup.
- Create broken scenario files:
  - startup probe too aggressive
  - missing GPU toleration
  - wrong node selector
  - PVC/model cache missing
- Prepare local k3d/minikube demo for non-GPU failures.
- If possible, prepare one real GPU test on RunPod, Lambda, GCP, AWS, or local GPU server.

Deliverable:

```text
Broken vLLM demo repo + documented failure scenarios
```

### Week 2: Build read-only Kubernetes scanner

**Goal:** Collect evidence from cluster.

Tasks:

- Implement cluster connection.
- Read pods, logs, events, deployments, services, PVCs, nodes.
- Detect namespace/workload/runtime.
- Produce JSON incident report.
- Add first rules for:
  - startup probe failure
  - Pending GPU pod
  - OOMKilled
  - PVC not bound

Deliverable:

```text
CLI command:
kubellm scan --namespace demo --workload vllm
```

### Week 3: Add inference-specific analyzers

**Goal:** Make it specialized, not generic.

Tasks:

- Build vLLM log analyzer.
- Parse startup/readiness/liveness probe config.
- Check model path, HF token secret reference, PVC mount.
- Check GPU requests and node scheduling constraints.
- Add confidence scoring.

Deliverable:

```text
Structured RCA:
failure_type, root_cause, evidence, suggested_fix, confidence
```

### Week 4: GitOps PR generator

**Goal:** Convert RCA into GitHub PR.

Tasks:

- GitHub App or PAT for prototype.
- Find manifest/Helm values path.
- Patch YAML safely.
- Run validation:
  - YAML parse
  - kubeconform
  - helm template if Helm
- Open draft PR.
- Add PR body with evidence and rollback.

Deliverable:

```text
Failed vLLM pod → GitHub PR with fix
```

### Week 5: Safety and approval workflow

**Goal:** Add trust layer.

Tasks:

- Define policy rules.
- Add allow/block/approval decisions.
- Add audit log.
- Add simple approval UI or Slack approval.
- Block secrets and live production patching.

Deliverable:

```text
Agent cannot perform risky actions without approval
```

### Week 6: Demo polish and outreach assets

**Goal:** Prepare for design partner outreach.

Tasks:

- Record 2-minute demo video.
- Create landing page.
- Create reliability audit offer.
- Prepare one-page PDF/README.
- Prepare outreach messages.
- Build sample report.

Deliverable:

```text
Public-facing pitch + demo + audit report template
```

### Week 7–8: Design partner outreach

**Goal:** Talk to real teams.

Tasks:

- Contact 50 engineers/leads.
- Target AI infra, MLOps, platform, SRE people.
- Offer free read-only audit.
- Run 5 discovery calls.
- Get 2–3 audits.
- Convert 1 into paid pilot.

Deliverable:

```text
3 design partner conversations + 1 serious pilot opportunity
```

### Week 9–10: Pilot hardening

**Goal:** Make it useful in real environments.

Tasks:

- Add more runtime support based on feedback.
- Add Prometheus metrics integration.
- Add ArgoCD/Flux awareness.
- Improve GitOps file mapping.
- Add report export.
- Add role-based approvals.

Deliverable:

```text
Pilot-ready KubeLLM Doctor v0.1
```

---

## 17. Team Work Division

For a 5-person team:

### Person 1: Kubernetes/Infra Lead

- Demo cluster setup.
- vLLM deployment.
- Broken scenarios.
- Kubernetes scanner.
- Helm/Kustomize validation.

### Person 2: Agent/AI Lead

- RCA engine.
- Multi-agent orchestration.
- Structured outputs.
- Confidence scoring.
- Evidence summarization.

### Person 3: GitHub/GitOps Lead

- GitHub integration.
- PR generation.
- File mapping.
- Patch validation.
- PR body templates.

### Person 4: Backend/Safety Lead

- FastAPI backend.
- Incident/action/audit data model.
- Policy engine.
- Approval workflow.
- Worker queue.

### Person 5: Frontend/Product/Outreach Lead

- Dashboard.
- Approval inbox.
- Landing page.
- Demo video.
- Outreach list and customer discovery.

---

## 18. First Demo Script

### Demo title

> **“vLLM CrashLoopBackOff to GitHub PR in 3 minutes.”**

### Demo flow

1. Show a vLLM pod repeatedly restarting.
2. Show Kubernetes events with startup probe failure.
3. Show logs where model is still loading.
4. Run KubeLLM Doctor scan.
5. Agent identifies root cause:
   - startup probe too aggressive for model load time.
6. Agent finds `values-prod.yaml`.
7. Agent opens GitHub PR increasing startup probe window.
8. PR includes:
   - root cause
   - evidence
   - validation
   - rollback
   - risk level
9. Merge or simulate merge.
10. Agent verifies endpoint health:
    - pod running
    - readiness passed
    - `/v1/chat/completions` returns successfully

### Demo punchline

> **Generic tools tell you the pod failed. KubeLLM Doctor tells you why the model server failed and opens the safe PR that fixes it.**

---

## 19. Product Roadmap

### V0: Demo

- vLLM only.
- 3–4 failure scenarios.
- CLI scan.
- GitHub PR generation.
- No real SaaS.

### V1: Design partner pilot

- vLLM + KServe basic support.
- Read-only cluster agent.
- GitHub App.
- Approval + audit.
- Slack summaries.
- Prometheus optional.

### V2: Commercial MVP

- Multi-cluster support.
- Ray Serve/Triton support.
- ArgoCD/Flux integration.
- Policy templates.
- Inference endpoint validation.
- Incident timeline UI.
- Report export.

### V3: Advanced platform

- GPU cost regression agent.
- Autoscaling optimization.
- Runbook learning from past incidents.
- Self-hosted enterprise deployment.
- Datadog/Grafana/Loki integrations.
- Agent firewall for infrastructure actions.

---

## 20. Success Metrics

### Technical metrics

| Metric | Target |
|---|---|
| Root cause accuracy on demo scenarios | 90%+ |
| PR generation success | 80%+ |
| False-positive risky fix rate | Near zero |
| Time from incident to suggested PR | Under 3 minutes |
| Validation pass rate | 90%+ |
| Recovery verification accuracy | 90%+ |

### Business validation metrics

| Metric | Target |
|---|---|
| Discovery calls | 20+ |
| Free audits completed | 3–5 |
| Companies saying pain is real | 60%+ |
| Paid pilot conversion | 1+ |
| Willingness to grant read-only access | 30%+ |
| Willingness to allow PR generation | 20%+ |

---

## 21. Pricing Strategy

### Early stage

| Offering | Price |
|---|---:|
| Free read-only audit | Free |
| 30-day pilot in India | ₹50,000–₹2,00,000 |
| 30-day global pilot | $1,000–$3,000 |
| Team monthly plan | $499–$1,999/month |
| Enterprise/self-hosted | $10,000–$50,000/year |

### Better paid pilot offer

> “We run a 30-day pilot. If we do not generate at least 3 useful incident reports or PR suggestions, you do not pay.”

---

## 22. What to Start Working on Immediately

### Step 1: Build the demo repo

Create:

```text
kubellm-demo/
  charts/
    vllm/
      values-good.yaml
      values-bad-startup-probe.yaml
      values-bad-gpu-selector.yaml
      values-bad-pvc.yaml
  manifests/
  README.md
```

### Step 2: Build scanner CLI

Command:

```bash
kubellm scan --namespace demo --workload vllm
```

Output:

```json
{
  "failure_type": "startup_probe_failure",
  "root_cause": "startup probe window too short for vLLM model load time",
  "confidence": "high",
  "evidence": [
    "pod restarted 9 times",
    "events show startup probe failed",
    "logs show model loading still in progress"
  ],
  "suggested_fix": {
    "file": "charts/vllm/values.yaml",
    "change": "increase startupProbe.failureThreshold"
  }
}
```

### Step 3: Add GitHub PR generation

Command:

```bash
kubellm fix --incident incident_123 --repo owner/repo --branch fix/vllm-startup-probe
```

Expected result:

```text
Draft PR opened with:
- root cause
- evidence
- YAML patch
- validation result
- rollback plan
```

### Step 4: Build one small dashboard

Screens:

1. Incidents
2. Incident detail
3. Evidence
4. Suggested fix
5. Approval
6. PR link

### Step 5: Start outreach while building

Do not wait until the product is complete.

Start outreach after the demo works.

---

## 23. Final Pitch

### One-line pitch

> **KubeLLM Doctor is an AI SRE agent that fixes LLM inference failures on Kubernetes through safe GitOps PRs.**

### Slightly longer pitch

> **KubeLLM Doctor monitors vLLM, KServe, Ray Serve, Triton, and GPU-backed inference workloads on Kubernetes. When inference pods fail or deployments become unhealthy, it collects evidence from Kubernetes, GPU scheduling, model runtime logs, and GitOps manifests, identifies root cause, opens a safe GitHub PR, and verifies recovery after deployment.**

### Investor/customer-friendly pitch

> **Companies want to self-host LLMs, but running inference on Kubernetes is operationally hard. KubeLLM Doctor gives them an AI SRE agent specialized for GPU and model-serving failures, reducing incident debugging time without allowing unsafe production mutations.**

---

## 24. Final Recommendation

Start with:

> **vLLM on Kubernetes failure diagnosis + GitHub PR generation.**

The first demo must be:

> **vLLM startup probe failure → root cause → patch → PR → verification.**

This gives the project a clear identity, technical depth, and a strong sales wedge.

Do not begin with all of Kubernetes.  
Do not begin with all AI agents.  
Do not begin with a large dashboard.

Begin with one painful, believable, repeatable workflow:

```text
LLM inference pod fails → KubeLLM Doctor explains why → opens safe PR → verifies recovery.
```

That is the product.
