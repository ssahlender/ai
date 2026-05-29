#!/usr/bin/env bash
# Compatibility wrapper. Prefer ./setup-agents-probook.sh.
set -euo pipefail

exec "$(dirname "${BASH_SOURCE[0]}")/setup-agents-probook.sh" "$@"
