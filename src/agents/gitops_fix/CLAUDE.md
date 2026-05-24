# src/agents/gitops_fix/ — GitOps PR Generation

This is the module that touches external systems: GitHub. Every line of code here has real consequences.

## What lives here

```
src/agents/gitops_fix/
├── agent.py          # Main agent node function
├── file_locator.py   # Maps live workload → GitOps source file
├── patcher.py        # Generates minimal YAML/Helm diffs
├── validator.py      # kubeconform + helm template + kustomize validation
├── pr_body.py        # Renders structured PR body from RCA
└── github_client.py  # GitHub API calls (branch, commit, PR)
```

## Hard rules — read before touching any file here

### 1. PRs are always opened as drafts

`github_client.py` must always set `draft=True` on PR creation. This is not configurable per-incident. The only way to make a PR ready-for-review is manual human action on GitHub.

```python
# github_client.py — enforced
assert draft is True, "KubeLLM never opens ready-for-review PRs automatically"
```

### 2. Patches are minimal-diff only

`patcher.py` generates the smallest possible diff that fixes the root cause. It must not:
- Reformat the file
- Reorder keys
- Remove comments
- Change unrelated fields
- Add new sections unless strictly required

Run `git diff --stat` on the patch before validation. If more than 5 lines change for a single-field fix, investigate why.

### 3. Validation is blocking, not advisory

`validator.py` runs before the PR is opened. If any validator fails, the PR is NOT opened. The failure reason is recorded in the incident and returned to the caller.

```python
validation_result = validator.validate(patched_file, chart_path)
if not validation_result.passed:
    raise ValidationError(f"Patch failed validation: {validation_result.errors}")
    # Do NOT open PR here
```

### 4. No secret values in patches

`patcher.py` must never include actual secret values in a diff. If the fix requires a secret (e.g., HF_TOKEN), the patch adds a reference to a Kubernetes Secret by name and creates a GitHub Issue with manual instructions for the secret setup.

Pattern to follow:
```yaml
# Correct — reference, not value
env:
  - name: HF_TOKEN
    valueFrom:
      secretKeyRef:
        name: hf-token-secret      # <-- reference
        key: token

# Never do this
env:
  - name: HF_TOKEN
    value: "hf_abc123xyz..."        # <-- BLOCKED
```

### 5. Branch names are deterministic

Branch naming: `fix/<workload-name>-<failure-type-slug>-<incident-id-short>`

Example: `fix/vllm-llama3-startup-probe-a1b2c3`

This prevents duplicate branches and makes incident→branch tracing easy.

## file_locator.py — how source files are found

Source file location tries in this order:
1. ArgoCD `argocd.argoproj.io/app-source-path` annotation
2. Flux `kustomize.toolkit.fluxcd.io/name` label → mapped to overlay
3. Helm labels → `helm.sh/chart` and `app.kubernetes.io/managed-by: Helm`
4. Full-repo search in configured `GITOPS_REPO_ROOT`

If nothing is found after all 4 attempts: raise `SourceNotFoundError`. This causes the incident to generate a GitHub Issue with manual file location instructions instead.

## Testing requirements

All changes to this module require:
- Unit tests that mock the GitHub API (no real API calls in unit tests)
- Integration test with a real or stubbed Git repo
- A test that verifies draft=True is always set
- A test that verifies validation failure blocks PR creation
