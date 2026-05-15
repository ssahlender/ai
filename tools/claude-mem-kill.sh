#!/usr/bin/env bash
# Stops claude-mem background services and kills common orphaned subprocesses.
# By default this does not uninstall or disable the Claude plugin.
set -euo pipefail

disable_claude=0
if [ "${1:-}" = "--disable-claude" ]; then
  disable_claude=1
fi

if command -v npx >/dev/null 2>&1; then
  echo "Stopping claude-mem worker..."
  npx -y claude-mem@latest stop >/dev/null 2>&1 || true
else
  echo "npx not found — skipping claude-mem CLI stop"
fi

if [ "$disable_claude" = "1" ]; then
  if command -v claude >/dev/null 2>&1; then
    echo "Disabling Claude Code claude-mem plugin..."
    claude plugin disable claude-mem >/dev/null 2>&1 || true
  else
    echo "claude not found — skipping plugin disable"
  fi
fi

echo "Killing leftover claude-mem worker/MCP subprocesses..."
pkill -f 'claude-mem/.*/scripts/worker-service\.cjs' 2>/dev/null || true
pkill -f 'claude-mem/.*/scripts/mcp-server\.cjs' 2>/dev/null || true
pkill -f 'chroma-mcp.*\.claude-mem/chroma' 2>/dev/null || true
pkill -f 'uvx .*chroma-mcp.*\.claude-mem/chroma' 2>/dev/null || true
pkill -f 'claude-haiku-4-5.*claude' 2>/dev/null || true

echo
echo "Remaining related processes:"
if command -v rg >/dev/null 2>&1; then
  ps -eo pid,ppid,etime,cmd | rg -i 'bun|claude-mem|chroma-mcp|claude-haiku|worker-service|mcp-server\.cjs' || true
else
  # shellcheck disable=SC2009
  ps -eo pid,ppid,etime,cmd | grep -Ei 'bun|claude-mem|chroma-mcp|claude-haiku|worker-service|mcp-server\.cjs' || true
fi
