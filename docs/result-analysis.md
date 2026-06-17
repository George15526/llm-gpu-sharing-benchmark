# Result Analysis

## Baseline Summary

| Mode | Replicas | Concurrency | Requests | Endpoint Count | Success Rate | RPS | Output Tokens/s | E2E Avg | E2E P50 | E2E P95 | E2E P99 | TTFT Avg | TTFT P50 | TTFT P95 | TTFT P99 | GPU Util Avg | GPU Util Max | GPU Mem Avg | GPU Mem Max |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| timeslicing | 1 | 1 | 100 | 1 | 100% | 2.47 | 316.20 | 404.78 ms | 404.60 ms | 407.45 ms | 408.62 ms | 6.63 ms | 6.53 ms | 8.19 ms | 8.41 ms | 41.97% | 90.00% | 2146.41 MiB | 4289 MiB |
| timeslicing | 1 | 2 | 100 | 1 | 100% | 2.49 | 318.83 | 798.91 ms | 802.85 ms | 806.06 ms | 807.17 ms | 400.77 ms | 404.87 ms | 406.59 ms | 407.47 ms | 41.50% | 90.00% | 2146.41 MiB | 4289 MiB |
| timeslicing | 1 | 4 | 100 | 1 | 100% | 2.49 | 319.03 | 1580.71 ms | 1604.42 ms | 1610.41 ms | 1613.32 ms | 1182.92 ms | 1206.63 ms | 1212.16 ms | 1214.09 ms | 42.39% | 90.00% | 2146.40 MiB | 4289 MiB |
| timeslicing | 2 | 2 | 100 | 2 | 100% | 4.97 | 636.38 | 402.23 ms | 401.71 ms | 407.02 ms | 408.15 ms | 6.70 ms | 6.51 ms | 8.26 ms | 8.38 ms | 70.08% | 91.00% | 4288.54 MiB | 4289 MiB |
| timeslicing | 4 | 4 | 100 | 4 | 100% | 5.12 | 655.47 | 780.73 ms | 777.01 ms | 863.29 ms | 874.61 ms | 22.83 ms | 9.89 ms | 84.63 ms | 100.13 ms | 69.38% | 100.00% | 4899.53 MiB | 5261 MiB |

> RPS = Requests per Second (req/s)

## Observations

- Time-slicing is easy to deploy but lacks memory isolation.
- HAMi is expected to provide finer-grained GPU resource control.
- Higher replica counts should be interpreted with Pod stability, not throughput alone.