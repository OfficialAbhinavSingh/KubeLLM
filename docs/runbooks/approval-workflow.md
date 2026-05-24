# Runbook: Approval Workflow

**Use when:** You need to approve, reject, or escalate an action that KubeLLM Doctor has flagged as requiring human approval.

---

## When approval is required

The Safety Agent flags an action as `requires_approval: true` when:

| Condition | Why |
|---|---|
| `risk_level: HIGH` | Change affects GPU replica count, node selectors, or tolerations |
| `risk_level: MEDIUM` + memory limit increase > 2x current | Cost impact is significant |
| Confidence is `MEDIUM` | Evidence is not fully conclusive |
| Workload is in production namespace | Higher blast radius |
| Change affects more than 1 file | More scope = more review needed |

**Actions that can never be approved** (policy block, not subject to approval):
- Modifying Kubernetes secrets
- Deleting any workload
- Live `kubectl apply` / `kubectl patch` to production
- RBAC or NetworkPolicy changes

---

## Approval via dashboard

1. Open the KubeLLM approval inbox.
2. Review incident summary, evidence, and PR diff.
3. Click **Approve** or **Reject**.
4. Required: leave a comment for any rejection.

---

## Approval via CLI

```bash
# Approve
kubellm approve --incident <incident_id> --comment "reviewed diff, change is safe"

# Reject
kubellm reject --incident <incident_id> --reason "the memory increase is too large, needs team discussion"

# Approve with a modified PR (edit the branch before approving)
kubellm approve --incident <incident_id> --pr-override <pr_number>
```

---

## Approval via GitHub

For teams that prefer GitHub-native review:

1. Open the draft PR created by KubeLLM.
2. Review the diff.
3. Add the label `kubellm/approved` to the PR.
4. KubeLLM Doctor polls for this label and records the approval in the audit log.

**Required:** The GitHub user who adds the label must be in the `APPROVED_REVIEWERS` list in `src/safety/policy.py`.

---

## Approval expiry

Approvals expire after **24 hours** by default. If the PR is not merged within 24 hours after approval:
- The incident status returns to `approval_required`.
- A Slack notification is sent to the incident channel.
- The PR is marked as stale (label added).

This prevents stale approvals from being used after cluster state has changed.

Configure expiry in `src/safety/policy.py`:
```python
APPROVAL_EXPIRY_HOURS = 24  # default
```

---

## Audit trail

Every approval, rejection, and expiry is recorded in the `audit_events` table with:
- Actor (GitHub handle or `system`)
- Timestamp
- Hash chain entry (tamper-evident)

To view the full audit log for an incident:

```bash
kubellm audit --incident <incident_id>
```

To export for compliance:

```bash
kubellm audit --incident <incident_id> --format json > audit_export.json
```

---

## Escalation policy

| Condition | Escalation |
|---|---|
| Approval pending > 2 hours on `HIGH` severity incident | Page on-call SRE |
| PR not merged > 6 hours after approval | Slack reminder to approver |
| Third re-scan on same workload within 24h | Escalate to Infra Lead |
| Verification fails after merge | Immediate page to on-call |

Configure escalation contacts in `src/api/config.py` or via the dashboard Policy Settings screen.
