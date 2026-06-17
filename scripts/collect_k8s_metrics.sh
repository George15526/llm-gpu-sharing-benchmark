# scripts/collect_k8s_metrics.sh
#!/usr/bin/env bash
set -euo pipefail

LABEL_SELECTOR="${1:-app=vllm}"
OUT_DIR="${2:-results/k8s_metrics}"
INTERVAL="${3:-2}"

mkdir -p "$OUT_DIR"

while true; do
  TS="$(date --iso-8601=seconds)"

  kubectl get pods -l "$LABEL_SELECTOR" -o wide \
    > "$OUT_DIR/pods_${TS}.txt" 2>/dev/null || true

  kubectl get pods -l "$LABEL_SELECTOR" -o yaml \
    > "$OUT_DIR/pods_${TS}.yaml" 2>/dev/null || true

  kubectl top pods -l "$LABEL_SELECTOR" --containers \
    > "$OUT_DIR/top_pods_${TS}.txt" 2>/dev/null || true

  kubectl top node \
    > "$OUT_DIR/top_nodes_${TS}.txt" 2>/dev/null || true

  sleep "$INTERVAL"
done
