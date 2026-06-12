#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/_brew-i9.sh"
# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/_brew-wrapper.sh"

if $BREW list repomix &>/dev/null; then
  _brew_upgrade repomix
  # Refresh the system-node wrapper if present (e.g. on Debian 12 / GLIBC < 2.38)
  if [ -f "$HOME/.local/bin/repomix" ]; then
    REPOMIX_BIN=$(ls -d /home/linuxbrew/.linuxbrew/Cellar/repomix/*/libexec/bin/repomix 2>/dev/null | sort -V | tail -1)
    if [ -f "$REPOMIX_BIN" ]; then
      cat > "$HOME/.local/bin/repomix" << 'SCRIPTEOF'
#!/bin/bash
REPOMIX_BIN=$(ls -d /home/linuxbrew/.linuxbrew/Cellar/repomix/*/libexec/bin/repomix 2>/dev/null | sort -V | tail -1)
NODE_BIN=$(command -v node)
exec $NODE_BIN "$REPOMIX_BIN" "$@"
SCRIPTEOF
      chmod +x "$HOME/.local/bin/repomix"
      echo "repomix wrapper refreshed"
    fi
  fi
elif command -v repomix >/dev/null 2>&1 && command -v npm >/dev/null 2>&1; then
  # shellcheck source=/dev/null
  source "$(dirname "${BASH_SOURCE[0]}")/_npm-wrapper.sh"
  _npm_update_g repomix
else
  echo "repomix not installed — skipping"
  exit 0
fi

"$(dirname "${BASH_SOURCE[0]}")/repomix-mcp-init.sh"
