#!/usr/bin/env bash
# Installs nvm via Homebrew and configures the shell. Skipped on i9 (work provides Node).
set -euo pipefail

# Skip on i9 (native Linux, company proxy) — work provides its own Node stack
if [[ "$(uname -s)" == "Linux" ]] && ! grep -qi "microsoft" /proc/version 2>/dev/null; then
  echo "Skipping on i9 — work provides its own Node stack."
  exit 0
fi

# Install nvm via brew
if ! brew list --formula nvm &>/dev/null; then
  echo "Installing nvm..."
  brew install nvm
else
  echo "nvm is already installed."
fi

# Detect shell config file
detect_shell_config() {
  case "${SHELL:-}" in
    */zsh)  echo "$HOME/.zshrc" ;;
    */bash)
      if [[ "$(uname -s)" == "Darwin" ]]; then
        echo "$HOME/.bash_profile"
      else
        echo "$HOME/.bashrc"
      fi
      ;;
    *)
      [[ -f "$HOME/.zshrc" ]] && echo "$HOME/.zshrc" || echo "$HOME/.bashrc"
      ;;
  esac
}

SHELL_CONFIG=$(detect_shell_config)
echo "Shell config: $SHELL_CONFIG"

if grep -q 'NVM_DIR' "$SHELL_CONFIG" 2>/dev/null; then
  echo "NVM config already present in $SHELL_CONFIG — skipping."
else
  cat >> "$SHELL_CONFIG" << 'EOF'

# nvm (Node Version Manager)
export NVM_DIR="$HOME/.nvm"
[ -s "$(brew --prefix)/opt/nvm/nvm.sh" ] && . "$(brew --prefix)/opt/nvm/nvm.sh"
EOF
  echo "Added NVM config to $SHELL_CONFIG"
fi

# Source nvm in this session and install LTS
export NVM_DIR="$HOME/.nvm"
# shellcheck source=/dev/null
[ -s "$(brew --prefix)/opt/nvm/nvm.sh" ] && . "$(brew --prefix)/opt/nvm/nvm.sh"

nvm install --lts
nvm alias default lts/*
nvm use default

node -v && npm -v && npx -v

npm install -g @rely-ai/caliber
echo "caliber installed: $(caliber --version)"
