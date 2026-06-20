# HAMi GPU Sharing Experiment

## 1. 實驗目的

本實驗評估 HAMi 作為 Kubernetes GPU sharing mechanism 時，能否穩定支援 vLLM inference workload。

HAMi 與 NVIDIA time-slicing 的主要差異在於：HAMi 不只提供 GPU sharing，還能透過 vGPU、GPU memory quota 與 GPU core quota 進行更細緻的資源控制。

本輪已完成並納入紀錄的 profile 為：

1. `config-aligned`
2. `memory-aligned`

`controlled` profile 保留作為後續展示 HAMi GPU memory + GPU core 細緻控制能力的擴充組，不納入本次已完成數據表。

## 2. HAMi 預期特性

| 特性 | NVIDIA Time-Slicing | HAMi |
|---|---|---|
| GPU sharing | 支援 | 支援 |
| GPU memory quota | 不支援 | 支援 |
| GPU core quota | 不支援 | 支援 |
| Scheduler awareness | 較弱 | 較強 |
| Isolation | 較弱 | 較強 |

## 3. 目前 HAMi 實驗環境

| 項目 | 數值 |
|---|---|
| Kubernetes | kubeadm single-node Kubernetes |
| CNI | Flannel |
| GPU | 1 × NVIDIA RTX 2000 Ada Generation |
| GPU Memory | 16380 MiB |
| Driver | 595.71.05 |
| CUDA | 13.2 |
| Runtime | containerd |
| Scheduler | HAMi scheduler |
| vLLM Image | `vllm/vllm-openai:v0.8.5` |
| Model | `Qwen/Qwen2.5-0.5B-Instruct` |

> 注意：目前 HAMi 實驗與原始 time-slicing baseline 使用的硬體不同，因此本文件記錄的是目前單 GPU 機器上的 HAMi 實驗結果，不應直接與舊 baseline 的絕對效能數值做硬體等價比較。

## 4. HAMi Profile 設計

### 4.1 `config-aligned`

`config-aligned` 的目標是盡量對齊 baseline workload 的 vLLM 設定，並觀察同樣 workload 在 HAMi scheduler 下的可行性。此 profile 的重點不是展示 HAMi 的細緻切分功能，而是確認 vLLM 是否能在 HAMi 環境下穩定運作。

本次 evidence 中的 `config-aligned` 實驗包含：

| Replicas | Concurrency | Requests/Run | Repeat | 狀態 |
|---:|---:|---:|---:|---|
| 1 | 1 | 100 | 3 | 成功 300/300 |
| 1 | 2 | 100 | 3 | 成功 300/300 |
| 1 | 4 | 100 | 3 | 成功 300/300 |

常見設定：

```text
max-model-len = 512
max-num-seqs = 1
gpu-memory-utilization = 0.18
enforce-eager = true
VLLM_USE_V1 = 0
```

### 4.2 `memory-aligned`

`memory-aligned` 的目標是加入 HAMi GPU memory quota，使每個 vLLM Pod 的 GPU memory 配額更明確。此 profile 可觀察 HAMi 在 memory-aware scheduling 下的行為。

本次 evidence 中的 `memory-aligned` 實驗包含：

| Replicas | Concurrency | Requests/Run | Repeat | 狀態 |
|---:|---:|---:|---:|---|
| 1 | 1 | 100 | 3 | 成功 300/300 |
| 1 | 2 | 100 | 3 | 成功 300/300 |
| 1 | 4 | 100 | 3 | 成功 300/300 |
| 2 | 2 | 100 | 3 | 成功 300/300 |

常見 resource 設定：

```yaml
resources:
  limits:
    nvidia.com/gpu: 1
    nvidia.com/gpumem: 6000
```

常見 vLLM 設定：

```text
max-model-len = 512
max-num-seqs = 1
gpu-memory-utilization = 0.30
max-num-batched-tokens = 512
enforce-eager = true
```

### 4.3 `controlled`，後續擴充 profile

`controlled` profile 預計用於展示 HAMi 的額外細緻控制能力，例如同時設定 GPU memory quota 與 GPU core quota。

範例：

```yaml
resources:
  limits:
    nvidia.com/gpu: 1
    nvidia.com/gpumem: 6000
    nvidia.com/gpucores: 50
```

此設定會引入額外實驗變因，因此不應與 `config-aligned` 或 `memory-aligned` 的結果直接混合比較。

## 5. 已完成實驗結果摘要

本次整理的 HAMi evidence 只取用 `results/evidence/hami/` 下的資料，忽略 `results/evidence/timeslicing/`。所有表列資料均完成：

```text
repeat = 3
warmup_requests_per_endpoint = 3
formal_requests_per_run = 100
max_tokens = 128
```

{summary_table}

## 6. 詳細指標

下表為三次 repeated runs 聚合後的 mean / standard deviation 等摘要值。單位除特別標示外，latency 為 ms，GPU memory 為 MiB，power 為 W。

{detail_table}

## 7. 目前機器的限制

目前 HAMi 實驗機器為單張 RTX 2000 Ada，GPU memory 約 16380 MiB。

對 `memory-aligned` 而言，若每個 Pod 設定：

```text
nvidia.com/gpumem = 6000 MiB
```

則可推得：

```text
2 Pods × 6000 MiB = 12000 MiB < 16380 MiB
4 Pods × 6000 MiB = 24000 MiB > 16380 MiB
```

因此，`r4_c4` 不適合納入目前這台單 GPU 機器的 memory-aligned 正式實驗結果。本次 evidence 中的 `memory-aligned r2_c2` 是目前已整理資料中可觀察多 Pod sharing 的主要組合。

## 8. HAMi Scheduling 觀察

HAMi scheduler 的判斷依據是 HAMi 的資源帳本與 Pod 宣告資源，而不只是 `nvidia-smi` 顯示的即時實體 GPU memory 使用量。因此，可能出現以下情況：

```text
nvidia-smi 顯示仍有空閒 GPU memory
但 Pending Pod event 顯示 CardInsufficientMemory
```

這代表 HAMi 認為該 GPU 在其 vGPU 資源模型下已無足夠可分配資源。

## 9. 初步結果解讀

- 本次 `config-aligned` 與 `memory-aligned` 所有納入表格的 repeated groups 均達成 `300/300` successful requests，表示目前設定在已選定矩陣內可穩定完成 benchmark。
- `memory-aligned r2_c2` 的平均 RPS 為 {fmt([r for r in rows if r['profile']=='memory-aligned' and r['replicas']==2 and r['concurrency']==2][0]['rps'])}，高於 `memory-aligned r1_c1` 的 {fmt([r for r in rows if r['profile']=='memory-aligned' and r['replicas']==1 and r['concurrency']==1][0]['rps'])}，且 TTFT 平均仍維持在 {fmt([r for r in rows if r['profile']=='memory-aligned' and r['replicas']==2 and r['concurrency']==2][0]['ttft_avg'])} ms 左右，顯示此組為目前機器上較具參考價值的 sharing 成功案例。
- 單 Pod 情境下，`memory-aligned r1_c1` 的平均 E2E latency 為 {fmt([r for r in rows if r['profile']=='memory-aligned' and r['replicas']==1 and r['concurrency']==1][0]['e2e_avg'])} ms，低於 `config-aligned r1_c1` 的 {fmt([r for r in rows if r['profile']=='config-aligned' and r['replicas']==1 and r['concurrency']==1][0]['e2e_avg'])} ms；但此差異可能同時受到 vLLM 參數與 HAMi profile 設定影響，不應單獨解讀為 HAMi memory quota 的直接效能優勢。
- 當 concurrency 從 1 增加到 2 或 4 時，RPS 變化有限，但 E2E latency 與 TTFT 顯著上升，代表目前模型與 GPU 組合較容易受到序列化生成與排程等待影響。

## 10. 與 Baseline 的比較方式

由於目前 HAMi 實驗機器與原始 NVIDIA time-slicing baseline 機器不同，因此本輪結果主要用於：

- 確認 HAMi 在目前單 GPU 機器上的部署可行性。
- 觀察 vLLM 與 HAMi 的相容性。
- 觀察 HAMi memory quota 對 Pod scheduling 的影響。
- 確認目前機器可承載的 replicas / concurrency 範圍。

不應直接使用絕對 RPS 或 latency 數值，宣稱 HAMi 與舊 time-slicing baseline 之間的效能優劣。
