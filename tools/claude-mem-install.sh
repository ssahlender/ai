#!/usr/bin/env bash
set -euo pipefail

if ! command -v npx >/dev/null 2>&1; then
  echo "npx not found. Install Node/npm first, for example with ./nvm-install.sh."
  exit 1
fi

npx -y claude-mem@latest install
npx -y claude-mem@latest install --ide codex-cli
npx -y claude-mem@latest install --ide opencode

# The claude-mem installer currently registers Codex from the local Claude
# marketplace cache. Re-registering the same marketplace from Git makes Codex
# upgrades work and keeps the /plugins source resolvable.
if command -v codex >/dev/null 2>&1; then
  codex plugin marketplace add thedotmack/claude-mem
  codex plugin marketplace upgrade claude-mem-local
fi

if command -v claude >/dev/null 2>&1; then
  claude plugin marketplace update thedotmack
fi
