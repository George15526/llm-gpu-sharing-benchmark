# NVIDIA Time-Slicing Evidence Data Summary

本檔由 `timeslicing/` repeated experiment evidence 整理而成，記錄的是重新於目前單張 RTX 2000 Ada 機器上執行的 NVIDIA time-slicing 結果。

## 1. 收錄範圍

本次納入的 repeated groups 包含：

| Replicas | Concurrency | Group | 狀態 |
|---:|---:|---|---|
| 1 | 1 | `repeat_r1_c1_20260621-211051` | 成功 300/300 |
| 1 | 2 | `repeat_r1_c2_20260621-211656` | 成功 300/300 |
| 1 | 4 | `repeat_r1_c4_20260621-212319` | 成功 300/300 |
| 2 | 2 | `repeat_r2_c2_20260621-213030` | 成功 300/300 |


所有收錄組合皆採用：

```text
repeat = 3
warmup_requests_per_endpoint = 3
formal_requests_per_run = 100
max_tokens = 128
model = Qwen/Qwen2.5-0.5B-Instruct
```

`r4_c4` 未納入本次成功 evidence。該組在目前設定下曾出現 vLLM KV cache 初始化失敗，代表 NVIDIA time-slicing 雖可在 Kubernetes 層宣告多個 GPU replicas，但不提供 GPU memory quota 或 memory isolation，實際可承載的 vLLM Pod 數量仍受模型與 GPU memory 狀態限制。

## 2. 聚合摘要

| Mode | Replicas | Concurrency | Requests/Run | Repeat | 成功率 | RPS Avg | Output Tokens/s Avg | E2E Avg (ms) | E2E P95 (ms) | TTFT Avg (ms) | GPU Util Avg | GPU Mem Avg (MiB) | Evidence |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|
| `timeslicing` | 1 | 1 | 100 | 3 | 300/300 (100.00%) | 1.21 | 155.07 | 825.35 | 905.57 | 13.87 | 85.67% | 4749.98 | `results/evidence/timeslicing/repeat_r1_c1_20260621-211051/repeated_summary.json` |
| `timeslicing` | 1 | 2 | 100 | 3 | 300/300 (100.00%) | 1.23 | 157.61 | 1616.07 | 1657.20 | 810.37 | 86.96% | 4749.98 | `results/evidence/timeslicing/repeat_r1_c2_20260621-211656/repeated_summary.json` |
| `timeslicing` | 1 | 4 | 100 | 3 | 300/300 (100.00%) | 1.22 | 156.33 | 3227.12 | 3461.51 | 2414.73 | 85.81% | 4749.98 | `results/evidence/timeslicing/repeat_r1_c4_20260621-212319/repeated_summary.json` |
| `timeslicing` | 2 | 2 | 100 | 3 | 300/300 (100.00%) | 1.31 | 168.25 | 1520.95 | 1533.16 | 18.71 | 95.69% | 4726.93 | `results/evidence/timeslicing/repeat_r2_c2_20260621-213030/repeated_summary.json` |

## 3. 詳細聚合指標

下表為三次 repeated runs 聚合後的 mean / standard deviation 等摘要值。單位除特別標示外，latency 為 ms，GPU memory 為 MiB，power 為 W。

| Mode | Replicas | Concurrency | RPS Mean ± Std | Output Tokens/s Mean | E2E Avg Mean | E2E P50 Mean | E2E P95 Mean | E2E P99 Mean | TTFT Avg Mean | TTFT P50 Mean | TTFT P95 Mean | TTFT P99 Mean | GPU Util Avg | GPU Util Max | GPU Mem Avg | GPU Mem Max | Power Avg | Power Max |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| `timeslicing` | 1 | 1 | 1.21 ± 0.01 | 155.07 | 825.35 | 817.64 | 905.57 | 914.16 | 13.87 | 13.55 | 16.21 | 17.27 | 85.67% | 91.00% | 4749.98 MiB | 4750.00 MiB | 55.11 W | 57.90 W |
| `timeslicing` | 1 | 2 | 1.23 ± 0.00 | 157.61 | 1616.07 | 1617.34 | 1657.20 | 1673.43 | 810.37 | 813.44 | 837.64 | 855.09 | 86.96% | 90.67% | 4749.98 MiB | 4750.00 MiB | 56.81 W | 59.09 W |
| `timeslicing` | 1 | 4 | 1.22 ± 0.01 | 156.33 | 3227.12 | 3244.66 | 3461.51 | 3620.15 | 2414.73 | 2439.78 | 2608.60 | 2732.54 | 85.81% | 90.67% | 4749.98 MiB | 4750.00 MiB | 56.54 W | 59.15 W |
| `timeslicing` | 2 | 2 | 1.31 ± 0.00 | 168.25 | 1520.95 | 1519.96 | 1533.16 | 1548.24 | 18.71 | 18.31 | 21.93 | 24.48 | 95.69% | 100.00% | 4726.93 MiB | 4727.00 MiB | 58.97 W | 61.63 W |

## 4. 單次 run 明細

| Group | Run | Requests | Success | Failed | RPS | Output tok/s | Avg E2E latency (ms) | P95 E2E latency (ms) | Avg TTFT (ms) | P95 TTFT (ms) | Avg GPU util (%) | Max GPU util (%) | Avg GPU mem (MiB) | Max GPU mem (MiB) |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| `repeat_r1_c1_20260621-211051` | 1 | 100 | 100 | 0 | 1.22 | 155.81 | 821.40 | 840.84 | 13.75 | 15.85 | 85.82 | 91.00 | 4749.95 | 4750.00 |
| `repeat_r1_c1_20260621-211051` | 2 | 100 | 100 | 0 | 1.21 | 155.16 | 824.87 | 940.38 | 13.62 | 15.77 | 85.84 | 91.00 | 4750.00 | 4750.00 |
| `repeat_r1_c1_20260621-211051` | 3 | 100 | 100 | 0 | 1.21 | 154.24 | 829.77 | 935.49 | 14.23 | 17.00 | 85.35 | 91.00 | 4750.00 | 4750.00 |
| `repeat_r1_c2_20260621-211656` | 1 | 100 | 100 | 0 | 1.23 | 157.46 | 1617.66 | 1660.28 | 811.10 | 840.78 | 86.29 | 91.00 | 4749.95 | 4750.00 |
| `repeat_r1_c2_20260621-211656` | 2 | 100 | 100 | 0 | 1.23 | 157.89 | 1613.14 | 1651.92 | 808.85 | 832.75 | 87.45 | 91.00 | 4750.00 | 4750.00 |
| `repeat_r1_c2_20260621-211656` | 3 | 100 | 100 | 0 | 1.23 | 157.46 | 1617.42 | 1659.42 | 811.17 | 839.40 | 87.15 | 90.00 | 4750.00 | 4750.00 |
| `repeat_r1_c4_20260621-212319` | 1 | 100 | 100 | 0 | 1.22 | 155.66 | 3241.21 | 3352.73 | 2425.34 | 2531.72 | 84.93 | 91.00 | 4749.95 | 4750.00 |
| `repeat_r1_c4_20260621-212319` | 2 | 100 | 100 | 0 | 1.24 | 158.20 | 3187.90 | 3284.37 | 2385.17 | 2471.05 | 86.52 | 90.00 | 4750.00 | 4750.00 |
| `repeat_r1_c4_20260621-212319` | 3 | 100 | 100 | 0 | 1.21 | 155.13 | 3252.25 | 3747.42 | 2433.68 | 2823.01 | 85.96 | 91.00 | 4750.00 | 4750.00 |
| `repeat_r2_c2_20260621-213030` | 1 | 100 | 100 | 0 | 1.32 | 168.45 | 1518.55 | 1534.12 | 18.89 | 21.81 | 93.48 | 100.00 | 4726.80 | 4727.00 |
| `repeat_r2_c2_20260621-213030` | 2 | 100 | 100 | 0 | 1.31 | 168.12 | 1522.39 | 1532.30 | 19.03 | 22.20 | 96.78 | 100.00 | 4727.00 | 4727.00 |
| `repeat_r2_c2_20260621-213030` | 3 | 100 | 100 | 0 | 1.31 | 168.17 | 1521.92 | 1533.06 | 18.20 | 21.79 | 96.83 | 100.00 | 4727.00 | 4727.00 |

## 5. 觀察

- `r1_c1`、`r1_c2`、`r1_c4` 與 `r2_c2` 均完成 `300/300` successful requests。
- 單 Pod 情境下，concurrency 從 1 增加到 2 或 4 時，RPS 變化有限，但 E2E latency 與 TTFT 顯著上升，表示請求主要受到單一 vLLM instance 內部排隊與序列化生成影響。
- `r2_c2` 的平均 RPS 為 `1.31`，是本次 time-slicing evidence 中 throughput 最高的成功組合。
- `r2_c2` 的平均 TTFT 為 `18.71 ms`，明顯低於 `r1_c2` 的 `810.37 ms`，顯示以兩個 Pod 分攤 endpoint 比單 Pod 承受 concurrency=2 更能降低 first-token 等待。
- Time-slicing 不提供 GPU memory isolation；因此 GPU replicas 的可排程數量不等於實際可穩定執行的 vLLM instance 數量。
