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
| `update-probook.sh` | Download/update ik_llama.cpp Windows binary |
| `update-i9.sh` | Download/update ik_llama.cpp Linux binary |
| `download-models-probook.sh` | Download GGUF models to `/mnt/c/data/llm/models` |
| `download-models-i9.sh` | Download GGUF models to `/data/llm/models` |
| `cleanup-models-i9.sh` | Remove rejected/obsolete i9 GGUF files (dry-run by default) |
| `start-probook.sh <mode>` | Start llama-server on ProBook (runs from WSL2) |
| `start-i9.sh <mode>` | Start llama-server on i9 |
| `bench-i9.sh <mode>` | Benchmark i9 CPU thread settings with llama-bench |
| `bench-probook.sh <mode>` | Benchmark ProBook CPU thread settings with Windows llama-bench.exe |
| `setup-opencode-probook.sh` | Auto-generate OpenCode provider config from start script |
| `setup-opencode-i9.sh` | Auto-generate OpenCode provider config from start script |
| `tune-i9.sh` | OS-level tuning for inference (cpu governor, THP, NUMA) |

### Quick start — ProBook

```bash
./update-probook.sh
./download-models-probook.sh
./setup-opencode-probook.sh
./start-probook.sh qwen36u35b   # or: gemma qwen3coder glm47flash
```

Benchmark thread settings:

```bash
./bench-probook.sh qwen36u35b
./bench-probook.sh all
BENCH_THREADS="8 12 16" BENCH_THREADS_BATCH="8 12 16" ./bench-probook.sh qwen36u35b
```

### Quick start — i9

```bash
sudo ./tune-i9.sh       # OS tuning (once per boot)
./update-i9.sh
./download-models-i9.sh
./setup-opencode-i9.sh
./start-i9.sh qwen36u35bq5kp   # or: qwen36u35bq6kp qwen36u35bq8kp qwen36u35bq4kp qwen36u27bq5kp gemma4q5km supergemma4q4km glm47flashq5km
./cleanup-models-i9.sh     # dry-run obsolete GGUF cleanup
```

All i9 start modes default to `IK_LLAMA_THREADS=8` and `IK_LLAMA_THREADS_BATCH=24`. Override these only for explicit benchmark tests.

For OpenCode edit loops where "Preparing write" feels slow, first try the same coder
model with a smaller active context:

```bash
IK_LLAMA_CTX_SIZE=32768 ./start-i9.sh qwen36u35bq5kp
```

Use the normal 64K default again when the session really needs the extra context.

Benchmark thread settings:

```bash
./bench-i9.sh qwen36u35bq5kp
./bench-i9.sh all
./bench-i9.sh qwen36
BENCH_THREADS="6 8" BENCH_THREADS_BATCH="24 32" ./bench-i9.sh qwen36u35bq5kp
```

To compare results, start with the generated `*-summary.tsv`, then inspect the referenced CSV files. Look for the highest prompt processing throughput (`pp`/prompt tok/s) that does not hurt generation throughput (`tg`/generation tok/s). For OpenCode, prefer the best overall balance over the absolute highest prompt-only score.

Summarize benchmark CSVs:

```bash
./summarize-bench.py bench-results/*-summary.tsv
```

`bench-results/` is ignored by git. Keep benchmark outputs local unless you explicitly want to share them for analysis.

## Models

### ProBook (32 GB RAM)

| Mode | Model | Size | Context | Notes |
|---|---|---|---|---|
| `qwen36u35b` | Qwen3.6-35B-A3B-Uncensored IQ4\_NL | ~16 GB | 32 K | 35B MoE, 3B active |
| `gemma` | Gemma4-26B-A4B IQ4\_NL | ~13 GB | 64 K | 26B MoE, 4B active |
| `qwen3coder` | Qwen3-Coder-30B-A3B Q3\_K\_M | ~14 GB | 64 K | 30B MoE, 3B active |
| `glm47flash` | GLM-4.7-Flash Q4\_K\_M | ~17 GB | 32 K | 30B MoE, 3B active, DeepSeek-V2 MLA |

### i9 (64 GB RAM)

| Mode | Model | Size | Context | Notes |
|---|---|---|---|---|
| `qwen36u27bq5kp` | Qwen3.6-27B-Uncensored Q5\_K\_P | ~20 GB | 64 K | 27B dense — all params active |
| `qwen36u35bq4kp` | Qwen3.6-35B-A3B-Uncensored Q4\_K\_P | ~21 GB | 64 K | 35B MoE, 3B active |
| `qwen36u35bq5kp` | Qwen3.6-35B-A3B-Uncensored Q5\_K\_P | ~28 GB | 64 K | Next likely quality/speed default |
| `qwen36u35bq6kp` | Qwen3.6-35B-A3B-Uncensored Q6\_K\_P | ~31 GB | 64 K | Main quality candidate |
| `qwen36u35bq8kp` | Qwen3.6-35B-A3B-Uncensored Q8\_K\_P | ~44 GB | 32 K default | Quality ceiling; memory-tight on 64 GB |
| `gemma4q5km` | Gemma4-26B-A4B Q5\_K\_M | ~21 GB | 128 K | 26B MoE, 4B active |
| `supergemma4q4km` | SuperGemma4-26B-Uncensored Q4\_K\_M | ~17 GB | 128 K | Uncensored Gemma4 fine-tune |
| `glm47flashq5km` | GLM-4.7-Flash Q5\_K\_M | ~20 GB | 64 K | 30B MoE, 3B active, coding-focused |

GLM-4.7-Flash uses the DeepSeek-V2 MLA attention architecture and remains a useful comparison model, but measured slower than the Qwen MoE models on this i9. It scores ~59% on SWE-Bench Verified.

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
| `--threads` | 8 | Generation threads (P-cores only). Override: `IK_LLAMA_THREADS` |
| `--threads-batch` | 24 | Prompt processing threads. Override: `IK_LLAMA_THREADS_BATCH` |
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
| `-v` | — | Verbose output (shows tok/s, timing) |
| `--mlock` | — | Lock model in RAM (i9 only, prevents swapping) |

### Qwen3 YaRN (context extension)

```
--rope-scaling yarn --yarn-orig-ctx 32768 --yarn-beta-fast 32 --yarn-beta-slow 1
```

Applied to Qwen3-family models when using contexts beyond 32K.

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

- `qwen36u35bq4kp`: ~126.4 prompt tok/s, ~27.2 gen tok/s at `8/24`; fastest retained Qwen3.6 35B-A3B option.
- `qwen36u35bq5kp`: ~126.2 prompt tok/s, ~24.7 gen tok/s at `8/24`; best higher-quant daily candidate if quality improves over Q4.
- `qwen36u35bq6kp`: ~122.8 prompt tok/s, ~22.6 gen tok/s at `8/24`; quality candidate, but slower than Q5.
- `qwen36u35bq8kp`: ~113.4 prompt tok/s, ~17.4 gen tok/s at `8/24`; quality ceiling only, not the default.
- `qwen3coderq5km`: ~110.6 prompt tok/s, ~29.8 gen tok/s at `8/24`; best generation row was ~30.0 gen tok/s at `8/32`, but prompt ingestion dropped to ~90.7 tok/s.
- `qwen3coderq6k`: ~102.1 prompt tok/s, ~25.6 gen tok/s at `8/24`.
- `qwen3coderq8`: ~105.8 prompt tok/s, ~20.7 gen tok/s at `8/24`.
- 32B dense candidates were only ~13.5–14.2 prompt tok/s and ~3.0–3.6 gen tok/s.

### i9 speed notes

The i9 is CPU-only and AVX2-only, so dense 20 GB-class models are mostly memory-bandwidth bound. `qwen36u27bq5kp` is the retained dense quality option, but it is not interactive. Qwen3-Coder A3B failed manual quality even at Q8, so the next responsive-quality track is Qwen3.6 35B-A3B with higher HauhauCS K_P quants. Speed benchmarks do not decide the default by themselves; manual code quality does.

- Test `qwen36u35bq5kp` first for responsiveness/quality. Keep `qwen36u35bq6kp` and `qwen36u35bq8kp` only if manual quality clearly beats Q5. Use Q8 at 32K first because it is memory-tight and much slower.
- Keep context as low as the task allows; 64K/128K context improves long sessions but slows prompt processing and grows KV memory.
- Use `IK_LLAMA_THREADS=8` and `IK_LLAMA_THREADS_BATCH=24` as the default i9 startup point.
- Avoid `IK_LLAMA_THREADS=10` and `12`; benchmarks were consistently worse than `6` and `8`.
- Keep `qwen36u27bq5kp` for quality checks only. It is too slow for normal OpenCode loops.

### Completed i9 benchmark notes

The completed i9 `llama-bench` runs point to `8/24` as the best default thread setting. `8/32` is usually close, but not better enough to justify changing the default. The dense "fast" Qwen models were not actually fast on this AVX2 CPU.

Best observed rows:

| Use | Mode | Threads | Prompt tok/s | Gen tok/s | Notes |
|---|---|---:|---:|---:|---|
| Fast retained Qwen3.6 MoE | `qwen36u35bq4kp` | 8/24 | ~126.4 | ~27.2 | Fastest retained 35B-A3B option; baseline to beat on quality |
| Higher-quant Qwen3.6 candidate | `qwen36u35bq5kp` | 8/24 | ~126.2 | ~24.7 | Best current daily candidate if manual quality beats Q4 |
| Higher-quant Qwen3.6 quality check | `qwen36u35bq6kp` | 8/24 | ~122.8 | ~22.6 | Slower than Q5; keep only if quality is noticeably better |
| Qwen3.6 quality ceiling | `qwen36u35bq8kp` | 8/24 | ~113.4 | ~17.4 | Too slow for default; useful only as a quality reference |
| Rejected coder Q8 | `qwen3coderq8` | 8/24 | ~105.8 | ~20.7 | Manual quality failed despite highest tested quant |
| Rejected coder Q6 | `qwen3coderq6k` | 8/24 | ~102.1 | ~25.6 | Manual quality did not justify keeping it |
| Rejected coder Q5 | `qwen3coderq5km` | 8/24 | ~110.6 | ~29.8 | Responsive, but manual quality failed |
| Rejected dense Qwen3 | `qwen332bq4km`/`qwen332bq5km` | 8/24 | ~13.5–13.7 | ~3.1–3.6 | Too slow for OpenCode daily use |
| Rejected dense coder | `qwen25coder32bq4km`/`qwen25coder32bq5km` | 8/24 | ~14.1 | ~3.1–3.5 | Too slow for OpenCode daily use |
| Rejected coder Q4 | `qwen3coderq4` | 8/24 | ~114 | ~33 | Responsive but failed manual quality |
| Rejected coder Q3 | `qwen3coderq3` | 8/24 | ~112 | ~40.5 | Responsive but failed manual quality |
| General fallback | `supergemma4q4km` | 8/24–8/32 | ~129 | ~23 | Decent non-Qwen fallback |
| GLM fallback | `glm47flashq5km` | 8/24 | ~92 | ~21 | Slower than expected here |
| Dense quality check | `qwen36u27bq5kp` | 8/24 | ~21 | ~3 | Quality-only, not interactive |

Rejected fast-tier candidates:

- `qwen3fast:q5` and `qwen3fast:q4` were much slower than the MoE models.
- `qwen38b:q5` and `qwen38b:q4` were faster than `qwen3fast`, but still not competitive with Qwen3-Coder MoE.
- `qwen36u35b:iq4nl` did not beat `qwen36u35b:q4kp`.
- `qwen332b:q4/q5` and `qwen25coder32b:q4/q5` were all around 3–3.6 gen tok/s.
- `qwen3coderq3` through `qwen3coderq8` were responsive enough, but not useful in manual coding tests.

The benchmark script accepts explicit quantized presets like `qwen36u35b:q5kp`, `qwen36u35b:q6kp`, and `qwen36u35b:q8kp`, but the canonical script/OpenCode names include the quantization suffix.

The active benchmark set is `qwen36u35bq4kp`, `qwen36u35bq5kp`, `qwen36u35bq6kp`, `qwen36u35bq8kp`, `qwen36u27bq5kp`, `gemma4q5km`, `supergemma4q4km`, and `glm47flashq5km`.

The `all` and `qwen36` benchmark groups use only the active model list. `qwen36` runs the full Qwen3.6 comparison.

For OpenCode, keep `IK_LLAMA_THREADS=8` and `IK_LLAMA_THREADS_BATCH=24` as the default. The new Qwen3.6 Q5/Q6/Q8 results confirmed that `8/32` loses a lot of prompt throughput without meaningful generation gain. `6/24` can be useful only when prompt ingestion dominates and generation speed matters less.

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
./cleanup-models-i9.sh
./cleanup-models-i9.sh --apply
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
