"""Tests for governor run.json manifest and resume."""

from __future__ import annotations

import json
from pathlib import Path

from harness.common import governor_campaign_log_dir
from harness.governor_run_manifest import (
    RUN_MANIFEST_NAME,
    campaign_resume_status,
    latest_governor_run_dir,
    load_run_manifest,
    picked_from_manifest,
    resolve_governor_run_dir,
    should_skip_campaign_on_resume,
    write_run_manifest,
)


def test_write_and_load_run_manifest(tmp_path: Path) -> None:
    run_root = tmp_path / "governor-run"
    picked = [("backend", "auth-rbac"), ("abo", "system")]
    plan = write_run_manifest(run_root, picked)
    assert plan.name == RUN_MANIFEST_NAME
    data = load_run_manifest(run_root)
    assert picked_from_manifest(data) == picked
    assert data["campaigns"][0]["area"] == "backend"
    assert "log_dir" in data["campaigns"][0]
    assert data["campaigns"][0]["summary_file"] == "backend/auth-rbac/summary.json"
    assert data["campaigns"][0]["output_file"] == "backend/auth-rbac/output.log"
    assert data["artifact_guide"] == "README.md"
    readme = (run_root / "README.md").read_text(encoding="utf-8")
    assert "compact campaign start/result ledger" in readme
    assert "backend/auth-rbac/output.log" in readme


def test_latest_governor_run_dir_picks_newest_manifest(tmp_path: Path) -> None:
    import os
    from unittest.mock import patch

    from harness import governor_run_manifest as mod

    governor_root = tmp_path / "governor"
    older = governor_root / "run-old"
    newer = governor_root / "run-new"
    write_run_manifest(older, [("backend", "all")])
    write_run_manifest(newer, [("abo", "system")])
    now = newer.stat().st_mtime
    os.utime(older, (now - 60, now - 60))

    with patch.object(mod, "test_results_root", lambda: tmp_path):
        assert latest_governor_run_dir() == newer.resolve()
        assert resolve_governor_run_dir("latest") == newer.resolve()


def test_resolve_governor_run_dir_accepts_run_json(tmp_path: Path) -> None:
    run_root = tmp_path / "run-1"
    write_run_manifest(run_root, [("ops-launch", "launch-check")])
    assert resolve_governor_run_dir(run_root / RUN_MANIFEST_NAME) == run_root.resolve()


def test_resume_skips_successful_campaign(tmp_path: Path) -> None:
    run_root = tmp_path / "run-2"
    write_run_manifest(run_root, [("backend", "all")])
    log_dir = governor_campaign_log_dir(run_root, "backend", "all")
    log_dir.mkdir(parents=True)
    summary = {
        "exit_code": 0,
        "passed": 1,
        "failed": 0,
    }
    (log_dir / "summary.json").write_text(json.dumps(summary), encoding="utf-8")
    assert campaign_resume_status(run_root, "backend", "all") == "finished"
    assert should_skip_campaign_on_resume(run_root, "backend", "all")
    assert campaign_resume_status(run_root, "backend", "all") == "finished"


def test_resume_reruns_failed_campaign(tmp_path: Path) -> None:
    run_root = tmp_path / "run-3"
    write_run_manifest(run_root, [("frontend", "unit")])
    log_dir = governor_campaign_log_dir(run_root, "frontend", "unit")
    log_dir.mkdir(parents=True)
    (log_dir / "summary.json").write_text(
        json.dumps({"exit_code": 1}), encoding="utf-8"
    )
    assert campaign_resume_status(run_root, "frontend", "unit") == "failed"
    assert not should_skip_campaign_on_resume(run_root, "frontend", "unit")
