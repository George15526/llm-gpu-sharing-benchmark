# HAMi GPU Sharing Experiment

## 1. 實驗目的

本實驗評估 HAMi 作為 Kubernetes GPU sharing mechanism 時，能否穩定支援 vLLM inference workload。

HAMi 與 NVIDIA time-slicing 的主要差異在於：HAMi 不只提供 GPU sharing，還能透過 vGPU、GPU memory quota 與 GPU core quota 進行更細緻的資源控制。

本輪已完成並納入紀錄的 profile 為：

1. `config-aligned`
2. `memory-aligned`

`controlled` profile 保留作為後續展示 HAMi GPU memory + GPU core 細緻控制能力的擴充組，不納入本次已完成數據表。

## 2. HAMi 預期特性

| 特性 | NVIDIA Time-Slicing | HAMi |
|---|---|---|
| GPU sharing | 支援 | 支援 |
| GPU memory quota | 不支援 | 支援 |
| GPU core quota | 不支援 | 支援 |
| Scheduler awareness | 較弱 | 較強 |
| Isolation | 較弱 | 較強 |

## 3. 目前 HAMi 實驗環境

| 項目 | 數值 |
|---|---|
| Kubernetes | kubeadm single-node Kubernetes |
| CNI | Flannel |
| GPU | 1 × NVIDIA RTX 2000 Ada Generation |
| GPU Memory | 16380 MiB |
| Driver | 595.71.05 |
| CUDA | 13.2 |
| Runtime | containerd |
| Scheduler | HAMi scheduler |
| vLLM Image | `vllm/vllm-openai:v0.8.5` |
| Model | `Qwen/Qwen2.5-0.5B-Instruct` |

> 本版 HAMi 結果與重新執行的 NVIDIA time-slicing 結果皆來自目前同一台 RTX 2000 Ada 單機 Kubernetes 環境。HAMi 文件本身聚焦 `results/evidence/hami/`，跨機制比較請參考 `docs/result-analysis.md`。

## 4. HAMi Profile 設計

### 4.1 `config-aligned`

`config-aligned` 的目標是盡量對齊 baseline workload 的 vLLM 設定，並觀察同樣 workload 在 HAMi scheduler 下的可行性。此 profile 的重點不是展示 HAMi 的細緻切分功能，而是確認 vLLM 是否能在 HAMi 環境下穩定運作。

本次 evidence 中的 `config-aligned` 實驗包含：

| Replicas | Concurrency | Requests/Run | Repeat | 狀態 |
|---:|---:|---:|---:|---|
| 1 | 1 | 100 | 3 | 成功 300/300 |
| 1 | 2 | 100 | 3 | 成功 300/300 |
| 1 | 4 | 100 | 3 | 成功 300/300 |

常見設定：

```text
max-model-len = 512
max-num-seqs = 1
gpu-memory-utilization = 0.18
enforce-eager = true
VLLM_USE_V1 = 0
```

### 4.2 `memory-aligned`

`memory-aligned` 的目標是加入 HAMi GPU memory quota，使每個 vLLM Pod 的 GPU memory 配額更明確。此 profile 可觀察 HAMi 在 memory-aware scheduling 下的行為。

本次 evidence 中的 `memory-aligned` 實驗包含：

| Replicas | Concurrency | Requests/Run | Repeat | 狀態 |
|---:|---:|---:|---:|---|
| 1 | 1 | 100 | 3 | 成功 300/300 |
| 1 | 2 | 100 | 3 | 成功 300/300 |
| 1 | 4 | 100 | 3 | 成功 300/300 |
| 2 | 2 | 100 | 3 | 成功 300/300 |

常見 resource 設定：

```yaml
resources:
  limits:
    nvidia.com/gpu: 1
    nvidia.com/gpumem: 6000
```

常見 vLLM 設定：

```text
max-model-len = 512
max-num-seqs = 1
gpu-memory-utilization = 0.30
max-num-batched-tokens = 512
enforce-eager = true
```

### 4.3 `controlled`，後續擴充 profile

`controlled` profile 預計用於展示 HAMi 的額外細緻控制能力，例如同時設定 GPU memory quota 與 GPU core quota。

範例：

```yaml
resources:
  limits:
    nvidia.com/gpu: 1
    nvidia.com/gpumem: 6000
    nvidia.com/gpucores: 50
```

此設定會引入額外實驗變因，因此不應與 `config-aligned` 或 `memory-aligned` 的結果直接混合比較。

## 5. 已完成實驗結果摘要

本次整理的 HAMi evidence 只取用 `results/evidence/hami/` 下的資料，忽略 `results/evidence/timeslicing/`。所有表列資料均完成：

```text
repeat = 3
warmup_requests_per_endpoint = 3
formal_requests_per_run = 100
max_tokens = 128
```

| Profile | Replicas | Concurrency | Requests/Run | Repeat | 成功率 | RPS Avg | Output Tokens/s Avg | E2E Avg (ms) | E2E P95 (ms) | TTFT Avg (ms) | GPU Util Avg | GPU Mem Avg (MiB) | Evidence |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|
| `config-aligned` | 1 | 1 | 100 | 3 | 300/300 (100.00%) | 1.12 | 143.20 | 893.78 | 968.03 | 14.68 | 79.29% | 5912.99 | `results/evidence/hami/config-aligned/repeat_r1_c1_20260620-170232/repeated_summary.json` |
| `config-aligned` | 1 | 2 | 100 | 3 | 300/300 (100.00%) | 1.14 | 145.50 | 1750.87 | 1884.95 | 878.24 | 80.35% | 2959.99 | `results/evidence/hami/config-aligned/repeat_r1_c2_20260620-172519/repeated_summary.json` |
| `config-aligned` | 1 | 4 | 100 | 3 | 300/300 (100.00%) | 1.14 | 145.56 | 3465.33 | 3738.46 | 2593.22 | 81.16% | 5914.99 | `results/evidence/hami/config-aligned/repeat_r1_c4_20260620-173554/repeated_summary.json` |
| `memory-aligned` | 1 | 1 | 100 | 3 | 300/300 (100.00%) | 1.21 | 155.42 | 823.51 | 871.43 | 13.87 | 84.59% | 1769.95 | `results/evidence/hami/memory-aligned/repeat_r1_c1_20260620-120654/repeated_summary.json` |
| `memory-aligned` | 1 | 2 | 100 | 3 | 300/300 (100.00%) | 1.23 | 157.01 | 1622.21 | 1666.87 | 813.47 | 85.72% | 1769.95 | `results/evidence/hami/memory-aligned/repeat_r1_c2_20260620-122850/repeated_summary.json` |
| `memory-aligned` | 1 | 4 | 100 | 3 | 300/300 (100.00%) | 1.22 | 156.65 | 3219.73 | 3328.78 | 2409.15 | 85.24% | 1769.95 | `results/evidence/hami/memory-aligned/repeat_r1_c4_20260620-130219/repeated_summary.json` |
| `memory-aligned` | 2 | 2 | 100 | 3 | 300/300 (100.00%) | 1.31 | 168.20 | 1521.71 | 1542.60 | 18.52 | 93.55% | 3534.79 | `results/evidence/hami/memory-aligned/repeat_r2_c2_20260620-124446/repeated_summary.json` |

## 6. 詳細指標

下表為三次 repeated runs 聚合後的 mean / standard deviation 等摘要值。單位除特別標示外，latency 為 ms，GPU memory 為 MiB，power 為 W。

| Profile | Replicas | Concurrency | RPS Mean ± Std | Output Tokens/s Mean | E2E Avg Mean | E2E P50 Mean | E2E P95 Mean | E2E P99 Mean | TTFT Avg Mean | TTFT P50 Mean | TTFT P95 Mean | TTFT P99 Mean | GPU Util Avg | GPU Util Max | GPU Mem Avg | GPU Mem Max | Power Avg | Power Max |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| `config-aligned` | 1 | 1 | 1.12 ± 0.01 | 143.20 | 893.78 | 872.32 | 968.03 | 1039.40 | 14.68 | 14.33 | 17.99 | 19.41 | 79.29% | 86.00% | 5912.99 MiB | 5913.00 MiB | 52.22 W | 55.44 W |
| `config-aligned` | 1 | 2 | 1.14 ± 0.01 | 145.50 | 1750.87 | 1731.08 | 1884.95 | 2022.79 | 878.24 | 869.30 | 963.91 | 1021.39 | 80.35% | 86.00% | 2959.99 MiB | 2960.00 MiB | 53.60 W | 56.65 W |
| `config-aligned` | 1 | 4 | 1.14 ± 0.01 | 145.56 | 3465.33 | 3454.64 | 3738.46 | 3814.11 | 2593.22 | 2593.07 | 2837.91 | 2921.31 | 81.16% | 86.00% | 5914.99 MiB | 5915.00 MiB | 52.83 W | 55.70 W |
| `memory-aligned` | 1 | 1 | 1.21 ± 0.01 | 155.42 | 823.51 | 817.81 | 871.43 | 914.51 | 13.87 | 13.47 | 16.41 | 17.24 | 84.59% | 90.00% | 1769.95 MiB | 1770.00 MiB | 53.56 W | 57.50 W |
| `memory-aligned` | 1 | 2 | 1.23 ± 0.00 | 157.01 | 1622.21 | 1627.70 | 1666.87 | 1679.37 | 813.47 | 820.33 | 842.05 | 855.96 | 85.72% | 90.33% | 1769.95 MiB | 1770.00 MiB | 53.87 W | 57.69 W |
| `memory-aligned` | 1 | 4 | 1.22 ± 0.00 | 156.65 | 3219.73 | 3257.10 | 3328.78 | 3360.52 | 2409.15 | 2447.97 | 2510.67 | 2547.47 | 85.24% | 90.00% | 1769.95 MiB | 1770.00 MiB | 53.55 W | 57.40 W |
| `memory-aligned` | 2 | 2 | 1.31 ± 0.00 | 168.20 | 1521.71 | 1519.98 | 1542.60 | 1558.55 | 18.52 | 18.31 | 22.22 | 23.64 | 93.55% | 100.00% | 3534.79 MiB | 3535.00 MiB | 55.66 W | 60.46 W |

## 7. 目前機器的限制

目前 HAMi 實驗機器為單張 RTX 2000 Ada，GPU memory 約 16380 MiB。

對 `memory-aligned` 而言，若每個 Pod 設定：

```text
nvidia.com/gpumem = 6000 MiB
```

則可推得：

```text
2 Pods × 6000 MiB = 12000 MiB < 16380 MiB
4 Pods × 6000 MiB = 24000 MiB > 16380 MiB
```

因此，`r4_c4` 不適合納入目前這台單 GPU 機器的 memory-aligned 正式實驗結果。本次 evidence 中的 `memory-aligned r2_c2` 是目前已整理資料中可觀察多 Pod sharing 的主要組合。

## 8. HAMi Scheduling 觀察

HAMi scheduler 的判斷依據是 HAMi 的資源帳本與 Pod 宣告資源，而不只是 `nvidia-smi` 顯示的即時實體 GPU memory 使用量。因此，可能出現以下情況：

```text
nvidia-smi 顯示仍有空閒 GPU memory
但 Pending Pod event 顯示 CardInsufficientMemory
```

這代表 HAMi 認為該 GPU 在其 vGPU 資源模型下已無足夠可分配資源。

## 9. 初步結果解讀

本次 `config-aligned` 與 `memory-aligned` 所有納入表格的 repeated groups 均達成 `300/300` successful requests，表示目前設定在已選定矩陣內可穩定完成 benchmark。

在目前已整理的 HAMi 結果中，`memory-aligned r2_c2` 是較具代表性的 GPU sharing 成功案例。此組平均 RPS 為 `1.31`，高於 `memory-aligned r1_c1` 的 `1.21`，且平均 TTFT 維持在 `18.52 ms` 左右。這表示在兩個 vLLM Pod 分攤請求的情況下，整體吞吐量提升，同時沒有出現明顯的 first-token 延遲惡化。

單 Pod 情境下，`memory-aligned r1_c1` 的平均 E2E latency 為 `823.51 ms`，低於 `config-aligned r1_c1` 的 `893.78 ms`。不過，這個差異可能同時受到 vLLM 參數、GPU memory utilization、HAMi profile 設定與實際 GPU memory 配額影響，因此不應單獨解讀為 HAMi memory quota 本身帶來的直接效能優勢。

當單 Pod 的 concurrency 從 1 增加到 2 或 4 時，RPS 變化有限，但 E2E latency 與 TTFT 明顯上升。以 `memory-aligned` 為例，`r1_c1`、`r1_c2`、`r1_c4` 的平均 RPS 分別約為 `1.21`、`1.23`、`1.22`，但平均 E2E latency 從 `823.51 ms` 上升到 `1622.21 ms` 與 `3219.73 ms`，平均 TTFT 也從 `13.87 ms` 上升到 `813.47 ms` 與 `2409.15 ms`。這表示在目前 `max-num-seqs = 1` 的設定下，單一 vLLM Pod 面對較高 concurrency 時容易產生排隊等待。

相較之下，`memory-aligned r2_c2` 透過兩個 Pod 分攤請求，使平均 TTFT 維持在 `18.52 ms`，明顯低於 `memory-aligned r1_c2` 的 `813.47 ms`。因此，在目前單張 RTX 2000 Ada GPU 上，`memory-aligned r2_c2` 可視為 HAMi 在本實驗條件下成功進行多 Pod GPU sharing 的主要佐證。

## 10. 與 NVIDIA Time-Slicing 的比較方式

本版文件中，HAMi 與 NVIDIA time-slicing 的比較以目前同一台 RTX 2000 Ada 單機環境下重新產生的 evidence 為準：

- NVIDIA time-slicing：`results/evidence/timeslicing/`
- HAMi config-aligned：`results/evidence/hami/config-aligned/`
- HAMi memory-aligned：`results/evidence/hami/memory-aligned/`

在相同 workload 與相同硬體背景下，`memory-aligned` HAMi 與 time-slicing 在 `r1_c1`、`r1_c2`、`r1_c4`、`r2_c2` 的吞吐量與 latency 走勢相近。主要差異不只在效能數字，而在資源控制能力：time-slicing 提供較簡單的 logical GPU over-subscription；HAMi 則可額外宣告 GPU memory quota 與 GPU core quota，並由 HAMi scheduler 進行資源帳本管理。

舊版 2 × RTX 4070 SUPER time-slicing baseline 不納入本節主比較，只作為專案早期實驗背景。
