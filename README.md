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

本專案目前包含兩個階段的實驗紀錄，且兩者使用的硬體環境不同。

### Legacy NVIDIA Time-Slicing Baseline Environment

此環境為原始 NVIDIA time-slicing baseline 實驗使用的機器。

| 項目 | 數值 |
|---|---|
| Kubernetes | v1.31.7 |
| CNI | Flannel |
| GPU | 2 × RTX 4070 SUPER |
| Driver | 550.144.03 |
| CUDA | 12.4 |
| Runtime | containerd |

### Current HAMi Experiment Environment

此環境為目前 HAMi 實驗使用的單機 Kubernetes 環境。

| 項目 | 數值 |
|---|---|
| Kubernetes | kubeadm single-node Kubernetes |
| CNI | Flannel |
| GPU | 1 × NVIDIA RTX 2000 Ada Generation |
| GPU Memory | 16380 MiB |
| Driver | 595.71.05 |
| CUDA | 13.2 |
| Runtime | containerd |
| GPU Scheduler | HAMi scheduler |

> 注意：目前 HAMi 實驗與原始 NVIDIA time-slicing baseline 並非在同一台機器上完成。因此，HAMi 結果應被視為目前單 GPU 機器上的可行性與行為觀察，不應直接與舊 baseline 的絕對吞吐量或延遲數值做硬體等價比較。

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


## 目前 HAMi 實驗數據摘要

本次整理的 HAMi evidence 來源為 `results/evidence/hami/`，已忽略 `results/evidence/timeslicing/` 內的資料。HAMi 目前收錄 `config-aligned` 與 `memory-aligned` 兩種 profile，所有列入表格的設定皆完成 `repeat = 3`，每輪正式請求數為 `100`，且每個 endpoint 於正式測量前執行 `warmup_requests_per_endpoint = 3`。

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
- [HAMi 實驗紀錄](docs/hami-experiment.md)
- [問題排查紀錄](docs/troubleshooting.md)
- [結果分析](docs/result-analysis.md)
