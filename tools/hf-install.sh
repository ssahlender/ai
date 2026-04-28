#!/usr/bin/env bash
set -euo pipefail

export UV_NATIVE_TLS=1
curl -LsSf https://hf.co/cli/install.sh | bash
