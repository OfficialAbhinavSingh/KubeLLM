# Skill: Debug Inference Failure

Use this skill when investigating a new LLM inference failure or when asked to "debug", "diagnose", or "triage" a pod issue.

---

## When to use

- A vLLM / KServe / Ray Serve / Triton pod is in `CrashLoopBackOff`, `OOMKilled`, or `Pending`
- An inference endpoint is returning errors despite the pod showing `Running`
- A user reports slow or failed model responses
- You need to understand what KubeLLM Doctor detected

---

## Protocol

### 1. Collect evidence first — never guess

Run these reads before forming any hypothesis:

```bash
kubectl get pod <name> -n <ns> -o json
kubectl describe pod <name> -n <ns>
kubectl logs <name> -n <ns> --previous 2>/dev/null || true
kubectl logs <name> -n <ns>
kubectl get events -n <ns> --sort-by=.lastTimestamp
kubectl get node -o wide
```

For GPU failures also check:
```bash
kubectl describe node <gpu-node-name>
kubectl get pod <name> -n <ns> -o jsonpath='{.spec.nodeSelector}'
kubectl get pod <name> -n <ns> -o jsonpath='{.spec.tolerations}'
```

### 2. Map to a failure type

Match the collected evidence to one of the known failure types:

| Evidence | Failure type |
|---|---|
| Events: "Startup probe failed" + logs: "Loading weights" | `startup_probe_failure` |
| Events: "0/N nodes available: insufficient nvidia.com/gpu" | `gpu_pending_capacity` |
| Events: "0/N nodes available: node(s) had untolerated taints" | `gpu_pending_toleration` |
| Last state: `OOMKilled` | `oom_killed` |
| Logs: "No such file or directory" at model path | `pvc_not_mounted` |
| Logs: "torch.cuda.OutOfMemoryError" | `cuda_oom` |
| Pod Ready=True but curl /v1/models fails | `endpoint_unhealthy` |

### 3. Score confidence

Count independent evidence sources confirming the failure type:
- ≥ 3 sources → `HIGH`
- 2 sources → `MEDIUM`
- 1 source → `LOW`

### 4. Output a structured RCA

Always produce a structured object, not a prose paragraph:

```json
{
  "failure_type": "<type>",
  "root_cause": "<specific one-sentence explanation>",
  "confidence": "high|medium|low",
  "evidence": [
    "<specific evidence item 1>",
    "<specific evidence item 2>"
  ],
  "suggested_fix": {
    "file": "<gitops file path if known>",
    "change": "<what to change>",
    "risk_level": "low|medium|high"
  },
  "action": "open_pr|open_issue|report_only"
}
```

### 5. Apply safety check before any action

Before generating a PR or suggesting any fix:
- Check `src/safety/policy.py` for this action type
- If `risk_level: high` → draft PR only, mark `requires_approval: true`
- If confidence is `low` → open Issue only, no PR
- Never suggest `kubectl apply` or live cluster mutation

---

## What NOT to do

- Do not guess the root cause without collecting evidence first
- Do not open a PR at `low` confidence
- Do not suggest secrets changes (model tokens, API keys)
- Do not suggest increasing GPU replica count without noting cost impact
- Do not mark an incident as resolved until Verification Agent confirms endpoint health
