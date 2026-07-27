"""Structured log retention helpers (PHI redaction disabled)."""

from __future__ import annotations

import logging
import os
from logging.handlers import RotatingFileHandler, TimedRotatingFileHandler
from typing import Any

# Kept for callers that import the field set explicitly.
SENSITIVE_LOG_FIELDS: frozenset[str] = frozenset(
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
    }
)


def hash_sensitive_value(value: str) -> str:
    """Legacy helper retained for callers; logging no longer hashes values."""
    return value


def redact_sensitive_fields(
    _logger: Any,
    _method: str,
    event_dict: dict[str, Any],
) -> dict[str, Any]:
    """Pass through structured log fields unchanged."""
    event_dict.pop("_log_verbatim", None)
    event_dict.pop("_skip_redaction", None)
    return event_dict


def redact_phi_patterns(
    _logger: Any,
    _method: str,
    event_dict: dict[str, Any],
) -> dict[str, Any]:
    """Pass through structured log fields unchanged."""
    event_dict.pop("_skip_redaction", None)
    return event_dict


def build_log_file_handler(
    log_file: str,
    *,
    log_verbatim: bool,
    log_verbatim_retention_hours: int,
) -> logging.Handler:
    """Create a rotating file handler with verbatim-aware retention."""
    if log_verbatim:
        handler: logging.Handler = TimedRotatingFileHandler(
            log_file,
            when="H",
            interval=1,
            backupCount=max(1, log_verbatim_retention_hours),
            encoding="utf-8",
        )
    else:
        handler = RotatingFileHandler(
            log_file,
            maxBytes=10 * 1024 * 1024,
            backupCount=5,
            encoding="utf-8",
        )

    handler.setLevel(logging.INFO)
    return handler


def is_production_profile() -> bool:
    """True when the gateway runs outside an explicit development profile."""
    profile = os.environ.get("GATEWAY_PROFILE", os.environ.get("GATEWAY_ENV", "development"))
    return profile.lower() not in {"development", "dev", "local", "test"}


def warn_verbatim_outside_development(
    *,
    log_verbatim: bool,
    development_profile: bool,
    log_verbatim_retention_hours: int,
) -> None:
    """Emit a startup warning when verbatim PHI logging is enabled outside dev."""
    if not log_verbatim:
        return
    if development_profile or not is_production_profile():
        return
    import structlog

    structlog.get_logger("gateway.startup").warning(
        "log_verbatim=true outside a development profile; verbatim PHI may be written "
        "to disk with %dh retention",
        log_verbatim_retention_hours,
    )
