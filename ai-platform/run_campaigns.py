#!/usr/bin/env python3
"""AI Platform test campaign orchestrator."""

from __future__ import annotations

import sys
from pathlib import Path

PKG_ROOT = Path(__file__).resolve().parent
REPO_ROOT = PKG_ROOT.parent
sys.path.insert(0, str(REPO_ROOT / "test"))

from harness.campaign_config import apply_campaign_args, load_campaign_config  # noqa: E402
from harness.common import (  # noqa: E402
    new_run_id,
    resolve_campaign_log_dir,
    run_campaign_script,
    run_subprocess_sequence,
    run_subprocess_with_live_status,
)

AREA = "ai-platform"


def _log_dir(subcampaign: str) -> Path:
    return resolve_campaign_log_dir(AREA, subcampaign, new_run_id())


def _status_label(subcampaign: str) -> str:
    return f"[{AREA}/{subcampaign}]"


def _prepare(subcampaign: str, cmd: list[str]) -> tuple[list[str], dict | None]:
    config = load_campaign_config(AREA, subcampaign)
    return apply_campaign_args(cmd, config), config


def _run(subcampaign: str, cmd: list[str]) -> int:
    prepared, config = _prepare(subcampaign, cmd)
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
    prepared = [(name, apply_campaign_args(list(cmd), config)) for name, cmd in steps]
    return run_subprocess_sequence(
        prepared,
        PKG_ROOT,
        _log_dir(subcampaign),
        status_label=_status_label(subcampaign),
        campaign_config=config,
        config_area=AREA,
    )


def _eval_files() -> list[str]:
    return sorted(str(p.relative_to(PKG_ROOT)) for p in (PKG_ROOT / "test/eval").glob("*.test.ts"))


def run_manifests(_: str) -> int:
    return _run(
        "manifests",
        [
            "npx",
            "vitest",
            "run",
            "test/manifest-registry-gate.test.ts",
            "test/prompt-registry-gate.test.ts",
        ],
    )


def run_unit(_: str) -> int:
    return _run("unit", ["npx", "vitest", "run"])


def run_workers(_: str) -> int:
    return _run(
        "workers",
        ["npx", "vitest", "run", "--config", "vitest.workers.config.ts"],
    )


def run_npm_test(_: str) -> int:
    return _run_steps(
        "npm-test",
        [
            (
                "verify-manifests",
                [
                    "npx",
                    "vitest",
                    "run",
                    "test/manifest-registry-gate.test.ts",
                    "test/prompt-registry-gate.test.ts",
                ],
            ),
            ("unit", ["npx", "vitest", "run"]),
            ("workers", ["npx", "vitest", "run", "--config", "vitest.workers.config.ts"]),
        ],
    )


def run_load(_: str) -> int:
    return _run(
        "load",
        [
            "npx",
            "vitest",
            "run",
            "--config",
            "vitest.workers.config.ts",
            "test/load/load-and-cost.test.ts",
        ],
    )


def run_e2e(_: str) -> int:
    return _run("e2e", ["npx", "vitest", "run", "--config", "vitest.e2e.config.ts"])


def run_eval(_: str) -> int:
    return _run(
        "eval",
        [
            "npx",
            "vitest",
            "run",
            "test/eval/golden.test.ts",
            "test/eval/conversation.test.ts",
            "test/eval/prohibitions.test.ts",
        ],
    )


def run_eval_all(_: str) -> int:
    files = _eval_files()
    if not files:
        print("error: no test/eval/*.test.ts files found", file=sys.stderr)
        return 1
    return _run("eval-all", ["npx", "vitest", "run", *files])


def run_version_matrix_channels(_: str) -> int:
    return _run(
        "version-matrix-channels",
        ["npx", "vitest", "run", "--config", "vitest.version-matrix.config.ts"],
    )


def run_version_matrix_do(_: str) -> int:
    return _run(
        "version-matrix-do",
        ["npx", "vitest", "run", "--config", "vitest.version-matrix-do.config.ts"],
    )


def run_version_matrix(_: str) -> int:
    return _run_steps(
        "version-matrix",
        [
            (
                "version-matrix-channels",
                ["npx", "vitest", "run", "--config", "vitest.version-matrix.config.ts"],
            ),
            (
                "version-matrix-do",
                ["npx", "vitest", "run", "--config", "vitest.version-matrix-do.config.ts"],
            ),
        ],
    )


SUBCAMPAIGNS = {
    "manifests": run_manifests,
    "unit": run_unit,
    "workers": run_workers,
    "npm-test": run_npm_test,
    "load": run_load,
    "e2e": run_e2e,
    "eval": run_eval,
    "eval-all": run_eval_all,
    "version-matrix": run_version_matrix,
    "version-matrix-channels": run_version_matrix_channels,
    "version-matrix-do": run_version_matrix_do,
}


def main() -> int:
    return run_campaign_script(AREA, SUBCAMPAIGNS)


if __name__ == "__main__":
    raise SystemExit(main())
