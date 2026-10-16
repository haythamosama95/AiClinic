"""Partial resume: skip test cases that already have a PASS or FAIL result."""

from __future__ import annotations

import json
import os
import re
from pathlib import Path
from typing import Any

from harness.common import REPO_ROOT, governor_campaign_log_dir

RESUME_STATE_NAME = "resume-state.json"
EXCLUDE_FILE_NAME = "exclude-tests.json"
RESUME_STATE_VERSION = 1

CAMPAIGN_RESUME_ENV = "AICLINIC_CAMPAIGN_RESUME"
EXCLUDE_TESTS_FILE_ENV = "AICLINIC_EXCLUDE_TESTS_FILE"


def campaign_key(area: str, subcampaign: str) -> str:
    return f"{area}/{subcampaign}"


def _summary_names_with_status(log_dir: Path, statuses: set[str]) -> set[str]:
    summary = log_dir / "summary.json"
    if not summary.is_file():
        return set()
    try:
        payload = json.loads(summary.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return set()
    names: set[str] = set()
    for entry in payload.get("tests", []):
        if not isinstance(entry, dict):
            continue
        if entry.get("status") not in statuses:
            continue
        name = entry.get("name")
        if isinstance(name, str) and name:
            names.add(name)
    return names


def passed_test_names_from_summary(log_dir: Path) -> set[str]:
    return _summary_names_with_status(log_dir, {"PASS"})


def recorded_test_names_from_summary(
    log_dir: Path,
    *,
    area: str | None = None,
    subcampaign: str | None = None,
) -> set[str]:
    """Tests that already have a result. Continue must not run these again."""
    from harness.campaign_vitest_reconcile import filter_recorded_vitest_names

    raw = _summary_names_with_status(log_dir, {"PASS", "FAIL"})
    return filter_recorded_vitest_names(
        raw,
        area=area,
        subcampaign=subcampaign,
    )


def resume_state_path(run_root: Path) -> Path:
    return run_root.resolve() / RESUME_STATE_NAME


def sync_resume_state(
    run_root: Path,
    picked: list[tuple[str, str]],
) -> Path:
    """Rebuild ``resume-state.json`` from per-campaign ``summary.json`` results."""
    run_root = run_root.resolve()
    exclude_map: dict[str, list[str]] = {}
    for area, sub in picked:
        log_dir = governor_campaign_log_dir(run_root, area, sub)
        recorded = sorted(
            recorded_test_names_from_summary(log_dir, area=area, subcampaign=sub)
        )
        if recorded:
            exclude_map[campaign_key(area, sub)] = recorded
    path = resume_state_path(run_root)
    payload: dict[str, Any] = {
        "version": RESUME_STATE_VERSION,
        "exclude": exclude_map,
    }
    path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    return path


def load_resume_exclude_map(run_root: Path) -> dict[str, list[str]]:
    path = resume_state_path(run_root)
    if not path.is_file():
        return {}
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return {}
    raw = data.get("exclude", {})
    if not isinstance(raw, dict):
        return {}
    out: dict[str, list[str]] = {}
    for key, value in raw.items():
        if isinstance(key, str) and isinstance(value, list):
            out[key] = [str(item) for item in value if item]
    return out


def exclude_tests_for_campaign(
    run_root: Path | None,
    area: str,
    subcampaign: str,
    log_dir: Path,
) -> set[str]:
    from harness.vitest_labels import vitest_exclude_label_set

    names = recorded_test_names_from_summary(
        log_dir,
        area=area,
        subcampaign=subcampaign,
    )
    if run_root is not None:
        key = campaign_key(area, subcampaign)
        from_state = set(load_resume_exclude_map(run_root).get(key, []))
        names |= from_state
    return vitest_exclude_label_set(names)


def write_campaign_exclude_file(log_dir: Path, exclude: set[str]) -> Path:
    log_dir.mkdir(parents=True, exist_ok=True)
    path = log_dir / EXCLUDE_FILE_NAME
    path.write_text(
        json.dumps({"exclude": sorted(exclude)}, indent=2) + "\n",
        encoding="utf-8",
    )
    return path


def read_exclude_tests_file(
    path: Path | None,
    *,
    area: str | None = None,
    subcampaign: str | None = None,
) -> set[str]:
    if path is None or not path.is_file():
        return set()
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return set()
    # Resume files use a flat ``exclude`` list. The shared user file scopes
    # labels by ``area/subcampaign`` under ``test_cases``.
    items = data.get("exclude", [])
    names = {str(item) for item in items if item} if isinstance(items, list) else set()
    if area and subcampaign:
        scoped = data.get("test_cases", {})
        if isinstance(scoped, dict):
            scoped_items = scoped.get(f"{area}/{subcampaign}", [])
            if isinstance(scoped_items, list):
                names.update(str(item) for item in scoped_items if item)
        from harness.campaign_exclusions import excluded_test_cases

        names.update(excluded_test_cases(area, subcampaign))
    return names


def exclude_tests_from_environ(
    *, area: str | None = None, subcampaign: str | None = None
) -> set[str]:
    path = os.environ.get(EXCLUDE_TESTS_FILE_ENV)
    if not path:
        return set()
    names = read_exclude_tests_file(Path(path), area=area, subcampaign=subcampaign)
    if area and subcampaign:
        from harness.campaign_exclusions import excluded_test_cases

        names.update(excluded_test_cases(area, subcampaign))
    return names


def campaign_resume_enabled() -> bool:
    return os.environ.get(CAMPAIGN_RESUME_ENV) == "1"


def _load_summary_payload(log_dir: Path) -> dict[str, Any] | None:
    summary = log_dir / "summary.json"
    if not summary.is_file():
        return None
    try:
        payload = json.loads(summary.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return None
    return payload if isinstance(payload, dict) else None


def prior_results_from_summary(log_dir: Path) -> tuple[int, int, list[str]]:
    """Return ``(passed, failed, failure_names)`` from an existing summary when resuming."""
    stats = summary_stats(log_dir)
    return stats.passed, stats.failed, list(stats.failure_names)


def summary_stats(log_dir: Path):
    """Deduped pass/fail from ``summary.json`` (latest row per test name)."""
    from harness.test_result_stats import stats_from_summary_payload

    return stats_from_summary_payload(_load_summary_payload(log_dir))


def prior_status_map_from_summary(log_dir: Path) -> dict[str, str]:
    from harness.test_result_stats import dedupe_test_statuses

    payload = _load_summary_payload(log_dir)
    if payload is None:
        return {}
    tests = payload.get("tests", [])
    return dedupe_test_statuses(tests if isinstance(tests, list) else [])


def prior_passed_counts(log_dir: Path) -> tuple[int, int]:
    """Return (passed, failed) from an existing summary when resuming."""
    passed, failed, _ = prior_results_from_summary(log_dir)
    return passed, failed


def summary_test_counts(log_dir: Path) -> tuple[int, int, int]:
    """Return ``(passed, failed, completed)`` from ``summary.json``."""
    stats = summary_stats(log_dir)
    return stats.passed, stats.failed, stats.completed


def progress_finished_count(
    passed: int,
    failed: int,
    *,
    resume: bool,
) -> int:
    """How many tests count toward ``[finished/total]`` progress (unique outcomes)."""
    return passed + failed


def work_remaining_count(
    total: int | None,
    passed: int,
    failed: int,
    *,
    resume: bool,
) -> int | None:
    """Tests still to execute (failures are re-run on resume)."""
    if total is None:
        return None
    if resume:
        return max(0, total - passed)
    return max(0, total - passed - failed)


def tests_remaining_for_campaign(
    run_root: Path,
    area: str,
    subcampaign: str,
    *,
    total: int | None = None,
    resume: bool = True,
) -> int | None:
    """How many tests still need to run (failures count on resume)."""
    from harness.campaign_vitest_reconcile import vitest_labels_for_subcampaign

    log_dir = governor_campaign_log_dir(run_root, area, subcampaign)
    passed, failed, _completed = summary_test_counts(log_dir)
    if total is None:
        from harness.campaign_counts import test_count

        total = test_count(area, subcampaign)
    base = work_remaining_count(total, passed, failed, resume=resume)
    labels = vitest_labels_for_subcampaign(area, subcampaign)
    if labels is None or base is None:
        return base
    recorded = recorded_test_names_from_summary(
        log_dir,
        area=area,
        subcampaign=subcampaign,
    )
    known = vitest_labels_for_subcampaign(area, subcampaign) or set()
    missing = len(known - recorded)
    if resume:
        return max(base or 0, missing)
    return max(base or 0, missing)


def sync_queue_campaign_progress(
    queue: object,
    area: str,
    subcampaign: str,
    log_dir: Path,
    *,
    exit_code: int,
) -> None:
    """Align batch queue finished count with on-disk summary after a campaign ends."""
    from harness.batch_queue_display import BatchQueueState, set_campaign_finished_count
    from harness.campaign_live_stats import apply_campaign_stats, load_campaign_stats
    from harness.test_result_stats import cap_stats, reconcile_total

    if not isinstance(queue, BatchQueueState):
        return
    key = (area, subcampaign)
    stats = load_campaign_stats(log_dir)
    total = queue.test_total_by_key.get(key)
    total = reconcile_total(total, stats)
    if key in queue.test_total_by_key:
        queue.test_total_by_key[key] = total
    stats = cap_stats(stats, total)
    finished = apply_campaign_stats(stats, area, subcampaign, batch_queue=queue)
    if exit_code == 0 and total is not None:
        finished = max(finished, total)
    set_campaign_finished_count(queue, area, subcampaign, finished)
