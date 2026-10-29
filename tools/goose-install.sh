#!/usr/bin/env bash
# Installs the goose CLI (aaif-goose/goose). The brew formula is block-goose-cli: the formula named
# plain `goose` is an unrelated database migration tool that installs the same binary name.
# Wire it to the local models afterwards with ../llm/setup-agents.sh.
set -euo pipefail

# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/_brew-i9.sh"
# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/_brew-wrapper.sh"

_brew_install block-goose-cli
