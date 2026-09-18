#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

IDENTITY_FIELDS = (
    "scenario",
    "scenario_version",
    "profile",
    "renderer",
    "rendering_driver",
    "runner_id",
    "settings_hash",
)

def load(path: str) -> dict:
    return json.loads(Path(path).read_text(encoding="utf-8"))

def compare(baseline: dict, current: dict, budgets: dict) -> list[str]:
    mismatches = [
        field for field in IDENTITY_FIELDS
        if baseline.get(field) != current.get(field)
    ]
    if mismatches:
        raise ValueError("Non-comparable benchmark identity: " + ", ".join(mismatches))

    failures: list[str] = []
    for metric, policy in budgets.get("metrics", {}).items():
        if metric not in baseline or metric not in current:
            failures.append(f"{metric}: missing from benchmark result")
            continue
        base = float(baseline[metric])
        now = float(current[metric])
        allowed = float(policy["max_relative_regression"])
        if base <= 0:
            failures.append(f"{metric}: baseline must be > 0")
            continue
        regression = (now - base) / base
        if regression > allowed:
            failures.append(
                f"{metric}: {regression:.1%} regression exceeds {allowed:.1%} "
                f"(baseline={base:.4f}, current={now:.4f})"
            )
    return failures

def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("baseline")
    parser.add_argument("current")
    parser.add_argument("--budgets", default="perf/budgets.json")
    args = parser.parse_args()
    try:
        failures = compare(load(args.baseline), load(args.current), load(args.budgets))
    except ValueError as exc:
        print(str(exc), file=sys.stderr)
        return 2
    if failures:
        for failure in failures:
            print("PERF REGRESSION:", failure, file=sys.stderr)
        return 1
    print("Performance comparison passed")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
