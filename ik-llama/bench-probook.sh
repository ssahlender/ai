#!/usr/bin/env bash
# Benchmarks ik_llama.cpp CPU thread settings on the ProBook Windows build.
# Run from WSL2. The Windows llama-bench.exe requires Windows-style model paths.
# Usage:
#   ./bench-probook.sh [mode|all]
#
# Environment overrides:
#   IK_LLAMA_DIR=/mnt/c/data/llm/ik_llama
#   MODELS_DIR=/mnt/c/data/llm/models
#   BENCH_THREADS="8 12 16"
#   BENCH_THREADS_BATCH="8 12 16"
#   BENCH_PROMPT_TOKENS=2048
#   BENCH_GEN_TOKENS=128
#   BENCH_REPETITIONS=3
#   BENCH_OUT_DIR=./bench-results
set -euo pipefail

IK_LLAMA_DIR="${IK_LLAMA_DIR:-/mnt/c/data/llm/ik_llama}"
MODELS_DIR="${MODELS_DIR:-/mnt/c/data/llm/models}"
BENCH="$IK_LLAMA_DIR/llama-bench.exe"
MODE="${1:-qwen36u35b}"
MODES=(qwen36u35b gemma qwen3coder glm47flash)

THREADS="${BENCH_THREADS:-8 12 16}"
THREADS_BATCH="${BENCH_THREADS_BATCH:-8 12 16}"
PROMPT_TOKENS="${BENCH_PROMPT_TOKENS:-2048}"
GEN_TOKENS="${BENCH_GEN_TOKENS:-128}"
REPETITIONS="${BENCH_REPETITIONS:-3}"
OUT_DIR="${BENCH_OUT_DIR:-$PWD/bench-results}"

usage() {
  echo "Usage: $0 [qwen36u35b|gemma|qwen3coder|glm47flash|all]" >&2
}

model_for_mode() {
  case "$1" in
    qwen36u35b) echo "Qwen3.6-35B-A3B-Uncensored-HauhauCS-Aggressive-IQ4_NL.gguf" ;;
    gemma)      echo "gemma-4-26B-A4B-it-UD-IQ4_NL.gguf" ;;
    qwen3coder) echo "Qwen3-Coder-30B-A3B-Instruct-Q3_K_M.gguf" ;;
    glm47flash) echo "zai-org_GLM-4.7-Flash-Q4_K_M.gguf" ;;
    *) return 1 ;;
  esac
}

win_path() {
  wslpath -w "$1"
}

if [ ! -x "$BENCH" ]; then
  echo "llama-bench.exe not found or not executable: $BENCH" >&2
  echo "Run ./update-probook.sh first, or set IK_LLAMA_DIR to the ik_llama.cpp install path." >&2
  exit 1
fi

if [ "$MODE" = "all" ]; then
  RUN_MODES=("${MODES[@]}")
elif model_for_mode "$MODE" >/dev/null; then
  RUN_MODES=("$MODE")
else
  usage
  exit 1
fi

mkdir -p "$OUT_DIR"
timestamp=$(date +%Y%m%d-%H%M%S)
summary="$OUT_DIR/${timestamp}-${MODE}-summary.tsv"

help_text=$("$BENCH" -h 2>&1 || true)
threads_batch_flag=""
if grep -q -- "--threads-batch" <<< "$help_text"; then
  threads_batch_flag="--threads-batch"
elif grep -q -- "-tb" <<< "$help_text"; then
  threads_batch_flag="-tb"
else
  # Most current llama.cpp/ik_llama builds support this even if help output is unavailable.
  threads_batch_flag="--threads-batch"
fi

{
  printf 'mode\tthreads\tthreads_batch\tprompt_tokens\tgen_tokens\trepetitions\toutput\n'
} > "$summary"

echo "Benchmarking $MODE"
echo "Output: $OUT_DIR"
echo "Summary: $summary"
echo

for run_mode in "${RUN_MODES[@]}"; do
  model_file=$(model_for_mode "$run_mode")
  model="$MODELS_DIR/$model_file"

  if [ ! -f "$model" ]; then
    echo "Skipping $run_mode; model not found: $model"
    echo
    continue
  fi

  echo "Model mode: $run_mode"
  echo "Model file: $model"

  for threads in $THREADS; do
    for threads_batch in $THREADS_BATCH; do
      output="$OUT_DIR/${timestamp}-${run_mode}-t${threads}-tb${threads_batch}.csv"
      echo "==> mode=$run_mode threads=$threads threads_batch=$threads_batch"

      args=(
        -m "$(win_path "$model")"
        -ngl 0
        -t "$threads"
        -p "$PROMPT_TOKENS"
        -n "$GEN_TOKENS"
        -r "$REPETITIONS"
        -ctk q8_0
        -ctv q8_0
        -o csv
        "$threads_batch_flag" "$threads_batch"
      )

      "$BENCH" "${args[@]}" | tee "$output"
      printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$run_mode" "$threads" "$threads_batch" "$PROMPT_TOKENS" "$GEN_TOKENS" "$REPETITIONS" "$output" >> "$summary"
      echo
    done
  done
done

echo "Done."
echo "Review the CSV files and compare prompt/gen tok/s for the best OpenCode tradeoff:"
echo "  $summary"
