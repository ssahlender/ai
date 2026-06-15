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
  # Persist HOMEBREW_NO_ASK for brewuser via Homebrew's own env config.
  # sudo strips env vars and only /path/to/brew is in the NOPASSWD rule
  # (env, tee, mkdir are not), so we use `brew sh` which runs a shell
  # with the brew prefix in scope, allowing it to write to the prefix.
  _BREW_ENV_FILE="/home/linuxbrew/.linuxbrew/etc/homebrew/brew.env"
  if ! grep -q "HOMEBREW_NO_ASK" "$_BREW_ENV_FILE" 2>/dev/null; then
    printf 'mkdir -p "${HOMEBREW_PREFIX}/etc/homebrew" && printf "HOMEBREW_NO_ASK=1\\n" >> "${HOMEBREW_PREFIX}/etc/homebrew/brew.env"\n' \
      | sudo -n -u brewuser /home/linuxbrew/.linuxbrew/bin/brew sh 2>/dev/null || true
  fi
  unset _BREW_ENV_FILE
else
  IS_I9=""
  BREW="brew"
fi
