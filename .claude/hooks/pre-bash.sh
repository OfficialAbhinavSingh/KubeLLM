#!/usr/bin/env bash
# Runs before every Bash tool call.
# Blocks destructive kubectl commands and secret file writes.

set -euo pipefail

COMMAND="${CLAUDE_BASH_COMMAND:-}"

if [[ -z "$COMMAND" ]]; then
  exit 0
fi

# --- Block live kubectl write operations ---
BLOCKED_KUBECTL_PATTERNS=(
  "kubectl apply"
  "kubectl edit"
  "kubectl patch"
  "kubectl delete"
  "kubectl exec"
  "kubectl replace"
  "kubectl rollout restart"
)

for pattern in "${BLOCKED_KUBECTL_PATTERNS[@]}"; do
  if echo "$COMMAND" | grep -q "$pattern"; then
    # Allow dry-run variants
    if echo "$COMMAND" | grep -q "\-\-dry-run"; then
      echo "[hook] kubectl dry-run allowed: $COMMAND"
      exit 0
    fi
    echo "[hook] BLOCKED: Live kubectl write command detected."
    echo "[hook] Command: $COMMAND"
    echo "[hook] KubeLLM Doctor never directly mutates production. Use GitOps PRs."
    echo "[hook] If this is intentional, run the command manually outside Claude."
    exit 1
  fi
done

# --- Block secret/credential file writes via shell ---
BLOCKED_FILE_PATTERNS=(
  ".env"
  "secret"
  "credentials"
  "id_rsa"
  ".pem"
  ".key"
  "token"
)

for pattern in "${BLOCKED_FILE_PATTERNS[@]}"; do
  if echo "$COMMAND" | grep -qi "$pattern" && echo "$COMMAND" | grep -q ">"; then
    echo "[hook] BLOCKED: Potential secret file write detected."
    echo "[hook] Command: $COMMAND"
    echo "[hook] Do not write secrets to files via shell. Use environment variables or secret managers."
    exit 1
  fi
done

# --- Warn on git push to main/master without review ---
if echo "$COMMAND" | grep -q "git push" && echo "$COMMAND" | grep -qE "origin (main|master)"; then
  echo "[hook] WARNING: Pushing directly to main/master."
  echo "[hook] Prefer feature branches and PRs for all changes."
  # Don't block — just warn
fi

exit 0
