# HAMi Evidence Data Summary

## 聚合摘要

| Profile | Replicas | Concurrency | Requests/Run | Repeat | 成功率 | RPS Avg | Output Tokens/s Avg | E2E Avg (ms) | E2E P95 (ms) | TTFT Avg (ms) | GPU Util Avg | GPU Mem Avg (MiB) | Evidence |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|
| `config-aligned` | 1 | 1 | 100 | 3 | 300/300 (100.00%) | 1.12 | 143.20 | 893.78 | 968.03 | 14.68 | 79.29% | 5912.99 | `results/evidence/hami/config-aligned/repeat_r1_c1_20260620-170232/repeated_summary.json` |
| `config-aligned` | 1 | 2 | 100 | 3 | 300/300 (100.00%) | 1.14 | 145.50 | 1750.87 | 1884.95 | 878.24 | 80.35% | 2959.99 | `results/evidence/hami/config-aligned/repeat_r1_c2_20260620-172519/repeated_summary.json` |
| `config-aligned` | 1 | 4 | 100 | 3 | 300/300 (100.00%) | 1.14 | 145.56 | 3465.33 | 3738.46 | 2593.22 | 81.16% | 5914.99 | `results/evidence/hami/config-aligned/repeat_r1_c4_20260620-173554/repeated_summary.json` |
| `memory-aligned` | 1 | 1 | 100 | 3 | 300/300 (100.00%) | 1.21 | 155.42 | 823.51 | 871.43 | 13.87 | 84.59% | 1769.95 | `results/evidence/hami/memory-aligned/repeat_r1_c1_20260620-120654/repeated_summary.json` |
| `memory-aligned` | 1 | 2 | 100 | 3 | 300/300 (100.00%) | 1.23 | 157.01 | 1622.21 | 1666.87 | 813.47 | 85.72% | 1769.95 | `results/evidence/hami/memory-aligned/repeat_r1_c2_20260620-122850/repeated_summary.json` |
| `memory-aligned` | 1 | 4 | 100 | 3 | 300/300 (100.00%) | 1.22 | 156.65 | 3219.73 | 3328.78 | 2409.15 | 85.24% | 1769.95 | `results/evidence/hami/memory-aligned/repeat_r1_c4_20260620-130219/repeated_summary.json` |
| `memory-aligned` | 2 | 2 | 100 | 3 | 300/300 (100.00%) | 1.31 | 168.20 | 1521.71 | 1542.60 | 18.52 | 93.55% | 3534.79 | `results/evidence/hami/memory-aligned/repeat_r2_c2_20260620-124446/repeated_summary.json` |

## 詳細指標

| Profile | Replicas | Concurrency | RPS Mean ± Std | Output Tokens/s Mean | E2E Avg Mean | E2E P50 Mean | E2E P95 Mean | E2E P99 Mean | TTFT Avg Mean | TTFT P50 Mean | TTFT P95 Mean | TTFT P99 Mean | GPU Util Avg | GPU Util Max | GPU Mem Avg | GPU Mem Max | Power Avg | Power Max |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| `config-aligned` | 1 | 1 | 1.12 ± 0.01 | 143.20 | 893.78 | 872.32 | 968.03 | 1039.40 | 14.68 | 14.33 | 17.99 | 19.41 | 79.29% | 86.00% | 5912.99 MiB | 5913.00 MiB | 52.22 W | 55.44 W |
| `config-aligned` | 1 | 2 | 1.14 ± 0.01 | 145.50 | 1750.87 | 1731.08 | 1884.95 | 2022.79 | 878.24 | 869.30 | 963.91 | 1021.39 | 80.35% | 86.00% | 2959.99 MiB | 2960.00 MiB | 53.60 W | 56.65 W |
| `config-aligned` | 1 | 4 | 1.14 ± 0.01 | 145.56 | 3465.33 | 3454.64 | 3738.46 | 3814.11 | 2593.22 | 2593.07 | 2837.91 | 2921.31 | 81.16% | 86.00% | 5914.99 MiB | 5915.00 MiB | 52.83 W | 55.70 W |
| `memory-aligned` | 1 | 1 | 1.21 ± 0.01 | 155.42 | 823.51 | 817.81 | 871.43 | 914.51 | 13.87 | 13.47 | 16.41 | 17.24 | 84.59% | 90.00% | 1769.95 MiB | 1770.00 MiB | 53.56 W | 57.50 W |
| `memory-aligned` | 1 | 2 | 1.23 ± 0.00 | 157.01 | 1622.21 | 1627.70 | 1666.87 | 1679.37 | 813.47 | 820.33 | 842.05 | 855.96 | 85.72% | 90.33% | 1769.95 MiB | 1770.00 MiB | 53.87 W | 57.69 W |
| `memory-aligned` | 1 | 4 | 1.22 ± 0.00 | 156.65 | 3219.73 | 3257.10 | 3328.78 | 3360.52 | 2409.15 | 2447.97 | 2510.67 | 2547.47 | 85.24% | 90.00% | 1769.95 MiB | 1770.00 MiB | 53.55 W | 57.40 W |
| `memory-aligned` | 2 | 2 | 1.31 ± 0.00 | 168.20 | 1521.71 | 1519.98 | 1542.60 | 1558.55 | 18.52 | 18.31 | 22.22 | 23.64 | 93.55% | 100.00% | 3534.79 MiB | 3535.00 MiB | 55.66 W | 60.46 W |
