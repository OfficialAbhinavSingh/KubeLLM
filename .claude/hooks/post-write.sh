#!/usr/bin/env bash
# Runs after every file write. Lints and formats Python files.
# Triggers test suite when core agent or safety logic is changed.

set -euo pipefail

FILE="${CLAUDE_FILE_PATH:-}"

if [[ -z "$FILE" ]]; then
  exit 0
fi

# --- Python formatting and linting ---
if [[ "$FILE" == *.py ]]; then
  echo "[hook] Running black on $FILE"
  black --quiet "$FILE" 2>/dev/null || echo "[hook] black not available, skipping"

  echo "[hook] Running ruff on $FILE"
  ruff check --fix --quiet "$FILE" 2>/dev/null || echo "[hook] ruff not available, skipping"
fi

# --- YAML validation for Kubernetes manifests ---
if [[ "$FILE" == charts/** || "$FILE" == manifests/** || "$FILE" == infra/** ]]; then
  if [[ "$FILE" == *.yaml || "$FILE" == *.yml ]]; then
    echo "[hook] Running kubeconform on $FILE"
    kubeconform -strict -summary "$FILE" 2>/dev/null \
      || echo "[hook] kubeconform not available or validation warning — review $FILE"
  fi
fi

# --- Run agent unit tests when core logic changes ---
if [[ "$FILE" == src/agents/** || "$FILE" == src/core/** ]]; then
  echo "[hook] Core agent file changed — running unit tests"
  python -m pytest tests/unit/ -q --tb=short 2>/dev/null \
    || echo "[hook] Unit tests failed or pytest not available — review before committing"
fi

# --- Run safety tests when safety policy changes ---
if [[ "$FILE" == src/safety/** ]]; then
  echo "[hook] Safety policy file changed — running safety tests"
  python -m pytest tests/unit/test_safety.py -v 2>/dev/null \
    || echo "[hook] Safety tests FAILED — do not commit without fixing"
fi
