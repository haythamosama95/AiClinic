"""Pure ASGI observability middleware (streaming-safe)."""

from __future__ import annotations

import json
import time
import uuid
from typing import Any

from ai_common.verbose_logging import get_logger, log_request_v2, log_response_v2
from starlette.types import ASGIApp, Message, Receive, Scope, Send

from gateway.obs.logging import log_record
from gateway.obs.metrics import record_request
from gateway.obs.trace_bus import TraceBus
from gateway.obs.trace_helpers import (
    body_text_for_trace,
    emit_client_trace,
    should_emit_client_trace,
    summarize_body,
)

_vlog = get_logger(__name__)


def _header(scope: Scope, name: bytes) -> str | None:
    for key, value in scope.get("headers", []):
        if key.lower() == name:
            return value.decode("latin-1")
    return None


async def _read_body(receive: Receive) -> bytes:
    body = b""
    more_body = True
    while more_body:
        message = await receive()
        if message["type"] != "http.request":
            continue
        body += message.get("body", b"")
        more_body = message.get("more_body", False)
    return body


def _replay_receive(body: bytes, receive: Receive) -> Receive:
    sent = False

    async def replay() -> Message:
        nonlocal sent
        if not sent:
            sent = True
            return {"type": "http.request", "body": body, "more_body": False}
        # Forward subsequent reads to the real client channel so streaming
        # responses (SSE) are not cancelled by a synthetic disconnect.
        return await receive()

    return replay


def _trace_request_body(body: bytes) -> str | None:
    if not body:
        return None
    try:
        return body_text_for_trace(json.loads(body))
    except (json.JSONDecodeError, TypeError):
        return body_text_for_trace(body)


def _parse_json_body(body: bytes) -> Any | None:
    if not body:
        return None
    try:
        return json.loads(body)
    except (json.JSONDecodeError, TypeError):
        return None


def _request_outcome(status: int, error_code: str | None) -> str:
    if status < 400:
        return "ok"
    if error_code == "unauthenticated":
        return "unauthenticated"
    if error_code == "forbidden":
        return "forbidden"
    if error_code == "not_implemented":
        return "not_implemented"
    if status == 401:
        return "unauthenticated"
    if status == 403:
        return "forbidden"
    if status == 501:
        return "not_implemented"
    return "error"


class ObservabilityMiddleware:
    """Request logging, metrics, and trace emission without breaking SSE streams."""

    def __init__(self, app: ASGIApp) -> None:
        self.app = app
        _vlog.v1("Initialized observability middleware")

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return

        method = scope.get("method", "GET")
        path = scope.get("path", "")
        _vlog.v0("Handling HTTP request", method=method, path=path)

        request_id = _header(scope, b"x-request-id") or str(uuid.uuid4())
        started = time.monotonic()
        state = scope.setdefault("state", {})
        state["request_id"] = request_id

        request_body_text: str | None = None
        if method in ("POST", "PUT", "PATCH"):
            body = await _read_body(receive)
            request_body_text = _trace_request_body(body)
            receive = _replay_receive(body, receive)
            parsed_request = _parse_json_body(body)
            if parsed_request is not None:
                log_request_v2(
                    _vlog,
                    "Received HTTP",
                    parsed_request,
                    request_id=request_id,
                    method=method,
                    path=path,
                )
            elif body:
                _vlog.v2(
                    "Received HTTP request body",
                    request_id=request_id,
                    method=method,
                    path=path,
                    body_bytes=len(body),
                )

        status_code = 500
        response_chunks: list[bytes] = []
        streaming_response = False

        async def send_wrapper(message: Message) -> None:
            nonlocal status_code, streaming_response
            if message["type"] == "http.response.start":
                status_code = message["status"]
                headers = list(message.get("headers", []))
                headers.append((b"x-request-id", request_id.encode()))
                message = {**message, "headers": headers}
            elif message["type"] == "http.response.body":
                chunk = message.get("body", b"")
                if chunk:
                    response_chunks.append(chunk)
                streaming_response = streaming_response or bool(message.get("more_body"))
            await send(message)

        await self.app(scope, receive, send_wrapper)

        latency_ms = (time.monotonic() - started) * 1000.0
        record_request(method, path, status_code)

        error_code: str | None = None
        response_body_text: str | None = None
        if response_chunks:
            body_bytes = b"".join(response_chunks)
            parsed_response = _parse_json_body(body_bytes)
            if parsed_response is not None:
                log_response_v2(
                    _vlog,
                    "Sending HTTP",
                    parsed_response,
                    request_id=request_id,
                    method=method,
                    path=path,
                    status_code=status_code,
                    streaming_response=streaming_response,
                )
            elif streaming_response and body_bytes:
                _vlog.v2(
                    "Sending HTTP streaming response",
                    request_id=request_id,
                    method=method,
                    path=path,
                    status_code=status_code,
                    response_bytes=len(body_bytes),
                )
            if not streaming_response:
                try:
                    parsed_body = json.loads(body_bytes)
                    response_body_text = body_text_for_trace(parsed_body)
                    if status_code >= 400 and isinstance(parsed_body, dict):
                        err = parsed_body.get("error")
                        if isinstance(err, dict):
                            error_code = err.get("code")
                except (json.JSONDecodeError, TypeError):
                    response_body_text = body_text_for_trace(body_bytes)

        outcome = _request_outcome(status_code, error_code)
        if status_code >= 400:
            _vlog.v0(
                "HTTP request returned error response",
                request_id=request_id,
                status_code=status_code,
                error_code=error_code,
            )
        _vlog.v1(
            "HTTP request completed",
            request_id=request_id,
            status_code=status_code,
            outcome=outcome,
            latency_ms=round(latency_ms, 2),
            streaming_response=streaming_response,
        )
        log_record(
            request_id=request_id,
            endpoint=path,
            outcome=outcome,
            caller_staff_id=state.get("caller_staff_id"),
            error_code=error_code,
            latency_ms=latency_ms,
        )

        app = scope.get("app")
        trace_bus: TraceBus | None = getattr(app.state, "trace_bus", None) if app else None
        if trace_bus is not None and should_emit_client_trace(path):
            response_summary = summarize_body(response_body_text) if response_body_text else None
            request_summary = summarize_body(request_body_text) if request_body_text else None
            await emit_client_trace(
                trace_bus,
                direction="client_to_gateway",
                method=method,
                path=path,
                status_code=status_code,
                latency_ms=latency_ms,
                request_id=request_id,
                kind="api",
                request_summary=request_summary,
                request_body=request_body_text,
            )
            await emit_client_trace(
                trace_bus,
                direction="gateway_to_client",
                method=method,
                path=path,
                status_code=status_code,
                latency_ms=latency_ms,
                request_id=request_id,
                kind="api",
                response_summary=response_summary,
                response_body=response_body_text,
            )
