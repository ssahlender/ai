#!/usr/bin/env bash
set -euo pipefail

MODELS_DIR="${MODELS_DIR:-/data/llm/models}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
START_SCRIPT="$SCRIPT_DIR/start-i9.sh"

if [ ! -f "$START_SCRIPT" ]; then
  echo "Missing $START_SCRIPT. Run from ik-llama/ directory." >&2
  exit 1
fi

b2h() {
  local bytes="$1"
  if [ "$bytes" -ge 1073741824 ]; then
    awk "BEGIN { printf \"%.1f GB\", $bytes / 1073741824 }"
  else
    awk "BEGIN { printf \"%.1f MB\", $bytes / 1048576 }"
  fi
}

echo "Scanning $MODELS_DIR ..."
echo

# ── On-disk GGUF listing ──────────────────────────────────────────
ON_DISK=()
echo "=== GGUF files on disk ==="
while IFS= read -r -d '' f; do
  name="$(basename "$f")"
  size="$(stat --format=%s "$f" 2>/dev/null || echo 0)"
  hsize="$(b2h "$size")"
  printf "  %-70s %s\n" "$name" "$hsize"
  ON_DISK+=("$name")
done < <(find "$MODELS_DIR" -maxdepth 1 -name '*.gguf' -not -name 'mmproj*' -print0 2>/dev/null | sort -z)

echo

# ── On-disk mmproj listing ────────────────────────────────────────
echo "=== mmproj files on disk ==="
mmproj_found=0
while IFS= read -r -d '' f; do
  name="$(basename "$f")"
  size="$(stat --format=%s "$f" 2>/dev/null || echo 0)"
  hsize="$(b2h "$size")"
  printf "  %-70s %s\n" "$name" "$hsize"
  mmproj_found=1
done < <(find "$MODELS_DIR" -maxdepth 1 -name 'mmproj*' -print0 2>/dev/null | sort -z)

if [ "$mmproj_found" -eq 0 ]; then
  echo "  (none)"
fi

echo

# ── Parse start-i9.sh for expected model entries ──────────────────
echo "=== Start-script model entries ==="

# Extract lines matching: shortname) start_model "Name" "file.gguf" ctx ...
# Format: shortname→file.gguf→ctx→mmprojfile(optional)
ENTRIES=$(grep -E '^\s+[a-z0-9]+\).*start_model.*\.gguf' "$START_SCRIPT" 2>/dev/null || true)

if [ -z "$ENTRIES" ]; then
  echo "  No model entries found in $START_SCRIPT"
  exit 0
fi

configured=0
missing=0

while IFS= read -r line; do
  shortname=$(echo "$line" | sed -n 's/^\s*\([a-z0-9][a-z0-9]*\))\s.*/\1/p')
  [ -z "$shortname" ] && continue

  gguf=$(echo "$line" | sed -n 's/.*start_model\s*"[^"]*"\s*"\([^"]*\)"\s.*/\1/p')
  [ -z "$gguf" ] && continue

  configured=$((configured + 1))

  ctx=$(echo "$line" | sed -n 's/.*\.gguf"[[:space:]]*\([0-9]\{1,\}\).*/\1/p')
  ctx="${ctx:-?}"

  mmproj=""
  if echo "$line" | grep -q -- '--mmproj'; then
    mmproj=$(echo "$line" | sed -n 's/.*--mmproj.*"\([^"]*\)".*/\1/p')
    mmproj=$(basename "$mmproj")
  fi

  # Check disk
  gguf_exists=0
  gguf_size=0
  gguf_hsize=""
  if [ -f "$MODELS_DIR/$gguf" ]; then
    gguf_exists=1
    gguf_size=$(stat --format=%s "$MODELS_DIR/$gguf" 2>/dev/null || echo 0)
    gguf_hsize=$(b2h "$gguf_size")
  fi

  mmproj_exists=0
  mmproj_hsize=""
  if [ -n "$mmproj" ] && [ -f "$MODELS_DIR/$mmproj" ]; then
    mmproj_exists=1
    mmproj_size=$(stat --format=%s "$MODELS_DIR/$mmproj" 2>/dev/null || echo 0)
    mmproj_hsize=$(b2h "$mmproj_size")
  fi

  if [ "$gguf_exists" -eq 0 ]; then
    status_icon="MISSING"
  elif [ -n "$mmproj" ] && [ "$mmproj_exists" -eq 0 ]; then
    status_icon="NO MMPROJ"
  else
    status_icon="OK     "
  fi

  [ "$status_icon" != "OK     " ] && missing=$((missing + 1))

  ctx_human="?"
  if [ "$ctx" -eq "$ctx" ] 2>/dev/null && [ "$ctx" -gt 0 ] 2>/dev/null; then
    ctx_human="$((ctx / 1024))K"
  fi

  printf "  %-20s %-65s %5s  %-6s %s\n" "$shortname" "$gguf" "$gguf_hsize" "$ctx_human" "$status_icon"

  if [ -n "$mmproj" ]; then
    if [ "$mmproj_exists" -eq 1 ]; then
      printf "    └─ mmproj: %-62s %5s  [on disk]\n" "$mmproj" "$mmproj_hsize"
    else
      printf "    └─ mmproj: %-62s   MISSING\n" "$mmproj"
    fi
  fi
done <<< "$ENTRIES"

echo
echo "=== Stale snapshots (.part files) ==="
stale_found=0
while IFS= read -r -d '' f; do
  name="$(basename "$f")"
  printf "  %s\n" "$name"
  stale_found=1
done < <(find "$MODELS_DIR" -maxdepth 1 -name '*.gguf.part' -print0 2>/dev/null | sort -z)
if [ "$stale_found" -eq 0 ]; then
  echo "  (none)"
fi
echo

echo "=== Summary ==="
printf "  Configured:      %d\n" "$configured"
printf "  Missing/incomplete: %d\n" "$missing"
echo "  Run: ./cleanup-models-i9.sh --apply   to remove obsolete files"
