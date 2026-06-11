#!/usr/bin/env bash
# Installs Pi Coding Agent. Uses Homebrew on Ubuntu 24.04 / macOS,
# falls back to npm on Debian 12 (brew bottles need GLIBC 2.38+).
set -euo pipefail

# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/_brew-i9.sh"
# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/_brew-wrapper.sh"

NEEDS_NPM=false
BREW_NODE_LINUX="/home/linuxbrew/.linuxbrew/opt/node/bin/node"
if [ -x "$BREW_NODE_LINUX" ] && ! "$BREW_NODE_LINUX" -e '0' &>/dev/null; then
  NEEDS_NPM=true
elif ! command -v node &>/dev/null; then
  NEEDS_NPM=true
fi

if $NEEDS_NPM; then
  echo "brew node unsupported on this glibc — creating pi wrapper"
  mkdir -p "$HOME/.local/bin"

  PI_DIR=$(ls -d /home/linuxbrew/.linuxbrew/Cellar/pi-coding-agent/*/libexec/lib/node_modules/@earendil-works/pi-coding-agent/dist/cli.js 2>/dev/null | sort -V | tail -1)
  if [ -f "$PI_DIR" ]; then
    NODE_BIN=$(command -v node)
    cat > "$HOME/.local/bin/pi" << 'SCRIPTEOF'
#!/bin/bash
PI_DIR=$(ls -d /home/linuxbrew/.linuxbrew/Cellar/pi-coding-agent/*/libexec/lib/node_modules/@earendil-works/pi-coding-agent/dist/cli.js 2>/dev/null | sort -V | tail -1)
NODE_BIN=$(command -v node)
exec $NODE_BIN "$PI_DIR" "$@"
SCRIPTEOF
    chmod +x "$HOME/.local/bin/pi"
    echo "pi wrapper installed to ~/.local/bin/pi"
    echo "Add to PATH: export PATH=\"\$HOME/.local/bin:\$PATH\""
  else
    echo "pi-coding-agent not found in brew cellar. Run: brew install pi-coding-agent"
    exit 1
  fi
else
  _brew_install pi-coding-agent
fi

"$(dirname "${BASH_SOURCE[0]}")/pi-init.sh"
