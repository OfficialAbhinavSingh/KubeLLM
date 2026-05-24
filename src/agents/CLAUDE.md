# src/agents/ — Dual-Mode LangGraph Agent Graph

This directory contains the LangGraph state machine and all agent nodes for both Proactive and Reactive modes.

## What lives here

```
src/agents/
├── graph.py              # Full dual-mode LangGraph graph
├── state.py              # KubeLLMState TypedDict — single shared state
├── cluster_watcher/      # Reactive: pod/event/node health detection
├── gpu_scheduler/        # Reactive: GPU scheduling checks
├── model_runtime/        # Reactive: vLLM/KServe/Ray/Triton log analysis + rules
│   └── rules.py          # Deterministic failure pattern rules (no LLM)
├── autoscaling/          # Reactive: HPA/KEDA/Prometheus scaling checks
├── root_cause/           # Reactive: aggregates evidence → RCA + confidence
├── gitops_fix/           # Shared: file locate → patch/generate → validate → PR
│   └── CLAUDE.md
├── safety/               # Shared: policy gate (ALWAYS before gitops_fix)
└── verification/         # Shared: post-merge pod + endpoint health check
```

## Dual-mode state

Both modes share one `KubeLLMState` TypedDict. Mode is determined by `entry_mode` field:

```python
class KubeLLMState(TypedDict):
    # Shared
    entry_mode: Literal["proactive", "reactive"]
    audit_trail: list[AuditEvent]
    policy_decision: PolicyDecision | None
    pr_result: PRResult | None
    verification: VerificationResult | None

    # Proactive mode fields
    raw_intent: str | None
    deployment_intent: DeploymentIntent | None
    generated_config: GeneratedConfig | None
    cluster_context: ClusterContext | None

    # Reactive mode fields
    incident_id: str | None
    failure_signals: list[FailureSignal]
    evidence_items: list[EvidenceItem]
    root_cause: RootCause | None
    confidence: Confidence | None
```

## Graph structure

```python
# graph.py — simplified
graph = StateGraph(KubeLLMState)

# Proactive path nodes
graph.add_node("intent_parser",    intent_parser_node)
graph.add_node("config_generator", config_generator_node)

# Reactive path nodes
graph.add_node("cluster_watcher",  cluster_watcher_node)
graph.add_node("gpu_scheduler",    gpu_scheduler_node)
graph.add_node("model_runtime",    model_runtime_node)
graph.add_node("autoscaling",      autoscaling_node)
graph.add_node("root_cause",       root_cause_node)

# Shared nodes
graph.add_node("safety_agent",     safety_agent_node)
graph.add_node("gitops_fix",       gitops_fix_node)
graph.add_node("approval_wait",    approval_wait_node)   # LangGraph interrupt
graph.add_node("verification",     verification_node)
graph.add_node("report_only",      report_only_node)     # LOW confidence exit
graph.add_node("blocked",          blocked_node)         # Policy block exit

# Entry routing
graph.set_conditional_entry_point(
    route_entry,   # "intent_parser" if proactive, "cluster_watcher" if reactive
)

# Proactive path
graph.add_edge("intent_parser", "config_generator")
graph.add_edge("config_generator", "safety_agent")

# Reactive path
graph.add_edge("cluster_watcher", "gpu_scheduler")
graph.add_edge("gpu_scheduler", "model_runtime")
graph.add_edge("model_runtime", "autoscaling")
graph.add_edge("autoscaling", "root_cause")
graph.add_conditional_edges(
    "root_cause",
    route_after_root_cause,  # "safety_agent" (HIGH/MEDIUM) | "report_only" (LOW)
)

# Shared path — safety is ALWAYS visited before gitops_fix
graph.add_conditional_edges(
    "safety_agent",
    route_after_safety,  # "gitops_fix" | "approval_wait" | "blocked"
)
graph.add_edge("gitops_fix", "approval_wait")
graph.add_edge("approval_wait", "verification")   # resumes after human approval + merge
```

## Non-negotiable graph rules

### 1. `safety_agent` is always visited before `gitops_fix`

There is no edge from any node directly to `gitops_fix` that does not pass through `safety_agent`. If you add a shortcut edge that bypasses safety, it will be caught in code review and reverted.

### 2. `approval_wait` uses LangGraph interrupt

The graph pauses at `approval_wait` using `interrupt_before=["verification"]`. The graph state is persisted to the database. When a human approves the PR (via dashboard, CLI, or GitHub label), the graph resumes from the checkpoint.

```python
# approval_wait_node
def approval_wait_node(state: KubeLLMState) -> KubeLLMState:
    # This node does nothing except mark the state as waiting
    # The actual wait is handled by LangGraph's interrupt mechanism
    return {**state, "status": "waiting_approval"}
```

### 3. All agent nodes have the same signature

```python
def <agent>_node(state: KubeLLMState) -> dict:
    # Process state
    # Return only the fields that changed (partial state update)
    return {"<field>": <new_value>}
```

Never return the full state dict. Return only changed fields. LangGraph merges them.

### 4. No LLM calls in rules.py

`src/agents/model_runtime/rules.py` contains only deterministic pattern-matching rules. No LLM calls. Each rule is a class with a `matches(evidence: EvidenceBundle) -> RuleMatch | None` method.

LLM calls happen only in:
- `src/intent/extractor.py` (intent extraction)
- `src/agents/root_cause/summarizer.py` (human-readable RCA summary)
- `src/agents/gitops_fix/pr_body.py` (PR body text)

### 5. Evidence agents are independent and parallelizable

`gpu_scheduler`, `model_runtime`, and `autoscaling` agents do not depend on each other's output. In V1, they should be parallelized using LangGraph's `Send` API to reduce diagnosis latency.

### 6. No cluster writes from any agent node

Agent nodes may only call `src/integrations/kubernetes_client.KubernetesReader`. Write operations are not exposed. If an agent node imports anything other than `KubernetesReader` from `src/integrations/kubernetes_client`, it is a bug.

## Adding a new reactive agent

1. Create `src/agents/<agent_name>/agent.py` with a node function `(<name>_node)`
2. Add new fields to `KubeLLMState` in `state.py`
3. Wire into `graph.py` — ensure Safety routing is preserved
4. Add unit tests: `tests/unit/test_agents/test_<name>.py`
5. Update `docs/architecture.md` Section 3
