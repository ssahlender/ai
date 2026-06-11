#!/usr/bin/env bash
# Installs/refreshes Pi-native packages used in this stack.
set -euo pipefail

# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/_brew-i9.sh"

SYSTEM_CA_FILE="${SYSTEM_CA_FILE:-/etc/ssl/certs/ca-certificates.crt}"

if ! command -v pi >/dev/null 2>&1; then
  echo "pi not found. Run ./pi-install.sh first."
  exit 1
fi

PI_PACKAGES=(
  context-mode
  @sherif-fanous/pi-rtk
  @gaodes/pi-graphify
)

for package in "${PI_PACKAGES[@]}"; do
  echo "Installing Pi package: $package"
  if [ -n "$IS_I9" ]; then
    if [ ! -f "$SYSTEM_CA_FILE" ]; then
      echo "System CA file not found: $SYSTEM_CA_FILE" >&2
      exit 1
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
done

echo "Pi packages installed. Restart Pi sessions to load changes."
