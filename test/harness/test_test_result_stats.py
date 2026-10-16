"""Deduped test result stats."""

from harness.test_result_stats import (
    dedupe_test_statuses,
    stats_from_summary_payload,
    stats_from_tests_list,
)


def test_dedupe_latest_status_wins() -> None:
    tests = [
        {"name": "a", "status": "FAIL"},
        {"name": "a", "status": "PASS"},
        {"name": "b", "status": "FAIL"},
    ]
    assert dedupe_test_statuses(tests) == {"a": "PASS", "b": "FAIL"}
    stats = stats_from_tests_list(tests)
    assert stats.passed == 1
    assert stats.failed == 1
    assert stats.attempted == 2


def test_summary_prefers_matching_top_level_totals() -> None:
    payload = {
        "tests": [
            {"name": "a", "status": "PASS"},
            {"name": "b", "status": "FAIL"},
        ],
        "passed": 1,
        "failed": 1,
    }
    stats = stats_from_summary_payload(payload)
    assert (stats.passed, stats.failed) == (1, 1)


def test_summary_uses_deduped_list_when_totals_drift() -> None:
    payload = {
        "tests": [
            {"name": "a", "status": "PASS"},
            {"name": "b", "status": "FAIL"},
        ],
        "passed": 40,
        "failed": 3,
    }
    stats = stats_from_summary_payload(payload)
    assert (stats.passed, stats.failed) == (1, 1)
