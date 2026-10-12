"""Per-test log files under ``tests/`` plus a single ``summary.json`` per run."""

from __future__ import annotations

import json
import re
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, TextIO

from harness.campaign_resume import campaign_resume_enabled, exclude_tests_from_environ


def _utc_now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()

_SLUG_RE = re.compile(r"[^a-zA-Z0-9]+")


def slug_for_test_log(name: str, max_len: int = 48) -> str:
    slug = _SLUG_RE.sub("-", name.strip()).strip("-").lower()
    if not slug:
        slug = "test"
    return slug[:max_len].rstrip("-") or "test"


class CampaignLogSession:
    """Write one ``tests/NNN-slug.log`` per test case and ``summary.json`` for the run."""

    def __init__(self, log_dir: Path, *, resume: bool | None = None) -> None:
        self.log_dir = log_dir.resolve()
        self.tests_dir = self.log_dir / "tests"
        self.tests_dir.mkdir(parents=True, exist_ok=True)
        self.summary_path = self.log_dir / "summary.json"
        self._entries: list[dict[str, Any]] = []
        self._seq = 0
        self._run_started = _utc_now_iso()
        self._run_mono = time.monotonic()
        self._current_name: str | None = None
        self._current_rel: str | None = None
        self._current_fp: TextIO | None = None
        self._current_started: str | None = None
        self._current_mono: float | None = None
        self._exclude = exclude_tests_from_environ()
        self._resume = resume if resume is not None else campaign_resume_enabled()
        self._summary_fields: dict[str, Any] = {}
        if self._resume and self.summary_path.is_file():
            self._load_prior_summary()

    def _load_prior_summary(self) -> None:
        try:
            payload = json.loads(self.summary_path.read_text(encoding="utf-8"))
        except json.JSONDecodeError:
            return
        if isinstance(payload.get("started_at"), str):
            self._run_started = payload["started_at"]
        tests = payload.get("tests", [])
        if not isinstance(tests, list):
            return
        by_name: dict[str, dict[str, Any]] = {}
        for entry in tests:
            if not isinstance(entry, dict):
                continue
            if entry.get("status") not in ("PASS", "FAIL"):
                continue
            name = entry.get("name")
            if isinstance(name, str) and name:
                by_name[name] = dict(entry)
        self._entries = list(by_name.values())
        for entry in self._entries:
            rel = entry.get("log_file")
            if isinstance(rel, str) and rel.startswith("tests/"):
                try:
                    seq = int(Path(rel).name.split("-", 1)[0])
                    self._seq = max(self._seq, seq)
                except ValueError:
                    pass

    def is_excluded(self, name: str) -> bool:
        return name in self._exclude

    def has_active(self) -> bool:
        return self._current_fp is not None

    def start_test(self, name: str) -> None:
        if self.is_excluded(name):
            return
        if self._current_name == name and self._current_fp is not None:
            return
        self._close_current_without_entry()
        self._seq += 1
        rel = f"tests/{self._seq:03d}-{slug_for_test_log(name)}.log"
        path = self.log_dir / rel
        self._current_name = name
        self._current_rel = rel
        self._current_fp = path.open("w", encoding="utf-8")
        self._current_started = _utc_now_iso()
        self._current_mono = time.monotonic()

    def append_output(self, text: str) -> None:
        if self._current_fp is None:
            self.start_test("_runner")
        if self._current_fp is None:
            return
        self._current_fp.write(text)
        if text and not text.endswith("\n"):
            self._current_fp.write("\n")
        self._current_fp.flush()

    def append_line(self, line: str) -> None:
        if self._current_fp is None:
            self.start_test("_runner")
        if self._current_fp is None:
            return
        self._current_fp.write(line)
        if not line.endswith("\n"):
            self._current_fp.write("\n")
        self._current_fp.flush()

    def end_test(
        self,
        name: str | None = None,
        *,
        status: str,
        error: str | None = None,
        skipped: bool = False,
        resumed: bool = False,
    ) -> None:
        resolved = name or self._current_name or "test"
        if self.is_excluded(resolved) and not resumed:
            self._close_current_without_entry()
            return
        if self._current_fp is None and status == "PASS" and skipped:
            self._entries.append(
                {
                    "name": resolved,
                    "status": "PASS",
                    "skipped": True,
                    "resumed": True,
                    "log_file": None,
                    "started_at": None,
                    "finished_at": _utc_now_iso(),
                    "elapsed_seconds": 0.0,
                    "error": None,
                }
            )
            self._flush_summary_partial()
            return
        if self._current_fp is None:
            return
        finished = _utc_now_iso()
        elapsed = round(time.monotonic() - (self._current_mono or time.monotonic()), 3)
        entry = {
            "name": resolved,
            "status": status,
            "skipped": skipped,
            "log_file": self._current_rel,
            "started_at": self._current_started,
            "finished_at": finished,
            "elapsed_seconds": elapsed,
            "error": error,
        }
        self._upsert_entry(entry)
        self._close_current_without_entry()
        self._flush_summary_partial()

    def _upsert_entry(self, entry: dict[str, Any]) -> None:
        name = entry.get("name")
        if isinstance(name, str) and name:
            for index in range(len(self._entries) - 1, -1, -1):
                if self._entries[index].get("name") == name:
                    self._entries[index] = entry
                    return
        self._entries.append(entry)

    def abort_current_test(self) -> None:
        """Drop the in-flight test without recording a result (user interrupt)."""
        rel = self._current_rel
        self._close_current_without_entry()
        if rel:
            path = self.log_dir / rel
            if path.is_file():
                path.unlink()

    def _close_current_without_entry(self) -> None:
        if self._current_fp is not None:
            self._current_fp.close()
        self._current_fp = None
        self._current_name = None
        self._current_rel = None
        self._current_started = None
        self._current_mono = None

    def _flush_summary_partial(self) -> None:
        payload = self._summary_payload()
        text = json.dumps(payload, indent=2) + "\n"
        self.summary_path.write_text(text, encoding="utf-8")
        (self.log_dir / "meta.json").write_text(text, encoding="utf-8")

    def _summary_payload(self, **extra: Any) -> dict[str, Any]:
        fields = {**self._summary_fields, **extra}
        return {
            "started_at": self._run_started,
            "finished_at": _utc_now_iso(),
            "elapsed_seconds": round(time.monotonic() - self._run_mono, 3),
            "log_dir": str(self.log_dir),
            "tests_dir": str(self.tests_dir),
            "summary_file": str(self.summary_path),
            "tests": self._entries,
            "resumed": self._resume,
            **fields,
        }

    def deduped_pass_fail_counts(self) -> tuple[int, int]:
        from harness.test_result_stats import stats_from_tests_list

        stats = stats_from_tests_list(self._entries)
        return stats.passed, stats.failed

    def write_summary(self, **fields: Any) -> dict[str, Any]:
        self._close_current_without_entry()
        self._summary_fields = dict(fields)
        if "passed" not in fields or "failed" not in fields:
            passed, failed = self.deduped_pass_fail_counts()
            fields.setdefault("passed", passed)
            fields.setdefault("failed", failed)
            self._summary_fields = dict(fields)
        payload = self._summary_payload()
        text = json.dumps(payload, indent=2) + "\n"
        self.summary_path.write_text(text, encoding="utf-8")
        (self.log_dir / "meta.json").write_text(text, encoding="utf-8")
        return payload
