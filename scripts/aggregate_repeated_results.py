#!/usr/bin/env python3
import json
import statistics
import sys
from pathlib import Path


METRICS = [
    "requests_per_sec",
    "output_tokens_per_sec",
    "e2e_latency_avg_ms",
    "e2e_latency_p50_ms",
    "e2e_latency_p95_ms",
    "e2e_latency_p99_ms",
    "ttft_avg_ms",
    "ttft_p50_ms",
    "ttft_p95_ms",
    "ttft_p99_ms",
    "gpu_util_avg_pct",
    "gpu_util_max_pct",
    "gpu_mem_used_avg_mib",
    "gpu_mem_used_max_mib",
    "gpu_power_avg_w",
    "gpu_power_max_w",
]


def load_json(path: Path):
    with path.open() as f:
        return json.load(f)


def stat_values(values):
    values = [v for v in values if isinstance(v, (int, float))]
    if not values:
        return None

    values_sorted = sorted(values)

    def pct(p):
        idx = int((len(values_sorted) - 1) * p / 100)
        return values_sorted[idx]

    return {
        "count": len(values),
        "mean": statistics.mean(values),
        "stdev": statistics.stdev(values) if len(values) >= 2 else 0.0,
        "min": min(values),
        "max": max(values),
        "p50": pct(50),
        "p95": pct(95),
        "p99": pct(99),
    }


def main():
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <repeat_group_dir>")
        raise SystemExit(1)

    root = Path(sys.argv[1])

    # Prefer merged_summary.json if available, otherwise summary.json.
    summary_paths = []
    for p in root.rglob("merged_summary.json"):
        summary_paths.append(p)

    if not summary_paths:
        summary_paths = list(root.rglob("summary.json"))

    if not summary_paths:
        raise SystemExit(f"No summary files found under {root}")

    rows = []
    for p in sorted(summary_paths):
        data = load_json(p)
        data["_path"] = str(p)
        rows.append(data)

    output = {
        "group_dir": str(root),
        "run_count": len(rows),
        "runs": rows,
        "metrics": {},
    }

    for metric in METRICS:
        values = [r.get(metric) for r in rows]
        s = stat_values(values)
        if s is not None:
            output["metrics"][metric] = s

    # Basic metadata from first run.
    first = rows[0]
    for key in [
        "mode",
        "model",
        "num_requests",
        "concurrency",
        "max_tokens",
        "endpoint_count",
        "warmup_requests_per_endpoint",
        "warmup_total_requests",
    ]:
        if key in first:
            output[key] = first[key]

    out_path = root / "repeated_summary.json"
    with out_path.open("w") as f:
        json.dump(output, f, indent=2)

    print(json.dumps(output["metrics"], indent=2))
    print(f"[INFO] Wrote {out_path}")


if __name__ == "__main__":
    main()