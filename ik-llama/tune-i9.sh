#!/usr/bin/env bash
# Applies OS-level tuning for CPU-only llama.cpp inference on i9-13900.
# Run once per boot: sudo ./tune-i9.sh
# All changes revert on reboot — no permanent config is modified.
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "Must run as root: sudo $0" >&2
  exit 1
fi

changed=0

# --- CPU frequency governor → performance ---
# Prevents frequency scaling latency on generation (single-token path).
echo "CPU governor:"
for gov in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
  [ -f "$gov" ] || continue
  current=$(cat "$gov")
  cpu=$(basename "$(dirname "$(dirname "$gov")")")
  if [ "$current" != "performance" ]; then
    echo performance > "$gov"
    echo "  $cpu: $current → performance"
    changed=$((changed + 1))
  else
    echo "  $cpu: already performance"
  fi
done

# --- Transparent Huge Pages → madvise ---
# Default "always" aggressively promotes 2MB pages for all processes.
# "madvise" lets llama-server opt in via madvise() without wasting
# huge pages on other processes that can't benefit.
echo
echo "Transparent huge pages:"
thp_path=/sys/kernel/mm/transparent_hugepage/enabled
if [ -f "$thp_path" ]; then
  current=$(grep -o '\[[^]]*\]' "$thp_path" | tr -d '[]')
  if [ "$current" != "madvise" ]; then
    echo madvise > "$thp_path"
    echo "  $current → madvise"
    changed=$((changed + 1))
  else
    echo "  already madvise"
  fi
else
  echo "  not available (WSL2? skipping)"
fi

# --- NUMA balancing → off ---
# Single-socket i9 has no benefit from automatic page migration.
# Disabling avoids kernel overhead during inference.
echo
echo "NUMA balancing:"
numa_path=/proc/sys/kernel/numa_balancing
if [ -f "$numa_path" ]; then
  current=$(cat "$numa_path")
  if [ "$current" != "0" ]; then
    echo 0 > "$numa_path"
    echo "  $current → 0 (off)"
    changed=$((changed + 1))
  else
    echo "  already off"
  fi
else
  echo "  not available"
fi

# --- RLIMIT_MEMLOCK → unlimited for llama-server user ---
# Default 8 GB limit causes mlock failures when loading large models.
# KV cache beyond the limit becomes swappable; with only ~2 GB swap this
# causes OOM during heavy context (compact, long sessions).
# Write to limits.d so every new llama-server session inherits unlimited.
echo
echo "memlock limit:"
limits_file="/etc/security/limits.d/llama-memlock.conf"
expected=$'isc-ssl soft memlock unlimited\nisc-ssl hard memlock unlimited'
if [ -f "$limits_file" ] && [ "$(cat "$limits_file")" = "$expected" ]; then
  echo "  already unlimited (${limits_file})"
else
  printf '%s\n' "$expected" > "$limits_file"
  echo "  set unlimited memlock for isc-ssl → ${limits_file}"
  echo "  (takes effect on next login / llama-server restart)"
  changed=$((changed + 1))
fi

# Also raise the limit for any currently running llama-server process.
llama_pid=$(pgrep -x llama-server 2>/dev/null | head -1 || true)
if [ -n "$llama_pid" ]; then
  prlimit --pid "$llama_pid" --memlock=unlimited:unlimited 2>/dev/null && \
    echo "  raised live limit for llama-server PID $llama_pid" || true
fi

echo
if [ "$changed" -gt 0 ]; then
  echo "$changed setting(s) applied. Reboot to revert CPU/NUMA settings; memlock persists."
else
  echo "All settings already optimal — nothing to change."
fi
