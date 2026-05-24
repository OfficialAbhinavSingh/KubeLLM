# Skill: Review a Root Cause Analysis

Use this skill when asked to "review the RCA", "check this diagnosis", "is this correct?", or "validate the root cause" for an incident.

---

## When to use

- An RCA has been generated and you need to verify its quality before a PR is opened
- A human-submitted RCA needs to be checked for completeness and correctness
- A PR is open and you need to verify the PR body matches the evidence

---

## Protocol

### 1. Verify the evidence is real and specific

For each evidence item, check:

| Check | Pass condition |
|---|---|
| Is it a direct observation? | Yes = specific log line, event text, pod status field |
| Or is it an inference? | Inferences are OK only in `root_cause`, not in `evidence` |
| Is the timestamp aligned? | Evidence should be from the failure window, not days ago |
| Are there at least 2 independent sources? | Events + logs count as independent; 2 log lines do not |

**Red flags in evidence:**
- "Pod has been restarting" (vague — how many restarts? Over what period?)
- "Logs indicate a problem" (not specific — what exact log pattern?)
- "The node might not have a GPU" (uncertainty in evidence = low confidence)

**Good evidence:**
- "Pod restarted 9 times in 20 minutes (kubernetes Events)"
- "Event: Startup probe failed after 60s (kubernetes Events)"
- "Log line at 14:32:01: 'Loading model weights...' — model still loading at probe timeout"

### 2. Verify the failure type is correct

Check against the catalogue in `docs/architecture.md` Section 6.

Ask:
- Does the evidence actually point to this failure type?
- Is there an alternative failure type that fits the same evidence better?
- Has the agent ruled out alternatives? (This is the `negative_evidence` field)

### 3. Verify confidence is correctly scored

Count independent sources:
- ≥ 3 → should be `HIGH`
- 2 → should be `MEDIUM`
- 1 → should be `LOW`

If confidence is higher than the evidence supports: downgrade it and explain why.

### 4. Verify the suggested fix is minimal and safe

Check:
- Does the fix address the root cause specifically?
- Does the fix change more than necessary? (over-patching is a risk)
- Does the fix have a valid rollback path?
- Is the risk level correctly assigned? (see `src/safety/policy.py` for criteria)

### 5. Output a review result

```json
{
  "review_result": "approved | needs_revision | rejected",
  "issues": [
    {
      "field": "evidence[1]",
      "issue": "evidence item is vague — needs specific log line and timestamp",
      "severity": "must_fix | should_fix | suggestion"
    }
  ],
  "confidence_assessment": "correctly_scored | should_be_lower | should_be_higher",
  "fix_assessment": "minimal_and_safe | over_scoped | missing_rollback | risk_level_wrong",
  "recommendation": "<one sentence summary>"
}
```

---

## Common RCA mistakes to catch

| Mistake | How to catch it |
|---|---|
| Correlation without causation | Ask: "Does the evidence prove this cause, or just correlate with the failure time?" |
| Single evidence source scored HIGH | Count sources — should be MEDIUM or LOW |
| Fix changes more than the failing field | Review the diff — is every line change necessary? |
| Missing rollback plan | Check PR body for `## Rollback Plan` with executable commands |
| Confidence stated as "the model says X" | Confidence must come from evidence count, not LLM self-assessment |
