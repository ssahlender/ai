#!/usr/bin/env bash
# Installs Graphify via uv tool where available, with pipx fallback.
set -euo pipefail

# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/_brew-i9.sh"
# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/_brew-wrapper.sh"

GRAPHIFY_EXTRAS="${GRAPHIFY_EXTRAS:-openai,ollama,sql,pdf,office}"
if [ -n "$GRAPHIFY_EXTRAS" ]; then
  GRAPHIFY_SPEC="graphifyy[$GRAPHIFY_EXTRAS]"
else
  GRAPHIFY_SPEC="graphifyy"
fi
UV_CERT_ARGS=()
if [ -n "$IS_I9" ]; then
  UV_CERT_ARGS+=(--system-certs)
fi

find_uv() {
  if command -v uv >/dev/null 2>&1; then
    command -v uv
    return 0
  fi

  for candidate in \
    "$HOME/.local/bin/uv" \
    /home/linuxbrew/.linuxbrew/bin/uv \
    /opt/homebrew/bin/uv \
    /usr/local/bin/uv; do
    if [ -x "$candidate" ]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  return 1
}

ensure_uv_or_pipx() {
  if find_uv >/dev/null 2>&1 || command -v pipx >/dev/null 2>&1; then
    return 0
  fi

  if command -v brew >/dev/null 2>&1 || [ -n "$IS_I9" ]; then
    echo "uv/pipx not found; installing uv with Homebrew..."
    _brew_install uv
    return 0
  fi

  echo "uv or pipx is required. Install uv first: https://docs.astral.sh/uv/getting-started/installation/" >&2
  exit 1
}

ensure_uv_or_pipx

if UV_BIN="$(find_uv)"; then
  "$UV_BIN" tool install "${UV_CERT_ARGS[@]}" --upgrade "$GRAPHIFY_SPEC"
elif command -v pipx >/dev/null 2>&1; then
  pipx install "$GRAPHIFY_SPEC"
fi

"$(dirname "${BASH_SOURCE[0]}")/graphify-init.sh"
