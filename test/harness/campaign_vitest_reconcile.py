"""Align ``summary.json`` with ``vitest list`` so resume exclude lists stay accurate."""

from __future__ import annotations

import json
import re
from pathlib import Path
from typing import Any

from harness.test_result_stats import dedupe_test_statuses, stats_from_status_map
from harness.vitest_labels import normalize_vitest_case_label, vitest_exclude_label_set


_RUNNER_DIAGNOSTIC = re.compile(
    r"(?:uncaught|unhandled|worker.{0,24}(?:error|crash|exit)|"
    r"(?:error|exception|failed).{0,32}(?:sqlite|snapshot|storage|runner)|"
    r"sqlite|vitest.{0,24}(?:error|crash)|test runner)",
    re.IGNORECASE,
)


def _runner_diagnostic_excerpt(log_dir: Path, *, limit: int = 12) -> list[str]:
    """Extract concise infrastructure clues from the merged runner transcript."""
    output = log_dir / "output.log"
    if not output.is_file():
        return []
    try:
        lines = output.read_text(encoding="utf-8", errors="replace").splitlines()
    except OSError:
        return []
    selected: list[str] = []
    seen: set[str] = set()
    for line in lines:
        stripped = line.strip()
        if not stripped or not _RUNNER_DIAGNOSTIC.search(stripped):
            continue
        excerpt = stripped[:500]
        if excerpt in seen:
            continue
        seen.add(excerpt)
        selected.append(excerpt)
        if len(selected) >= limit:
            break
    return selected


def _report_outcomes(log_dir: Path) -> dict[str, dict[str, Any]]:
    """Read normalized sibling output or Vitest's standard JSON report."""
    outcomes: dict[str, dict[str, Any]] = {}

    def add(name: Any, status: Any, error: Any = None, stack: Any = None, reference: str = "vitest-report.json") -> None:
        if not isinstance(name, str) or not name.strip():
            return
        label = normalize_vitest_case_label(name.strip())
        if status not in ("FAIL", "failed", "failure", "passed", "PASS", "skipped", "pending"):
            return
        failed = status in ("FAIL", "failed", "failure")
        if not failed:
            return
        details = error if isinstance(error, (str, list)) else None
        if isinstance(stack, str) and stack.strip():
            details = ([details] if isinstance(details, str) else list(details or [])) + [stack]
        outcomes[label] = {"error": details, "failure_kind": "test_failure", "report_reference": reference}

    for path in sorted(log_dir.glob("vitest-report*.json")):
        try:
            payload = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            continue
        if not isinstance(payload, dict):
            continue
        tests = payload.get("tests")
        if isinstance(tests, list):
            for row in tests:
                if isinstance(row, dict):
                    add(row.get("name"), row.get("status"), row.get("error"), row.get("stack"), path.name)
        results = payload.get("testResults")
        if isinstance(results, list):
            for file_result in results:
                if not isinstance(file_result, dict):
                    continue
                assertions = file_result.get("assertionResults", [])
                if not isinstance(assertions, list):
                    continue
                for assertion in assertions:
                    if not isinstance(assertion, dict):
                        continue
                    parts = assertion.get("ancestorTitles", [])
                    title = assertion.get("fullName") or assertion.get("title")
                    name = " > ".join([str(x) for x in parts if x] + ([str(title)] if title else []))
                    if not name:
                        continue
                    filename = str(file_result.get("name", file_result.get("testFilePath", "")))
                    if filename and not name.startswith(filename + " > "):
                        name = f"{filename} > {name}"
                    errors = assertion.get("failureMessages", assertion.get("failureMessage"))
                    add(name, assertion.get("status"), errors, reference=path.name)
    return outcomes


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
    report = _report_outcomes(log_dir)
    summary_exit = payload.get("exit_code")
    summary_signal = payload.get("signal")
    diagnostics = _runner_diagnostic_excerpt(log_dir)
    cause = diagnostics[0] if diagnostics else None
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
        normalized = {**entry, "name": label}
        if status == "FAIL":
            normalized["failure_kind"] = "test_failure"
            outcome = report.get(label)
            if outcome:
                normalized["error"] = outcome.get("error")
                normalized["report_reference"] = outcome.get("report_reference")
        by_name[label] = normalized

    for label in sorted(labels):
        if label not in by_name:
            outcome = report.get(label)
            if outcome:
                by_name[label] = {
                    "name": label,
                    "status": "FAIL",
                    "skipped": False,
                    "log_file": None,
                    "started_at": None,
                    "finished_at": None,
                    "elapsed_seconds": 0.0,
                    "error": outcome.get("error"),
                    "failure_kind": "test_failure",
                    "report_reference": outcome.get("report_reference"),
                    "reconciled": True,
                }
                continue
            by_name[label] = {
                "name": label,
                "status": "FAIL",
                "skipped": False,
                "log_file": None,
                "started_at": None,
                "finished_at": None,
                "elapsed_seconds": 0.0,
                "error": cause or "Vitest did not report an outcome for this case.",
                "failure_kind": "runner_missing_outcome",
                "reference": "output.log",
                "runner_exit_code": summary_exit,
                "runner_signal": summary_signal,
                "runner_context": diagnostics,
                "reconciled": True,
            }
    missing_labels = sorted(
        label
        for label, entry in by_name.items()
        if entry.get("failure_kind") == "runner_missing_outcome"
    )

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
    if missing_labels:
        new_payload["not_recorded"] = missing_labels
        new_payload["diagnostics_file"] = "output.log"
        new_payload["runner_diagnostics"] = diagnostics
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
