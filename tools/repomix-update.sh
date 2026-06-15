#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/_brew-i9.sh"
# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/_brew-wrapper.sh"

WRAPPER="$HOME/.local/bin/repomix"

_refresh_wrapper() {
  local bin
  bin=$(ls -d /home/linuxbrew/.linuxbrew/Cellar/repomix/*/libexec/bin/repomix 2>/dev/null | sort -V | tail -1)
  if [ -f "$bin" ]; then
    cat > "$WRAPPER" << 'SCRIPTEOF'
#!/bin/bash
REPOMIX_BIN=$(ls -d /home/linuxbrew/.linuxbrew/Cellar/repomix/*/libexec/bin/repomix 2>/dev/null | sort -V | tail -1)
NODE_BIN=$(command -v node)
exec $NODE_BIN "$REPOMIX_BIN" "$@"
SCRIPTEOF
    chmod +x "$WRAPPER"
    echo "repomix wrapper refreshed"
  fi
}

# Detect brew wrapper: if ~/.local/bin/repomix references the brew cellar it's
# a brew-managed install regardless of whether $BREW list succeeds.
IS_BREW_WRAPPER=false
grep -q "Cellar\|linuxbrew" "$WRAPPER" 2>/dev/null && IS_BREW_WRAPPER=true

if $BREW list repomix &>/dev/null || $IS_BREW_WRAPPER; then
  _brew_upgrade repomix
  [ -f "$WRAPPER" ] && _refresh_wrapper
elif command -v repomix >/dev/null 2>&1 && command -v npm >/dev/null 2>&1; then
  # shellcheck source=/dev/null
  source "$(dirname "${BASH_SOURCE[0]}")/_npm-wrapper.sh"
  _npm_update_g repomix
else
  echo "repomix not installed — skipping"
  exit 0
fi

"$(dirname "${BASH_SOURCE[0]}")/repomix-init.sh"
