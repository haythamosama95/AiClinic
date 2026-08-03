#!/usr/bin/env python3
"""Progress tracking and live terminal display for flutter test --machine runners."""

from __future__ import annotations

import itertools
import sys
import threading
import time
from pathlib import Path
from urllib.parse import unquote, urlparse


class TestRunProgress:
    """Progress with a precomputed total (no runtime suite discovery)."""

    def __init__(self) -> None:
        self.tests_done = 0
        self.total_tests = 0
        self.started_at = time.monotonic()
        self.finished_at: float | None = None

    def reset(self, total_tests: int) -> None:
        self.tests_done = 0
        self.total_tests = max(0, total_tests)
        self.started_at = time.monotonic()
        self.finished_at = None

    def handle_event(self, event: dict) -> None:
        if event.get("type") == "testDone" and not event.get("hidden"):
            self.tests_done += 1

    def label(self) -> str:
        elapsed = self._format_elapsed()
        if self.total_tests > 0:
            pct = min(100.0, (self.tests_done / self.total_tests) * 100)
            return f"{self.tests_done}/{self.total_tests} ({pct:.1f}%) | elapsed {elapsed}"
        return f"{self.tests_done} tests | elapsed {elapsed}"

    def finalize(self) -> None:
        self.finished_at = time.monotonic()

    def _format_elapsed(self) -> str:
        end = self.finished_at if self.finished_at is not None else time.monotonic()
        elapsed_seconds = int(max(0.0, end - self.started_at))
        minutes, seconds = divmod(elapsed_seconds, 60)
        hours, minutes = divmod(minutes, 60)
        if hours:
            return f"{hours:02d}:{minutes:02d}:{seconds:02d}"
        return f"{minutes:02d}:{seconds:02d}"


def _truncate(text: str, max_len: int = 88) -> str:
    if len(text) <= max_len:
        return text
    return text[: max_len - 1] + "…"


def _filename_from_url(url: str | None) -> str | None:
    if not url:
        return None
    parsed = urlparse(url)
    if parsed.scheme != "file":
        return None
    path = unquote(parsed.path)
    if path.startswith("/") and len(path) > 2 and path[2] == ":":
        path = path[1:]
    return Path(path).name or None


def _format_test_label(test: dict) -> str:
    """Show only the test file basename, not its full path."""
    filename = _filename_from_url(test.get("url"))
    if filename:
        return filename

    name = test.get("name", "")
    if name.startswith("loading "):
        rest = name[len("loading ") :].strip()
        if "/" in rest or "\\" in rest:
            return f"loading {Path(rest).name}"
        return name

    if "/" in name or "\\" in name:
        return Path(name).name

    return name or "?"


class LiveTestDisplay:
    """Multi-line live progress: one header plus one line per parallel worker."""

    def __init__(
        self,
        title: str,
        *,
        concurrency: int = 1,
        total_tests: int = 0,
        refresh_interval: float = 0.1,
    ) -> None:
        self.title = title
        self.concurrency = max(1, concurrency)
        self.progress = TestRunProgress()
        self.progress.reset(total_tests)
        self._refresh_interval = refresh_interval
        self._running = False
        self._lock = threading.Lock()
        self._lines_rendered = 0
        self._spinner = itertools.cycle(["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"])
        self._thread: threading.Thread | None = None

        self._running_tests: dict[int, str] = {}
        self._slots: dict[int, int | None] = dict.fromkeys(range(self.concurrency))
        self._test_slot: dict[int, int] = {}

    def start(self) -> None:
        self._running = True
        self._thread = threading.Thread(target=self._refresh_loop, daemon=True)
        self._thread.start()

    def stop(self) -> None:
        self._running = False
        if self._thread is not None:
            self._thread.join()
        with self._lock:
            self.progress.finalize()
            self._render(final=True)

    def handle_event(self, event: dict | list) -> None:
        if isinstance(event, list):
            for item in event:
                self.handle_event(item)
            return
        if not isinstance(event, dict):
            return

        event_type = event.get("type")
        with self._lock:
            if event_type == "testStart":
                test = event.get("test", {})
                tid = test.get("id")
                label = _format_test_label(test)
                if tid is not None and label != "?":
                    self._assign_test(tid, label)
            elif event_type == "testDone":
                tid = event.get("testID")
                self.progress.handle_event(event)
                if tid is not None:
                    self._release_test(tid)

    def _assign_test(self, test_id: int, name: str) -> None:
        self._running_tests[test_id] = name
        for slot in range(self.concurrency):
            if self._slots[slot] is None:
                self._slots[slot] = test_id
                self._test_slot[test_id] = slot
                return

    def _release_test(self, test_id: int) -> None:
        self._running_tests.pop(test_id, None)
        slot = self._test_slot.pop(test_id, None)
        if slot is not None:
            self._slots[slot] = None

    def _refresh_loop(self) -> None:
        while self._running:
            with self._lock:
                self._render()
            time.sleep(self._refresh_interval)

    def _render(self, final: bool = False) -> None:
        spinner_char = "✔" if final else next(self._spinner)
        header = f"{self.title} {spinner_char} {self.progress.label()}"

        worker_lines: list[str] = []
        for slot in range(self.concurrency):
            test_id = self._slots.get(slot)
            if test_id is not None:
                name = self._running_tests.get(test_id, "?")
                worker_lines.append(f"  ▸ [worker {slot + 1}] {_truncate(name)}")

        lines = [header, *worker_lines]
        line_count = len(lines)

        if self._lines_rendered > 0:
            sys.stdout.write(f"\033[{self._lines_rendered}A")

        for line in lines:
            sys.stdout.write("\033[2K\r" + line + "\n")

        if self._lines_rendered > line_count:
            for _ in range(self._lines_rendered - line_count):
                sys.stdout.write("\033[2K\r\n")

        self._lines_rendered = line_count
        sys.stdout.flush()
