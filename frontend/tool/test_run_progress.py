#!/usr/bin/env python3
"""Progress tracking for flutter test --machine runners."""

from __future__ import annotations

import time


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
