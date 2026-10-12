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
