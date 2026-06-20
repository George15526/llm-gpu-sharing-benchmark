# 結果分析

## 1. 說明

本文件整理目前專案中的實驗結果。此次更新只取用 `results/evidence/hami/` 下的 HAMi evidence，並忽略 `results/evidence/timeslicing/` 內的資料。

需要特別注意的是，原始 NVIDIA time-slicing baseline 與目前 HAMi 實驗使用的硬體環境不同：

| 類別 | 環境 |
|---|---|
| Legacy time-slicing baseline | 2 × RTX 4070 SUPER |
| Current HAMi experiment | 1 × NVIDIA RTX 2000 Ada Generation |

因此，time-slicing baseline 結果與目前 HAMi 結果不應直接做硬體等價的效能比較。較適合的解讀方式是：

- time-slicing baseline：作為舊環境的 baseline 行為與效能參考。
- HAMi results：作為目前單 GPU 機器上的 HAMi 可行性、穩定性與資源控制行為紀錄。

## 2. Current HAMi Experiment Results

目前 HAMi 實驗已完成 `config-aligned` 與 `memory-aligned` 兩類 profile，且每組皆採用：

```text
repeat = 3
warmup_requests_per_endpoint = 3
formal_requests_per_run = 100
max_tokens = 128
model = Qwen/Qwen2.5-0.5B-Instruct
```

### 2.1 HAMi 聚合摘要

| Profile | Replicas | Concurrency | Requests/Run | Repeat | 成功率 | RPS Avg | Output Tokens/s Avg | E2E Avg (ms) | E2E P95 (ms) | TTFT Avg (ms) | GPU Util Avg | GPU Mem Avg (MiB) | Evidence |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|
| `config-aligned` | 1 | 1 | 100 | 3 | 300/300 (100.00%) | 1.12 | 143.20 | 893.78 | 968.03 | 14.68 | 79.29% | 5912.99 | `results/evidence/hami/config-aligned/repeat_r1_c1_20260620-170232/repeated_summary.json` |
| `config-aligned` | 1 | 2 | 100 | 3 | 300/300 (100.00%) | 1.14 | 145.50 | 1750.87 | 1884.95 | 878.24 | 80.35% | 2959.99 | `results/evidence/hami/config-aligned/repeat_r1_c2_20260620-172519/repeated_summary.json` |
| `config-aligned` | 1 | 4 | 100 | 3 | 300/300 (100.00%) | 1.14 | 145.56 | 3465.33 | 3738.46 | 2593.22 | 81.16% | 5914.99 | `results/evidence/hami/config-aligned/repeat_r1_c4_20260620-173554/repeated_summary.json` |
| `memory-aligned` | 1 | 1 | 100 | 3 | 300/300 (100.00%) | 1.21 | 155.42 | 823.51 | 871.43 | 13.87 | 84.59% | 1769.95 | `results/evidence/hami/memory-aligned/repeat_r1_c1_20260620-120654/repeated_summary.json` |
| `memory-aligned` | 1 | 2 | 100 | 3 | 300/300 (100.00%) | 1.23 | 157.01 | 1622.21 | 1666.87 | 813.47 | 85.72% | 1769.95 | `results/evidence/hami/memory-aligned/repeat_r1_c2_20260620-122850/repeated_summary.json` |
| `memory-aligned` | 1 | 4 | 100 | 3 | 300/300 (100.00%) | 1.22 | 156.65 | 3219.73 | 3328.78 | 2409.15 | 85.24% | 1769.95 | `results/evidence/hami/memory-aligned/repeat_r1_c4_20260620-130219/repeated_summary.json` |
| `memory-aligned` | 2 | 2 | 100 | 3 | 300/300 (100.00%) | 1.31 | 168.20 | 1521.71 | 1542.60 | 18.52 | 93.55% | 3534.79 | `results/evidence/hami/memory-aligned/repeat_r2_c2_20260620-124446/repeated_summary.json` |

### 2.2 HAMi 詳細聚合指標

下表為三次 repeated runs 的聚合結果。RPS 欄位以 `mean ± stdev` 表示，其餘欄位為 mean。

| Profile | Replicas | Concurrency | RPS Mean ± Std | Output Tokens/s Mean | E2E Avg Mean | E2E P50 Mean | E2E P95 Mean | E2E P99 Mean | TTFT Avg Mean | TTFT P50 Mean | TTFT P95 Mean | TTFT P99 Mean | GPU Util Avg | GPU Util Max | GPU Mem Avg | GPU Mem Max | Power Avg | Power Max |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| `config-aligned` | 1 | 1 | 1.12 ± 0.01 | 143.20 | 893.78 | 872.32 | 968.03 | 1039.40 | 14.68 | 14.33 | 17.99 | 19.41 | 79.29% | 86.00% | 5912.99 MiB | 5913.00 MiB | 52.22 W | 55.44 W |
| `config-aligned` | 1 | 2 | 1.14 ± 0.01 | 145.50 | 1750.87 | 1731.08 | 1884.95 | 2022.79 | 878.24 | 869.30 | 963.91 | 1021.39 | 80.35% | 86.00% | 2959.99 MiB | 2960.00 MiB | 53.60 W | 56.65 W |
| `config-aligned` | 1 | 4 | 1.14 ± 0.01 | 145.56 | 3465.33 | 3454.64 | 3738.46 | 3814.11 | 2593.22 | 2593.07 | 2837.91 | 2921.31 | 81.16% | 86.00% | 5914.99 MiB | 5915.00 MiB | 52.83 W | 55.70 W |
| `memory-aligned` | 1 | 1 | 1.21 ± 0.01 | 155.42 | 823.51 | 817.81 | 871.43 | 914.51 | 13.87 | 13.47 | 16.41 | 17.24 | 84.59% | 90.00% | 1769.95 MiB | 1770.00 MiB | 53.56 W | 57.50 W |
| `memory-aligned` | 1 | 2 | 1.23 ± 0.00 | 157.01 | 1622.21 | 1627.70 | 1666.87 | 1679.37 | 813.47 | 820.33 | 842.05 | 855.96 | 85.72% | 90.33% | 1769.95 MiB | 1770.00 MiB | 53.87 W | 57.69 W |
| `memory-aligned` | 1 | 4 | 1.22 ± 0.00 | 156.65 | 3219.73 | 3257.10 | 3328.78 | 3360.52 | 2409.15 | 2447.97 | 2510.67 | 2547.47 | 85.24% | 90.00% | 1769.95 MiB | 1770.00 MiB | 53.55 W | 57.40 W |
| `memory-aligned` | 2 | 2 | 1.31 ± 0.00 | 168.20 | 1521.71 | 1519.98 | 1542.60 | 1558.55 | 18.52 | 18.31 | 22.22 | 23.64 | 93.55% | 100.00% | 3534.79 MiB | 3535.00 MiB | 55.66 W | 60.46 W |

## 3. Profile 觀察

### 3.1 `config-aligned`

`config-aligned` 在本次 evidence 中包含 `r1_c1`、`r1_c2`、`r1_c4` 三組，全部完成 `300/300` successful requests。

觀察重點：

- RPS 約落在 1.12 到 1.14 req/s，隨 concurrency 增加並沒有明顯提升。
- E2E latency 隨 concurrency 增加而上升：`r1_c1` 約 893.78 ms，`r1_c2` 約 1750.87 ms，`r1_c4` 約 3465.33 ms。
- TTFT 也隨 concurrency 增加而顯著上升，表示排隊與生成等待時間是主要瓶頸之一。

### 3.2 `memory-aligned`

`memory-aligned` 在本次 evidence 中包含 `r1_c1`、`r1_c2`、`r1_c4`、`r2_c2` 四組，全部完成 `300/300` successful requests。

觀察重點：

- 單 Pod 情境下，`r1_c1`、`r1_c2`、`r1_c4` 的 GPU memory 平均使用量均約 1769.95 MiB。
- `r2_c2` 的 GPU memory 平均使用量約 3534.79 MiB，接近單 Pod 使用量的兩倍，符合兩個 vLLM Pod 同時執行的預期。
- `r2_c2` 平均 RPS 為 1.31，是目前 HAMi evidence 中 throughput 最高的組合。
- `r2_c2` 的 TTFT 平均約 18.52 ms，明顯低於單 Pod 高 concurrency 的 `r1_c2` / `r1_c4`，表示以多 Pod 分攤 endpoint 可能比單 Pod 承受較高 concurrency 更適合目前 workload。

## 4. 初步結論

1. 本次納入的 HAMi repeated groups 全部完成，且沒有 request failure。
2. 在目前 RTX 2000 Ada 16GB 單 GPU 環境中，`memory-aligned r2_c2` 是目前最有代表性的 multi-Pod sharing 成功案例。
3. 單 Pod 下提高 concurrency 並未顯著提升 RPS，反而明顯增加 E2E latency 與 TTFT。
4. `memory-aligned` 透過 `nvidia.com/gpumem` 讓 GPU memory quota 更明確，有助於解釋可排程 Pod 數量與 GPU memory 使用量。
5. 本文件不將 HAMi 結果與 legacy time-slicing baseline 做直接效能優劣比較，因為兩者硬體環境不同。

## 5. Evidence 位置

本次整理使用的 HAMi evidence 位置如下：

| Profile | Evidence Root |
|---|---|
| config-aligned | `results/evidence/hami/config-aligned/` |
| memory-aligned | `results/evidence/hami/memory-aligned/` |

每個 repeated group 內的 `repeated_summary.json` 為主要聚合依據；各 run 目錄內的 `summary.json`、`experiment_config.json`、`gpu_metrics.csv` 則作為單次 run 的佐證資料。

## 6. 解讀限制

- Evidence 中的 endpoint、node name、GPU UUID 等資訊已經過遮蔽，因此無法用於追溯實際機器網路資訊。
- HAMi 與 legacy time-slicing baseline 並非同一台機器，不能直接以絕對 RPS 或 latency 作為公平比較。
- `controlled` profile 尚未納入本次正式結果；若後續加入 `gpucores` quota，應獨立作為 HAMi 細緻控制功能展示組。
