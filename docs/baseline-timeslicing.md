# NVIDIA GPU Time-Slicing Baseline

## 1. Purpose

Use NVIDIA GPU time-slicing as the baseline GPU sharing mechanism.

## 2. Environment

| Item | Value |
|---|---|
| Kubernetes | v1.31.7 |
| CNI | Flannel |
| GPU | 2 × RTX 4070 SUPER |
| Driver | 550.144.03 |
| CUDA | 12.4 |
| Runtime | containerd |

## 3. Time-Slicing Configuration

| Item | Value |
|---|---|
| Physical GPUs | 2 |
| Replicas per GPU | 4 |
| Advertised `nvidia.com/gpu` | 8 |

## 4. vLLM Configuration

| Item | Value |
|---|---|
| Image | vllm/vllm-openai:v0.8.5 |
| Model | Qwen/Qwen2.5-0.5B-Instruct |
| max-model-len | 2048 |
| max-num-seqs | 1 |
| gpu-memory-utilization | 0.35 |

## 5. Important Finding

Do not manually set:

```yaml
NVIDIA_VISIBLE_DEVICES=all
```

> This bypasses the GPU visibility assigned by the NVIDIA device plugin and may cause multiple Pods to use cuda:0

## 6. Stable Baseline

| Replicas | Concurrency | Status          |
| -------: | ----------: | --------------- |
|        1 |           1 | Stable          |
|        1 |           2 | Stable          |
|        1 |           4 | Stable          |
|        2 |           2 | Stable          |
|        4 |           4 | Stable          |
|        6 |           6 | Partial failure |

## 7. Summary
NVIDIA time-slicing can run up to 4 vLLM Pods stably in this environment, with 2 Pods per physical GPU. However, it does not provide GPU memory isolation, and higher replica counts may fail due to memory contention.