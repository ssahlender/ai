#!/bin/bash

sudo apt update
sudo apt install -y curl ca-certificates build-essential

curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/master/install.sh | bash

# load nvm into the current shell
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

# install the current LTS release
nvm install --lts
nvm alias default lts/*
nvm use default

# verify
node -v
npm -v
npx -v
