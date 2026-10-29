#!/usr/bin/env bash
# Wire the local model into every installed agent (OpenCode, Pi, Docker Agent, goose) on the i9 or the Mac.
# The machine is detected (override: --machine i9|mac or LLM_MACHINE); the logic is in
# shared/setup_agents.py, shared with the ProBook's probook/setup-agents.ps1.
# Usage: ./setup-agents.sh [--dry-run] [--base-url URL] [--machine i9|mac]
exec python3 "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/shared/setup_agents.py" "$@"
