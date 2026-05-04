#!/usr/bin/env bash
# Updates nvm via Homebrew and installs the latest LTS Node. Skipped on i9 (work provides Node).
set -euo pipefail

# Skip on i9 (native Linux, company proxy) — work provides its own Node stack
if [[ "$(uname -s)" == "Linux" ]] && ! grep -qi "microsoft" /proc/version 2>/dev/null; then
  echo "Skipping on i9 — work provides its own Node stack."
  exit 0
fi

echo "Updating nvm..."
brew upgrade nvm || true

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

npm install -g @rely-ai/caliber
echo "caliber updated: $(caliber --version)"
