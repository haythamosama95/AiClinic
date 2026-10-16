#!/usr/bin/env python3
"""Live Flutter ↔ Supabase boundary integration tests (requires local stack)."""

import argparse
import atexit
import json
import os
import subprocess
import sys
import urllib.error
import urllib.request
from collections import defaultdict
from pathlib import Path

from discover_tests import (
    BOUNDARY_SUBSET_ROOTS,
    boundary_test_files,
    count_expected_tests,
)
from test_run_artifacts import (
    MachineEventRecorder,
    refresh_latest,
    resolve_suite_artifact_dir,
)
from campaign_governor_echo import echo_stdout_line, governor_live_progress
from test_run_progress import LiveTestDisplay

ROOT = Path(__file__).resolve().parent.parent
REPO_ROOT = ROOT.parent
REPO_TEST = REPO_ROOT / "test"
if str(REPO_TEST) not in sys.path:
    sys.path.insert(0, str(REPO_TEST))
os.chdir(ROOT)

from harness.campaign_config import apply_flutter_args  # noqa: E402
COMPOSE_FILE = REPO_ROOT / "backend" / "local" / "docker-compose.yml"
DEPLOYMENT_PROFILE = ROOT / "config/local/deployment-profile.json"
DB_RESET_SQL = ROOT / "tool/boundary/boundary_force_db_reset.sql"
VERIFY_MANIFEST = ROOT / "tool/boundary/verify_boundary_manifest.sh"

CONCURRENCY = 1
DEFAULT_CONFIG = {"kind": "flutter", "parallel_tests": CONCURRENCY, "coverage": True}

FAILURES = []
CURRENT_TEST = None
DISPLAY: LiveTestDisplay | None = None
RECORDER: MachineEventRecorder | None = None


def _supabase_http_ready() -> bool:
    url = os.environ.get("SUPABASE_URL", "http://127.0.0.1:54321").rstrip("/") + "/rest/v1/"
    try:
        urllib.request.urlopen(url, timeout=3)
        return True
    except urllib.error.HTTPError as error:
        return error.code < 500
    except (urllib.error.URLError, OSError):
        return False


def ensure_stack_running():
    if _supabase_http_ready():
        return
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
            "(copy from config/examples/deployment-profile.example.json).",
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


def run_tests(test_files: list[str], config: dict) -> int:
    if not test_files:
        print("ERROR: no boundary test files found.", file=sys.stderr)
        return 1

    env = {
        **os.environ,
        "AICLINIC_BOUNDARY_INTEGRATION": "1",
        "AICLINIC_DEPLOYMENT_PROFILE_PATH": "config/local/deployment-profile.json",
    }
    if os.environ.get("CI"):
        env.setdefault("AICLINIC_BOUNDARY_REQUIRE_LIVE", "1")

    cmd = apply_flutter_args(
        [
            "flutter",
            "test",
            *test_files,
            "--tags",
            "boundary",
            "--timeout",
            "3m",
            "--machine",
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
        cwd=ROOT,
        env=env,
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
        FAILURES.append(
            {
                "test": CURRENT_TEST or "Unknown test",
                "message": event.get("error", "").strip(),
                "stack": event.get("stackTrace", "").strip(),
            }
        )


def print_summary():
    if FAILURES:
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


def verify_manifest_with_logging() -> int:
    cmd = [str(VERIFY_MANIFEST)]
    if not VERIFY_MANIFEST.is_file() or not os.access(VERIFY_MANIFEST, os.X_OK):
        if RECORDER is not None:
            RECORDER.add_extra_step(
                "manifest-verify",
                cmd,
                0,
                stdout="skipped (script missing or not executable)",
            )
        return 0

    result = subprocess.run(cmd, cwd=ROOT)
    if RECORDER is not None:
        RECORDER.add_extra_step(
            "manifest-verify",
            cmd,
            result.returncode,
            stdout="(written to console)",
            stderr="",
        )
    return result.returncode


def main():
    parser = argparse.ArgumentParser(
        description="Run Flutter ↔ Supabase boundary integration tests."
    )
    parser.add_argument(
        "subset",
        nargs="?",
        choices=[*BOUNDARY_SUBSET_ROOTS.keys()],
        help="Run a subset: auth, settings, patients, or postgrest",
    )
    parser.add_argument(
        "--artifacts-dir",
        type=Path,
        help="Directory for test log artifacts (summary, failures, raw).",
    )
    parser.add_argument(
        "--campaign-dir",
        type=Path,
        help="Campaign root; suite artifacts written to <campaign-dir>/boundary.",
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
    args = parser.parse_args()

    config = (
        json.loads(args.campaign_config.read_text(encoding="utf-8"))
        if args.campaign_config and args.campaign_config.is_file()
        else dict(DEFAULT_CONFIG)
    )
    parallel = int(config.get("parallel_tests", CONCURRENCY))

    ensure_stack_running()
    ensure_deployment_profile()

    atexit.register(boundary_force_db_reset)
    boundary_force_db_reset()

    test_files = boundary_test_files(ROOT, args.subset)
    total_tests = count_expected_tests(ROOT, test_files)

    artifacts_enabled = not args.no_artifacts
    campaign_dir = args.campaign_dir
    artifact_dir = None
    global RECORDER, DISPLAY
    if artifacts_enabled:
        artifact_dir = resolve_suite_artifact_dir(
            ROOT,
            "boundary",
            args.artifacts_dir,
            campaign_dir,
        )
        RECORDER = MachineEventRecorder(
            suite_name="boundary",
            command=[],
            cwd=ROOT,
            test_files=test_files,
            artifact_dir=artifact_dir,
        )
        RECORDER.add_extra_step(
            "boundary-db-reset",
            ["psql", "-f", str(DB_RESET_SQL)],
            0,
            stdout="executed before test run (stdout discarded)",
        )

    if not governor_live_progress():
        DISPLAY = LiveTestDisplay(
            "🧪 Running boundary tests...",
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

    if exit_code == 0:
        exit_code = verify_manifest_with_logging() if RECORDER else verify_manifest()

    if RECORDER is not None:
        RECORDER.finalize(exit_code)
        written = RECORDER.write_artifacts()
        if written is not None:
            manifest_path = written / "manifest-verify.json"
            for step in RECORDER.extra_steps:
                if step.get("name") == "manifest-verify":
                    manifest_path.write_text(
                        json.dumps(step, indent=2, ensure_ascii=False) + "\n",
                        encoding="utf-8",
                    )
            print(f"\n📁 Test artifacts: {written}")
        if campaign_dir is None and artifacts_enabled:
            campaign_path = written.parent if written else None
            if campaign_path is not None:
                refresh_latest(ROOT, campaign_path)

    sys.exit(exit_code)


if __name__ == "__main__":
    main()
