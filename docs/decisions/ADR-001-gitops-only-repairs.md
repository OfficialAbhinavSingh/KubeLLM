# ADR-001: GitOps-only repairs — no live production mutation

**Status:** Accepted  
**Date:** 2026-05-24  
**Deciders:** KubeLLM team

---

## Context

When an LLM inference workload fails, the fastest path to recovery is to patch the live Kubernetes object directly (`kubectl edit` / `kubectl apply`). However, this creates operational risk:

- Direct mutations bypass GitOps reconciliation (ArgoCD/Flux drift).
- No audit trail of who changed what and why.
- Engineers cannot review or reject an automated change before it lands.
- AI-generated patches may be incorrect and could worsen the failure.
- Production clusters at inference companies may serve millions of tokens per hour; a bad live patch could be catastrophic.

---

## Decision

KubeLLM Doctor will **never directly mutate a live production Kubernetes object**. All repairs are delivered exclusively as **GitHub Pull Requests** against the GitOps source (Helm values, Kustomize overlays, or raw YAML manifests).

The flow is:
```
Evidence → Root cause → Policy check → PR (draft) → Human approval → GitOps merge → Verification
```

Live cluster write access is permanently blocked at the policy engine level (see `src/safety/`).

---

## Consequences

**Positive:**
- Humans remain in control of all production changes.
- Full audit trail via Git history + KubeLLM audit log.
- Reduces risk of AI-generated mistakes reaching production.
- Aligns with GitOps principles that most target customers already use.
- Design partner acquisition is easier — read-only cluster access is a low-trust ask.

**Negative:**
- MTTR is slower than live patching (minutes vs seconds for PR review).
- Requires that customers have their manifests in GitHub (or similar).
- Does not help teams with fully manual `kubectl`-based workflows.

**Mitigation:**
- V1 will add an "emergency fast-path" option: pre-approved PR auto-merge for specific low-risk fix types if the customer explicitly opts in.
- Audit every fast-path use prominently.
