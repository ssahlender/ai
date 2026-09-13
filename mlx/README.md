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
