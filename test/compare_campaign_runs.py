#!/usr/bin/env python3
"""Compare campaign stats downloaded from two GitHub Actions runs."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any


METRICS = ("passed", "failed", "skipped", "attempted", "total", "elapsed_seconds")


def _stats_files(root: Path) -> dict[str, dict[str, Any]]:
    matches = sorted(root.rglob("stats.json"))
    if not matches:
        raise FileNotFoundError(f"no stats.json files found under {root}")
    rows: dict[str, dict[str, Any]] = {}
    for path in matches:
        try:
            row = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as exc:
            raise ValueError(f"cannot read {path}: {exc}") from exc
        if not isinstance(row, dict):
            continue
        area, sub = row.get("area"), row.get("subcampaign")
        if isinstance(area, str) and isinstance(sub, str):
            key = f"{area}/{sub}"
            rows[key] = row
    if not rows:
        raise ValueError(f"no valid campaign stats found under {root}")
    return rows


def _fmt(value: Any) -> str:
    if value is None:
        return "—"
    if isinstance(value, float):
        return f"{value:.1f}s"
    return str(value)


def _delta(a: Any, b: Any) -> str:
    if isinstance(a, (int, float)) and not isinstance(a, bool) and isinstance(b, (int, float)) and not isinstance(b, bool):
        diff = b - a
        if isinstance(diff, float):
            return f"{diff:+.1f}s"
        return f"{diff:+d}"
    return "—" if a == b else f"{_fmt(a)} → {_fmt(b)}"


def compare(run_a: dict[str, dict[str, Any]], run_b: dict[str, dict[str, Any]], area: str | None) -> str:
    keys = sorted(set(run_a) | set(run_b))
    if area:
        keys = [key for key in keys if key.split("/", 1)[0] == area]
    if not keys:
        raise ValueError(f"no matching campaign stats found{f' for area {area}' if area else ''}")

    lines = [
        "| Campaign | Status (A → B) | Passed Δ | Failed Δ | Skipped Δ | Attempted Δ | Total Δ | Time Δ |",
        "|---|---|---:|---:|---:|---:|---:|---:|",
    ]
    for key in keys:
        a, b = run_a.get(key), run_b.get(key)
        if a is None or b is None:
            lines.append(f"| `{key}` | {'missing in A' if a is None else 'missing in B'} | — | — | — | — | — | — |")
            continue
        status_a = "passed" if a.get("exit_code") == 0 else "failed" if a.get("exit_code") not in (None, 0) else "partial"
        status_b = "passed" if b.get("exit_code") == 0 else "failed" if b.get("exit_code") not in (None, 0) else "partial"
        cells = [
            f"{_delta(a.get(metric), b.get(metric))}"
            for metric in METRICS
        ]
        lines.append(f"| `{key}` | {status_a} → {status_b} | " + " | ".join(cells) + " |")
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run-a", type=Path, required=True)
    parser.add_argument("--run-b", type=Path, required=True)
    parser.add_argument("--run-a-id", required=True)
    parser.add_argument("--run-b-id", required=True)
    parser.add_argument("--area")
    parser.add_argument("--github-summary", action="store_true")
    args = parser.parse_args()
    try:
        table = compare(_stats_files(args.run_a), _stats_files(args.run_b), args.area)
    except (FileNotFoundError, ValueError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2
    heading = f"## Campaign comparison: run #{args.run_a_id} → run #{args.run_b_id}"
    body = f"{heading}\n\n{table}\n"
    print(body, end="")
    if args.github_summary:
        import os

        target = os.environ.get("GITHUB_STEP_SUMMARY")
        if target:
            with Path(target).open("a", encoding="utf-8") as stream:
                stream.write(body)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
