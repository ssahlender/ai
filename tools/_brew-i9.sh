# Shared i9 (company proxy) detection for scripts that invoke brew.
# Source this file in scripts that need to run or print brew commands.
#
# Sets:
#   IS_I9  — non-empty if running on the i9 work PC (proxy env vars present)
#   BREW   — full brew command: sudo on i9, plain "brew" elsewhere
#
# Usage:
#   source "$(dirname "${BASH_SOURCE[0]}")/_brew-i9.sh"

if [[ -n "${http_proxy:-}${HTTP_PROXY:-}${https_proxy:-}${HTTPS_PROXY:-}" ]]; then
  IS_I9=1
  BREW="sudo -n -u brewuser /home/linuxbrew/.linuxbrew/bin/brew"
else
  IS_I9=""
  BREW="brew"
fi
