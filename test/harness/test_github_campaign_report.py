"""Tests for GitHub campaign failure reporting."""

from __future__ import annotations

import json
from pathlib import Path

from harness.github_campaign_report import (
    collect_area_failures,
    format_markdown_report,
)


def test_collect_area_failures_reads_summary(tmp_path: Path) -> None:
    run_root = tmp_path / "20260101T000000Z-deadbeef"
    log_dir = run_root / "abo" / "system"
    tests_dir = log_dir / "tests"
    tests_dir.mkdir(parents=True)
    (log_dir / "summary.json").write_text(
        json.dumps(
            {
                "tests": [
                    {
                        "name": "case-a",
                        "status": "PASS",
                        "log_file": "tests/001.log",
                    },
                    {
                        "name": "case-b",
                        "status": "FAIL",
                        "error": "boom",
                        "log_file": "tests/002.log",
                    },
                ]
            }
        ),
        encoding="utf-8",
    )
    failures = collect_area_failures(run_root, "abo")
    assert len(failures) == 1
    assert failures[0].name == "case-b"
    assert failures[0].error == "boom"


def test_format_markdown_includes_failure_name() -> None:
    from harness.github_campaign_report import FailedTest

    md = format_markdown_report(
        Path("/tmp/run"),
        "abo",
        [
            FailedTest(
                area="abo",
                subcampaign="system",
                name="case-b",
                error="boom",
                log_file="tests/002.log",
            )
        ],
    )
    assert "case-b" in md
    assert "boom" in md


def test_format_markdown_separates_missing_results_and_shows_diagnostics(
    tmp_path: Path,
) -> None:
    from harness.github_campaign_report import FailedTest

    log_dir = tmp_path / "ai-platform" / "npm-test"
    log_dir.mkdir(parents=True)
    (log_dir / "summary.json").write_text(
        json.dumps(
            {
                "diagnostics_file": "output.log",
                "runner_diagnostics": ["expected .sqlite, got .sqlite-shm"],
            }
        ),
        encoding="utf-8",
    )
    md = format_markdown_report(
        tmp_path,
        "ai-platform",
        [
            FailedTest(
                area="ai-platform",
                subcampaign="npm-test",
                name="missing-case",
                error="no result recorded (harness reconcile)",
                log_file=None,
                failure_kind="not_recorded",
            ),
            FailedTest(
                area="ai-platform",
                subcampaign="npm-test",
                name="assertion-case",
                error="expected 200, got 500",
                log_file="tests/001.log",
            ),
        ],
    )

    assert "1 test case(s) had no recorded result" in md
    assert "1 recorded test failure(s)" in md
    assert "NOT RECORDED: missing-case" in md
    assert "FAIL: assertion-case" in md
    assert "ai-platform/npm-test/output.log" in md
    assert "expected .sqlite, got .sqlite-shm" in md
