# MLX test run (MacBook Air M4, 24 GB)

One-off comparison: does Apple's native [MLX](https://github.com/ml-explore/mlx-lm)
framework beat the existing ik_llama.cpp/llama.cpp + Metal setup in `../ik-llama/`?
Not a replacement — that pipeline is the daily driver. This is a Sunday-afternoon
second opinion on engine choice, using pre-quantized models from the `mlx-community`
org on Hugging Face (same architecture families as the ik-llama lineup, so results
are directly comparable).

## Setup

```bash
uv venv .venv && source .venv/bin/activate   # or: pip install --user
uv pip install mlx-lm huggingface_hub
huggingface-cli login                        # uses your HF account/token
```

## Models to test

| Model | Size (4-bit) | Why |
|---|---:|---|
| `mlx-community/Qwen3-30B-A3B-Instruct-2507-4bit` | ~17 GB | Same family/size class as `qwen3coder30b` and `qwen36u35b` — direct MLX-vs-llama.cpp comparison on a MoE model |
| `mlx-community/Qwen3-14B-4bit` | ~8 GB | Dense sanity check — smaller footprint, leaves headroom to see if a dense model at a smaller size beats the MoE on quality per the same "3B active params ceiling" lesson noted in `../ik-llama/README.md` |

Both fit comfortably in 24 GB unified memory alongside macOS + a browser.

## Running it

```bash
./bench.sh mlx-community/Qwen3-30B-A3B-Instruct-2507-4bit
./bench.sh mlx-community/Qwen3-14B-4bit
```

`mlx_lm.generate` prints prompt tok/s and generation tok/s at the end of each run —
`bench.sh` just wraps it with a fixed prompt/max-tokens so runs are comparable.

## What to compare against

From `../ik-llama/README.md` (Metal, `-ngl 99`, 4 threads):

| Mode | Size | Context | Notes |
|---|---:|---:|---|
| `qwen36u27b` | ~15 GB | 32K | 27B dense, daily driver |
| `qwen36u35b` | ~16 GB | 16K | 35B MoE, 3B active, vision |
| `qwen3coder30b` | ~17 GB | 32K | 30B MoE, coding |

No llama.cpp/ik_llama tok/s numbers are recorded yet for the Mac in that README —
worth capturing while doing this comparison so both engines have numbers side by side.

## After running

Log results (tok/s prompt/gen, subjective quality) back into this README or into
`../ik-llama/README.md`'s Mac section — whichever engine wins becomes the new
recommendation for daily use.

## Results — 2026-09-13

Actual test used current (Sept 2026) models instead of the ones listed above, since
those are already a generation behind — `mlx-community` had already moved on from
Qwen3.6 to Qwen3.8. Setup: `uv tool install mlx-lm` (no HF login needed — public repos).

| Model | Size | Prompt tok/s | Gen tok/s | Peak mem | Notes |
|---|---:|---:|---:|---:|---|
| `mlx-community/Qwen3-14B-4bit` | ~8 GB | 20.5 | 12.4 | 8.4 GB | Previous-gen dense, baseline sanity check |
| `mlx-community/Qwen3.8-27B-4bit` | ~15.5 GB | 22.7–37.9 | **6.5–6.6** | 15.5 GB | Official successor to the `HauhauCS` Qwen3.6-27B fine-tune used as `qwen36u27b`. Defaults to `reasoning_effort: xhigh` and will burn the whole token budget thinking — pass `--chat-template-config '{"reasoning_effort": "low"}'` or it silently truncates before answering. With that set: clean, correct, complete answers. |
| `LiquidAI/LFM2-24B-A2B-MLX-4bit` | ~13.5 GB | 58.1 | 63.9 | 13.5 GB | 10x faster (2B active MoE) but noticeably lower quality — factually loose description of MoE routing in its own test answer. Vendor explicitly says it's not optimized for coding; it's a fast tool-dispatch/router model for agent inner loops, not a chat/coding daily driver. |

**Verdict: `Qwen3.8-27B-4bit` is the daily-driver upgrade**, replacing the Qwen3.6-27B
fine-tune. Confirmed by public benchmarks too — big agentic/coding jump over 3.6
(SWE-bench Pro 53.5→61.7, DeepSWE 1.1 13.3→42.2). LFM2 is a different tool for a
different job (fast tool selection), not a competitor here.

Tradeoff: 6.5 tok/s generation is slower than the i9's ~26 tok/s or ProBook's ~13 tok/s
for a comparable dense/MoE model — that's the M4 base chip's unified-memory bandwidth
ceiling for a 15.5 GB 4-bit model, not an MLX-vs-llama.cpp gap (no llama.cpp/Metal
number was captured on the Mac for direct comparison — still open, see below).

### Not yet done

- No llama.cpp/ik_llama Metal benchmark captured on the Mac to compare tok/s
  apples-to-apples against MLX for the same architecture — the numbers above only
  compare MLX models against each other and against benchmarks quoted by other people
  for the model's *quality*, not a head-to-head engine speed test on this machine.
- `reasoning_effort: low` was only smoke-tested on one short prompt — worth checking
  it holds up on an actual coding/tool-call task before wiring into OpenCode.
- If adopted as daily driver: update `ik-llama/README.md`'s Mac table, and either
  add an `mlx_lm.server` OpenAI-compatible provider entry (same
  `@ai-sdk/openai-compatible` pattern `setup-agents.sh` already uses for llama-server)
  or pull a GGUF of Qwen3.8-27B and keep using the existing llama.cpp pipeline as-is.
