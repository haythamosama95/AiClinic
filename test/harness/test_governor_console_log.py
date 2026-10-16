"""Governor console.log capture."""

from __future__ import annotations

from harness.governor_console_log import (
    attach_governor_console_log,
    governor_console_log_line,
    governor_console_log_path,
)


def test_resume_appends_to_console_log(tmp_path) -> None:
    run_root = tmp_path / "gov-run"
    run_root.mkdir()
    path = governor_console_log_path(run_root)
    path.write_text("stale output from prior session\n", encoding="utf-8")

    with attach_governor_console_log(run_root, meta={"resume": True}):
        governor_console_log_line("fresh resume line")

    text = path.read_text(encoding="utf-8")
    assert "stale output from prior session" in text
    assert "Governor campaign summary started" in text
    assert "resume: True" in text
    assert "fresh resume line" in text
    assert "Governor campaign summary ended" in text


def test_fresh_run_appends_when_file_already_exists(tmp_path) -> None:
    run_root = tmp_path / "gov-run"
    run_root.mkdir()
    path = governor_console_log_path(run_root)
    path.write_text("earlier segment\n", encoding="utf-8")

    with attach_governor_console_log(run_root, meta={"resume": False}):
        governor_console_log_line("new segment")

    text = path.read_text(encoding="utf-8")
    assert "earlier segment" in text
    assert "new segment" in text
