#!/usr/bin/env bash
set -euo pipefail

MODE="${1:?Usage: $0 <timeslicing|hami> <replicas> <concurrency> <num_requests> [repeat]}"
REPLICAS="${2:?Usage: $0 <timeslicing|hami> <replicas> <concurrency> <num_requests> [repeat]}"
CONCURRENCY="${3:?Usage: $0 <timeslicing|hami> <replicas> <concurrency> <num_requests> [repeat]}"
NUM_REQUESTS="${4:?Usage: $0 <timeslicing|hami> <replicas> <concurrency> <num_requests> [repeat]}"
REPEAT="${5:-3}"
RUN_TIMEOUT_SEC="${RUN_TIMEOUT_SEC:-1800}"

RESULT_ROOT="${RESULT_ROOT:-results}"
GROUP_TS="$(date +%Y%m%d-%H%M%S)"

HAMI_PROFILE="${HAMI_PROFILE:-}"

if [[ "$MODE" == "hami" ]]; then
  HAMI_PROFILE="${HAMI_PROFILE:-config-aligned}"
  GROUP_DIR="${RESULT_ROOT}/${MODE}/${HAMI_PROFILE}/repeat_r${REPLICAS}_c${CONCURRENCY}_${GROUP_TS}"
else
  GROUP_DIR="${RESULT_ROOT}/${MODE}/repeat_r${REPLICAS}_c${CONCURRENCY}_${GROUP_TS}"
fi

mkdir -p "$GROUP_DIR"

echo "[INFO] Repeated experiment group: $GROUP_DIR"
echo "[INFO] mode=$MODE replicas=$REPLICAS concurrency=$CONCURRENCY requests=$NUM_REQUESTS repeat=$REPEAT"
echo "[INFO] HAMI profile: ${HAMI_PROFILE:-N/A}"
echo "[INFO] Per-run timeout sec: $RUN_TIMEOUT_SEC"

for i in $(seq 1 "$REPEAT"); do
  echo "=============================="
  echo "[INFO] Run $i / $REPEAT"
  echo "=============================="

  if [[ "$i" -eq 1 ]]; then
    REUSE_EXISTING_WORKLOAD=0
    CLEANUP_BEFORE_RUN=1
  else
    REUSE_EXISTING_WORKLOAD=1
    CLEANUP_BEFORE_RUN=0
  fi

  RUN_CMD=(
    bash scripts/run_experiment.sh "$MODE" "$REPLICAS" "$CONCURRENCY" "$NUM_REQUESTS"
  )

  if command -v timeout >/dev/null 2>&1; then
    OUT_DIR_BASE="$GROUP_DIR" \
    HAMI_PROFILE="${HAMI_PROFILE:-}" \
    REUSE_EXISTING_WORKLOAD="$REUSE_EXISTING_WORKLOAD" \
    CLEANUP_BEFORE_RUN="$CLEANUP_BEFORE_RUN" \
    CLEANUP_WORKLOAD_AFTER_RUN=0 \
    HOST_GPU_CLEANUP=0 \
    AUTO_KILL_ORPHAN_GPU_PROCS=0 \
    AUTO_RESTART_RUNTIME_ON_STUCK_POD=0 \
    timeout --signal=TERM --kill-after=30s "${RUN_TIMEOUT_SEC}s" "${RUN_CMD[@]}"
  else
    OUT_DIR_BASE="$GROUP_DIR" \
    HAMI_PROFILE="${HAMI_PROFILE:-}" \
    REUSE_EXISTING_WORKLOAD="$REUSE_EXISTING_WORKLOAD" \
    CLEANUP_BEFORE_RUN="$CLEANUP_BEFORE_RUN" \
    CLEANUP_WORKLOAD_AFTER_RUN=0 \
    HOST_GPU_CLEANUP=0 \
    AUTO_KILL_ORPHAN_GPU_PROCS=0 \
    AUTO_RESTART_RUNTIME_ON_STUCK_POD=0 \
    "${RUN_CMD[@]}"
  fi

  sleep 10
done

echo "[INFO] Aggregating repeated results"

python_bin="python3"
if [[ -x ".venv/bin/python" ]]; then
  python_bin=".venv/bin/python"
fi

"$python_bin" scripts/aggregate_repeated_results.py "$GROUP_DIR"

echo "[INFO] Done repeated experiment: $GROUP_DIR"
