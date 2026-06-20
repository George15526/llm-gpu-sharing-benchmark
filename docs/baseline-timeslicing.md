# NVIDIA GPU Time-Slicing Baseline

> 注意：本文件記錄的是原始 baseline 環境的 NVIDIA time-slicing 實驗結果。該環境使用 2 × RTX 4070 SUPER，與目前 HAMi 實驗所使用的單張 RTX 2000 Ada 機器不同。因此，本文件中的結果應作為 legacy baseline 參考，不應直接與目前 HAMi 實驗結果做硬體等價的數值比較。

## 1. 實驗目的

本實驗使用 NVIDIA GPU time-slicing 作為 GPU 共享機制的 baseline。

Time-slicing 的主要用途是讓多個 Pod 透過 NVIDIA device plugin 共享同一張實體 GPU。此方式部署相對簡單，但缺乏 GPU memory isolation，也無法針對不同 Pod 設定獨立的 GPU 記憶體或核心比例配額。

## 2. 實驗環境

| 項目 | 數值 |
|---|---|
| Kubernetes | v1.31.7 |
| CNI | Flannel |
| GPU | 2 × RTX 4070 SUPER |
| Driver | 550.144.03 |
| CUDA | 12.4 |
| Runtime | containerd |

## 3. Time-Slicing 設定

| 項目 | 數值 |
|---|---|
| 實體 GPU 數量 | 2 |
| 每張 GPU 的 replicas | 4 |
| 對 Kubernetes 宣告的 `nvidia.com/gpu` 數量 | 8 |

此設定會讓 Kubernetes 看到 8 個可分配的 GPU device，但實際上它們來自 2 張實體 GPU 的 time-slicing 共享。

## 4. vLLM 設定

| 項目 | 數值 |
|---|---|
| Image | vllm/vllm-openai:v0.8.5 |
| Model | Qwen/Qwen2.5-0.5B-Instruct |
| max-model-len | 2048 |
| max-num-seqs | 1 |
| gpu-memory-utilization | 0.35 |

## 5. 重要發現

請勿在 Pod spec 中手動設定：

```yaml
NVIDIA_VISIBLE_DEVICES=all
```

原因是此設定會繞過 NVIDIA device plugin 分配給 Pod 的 GPU visibility，可能造成多個 Pod 都看見並使用 `cuda:0`，導致原本的 time-slicing 分配失效或結果失真。

## 6. 穩定 baseline

| Replicas | Concurrency | 狀態 |
|---:|---:|---|
| 1 | 1 | 穩定 |
| 1 | 2 | 穩定 |
| 1 | 4 | 穩定 |
| 2 | 2 | 穩定 |
| 4 | 4 | 穩定 |
| 6 | 6 | 部分失敗 |

## 7. 小結

在此 2 × RTX 4070 SUPER 的 baseline 環境中，NVIDIA time-slicing 可以穩定執行最多 4 個 vLLM Pod，約等於每張實體 GPU 承載 2 個 vLLM instance。

然而，time-slicing 不提供 GPU memory isolation。當 replicas 進一步提高時，多個 vLLM instance 可能因 GPU memory contention 而出現 Pod 啟動失敗或推論失敗。
