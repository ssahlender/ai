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
PLUGIN_INSTALLED=false
if command -v claude >/dev/null 2>&1 && claude plugins list 2>/dev/null | grep -q 'mattpocock-skills@'; then
  PLUGIN_INSTALLED=true
  echo "mattpocock-skills (Claude Code plugin): auto-updates on use — OK"
fi

# ── Editable installs (other agents) ─────────────────────────────────────────
if [ ! -d "$HOME/.agents/skills" ] || [ -z "$(ls -A "$HOME/.agents/skills" 2>/dev/null)" ]; then
  if ! $PLUGIN_INSTALLED; then
    echo "mattpocock-skills not installed — skipping (run mattpocock-skills-install.sh first)"
  fi
  exit 0
fi

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
UPDATE_OUTPUT=""
if ! UPDATE_OUTPUT=$(_npx_cmd --yes skills update -g -y 2>&1); then
  echo "$UPDATE_OUTPUT"
  echo "  skills update failed — skipping"
  exit 0
fi
echo "$UPDATE_OUTPUT"

# `update -y` skips deleting skills the upstream repo no longer serves
# (it would otherwise need an interactive y/n prompt). Parse those names
# out of the warning block and remove them explicitly via `skills remove`,
# which does have a real non-interactive -y, so stale skills don't pile
# up in ~/.agents/skills/ forever.
mapfile -t STALE_SKILLS < <(printf '%s\n' "$UPDATE_OUTPUT" \
  | sed -E 's/\x1b\[[0-9;]*m//g' \
  | awk '/appear to have been deleted upstream/{flag=1; next} flag && /^[[:space:]]*•/{print; next} flag{flag=0}' \
  | sed -E 's/^[[:space:]]*•[[:space:]]*//')

if [ "${#STALE_SKILLS[@]}" -gt 0 ]; then
  echo "Removing skills mattpocock/skills no longer serves: ${STALE_SKILLS[*]}"
  if ! _npx_cmd --yes skills remove -y -g "${STALE_SKILLS[@]}" 2>&1; then
    echo "  removal failed — leaving stale skills in place"
  fi
fi
