#!/usr/bin/env python3
"""E2E fullstack test campaigns."""

from __future__ import annotations

import sys
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


def _run_node_steps(subcampaign: str, steps: list[tuple[str, list[str]]]) -> int:
    config = load_campaign_config(AREA, subcampaign)
    exit_code = 0
    log_dir = _log_dir(subcampaign)
    for name, files in steps:
        _prepare_fullstack_stack_ports()
        cmd = apply_campaign_args(_node_cmd(files), config)
        code = run_subprocess_sequence(
            [(name, cmd)],
            E2E_ROOT,
            log_dir,
            status_label=_status_label(subcampaign),
            campaign_config=config,
            config_area=AREA,
        )
        exit_code = max(exit_code, code)
    return exit_code


def run_p5_1(_: str) -> int:
    return _run_node_tests("p5-1", ["test/p5-1.test.mjs"])


def run_p5_2(_: str) -> int:
    return _run_node_tests("p5-2", ["test/p5-2.test.mjs"])


def run_p5_2b(_: str) -> int:
    return _run_node_tests("p5-2b", ["test/p5-2b.test.mjs"])


def run_p7_3(_: str) -> int:
    files = _node_test_files("p7-3*.test.mjs")
    return _run_node_tests("p7-3", files)


def run_p7_2(_: str) -> int:
    files = _node_test_files("p7-2*.test.mjs")
    return _run_node_tests("p7-2", files)


def run_all_ci(_: str) -> int:
    return _run_node_steps(
        "all-ci",
        [
            ("p5-1", ["test/p5-1.test.mjs"]),
            ("p5-2", ["test/p5-2.test.mjs"]),
        ],
    )


def run_all_manual(_: str) -> int:
    files = _node_test_files("*.test.mjs")
    return _run_node_tests("all-manual", files)


SUBCAMPAIGNS = {
    "p5-1": run_p5_1,
    "p5-2": run_p5_2,
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
