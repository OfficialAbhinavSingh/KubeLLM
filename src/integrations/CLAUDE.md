# src/integrations/ — External System Clients

**Role:** Thin, typed wrappers around external APIs. Each integration module has one responsibility: talk to one external system. No business logic here.

## What lives here

```
src/integrations/
├── kubernetes_client.py   # Read-only Kubernetes API client
├── github_client.py       # GitHub App / PAT — PR creation, file reads
├── slack_client.py        # Slack webhook — alerts, approval notifications
├── prometheus_client.py   # Prometheus query client (optional)
└── tests/
    ├── test_kubernetes.py  # Uses mock k8s API
    └── test_github.py      # Uses mock GitHub API
```

## kubernetes_client.py — critical rules

### Read-only. Always.

The Kubernetes client exposes only these operations:

```python
class KubernetesReader:
    def get_pod(self, namespace: str, name: str) -> V1Pod: ...
    def list_pods(self, namespace: str, label_selector: str = "") -> list[V1Pod]: ...
    def get_pod_logs(self, namespace: str, name: str, previous: bool = False) -> str: ...
    def list_events(self, namespace: str) -> list[CoreV1Event]: ...
    def get_deployment(self, namespace: str, name: str) -> V1Deployment: ...
    def list_nodes(self) -> list[V1Node]: ...
    def get_node(self, name: str) -> V1Node: ...
    def get_pvc(self, namespace: str, name: str) -> V1PersistentVolumeClaim: ...
    def list_pvcs(self, namespace: str) -> list[V1PersistentVolumeClaim]: ...
    def get_hpa(self, namespace: str, name: str) -> V1HorizontalPodAutoscaler: ...
    def list_storage_classes(self) -> list[V1StorageClass]: ...
    def check_secret_exists(self, namespace: str, name: str) -> bool: ...
    # ^ Note: check_secret_exists returns bool, never the secret value
```

**Do not add any method with verbs: create, update, patch, delete, apply, replace, exec.**

If a new feature appears to require a write operation (e.g., "create namespace"), it must go through the GitOps PR pipeline — not a direct Kubernetes API call.

### RBAC must match

Every method in `KubernetesReader` must correspond to a resource + verb in `infra/rbac/cluster-role.yaml`. When you add a new read method, add the corresponding RBAC entry in the same PR.

### Auth modes

```python
class KubernetesReader:
    def __init__(self, in_cluster: bool = False):
        if in_cluster:
            config.load_incluster_config()   # inside the cluster pod
        else:
            config.load_kube_config()        # local kubeconfig
```

The `in_cluster` flag comes from `src/core/config.py Settings.in_cluster`. Do not hardcode either path.

---

## github_client.py — rules

### Token handling

GitHub authentication supports two modes:
1. **GitHub App** (preferred for production) — `GITHUB_APP_ID` + `GITHUB_PRIVATE_KEY`
2. **PAT** (acceptable for prototyping) — `GITHUB_PAT`

The client selects the mode automatically from which env vars are set. Both must be read from `src/core/config.py` — never hardcoded.

### PR creation always sets draft=True

```python
def create_pull_request(
    self,
    repo: str,
    title: str,
    body: str,
    head: str,
    base: str,
    draft: bool = True,   # default is True — cannot be False without policy override
) -> PullRequest:
    assert draft is True, "KubeLLM never creates non-draft PRs automatically"
    ...
```

### File reading for manifest location

```python
def get_file_content(self, repo: str, path: str, ref: str = "main") -> str: ...
def search_code(self, repo: str, query: str) -> list[SearchResult]: ...
def list_directory(self, repo: str, path: str, ref: str = "main") -> list[RepositoryContent]: ...
```

These are used by `src/agents/gitops_fix/file_locator.py` to find the GitOps source file.

---

## slack_client.py — rules

Slack is notification-only. No commands, no interactive buttons (in V0).

```python
class SlackNotifier:
    def post_incident_summary(self, channel: str, incident: Incident) -> None: ...
    def post_pr_opened(self, channel: str, pr_url: str, risk_level: RiskLevel) -> None: ...
    def post_approval_required(self, channel: str, incident_id: str, pr_url: str) -> None: ...
    def post_verification_result(self, channel: str, result: VerificationResult) -> None: ...
```

Slack messages must never include raw pod logs or sensitive Kubernetes YAML. Summary only.

---

## prometheus_client.py — rules

Optional in V0. The client must gracefully degrade if Prometheus is not available.

```python
class PrometheusClient:
    def query(self, promql: str) -> PrometheusResult | None:
        try:
            ...
        except Exception:
            return None   # callers handle None gracefully — not an error in V0
```

GPU metrics queries (DCGM exporter):
```python
DCGM_GPU_UTIL = 'DCGM_FI_DEV_GPU_UTIL{namespace="{ns}"}'
DCGM_FB_USED  = 'DCGM_FI_DEV_FB_USED{namespace="{ns}"}'
VLLM_TOKEN_THROUGHPUT = 'vllm:prompt_tokens_total{namespace="{ns}"}'
```
