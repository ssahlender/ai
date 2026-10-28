#!/usr/bin/env bash
# One-time move of i9's local-LLM engine/models from /data/llm to the home layout the
# scripts now default to (~/.local/share/llama.cpp). Mirrors llm/move-to-home.ps1 for
# ProBook. Safe to re-run: skips anything already moved or not present at the source, and
# refuses if llama-server is running (moving its model/binary out from under it fails
# confusingly instead of cleanly).
#
# Usage: ./move-to-home.sh [--dry-run] [--from DIR] [--to DIR]
set -euo pipefail

DRY_RUN=0
FROM="/data/llm"
TO="$HOME/.local/share/llama.cpp"

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    --from) FROM="$2"; shift 2 ;;
    --to) TO="$2"; shift 2 ;;
    *) echo "Usage: $0 [--dry-run] [--from DIR] [--to DIR]" >&2; exit 1 ;;
  esac
done

if pgrep -x llama-server >/dev/null 2>&1; then
  echo "llama-server is running. Stop it first (it may be serving a live agent session) -- moving its model/binary out from under it fails confusingly instead of cleanly." >&2
  exit 1
fi

if [ ! -d "$FROM" ]; then
  echo "Nothing to move: $FROM does not exist. Already migrated, or never used the old layout."
  exit 0
fi

if [ "$DRY_RUN" -eq 0 ]; then
  mkdir -p "$TO"
elif [ ! -d "$TO" ]; then
  echo "would create: $TO"
fi

KNOWN=(ik_llama models)
for name in "${KNOWN[@]}"; do
  src="$FROM/$name"
  dst="$TO/$name"
  if [ ! -e "$src" ]; then
    echo "skip (not present): $src"
    continue
  fi
  if [ -e "$dst" ]; then
    echo "skip (already exists at destination): $dst"
    continue
  fi
  if [ "$DRY_RUN" -eq 1 ]; then
    echo "would move: $src -> $dst"
  else
    echo "moving: $src -> $dst"
    mv "$src" "$dst"
  fi
done

leftover=$(find "$FROM" -maxdepth 1 -mindepth 1 2>/dev/null | while read -r p; do
  base="$(basename "$p")"
  skip=0
  for k in "${KNOWN[@]}"; do [ "$base" = "$k" ] && skip=1; done
  [ "$skip" -eq 0 ] && echo "$p"
done || true)
if [ -n "$leftover" ]; then
  echo
  echo "Left behind under $FROM (not one of the known subdirs, review manually):"
  echo "$leftover" | sed 's/^/  /'
fi

if [ "$DRY_RUN" -eq 0 ] && [ -z "$(find "$FROM" -maxdepth 1 -mindepth 1 2>/dev/null)" ]; then
  echo
  echo "$FROM is now empty. Remove it manually once you've confirmed everything works: rm -rf '$FROM'"
fi
