# ADR-002: Read-only cluster access via RBAC ClusterRole

**Status:** Accepted  
**Date:** 2026-05-24  
**Deciders:** KubeLLM team

---

## Context

KubeLLM Doctor must connect to customer Kubernetes clusters to collect evidence. The level of RBAC permission granted to the agent has major security and trust implications:

- Customers will resist installing an agent with broad write permissions.
- An AI agent with cluster admin access could be exploited or make destructive changes.
- vLLM/inference failures require reads across multiple resource types: pods, events, logs, nodes, PVCs, deployments, services, HPA, metrics.

---

## Decision

The KubeLLM in-cluster agent will be bound to a **read-only `ClusterRole`** with precisely scoped permissions. No `create`, `update`, `patch`, `delete`, or `exec` verbs are granted.

**Permitted verbs:** `get`, `list`, `watch`

**Permitted resources:**
```yaml
- pods, pods/log, pods/status
- events
- deployments, replicasets, statefulsets
- services, endpoints
- nodes
- persistentvolumeclaims, persistentvolumes
- namespaces
- horizontalpodautoscalers
- configmaps (non-secret)
```

**Explicitly excluded:**
```yaml
- secrets          # never read, never write
- serviceaccounts  # no token access
- roles, clusterroles, rolebindings
- networkpolicies
- exec into pods   # no pods/exec
```

The `ClusterRole` manifest lives at `infra/rbac/cluster-role.yaml`.

---

## Consequences

**Positive:**
- Minimal footprint reduces security risk to customers.
- Easy to audit: customers can review the ClusterRole YAML before installing.
- Lower barrier to adoption — customers with strict security policies can accept this.
- Consistent with the "read-only scanner" positioning in sales outreach.

**Negative:**
- Cannot read secrets, so HuggingFace token validation must be inferred from log errors rather than direct inspection.
- Cannot execute into pods for active diagnosis (e.g., `nvidia-smi` output requires DCGM exporter instead).

**Mitigation:**
- Secrets are identified by name reference in pod specs; the agent checks that the secret exists (status) without reading its value.
- GPU metrics are sourced from DCGM exporter via Prometheus or node-level metrics, not pod exec.
