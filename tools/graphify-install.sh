#!/usr/bin/env bash
# Installs Graphify via uv tool where available, with pipx fallback.
set -euo pipefail

# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/_brew-i9.sh"
# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/_brew-wrapper.sh"
# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/_uv-wrapper.sh"

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

ensure_uv_or_pipx

if UV_BIN="$(find_uv)"; then
  "$UV_BIN" tool install "${UV_CERT_ARGS[@]}" --upgrade "$GRAPHIFY_SPEC"
elif command -v pipx >/dev/null 2>&1; then
  pipx install "$GRAPHIFY_SPEC"
fi

"$(dirname "${BASH_SOURCE[0]}")/graphify-init.sh"
