#!/usr/bin/env bash
# kill-proxy.sh — stop ocg-proxy.py
set -euo pipefail
fuser -k 4099/tcp 2>/dev/null && echo "proxy killed" || echo "no proxy running"
