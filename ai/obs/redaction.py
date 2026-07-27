"""Verbose runner log helpers (PHI redaction disabled)."""

from __future__ import annotations

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
        "authorization",
        "token",
        "api_key",
        "password",
        "secret",
        "messages",
        "body",
        "payload",
        "text",
    }
)


def hash_sensitive_value(value: str) -> str:
    """Legacy helper retained for callers; logging no longer hashes values."""
    return value


def redact_value(value: Any) -> Any:
    """Return values unchanged for verbose logging."""
    return value


def sanitize_for_log(data: Any, *, level: int = 1) -> Any:
    """Return values unchanged for V1/V2 logs."""
    if level < 1:
        return "<omitted>"
    return data
