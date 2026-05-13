#!/usr/bin/env bash
# Focused i9 benchmark for Qwen3-Coder quantization tradeoffs.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

exec "$SCRIPT_DIR/bench-i9.sh" coder
