# ik_llama.cpp scripts

CPU-only local LLM inference on two machines using [ik_llama.cpp](https://github.com/Thireus/ik_llama.cpp) — a fork of llama.cpp with better AVX512/AVX2 kernels, optimized quantization formats (IQ\*, K\_P variants), and improved MoE scheduling.

## Hardware

| Machine | CPU | RAM | OS | Notes |
|---|---|---|---|---|
| HP ProBook (Ryzen) | AMD Ryzen 7 250 (Zen 5) | 32 GB | Windows 11 + WSL2 | AVX512 VNNI VBMI BF16 |
| Work PC (i9) | Intel Core i9-13900 (Raptor Lake) | 64 GB | Debian 13 | AVX2 only — no AVX512 |

Neither machine has a usable GPU. The ProBook's integrated AMD Radeon causes Vulkan OOM crashes — always use `-ngl 0`.

## Scripts

| Script | Purpose |
|---|---|
| `update.sh <machine>` | Download/update ik_llama.cpp (Linux/Windows) or brew upgrade llama.cpp (Mac) |
| `download-models.sh <machine>` | Download GGUF + mmproj files for i9/probook/macbook-air |
| `start.sh <machine> <mode>` | Start llama-server on any machine |
| `setup-agents.sh <machine>` | Auto-generate OpenCode/Pi provider config (parses start.sh) |
| `claude-providers.sh [provider] [model]` | Interactive picker & launch Claude Code with local or remote models (shows live n_ctx from `/props`) |
| `.secrets.example` | Template for `~/.secrets` (copy, chmod 600, fill in keys) |
| `ocg-proxy.py` | Anthropic ↔ OpenAI proxy for OpenCode Go (DeepSeek/Kimi/GLM + Claude Code) |
| `bench.sh <machine> <mode>` | Benchmark CPU thread settings with llama-bench (i9/probook) |
| `model-info.sh` | Show on-disk models, file sizes, mmproj status |
| `cleanup-models.sh i9` | Remove rejected/obsolete i9 GGUF files (dry-run by default) |
| `tune-i9.sh` | OS-level tuning for inference (cpu governor, THP, NUMA) |

`setup-agents.sh` writes the `ik-llama` provider for OpenCode when `opencode` is
installed and for Pi when `pi` is installed. Per-model context values are parsed
from `start.sh`. Vision models get `modalities: {input: [text, image], output: [text]}`.
OpenCode gets a conservative `limit.output` of
8192 tokens and:

```json
"compaction": {
  "auto": true,
  "prune": true,
  "reserved": 10000
}
```

This keeps OpenCode's context accounting aligned with the running
llama-server and starts compacting before the context window fills. If you start
llama-server with a non-default `IK_LLAMA_CTX_SIZE`, rerun setup with the same
override so OpenCode uses the correct context window:

```bash
IK_LLAMA_CTX_SIZE=32768 ./setup-agents.sh i9
IK_LLAMA_CTX_SIZE=32768 ./start.sh i9 qwopus35bq5km
```

Use `OPENCODE_OUTPUT_LIMIT=<tokens>` only to change OpenCode's reserved output
budget for context accounting. Use `OPENCODE_COMPACTION_RESERVED=<tokens>` only
when testing a different compaction buffer.

Pi config is written to `~/.pi/agent/models.json` with `api:
"openai-completions"`, `contextWindow`, and `maxTokens` for each local model.

### Quick start — ProBook

```bash
./update.sh probook
./download-models.sh probook
./setup-agents.sh probook
./start.sh probook qwen36u35b   # or: gemma qwen3coder glm47flash
```

Benchmark thread settings:

```bash
./bench.sh probook qwen36u35b
./bench.sh probook all
BENCH_THREADS="8 12 16" BENCH_THREADS_BATCH="8 12 16" ./bench.sh probook qwen36u35b
```

### Quick start — i9

```bash
sudo ./tune-i9.sh       # OS tuning (once per boot)
./update.sh i9
./download-models.sh i9
./setup-agents.sh i9
./start.sh i9 qwopus35bq5km   # or: qwen36u35bq6kp qwen36u27bq5kp qwopus35bq6k gemma4q5km supergemma4q4km glm47flashq5km qwen3codernext
./cleanup-models.sh i9     # dry-run obsolete GGUF cleanup
```

All i9 start modes default to `IK_LLAMA_THREADS=8` and `IK_LLAMA_THREADS_BATCH=24`. Override these only for explicit benchmark tests.

### Quick start — MacBook Air M4

```bash
brew install llama.cpp             # prerequisite (once)
./download-models.sh macbook-air
./setup-agents.sh macbook-air
./start.sh macbook-air qwen36u27b  # daily: 27B dense IQ4_XS, 32K ctx
./start.sh macbook-air qwen36u35b  # fallback: 35B MoE IQ4_NL, 16K ctx
```

All Mac modes use Metal GPU (`-ngl 99`) with 4 threads. Same HF repos and mmproj as i9.

For OpenCode edit loops where "Preparing write" feels slow, first try the same coder
model with a smaller active context:

```bash
IK_LLAMA_CTX_SIZE=32768 ./start.sh i9 qwopus35bq5km
```

Use the normal 64K default again when the session really needs the extra context.

Benchmark thread settings:

```bash
./bench.sh i9 qwopus35bq5km
./bench.sh i9 all
./bench.sh i9 qwen36
BENCH_THREADS="6 8" BENCH_THREADS_BATCH="24 32" ./bench.sh i9 qwopus35bq5km
```

To compare results, start with the generated `*-summary.tsv`, then inspect the referenced CSV files. Look for the highest prompt processing throughput (`pp`/prompt tok/s) that does not hurt generation throughput (`tg`/generation tok/s). For OpenCode, prefer the best overall balance over the absolute highest prompt-only score.

Summarize benchmark CSVs:

```bash
./summarize-bench.py bench-results/*-summary.tsv
```

`bench-results/` is ignored by git. Keep benchmark outputs local unless you explicitly want to share them for analysis.

## Models

### ProBook (32 GB RAM)

| Mode | Model | Size | Context | Vision | Notes |
|---|---|---|---|---|---|---|
| `qwen36u35b` | Qwen3.6-35B-A3B-Uncensored IQ4\_NL | ~16 GB | 32 K | yes | 35B MoE, 3B active |
| `gemma` | Gemma4-26B-A4B IQ4\_NL | ~13 GB | 64 K | yes | 26B MoE, 4B active |
| `qwen3coder` | Qwen3-Coder-30B-A3B Q3\_K\_M | ~14 GB | 64 K | no | 30B MoE, 3B active |
| `glm47flash` | GLM-4.7-Flash Q4\_K\_M | ~17 GB | 32 K | no | 30B MoE, 3B active, DeepSeek-V2 MLA |

### MacBook Air M4 (24 GB, Metal GPU)

| Mode | Model | Size | Context | Vision | Notes |
|---|---|---|---|---|---|
| `qwen36u27b` | Qwen3.6-27B-Uncensored IQ4\_XS | ~15 GB | 32 K | yes | 27B dense — all params active, daily driver |
| `qwen36u35b` | Qwen3.6-35B-A3B-Uncensored IQ4\_NL | ~16 GB | 16 K | yes | 35B MoE, 3B active — speed fallback |

Quick start:
```bash
brew install llama.cpp                      # prerequisite
./download-models.sh macbook-air             # pull GGUFs + mmproj
./setup-agents.sh macbook-air                # wire OpenCode + Pi
./start.sh macbook-air qwen36u27b            # daily driver: 27B dense, 32K ctx
```

The 27B dense IQ4\_XS is the smarter pick — all 27B params active vs 3B MoE for the 35B, and still fits at 32K context on 24 GB unified memory. Same HF repos and mmproj files as i9, just different quants (IQ4\_XS/IQ4\_NL for Mac vs K\_P for i9).

### i9 (64 GB RAM)

| Mode | Model | Size | Context | Vision | Notes |
|---|---|---|---|---|---|---|
| `qwen36u27bq5kp` | Qwen3.6-27B-Uncensored Q5\_K\_P | ~20 GB | 64 K | yes | 27B dense — all params active |
| `qwen36u35bq6kp` | Qwen3.6-35B-A3B-Uncensored Q6\_K\_P | ~31 GB | 128 K | yes | 35B MoE quality baseline |
| `qwopus35bq5km` | Qwopus3.6-35B-A3B Q5\_K\_M | ~25 GB | 128 K | yes | Reasoning-enhanced, tool-calling, vision |
| `qwopus35bq6k` | Qwopus3.6-35B-A3B Q6\_K | ~29 GB | 128 K | yes | Qwopus quality candidate |
| `gemma4q5km` | Gemma4-26B-A4B Q5\_K\_M | ~21 GB | 128 K | yes | 26B MoE, 4B active |
| `supergemma4q4km` | SuperGemma4-26B-Uncensored Q4\_K\_M | ~17 GB | 128 K | no | Uncensored Gemma4 fine-tune, text-only |
| `glm47flashq5km` | GLM-4.7-Flash Q5\_K\_M | ~20 GB | 64 K | no | 30B MoE, 3B active, coding-focused |
| `qwen3codernext` | Qwen3-Coder-Next 80B-A3B UD-Q3\_K\_M | ~36 GB | 64 K | no | 80B MoE, 3B active, coder-focused — test candidate |

GLM-4.7-Flash uses the DeepSeek-V2 MLA attention architecture and remains a useful comparison model, but measured slower than the Qwen MoE models on this i9. It scores ~59% on SWE-Bench Verified.

Qwen3-Coder-Next 80B-A3B (UD-Q3_K_M, ~36 GB) runs at ~93 pp tok/s and ~16 tg tok/s at 8/24 — about 25% slower than Qwopus due to the larger model footprint (same 3B active params, more bytes to stream). Still interactive; quality check pending.

## Binaries

Downloaded automatically by `update-*.sh`. Correct build for each machine:

| Machine | Build pattern |
|---|---|
| ProBook (Windows) | `*-bin-win-cpu-x64-avx512_vnni_vbmi_bf16.zip` |
| i9 (Linux) | `*-bin-ubuntu-x64-avx2.zip` |

Note: Use the generic `avx512_vnni_vbmi_bf16` build on ProBook, **not** `znver5` — the znver5 build crashes with Qwen3 MoE models.

## Flag reference

| Flag | Value | Purpose |
|---|---|---|
| `-ngl 0` | 0 | CPU-only, disables GPU offload |
| `--threads` | machine default | Generation threads. Override: `IK_LLAMA_THREADS` |
| `--threads-batch` | machine default | Prompt processing threads. Override: `IK_LLAMA_THREADS_BATCH` |
| `--parallel` | 1 | Keep one full-context slot and preserve prompt-cache locality. Override: `IK_LLAMA_PARALLEL` |
| `--ctx-size` | 32768–131072 | Context window |
| `IK_LLAMA_CTX_SIZE` | env override | Override the per-model context size for fast OpenCode edit loops |
| `IK_LLAMA_CRAM_MB` | env override | Override the per-model KV cache RAM limit |
| `-sps 0.5` | 0.5 | Slot prompt similarity for cache reuse |
| `-cram <MB>` | 8192–32768 | KV cache RAM limit |
| `-crs 0.5` | 0.5 | Cache similarity threshold |
| `-ctk q8_0` | q8_0 | Quantize K cache (requires flash attention) |
| `-ctv q8_0` | q8_0 | Quantize V cache (requires flash attention) |
| `-dt 0.1` | 0.1 | Defragmentation threshold |
| `--host 0.0.0.0` | — | Listen on all interfaces (required for WSL2) |
| `--jinja` | — | Enable Jinja templates (required for tool calling) |
| `-rea off` | off | Disable thinking/reasoning mode |
| `--temp` / `--top-p` / `--top-k` | 0.2 / 0.8 / 20 | Conservative i9 Qwen sampling for OpenCode tool-call JSON reliability. Override: `IK_LLAMA_TEMP`, `IK_LLAMA_TOP_P`, `IK_LLAMA_TOP_K` |
| `-v` | — | Verbose output (shows tok/s, timing) |
| `--mlock` | — | Lock model in RAM (i9 only, prevents swapping) |
| `--mmproj <file>` | — | Multimodal projector GGUF for vision (Qwen3.6, Qwopus3.6, Gemma4) |

### Qwen3 sampling

```
--temp 0.6 --top-p 0.95 --top-k 20
```

Recommended by the Qwen3 technical report for thinking/chat mode.

## OS tuning (i9)

Run `sudo ./tune-i9.sh` once per boot to apply:

- **CPU governor → performance** — prevents frequency scaling latency on the single-token generation path
- **Transparent Huge Pages → madvise** — lets llama-server opt into 2MB pages without wasting them on other processes
- **NUMA balancing → off** — no benefit on single-socket; avoids kernel migration overhead

All changes revert on reboot. The script is idempotent — safe to re-run.

## Performance

### ProBook (Ryzen 7 250, Zen 5, AVX512)

- Prompt eval: ~44 tok/s
- Generation: ~7 tok/s
- First message with long system prompt: ~5 min (cache cold)
- Subsequent messages: ~2.5 s (cache hit)

### i9-13900 (Raptor Lake, AVX2)

- `qwen36u35bq6kp`: ~122.8 prompt tok/s, ~22.6 gen tok/s at `8/24`; sole retained Qwen3.6 35B-A3B HauhauCS quant (Q4/Q5/Q8 replaced by Qwopus).
- `qwen3coderq5km`: ~110.6 prompt tok/s, ~29.8 gen tok/s at `8/24`; best generation row was ~30.0 gen tok/s at `8/32`, but prompt ingestion dropped to ~90.7 tok/s.
- `qwen3coderq6k`: ~102.1 prompt tok/s, ~25.6 gen tok/s at `8/24`.
- `qwen3coderq8`: ~105.8 prompt tok/s, ~20.7 gen tok/s at `8/24`.
- 32B dense candidates were only ~13.5–14.2 prompt tok/s and ~3.0–3.6 gen tok/s.
- Qwopus Q5_K_M / Q6_K: not yet benchmarked on this i9 (same `qwen35moe` arch — expect similar throughput to HauhauCS Qwen3.6-35B-A3B).

### i9 speed notes

The i9 is CPU-only and AVX2-only, so dense 20 GB-class models are mostly memory-bandwidth bound. `qwen36u27bq5kp` is the retained dense quality option, but it is not interactive. Qwen3.6-35B-A3B Q4/Q5/Q8 HauhauCS quants are replaced by Qwopus3.6-35B-A3B Q5_K_M and Q6_K. Qwen3-Coder A3B failed manual quality even at Q8.

- Test `qwopus35bq5km` first for daily use. Keep `qwopus35bq6k` and `qwen36u35bq6kp` for quality checks.
- Keep context as low as the task allows; 64K/128K context improves long sessions but slows prompt processing and grows KV memory.
- Use `IK_LLAMA_THREADS=8` and `IK_LLAMA_THREADS_BATCH=24` as the default i9 startup point.
- Avoid `IK_LLAMA_THREADS=10` and `12`; benchmarks were consistently worse than `6` and `8`.
- Keep `qwen36u27bq5kp` for quality checks only. It is too slow for normal OpenCode loops.

### Completed i9 benchmark notes

The completed i9 `llama-bench` runs point to `8/24` as the best default thread setting. `8/32` is usually close, but not better enough to justify changing the default. The dense "fast" Qwen models were not actually fast on this AVX2 CPU.

Best observed rows:

| Use | Mode | Threads | Prompt tok/s | Gen tok/s | Notes |
|---|---|---|---:|---:|---:|---|
| Qwen3.6 MoE quality baseline | `qwen36u35bq6kp` | 8/24 | ~122.8 | ~22.6 | Sole retained HauhauCS Qwen3.6 35B quant |
| Rejected coder Q8 | `qwen3coderq8` | 8/24 | ~105.8 | ~20.7 | Manual quality failed despite highest tested quant |
| Rejected coder Q6 | `qwen3coderq6k` | 8/24 | ~102.1 | ~25.6 | Manual quality did not justify keeping it |
| Rejected coder Q5 | `qwen3coderq5km` | 8/24 | ~110.6 | ~29.8 | Responsive, but manual quality failed |
| Rejected dense Qwen3 | `qwen332bq4km`/`qwen332bq5km` | 8/24 | ~13.5–13.7 | ~3.1–3.6 | Too slow for OpenCode daily use |
| Rejected dense coder | `qwen25coder32bq4km`/`qwen25coder32bq5km` | 8/24 | ~14.1 | ~3.1–3.5 | Too slow for OpenCode daily use |
| Rejected coder Q4 | `qwen3coderq4` | 8/24 | ~114 | ~33 | Responsive but failed manual quality |
| Rejected coder Q3 | `qwen3coderq3` | 8/24 | ~112 | ~40.5 | Responsive but failed manual quality |
| Coder-Next candidate | `qwen3codernext` | 8/24 | ~93 | ~16 | 80B total, 3B active; 25% slower than Qwopus; quality pending |
| General fallback | `supergemma4q4km` | 8/24–8/32 | ~129 | ~23 | Decent non-Qwen fallback |
| GLM fallback | `glm47flashq5km` | 8/24 | ~92 | ~21 | Slower than expected here |
| Dense quality check | `qwen36u27bq5kp` | 8/24 | ~21 | ~3 | Quality-only, not interactive |

Rejected fast-tier candidates:

- `qwen3fast:q5` and `qwen3fast:q4` were much slower than the MoE models.
- `qwen38b:q5` and `qwen38b:q4` were faster than `qwen3fast`, but still not competitive with Qwen3-Coder MoE.
- `qwen332b:q4/q5` and `qwen25coder32b:q4/q5` were all around 3–3.6 gen tok/s.
- `qwen3coderq3` through `qwen3coderq8` were responsive enough, but not useful in manual coding tests.

The benchmark script accepts explicit quantized presets like `qwopus35b:q5km`, but the canonical script/OpenCode names include the quantization suffix.

The active benchmark set is `qwen36u35bq6kp`, `qwen36u27bq5kp`, `qwopus35bq5km`, `qwopus35bq6k`, `gemma4q5km`, `supergemma4q4km`, and `glm47flashq5km`.

The `all` and `qwen36` benchmark groups use only the active model list. `qwen36` runs the full Qwen3.6 comparison.

For OpenCode, keep `IK_LLAMA_THREADS=8` and `IK_LLAMA_THREADS_BATCH=24` as the default. The new Qwen3.6 Q5/Q6/Q8 results confirmed that `8/32` loses a lot of prompt throughput without meaningful generation gain. `6/24` can be useful only when prompt ingestion dominates and generation speed matters less.

For 128K OpenCode sessions on the i9 with `qwen36u35bq6kp`, start with:

```bash
./start.sh i9 qwen36u35bq6kp
OPENCODE_COMPACTION_RESERVED=24000 ./setup-agents.sh i9
```

Raise `IK_LLAMA_CRAM_MB` to `28672` only if RAM stays comfortable. Avoid
`32768` with Q6 unless you have verified there is no swap pressure: the Q6 model
plus a 32 GB KV cap leaves too little headroom on a 64 GB machine with
`--mlock`.

If OpenCode shows "Preparing write" while CPU usage stays low, suspect OpenCode-side
helpers before changing CPU threads. Disable OpenCode MCP/plugins for an A/B test:

```bash
../tools/opencode-local-speed.sh status
../tools/opencode-local-speed.sh fast
opencode mcp list
```

With local ik_llama.cpp, keep `context-mode` disabled unless you explicitly need it:

```bash
CONTEXT_MODE_ENABLE_OPENCODE=1 ../tools/context-mode-init.sh
```

To free disk space after benchmarking rejected candidates:

```bash
./cleanup-models.sh i9
./cleanup-models.sh i9 --apply
```

The cleanup list includes the rejected Qwen3-Coder Q3/Q4/Q5/Q6/Q8 files.

## Key lessons

1. **`-ngl 0` always** — integrated GPU causes Vulkan OOM crashes
2. **Quantized KV cache requires flash attention on** — `-ctv q8_0` is incompatible with `--flash-attn off`; ik_llama.cpp enables FA by default which is correct
3. **Avoid `_XL` variants** — incompatible quantization format with ik_llama.cpp
4. **ProBook: use generic AVX512 build** — `znver5` crashes with MoE models
5. **i9 has no AVX512** — despite being 13th gen Raptor Lake; use AVX2 build only
6. **Prompt cache is critical** — first message is slow; subsequent messages hit cache and are fast
7. **`-rea off`** — disables thinking mode; cuts response time 50–80% for coding tasks
8. **MoE active-parameter ceiling** — 3B active params is the real intelligence limit regardless of quantization level; for more intelligence use a dense model like `qwen36u27bq5kp`
9. **GLM-4.7-Flash is not faster than Qwen3-Coder on this i9** — despite MLA, measured throughput was lower than the Qwen MoE models
10. **Vision requires mmproj** — Qwen3.6, Qwopus3.6, and Gemma4 models support image input when `--mmproj <file>.gguf` is passed to llama-server. The mmproj file is downloaded alongside the model GGUF. SuperGemma4 and GLM-4.7-Flash are text-only.
11. **One server slot per active agent** — `--parallel 2` divides the configured context between slots, while unrelated sessions evict each other's cached prefixes. Keep the default `IK_LLAMA_PARALLEL=1`; use separate server instances when concurrent agents need full context and stable cache reuse.

## Debian 12 / GLIBC 2.36 compatibility

Homebrew binary bottles are built on Ubuntu 24.04 (GLIBC 2.38). They won't run
on Debian 12 (GLIBC 2.36). Affected: node, pi, and any brew formula that ships
a compiled binary.

**Symptoms:**
```
/home/linuxbrew/.linuxbrew/opt/node/bin/node: /lib/x86_64-linux-gnu/libm.so.6:
version `GLIBC_2.38' not found
```

**Fix — wrapper script (no root, no npm):**
`pi-install.sh` auto-detects the glibc issue and creates `~/.local/bin/pi`
— a wrapper that runs pi's JS via the system node, bypassing brew's broken
node. Brew still manages pi upgrades; the wrapper auto-picks the latest version.

For other brew formulae with the same issue, either build from source
(`brew install --build-from-source <formula>`) or install via the system package
manager instead of brew.

Ubuntu 24.04 and macOS are unaffected — brew bottles work natively.
