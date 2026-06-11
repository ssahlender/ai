#!/usr/bin/env bash
# Updates Graphify if it is installed, then refreshes agent integrations.
set -euo pipefail

# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/_brew-i9.sh"
# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/_brew-wrapper.sh"
# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/_uv-wrapper.sh"

if ! command -v graphify >/dev/null 2>&1; then
  echo "graphify not installed — skipping"
  exit 0
fi

# pdf extra blocked by corporate proxy CVE filter on i9 — omit by default
if [ -n "${IS_I9:-}" ]; then
  GRAPHIFY_EXTRAS="${GRAPHIFY_EXTRAS:-openai,ollama,sql,office}"
else
  GRAPHIFY_EXTRAS="${GRAPHIFY_EXTRAS:-openai,ollama,sql,pdf,office}"
fi
if [ -n "$GRAPHIFY_EXTRAS" ]; then
  GRAPHIFY_SPEC="graphifyy[$GRAPHIFY_EXTRAS]"
else
  GRAPHIFY_SPEC="graphifyy"
fi
UV_CERT_ARGS=()
if [ -n "${IS_I9:-}" ]; then
  UV_CERT_ARGS+=(--system-certs)
fi

if UV_BIN="$(find_uv)" && "$UV_BIN" tool list 2>/dev/null | grep -q '^graphifyy '; then
  "$UV_BIN" tool install "${UV_CERT_ARGS[@]}" --upgrade "$GRAPHIFY_SPEC"
elif command -v pipx >/dev/null 2>&1 && pipx list 2>/dev/null | grep -q 'package graphifyy '; then
  pipx upgrade graphifyy
  if [ -n "$GRAPHIFY_EXTRAS" ]; then
    pipx inject graphifyy "$GRAPHIFY_SPEC"
  fi
else
  echo "graphify is installed, but not managed by uv tool or pipx — skipping package update"
fi

"$(dirname "${BASH_SOURCE[0]}")/graphify-init.sh"
