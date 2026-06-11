#!/usr/bin/env bash
# Pack a directory with repomix and print the output path.
# Usage: repomix-pack.sh [dir] [--style markdown|xml|plain] [--ignore "pat1,pat2"]
#                        [--logs] [--logs-count N] [--diffs] [--compress]
#
# --logs          Include recent git commit history (default: on). Useful when
#                 multiple agents work on the same repo.
# --no-logs       Disable git history inclusion.
# --logs-count N  Number of commits to include (default: 20).
# --diffs         Include git diff for working tree and staged changes.
# --compress      Extract code structure only (classes, functions, interfaces)
#                 instead of full file contents — reduces token count significantly.
#
# Output goes to /tmp/repomix-<dirname>.md (or .xml/.txt).
# Any repomix.config.json in the target dir is respected as-is.
set -euo pipefail

TARGET_DIR="."
STYLE="markdown"
EXTRA_IGNORE=""
INCLUDE_LOGS=true
LOGS_COUNT=20
INCLUDE_DIFFS=false
COMPRESS=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --style)       STYLE="$2"; shift 2 ;;
    --ignore)      EXTRA_IGNORE="$2"; shift 2 ;;
    --logs)        INCLUDE_LOGS=true; shift ;;
    --no-logs)     INCLUDE_LOGS=false; shift ;;
    --logs-count)  LOGS_COUNT="$2"; shift 2 ;;
    --diffs)       INCLUDE_DIFFS=true; shift ;;
    --compress)    COMPRESS=true; shift ;;
    -*) echo "Unknown option: $1" >&2; exit 1 ;;
    *) TARGET_DIR="$1"; shift ;;
  esac
done

TARGET_DIR="$(realpath "$TARGET_DIR")"
DIRNAME="$(basename "$TARGET_DIR")"

case "$STYLE" in
  markdown) EXT="md" ;;
  xml)      EXT="xml" ;;
  plain)    EXT="txt" ;;
  *)        EXT="md" ;;
esac

OUTPUT="/tmp/repomix-${DIRNAME}.${EXT}"

IGNORE_PATTERNS="repomix-output.*,bench-results/"
if [ -n "$EXTRA_IGNORE" ]; then
  IGNORE_PATTERNS="${IGNORE_PATTERNS},${EXTRA_IGNORE}"
fi

EXTRA_FLAGS=()
$INCLUDE_LOGS  && EXTRA_FLAGS+=(--include-logs --include-logs-count "$LOGS_COUNT")
$INCLUDE_DIFFS && EXTRA_FLAGS+=(--include-diffs)
$COMPRESS      && EXTRA_FLAGS+=(--compress)

echo "Packing: $TARGET_DIR"
repomix \
  --style "$STYLE" \
  --output "$OUTPUT" \
  --ignore "$IGNORE_PATTERNS" \
  "${EXTRA_FLAGS[@]}" \
  "$TARGET_DIR" 2>&1 | grep -E "✔|Total Files|Total Tokens|Output|Error|error" || true

echo ""
echo "Output: $OUTPUT"
