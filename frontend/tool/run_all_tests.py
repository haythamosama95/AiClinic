#!/usr/bin/env python3
"""Run unit tests and boundary integration tests; print a combined final summary."""

import argparse
import os
import subprocess
import sys
from pathlib import Path

from test_run_artifacts import (
    CAMPAIGN_ENV,
    create_campaign_dir,
    new_campaign_id,
    refresh_latest,
    utc_now_iso,
    write_campaign_artifacts,
)

TOOL_DIR = Path(__file__).resolve().parent
FRONTEND_ROOT = TOOL_DIR.parent
UNIT_RUNNER = TOOL_DIR / "run_unit_tests.py"
BOUNDARY_RUNNER = TOOL_DIR / "run_boundary_tests.py"


def _run(label: str, cmd: list[str], env: dict[str, str] | None = None) -> int:
    print("\n" + "=" * 90)
    print(f"▶ {label}")
    print("=" * 90 + "\n")
    return subprocess.run(cmd, env=env).returncode


def _status(exit_code: int) -> str:
    return "PASSED" if exit_code == 0 else "FAILED"


def print_final_summary(results: list[tuple[str, int]]) -> None:
    print("\n" + "=" * 90)
    print("COMBINED TEST RUN SUMMARY")
    print("=" * 90)
    for name, code in results:
        print(f"  {name:<24} {_status(code)} (exit {code})")
    print("=" * 90)
    overall = max(code for _, code in results)
    if overall == 0:
        print("Overall: PASSED")
    else:
        print(f"Overall: FAILED (exit {overall})")
    print("=" * 90)


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Run Flutter unit tests and boundary integration tests."
    )
    parser.add_argument(
        "--unit-only",
        action="store_true",
        help="Run only unit tests (exclude boundary tag).",
    )
    parser.add_argument(
        "--boundary-only",
        action="store_true",
        help="Run only boundary integration tests.",
    )
    parser.add_argument(
        "boundary_subset",
        nargs="?",
        choices=["auth", "settings", "patients", "postgrest"],
        help="Optional boundary subset (ignored with --unit-only).",
    )
    parser.add_argument(
        "--campaign-dir",
        type=Path,
        help="Directory for campaign-level artifacts (default: test-results/campaigns/<id>).",
    )
    parser.add_argument(
        "--no-artifacts",
        action="store_true",
        help="Skip writing log artifacts to disk.",
    )
    args = parser.parse_args()

    if args.unit_only and args.boundary_only:
        parser.error("--unit-only and --boundary-only are mutually exclusive.")

    artifacts_enabled = not args.no_artifacts
    campaign_id = new_campaign_id()
    campaign_dir: Path | None = None
    child_env: dict[str, str] | None = None

    if artifacts_enabled:
        campaign_dir = args.campaign_dir or create_campaign_dir(FRONTEND_ROOT, campaign_id)
        campaign_id = campaign_dir.name
        child_env = {
            **os.environ,
            CAMPAIGN_ENV: str(campaign_dir.resolve()),
        }

    started_at = utc_now_iso()
    results: list[tuple[str, int]] = []
    suite_results: list[dict[str, object]] = []

    def child_runner_cmd(runner: Path, extra: list[str] | None = None) -> list[str]:
        cmd = [sys.executable, str(runner)]
        if extra:
            cmd.extend(extra)
        if args.no_artifacts:
            cmd.append("--no-artifacts")
        elif campaign_dir is not None:
            cmd.extend(["--campaign-dir", str(campaign_dir)])
        return cmd

    if not args.boundary_only:
        unit_cmd = child_runner_cmd(UNIT_RUNNER)
        code = _run("Unit tests", unit_cmd, env=child_env)
        results.append(("Unit tests", code))
        if artifacts_enabled and campaign_dir:
            unit_dir = campaign_dir / "unit"
            suite_results.append(
                {
                    "name": "Unit tests",
                    "runner": "run_unit_tests.py",
                    "exit_code": code,
                    "artifact_dir": "unit",
                    "summary_path": str(unit_dir / "summary.json"),
                    "failures_path": str(unit_dir / "failures.json"),
                    "command": unit_cmd,
                }
            )

    if not args.unit_only:
        boundary_extra = [args.boundary_subset] if args.boundary_subset else []
        boundary_cmd = child_runner_cmd(BOUNDARY_RUNNER, boundary_extra)
        code = _run("Boundary tests", boundary_cmd, env=child_env)
        results.append(("Boundary tests", code))
        if artifacts_enabled and campaign_dir:
            boundary_dir = campaign_dir / "boundary"
            suite_results.append(
                {
                    "name": "Boundary tests",
                    "runner": "run_boundary_tests.py",
                    "exit_code": code,
                    "artifact_dir": "boundary",
                    "summary_path": str(boundary_dir / "summary.json"),
                    "failures_path": str(boundary_dir / "failures.json"),
                    "command": boundary_cmd,
                }
            )

    print_final_summary(results)
    overall = max(code for _, code in results)

    if artifacts_enabled and campaign_dir is not None:
        finished_at = utc_now_iso()
        write_campaign_artifacts(
            campaign_dir,
            campaign_id,
            started_at,
            finished_at,
            overall,
            suite_results,
        )
        refresh_latest(FRONTEND_ROOT, campaign_dir)
        print(f"\n📁 Campaign artifacts: {campaign_dir}")
        print(f"📁 Latest symlink/copy: {FRONTEND_ROOT / 'test-results' / 'latest'}")

    sys.exit(overall)


if __name__ == "__main__":
    main()
