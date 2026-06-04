#!/usr/bin/env bash
# Shows on-disk GGUF models vs expected entries from start.sh.
# Usage: ./model-info.sh [i9|probook|macbook-air]
set -euo pipefail

MACHINE="${1:-}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
START_SCRIPT="$SCRIPT_DIR/start.sh"

if [ ! -f "$START_SCRIPT" ]; then
  echo "Missing $START_SCRIPT" >&2
  exit 1
fi

# Default models dir based on machine arg, or try to auto-detect
if [ -n "$MACHINE" ]; then
  case "$MACHINE" in
    i9) MODELS_DIR="${MODELS_DIR:-/data/llm/models}" ;;
    probook) MODELS_DIR="${MODELS_DIR:-/mnt/c/data/llm/models}" ;;
    macbook-air) MODELS_DIR="${MODELS_DIR:-$HOME/.local/share/llama.cpp/models}" ;;
    *) echo "Usage: $0 [i9|probook|macbook-air]" >&2; exit 1 ;;
  esac
else
  # Auto-detect: try paths
  for d in /data/llm/models /mnt/c/data/llm/models "$HOME/.local/share/llama.cpp/models"; do
    if [ -d "$d" ] && ls "$d"/*.gguf >/dev/null 2>&1; then
      MODELS_DIR="$d"
      break
    fi
  done
  MODELS_DIR="${MODELS_DIR:-/data/llm/models}"
fi

b2h() {
  local bytes="$1"
  if [ "$bytes" -ge 1073741824 ]; then
    awk "BEGIN { printf \"%.1f GB\", $bytes / 1073741824 }"
  else
    awk "BEGIN { printf \"%.1f MB\", $bytes / 1048576 }"
  fi
}

echo "Models dir: $MODELS_DIR"
echo

# ── On-disk GGUF listing ───────────────────────────────────────────
echo "=== GGUF files on disk ==="
found_gguf=0
while IFS= read -r -d '' f; do
  name="$(basename "$f")"
  size="$(stat --format=%s "$f" 2>/dev/null || echo 0)"
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
  size="$(stat --format=%s "$f" 2>/dev/null || echo 0)"
  printf "  %-70s %s\n" "$name" "$(b2h "$size")"
  found_mm=1
done < <(find "$MODELS_DIR" -maxdepth 1 -name 'mmproj*' -print0 2>/dev/null | sort -z)
[ "$found_mm" -eq 0 ] && echo "  (none)"
echo

# ── Parse start.sh for model entries ───────────────────────────────
echo "=== Start-script model entries ==="

if [ -z "$MACHINE" ]; then
  echo "  No machine specified. Run: $0 <i9|probook|macbook-air>"
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

# Extract entries from the machine case block in start.sh
# Format: "shortname|desc|filename.gguf|ctx|cram|flags"
ENTRIES=$(awk -v m="$MACHINE" '
  $0 ~ "^[[:space:]]*" m "\\)[[:space:]]*$" { in_block=1; next }
  in_block && /^[[:space:]]*;;/ { exit }
  in_block && /\".*[.]gguf\|/ {
    if (match($0, /"[^"]+[.]gguf\|[0-9]+\|[0-9]+[^"]*"/)) {
      entry = substr($0, RSTART+1, RLENGTH-2)
      print entry
    }
  }
' "$START_SCRIPT")

if [ -z "$ENTRIES" ]; then
  echo "  No model entries found for machine '$MACHINE'"
  exit 0
fi

configured=0
missing=0

while IFS= read -r line; do
  IFS='|' read -r sn desc fn ctx cram rest <<< "$line"
  [ -z "$sn" ] && continue
  configured=$((configured + 1))

  # Vision detection: extra fields after cram may contain mmproj-*.gguf
  is_vision=0
  mmproj_file=""
  if echo "$rest" | grep -q 'mmproj-'; then
    is_vision=1
    for f in $(echo "$rest" | tr '|' ' '); do
      case "$f" in
        mmproj-*) mmproj_file="$f" ;;
      esac
    done
  fi

  # Check disk
  gguf_ok=0; gguf_size=0
  if [ -f "$MODELS_DIR/$fn" ]; then
    gguf_ok=1
    gguf_size=$(stat --format=%s "$MODELS_DIR/$fn" 2>/dev/null || echo 0)
  fi

  mmproj_ok=0; mmproj_size=0
  if [ "$is_vision" -eq 1 ] && [ -n "$mmproj_file" ] && [ -f "$MODELS_DIR/$mmproj_file" ]; then
    mmproj_ok=1
    mmproj_size=$(stat --format=%s "$MODELS_DIR/$mmproj_file" 2>/dev/null || echo 0)
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
  printf "  %-20s %-65s %5s  %-6s %s\n" "$sn" "$fn" "$gguf_hsize" "$ctx_human" "$status"

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
