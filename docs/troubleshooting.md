# 問題排查紀錄

## 1. vLLM Image Compatibility

| Image | 結果 |
|---|---|
| latest | NumPy package issue |
| v0.10.1 | CUDA Error 804 |
| v0.9.2 | torch cu128，CUDA Error 804 |
| v0.8.5 | 可正常運行，torch cu124 |
| v0.7.3 | libcusparse.so.12 issue |

目前建議使用：

```text
vllm/vllm-openai:v0.8.5
```

## 2. CUDA Error 804

### 現象

vLLM container 啟動時出現 CUDA Error 804。

### 可能原因

Container 內的 CUDA userspace 版本高於 host driver 可支援範圍，或在 GeForce / RTX 類 GPU 上觸發 unsupported forward compatibility 問題。

### 建議處理方式

使用已驗證可運行的 vLLM image：

```text
vllm/vllm-openai:v0.8.5
```

## 3. 不要手動設定 `NVIDIA_VISIBLE_DEVICES=all`

請勿在 Pod spec 中手動加入：

```yaml
NVIDIA_VISIBLE_DEVICES=all
```

原因是此設定可能繞過 NVIDIA device plugin 或 HAMi 分配給 Pod 的 GPU visibility，使多個 Pod 同時看到不該看到的 GPU，導致 GPU sharing 行為失真。

## 4. `UnexpectedAdmissionError`

### 可能原因

NVIDIA device plugin 回報沒有 healthy GPU device，或 kubelet / device plugin 狀態不同步。

### 建議恢復方式

```bash
kubectl delete pod -l app=vllm --grace-period=0 --force
kubectl rollout restart ds/nvidia-device-plugin -n kube-system
sudo systemctl restart kubelet
```

若目前使用 HAMi，則應檢查 HAMi device plugin 與 HAMi scheduler：

```bash
kubectl get pods -n kube-system -o wide | grep -i hami
kubectl logs -n kube-system -l app.kubernetes.io/name=hami --all-containers --tail=200
```

## 5. vLLM KV Cache Error

### 常見錯誤

```text
ValueError: No available memory for the cache blocks. Try increasing `gpu_memory_utilization` when initializing the engine.
```

### 可能原因

在多 Pod GPU sharing 或 HAMi memory quota 下，vLLM 根據 `gpu-memory-utilization` 計算可用 KV cache 空間時，判斷剩餘空間不足。

### 建議處理方式

可依序調整：

- 提高 `--gpu-memory-utilization`。
- 降低 `--max-model-len`。
- 降低 `--max-num-seqs`。
- 加上 `--max-num-batched-tokens`。
- 使用 `--enforce-eager`。
- 若使用 HAMi，確認 `nvidia.com/gpumem` 是否足夠。

範例：

```bash
--max-model-len 512 \
--max-num-seqs 1 \
--gpu-memory-utilization 0.30 \
--max-num-batched-tokens 512 \
--enforce-eager
```

## 6. HAMi `CardInsufficientMemory`

### 現象

Pending Pod 的 event 顯示：

```text
FilteringFailed   CardInsufficientMemory
```

### 意義

HAMi scheduler 認為該 GPU 在 HAMi 的資源帳本中，已沒有足夠可分配的 GPU memory。

這可能發生在 `nvidia-smi` 仍顯示有空閒 GPU memory 的情況，因為 HAMi scheduling 是依照 Pod 宣告資源與 HAMi 內部 vGPU allocation state 判斷，而不是只看即時實體使用量。

### 建議檢查

```bash
kubectl describe pod <pending-pod>
kubectl describe pod <running-pod> | grep -A20 -E "Annotations|Limits|Requests"
kubectl describe node <node-name> | grep -A100 -E "Capacity|Allocatable|Allocated resources"
```

若 `memory-aligned` 設定為：

```text
nvidia.com/gpumem = 6000
```

則 16GB GPU 上合理的上限約為 2 個 Pod，而不適合 4 個 Pod。

## 7. vLLM Orphan GPU Processes

### 現象

Pod 已被刪除，但 `nvidia-smi` 仍看到 `/usr/bin/python3` 佔用 GPU memory。

### 可能原因

vLLM 使用 multiprocessing。若 Pod 被頻繁刪除與重建，container runtime 或 GPU process 可能短暫殘留。

### 專案預設處理方式

本專案的 repeated experiments 預設使用 portable mode：

```text
Run 1：部署 workload
Run 2：沿用既有 ready workload
Run 3：沿用既有 ready workload
```

此方式避免每一輪都刪除 Pod，因此可降低 orphan GPU process 問題。

### Maintenance Mode

若本地實驗機已經出現殘留 process，可手動清理：

```bash
kubectl delete pod -l app=vllm --grace-period=0 --force --ignore-not-found
sudo pkill -TERM -f 'vllm.entrypoints.openai.api_server|multiprocessing.spawn|multiprocessing.resource_tracker'
sleep 3
sudo pkill -KILL -f 'vllm.entrypoints.openai.api_server|multiprocessing.spawn|multiprocessing.resource_tracker' 2>/dev/null || true
nvidia-smi
```

此流程需要 host 權限，僅作為維護用途，不應作為專案一般執行流程的必要條件。

## 8. Repeated Experiment Portable Mode

建議 repeated experiment 的正常流程如下：

```text
Run 1：clean workload → deploy Pods → warm-up → formal benchmark
Run 2：reuse existing ready Pods → warm-up → formal benchmark
Run 3：reuse existing ready Pods → warm-up → formal benchmark
```

此模式不需要：

- `sudo kill`
- 修改 sudoers
- 重啟 `containerd`
- 重啟 `kubelet`
- 每輪刪除並重建 Pod


## Evidence 公開前的資訊遮蔽

`results/evidence/` 內的檔案若要放到 public repository，應避免直接公開 raw Kubernetes YAML、Pod IP、node name、GPU UUID、container ID 或 host path。

目前建議 evidence 僅保留：

- `summary.json`
- `repeated_summary.json`
- `experiment_config.json`
- `gpu_metrics.csv`
- 已遮蔽後的 endpoint / Pod / node / nvidia-smi 文字快照

不建議將 `k8s_metrics/`、raw `pods_*.yaml`、`requests.jsonl`、repo 內的 `scripts/`、`k8s/`、`docs/` 重複放進 evidence。
