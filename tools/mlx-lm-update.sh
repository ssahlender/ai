#!/usr/bin/env bash
# Updates mlx-lm if it is installed.
set -euo pipefail

# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/_brew-i9.sh"
# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/_brew-wrapper.sh"
# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/_uv-wrapper.sh"

if ! command -v mlx_lm.generate >/dev/null 2>&1; then
  echo "mlx-lm not installed — skipping"
  exit 0
fi

if UV_BIN="$(find_uv)" && "$UV_BIN" tool list 2>/dev/null | grep -q '^mlx-lm '; then
  "$UV_BIN" tool install --upgrade mlx-lm
elif command -v pipx >/dev/null 2>&1 && pipx list 2>/dev/null | grep -q 'package mlx-lm '; then
  pipx upgrade mlx-lm
else
  echo "mlx-lm is installed, but not managed by uv tool or pipx — skipping package update"
fi
