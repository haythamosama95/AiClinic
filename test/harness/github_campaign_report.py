"""GitHub Actions summaries and annotations for governor campaign runs."""

from __future__ import annotations

import json
import os
import re
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from harness.common import governor_campaign_log_dir
from harness.governor_run_manifest import resolve_governor_run_dir
from harness.governor_run_stats import (
    campaigns_for_run_stats,
    resolve_campaign_stats,
)
from harness.governor_run_stats_display import format_elapsed

_ANNOTATION_ESCAPE = re.compile(r"[\r\n%]")


@dataclass(frozen=True)
class FailedTest:
    area: str
    subcampaign: str
    name: str
    error: str | None
    log_file: str | None


def _load_summary_tests(log_dir: Path) -> list[dict[str, Any]]:
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
    if not isinstance(tests, list):
        return []
    out: list[dict[str, Any]] = []
    for entry in tests:
        if isinstance(entry, dict):
            out.append(entry)
    return out


def _dedupe_latest(tests: list[dict[str, Any]]) -> dict[str, dict[str, Any]]:
    by_name: dict[str, dict[str, Any]] = {}
    for entry in tests:
        name = entry.get("name")
        if isinstance(name, str) and name:
            by_name[name] = entry
    return by_name


def failed_tests_for_subcampaign(
    run_root: Path,
    area: str,
    subcampaign: str,
) -> list[FailedTest]:
    log_dir = governor_campaign_log_dir(run_root, area, subcampaign)
    deduped = _dedupe_latest(_load_summary_tests(log_dir))
    failures: list[FailedTest] = []
    for name, entry in sorted(deduped.items()):
        if entry.get("status") != "FAIL":
            continue
        err = entry.get("error")
        log_file = entry.get("log_file")
        failures.append(
            FailedTest(
                area=area,
                subcampaign=subcampaign,
                name=name,
                error=err if isinstance(err, str) else None,
                log_file=log_file if isinstance(log_file, str) else None,
            )
        )
    return failures


def collect_area_failures(run_root: Path, area: str) -> list[FailedTest]:
    run_root = run_root.resolve()
    picked = (
        [(a, s) for a, s in campaigns_for_run_stats(run_root) if a == area]
        if run_root.is_dir()
        else []
    )
    failures: list[FailedTest] = []
    for sub_area, sub_id in picked:
        resolve_campaign_stats(run_root, sub_area, sub_id, refresh=True)
        failures.extend(failed_tests_for_subcampaign(run_root, sub_area, sub_id))
    return failures


def area_has_incomplete_or_failed_campaigns(run_root: Path, area: str) -> bool:
    picked = [(a, s) for a, s in campaigns_for_run_stats(run_root) if a == area]
    if not picked:
        return True
    for sub_area, sub_id in picked:
        row = resolve_campaign_stats(run_root, sub_area, sub_id, refresh=True)
        if row.get("exit_code") != 0:
            return True
    return False


def _escape_annotation(value: str) -> str:
    return _ANNOTATION_ESCAPE.sub(" ", value)


def format_markdown_report(
    run_root: Path,
    area: str,
    failures: list[FailedTest],
) -> str:
    picked = (
        [(a, s) for a, s in campaigns_for_run_stats(run_root) if a == area]
        if run_root.is_dir()
        else []
    )
    stats_rows = [
        resolve_campaign_stats(run_root, sub_area, sub_id, refresh=True)
        for sub_area, sub_id in picked
    ]
    lines = [
        f"## Campaign `{area}`",
        "",
        f"Governor run: `{run_root.name}`",
        "",
    ]
    if stats_rows:
        lines.extend([
            "| Subcampaign | Result | Passed | Failed | Progress | Duration |",
            "| --- | --- | ---: | ---: | ---: | ---: |",
        ])
        for row in stats_rows:
            code = row.get("exit_code")
            result = "✅ Passed" if code == 0 else ("❌ Failed" if code is not None else "⏳ Incomplete")
            attempted = int(row.get("attempted") or 0)
            total = row.get("total")
            progress = f"{attempted}/{total}" if isinstance(total, int) else f"{attempted}/—"
            duration = format_elapsed(row.get("elapsed_seconds"))
            lines.append(
                f"| `{row.get('subcampaign', '')}` | {result} | {row.get('passed', 0)} | "
                f"{row.get('failed', 0)} | {progress} | {duration} |"
            )
        total_passed = sum(int(row.get("passed") or 0) for row in stats_rows)
        total_failed = sum(int(row.get("failed") or 0) for row in stats_rows)
        total_attempted = sum(int(row.get("attempted") or 0) for row in stats_rows)
        durations = [row.get("elapsed_seconds") for row in stats_rows if isinstance(row.get("elapsed_seconds"), (int, float))]
        lines.extend([
            "",
            f"**Totals:** {total_passed} passed, {total_failed} failed, "
            f"{total_attempted} attempted across {len(stats_rows)} subcampaign(s); "
            f"recorded test time {format_elapsed(sum(durations) if durations else None)}.",
            "",
        ])
    if not failures:
        failed_campaigns = [row for row in stats_rows if row.get("exit_code") not in (None, 0)]
        incomplete = [row for row in stats_rows if row.get("exit_code") is None]
        if failed_campaigns:
            lines.append(f"{len(failed_campaigns)} subcampaign(s) failed without recorded failing test cases.")
        elif incomplete:
            lines.append(f"{len(incomplete)} subcampaign(s) did not record a final exit status.")
        else:
            lines.append("All recorded test cases passed.")
        return "\n".join(lines) + "\n"

    lines.append(f"**{len(failures)} failed test case(s):**")
    lines.append("")
    for item in failures:
        lines.append(f"### `{item.subcampaign}`")
        lines.append("")
        lines.append(f"- **{item.name}**")
        if item.log_file:
            lines.append(f"  - log: `{item.log_file}`")
        if item.error:
            lines.append("")
            lines.append("```")
            lines.append(item.error.strip())
            lines.append("```")
        lines.append("")
    return "\n".join(lines)


def emit_github_annotations(failures: list[FailedTest]) -> None:
    for item in failures:
        title = _escape_annotation(f"{item.area}/{item.subcampaign}")
        message = _escape_annotation(item.name)
        if item.error:
            message = _escape_annotation(f"{item.name}: {item.error[:500]}")
        print(f"::error title={title}::{message}")


def write_github_step_summary(markdown: str) -> None:
    summary_path = os.environ.get("GITHUB_STEP_SUMMARY")
    if not summary_path:
        return
    path = Path(summary_path)
    with path.open("a", encoding="utf-8") as handle:
        handle.write(markdown)
        if not markdown.endswith("\n"):
            handle.write("\n")


def report_area_to_github(
    run_root: Path | str,
    area: str,
    *,
    github_summary: bool = True,
    annotations: bool = True,
) -> list[FailedTest]:
    root = resolve_governor_run_dir(run_root)
    failures = collect_area_failures(root, area)
    markdown = format_markdown_report(root, area, failures)
    print(markdown)
    if annotations and failures:
        emit_github_annotations(failures)
    if github_summary:
        write_github_step_summary(markdown)
    return failures


def report_area_exit_code(run_root: Path | str, area: str) -> int:
    """Return failure when any selected campaign failed or did not finish."""
    root = resolve_governor_run_dir(run_root)
    return 1 if area_has_incomplete_or_failed_campaigns(root, area) else 0
