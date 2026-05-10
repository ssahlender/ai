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

echo
if [ "$changed" -gt 0 ]; then
  echo "$changed setting(s) applied. Reboot to revert."
else
  echo "All settings already optimal — nothing to change."
fi
