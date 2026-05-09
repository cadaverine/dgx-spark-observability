#!/usr/bin/env bash
# Polls nvidia-smi every 5s and writes Prometheus textfile-format metrics
# for node-exporter to pick up. Augments dcgm-exporter on Blackwell GB10
# / sm_121a where DCGM_FI_DEV_FB_USED / FB_FREE and DCGM_FI_PROF_* are
# unavailable.
#
# GB10 / unified memory note: nvidia-smi --query-gpu=memory.used,memory.total
# returns [N/A] because there is no separate VRAM pool. We derive:
#   - memory.used = sum(per-process used_memory) from --query-compute-apps
#   - memory.total = MemTotal from /proc/meminfo (mounted from host)
# This matches the unified-memory model: the "GPU memory pool" IS host RAM.
set -euo pipefail

OUT_DIR="${OUT_DIR:-/var/lib/node_exporter/textfile}"
TMP="${OUT_DIR}/nvidia.prom.tmp"
FINAL="${OUT_DIR}/nvidia.prom"
MEMINFO="${MEMINFO:-/host/proc/meminfo}"
[ -r "$MEMINFO" ] || MEMINFO=/proc/meminfo

mkdir -p "${OUT_DIR}"

while true; do
  {
    echo "# HELP nvidia_gpu_temp_celsius GPU temperature."
    echo "# TYPE nvidia_gpu_temp_celsius gauge"
    echo "# HELP nvidia_gpu_memory_used_bytes GPU memory used (sum of per-process; unified memory on GB10)."
    echo "# TYPE nvidia_gpu_memory_used_bytes gauge"
    echo "# HELP nvidia_gpu_memory_total_bytes GPU memory total (host RAM; unified memory on GB10)."
    echo "# TYPE nvidia_gpu_memory_total_bytes gauge"
    echo "# HELP nvidia_gpu_utilization_ratio GPU utilization (0..1)."
    echo "# TYPE nvidia_gpu_utilization_ratio gauge"
    echo "# HELP nvidia_gpu_power_draw_watts GPU instantaneous power draw."
    echo "# TYPE nvidia_gpu_power_draw_watts gauge"
    echo "# HELP nvidia_gpu_throttle_active 1 if any throttle reason is active, 0 otherwise."
    echo "# TYPE nvidia_gpu_throttle_active gauge"

    # Total memory: host RAM (unified memory)
    mem_total_kb=$(awk '/^MemTotal:/ {print $2}' "$MEMINFO")
    mem_total_b=$(( mem_total_kb * 1024 ))

    # Sum per-process GPU memory by GPU index. On GB10 we have a single GPU
    # (index 0); --query-compute-apps lists each compute process's used_memory in MiB.
    mem_used_mib=$(nvidia-smi --query-compute-apps=used_memory \
                              --format=csv,noheader,nounits \
                  | awk '{s+=$1} END {print s+0}')
    mem_used_b=$(( mem_used_mib * 1024 * 1024 ))

    nvidia-smi --query-gpu=index,uuid,temperature.gpu,utilization.gpu,power.draw,clocks_throttle_reasons.active \
               --format=csv,noheader,nounits | \
    while IFS=, read -r idx uuid temp util power_w throttle; do
      idx=$(echo "$idx" | xargs)
      uuid=$(echo "$uuid" | xargs)
      temp=$(echo "$temp" | xargs)
      util_clean=$(echo "$util" | xargs)
      util_ratio=$(awk "BEGIN {printf \"%.4f\", $util_clean / 100.0}")
      power_w=$(echo "$power_w" | xargs)
      throttle=$(echo "$throttle" | xargs)
      if [ "$throttle" = "0x0000000000000000" ]; then th=0; else th=1; fi

      lbl="gpu=\"$idx\",uuid=\"$uuid\""
      echo "nvidia_gpu_temp_celsius{$lbl} $temp"
      echo "nvidia_gpu_memory_used_bytes{$lbl} $mem_used_b"
      echo "nvidia_gpu_memory_total_bytes{$lbl} $mem_total_b"
      echo "nvidia_gpu_utilization_ratio{$lbl} $util_ratio"
      echo "nvidia_gpu_power_draw_watts{$lbl} $power_w"
      echo "nvidia_gpu_throttle_active{$lbl} $th"
    done
  } > "$TMP"
  mv -f "$TMP" "$FINAL"
  sleep 5
done
