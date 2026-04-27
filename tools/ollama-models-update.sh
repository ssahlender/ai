#!/usr/bin/env bash
set -euo pipefail

ollama list | awk 'NR > 1 {print $1}' | xargs -r -n1 ollama pull
