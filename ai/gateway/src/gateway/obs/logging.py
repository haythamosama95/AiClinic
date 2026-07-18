"""Structured JSON logging with PHI redaction."""

from __future__ import annotations

import hashlib
import logging
import re
from logging.handlers import RotatingFileHandler
from pathlib import Path
from typing import Any

import structlog

_PHI_PATTERNS: list[re.Pattern[str]] = [
    re.compile(r"\bpatient[_\s]?name\b", re.IGNORECASE),
    re.compile(r"\b[A-Z][a-z]+ [A-Z][a-z]+\b"),
]


def _hash_value(value: str) -> str:
    return f"sha256:{hashlib.sha256(value.encode()).hexdigest()[:16]}"


def redact_phi(
    _logger: Any,
    _method: str,
    event_dict: dict[str, Any],
) -> dict[str, Any]:
    """Structlog processor that redacts potential PHI from log fields."""
    log_verbatim = event_dict.pop("_log_verbatim", False)
    if log_verbatim:
        return event_dict

    redacted = False
    for key, value in list(event_dict.items()):
        if not isinstance(value, str):
            continue
        for pattern in _PHI_PATTERNS:
            if pattern.search(value):
                event_dict[key] = _hash_value(value)
                redacted = True
                break
    if redacted:
        event_dict["redacted"] = True
    return event_dict


def configure_logging(log_dir: str, log_verbatim: bool = False) -> None:
    """Configure structlog JSON logging to rotating local files."""
    path = Path(log_dir)
    path.mkdir(parents=True, exist_ok=True)
    log_file = path / "gateway.jsonl"

    file_handler = RotatingFileHandler(
        log_file,
        maxBytes=10 * 1024 * 1024,
        backupCount=5,
        encoding="utf-8",
    )
    file_handler.setLevel(logging.INFO)

    root = logging.getLogger()
    root.handlers.clear()
    root.addHandler(file_handler)
    root.setLevel(logging.INFO)

    structlog.configure(
        processors=[
            structlog.contextvars.merge_contextvars,
            structlog.stdlib.add_log_level,
            structlog.stdlib.PositionalArgumentsFormatter(),
            structlog.processors.TimeStamper(fmt="iso"),
            lambda _l, _m, ed: {**ed, "_log_verbatim": log_verbatim},
            redact_phi,
            structlog.processors.JSONRenderer(),
        ],
        wrapper_class=structlog.stdlib.BoundLogger,
        context_class=dict,
        logger_factory=structlog.stdlib.LoggerFactory(),
        cache_logger_on_first_use=True,
    )


def get_logger(name: str | None = None) -> structlog.stdlib.BoundLogger:
    return structlog.get_logger(name)


def log_record(
    *,
    request_id: str,
    endpoint: str,
    outcome: str,
    caller_staff_id: str | None = None,
    error_code: str | None = None,
    runner_id: str | None = None,
    runner_status_change: str | None = None,
    latency_ms: float | None = None,
    agent: str | None = None,
    model: str | None = None,
    digest: str | None = None,
    queue_wait_seconds: float | None = None,
    first_token_seconds: float | None = None,
    total_seconds: float | None = None,
    prompt_tokens: int | None = None,
    completion_tokens: int | None = None,
    error_class: str | None = None,
    retried: bool | None = None,
    verbatim: bool | None = None,
    **extra: Any,
) -> None:
    """Emit a structured LogRecord per data-model §7."""
    logger = get_logger("gateway")
    fields: dict[str, Any] = {
        "request_id": request_id,
        "endpoint": endpoint,
        "outcome": outcome,
        "caller_staff_id": caller_staff_id,
        "error_code": error_code,
        "runner_id": runner_id,
        "runner_status_change": runner_status_change,
        "latency_ms": latency_ms,
        "agent": agent,
        "model": model,
        "digest": digest,
        "queue_wait_seconds": queue_wait_seconds,
        "first_token_seconds": first_token_seconds,
        "total_seconds": total_seconds,
        "prompt_tokens": prompt_tokens,
        "completion_tokens": completion_tokens,
        "error_class": error_class,
        "retried": retried,
        "verbatim": verbatim,
    }
    fields.update(extra)
    logger.info("request", **{k: v for k, v in fields.items() if v is not None})


def log_generation_record(
    *,
    request_id: str,
    endpoint: str,
    outcome: str,
    agent: str,
    model: str,
    digest: str,
    queue_wait_seconds: float,
    total_seconds: float,
    prompt_tokens: int,
    completion_tokens: int,
    retried: bool,
    verbatim: bool,
    caller_staff_id: str | None = None,
    runner_id: str | None = None,
    first_token_seconds: float | None = None,
    error_class: str | None = None,
    **extra: Any,
) -> None:
    """Emit a generation log record with required Phase 2 fields."""
    log_record(
        request_id=request_id,
        endpoint=endpoint,
        outcome=outcome,
        caller_staff_id=caller_staff_id,
        runner_id=runner_id,
        agent=agent,
        model=model,
        digest=digest,
        queue_wait_seconds=queue_wait_seconds,
        first_token_seconds=first_token_seconds,
        total_seconds=total_seconds,
        prompt_tokens=prompt_tokens,
        completion_tokens=completion_tokens,
        error_class=error_class,
        retried=retried,
        verbatim=verbatim,
        **extra,
    )
