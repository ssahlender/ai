#!/usr/bin/env bash
# Updates mattpocock/skills.
# - Claude Code plugin: auto-updates on use, nothing to do here.
# - Editable installs (Codex, OpenCode, Pi, ...): npx skills update pulls
#   latest skill files into any repo where you previously ran the installer.
#   Run this from inside a repo that has editable skills installed.
set -euo pipefail

# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/_brew-i9.sh"
# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/_npm-wrapper.sh"

# ── Claude Code plugin ────────────────────────────────────────────────────────
if command -v claude >/dev/null 2>&1; then
  echo "mattpocock-skills (Claude Code plugin): auto-updates on use — OK"
fi

# ── Editable installs (other agents) ─────────────────────────────────────────
if ! command -v node >/dev/null 2>&1; then
  echo "node not found — skipping skills editable update"
  exit 0
fi

NODE_MAJOR=$(node -e 'process.stdout.write(process.versions.node.split(".")[0])' 2>/dev/null || echo 0)
if [ "$NODE_MAJOR" -lt 22 ]; then
  echo "node ${NODE_MAJOR} < 22 — skipping skills update (requires ≥ 22.20.0)"
  exit 0
fi

echo "Updating global skills (~/.agents/skills/)..."
_npx_cmd skills update -g -y 2>&1 || echo "  skills update failed — skipping"
