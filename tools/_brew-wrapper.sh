# shellcheck shell=bash
# Shared brew helpers. Source after _brew-i9.sh.
#
# _brew_install <pkg> [<flags>...]
# _brew_upgrade <pkg> [<flags>...]

_brew_install() {
  $BREW install "$@"
}

_brew_upgrade() {
  local name="$1"; shift
  if $BREW list "$name" &>/dev/null; then
    $BREW upgrade "$name" "$@" || true
  else
    echo "$name not installed — skipping"
  fi
}
