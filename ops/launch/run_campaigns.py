#!/usr/bin/env python3
"""Ops launch readiness test campaigns."""

from __future__ import annotations

import sys
from pathlib import Path

LAUNCH_ROOT = Path(__file__).resolve().parent
REPO_ROOT = LAUNCH_ROOT.parents[1]
sys.path.insert(0, str(REPO_ROOT / "test"))

from harness.campaign_config import apply_campaign_args, load_campaign_config  # noqa: E402
from harness.common import (  # noqa: E402
    campaign_log_dir,
    new_run_id,
    run_campaign_script,
    run_subprocess_with_live_status,
)

AREA = "ops-launch"


def run_launch_check(_: str) -> int:
    run_id = new_run_id()
    log_dir = campaign_log_dir(AREA, "launch-check", run_id)
    test_file = LAUNCH_ROOT / "launch-check.test.mjs"
    config = load_campaign_config(AREA, "launch-check")
    cmd = apply_campaign_args(["node", "--test", str(test_file)], config)
    return run_subprocess_with_live_status(
        cmd,
        REPO_ROOT,
        log_dir,
        status_label=f"[{AREA}/launch-check]",
        campaign_config=config,
        config_area=AREA,
    )


SUBCAMPAIGNS = {
    "launch-check": run_launch_check,
}


def main() -> int:
    return run_campaign_script(AREA, SUBCAMPAIGNS)


if __name__ == "__main__":
    raise SystemExit(main())
