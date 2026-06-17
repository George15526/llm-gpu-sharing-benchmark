#!/usr/bin/env bash
set -euo pipefail

MODE="${1:?Usage: $0 <timeslicing|hami> <replicas> <concurrency> <num_requests> [repeat]}"
REPLICAS="${2:?Usage: $0 <timeslicing|hami> <replicas> <concurrency> <num_requests> [repeat]}"
CONCURRENCY="${3:?Usage: $0 <timeslicing|hami> <replicas> <concurrency> <num_requests> [repeat]}"
NUM_REQUESTS="${4:?Usage: $0 <timeslicing|hami> <replicas> <concurrency> <num_requests> [repeat]}"
REPEAT="${5:-3}"

RESULT_ROOT="${RESULT_ROOT:-results}"
GROUP_TS="$(date +%Y%m%d-%H%M%S)"
GROUP_DIR="${RESULT_ROOT}/${MODE}/repeat_r${REPLICAS}_c${CONCURRENCY}_${GROUP_TS}"

mkdir -p "$GROUP_DIR"

echo "[INFO] Repeated experiment group: $GROUP_DIR"
echo "[INFO] mode=$MODE replicas=$REPLICAS concurrency=$CONCURRENCY requests=$NUM_REQUESTS repeat=$REPEAT"

for i in $(seq 1 "$REPEAT"); do
  echo "=============================="
  echo "[INFO] Run $i / $REPEAT"
  echo "=============================="

  RUN_RESULT_ROOT="$GROUP_DIR" \
  RESULT_ROOT="$RUN_RESULT_ROOT" \
  bash scripts/run_experiment.sh "$MODE" "$REPLICAS" "$CONCURRENCY" "$NUM_REQUESTS"

  sleep 10
done

echo "[INFO] Aggregating repeated results"
python_bin="python3"
if [[ -x ".venv/bin/python" ]]; then
  python_bin=".venv/bin/python"
fi

"$python_bin" scripts/aggregate_repeated_results.py "$GROUP_DIR"

echo "[INFO] Done repeated experiment: $GROUP_DIR"