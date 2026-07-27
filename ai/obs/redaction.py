"""PHI and secret redaction for verbose runner logs (delegates to ai_common)."""

from __future__ import annotations

from typing import Any

from ai_common.verbose_logging import hash_sensitive_value, sanitize

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


def redact_value(value: Any) -> Any:
    """Hash a scalar or nested structure for safe logging."""
    if value is None:
        return None
    if isinstance(value, str):
        return hash_sensitive_value(value) if value else ""
    return sanitize(value)


def sanitize_for_log(data: Any, *, level: int = 1) -> Any:
    """Sanitize values for V1/V2 logs. V0 callers should omit sensitive payloads."""
    if level < 1:
        return "<omitted>"
    if isinstance(data, str) and len(data) > 500:
        return f"{data[:200]}…<truncated len={len(data)}>"
    return sanitize(data)
