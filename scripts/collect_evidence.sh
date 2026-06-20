#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# collect_evidence.sh
#
# Purpose:
#   Collect selected, public-safe benchmark evidence into:
#
#     results/evidence/
#
# Design:
#   - Do NOT delete the whole results/evidence directory by default.
#   - Do NOT copy repo scripts/, k8s/, or docs/ into evidence.
#   - Do NOT create compressed archives.
#   - Support EVIDENCE_MANIFEST to select which result directories are published.
#   - Redact IPs, endpoints, node names, GPU UUIDs, container IDs, UIDs, paths,
#     and PIDs from public evidence files.
#
# Usage:
#   # Collect all results under results/, excluding results/evidence/
#   bash scripts/collect_evidence.sh
#
#   # Collect selected result directories only
#   EVIDENCE_MANIFEST=evidence_manifest.txt bash scripts/collect_evidence.sh
#
#   # Replace only evidence paths mapped from selected manifest entries
#   EVIDENCE_MANIFEST=evidence_manifest.txt EVIDENCE_REPLACE_SELECTED=1 \
#     bash scripts/collect_evidence.sh
#
# Manifest format:
#   - One result directory per line.
#   - Blank lines and lines starting with # are ignored.
#   - Both repeat group directories and single-run directories are supported.
#
# Example:
#   results/timeslicing/r1_c1_20260610-022818
#   results/hami/config-aligned/repeat_r1_c1_20260620-170232
#   results/hami/memory-aligned/repeat_r2_c2_20260620-180216
# ==============================================================================

RESULT_ROOT="${RESULT_ROOT:-results}"
EVIDENCE_ROOT="${EVIDENCE_ROOT:-${RESULT_ROOT}/evidence}"
EVIDENCE_MANIFEST="${EVIDENCE_MANIFEST:-}"

# 0 = merge/copy over existing evidence files
# 1 = remove only destination folders mapped from selected source folders before copying
#
# This does NOT delete the whole results/evidence directory.
EVIDENCE_REPLACE_SELECTED="${EVIDENCE_REPLACE_SELECTED:-0}"

# 1 = collect a redacted environment snapshot
# 0 = skip environment snapshot
COLLECT_ENV_SNAPSHOT="${COLLECT_ENV_SNAPSHOT:-1}"

# 1 = copy raw request logs, usually large and not recommended for public repos
# 0 = do not copy requests.jsonl
COPY_RAW_REQUESTS="${COPY_RAW_REQUESTS:-0}"
COPY_K8S_METRICS="${COPY_K8S_METRICS:-0}"
COPY_K8S_YAML="${COPY_K8S_YAML:-0}"

# Optional node override. If empty, the first Kubernetes node is used.
NODE_NAME="${NODE_NAME:-}"

RESULT_ROOT="${RESULT_ROOT%/}"
EVIDENCE_ROOT="${EVIDENCE_ROOT%/}"
OUT_DIR="$EVIDENCE_ROOT"

echo "[INFO] Result root: $RESULT_ROOT"
echo "[INFO] Evidence output: $OUT_DIR"

if [[ ! -d "$RESULT_ROOT" ]]; then
  echo "[ERROR] RESULT_ROOT not found: $RESULT_ROOT"
  echo "[ERROR] Please run experiments first or set RESULT_ROOT=/path/to/results"
  exit 1
fi

if [[ -n "$EVIDENCE_MANIFEST" && ! -f "$EVIDENCE_MANIFEST" ]]; then
  echo "[ERROR] EVIDENCE_MANIFEST not found: $EVIDENCE_MANIFEST"
  exit 1
fi

mkdir -p "$OUT_DIR"

if [[ -z "$NODE_NAME" ]]; then
  NODE_NAME="$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
fi
NODE_NAME="${NODE_NAME:-unknown}"

# ------------------------------------------------------------------------------
# Helper functions
# ------------------------------------------------------------------------------

is_under_evidence_dir() {
  local path="$1"
  [[ "$path" == "$EVIDENCE_ROOT" || "$path" == "$EVIDENCE_ROOT/"* ]]
}

result_relative_path() {
  local path="$1"
  path="${path%/}"
  echo "${path#${RESULT_ROOT}/}"
}

detect_mode_profile() {
  local rel="$1"
  local mode="unknown"
  local profile="N/A"

  if [[ "$rel" == timeslicing/* ]]; then
    mode="timeslicing"
  elif [[ "$rel" == hami/* ]]; then
    mode="hami"
    profile="$(echo "$rel" | cut -d/ -f2)"
  fi

  echo -e "${mode}\t${profile}"
}

extract_r_c_from_basename() {
  local base="$1"
  local replicas="NA"
  local concurrency="NA"

  if [[ "$base" =~ ^repeat_r([0-9]+)_c([0-9]+)_.*$ ]]; then
    replicas="${BASH_REMATCH[1]}"
    concurrency="${BASH_REMATCH[2]}"
  elif [[ "$base" =~ ^r([0-9]+)_c([0-9]+)_.*$ ]]; then
    replicas="${BASH_REMATCH[1]}"
    concurrency="${BASH_REMATCH[2]}"
  fi

  echo -e "${replicas}\t${concurrency}"
}

selected_dirs_from_manifest() {
  local manifest="$1"

  grep -vE '^[[:space:]]*($|#)' "$manifest" \
    | sed 's/\r$//' \
    | sed 's/[[:space:]]*$//' \
    | while IFS= read -r dir; do
        dir="${dir%/}"

        if [[ ! -d "$dir" ]]; then
          echo "[WARN] Skip missing directory from manifest: $dir" >&2
          continue
        fi

        if is_under_evidence_dir "$dir"; then
          echo "[WARN] Skip evidence directory from manifest: $dir" >&2
          continue
        fi

        printf '%s\n' "$dir"
      done
}

find_all_result_files() {
  local pattern="$1"

  find "$RESULT_ROOT" \
    \( -path "$EVIDENCE_ROOT" -o -path "$EVIDENCE_ROOT/*" \) -prune \
    -o -type f -name "$pattern" -print \
    | sort
}

find_selected_repeat_summaries() {
  if [[ -n "$EVIDENCE_MANIFEST" ]]; then
    selected_dirs_from_manifest "$EVIDENCE_MANIFEST" \
      | while IFS= read -r dir; do
          find "$dir" -type f -name repeated_summary.json
        done \
      | sort -u
  else
    find_all_result_files repeated_summary.json
  fi
}

find_selected_experiment_configs() {
  if [[ -n "$EVIDENCE_MANIFEST" ]]; then
    selected_dirs_from_manifest "$EVIDENCE_MANIFEST" \
      | while IFS= read -r dir; do
          find "$dir" -type f -name experiment_config.json
        done \
      | sort -u
  else
    find_all_result_files experiment_config.json
  fi
}

find_selected_run_dirs() {
  find_selected_experiment_configs \
    | xargs -r dirname \
    | sort -u
}

copy_file_if_exists() {
  local src="$1"
  local dst_dir="$2"

  [[ -f "$src" ]] || return 0

  mkdir -p "$dst_dir"
  cp "$src" "$dst_dir/"
}

copy_dir_redacted_if_exists() {
  local src_dir="$1"
  local dst_dir="$2"

  [[ -d "$src_dir" ]] || return 0

  mkdir -p "$dst_dir"

  while IFS= read -r src_file; do
    local rel_file
    rel_file="${src_file#${src_dir}/}"

    mkdir -p "$dst_dir/$(dirname "$rel_file")"
    redact_file "$src_file" "$dst_dir/$rel_file"
  done < <(find "$src_dir" -type f | sort)
}

replace_selected_dest_if_needed() {
  local src_dir="$1"

  [[ "$EVIDENCE_REPLACE_SELECTED" == "1" ]] || return 0

  local rel
  rel="$(result_relative_path "$src_dir")"

  if [[ "$rel" == "$src_dir" ]]; then
    echo "[WARN] Skip replace for path outside RESULT_ROOT: $src_dir"
    return 0
  fi

  local dest="$OUT_DIR/$rel"

  if [[ -e "$dest" ]]; then
    echo "[INFO] Replacing selected evidence path: $dest"
    rm -rf "$dest"
  fi
}

escape_sed_pattern() {
  printf '%s' "$1" | sed -E 's/[][\/.^$*+?{}()|]/\\&/g'
}

redact_stream_static() {
  sed -E \
    -e 's#https?://[0-9]{1,3}(\.[0-9]{1,3}){3}(:[0-9]+)?#http://<ENDPOINT_REDACTED>#g' \
    -e 's#([0-9]{1,3}\.){3}[0-9]{1,3}#<IP_REDACTED>#g' \
    -e 's#GPU-[A-Fa-f0-9-]+#GPU-<UUID_REDACTED>#g' \
    -e 's#containerd://[A-Fa-f0-9]+#containerd://<CONTAINER_ID_REDACTED>#g' \
    -e 's#docker://[A-Fa-f0-9]+#docker://<CONTAINER_ID_REDACTED>#g' \
    -e 's#[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}#<UUID_REDACTED>#g' \
    -e 's#(/home/)[^/[:space:]]+#\1<USER_REDACTED>#g' \
    -e 's#(/mnt/data/)[^/[:space:]]+#\1<PATH_REDACTED>#g' \
    -e 's#(/data/hf-cache)#/data/<HF_CACHE_REDACTED>#g' \
    -e 's#(node_name": ")[^"]+#\1<NODE_NAME_REDACTED>#g' \
    -e 's#(nodeName: )[A-Za-z0-9._-]+#\1<NODE_NAME_REDACTED>#g' \
    -e 's#(Node:)[[:space:]]+[A-Za-z0-9._-]+#\1 <NODE_NAME_REDACTED>#g' \
    -e 's#(NODE:)[[:space:]]+[A-Za-z0-9._-]+#\1 <NODE_NAME_REDACTED>#g' \
    -e 's#(HOSTNAME=)[A-Za-z0-9._-]+#\1<HOSTNAME_REDACTED>#g' \
    -e 's#wtlee[A-Za-z0-9._-]*#<NODE_NAME_REDACTED>#g' \
    -e 's#(pid=)[0-9]+#\1<PID_REDACTED>#g' \
    -e 's#(PID[[:space:]]+)[0-9]+#\1<PID_REDACTED>#g' \
    -e 's#([[:space:]])[0-9]{6,}([[:space:]])#\1<PID_OR_ID_REDACTED>\2#g'
}

redact_file() {
  local src="$1"
  local dst="$2"

  [[ -f "$src" ]] || return 0

  mkdir -p "$(dirname "$dst")"

  local tmp
  tmp="$(mktemp)"

  redact_stream_static < "$src" > "$tmp"

  if [[ -n "$NODE_NAME" && "$NODE_NAME" != "unknown" ]]; then
    local escaped_node
    escaped_node="$(escape_sed_pattern "$NODE_NAME")"
    sed -E -i "s#${escaped_node}#<NODE_NAME_REDACTED>#g" "$tmp"
  fi

  mv "$tmp" "$dst"
}

redacted_name() {
  local filename="$1"
  local base=""
  local ext=""

  if [[ "$filename" == *.* ]]; then
    base="${filename%.*}"
    ext="${filename##*.}"
    echo "${base}.redacted.${ext}"
  else
    echo "${filename}.redacted"
  fi
}

copy_redacted_same_name_if_exists() {
  local src="$1"
  local dst_dir="$2"

  [[ -f "$src" ]] || return 0

  mkdir -p "$dst_dir"
  redact_file "$src" "$dst_dir/$(basename "$src")"
}

copy_redacted_with_suffix_if_exists() {
  local src="$1"
  local dst_dir="$2"

  [[ -f "$src" ]] || return 0

  mkdir -p "$dst_dir"
  local name
  name="$(redacted_name "$(basename "$src")")"
  redact_file "$src" "$dst_dir/$name"
}

# ------------------------------------------------------------------------------
# 1. Optional environment snapshot
# ------------------------------------------------------------------------------

if [[ "$COLLECT_ENV_SNAPSHOT" == "1" ]]; then
  tmp_env="$OUT_DIR/environment_snapshot.raw.txt"

  {
    echo "=== Evidence ==="
    echo "Generated at: $(date)"
    echo "Result root: $RESULT_ROOT"
    echo "Evidence root: $OUT_DIR"

    if [[ -n "$EVIDENCE_MANIFEST" ]]; then
      echo "Evidence manifest: $EVIDENCE_MANIFEST"
    else
      echo "Evidence manifest: N/A, collect all results"
    fi

    echo
    echo "=== Git ==="
    git rev-parse --show-toplevel 2>/dev/null || true
    git rev-parse HEAD 2>/dev/null || true
    git status --short 2>/dev/null || true

    echo
    echo "=== Date ==="
    date

    echo
    echo "=== Kubernetes ==="
    kubectl version --short 2>/dev/null || kubectl version 2>/dev/null || true

    echo
    echo "=== Nodes ==="
    kubectl get nodes -o wide 2>/dev/null || true

    echo
    echo "=== Selected Node ==="
    echo "$NODE_NAME"

    echo
    echo "=== Node GPU Resources ==="
    if [[ "$NODE_NAME" != "unknown" ]]; then
      kubectl describe node "$NODE_NAME" 2>/dev/null \
        | grep -A80 -E "Capacity|Allocatable|Allocated resources" || true
    else
      echo "Node name unavailable"
    fi

    echo
    echo "=== Pods ==="
    kubectl get pods -A -o wide 2>/dev/null || true

    echo
    echo "=== RuntimeClass ==="
    kubectl get runtimeclass 2>/dev/null || true

    echo
    echo "=== NVIDIA SMI ==="
    nvidia-smi 2>/dev/null || true
  } > "$tmp_env"

  redact_file "$tmp_env" "$OUT_DIR/environment_snapshot.txt"
  rm -f "$tmp_env"
fi

# ------------------------------------------------------------------------------
# 2. Evidence README
# ------------------------------------------------------------------------------

cat > "$OUT_DIR/README.md" <<EOF_README
# Experiment Evidence

此資料夾保存本專案挑選後的實驗佐證資料。

## 目錄說明

| 路徑 | 說明 |
|---|---|
| \`timeslicing/\` | NVIDIA time-slicing baseline 的實驗佐證資料 |
| \`hami/\` | HAMi 實驗佐證資料 |
| \`summary_index.tsv\` | repeated experiment summary 索引 |
| \`run_index.tsv\` | 單次 run 輸出索引 |
| \`environment_snapshot.txt\` | 收集 evidence 當下的 Git / Kubernetes / NVIDIA 狀態快照，已做基本資訊遮蔽 |

## 收集原則

此資料夾僅放置可閱讀的實驗數據與佐證檔案，不重複複製專案內既有的 \`scripts/\`、\`k8s/\`、\`docs/\`。

實驗設計、環境說明、疑難排解與結果分析請參考 repo 根目錄的 \`README.md\` 與 \`docs/\`。

## Public-safe Redaction

可能包含機器資訊的檔案會進行基本遮蔽，例如：

- IP / endpoint
- Node name / hostname
- GPU UUID
- Container ID
- Kubernetes UID
- Host path / user path
- PID 或大型程序 ID

EOF_README

if [[ -n "$EVIDENCE_MANIFEST" ]]; then
  cat >> "$OUT_DIR/README.md" <<EOF_README
## 收集模式

本次 evidence 是依據 manifest 檔案挑選：

\`\`\`text
$EVIDENCE_MANIFEST
\`\`\`

僅 manifest 內列出的 result directory 會被複製。
EOF_README
else
  cat >> "$OUT_DIR/README.md" <<EOF_README
## 收集模式

本次 evidence 未指定 manifest，因此會掃描 \`$RESULT_ROOT\` 底下所有結果資料夾，並排除 \`$EVIDENCE_ROOT\` 本身。
EOF_README
fi

cat >> "$OUT_DIR/README.md" <<EOF_README

## 備註

預設不複製 raw request logs，例如 \`requests.jsonl\`，避免 repo 體積過大。
EOF_README

if [[ -n "$EVIDENCE_MANIFEST" ]]; then
  cp "$EVIDENCE_MANIFEST" "$OUT_DIR/evidence_manifest.txt"
fi

# ------------------------------------------------------------------------------
# 3. Optional selected destination replacement
# ------------------------------------------------------------------------------

if [[ "$EVIDENCE_REPLACE_SELECTED" == "1" ]]; then
  if [[ -n "$EVIDENCE_MANIFEST" ]]; then
    selected_dirs_from_manifest "$EVIDENCE_MANIFEST" \
      | while IFS= read -r selected_dir; do
          replace_selected_dest_if_needed "$selected_dir"
        done
  else
    echo "[WARN] EVIDENCE_REPLACE_SELECTED=1 without EVIDENCE_MANIFEST"
    echo "[WARN] To avoid deleting unrelated evidence, no existing evidence directory will be removed."
  fi
fi

# ------------------------------------------------------------------------------
# 4. Collect repeated summaries
# ------------------------------------------------------------------------------

SUMMARY_INDEX="$OUT_DIR/summary_index.tsv"
echo -e "mode\tprofile\treplicas\tconcurrency\trepeat_group\tsource_summary_path\tevidence_summary_path" > "$SUMMARY_INDEX"

while IFS= read -r summary; do
  group_dir="$(dirname "$summary")"
  rel="$(result_relative_path "$group_dir")"

  if [[ "$rel" == "$group_dir" ]]; then
    echo "[WARN] Skip summary outside RESULT_ROOT: $summary"
    continue
  fi

  read -r mode profile < <(detect_mode_profile "$rel")
  base="$(basename "$group_dir")"
  read -r replicas concurrency < <(extract_r_c_from_basename "$base")

  dest="$OUT_DIR/$rel"
  mkdir -p "$dest"

  # repeated_summary can contain endpoints; redact and keep same filename.
  redact_file "$summary" "$dest/repeated_summary.json"

  # Copy selected group-level small files only.
  for f in \
    aggregate_summary.json \
    repeated_config.json \
    experiment_group.json
  do
    copy_redacted_same_name_if_exists "$group_dir/$f" "$dest"
  done

  # README in result groups is usually human-written; still redact defensively.
  copy_redacted_same_name_if_exists "$group_dir/README.md" "$dest"

  evidence_summary_path="$dest/repeated_summary.json"

  echo -e "${mode}\t${profile}\t${replicas}\t${concurrency}\t${group_dir}\t${summary}\t${evidence_summary_path}" >> "$SUMMARY_INDEX"
done < <(find_selected_repeat_summaries)

# ------------------------------------------------------------------------------
# 5. Build run index
# ------------------------------------------------------------------------------

RUN_INDEX="$OUT_DIR/run_index.tsv"
echo -e "mode\tprofile\treplicas\tconcurrency\trun_dir\tsummary_json\texperiment_config\tevidence_dir" > "$RUN_INDEX"

while IFS= read -r config; do
  run_dir="$(dirname "$config")"
  rel="$(result_relative_path "$run_dir")"

  if [[ "$rel" == "$run_dir" ]]; then
    echo "[WARN] Skip config outside RESULT_ROOT: $config"
    continue
  fi

  read -r mode profile < <(detect_mode_profile "$rel")
  base="$(basename "$run_dir")"
  read -r replicas concurrency < <(extract_r_c_from_basename "$base")

  summary_json="NA"
  if [[ -f "$run_dir/summary.json" ]]; then
    summary_json="$run_dir/summary.json"
  elif [[ -f "$run_dir/benchmark_summary.json" ]]; then
    summary_json="$run_dir/benchmark_summary.json"
  fi

  evidence_dir="$OUT_DIR/$rel"

  echo -e "${mode}\t${profile}\t${replicas}\t${concurrency}\t${run_dir}\t${summary_json}\t${config}\t${evidence_dir}" >> "$RUN_INDEX"
done < <(find_selected_experiment_configs)

# ------------------------------------------------------------------------------
# 6. Copy public-safe run-level evidence files
# ------------------------------------------------------------------------------

while IFS= read -r run_dir; do
  rel="$(result_relative_path "$run_dir")"

  if [[ "$rel" == "$run_dir" ]]; then
    echo "[WARN] Skip run outside RESULT_ROOT: $run_dir"
    continue
  fi

  dest="$OUT_DIR/$rel"
  mkdir -p "$dest"

  # Summary/config files may contain endpoints and node names, so redact.
  for f in \
    experiment_config.json \
    summary.json \
    benchmark_summary.json
  do
    copy_redacted_same_name_if_exists "$run_dir/$f" "$dest"
  done

  # Metrics are usually numeric and useful. Redact defensively but keep same name.
  copy_redacted_same_name_if_exists "$run_dir/gpu_metrics.csv" "$dest"

  # K8s metrics are debug evidence. They are disabled by default for public evidence.
  if [[ "$COPY_K8S_METRICS" == "1" && -d "$run_dir/k8s_metrics" ]]; then
    copy_dir_redacted_if_exists "$run_dir/k8s_metrics" "$dest/k8s_metrics"
  fi

  # Diagnostic files: keep only redacted versions.
  for f in \
    bench_endpoints.txt \
    pods_before.txt \
    pods_after.txt \
    node_describe_before.txt \
    node_describe_after.txt \
    nvidia_smi_before.txt \
    nvidia_smi_after.txt \
    endpoints_before.yaml \
    endpoints_after.yaml \
    pods_describe_error.txt \
    pods_logs_error.txt \
    pods_rollout_error.txt \
    pods_ready_error.txt \
    pods_endpoint_error.txt \
    pods_describe_endpoint_error.txt \
    pods_describe_endpoint_ready_error.txt \
    pods_logs_endpoint_ready_error.txt \
    nvidia_smi_rollout_error.txt \
    nvidia_smi_benchmark_timeout.txt
  do
    copy_redacted_with_suffix_if_exists "$run_dir/$f" "$dest"
  done

  # Optional raw requests. Redact defensively if enabled.
  if [[ "$COPY_RAW_REQUESTS" == "1" ]]; then
    copy_redacted_same_name_if_exists "$run_dir/requests.jsonl" "$dest"
  fi

  if [[ "$COPY_K8S_YAML" == "1" ]]; then
    for f in \
      pods_before.yaml \
      pods_after.yaml \
      endpoints_before.yaml \
      endpoints_after.yaml
    do
      copy_redacted_with_suffix_if_exists "$run_dir/$f" "$dest"
    done
  fi

  # Intentionally not copied:
  # - repo scripts/
  # - repo k8s/
  # - repo docs/
  # - deploy_manifest.yaml
  # - service_manifest.yaml
  #
  # Those files already exist in the repo or may expose unnecessary deployment details.

done < <(find_selected_run_dirs)

# ------------------------------------------------------------------------------
# 7. Final summary and public-safety scan
# ------------------------------------------------------------------------------

echo "[INFO] Evidence collected:"
echo "$OUT_DIR"

echo
echo "[INFO] Summary index:"
echo "$SUMMARY_INDEX"

echo
echo "[INFO] Run index:"
echo "$RUN_INDEX"

echo
echo "[INFO] Public-safety scan candidates:"
if grep -R -nE '([0-9]{1,3}\.){3}[0-9]{1,3}|GPU-[A-Fa-f0-9-]+|containerd://[A-Fa-f0-9]+|docker://[A-Fa-f0-9]+' "$OUT_DIR" 2>/dev/null; then
  echo "[WARN] Potential sensitive values still exist in evidence. Please review the lines above."
else
  echo "[INFO] No obvious IP/GPU UUID/container ID patterns found."
fi

echo
echo "[INFO] Evidence tree preview:"
if command -v tree >/dev/null 2>&1; then
  tree "$OUT_DIR" -L 5
else
  find "$OUT_DIR" -maxdepth 5 | sort
fi
