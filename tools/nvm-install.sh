#!/usr/bin/env bash
set -euo pipefail

sudo apt update
sudo apt install -y curl ca-certificates build-essential

curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/master/install.sh | bash

export NVM_DIR="$HOME/.nvm"
# shellcheck source=/dev/null
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

nvm install --lts
nvm alias default lts/*
nvm use default

node -v
npm -v
npx -v
