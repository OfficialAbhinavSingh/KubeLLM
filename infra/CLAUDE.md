# infra/ — Kubernetes Deployment & RBAC

This directory contains everything needed to deploy KubeLLM Doctor's in-cluster agent.

## What lives here

```
infra/
├── helm/
│   └── kubellm-agent/
│       ├── Chart.yaml
│       ├── values.yaml
│       └── templates/
│           ├── deployment.yaml
│           ├── serviceaccount.yaml
│           ├── clusterrole.yaml        # READ-ONLY — critical
│           ├── clusterrolebinding.yaml
│           ├── configmap.yaml
│           └── secret.yaml             # placeholders only
└── rbac/
    └── cluster-role.yaml               # Standalone RBAC for manual install
```

## Hard rules for this directory

### 1. The ClusterRole is read-only — keep it that way

`infra/rbac/cluster-role.yaml` and `infra/helm/kubellm-agent/templates/clusterrole.yaml` must only contain these verbs: `get`, `list`, `watch`.

**Never add:** `create`, `update`, `patch`, `delete`, `exec`, `bind`, `escalate`.

If a new feature requires reading a new resource type, add it with `get/list/watch` only. If a new feature claims to require write access to the cluster, escalate to the team — this likely means the architecture needs rethinking, not that the ClusterRole should be expanded.

### 2. Secrets in Helm chart are references, not values

`infra/helm/kubellm-agent/templates/secret.yaml` creates placeholder secrets. Actual values must be provided by the operator at install time via:

```bash
helm install kubellm-agent ./infra/helm/kubellm-agent \
  --set secrets.githubToken="<REPLACE>" \
  --set secrets.slackWebhook="<REPLACE>"
```

Never commit actual token or secret values. Use `<REPLACE_WITH_SECRET>` as placeholder in YAML files.

### 3. Default values are safe (no production write access)

`values.yaml` defaults:
- `clusterAccess: readOnly: true`
- `livePatching: enabled: false`
- `autoApprove: enabled: false`

These are opt-in, not opt-out. If a customer wants to enable live patching or auto-approve, they must explicitly set these values. This ensures a fresh install is always safe by default.

### 4. Validate before committing

Before committing any change to this directory:

```bash
# Validate Helm chart renders without errors
helm template kubellm-agent ./infra/helm/kubellm-agent > /tmp/rendered.yaml

# Validate rendered YAML against Kubernetes schema
kubeconform -strict -summary /tmp/rendered.yaml

# Dry-run against a local cluster
kubectl apply --dry-run=server -f /tmp/rendered.yaml
```

The `kubectl --dry-run=server` step requires access to a non-production cluster (use k3d/minikube for local).

## Resource requirements

The in-cluster KubeLLM agent is read-only and lightweight:

```yaml
resources:
  requests:
    cpu: 100m
    memory: 128Mi
  limits:
    cpu: 500m
    memory: 512Mi
```

Do not increase these limits without a measured justification. The agent should not compete with inference workloads for resources.
