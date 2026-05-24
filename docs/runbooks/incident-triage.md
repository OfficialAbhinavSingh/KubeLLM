# Runbook: LLM Inference Incident Triage

**Use when:** A KubeLLM Doctor incident is created and you need to understand what happened, assess the evidence, and decide whether to approve the generated PR.

---

## Step 1: Understand the incident

Open the incident from the dashboard or via CLI:

```bash
kubellm incident show --id <incident_id>
```

Check:
- `failure_type` — what class of failure was detected
- `confidence` — `HIGH`, `MEDIUM`, or `LOW`
- `runtime_type` — which inference runtime (vLLM, KServe, Ray Serve, Triton)
- `severity` — `low`, `medium`, `high`, `critical`

**If confidence is `LOW`:** No PR was opened. Review the GitHub Issue instead. Add missing evidence manually before requesting a re-scan.

---

## Step 2: Review the evidence

```bash
kubellm evidence list --incident <incident_id>
```

For each evidence item, verify:

| Evidence type | What to check |
|---|---|
| `k8s_event` | Does the event timestamp match the failure window? |
| `pod_log` | Is the log pattern genuinely from the inference runtime, not a one-off? |
| `node_label` | Are the node labels current? (Node pool changes may not be reflected) |
| `pvc_status` | Is the PVC issue transient (storage provisioner delay) or persistent? |
| `metric` | Is the metric window aligned with the incident? |

---

## Step 3: Review the PR

Open the draft PR linked in the incident.

**Check the PR body for:**
- [ ] Root cause clearly stated
- [ ] Evidence list matches what you saw in Step 2
- [ ] Files changed are the correct GitOps files for this workload
- [ ] Risk level is accurately assigned
- [ ] Validation passed (kubeconform, helm template)
- [ ] Rollback plan is complete and executable

**Review the diff:**
- For `startupProbe` changes: verify the new `failureThreshold` is reasonable for the model size
- For node selector changes: verify the label exists on at least one ready node
- For memory limit changes: verify the new value is above current OOMKill threshold

---

## Step 4: Approve or reject

**Approve:**

```bash
kubellm approve --incident <incident_id>
# or approve via GitHub PR review
```

**Reject with reason:**

```bash
kubellm reject --incident <incident_id> --reason "evidence is from a transient storage delay, not a config issue"
```

**Request re-analysis:**

```bash
kubellm rescan --incident <incident_id> --force
```

---

## Step 5: Post-merge verification

After the PR is merged and GitOps deploys, the Verification Agent runs automatically. Check:

```bash
kubellm verify --incident <incident_id>
```

If verification fails (endpoint not recovering):
1. Do not merge a second fix immediately.
2. Check if GitOps reconciliation completed (`argocd app sync` or `flux reconcile`).
3. Check pod events for new failure type.
4. Create a new incident or escalate.

---

## Escalation

Escalate to a senior SRE if:
- Confidence is `MEDIUM` and the change affects GPU replica count or node selectors
- The PR changes more than 3 files
- The affected workload is customer-facing production with active traffic
- `risk_level` is `HIGH`

---

## Common failure type quick reference

| Failure type | Immediate check |
|---|---|
| `startup_probe_failure` | `kubectl describe pod <name>` → Events → look for "Startup probe failed" |
| `gpu_pending` | `kubectl describe pod <name>` → Events → "0/N nodes available: insufficient nvidia.com/gpu" |
| `pvc_not_mounted` | `kubectl get pvc -n <ns>` → check Bound status |
| `oom_killed` | `kubectl describe pod <name>` → Last State → reason: OOMKilled |
| `endpoint_unhealthy` | `curl http://<svc>/v1/models` — inspect response |
