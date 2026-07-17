"""Helpers for emitting structured trace events."""

from __future__ import annotations

import json
from typing import Any

from gateway.obs.trace_bus import TraceBus, TraceKind

# Operator/client routes outside /v1/* that should appear in the live trace panel.
_TRACED_ROOT_PATHS = frozenset({"/health", "/ready", "/metrics"})


def should_emit_client_trace(path: str) -> bool:
    """Whether an inbound HTTP request should produce client↔gateway trace events."""
    return path.startswith("/v1/") or path in _TRACED_ROOT_PATHS


def body_text_for_trace(body: Any) -> str | None:
    """Serialize a body value for trace storage."""
    if body is None:
        return None
    if isinstance(body, (bytes, bytearray)):
        try:
            return body.decode("utf-8", errors="replace")
        except Exception:
            return "<binary>"
    if isinstance(body, str):
        return body
    try:
        return json.dumps(body, indent=2, default=str)
    except (TypeError, ValueError):
        return str(body)


def summarize_body(body: Any, *, max_len: int = 200) -> str | None:
    """Produce a compact string summary of a request/response body."""
    if body is None:
        return None
    if isinstance(body, (bytes, bytearray)):
        try:
            text = body.decode("utf-8", errors="replace")
        except Exception:
            return "<binary>"
        return text[:max_len] + ("…" if len(text) > max_len else "")
    if isinstance(body, str):
        return body[:max_len] + ("…" if len(body) > max_len else "")
    try:
        text = json.dumps(body, separators=(",", ":"), default=str)
    except (TypeError, ValueError):
        text = str(body)
    return text[:max_len] + ("…" if len(text) > max_len else "")


async def emit_client_trace(
    bus: TraceBus | None,
    *,
    direction: str,
    method: str,
    path: str,
    status_code: int,
    latency_ms: float,
    request_id: str,
    kind: TraceKind = "api",
    request_summary: str | None = None,
    response_summary: str | None = None,
    request_body: str | None = None,
    response_body: str | None = None,
) -> None:
    if bus is None:
        return
    await bus.emit(
        direction=direction,  # type: ignore[arg-type]
        method=method,
        path=path,
        kind=kind,
        status_code=status_code,
        latency_ms=latency_ms,
        request_id=request_id,
        request_summary=request_summary,
        response_summary=response_summary,
        request_body=request_body,
        response_body=response_body,
    )
