#!/usr/bin/env bash
# Shows on-disk GGUF models vs expected entries from start.sh.
# Usage: ./model-info.sh [i9|macbook-air]
set -euo pipefail

MACHINE="${1:-}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Default models dir based on machine arg, or try to auto-detect
if [ -n "$MACHINE" ]; then
  case "$MACHINE" in
    i9) MODELS_DIR="${MODELS_DIR:-$HOME/.local/share/llama.cpp/models}" ;;
    probook)
      echo "WSL is retired on ProBook. Run model inspection natively on Windows via llm/ (e.g. llm\\fetch-model.ps1 -List)." >&2
      exit 1
      ;;
    macbook-air) MODELS_DIR="${MODELS_DIR:-$HOME/.local/share/llama.cpp/models}" ;;
    *) echo "Usage: $0 [i9|macbook-air]" >&2; exit 1 ;;
  esac
else
  # Auto-detect: try paths
  for d in "$HOME/.local/share/llama.cpp/models"; do
    if [ -d "$d" ] && ls "$d"/*.gguf >/dev/null 2>&1; then
      MODELS_DIR="$d"
      break
    fi
  done
  MODELS_DIR="${MODELS_DIR:-$HOME/.local/share/llama.cpp/models}"
fi

b2h() {
  local bytes="$1"
  if [ "$bytes" -ge 1073741824 ]; then
    awk "BEGIN { printf \"%.1f GB\", $bytes / 1073741824 }"
  else
    awk "BEGIN { printf \"%.1f MB\", $bytes / 1048576 }"
  fi
}

file_size() {
  local f="$1"
  if [ -f "$f" ]; then
    wc -c < "$f" | tr -d ' '
  else
    echo 0
  fi
}

echo "Models dir: $MODELS_DIR"
echo

# ── On-disk GGUF listing ───────────────────────────────────────────
echo "=== GGUF files on disk ==="
found_gguf=0
while IFS= read -r -d '' f; do
  name="$(basename "$f")"
  size="$(file_size "$f")"
  printf "  %-70s %s\n" "$name" "$(b2h "$size")"
  found_gguf=1
done < <(find "$MODELS_DIR" -maxdepth 1 -name '*.gguf' -not -name 'mmproj*' -print0 2>/dev/null | sort -z)
[ "$found_gguf" -eq 0 ] && echo "  (none)"
echo

# ── On-disk mmproj listing ─────────────────────────────────────────
echo "=== mmproj files on disk ==="
found_mm=0
while IFS= read -r -d '' f; do
  name="$(basename "$f")"
  size="$(file_size "$f")"
  printf "  %-70s %s\n" "$name" "$(b2h "$size")"
  found_mm=1
done < <(find "$MODELS_DIR" -maxdepth 1 -name 'mmproj*' -print0 2>/dev/null | sort -z)
[ "$found_mm" -eq 0 ] && echo "  (none)"
echo

# ── Parse start.sh for model entries ───────────────────────────────
echo "=== Start-script model entries ==="

if [ -z "$MACHINE" ]; then
  echo "  No machine specified. Run: $0 <i9|macbook-air>"
  echo
  echo "=== Stale snapshots (.part files) ==="
  stale=0
  while IFS= read -r -d '' f; do
    printf "  %s\n" "$(basename "$f")"
    stale=1
  done < <(find "$MODELS_DIR" -maxdepth 1 -name '*.gguf.part' -print0 2>/dev/null | sort -z)
  [ "$stale" -eq 0 ] && echo "  (none)"
  exit 0
fi

# Extract entries from models.json (the one place model lists live) via models.py
ENTRIES=$(python3 "$SCRIPT_DIR/models.py" info "$MACHINE")

if [ -z "$ENTRIES" ]; then
  echo "  No model entries found for machine '$MACHINE'"
  exit 0
fi

configured=0
missing=0

while IFS=$'\t' read -r desc fn ctx cram mmproj_file; do
  [ -z "$fn" ] && continue
  configured=$((configured + 1))

  is_vision=0
  [ -n "$mmproj_file" ] && is_vision=1

  # Check disk
  gguf_ok=0; gguf_size=0
  if [ -f "$MODELS_DIR/$fn" ]; then
    gguf_ok=1
    gguf_size="$(file_size "$MODELS_DIR/$fn")"
  fi

  mmproj_ok=0; mmproj_size=0
  if [ "$is_vision" -eq 1 ] && [ -n "$mmproj_file" ] && [ -f "$MODELS_DIR/$mmproj_file" ]; then
    mmproj_ok=1
    mmproj_size="$(file_size "$MODELS_DIR/$mmproj_file")"
  fi

  # Status
  if [ "$gguf_ok" -eq 0 ]; then
    status="MISSING"
  elif [ "$is_vision" -eq 1 ] && [ "$mmproj_ok" -eq 0 ]; then
    status="NO MMPROJ"
  else
    status="OK"
  fi
  [ "$status" != "OK" ] && missing=$((missing + 1))

  ctx_human="$((ctx / 1024))K"
  gguf_hsize="$(b2h "$gguf_size")"
  printf "  %-65s %5s  %-6s %s\n" "${fn%.gguf}" "$gguf_hsize" "$ctx_human" "$status"

  if [ "$is_vision" -eq 1 ] && [ -n "$mmproj_file" ]; then
    if [ "$mmproj_ok" -eq 1 ]; then
      mmproj_hsize="$(b2h "$mmproj_size")"
      printf "    └─ mmproj: %-62s %5s  [on disk]\n" "$mmproj_file" "$mmproj_hsize"
    else
      printf "    └─ mmproj: %-62s   MISSING\n" "$mmproj_file"
    fi
  fi
done <<< "$ENTRIES"

echo
echo "=== Stale snapshots (.part files) ==="
stale=0
while IFS= read -r -d '' f; do
  printf "  %s\n" "$(basename "$f")"
  stale=1
done < <(find "$MODELS_DIR" -maxdepth 1 -name '*.gguf.part' -print0 2>/dev/null | sort -z)
[ "$stale" -eq 0 ] && echo "  (none)"
echo

echo "=== Summary ==="
printf "  Configured:      %d\n" "$configured"
printf "  Missing/incomplete: %d\n" "$missing"
echo "  Run: ./cleanup-models.sh $MACHINE --apply   to remove obsolete files"
