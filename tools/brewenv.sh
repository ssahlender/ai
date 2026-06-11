#!/usr/bin/env bash
# brewenv.sh — create ~/brewenv/ symlinks for brew-installed tools.
#
# On corporate Debian machines, brew runs as a shared brewuser account and its
# binaries are not in your PATH directly. This script creates per-user symlinks
# in ~/brewenv/ for whitelisted tools so they are accessible normally.
#
# Usage:
#   brewenv.sh                    # sync all tools from conf to ~/brewenv/
#   brewenv.sh --prune            # also remove links not covered by conf
#   brewenv.sh --add <pattern>    # append pattern to conf, link immediately
#   brewenv.sh --list             # show patterns in conf
#   brewenv.sh --check            # show which conf entries have no brew binary
#   brewenv.sh --conf <path>      # use a different conf file
#
# Add ~/brewenv to PATH in ~/.bashrc / ~/.zshrc:
#   export PATH="$HOME/.local/bin:$HOME/brewenv:$PATH"
set -euo pipefail

BREW_BIN="/home/linuxbrew/.linuxbrew/bin"
BREWENV_DIR="$HOME/brewenv"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF="${SCRIPT_DIR}/brewenv-tools.conf"

ADD_PATTERN=""
LIST_ONLY=false
CHECK_ONLY=false
PRUNE=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --add)    ADD_PATTERN="$2"; shift 2 ;;
    --list)   LIST_ONLY=true; shift ;;
    --check)  CHECK_ONLY=true; shift ;;
    --prune)  PRUNE=true; shift ;;
    --conf)   CONF="$2"; shift 2 ;;
    -h|--help)
      sed -n '2,/^set /p' "${BASH_SOURCE[0]}" | grep '^#' | sed 's/^# \?//'
      exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

if [ ! -f "$CONF" ]; then
  echo "Config not found: $CONF" >&2
  exit 1
fi

# --list
if $LIST_ONLY; then
  echo "Patterns in $CONF:"
  grep -v '^\s*#' "$CONF" | grep -v '^\s*$'
  exit 0
fi

# --add
if [ -n "$ADD_PATTERN" ]; then
  if grep -qxF "$ADD_PATTERN" "$CONF" 2>/dev/null; then
    echo "'$ADD_PATTERN' already in $CONF"
  else
    printf '\n%s\n' "$ADD_PATTERN" >> "$CONF"
    echo "Added '$ADD_PATTERN' to $CONF"
  fi
fi

mkdir -p "$BREWENV_DIR"

linked=0
skipped=0
missing=0

while IFS= read -r pattern || [[ -n "$pattern" ]]; do
  # skip comments and blank lines
  [[ "$pattern" =~ ^[[:space:]]*# ]] && continue
  [[ -z "${pattern// }" ]] && continue

  # expand glob
  if [[ "$pattern" == *\** ]] || [[ "$pattern" == *\?* ]]; then
    matches=("$BREW_BIN"/$pattern)
  else
    matches=("$BREW_BIN/$pattern")
  fi

  found_any=false
  for src in "${matches[@]}"; do
    [ -e "$src" ] || [ -L "$src" ] || continue
    found_any=true
    name="$(basename "$src")"
    dest="$BREWENV_DIR/$name"

    if [ -L "$dest" ] && [ "$(readlink "$dest")" = "$src" ]; then
      (( skipped++ )) || true
    else
      ln -sf "$src" "$dest"
      echo "  linked: $name"
      (( linked++ )) || true
    fi
  done

  if ! $found_any; then
    if $CHECK_ONLY || [[ "$pattern" != *\** && "$pattern" != *\?* ]]; then
      echo "  missing: $pattern (not in $BREW_BIN)"
    fi
    (( missing++ )) || true
  fi
done < "$CONF"

# --prune: remove links in ~/brewenv/ that point into BREW_BIN but aren't in conf
pruned=0
if $PRUNE; then
  # collect all names covered by conf patterns
  declare -A covered
  while IFS= read -r pattern || [[ -n "$pattern" ]]; do
    [[ "$pattern" =~ ^[[:space:]]*# ]] && continue
    [[ -z "${pattern// }" ]] && continue
    if [[ "$pattern" == *\** ]] || [[ "$pattern" == *\?* ]]; then
      for src in "$BREW_BIN"/$pattern; do
        [ -e "$src" ] && covered["$(basename "$src")"]=1
      done
    else
      covered["$pattern"]=1
    fi
  done < "$CONF"

  for link in "$BREWENV_DIR"/*; do
    [ -L "$link" ] || continue
    target="$(readlink "$link")"
    # only touch links that point into the brew bin dir
    [[ "$target" == "$BREW_BIN"/* ]] || continue
    name="$(basename "$link")"
    if [[ -z "${covered[$name]+x}" ]]; then
      rm "$link"
      echo "  pruned: $name"
      (( pruned++ )) || true
    fi
  done
fi

echo ""
echo "Done: $linked new link(s), $skipped already current, $missing pattern(s) not found in brew${PRUNE:+", $pruned pruned"}."
if [ "$missing" -gt 0 ]; then
  echo "       Install missing tools with: sudo -n -u brewuser $BREW_BIN/brew install <tool>"
fi
