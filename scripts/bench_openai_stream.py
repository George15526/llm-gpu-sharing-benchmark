# scripts/bench_openai_stream.py
#!/usr/bin/env python3
import argparse
import asyncio
import aiohttp
import json
import statistics
import time
from pathlib import Path


def estimate_tokens(text: str) -> int:
    # 粗估：英文約 4 chars/token；中文會不準。
    # 若要論文級嚴謹，後續建議改用 HF tokenizer。
    return max(1, len(text) // 4)


async def one_request(session, url, model, prompt, max_tokens, temperature, request_id):
    payload = {
        "model": model,
        "messages": [{"role": "user", "content": prompt}],
        "max_tokens": max_tokens,
        "temperature": temperature,
        "stream": True,
        "stream_options": {"include_usage": True},
    }

    start = time.perf_counter()
    first_token_time = None
    chunks = []
    error = None
    usage = None

    try:
        async with session.post(url, json=payload, timeout=None) as resp:
            if resp.status != 200:
                error = f"HTTP {resp.status}: {await resp.text()}"
            else:
                async for raw in resp.content:
                    line = raw.decode("utf-8", errors="ignore").strip()
                    if not line or not line.startswith("data:"):
                        continue
                    data = line[len("data:"):].strip()
                    if data == "[DONE]":
                        break
                    try:
                        obj = json.loads(data)
                    except Exception:
                        continue

                    if obj.get("usage"):
                        usage = obj["usage"]

                    choices = obj.get("choices") or []
                    if choices:
                        delta = choices[0].get("delta", {})
                        content = delta.get("content")
                        if content:
                            if first_token_time is None:
                                first_token_time = time.perf_counter()
                            chunks.append(content)
    except Exception as e:
        error = repr(e)

    end = time.perf_counter()
    output_text = "".join(chunks)

    completion_tokens = None
    prompt_tokens = None
    total_tokens = None
    if usage:
        completion_tokens = usage.get("completion_tokens")
        prompt_tokens = usage.get("prompt_tokens")
        total_tokens = usage.get("total_tokens")

    if completion_tokens is None:
        completion_tokens = estimate_tokens(output_text)

    return {
        "request_id": request_id,
        "endpoint": url.split("/v1/chat/completions")[0],
        "success": error is None,
        "error": error,
        "e2e_latency_ms": (end - start) * 1000,
        "ttft_ms": None if first_token_time is None else (first_token_time - start) * 1000,
        "output_chars": len(output_text),
        "completion_tokens": completion_tokens,
        "prompt_tokens": prompt_tokens,
        "total_tokens": total_tokens,
    }


async def run(args):
    if args.endpoints:
        endpoints = [x.strip().rstrip("/") for x in args.endpoints.split(",") if x.strip()]
    else:
        endpoints = [args.endpoint.rstrip("/")]

    if not endpoints:
        raise ValueError("No valid endpoints provided.")

    prompt = args.prompt

    connector = aiohttp.TCPConnector(limit=max(args.concurrency, len(endpoints)))
    timeout = aiohttp.ClientTimeout(total=None)

    results = []

    async with aiohttp.ClientSession(connector=connector, timeout=timeout) as session:
        # Warm-up phase: not included in formal statistics.
        if args.warmup_requests_per_endpoint > 0:
            print(
                f"[INFO] Warm-up: {args.warmup_requests_per_endpoint} requests per endpoint, "
                f"{len(endpoints)} endpoints",
                flush=True,
            )

            warmup_id = -1
            for ep in endpoints:
                warmup_url = ep + "/v1/chat/completions"
                for _ in range(args.warmup_requests_per_endpoint):
                    warmup_result = await one_request(
                        session=session,
                        url=warmup_url,
                        model=args.model,
                        prompt=prompt,
                        max_tokens=args.max_tokens,
                        temperature=args.temperature,
                        request_id=warmup_id,
                    )
                    warmup_result["endpoint"] = ep
                    warmup_result["phase"] = "warmup"
                    print(json.dumps(warmup_result), flush=True)
                    warmup_id -= 1

        print("[INFO] Warm-up completed. Starting formal benchmark...", flush=True)

        sem = asyncio.Semaphore(args.concurrency)
        start = time.perf_counter()

        async def guarded(i):
            async with sem:
                base_url = endpoints[i % len(endpoints)]
                url = base_url + "/v1/chat/completions"

                result = await one_request(
                    session=session,
                    url=url,
                    model=args.model,
                    prompt=prompt,
                    max_tokens=args.max_tokens,
                    temperature=args.temperature,
                    request_id=i,
                )
                result["phase"] = "benchmark"
                return result

        tasks = [asyncio.create_task(guarded(i)) for i in range(args.num_requests)]
        for t in asyncio.as_completed(tasks):
            r = await t
            results.append(r)
            print(json.dumps(r), flush=True)

        end = time.perf_counter()

    duration = end - start

    ok = [r for r in results if r["success"]]
    failed = [r for r in results if not r["success"]]

    lat = [r["e2e_latency_ms"] for r in ok]
    ttft = [r["ttft_ms"] for r in ok if r["ttft_ms"] is not None]
    out_tokens = sum(r["completion_tokens"] or 0 for r in ok)

    def pct(xs, p):
        if not xs:
            return None
        xs = sorted(xs)
        idx = int((len(xs) - 1) * p / 100)
        return xs[idx]
    
    endpoint_request_count = {}
    for r in ok:
        ep = r["endpoint"]
        endpoint_request_count[ep] = endpoint_request_count.get(ep, 0) + 1

    summary = {
        "mode": args.mode,
        "model": args.model,
        "num_requests": args.num_requests,
        "concurrency": args.concurrency,
        "max_tokens": args.max_tokens,
        "endpoint_count": len(endpoints),
        "endpoints": endpoints,
        "endpoint_request_count": endpoint_request_count,
        "warmup_requests_per_endpoint": args.warmup_requests_per_endpoint,
        "warmup_total_requests": args.warmup_requests_per_endpoint * len(endpoints),
        "success_count": len(ok),
        "failed_count": len(failed),
        "duration_sec": duration,
        "requests_per_sec": len(ok) / duration if duration > 0 else 0,
        "output_tokens_per_sec": out_tokens / duration if duration > 0 else 0,
        "e2e_latency_avg_ms": statistics.mean(lat) if lat else None,
        "e2e_latency_p50_ms": pct(lat, 50),
        "e2e_latency_p95_ms": pct(lat, 95),
        "e2e_latency_p99_ms": pct(lat, 99),
        "ttft_avg_ms": statistics.mean(ttft) if ttft else None,
        "ttft_p50_ms": pct(ttft, 50),
        "ttft_p95_ms": pct(ttft, 95),
        "ttft_p99_ms": pct(ttft, 99),
    }

    Path(args.output_dir).mkdir(parents=True, exist_ok=True)

    with open(Path(args.output_dir) / "requests.jsonl", "w") as f:
        for r in results:
            f.write(json.dumps(r) + "\n")

    with open(Path(args.output_dir) / "summary.json", "w") as f:
        json.dump(summary, f, indent=2)

    print("===== SUMMARY =====")
    print(json.dumps(summary, indent=2))


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--mode", required=True, choices=["timeslicing", "hami"])
    p.add_argument("--endpoint", default="http://127.0.0.1:8000")
    p.add_argument("--model", default="Qwen/Qwen2.5-0.5B-Instruct")
    p.add_argument("--num-requests", type=int, default=100)
    p.add_argument("--concurrency", type=int, default=4)
    p.add_argument("--max-tokens", type=int, default=128)
    p.add_argument("--temperature", type=float, default=0.0)
    p.add_argument("--prompt", default="Explain Kubernetes GPU sharing in 5 bullet points.")
    p.add_argument("--output-dir", required=True)
    p.add_argument("--endpoints", default=None, help="Comma-separated endpoint list. Requests will be distributed round-robin.")
    p.add_argument("--warmup-requests-per-endpoint", type=int, default=0, help="Number of warm-up requests sent to each endpoint before formal benchmark.")
    args = p.parse_args()

    asyncio.run(run(args))


if __name__ == "__main__":
    main()
