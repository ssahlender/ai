# MLX (MacBook Air M4, 24 GB)

[MLX](https://github.com/ml-explore/mlx-lm) — Apple's native ML framework — as a
second engine alongside the existing ik_llama.cpp/llama.cpp + Metal setup in
`../ik-llama/`. Not a replacement for that pipeline's structure, just a different
backend: same idea (`start.sh`/`setup-agent.sh` wiring OpenCode/Pi), different
runtime, model pulled straight from Hugging Face instead of a local GGUF.

## Setup

Install via the shared `tools/` install/update scripts (same pattern as every
other CLI tool in this repo):

```bash
cd ../tools
./mlx-lm-install.sh      # uv tool install mlx-lm
```

`mlx-lm` is also in `tools/update-all.sh`'s `UPDATE_TOOLS` list, so
`./update-all.sh` keeps it current alongside everything else. No Hugging Face
login needed — `mlx-community` and `LiquidAI` repos are public.

## Scripts

| Script | Purpose |
|---|---|
| `start.sh <mode>` | Start `mlx_lm.server` (OpenAI-compatible API) for a model in the `MODES` table |
| `stop.sh` | Stop the running server (`fuser -k` on `MLX_PORT`) |
| `setup-agent.sh` | Wire OpenCode + Pi provider config, parsed from `start.sh`'s `MODES` table |
| `bench.sh <hf-repo> [max-tokens]` | One-shot `mlx_lm.generate` throughput test, no server |

### Quick start

```bash
./start.sh qwen38-27b          # foreground; Ctrl-C to stop, or use ./stop.sh from another shell
./setup-agent.sh               # in another shell, once the server is up
```

`setup-agent.sh` writes provider `mlx` into `~/.config/opencode/opencode.json` /
`~/.local/share/opencode/auth.json` and `~/.pi/agent/models.json`, pointing at
`http://localhost:$MLX_PORT/v1` (default port `8090` — deliberately different
from ik-llama's `9080` so both can run side by side for comparison, memory
permitting). Model shortname in OpenCode/Pi: `mlx/qwen38-27b`.

### Environment overrides

| Var | Default | Purpose |
|---|---|---|
| `MLX_PORT` | `8090` | Server port |
| `MLX_REASONING_EFFORT` | `low` | Qwen3.8 chat-template reasoning level (`low`/`medium`/`xhigh`) — see below |
| `MLX_MAX_TOKENS` | `4096` | Default max generation tokens |

## Models

| Mode | Model | Size (4-bit) | Context | Notes |
|---|---|---:|---:|---|
| `qwen38-27b` | `mlx-community/Qwen3.8-27B-4bit` | ~15.5 GB | 128K (native) | Dense daily-driver candidate — see Results below |

## Key lesson: `reasoning_effort`

Qwen3.8-27B's chat template defaults to `reasoning_effort: xhigh` and will burn
an entire token budget on `<think>` before answering — with a short `--max-tokens`
it truncates before ever producing a real answer. `start.sh` sets
`--chat-template-args '{"reasoning_effort": "low"}'` by default (override with
`MLX_REASONING_EFFORT`) — confirmed via `mlx_lm.generate --chat-template-config`
to give clean, complete answers with only brief thinking.

## Results — 2026-09-13

Tested with `mlx_lm.generate` (no server yet at that point) against current
(Sept 2026) models, not the ones originally picked for this comparison —
`mlx-community` had already moved from Qwen3.6 to Qwen3.8 by the time this ran.

| Model | Size | Prompt tok/s | Gen tok/s | Peak mem | Notes |
|---|---:|---:|---:|---:|---|
| `mlx-community/Qwen3-14B-4bit` | ~8 GB | 20.5 | 12.4 | 8.4 GB | Previous-gen dense, baseline sanity check |
| `mlx-community/Qwen3.8-27B-4bit` | ~15.5 GB | 22.7–37.9 | **6.5–6.6** | 15.5 GB | Official successor to the `HauhauCS` Qwen3.6-27B fine-tune used as `qwen36u27b` in `../ik-llama/`. Needs `reasoning_effort: low` (see above). |
| `LiquidAI/LFM2-24B-A2B-MLX-4bit` | ~13.5 GB | 58.1 | 63.9 | 13.5 GB | 10x faster (2B active MoE) but noticeably lower quality — factually loose description of MoE routing in its own test answer. Vendor explicitly says it's not optimized for coding; it's a fast tool-dispatch/router model for agent inner loops, not a chat/coding daily driver. Tested, then **removed** — not a fit for this use case. |

**Verdict: `Qwen3.8-27B-4bit` is the daily-driver upgrade**, replacing the Qwen3.6-27B
fine-tune. Confirmed by public benchmarks too — big agentic/coding jump over 3.6
(SWE-bench Pro 53.5→61.7, DeepSWE 1.1 13.3→42.2). LFM2 was a different tool for a
different job (fast tool selection) — cache removed after the test (`rm -rf
~/.cache/huggingface/hub/models--LiquidAI--LFM2-24B-A2B-MLX-4bit`), 12 GB freed.

Tradeoff: 6.5 tok/s generation is slower than the i9's ~26 tok/s or ProBook's ~13 tok/s
for a comparable dense/MoE model — that's the M4 base chip's unified-memory bandwidth
ceiling for a 15.5 GB 4-bit model, not an MLX-vs-llama.cpp gap (no llama.cpp/Metal
number has been captured on the Mac for a direct comparison — still open, see below).

`mlx_lm.server` smoke-tested via `curl /v1/chat/completions` — OpenAI-compatible
API confirmed working with `reasoning_effort: low` applied server-wide.

## Engine comparison — 2026-09-13

Before committing to raw `mlx_lm.server`, ran the same Qwen3.8-27B model through
three engines, all on this Mac:

| Engine | Model file | Size | Prompt tok/s | Gen tok/s | Notes |
|---|---|---:|---:|---:|---|
| **Raw `mlx_lm.server`** | `mlx-community/Qwen3.8-27B-4bit` (MLX) | 15.5 GB | 22.7–37.9 | **6.5–6.6** | Winner — fits with headroom, fastest |
| Ollama 0.33.3 + MLX backend | `qwen3.8:27b-mlx` | 18 GB | 12.7 | 2.69 | Ollama ships MLX as a hard dependency now (not just a preview flag) and manages context safely (bounded to 4K by default via "vram-based default context"), but memory pressure (only 17.8 GB of 24 GB available to the GPU) made it 2.4x slower than raw MLX |
| llama.cpp `llama-server` | `unsloth/Qwen3.8-27B-UD-Q4_K_XL.gguf` | 17.6 GB | 23.46 | 4.56 | Unsloth's "dynamic" Q4_K_XL quant is bigger than the MLX 4-bit build — OOM'd (`ggml_metal_synchronize: Insufficient Memory`) at 8K+ context on this 24 GB machine, only worked reduced to 4K context. Needed `--parallel 1` (ik-llama's own documented lesson) to even get that far — default 4 slots multiply KV cache 4x and OOM immediately. |

**Raw `mlx_lm.server` wins on both speed and memory headroom.** The smaller MLX
quant (15.5 GB vs. 17.6 GB GGUF) is what lets it fit on 24 GB with room for a
real context window at all — the other two paths are memory-constrained on this
specific machine, not just slower. Ollama's own research context (checked
2026-09-13): even the general MLX-vs-llama.cpp comparisons out there report
MLX 15–25% faster for 14B+ models and Ollama itself switched its Apple Silicon
backend to MLX in March 2026 (stable/default since v0.30, May 2026) — this test
confirms that holds for this exact model on this exact machine.

Ollama and its test model were removed after the comparison (`brew uninstall
ollama`, `ollama rm qwen3.8:27b-mlx`) — not part of the chosen stack. The
Unsloth GGUF (17.6 GB) was deleted too.

### Known risk: accepted, with mitigation

`mlx_lm.server` has open upstream issues about unbounded KV-cache growth during
long agentic sessions, up to a macOS kernel panic on a 96 GB Mac Studio after
~58K tokens ([ml-explore/mlx-lm#883](https://github.com/ml-explore/mlx-lm/issues/883),
[#1390](https://github.com/ml-explore/mlx-lm/issues/1390),
[#1672](https://github.com/ml-explore/mlx-lm/issues/1672)) — root cause: no
`--max-kv-size` support on the server ([#615](https://github.com/ml-explore/mlx-lm/issues/615),
still open). This Air has 24 GB, less headroom than that Mac Studio. Accepted
for now since it only bites at very long (50K+ token) unbounded sessions — mitigate by
restarting the server between long OpenCode sessions rather than leaving it up
indefinitely, and revisit if `--max-kv-size` lands on the server.

### Not yet done

- `reasoning_effort: low` only smoke-tested on short prompts via CLI and one curl
  request — not yet run through an actual OpenCode coding/tool-call session.
- Not yet decided: keep `qwen36u27b` (llama.cpp/GGUF, `../ik-llama/`) as the
  OpenCode daily driver and treat MLX/Qwen3.8-27B as a second option, or switch
  the daily driver over and update `../ik-llama/README.md`'s Mac table
  accordingly.
