"""Count Vitest cases via ``vitest list`` (discovery only; does not run tests)."""

from __future__ import annotations

import os
import subprocess
import threading
from pathlib import Path

from harness.campaign_config import apply_campaign_args, load_campaign_config
from harness.vitest_labels import vitest_list_line_label

# Cap concurrent ``vitest list`` subprocesses (nested batch + per-campaign parallelism).
_VITEST_LIST_SLOTS = max(2, min(8, (os.cpu_count() or 4)))
_VITEST_LIST_SEMAPHORE = threading.Semaphore(_VITEST_LIST_SLOTS)


def labels_in_vitest_list_output(stdout: str) -> set[str]:
    """Unique case labels in ``vitest list`` stdout.

    Vitest sometimes prints the same case twice. The summary keeps one row per
    name, so the campaign total has to be that unique set.
    """
    labels: set[str] = set()
    for line in stdout.splitlines():
        label = vitest_list_line_label(line)
        if label:
            labels.add(label)
    return labels


def count_labels_in_vitest_list_output(stdout: str) -> int:
    return len(labels_in_vitest_list_output(stdout))


def list_vitest_labels(
    cwd: Path,
    list_args: list[str],
    *,
    area: str | None = None,
    subcampaign: str | None = None,
    timeout: float = 600.0,
) -> set[str] | None:
    """Return the unique case labels for one ``vitest list`` invocation."""
    config = None
    if area and subcampaign:
        config = load_campaign_config(area, subcampaign)
    cmd = apply_campaign_args(["npx", "vitest", "list", *list_args], config)
    try:
        with _VITEST_LIST_SEMAPHORE:
            # Register discovery processes with the campaign SIGINT handler.
            # subprocess.run() owns its child internally, so the harness cannot
            # terminate and reap it when reconciliation is interrupted.
            from harness.common import _monitored_subprocess, _terminate_process

            proc = subprocess.Popen(
                cmd,
                cwd=str(cwd),
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                start_new_session=os.name != "nt",
            )
            try:
                with _monitored_subprocess(proc):
                    stdout, _stderr = proc.communicate(timeout=timeout)
            except KeyboardInterrupt:
                _terminate_process(proc)
                raise
            except subprocess.TimeoutExpired:
                _terminate_process(proc)
                return None
    except (OSError, subprocess.TimeoutExpired):
        return None
    if proc.returncode != 0:
        return None
    return labels_in_vitest_list_output(stdout)


def count_vitest_list(
    cwd: Path,
    list_args: list[str],
    *,
    area: str | None = None,
    subcampaign: str | None = None,
    timeout: float = 600.0,
) -> int | None:
    """Return expanded test count for one ``vitest list`` invocation."""
    labels = list_vitest_labels(
        cwd,
        list_args,
        area=area,
        subcampaign=subcampaign,
        timeout=timeout,
    )
    if labels is None:
        return None
    return len(labels)
