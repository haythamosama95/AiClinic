"""Queue progress label formatting."""

from harness.batch_queue_display import (
    batch_queue_from_picked,
    format_queue_progress,
    format_resume_queue_progress,
    set_campaign_finished_count,
    set_campaign_pass_fail_counts,
    set_campaign_resume_baseline,
)


def test_format_queue_progress_finished_success() -> None:
    assert format_queue_progress(
        1465, 1465, passed=1460, failed=5, run_status="finished"
    ) == "[Pass 1460| Fail 5] [1465/1465]"


def test_format_queue_progress_failed() -> None:
    assert format_queue_progress(
        10, 20, passed=8, failed=2, run_status="failed"
    ) == "[Pass 8| Fail 2] [10/20]"


def test_format_queue_progress_running() -> None:
    assert format_queue_progress(3, 10, passed=2, failed=1) == "[Pass 2| Fail 1] [3/10]"


def test_format_resume_queue_progress() -> None:
    assert format_resume_queue_progress(40, 50, 50, 100, 45, 5) == (
        "[Pass 45| Fail 5] [50/100] [55 Left]"
    )
    assert format_resume_queue_progress(
        40, 50, 100, 100, 95, 5, run_status="finished"
    ) == "[Pass 95| Fail 5] [100/100] [0 Left]"
    assert format_resume_queue_progress(10, None, 15, None, 12, 3) == (
        "[Pass 12| Fail 3] [15/—]"
    )
    assert format_resume_queue_progress(1229, 115, 1346, 1461, 1229, 117) == (
        "[Pass 1229| Fail 117] [1346/1461] [232 Left]"
    )


def test_format_resume_queue_progress_no_continuation() -> None:
    assert format_resume_queue_progress(0, 20, 0, 20, 0, 0) == "[Pass 0| Fail 0] [0/20]"
    assert format_resume_queue_progress(20, 0, 20, 20, 18, 2) == (
        "[Pass 18| Fail 2] [20/20] [2 Left]"
    )


def test_resume_progress_counts_unique_pass_and_fail() -> None:
    from harness.batch_queue_display import campaign_progress_finished, batch_queue_from_picked

    state = batch_queue_from_picked(
        [("ai-platform", "npm-test")],
        {"ai-platform": ["npm-test"]},
        test_totals={("ai-platform", "npm-test"): 100},
        resume_display=True,
    )
    set_campaign_pass_fail_counts(state, "ai-platform", "npm-test", 80, 20)
    assert campaign_progress_finished(state, "ai-platform", "npm-test") == 100


def test_resume_campaign_complete_only_when_nothing_unrecorded() -> None:
    from harness.batch_queue_display import resume_campaign_is_complete

    state = batch_queue_from_picked(
        [("ai-platform", "npm-test"), ("backend", "all")],
        {"ai-platform": ["npm-test"], "backend": ["all"]},
        test_totals={
            ("ai-platform", "npm-test"): 1461,
            ("backend", "all"): 77,
        },
        resume_display=True,
    )
    set_campaign_pass_fail_counts(state, "ai-platform", "npm-test", 1229, 117)
    set_campaign_pass_fail_counts(state, "backend", "all", 68, 5)
    assert resume_campaign_is_complete(state, "ai-platform", "npm-test") is False
    assert resume_campaign_is_complete(state, "backend", "all") is False
    set_campaign_pass_fail_counts(state, "abo", "system", 23, 0)
    done = batch_queue_from_picked(
        [("abo", "system")],
        {"abo": ["system"]},
        test_totals={("abo", "system"): 23},
        resume_display=True,
    )
    set_campaign_pass_fail_counts(done, "abo", "system", 23, 0)
    assert resume_campaign_is_complete(done, "abo", "system") is True


def test_resume_queue_row_shows_pass_fail_and_left() -> None:
    picked = [("backend", "auth-rbac")]
    area_subs = {"backend": ["all", "auth-rbac"]}
    state = batch_queue_from_picked(
        picked, area_subs, test_totals={("backend", "auth-rbac"): 20}, resume_display=True
    )
    set_campaign_resume_baseline(state, "backend", "auth-rbac", 6, 2)
    set_campaign_finished_count(state, "backend", "auth-rbac", 10)
    from harness.batch_queue_display import _queue_body_lines

    set_campaign_pass_fail_counts(state, "backend", "auth-rbac", 10, 2)
    lines = _queue_body_lines(state)
    joined = "\n".join(lines)
    assert "auth-rbac" in joined
    assert "12/20" in joined
    assert "10" in joined
    assert "Left" in joined
