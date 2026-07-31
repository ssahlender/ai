# shellcheck shell=bash
# Shared npm helpers. Source after _brew-i9.sh.
#
# _npm_install_g <package>  — global install with i9 cert + prefix handling
# _npm_update_g <package>   — global update with i9 cert + prefix handling
#
# If the system npm prefix is not user-writable, installs to ~/.local instead.
# Override the CA bundle with SYSTEM_CA_FILE=/path/to/ca.crt.

SYSTEM_CA_FILE="${SYSTEM_CA_FILE:-/etc/ssl/certs/ca-certificates.crt}"

_npm_cmd() {
  if [ -n "${IS_I9:-}" ] && [ -f "$SYSTEM_CA_FILE" ]; then
    env \
      NODE_OPTIONS="${NODE_OPTIONS:+$NODE_OPTIONS }--use-openssl-ca" \
      NODE_EXTRA_CA_CERTS="$SYSTEM_CA_FILE" \
      NPM_CONFIG_CAFILE="$SYSTEM_CA_FILE" \
      NPM_CONFIG_STRICT_SSL=true \
      npm "$@"
  else
    npm "$@"
  fi
}

_npm_install_g() {
  local prefix
  prefix="$(npm config get prefix 2>/dev/null)"
  if [ -w "$prefix" ]; then
    _npm_cmd install -g "$@"
  else
    echo "npm prefix $prefix not writable — installing to ~/.local"
    _npm_cmd install -g --prefix "$HOME/.local" "$@"
    echo "Ensure ~/.local/bin is in your PATH."
  fi
}

_npm_update_g() {
  local prefix
  prefix="$(npm config get prefix 2>/dev/null)"
  if [ -w "$prefix" ]; then
    _npm_cmd update -g "$@"
  else
    _npm_cmd install -g --prefix "$HOME/.local" "$@"
  fi
}

_npx_cmd() {
  # Resolve npx from the same installation as the node binary in PATH.
  # On i9, 'npx' in PATH is Node 16's npx but 'node' is Node 24; using
  # node's sibling npx ensures version consistency.
  local node_dir npx_bin
  node_dir="$(dirname "$(node -e 'process.stdout.write(process.execPath)' 2>/dev/null)")" || node_dir=""
  if [ -n "$node_dir" ] && [ -x "$node_dir/npx" ]; then
    npx_bin="$node_dir/npx"
  else
    npx_bin="npx"
  fi

  if [ -n "${IS_I9:-}" ] && [ -f "$SYSTEM_CA_FILE" ]; then
    env \
      NODE_OPTIONS="${NODE_OPTIONS:+$NODE_OPTIONS }--use-openssl-ca" \
      NODE_EXTRA_CA_CERTS="$SYSTEM_CA_FILE" \
      NPM_CONFIG_CAFILE="$SYSTEM_CA_FILE" \
      NPM_CONFIG_STRICT_SSL=true \
      "$npx_bin" "$@"
  else
    "$npx_bin" "$@"
  fi
}
