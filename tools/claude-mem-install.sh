#!/usr/bin/env bash
set -euo pipefail

if ! command -v npx >/dev/null 2>&1; then
  echo "npx not found. Install Node/npm first, for example with ./nvm-install.sh."
  exit 1
fi

if [ "${CLAUDE_MEM_ENABLE_CLAUDE:-0}" = "1" ]; then
  if command -v claude >/dev/null 2>&1 && claude plugin list 2>/dev/null | grep -q 'claude-mem@thedotmack'; then
    claude plugin enable claude-mem || true
  else
    npx -y claude-mem@latest install \
      --ide claude-code \
      --provider claude \
      --model claude-haiku-4-5-20251001 \
      --no-auto-start
  fi
else
  echo "Claude Code claude-mem plugin skipped. Set CLAUDE_MEM_ENABLE_CLAUDE=1 to enable it."
fi

if [ "${CLAUDE_MEM_FORCE_INSTALL:-0}" = "1" ]; then
  npx -y claude-mem@latest install --ide codex-cli --no-auto-start
  npx -y claude-mem@latest install --ide opencode --no-auto-start
else
  echo "Codex/OpenCode claude-mem reinstall skipped. Set CLAUDE_MEM_FORCE_INSTALL=1 to force upstream installer."
fi

# The claude-mem installer currently registers Codex from the local Claude
# marketplace cache. Re-registering the same marketplace from Git makes Codex
# upgrades work and keeps the /plugins source resolvable.
if command -v codex >/dev/null 2>&1; then
  codex plugin marketplace add thedotmack/claude-mem
  codex plugin marketplace upgrade claude-mem-local
fi

if [ "${CLAUDE_MEM_ENABLE_CLAUDE:-0}" = "1" ] && command -v claude >/dev/null 2>&1; then
  claude plugin marketplace update thedotmack
fi
