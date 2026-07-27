"""Tests for ai_common.verbose_logging."""

from __future__ import annotations

import io
import json
import os
import re

import pytest

from ai_common import verbose_logging as vl
from ai_common.verbose_logging import (
    configure,
    dump_json_for_log,
    emit_shell_verbose_log,
    format_verbose_line,
    get_logger,
    get_verbose_target,
    health_poll_verbose_enabled,
    json_dump_sanitized,
    log_request_v2,
    log_response_v2,
    resolve_verbose_log_file,
    sanitize,
    trace,
)

_LINE_RE = re.compile(
    r"^\[(?P<ts>\d{2}:\d{2}:\d{2}\.\d{3})\] \[(?P<source>gateway|runner|unknown)\] \[(?P<component>[^\]]+)\] (?P<message>.+)$"
)


@pytest.fixture(autouse=True)
def _reset_verbose_logging() -> None:
    vl._reset_for_tests()
    os.environ.pop("AI_VERBOSE_LOG_LEVEL", None)
    os.environ.pop("AI_VERBOSE_LOG_TARGET", None)
    os.environ.pop("AI_VERBOSE_LOG_FILE", None)
    os.environ.pop("AI_VERBOSE_LOG_SOURCE", None)
    os.environ.pop("AI_HEALTH_POLL_VERBOSE", None)
    os.environ.pop("RUNNER_LOG_DIR", None)
    os.environ.pop("GATEWAY_LOG_DIR", None)
    yield
    vl._reset_for_tests()
    os.environ.pop("AI_VERBOSE_LOG_LEVEL", None)
    os.environ.pop("AI_VERBOSE_LOG_TARGET", None)
    os.environ.pop("AI_VERBOSE_LOG_FILE", None)
    os.environ.pop("AI_VERBOSE_LOG_SOURCE", None)
    os.environ.pop("AI_HEALTH_POLL_VERBOSE", None)
    os.environ.pop("RUNNER_LOG_DIR", None)
    os.environ.pop("GATEWAY_LOG_DIR", None)


def test_default_level_is_zero() -> None:
    assert vl.get_verbose_level() == 0


def test_level_from_env() -> None:
    os.environ["AI_VERBOSE_LOG_LEVEL"] = "2"
    assert vl.get_verbose_level() == 2


def test_level_clamped() -> None:
    os.environ["AI_VERBOSE_LOG_LEVEL"] = "9"
    assert vl.get_verbose_level() == 2


def test_health_poll_verbose_defaults_off() -> None:
    assert health_poll_verbose_enabled() is False


@pytest.mark.parametrize("value", ["1", "true", "yes", "on", "TRUE"])
def test_health_poll_verbose_truthy(value: str) -> None:
    os.environ["AI_HEALTH_POLL_VERBOSE"] = value
    assert health_poll_verbose_enabled() is True


@pytest.mark.parametrize("value", ["0", "false", "no", "off", ""])
def test_health_poll_verbose_falsy(value: str) -> None:
    os.environ["AI_HEALTH_POLL_VERBOSE"] = value
    assert health_poll_verbose_enabled() is False


def test_format_verbose_line_plain() -> None:
    line = format_verbose_line(
        source="gateway",
        component="trace_bus",
        message="TraceBus.emit complete",
        fields={"buffer_size": 8, "event_id": "f1b2815b-be47-48f6-aa86-00db6fcd94b5"},
        now=__import__("datetime").datetime(2026, 7, 27, 2, 42, 49, 536000),
        use_color=False,
    )
    assert line == (
        "[02:42:49.536] [gateway] [trace_bus] TraceBus.emit complete"
        "\tbuffer_size=8 event_id='f1b2815b-be47-48f6-aa86-00db6fcd94b5'"
    )


def test_format_verbose_line_with_color() -> None:
    line = format_verbose_line(
        source="gateway",
        component="startup",
        message="verbose logging configured",
        fields={"ai_verbose_log_level": 0},
        now=__import__("datetime").datetime(2026, 7, 27, 2, 42, 49, 100000),
        use_color=True,
    )
    assert "\033[" in line
    assert "[gateway]" in line
    assert "[startup]" in line


def test_v0_emits_at_default_level() -> None:
    stream = io.StringIO()
    configure(level=0, stream=stream, source="gateway")
    logger = get_logger("test.module")
    logger.v0("started", request_id="abc")
    logger.v1("should not appear")
    logger.v2("also hidden")
    output = stream.getvalue()
    assert "[gateway]" in output
    assert "[module]" in output
    assert "started" in output
    assert "request_id='abc'" in output
    assert "should not appear" not in output


def test_v1_logs_sensitive_fields_verbatim() -> None:
    os.environ["AI_VERBOSE_LOG_LEVEL"] = "1"
    stream = io.StringIO()
    configure(stream=stream, source="gateway")
    logger = get_logger("test.sanitize")
    logger.v1(
        "request",
        prompt="book Ahmed with Dr Ali",
        request_id="req-1",
        api_key="sk-secret",
    )
    output = stream.getvalue()
    assert "req-1" in output
    assert "sk-secret" in output
    assert "book Ahmed" in output
    assert "sha256:" not in output


def test_sanitize_nested_mapping() -> None:
    payload = {
        "context": {"patient_name": "Jane Doe"},
        "meta": {"request_id": "r1"},
    }
    sanitized = sanitize(payload)
    assert sanitized["meta"]["request_id"] == "r1"
    assert sanitized["context"]["patient_name"] == "Jane Doe"


def test_trace_decorator_sync() -> None:
    stream = io.StringIO()
    configure(level=2, stream=stream, source="gateway")

    @trace("adding two integers")
    def add(a: int, b: int) -> int:
        return a + b

    assert add(1, 2) == 3
    output = stream.getvalue()
    assert "adding two integers enter" in output
    assert "adding two integers exit" in output
    assert "duration_ms=" in output


def test_trace_requires_explicit_operation() -> None:
    with pytest.raises(TypeError, match="explicit operation description"):

        @trace
        def unlabeled() -> None:
            return None


@pytest.mark.asyncio
async def test_trace_decorator_async() -> None:
    stream = io.StringIO()
    configure(level=2, stream=stream, source="gateway")

    @trace("adding two integers asynchronously")
    async def async_add(a: int, b: int) -> int:
        return a + b

    assert await async_add(2, 3) == 5
    output = stream.getvalue()
    assert "adding two integers asynchronously enter" in output
    assert "adding two integers asynchronously exit" in output


def test_trace_logs_v0_on_failure() -> None:
    stream = io.StringIO()
    configure(level=2, stream=stream, source="gateway")

    @trace("raising a deliberate error")
    def boom() -> None:
        raise ValueError("nope")

    with pytest.raises(ValueError, match="nope"):
        boom()
    output = stream.getvalue()
    assert "raising a deliberate error failed" in output
    assert "error_type='ValueError'" in output


def test_default_target_is_console() -> None:
    assert get_verbose_target() == "console"


def test_target_from_env() -> None:
    os.environ["AI_VERBOSE_LOG_TARGET"] = "both"
    assert get_verbose_target() == "both"


def test_invalid_target_defaults_to_console() -> None:
    os.environ["AI_VERBOSE_LOG_TARGET"] = "syslog"
    assert get_verbose_target() == "console"


def test_resolve_verbose_log_file_prefers_explicit_path(tmp_path) -> None:
    log_file = tmp_path / "custom.log"
    os.environ["AI_VERBOSE_LOG_FILE"] = str(log_file)
    assert resolve_verbose_log_file() == log_file


def test_resolve_verbose_log_file_uses_runner_log_dir(tmp_path) -> None:
    os.environ["RUNNER_LOG_DIR"] = str(tmp_path)
    assert resolve_verbose_log_file() == tmp_path / "verbose.log"


def test_configure_file_target_writes_to_file_only(tmp_path) -> None:
    log_file = tmp_path / "verbose.log"
    stream = io.StringIO()
    configure(level=0, stream=stream, target="file", log_file=log_file, source="gateway")
    logger = get_logger("test.file")
    logger.v0("file_only", request_id="abc")
    assert stream.getvalue() == ""
    content = log_file.read_text(encoding="utf-8")
    assert "[gateway]" in content
    assert "file_only" in content
    assert "request_id='abc'" in content


def test_configure_both_target_writes_console_and_file(tmp_path) -> None:
    log_file = tmp_path / "verbose.log"
    stream = io.StringIO()
    configure(level=0, stream=stream, target="both", log_file=log_file, source="gateway")
    logger = get_logger("test.both")
    logger.v0("both_targets")
    assert "both_targets" in stream.getvalue()
    assert "both_targets" in log_file.read_text(encoding="utf-8")


def test_emit_shell_verbose_log_file_target(tmp_path) -> None:
    log_file = tmp_path / "shell.log"
    os.environ["AI_VERBOSE_LOG_TARGET"] = "file"
    os.environ["AI_VERBOSE_LOG_FILE"] = str(log_file)
    os.environ["AI_VERBOSE_LOG_SOURCE"] = "runner"
    stream = io.StringIO()
    emit_shell_verbose_log(0, "shell_event", component="shell", stream=stream, job="demo")
    assert stream.getvalue() == ""
    content = log_file.read_text(encoding="utf-8")
    assert "shell_event" in content
    assert "[runner]" in content
    assert "job='demo'" in content


def test_dump_json_for_log_preserves_sensitive_keys() -> None:
    payload = {
        "request_id": "req-1",
        "api_key": "sk-secret-key",
        "prompt": "book Ahmed with Dr Ali",
    }
    dumped = dump_json_for_log(payload)
    assert "req-1" in dumped
    assert "sk-secret-key" in dumped
    assert "book Ahmed" in dumped
    assert "sha256:" not in dumped
    assert "\n" in dumped  # pretty-printed by default


def test_dump_json_for_log_compact() -> None:
    dumped = dump_json_for_log({"ok": True}, compact=True)
    assert dumped == '{"ok":true}'
    assert "\n" not in dumped


def test_dump_json_for_log_json_string_input() -> None:
    dumped = dump_json_for_log('{"token":"abc123","id":"x1"}')
    assert "abc123" in dumped
    assert "x1" in dumped
    assert "sha256:" not in dumped


def test_dump_json_for_log_expands_embedded_json_strings() -> None:
    inner = {"command_type": "create_appointment", "confidence": 0.9}
    payload = {"message": {"role": "assistant", "content": json.dumps(inner)}}
    dumped = dump_json_for_log(payload)
    assert '"content": {' in dumped
    assert '"command_type": "create_appointment"' in dumped
    assert '\\n  \\"command_type\\"' not in dumped


def test_format_fields_multiline_body_on_separate_lines() -> None:
    body = '{\n  "ok": true\n}'
    line = format_verbose_line(
        source="gateway",
        component="openai_client",
        message="Runner chat completion response",
        fields={"model": "qwen3:4b", "url": "http://127.0.0.1:11434/api/chat", "body": body},
        now=__import__("datetime").datetime(2026, 7, 27, 3, 40, 45, 740000),
        use_color=False,
    )
    assert "model='qwen3:4b'" in line
    assert "url='http://127.0.0.1:11434/api/chat'" in line
    assert "\n\tbody=\n" in line
    assert 'body=\'' not in line
    assert '\n  "ok": true' in line


def test_dump_json_for_log_plain_text_truncates() -> None:
    text = "x" * 9000
    dumped = dump_json_for_log(text)
    assert "<truncated len=9000>" in dumped


def test_dump_json_for_log_binary_bytes() -> None:
    dumped = dump_json_for_log(bytes([0xFF, 0xFE, 0xFD]))
    assert dumped.startswith("<binary hex=")
    assert "len=3" in dumped


def test_log_request_v2_emits_at_level_2() -> None:
    stream = io.StringIO()
    configure(level=2, stream=stream, source="gateway")
    logger = get_logger("test.request")
    log_request_v2(
        logger,
        "posting generate request",
        {"request_id": "r1", "model": "qwen3:4b"},
    )
    output = stream.getvalue()
    assert "posting generate request request" in output
    assert "\tbody=" in output
    assert "json_body=" not in output
    assert "request_id" in output
    assert "qwen3:4b" in output


def test_log_response_v2_emits_at_level_2() -> None:
    stream = io.StringIO()
    configure(level=2, stream=stream, source="gateway")
    logger = get_logger("test.response")
    log_response_v2(
        logger,
        "runner health check",
        {"status": "ok", "runner_id": "ollama-1"},
    )
    output = stream.getvalue()
    assert "runner health check response" in output
    assert "\tbody=" in output
    assert "json_body=" not in output
    assert "ollama-1" in output


def test_log_request_v2_suppressed_below_level_2() -> None:
    stream = io.StringIO()
    configure(level=1, stream=stream, source="gateway")
    logger = get_logger("test.suppressed")
    log_request_v2(logger, "hidden request", {"secret_field": "value"})
    log_response_v2(logger, "hidden response", {"data": "value"})
    output = stream.getvalue()
    assert "hidden request" not in output
    assert "hidden response" not in output
    assert "\tbody=" not in output
    assert "json_body=" not in output


def test_log_request_v2_logs_sensitive_fields_in_dump() -> None:
    stream = io.StringIO()
    configure(level=2, stream=stream, source="gateway")
    logger = get_logger("test.redact")
    log_request_v2(
        logger,
        "sending auth request",
        {"request_id": "r9", "api_key": "sk-live", "password": "p@ss"},
    )
    output = stream.getvalue()
    assert "r9" in output
    assert "sk-live" in output
    assert "p@ss" in output
    assert "sha256:" not in output


def test_json_dump_sanitized_preserves_sensitive_fields() -> None:
    dumped = json_dump_sanitized({"prompt": "secret text", "task": "command"})
    assert "secret text" in dumped
    assert "sha256:" not in dumped
    assert '"task":"command"' in dumped
