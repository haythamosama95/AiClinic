#!/usr/bin/env python3
"""Frontend test campaign orchestrator (unit + boundary suites)."""

from __future__ import annotations

import json
import sys
from pathlib import Path

TOOL_DIR = Path(__file__).resolve().parent
FRONTEND_ROOT = TOOL_DIR.parent
REPO_TEST = FRONTEND_ROOT.parent / "test"
if str(TOOL_DIR) not in sys.path:
    sys.path.insert(0, str(TOOL_DIR))
if str(REPO_TEST) not in sys.path:
    sys.path.insert(0, str(REPO_TEST))

from discover_tests import FULLSTACK_INTEGRATION_DIR, fullstack_test_files  # noqa: E402

from harness.campaign_config import (  # noqa: E402
    apply_campaign_args,
    load_campaign_config,
    resolve_campaign_config_path,
)
from harness.common import (  # noqa: E402
    make_arg_parser,
    resolve_campaign_log_dir,
    resolve_governor_run_id,
    resolve_subcampaign,
    run_subprocess_sequence,
    run_subprocess_with_live_status,
    utc_now_iso,
)

AREA = "frontend"
UNIT_RUNNER = TOOL_DIR / "run_unit_tests.py"
BOUNDARY_RUNNER = TOOL_DIR / "run_boundary_tests.py"

BOUNDARY_SUBSET_BY_SUBCAMPAIGN: dict[str, str] = {
    "boundary-auth": "auth",
    "boundary-settings": "settings",
    "boundary-patients": "patients",
    "boundary-appointments": "appointments",
    "boundary-postgrest": "postgrest",
}


def _status_label(subcampaign: str) -> str:
    return f"[{AREA}/{subcampaign}]"


def _campaign_config_path(subcampaign: str) -> Path | None:
    return resolve_campaign_config_path(AREA, subcampaign)


def _child_cmd(
    runner: Path,
    campaign_dir: Path,
    boundary_subset: str | None,
    config_path: Path | None,
) -> list[str]:
    cmd = [sys.executable, str(runner), "--campaign-dir", str(campaign_dir)]
    if config_path is not None:
        cmd.extend(["--campaign-config", str(config_path)])
    if boundary_subset:
        cmd.append(boundary_subset)
    return cmd


def _augment_meta(
    log_dir: Path,
    *,
    subcampaign: str,
    run_id: str,
    runner: str,
    boundary_subset: str | None,
) -> None:
    meta_path = log_dir / "meta.json"
    if meta_path.is_file():
        meta = json.loads(meta_path.read_text(encoding="utf-8"))
    else:
        meta = {}
    meta.update(
        {
            "area": AREA,
            "subcampaign": subcampaign,
            "run_id": run_id,
            "runner": runner,
            "boundary_subset": boundary_subset,
            "campaign_dir": str(log_dir.resolve()),
        }
    )
    meta_path.write_text(json.dumps(meta, indent=2) + "\n", encoding="utf-8")


def _run_live(
    subcampaign: str,
    cmd: list[str],
    log_dir: Path,
    cwd: Path,
) -> int:
    config = load_campaign_config(AREA, subcampaign)
    return run_subprocess_with_live_status(
        cmd,
        cwd,
        log_dir,
        status_label=_status_label(subcampaign),
        campaign_config=config,
        config_area=AREA,
    )


def _run_child_subcampaign(
    subcampaign: str,
    runner: Path,
    boundary_subset: str | None,
) -> int:
    run_id = resolve_governor_run_id()
    log_dir = resolve_campaign_log_dir(AREA, subcampaign, run_id)
    config_path = _campaign_config_path(subcampaign)
    cmd = _child_cmd(runner, log_dir, boundary_subset, config_path)
    code = _run_live(subcampaign, cmd, log_dir, FRONTEND_ROOT)
    _augment_meta(
        log_dir,
        subcampaign=subcampaign,
        run_id=run_id,
        runner=runner.name,
        boundary_subset=boundary_subset,
    )
    return code


def _run_unit(_subcampaign: str) -> int:
    return _run_child_subcampaign("unit", UNIT_RUNNER, None)


def _run_boundary(_subcampaign: str) -> int:
    return _run_child_subcampaign("boundary", BOUNDARY_RUNNER, None)


def _run_boundary_subset(subcampaign: str) -> int:
    subset = BOUNDARY_SUBSET_BY_SUBCAMPAIGN[subcampaign]
    return _run_child_subcampaign(subcampaign, BOUNDARY_RUNNER, subset)


def _run_fullstack(_subcampaign: str) -> int:
    run_id = resolve_governor_run_id()
    log_dir = resolve_campaign_log_dir(AREA, "fullstack", run_id)
    config = load_campaign_config(AREA, "fullstack")
    test_files = fullstack_test_files(FRONTEND_ROOT)
    if not test_files:
        print(
            "ERROR: no fullstack integration test files found under "
            f"{FULLSTACK_INTEGRATION_DIR}.",
            file=sys.stderr,
        )
        return 1
    cmd = apply_campaign_args(
        ["flutter", "test", *test_files, "--tags", "fullstack"],
        config,
    )
    return _run_live("fullstack", cmd, log_dir, FRONTEND_ROOT)


def _run_all(_subcampaign: str) -> int:
    run_id = resolve_governor_run_id()
    log_dir = resolve_campaign_log_dir(AREA, "all", run_id)
    log_dir.mkdir(parents=True, exist_ok=True)
    started_at = utc_now_iso()

    steps: list[tuple[str, list[str]]] = []
    for step_name, runner, subset in (
        ("unit", UNIT_RUNNER, None),
        ("boundary", BOUNDARY_RUNNER, None),
    ):
        config_path = _campaign_config_path(step_name)
        steps.append(
            (
                step_name,
                _child_cmd(runner, log_dir, subset, config_path),
            )
        )

    overall = run_subprocess_sequence(
        steps,
        FRONTEND_ROOT,
        log_dir,
        status_label=_status_label("all"),
        campaign_config=None,
        config_area=AREA,
        continue_on_step_failure=True,
    )

    meta = {
        "area": AREA,
        "subcampaign": "all",
        "run_id": run_id,
        "started_at": started_at,
        "finished_at": utc_now_iso(),
        "exit_code": overall,
        "campaign_dir": str(log_dir.resolve()),
        "steps": [{"name": name, "command": cmd} for name, cmd in steps],
    }
    (log_dir / "meta.json").write_text(
        json.dumps(meta, indent=2) + "\n", encoding="utf-8"
    )
    return overall


SUBCAMPAIGNS: dict[str, object] = {
    "unit": _run_unit,
    "fullstack": _run_fullstack,
    "boundary": _run_boundary,
    **{name: _run_boundary_subset for name in BOUNDARY_SUBSET_BY_SUBCAMPAIGN},
    "all": _run_all,
}


def main() -> int:
    parser = make_arg_parser(
        AREA,
        SUBCAMPAIGNS,
        description="Run frontend unit and boundary test campaigns.",
    )
    args = parser.parse_args()
    if args.list:
        from harness.campaign_catalog import list_subcampaign_ids

        list_subcampaign_ids(AREA, sorted(SUBCAMPAIGNS.keys()))
        return 0
    chosen = resolve_subcampaign(args, SUBCAMPAIGNS, area=AREA)
    if chosen is None:
        return 0
    runner = SUBCAMPAIGNS[chosen]
    return int(runner(chosen))  # type: ignore[operator,call-arg]


if __name__ == "__main__":
    sys.exit(main())
