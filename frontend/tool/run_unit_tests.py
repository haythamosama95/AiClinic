#!/usr/bin/env python3

import argparse
import json
import os
import subprocess
import sys
from collections import defaultdict
from pathlib import Path

from discover_tests import count_expected_tests, unit_test_files
from test_run_artifacts import (
    MachineEventRecorder,
    refresh_latest,
    resolve_suite_artifact_dir,
)
from test_run_progress import LiveTestDisplay

ROOT = Path(__file__).resolve().parent.parent
os.chdir(ROOT)

CONCURRENCY = 15

FAILURES = []
CURRENT_TEST = None

DISPLAY: LiveTestDisplay | None = None
RECORDER: MachineEventRecorder | None = None


# ---------------- Runner ----------------

def run_tests(test_files: list[str]) -> int:
    if not test_files:
        print("ERROR: no unit/widget/integration test files found.", file=sys.stderr)
        return 1

    cmd = [
        "flutter",
        "test",
        *test_files,
        "--concurrency",
        str(CONCURRENCY),
        "--machine",
    ]

    global RECORDER
    if RECORDER is not None:
        RECORDER.command = cmd
        RECORDER.test_files = test_files

    process = subprocess.Popen(
        cmd,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        bufsize=1,
    )

    for line in process.stdout:
        line = line.strip()
        if not line:
            continue

        if RECORDER is not None:
            parsed = RECORDER.ingest_line(line)
        else:
            try:
                parsed = json.loads(line)
            except json.JSONDecodeError:
                continue

        if parsed is None:
            continue

        handle_event(parsed)

    return process.wait()


# ---------------- Event Handling ----------------

def handle_event(event):
    global CURRENT_TEST

    if isinstance(event, list):
        for e in event:
            handle_event(e)
        return

    if not isinstance(event, dict):
        return

    if DISPLAY is not None:
        DISPLAY.handle_event(event)

    event_type = event.get("type")

    if event_type == "testStart":
        CURRENT_TEST = event.get("test", {}).get("name")

    elif event_type == "error":
        FAILURES.append({
            "test": CURRENT_TEST or "Unknown test",
            "message": event.get("error", "").strip(),
            "stack": event.get("stackTrace", "").strip()
        })


# ---------------- Summary ----------------

def print_summary():
    if FAILURES:
        print("\n" + "=" * 90)
        print("❌ FLUTTER TEST FAILURE REPORT")
        print("=" * 90)

    if not FAILURES:
        print("🎉 All tests passed successfully!")
        return

    grouped = defaultdict(list)

    for f in FAILURES:
        grouped[f["test"]].append(f)

    for i, (test, issues) in enumerate(grouped.items(), 1):
        print(f"\n[{i}] 🧪 {test}")
        print("-" * 90)

        for issue in issues:
            print("🔴 Error:")
            print(issue["message"] or "No message")

            if issue["stack"]:
                print("\n📍 Stack (trimmed):")
                print("\n".join(issue["stack"].splitlines()[:12]))

            print("-" * 90)

    print("\n" + "=" * 90)
    print(f"Failures: {len(FAILURES)}")
    print("=" * 90)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Run Flutter unit/widget/integration tests.")
    parser.add_argument(
        "--artifacts-dir",
        type=Path,
        help="Directory for test log artifacts (summary, failures, raw).",
    )
    parser.add_argument(
        "--campaign-dir",
        type=Path,
        help="Campaign root; suite artifacts written to <campaign-dir>/unit.",
    )
    parser.add_argument(
        "--no-artifacts",
        action="store_true",
        help="Skip writing log artifacts to disk.",
    )
    return parser.parse_args()


# ---------------- Main ----------------

def main():
    args = parse_args()
    artifacts_enabled = not args.no_artifacts
    campaign_dir = args.campaign_dir
    artifact_dir = None
    if artifacts_enabled:
        artifact_dir = resolve_suite_artifact_dir(
            ROOT,
            "unit",
            args.artifacts_dir,
            campaign_dir,
        )

    test_files = unit_test_files(ROOT)
    total_tests = count_expected_tests(ROOT, test_files)

    global RECORDER, DISPLAY
    if artifacts_enabled and artifact_dir is not None:
        RECORDER = MachineEventRecorder(
            suite_name="unit",
            command=[],
            cwd=ROOT,
            test_files=test_files,
            artifact_dir=artifact_dir,
        )

    DISPLAY = LiveTestDisplay(
        "🧪 Running Flutter tests...",
        concurrency=CONCURRENCY,
        total_tests=total_tests,
    )
    DISPLAY.start()

    exit_code = run_tests(test_files)

    DISPLAY.stop()
    print_summary()

    if RECORDER is not None:
        RECORDER.finalize(exit_code)
        written = RECORDER.write_artifacts()
        if written is not None:
            print(f"\n📁 Test artifacts: {written}")
        if campaign_dir is None and artifacts_enabled:
            campaign_path = written.parent if written else None
            if campaign_path is not None:
                refresh_latest(ROOT, campaign_path)

    sys.exit(exit_code)


if __name__ == "__main__":
    main()
