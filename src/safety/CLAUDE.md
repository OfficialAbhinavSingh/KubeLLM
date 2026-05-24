# src/safety/ — Policy Engine & Approval Gate

**This is a danger zone. Read this file completely before modifying anything here.**

The safety module is the only thing preventing KubeLLM Doctor from making unsafe automated changes to production infrastructure. Any bug here can cause:
- A high-risk action being executed without approval
- A blocked action being accidentally allowed
- Audit log entries being missing or incorrect
- A live cluster mutation reaching production

## What lives here

```
src/safety/
├── policy.py          # Action policy table — allow/block/require_approval decisions
├── audit.py           # Hash-chained audit log writer
├── approval.py        # Approval state machine and expiry logic
└── constants.py       # Risk levels, action types, policy defaults
```

## Rules — enforced, not optional

### 1. Policy table is the source of truth

`policy.py` contains the authoritative action → decision mapping. No other module may make allow/block decisions. All agents must call `policy.check(action_type, context)` and respect the result.

The policy table must be updated via PR + review. It must not be changed as part of an incident fix.

### 2. Every action that reaches Safety must be logged

`audit.py` must be called for every action that Safety evaluates, including:
- `ALLOW` decisions (not just blocks)
- `REQUIRE_APPROVAL` transitions
- Approval granted / rejected events
- Approval expiry events
- Block events

Missing audit entries make post-incident review impossible.

### 3. Audit log is hash-chained

Each `AuditEvent` contains:
- `hash`: SHA256 of (`incident_id` + `event_type` + `actor` + `message` + `created_at`)
- `previous_hash`: hash of the immediately preceding event for this incident

This creates a tamper-evident chain. Do not break the chain by inserting or deleting events. Do not reuse or regenerate hashes.

### 4. Approval expiry is enforced server-side

`approval.py` checks expiry timestamps on every action evaluation, not just on first approval. An expired approval is treated as `requires_approval` again — the action is not executed.

Do not cache approval decisions in the agent layer. Always call `approval.is_valid(approval_id)` before acting.

### 5. Block decisions cannot be overridden by configuration

Actions in the `HARD_BLOCK` list in `constants.py` cannot be enabled by any configuration change, feature flag, or runtime override. They require a code change + PR + review to modify.

Current hard blocks:
```python
HARD_BLOCK = {
    "kubectl_apply_live",
    "kubectl_patch_live",
    "kubectl_delete",
    "modify_secret",
    "exec_into_pod",
    "modify_rbac",
    "modify_network_policy",
}
```

## Modifying the policy table

If you need to change an `allow/block/require_approval` decision:

1. Open a PR titled `policy: <description of change>`
2. Include in the PR body:
   - Why the change is needed
   - What risk it introduces
   - What mitigations exist
3. Requires review from at least 2 team members
4. Add a corresponding test in `tests/unit/test_safety/test_policy.py`

## Testing requirements

All changes to this module require:
- `tests/unit/test_safety/test_policy.py` — every action type has a test
- `tests/unit/test_safety/test_audit.py` — hash chain integrity test
- `tests/unit/test_safety/test_approval.py` — expiry test, state transition test
- Tests must not mock the policy table — they test the real policy decisions

Run before any PR on this module:
```bash
pytest tests/unit/test_safety/ -v --tb=short
```

All tests must pass. No exceptions.
