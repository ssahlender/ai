# shellcheck shell=bash
# shellcheck disable=SC2034
# Shared i9 (company proxy) detection for scripts that invoke brew.
# Source this file in scripts that need to run or print brew commands.
#
# Sets:
#   IS_I9  — non-empty if running on the i9 work PC (proxy env vars present)
#   BREW   — full brew command: sudo on i9, plain "brew" elsewhere
#
# Usage:
#   source "$(dirname "${BASH_SOURCE[0]}")/_brew-i9.sh"

export HOMEBREW_NO_ASK=1

if [[ -n "${http_proxy:-}${HTTP_PROXY:-}${https_proxy:-}${HTTPS_PROXY:-}" ]]; then
  IS_I9=1
  BREW="sudo -n -u brewuser /home/linuxbrew/.linuxbrew/bin/brew"
  # Persist HOMEBREW_NO_ASK for brewuser via Homebrew's own env config so it
  # survives the sudo env-strip without needing to run `env` through sudo
  # (which would require a separate sudoers entry).
  _BREW_ENV_FILE="/home/linuxbrew/.linuxbrew/etc/homebrew/brew.env"
  if ! grep -q "HOMEBREW_NO_ASK" "$_BREW_ENV_FILE" 2>/dev/null; then
    sudo -n -u brewuser mkdir -p "$(dirname "$_BREW_ENV_FILE")" 2>/dev/null || true
    printf 'HOMEBREW_NO_ASK=1\n' | sudo -n -u brewuser tee -a "$_BREW_ENV_FILE" >/dev/null 2>/dev/null || true
  fi
  unset _BREW_ENV_FILE
else
  IS_I9=""
  BREW="brew"
fi
