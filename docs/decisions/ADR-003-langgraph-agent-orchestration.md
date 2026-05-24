# ADR-003: LangGraph state-machine for multi-agent orchestration

**Status:** Accepted  
**Date:** 2026-05-24  
**Deciders:** KubeLLM team

---

## Context

KubeLLM Doctor requires multiple specialized agents to collaborate on a single incident:

1. Cluster Watcher detects the failure.
2. GPU Scheduler, Model Runtime, and Autoscaling agents each analyze a domain.
3. Safety Agent gates every action.
4. GitOps Fix Agent generates the PR.
5. Verification Agent confirms recovery.

Orchestration options considered:

| Option | Tradeoffs |
|---|---|
| LangChain AgentExecutor | Good tool-calling, but difficult to enforce structured handoffs or interrupt at approval gates |
| LangGraph | State-machine model, explicit node/edge control, easy human-in-the-loop suspension, structured typed state |
| CrewAI | Role-based, simpler API, but less control over state transitions and approval pauses |
| Custom state machine | Full control, but significant implementation cost |
| AutoGen | Good multi-agent conversation, but less deterministic routing for a safety-critical system |

---

## Decision

Use **LangGraph** as the agent orchestration framework.

Each agent is a LangGraph **node**. State flows along **edges** with conditional routing:
- Confidence gates route to `pr_generation` or `report_only`.
- Policy engine gates route to `approval_required` suspension or `blocked`.
- Verification result routes to `resolved` or `reopen_incident`.

The graph enforces that the Safety Agent node is **always** visited before `gitops_fix` and before any external write (GitHub API call).

**State schema** (`src/agents/state.py`):
```python
class IncidentState(TypedDict):
    incident_id: str
    failure_signals: list[FailureSignal]
    root_cause: RootCause | None
    confidence: Confidence
    policy_decision: PolicyDecision | None
    pr_result: PRResult | None
    verification: VerificationResult | None
    audit_trail: list[AuditEvent]
```

---

## Consequences

**Positive:**
- Explicit graph makes control flow reviewable by humans (not a black box).
- Human-in-the-loop approval is a first-class LangGraph primitive (`interrupt_before`).
- Typed state prevents agents from passing unvalidated data to downstream nodes.
- Each node can be independently unit-tested with mock state.

**Negative:**
- LangGraph adds a dependency and learning curve for contributors unfamiliar with it.
- Graph definition requires upfront design; ad-hoc agent additions need graph modification.

**Mitigation:**
- Graph is documented visually in `docs/architecture.md`.
- Each node is a plain Python function that accepts and returns `IncidentState`; LangGraph wiring is isolated in `src/agents/graph.py`.
