# src/api/ — FastAPI Backend

This directory is the HTTP layer between the frontend, CLI, and the agent orchestration system.

## What lives here

```
src/api/
├── main.py              # FastAPI app, routers, middleware
├── routers/
│   ├── incidents.py     # GET/POST /incidents, /incidents/{id}
│   ├── actions.py       # POST /actions/{id}/approve, /reject
│   ├── audit.py         # GET /audit/{incident_id}
│   └── health.py        # GET /health, /ready
├── models/              # Pydantic request/response schemas
├── dependencies.py      # Auth, DB session, rate limiting
└── config.py            # Settings from env vars (no hardcoded values)
```

## Rules for this directory

### 1. Approval endpoints require authentication

`POST /actions/{id}/approve` and `POST /actions/{id}/reject` must:
- Require a valid authenticated user (JWT or API key)
- Record `approved_by` as the authenticated user's identity
- Call `safety.audit.log_event(...)` — the Safety module owns the audit trail

Do not record approvals without calling the Safety audit log.

### 2. No business logic in routers

Routers call service functions in `src/core/` or agent functions. They do not contain decision logic. A router function should be ≤ 20 lines.

### 3. Config from environment, never hardcoded

`config.py` uses `pydantic-settings`. All sensitive values (DB URL, GitHub token, Slack webhook) come from environment variables.

```python
# Good
class Settings(BaseSettings):
    github_token: str = Field(..., env="GITHUB_TOKEN")

# Never do this
GITHUB_TOKEN = "ghp_abc123..."
```

### 4. Rate limit the scan endpoint

`POST /scan` triggers a cluster scan and can be expensive. Apply rate limiting:
- Max 10 scans per namespace per hour per API key
- Return 429 with `Retry-After` header on limit hit

This prevents runaway agent invocations.

### 5. Never expose raw evidence in unauthenticated endpoints

`GET /incidents/{id}` and `GET /evidence/{id}` must require authentication. Raw pod logs and Kubernetes events may contain sensitive application data.
