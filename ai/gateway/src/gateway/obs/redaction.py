"""PHI-redacting structlog processor and verbatim log retention."""

from __future__ import annotations

import hashlib
import logging
import os
import re
from logging.handlers import RotatingFileHandler, TimedRotatingFileHandler
from typing import Any

# Fields that may carry PHI or user-supplied text — redacted when log_verbatim=false.
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

_PHI_PATTERNS: list[re.Pattern[str]] = [
    re.compile(r"\bpatient[_\s]?name\b", re.IGNORECASE),
    re.compile(r"\b[A-Z][a-z]+ [A-Z][a-z]+\b"),
]


def hash_sensitive_value(value: str) -> str:
    """Return a stable short hash for redacted log fields."""
    digest = hashlib.sha256(value.encode()).hexdigest()[:16]
    return f"sha256:{digest}"


def redact_sensitive_fields(
    _logger: Any,
    _method: str,
    event_dict: dict[str, Any],
) -> dict[str, Any]:
    """Drop or hash prompt/context/params text unless verbatim logging is enabled."""
    log_verbatim = event_dict.pop("_log_verbatim", False)
    if log_verbatim:
        event_dict["_skip_redaction"] = True
        return event_dict

    redacted = False
    for key in list(event_dict.keys()):
        if key not in SENSITIVE_LOG_FIELDS:
            continue
        value = event_dict[key]
        if value is None:
            continue
        if isinstance(value, str):
            if value:
                event_dict[key] = hash_sensitive_value(value)
                redacted = True
        elif isinstance(value, dict):
            serialized = str(sorted(value.items()))
            event_dict[key] = hash_sensitive_value(serialized)
            redacted = True
        else:
            event_dict[key] = hash_sensitive_value(str(value))
            redacted = True

    if redacted:
        event_dict["redacted"] = True
    return event_dict


def redact_phi_patterns(
    _logger: Any,
    _method: str,
    event_dict: dict[str, Any],
) -> dict[str, Any]:
    """Hash remaining string values that match common PHI patterns."""
    if event_dict.pop("_skip_redaction", False):
        return event_dict

    redacted = event_dict.get("redacted", False)
    for key, value in list(event_dict.items()):
        if key.startswith("_") or not isinstance(value, str):
            continue
        for pattern in _PHI_PATTERNS:
            if pattern.search(value):
                event_dict[key] = hash_sensitive_value(value)
                redacted = True
                break

    if redacted:
        event_dict["redacted"] = True
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
