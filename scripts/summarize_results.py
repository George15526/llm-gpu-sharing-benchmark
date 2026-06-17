# scripts/summarize_results.py
#!/usr/bin/env python3
import argparse
import csv
import json
from pathlib import Path
import statistics


def parse_float(x):
    try:
        return float(str(x).strip())
    except Exception:
        return None


def main():
    p = argparse.ArgumentParser()
    p.add_argument("result_dir")
    args = p.parse_args()

    d = Path(args.result_dir)
    summary_path = d / "summary.json"
    gpu_path = d / "gpu_metrics.csv"

    summary = json.loads(summary_path.read_text())

    gpu_utils = []
    mem_used = []
    power = []

    if gpu_path.exists():
        with gpu_path.open() as f:
            reader = csv.reader(f)
            header = next(reader, None)
            for row in reader:
                if len(row) < 9:
                    continue
                gpu_utils.append(parse_float(row[3]))
                mem_used.append(parse_float(row[5]))
                power.append(parse_float(row[7]))

    gpu_utils = [x for x in gpu_utils if x is not None]
    mem_used = [x for x in mem_used if x is not None]
    power = [x for x in power if x is not None]

    merged = dict(summary)
    merged.update({
        "gpu_util_avg_pct": statistics.mean(gpu_utils) if gpu_utils else None,
        "gpu_util_max_pct": max(gpu_utils) if gpu_utils else None,
        "gpu_mem_used_avg_mib": statistics.mean(mem_used) if mem_used else None,
        "gpu_mem_used_max_mib": max(mem_used) if mem_used else None,
        "gpu_power_avg_w": statistics.mean(power) if power else None,
        "gpu_power_max_w": max(power) if power else None,
    })

    print(json.dumps(merged, indent=2))
    (d / "merged_summary.json").write_text(json.dumps(merged, indent=2))


if __name__ == "__main__":
    main()
