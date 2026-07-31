#!/usr/bin/env bash
# Installs mattpocock/skills.
# - Claude Code: global plugin via marketplace (non-interactive, auto-updates)
# - All other agents (Codex, OpenCode, Pi, Hermes, Antigravity, ...):
#   interactive npx picker — a TUI opens so you can select skills and agents.
#
# After install: run /setup-matt-pocock-skills once per repo to configure
# your issue tracker (GitHub / Linear / local files) and documentation paths.
set -euo pipefail

# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/_brew-i9.sh"
# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/_npm-wrapper.sh"

# ── Claude Code plugin ────────────────────────────────────────────────────────
if command -v claude >/dev/null 2>&1; then
  echo "Installing mattpocock-skills plugin for Claude Code..."
  claude plugins install mattpocock-skills
  echo "  Done. Plugin auto-updates on use — no manual update needed."
else
  echo "claude not found — skipping Claude Code plugin install"
fi

echo ""

# ── Other agents (interactive TUI) ───────────────────────────────────────────
if ! command -v node >/dev/null 2>&1; then
  echo "node not found — skipping npx installer for other agents"
  exit 0
fi

NODE_MAJOR=$(node -e 'process.stdout.write(process.versions.node.split(".")[0])' 2>/dev/null || echo 0)
if [ "$NODE_MAJOR" -lt 22 ]; then
  echo "node ${NODE_MAJOR} < 22 — skills package requires Node ≥ 22.20.0; skipping"
  echo "Upgrade node (e.g. nvm install 22) then re-run this script."
  exit 0
fi

echo "Installing all skills for all detected agents (global)..."
echo "  --all  = every skill"
echo "  -g     = user-level (not project-level)"
echo "  -y     = no prompts"
echo ""
_npx_cmd skills@latest add mattpocock/skills --all -g

echo ""
echo "Next: open a project repo and run /setup-matt-pocock-skills"
echo "to configure issue tracker, triage labels, and documentation paths."
