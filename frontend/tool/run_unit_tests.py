#!/usr/bin/env python3

import argparse
import json
import os
import subprocess
import sys
from collections import defaultdict
from pathlib import Path

from discover_tests import count_expected_tests, unit_test_files, unit_test_shards
from test_run_artifacts import (
    MachineEventRecorder,
    refresh_latest,
    resolve_suite_artifact_dir,
)
from campaign_governor_echo import echo_stdout_line, governor_live_progress
from test_run_progress import LiveTestDisplay

ROOT = Path(__file__).resolve().parent.parent
REPO_TEST = ROOT.parent / "test"
if str(REPO_TEST) not in sys.path:
    sys.path.insert(0, str(REPO_TEST))
os.chdir(ROOT)

from harness.campaign_config import apply_flutter_args  # noqa: E402

CONCURRENCY = 15
DEFAULT_CONFIG = {"kind": "flutter", "parallel_tests": CONCURRENCY, "coverage": True}

FAILURES = []
CURRENT_TEST = None

DISPLAY: LiveTestDisplay | None = None
RECORDER: MachineEventRecorder | None = None


# ---------------- Runner ----------------

def run_tests(test_files: list[str], config: dict) -> int:
    if not test_files:
        print("ERROR: no unit/widget/integration test files found.", file=sys.stderr)
        return 1

    cmd = apply_flutter_args(
        [
            "flutter",
            "test",
            *test_files,
            "--machine",
            "--exclude-tags",
            "fullstack",
        ],
        config,
    )

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
        echo_stdout_line(line)
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
    parser.add_argument(
        "--campaign-config",
        type=Path,
        help="JSON campaign runner config (parallelism, coverage).",
    )
    parser.add_argument("--shard", type=int, choices=(1, 2, 3, 4))
    return parser.parse_args()


def _read_config(path: Path | None) -> dict:
    if path is not None and path.is_file():
        return json.loads(path.read_text(encoding="utf-8"))
    return dict(DEFAULT_CONFIG)


# ---------------- Main ----------------

def main():
    args = parse_args()
    config = _read_config(args.campaign_config)
    parallel = int(config.get("parallel_tests", CONCURRENCY))
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

    test_files = (
        unit_test_shards(ROOT, shard_count=4)[args.shard - 1]
        if args.shard is not None
        else unit_test_files(ROOT)
    )
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

    if not governor_live_progress():
        DISPLAY = LiveTestDisplay(
            "🧪 Running Flutter tests...",
            concurrency=parallel,
            total_tests=total_tests,
        )
        DISPLAY.start()
    else:
        DISPLAY = None

    exit_code = run_tests(test_files, config)

    if DISPLAY is not None:
        DISPLAY.stop()
    if not governor_live_progress():
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
