"""Governor per-campaign stats.json generation."""

from __future__ import annotations

import json
from pathlib import Path

from harness.governor_run_manifest import write_run_manifest
from harness.governor_run_stats import (
    OUTCOME_FILE_NAMES,
    STATS_FILE_NAME,
    build_campaign_stats,
    generate_governor_run_stats,
    resolve_campaign_stats,
    write_campaign_stats,
)


def test_write_campaign_stats_from_summary(tmp_path: Path) -> None:
    run_root = tmp_path / "gov"
    log_dir = run_root / "abo" / "system"
    log_dir.mkdir(parents=True)
    (log_dir / "summary.json").write_text(
        json.dumps(
            {
                "started_at": "2026-01-01T00:00:00+00:00",
                "finished_at": "2026-01-01T00:01:00+00:00",
                "elapsed_seconds": 60.0,
                "exit_code": 0,
                "tests": [
                    {"name": "a", "status": "PASS"},
                    {"name": "b", "status": "FAIL"},
                ],
            }
        ),
        encoding="utf-8",
    )
    write_run_manifest(run_root, [("abo", "system")])
    path = write_campaign_stats(run_root, "abo", "system")
    assert path.name == STATS_FILE_NAME
    body = json.loads(path.read_text(encoding="utf-8"))
    assert body["area"] == "abo"
    assert body["subcampaign"] == "system"
    assert body["passed"] == 1
    assert body["failed"] == 1
    assert body["exit_code"] == 0
    assert body["has_summary"] is True
    for name in OUTCOME_FILE_NAMES:
        manifest = json.loads((log_dir / name).read_text(encoding="utf-8"))
        assert manifest["kind"] == name
    passed = json.loads((log_dir / "passed").read_text(encoding="utf-8"))["tests"]
    failed = json.loads((log_dir / "failed").read_text(encoding="utf-8"))["tests"]
    assert len(passed) == 1
    assert len(failed) == 1
    assert passed[0]["name"] == "a"
    assert failed[0]["name"] == "b"
    assert "log_file" not in failed[0]


def test_generate_governor_run_stats_lists_campaigns(tmp_path: Path) -> None:
    run_root = tmp_path / "gov"
    log_dir = run_root / "backend" / "all"
    log_dir.mkdir(parents=True)
    (log_dir / "summary.json").write_text(
        json.dumps({"tests": [{"name": "t", "status": "PASS"}]}),
        encoding="utf-8",
    )
    write_run_manifest(run_root, [("backend", "all")])
    assert generate_governor_run_stats(run_root, display=False) == 0
    assert (log_dir / STATS_FILE_NAME).is_file()


def test_outcome_manifests_classify_skip(tmp_path: Path) -> None:
    run_root = tmp_path / "gov"
    log_dir = run_root / "backend" / "all"
    log_dir.mkdir(parents=True)
    (log_dir / "summary.json").write_text(
        json.dumps(
            {
                "tests": [
                    {
                        "name": "skipped test",
                        "status": "SKIP",
                        "skipped": True,
                        "log_file": "tests/001-skip.log",
                    },
                    {
                        "name": "resumed pass",
                        "status": "PASS",
                        "skipped": True,
                        "log_file": None,
                    },
                ]
            }
        ),
        encoding="utf-8",
    )
    write_campaign_stats(run_root, "backend", "all")
    skipped = json.loads((log_dir / "skipped").read_text(encoding="utf-8"))["tests"]
    assert len(skipped) == 2
    by_name = {row["name"]: row for row in skipped}
    assert "log_path" not in by_name["resumed pass"]
    assert by_name["skipped test"].get("log_path", "").endswith("tests/001-skip.log")


def test_resolve_campaign_stats_uses_cache_without_refresh(tmp_path: Path) -> None:
    run_root = tmp_path / "gov"
    log_dir = run_root / "abo" / "system"
    log_dir.mkdir(parents=True)
    (log_dir / "summary.json").write_text(
        json.dumps({"tests": [{"name": "x", "status": "PASS"}]}),
        encoding="utf-8",
    )
    write_run_manifest(run_root, [("abo", "system")])
    write_campaign_stats(run_root, "abo", "system")
    cached = json.loads((log_dir / STATS_FILE_NAME).read_text(encoding="utf-8"))
    cached["passed"] = 999
    (log_dir / STATS_FILE_NAME).write_text(json.dumps(cached), encoding="utf-8")

    body = resolve_campaign_stats(run_root, "abo", "system", refresh=False)
    assert body["passed"] == 999


def test_build_campaign_stats_without_summary(tmp_path: Path) -> None:
    run_root = tmp_path / "gov"
    body = build_campaign_stats(run_root, "ops-launch", "launch-check")
    assert body["has_summary"] is False
    assert body["passed"] == 0
    assert body["failed"] == 0
