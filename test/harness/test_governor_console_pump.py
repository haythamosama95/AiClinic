"""Console.log capture from subprocess pump under live progress."""

from __future__ import annotations

import io
import os
from unittest.mock import MagicMock

from harness.governor_console_log import (
    attach_governor_console_log,
    governor_console_log_path,
    governor_console_output_path,
)
from harness.live_progress import NoOpCampaignProgressDisplay, pump_process_output


def test_pump_keeps_runner_output_out_of_console_log(tmp_path, monkeypatch) -> None:
    run_root = tmp_path / "gov-run"
    run_root.mkdir()
    monkeypatch.setenv("AICLINIC_LIVE_PROGRESS", "1")

    campaign_dir = run_root / "backend" / "all"
    campaign_dir.mkdir(parents=True)
    from harness.campaign_logging import CampaignLogSession

    with attach_governor_console_log(run_root, meta={"resume": False}):
        parser = NoOpCampaignProgressDisplay()
        stream = io.StringIO("hello from runner\nsecond line\n")
        pump_process_output(stream, parser, CampaignLogSession(campaign_dir))

    console = governor_console_log_path(run_root).read_text(encoding="utf-8")
    transcript = governor_console_output_path(campaign_dir).read_text(encoding="utf-8")
    assert "hello from runner" not in console
    assert "second line" not in console
    assert "hello from runner" in transcript
    assert "second line" in transcript


def test_pump_reader_survives_closed_stdout_after_child_exit(tmp_path, monkeypatch) -> None:
    run_root = tmp_path / "gov-run"
    run_root.mkdir()
    monkeypatch.delenv("AICLINIC_LIVE_PROGRESS", raising=False)

    proc = MagicMock()
    proc.poll.return_value = 0

    class BrokenStream:
        def __iter__(self):
            yield "line one\n"
            raise ValueError("I/O operation on closed file")

    campaign_dir = run_root / "backend" / "all"
    campaign_dir.mkdir(parents=True)
    from harness.campaign_logging import CampaignLogSession

    with attach_governor_console_log(run_root, meta={"resume": False}):
        pump_process_output(
            BrokenStream(),
            NoOpCampaignProgressDisplay(),
            CampaignLogSession(campaign_dir),
            proc=proc,
        )

    text = governor_console_log_path(run_root).read_text(encoding="utf-8")
    transcript = governor_console_output_path(campaign_dir).read_text(encoding="utf-8")
    assert "line one" not in text
    assert "line one" in transcript
    assert "harness stdout reader" not in text
