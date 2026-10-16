"""Deduped per-test outcomes for campaign summaries and live progress."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any


@dataclass(frozen=True)
class CampaignTestStats:
    """Counts with at most one terminal status per test identity (latest wins)."""

    passed: int
    failed: int
    failure_names: tuple[str, ...]

    @property
    def attempted(self) -> int:
        return self.passed + self.failed

    @property
    def completed(self) -> int:
        return self.attempted


def dedupe_test_statuses(tests: list[Any]) -> dict[str, str]:
    """Map stable test identity → latest PASS/FAIL (rows are chronological).

    New campaign rows include an ``identity`` that can distinguish equal test
    names in different files. Legacy rows fall back to their display name.
    """
    statuses: dict[str, str] = {}
    if not isinstance(tests, list):
        return statuses
    for entry in tests:
        if not isinstance(entry, dict):
            continue
        status = entry.get("status")
        if status not in ("PASS", "FAIL"):
            continue
        identity = entry.get("identity")
        name = entry.get("name")
        key = identity if isinstance(identity, str) and identity else name
        if isinstance(key, str) and key:
            statuses[key] = status
    return statuses


def dedupe_test_entries(tests: list[Any]) -> dict[str, dict[str, Any]]:
    """Map stable test identity to the latest terminal summary row."""
    entries: dict[str, dict[str, Any]] = {}
    if not isinstance(tests, list):
        return entries
    for entry in tests:
        if not isinstance(entry, dict):
            continue
        identity = entry.get("identity")
        name = entry.get("name")
        key = identity if isinstance(identity, str) and identity else name
        if isinstance(key, str) and key:
            entries[key] = entry
    return entries


def stats_from_status_map(statuses: dict[str, str]) -> CampaignTestStats:
    passed = failed = 0
    failures: list[str] = []
    for name, status in statuses.items():
        if status == "PASS":
            passed += 1
        elif status == "FAIL":
            failed += 1
            failures.append(name)
    failures.sort()
    return CampaignTestStats(passed=passed, failed=failed, failure_names=tuple(failures))


def stats_from_tests_list(tests: list[Any]) -> CampaignTestStats:
    entries = dedupe_test_entries(tests)
    passed = failed = 0
    failures: list[str] = []
    for entry in entries.values():
        status = entry.get("status")
        if status == "PASS":
            passed += 1
        elif status == "FAIL":
            failed += 1
            name = entry.get("name")
            failures.append(name if isinstance(name, str) and name else "unknown test")
    return CampaignTestStats(passed, failed, tuple(sorted(failures)))


def stats_from_summary_payload(payload: dict[str, Any] | None) -> CampaignTestStats:
    if not payload:
        return CampaignTestStats(0, 0, ())
    tests = payload.get("tests", [])
    listed = stats_from_tests_list(tests if isinstance(tests, list) else [])
    summary_passed = payload.get("passed")
    summary_failed = payload.get("failed")
    if isinstance(summary_passed, int) and isinstance(summary_failed, int):
        if (
            summary_passed == listed.passed
            and summary_failed == listed.failed
        ) or listed.attempted == 0:
            return CampaignTestStats(
                max(0, summary_passed),
                max(0, summary_failed),
                listed.failure_names,
            )
    return listed


def cap_stats(stats: CampaignTestStats, total: int | None) -> CampaignTestStats:
    if total is None or total < 0:
        return stats
    attempted = min(stats.attempted, total)
    if attempted == stats.attempted:
        return stats
    passed = min(stats.passed, attempted)
    failed = attempted - passed
    failures = stats.failure_names[:failed] if failed < stats.failed else stats.failure_names
    return CampaignTestStats(passed=passed, failed=failed, failure_names=failures)


def reconcile_total(discovered: int | None, stats: CampaignTestStats) -> int | None:
    """Prefer the larger of discovery vs recorded unique tests."""
    if discovered is None:
        return stats.attempted or None
    return max(discovered, stats.attempted)
