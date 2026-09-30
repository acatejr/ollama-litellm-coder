"""Benchmark the model through the LiteLLM proxy, the way clients experience it.

For each prompt size it measures:
  - time to first token (TTFT): how long you wait before anything appears
  - prefill speed: prompt tokens / TTFT, i.e. how fast the model reads the prompt
  - output speed: generated tokens / time spent generating

Every request starts with a unique marker so Ollama can't reuse a cached prompt
from an earlier request; otherwise repeats would look unrealistically fast.

Reads LITELLM_PROXY_API_BASE and TF_VAR_litellm_api_key from .env (same as main.py).

Examples:
  uv run benchmark.py                          # default sizes 1k, 4k, 8k, 16k tokens
  uv run benchmark.py --sizes 1000 4000 -r 3   # custom sizes, 3 runs each
  uv run benchmark.py --markdown               # also print a table for the README
"""

import argparse
import os
import statistics
import sys
import time
import uuid

from dotenv import load_dotenv
from litellm import completion

load_dotenv()

CHARS_PER_TOKEN = 3.5  # rough ratio for Python code; reported counts come from the server


def make_code(target_tokens: int) -> str:
    """Generate varied, realistic-looking Python of roughly target_tokens tokens."""
    blocks = []
    i = 0
    while sum(len(b) for b in blocks) / CHARS_PER_TOKEN < target_tokens:
        blocks.append(
            f"def process_record_{i}(record: dict, threshold: int = {i % 17 + 3}) -> dict:\n"
            f'    """Normalize record {i} and flag values above the threshold."""\n'
            f"    result = {{}}\n"
            f"    for key, value in record.items():\n"
            f"        if isinstance(value, (int, float)) and value > threshold * {i % 5 + 1}:\n"
            f"            result[f\"{{key}}_flag_{i}\"] = True\n"
            f"        result[key.strip().lower()] = value\n"
            f"    return result\n\n"
        )
        i += 1
    return "".join(blocks)


def make_prompt(target_tokens: int) -> str:
    code = make_code(target_tokens)
    return (
        f"[benchmark run {uuid.uuid4()}]\n"  # unique prefix defeats prompt caching
        f"Here is a Python module:\n```python\n{code}```\n"
        "In two sentences, summarize what this module does."
    )


def run_once(model: str, api_base: str, api_key: str, prompt: str, max_tokens: int, timeout: float) -> dict:
    start = time.perf_counter()
    first = None
    chunks = 0
    usage = None

    stream = completion(
        model=model,
        api_base=api_base,
        api_key=api_key,
        messages=[{"role": "user", "content": prompt}],
        max_tokens=max_tokens,
        temperature=0,
        stream=True,
        stream_options={"include_usage": True},
        timeout=timeout,
    )
    for chunk in stream:
        if chunk.choices and chunk.choices[0].delta.content:
            if first is None:
                first = time.perf_counter()
            chunks += 1
        if getattr(chunk, "usage", None):
            usage = chunk.usage
    end = time.perf_counter()

    if first is None:
        raise RuntimeError("model returned no content")

    prompt_tokens = usage.prompt_tokens if usage else round(len(prompt) / CHARS_PER_TOKEN)
    output_tokens = usage.completion_tokens if usage else chunks  # ~1 token per chunk
    ttft = first - start
    gen_time = end - first
    return {
        "prompt_tokens": prompt_tokens,
        "output_tokens": output_tokens,
        "ttft": ttft,
        "prefill_tps": prompt_tokens / ttft,
        "output_tps": (output_tokens - 1) / gen_time if gen_time > 0 and output_tokens > 1 else 0.0,
        "total": end - start,
        "estimated": usage is None,
    }


def summarize(runs: list[dict]) -> dict:
    return {
        key: statistics.median(r[key] for r in runs)
        for key in ("prompt_tokens", "output_tokens", "ttft", "prefill_tps", "output_tps", "total")
    } | {"estimated": any(r["estimated"] for r in runs)}


def print_table(rows: list[tuple[int, dict]], markdown: bool) -> None:
    headers = ["Target", "Prompt tok", "TTFT (s)", "Prefill tok/s", "Output tok/s", "Total (s)"]
    lines = [
        [
            f"{target:,}",
            f"{s['prompt_tokens']:,.0f}" + ("*" if s["estimated"] else ""),
            f"{s['ttft']:.1f}",
            f"{s['prefill_tps']:.0f}",
            f"{s['output_tps']:.1f}",
            f"{s['total']:.1f}",
        ]
        for target, s in rows
    ]
    if markdown:
        print("| " + " | ".join(headers) + " |")
        print("|" + "---|" * len(headers))
        for line in lines:
            print("| " + " | ".join(line) + " |")
    else:
        widths = [max(len(h), *(len(l[i]) for l in lines)) for i, h in enumerate(headers)]
        print("  ".join(h.rjust(w) for h, w in zip(headers, widths)))
        for line in lines:
            print("  ".join(c.rjust(w) for c, w in zip(line, widths)))
    if any(s["estimated"] for _, s in rows):
        print("* server did not report token usage; counts are estimates")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--sizes", type=int, nargs="+", default=[1000, 4000, 8000, 16000],
                        help="approximate prompt sizes in tokens (default: 1000 4000 8000 16000)")
    parser.add_argument("-r", "--repeats", type=int, default=2, help="runs per size; median is reported (default: 2)")
    parser.add_argument("--max-tokens", type=int, default=128, help="output tokens per request (default: 128)")
    parser.add_argument("--model", default="qwen2.5-coder-3b", help="LiteLLM model name (default: qwen2.5-coder-3b)")
    parser.add_argument("--timeout", type=float, default=1800, help="per-request timeout in seconds (default: 1800)")
    parser.add_argument("--no-warmup", action="store_true", help="skip the warm-up request")
    parser.add_argument("--markdown", action="store_true", help="print the results as a Markdown table")
    args = parser.parse_args()

    api_base = os.environ.get("LITELLM_PROXY_API_BASE")
    api_key = os.environ.get("TF_VAR_litellm_api_key")
    if not api_base or not api_key:
        print("error: set LITELLM_PROXY_API_BASE and TF_VAR_litellm_api_key (e.g. in .env)", file=sys.stderr)
        return 1
    model = f"litellm_proxy/{args.model}"

    print(f"Benchmarking {args.model} at {api_base}")
    print(f"sizes={args.sizes} repeats={args.repeats} max_tokens={args.max_tokens}")
    print("Large prompts can take several minutes each on CPU.\n")

    if not args.no_warmup:
        print("warm-up (loads the model if needed)...", flush=True)
        run_once(model, api_base, api_key, make_prompt(50), 16, args.timeout)

    rows = []
    for target in args.sizes:
        runs = []
        for n in range(1, args.repeats + 1):
            print(f"  ~{target:,} tokens, run {n}/{args.repeats}...", end=" ", flush=True)
            r = run_once(model, api_base, api_key, make_prompt(target), args.max_tokens, args.timeout)
            print(f"TTFT {r['ttft']:.1f}s, prefill {r['prefill_tps']:.0f} tok/s, output {r['output_tps']:.1f} tok/s")
            runs.append(r)
        rows.append((target, summarize(runs)))

    print("\nResults (median per size):\n")
    print_table(rows, markdown=False)
    if args.markdown:
        print()
        print_table(rows, markdown=True)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        sys.exit(130)
