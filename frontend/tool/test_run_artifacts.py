#!/usr/bin/env python3
"""Persistent test-run artifacts for Flutter --machine campaign runners."""

from __future__ import annotations

import json
import os
import re
import shutil
from collections import defaultdict
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Any
from urllib.parse import unquote, urlparse

SCHEMA_VERSION = "1.0"
CAMPAIGN_ENV = "AICLINIC_TEST_CAMPAIGN_DIR"
SUITE_ARTIFACT_ENV = "AICLINIC_TEST_SUITE_ARTIFACT_DIR"

_EXPECTED_ACTUAL = re.compile(
    r"Expected:\s*(.+?)\n\s*Actual:\s*(.+?)(?:\n|$)", re.DOTALL
)
_EXCEPTION_PREFIX = re.compile(r"^([A-Za-z][\w]*(?:Error|Exception|Failure)):")


def utc_now_iso() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3] + "Z"


def new_campaign_id() -> str:
    return datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")


def campaigns_root(frontend_root: Path) -> Path:
    return frontend_root / "test-results" / "campaigns"


def latest_root(frontend_root: Path) -> Path:
    return frontend_root / "test-results" / "latest"


def resolve_suite_artifact_dir(
    frontend_root: Path,
    suite_name: str,
    explicit: Path | None,
    campaign_dir: Path | None,
) -> Path | None:
    if explicit is not None:
        return explicit
    env_suite = os.environ.get(SUITE_ARTIFACT_ENV)
    if env_suite:
        return Path(env_suite)
    if campaign_dir is not None:
        return campaign_dir / suite_name
    env_campaign = os.environ.get(CAMPAIGN_ENV)
    if env_campaign:
        return Path(env_campaign) / suite_name
    auto_campaign = campaigns_root(frontend_root) / new_campaign_id()
    auto_campaign.mkdir(parents=True, exist_ok=True)
    return auto_campaign / suite_name


def create_campaign_dir(frontend_root: Path, campaign_id: str | None = None) -> Path:
    cid = campaign_id or new_campaign_id()
    path = campaigns_root(frontend_root) / cid
    path.mkdir(parents=True, exist_ok=True)
    return path


def refresh_latest(frontend_root: Path, campaign_dir: Path) -> None:
    dest = latest_root(frontend_root)
    if dest.exists():
        if dest.is_symlink():
            dest.unlink()
        else:
            shutil.rmtree(dest)
    dest.parent.mkdir(parents=True, exist_ok=True)
    try:
        dest.symlink_to(campaign_dir.resolve(), target_is_directory=True)
    except OSError:
        shutil.copytree(campaign_dir, dest)


def _url_to_relative_path(url: str | None, cwd: Path) -> str | None:
    if not url:
        return None
    parsed = urlparse(url)
    if parsed.scheme == "file":
        path = unquote(parsed.path)
        if path.startswith("/") and len(path) > 2 and path[2] == ":":
            path = path[1:]
        try:
            return str(Path(path).resolve().relative_to(cwd.resolve()))
        except ValueError:
            return path
    if parsed.scheme == "package":
        return url
    return url


def parse_failure_details(message: str, is_failure: bool) -> dict[str, Any]:
    expected = None
    actual = None
    match = _EXPECTED_ACTUAL.search(message)
    if match:
        expected = match.group(1).strip()
        actual = match.group(2).strip()

    exception_type = None
    for line in message.splitlines():
        m = _EXCEPTION_PREFIX.match(line.strip())
        if m:
            exception_type = m.group(1)
            break
    if exception_type is None and is_failure:
        exception_type = "TestFailure"

    return {
        "expected": expected,
        "actual": actual,
        "exception_type": exception_type,
    }


@dataclass
class TestError:
    message: str
    stack_trace: str
    is_failure: bool

    def to_dict(self) -> dict[str, Any]:
        details = parse_failure_details(self.message, self.is_failure)
        return {
            "failure_message": self.message,
            "is_test_failure": self.is_failure,
            "expected": details["expected"],
            "actual": details["actual"],
            "exception_type": details["exception_type"],
            "stack_trace": self.stack_trace,
        }


@dataclass
class TestRecord:
    id: int
    name: str
    suite_id: int | None = None
    file: str | None = None
    line: int | None = None
    column: int | None = None
    url: str | None = None
    hidden: bool = False
    skipped: bool = False
    status: str | None = None
    duration_ms: int | None = None
    started_ms: int | None = None
    errors: list[TestError] = field(default_factory=list)
    prints: list[str] = field(default_factory=list)

    def is_failed(self) -> bool:
        if self.status in ("failure", "error"):
            return True
        return bool(self.errors) and self.status not in ("success", None)

    def to_summary_dict(self) -> dict[str, Any]:
        return {
            "id": self.id,
            "name": self.name,
            "file": self.file,
            "line": self.line,
            "column": self.column,
            "status": self.status or ("failure" if self.errors else "unknown"),
            "skipped": self.skipped,
            "hidden": self.hidden,
            "duration_ms": self.duration_ms,
            "errors": [e.to_dict() for e in self.errors],
            "prints": self.prints,
        }

    def to_failure_dict(self) -> dict[str, Any]:
        primary = self.errors[0].to_dict() if self.errors else {
            "failure_message": "",
            "is_test_failure": False,
            "expected": None,
            "actual": None,
            "exception_type": None,
            "stack_trace": "",
        }
        return {
            "test_name": self.name,
            "test_file": self.file,
            "line": self.line,
            "status": self.status or "failure",
            "prints": self.prints,
            **primary,
            "related_errors": [e.to_dict() for e in self.errors[1:]],
        }


@dataclass
class SuiteRecord:
    id: int
    path: str | None
    platform: str | None = None
    tests: list[int] = field(default_factory=list)


class MachineEventRecorder:
    """Accumulates flutter test --machine output for artifact generation."""

    def __init__(
        self,
        suite_name: str,
        command: list[str],
        cwd: Path,
        test_files: list[str],
        artifact_dir: Path | None,
    ) -> None:
        self.suite_name = suite_name
        self.command = command
        self.cwd = cwd
        self.test_files = list(test_files)
        self.artifact_dir = artifact_dir
        self.started_at = utc_now_iso()
        self.finished_at: str | None = None
        self.exit_code: int | None = None
        self.flutter_done_success: bool | None = None
        self.extra_steps: list[dict[str, Any]] = []
        self.non_json_lines: list[str] = []

        self._line_no = 0
        self._raw_records: list[dict[str, Any]] = []
        self._tests: dict[int, TestRecord] = {}
        self._suites: dict[int, SuiteRecord] = {}
        self._test_id_by_name: dict[str, int] = {}

    def add_extra_step(
        self,
        name: str,
        command: list[str],
        exit_code: int,
        stdout: str = "",
        stderr: str = "",
    ) -> None:
        self.extra_steps.append(
            {
                "name": name,
                "command": command,
                "exit_code": exit_code,
                "stdout": stdout,
                "stderr": stderr,
                "finished_at": utc_now_iso(),
            }
        )

    def ingest_line(self, line: str) -> Any | None:
        self._line_no += 1
        ts = utc_now_iso()
        record: dict[str, Any] = {
            "line": self._line_no,
            "timestamp": ts,
            "raw": line,
        }
        parsed: Any | None = None
        try:
            parsed = json.loads(line)
            if isinstance(parsed, list):
                for item in parsed:
                    if isinstance(item, dict):
                        self._apply_event(item)
            elif isinstance(parsed, dict):
                self._apply_event(parsed)
        except json.JSONDecodeError:
            self.non_json_lines.append(line)

        if parsed is not None:
            record["event"] = parsed
        self._raw_records.append(record)
        return parsed

    def _apply_event(self, event: dict[str, Any]) -> None:
        event_type = event.get("type")

        if event_type == "suite":
            suite = event.get("suite", {})
            sid = suite.get("id")
            if sid is None:
                return
            path = suite.get("path")
            rel = None
            if path:
                p = Path(path)
                rel = str(p.relative_to(self.cwd)) if p.is_absolute() else path
            self._suites[sid] = SuiteRecord(
                id=sid,
                path=rel or path,
                platform=suite.get("platform"),
            )

        elif event_type == "testStart":
            test = event.get("test", {})
            tid = test.get("id")
            if tid is None:
                return
            file_path = _url_to_relative_path(test.get("url"), self.cwd)
            rec = TestRecord(
                id=tid,
                name=test.get("name", ""),
                suite_id=test.get("suiteID"),
                file=file_path,
                line=test.get("line"),
                column=test.get("column"),
                url=test.get("url"),
                started_ms=event.get("time"),
            )
            self._tests[tid] = rec
            self._test_id_by_name[rec.name] = tid
            suite_id = test.get("suiteID")
            if suite_id in self._suites:
                self._suites[suite_id].tests.append(tid)

        elif event_type == "print":
            tid = event.get("testID")
            if tid in self._tests:
                self._tests[tid].prints.append(event.get("message", ""))

        elif event_type == "error":
            tid = event.get("testID")
            err = TestError(
                message=(event.get("error") or "").strip(),
                stack_trace=(event.get("stackTrace") or "").strip(),
                is_failure=bool(event.get("isFailure")),
            )
            if tid in self._tests:
                self._tests[tid].errors.append(err)
            else:
                unknown = TestRecord(id=-1, name="Unknown test")
                unknown.errors.append(err)
                self._tests[-1] = unknown

        elif event_type == "testDone":
            tid = event.get("testID")
            if tid not in self._tests:
                return
            rec = self._tests[tid]
            rec.status = event.get("result")
            rec.hidden = bool(event.get("hidden"))
            rec.skipped = bool(event.get("skipped"))
            if rec.started_ms is not None and event.get("time") is not None:
                rec.duration_ms = max(0, int(event["time"]) - int(rec.started_ms))

        elif event_type == "done":
            self.flutter_done_success = event.get("success")

    def finalize(self, exit_code: int) -> None:
        self.finished_at = utc_now_iso()
        self.exit_code = exit_code
        for rec in self._tests.values():
            if rec.errors and rec.status == "success":
                rec.status = "failure"

    def write_artifacts(self) -> Path | None:
        if self.artifact_dir is None:
            return None
        self.artifact_dir.mkdir(parents=True, exist_ok=True)

        raw_jsonl = self.artifact_dir / "raw.jsonl"
        with raw_jsonl.open("w", encoding="utf-8") as fh:
            for rec in self._raw_records:
                fh.write(json.dumps(rec, ensure_ascii=False) + "\n")

        raw_txt = self.artifact_dir / "raw.txt"
        with raw_txt.open("w", encoding="utf-8") as fh:
            for rec in self._raw_records:
                fh.write(rec["raw"] + "\n")

        summary = self.build_summary()
        failures = self.build_failures()

        (self.artifact_dir / "summary.json").write_text(
            json.dumps(summary, indent=2, ensure_ascii=False) + "\n",
            encoding="utf-8",
        )
        (self.artifact_dir / "failures.json").write_text(
            json.dumps(failures, indent=2, ensure_ascii=False) + "\n",
            encoding="utf-8",
        )
        (self.artifact_dir / "summary.md").write_text(
            render_summary_md(summary),
            encoding="utf-8",
        )
        (self.artifact_dir / "failures.md").write_text(
            render_failures_md(failures),
            encoding="utf-8",
        )
        return self.artifact_dir

    def build_summary(self) -> dict[str, Any]:
        counts = defaultdict(int)
        visible_tests: list[TestRecord] = []
        for rec in self._tests.values():
            if rec.id < 0:
                continue
            if rec.hidden:
                counts["hidden"] += 1
                continue
            visible_tests.append(rec)
            if rec.skipped:
                counts["skipped"] += 1
            elif rec.status == "success":
                counts["passed"] += 1
            elif rec.status == "failure":
                counts["failed"] += 1
            elif rec.status == "error":
                counts["error"] += 1
            elif rec.is_failed():
                counts["failed"] += 1
            else:
                counts["unknown"] += 1

        suites_out: list[dict[str, Any]] = []
        by_file: dict[str, list[TestRecord]] = defaultdict(list)
        for rec in visible_tests:
            key = rec.file or "(unknown file)"
            by_file[key].append(rec)

        for file_path, tests in sorted(by_file.items()):
            suites_out.append(
                {
                    "path": file_path,
                    "tests": [t.to_summary_dict() for t in sorted(tests, key=lambda t: t.name)],
                }
            )

        started = datetime.fromisoformat(self.started_at.replace("Z", "+00:00"))
        finished = datetime.fromisoformat(
            (self.finished_at or utc_now_iso()).replace("Z", "+00:00")
        )
        duration_ms = int((finished - started).total_seconds() * 1000)

        return {
            "schema_version": SCHEMA_VERSION,
            "suite_name": self.suite_name,
            "command": self.command,
            "cwd": str(self.cwd.resolve()),
            "started_at": self.started_at,
            "finished_at": self.finished_at,
            "duration_ms": duration_ms,
            "exit_code": self.exit_code,
            "flutter_done_success": self.flutter_done_success,
            "test_files": self.test_files,
            "counts": dict(counts),
            "suites": suites_out,
            "stderr_lines": list(self.non_json_lines),
            "extra_steps": self.extra_steps,
        }

    def build_failures(self) -> dict[str, Any]:
        failed = [
            rec
            for rec in self._tests.values()
            if rec.id >= 0 and not rec.hidden and rec.is_failed()
        ]
        return {
            "schema_version": SCHEMA_VERSION,
            "suite_name": self.suite_name,
            "failure_count": len(failed),
            "failures": [rec.to_failure_dict() for rec in sorted(failed, key=lambda r: (r.file or "", r.name))],
        }


def render_summary_md(summary: dict[str, Any]) -> str:
    lines = [
        f"# Test summary — {summary.get('suite_name', '')}",
        "",
        f"- **Started:** {summary.get('started_at')}",
        f"- **Finished:** {summary.get('finished_at')}",
        f"- **Duration:** {summary.get('duration_ms')} ms",
        f"- **Exit code:** {summary.get('exit_code')}",
        f"- **Flutter done success:** {summary.get('flutter_done_success')}",
        "",
        "## Command",
        "",
        "```",
        " ".join(summary.get("command") or []),
        "```",
        "",
        "## Counts",
        "",
    ]
    for key, val in sorted((summary.get("counts") or {}).items()):
        lines.append(f"- **{key}:** {val}")
    lines.extend(["", "## Tests by file", ""])
    for suite in summary.get("suites") or []:
        lines.append(f"### `{suite.get('path')}`")
        lines.append("")
        for test in suite.get("tests") or []:
            status = test.get("status", "?")
            mark = "✅" if status == "success" else ("⏭" if test.get("skipped") else "❌")
            loc = ""
            if test.get("line"):
                loc = f":{test['line']}"
            lines.append(f"- {mark} `{test.get('name')}` ({status}){loc}")
        lines.append("")
    if summary.get("stderr_lines"):
        lines.extend(["## Non-JSON output lines", ""])
        for ln in summary["stderr_lines"]:
            lines.append(f"- `{ln[:200]}`")
        lines.append("")
    return "\n".join(lines)


def render_failures_md(failures: dict[str, Any]) -> str:
    lines = [
        f"# Failures — {failures.get('suite_name', '')}",
        "",
        f"**{failures.get('failure_count', 0)}** failing test(s)",
        "",
    ]
    for i, fail in enumerate(failures.get("failures") or [], 1):
        loc = fail.get("test_file") or "unknown"
        if fail.get("line"):
            loc += f":{fail['line']}"
        lines.extend(
            [
                f"## [{i}] {fail.get('test_name')}",
                "",
                f"- **File:** `{loc}`",
                f"- **Status:** {fail.get('status')}",
                f"- **Exception:** {fail.get('exception_type')}",
                "",
            ]
        )
        if fail.get("expected") is not None:
            lines.extend(["### Expected", "", "```", str(fail["expected"]), "```", ""])
        if fail.get("actual") is not None:
            lines.extend(["### Actual", "", "```", str(fail["actual"]), "```", ""])
        lines.extend(
            [
                "### Message",
                "",
                "```",
                fail.get("failure_message") or "",
                "```",
                "",
                "### Stack trace",
                "",
                "```",
                fail.get("stack_trace") or "",
                "```",
                "",
            ]
        )
    if failures.get("failure_count", 0) == 0:
        lines.append("_No failures._\n")
    return "\n".join(lines)


def write_campaign_artifacts(
    campaign_dir: Path,
    campaign_id: str,
    started_at: str,
    finished_at: str,
    overall_exit_code: int,
    suite_results: list[dict[str, Any]],
) -> None:
    campaign_dir.mkdir(parents=True, exist_ok=True)
    started = datetime.fromisoformat(started_at.replace("Z", "+00:00"))
    finished = datetime.fromisoformat(finished_at.replace("Z", "+00:00"))
    duration_ms = int((finished - started).total_seconds() * 1000)

    campaign = {
        "schema_version": SCHEMA_VERSION,
        "campaign_id": campaign_id,
        "started_at": started_at,
        "finished_at": finished_at,
        "duration_ms": duration_ms,
        "overall_exit_code": overall_exit_code,
        "overall_status": "PASSED" if overall_exit_code == 0 else "FAILED",
        "suites": suite_results,
    }
    (campaign_dir / "campaign.json").write_text(
        json.dumps(campaign, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )

    lines = [
        f"# Campaign {campaign_id}",
        "",
        f"- **Overall:** {campaign['overall_status']} (exit {overall_exit_code})",
        f"- **Duration:** {duration_ms} ms",
        "",
        "## Suites",
        "",
    ]
    for suite in suite_results:
        status = "PASSED" if suite.get("exit_code") == 0 else "FAILED"
        lines.append(
            f"- **{suite.get('name')}:** {status} (exit {suite.get('exit_code')}) "
            f"— artifacts: `{suite.get('artifact_dir')}`"
        )
    lines.append("")
    (campaign_dir / "campaign.md").write_text("\n".join(lines), encoding="utf-8")

    merged_failures: list[dict[str, Any]] = []
    for suite in suite_results:
        failures_path = suite.get("failures_path")
        if not failures_path:
            continue
        path = Path(failures_path)
        if not path.is_file():
            continue
        data = json.loads(path.read_text(encoding="utf-8"))
        for fail in data.get("failures") or []:
            entry = dict(fail)
            entry["suite_name"] = data.get("suite_name") or suite.get("name")
            merged_failures.append(entry)

    merged = {
        "schema_version": SCHEMA_VERSION,
        "campaign_id": campaign_id,
        "failure_count": len(merged_failures),
        "failures": merged_failures,
    }
    (campaign_dir / "failures.json").write_text(
        json.dumps(merged, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )
    (campaign_dir / "failures.md").write_text(
        render_failures_md(
            {
                "suite_name": f"campaign {campaign_id}",
                "failure_count": len(merged_failures),
                "failures": merged_failures,
            }
        ),
        encoding="utf-8",
    )
