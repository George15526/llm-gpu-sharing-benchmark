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

> 注意：目前 HAMi 實驗與原始 time-slicing baseline 使用的硬體不同，因此本文件記錄的是目前單 GPU 機器上的 HAMi 實驗結果，不應直接與舊 baseline 的絕對效能數值做硬體等價比較。

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

| Profile          | Replicas | Concurrency | Runs | Requests | Success | Failed | Avg RPS | Avg output tok/s | Avg E2E latency (ms) | P95 E2E latency (ms) | Avg TTFT (ms) | P95 TTFT (ms) | Avg GPU util (%) | Max GPU util (%) | Avg GPU mem (MiB) | Max GPU mem (MiB) |
| ---------------- | -------: | ----------: | ---: | -------: | ------: | -----: | ------: | ---------------: | -------------------: | -------------------: | ------------: | ------------: | ---------------: | ---------------: | ----------------: | ----------------: |
| `config-aligned` |        1 |           1 |    3 |      300 |     300 |      0 |   1.119 |           143.20 |               893.78 |               968.03 |         14.68 |         17.99 |            79.29 |            86.00 |           5912.99 |           5913.00 |
| `config-aligned` |        1 |           2 |    3 |      300 |     300 |      0 |   1.137 |           145.50 |              1750.87 |              1884.95 |        878.24 |        963.91 |            80.35 |            86.00 |           2959.99 |           2960.00 |
| `config-aligned` |        1 |           4 |    3 |      300 |     300 |      0 |   1.137 |           145.56 |              3465.33 |              3738.46 |       2593.22 |       2837.91 |            81.16 |            86.00 |           5914.99 |           5915.00 |
| `memory-aligned` |        1 |           1 |    3 |      300 |     300 |      0 |   1.214 |           155.42 |               823.51 |               871.43 |         13.87 |         16.41 |            84.59 |            90.00 |           1769.95 |           1770.00 |
| `memory-aligned` |        1 |           2 |    3 |      300 |     300 |      0 |   1.227 |           157.01 |              1622.21 |              1666.87 |        813.47 |        842.05 |            85.72 |            90.33 |           1769.95 |           1770.00 |
| `memory-aligned` |        1 |           4 |    3 |      300 |     300 |      0 |   1.224 |           156.65 |              3219.73 |              3328.78 |       2409.15 |       2510.67 |            85.24 |            90.00 |           1769.95 |           1770.00 |
| `memory-aligned` |        2 |           2 |    3 |      300 |     300 |      0 |   1.314 |           168.20 |              1521.71 |              1542.60 |         18.52 |         22.22 |            93.55 |           100.00 |           3534.79 |           3535.00 |


## 6. 詳細指標

下表為三次 repeated runs 聚合後的 mean / standard deviation 等摘要值。單位除特別標示外，latency 為 ms，GPU memory 為 MiB，power 為 W。

| Profile          | Group                          | Run | Requests | Success | Failed |   RPS | Output tok/s | Avg E2E latency (ms) | P95 E2E latency (ms) | Avg TTFT (ms) | P95 TTFT (ms) | Avg GPU util (%) | Max GPU util (%) | Avg GPU mem (MiB) | Max GPU mem (MiB) |
| ---------------- | ------------------------------ | --: | -------: | ------: | -----: | ----: | -----------: | -------------------: | -------------------: | ------------: | ------------: | ---------------: | ---------------: | ----------------: | ----------------: |
| `config-aligned` | `repeat_r1_c1_20260620-170232` |   1 |      100 |     100 |      0 | 1.118 |       143.10 |               894.40 |               968.88 |         14.97 |         19.22 |            78.46 |            86.00 |           5912.96 |           5913.00 |
| `config-aligned` | `repeat_r1_c1_20260620-170232` |   2 |      100 |     100 |      0 | 1.124 |       143.92 |               889.29 |               965.54 |         14.49 |         17.31 |            80.26 |            86.00 |           5913.00 |           5913.00 |
| `config-aligned` | `repeat_r1_c1_20260620-170232` |   3 |      100 |     100 |      0 | 1.114 |       142.58 |               897.63 |               969.66 |         14.58 |         17.44 |            79.15 |            86.00 |           5913.00 |           5913.00 |
| `config-aligned` | `repeat_r1_c2_20260620-172519` |   1 |      100 |     100 |      0 | 1.140 |       145.88 |              1746.14 |              1907.46 |        875.88 |        967.81 |            79.68 |            86.00 |           2959.96 |           2960.00 |
| `config-aligned` | `repeat_r1_c2_20260620-172519` |   2 |      100 |     100 |      0 | 1.125 |       144.04 |              1768.34 |              1908.48 |        886.87 |        968.81 |            80.33 |            86.00 |           2960.00 |           2960.00 |
| `config-aligned` | `repeat_r1_c2_20260620-172519` |   3 |      100 |     100 |      0 | 1.145 |       146.56 |              1738.14 |              1838.89 |        871.97 |        955.11 |            81.03 |            86.00 |           2960.00 |           2960.00 |
| `config-aligned` | `repeat_r1_c4_20260620-173554` |   1 |      100 |     100 |      0 | 1.130 |       144.68 |              3485.40 |              3744.98 |       2608.11 |       2857.61 |            79.97 |            86.00 |           5914.96 |           5915.00 |
| `config-aligned` | `repeat_r1_c4_20260620-173554` |   2 |      100 |     100 |      0 | 1.139 |       145.75 |              3461.27 |              3768.36 |       2590.23 |       2865.75 |            81.49 |            86.00 |           5915.00 |           5915.00 |
| `config-aligned` | `repeat_r1_c4_20260620-173554` |   3 |      100 |     100 |      0 | 1.143 |       146.26 |              3449.33 |              3702.02 |       2581.33 |       2790.37 |            82.01 |            86.00 |           5915.00 |           5915.00 |
| `memory-aligned` | `repeat_r1_c1_20260620-120654` |   1 |      100 |     100 |      0 | 1.220 |       156.16 |               819.56 |               836.30 |         13.84 |         15.85 |            84.25 |            90.00 |           1769.95 |           1770.00 |
| `memory-aligned` | `repeat_r1_c1_20260620-120654` |   2 |      100 |     100 |      0 | 1.213 |       155.30 |               824.15 |               842.28 |         13.86 |         16.54 |            85.09 |            90.00 |           1769.95 |           1770.00 |
| `memory-aligned` | `repeat_r1_c1_20260620-120654` |   3 |      100 |     100 |      0 | 1.209 |       154.80 |               826.81 |               935.73 |         13.92 |         16.83 |            84.44 |            90.00 |           1769.95 |           1770.00 |
| `memory-aligned` | `repeat_r1_c2_20260620-122850` |   1 |      100 |     100 |      0 | 1.223 |       156.59 |              1626.53 |              1674.31 |        815.58 |        845.96 |            85.63 |            91.00 |           1769.95 |           1770.00 |
| `memory-aligned` | `repeat_r1_c2_20260620-122850` |   2 |      100 |     100 |      0 | 1.231 |       157.63 |              1615.94 |              1653.25 |        810.33 |        835.25 |            85.86 |            90.00 |           1769.95 |           1770.00 |
| `memory-aligned` | `repeat_r1_c2_20260620-122850` |   3 |      100 |     100 |      0 | 1.225 |       156.81 |              1624.17 |              1673.05 |        814.51 |        844.95 |            85.68 |            90.00 |           1769.95 |           1770.00 |
| `memory-aligned` | `repeat_r1_c4_20260620-130219` |   1 |      100 |     100 |      0 | 1.220 |       156.21 |              3228.35 |              3316.53 |       2415.52 |       2505.00 |            84.07 |            90.00 |           1769.95 |           1770.00 |
| `memory-aligned` | `repeat_r1_c4_20260620-130219` |   2 |      100 |     100 |      0 | 1.229 |       157.28 |              3206.95 |              3317.40 |       2399.50 |       2498.11 |            86.39 |            90.00 |           1769.95 |           1770.00 |
| `memory-aligned` | `repeat_r1_c4_20260620-130219` |   3 |      100 |     100 |      0 | 1.222 |       156.46 |              3223.87 |              3352.42 |       2412.42 |       2528.90 |            85.26 |            90.00 |           1769.95 |           1770.00 |
| `memory-aligned` | `repeat_r2_c2_20260620-124446` |   1 |      100 |     100 |      0 | 1.315 |       168.26 |              1521.03 |              1532.05 |         18.34 |         21.96 |            93.45 |           100.00 |           3534.78 |           3535.00 |
| `memory-aligned` | `repeat_r2_c2_20260620-124446` |   2 |      100 |     100 |      0 | 1.314 |       168.24 |              1521.42 |              1535.33 |         18.72 |         22.49 |            93.27 |           100.00 |           3534.78 |           3535.00 |
| `memory-aligned` | `repeat_r2_c2_20260620-124446` |   3 |      100 |     100 |      0 | 1.313 |       168.11 |              1522.68 |              1560.43 |         18.51 |         22.22 |            93.93 |           100.00 |           3534.81 |           3535.00 |


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

在目前已整理的 HAMi 結果中，`memory-aligned r2_c2` 是較具代表性的 GPU sharing 成功案例。此組平均 RPS 為 `1.314`，高於 `memory-aligned r1_c1` 的 `1.214`，且平均 TTFT 維持在 `18.52 ms` 左右。這表示在兩個 vLLM Pod 分攤請求的情況下，整體吞吐量提升，同時沒有出現明顯的 first-token 延遲惡化。

單 Pod 情境下，`memory-aligned r1_c1` 的平均 E2E latency 為 `823.51 ms`，低於 `config-aligned r1_c1` 的 `893.78 ms`。不過，這個差異可能同時受到 vLLM 參數、GPU memory utilization、HAMi profile 設定與實際 GPU memory 配額影響，因此不應單獨解讀為 HAMi memory quota 本身帶來的直接效能優勢。

當單 Pod 的 concurrency 從 1 增加到 2 或 4 時，RPS 變化有限，但 E2E latency 與 TTFT 明顯上升。以 `memory-aligned` 為例，`r1_c1`、`r1_c2`、`r1_c4` 的平均 RPS 分別約為 `1.214`、`1.227`、`1.224`，但平均 E2E latency 從 `823.51 ms` 上升到 `1622.21 ms` 與 `3219.73 ms`，平均 TTFT 也從 `13.87 ms` 上升到 `813.47 ms` 與 `2409.15 ms`。這表示在目前 `max-num-seqs = 1` 的設定下，單一 vLLM Pod 面對較高 concurrency 時容易產生排隊等待。

相較之下，`memory-aligned r2_c2` 透過兩個 Pod 分攤請求，使平均 TTFT 維持在 `18.52 ms`，明顯低於 `memory-aligned r1_c2` 的 `813.47 ms`。因此，在目前單張 RTX 2000 Ada GPU 上，`memory-aligned r2_c2` 可視為 HAMi 在本實驗條件下成功進行多 Pod GPU sharing 的主要佐證。

## 10. 與 Baseline 的比較方式

由於目前 HAMi 實驗機器與原始 NVIDIA time-slicing baseline 機器不同，因此本輪結果主要用於：

- 確認 HAMi 在目前單 GPU 機器上的部署可行性。
- 觀察 vLLM 與 HAMi 的相容性。
- 觀察 HAMi memory quota 對 Pod scheduling 的影響。
- 確認目前機器可承載的 replicas / concurrency 範圍。

不應直接使用絕對 RPS 或 latency 數值，宣稱 HAMi 與舊 time-slicing baseline 之間的效能優劣。
