# common.sh — sourced by the Unix scripts in llm/ (i9 and Mac). Functions only, no side effects.

# find_bin <name>: PATH first, then the Homebrew/Linuxbrew prefixes that non-interactive shells
# (ssh, launchd, cron) do not have on PATH. Prints the path, or nothing.
find_bin() {
  local c
  for c in "$(command -v "$1" 2>/dev/null || true)" "/home/linuxbrew/.linuxbrew/bin/$1" \
           "/opt/homebrew/bin/$1" "/usr/local/bin/$1"; do
    [ -n "$c" ] && [ -x "$c" ] && { echo "$c"; return 0; }
  done
  return 1
}

# pids_on_port <port>: pids listening on a TCP port (lsof, else fuser). Matching by port, not by
# command line: `pkill -f <name>` also hits any shell whose own command line contains <name>.
pids_on_port() {
  if command -v lsof >/dev/null 2>&1; then
    lsof -ti ":$1" -sTCP:LISTEN 2>/dev/null || true
  elif command -v fuser >/dev/null 2>&1; then
    fuser "$1/tcp" 2>/dev/null || true
  fi
}

# stop_port <port> <label>: SIGTERM whatever listens there (llama-swap then stops its model cleanly).
stop_port() {
  local pids
  pids=$(pids_on_port "$1")
  if [ -n "$pids" ]; then
    kill $pids 2>/dev/null || true
    echo "$2 stopped (port $1)"
  else
    echo "$2 not running (port $1)"
  fi
}

# wait_http <url> [tries]: poll until the URL answers at all (any HTTP status), 0.5 s apart.
wait_http() {
  local i
  for i in $(seq 1 "${2:-20}"); do
    curl -s -o /dev/null --max-time 2 "$1" && return 0
    sleep 0.5
  done
  return 1
}
