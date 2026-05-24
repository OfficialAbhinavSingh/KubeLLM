# Skill: Generate GitOps PR

Use this skill when asked to "generate a PR", "create a fix", "open a pull request", or "patch the manifest" for an incident.

---

## When to use

- An incident has `confidence: high` or `confidence: medium`
- A root cause and suggested fix have been identified
- You need to find the correct GitOps file and generate a minimal, validated patch

---

## Protocol

### 1. Prerequisite checks

Before touching any file, verify:

```python
assert incident.confidence in ("high", "medium"), "LOW confidence — open Issue, not PR"
assert policy_decision.decision != "block", "Action is blocked by policy"
assert incident.suggested_fix.risk_level != "high" or policy_decision.requires_approval, \
    "HIGH risk requires approval flag"
```

### 2. Locate the source file

Try in order:

1. Check ArgoCD/Flux annotations on the live Deployment for GitOps source path
2. Check Helm release labels → map to `charts/<release>/values.yaml`
3. Check Kustomize labels → map to overlay path
4. Search configured `GITOPS_REPO_ROOT` for YAML containing the workload name

If not found: create a GitHub Issue with manual instructions. Stop here.

### 3. Generate a minimal patch

Rules for the patch:
- Change **only** the field that fixes the root cause
- Do not reformat, re-order, or clean up unrelated parts of the file
- Preserve all comments in the original file
- For Helm values: change the specific key, not the entire values block
- For raw YAML: use strategic merge patch syntax in the PR body

### 4. Validate before opening PR

```bash
# Always run kubeconform
kubeconform -strict -summary <patched_file>

# If Helm
helm template <chart_path> -f <patched_values_file> > /dev/null

# If Kustomize
kustomize build <overlay_path> > /dev/null
```

If validation fails: do not open the PR. Report the validation error in the incident.

### 5. Build the PR body

Use this exact template. Every section is required:

```markdown
## Root Cause
<one specific sentence — not generic>

## Evidence
- <evidence_item_1>
- <evidence_item_2>
- <evidence_item_3_if_available>

## Files Changed
- `<file_path>` — <what changed and why>

## Risk Level
<LOW | MEDIUM | HIGH>

## Validation
- kubeconform: PASS
- helm template: PASS / N/A
- kustomize build: PASS / N/A

## Expected Impact
<what should improve after this change>

## Cost Impact
<none | estimated delta if relevant>

## Rollback Plan
```bash
git revert <commit_sha>
# or helm rollback <release> <revision>
```

## Agent Confidence
<HIGH | MEDIUM>

## Approval Status
- [ ] Human reviewer approved
```

### 6. Open as draft PR

```bash
gh pr create \
  --title "fix(<workload>): <root_cause_slug>" \
  --body "$(cat pr_body.md)" \
  --draft \
  --base main \
  --head fix/<incident-slug>
```

**Always open as draft.** Never open a ready-for-review PR automatically.

### 7. Post-PR actions

- Link PR URL to incident record
- If `risk_level: high` or `confidence: medium`: post to Slack approval channel
- Set incident status to `pr_opened`
- Do not merge — wait for human approval

---

## PR title conventions

```
fix(vllm): increase startupProbe window for model load time
fix(gpu): add nvidia toleration for GPU node scheduling
fix(pvc): add model cache volumeMount to inference container
fix(memory): increase memory limit to prevent OOMKilled
```

---

## What NOT to do

- Do not open a non-draft PR
- Do not merge the PR yourself
- Do not patch more than the minimum required to fix the root cause
- Do not include unrelated formatting or cleanup in the diff
- Do not patch secret values — create an Issue with instructions instead
