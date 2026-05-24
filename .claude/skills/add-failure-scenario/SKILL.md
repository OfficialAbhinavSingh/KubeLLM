# Skill: Add a New Failure Scenario

Use this skill when asked to "add a new failure type", "implement a new scenario", "support a new error", or "handle <X> failure".

---

## When to use

- Adding detection for a failure type not yet in `src/agents/`
- Adding a new broken demo scenario to `charts/` or `manifests/`
- Extending the failure scenario catalogue in `docs/architecture.md`

---

## Protocol

Every new failure scenario requires all 5 artifacts. Do not add a partial scenario.

### 1. Add a broken demo YAML

In `charts/vllm/` (or the relevant runtime chart):

```yaml
# charts/vllm/values-bad-<scenario-slug>.yaml
# Scenario: <title>
# Failure: <what this config causes>
# Evidence to look for: <what KubeLLM Doctor should detect>

replicaCount: 1
image:
  repository: vllm/vllm-openai
  tag: latest

# <The intentionally broken config goes here>
```

Naming convention: `values-bad-<scenario-slug>.yaml`

### 2. Add the detection rule

In `src/agents/model_runtime/rules.py` (or the appropriate agent):

```python
@dataclass
class <ScenarioName>Rule:
    """
    Detects: <failure type>
    Evidence required: <list what signals are needed>
    Confidence scoring: <describe how confidence is calculated>
    """

    def matches(self, evidence: EvidenceBundle) -> RuleMatch | None:
        # Return RuleMatch with confidence score, or None if no match
        ...
```

Rules must be pure functions of `EvidenceBundle` — no side effects, no LLM calls.

### 3. Add unit tests

In `tests/unit/test_rules/test_<scenario_slug>.py`:

```python
def test_<scenario>_high_confidence():
    evidence = EvidenceBundle(
        events=[...],  # matching signals
        logs=[...],
        pod_status=...,
    )
    rule = <ScenarioName>Rule()
    match = rule.matches(evidence)
    assert match is not None
    assert match.confidence == Confidence.HIGH
    assert match.failure_type == "<failure_type>"

def test_<scenario>_no_match_when_different_cause():
    # Evidence that looks similar but is a different root cause
    ...
```

Tests must cover: match, no-match, and edge cases (missing log data, transient events).

### 4. Add an integration scenario test

In `tests/scenarios/<scenario-slug>/`:

```
tests/scenarios/<scenario-slug>/
  README.md          # what the scenario tests and how to reproduce
  broken.yaml        # the broken manifest
  expected_rca.json  # what KubeLLM should produce
  expected_pr.md     # what the PR body should contain
```

### 5. Update the catalogue

In `docs/architecture.md`, Section 6 (Failure scenario catalogue):

Add a row:
```markdown
| S<N> | <Scenario title> | <Runtime> | <Confidence> |
```

And in `KubeLLM_Doctor_Project_Plan.md` Section 11, add the scenario with:
- Problem description
- Detection evidence list
- Fix description

---

## Checklist before marking complete

- [ ] Broken demo YAML added to `charts/`
- [ ] Detection rule added to appropriate agent
- [ ] Unit tests pass: `pytest tests/unit/test_rules/test_<scenario>.py -v`
- [ ] Integration scenario test added
- [ ] Catalogue updated in `docs/architecture.md`
- [ ] PR opened against `main` (do not push directly)
