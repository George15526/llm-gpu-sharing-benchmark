# LLM GPU Sharing Benchmark on Kubernetes

## Overview

This project evaluates GPU sharing mechanisms for LLM inference workloads on Kubernetes.  
The baseline uses NVIDIA GPU time-slicing, while the experimental group uses HAMi.

## Architecture

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

## Compared Methods

| Method              | Role       | Description                                             |
| ------------------- | ---------- | ------------------------------------------------------- |
| NVIDIA Time-Slicing | Baseline   | Logical GPU sharing using NVIDIA k8s-device-plugin      |
| HAMi                | Experiment | GPU sharing with vGPU, GPU memory, and GPU core control |

## Evironment

| Item       | Value              |
| ---------- | ------------------ |
| Kubernetes | v1.31.7            |
| CNI        | Flannel            |
| GPU        | 2 × RTX 4070 SUPER |
| Driver     | 550.144.03         |
| CUDA       | 12.4               |
| Runtime    | containerd         |

## Workload

| Item              | Value                      |
| ----------------- | -------------------------- |
| Serving framework | vLLM                       |
| Model             | Qwen/Qwen2.5-0.5B-Instruct |
| Image             | vllm/vllm-openai:v0.8.5    |
| API               | OpenAI-compatible API      |

## Reproduction

```bash
WARMUP_REQUESTS_PER_ENDPOINT=3 bash scripts/run_experiment.sh timeslicing 1 1 100
WARMUP_REQUESTS_PER_ENDPOINT=3 bash scripts/run_experiment.sh timeslicing 2 2 100
WARMUP_REQUESTS_PER_ENDPOINT=3 bash scripts/run_experiment.sh timeslicing 4 4 100
```

## Metrics

- End-to-end latency
- Time To First Token, TTFT
- Requests per second
- Output tokens per second
- GPU memory usage
- GPU utilization
- Pod success / failure status

## Baseline Status

NVIDIA time-slicing can stably run 4 vLLM Pods in this environment.
Each physical GPU hosts 2 vLLM instances.

A 6-replica configuration may trigger Pod failures due to GPU memory contention.

## Documentation
- [Experiment Design](/docs/experiment-design.md)
- [NVIDIA Time-Slicing Baseline](/docs/baseline-timeslicing.md)
- [HAMi Experiment](/docs/hami-experiment.md)
- [Troubleshooting](/docs/troubleshooting.md)
- [Result Analysis](/docs/result-analysis.md)