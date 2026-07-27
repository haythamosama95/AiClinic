"""Verbose logging for the AiClinic AI layer (gateway + runners).

Environment
-----------
AI_VERBOSE_LOG_LEVEL
    Controls how much diagnostic detail is written (independent of the
    structured JSON audit logs in ``gateway.obs.logging``).

    * ``0`` (default) — V0: entry/exit of major operations, key decisions, errors.
    * ``1`` — V1: sanitized parameters, branch paths, timing hints.
    * ``2`` — V2: full internal traces (enter/exit via ``@trace`` with an
      explicit operation description).

AI_VERBOSE_LOG_TARGET
    Where human-readable verbose logs are written (default ``console``).

    * ``console`` — stderr only.
    * ``file`` — log file only (see ``AI_VERBOSE_LOG_FILE``).
    * ``both`` — stderr and log file.

AI_VERBOSE_LOG_FILE
    Path for verbose log file output when target is ``file`` or ``both``.
    When unset, defaults to ``verbose.log`` under ``RUNNER_LOG_DIR`` or
    ``GATEWAY_LOG_DIR`` (a symlink to the latest run when started via
    ``ai/start.sh`` with file logging). Start scripts create a new
    ``verbose-YYYYMMDD-HHMMSS.log`` per run and update the symlink.

Sensitive values (API keys, tokens, JWTs, PHI-bearing fields) are hashed or
redacted at V1 and V2. V0 messages should avoid embedding secrets directly.

Log messages must describe *operations* in plain language (e.g. "polling runner
health", "validating scheduling command"), not function or class identifiers
(e.g. ``HealthPoller.start``, ``ensure_capable_runner``).

AI_VERBOSE_LOG_SOURCE
    Origin tag printed on each line: ``gateway`` or ``runner``.

AI_HEALTH_POLL_VERBOSE
    When enabled (``1``, ``true``, ``yes``, or ``on``), emit verbose logs for
    each runner health poll cycle (poll loop, per-runner results, trace events).
    Default is off so periodic polling does not flood logs when
    ``AI_VERBOSE_LOG_LEVEL`` is raised for other diagnostics.

Output format (stderr)::

    [HH:MM:SS.mmm] [gateway] [component] message\\tkey=value key='value'
"""

from __future__ import annotations

import functools
import hashlib
import inspect
import json
import logging
import os
import re
import sys
import time
from collections.abc import Callable, Mapping
from datetime import datetime
from pathlib import Path
from typing import Any, IO, ParamSpec, TextIO, TypeVar

# AI_VERBOSE_LOG_LEVEL: 0 (default) | 1 | 2 — see module docstring.
_ENV_VAR = "AI_VERBOSE_LOG_LEVEL"
_TARGET_ENV_VAR = "AI_VERBOSE_LOG_TARGET"
_FILE_ENV_VAR = "AI_VERBOSE_LOG_FILE"
_SOURCE_ENV_VAR = "AI_VERBOSE_LOG_SOURCE"
_HEALTH_POLL_VERBOSE_ENV_VAR = "AI_HEALTH_POLL_VERBOSE"
_VALID_TARGETS = frozenset({"console", "file", "both"})
_VALID_SOURCES = frozenset({"gateway", "runner"})
_TRUTHY = frozenset({"1", "true", "yes", "on"})

# ANSI colors (disabled when stderr is not a TTY or NO_COLOR is set).
_COLOR_RESET = "\033[0m"
_COLOR_DIM = "\033[90m"
_COLOR_GATEWAY = "\033[36m"  # cyan
_COLOR_RUNNER = "\033[33m"  # yellow
_COLOR_SOURCE_DEFAULT = "\033[37m"  # white
_COLOR_COMPONENT = "\033[32m"  # green
_SOURCE_COLORS = {
    "gateway": _COLOR_GATEWAY,
    "runner": _COLOR_RUNNER,
}

_SENSITIVE_FIELD_NAMES: frozenset[str] = frozenset(
    {
        "prompt",
        "context",
        "params",
        "display_summary",
        "notes",
        "patient_name",
        "request_body",
        "response_body",
        "request_summary",
        "response_summary",
        "password",
        "secret",
        "api_key",
        "apikey",
        "access_token",
        "refresh_token",
        "authorization",
        "bearer",
        "jwt",
        "token",
    }
)

_SENSITIVE_KEY_SUBSTRINGS: tuple[str, ...] = (
    "password",
    "secret",
    "token",
    "api_key",
    "apikey",
    "authorization",
    "bearer",
    "jwt",
    "credential",
)

_PHI_PATTERNS: list[re.Pattern[str]] = [
    re.compile(r"\bpatient[_\s]?name\b", re.IGNORECASE),
    re.compile(r"\b[A-Z][a-z]+ [A-Z][a-z]+\b"),
]

_JWT_PATTERN = re.compile(r"eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+")

# Cap for non-JSON body text logged as a raw string (bytes or plain text).
_MAX_NON_JSON_BODY_CHARS = 8192

P = ParamSpec("P")
R = TypeVar("R")

_configured = False
_cached_level: int | None = None
_cached_target: str | None = None
_cached_source: str | None = None
_cached_health_poll_verbose: bool | None = None
_shell_log_file: TextIO | None = None


def get_verbose_level() -> int:
    """Return the active verbose level (0, 1, or 2)."""
    global _cached_level
    if _cached_level is not None:
        return _cached_level
    raw = os.environ.get(_ENV_VAR, "0").strip()
    try:
        level = int(raw)
    except ValueError:
        level = 0
    _cached_level = max(0, min(2, level))
    return _cached_level


def get_verbose_source() -> str:
    """Return the active verbose log source tag (gateway or runner)."""
    global _cached_source
    if _cached_source is not None:
        return _cached_source
    raw = os.environ.get(_SOURCE_ENV_VAR, "").strip().lower()
    if raw in _VALID_SOURCES:
        _cached_source = raw
    else:
        _cached_source = "unknown"
    return _cached_source


def get_verbose_target() -> str:
    """Return the active verbose log destination (console, file, or both)."""
    global _cached_target
    if _cached_target is not None:
        return _cached_target
    raw = os.environ.get(_TARGET_ENV_VAR, "console").strip().lower()
    if raw not in _VALID_TARGETS:
        raw = "console"
    _cached_target = raw
    return _cached_target


def health_poll_verbose_enabled() -> bool:
    """Return whether per-cycle runner health poll verbose logging is enabled."""
    global _cached_health_poll_verbose
    if _cached_health_poll_verbose is not None:
        return _cached_health_poll_verbose
    raw = os.environ.get(_HEALTH_POLL_VERBOSE_ENV_VAR, "0").strip().lower()
    _cached_health_poll_verbose = raw in _TRUTHY
    return _cached_health_poll_verbose


def resolve_verbose_log_file() -> Path:
    """Return the path for human-readable verbose log file output."""
    explicit = os.environ.get(_FILE_ENV_VAR, "").strip()
    if explicit:
        return Path(explicit)
    for env_name in ("RUNNER_LOG_DIR", "GATEWAY_LOG_DIR"):
        log_dir = os.environ.get(env_name, "").strip()
        if log_dir:
            return Path(log_dir) / "verbose.log"
    return Path("ai/logs/verbose.log")


def _reset_for_tests() -> None:
    """Reset cached configuration (tests only)."""
    global _configured, _cached_level, _cached_target, _cached_source
    global _cached_health_poll_verbose, _shell_log_file
    _configured = False
    _cached_level = None
    _cached_target = None
    _cached_source = None
    _cached_health_poll_verbose = None
    if _shell_log_file is not None:
        try:
            _shell_log_file.close()
        except Exception:
            pass
    _shell_log_file = None


def hash_sensitive_value(value: str) -> str:
    """Return a stable short hash for redacted log fields."""
    digest = hashlib.sha256(value.encode()).hexdigest()[:16]
    return f"sha256:{digest}"


def _is_sensitive_key(key: str) -> bool:
    lowered = key.lower().replace("-", "_")
    if lowered in _SENSITIVE_FIELD_NAMES:
        return True
    return any(substr in lowered for substr in _SENSITIVE_KEY_SUBSTRINGS)


def _redact_string(value: str, *, deep: bool) -> str:
    if not value:
        return value
    if _JWT_PATTERN.search(value):
        return hash_sensitive_value(value)
    if deep:
        for pattern in _PHI_PATTERNS:
            if pattern.search(value):
                return hash_sensitive_value(value)
    return value


def sanitize(value: Any, *, deep: bool = True) -> Any:
    """Recursively sanitize a value for verbose logging at V1/V2."""
    if value is None or isinstance(value, (bool, int, float)):
        return value
    if isinstance(value, str):
        return _redact_string(value, deep=deep)
    if isinstance(value, Mapping):
        return {
            str(key): (
                hash_sensitive_value(str(value[key]))
                if _is_sensitive_key(str(key)) and value[key] is not None
                else sanitize(value[key], deep=deep)
            )
            for key in value
        }
    if isinstance(value, (list, tuple, set)):
        return [sanitize(item, deep=deep) for item in value]
    return value


def should_use_color(stream: IO[str] | None = None) -> bool:
    """Return True when ANSI colors should be applied."""
    if os.environ.get("NO_COLOR"):
        return False
    target = stream if stream is not None else sys.stderr
    return hasattr(target, "isatty") and bool(target.isatty())


def component_from_logger_name(logger_name: str) -> str:
    """Return the short component tag from a fully-qualified logger name."""
    return logger_name.rsplit(".", 1)[-1]


def _format_field_value(value: Any) -> str:
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        return str(value)
    if isinstance(value, str):
        escaped = value.replace("'", "\\'")
        return f"'{escaped}'"
    return repr(value)


def format_fields(fields: Mapping[str, Any]) -> str:
    """Format sanitized fields as a tab-indented ``key=value`` suffix."""
    if not fields:
        return ""
    parts = [f"{key}={_format_field_value(fields[key])}" for key in sorted(fields)]
    return "\t" + " ".join(parts)


def _prepare_fields(fields: Mapping[str, Any], *, level: int) -> dict[str, Any]:
    if not fields:
        return {}
    if level >= 1:
        return dict(sanitize(dict(fields)))
    return {key: value for key, value in fields.items() if not _is_sensitive_key(key)}


def format_verbose_line(
    *,
    source: str,
    component: str,
    message: str,
    fields: Mapping[str, Any] | None = None,
    now: datetime | None = None,
    use_color: bool | None = None,
) -> str:
    """Format a single verbose log line (no trailing newline)."""
    stamp = (now or datetime.now()).strftime("%H:%M:%S.%f")[:-3]
    source_tag = source or get_verbose_source()
    field_suffix = format_fields(fields or {})

    if use_color is None:
        use_color = should_use_color()

    if use_color:
        source_color = _SOURCE_COLORS.get(source_tag, _COLOR_SOURCE_DEFAULT)
        return (
            f"{_COLOR_DIM}[{stamp}]{_COLOR_RESET} "
            f"{source_color}[{source_tag}]{_COLOR_RESET} "
            f"{_COLOR_COMPONENT}[{component}]{_COLOR_RESET} "
            f"{message}{field_suffix}"
        )

    return f"[{stamp}] [{source_tag}] [{component}] {message}{field_suffix}"


class VerboseFormatter(logging.Formatter):
    """Human-readable verbose log formatter for stderr."""

    def __init__(self, *, stream: TextIO | None = None) -> None:
        super().__init__()
        self._stream = stream

    def format(self, record: logging.LogRecord) -> str:
        fields = getattr(record, "ai_verbose_fields", None) or {}
        component = component_from_logger_name(record.name)
        return format_verbose_line(
            source=get_verbose_source(),
            component=component,
            message=record.getMessage(),
            fields=fields,
            now=datetime.fromtimestamp(record.created),
            use_color=should_use_color(self._stream),
        )


class VerboseLogger:
    """Level-gated verbose logger writing to stderr.

    Every *message* / *operation* argument must be a human-readable description
    of what the system is doing — never a function, method, or class name.
    """

    def __init__(self, name: str) -> None:
        self.name = name
        self._stdlib = logging.getLogger(f"ai.verbose.{name}")

    def _emit(self, level: int, message: str, **fields: Any) -> None:
        if get_verbose_level() < level:
            return
        safe_fields = _prepare_fields(fields, level=level)
        self._stdlib.log(
            logging.INFO,
            message,
            extra={
                "ai_verbose_level": level,
                "ai_verbose_fields": safe_fields,
            },
        )

    def v0(self, message: str, **fields: Any) -> None:
        """Minimum detail — major operations, decisions, errors."""
        self._emit(0, message, **fields)

    def v1(self, message: str, **fields: Any) -> None:
        """More detail — sanitized parameters, branches, timing hints."""
        self._emit(1, message, **fields)

    def v2(self, message: str, **fields: Any) -> None:
        """Maximum detail — internal traces and debug internals."""
        self._emit(2, message, **fields)

    def entry(self, operation: str, **fields: Any) -> None:
        """V0 alias: major operation entry.

        *operation* must describe the work (e.g. "polling runner health"), not
        a code identifier.
        """
        self.v0(f"{operation} start", **fields)

    def exit(self, operation: str, **fields: Any) -> None:
        """V0 alias: major operation exit.

        *operation* must describe the work (e.g. "polling runner health"), not
        a code identifier.
        """
        self.v0(f"{operation} complete", **fields)

    def init(self, operation: str, **fields: Any) -> None:
        """V0 alias: component or subsystem initialization.

        *operation* must describe what is starting (e.g. "health poller"), not
        a class name like ``HealthPoller``.
        """
        self.v0(f"{operation} initializing", **fields)

    def detail(self, message: str, **fields: Any) -> None:
        """V1 alias: supplementary diagnostic detail."""
        self.v1(message, **fields)


def get_logger(name: str) -> VerboseLogger:
    """Return a verbose logger bound to *name* (typically ``__name__``)."""
    return VerboseLogger(name)


def log_v0(logger: VerboseLogger, message: str, **fields: Any) -> None:
    logger.v0(message, **fields)


def log_v1(logger: VerboseLogger, message: str, **fields: Any) -> None:
    logger.v1(message, **fields)


def log_v2(logger: VerboseLogger, message: str, **fields: Any) -> None:
    logger.v2(message, **fields)


def _bytes_as_log_text(data: bytes) -> str | None:
    """Return UTF-8 text when *data* looks textual; otherwise None (binary)."""
    if not data:
        return ""
    if any(byte < 32 and byte not in (9, 10, 13) for byte in data):
        return None
    try:
        return data.decode("utf-8")
    except UnicodeDecodeError:
        return None


def _truncate_body_text(text: str) -> str:
    if len(text) <= _MAX_NON_JSON_BODY_CHARS:
        return text
    return f"{text[:_MAX_NON_JSON_BODY_CHARS]}…<truncated len={len(text)}>"


def parse_http_json_body(raw: bytes | str | None) -> Any | None:
    """Parse HTTP body bytes to JSON when possible; otherwise return decoded text."""
    if raw is None:
        return None
    if isinstance(raw, bytes):
        if not raw:
            return None
        text = raw.decode("utf-8", errors="replace")
    else:
        text = raw
    if not text.strip():
        return None
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        return text


def sanitized_json_body(
    raw: bytes | str | dict | list | Any | None,
    *,
    level: int = 2,
) -> Any | None:
    """Return a redacted JSON value suitable for V2 verbose logging."""
    if raw is None:
        return None
    if isinstance(raw, (dict, list)):
        parsed: Any = raw
    elif isinstance(raw, (bytes, str)):
        parsed = parse_http_json_body(raw)
        if parsed is None and isinstance(raw, bytes) and raw:
            parsed = raw.decode("utf-8", errors="replace")
    else:
        parsed = raw
    if parsed is None:
        return None
    if level < 1:
        return "<omitted>"
    return sanitize(parsed)


def dump_json_for_log(obj: Any, *, compact: bool = False) -> str:
    """Serialize a request/response payload for V2 verbose logs.

    Dicts and other JSON-serializable structures are passed through
    ``sanitize()`` before encoding. String bodies that parse as JSON are
    decoded, sanitized, and re-encoded. Non-JSON strings are redacted and
    truncated when huge. Binary ``bytes`` are decoded as UTF-8 when possible;
    otherwise a short hex preview and total length are logged.
    """
    if isinstance(obj, bytes):
        text = _bytes_as_log_text(obj)
        if text is None:
            preview_len = min(200, len(obj))
            hex_preview = obj[:preview_len].hex()
            if len(obj) > preview_len:
                return f"<binary hex={hex_preview}… truncated len={len(obj)}>"
            return f"<binary hex={hex_preview} len={len(obj)}>"
        obj = text

    if isinstance(obj, str):
        stripped = obj.strip()
        if not stripped:
            return obj
        try:
            obj = json.loads(obj)
        except (json.JSONDecodeError, ValueError):
            return _truncate_body_text(_redact_string(obj, deep=True))

    sanitized = sanitize(obj)
    if compact:
        return json.dumps(
            sanitized,
            ensure_ascii=False,
            separators=(",", ":"),
            default=str,
        )
    return json.dumps(sanitized, ensure_ascii=False, indent=2, default=str)


def json_dump_sanitized(payload: Any) -> str:
    """Compact JSON dump after ``sanitize()`` (alias for ``dump_json_for_log``)."""
    return dump_json_for_log(payload, compact=True)


def log_request_v2(
    logger: VerboseLogger,
    operation: str,
    request: dict[str, Any] | str | bytes,
    **ctx: Any,
) -> None:
    """Emit a V2 log entry with the full sanitized request JSON body.

    *operation* describes the work (e.g. "posting generate request"), not a
    code identifier. No-op when ``AI_VERBOSE_LOG_LEVEL`` is below 2.
    """
    logger.v2(f"{operation} request", body=dump_json_for_log(request), **ctx)


def log_response_v2(
    logger: VerboseLogger,
    operation: str,
    response: dict[str, Any] | str | bytes,
    **ctx: Any,
) -> None:
    """Emit a V2 log entry with the full sanitized response JSON body.

    *operation* describes the work (e.g. "posting generate request"), not a
    code identifier. No-op when ``AI_VERBOSE_LOG_LEVEL`` is below 2.
    """
    logger.v2(f"{operation} response", body=dump_json_for_log(response), **ctx)


def _shell_log_file_handle() -> TextIO:
    global _shell_log_file
    if _shell_log_file is None:
        path = resolve_verbose_log_file()
        path.parent.mkdir(parents=True, exist_ok=True)
        _shell_log_file = path.open("a", encoding="utf-8")
    return _shell_log_file


def emit_shell_verbose_log(
    min_level: int,
    event: str,
    *,
    component: str = "shell",
    stream: TextIO | None = None,
    **fields: Any,
) -> None:
    """Emit a level-gated verbose log line from shell scripts."""
    if get_verbose_level() < min_level:
        return
    safe_fields = _prepare_fields(fields, level=min_level)
    log_target = get_verbose_target()
    source = get_verbose_source()
    line = format_verbose_line(
        source=source,
        component=component,
        message=event,
        fields=safe_fields,
        use_color=False,
    )

    if log_target in ("console", "both"):
        console = stream or sys.stderr
        colored = format_verbose_line(
            source=source,
            component=component,
            message=event,
            fields=safe_fields,
            use_color=should_use_color(console),
        )
        console.write(f"{colored}\n")

    if log_target in ("file", "both"):
        _shell_log_file_handle().write(f"{line}\n")
        _shell_log_file_handle().flush()


def configure(
    *,
    level: int | None = None,
    stream: Any | None = None,
    target: str | None = None,
    log_file: str | Path | None = None,
    source: str | None = None,
) -> int:
    """Configure the shared verbose logging handler (idempotent).

    Returns the active verbose level after configuration.
    """
    global _configured, _cached_level, _cached_target, _cached_source

    if level is not None:
        _cached_level = max(0, min(2, level))
    else:
        _cached_level = None
        level = get_verbose_level()

    if source is not None:
        normalized_source = source.strip().lower()
        _cached_source = (
            normalized_source if normalized_source in _VALID_SOURCES else "unknown"
        )
    else:
        _cached_source = None

    if target is not None:
        normalized = target.strip().lower()
        _cached_target = normalized if normalized in _VALID_TARGETS else "console"
    else:
        _cached_target = None

    resolved_target = _cached_target or get_verbose_target()
    resolved_file = Path(log_file) if log_file is not None else resolve_verbose_log_file()

    if _configured:
        return level

    root = logging.getLogger("ai.verbose")
    root.handlers.clear()

    if resolved_target in ("console", "both"):
        console_stream = stream or sys.stderr
        console_handler = logging.StreamHandler(console_stream)
        console_handler.setLevel(logging.INFO)
        console_handler.setFormatter(VerboseFormatter(stream=console_stream))
        root.addHandler(console_handler)

    if resolved_target in ("file", "both"):
        resolved_file.parent.mkdir(parents=True, exist_ok=True)
        file_handler = logging.FileHandler(resolved_file, encoding="utf-8")
        file_handler.setLevel(logging.INFO)
        file_handler.setFormatter(VerboseFormatter(stream=None))
        root.addHandler(file_handler)

    root.setLevel(logging.INFO)
    root.propagate = False
    _configured = True

    get_logger("ai_common").v0(
        "verbose logging configured",
        ai_verbose_log_level=level,
        ai_verbose_log_source=get_verbose_source(),
        ai_verbose_log_target=resolved_target,
        ai_verbose_log_file=str(resolved_file)
        if resolved_target in ("file", "both")
        else None,
    )
    return level


def trace(
    operation: str | Callable[P, R],
    *,
    logger: VerboseLogger | None = None,
) -> Callable[P, R] | Callable[[Callable[P, R]], Callable[P, R]]:
    """Decorator that logs operation entry/exit at V2 with elapsed milliseconds.

    Requires an explicit *operation* description — never derives messages from
    the wrapped function's name. Example::

        @trace("ensuring capable runner")
        async def ensure_capable_runner(...): ...
    """
    if callable(operation):
        raise TypeError(
            "@trace requires an explicit operation description; "
            'use @trace("human-readable operation") instead of @trace'
        )

    def decorator(inner: Callable[P, R]) -> Callable[P, R]:
        bound_logger = logger or get_logger(inner.__module__)

        if inspect.iscoroutinefunction(inner):

            @functools.wraps(inner)
            async def async_wrapper(*args: P.args, **kwargs: P.kwargs) -> R:
                bound_logger.v2(f"{operation} enter")
                started = time.perf_counter()
                try:
                    result = await inner(*args, **kwargs)
                except BaseException as exc:
                    elapsed_ms = (time.perf_counter() - started) * 1000.0
                    bound_logger.v0(
                        f"{operation} failed",
                        error_type=type(exc).__name__,
                        duration_ms=round(elapsed_ms, 2),
                    )
                    raise
                elapsed_ms = (time.perf_counter() - started) * 1000.0
                bound_logger.v2(
                    f"{operation} exit",
                    duration_ms=round(elapsed_ms, 2),
                )
                return result

            return async_wrapper  # type: ignore[return-value]

        @functools.wraps(inner)
        def sync_wrapper(*args: P.args, **kwargs: P.kwargs) -> R:
            bound_logger.v2(f"{operation} enter")
            started = time.perf_counter()
            try:
                result = inner(*args, **kwargs)
            except BaseException as exc:
                elapsed_ms = (time.perf_counter() - started) * 1000.0
                bound_logger.v0(
                    f"{operation} failed",
                    error_type=type(exc).__name__,
                    duration_ms=round(elapsed_ms, 2),
                )
                raise
            elapsed_ms = (time.perf_counter() - started) * 1000.0
            bound_logger.v2(f"{operation} exit", duration_ms=round(elapsed_ms, 2))
            return result

        return sync_wrapper

    return decorator
