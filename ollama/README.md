# Ollama on MacBook Air M4

Scripts for Apple Silicon local inference using Ollama with Metal GPU acceleration.

## Setup

```bash
../tools/ollama-install.sh
./download-models-mac.sh
./setup-opencode-mac.sh
```

## Speed guidance

For a 24 GB MacBook Air M4, Ollama is the pragmatic default for OpenCode: simple model management, OpenAI-compatible API, and Metal acceleration without maintaining a separate llama.cpp build. Ollama uses llama.cpp-derived GGUF inference underneath, so the raw throughput difference is usually smaller than the difference caused by model size, quantization, and context length.

Use direct llama.cpp when you want maximum control over flags, repeatable benchmarking, or slightly better raw throughput. It is also useful when you need a GGUF or KV-cache option that Ollama does not expose yet.

Practical defaults:

- Use 7B–14B dense models for speed and low heat.
- Use the 27B IQ4_NL model for quality, not for maximum tokens/sec.
- Keep context at 8K–16K for fast interactive work; raise it only for long agent sessions.
- Check `ollama ps` while a model is loaded; best performance means the model is fully on GPU/Metal rather than partially offloaded to CPU.
- The MacBook Air is fanless, so sustained long generations may throttle. Smaller models usually feel faster over real coding sessions than a larger model that starts fast and then heats up.

Ollama supports context length through `OLLAMA_CONTEXT_LENGTH` when serving. Larger context costs memory and speed, so do not set 64K globally unless the active workflow needs it.
