# NVIDIA GPU Time-Slicing Experiment

本文件記錄目前單張 RTX 2000 Ada 機器上重新執行的 NVIDIA time-slicing repeated experiment evidence。此版本以目前 evidence 為主，不再使用舊機器 baseline 作為主要數據。

## 1. 實驗目的

本實驗使用 NVIDIA GPU time-slicing 作為 GPU sharing baseline，觀察在 Kubernetes 中將單張實體 GPU 宣告為多個邏輯 `nvidia.com/gpu` replica 後，vLLM inference workload 在不同 replicas / concurrency 組合下的穩定性與效能表現。

Time-slicing 的主要用途是讓多個 Pod 透過 NVIDIA device plugin 共享同一張實體 GPU。此方式部署相對簡單，但缺乏 GPU memory isolation，也無法針對不同 Pod 設定獨立的 GPU 記憶體或核心比例配額。

## 2. 實驗環境

| 項目 | 數值 |
|---|---|
| Kubernetes | kubeadm single-node Kubernetes |
| CNI | Flannel |
| GPU | 1 × NVIDIA RTX 2000 Ada Generation |
| GPU Memory | 16380 MiB |
| Driver | 595.71.05 |
| CUDA | 13.2 |
| Runtime | containerd |
| GPU sharing | NVIDIA device plugin time-slicing |
| Time-slicing replicas | 4 |

## 3. vLLM 設定

| 項目 | 數值 |
|---|---|
| Image | `vllm/vllm-openai:v0.8.5` |
| Model | `Qwen/Qwen2.5-0.5B-Instruct` |
| max-model-len | 512 |
| max-num-seqs | 1 |
| gpu-memory-utilization | 0.30 |
| enforce-eager | true |
| max tokens per request | 128 |

## 4. Repeated Experiment Results

| Mode | Replicas | Concurrency | Requests/Run | Repeat | 成功率 | RPS Avg | Output Tokens/s Avg | E2E Avg (ms) | E2E P95 (ms) | TTFT Avg (ms) | GPU Util Avg | GPU Mem Avg (MiB) | Evidence |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|
| `timeslicing` | 1 | 1 | 100 | 3 | 300/300 (100.00%) | 1.21 | 155.07 | 825.35 | 905.57 | 13.87 | 85.67% | 4749.98 | `results/evidence/timeslicing/repeat_r1_c1_20260621-211051/repeated_summary.json` |
| `timeslicing` | 1 | 2 | 100 | 3 | 300/300 (100.00%) | 1.23 | 157.61 | 1616.07 | 1657.20 | 810.37 | 86.96% | 4749.98 | `results/evidence/timeslicing/repeat_r1_c2_20260621-211656/repeated_summary.json` |
| `timeslicing` | 1 | 4 | 100 | 3 | 300/300 (100.00%) | 1.22 | 156.33 | 3227.12 | 3461.51 | 2414.73 | 85.81% | 4749.98 | `results/evidence/timeslicing/repeat_r1_c4_20260621-212319/repeated_summary.json` |
| `timeslicing` | 2 | 2 | 100 | 3 | 300/300 (100.00%) | 1.31 | 168.25 | 1520.95 | 1533.16 | 18.71 | 95.69% | 4726.93 | `results/evidence/timeslicing/repeat_r2_c2_20260621-213030/repeated_summary.json` |

## 5. 結果解讀

重新執行後，`r1_c1`、`r1_c2`、`r1_c4` 與 `r2_c2` 均完成 `300/300` successful requests。`r2_c2` 平均 RPS 為 `1.31`，是目前 time-slicing evidence 中最高的成功組合。

單 Pod 情境下，增加 concurrency 對 RPS 幫助有限，但會明顯增加 E2E latency 與 TTFT。例如 `r1_c1` 的平均 TTFT 為 `13.87 ms`，`r1_c4` 則上升至 `2414.73 ms`。

`r4_c4` 未納入成功結果。該組在目前設定下會受到 vLLM KV cache 初始化與 GPU memory contention 影響，說明 time-slicing 雖可增加 Kubernetes 層的 `nvidia.com/gpu` 可排程數量，但不提供 GPU memory isolation。


## 6. 重要設定注意事項

請勿在 Pod spec 中手動設定：

```yaml
NVIDIA_VISIBLE_DEVICES=all
```

原因是此設定會繞過 NVIDIA device plugin 分配給 Pod 的 GPU visibility，可能造成多個 Pod 都看見並使用 `cuda:0`，導致原本的 time-slicing 分配失效或結果失真。

## 7. 舊版 baseline 紀錄說明

早期文件曾記錄 2 × RTX 4070 SUPER 環境下的 NVIDIA time-slicing baseline，當時設定包含 Kubernetes v1.31.7、Driver 550.144.03、CUDA 12.4，以及每張 GPU `replicas = 4`。該資料目前不列入本版主表與結論，僅保留為專案演進背景。

目前正式 evidence 以同一台 RTX 2000 Ada 單機環境下重新執行的 `results/evidence/timeslicing/` 與 `results/evidence/hami/` 為主。
