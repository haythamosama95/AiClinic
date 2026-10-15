#!/usr/bin/env python3
"""E2E fullstack test campaigns."""

from __future__ import annotations

import os
import subprocess
import sys
import time
import urllib.request
from pathlib import Path

E2E_ROOT = Path(__file__).resolve().parent
REPO_ROOT = E2E_ROOT.parents[1]
sys.path.insert(0, str(REPO_ROOT / "test"))

from harness.campaign_config import apply_campaign_args, load_campaign_config  # noqa: E402
from harness.common import (  # noqa: E402
    new_run_id,
    resolve_campaign_log_dir,
    run_campaign_script,
    run_subprocess_sequence,
    run_subprocess_with_live_status,
)
from harness.local_dev_ports import prepare_fullstack_e2e_stack  # noqa: E402

AREA = "e2e-fullstack"
TEST_DIR = E2E_ROOT / "test"
_SUPABASE_URL = os.environ.get("SUPABASE_URL", "http://127.0.0.1:54321")
_SUPABASE_ANON_KEY = os.environ.get(
    "SUPABASE_ANON_KEY",
    "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0",
)


def _log_dir(subcampaign: str) -> Path:
    return resolve_campaign_log_dir(AREA, subcampaign, new_run_id())


def _status_label(subcampaign: str) -> str:
    return f"[{AREA}/{subcampaign}]"


def _node_test_files(pattern: str) -> list[str]:
    paths = sorted(TEST_DIR.glob(pattern))
    return [str(p.relative_to(E2E_ROOT)) for p in paths]


def _node_cmd(files: list[str]) -> list[str]:
    return ["node", "--import", "tsx", "--test", *files]


def _prepare_fullstack_stack_ports() -> None:
    prepare_fullstack_e2e_stack()


def _run_node_tests(subcampaign: str, files: list[str]) -> int:
    if not files:
        print(f"error: no test files for {subcampaign}", file=sys.stderr)
        return 1
    _prepare_fullstack_stack_ports()
    config = load_campaign_config(AREA, subcampaign)
    cmd = apply_campaign_args(_node_cmd(files), config)
    return run_subprocess_with_live_status(
        cmd,
        E2E_ROOT,
        _log_dir(subcampaign),
        status_label=_status_label(subcampaign),
        campaign_config=config,
        config_area=AREA,
    )


def _supabase_endpoint_ready(path: str) -> bool:
    try:
        request = urllib.request.Request(
            f"{_SUPABASE_URL}{path}", headers={"apikey": _SUPABASE_ANON_KEY}
        )
        with urllib.request.urlopen(request, timeout=3) as response:
            return response.status == 200
    except OSError:
        return False


def _reset_supabase_between_files(subcampaign: str, step_name: str) -> bool:
    if os.environ.get("HFS_RESET_SUPABASE") != "1":
        return True
    reset_started = time.monotonic()
    label = f"{_status_label(subcampaign)} step={step_name}"
    print(f"{label} supabase-reset=started", flush=True)
    result = subprocess.run(
        ["supabase", "db", "reset", "--local"], cwd=REPO_ROOT / "backend"
    )
    if result.returncode != 0:
        elapsed = time.monotonic() - reset_started
        print(
            f"{label} supabase-reset=failed elapsed={elapsed:.1f}s "
            f"exit_code={result.returncode}",
            file=sys.stderr,
            flush=True,
        )
        return False
    reset_elapsed = time.monotonic() - reset_started
    readiness_started = time.monotonic()
    deadline = time.monotonic() + 120
    while time.monotonic() < deadline:
        if _supabase_endpoint_ready("/auth/v1/health") and _supabase_endpoint_ready(
            "/rest/v1/"
        ):
            readiness_elapsed = time.monotonic() - readiness_started
            print(
                f"{label} supabase-reset=ready reset_elapsed={reset_elapsed:.1f}s "
                f"readiness_elapsed={readiness_elapsed:.1f}s",
                flush=True,
            )
            return True
        time.sleep(1)
    readiness_elapsed = time.monotonic() - readiness_started
    print(
        f"{label} supabase-reset=readiness-timeout reset_elapsed={reset_elapsed:.1f}s "
        f"readiness_elapsed={readiness_elapsed:.1f}s",
        file=sys.stderr,
        flush=True,
    )
    return False


def _per_file_steps(files: list[str]) -> list[tuple[str, list[str]]]:
    return [(Path(f).name.removesuffix(".test.mjs"), [f]) for f in files]


def _run_node_steps(subcampaign: str, steps: list[tuple[str, list[str]]]) -> int:
    if not steps:
        print(f"error: no test files for {subcampaign}", file=sys.stderr)
        return 1
    config = load_campaign_config(AREA, subcampaign)
    exit_code = 0
    log_dir = _log_dir(subcampaign)
    for name, files in steps:
        _prepare_fullstack_stack_ports()
        if not _reset_supabase_between_files(subcampaign, name):
            exit_code = max(exit_code, 1)
            continue
        cmd = apply_campaign_args(_node_cmd(files), config)
        step_started = time.monotonic()
        step_label = f"{_status_label(subcampaign)} step={name}"
        print(f"{step_label} node-tests=started", flush=True)
        code = run_subprocess_sequence(
            [(name, cmd)],
            E2E_ROOT,
            log_dir,
            status_label=_status_label(subcampaign),
            campaign_config=config,
            config_area=AREA,
        )
        print(
            f"{step_label} node-tests={'passed' if code == 0 else 'failed'} "
            f"elapsed={time.monotonic() - step_started:.1f}s exit_code={code}",
            flush=True,
        )
        exit_code = max(exit_code, code)
    return exit_code


def run_p5_1(_: str) -> int:
    return _run_node_tests("p5-1", ["test/p5-1.test.mjs"])


def run_p5_2(_: str) -> int:
    return _run_node_tests("p5-2", ["test/p5-2.test.mjs"])


def run_p5_core(_: str) -> int:
    return _run_node_steps(
        "p5-core",
        [
            ("p5-1", ["test/p5-1.test.mjs"]),
            ("p5-2", ["test/p5-2.test.mjs"]),
        ],
    )


def run_p5_2b(_: str) -> int:
    return _run_node_tests("p5-2b", ["test/p5-2b.test.mjs"])


def run_p7_3(_: str) -> int:
    return _run_node_steps("p7-3", _per_file_steps(_node_test_files("p7-3*.test.mjs")))


def run_p7_2(_: str) -> int:
    return _run_node_steps("p7-2", _per_file_steps(_node_test_files("p7-2*.test.mjs")))


def run_all_ci(_: str) -> int:
    return _run_node_steps(
        "all-ci",
        [
            ("p5-1", ["test/p5-1.test.mjs"]),
            ("p5-2", ["test/p5-2.test.mjs"]),
        ],
    )


def run_all_manual(_: str) -> int:
    files = [
        file
        for file in _node_test_files("*.test.mjs")
        if Path(file).name not in {"p5-1.test.mjs", "p5-2.test.mjs"}
    ]
    return _run_node_steps("all-manual", _per_file_steps(files))


SUBCAMPAIGNS = {
    "p5-1": run_p5_1,
    "p5-2": run_p5_2,
    "p5-core": run_p5_core,
    "p5-2b": run_p5_2b,
    "p7-3": run_p7_3,
    "p7-2": run_p7_2,
    "all-ci": run_all_ci,
    "all-manual": run_all_manual,
}


def main() -> int:
    return run_campaign_script(AREA, SUBCAMPAIGNS)


if __name__ == "__main__":
    raise SystemExit(main())
