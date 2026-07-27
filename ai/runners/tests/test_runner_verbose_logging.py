"""Tests for runner verbose logging."""

from __future__ import annotations

import json
import re

import pytest
from obs.redaction import hash_sensitive_value, sanitize_for_log
from obs.verbose_logging import (
    VerboseLogger,
    configure_logging,
    get_verbose_level,
    parse_http_json_body,
    sanitized_json_body,
)

_LINE_RE = re.compile(
    r"^\[(?P<ts>\d{2}:\d{2}:\d{2}\.\d{3})\] \[(?P<source>gateway|runner|unknown)\] \[(?P<component>[^\]]+)\] (?P<message>.+)$"
)


def test_get_verbose_level_defaults_to_zero(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.delenv("AI_VERBOSE_LOG_LEVEL", raising=False)
    assert get_verbose_level() == 0


def test_get_verbose_level_clamps(monkeypatch: pytest.MonkeyPatch) -> None:
    from ai_common.verbose_logging import _reset_for_tests

    monkeypatch.setenv("AI_VERBOSE_LOG_LEVEL", "9")
    _reset_for_tests()
    assert get_verbose_level() == 2
    monkeypatch.setenv("AI_VERBOSE_LOG_LEVEL", "invalid")
    _reset_for_tests()
    assert get_verbose_level() == 0


def test_sanitize_for_log_redacts_sensitive_keys() -> None:
    payload = {"prompt": "patient notes", "model": "qwen3:4b"}
    sanitized = sanitize_for_log(payload, level=1)
    assert sanitized["model"] == "qwen3:4b"
    assert sanitized["prompt"].startswith("sha256:")


def test_hash_sensitive_value_is_stable() -> None:
    assert hash_sensitive_value("hello") == hash_sensitive_value("hello")
    assert hash_sensitive_value("hello") != hash_sensitive_value("world")


def test_verbose_logger_emits_human_format(
    monkeypatch: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
) -> None:
    import obs.verbose_logging as vl

    monkeypatch.setattr(vl, "_CONFIGURED", False)
    monkeypatch.setenv("AI_VERBOSE_LOG_LEVEL", "0")
    configure_logging(component="runners-test")
    logger = VerboseLogger("test", component="runners-test")
    logger.v0("Starting demo job", job="demo", success=True)
    captured = capsys.readouterr().err.strip().splitlines()[-1]
    match = _LINE_RE.match(captured)
    assert match is not None, captured
    assert match.group("source") == "runner"
    assert match.group("component") == "test"
    assert "Starting demo job" in match.group("message")
    assert "job='demo'" in match.group("message")


def test_v1_suppressed_at_level_zero(
    monkeypatch: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
) -> None:
    import obs.verbose_logging as vl

    monkeypatch.setattr(vl, "_CONFIGURED", False)
    monkeypatch.setenv("AI_VERBOSE_LOG_LEVEL", "0")
    configure_logging(component="runners-test")
    capsys.readouterr()
    logger = VerboseLogger("test", component="runners-test")
    logger.v1("Suppressed diagnostic detail", secret="value")
    captured = capsys.readouterr().err
    assert captured == ""
    assert "Suppressed diagnostic detail" not in captured


def test_job_end_reports_duration(
    monkeypatch: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
) -> None:
    import obs.verbose_logging as vl

    monkeypatch.setattr(vl, "_CONFIGURED", False)
    monkeypatch.setenv("AI_VERBOSE_LOG_LEVEL", "1")
    configure_logging(component="runners-test")
    logger = VerboseLogger("test", component="runners-test")
    started = logger.job_start("Starting work unit")
    logger.job_end("Finished work unit", started_at=started, success=True)
    lines = [
        _LINE_RE.match(line).groupdict()
        for line in capsys.readouterr().err.strip().splitlines()
        if _LINE_RE.match(line)
    ]
    end_events = [line for line in lines if "Finished work unit" in line["message"]]
    assert end_events
    assert "duration_ms=" in end_events[0]["message"]


def test_configure_logging_file_target_writes_file_only(
    monkeypatch: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
    tmp_path,
) -> None:
    import obs.verbose_logging as vl
    from ai_common.verbose_logging import _reset_for_tests

    _reset_for_tests()
    monkeypatch.setattr(vl, "_CONFIGURED", False)
    monkeypatch.setenv("AI_VERBOSE_LOG_LEVEL", "0")
    monkeypatch.setenv("AI_VERBOSE_LOG_TARGET", "file")
    log_file = tmp_path / "verbose.log"
    monkeypatch.setenv("AI_VERBOSE_LOG_FILE", str(log_file))
    configure_logging(component="runners-test")
    capsys.readouterr()
    logger = VerboseLogger("test", component="runners-test")
    logger.v0("Writing file-only verbose event", job="demo")
    captured = capsys.readouterr().err
    assert captured == ""
    content = log_file.read_text(encoding="utf-8")
    assert "Writing file-only verbose event" in content
    assert "job='demo'" in content


def test_configure_logging_both_target_writes_console_and_file(
    monkeypatch: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
    tmp_path,
) -> None:
    import obs.verbose_logging as vl
    from ai_common.verbose_logging import _reset_for_tests

    _reset_for_tests()
    monkeypatch.setattr(vl, "_CONFIGURED", False)
    monkeypatch.setenv("AI_VERBOSE_LOG_LEVEL", "0")
    monkeypatch.setenv("AI_VERBOSE_LOG_TARGET", "both")
    log_file = tmp_path / "verbose.log"
    monkeypatch.setenv("AI_VERBOSE_LOG_FILE", str(log_file))
    configure_logging(component="runners-test")
    capsys.readouterr()
    logger = VerboseLogger("test", component="runners-test")
    logger.v0("Writing console and file verbose event", job="demo")
    captured = capsys.readouterr().err
    assert "Writing console and file verbose event" in captured
    assert "Writing console and file verbose event" in log_file.read_text(encoding="utf-8")


def test_parse_http_json_body_parses_json_bytes() -> None:
    raw = json.dumps({"model": "qwen3:4b", "stream": False}).encode()
    parsed = parse_http_json_body(raw)
    assert parsed == {"model": "qwen3:4b", "stream": False}


def test_parse_http_json_body_returns_text_for_non_json() -> None:
    assert parse_http_json_body(b"plain text") == "plain text"
    assert parse_http_json_body(None) is None
    assert parse_http_json_body(b"") is None


def test_sanitized_json_body_redacts_sensitive_fields() -> None:
    raw = json.dumps({"model": "qwen3:4b", "prompt": "patient notes"}).encode()
    sanitized = sanitized_json_body(raw)
    assert sanitized["model"] == "qwen3:4b"
    assert str(sanitized["prompt"]).startswith("sha256:")


def test_v2_json_dump_emitted_with_redaction(
    monkeypatch: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
) -> None:
    import obs.verbose_logging as vl

    monkeypatch.setattr(vl, "_CONFIGURED", False)
    monkeypatch.setenv("AI_VERBOSE_LOG_LEVEL", "2")
    configure_logging(component="runners-test")
    capsys.readouterr()
    logger = VerboseLogger("console", component="runners-test")
    payload = {"model": "qwen3:4b", "prompt": "book Ahmed with Dr Ali"}
    logger.v2(
        "Sending JSON response to client",
        path="/api/runtime",
        status=200,
        body=sanitized_json_body(payload),
    )
    captured = capsys.readouterr().err
    assert "Sending JSON response to client" in captured
    assert "qwen3:4b" in captured
    assert "book Ahmed" not in captured
    assert "sha256:" in captured


def test_v2_json_dump_suppressed_at_level_one(
    monkeypatch: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
) -> None:
    import obs.verbose_logging as vl

    monkeypatch.setattr(vl, "_CONFIGURED", False)
    monkeypatch.setenv("AI_VERBOSE_LOG_LEVEL", "1")
    configure_logging(component="runners-test")
    capsys.readouterr()
    logger = VerboseLogger("console", component="runners-test")
    logger.v2(
        "Received JSON request body",
        path="/api/runtime",
        body=sanitized_json_body({"enabled": True}),
    )
    assert capsys.readouterr().err == ""
