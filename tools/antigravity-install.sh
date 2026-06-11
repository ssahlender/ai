#!/usr/bin/env bash
# Installs Antigravity CLI (Google) via the official bootstrapper.
# The binary is a flat native build placed at ~/.local/bin/agy.
set -euo pipefail

# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/_brew-i9.sh"

INSTALL_DIR="${ANTIGRAVITY_INSTALL_DIR:-}"
INSTALL_ARGS=()
if [ -n "$INSTALL_DIR" ]; then
  INSTALL_ARGS+=(--dir "$INSTALL_DIR")
fi

echo "Installing Antigravity CLI..."
curl -fsSL https://antigravity.google/cli/install.sh | bash -s -- "${INSTALL_ARGS[@]}"
