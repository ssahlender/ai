#!/usr/bin/env bash
# Benchmarks ik_llama.cpp CPU thread settings on the i9.
# Usage:
#   ./bench-i9.sh [preset|preset:quant|all|today|tomorrow|coder|qwen36]
#
# Environment overrides:
#   IK_LLAMA_DIR=/data/llm/ik_llama
#   MODELS_DIR=/data/llm/models
#   BENCH_THREADS="6 8"
#   BENCH_THREADS_BATCH="24 32"
#   BENCH_PROMPT_TOKENS=2048
#   BENCH_GEN_TOKENS=128
#   BENCH_REPETITIONS=3
#   BENCH_OUT_DIR=./bench-results
set -euo pipefail

IK_LLAMA_DIR="${IK_LLAMA_DIR:-/data/llm/ik_llama}"
MODELS_DIR="${MODELS_DIR:-/data/llm/models}"
BENCH="$IK_LLAMA_DIR/build/bin/llama-bench"
MODE="${1:-qwen36u35bq5kp}"
MODES=(qwen36u35bq4kp qwen36u35bq5kp qwen36u35bq6kp qwen36u35bq8kp qwen36u27bq5kp gemma4q5km supergemma4q4km glm47flashq5km)
TODAY_MODES=(qwen36u35bq4kp qwen36u35bq5kp qwen36u35bq6kp qwen36u35bq8kp qwen36u27bq5kp gemma4q5km supergemma4q4km glm47flashq5km)
TOMORROW_MODES=(qwen36u35bq5kp qwen36u35bq6kp qwen36u35bq8kp qwen36u27bq5kp)
CODER_MODES=(qwen36u35bq5kp qwen36u35bq6kp qwen36u35bq8kp)
QWEN36_MODES=(qwen36u35bq4kp qwen36u35bq5kp qwen36u35bq6kp qwen36u35bq8kp qwen36u27bq5kp)

THREADS="${BENCH_THREADS:-6 8}"
THREADS_BATCH="${BENCH_THREADS_BATCH:-24 32}"
PROMPT_TOKENS="${BENCH_PROMPT_TOKENS:-2048}"
GEN_TOKENS="${BENCH_GEN_TOKENS:-128}"
REPETITIONS="${BENCH_REPETITIONS:-3}"
OUT_DIR="${BENCH_OUT_DIR:-$PWD/bench-results}"

usage() {
  echo "Usage: $0 [preset|preset:quant|all|today|tomorrow|coder|qwen36]" >&2
  echo "Presets: qwen36u35bq4kp, qwen36u35bq5kp, qwen36u35bq6kp, qwen36u35bq8kp, qwen36u27bq5kp, gemma4q5km, supergemma4q4km, glm47flashq5km" >&2
}

normalize_mode() {
  case "$1" in
    qwen3coder:q8|qwen3coderq8|qwen3coderq8_0) echo "qwen3coderq8" ;;
    qwen3coder:q6|qwen3coderq6|qwen3coderq6k) echo "qwen3coderq6k" ;;
    qwen3coder:q5|qwen3coderq5|qwen3coderq5km) echo "qwen3coderq5km" ;;
    qwen36u27b|qwen36u27b:q5kp|qwen36u27bq5kp) echo "qwen36u27bq5kp" ;;
    qwen36u35b|qwen36u35b:q4kp|qwen36u35bq4kp) echo "qwen36u35bq4kp" ;;
    qwen36u35b:q5kp|qwen36u35bq5kp) echo "qwen36u35bq5kp" ;;
    qwen36u35b:q6kp|qwen36u35bq6kp) echo "qwen36u35bq6kp" ;;
    qwen36u35b:q8kp|qwen36u35bq8kp) echo "qwen36u35bq8kp" ;;
    gemma4|gemma4:q5km|gemma4q5km) echo "gemma4q5km" ;;
    supergemma4|supergemma4:q4km|supergemma4q4km) echo "supergemma4q4km" ;;
    glm47flash|glm47flash:q5km|glm47flashq5km) echo "glm47flashq5km" ;;
    *) return 1 ;;
  esac
}

model_for_mode() {
  case "$(normalize_mode "$1")" in
    qwen3coderq8)     echo "Qwen3-Coder-30B-A3B-Instruct-Q8_0.gguf" ;;
    qwen3coderq6k)    echo "Qwen3-Coder-30B-A3B-Instruct-Q6_K.gguf" ;;
    qwen3coderq5km)   echo "Qwen3-Coder-30B-A3B-Instruct-Q5_K_M.gguf" ;;
    qwen36u27bq5kp)   echo "Qwen3.6-27B-Uncensored-HauhauCS-Aggressive-Q5_K_P.gguf" ;;
    qwen36u35bq4kp)   echo "Qwen3.6-35B-A3B-Uncensored-HauhauCS-Aggressive-Q4_K_P.gguf" ;;
    qwen36u35bq5kp)   echo "Qwen3.6-35B-A3B-Uncensored-HauhauCS-Aggressive-Q5_K_P.gguf" ;;
    qwen36u35bq6kp)   echo "Qwen3.6-35B-A3B-Uncensored-HauhauCS-Aggressive-Q6_K_P.gguf" ;;
    qwen36u35bq8kp)   echo "Qwen3.6-35B-A3B-Uncensored-HauhauCS-Aggressive-Q8_K_P.gguf" ;;
    gemma4q5km)       echo "gemma-4-26B-A4B-it-UD-Q5_K_M.gguf" ;;
    supergemma4q4km)  echo "supergemma4-26b-uncensored-fast-v2-Q4_K_M.gguf" ;;
    glm47flashq5km)   echo "zai-org_GLM-4.7-Flash-Q5_K_M.gguf" ;;
    *) return 1 ;;
  esac
}

if [ ! -x "$BENCH" ]; then
  echo "llama-bench not found or not executable: $BENCH" >&2
  echo "Run ./update-i9.sh first, or set IK_LLAMA_DIR to the ik_llama.cpp install path." >&2
  exit 1
fi

if [ "$MODE" = "all" ]; then
  RUN_MODES=("${MODES[@]}")
elif [ "$MODE" = "today" ]; then
  RUN_MODES=("${TODAY_MODES[@]}")
elif [ "$MODE" = "tomorrow" ]; then
  RUN_MODES=("${TOMORROW_MODES[@]}")
elif [ "$MODE" = "coder" ]; then
  RUN_MODES=("${CODER_MODES[@]}")
elif [ "$MODE" = "qwen36" ]; then
  RUN_MODES=("${QWEN36_MODES[@]}")
elif normalized_mode=$(normalize_mode "$MODE") && model_for_mode "$normalized_mode" >/dev/null; then
  RUN_MODES=("$normalized_mode")
else
  usage
  exit 1
fi

mkdir -p "$OUT_DIR"
timestamp=$(date +%Y%m%d-%H%M%S)
summary="$OUT_DIR/${timestamp}-${MODE}-summary.tsv"

help_text=$("$BENCH" -h 2>&1 || true)
bench_strings=$(strings "$BENCH" 2>/dev/null || true)
option_text="${help_text}"$'\n'"${bench_strings}"
threads_batch_flag=""
if grep -q -- "-tgb" <<< "$option_text"; then
  threads_batch_flag="-tgb"
elif grep -q -- "--threads-batch" <<< "$option_text"; then
  threads_batch_flag="--threads-batch"
elif grep -q -- "-tb" <<< "$option_text"; then
  threads_batch_flag="-tb"
fi

{
  printf 'mode\tthreads\tthreads_batch\tprompt_tokens\tgen_tokens\trepetitions\toutput\n'
} > "$summary"

echo "Benchmarking $MODE"
echo "Output: $OUT_DIR"
echo "Summary: $summary"
if [ -z "$threads_batch_flag" ]; then
  echo "Note: this llama-bench does not advertise --threads-batch/-tb; batch thread sweep will be recorded but not passed."
fi
echo

for run_mode in "${RUN_MODES[@]}"; do
  run_mode=$(normalize_mode "$run_mode")
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
        -m "$model"
        -ngl 0
        -p "$PROMPT_TOKENS"
        -n "$GEN_TOKENS"
        -r "$REPETITIONS"
        -o csv
      )

      if [ "$threads_batch_flag" = "-tgb" ]; then
        args+=("-tgb" "${threads},${threads_batch}")
      else
        args+=("-t" "$threads")
      fi

      if [ -n "$threads_batch_flag" ] && [ "$threads_batch_flag" != "-tgb" ]; then
        args+=("$threads_batch_flag" "$threads_batch")
      fi

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
