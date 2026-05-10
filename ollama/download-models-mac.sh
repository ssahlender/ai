#!/usr/bin/env bash
# Downloads models for MacBook Air M4 (24 GB unified memory).
# Uses Ollama with Metal GPU acceleration.
# Custom-quant models (IQ4_NL, etc.) are pulled from HuggingFace GGUFs
# and imported into Ollama via Modelfile.
set -euo pipefail

# --- config ----------------------------------------------------------------
MODELS_DIR="${MODELS_DIR:-$HOME/.ollama-models}"
mkdir -p "$MODELS_DIR"

if ! command -v ollama >/dev/null 2>&1; then
  echo "ollama not found. Install: curl -fsSL https://ollama.com/install.sh | sh" >&2
  exit 1
fi

# --- helpers ---------------------------------------------------------------
download_gguf() {
  local repo="$1" file="$2"
  local dest="$MODELS_DIR/$file"
  if [ -f "$dest" ]; then
    echo "Already present: $file"
  else
    echo "Downloading $file..."
    curl -fSL --progress-bar -o "$dest" "https://huggingface.co/${repo}/resolve/main/${file}"
  fi
}

create_ollama_model() {
  local name="$1" gguf="$2" shift 2
  local gguf_path="$MODELS_DIR/$gguf"

  if ollama list | awk '{print $1}' | grep -Fxq "$name"; then
    echo "Ollama model $name already exists."
    return
  fi

  echo "Creating Ollama model $name from $gguf..."
  cat > "$MODELS_DIR/.Modelfile" <<EOF
FROM $gguf_path
EOF
  ollama create "$name" -f "$MODELS_DIR/.Modelfile"
  rm -f "$MODELS_DIR/.Modelfile"
  echo "Created: $name"
}

# --- custom GGUF models ----------------------------------------------------
# Qwen3.6 27B IQ4_NL — ~14 GB, best quality-for-size coding model.
# IQ4_NL quality ≈ Q5_K_M but at IQ4 size. Dense 27B, all params active.
download_gguf HauhauCS/Qwen3.6-27B-Uncensored-HauhauCS-Aggressive \
  Qwen3.6-27B-Uncensored-HauhauCS-Aggressive-IQ4_NL.gguf
create_ollama_model "qwen36-27b-iq4nl" \
  Qwen3.6-27B-Uncensored-HauhauCS-Aggressive-IQ4_NL.gguf

# Qwen3.6 35B MoE IQ4_NL — ~16 GB, 3B active/token. Fast but MoE ceiling.
# Uncomment if you want the MoE option:
# download_gguf HauhauCS/Qwen3.6-35B-A3B-Uncensored-HauhauCS-Aggressive \
#   Qwen3.6-35B-A3B-Uncensored-HauhauCS-Aggressive-IQ4_NL.gguf
# create_ollama_model "qwen36-35b-moe" \
#   Qwen3.6-35B-A3B-Uncensored-HauhauCS-Aggressive-IQ4_NL.gguf

# --- standard Ollama models ------------------------------------------------
echo "Pulling standard Ollama models..."

# Qwen3 14B dense — ~9 GB, solid fallback, all 14B active
ollama pull qwen3:14b

# Gemma3 12B dense — ~8 GB, fast alternative
ollama pull gemma3:12b

echo
echo "All models ready."
echo "Installed:"
ollama list
