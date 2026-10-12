"""Campaign queue progress labels."""

from harness.batch_queue_display import (
    BatchQueueState,
    batch_queue_from_picked,
    format_queue_progress,
    record_test_finished,
)
from harness.curses_campaign_ui import build_status_forest


def test_format_queue_progress() -> None:
    assert format_queue_progress(2, 10) == "[Pass 0| Fail 0] [2/10]"
    assert format_queue_progress(0, None) == "[Pass 0| Fail 0] [0/—]"


def test_flat_queue_lists_every_picked_campaign() -> None:
    picked = [
        ("abo", "cross-worker"),
        ("abo", "system"),
        ("ai-platform", "e2e"),
        ("ai-platform", "eval"),
        ("backend", "all"),
        ("frontend", "all"),
        ("frontend", "fullstack"),
        ("vendor-contracts", "all"),
    ]
    area_subs = {
        "abo": ["cross-worker", "import-boundary", "system", "version-matrix"],
        "ai-platform": ["e2e", "eval", "npm-test"],
        "backend": ["all", "catalog"],
        "frontend": ["all", "fullstack", "unit"],
        "vendor-contracts": ["all"],
    }
    state = batch_queue_from_picked(picked, area_subs)
    from harness.batch_queue_display import _queue_body_lines

    lines = _queue_body_lines(state)
    data_lines = [line for line in lines if "Campaign" not in line and "─" not in line]
    assert len(data_lines) == len(picked)


def test_queue_row_includes_progress_for_picked_subcampaign() -> None:
    picked = [("backend", "auth-rbac")]
    area_subs = {"backend": ["all", "auth-rbac", "patients"]}
    state = batch_queue_from_picked(
        picked, area_subs, test_totals={("backend", "auth-rbac"): 10}
    )
    record_test_finished(state, "backend", "auth-rbac")
    record_test_finished(state, "backend", "auth-rbac")
    forest = build_status_forest(picked, area_subs)
    assert len(forest) == 1
    from harness.batch_queue_display import _queue_body_lines

    lines = _queue_body_lines(state)
    joined = "\n".join(lines)
    assert "auth-rbac" in joined and "2/10" in joined
    assert not any("backend / all" in line for line in lines)
    assert not any("├─" in line for line in lines)
