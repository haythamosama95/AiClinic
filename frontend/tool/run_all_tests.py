#!/usr/bin/env python3
"""Run unit tests and boundary integration tests; print a combined final summary."""

import argparse
import subprocess
import sys
from pathlib import Path

TOOL_DIR = Path(__file__).resolve().parent
UNIT_RUNNER = TOOL_DIR / "run_unit_tests.py"
BOUNDARY_RUNNER = TOOL_DIR / "run_boundary_tests.py"


def _run(label: str, cmd: list[str]) -> int:
    print("\n" + "=" * 90)
    print(f"▶ {label}")
    print("=" * 90 + "\n")
    return subprocess.run(cmd).returncode


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
    args = parser.parse_args()

    if args.unit_only and args.boundary_only:
        parser.error("--unit-only and --boundary-only are mutually exclusive.")

    results: list[tuple[str, int]] = []

    if not args.boundary_only:
        results.append(("Unit tests", _run("Unit tests", [sys.executable, str(UNIT_RUNNER)])))

    if not args.unit_only:
        boundary_cmd = [sys.executable, str(BOUNDARY_RUNNER)]
        if args.boundary_subset:
            boundary_cmd.append(args.boundary_subset)
        results.append(
            ("Boundary tests", _run("Boundary tests", boundary_cmd))
        )

    print_final_summary(results)
    sys.exit(max(code for _, code in results))


if __name__ == "__main__":
    main()
