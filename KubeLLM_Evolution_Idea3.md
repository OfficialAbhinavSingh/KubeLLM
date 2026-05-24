# KubeLLM — Evolution to Idea 3: Cursor for Infrastructure

**Version:** 2.0
**Date:** 2026-05-24
**Context:** This document records the strategic evolution from KubeLLM Doctor (reactive AI SRE) to the expanded dual-mode "Cursor for Infrastructure Engineers" vision.

---

## Why we evolved

The original KubeLLM Doctor plan (see `KubeLLM_Doctor_Project_Plan.md`) positioned the product as a reactive AI SRE tool: detect failures, diagnose root cause, open fix PR.

This is correct and remains the reactive core. But it has a market positioning problem:

> "AI Kubernetes debugger" has a ceiling — it only helps teams that are already failing.

The insight that drives the evolution:

> **The most expensive failure is deploying incorrectly in the first place.** A team that deploys Llama 70B with the wrong startupProbe will burn 30 minutes debugging before KubeLLM Doctor even gets a chance to help. The right tool prevents that failure, not just fixes it.

And a product that prevents failures is valuable to every team deploying LLM inference — not just teams already experiencing incidents.

---

## What changed and what stayed the same

### What stayed exactly the same

- Reactive mode (KubeLLM Doctor) — unchanged
- Safety model — unchanged (all PRs draft, no live mutations)
- GitOps PR engine — unchanged (now shared between both modes)
- Validation pipeline — unchanged
- Verification agent — unchanged
- Audit log — unchanged
- All 10 reactive failure scenarios — unchanged

### What was added

| Component | Purpose |
|---|---|
| `src/intent/` | Natural language → `DeploymentIntent` (one LLM call) |
| `src/config_gen/` | `DeploymentIntent` + cluster state → production Helm values |
| `src/knowledge/` | Best-practice defaults (sourced from failure catalogue) |
| `kubellm generate` CLI command | Proactive mode entry point |
| Proactive path in LangGraph graph | Intent → Config → Safety → PR → Verify |
| `docs/runbooks/proactive-deployment.md` | How to use proactive mode |
| `.claude/skills/generate-deployment-config/` | Claude Code skill for proactive generation |
| `ADR-005`, `ADR-006` | Engineering decisions for proactive mode |

### The reuse ratio

~60% of the codebase is shared between modes. The GitOps PR engine, Safety agent, Verification agent, and Audit log are used identically in both directions. This means proactive mode was added with minimal new infrastructure.

---

## The "Cursor for Infrastructure" positioning

### Why this framing is stronger for YC

| Original framing | Evolved framing |
|---|---|
| "AI SRE agent for LLM inference" | "Cursor for infrastructure engineers" |
| Reactive only — helps when things break | Proactive + reactive — helps at every step |
| Customer needs an incident to see value | Customer sees value on day 1 (first deployment) |
| WTP driven by how often failures occur | WTP driven by how often teams deploy |
| TAM = companies with LLM incidents | TAM = every company deploying LLMs |

The Cursor comparison resonates with engineers and investors immediately. Cursor took a workflow (writing code) and made AI a collaborator at every step. KubeLLM does the same for infrastructure: AI helps you write it correctly (proactive), and fixes it when it breaks (reactive).

### The YC RFS alignment

The Spring 2026 YC RFS "Make LLMs Easy to Train" (Gabriel Birnbaum) describes the identical pain for training infrastructure that KubeLLM solves for inference. Our positioning connects directly:

> *"Gabriel's RFS describes GPU instances that are busted when you spin them up. We solve the serving-side equivalent: vLLM pods that are misconfigured when you deploy them. Together they cover the full LLM infrastructure lifecycle."*

---

## The compounding flywheel

The dual-mode design creates a compounding data advantage:

```
Reactive mode collects failure patterns
        ↓
Failure patterns become knowledge library entries
        ↓
Knowledge library prevents those failures in proactive mode
        ↓
Proactive deployments feed back correct config patterns
        ↓
Correct patterns refine the reactive diagnosis baseline
        ↓
More reactive accuracy → more failure patterns → better knowledge library
```

Competitors cannot replicate this without both the reactive failure data AND the proactive deployment data. Each side of the system makes the other side better.

---

## Revised product roadmap

### V0: Reactive foundation + proactive prototype
- vLLM reactive diagnosis (5 failure scenarios)
- CLI: `kubellm scan` + `kubellm fix`
- CLI: `kubellm generate` (proactive, vLLM only)
- GitHub PR generation (both modes)
- Demo: startup probe failure → fix PR + Llama 70B generation → correct config PR

### V1: Design partner pilot (both modes)
- vLLM + KServe support (both modes)
- GitHub App (replace PAT)
- Approval UI (Next.js)
- Slack notifications
- Prometheus integration (reactive GPU metrics)
- `kubellm generate` → proactive PR for KServe InferenceService

### V2: Commercial MVP
- Ray Serve / Triton (both modes)
- ArgoCD / Flux integration
- Multi-cluster
- Incident timeline UI
- Config history ("what configs were generated for this workload")
- Natural language diff: "what changed between this PR and the last one?"

### V3: Platform
- GPU cost regression agent
- Autoscaling intelligence ("suggest better HPA thresholds based on your traffic pattern")
- Runbook learning from past incidents
- Enterprise self-hosted
- "Config audit": scan existing Kubernetes manifests and flag misconfigurations proactively

---

## First demo script (updated)

**Title:** "Deploy Llama 70B correctly and fix it when it breaks — in under 5 minutes."

**Part 1: Proactive (2 min)**
1. Show a new engineer on day 1, asked to deploy Llama 3.1 70B.
2. Run: `kubellm generate "deploy Llama 3.1 70B on 2 A100s with autoscaling"`
3. Show the output: GPU math, startupProbe window (40 min for 70B), PVC config.
4. Show the draft PR opened automatically.
5. Engineer reviews, approves, merges. Deployment succeeds first time.
6. **Punchline:** "No Google, no StackOverflow, no Slack ping to a senior engineer."

**Part 2: Reactive (3 min)**
1. Show a vLLM pod repeatedly restarting (startup probe failure, pre-existing cluster).
2. Run: `kubellm scan --namespace inference --workload vllm-llama3`
3. Agent identifies root cause: startup probe too aggressive for model load time.
4. Shows the fix PR with evidence, root cause, validation.
5. Merge. Agent verifies `/v1/chat/completions` returns successfully.
6. **Punchline:** "Generic tools tell you the pod failed. KubeLLM tells you why and opens the fix."

**Combined punchline:**
> "If you deploy with KubeLLM, you get it right the first time. If something breaks anyway, KubeLLM fixes it. That's what Cursor did for code — we're doing it for infrastructure."

---

## Success metrics (updated)

### Proactive mode
| Metric | Target |
|---|---|
| Config generation success rate | 90%+ (valid kubeconform + helm template) |
| Time to generate + open PR | < 60 seconds |
| Deployment success rate after proactive config | 85%+ first attempt |
| Startup probe wrong → failure rate | Near zero |

### Reactive mode (unchanged from original plan)
| Metric | Target |
|---|---|
| Root cause accuracy on demo scenarios | 90%+ |
| PR generation success | 80%+ |
| Time from incident to PR | < 3 minutes |
| Verification accuracy | 90%+ |
