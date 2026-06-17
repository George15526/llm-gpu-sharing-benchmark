# HAMi GPU Sharing Experiment

## 1. Purpose

Evaluate HAMi as the experimental GPU sharing mechanism and compare it with NVIDIA time-slicing.

## 2. Expected Features

| Feature | NVIDIA Time-Slicing | HAMi |
|---|---|---|
| GPU sharing | Yes | Yes |
| GPU memory quota | No | Yes |
| GPU core quota | No | Yes |
| Scheduler awareness | Limited | Stronger |
| Isolation | Weak | Stronger |

## 3. HAMi Deployment

To be added after installation.

## 4. vLLM Workload

Use the same model and benchmark client as the baseline.

## 5. Test Matrix

| Replicas | Concurrency | Requests |
|---:|---:|---:|
| 1 | 1 | 100 |
| 2 | 2 | 100 |
| 4 | 4 | 100 |
| 6 | 6 | 100 |

## 6. Results

To be added.

## 7. Comparison with Baseline

To be added.