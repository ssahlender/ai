#!/usr/bin/env bash
# kill-proxy.sh — stop ocg-proxy.py (4099) and local-proxy.py (9081)
set -euo pipefail
fuser -k 4099/tcp 2>/dev/null && echo "ocg-proxy killed"   || echo "ocg-proxy not running"
fuser -k 9081/tcp 2>/dev/null && echo "local-proxy killed" || echo "local-proxy not running"
