# ADR-004: Three-tier confidence scoring with action gating

**Status:** Accepted  
**Date:** 2026-05-24  
**Deciders:** KubeLLM team

---

## Context

An AI-generated diagnosis can be wrong. If KubeLLM Doctor opens a GitHub PR for a root cause it has incorrectly identified, it erodes engineer trust and may introduce a regression. We need a model for expressing and acting on uncertainty.

Key constraints:
- Engineers will not trust the system if it floods them with low-quality PRs.
- A system that only acts on certainty will miss real incidents.
- Confidence must be computable from available signals, not just an LLM self-assessment.

---

## Decision

Use a **three-tier confidence model** computed deterministically from evidence signals, not from LLM self-reported confidence.

| Tier | Criteria | Action |
|---|---|---|
| `HIGH` | ≥ 3 independent evidence sources all point to the same failure type | Open draft PR immediately |
| `MEDIUM` | 2 sources confirm, 1 source ambiguous or missing | Open draft PR, mark as requiring human review |
| `LOW` | Only 1 source, or conflicting signals | Generate GitHub Issue + report only. No PR. |

**Evidence sources for scoring:**

| Source | Weight |
|---|---|
| Kubernetes events matching failure type | 1 point |
| Pod log pattern matching failure type | 1 point |
| Pod restart count above threshold | 1 point |
| Node/resource state consistent with failure | 1 point |
| Negative evidence (rules out alternative causes) | 0.5 points |

Score ≥ 3 → `HIGH`. Score 2–2.5 → `MEDIUM`. Score < 2 → `LOW`.

The scoring logic lives in `src/core/confidence.py` and is deterministic (no LLM call).

The LLM is used only to generate the human-readable `root_cause_summary` and PR body text.

---

## Consequences

**Positive:**
- Trust is built on evidence, not LLM self-reporting.
- Prevents low-quality PRs from being auto-opened.
- Engineers can inspect the scoring inputs per incident.
- Scoring is unit-testable with fixture evidence sets.

**Negative:**
- Some real failures will be scored `LOW` if logs are missing or noisy.
- Requires careful tuning of scoring thresholds per failure type (some types have naturally fewer signals).

**Mitigation:**
- Scoring thresholds are configurable per failure type in `src/core/config.py`.
- `LOW` confidence incidents still produce a useful GitHub Issue with whatever evidence was found.
- Future: feedback loop from "human-approved PRs" to recalibrate scoring weights.
