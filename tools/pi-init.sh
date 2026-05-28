#!/usr/bin/env bash
# Installs/refreshes Pi-native packages used in this stack.
set -euo pipefail

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
  pi install "npm:$package"
done

echo "Pi packages installed. Restart Pi sessions to load changes."
