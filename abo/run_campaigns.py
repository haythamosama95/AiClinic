#!/usr/bin/env python3
"""ABO test campaign orchestrator."""

from __future__ import annotations

import sys
from pathlib import Path

PKG_ROOT = Path(__file__).resolve().parent
REPO_ROOT = PKG_ROOT.parent
sys.path.insert(0, str(REPO_ROOT / "test"))

from harness.campaign_config import apply_campaign_args, load_campaign_config  # noqa: E402
from harness.common import (  # noqa: E402
    resolve_campaign_log_dir,
    new_run_id,
    run_campaign_script,
    run_subprocess_sequence,
    run_subprocess_with_live_status,
)

AREA = "abo"

_BUILD = ("build-platform", ["node", "scripts/build-platform-for-hxw.mjs"])
_CROSS_WORKER = (
    "cross-worker-vitest",
    ["npx", "vitest", "run", "--config", "vitest.cross-worker.config.ts"],
)
_PLATFORM_THROW = (
    "platform-throw-vitest",
    ["npx", "vitest", "run", "--config", "vitest.platform-throw.config.ts"],
)


def _log_dir(subcampaign: str) -> Path:
    return resolve_campaign_log_dir(AREA, subcampaign, new_run_id())


def _status_label(subcampaign: str) -> str:
    return f"[{AREA}/{subcampaign}]"


def _run(subcampaign: str, cmd: list[str]) -> int:
    config = load_campaign_config(AREA, subcampaign)
    prepared = apply_campaign_args(cmd, config)
    return run_subprocess_with_live_status(
        prepared,
        PKG_ROOT,
        _log_dir(subcampaign),
        status_label=_status_label(subcampaign),
        campaign_config=config,
        config_area=AREA,
    )


def _run_steps(subcampaign: str, steps: list[tuple[str, list[str]]]) -> int:
    config = load_campaign_config(AREA, subcampaign)
    prepared: list[tuple[str, list[str]]] = []
    for name, cmd in steps:
        joined = " ".join(cmd)
        if "vitest" in joined or ("node" in cmd and "--test" in cmd):
            prepared.append((name, apply_campaign_args(list(cmd), config)))
        else:
            prepared.append((name, list(cmd)))
    return run_subprocess_sequence(
        prepared,
        PKG_ROOT,
        _log_dir(subcampaign),
        status_label=_status_label(subcampaign),
        campaign_config=config,
        config_area=AREA,
        # A failing earlier step (e.g. cross-worker-main vitest) must not skip
        # later steps (platform-throw vitest) — a skipped step otherwise gets
        # reconciled as a phantom "no result recorded" FAIL for tests that
        # never ran. The worst exit code still fails the subcampaign.
        continue_on_step_failure=True,
    )


def run_system(_: str) -> int:
    return _run(
        "system",
        ["npx", "vitest", "run", "--config", "vitest.workers.config.ts", "test/system"],
    )


def run_cross_worker(_: str) -> int:
    return _run_steps("cross-worker", [_BUILD, _CROSS_WORKER, _PLATFORM_THROW])


def run_cross_worker_main(_: str) -> int:
    return _run_steps("cross-worker-main", [_BUILD, _CROSS_WORKER])


def run_platform_throw(_: str) -> int:
    return _run_steps("platform-throw", [_PLATFORM_THROW])


def run_import_boundary(_: str) -> int:
    return _run_steps(
        "import-boundary",
        [
            ("import-boundary-scan", ["node", "scripts/check-import-boundary.mjs", "src"]),
            (
                "import-boundary-test",
                ["node", "--test", "test/import-boundary/boundary.test.mjs"],
            ),
        ],
    )


def run_version_matrix(_: str) -> int:
    return _run(
        "version-matrix",
        ["npx", "vitest", "run", "--config", "vitest.version-matrix.config.ts"],
    )


SUBCAMPAIGNS = {
    "system": run_system,
    "cross-worker": run_cross_worker,
    "cross-worker-main": run_cross_worker_main,
    "platform-throw": run_platform_throw,
    "import-boundary": run_import_boundary,
    "version-matrix": run_version_matrix,
}


def main() -> int:
    return run_campaign_script(AREA, SUBCAMPAIGNS)


if __name__ == "__main__":
    raise SystemExit(main())
