# KubeLLM — Repo Memory

## Purpose

**The AI-native infrastructure engineer for LLM/GPU workloads on Kubernetes.**

KubeLLM operates in two modes that share the same core engine:

- **Proactive Mode** — Engineer types intent in natural language. KubeLLM generates production-ready Helm/Kustomize/YAML configs, validates them against the live cluster, and opens a GitOps PR. Like Cursor for writing code, but for writing infrastructure.
- **Reactive Mode** — Inference pod fails. KubeLLM collects evidence, identifies root cause, generates a safe fix, opens a PR, and verifies recovery. Like an AI SRE on call 24/7.

Both modes share the same safety gate, GitOps PR engine, validation pipeline, and audit trail. **Neither mode ever mutates a production cluster directly.**

> YC positioning: "Cursor for infrastructure engineers — proactive config generation + reactive failure diagnosis, both delivered as safe GitOps PRs."

---

## Repo Map

```
KubeLLM/
├── src/
│   ├── intent/          # NL → DeploymentIntent parser (proactive mode entry)
│   ├── config_gen/      # DeploymentIntent → Helm/YAML/Kustomize generator
│   ├── knowledge/       # Best-practice config library (vLLM, KServe, Ray, Triton)
│   ├── agents/          # LangGraph multi-agent graph (reactive mode + shared)
│   │   ├── graph.py           # Full dual-mode state machine
│   │   ├── state.py           # KubeLLMState TypedDict
│   │   ├── cluster_watcher/   # Pod/event/node health detection
│   │   ├── gpu_scheduler/     # GPU scheduling, taints, tolerations
│   │   ├── model_runtime/     # vLLM/KServe/Ray/Triton log analysis + rules
│   │   ├── autoscaling/       # HPA/KEDA/Prometheus scaling checks
│   │   ├── gitops_fix/        # Manifest mapping + patch gen + PR (shared)
│   │   ├── safety/            # Policy gate — always last before PR
│   │   └── verification/      # Post-merge pod + endpoint health check
│   ├── api/             # FastAPI — incidents, actions, chat, approvals
│   ├── core/            # Pydantic models, confidence scoring, shared types
│   ├── safety/          # Policy engine, audit log, approval state machine
│   └── integrations/    # Kubernetes client, GitHub, Slack, Prometheus, ArgoCD
├── infra/               # Helm chart for in-cluster KubeLLM agent (read-only RBAC)
├── charts/              # Demo broken vLLM scenario Helm values
├── manifests/           # Demo Kubernetes manifests
├── frontend/            # Next.js — chat UI, incident inbox, approval queue
├── docs/
│   ├── architecture.md  # Full dual-mode system design
│   ├── decisions/       # ADRs — all engineering decisions
│   └── runbooks/        # Operational procedures
├── tests/
│   ├── unit/
│   ├── integration/
│   └── scenarios/       # Reproducer YAMLs for each failure + config type
├── pyproject.toml       # Python deps (FastAPI, LangGraph, pydantic, k8s client)
└── .claude/
    ├── settings.json
    ├── skills/          # Reusable Claude Code workflows
    └── hooks/           # Guardrails: format, validate, block writes
```

---

## Rules

### Safety (non-negotiable — both modes)
- **Never** `kubectl apply`, `kubectl patch`, `kubectl edit`, or `kubectl delete` against any cluster without `--dry-run`.
- **Never** read or modify `src/safety/` without reading `src/safety/CLAUDE.md` first.
- **Never** generate or commit secrets, tokens, or credentials. Use `<REPLACE_WITH_SECRET>` placeholder only.
- **Never** open a non-draft PR. All PRs are draft by default. Human approves before merge.
- **Never** skip the Safety agent node in the LangGraph graph. See `src/agents/CLAUDE.md`.
- All PRs (both modes) must include: intent/root-cause, evidence, files changed, risk level, validation result, rollback plan.

### Proactive mode rules
- Config generation must always validate against live cluster state (node labels, GPU capacity, taints).
- Never generate a config that requests more GPU than currently schedulable without flagging it.
- Generated configs must include: resource requests/limits, startupProbe, readinessProbe, liveness probe, PVC mounts (if model cache needed), GPU nodeSelector + toleration.
- Generated configs go through `src/knowledge/` for best-practice injection before validation.
- Confidence for generated configs: always `MEDIUM` until the user's cluster has confirmed deployment. Requires human approval before PR is marked ready.

### Reactive mode rules
- Confidence is computed from evidence count in `src/core/confidence.py` — not from LLM self-assessment.
- `LOW` confidence → GitHub Issue only, no PR.
- `MEDIUM` confidence → draft PR, requires approval.
- `HIGH` confidence → draft PR, may be auto-approved if policy permits.

### Code conventions
- All agent inputs/outputs: Pydantic v2 models with typed fields.
- Python: `black` formatting, `ruff` linting, `mypy --strict`.
- YAML: `kubeconform --strict` before any PR.
- Tests: `pytest` with ≥80% coverage on `src/core/` and `src/safety/`.
- No raw dicts passed between agents — use `KubeLLMState` TypedDict.

### Commands
```bash
# Proactive: generate config from natural language
kubellm generate "deploy Llama 3.1 70B on 2 A100s with autoscaling and model caching"

# Proactive: generate and open PR directly
kubellm generate --pr --repo owner/infra "deploy vLLM with KServe, 4 H100s, HPA on token throughput"

# Reactive: scan for failures
kubellm scan --namespace inference --workload vllm-llama3

# Reactive: generate fix PR from incident
kubellm fix --incident <id> --repo owner/infra --branch fix/<slug>

# Validate a YAML patch or generated config
kubellm validate --file <path>

# Development
make test          # pytest full suite
make lint          # black + ruff + mypy
make validate-all  # kubeconform on all charts/ and manifests/
```

### Where to find more context
- Full system design → `docs/architecture.md`
- Engineering decisions → `docs/decisions/ADR-*.md`
- Runbooks → `docs/runbooks/`
- Intent parser → `src/intent/CLAUDE.md`
- Config generator → `src/config_gen/CLAUDE.md`
- Best-practice library → `src/knowledge/CLAUDE.md`
- Agent graph (reactive) → `src/agents/CLAUDE.md`
- GitOps PR engine (shared) → `src/agents/gitops_fix/CLAUDE.md`
- Safety policy → `src/safety/CLAUDE.md`
- In-cluster infra → `infra/CLAUDE.md`
