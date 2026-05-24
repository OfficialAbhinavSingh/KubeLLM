# src/core/ — Shared Types, Models, and Confidence Engine

**Role:** Shared Pydantic models, enums, confidence scoring, and utilities used by both Proactive and Reactive modes. No business logic. No external dependencies beyond Pydantic.

## What lives here

```
src/core/
├── models.py            # All shared Pydantic v2 models
├── enums.py             # All shared enums (RuntimeType, GPUType, Confidence, etc.)
├── confidence.py        # Evidence-based confidence scoring (reactive mode)
├── config.py            # Application config from environment (pydantic-settings)
├── exceptions.py        # All custom exception classes
└── tests/
    ├── test_confidence.py
    └── test_models.py
```

## Rules

### 1. No external I/O in this module

`src/core/` has zero I/O. No database calls, no Kubernetes calls, no LLM calls, no HTTP requests. It is pure Python + Pydantic.

If you need to add something here that requires an import from `src/integrations/` or `src/agents/`, it belongs somewhere else.

### 2. Confidence scoring is deterministic (no LLM)

`confidence.py` computes confidence from evidence item counts and types. This is the authoritative implementation — all agents call this, none implement their own.

```python
# confidence.py
def score_confidence(
    evidence: list[EvidenceItem],
    failure_type: FailureType,
) -> Confidence:
    """
    Scores confidence from evidence count and independence.
    Never calls an LLM. Fully deterministic.

    Evidence independence rules:
    - k8s_event + pod_log = 2 independent sources
    - pod_log[line_1] + pod_log[line_2] = 1 source (same source type)
    - k8s_event + pod_log + node_state = 3 independent sources
    """
    independent_sources = count_independent_sources(evidence, failure_type)

    if independent_sources >= 3:
        return Confidence.HIGH
    elif independent_sources >= 2:
        return Confidence.MEDIUM
    else:
        return Confidence.LOW
```

### 3. All shared enums live in enums.py

Do not define enums in individual agent modules. If two modules need the same concept (e.g., `RuntimeType`), it lives in `core/enums.py`.

```python
# enums.py
class RuntimeType(str, Enum):
    VLLM = "vllm"
    KSERVE = "kserve"
    RAY_SERVE = "ray_serve"
    TRITON = "triton"
    CUSTOM = "custom"

class Confidence(str, Enum):
    HIGH = "high"
    MEDIUM = "medium"
    LOW = "low"

class GPUType(str, Enum):
    A10G = "A10G"
    A100_40 = "A100_40GB"
    A100_80 = "A100_80GB"
    H100_80 = "H100_80GB"
    H100_NVL = "H100_NVL"
    RTX_4090 = "RTX_4090"

class RiskLevel(str, Enum):
    LOW = "low"
    MEDIUM = "medium"
    HIGH = "high"

class PolicyDecision(str, Enum):
    ALLOW = "allow"
    PR_ONLY = "pr_only"
    REQUIRE_APPROVAL = "require_approval"
    BLOCK = "block"
    SENIOR_APPROVAL = "senior_approval"
```

### 4. Config uses pydantic-settings — no hardcoded values

```python
# config.py
class Settings(BaseSettings):
    # Database
    database_url: PostgresDsn = Field(..., env="DATABASE_URL")

    # LLM
    anthropic_api_key: str = Field(..., env="ANTHROPIC_API_KEY")
    llm_model: str = Field("claude-sonnet-4-5", env="LLM_MODEL")

    # GitHub
    github_app_id: int | None = Field(None, env="GITHUB_APP_ID")
    github_private_key: str | None = Field(None, env="GITHUB_PRIVATE_KEY")
    github_pat: str | None = Field(None, env="GITHUB_PAT")

    # Kubernetes
    kubeconfig_path: str | None = Field(None, env="KUBECONFIG")
    in_cluster: bool = Field(False, env="KUBELLM_IN_CLUSTER")

    # Safety
    approval_expiry_hours: int = Field(24, env="APPROVAL_EXPIRY_HOURS")
    live_patching_enabled: bool = Field(False, env="LIVE_PATCHING_ENABLED")  # always False

    # Feature flags
    proactive_mode_enabled: bool = Field(True, env="PROACTIVE_MODE_ENABLED")

    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8")
```

`live_patching_enabled` exists in the config schema to make it explicit that it is always `False`. The safety engine ignores its value — the policy table is the source of truth.

### 5. Exceptions are typed

```python
# exceptions.py
class KubeLLMError(Exception): ...
class IntentExtractionError(KubeLLMError): ...
class ClusterValidationError(KubeLLMError): ...
class ValidationError(KubeLLMError): ...
class PolicyBlockError(KubeLLMError): ...
class ApprovalRequiredError(KubeLLMError): ...
class SourceNotFoundError(KubeLLMError): ...
class VerificationError(KubeLLMError): ...
```

All modules raise typed exceptions. No bare `raise Exception("something failed")`.
