#!/usr/bin/env python3
"""Run unit tests and boundary integration tests; print a combined final summary."""

from __future__ import annotations

import argparse
import os
import subprocess
import sys
import threading
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


def _run(
    label: str,
    cmd: list[str],
    env: dict[str, str] | None = None,
    cwd: Path | None = None,
) -> int:
    print("\n" + "=" * 90)
    print(f"▶ {label}")
    print("=" * 90 + "\n")
    return subprocess.run(cmd, env=env, cwd=cwd).returncode


def _forward_labeled_output(
    stream,
    label: str,
    lock: threading.Lock,
) -> None:
    tag = f"[{label}] "
    pending = b""
    last_spinner: str | None = None

    while True:
        chunk = stream.read(4096)
        if not chunk:
            break
        pending += chunk

        while True:
            sep_n = pending.find(b"\n")
            sep_r = pending.find(b"\r")
            if sep_n == -1 and sep_r == -1:
                break

            if sep_n == -1:
                sep_pos = sep_r
            elif sep_r == -1:
                sep_pos = sep_n
            else:
                sep_pos = min(sep_n, sep_r)

            line_bytes = pending[:sep_pos]
            pending = pending[sep_pos + 1 :]
            if pending.startswith(b"\n") and sep_pos == sep_r:
                pending = pending[1:]

            text = line_bytes.decode("utf-8", errors="replace").strip()
            if not text:
                continue

            is_spinner = "🧪" in text and "Running" in text
            if is_spinner and text == last_spinner:
                continue
            if is_spinner:
                last_spinner = text

            with lock:
                sys.stdout.write(f"{tag}{text}\n")
                sys.stdout.flush()

    if pending.strip():
        text = pending.decode("utf-8", errors="replace").strip()
        if text:
            with lock:
                sys.stdout.write(f"{tag}{text}\n")
                sys.stdout.flush()


def _run_streaming(
    label: str,
    cmd: list[str],
    env: dict[str, str] | None = None,
    cwd: Path | None = None,
    print_lock: threading.Lock | None = None,
) -> int:
    streaming_env = {**(env or os.environ), "PYTHONUNBUFFERED": "1"}
    process = subprocess.Popen(
        cmd,
        env=streaming_env,
        cwd=cwd,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        bufsize=0,
    )
    lock = print_lock or threading.Lock()
    assert process.stdout is not None
    _forward_labeled_output(process.stdout, label, lock)
    return process.wait()


def _run_parallel(
    suites: list[tuple[str, list[str]]],
    env: dict[str, str] | None = None,
    cwd: Path | None = None,
) -> list[tuple[str, int]]:
    labels = ", ".join(label for label, _ in suites)
    print(f"\n▶ Running suites in parallel: {labels}")
    print("=" * 90)
    print("(Live output is prefixed by suite name)\n")

    print_lock = threading.Lock()
    results: list[tuple[str, int] | None] = [None] * len(suites)

    def run_one(index: int, label: str, cmd: list[str]) -> None:
        code = _run_streaming(label, cmd, env=env, cwd=cwd, print_lock=print_lock)
        results[index] = (label, code)

    threads = [
        threading.Thread(target=run_one, args=(index, label, cmd), daemon=True)
        for index, (label, cmd) in enumerate(suites)
    ]
    for thread in threads:
        thread.start()
    for thread in threads:
        thread.join()

    return [entry for entry in results if entry is not None]


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
    parser.add_argument(
        "--parallel",
        action="store_true",
        help="Run unit and boundary suites concurrently (default: sequential).",
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

    for label, flutter_cmd in (
        ("flutter clean", ["flutter", "clean"]),
        ("flutter pub get", ["flutter", "pub", "get"]),
    ):
        code = _run(label, flutter_cmd, cwd=FRONTEND_ROOT)
        if code != 0:
            print(f"\n❌ {label} failed (exit {code}); aborting test run.")
            sys.exit(code)

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

    suites: list[tuple[str, list[str]]] = []
    suite_meta: list[dict[str, object]] = []

    if not args.boundary_only:
        unit_cmd = child_runner_cmd(UNIT_RUNNER)
        suites.append(("Unit tests", unit_cmd))
        if artifacts_enabled and campaign_dir:
            unit_dir = campaign_dir / "unit"
            suite_meta.append(
                {
                    "name": "Unit tests",
                    "runner": "run_unit_tests.py",
                    "artifact_dir": "unit",
                    "summary_path": str(unit_dir / "summary.json"),
                    "failures_path": str(unit_dir / "failures.json"),
                    "command": unit_cmd,
                }
            )

    if not args.unit_only:
        boundary_extra = [args.boundary_subset] if args.boundary_subset else []
        boundary_cmd = child_runner_cmd(BOUNDARY_RUNNER, boundary_extra)
        suites.append(("Boundary tests", boundary_cmd))
        if artifacts_enabled and campaign_dir:
            boundary_dir = campaign_dir / "boundary"
            suite_meta.append(
                {
                    "name": "Boundary tests",
                    "runner": "run_boundary_tests.py",
                    "artifact_dir": "boundary",
                    "summary_path": str(boundary_dir / "summary.json"),
                    "failures_path": str(boundary_dir / "failures.json"),
                    "command": boundary_cmd,
                }
            )

    if len(suites) == 1:
        label, cmd = suites[0]
        code = _run(label, cmd, env=child_env)
        results.append((label, code))
        if suite_meta:
            suite_results.append({**suite_meta[0], "exit_code": code})
    elif args.parallel:
        parallel_results = _run_parallel(suites, env=child_env)
        results.extend(parallel_results)
        for meta, (_label, code) in zip(suite_meta, parallel_results, strict=True):
            suite_results.append({**meta, "exit_code": code})
    else:
        for index, (label, cmd) in enumerate(suites):
            code = _run(label, cmd, env=child_env)
            results.append((label, code))
            if index < len(suite_meta):
                suite_results.append({**suite_meta[index], "exit_code": code})

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
