#!/usr/bin/env bash
# Installs Pi Coding Agent. Uses Homebrew on Ubuntu 24.04 / macOS,
# falls back to npm on Debian 12 (brew bottles need GLIBC 2.38+).
set -euo pipefail

# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/_brew-i9.sh"

# Detect if brew's node can actually run on this glibc
NEEDS_NPM=false
if command -v node &>/dev/null; then
  node -e '0' 2>/dev/null || NEEDS_NPM=true
else
  NEEDS_NPM=true
fi

if $NEEDS_NPM; then
  echo "brew node unsupported on this glibc — creating pi wrapper"
  mkdir -p "$HOME/.local/bin"

  # Find the pi JS entrypoint from brew's cellar
  PI_DIR=$(ls -d /home/linuxbrew/.linuxbrew/Cellar/pi-coding-agent/*/libexec/lib/node_modules/@earendil-works/pi-coding-agent/dist/cli.js 2>/dev/null | sort -V | tail -1)
  if [ -f "$PI_DIR" ]; then
    NODE_BIN=$(command -v node)
    cat > "$HOME/.local/bin/pi" << SCRIPTEOF
#!/bin/bash
exec $NODE_BIN "$PI_DIR" "\$@"
SCRIPTEOF
    chmod +x "$HOME/.local/bin/pi"
    echo "pi wrapper installed to ~/.local/bin/pi"
    echo "Add to PATH: export PATH=\"\$HOME/.local/bin:\$PATH\""
  else
    echo "pi-coding-agent not found in brew cellar. Run: brew install pi-coding-agent"
    exit 1
  fi
else
  $BREW install pi-coding-agent
fi

"$(dirname "${BASH_SOURCE[0]}")/pi-init.sh"
