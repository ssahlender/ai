#!/usr/bin/env bash
# Uninstalls tools installed by the <tool>-install.sh scripts in this folder, including what their
# *-init.sh scripts registered with the agents (plugins, MCP servers, hooks, Pi packages).
#
# Usage: ./uninstall.sh [--dry-run] [--purge] <tool>... | --all | --list
#   --dry-run  print what would be removed, change nothing (run it first)
#   --purge    also delete the tool's own data: Ollama models (~/.ollama), Node versions (~/.nvm),
#              the claude-mem database (~/.claude-mem)
#   --all      every tool (--list), integrations first, agents next, nvm last
#
# Never touched: the agents' own settings and sessions (~/.claude, ~/.codex, ~/.config/opencode,
# ~/.hermes, ~/.gemini, ~/.pi), the remote-control policy written by disable-remote-control.sh, and
# the local LLM chain in ../llm (stop it first with ../llm/stop.sh).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/_brew-i9.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/_npm-wrapper.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/_uv-wrapper.sh"
export PATH="$HOME/.local/bin:$PATH"

# Removal order for --all: things registered inside an agent go before the agent itself.
TOOLS=(
  mattpocock-skills claude-mem context-mode graphify repomix rtk ccusage
  obsidian hf llama-swap ollama docker-agent
  pi opencode hermes antigravity codex claude
  nvm
)

DRY=0
PURGE=0
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"

run() {
  if [ "$DRY" = 1 ]; then
    echo "  would run: $*"
  else
    echo "  $*"
    "$@" || echo "  failed (continuing): $*"
  fi
}

have() { command -v "$1" >/dev/null 2>&1; }

has_brew() { [ -n "$IS_I9" ] || have brew; }

brew_rm() {
  local flag=()
  if [ "$1" = --cask ]; then flag=(--cask); shift; fi
  if ! has_brew; then
    echo "  brew: not available, skipping $1"
  elif $BREW list ${flag[@]+"${flag[@]}"} "$1" >/dev/null 2>&1; then
    # shellcheck disable=SC2086
    run $BREW uninstall ${flag[@]+"${flag[@]}"} "$1"
  else
    echo "  brew $1: not installed"
  fi
}

# Global npm package, in the default prefix or the ~/.local fallback _npm_install_g uses.
npm_rm() {
  if ! have npm; then
    echo "  npm: not available, skipping $1"
    return
  fi
  local found=0
  if npm ls -g --depth=0 "$1" >/dev/null 2>&1; then
    run _npm_cmd uninstall -g "$1"; found=1
  fi
  if [ "$(npm config get prefix 2>/dev/null)" != "$HOME/.local" ] &&
     npm ls -g --prefix "$HOME/.local" --depth=0 "$1" >/dev/null 2>&1; then
    run _npm_cmd uninstall -g --prefix "$HOME/.local" "$1"; found=1
  fi
  [ "$found" = 1 ] || echo "  npm $1: not installed"
}

# A file this repo wrote; with a marker, only if the file contains it (so a foreign file stays).
rm_file() {
  local f="$1" marker="${2:-}"
  if [ ! -e "$f" ]; then
    echo "  $f: not present"
  elif [ -n "$marker" ] && ! grep -q "$marker" "$f" 2>/dev/null; then
    echo "  $f: not written by this repo (no '$marker'), left alone"
  else
    run rm -f "$f"
  fi
}

purge_dir() {
  if [ "$PURGE" != 1 ]; then
    [ -e "$1" ] && echo "  $1: kept (--purge deletes it)"
    return 0
  fi
  if [ -e "$1" ]; then run rm -rf "$1"; else echo "  $1: not present"; fi
}

config_rm() {
  local dry=()
  [ "$DRY" = 1 ] && dry=(--dry-run)
  python3 "$SCRIPT_DIR/_config-remove.py" ${dry[@]+"${dry[@]}"} "$@"
}

claude_plugin_rm() {
  if have claude && claude plugin list 2>/dev/null | grep -q "$1"; then
    run claude plugin uninstall "$1"
  else
    echo "  Claude Code plugin $1: not installed"
  fi
}

claude_marketplace_rm() {
  if have claude && claude plugin marketplace list 2>/dev/null | grep -qw "$1"; then
    run claude plugin marketplace remove "$1"
  else
    echo "  Claude Code marketplace $1: not configured"
  fi
}

codex_mcp_rm() {
  if have codex && codex mcp get "$1" >/dev/null 2>&1; then
    run codex mcp remove "$1"
  else
    echo "  Codex MCP $1: not configured"
  fi
}

pi_pkg_rm() {
  if have pi && pi list 2>/dev/null | grep -q "$1"; then
    run pi remove "npm:$1"
  else
    echo "  Pi package $1: not installed"
  fi
}

# ── one function per <tool>-install.sh ───────────────────────────────────────

un_mattpocock_skills() {
  claude_plugin_rm mattpocock-skills
  if have node; then
    run _npx_cmd --yes skills@latest remove mattpocock/skills --global --agent '*' -y
  else
    echo "  node not found, skipping the skills for the other agents"
  fi
}

un_claude_mem() {
  run "$SCRIPT_DIR/claude-mem-kill.sh"
  # Its own uninstaller removes the Claude plugin, the other IDEs' configs and the hook launcher.
  if have npx; then
    run npx -y claude-mem@latest uninstall </dev/null
  else
    echo "  npx not found, skipping claude-mem's own uninstaller"
  fi
  claude_plugin_rm claude-mem   # in case its uninstaller failed or skipped it
  claude_marketplace_rm thedotmack
  if have codex; then
    local mk
    for mk in $(codex plugin marketplace list 2>/dev/null | awk 'NR>1 && /claude-mem|thedotmack/ {print $1}'); do
      run codex plugin marketplace remove "$mk"
    done
  fi
  purge_dir "$HOME/.claude-mem"
}

un_context_mode() {
  claude_plugin_rm context-mode
  claude_marketplace_rm context-mode
  codex_mcp_rm context-mode
  config_rm "$CONFIG_HOME/opencode/opencode.json" mcp.context-mode
  pi_pkg_rm context-mode
  npm_rm context-mode
}

un_graphify() {
  if have graphify; then
    run graphify uninstall
  else
    echo "  graphify: not installed (registrations, if any, stay)"
  fi
  pi_pkg_rm @gaodes/pi-graphify
  local uv
  if uv="$(find_uv)" && "$uv" tool list 2>/dev/null | grep -q '^graphifyy '; then
    run "$uv" tool uninstall graphifyy
  elif have pipx && pipx list --short 2>/dev/null | grep -q '^graphifyy '; then
    run pipx uninstall graphifyy
  else
    echo "  graphifyy: not installed (uv tool / pipx)"
  fi
}

un_repomix() {
  config_rm "$HOME/.claude/settings.json" mcpServers.repomix
  codex_mcp_rm repomix
  config_rm "$CONFIG_HOME/opencode/opencode.json" mcp.repomix
  config_rm "$HOME/.hermes/config.yaml" mcp_servers.repomix
  rm_file "$HOME/.local/bin/repomix" 'REPOMIX_BIN='
  brew_rm repomix
  npm_rm repomix
}

un_rtk() {
  local rtk
  if rtk="$(command -v rtk)"; then
    run "$rtk" init -g --uninstall
    run "$rtk" init -g --codex --uninstall
    run "$rtk" init -g --opencode --uninstall
    run "$rtk" init -g --agent pi --uninstall
    have hermes && run "$rtk" init -g --agent hermes --uninstall
  else
    echo "  rtk: not installed (hooks, if any, stay)"
  fi
  pi_pkg_rm @sherif-fanous/pi-rtk
  brew_rm rtk
}

un_ccusage() { npm_rm ccusage; }

un_obsidian() {
  rm_file "$HOME/.local/bin/obsidian" 'tools/obsidian-install.sh'
  brew_rm --cask obsidian
}

un_hf() { brew_rm hf; }

un_llama_swap() {
  brew_rm llama-swap
  if has_brew && $BREW tap 2>/dev/null | grep -q '^mostlygeek/llama-swap$'; then
    # shellcheck disable=SC2086
    run $BREW untap mostlygeek/llama-swap
  fi
}

un_ollama() {
  if has_brew && $BREW services list 2>/dev/null | grep -q '^ollama .*started'; then
    # shellcheck disable=SC2086
    run $BREW services stop ollama
  fi
  brew_rm ollama
  purge_dir "$HOME/.ollama"
}

un_docker_agent() { brew_rm docker-agent; }

un_pi() {
  rm_file "$HOME/.local/bin/pi" 'PI_DIR='
  brew_rm pi-coding-agent
}

un_opencode() { brew_rm opencode; }

un_hermes() { brew_rm hermes-agent; }

un_antigravity() {
  rm_file "${ANTIGRAVITY_INSTALL_DIR:-$HOME/.local/bin}/agy"
}

un_codex() { brew_rm --cask codex; }

un_claude() { brew_rm --cask claude-code; }

un_nvm() {
  if [ -n "$IS_I9" ]; then
    echo "  skipped on i9 (nvm-install.sh never installs it there)"
    return
  fi
  brew_rm nvm
  local rc
  for rc in "$HOME/.zshrc" "$HOME/.bashrc" "$HOME/.bash_profile"; do
    if [ -f "$rc" ] && grep -q '^# nvm (Node Version Manager)$' "$rc"; then
      if [ "$DRY" = 1 ]; then
        echo "  would remove the nvm block from $rc"
      else
        # The 3 lines nvm-install.sh appended: comment, NVM_DIR, the nvm.sh source line.
        python3 - "$rc" <<'PY'
import sys
p = sys.argv[1]
lines = open(p).read().split('\n')
i = lines.index('# nvm (Node Version Manager)')
del lines[i:i + 3]
open(p, 'w').write('\n'.join(lines))
PY
        echo "  removed the nvm block from $rc"
      fi
    fi
  done
  purge_dir "$HOME/.nvm"
}

# ── main ─────────────────────────────────────────────────────────────────────

usage() { sed -n '5,10p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }

selected=()
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY=1 ;;
    --purge) PURGE=1 ;;
    --all) selected=("${TOOLS[@]}") ;;
    --list) printf '%s\n' "${TOOLS[@]}"; exit 0 ;;
    -h|--help) usage 0 ;;
    -*) echo "Unknown option: $1" >&2; usage 1 ;;
    *)
      known=0
      for t in "${TOOLS[@]}"; do [ "$t" = "$1" ] && known=1; done
      if [ "$known" = 0 ]; then
        echo "Unknown tool: $1 (./uninstall.sh --list)" >&2
        exit 1
      fi
      selected+=("$1")
      ;;
  esac
  shift
done
[ ${#selected[@]} -gt 0 ] || usage 1

# Run in --all order whatever order the names were given in.
for t in "${TOOLS[@]}"; do
  for s in "${selected[@]}"; do
    if [ "$t" = "$s" ]; then
      echo "==> $t"
      "un_${t//-/_}"
      break
    fi
  done
done
[ "$DRY" = 1 ] && echo && echo "Dry run: nothing changed. Run again without --dry-run to remove."
echo "Restart running agent sessions so they drop removed plugins and MCP servers."
