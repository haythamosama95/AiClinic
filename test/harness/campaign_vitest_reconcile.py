"""Align ``summary.json`` with ``vitest list`` so resume exclude lists stay accurate."""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from harness.test_result_stats import dedupe_test_statuses, stats_from_status_map
from harness.vitest_labels import normalize_vitest_case_label, vitest_exclude_label_set


def is_harness_artifact_test_name(name: str) -> bool:
    """Names that are not real Vitest case labels (stall/stdout noise)."""
    stripped = name.strip()
    if not stripped:
        return True
    if stripped.startswith(("stdout |", "stderr |")):
        return True
    if "runner stalled" in stripped:
        return True
    if stripped.endswith(": runner stalled (no progress)"):
        return True
    return False


def vitest_labels_for_subcampaign(area: str, subcampaign: str) -> set[str] | None:
    """Full ``vitest list`` label set for a subcampaign, when discoverable."""
    from harness.dynamic_test_counts import list_vitest_labels_for_subcampaign

    return list_vitest_labels_for_subcampaign(area, subcampaign)


def filter_recorded_vitest_names(
    names: set[str],
    *,
    area: str | None = None,
    subcampaign: str | None = None,
) -> set[str]:
    """Drop harness noise; keep only labels Vitest would report."""
    cleaned = {n for n in names if not is_harness_artifact_test_name(n)}
    if not area or not subcampaign:
        return cleaned
    labels = vitest_labels_for_subcampaign(area, subcampaign)
    if not labels:
        return cleaned
    known = vitest_exclude_label_set(labels)
    return {n for n in cleaned if normalize_vitest_case_label(n) in known}


def reconcile_vitest_summary_log(
    log_dir: Path,
    *,
    area: str,
    subcampaign: str,
    cwd: Path,
) -> bool:
    """
    Remove invalid rows, dedupe by test name, and record FAIL for list cases with no outcome.

    Returns True when ``summary.json`` was updated.
    """
    summary_path = log_dir / "summary.json"
    if not summary_path.is_file():
        return False
    labels = vitest_labels_for_subcampaign(area, subcampaign)
    if not labels:
        return False
    try:
        payload = json.loads(summary_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return False
    if not isinstance(payload, dict):
        return False
    tests = payload.get("tests", [])
    if not isinstance(tests, list):
        return False

    known = vitest_exclude_label_set(labels)
    by_name: dict[str, dict[str, Any]] = {}
    for entry in tests:
        if not isinstance(entry, dict):
            continue
        name = entry.get("name")
        if not isinstance(name, str) or not name:
            continue
        label = normalize_vitest_case_label(name)
        if is_harness_artifact_test_name(label):
            continue
        if label not in known:
            continue
        status = entry.get("status")
        if status not in ("PASS", "FAIL"):
            continue
        by_name[label] = {**entry, "name": label}

    for label in sorted(labels):
        if label not in by_name:
            by_name[label] = {
                "name": label,
                "status": "FAIL",
                "skipped": False,
                "log_file": None,
                "started_at": None,
                "finished_at": None,
                "elapsed_seconds": 0.0,
                "error": "no result recorded (harness reconcile)",
                "reconciled": True,
            }

    ordered = [by_name[label] for label in sorted(by_name)]
    statuses = dedupe_test_statuses(ordered)
    stats = stats_from_status_map(statuses)
    new_payload = {
        **payload,
        "tests": ordered,
        "passed": stats.passed,
        "failed": stats.failed,
        "reconciled_vitest": True,
    }
    text = json.dumps(new_payload, indent=2) + "\n"
    summary_path.write_text(text, encoding="utf-8")
    meta = log_dir / "meta.json"
    if meta.is_file():
        meta.write_text(text, encoding="utf-8")
    return True


def should_reconcile_vitest_campaign(
    cmd: list[str],
    *,
    area: str | None,
    subcampaign: str | None,
    campaign_config: dict[str, Any] | None,
) -> bool:
    if not area or not subcampaign:
        return False
    if campaign_config and campaign_config.get("kind") == "vitest":
        return vitest_labels_for_subcampaign(area, subcampaign) is not None
    joined = " ".join(cmd)
    return "vitest" in joined and vitest_labels_for_subcampaign(area, subcampaign) is not None
