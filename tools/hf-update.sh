#!/usr/bin/env bash
set -euo pipefail

pypi_url="https://pypi.org/pypi/huggingface_hub/json"
install_url="https://hf.co/cli/install.sh"

installed_version() {
  if ! command -v hf >/dev/null 2>&1; then
    return 1
  fi

  hf version | sed -nE 's/.*([0-9]+([.][0-9A-Za-z]+)+).*/\1/p' | head -n1
}

latest_version() {
  curl -fsSL "$pypi_url" |
    grep -m1 -o '"version"[[:space:]]*:[[:space:]]*"[^"]*"' |
    sed -nE 's/.*"([^"]+)".*/\1/p'
}

install_hf() {
  export UV_NATIVE_TLS=1
  curl -LsSf "$install_url" | bash
}

current="$(installed_version || true)"

if [ -z "$current" ]; then
  echo "Hugging Face CLI is not installed. Installing latest release."
  install_hf
  exit 0
fi

latest="$(latest_version)"

if [ -z "$latest" ]; then
  echo "Could not determine latest Hugging Face CLI release from PyPI."
  exit 1
fi

if [ "$(printf '%s\n%s\n' "$current" "$latest" | sort -V | tail -n1)" = "$current" ]; then
  echo "Hugging Face CLI is already up to date: $current"
  exit 0
fi

echo "Updating Hugging Face CLI from $current to $latest."
install_hf
