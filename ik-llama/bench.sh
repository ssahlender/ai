#!/usr/bin/env bash
# Benchmarks CPU thread settings for ik_llama.cpp.
# Usage: ./bench.sh <machine> [mode|all|qwen36]
#   Machine: i9 | probook
set -euo pipefail

MACHINE="${1:-}"
MODE="${2:-}"

[ -n "$MACHINE" ] || { echo "Usage: $0 <i9|probook> [mode|all|qwen36]" >&2; exit 1; }

case "$MACHINE" in
  i9)
    IK_LLAMA_DIR="${IK_LLAMA_DIR:-/data/llm/ik_llama}"
    MODELS_DIR="${MODELS_DIR:-/data/llm/models}"
    BENCH="$IK_LLAMA_DIR/build/bin/llama-bench"
    NGL=0; MACHINE_PATH=
    THREADS_DEFAULT="${BENCH_THREADS:-6 8}"; THREADS_BATCH_DEFAULT="${BENCH_THREADS_BATCH:-24 32}"
    MODE="${MODE:-qwopus35bq5km}"
    MODES=(qwen36u35bq6kp qwen36u27bq5kp qwopus35bq5km qwopus35bq6k gemma4q5km supergemma4q4km glm47flashq5km qwen3codernext)
    QWEN_MODES=(qwen36u35bq6kp qwen36u27bq5kp qwopus35bq5km qwopus35bq6k)
    normalize_mode() {
      case "$1" in
        qwen36u27b|qwen36u27b:q5kp|qwen36u27bq5kp) echo "qwen36u27bq5kp" ;;
        qwen36u35b|qwen36u35b:q6kp|qwen36u35bq6kp) echo "qwen36u35bq6kp" ;;
        qwopus35b|qwopus35b:q5km|qwopus35bq5km) echo "qwopus35bq5km" ;;
        qwopus35b:q6k|qwopus35bq6k) echo "qwopus35bq6k" ;;
        gemma4|gemma4:q5km|gemma4q5km) echo "gemma4q5km" ;;
        supergemma4|supergemma4:q4km|supergemma4q4km) echo "supergemma4q4km" ;;
        glm47flash|glm47flash:q5km|glm47flashq5km) echo "glm47flashq5km" ;;
        qwen3codernext|qwcn|qwcn:q3km) echo "qwen3codernext" ;;
        *) return 1 ;;
      esac
    }
    model_for_mode() {
      case "$(normalize_mode "$1")" in
        qwen36u27bq5kp)   echo "Qwen3.6-27B-Uncensored-HauhauCS-Aggressive-Q5_K_P.gguf" ;;
        qwen36u35bq6kp)   echo "Qwen3.6-35B-A3B-Uncensored-HauhauCS-Aggressive-Q6_K_P.gguf" ;;
        qwopus35bq5km)    echo "Qwopus3.6-35B-A3B-v1-Q5_K_M.gguf" ;;
        qwopus35bq6k)     echo "Qwopus3.6-35B-A3B-v1-Q6_K.gguf" ;;
        gemma4q5km)       echo "gemma-4-26B-A4B-it-UD-Q5_K_M.gguf" ;;
        supergemma4q4km)  echo "supergemma4-26b-uncensored-fast-v2-Q4_K_M.gguf" ;;
        glm47flashq5km)   echo "zai-org_GLM-4.7-Flash-Q5_K_M.gguf" ;;
        qwen3codernext)   echo "Qwen3-Coder-Next-UD-Q3_K_M.gguf" ;;
        *) return 1 ;;
      esac
    }
    ;;
  probook)
    IK_LLAMA_DIR="${IK_LLAMA_DIR:-/mnt/c/data/llm/ik_llama}"
    MODELS_DIR="${MODELS_DIR:-/mnt/c/data/llm/models}"
    BENCH="$IK_LLAMA_DIR/llama-bench.exe"
    NGL=0; MACHINE_PATH=1
    THREADS_DEFAULT="${BENCH_THREADS:-8 12 16}"; THREADS_BATCH_DEFAULT="${BENCH_THREADS_BATCH:-8 12 16}"
    MODE="${MODE:-qwen36u35b}"
    MODES=(qwen36u35b gemma qwen3coder glm47flash)
    QWEN_MODES=()
    normalize_mode() { echo "$1"; }
    model_for_mode() {
      case "$1" in
        qwen36u35b) echo "Qwen3.6-35B-A3B-Uncensored-HauhauCS-Aggressive-IQ4_NL.gguf" ;;
        gemma)      echo "gemma-4-26B-A4B-it-UD-IQ4_NL.gguf" ;;
        qwen3coder) echo "Qwen3-Coder-30B-A3B-Instruct-Q3_K_M.gguf" ;;
        glm47flash) echo "zai-org_GLM-4.7-Flash-Q4_K_M.gguf" ;;
        *) return 1 ;;
      esac
    }
    ;;
  *) echo "Usage: $0 <i9|probook> [mode|all|qwen36]" >&2; exit 1 ;;
esac

# ── shared benchmark logic ─────────────────────────────────────────
THREADS="${BENCH_THREADS:-$THREADS_DEFAULT}"
THREADS_BATCH="${BENCH_THREADS_BATCH:-$THREADS_BATCH_DEFAULT}"
PROMPT_TOKENS="${BENCH_PROMPT_TOKENS:-2048}"
GEN_TOKENS="${BENCH_GEN_TOKENS:-128}"
REPETITIONS="${BENCH_REPETITIONS:-3}"
OUT_DIR="${BENCH_OUT_DIR:-$PWD/bench-results}"

model_path() {
  if [ -n "$MACHINE_PATH" ] && command -v wslpath >/dev/null 2>&1; then
    wslpath -w "$MODELS_DIR/$1"
  else
    echo "$MODELS_DIR/$1"
  fi
}

usage() {
  echo "Usage: $0 $MACHINE [mode|all${QWEN_MODES:+|qwen36}]" >&2
  printf 'Modes: %s\n' "${MODES[*]}" >&2
}

[ -n "$MODE" ] || { usage; exit 1; }

if [ ! -x "$BENCH" ]; then
  echo "Bench binary not found: $BENCH" >&2
  echo "Run ./update.sh $MACHINE first." >&2
  exit 1
fi

if [ "$MODE" = "all" ]; then
  RUN_MODES=("${MODES[@]}")
elif [ "$MODE" = "qwen36" ]; then
  [ ${#QWEN_MODES[@]} -gt 0 ] || { echo "qwen36 group not available for $MACHINE" >&2; exit 1; }
  RUN_MODES=("${QWEN_MODES[@]}")
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

{ printf 'mode\tthreads\tthreads_batch\tprompt_tokens\tgen_tokens\trepetitions\toutput\n'; } > "$summary"

echo "Benchmarking $MACHINE ($MODE)"
echo "Output: $OUT_DIR"
echo "Summary: $summary"
[ -z "$threads_batch_flag" ] && echo "Note: llama-bench does not advertise --threads-batch/-tb; batch sweep recorded but not passed."
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

  echo "Model: $run_mode  File: $model"

  for threads in $THREADS; do
    for threads_batch in $THREADS_BATCH; do
      output="$OUT_DIR/${timestamp}-${run_mode}-t${threads}-tb${threads_batch}.csv"
      echo "==> threads=$threads threads_batch=$threads_batch"

      args=(-m "$(model_path "$model_file")" -ngl "$NGL" -p "$PROMPT_TOKENS" -n "$GEN_TOKENS" -r "$REPETITIONS" -o csv)

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

echo "Done. Summary: $summary"
