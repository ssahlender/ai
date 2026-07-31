#!/usr/bin/env bash
# session-cleanup.sh — list and optionally truncate large Claude Code sessions.
#
# Usage:
#   ./session-cleanup.sh              # list all sessions, highlight large ones
#   ./session-cleanup.sh --truncate <uuid>  # truncate one session (backup first)
#   ./session-cleanup.sh --truncate-all     # truncate every session >300 KB
#
# Truncation keeps line 1 (session metadata) + last 150 lines (recent context).
# A .bak copy is saved before any truncation.
set -euo pipefail

THRESHOLD_KB=300
TAIL_LINES=150
SESSIONS_ROOT="$HOME/.claude/projects"

# ── helpers ─────────────────────────────────────────────────────────────────

red()   { printf '\033[31m%s\033[0m\n' "$*"; }
green() { printf '\033[32m%s\033[0m\n' "$*"; }
dim()   { printf '\033[2m%s\033[0m\n' "$*"; }

truncate_session() {
  local file="$1"
  local bak="${file}.bak"
  local size_kb=$(( $(wc -c < "$file") / 1024 ))
  local lines
  lines=$(wc -l < "$file")

  cp "$file" "$bak"

  # Keep first line (sessionId metadata) + last TAIL_LINES lines.
  # If the file has <= TAIL_LINES+1 lines, nothing to do.
  if [ "$lines" -le $(( TAIL_LINES + 1 )) ]; then
    echo "  $(basename "$file"): only ${lines} lines — nothing to truncate"
    rm -f "$bak"
    return
  fi

  { head -1 "$bak"; tail -n "$TAIL_LINES" "$bak"; } > "$file"
  local new_lines new_kb
  new_lines=$(wc -l < "$file")
  new_kb=$(( $(wc -c < "$file") / 1024 ))
  green "  truncated: $(basename "$file")  ${size_kb}KB/${lines}L → ${new_kb}KB/${new_lines}L  (backup: $(basename "$bak"))"
}

# ── list mode (default) ───────────────────────────────────────────────────────

list_sessions() {
  local found=0
  while IFS= read -r -d '' file; do
    local size_kb lines project uuid
    size_kb=$(( $(wc -c < "$file") / 1024 ))
    lines=$(wc -l < "$file")
    project=$(basename "$(dirname "$file")")
    uuid=$(basename "$file" .jsonl)
    found=1

    if [ "$size_kb" -ge "$THRESHOLD_KB" ]; then
      red "  ⚠ ${size_kb}KB  ${lines}L  ${uuid}  (${project})"
    else
      dim "    ${size_kb}KB  ${lines}L  ${uuid}  (${project})"
    fi
  done < <(find "$SESSIONS_ROOT" -name '*.jsonl' -not -name '*.bak' -print0 2>/dev/null | sort -z)

  [ "$found" -eq 0 ] && echo "  No sessions found in $SESSIONS_ROOT" || true
}

# ── argument parsing ─────────────────────────────────────────────────────────

ACTION="${1:-list}"

case "$ACTION" in
  list|"")
    echo "Claude Code sessions (threshold: >${THRESHOLD_KB} KB highlighted in red):"
    echo
    list_sessions
    echo
    dim "Truncate a session:  $0 --truncate <uuid>"
    dim "Truncate all large:  $0 --truncate-all"
    ;;

  --truncate)
    UUID="${2:?--truncate requires a session UUID}"
    file=$(find "$SESSIONS_ROOT" -name "${UUID}.jsonl" -not -name '*.bak' 2>/dev/null | head -1)
    if [ -z "$file" ]; then
      echo "Session not found: $UUID" >&2
      exit 1
    fi
    truncate_session "$file"
    ;;

  --truncate-all)
    echo "Truncating all sessions >${THRESHOLD_KB} KB:"
    echo
    count=0
    while IFS= read -r -d '' file; do
      size_kb=$(( $(wc -c < "$file") / 1024 ))
      if [ "$size_kb" -ge "$THRESHOLD_KB" ]; then
        truncate_session "$file"
        count=$(( count + 1 ))
      fi
    done < <(find "$SESSIONS_ROOT" -name '*.jsonl' -not -name '*.bak' -print0 2>/dev/null | sort -z)
    echo
    [ "$count" -eq 0 ] && echo "Nothing to truncate — no sessions >${THRESHOLD_KB} KB." || echo "${count} session(s) truncated."
    ;;

  -h|--help)
    sed -n '2,9p' "${BASH_SOURCE[0]}" | sed 's/^# \?//'
    ;;

  *)
    echo "Unknown option: $ACTION" >&2
    echo "Usage: $0 [--truncate <uuid>] [--truncate-all]" >&2
    exit 1
    ;;
esac
