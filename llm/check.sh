#!/usr/bin/env bash
# Check the repository: syntax, catalog, public-repo rule, sandboxed dry runs for every machine, and
# (read-only) this machine's engine, models and llama-swap config. Logic: shared/check.py. Exit 0 = ok.
exec python3 "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/shared/check.py" "$@"
