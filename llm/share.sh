#!/usr/bin/env bash
# Share this machine's local models with the home gateway through an outgoing SSH tunnel (i9, Mac).
# llama-swap stays on 127.0.0.1; the logic is in shared/share.py, shared with probook/share.ps1.
# Usage: ./share.sh --init (once: key + config)   ./share.sh (foreground, Ctrl-C stops)   ./share.sh --dry-run
exec python3 "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/shared/share.py" "$@"
