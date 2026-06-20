#!/usr/bin/env bash
set -euo pipefail

NODE_NAME="${NODE_NAME:-$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')}"

MODE="${1:?Usage: $0 <timeslicing|hami> <replicas> <concurrency> <num_requests>}"
REPLICAS="${2:-1}"
CONCURRENCY="${3:-4}"
NUM_REQUESTS="${4:-100}"

MODEL="${MODEL:-Qwen/Qwen2.5-0.5B-Instruct}"
MAX_TOKENS="${MAX_TOKENS:-128}"
WARMUP_REQUESTS_PER_ENDPOINT="${WARMUP_REQUESTS_PER_ENDPOINT:-3}"
BENCH_REQUEST_TIMEOUT_SEC="${BENCH_REQUEST_TIMEOUT_SEC:-180}"
BENCH_CONNECT_TIMEOUT_SEC="${BENCH_CONNECT_TIMEOUT_SEC:-10}"
BENCH_TIMEOUT_SEC="${BENCH_TIMEOUT_SEC:-900}"
REUSE_EXISTING_WORKLOAD="${REUSE_EXISTING_WORKLOAD:-0}"
CLEANUP_BEFORE_RUN="${CLEANUP_BEFORE_RUN:-1}"
CLEANUP_WORKLOAD_AFTER_RUN="${CLEANUP_WORKLOAD_AFTER_RUN:-0}"

# Portable mode 預設不要碰 host process / container runtime
HOST_GPU_CLEANUP="${HOST_GPU_CLEANUP:-0}"
AUTO_KILL_ORPHAN_GPU_PROCS="${AUTO_KILL_ORPHAN_GPU_PROCS:-0}"
AUTO_FORCE_CLEAN_STUCK_PODS="${AUTO_FORCE_CLEAN_STUCK_PODS:-1}"
AUTO_RESTART_RUNTIME_ON_STUCK_POD="${AUTO_RESTART_RUNTIME_ON_STUCK_POD:-0}"
RESULT_ROOT="${RESULT_ROOT:-results}"
TS="$(date +%Y%m%d-%H%M%S)"

HAMI_PROFILE="${HAMI_PROFILE:-}"

if [[ "$MODE" == "hami" ]]; then
  HAMI_PROFILE="${HAMI_PROFILE:-config-aligned}"
fi

if [[ -n "${OUT_DIR_BASE:-}" ]]; then
  OUT_DIR="${OUT_DIR_BASE}/r${REPLICAS}_c${CONCURRENCY}_${TS}"
else
  if [[ "$MODE" == "hami" ]]; then
    OUT_DIR="${RESULT_ROOT}/${MODE}/${HAMI_PROFILE}/r${REPLICAS}_c${CONCURRENCY}_${TS}"
  else
    OUT_DIR="${RESULT_ROOT}/${MODE}/r${REPLICAS}_c${CONCURRENCY}_${TS}"
  fi
fi

mkdir -p "$OUT_DIR"

if [[ -x ".venv/bin/python" ]]; then
  PYTHON_BIN="${PYTHON_BIN:-.venv/bin/python}"
else
  PYTHON_BIN="${PYTHON_BIN:-python3}"
fi

if [[ "$MODE" == "timeslicing" ]]; then
  DEPLOY="k8s/timeslicing/vllm-timeslicing.yaml"
  DEPLOY_NAME="vllm-timeslicing"
elif [[ "$MODE" == "hami" ]]; then
  if [[ "$HAMI_PROFILE" == "config-aligned" ]]; then
    DEPLOY="k8s/hami/vllm-hami-config-aligned.yaml"
  elif [[ "$HAMI_PROFILE" == "memory-aligned" ]]; then
    DEPLOY="k8s/hami/vllm-hami-memory-aligned.yaml"
  elif [[ "$HAMI_PROFILE" == "controlled" ]]; then
    DEPLOY="k8s/hami/vllm-hami-controlled.yaml"
  else
    echo "[ERROR] Invalid HAMI_PROFILE: $HAMI_PROFILE"
    echo "[ERROR] Valid values: config-aligned | memory-aligned | controlled"
    exit 1
  fi

  DEPLOY_NAME="vllm-hami"
else
  echo "[ERROR] Invalid mode: $MODE"
  echo "[ERROR] Valid values: timeslicing | hami"
  exit 1
fi

echo "[INFO] Mode: $MODE"
echo "[INFO] HAMI profile: ${HAMI_PROFILE:-N/A}"
echo "[INFO] Replicas: $REPLICAS"
echo "[INFO] Concurrency: $CONCURRENCY"
echo "[INFO] Num requests: $NUM_REQUESTS"
echo "[INFO] Warmup requests per endpoint: $WARMUP_REQUESTS_PER_ENDPOINT"
echo "[INFO] Bench request timeout sec: $BENCH_REQUEST_TIMEOUT_SEC"
echo "[INFO] Bench connect timeout sec: $BENCH_CONNECT_TIMEOUT_SEC"
echo "[INFO] Bench total timeout sec: $BENCH_TIMEOUT_SEC"
echo "[INFO] Reuse existing workload: $REUSE_EXISTING_WORKLOAD"
echo "[INFO] Cleanup before run: $CLEANUP_BEFORE_RUN"
echo "[INFO] Cleanup workload after run: $CLEANUP_WORKLOAD_AFTER_RUN"
echo "[INFO] Host GPU cleanup: $HOST_GPU_CLEANUP"
echo "[INFO] Auto kill orphan GPU processes: $AUTO_KILL_ORPHAN_GPU_PROCS"
echo "[INFO] Auto force clean stuck pods: $AUTO_FORCE_CLEAN_STUCK_PODS"
echo "[INFO] Auto restart runtime on stuck pod: $AUTO_RESTART_RUNTIME_ON_STUCK_POD"
echo "[INFO] Output dir: $OUT_DIR"
echo "[INFO] Deploy manifest: $DEPLOY"
echo "[INFO] Python: $PYTHON_BIN"

sudo_prefix=()
if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
  sudo_prefix=()
elif command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
  sudo_prefix=(sudo -n)
fi

is_true() {
  local v="${1:-}"
  [[ "$v" == "1" || "$v" == "true" || "$v" == "yes" ]]
}

force_cleanup_stuck_vllm_pods() {
  local names=()
  mapfile -t names < <(kubectl get pods -l app=vllm --no-headers 2>/dev/null | awk '{print $1}')

  if [[ "${#names[@]}" -eq 0 ]]; then
    return 0
  fi

  echo "[WARN] Force cleaning stuck vLLM pods: ${names[*]}"

  for pod in "${names[@]}"; do
    mapfile -t cids < <(kubectl get pod "$pod" -o jsonpath='{range .status.containerStatuses[*]}{.containerID}{"\n"}{end}' 2>/dev/null | sed '/^$/d')

    for full_id in "${cids[@]:-}"; do
      cid="${full_id##*://}"
      [[ -n "$cid" ]] || continue

      if command -v crictl >/dev/null 2>&1; then
        "${sudo_prefix[@]}" crictl stop "$cid" 2>/dev/null || true
        "${sudo_prefix[@]}" crictl rm "$cid" 2>/dev/null || true
      fi

      if command -v ctr >/dev/null 2>&1; then
        "${sudo_prefix[@]}" ctr -n k8s.io tasks kill -s SIGKILL "$cid" 2>/dev/null || true
        "${sudo_prefix[@]}" ctr -n k8s.io tasks rm -f "$cid" 2>/dev/null || true
        "${sudo_prefix[@]}" ctr -n k8s.io containers rm "$cid" 2>/dev/null || true
      fi
    done

    kubectl delete pod "$pod" --grace-period=0 --force 2>/dev/null || true
  done

  return 0
}

restart_runtime_if_enabled() {
  if ! is_true "$AUTO_RESTART_RUNTIME_ON_STUCK_POD"; then
    return 0
  fi

  if [[ "${#sudo_prefix[@]}" -eq 0 && "${EUID:-$(id -u)}" -ne 0 ]]; then
    echo "[WARN] Runtime restart skipped: passwordless sudo not available"
    return 0
  fi

  echo "[WARN] Restarting container runtime services due to stuck terminating pods"
  "${sudo_prefix[@]}" systemctl restart containerd || true
  "${sudo_prefix[@]}" systemctl restart kubelet || true
  sleep 5
}

kill_orphan_vllm_gpu_processes() {
  echo "[INFO] Checking orphan vLLM GPU processes"

  if ! command -v nvidia-smi >/dev/null 2>&1; then
    return 0
  fi

  local pids=()
  mapfile -t pids < <(
    nvidia-smi --query-compute-apps=pid --format=csv,noheader,nounits 2>/dev/null \
      | tr -d ' ' \
      | sed '/^$/d' \
      | sort -u
  )

  if [[ "${#pids[@]}" -eq 0 ]]; then
    echo "[INFO] No GPU compute processes found"
    return 0
  fi

  local targets=()

  for pid in "${pids[@]}"; do
    [[ -d "/proc/$pid" ]] || continue

    local cmdline=""
    local cgroup=""
    local user_name=""

    cmdline="$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null || true)"
    cgroup="$(cat "/proc/$pid/cgroup" 2>/dev/null || true)"
    user_name="$(ps -o user= -p "$pid" 2>/dev/null | awk '{print $1}')"

    if [[ "$cmdline" == *"vllm.entrypoints.openai.api_server"* \
       || "$cmdline" == *"multiprocessing.spawn"* \
       || "$cmdline" == *"multiprocessing.resource_tracker"* \
       || ( "$cmdline" == *"/usr/bin/python3"* && "$cgroup" == *"kubepods"* ) ]]; then

      echo "[WARN] Found orphan vLLM GPU process pid=$pid user=$user_name cmd=$cmdline"
      targets+=("$pid")
    fi
  done

  if [[ "${#targets[@]}" -eq 0 ]]; then
    echo "[INFO] No orphan vLLM GPU processes found"
    return 0
  fi

  for pid in "${targets[@]}"; do
    [[ -d "/proc/$pid" ]] || continue
    echo "[WARN] Sending SIGTERM to pid=$pid"
    "${sudo_prefix[@]}" kill -TERM "$pid" 2>/dev/null || kill -TERM "$pid" 2>/dev/null || true
  done

  sleep 3

  for pid in "${targets[@]}"; do
    [[ -d "/proc/$pid" ]] || continue
    echo "[WARN] Sending SIGKILL to pid=$pid"
    "${sudo_prefix[@]}" kill -KILL "$pid" 2>/dev/null || kill -KILL "$pid" 2>/dev/null || true
  done

  sleep 3

  local still_alive=()

  for pid in "${targets[@]}"; do
    if [[ -d "/proc/$pid" ]]; then
      local stat=""
      stat="$(ps -o stat= -p "$pid" 2>/dev/null | awk '{print $1}')"

      if [[ "$stat" == Z* ]]; then
        echo "[WARN] pid=$pid is zombie; waiting for parent/container runtime cleanup"
      else
        echo "[ERROR] pid=$pid still alive after SIGKILL stat=$stat"
        still_alive+=("$pid")
      fi
    fi
  done

  if [[ "${#still_alive[@]}" -gt 0 ]]; then
    echo "[WARN] Orphan GPU processes remain after kill: ${still_alive[*]}"
    restart_runtime_if_enabled
    sleep 10

    local after_restart_alive=0

    for pid in "${still_alive[@]}"; do
      if [[ -d "/proc/$pid" ]]; then
        echo "[ERROR] pid=$pid still alive after runtime restart"
        after_restart_alive=1
      fi
    done

    if [[ "$after_restart_alive" -eq 1 ]]; then
      echo "[ERROR] Failed to remove orphan GPU processes"
      nvidia-smi || true
      exit 1
    fi
  fi

  echo "[INFO] Orphan vLLM GPU process cleanup completed"
}

patch_vllm_pod_finalizers() {
  local pods=()
  mapfile -t pods < <(kubectl get pods -l app=vllm --no-headers 2>/dev/null | awk 'NF {print $1}')

  for pod in "${pods[@]:-}"; do
    [[ -n "$pod" ]] || continue
    echo "[WARN] Patching finalizers for pod=$pod"
    kubectl patch pod "$pod" \
      -p '{"metadata":{"finalizers":null}}' \
      --type=merge 2>/dev/null || true
  done
}

wait_until_no_vllm_pods() {
  local timeout_sec="${1:-30}"
  local deadline=$((SECONDS + timeout_sec))

  while (( SECONDS < deadline )); do
    local left
    left="$(kubectl get pods -l app=vllm --no-headers 2>/dev/null | wc -l)"

    if [[ "$left" == "0" ]]; then
      return 0
    fi

    sleep 2
  done

  return 1
}

cleanup_vllm_workload() {
  local phase="${1:-cleanup}"

  nvidia-smi > "$OUT_DIR/nvidia_smi_cleanup_${phase}_before.txt" 2>&1 || true

  echo "[INFO] Cleanup vLLM workload phase=$phase"

  echo "[INFO] Scaling old deployments to zero"
  kubectl scale deploy vllm-timeslicing --replicas=0 --timeout=30s 2>/dev/null || true
  kubectl scale deploy vllm-hami --replicas=0 --timeout=30s 2>/dev/null || true

  echo "[INFO] Deleting old deployments/services without waiting"
  kubectl delete deploy vllm-timeslicing --ignore-not-found --wait=false 2>/dev/null || true
  kubectl delete deploy vllm-hami --ignore-not-found --wait=false 2>/dev/null || true
  kubectl delete svc vllm-service --ignore-not-found --wait=false 2>/dev/null || true

  echo "[INFO] Requesting graceful vLLM pod deletion"
  kubectl delete pod -l app=vllm --ignore-not-found --wait=false 2>/dev/null || true

  if wait_until_no_vllm_pods 30; then
    echo "[INFO] Old vLLM pods removed gracefully"
  else
    echo "[WARN] Old vLLM pods still exist after graceful wait"
    kubectl get pods -l app=vllm -o wide || true

    echo "[WARN] Force deleting vLLM pods"
    kubectl delete pod -l app=vllm \
      --grace-period=0 \
      --force \
      --wait=false \
      --ignore-not-found 2>/dev/null || true

    sleep 3

    patch_vllm_pod_finalizers

    if ! wait_until_no_vllm_pods 20; then
      echo "[WARN] vLLM pods still exist after force delete; cleaning container runtime objects"
      force_cleanup_stuck_vllm_pods
    fi

    if ! wait_until_no_vllm_pods 20; then
      echo "[WARN] vLLM pods still stuck after runtime object cleanup"
      restart_runtime_if_enabled
    fi
  fi

  if ! wait_until_no_vllm_pods 30; then
    echo "[ERROR] Failed to cleanup old vLLM pods"
    kubectl get pods -l app=vllm -o wide || true
    kubectl describe pods -l app=vllm > "$OUT_DIR/pods_cleanup_error.txt" 2>/dev/null || true
    nvidia-smi > "$OUT_DIR/nvidia_smi_cleanup_error.txt" 2>&1 || true
    exit 1
  fi

  if is_true "$HOST_GPU_CLEANUP" && is_true "$AUTO_KILL_ORPHAN_GPU_PROCS"; then
    kill_orphan_vllm_gpu_processes
  else
    echo "[INFO] Host GPU process cleanup disabled; skipping orphan GPU PID kill"
  fi

  echo "[INFO] vLLM workload cleanup completed"
  nvidia-smi > "$OUT_DIR/nvidia_smi_cleanup_${phase}_after.txt" 2>&1 || true
}

if is_true "$REUSE_EXISTING_WORKLOAD"; then
  echo "[INFO] Reusing existing workload"

  if ! kubectl get deploy "$DEPLOY_NAME" >/dev/null 2>&1; then
    echo "[ERROR] REUSE_EXISTING_WORKLOAD=1 but deployment $DEPLOY_NAME does not exist"
    exit 1
  fi
else
  if is_true "$CLEANUP_BEFORE_RUN"; then
    echo "[INFO] Cleaning old workload"
    cleanup_vllm_workload "before-run"
  else
    echo "[INFO] Cleanup before run disabled"
  fi

  echo "[INFO] Applying workload"
  kubectl apply -f "$DEPLOY"
  kubectl apply -f k8s/common/service.yaml

  echo "[INFO] Scaling deployment to replicas=$REPLICAS"
  kubectl scale deploy "$DEPLOY_NAME" --replicas="$REPLICAS"

  echo "[INFO] Waiting for rollout"

  if ! kubectl rollout status deploy/"$DEPLOY_NAME" --timeout=600s; then
    echo "[ERROR] Rollout failed or timed out"
    kubectl get pods -l app=vllm -o wide || true
    kubectl get pods -l app=vllm -o wide > "$OUT_DIR/pods_rollout_error.txt" || true
    kubectl describe pods -l app=vllm > "$OUT_DIR/pods_describe_error.txt" || true
    kubectl logs -l app=vllm --all-containers=true --tail=200 > "$OUT_DIR/pods_logs_error.txt" 2>&1 || true
    kubectl describe node "$NODE_NAME" > "$OUT_DIR/node_describe_rollout_error.txt" || true
    nvidia-smi > "$OUT_DIR/nvidia_smi_rollout_error.txt" 2>&1 || true
    exit 1
  fi
fi

READY_COUNT="$(kubectl get pods -l app=vllm \
  -o jsonpath='{range .items[*]}{.status.containerStatuses[0].ready}{"\n"}{end}' \
  | grep -c true || true)"

echo "[INFO] Ready vLLM pods: $READY_COUNT / $REPLICAS"

if [[ "$READY_COUNT" -ne "$REPLICAS" ]]; then
  echo "[ERROR] Not all vLLM pods are ready"
  kubectl get pods -l app=vllm -o wide || true
  kubectl get pods -l app=vllm -o wide > "$OUT_DIR/pods_ready_error.txt" || true
  kubectl describe pods -l app=vllm > "$OUT_DIR/pods_describe_error.txt" || true
  kubectl logs -l app=vllm --all-containers=true --tail=200 > "$OUT_DIR/pods_logs_error.txt" 2>&1 || true
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
  kubectl get pods -l app=vllm -o wide || true
  kubectl get endpoints vllm-service -o wide || true
  kubectl get pods -l app=vllm -o wide > "$OUT_DIR/pods_endpoint_error.txt" || true
  kubectl get endpoints vllm-service -o yaml > "$OUT_DIR/endpoints_endpoint_error.yaml" || true
  kubectl describe pods -l app=vllm > "$OUT_DIR/pods_describe_endpoint_error.txt" || true
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
    kubectl describe pods -l app=vllm > "$OUT_DIR/pods_describe_endpoint_ready_error.txt" || true
    kubectl logs -l app=vllm --all-containers=true --tail=200 > "$OUT_DIR/pods_logs_endpoint_ready_error.txt" 2>&1 || true
    exit 1
  fi
done

cat > "$OUT_DIR/experiment_config.json" <<EOF_CONFIG
{
  "mode": "$MODE",
  "hami_profile": "${HAMI_PROFILE:-}",
  "replicas": $REPLICAS,
  "concurrency": $CONCURRENCY,
  "num_requests": $NUM_REQUESTS,
  "model": "$MODEL",
  "max_tokens": $MAX_TOKENS,
  "warmup_requests_per_endpoint": $WARMUP_REQUESTS_PER_ENDPOINT,
  "endpoint_count": $ENDPOINT_COUNT,
  "endpoints": "$ENDPOINTS",
  "node_name": "$NODE_NAME",
  "deploy_manifest": "$DEPLOY",
  "out_dir": "$OUT_DIR",
  "timestamp": "$TS"
}
EOF_CONFIG

echo "[INFO] Snapshot allocation before benchmark"

kubectl get pods -l app=vllm -o wide > "$OUT_DIR/pods_before.txt"
kubectl get pods -l app=vllm -o yaml > "$OUT_DIR/pods_before.yaml"
kubectl get endpoints vllm-service -o wide > "$OUT_DIR/endpoints_before.txt"
kubectl get endpoints vllm-service -o yaml > "$OUT_DIR/endpoints_before.yaml"
kubectl describe node "$NODE_NAME" > "$OUT_DIR/node_describe_before.txt"
nvidia-smi > "$OUT_DIR/nvidia_smi_before.txt" 2>&1 || true

if [[ -f "$DEPLOY" ]]; then
  cp "$DEPLOY" "$OUT_DIR/deploy_manifest.yaml"
fi

if [[ -f "k8s/common/service.yaml" ]]; then
  cp "k8s/common/service.yaml" "$OUT_DIR/service_manifest.yaml"
fi

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
}
trap cleanup EXIT

echo "[INFO] Run benchmark"

BENCH_CMD=(
  "$PYTHON_BIN" scripts/bench_openai_stream.py
  --mode "$MODE"
  --endpoints "$ENDPOINTS"
  --model "$MODEL"
  --num-requests "$NUM_REQUESTS"
  --concurrency "$CONCURRENCY"
  --max-tokens "$MAX_TOKENS"
  --warmup-requests-per-endpoint "$WARMUP_REQUESTS_PER_ENDPOINT"
  --connect-timeout-sec "$BENCH_CONNECT_TIMEOUT_SEC"
  --request-timeout-sec "$BENCH_REQUEST_TIMEOUT_SEC"
  --output-dir "$OUT_DIR"
)

if command -v timeout >/dev/null 2>&1; then
  if ! timeout --signal=TERM --kill-after=30s "${BENCH_TIMEOUT_SEC}s" "${BENCH_CMD[@]}"; then
    RC=$?
    if [[ "$RC" -eq 124 || "$RC" -eq 137 ]]; then
      echo "[ERROR] Benchmark timed out after ${BENCH_TIMEOUT_SEC}s"
      kubectl get pods -l app=vllm -o wide > "$OUT_DIR/pods_benchmark_timeout.txt" || true
      kubectl logs -l app=vllm --all-containers=true --tail=200 > "$OUT_DIR/pods_logs_benchmark_timeout.txt" 2>&1 || true
      nvidia-smi > "$OUT_DIR/nvidia_smi_benchmark_timeout.txt" 2>&1 || true
    fi
    exit "$RC"
  fi
else
  "${BENCH_CMD[@]}"
fi

echo "[INFO] Snapshot allocation after benchmark"

kubectl get pods -l app=vllm -o wide > "$OUT_DIR/pods_after.txt"
kubectl get pods -l app=vllm -o yaml > "$OUT_DIR/pods_after.yaml"
kubectl get endpoints vllm-service -o wide > "$OUT_DIR/endpoints_after.txt"
kubectl get endpoints vllm-service -o yaml > "$OUT_DIR/endpoints_after.yaml"
kubectl describe node "$NODE_NAME" > "$OUT_DIR/node_describe_after.txt"
nvidia-smi > "$OUT_DIR/nvidia_smi_after.txt" 2>&1 || true

echo "[INFO] Summarize results"

"$PYTHON_BIN" scripts/summarize_results.py "$OUT_DIR" || true

echo "[INFO] Done: $OUT_DIR"

if [[ "${CLEANUP_WORKLOAD_AFTER_RUN:-0}" == "1" ]]; then
  cleanup_vllm_workload "after-run"
fi
