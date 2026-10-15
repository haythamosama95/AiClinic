#!/usr/bin/env python3
"""Write a per-area test trend comparison to a GitHub Actions job summary."""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
from typing import Any


METRICS = ("passed", "failed", "skipped", "total")
AREAS = (
    "frontend",
    "backend",
    "ai-platform",
    "abo",
    "e2e-fullstack",
    "vendor-contracts",
    "ops-launch",
)


def _stats_by_area(root: Path) -> dict[str, dict[str, int]]:
    totals: dict[str, dict[str, int]] = {}
    for path in sorted(root.rglob("stats.json")) if root.exists() else []:
        try:
            item: Any = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            continue
        if not isinstance(item, dict) or item.get("area") not in AREAS:
            continue
        area = item["area"]
        row = totals.setdefault(area, {metric: 0 for metric in METRICS})
        for metric in METRICS:
            value = item.get(metric)
            if isinstance(value, int) and not isinstance(value, bool):
                row[metric] += max(0, value)
    return totals


def _chart(area: str, metric: str, previous: dict[str, int] | None, current: dict[str, int] | None) -> str:
    series = [(label, stats) for label, stats in (("Previous", previous), ("Current", current)) if stats is not None]
    labels = ", ".join(f'"{label}"' for label, _ in series)
    values = [stats[metric] for _, stats in series]
    maximum = max(values, default=0)
    upper = max(1, int(maximum * 1.15))
    mermaid_values = ", ".join(str(value) for value in values)
    return (
        "```mermaid\n"
        "xychart-beta\n"
        f'    title "{area} — {metric}"\n'
        f"    x-axis [{labels}]\n"
        f'    y-axis "Tests" 0 --> {upper}\n'
        f"    bar [{mermaid_values}]\n"
        "```"
    )


def render(previous_root: Path, current_root: Path, previous_run_id: str | None, current_run_id: str) -> str:
    previous = _stats_by_area(previous_root)
    current = _stats_by_area(current_root)
    areas = [area for area in AREAS if area in current or area in previous]
    if not areas:
        return "## CI test history\n\nNo campaign test statistics were found in this run's artifacts.\n"

    previous_label = f"[#{previous_run_id}]({os.environ.get('GITHUB_SERVER_URL', 'https://github.com')}/{os.environ.get('GITHUB_REPOSITORY', '')}/actions/runs/{previous_run_id})" if previous_run_id else "No previous run"
    current_label = f"[#{current_run_id}]({os.environ.get('GITHUB_SERVER_URL', 'https://github.com')}/{os.environ.get('GITHUB_REPOSITORY', '')}/actions/runs/{current_run_id})"
    lines = [
        "## CI test history",
        "",
        f"Comparing previous completed CI run {previous_label} with current run {current_label}. Counts are summed from campaign subcampaigns for each area.",
        "",
        "| Campaign area (aggregated) | Run | Passed | Failed | Skipped | Total |",
        "|---|---|---:|---:|---:|---:|",
    ]
    for area in areas:
        for run_label, stats in ((previous_label, previous.get(area)), (current_label, current.get(area))):
            values = [str(stats[metric]) if stats is not None else "—" for metric in METRICS]
            lines.append(f"| `{area}` | {run_label} | " + " | ".join(values) + " |")
        for metric in METRICS:
            lines.extend((f"#### {metric.title()}", "", _chart(area, metric, previous.get(area), current.get(area)), ""))
    return "\n".join(lines).rstrip() + "\n"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--previous", type=Path, default=Path("ci-history/previous"))
    parser.add_argument("--current", type=Path, default=Path("ci-history/current"))
    parser.add_argument("--previous-run-id")
    parser.add_argument("--current-run-id", required=True)
    args = parser.parse_args()
    body = render(args.previous, args.current, args.previous_run_id, args.current_run_id)
    print(body, end="")
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        Path(summary).write_text(body, encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
