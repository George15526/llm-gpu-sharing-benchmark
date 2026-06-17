#!/usr/bin/env bash
set -euo pipefail

RESULTS_DIR="results"
MODE=""
RUNS=()
ALL=0
ACTION="copy"

INCLUDE_REQUESTS=0
INCLUDE_SUMMARY=0

usage() {
  cat <<'USAGE'
Usage:
  ./scripts/collect_evidence.sh --mode timeslicing --all
  ./scripts/collect_evidence.sh --mode timeslicing --run r1_c1_20260610-022818
  ./scripts/collect_evidence.sh --mode hami --all --include-requests
  ./scripts/collect_evidence.sh --mode timeslicing --all --move

Options:
  --mode MODE            Source mode under results/, e.g. timeslicing, hami, stress-test
  --run RUN_ID           Collect one run. Can be used multiple times
  --all                  Collect all run directories under results/MODE
  --results-dir DIR      Default: results
  --include-requests     Also include requests.jsonl
  --include-summary      Also include summary.json
  --move                 Move files instead of copying them
  -h, --help             Show this help
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode)
      MODE="${2:-}"
      shift 2
      ;;
    --run)
      RUNS+=("${2:-}")
      shift 2
      ;;
    --all)
      ALL=1
      shift
      ;;
    --results-dir)
      RESULTS_DIR="${2:-}"
      shift 2
      ;;
    --include-requests)
      INCLUDE_REQUESTS=1
      shift
      ;;
    --include-summary)
      INCLUDE_SUMMARY=1
      shift
      ;;
    --move)
      ACTION="move"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ -z "$MODE" ]]; then
  echo "Error: --mode is required" >&2
  usage
  exit 1
fi

SRC_MODE_DIR="${RESULTS_DIR}/${MODE}"

if [[ ! -d "$SRC_MODE_DIR" ]]; then
  echo "Error: source directory not found: $SRC_MODE_DIR" >&2
  exit 1
fi

if [[ "$ALL" -eq 1 ]]; then
  mapfile -t RUNS < <(
    find "$SRC_MODE_DIR" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort
  )
fi

if [[ "${#RUNS[@]}" -eq 0 ]]; then
  echo "Error: no runs selected. Use --run RUN_ID or --all." >&2
  exit 1
fi

create_evidence_readme() {
  local readme="${RESULTS_DIR}/evidence/README.md"

  if [[ ! -f "$readme" ]]; then
    mkdir -p "$(dirname "$readme")"
    cat > "$readme" <<'README_EOF'
# Evidence Results

This directory contains curated benchmark evidence.

Raw benchmark outputs, temporary logs, and Kubernetes snapshots are intentionally excluded from this directory.

Recommended evidence files:

- `experiment_config.json`: benchmark configuration
- `merged_summary.json`: merged benchmark result
- `gpu_metrics.csv`: GPU utilization / memory / power metrics
- `pods_after.txt`: final Kubernetes Pod state
- `nvidia_smi_after.txt`: final GPU state
- `node_allocated_resources_after.txt`: extracted resource allocation from `node_describe_after.txt`
- `requests.jsonl`: optional per-request latency records
README_EOF
  fi
}

put_file() {
  local src="$1"
  local dst="$2"

  if [[ ! -f "$src" ]]; then
    echo "  - missing: $(basename "$src")"
    return 0
  fi

  mkdir -p "$(dirname "$dst")"

  if [[ "$ACTION" == "move" ]]; then
    mv -f "$src" "$dst"
  else
    cp -f "$src" "$dst"
  fi

  echo "  + $(basename "$dst")"
}

extract_node_allocated_resources() {
  local src="$1"
  local dst="$2"

  if [[ ! -f "$src" ]]; then
    echo "  - missing: node_describe_after.txt"
    return 0
  fi

  mkdir -p "$(dirname "$dst")"

  {
    echo "# Extracted from: node_describe_after.txt"
    echo "# Generated at: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    echo

    awk '
      /^Capacity:/ {
        capture_capacity = 1
      }

      /^System Info:/ {
        capture_capacity = 0
      }

      /^Non-terminated Pods:/ {
        capture_pods = 1
      }

      capture_capacity || capture_pods {
        print
      }
    ' "$src"
  } > "$dst"

  if [[ "$(wc -l < "$dst")" -le 3 ]]; then
    echo "  - failed to extract node allocation info"
    rm -f "$dst"
  else
    echo "  + node_allocated_resources_after.txt"
  fi
}

collect_one_run() {
  local run_id="$1"
  local src_dir="${RESULTS_DIR}/${MODE}/${run_id}"
  local dst_dir="${RESULTS_DIR}/evidence/${MODE}/${run_id}"

  if [[ ! -d "$src_dir" ]]; then
    echo "Skip: source run directory not found: $src_dir" >&2
    return 0
  fi

  echo
  echo "Collecting evidence:"
  echo "  source:      $src_dir"
  echo "  destination: $dst_dir"

  mkdir -p "$dst_dir"

  local files=(
    "experiment_config.json"
    "merged_summary.json"
    "gpu_metrics.csv"
    "pods_after.txt"
    "nvidia_smi_after.txt"
  )

  if [[ "$INCLUDE_SUMMARY" -eq 1 ]]; then
    files+=("summary.json")
  fi

  if [[ "$INCLUDE_REQUESTS" -eq 1 ]]; then
    files+=("requests.jsonl")
  fi

  for file in "${files[@]}"; do
    put_file "${src_dir}/${file}" "${dst_dir}/${file}"
  done

  extract_node_allocated_resources \
    "${src_dir}/node_describe_after.txt" \
    "${dst_dir}/node_allocated_resources_after.txt"
}

create_evidence_readme

for run_id in "${RUNS[@]}"; do
  collect_one_run "$run_id"
done

echo
echo "Done."
echo "Evidence directory: ${RESULTS_DIR}/evidence/${MODE}"