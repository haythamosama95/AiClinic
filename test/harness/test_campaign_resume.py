"""Tests for partial campaign resume exclude lists."""

from __future__ import annotations

import json
from pathlib import Path

from harness.campaign_resume import (
    passed_test_names_from_summary,
    prior_passed_counts,
    prior_results_from_summary,
    sync_resume_state,
    write_campaign_exclude_file,
)
from harness.common import governor_campaign_log_dir


def test_recorded_names_include_failures(tmp_path: Path) -> None:
    from harness.campaign_resume import (
        exclude_tests_for_campaign,
        recorded_test_names_from_summary,
    )

    log_dir = tmp_path / "campaign"
    log_dir.mkdir()
    (log_dir / "summary.json").write_text(
        json.dumps(
            {
                "tests": [
                    {"name": "case a", "status": "PASS"},
                    {"name": "case b", "status": "FAIL"},
                ]
            }
        ),
        encoding="utf-8",
    )
    assert recorded_test_names_from_summary(log_dir) == {"case a", "case b"}
    assert exclude_tests_for_campaign(None, "harness-fixture", "no-vitest", log_dir) == {
        "case a",
        "case b",
    }


def test_passed_test_names_from_summary(tmp_path: Path) -> None:
    log_dir = tmp_path / "campaign"
    log_dir.mkdir()
    (log_dir / "summary.json").write_text(
        json.dumps(
            {
                "tests": [
                    {"name": "case a", "status": "PASS"},
                    {"name": "case b", "status": "FAIL"},
                ]
            }
        ),
        encoding="utf-8",
    )
    assert passed_test_names_from_summary(log_dir) == {"case a"}


def test_sync_resume_state_writes_exclude_map(tmp_path: Path) -> None:
    run_root = tmp_path / "gov"
    area, sub = "harness-fixture", "no-vitest"
    log_dir = governor_campaign_log_dir(run_root, area, sub)
    log_dir.mkdir(parents=True)
    (log_dir / "summary.json").write_text(
        json.dumps(
            {
                "tests": [
                    {"name": "t1", "status": "PASS"},
                    {"name": "t2", "status": "FAIL"},
                ]
            }
        ),
        encoding="utf-8",
    )
    path = sync_resume_state(run_root, [(area, sub)])
    data = json.loads(path.read_text(encoding="utf-8"))
    assert data["exclude"][f"{area}/{sub}"] == ["t1", "t2"]


def test_prior_passed_counts_uses_summary_totals(tmp_path: Path) -> None:
    log_dir = tmp_path / "campaign"
    log_dir.mkdir()
    (log_dir / "summary.json").write_text(
        json.dumps(
            {
                "tests": [
                    {"name": "case a", "status": "PASS"},
                    {"name": "case b", "status": "FAIL"},
                ],
                "passed": 40,
                "failed": 3,
            }
        ),
        encoding="utf-8",
    )
    assert prior_passed_counts(log_dir) == (1, 1)
    passed, failed, failures = prior_results_from_summary(log_dir)
    assert (passed, failed) == (1, 1)
    assert failures == ["case b"]


def test_write_campaign_exclude_file(tmp_path: Path) -> None:
    path = write_campaign_exclude_file(tmp_path, {"a", "b"})
    data = json.loads(path.read_text(encoding="utf-8"))
    assert data["exclude"] == ["a", "b"]
