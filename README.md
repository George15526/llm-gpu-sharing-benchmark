# Kubernetes LLM GPU Sharing Benchmark

## 專案概述

本專案用於評估 Kubernetes 環境中，LLM 推論工作負載在不同 GPU 共享機制下的行為與效能表現。

目前專案主要比較兩種 GPU 共享方式：

| 方法 | 角色 | 說明 |
|---|---|---|
| NVIDIA Time-Slicing | Baseline | 使用 NVIDIA k8s-device-plugin 提供的邏輯 GPU 共享機制 |
| HAMi | Experiment | 使用 vGPU、GPU memory quota、GPU core quota 等方式進行更細緻的 GPU 資源管理 |

## 系統架構

```text
Benchmark Client
      |
      v
Kubernetes Service
      |
      v
vLLM Inference Pods
      |
      v
Shared NVIDIA GPUs
```

Benchmark client 會透過 Kubernetes Service 將請求分送至多個 vLLM Pod，並記錄端到端延遲、TTFT、吞吐量、GPU 使用率、GPU 記憶體使用量等資料。

## 實驗環境說明

本版文件以目前同一台單機 Kubernetes 環境所產生的 evidence 為主。NVIDIA time-slicing 與 HAMi 皆已在此環境下重新執行，因此目前的結果分析可直接依據本次 evidence 中的相同 workload 與相同硬體背景進行觀察。

### Current Single-GPU Experiment Environment

| 項目 | 數值 |
|---|---|
| Kubernetes | kubeadm single-node Kubernetes |
| CNI | Flannel |
| GPU | 1 × NVIDIA RTX 2000 Ada Generation |
| GPU Memory | 16380 MiB |
| Driver | 595.71.05 |
| CUDA | 13.2 |
| Runtime | containerd |
| NVIDIA time-slicing | NVIDIA k8s-device-plugin, `replicas = 4` |
| HAMi | HAMi scheduler / vGPU resource control |

> 舊版 2 × RTX 4070 SUPER 的 time-slicing baseline 已不作為本次主表數據。若文件中保留舊版紀錄，僅作為歷史背景與實驗演進說明；目前結論以 `results/evidence/timeslicing/` 與 `results/evidence/hami/` 中同機器重新整理的資料為準。

## 工作負載

| 項目 | 數值 |
|---|---|
| Serving framework | vLLM |
| Model | Qwen/Qwen2.5-0.5B-Instruct |
| Image | vllm/vllm-openai:v0.8.5 |
| API | OpenAI-compatible API |

## 實驗指標

本專案主要記錄以下指標：

- End-to-end latency，端到端延遲
- Time To First Token，TTFT
- Requests per second，RPS
- Output tokens per second
- GPU memory usage
- GPU utilization
- Pod readiness / failure status
- Endpoint count
- Request success / failure count

## 執行方式

### 單次實驗

```bash
WARMUP_REQUESTS_PER_ENDPOINT=3 bash scripts/run_experiment.sh timeslicing 1 1 100

HAMI_PROFILE=config-aligned WARMUP_REQUESTS_PER_ENDPOINT=3 \
  bash scripts/run_experiment.sh hami 1 1 100

HAMI_PROFILE=memory-aligned WARMUP_REQUESTS_PER_ENDPOINT=3 \
  bash scripts/run_experiment.sh hami 1 1 100
```

### 重複實驗

```bash
HAMI_PROFILE=config-aligned WARMUP_REQUESTS_PER_ENDPOINT=3 \
  bash scripts/run_repeated_experiments.sh hami 1 1 100 3

HAMI_PROFILE=memory-aligned WARMUP_REQUESTS_PER_ENDPOINT=3 \
  bash scripts/run_repeated_experiments.sh hami 1 1 100 3
```

目前重複實驗採用 portable mode：

```text
Run 1：清理既有 workload → 部署 Pod → warm-up → formal benchmark
Run 2：沿用既有 ready Pod → warm-up → formal benchmark
Run 3：沿用既有 ready Pod → warm-up → formal benchmark
```

此設計可避免每輪實驗都刪除並重新建立 Pod，降低 vLLM multiprocessing process 殘留、Pod Terminating 卡住、或需要 host-level cleanup 權限的風險。



## 目前 NVIDIA Time-Slicing 重新執行數據摘要

本次整理的 time-slicing evidence 來源為 `results/evidence/timeslicing/`，是在目前單張 RTX 2000 Ada 機器上重新執行的結果。所有列入表格的設定皆完成 `repeat = 3`，每輪正式請求數為 `100`，且每個 endpoint 於正式測量前執行 `warmup_requests_per_endpoint = 3`。

| Mode | Replicas | Concurrency | Requests/Run | Repeat | 成功率 | RPS Avg | Output Tokens/s Avg | E2E Avg (ms) | E2E P95 (ms) | TTFT Avg (ms) | GPU Util Avg | GPU Mem Avg (MiB) | Evidence |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|
| `timeslicing` | 1 | 1 | 100 | 3 | 300/300 (100.00%) | 1.21 | 155.07 | 825.35 | 905.57 | 13.87 | 85.67% | 4749.98 | `results/evidence/timeslicing/repeat_r1_c1_20260621-211051/repeated_summary.json` |
| `timeslicing` | 1 | 2 | 100 | 3 | 300/300 (100.00%) | 1.23 | 157.61 | 1616.07 | 1657.20 | 810.37 | 86.96% | 4749.98 | `results/evidence/timeslicing/repeat_r1_c2_20260621-211656/repeated_summary.json` |
| `timeslicing` | 1 | 4 | 100 | 3 | 300/300 (100.00%) | 1.22 | 156.33 | 3227.12 | 3461.51 | 2414.73 | 85.81% | 4749.98 | `results/evidence/timeslicing/repeat_r1_c4_20260621-212319/repeated_summary.json` |
| `timeslicing` | 2 | 2 | 100 | 3 | 300/300 (100.00%) | 1.31 | 168.25 | 1520.95 | 1533.16 | 18.71 | 95.69% | 4726.93 | `results/evidence/timeslicing/repeat_r2_c2_20260621-213030/repeated_summary.json` |

`r4_c4` 未納入成功表格；該組在目前設定下會受到 vLLM KV cache 初始化與 GPU memory contention 影響。完整解讀請參考 [NVIDIA Time-Slicing Evidence Summary](docs/timeslicing-evidence-summary.md) 與 [結果分析](docs/result-analysis.md)。

## 目前 HAMi 實驗數據摘要

本次整理的 HAMi evidence 來源為 `results/evidence/hami/`，並可與目前重新執行的 `results/evidence/timeslicing/` 結果共同作為同機器下的 GPU sharing 行為觀察。HAMi 目前收錄 `config-aligned` 與 `memory-aligned` 兩種 profile，所有列入表格的設定皆完成 `repeat = 3`，每輪正式請求數為 `100`，且每個 endpoint 於正式測量前執行 `warmup_requests_per_endpoint = 3`。

| Profile | Replicas | Concurrency | Requests/Run | Repeat | 成功率 | RPS Avg | Output Tokens/s Avg | E2E Avg (ms) | E2E P95 (ms) | TTFT Avg (ms) | GPU Util Avg | GPU Mem Avg (MiB) | Evidence |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|
| `config-aligned` | 1 | 1 | 100 | 3 | 300/300 (100.00%) | 1.12 | 143.20 | 893.78 | 968.03 | 14.68 | 79.29% | 5912.99 | `results/evidence/hami/config-aligned/repeat_r1_c1_20260620-170232/repeated_summary.json` |
| `config-aligned` | 1 | 2 | 100 | 3 | 300/300 (100.00%) | 1.14 | 145.50 | 1750.87 | 1884.95 | 878.24 | 80.35% | 2959.99 | `results/evidence/hami/config-aligned/repeat_r1_c2_20260620-172519/repeated_summary.json` |
| `config-aligned` | 1 | 4 | 100 | 3 | 300/300 (100.00%) | 1.14 | 145.56 | 3465.33 | 3738.46 | 2593.22 | 81.16% | 5914.99 | `results/evidence/hami/config-aligned/repeat_r1_c4_20260620-173554/repeated_summary.json` |
| `memory-aligned` | 1 | 1 | 100 | 3 | 300/300 (100.00%) | 1.21 | 155.42 | 823.51 | 871.43 | 13.87 | 84.59% | 1769.95 | `results/evidence/hami/memory-aligned/repeat_r1_c1_20260620-120654/repeated_summary.json` |
| `memory-aligned` | 1 | 2 | 100 | 3 | 300/300 (100.00%) | 1.23 | 157.01 | 1622.21 | 1666.87 | 813.47 | 85.72% | 1769.95 | `results/evidence/hami/memory-aligned/repeat_r1_c2_20260620-122850/repeated_summary.json` |
| `memory-aligned` | 1 | 4 | 100 | 3 | 300/300 (100.00%) | 1.22 | 156.65 | 3219.73 | 3328.78 | 2409.15 | 85.24% | 1769.95 | `results/evidence/hami/memory-aligned/repeat_r1_c4_20260620-130219/repeated_summary.json` |
| `memory-aligned` | 2 | 2 | 100 | 3 | 300/300 (100.00%) | 1.31 | 168.20 | 1521.71 | 1542.60 | 18.52 | 93.55% | 3534.79 | `results/evidence/hami/memory-aligned/repeat_r2_c2_20260620-124446/repeated_summary.json` |

完整解讀請參考 [HAMi 實驗紀錄](docs/hami-experiment.md) 與 [結果分析](docs/result-analysis.md)。

## 文件索引

- [實驗設計](docs/experiment-design.md)
- [NVIDIA Time-Slicing Baseline](docs/baseline-timeslicing.md)
- [NVIDIA Time-Slicing Evidence Summary](docs/timeslicing-evidence-summary.md)
- [HAMi 實驗紀錄](docs/hami-experiment.md)
- [問題排查紀錄](docs/troubleshooting.md)
- [結果分析](docs/result-analysis.md)
