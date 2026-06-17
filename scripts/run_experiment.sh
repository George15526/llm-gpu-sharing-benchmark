# scripts/run_experiment.sh
#!/usr/bin/env bash
set -euo pipefail

NODE_NAME="${NODE_NAME:-wtlee4070s}"

MODE="${1:?Usage: $0 <timeslicing|hami> <replicas> <concurrency> <num_requests>}"
REPLICAS="${2:-1}"
CONCURRENCY="${3:-4}"
NUM_REQUESTS="${4:-100}"

MODEL="${MODEL:-Qwen/Qwen2.5-0.5B-Instruct}"
MAX_TOKENS="${MAX_TOKENS:-128}"
WARMUP_REQUESTS_PER_ENDPOINT="${WARMUP_REQUESTS_PER_ENDPOINT:-3}"
RESULT_ROOT="${RESULT_ROOT:-results}"
TS="$(date +%Y%m%d-%H%M%S)"
OUT_DIR="${RESULT_ROOT}/${MODE}/r${REPLICAS}_c${CONCURRENCY}_${TS}"

mkdir -p "$OUT_DIR"

if [[ -x ".venv/bin/python" ]]; then
  PYTHON_BIN="${PYTHON_BIN:-.venv/bin/python}"
else
  PYTHON_BIN="${PYTHON_BIN:-python3}"
fi

echo "[INFO] Cleaning old workload"

kubectl delete deploy vllm-timeslicing --ignore-not-found
kubectl delete deploy vllm-hami --ignore-not-found
kubectl delete svc vllm-service --ignore-not-found
kubectl delete pod -l app=vllm --grace-period=0 --force 2>/dev/null || true

echo "[INFO] Waiting old vLLM pods removed"
for i in $(seq 1 60); do
  LEFT="$(kubectl get pods -l app=vllm --no-headers 2>/dev/null | wc -l)"
  if [[ "$LEFT" == "0" ]]; then
    break
  fi
  kubectl get pods -l app=vllm -o wide || true
  sleep 2
done

if [[ "$MODE" == "timeslicing" ]]; then
  DEPLOY="k8s/timeslicing/vllm-timeslicing.yaml"
  DEPLOY_NAME="vllm-timeslicing"
elif [[ "$MODE" == "hami" ]]; then
  DEPLOY="k8s/hami/vllm-hami.yaml"
  DEPLOY_NAME="vllm-hami"
else
  echo "Invalid mode: $MODE"
  exit 1
fi

echo "[INFO] Output dir: $OUT_DIR"
echo "[INFO] Applying workload: $DEPLOY"
kubectl apply -f "$DEPLOY"
kubectl apply -f k8s/common/service.yaml

echo "[INFO] Scaling deployment to replicas=$REPLICAS"
kubectl scale deploy "$DEPLOY_NAME" --replicas="$REPLICAS"

echo "[INFO] Waiting for rollout"
kubectl rollout status deploy/"$DEPLOY_NAME" --timeout=600s

READY_COUNT=$(kubectl get pods -l app=vllm \
  -o jsonpath='{range .items[*]}{.status.containerStatuses[0].ready}{"\n"}{end}' \
  | grep -c true || true)

echo "[INFO] Ready vLLM pods: $READY_COUNT / $REPLICAS"

if [[ "$READY_COUNT" -ne "$REPLICAS" ]]; then
  echo "[ERROR] Not all vLLM pods are ready"
  kubectl get pods -l app=vllm -o wide
  kubectl describe pods -l app=vllm > "$OUT_DIR/pods_describe_error.txt" || true
  exit 1
fi

echo "[INFO] Collecting vLLM service endpoints"

ENDPOINTS="$(kubectl get endpoints vllm-service \
  -o jsonpath='{range .subsets[*].addresses[*]}http://{.ip}:8000{","}{end}' \
  | sed 's/,$//')"

ENDPOINT_COUNT="$(echo "$ENDPOINTS" | tr ',' '\n' | grep -c '^http' || true)"

echo "[INFO] Endpoints: $ENDPOINTS"
echo "[INFO] Endpoint count: $ENDPOINT_COUNT / $REPLICAS"

echo "$ENDPOINTS" > "$OUT_DIR/bench_endpoints.txt"

if [[ "$ENDPOINT_COUNT" -ne "$REPLICAS" ]]; then
  echo "[ERROR] Endpoint count does not match replicas"
  kubectl get pods -l app=vllm -o wide
  kubectl get endpoints vllm-service -o wide
  exit 1
fi

echo "[INFO] Checking each endpoint readiness"

for ep in $(echo "$ENDPOINTS" | tr ',' '\n'); do
  echo "[INFO] Checking $ep/v1/models"

  EP_READY=0
  for i in $(seq 1 120); do
    if curl -sf "$ep/v1/models" >/dev/null 2>&1; then
      echo "[INFO] Endpoint ready: $ep"
      EP_READY=1
      break
    fi
    sleep 2
  done

  if [[ "$EP_READY" -ne 1 ]]; then
    echo "[ERROR] Endpoint not ready: $ep"
    kubectl get pods -l app=vllm -o wide || true
    kubectl get endpoints vllm-service -o wide || true
    exit 1
  fi
done

cat > "$OUT_DIR/experiment_config.json" <<EOF
{
  "mode": "$MODE",
  "replicas": $REPLICAS,
  "concurrency": $CONCURRENCY,
  "num_requests": $NUM_REQUESTS,
  "model": "$MODEL",
  "max_tokens": $MAX_TOKENS,
  "warmup_requests_per_endpoint": $WARMUP_REQUESTS_PER_ENDPOINT,
  "endpoint_count": $ENDPOINT_COUNT,
  "endpoints": "$ENDPOINTS",
  "node_name": "$NODE_NAME",
  "deploy_manifest": "$DEPLOY"
}
EOF

echo "[INFO] Snapshot allocation"
kubectl get pods -l app=vllm -o wide > "$OUT_DIR/pods_before.txt"
kubectl get pods -l app=vllm -o yaml > "$OUT_DIR/pods_before.yaml"
kubectl get endpoints vllm-service -o wide > "$OUT_DIR/endpoints_before.txt"
kubectl describe node "$NODE_NAME" > "$OUT_DIR/node_describe_before.txt"
nvidia-smi > "$OUT_DIR/nvidia_smi_before.txt" || true

echo "[INFO] Start GPU metrics collector"
bash scripts/collect_gpu_metrics.sh "$OUT_DIR/gpu_metrics.csv" 1 &
GPU_METRICS_PID=$!

echo "[INFO] Start K8s metrics collector"
bash scripts/collect_k8s_metrics.sh "app=vllm" "$OUT_DIR/k8s_metrics" 2 &
K8S_METRICS_PID=$!

cleanup() {
  echo "[INFO] Cleanup background jobs"
  kill "$GPU_METRICS_PID" 2>/dev/null || true
  kill "$K8S_METRICS_PID" 2>/dev/null || true
  # kill "$PF_PID" 2>/dev/null || true
}
trap cleanup EXIT

echo "[INFO] Run benchmark"
"$PYTHON_BIN" scripts/bench_openai_stream.py \
  --mode "$MODE" \
  --endpoints "$ENDPOINTS" \
  --model "$MODEL" \
  --num-requests "$NUM_REQUESTS" \
  --concurrency "$CONCURRENCY" \
  --max-tokens "$MAX_TOKENS" \
  --warmup-requests-per-endpoint "$WARMUP_REQUESTS_PER_ENDPOINT" \
  --output-dir "$OUT_DIR"

echo "[INFO] Snapshot allocation after benchmark"
kubectl get pods -l app=vllm -o wide > "$OUT_DIR/pods_after.txt"
kubectl get pods -l app=vllm -o yaml > "$OUT_DIR/pods_after.yaml"
kubectl get endpoints vllm-service -o wide > "$OUT_DIR/endpoints_after.txt"
kubectl describe node "$NODE_NAME" > "$OUT_DIR/node_describe_after.txt"
nvidia-smi > "$OUT_DIR/nvidia_smi_after.txt" || true

echo "[INFO] Done: $OUT_DIR"

echo "[INFO] Summarize results"
"$PYTHON_BIN" scripts/summarize_results.py "$OUT_DIR" || true
