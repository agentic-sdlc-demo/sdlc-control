#!/usr/bin/env python3
"""Western Electric detection over tasklist-prod metrics samples.

Reads a JSONL metrics log (one sample per line: {"ts": ..., "p95_ms": ...,
"error_count": ...}) produced by the local sampler cron hitting /metrics.

Control bands come from a baseline window; breaches escalate:
  1 sigma -> LOG only
  2 sigma -> DIAGNOSE (invoke Claude headlessly, commit a report)
  3 sigma -> FILE_INTENT (Claude files an intents/INT-*.md PR in sdlc-control)

Prints the action for the newest sample; the wrapper script acts on it.
"""
import json
import statistics
import sys

BASELINE = 30  # samples used to establish the control bands
METRIC = "p95_ms"


def main(path: str) -> int:
    with open(path) as f:
        samples = [json.loads(line) for line in f if line.strip()]
    if len(samples) < BASELINE + 1:
        print(f"WARMUP not enough samples ({len(samples)}/{BASELINE + 1})")
        return 0

    baseline = [s[METRIC] for s in samples[:BASELINE]]
    mean = statistics.fmean(baseline)
    sigma = statistics.stdev(baseline) or 1e-9
    latest = samples[-1][METRIC]
    z = (latest - mean) / sigma

    if z >= 3:
        action = "FILE_INTENT"
    elif z >= 2:
        action = "DIAGNOSE"
    elif z >= 1:
        action = "LOG"
    else:
        action = "OK"
    print(f"{action} metric={METRIC} latest={latest:.1f} mean={mean:.1f} sigma={sigma:.1f} z={z:.2f}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1] if len(sys.argv) > 1 else "metrics.jsonl"))
