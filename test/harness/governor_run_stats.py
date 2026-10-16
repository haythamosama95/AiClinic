"""Write per-campaign ``stats.json`` under a governor run directory."""

from __future__ import annotations

import json
import sys
from pathlib import Path
from typing import Any

from harness.campaign_counts import test_count
from harness.campaign_resume import summary_stats
from harness.common import governor_campaign_log_dir
from harness.governor_run_manifest import (
    load_run_manifest,
    manifest_path,
    picked_from_manifest,
    read_campaign_exit_code,
    resolve_governor_run_dir,
)
from harness.governor_run_stats_display import print_governor_run_stats_report
from harness.test_result_stats import cap_stats, dedupe_test_entries, reconcile_total

STATS_FILE_NAME = "stats.json"
STATS_VERSION = 1
OUTCOME_MANIFEST_VERSION = 1
OUTCOME_FILE_NAMES = ("passed", "failed", "skipped")

_RUN_ROOT_SKIP_NAMES = frozenset(
    {
        "run.json",
        "console.log",
        "resume-state.json",
        STATS_FILE_NAME,
        *OUTCOME_FILE_NAMES,
    }
)


def _load_summary_tests(log_dir: Path) -> list[Any]:
    summary = log_dir / "summary.json"
    if not summary.is_file():
        return []
    try:
        payload = json.loads(summary.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return []
    if not isinstance(payload, dict):
        return []
    tests = payload.get("tests", [])
    return tests if isinstance(tests, list) else []


def _dedupe_test_entries(tests: list[Any]) -> dict[str, dict[str, Any]]:
    """Latest summary row per stable test identity."""
    return dedupe_test_entries(tests)


def _outcome_bucket(entry: dict[str, Any]) -> str | None:
    status = entry.get("status")
    skipped = entry.get("skipped") is True
    if status == "FAIL":
        return "failed"
    if status == "SKIP" or skipped:
        return "skipped"
    if status == "PASS":
        return "passed"
    return None


def _manifest_test_row(log_dir: Path, entry: dict[str, Any]) -> dict[str, Any]:
    name = entry.get("name")
    rel = entry.get("log_file")
    log_file: str | None = rel if isinstance(rel, str) and rel else None
    log_path: str | None = None
    if log_file:
        log_path = str((log_dir / log_file).resolve())
    row: dict[str, Any] = {"name": name}
    identity = entry.get("identity")
    if isinstance(identity, str) and identity:
        row["identity"] = identity
    if log_file is not None:
        row["log_file"] = log_file
    if log_path is not None:
        row["log_path"] = log_path
    return row


def outcome_manifests_complete(log_dir: Path) -> bool:
    log_dir = log_dir.resolve()
    return all((log_dir / name).is_file() for name in OUTCOME_FILE_NAMES)


def write_campaign_outcome_manifests(log_dir: Path) -> None:
    """Write ``passed``, ``failed``, and ``skipped`` lists under the campaign log dir."""
    log_dir = log_dir.resolve()
    log_dir.mkdir(parents=True, exist_ok=True)
    from harness.campaign_exclusions import excluded_test_cases

    excluded = excluded_test_cases(log_dir.parent.name, log_dir.name)
    deduped = {
        key: entry
        for key, entry in _dedupe_test_entries(_load_summary_tests(log_dir)).items()
        if entry.get("name") not in excluded
    }
    buckets: dict[str, list[dict[str, Any]]] = {
        name: [] for name in OUTCOME_FILE_NAMES
    }
    for _name, entry in sorted(deduped.items(), key=lambda item: item[0]):
        bucket = _outcome_bucket(entry)
        if bucket is None:
            continue
        buckets[bucket].append(_manifest_test_row(log_dir, entry))
    for kind in OUTCOME_FILE_NAMES:
        payload = {
            "version": OUTCOME_MANIFEST_VERSION,
            "kind": kind,
            "tests": buckets[kind],
        }
        (log_dir / kind).write_text(
            json.dumps(payload, indent=2) + "\n",
            encoding="utf-8",
        )


def _skipped_count(log_dir: Path) -> int:
    deduped = _dedupe_test_entries(_load_summary_tests(log_dir))
    return sum(1 for entry in deduped.values() if _outcome_bucket(entry) == "skipped")


def _load_summary_fields(log_dir: Path) -> dict[str, Any]:
    summary = log_dir / "summary.json"
    if not summary.is_file():
        return {}
    try:
        payload = json.loads(summary.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return {}
    if not isinstance(payload, dict):
        return {}
    out: dict[str, Any] = {}
    for key in (
        "started_at",
        "finished_at",
        "elapsed_seconds",
        "passed",
        "failed",
        "exit_code",
        "resumed",
        "not_recorded",
        "campaign_infrastructure_error",
        "runner_diagnostics",
        "diagnostics_file",
        "runner_exit_code",
    ):
        if key in payload:
            out[key] = payload[key]
    return out


def build_campaign_stats(
    run_root: Path,
    area: str,
    subcampaign: str,
) -> dict[str, Any]:
    """Aggregate one campaign's on-disk results into a stats document."""
    run_root = run_root.resolve()
    log_dir = governor_campaign_log_dir(run_root, area, subcampaign)
    summary_fields = _load_summary_fields(log_dir)
    from harness.campaign_exclusions import excluded_test_cases
    from harness.test_result_stats import stats_from_tests_list

    excluded = excluded_test_cases(area, subcampaign)
    tests = [
        entry for entry in _load_summary_tests(log_dir)
        if not isinstance(entry, dict) or entry.get("name") not in excluded
    ]
    stats = stats_from_tests_list(tests) if excluded else summary_stats(log_dir)
    discovered = test_count(area, subcampaign)
    total = reconcile_total(discovered, stats)
    stats = cap_stats(stats, total)
    exit_code = summary_fields.get("exit_code")
    if exit_code is None:
        exit_code = read_campaign_exit_code(run_root, area, subcampaign)

    failures = list(stats.failure_names)
    skipped = _skipped_count(log_dir)
    body: dict[str, Any] = {
        "version": STATS_VERSION,
        "area": area,
        "subcampaign": subcampaign,
        "log_dir": log_dir.relative_to(run_root).as_posix(),
        "summary_file": (log_dir / "summary.json").relative_to(run_root).as_posix(),
        "output_file": (log_dir / "output.log").relative_to(run_root).as_posix(),
        "tests_dir": (log_dir / "tests").relative_to(run_root).as_posix(),
        "has_summary": (log_dir / "summary.json").is_file(),
        "passed": stats.passed,
        "failed": stats.failed,
        "skipped": skipped,
        "not_recorded": len(summary_fields.get("not_recorded", []))
        if isinstance(summary_fields.get("not_recorded"), list)
        else 0,
        "campaign_infrastructure_error": summary_fields.get("campaign_infrastructure_error", False),
        "attempted": stats.attempted,
        "total": total,
        "exit_code": exit_code,
        "failure_count": len(failures),
        "failures": failures,
        **summary_fields,
    }
    body["passed"] = stats.passed
    body["failed"] = stats.failed
    body["attempted"] = stats.attempted
    body["not_recorded"] = (
        len(summary_fields["not_recorded"])
        if isinstance(summary_fields.get("not_recorded"), list)
        else 0
    )
    return body


def campaign_stats_path(run_root: Path, area: str, subcampaign: str) -> Path:
    return governor_campaign_log_dir(run_root, area, subcampaign) / STATS_FILE_NAME


def load_campaign_stats_file(path: Path) -> dict[str, Any] | None:
    if not path.is_file():
        return None
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return None
    if not isinstance(payload, dict):
        return None
    if payload.get("version") != STATS_VERSION:
        return None
    if not isinstance(payload.get("area"), str) or not isinstance(
        payload.get("subcampaign"), str
    ):
        return None
    return payload


def resolve_campaign_stats(
    run_root: Path,
    area: str,
    subcampaign: str,
    *,
    refresh: bool,
) -> dict[str, Any]:
    """Return stats document, building (and writing) only when ``refresh`` or cache miss."""
    run_root = run_root.resolve()
    cached_path = campaign_stats_path(run_root, area, subcampaign)
    log_dir = governor_campaign_log_dir(run_root, area, subcampaign)
    if not refresh:
        cached = load_campaign_stats_file(cached_path)
        if cached is not None:
            if not outcome_manifests_complete(log_dir):
                write_campaign_outcome_manifests(log_dir)
            return cached
    body = build_campaign_stats(run_root, area, subcampaign)
    write_campaign_stats(run_root, area, subcampaign, body=body)
    return body


def write_campaign_stats(
    run_root: Path,
    area: str,
    subcampaign: str,
    *,
    body: dict[str, Any] | None = None,
) -> Path:
    run_root = run_root.resolve()
    log_dir = governor_campaign_log_dir(run_root, area, subcampaign)
    log_dir.mkdir(parents=True, exist_ok=True)
    if body is None:
        body = build_campaign_stats(run_root, area, subcampaign)
    path = log_dir / STATS_FILE_NAME
    path.write_text(json.dumps(body, indent=2) + "\n", encoding="utf-8")
    write_campaign_outcome_manifests(log_dir)
    return path


def campaigns_for_run_stats(run_root: Path) -> list[tuple[str, str]]:
    """Campaign list from ``run.json`` when present, else ``<area>/<sub>/summary.json``."""
    run_root = run_root.resolve()
    from harness.campaign_exclusions import subcampaign_is_excluded

    if manifest_path(run_root).is_file():
        picked = picked_from_manifest(load_run_manifest(run_root))
        return [(area, sub) for area, sub in picked if not subcampaign_is_excluded(area, sub)]
    picked: list[tuple[str, str]] = []
    for area_dir in sorted(run_root.iterdir()):
        if not area_dir.is_dir() or area_dir.name in _RUN_ROOT_SKIP_NAMES:
            continue
        for sub_dir in sorted(area_dir.iterdir()):
            if not sub_dir.is_dir():
                continue
            if (sub_dir / "summary.json").is_file():
                picked.append((area_dir.name, sub_dir.name))
    return [(area, sub) for area, sub in picked if not subcampaign_is_excluded(area, sub)]


def generate_governor_run_stats(
    run_root: Path | str,
    *,
    display: bool = True,
    refresh: bool = True,
) -> int:
    """Load or write per-campaign ``stats.json`` and optionally print the report."""
    root = resolve_governor_run_dir(run_root)
    picked = campaigns_for_run_stats(root)
    if not picked:
        print(f"error: no campaigns to summarize under {root}", file=sys.stderr)
        return 2
    rows: list[dict[str, Any]] = []
    for area, sub_id in picked:
        rows.append(
            resolve_campaign_stats(root, area, sub_id, refresh=refresh)
        )
    if display:
        print_governor_run_stats_report(root, rows)
    return 0
