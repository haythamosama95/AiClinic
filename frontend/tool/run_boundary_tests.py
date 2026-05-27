#!/usr/bin/env python3
"""Live Flutter ↔ Supabase boundary integration tests (requires local stack)."""

import argparse
import atexit
import os
import subprocess
import json
import sys
import threading
import time
import itertools
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parent
REPO_ROOT = ROOT.parent
COMPOSE_FILE = REPO_ROOT / "backend" / "local" / "docker-compose.yml"
DEPLOYMENT_PROFILE = ROOT / "deployment-profile.json"
DB_RESET_SQL = ROOT / "scripts" / "boundary_force_db_reset.sql"
VERIFY_MANIFEST = ROOT / "scripts" / "verify_boundary_manifest.sh"

SUBSET_PATHS = {
    "auth": "test/boundary/auth",
    "settings": "test/boundary/settings",
    "patients": "test/boundary/patients",
    "postgrest": "test/boundary/postgrest_reads_boundary_test.dart",
}

FAILURES = []
CURRENT_TEST = None
RUNNING = True
TESTS_STARTED = 0
TESTS_DONE = 0
TOTAL_ESTIMATED = 0


def spinner_task():
    global TESTS_STARTED, TESTS_DONE, TOTAL_ESTIMATED

    spinner = itertools.cycle(["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"])

    while RUNNING:
        if TOTAL_ESTIMATED > 0:
            progress = f"{TESTS_DONE}/{TOTAL_ESTIMATED}"
        else:
            progress = f"{TESTS_DONE} tests"

        sys.stdout.write(f"\r🧪 Running boundary tests... {next(spinner)} {progress}")
        sys.stdout.flush()
        time.sleep(0.1)

    sys.stdout.write("\r🧪 Running boundary tests... Done ✔️\n")
    sys.stdout.flush()


def ensure_stack_running():
    result = subprocess.run(
        ["docker", "compose", "-f", str(COMPOSE_FILE), "ps", "--status", "running"],
        capture_output=True,
        text=True,
        cwd=REPO_ROOT,
    )
    if result.returncode != 0 or not result.stdout.strip():
        print("ERROR: backend/local stack is not running.", file=sys.stderr)
        print("  cd backend/local && docker compose up -d", file=sys.stderr)
        sys.exit(1)


def ensure_deployment_profile():
    if not DEPLOYMENT_PROFILE.is_file():
        print(
            f"ERROR: Missing {DEPLOYMENT_PROFILE} "
            "(copy from deployment-profile.example.json).",
            file=sys.stderr,
        )
        sys.exit(1)


def boundary_force_db_reset():
    db_port = os.environ.get("SUPABASE_DB_PORT", "54322")
    db_password = os.environ.get("POSTGRES_PASSWORD", "postgres")
    env = {**os.environ, "PGPASSWORD": db_password}
    subprocess.run(
        [
            "psql",
            "-h",
            "127.0.0.1",
            "-p",
            db_port,
            "-U",
            "postgres",
            "-d",
            "postgres",
            "-v",
            "ON_ERROR_STOP=1",
            "-f",
            str(DB_RESET_SQL),
        ],
        env=env,
        stdout=subprocess.DEVNULL,
        check=True,
    )


def resolve_test_path(subset: str | None) -> str:
    if not subset:
        return "test/boundary"
    if subset not in SUBSET_PATHS:
        print(f"Usage: {sys.argv[0]} [auth|settings|patients|postgrest]", file=sys.stderr)
        sys.exit(2)
    return SUBSET_PATHS[subset]


def run_tests(test_path: str) -> int:
    global RUNNING

    env = {
        **os.environ,
        "AICLINIC_BOUNDARY_INTEGRATION": "1",
        "AICLINIC_DEPLOYMENT_PROFILE_PATH": "deployment-profile.json",
    }

    cmd = [
        "flutter",
        "test",
        test_path,
        "--tags",
        "boundary",
        "--concurrency",
        "1",
        "--timeout",
        "3m",
        "--machine",
    ]

    process = subprocess.Popen(
        cmd,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        bufsize=1,
        cwd=ROOT,
        env=env,
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


def handle_event(event):
    global CURRENT_TEST, TESTS_STARTED, TESTS_DONE, TOTAL_ESTIMATED

    if isinstance(event, list):
        for e in event:
            handle_event(e)
        return

    if not isinstance(event, dict):
        return

    event_type = event.get("type")

    if event_type == "testStart":
        TESTS_STARTED += 1
        if TESTS_STARTED > TOTAL_ESTIMATED:
            TOTAL_ESTIMATED = TESTS_STARTED
        CURRENT_TEST = event.get("test", {}).get("name")

    elif event_type == "testDone":
        TESTS_DONE += 1

    elif event_type == "error":
        FAILURES.append(
            {
                "test": CURRENT_TEST or "Unknown test",
                "message": event.get("error", "").strip(),
                "stack": event.get("stackTrace", "").strip(),
            }
        )


def print_summary():
    print("\n" + "=" * 90)
    print("❌ BOUNDARY TEST FAILURE REPORT")
    print("=" * 90)

    if not FAILURES:
        print("🎉 All boundary tests passed successfully!")
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


def verify_manifest() -> int:
    if not VERIFY_MANIFEST.is_file():
        return 0
    if not os.access(VERIFY_MANIFEST, os.X_OK):
        return 0
    return subprocess.run([str(VERIFY_MANIFEST)], cwd=ROOT).returncode


def main():
    parser = argparse.ArgumentParser(
        description="Run Flutter ↔ Supabase boundary integration tests."
    )
    parser.add_argument(
        "subset",
        nargs="?",
        choices=[*SUBSET_PATHS.keys()],
        help="Run a subset: auth, settings, patients, or postgrest",
    )
    args = parser.parse_args()

    ensure_stack_running()
    ensure_deployment_profile()

    atexit.register(boundary_force_db_reset)
    boundary_force_db_reset()

    test_path = resolve_test_path(args.subset)

    spinner = threading.Thread(target=spinner_task)
    spinner.start()

    exit_code = run_tests(test_path)

    spinner.join()
    print_summary()

    if exit_code == 0:
        exit_code = verify_manifest()

    sys.exit(exit_code)


if __name__ == "__main__":
    main()
