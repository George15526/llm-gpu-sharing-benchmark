# 實驗設計

## 1. 實驗目標

本專案的目標是比較不同 Kubernetes GPU 共享機制在 LLM inference workload 下的部署可行性、穩定性與效能表現。

實驗特別關注以下問題：

- 多個 vLLM Pod 是否能穩定共享 GPU。
- 不同 GPU sharing mechanism 對 throughput 與 latency 的影響。
- HAMi 是否能透過 GPU memory quota / GPU core quota 提供更細緻的資源控制。
- 在單 GPU 或多 GPU 環境下，不同 replicas / concurrency 組合的可行範圍。

## 2. 比較方法

| 方法 | 說明 |
|---|---|
| `NVIDIA Time-Slicing` | 使用 NVIDIA k8s-device-plugin 的 baseline GPU 共享方法 |
| `HAMi` | 使用 vGPU / memory quota / core quota 的 GPU 共享框架 |

## 3. 工作負載

| 項目 | 數值 |
|---|---|
| Model | Qwen/Qwen2.5-0.5B-Instruct |
| Serving framework | vLLM |
| API | OpenAI-compatible API |
| Image | vllm/vllm-openai:v0.8.5 |

## 4. 評估指標

- End-to-end latency
- TTFT，Time To First Token
- Requests per second，RPS
- Output tokens per second
- GPU memory usage
- GPU utilization
- Pod readiness / failure rate
- Endpoint count
- Request success / failure count

## 5. 單次實驗流程

單次實驗流程如下：

1. 清理既有 vLLM workload。
2. 部署指定的 GPU sharing workload。
3. 將 vLLM Deployment scale 到指定 replica 數量。
4. 等待所有 Pod Ready。
5. 從 `vllm-service` 收集所有 ready endpoint。
6. 驗證 endpoint 數量是否等於預期 replica 數量。
7. 對每個 endpoint 檢查 `/v1/models` readiness。
8. 對每個 endpoint 送出 warm-up requests。
9. 使用 round-robin endpoint dispatch 執行正式 benchmark requests。
10. 收集 request-level logs、summary statistics、GPU metrics、Kubernetes metrics 與 endpoint snapshots。

## 6. Warm-up Policy

正式測量前，benchmark client 會先對每個 endpoint 送出 warm-up requests。

預設設定：

```text
warmup_requests_per_endpoint = 3
```

Warm-up requests 的目的，是降低以下因素對正式數據的影響：

- CUDA lazy initialization
- vLLM generation path initialization
- tokenizer / cache setup
- GPU power-state transition
- 第一次 request 的額外初始化成本

Warm-up requests 不會被納入正式統計。

## 7. 重複實驗流程

每個正式實驗組合預設重複執行 3 次：

```bash
bash scripts/run_repeated_experiments.sh <mode> <replicas> <concurrency> <num_requests> 3
```

目前重複實驗採用 portable mode。流程如下：

1. Run 1 清理既有 workload 並部署指定的 vLLM workload。
2. Run 1 等待所有 endpoint Ready。
3. Run 1 執行 warm-up 與 formal benchmark。
4. Run 2 與 Run 3 沿用 Run 1 已經 Ready 的 workload。
5. 每一輪仍會各自執行 warm-up requests。
6. 每一輪都會輸出獨立的 request logs、summary statistics、GPU metrics、Kubernetes metrics 與 endpoint snapshots。
7. 所有 repeated runs 完成後，aggregate script 會彙整結果。

此設計避免每一輪都刪除並重新建立 vLLM Pod，降低以下問題：

- Pod 長時間停留在 `Terminating`。
- vLLM multiprocessing GPU process 殘留。
- 需要使用 `sudo kill` 或重啟 `containerd` / `kubelet`。
- 使用者 clone 專案後因 host-level 權限不足而無法完成測試。

## 8. Portable Mode 與 Maintenance Mode

### Portable Mode

Portable mode 是預設模式，目標是讓使用者 clone 專案後即可執行測試，不需要額外設定 sudoers 或重啟系統服務。

預設行為：

```text
HOST_GPU_CLEANUP=0
AUTO_KILL_ORPHAN_GPU_PROCS=0
AUTO_RESTART_RUNTIME_ON_STUCK_POD=0
```

### Maintenance Mode

Maintenance mode 僅作為本地實驗機的維護用途。當 container runtime 或 GPU process 已經殘留時，可手動啟用 host-level cleanup。

此模式可能需要 sudo 權限，不應作為一般使用者的必要執行條件。

## 9. 結果彙整

Repeated results 會彙整為 `repeated_summary.json`，內容包含：

- mean
- standard deviation
- min
- max
- p50
- p95
- p99

每個實驗組合的詳細資料會存放於 `results/` 目錄下。



## Evidence 收錄策略

目前 public evidence 僅整理可閱讀且已遮蔽敏感資訊的實驗佐證資料。正式分析主要依據：

```text
results/evidence/timeslicing/<repeat_group>/repeated_summary.json
results/evidence/hami/<profile>/<repeat_group>/repeated_summary.json
```

本次納入分析的 current-machine time-slicing repeated groups 包含：

| Mode | Replicas | Concurrency | Requests/Run | Repeat | 成功率 | RPS Avg | Output Tokens/s Avg | E2E Avg (ms) | E2E P95 (ms) | TTFT Avg (ms) | GPU Util Avg | GPU Mem Avg (MiB) | Evidence |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|
| `timeslicing` | 1 | 1 | 100 | 3 | 300/300 (100.00%) | 1.21 | 155.07 | 825.35 | 905.57 | 13.87 | 85.67% | 4749.98 | `results/evidence/timeslicing/repeat_r1_c1_20260621-211051/repeated_summary.json` |
| `timeslicing` | 1 | 2 | 100 | 3 | 300/300 (100.00%) | 1.23 | 157.61 | 1616.07 | 1657.20 | 810.37 | 86.96% | 4749.98 | `results/evidence/timeslicing/repeat_r1_c2_20260621-211656/repeated_summary.json` |
| `timeslicing` | 1 | 4 | 100 | 3 | 300/300 (100.00%) | 1.22 | 156.33 | 3227.12 | 3461.51 | 2414.73 | 85.81% | 4749.98 | `results/evidence/timeslicing/repeat_r1_c4_20260621-212319/repeated_summary.json` |
| `timeslicing` | 2 | 2 | 100 | 3 | 300/300 (100.00%) | 1.31 | 168.25 | 1520.95 | 1533.16 | 18.71 | 95.69% | 4726.93 | `results/evidence/timeslicing/repeat_r2_c2_20260621-213030/repeated_summary.json` |

HAMi repeated groups 則包含 `config-aligned` 與 `memory-aligned` 兩類 profile，完整表格請參考 `docs/hami-evidence-summary.md`。

`results/evidence/` 不重複放置 repo 內既有的 `scripts/`、`k8s/`、`docs/`，避免產生版本混淆；實驗設計與設定說明以 repo 根目錄文件為準。

Public evidence 預設不收錄 raw request logs 與高頻 Kubernetes metrics snapshots。若需要針對 Pod lifecycle 或 endpoint 狀態進行 debug，可在本機保留 debug evidence，但不建議直接放入 public repo。
