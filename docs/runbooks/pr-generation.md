# Runbook: GitOps PR Generation

**Use when:** You need to understand how KubeLLM Doctor generates PRs, debug a failed PR generation, or manually trigger PR generation for an existing incident.

---

## How PR generation works

```
Incident with HIGH or MEDIUM confidence
        ↓
GitOps Fix Agent: identify source file
        ↓
Clone / fetch target GitHub repo
        ↓
Locate exact field in Helm values / Kustomize / YAML
        ↓
Generate minimal YAML diff
        ↓
Validation:
  kubeconform (Kubernetes schema)
  helm template --dry-run (if Helm)
  kustomize build (if Kustomize)
        ↓
Create branch: fix/<incident-slug>
        ↓
Open draft PR with structured body
        ↓
Post PR link to incident + Slack
```

---

## How the source file is located

KubeLLM Doctor attempts file location in this order:

1. **ArgoCD/Flux annotations** on the Deployment/StatefulSet:
   ```yaml
   annotations:
     argocd.argoproj.io/managed-by: argocd
     kubectl.kubernetes.io/last-applied-configuration: ...
   ```
2. **Helm release labels**:
   ```yaml
   labels:
     helm.sh/chart: vllm-1.2.3
     app.kubernetes.io/managed-by: Helm
   ```
   → finds Helm release → maps to `charts/<name>/values.yaml`
3. **Kustomize labels**:
   ```yaml
   labels:
     kustomize.toolkit.fluxcd.io/name: vllm-overlay
   ```
4. **Fallback**: search configured `GITOPS_REPO_ROOT` for YAML files referencing the workload name.

If no source file is found, the incident is marked `source_not_found` and an Issue is created with manual instructions.

---

## Manually trigger PR generation

```bash
kubellm fix \
  --incident <incident_id> \
  --repo owner/inference-infra \
  --branch fix/vllm-startup-probe-<incident_id_short> \
  --dry-run          # print diff only, do not open PR
```

Remove `--dry-run` to actually open the PR.

---

## PR validation failures

If `kubellm fix` reports a validation error:

### kubeconform failure

```
Error: kubeconform validation failed
  deployments.apps "vllm" is invalid: spec.template.spec.containers[0].startupProbe.failureThreshold: must be greater than 0
```

**Fix:** The generated patch has an invalid value. Check `--dry-run` output for the offending field. File a bug in the issue tracker.

### helm template failure

```
Error: helm template failed: coerce "" into int
```

**Fix:** The Helm values patch introduced a type mismatch. Review the Helm chart schema (`values.schema.json`) for the correct type.

### Branch already exists

```
Error: branch fix/vllm-startup-probe already exists
```

**Fix:** 

```bash
# Delete the stale branch and retry
gh api -X DELETE repos/owner/repo/git/refs/heads/fix/vllm-startup-probe
kubellm fix --incident <id> --repo owner/repo --branch fix/vllm-startup-probe-v2
```

---

## PR body must always include

Before approving any PR, verify these sections are present:

- [ ] `## Root Cause` — specific, not generic
- [ ] `## Evidence` — at least 2 items
- [ ] `## Files Changed` — exact paths
- [ ] `## Risk Level` — `LOW`, `MEDIUM`, or `HIGH`
- [ ] `## Validation` — at least kubeconform result
- [ ] `## Rollback Plan` — executable commands

If any section is missing, reject the PR and re-run:

```bash
kubellm fix --incident <id> --repo owner/repo --regenerate-body
```

---

## GitHub token permissions required

The GitHub App or PAT used by KubeLLM needs:

| Permission | Level |
|---|---|
| Contents | Read + Write (to push branch) |
| Pull requests | Write (to open PR) |
| Issues | Write (for LOW confidence issues) |
| Metadata | Read |

**Never grant:**
- Admin
- Secrets
- Actions write
- Deployments write (unless Verification Agent needs it in V2)
