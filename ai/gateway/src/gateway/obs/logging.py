"""Structured JSON logging with PHI redaction."""

from __future__ import annotations

import logging
from pathlib import Path
from typing import Any

import structlog

from gateway.obs.redaction import (
    build_log_file_handler,
    redact_phi_patterns,
    redact_sensitive_fields,
    warn_verbatim_outside_development,
)


def configure_logging(
    log_dir: str,
    log_verbatim: bool = False,
    *,
    retention_hours: int = 24,
    log_verbatim_retention_hours: int | None = None,
    development_profile: bool = False,
) -> None:
    """Configure structlog JSON logging to rotating local files."""
    hours = (
        log_verbatim_retention_hours
        if log_verbatim_retention_hours is not None
        else retention_hours
    )
    path = Path(log_dir)
    path.mkdir(parents=True, exist_ok=True)
    file_handler = build_log_file_handler(
        str(path / "gateway.jsonl"),
        log_verbatim=log_verbatim,
        log_verbatim_retention_hours=hours,
    )

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
            redact_sensitive_fields,
            redact_phi_patterns,
            structlog.processors.JSONRenderer(),
        ],
        wrapper_class=structlog.stdlib.BoundLogger,
        context_class=dict,
        logger_factory=structlog.stdlib.LoggerFactory(),
        cache_logger_on_first_use=True,
    )

    warn_verbatim_outside_development(
        log_verbatim=log_verbatim,
        development_profile=development_profile,
        log_verbatim_retention_hours=hours,
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
