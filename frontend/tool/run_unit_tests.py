#!/usr/bin/env python3

import os
import subprocess
from pathlib import Path

from discover_tests import unit_test_files
from test_run_progress import TestRunProgress

ROOT = Path(__file__).resolve().parent.parent
os.chdir(ROOT)
import json
import sys
import threading
import time
import itertools
from collections import defaultdict

FAILURES = []
CURRENT_TEST = None

RUNNING = True

PROGRESS = TestRunProgress()


# ---------------- Spinner + Progress ----------------

def spinner_task():
    spinner = itertools.cycle(["⠋","⠙","⠹","⠸","⠼","⠴","⠦","⠧","⠇","⠏"])

    while RUNNING:
        sys.stdout.write(
            f"\r🧪 Running Flutter tests... {next(spinner)} {PROGRESS.label()}"
        )
        sys.stdout.flush()

        time.sleep(0.1)

    PROGRESS.finalize()
    done = f"\r🧪 Running Flutter tests... Done ✔️ {PROGRESS.label()}"
    sys.stdout.write(done.ljust(80) + "\n")
    sys.stdout.flush()


# ---------------- Runner ----------------

def run_tests():
    global RUNNING

    test_files = unit_test_files(ROOT)
    if not test_files:
        print("ERROR: no unit/widget/integration test files found.", file=sys.stderr)
        return 1

    PROGRESS.reset(0)

    cmd = [
        "flutter",
        "test",
        *test_files,
        "--concurrency",
        "15",
        "--machine",
    ]

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

        try:
            event = json.loads(line)
        except json.JSONDecodeError:
            continue

        handle_event(event)

    PROGRESS.finalize()
    RUNNING = False
    return process.wait()


# ---------------- Event Handling ----------------

def handle_event(event):
    global CURRENT_TEST

    # normalize
    if isinstance(event, list):
        for e in event:
            handle_event(e)
        return

    if not isinstance(event, dict):
        return

    event_type = event.get("type")

    # ---- test lifecycle ----

    if event_type == "testStart":
        CURRENT_TEST = event.get("test", {}).get("name")

    elif event_type == "testDone":
        PROGRESS.handle_event(event)

    # ---- failures ----

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


# ---------------- Main ----------------

def main():
    spinner = threading.Thread(target=spinner_task)
    spinner.start()

    exit_code = run_tests()

    spinner.join()
    print_summary()

    sys.exit(exit_code)


if __name__ == "__main__":
    main()
