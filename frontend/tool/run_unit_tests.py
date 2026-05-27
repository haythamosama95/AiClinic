#!/usr/bin/env python3

import subprocess
import json
import sys
import threading
import time
import itertools
from collections import defaultdict

FAILURES = []
CURRENT_TEST = None

RUNNING = True

# progress tracking
TESTS_STARTED = 0
TESTS_DONE = 0
TOTAL_ESTIMATED = 0


# ---------------- Spinner + Progress ----------------

def spinner_task():
    global TESTS_STARTED, TESTS_DONE, TOTAL_ESTIMATED

    spinner = itertools.cycle(["⠋","⠙","⠹","⠸","⠼","⠴","⠦","⠧","⠇","⠏"])

    while RUNNING:
        progress = ""

        if TOTAL_ESTIMATED > 0:
            progress = f"{TESTS_DONE}/{TOTAL_ESTIMATED}"
        else:
            progress = f"{TESTS_DONE} tests"

        sys.stdout.write(
            f"\r🧪 Running Flutter tests... {next(spinner)} {progress}"
        )
        sys.stdout.flush()

        time.sleep(0.1)

    sys.stdout.write("\r🧪 Running Flutter tests... Done ✔️\n")
    sys.stdout.flush()


# ---------------- Runner ----------------

def run_tests():
    global RUNNING

    cmd = [
        "flutter",
        "test",
        "--concurrency",
        "15",
        "--machine",
        "--exclude-tags",
        "boundary",
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

    RUNNING = False
    return process.wait()


# ---------------- Event Handling ----------------

def handle_event(event):
    global CURRENT_TEST, TESTS_STARTED, TESTS_DONE, TOTAL_ESTIMATED

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
        TESTS_STARTED += 1

        # crude estimation of total (max seen so far)
        if TESTS_STARTED > TOTAL_ESTIMATED:
            TOTAL_ESTIMATED = TESTS_STARTED

        CURRENT_TEST = event.get("test", {}).get("name")

    elif event_type == "testDone":
        TESTS_DONE += 1

    # ---- failures ----

    elif event_type == "error":
        FAILURES.append({
            "test": CURRENT_TEST or "Unknown test",
            "message": event.get("error", "").strip(),
            "stack": event.get("stackTrace", "").strip()
        })


# ---------------- Summary ----------------

def print_summary():
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
