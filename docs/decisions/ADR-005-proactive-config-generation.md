# ADR-005: Proactive config generation as a first-class mode

**Status:** Accepted
**Date:** 2026-05-24
**Deciders:** KubeLLM team

---

## Context

KubeLLM Doctor (reactive mode) solves failures after they happen. But the most expensive failure is deploying incorrectly in the first place — a misconfigured startupProbe, missing GPU toleration, or undersized memory limit wastes engineer hours and GPU cost before the system even gets a chance to diagnose it.

The reactive system already contains all the components needed to generate correct configs proactively:
- Cluster state reader (knows what GPU nodes exist, their labels, taints)
- Knowledge of vLLM/KServe/Triton config patterns (captured in failure rules)
- GitOps PR generation engine
- YAML validation pipeline

Adding a proactive mode reuses ~60% of the existing engine in a new direction.

This also repositions KubeLLM from a "Kubernetes debugging tool" (crowded, low WTP) to a "Cursor for infrastructure engineers" (novel, high WTP, defensible moat from cluster context awareness).

---

## Decision

Add **Proactive Mode** as a first-class KubeLLM operating mode alongside the existing reactive mode.

**Entry point:** `kubellm generate "<natural language intent>"`

**Pipeline:**
```
NL input → Intent Parser → Config Generator → Knowledge Injection
→ Cluster Validation → Safety Gate → GitOps PR → Human Approval → Verify
```

**What it generates:**
- Complete Helm values file for the requested runtime + model + hardware
- All production-required fields: startupProbe, readinessProbe, liveness probe, nodeSelector, tolerations, resource requests/limits, PVC mounts, HPA config
- PR with resource math, GPU memory calculation, cost estimate, rollback plan

**What it does NOT generate:**
- Secret values (uses references only)
- Configs for GPU counts exceeding current cluster capacity (flags this instead)
- Configs with `LOW` confidence in cluster state (requires manual cluster context)

---

## Consequences

**Positive:**
- Prevents the #1 and #2 most common failure types (startup probe, GPU scheduling) before they happen
- Makes KubeLLM valuable to a team that has never had an incident — dramatically widens the addressable market
- Reuses the existing GitOps PR engine, validation pipeline, and safety gate — minimal new infrastructure
- Creates a compounding advantage: proactive deployments feed data back into the reactive system (we know the intended config, so reactive diagnosis becomes more accurate)
- Much stronger YC pitch: "Cursor for infra" vs "AI Kubernetes debugger"

**Negative:**
- Adds complexity to the system — two entry modes vs one
- Intent parsing introduces LLM dependency into a previously deterministic pipeline
- Generated configs may be incorrect for edge cases (unusual GPU types, custom storage classes, private model repos)

**Mitigations:**
- All proactive PRs are always `REQUIRE_APPROVAL` — a human reviews before any deployment
- Confidence for proactive configs defaults to `MEDIUM` until first successful deployment confirms correctness
- Intent parsing uses strict Pydantic schema validation — if a field cannot be extracted with confidence, it defaults to a known-safe value from `src/knowledge/`, not to a guess
- The knowledge library contains only patterns that have been validated through the reactive system's failure catalogue
