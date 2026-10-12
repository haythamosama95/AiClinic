"""Stats terminal report helpers."""

from harness.governor_run_stats_display import (
    _aggregate,
    _format_progress_field,
    _progress_label_width,
    format_elapsed,
    print_governor_run_stats_report,
)


def test_format_elapsed() -> None:
    assert format_elapsed(None) == "—"
    assert format_elapsed(12.4) == "12.4s"
    assert format_elapsed(125) == "2m 5s"


def test_aggregate_totals() -> None:
    rows = [
        {"passed": 1, "failed": 0, "attempted": 1, "total": 2, "exit_code": 0},
        {"passed": 0, "failed": 1, "attempted": 1, "total": 1, "exit_code": 1},
    ]
    totals = _aggregate(rows)
    assert totals["passed"] == 1
    assert totals["failed"] == 1
    assert totals["total"] == 3
    assert totals["failed_campaigns"] == 1


def test_progress_fields_share_width_for_alignment() -> None:
    campaigns = [
        {"attempted": 74, "total": 74},
        {"attempted": 709, "total": 4511},
    ]
    totals = _aggregate(
        [
            {"passed": 0, "failed": 0, "attempted": 74, "total": 74, "exit_code": 0},
            {"passed": 0, "failed": 0, "attempted": 709, "total": 4511, "exit_code": 0},
        ]
    )
    label_w = _progress_label_width(campaigns, totals)
    fields = [
        _format_progress_field(74, 74, label_width=label_w),
        _format_progress_field(709, 4511, label_width=label_w),
        _format_progress_field(totals["attempted"], totals["total"], label_width=label_w),
    ]
    assert len({len(field) for field in fields}) == 1
    assert fields[1].endswith("709/4511".rjust(label_w))


def test_plain_report_writes_to_file(tmp_path) -> None:
    import io

    run_root = tmp_path / "gov-run"
    run_root.mkdir()
    buf = io.StringIO()
    print_governor_run_stats_report(
        run_root,
        [
            {
                "area": "abo",
                "subcampaign": "system",
                "passed": 10,
                "failed": 0,
                "attempted": 10,
                "total": 10,
                "exit_code": 0,
                "has_summary": True,
                "failures": [],
            }
        ],
        file=buf,
    )
    text = buf.getvalue()
    assert "abo" in text
    assert "10/10" in text
    assert "Governor run stats" in text
