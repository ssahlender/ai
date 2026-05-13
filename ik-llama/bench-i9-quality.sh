#!/usr/bin/env bash
# Focused i9 benchmark for dense quality candidates and current baselines.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

exec "$SCRIPT_DIR/bench-i9.sh" quality
