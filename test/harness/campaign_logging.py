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
        self._current_identity: str | None = None
        self._current_rel: str | None = None
        self._current_fp: TextIO | None = None
        self._current_started: str | None = None
        self._current_mono: float | None = None
        self._active_tests: dict[str, dict[str, Any]] = {}
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
        by_identity: dict[str, dict[str, Any]] = {}
        for entry in tests:
            if not isinstance(entry, dict):
                continue
            if entry.get("status") not in ("PASS", "FAIL"):
                continue
            identity = entry.get("identity")
            name = entry.get("name")
            key = identity if isinstance(identity, str) and identity else name
            if isinstance(key, str) and key:
                by_identity[key] = dict(entry)
        self._entries = list(by_identity.values())
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
        return bool(self._active_tests) or self._current_fp is not None

    def start_test(self, name: str, *, identity: str | None = None) -> None:
        if self.is_excluded(name):
            return
        resolved_identity = identity or name
        if resolved_identity in self._active_tests:
            return
        self._seq += 1
        rel = f"tests/{self._seq:03d}-{slug_for_test_log(name)}.log"
        path = self.log_dir / rel
        fp = path.open("w", encoding="utf-8")
        started = _utc_now_iso()
        mono = time.monotonic()
        self._active_tests[resolved_identity] = {
            "name": name,
            "log_file": rel,
            "fp": fp,
            "started_at": started,
            "started_mono": mono,
        }
        self._current_name = name
        self._current_identity = resolved_identity
        self._current_rel = rel
        self._current_fp = fp
        self._current_started = started
        self._current_mono = mono

    def append_output(self, text: str, *, identity: str | None = None) -> None:
        fp = self._active_fp(identity)
        if fp is None:
            if identity is not None:
                return
            self.start_test("_runner")
            fp = self._active_fp(identity)
        if fp is None:
            return
        fp.write(text)
        if text and not text.endswith("\n"):
            fp.write("\n")
        fp.flush()

    def append_line(self, line: str, *, identity: str | None = None) -> None:
        fp = self._active_fp(identity)
        if fp is None:
            if identity is not None:
                return
            self.start_test("_runner")
            fp = self._active_fp(identity)
        if fp is None:
            return
        fp.write(line)
        if not line.endswith("\n"):
            fp.write("\n")
        fp.flush()

    def _active_fp(self, identity: str | None = None) -> TextIO | None:
        if identity is not None:
            active = self._active_tests.get(identity)
            return active.get("fp") if active is not None else None
        key = self._current_identity
        active = self._active_tests.get(key) if key is not None else None
        return active.get("fp") if active is not None else self._current_fp

    def end_test(
        self,
        name: str | None = None,
        *,
        status: str,
        error: str | None = None,
        skipped: bool = False,
        resumed: bool = False,
        identity: str | None = None,
    ) -> None:
        resolved = name or self._current_name or "test"
        if self.is_excluded(resolved) and not resumed:
            if identity is None:
                self._close_current_without_entry()
            return
        resolved_identity = identity or self._current_identity or resolved
        active = self._active_tests.get(resolved_identity)
        if identity is not None and active is None:
            return
        if active is None and self._current_fp is None and status == "PASS" and skipped:
            self._entries.append(
                {
                    "name": resolved,
                    "identity": resolved_identity,
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
        if active is None and self._current_fp is None:
            return
        finished = _utc_now_iso()
        started_mono = active.get("started_mono") if active else self._current_mono
        started_at = active.get("started_at") if active else self._current_started
        log_file = active.get("log_file") if active else self._current_rel
        elapsed = round(time.monotonic() - (started_mono or time.monotonic()), 3)
        entry = {
            "name": resolved,
            "identity": resolved_identity,
            "status": status,
            "skipped": skipped,
            "log_file": log_file,
            "started_at": started_at,
            "finished_at": finished,
            "elapsed_seconds": elapsed,
            "error": error,
        }
        self._upsert_entry(entry)
        if active is not None:
            active["fp"].close()
            self._active_tests.pop(resolved_identity, None)
            if self._current_identity == resolved_identity:
                self._set_current_from_active()
        else:
            self._close_current_without_entry()
        self._flush_summary_partial()

    def _upsert_entry(self, entry: dict[str, Any]) -> None:
        identity = entry.get("identity")
        name = entry.get("name")
        key = identity if isinstance(identity, str) and identity else name
        if isinstance(key, str) and key:
            for index in range(len(self._entries) - 1, -1, -1):
                existing = self._entries[index]
                existing_identity = existing.get("identity")
                existing_name = existing.get("name")
                existing_key = (
                    existing_identity
                    if isinstance(existing_identity, str) and existing_identity
                    else existing_name
                )
                if existing_key == key:
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
        if self._current_identity is not None:
            active = self._active_tests.pop(self._current_identity, None)
            if active is not None:
                active["fp"].close()
        elif self._current_fp is not None:
            self._current_fp.close()
        self._set_current_from_active()

    def _set_current_from_active(self) -> None:
        if self._active_tests:
            key, active = next(reversed(self._active_tests.items()))
            self._current_identity = key
            self._current_name = active["name"]
            self._current_rel = active["log_file"]
            self._current_fp = active["fp"]
            self._current_started = active["started_at"]
            self._current_mono = active["started_mono"]
            return
        self._current_fp = None
        self._current_name = None
        self._current_identity = None
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
        for active in self._active_tests.values():
            active["fp"].close()
        self._active_tests.clear()
        self._set_current_from_active()
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
