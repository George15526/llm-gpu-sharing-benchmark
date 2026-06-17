# Experiment Design

## Objective

Compare different GPU sharing mechanisms for LLM inference on Kubernetes.

## Compared Methods

| Method | Description |
|---|---|
| `NVIDIA Time-Slicing` | Baseline GPU sharing using NVIDIA k8s-device-plugin |
| `HAMi` | Experimental GPU sharing framework with vGPU / memory / core quota |

## Workload

| Item | Value |
|---|---|
| Model | Qwen/Qwen2.5-0.5B-Instruct |
| Serving framework | vLLM |
| API | OpenAI-compatible API |
| Image | vllm/vllm-openai:v0.8.5 |

## Metrics

- End-to-end latency
- TTFT
- Requests per second
- Output tokens per second
- GPU memory usage
- GPU utilization
- Pod readiness / failure rate

## Benchmark Flow

Each experiment follows the procedure below:

1. Clean existing vLLM workloads.
2. Deploy the selected GPU sharing workload.
3. Scale vLLM Deployment to the target replica count.
4. Wait until all Pods are Ready.
5. Collect all ready service endpoints from `vllm-service`.
6. Validate that endpoint count equals replica count.
7. Check `/v1/models` readiness for each endpoint.
8. Send warm-up requests to each endpoint.
9. Run formal benchmark requests using round-robin endpoint dispatch.
10. Collect GPU metrics, Kubernetes metrics, request-level results, and summary statistics.
11. Repeat the same experiment multiple times for stability.

## Warm-up Policy

Before formal measurement, the benchmark client sends warm-up requests to each endpoint.

Default setting:

```text
warmup_requests_per_endpoint = 3
```

Warm-up requests are used to reduce first-request effects caused by CUDA lazy initialization, vLLM generation path initialization, tokenizer/cache setup, or GPU power-state transition.

Warm-up requests are not included in formal statistics.

## Repeated Experiments

Each formal configuration is repeated three times.

```bash
bash scripts/run_repeated_experiments.sh <mode> <replicas> <concurrency> <num_requests> 3
```

The repeated results are aggregated into repeated_summary.json, including mean, standard deviation, min, max, p50, p95, and p99 across runs.