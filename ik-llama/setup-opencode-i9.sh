#!/usr/bin/env bash
# Compatibility wrapper. Prefer ./setup-agents-i9.sh.
set -euo pipefail

exec "$(dirname "${BASH_SOURCE[0]}")/setup-agents-i9.sh" "$@"
