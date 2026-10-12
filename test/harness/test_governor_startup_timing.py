"""Governor batch must not block on vitest list before the live UI."""

from __future__ import annotations

import os
import subprocess
import time
from pathlib import Path
from unittest.mock import patch

import pytest

_PICKED_16 = [
    ("abo", "cross-worker"),
    ("abo", "import-boundary"),
    ("abo", "system"),
    ("abo", "version-matrix"),
    ("ai-platform", "e2e"),
    ("ai-platform", "eval"),
    ("ai-platform", "eval-all"),
    ("ai-platform", "load"),
    ("ai-platform", "npm-test"),
    ("ai-platform", "version-matrix"),
    ("backend", "all"),
    ("backend", "catalog"),
    ("frontend", "all"),
    ("frontend", "fullstack"),
    ("ops-launch", "launch-check"),
    ("vendor-contracts", "all"),
]


def test_test_count_never_spawns_subprocess_even_with_vitest_list_env(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setenv("AICLINIC_VITEST_LIST_COUNTS", "1")

    def fail_run(*_args, **_kwargs):
        raise AssertionError("test_count must not run vitest list")

    monkeypatch.setattr(subprocess, "run", fail_run)
    from harness.campaign_counts import test_count

    assert test_count("ai-platform", "npm-test") is not None


def test_warm_test_counts_static_under_two_seconds() -> None:
    from harness.dynamic_test_counts import clear_test_count_cache, warm_test_counts

    clear_test_count_cache()
    t0 = time.monotonic()
    out = warm_test_counts(_PICKED_16)
    elapsed = time.monotonic() - t0
    assert len(out) == len(_PICKED_16)
    assert elapsed < 2.0, f"warm_test_counts took {elapsed:.1f}s"


def test_prefetch_queue_totals_uses_static_only(monkeypatch: pytest.MonkeyPatch) -> None:
    from harness.batch_queue_display import batch_queue_from_picked
    from harness.interactive_run_dashboard import _prefetch_queue_totals_async
    from harness.live_progress import CampaignProgressDisplay

    monkeypatch.setenv("AICLINIC_VITEST_LIST_COUNTS", "1")

    def fail_run(*_args, **_kwargs):
        raise AssertionError("prefetch must not run vitest list")

    monkeypatch.setattr(subprocess, "run", fail_run)
    picked = [("abo", "system")]
    area_subs = {"abo": ["system"]}
    queue = batch_queue_from_picked(picked, area_subs)
    display = CampaignProgressDisplay("[abo/system]", batch_queue=queue)
    display.begin(clear_screen=False)
    _prefetch_queue_totals_async(queue, [("abo", "system")], display)
    time.sleep(0.3)
    assert queue.test_total_by_key.get(("abo", "system")) is not None
