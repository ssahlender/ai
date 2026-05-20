#!/usr/bin/env bash
# Updates Graphify if it is installed, then refreshes agent integrations.
set -euo pipefail

if ! command -v graphify >/dev/null 2>&1; then
  echo "graphify not installed — skipping"
  exit 0
fi

GRAPHIFY_EXTRAS="${GRAPHIFY_EXTRAS:-openai,ollama,sql,pdf,office}"
if [ -n "$GRAPHIFY_EXTRAS" ]; then
  GRAPHIFY_SPEC="graphifyy[$GRAPHIFY_EXTRAS]"
else
  GRAPHIFY_SPEC="graphifyy"
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

if UV_BIN="$(find_uv)" && "$UV_BIN" tool list 2>/dev/null | grep -q '^graphifyy '; then
  "$UV_BIN" tool install --upgrade "$GRAPHIFY_SPEC"
elif command -v pipx >/dev/null 2>&1 && pipx list 2>/dev/null | grep -q 'package graphifyy '; then
  pipx upgrade graphifyy
  if [ -n "$GRAPHIFY_EXTRAS" ]; then
    pipx inject graphifyy "$GRAPHIFY_SPEC"
  fi
else
  echo "graphify is installed, but not managed by uv tool or pipx — skipping package update"
fi

"$(dirname "${BASH_SOURCE[0]}")/graphify-init.sh"
