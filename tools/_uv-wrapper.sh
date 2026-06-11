# shellcheck shell=bash
# Shared uv helpers. Source after _brew-i9.sh and _brew-wrapper.sh.
#
# find_uv          — print path to a working uv binary, or return 1
# ensure_uv_or_pipx — ensure a working uv or pipx is available, installing if needed
#
# On i9 (Debian 12, GLIBC < 2.38/2.39) brew's uv bottle is incompatible.
# ensure_uv_or_pipx installs via the official astral.sh installer instead,
# which provides a musl binary that works on any glibc version.
# Set SYSTEM_CA_FILE to override the default CA bundle path.

SYSTEM_CA_FILE="${SYSTEM_CA_FILE:-/etc/ssl/certs/ca-certificates.crt}"

find_uv() {
  local candidates=()

  # On i9 brew's uv is GLIBC-incompatible — only check user-local locations
  if [ -z "${IS_I9:-}" ]; then
    local path_uv
    path_uv="$(command -v uv 2>/dev/null)" && candidates+=("$path_uv")
    candidates+=(/home/linuxbrew/.linuxbrew/bin/uv /opt/homebrew/bin/uv /usr/local/bin/uv)
  fi

  candidates+=("$HOME/.local/bin/uv" "$HOME/.cargo/bin/uv")

  for candidate in "${candidates[@]}"; do
    if [ -x "$candidate" ] && "$candidate" --version &>/dev/null; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  return 1
}

_install_uv_official() {
  echo "Installing uv via official astral.sh installer (musl binary, glibc-independent)"
  if [ -n "${IS_I9:-}" ] && [ -f "$SYSTEM_CA_FILE" ]; then
    SSL_CERT_FILE="$SYSTEM_CA_FILE" \
      curl -LsSf https://astral.sh/uv/install.sh | \
      SSL_CERT_FILE="$SYSTEM_CA_FILE" sh
  else
    curl -LsSf https://astral.sh/uv/install.sh | sh
  fi
  export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"
}

ensure_uv_or_pipx() {
  # On i9 brew's uv is GLIBC-incompatible — install via official installer
  # even if pipx is available, so uv is the preferred path going forward.
  if [ -n "${IS_I9:-}" ] && ! find_uv >/dev/null 2>&1; then
    _install_uv_official
    return 0
  fi

  if find_uv >/dev/null 2>&1 || command -v pipx >/dev/null 2>&1; then
    return 0
  fi

  if command -v brew >/dev/null 2>&1; then
    _brew_install uv
    return 0
  elif command -v curl >/dev/null 2>&1; then
    _install_uv_official
    find_uv >/dev/null 2>&1 && return 0
  fi

  echo "uv or pipx is required. Install uv: https://docs.astral.sh/uv/getting-started/installation/" >&2
  exit 1
}
