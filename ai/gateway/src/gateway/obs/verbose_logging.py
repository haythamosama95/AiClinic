"""Re-export shared verbose logging for gateway modules."""

from ai_common.verbose_logging import (
    VerboseLogger,
    configure,
    dump_json_for_log,
    get_logger,
    get_verbose_level,
    json_dump_sanitized,
    log_request_v2,
    log_response_v2,
    log_v0,
    log_v1,
    log_v2,
    parse_http_json_body,
    sanitized_json_body,
    sanitize,
    trace,
)

__all__ = [
    "VerboseLogger",
    "configure",
    "dump_json_for_log",
    "get_logger",
    "get_verbose_level",
    "get_verbose_logger",
    "json_dump_sanitized",
    "log_request_v2",
    "log_response_v2",
    "log_v0",
    "log_v1",
    "log_v2",
    "parse_http_json_body",
    "sanitized_json_body",
    "sanitize",
    "trace",
]


def get_verbose_logger(name: str) -> VerboseLogger:
    """Alias for :func:`get_logger` (gateway naming convention)."""
    return get_logger(name)
