#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/_brew-i9.sh"
# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/_brew-wrapper.sh"

NEEDS_WRAPPER=false
BREW_NODE_LINUX="/home/linuxbrew/.linuxbrew/opt/node/bin/node"
if [ -x "$BREW_NODE_LINUX" ] && ! "$BREW_NODE_LINUX" -e '0' &>/dev/null; then
  NEEDS_WRAPPER=true
fi

if [ -n "$IS_I9" ] || command -v brew >/dev/null 2>&1; then
  _brew_install repomix

  if $NEEDS_WRAPPER; then
    echo "brew node unsupported on this glibc — creating repomix wrapper"
    mkdir -p "$HOME/.local/bin"
    REPOMIX_BIN=$(ls -d /home/linuxbrew/.linuxbrew/Cellar/repomix/*/libexec/bin/repomix 2>/dev/null | sort -V | tail -1)
    if [ -f "$REPOMIX_BIN" ]; then
      cat > "$HOME/.local/bin/repomix" << 'SCRIPTEOF'
#!/bin/bash
REPOMIX_BIN=$(ls -d /home/linuxbrew/.linuxbrew/Cellar/repomix/*/libexec/bin/repomix 2>/dev/null | sort -V | tail -1)
NODE_BIN=$(command -v node)
exec $NODE_BIN "$REPOMIX_BIN" "$@"
SCRIPTEOF
      chmod +x "$HOME/.local/bin/repomix"
      echo "repomix wrapper installed to ~/.local/bin/repomix"
    else
      echo "repomix not found in brew cellar after install" >&2
      exit 1
    fi
  fi
elif command -v npm >/dev/null 2>&1; then
  echo "brew not found — falling back to npm"
  # shellcheck source=/dev/null
  source "$(dirname "${BASH_SOURCE[0]}")/_npm-wrapper.sh"
  _npm_install_g repomix
else
  echo "Neither brew nor npm found. Install one first." >&2
  exit 1
fi

"$(dirname "${BASH_SOURCE[0]}")/repomix-init.sh"
