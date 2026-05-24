# ADR-006: Knowledge library sourced from reactive failure patterns

**Status:** Accepted
**Date:** 2026-05-24
**Deciders:** KubeLLM team

---

## Context

The proactive config generator (ADR-005) needs a source of best-practice defaults. Two options:

**Option A:** LLM generates defaults from training knowledge
- Pros: flexible, can handle any runtime
- Cons: LLM training data is outdated; vLLM/KServe configs change rapidly; hallucination risk on probe windows and GPU math; no connection to real failure data

**Option B:** Curated library derived from reactive failure patterns
- Pros: every default is derived from a real failure mode we have seen and modeled; deterministic; versioned; testable; gets better as reactive usage grows
- Cons: requires ongoing curation; starts sparse and grows over time

---

## Decision

Use **Option B**: a curated, code-based knowledge library (`src/knowledge/`) where every default is derived from a failure type in the reactive system's catalogue.

**Derivation rule:** If a failure type in `src/agents/model_runtime/rules.py` is caused by "X was misconfigured," then the knowledge library default for X is the value that prevents that failure.

**Examples of this derivation:**

| Reactive failure (rules.py) | Knowledge library default (knowledge/) |
|---|---|
| `startup_probe_failure` — probe too short for 70B model load | `STARTUP_PROBE_WINDOWS[XLARGE] = failureThreshold: 240` |
| `gpu_pending_toleration` — toleration missing for GPU taint | `GPU_TOLERATIONS = [{key: "nvidia.com/gpu", operator: "Exists", effect: "NoSchedule"}]` |
| `oom_killed` — memory limit below vLLM base + KV cache | `MEMORY_RATIO = model_vram * 1.3` (30% buffer) |
| `pvc_not_mounted` — model cache path wrong | `MODEL_CACHE_MOUNT = {mountPath: "/root/.cache/huggingface"}` |

This means every time we add a new reactive failure scenario, we also add (or update) the corresponding knowledge library entry that prevents it. The two systems are coupled by design.

**Versioning:** The knowledge library is versioned alongside the application code. When a new vLLM version changes default behavior, a PR updates both the failure rules and the knowledge defaults together.

---

## Consequences

**Positive:**
- Knowledge defaults are battle-tested, not academic — they come from real failure patterns
- As reactive usage accumulates data, knowledge library quality improves organically
- Fully deterministic — no LLM call needed to apply defaults
- Testable: unit tests can verify `knowledge.get_probe_config(RuntimeType.VLLM, ModelSizeTier.LARGE)` returns the exact expected values
- Creates a defensible moat: competitors cannot copy the knowledge library without also having the failure pattern data that informs it

**Negative:**
- Library starts sparse — V0 only covers vLLM failure scenarios that are already modeled
- Defaults may not be optimal for all hardware configurations (A100 vs H100 vs A10G have different characteristics)
- Requires discipline to keep rules.py and knowledge/ in sync

**Mitigations:**
- V0 ships with defaults for the 5 MVP failure scenarios — enough to generate a correct vLLM deployment
- Hardware-specific overrides are supported: `knowledge.get_probe_config(runtime, model_size, gpu_type=GPUType.H100)`
- A coupling test in `tests/unit/test_knowledge_coverage.py` asserts that every failure type in `rules.py` has a corresponding knowledge library entry
