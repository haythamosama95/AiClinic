#!/usr/bin/env python3
"""vendor-contracts package test campaigns."""

from __future__ import annotations

import sys
from pathlib import Path

PKG_ROOT = Path(__file__).resolve().parent
REPO_ROOT = PKG_ROOT.parents[1]
sys.path.insert(0, str(REPO_ROOT / "test"))

from harness.campaign_config import apply_campaign_args, load_campaign_config  # noqa: E402
from harness.common import (  # noqa: E402
    new_run_id,
    resolve_campaign_log_dir,
    run_campaign_script,
    run_subprocess_with_live_status,
)

AREA = "vendor-contracts"


def _vitest(subcampaign: str, config_name: str) -> int:
    run_id = new_run_id()
    log_dir = resolve_campaign_log_dir(AREA, subcampaign, run_id)
    config = load_campaign_config(AREA, subcampaign)
    cmd = apply_campaign_args(
        ["npx", "vitest", "run", "--config", config_name],
        config,
    )
    return run_subprocess_with_live_status(
        cmd,
        PKG_ROOT,
        log_dir,
        status_label=f"[{AREA}/{subcampaign}]",
        campaign_config=config,
        config_area=AREA,
    )


def run_node(_: str) -> int:
    return _vitest("node", "vitest.config.ts")


def run_workers(_: str) -> int:
    return _vitest("workers", "vitest.workers.config.ts")


def run_all(_: str) -> int:
    code = run_node("node")
    if code != 0:
        return code
    return run_workers("workers")


SUBCAMPAIGNS = {
    "node": run_node,
    "workers": run_workers,
    "all": run_all,
}


def main() -> int:
    return run_campaign_script(AREA, SUBCAMPAIGNS)


if __name__ == "__main__":
    raise SystemExit(main())
