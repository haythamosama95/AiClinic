"""summary.json is the live stats source of truth for governor UI."""

import json
from pathlib import Path

from harness.batch_queue_display import batch_queue_from_picked
from harness.campaign_live_stats import apply_campaign_stats, refresh_live_campaign_stats
from harness.live_progress import CampaignProgressDisplay
from harness.test_result_stats import CampaignTestStats


def test_apply_campaign_stats_without_queue_returns_finished_count() -> None:
    stats = CampaignTestStats(passed=3, failed=2, failure_names=("f1", "f2"))

    assert apply_campaign_stats(stats, "ai-platform", "npm-test") == 5
    assert apply_campaign_stats(stats, "ai-platform", "npm-test", total=4) == 4


def test_refresh_live_campaign_stats_without_queue(tmp_path: Path) -> None:
    log_dir = tmp_path / "ai-platform" / "npm-test"
    log_dir.mkdir(parents=True)
    (log_dir / "summary.json").write_text(
        json.dumps(
            {
                "passed": 2,
                "failed": 1,
                "tests": [
                    {"name": "a", "status": "PASS"},
                    {"name": "b", "status": "PASS"},
                    {"name": "c", "status": "FAIL"},
                ],
            }
        ),
        encoding="utf-8",
    )

    stats = refresh_live_campaign_stats(log_dir, "ai-platform", "npm-test")

    assert stats.passed == 2
    assert stats.failed == 1


def test_refresh_live_campaign_stats_updates_queue_and_display(tmp_path: Path) -> None:
    log_dir = tmp_path / "ai-platform" / "npm-test"
    log_dir.mkdir(parents=True)
    summary = {
        "passed": 3,
        "failed": 1,
        "tests": [
            {"name": "a", "status": "PASS"},
            {"name": "b", "status": "PASS"},
            {"name": "c", "status": "PASS"},
            {"name": "d", "status": "FAIL"},
        ],
    }
    (log_dir / "summary.json").write_text(json.dumps(summary), encoding="utf-8")

    run_root = tmp_path
    queue = batch_queue_from_picked(
        [("ai-platform", "npm-test")],
        {"ai-platform": ["npm-test"]},
        test_totals={("ai-platform", "npm-test"): 10},
        resume_display=True,
    )
    display = CampaignProgressDisplay(
        "[ai-platform/npm-test]",
        run_log_root=run_root,
    )
    display.prepare_run("[ai-platform/npm-test]", log_dir, batch_queue=queue)

    refresh_live_campaign_stats(
        log_dir,
        "ai-platform",
        "npm-test",
        batch_queue=queue,
        display=display,
    )

    assert display.passed == 3
    assert display.failed == 1
    assert queue.passed_by_key[("ai-platform", "npm-test")] == 3
    assert queue.failed_by_key[("ai-platform", "npm-test")] == 1


def test_sync_queue_counts_does_not_regress_to_stale_summary(tmp_path: Path) -> None:
    log_dir = tmp_path / "ai-platform" / "npm-test"
    log_dir.mkdir(parents=True)
    (log_dir / "summary.json").write_text(
        json.dumps({"passed": 1, "failed": 0, "tests": [{"name": "a", "status": "PASS"}]}),
        encoding="utf-8",
    )
    queue = batch_queue_from_picked(
        [("ai-platform", "npm-test")],
        {"ai-platform": ["npm-test"]},
        test_totals={("ai-platform", "npm-test"): 10},
    )
    display = CampaignProgressDisplay("[ai-platform/npm-test]")
    display.prepare_run("[ai-platform/npm-test]", log_dir, batch_queue=queue)
    display.passed = 5
    display.failed = 0
    display._poll_summary_on_tick = False
    display._sync_queue_counts()
    assert display.passed == 5
    assert queue.passed_by_key[("ai-platform", "npm-test")] == 5


def test_prepare_then_seed_does_not_copy_counts_onto_previous_campaign(tmp_path: Path) -> None:
    """Backend resume numbers must not replace the ai-platform row."""
    queue = batch_queue_from_picked(
        [("ai-platform", "npm-test"), ("backend", "all")],
        {"ai-platform": ["npm-test"], "backend": ["all"]},
        test_totals={
            ("ai-platform", "npm-test"): 1461,
            ("backend", "all"): 77,
        },
        resume_display=True,
    )
    from harness.batch_queue_display import set_campaign_pass_fail_counts

    set_campaign_pass_fail_counts(queue, "ai-platform", "npm-test", 1229, 117)
    set_campaign_pass_fail_counts(queue, "backend", "all", 68, 5)
    display = CampaignProgressDisplay(
        "[ai-platform/npm-test]",
        batch_queue=queue,
    )
    display.passed = 1229
    display.failed = 117
    display.prepare_run(
        "[backend/all]",
        tmp_path / "backend" / "all",
        batch_queue=queue,
    )
    display.seed_prior_results(68, 5, failure_names=["step"])
    assert queue.passed_by_key[("ai-platform", "npm-test")] == 1229
    assert queue.failed_by_key[("ai-platform", "npm-test")] == 117
    assert queue.test_total_by_key[("ai-platform", "npm-test")] == 1461
    assert queue.passed_by_key[("backend", "all")] == 68
    assert queue.failed_by_key[("backend", "all")] == 5
    assert queue.test_total_by_key[("backend", "all")] == 77


def test_disk_refresh_does_not_regress_live_counts(tmp_path: Path) -> None:
    log_dir = tmp_path / "ai-platform" / "npm-test"
    log_dir.mkdir(parents=True)
    (log_dir / "summary.json").write_text(
        json.dumps(
            {
                "passed": 1229,
                "failed": 117,
                "tests": [
                    {"name": f"p{i}", "status": "PASS"} for i in range(1229)
                ]
                + [{"name": f"f{i}", "status": "FAIL"} for i in range(117)],
            }
        ),
        encoding="utf-8",
    )
    queue = batch_queue_from_picked(
        [("ai-platform", "npm-test")],
        {"ai-platform": ["npm-test"]},
        test_totals={("ai-platform", "npm-test"): 1461},
        resume_display=True,
    )
    display = CampaignProgressDisplay(
        "[ai-platform/npm-test]",
        run_log_root=tmp_path,
    )
    display.prepare_run("[ai-platform/npm-test]", log_dir, batch_queue=queue)
    display.passed = 1230
    display.failed = 117
    display._sync_queue_counts()
    refresh_live_campaign_stats(
        log_dir,
        "ai-platform",
        "npm-test",
        batch_queue=queue,
        display=display,
    )
    assert display.passed == 1230
    assert display.failed == 117
    assert queue.passed_by_key[("ai-platform", "npm-test")] == 1230
