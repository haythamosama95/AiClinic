"""V0/V1/V2 verbose logging for AiClinic AI runners and operator tooling.

Levels (``AI_VERBOSE_LOG_LEVEL``):
  0 — job start/end, component name, success/fail, errors
  1 — config, branch decisions, durations, sanitized inputs
  2 — step-by-step trace, loop iterations, intermediate values (sanitized)
"""

from __future__ import annotations

import json
import logging
import os
import sys
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from ai_common.verbose_logging import (
    VerboseFormatter,
    configure as configure_common_verbose,
    get_verbose_level,
    get_verbose_source,
    get_verbose_target,
    parse_http_json_body,
    resolve_verbose_log_file,
    sanitized_json_body,
)

from obs.redaction import sanitize_for_log

_COMPONENT = "runners"
_CONFIGURED = False


class _JsonFormatter(logging.Formatter):
    """JSON formatter for optional runner log files (not stderr)."""

    def format(self, record: logging.LogRecord) -> str:
        payload: dict[str, Any] = {
            "ts": datetime.now(timezone.utc).isoformat(),  # noqa: UP017
            "level": record.levelname.lower(),
            "component": getattr(record, "component", _COMPONENT),
            "logger": record.name,
            "event": record.getMessage(),
        }
        extra = getattr(record, "fields", None)
        if isinstance(extra, dict):
            payload.update(extra)
        return json.dumps(payload, default=str, ensure_ascii=False)


class VerboseLogger:
    """Structured logger with V0/V1/V2 gating."""

    def __init__(self, name: str, *, component: str = _COMPONENT) -> None:
        self._name = name
        self._component = component
        self._stdlib = logging.getLogger(f"ai.{component}.{name}")

    def _emit(self, level: int, event: str, **fields: Any) -> None:
        if get_verbose_level() < level:
            return
        clean = {k: v for k, v in fields.items() if v is not None}
        if level >= 1 and clean:
            clean = sanitize_for_log(clean, level=level)
        record = self._stdlib.makeRecord(
            self._stdlib.name,
            logging.INFO,
            "(verbose)",
            0,
            event,
            (),
            None,
        )
        record.ai_verbose_level = level  # type: ignore[attr-defined]
        record.ai_verbose_fields = clean  # type: ignore[attr-defined]
        record.component = self._component  # type: ignore[attr-defined]
        record.fields = {"verbose_level": level, **clean}  # type: ignore[attr-defined]
        self._stdlib.handle(record)

    def v0(self, event: str, **fields: Any) -> None:
        """Minimum visibility: lifecycle and outcomes."""
        self._emit(0, event, **fields)

    def v1(self, event: str, **fields: Any) -> None:
        """Operational detail with sanitized inputs."""
        self._emit(1, event, **fields)

    def v2(self, event: str, **fields: Any) -> None:
        """Trace-level internals."""
        self._emit(2, event, **fields)

    def error(self, event: str, **fields: Any) -> None:
        """Always emit errors (treated as V0)."""
        self._emit(0, event, level="error", **fields)

    def job_start(self, message: str, **fields: Any) -> float:
        """Log operation start; return monotonic timestamp for duration helpers."""
        self.v0(message, runner=self._name, **fields)
        return time.monotonic()

    def job_end(
        self,
        message: str,
        *,
        started_at: float,
        success: bool,
        error: str | None = None,
        **fields: Any,
    ) -> None:
        duration_ms = round((time.monotonic() - started_at) * 1000, 2)
        payload = {
            "runner": self._name,
            "success": success,
            "duration_ms": duration_ms,
            **fields,
        }
        if error:
            payload["error"] = error
        if success:
            self.v0(message, **payload)
        else:
            self.error(message, **payload)
        self.v1(
            "Operation finished",
            duration_ms=duration_ms,
            success=success,
        )


def configure_logging(
    component: str = _COMPONENT,
    *,
    log_dir: str | None = None,
) -> None:
    """Configure human verbose logs to stderr and optional JSON log files."""
    global _CONFIGURED, _COMPONENT
    if _CONFIGURED:
        return

    _COMPONENT = component
    configure_common_verbose(source="runner")
    root = logging.getLogger("ai")
    root.handlers.clear()
    root.setLevel(logging.INFO)
    root.propagate = False

    log_target = get_verbose_target()
    if log_target in ("console", "both"):
        stderr_handler = logging.StreamHandler(sys.stderr)
        stderr_handler.setFormatter(VerboseFormatter(stream=sys.stderr))
        root.addHandler(stderr_handler)

    if log_target in ("file", "both"):
        verbose_path = resolve_verbose_log_file()
        verbose_path.parent.mkdir(parents=True, exist_ok=True)
        verbose_file_handler = logging.FileHandler(verbose_path, encoding="utf-8")
        verbose_file_handler.setFormatter(VerboseFormatter(stream=None))
        root.addHandler(verbose_file_handler)

    resolved_dir = log_dir or os.environ.get("RUNNER_LOG_DIR")
    if resolved_dir:
        path = Path(resolved_dir)
        path.mkdir(parents=True, exist_ok=True)
        file_handler = logging.FileHandler(path / f"{component}.jsonl", encoding="utf-8")
        file_handler.setFormatter(_JsonFormatter())
        root.addHandler(file_handler)

    _CONFIGURED = True
    get_logger("startup").v0(
        "Verbose logging configured",
        component=component,
        verbose_level=get_verbose_level(),
        verbose_source=get_verbose_source(),
        verbose_target=log_target,
        verbose_log_file=str(resolve_verbose_log_file())
        if log_target in ("file", "both")
        else None,
        log_dir=resolved_dir,
    )


def get_logger(name: str, *, component: str = _COMPONENT) -> VerboseLogger:
    """Return a verbose logger for the given runner sub-component."""
    return VerboseLogger(name, component=component)
