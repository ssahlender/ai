#!/usr/bin/env bash
# Installs mlx-lm via uv tool where available, with pipx fallback.
# Only useful on Apple Silicon (Metal backend) — harmless to install elsewhere.
set -euo pipefail

# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/_brew-i9.sh"
# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/_brew-wrapper.sh"
# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/_uv-wrapper.sh"

ensure_uv_or_pipx

if UV_BIN="$(find_uv)"; then
  "$UV_BIN" tool install mlx-lm
elif command -v pipx >/dev/null 2>&1; then
  pipx install mlx-lm
fi
