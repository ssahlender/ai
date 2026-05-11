#!/usr/bin/env bash
# Updates nvm via Homebrew and installs the latest LTS Node. Skipped on i9 (work provides Node).
set -euo pipefail

# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/_brew-i9.sh"

# Skip on i9 — work provides its own Node stack
if [ -n "$IS_I9" ]; then
  echo "Skipping on i9 — work provides its own Node stack."
  exit 0
fi

if ! $BREW list --formula nvm &>/dev/null; then
  echo "nvm not installed — skipping"
  exit 0
fi

echo "Updating nvm..."
$BREW upgrade nvm || true

# Source nvm
export NVM_DIR="$HOME/.nvm"
# shellcheck source=/dev/null
[ -s "$(brew --prefix)/opt/nvm/nvm.sh" ] && . "$(brew --prefix)/opt/nvm/nvm.sh"

if ! command -v nvm &>/dev/null; then
  echo "nvm not available — run nvm-install.sh first." >&2
  exit 1
fi

nvm install --lts --reinstall-packages-from=current
nvm alias default lts/*
nvm use default

npm install -g npm@latest
npm update -g

node -v && npm -v && npx -v
