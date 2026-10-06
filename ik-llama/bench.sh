#!/usr/bin/env bash
# Benchmarks CPU thread settings for ik_llama.cpp.
# Usage: ./bench.sh <machine> [mode|number|all]   (mode = GGUF file name without .gguf; no mode = numbered menu)
#   Machine: i9
#   (ProBook benchmarks run natively on Windows via llm/bench/)
set -euo pipefail

MACHINE="${1:-}"
MODE="${2:-}"

[ -n "$MACHINE" ] || { echo "Usage: $0 <i9> [mode|all]" >&2; exit 1; }

case "$MACHINE" in
  i9)
    IK_LLAMA_DIR="${IK_LLAMA_DIR:-/data/llm/ik_llama}"
    MODELS_DIR="${MODELS_DIR:-/data/llm/models}"
    BENCH="$IK_LLAMA_DIR/build/bin/llama-bench"
    NGL=0
    THREADS_DEFAULT="${BENCH_THREADS:-6 8}"; THREADS_BATCH_DEFAULT="${BENCH_THREADS_BATCH:-24 32}"
    # Modes are the GGUF stems listed in start.sh (single source of truth).
    START_SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/start.sh"
    MODES=()
    while IFS= read -r gguf; do
      [ -n "$gguf" ] && MODES+=("${gguf%.gguf}")
    done < <(awk -v m="$MACHINE" '
      /# ── machine config/ { in_config=1 }
      !in_config { next }
      $0 ~ "^[[:space:]]*" m "\\)[[:space:]]*$" { in_block=1; next }
      in_block && /;;[[:space:]]*$/ { exit }
      in_block && /^[[:space:]]*"[^"]*[.]gguf\|/ { split($0, a, "|"); print a[2] }
    ' "$START_SCRIPT")
    [ "${#MODES[@]}" -gt 0 ] || { echo "No modes parsed from $START_SCRIPT for $MACHINE" >&2; exit 1; }
    normalize_mode() {
      local m
      for m in "${MODES[@]}"; do [ "$m" = "$1" ] && { echo "$m"; return 0; }; done
      return 1
    }
    model_for_mode() { normalize_mode "$1" >/dev/null && echo "$1.gguf"; }
    ;;
  probook)
    echo "WSL is retired on ProBook. Benchmarking runs natively on Windows in llm/bench/ (e.g. powershell -File llm\\bench\\bench-threads.ps1)." >&2
    exit 1
    ;;
  *) echo "Usage: $0 <i9> [mode|all]" >&2; exit 1 ;;
esac

# ── shared benchmark logic ─────────────────────────────────────────
THREADS="${BENCH_THREADS:-$THREADS_DEFAULT}"
THREADS_BATCH="${BENCH_THREADS_BATCH:-$THREADS_BATCH_DEFAULT}"
PROMPT_TOKENS="${BENCH_PROMPT_TOKENS:-2048}"
GEN_TOKENS="${BENCH_GEN_TOKENS:-128}"
REPETITIONS="${BENCH_REPETITIONS:-3}"
OUT_DIR="${BENCH_OUT_DIR:-$PWD/bench-results}"

model_path() {
  echo "$MODELS_DIR/$1"
}

list_modes() {
  local i=1 m
  for m in "${MODES[@]}"; do
    printf '  %2d) %s\n' "$i" "$m"
    i=$((i + 1))
  done
  printf '   a) all\n'
}

usage() {
  echo "Usage: $0 $MACHINE [mode|number|all]" >&2
  echo "Modes:" >&2
  list_modes >&2
}

if [ -z "$MODE" ]; then
  if [ -t 0 ] && [ -t 1 ]; then
    echo "Benchmark which model on $MACHINE?"
    list_modes
    read -r -p "Select a number or a: " MODE
  else
    usage
    exit 1
  fi
fi

[ "$MODE" = "a" ] || [ "$MODE" = "A" ] && MODE=all
# A number picks the Nth entry of the list above.
if [[ "$MODE" =~ ^[0-9]+$ ]]; then
  if [ "$MODE" -lt 1 ] || [ "$MODE" -gt "${#MODES[@]}" ]; then
    echo "No model number $MODE (valid: 1-${#MODES[@]})." >&2
    exit 1
  fi
  MODE="${MODES[$((MODE - 1))]}"
  echo "Selected: $MODE"
fi

if [ ! -x "$BENCH" ]; then
  echo "Bench binary not found: $BENCH" >&2
  echo "Run ./update.sh $MACHINE first." >&2
  exit 1
fi

if [ "$MODE" = "all" ]; then
  RUN_MODES=("${MODES[@]}")
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
option_text="${help_text}"
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
      output="$OUT_DIR/${timestamp}-${run_mode}-t${threads}-tb${threads_batch}.json"
      echo "==> threads=$threads threads_batch=$threads_batch"
      args=(-m "$(model_path "$model_file")" -ngl "$NGL" -p "$PROMPT_TOKENS" -n "$GEN_TOKENS" -r "$REPETITIONS" -o json)
      [ -n "${MMAP:-}" ] && args+=(-mmp "$MMAP")

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
