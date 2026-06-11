#!/usr/bin/env bash
# Pack a directory with repomix and print the output path.
# Usage: repomix-pack.sh [dir] [--style markdown|xml|plain] [--ignore "pat1,pat2"]
#
# Output goes to /tmp/repomix-<dirname>.md (or .xml/.txt).
# Any repomix.config.json in the target dir is respected as-is.
set -euo pipefail

TARGET_DIR="."
STYLE="markdown"
EXTRA_IGNORE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --style) STYLE="$2"; shift 2 ;;
    --ignore) EXTRA_IGNORE="$2"; shift 2 ;;
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

echo "Packing: $TARGET_DIR"
repomix \
  --style "$STYLE" \
  --output "$OUTPUT" \
  --ignore "$IGNORE_PATTERNS" \
  "$TARGET_DIR" 2>&1 | grep -E "✔|Total Files|Total Tokens|Output|Error|error" || true

echo ""
echo "Output: $OUTPUT"
