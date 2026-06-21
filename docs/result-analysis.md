# 結果分析

## 1. 說明

本文件整理目前專案中的實驗結果。此次更新納入兩類 public-safe evidence：

| 類別 | Evidence 來源 | 說明 |
|---|---|---|
| Current NVIDIA time-slicing re-run | `results/evidence/timeslicing/` | 重新於目前單張 RTX 2000 Ada 機器執行 |
| Current HAMi experiment | `results/evidence/hami/` | 目前單張 RTX 2000 Ada 機器上的 HAMi 結果 |

本文件主要比較目前同一台單 GPU 機器上的 NVIDIA time-slicing re-run 與 HAMi evidence。兩類資料均來自目前 RTX 2000 Ada 單機 Kubernetes 環境，並採用相同模型、vLLM image、請求數、repeat 次數與 warm-up 設定。舊版 2 × RTX 4070 SUPER baseline 不列入本版主表分析。

兩類目前 evidence 皆採用相同基礎 workload：

```text
model = Qwen/Qwen2.5-0.5B-Instruct
vLLM image = vllm/vllm-openai:v0.8.5
repeat = 3
warmup_requests_per_endpoint = 3
formal_requests_per_run = 100
max_tokens = 128
```

## 2. Current NVIDIA Time-Slicing Re-run Results

### 2.1 Time-slicing 聚合摘要

| Mode | Replicas | Concurrency | Requests/Run | Repeat | 成功率 | RPS Avg | Output Tokens/s Avg | E2E Avg (ms) | E2E P95 (ms) | TTFT Avg (ms) | GPU Util Avg | GPU Mem Avg (MiB) | Evidence |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|
| `timeslicing` | 1 | 1 | 100 | 3 | 300/300 (100.00%) | 1.21 | 155.07 | 825.35 | 905.57 | 13.87 | 85.67% | 4749.98 | `results/evidence/timeslicing/repeat_r1_c1_20260621-211051/repeated_summary.json` |
| `timeslicing` | 1 | 2 | 100 | 3 | 300/300 (100.00%) | 1.23 | 157.61 | 1616.07 | 1657.20 | 810.37 | 86.96% | 4749.98 | `results/evidence/timeslicing/repeat_r1_c2_20260621-211656/repeated_summary.json` |
| `timeslicing` | 1 | 4 | 100 | 3 | 300/300 (100.00%) | 1.22 | 156.33 | 3227.12 | 3461.51 | 2414.73 | 85.81% | 4749.98 | `results/evidence/timeslicing/repeat_r1_c4_20260621-212319/repeated_summary.json` |
| `timeslicing` | 2 | 2 | 100 | 3 | 300/300 (100.00%) | 1.31 | 168.25 | 1520.95 | 1533.16 | 18.71 | 95.69% | 4726.93 | `results/evidence/timeslicing/repeat_r2_c2_20260621-213030/repeated_summary.json` |

### 2.2 Time-slicing 詳細聚合指標

| Mode | Replicas | Concurrency | RPS Mean ± Std | Output Tokens/s Mean | E2E Avg Mean | E2E P50 Mean | E2E P95 Mean | E2E P99 Mean | TTFT Avg Mean | TTFT P50 Mean | TTFT P95 Mean | TTFT P99 Mean | GPU Util Avg | GPU Util Max | GPU Mem Avg | GPU Mem Max | Power Avg | Power Max |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| `timeslicing` | 1 | 1 | 1.21 ± 0.01 | 155.07 | 825.35 | 817.64 | 905.57 | 914.16 | 13.87 | 13.55 | 16.21 | 17.27 | 85.67% | 91.00% | 4749.98 MiB | 4750.00 MiB | 55.11 W | 57.90 W |
| `timeslicing` | 1 | 2 | 1.23 ± 0.00 | 157.61 | 1616.07 | 1617.34 | 1657.20 | 1673.43 | 810.37 | 813.44 | 837.64 | 855.09 | 86.96% | 90.67% | 4749.98 MiB | 4750.00 MiB | 56.81 W | 59.09 W |
| `timeslicing` | 1 | 4 | 1.22 ± 0.01 | 156.33 | 3227.12 | 3244.66 | 3461.51 | 3620.15 | 2414.73 | 2439.78 | 2608.60 | 2732.54 | 85.81% | 90.67% | 4749.98 MiB | 4750.00 MiB | 56.54 W | 59.15 W |
| `timeslicing` | 2 | 2 | 1.31 ± 0.00 | 168.25 | 1520.95 | 1519.96 | 1533.16 | 1548.24 | 18.71 | 18.31 | 21.93 | 24.48 | 95.69% | 100.00% | 4726.93 MiB | 4727.00 MiB | 58.97 W | 61.63 W |

### 2.3 Time-slicing 觀察

`time-slicing` 的 `r1_c1`、`r1_c2`、`r1_c4` 與 `r2_c2` 均完成 `300/300` successful requests。

單 Pod 情境下，concurrency 從 1 增加到 2 或 4 時，RPS 僅小幅變動，但 E2E latency 與 TTFT 明顯上升。這代表在目前 `max-num-seqs = 1` 的 vLLM 設定下，單一 Pod 面對較高 concurrency 時主要受排隊等待影響。

`r2_c2` 平均 RPS 為 `1.31`，高於 `r1_c1` 的 `1.21`。同時，`r2_c2` 平均 TTFT 為 `18.71 ms`，明顯低於 `r1_c2` 的 `810.37 ms`，表示以多 Pod 分攤請求比單 Pod 承受較高 concurrency 更能降低 first-token 等待。

`r4_c4` 不納入成功結果。該組在目前 vLLM 設定下會受到 KV cache 初始化與 GPU memory contention 影響，這反映 time-slicing 缺乏 GPU memory isolation 的限制。

## 3. Current HAMi Experiment Results

目前 HAMi 實驗已完成 `config-aligned` 與 `memory-aligned` 兩類 profile，且每組皆採用：

```text
repeat = 3
warmup_requests_per_endpoint = 3
formal_requests_per_run = 100
max_tokens = 128
model = Qwen/Qwen2.5-0.5B-Instruct
```

### 3.1 HAMi 聚合摘要

| Profile | Replicas | Concurrency | Requests/Run | Repeat | 成功率 | RPS Avg | Output Tokens/s Avg | E2E Avg (ms) | E2E P95 (ms) | TTFT Avg (ms) | GPU Util Avg | GPU Mem Avg (MiB) | Evidence |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|
| `config-aligned` | 1 | 1 | 100 | 3 | 300/300 (100.00%) | 1.12 | 143.20 | 893.78 | 968.03 | 14.68 | 79.29% | 5912.99 | `results/evidence/hami/config-aligned/repeat_r1_c1_20260620-170232/repeated_summary.json` |
| `config-aligned` | 1 | 2 | 100 | 3 | 300/300 (100.00%) | 1.14 | 145.50 | 1750.87 | 1884.95 | 878.24 | 80.35% | 2959.99 | `results/evidence/hami/config-aligned/repeat_r1_c2_20260620-172519/repeated_summary.json` |
| `config-aligned` | 1 | 4 | 100 | 3 | 300/300 (100.00%) | 1.14 | 145.56 | 3465.33 | 3738.46 | 2593.22 | 81.16% | 5914.99 | `results/evidence/hami/config-aligned/repeat_r1_c4_20260620-173554/repeated_summary.json` |
| `memory-aligned` | 1 | 1 | 100 | 3 | 300/300 (100.00%) | 1.21 | 155.42 | 823.51 | 871.43 | 13.87 | 84.59% | 1769.95 | `results/evidence/hami/memory-aligned/repeat_r1_c1_20260620-120654/repeated_summary.json` |
| `memory-aligned` | 1 | 2 | 100 | 3 | 300/300 (100.00%) | 1.23 | 157.01 | 1622.21 | 1666.87 | 813.47 | 85.72% | 1769.95 | `results/evidence/hami/memory-aligned/repeat_r1_c2_20260620-122850/repeated_summary.json` |
| `memory-aligned` | 1 | 4 | 100 | 3 | 300/300 (100.00%) | 1.22 | 156.65 | 3219.73 | 3328.78 | 2409.15 | 85.24% | 1769.95 | `results/evidence/hami/memory-aligned/repeat_r1_c4_20260620-130219/repeated_summary.json` |
| `memory-aligned` | 2 | 2 | 100 | 3 | 300/300 (100.00%) | 1.31 | 168.20 | 1521.71 | 1542.60 | 18.52 | 93.55% | 3534.79 | `results/evidence/hami/memory-aligned/repeat_r2_c2_20260620-124446/repeated_summary.json` |

### 3.2 HAMi 詳細聚合指標

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

## 4. 同機器下的初步比較

在目前單張 RTX 2000 Ada 機器上，time-slicing 與 `memory-aligned` HAMi 的成功矩陣呈現相近的 throughput 與 latency 走勢。

| 組合 | Time-slicing RPS | HAMi memory-aligned RPS | Time-slicing TTFT Avg (ms) | HAMi memory-aligned TTFT Avg (ms) |
|---|---:|---:|---:|---:|
| r1_c1 | 1.21 | 1.21 | 13.87 | 13.87 |
| r1_c2 | 1.23 | 1.23 | 810.37 | 813.47 |
| r1_c4 | 1.22 | 1.22 | 2414.73 | 2409.15 |
| r2_c2 | 1.31 | 1.31 | 18.71 | 18.52 |

此結果不應被解讀為兩種 GPU sharing 機制在所有情境下效能等價。較合理的解讀是：在本模型、vLLM 參數與目前成功矩陣內，兩者能完成相近的 serving workload；但 HAMi 額外提供 GPU memory quota / GPU core quota 等資源控制能力，而 NVIDIA time-slicing 則較接近簡單的 logical GPU over-subscription。

## 5. 初步結論

1. 目前 time-slicing re-run 與 HAMi `memory-aligned` 在 `r1_c1`、`r1_c2`、`r1_c4`、`r2_c2` 成功矩陣內均能完成 repeated benchmark。
2. 單 Pod 提高 concurrency 對 RPS 幫助有限，但會顯著增加 E2E latency 與 TTFT。
3. `r2_c2` 在兩種 sharing mechanism 中都是較有代表性的多 Pod sharing 成功案例。
4. Time-slicing 缺乏 GPU memory isolation，因此 `r4_c4` 在目前設定下不納入成功結果。
5. HAMi 的主要額外價值不只在 throughput，而是在可宣告 GPU memory / GPU core quota，並由 scheduler 進行較明確的資源控管。

## 6. Evidence 位置

| 類別 | Evidence Root |
|---|---|
| Time-slicing re-run | `results/evidence/timeslicing/` |
| HAMi config-aligned | `results/evidence/hami/config-aligned/` |
| HAMi memory-aligned | `results/evidence/hami/memory-aligned/` |

每個 repeated group 內的 `repeated_summary.json` 為主要聚合依據；各 run 目錄內的 `summary.json`、`experiment_config.json`、`gpu_metrics.csv` 則作為單次 run 的佐證資料。

## 7. 解讀限制

- Evidence 中的 endpoint、node name、GPU UUID 等資訊已經過遮蔽，因此無法用於追溯實際機器網路資訊。
- 舊版 2 × RTX 4070 SUPER time-slicing baseline 不列入本次主表分析；目前結論以同機器重新執行的 evidence 為準。
- `r4_c4` 若要作為成功 benchmark，需另建低記憶體 time-slicing profile；但這會改變與 HAMi `memory-aligned` 的比較條件。
- `controlled` profile 尚未納入本次正式結果；若後續加入 `gpucores` quota，應獨立作為 HAMi 細緻控制功能展示組。
