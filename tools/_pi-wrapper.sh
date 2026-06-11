# shellcheck shell=bash
# Shared Pi package install helper. Source after _brew-i9.sh.
#
# _pi_install_package <npm-package>
#   Installs or refreshes one Pi npm package, with i9 CA cert handling.
#   No-ops silently if pi is not installed.

SYSTEM_CA_FILE="${SYSTEM_CA_FILE:-/etc/ssl/certs/ca-certificates.crt}"

_pi_install_package() {
  local package="$1"
  if ! command -v pi >/dev/null 2>&1; then
    return 0
  fi
  echo "Installing Pi package: $package"
  if [ -n "${IS_I9:-}" ]; then
    if [ ! -f "$SYSTEM_CA_FILE" ]; then
      echo "System CA file not found: $SYSTEM_CA_FILE" >&2
      return 1
    fi
    env \
      NODE_OPTIONS="${NODE_OPTIONS:+$NODE_OPTIONS }--use-openssl-ca" \
      NODE_EXTRA_CA_CERTS="$SYSTEM_CA_FILE" \
      NPM_CONFIG_CAFILE="$SYSTEM_CA_FILE" \
      NPM_CONFIG_STRICT_SSL=true \
      pi install --approve "npm:$package"
  else
    pi install --approve "npm:$package"
  fi
}
