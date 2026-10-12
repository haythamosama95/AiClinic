#!/usr/bin/env python3
"""Print failed campaign tests for GitHub Actions (stdout, annotations, step summary)."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPT_DIR))

from harness.github_campaign_report import report_area_to_github  # noqa: E402
from harness.governor_run_manifest import resolve_governor_run_dir  # noqa: E402


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Report governor campaign failures for CI.")
    parser.add_argument("--area", required=True, help="Root campaign area id.")
    parser.add_argument(
        "--run",
        default="latest",
        help="Governor run directory, run.json path, or ``latest``.",
    )
    parser.add_argument(
        "--github-summary",
        action="store_true",
        help="Append markdown to GITHUB_STEP_SUMMARY when set.",
    )
    parser.add_argument(
        "--print-run-dir",
        action="store_true",
        help="Print resolved governor run directory and exit.",
    )
    parser.add_argument(
        "--no-annotations",
        action="store_true",
        help="Do not emit ::error:: workflow commands.",
    )
    args = parser.parse_args(argv)

    try:
        run_root = resolve_governor_run_dir(args.run)
    except FileNotFoundError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2

    if args.print_run_dir:
        print(run_root)
        return 0

    failures = report_area_to_github(
        run_root,
        args.area,
        github_summary=args.github_summary,
        annotations=not args.no_annotations,
    )
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
