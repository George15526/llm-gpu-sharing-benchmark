# scripts/collect_gpu_metrics.sh
#!/usr/bin/env bash
set -euo pipefail

OUT="${1:-gpu_metrics.csv}"
INTERVAL="${2:-1}"

echo "timestamp,gpu_index,name,util_gpu_pct,util_mem_pct,memory_used_mib,memory_total_mib,power_w,temp_c" > "$OUT"

while true; do
  nvidia-smi \
    --query-gpu=timestamp,index,name,utilization.gpu,utilization.memory,memory.used,memory.total,power.draw,temperature.gpu \
    --format=csv,noheader,nounits \
    >> "$OUT"
  sleep "$INTERVAL"
done
