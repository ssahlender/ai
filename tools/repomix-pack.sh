#!/usr/bin/env bash
# Create a Repomix config when needed, then pack a repository for an AI agent.
# Usage: repomix-pack.sh [dir] [--style markdown|xml|json|plain]
#                        [--output path] [--ignore "pat1,pat2"]
#                        [--logs] [--logs-count N] [--diffs] [--compress]
#                        [--init-only]
#
# The default output is <repo>/repomix-output.md. Existing Repomix config files
# are preserved. CLI options override their corresponding config values.
set -euo pipefail

TARGET_DIR="."
TARGET_SET=false
STYLE=""
OUTPUT=""
EXTRA_IGNORE=""
INCLUDE_LOGS=false
LOGS_COUNT=20
INCLUDE_DIFFS=false
COMPRESS=false
INIT_ONLY=false

usage() {
  sed -n '2,9p' "${BASH_SOURCE[0]}" | sed 's/^# \?//'
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)     usage; exit 0 ;;
    --style)       STYLE="${2:?--style requires a value}"; shift 2 ;;
    --output)      OUTPUT="${2:?--output requires a value}"; shift 2 ;;
    --ignore)      EXTRA_IGNORE="${2:?--ignore requires a value}"; shift 2 ;;
    --logs)        INCLUDE_LOGS=true; shift ;;
    --logs-count)  LOGS_COUNT="${2:?--logs-count requires a value}"; shift 2 ;;
    --diffs)       INCLUDE_DIFFS=true; shift ;;
    --compress)    COMPRESS=true; shift ;;
    --init-only)   INIT_ONLY=true; shift ;;
    -*) echo "Unknown option: $1" >&2; exit 1 ;;
    *)
      if $TARGET_SET; then
        echo "Only one target directory may be specified." >&2
        exit 1
      fi
      TARGET_DIR="$1"
      TARGET_SET=true
      shift
      ;;
  esac
done

TARGET_DIR="$(realpath "$TARGET_DIR")"
if [ ! -d "$TARGET_DIR" ]; then
  echo "Directory not found: $TARGET_DIR" >&2
  exit 1
fi

CONFIG_FOUND=false
for config in \
  repomix.config.ts repomix.config.mts repomix.config.cts \
  repomix.config.js repomix.config.mjs repomix.config.cjs \
  repomix.config.json5 repomix.config.jsonc repomix.config.json; do
  if [ -f "$TARGET_DIR/$config" ]; then
    CONFIG_FOUND=true
    echo "Using config: $TARGET_DIR/$config"
    break
  fi
done

if ! $CONFIG_FOUND; then
  cat > "$TARGET_DIR/repomix.config.json" <<'EOF'
{
  "$schema": "https://repomix.com/schemas/latest/schema.json",
  "output": {
    "style": "markdown",
    "filePath": "repomix-output.md",
    "compress": false,
    "fileSummary": true,
    "directoryStructure": true,
    "files": true,
    "removeComments": false,
    "removeEmptyLines": false,
    "showLineNumbers": false,
    "topFilesLength": 10,
    "git": {
      "sortByChanges": true,
      "sortByChangesMaxCommits": 100,
      "includeDiffs": false,
      "includeLogs": false,
      "includeLogsCount": 20
    }
  },
  "ignore": {
    "useGitignore": true,
    "useDotIgnore": true,
    "useDefaultPatterns": true,
    "customPatterns": [
      "repomix-output.*",
      "bench-results/"
    ]
  },
  "security": {
    "enableSecurityCheck": true
  },
  "tokenCount": {
    "encoding": "o200k_base"
  }
}
EOF
  echo "Created config: $TARGET_DIR/repomix.config.json"
fi

GITIGNORE="$TARGET_DIR/.gitignore"
if ! grep -qxF 'repomix-output.*' "$GITIGNORE" 2>/dev/null; then
  if [ -s "$GITIGNORE" ] && [ -n "$(tail -c 1 "$GITIGNORE")" ]; then
    printf '\n' >> "$GITIGNORE"
  fi
  if [ -s "$GITIGNORE" ]; then
    printf '\n# Generated AI context\n' >> "$GITIGNORE"
  fi
  printf 'repomix-output.*\n' >> "$GITIGNORE"
  echo "Added generated output to: $GITIGNORE"
fi

if $INIT_ONLY; then
  exit 0
fi

if ! command -v repomix >/dev/null 2>&1; then
  echo "repomix is not installed or not in PATH." >&2
  echo "Run tools/repomix-install.sh first." >&2
  exit 1
fi

if [ -z "$OUTPUT" ]; then
  case "${STYLE:-markdown}" in
    markdown) OUTPUT="$TARGET_DIR/repomix-output.md" ;;
    xml)      OUTPUT="$TARGET_DIR/repomix-output.xml" ;;
    json)     OUTPUT="$TARGET_DIR/repomix-output.json" ;;
    plain)    OUTPUT="$TARGET_DIR/repomix-output.txt" ;;
    *) echo "Unsupported style: $STYLE" >&2; exit 1 ;;
  esac
elif [[ "$OUTPUT" != /* ]]; then
  OUTPUT="$TARGET_DIR/$OUTPUT"
fi

EXTRA_FLAGS=()
if [ -n "$STYLE" ]; then
  EXTRA_FLAGS+=(--style "$STYLE")
fi
if [ -n "$EXTRA_IGNORE" ]; then
  EXTRA_FLAGS+=(--ignore "$EXTRA_IGNORE")
fi
$INCLUDE_LOGS  && EXTRA_FLAGS+=(--include-logs --include-logs-count "$LOGS_COUNT")
$INCLUDE_DIFFS && EXTRA_FLAGS+=(--include-diffs)
$COMPRESS      && EXTRA_FLAGS+=(--compress)

echo "Packing: $TARGET_DIR"
(
  cd "$TARGET_DIR"
  repomix --output "$OUTPUT" "${EXTRA_FLAGS[@]}" .
)

echo ""
echo "Agent context: $OUTPUT"
