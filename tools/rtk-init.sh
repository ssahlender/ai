#!/usr/bin/env bash
set -euo pipefail

find_rtk() {
  if command -v rtk >/dev/null 2>&1; then
    command -v rtk
    return
  fi

  for candidate in \
    /home/linuxbrew/.linuxbrew/bin/rtk \
    /opt/homebrew/bin/rtk \
    /usr/local/bin/rtk \
    "$HOME/.local/bin/rtk"; do
    if [ -x "$candidate" ]; then
      echo "$candidate"
      return
    fi
  done

  return 1
}

RTK="$(find_rtk)" || {
  echo "rtk not found in PATH or common install locations." >&2
  exit 1
}

"$RTK" init -g
"$RTK" init -g --codex
"$RTK" init -g --opencode
"$RTK" init -g --agent pi
if command -v hermes >/dev/null 2>&1; then
  "$RTK" init -g --agent hermes
else
  echo "hermes not found — skipping Hermes RTK init"
fi
