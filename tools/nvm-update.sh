#!/usr/bin/env bash
set -euo pipefail

export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"

if [ -s "$NVM_DIR/nvm.sh" ]; then
  . "$NVM_DIR/nvm.sh"
else
  echo "nvm not found in $NVM_DIR"
  echo "Install it first, or fix NVM_DIR."
  exit 1
fi

nvm install --lts --reinstall-packages-from=current
nvm alias default 'lts/*'
nvm use default

npm install -g npm@latest

node -v
npm -v
npx -v
