"""Read-only runner probe endpoints for the control plane."""

from __future__ import annotations

import time
from typing import Annotated, Any

import httpx
from ai_common.verbose_logging import get_logger, log_request_v2, log_response_v2
from fastapi import APIRouter, Depends, Request
from fastapi.responses import JSONResponse

from gateway.api.errors import ErrorCode, error_response
from gateway.auth.dependencies import require_ai_access
from gateway.auth.jwt_validator import CallerIdentity
from gateway.obs.trace_bus import TraceBus
from gateway.obs.trace_helpers import body_text_for_trace, summarize_body
from gateway.routing.registry import RunnerRegistry
from gateway.runners.openai_client import POLL_TIMEOUT_S

router = APIRouter(prefix="/v1/runners", tags=["runners"])

vlog = get_logger(__name__)


def _registry(request: Request) -> RunnerRegistry:
    return request.app.state.registry


@router.get("/{runner_id}/models")
async def get_runner_models(
    runner_id: str,
    request: Request,
    _caller: Annotated[CallerIdentity, Depends(require_ai_access)],
) -> JSONResponse:
    """Proxy GET /v1/models to a configured runner (dashboard / operators only).

    Clients must not reach runners directly; this route lets the control plane
    inspect the same discovery response the health poller uses.
    """
    vlog.v0("Proxying runner models request", runner_id=runner_id)
    registry = _registry(request)
    entry = registry.get(runner_id)
    request_id = getattr(request.state, "request_id", "unknown")
    log_request_v2(
        vlog,
        "Proxying runner models",
        {"runner_id": runner_id, "method": "GET", "path": "/v1/models"},
        request_id=request_id,
        runner_id=runner_id,
    )

    if entry is None:
        vlog.v0("Runner models request for unknown runner", runner_id=runner_id, request_id=request_id)
        return error_response(
            ErrorCode.BAD_REQUEST,
            f"Unknown runner: {runner_id}",
            request_id,
        )

    url = entry.base_url.rstrip("/") + "/v1/models"
    started = time.perf_counter()
    trace_bus: TraceBus | None = getattr(request.app.state, "trace_bus", None)

    if trace_bus is not None:
        await trace_bus.emit(
            direction="gateway_to_runner",
            method="GET",
            path="/v1/models",
            kind="proxy",
            runner_id=runner_id,
            request_id=request_id,
            request_summary="dashboard proxy",
        )

    try:
        async with httpx.AsyncClient() as client:
            response = await client.get(url, timeout=POLL_TIMEOUT_S)
        latency_ms = (time.perf_counter() - started) * 1000.0

        content_type = response.headers.get("content-type", "")
        body: Any = response.json() if "application/json" in content_type else response.text

        if trace_bus is not None:
            await trace_bus.emit(
                direction="runner_to_gateway",
                method="GET",
                path="/v1/models",
                kind="proxy",
                runner_id=runner_id,
                status_code=response.status_code,
                latency_ms=latency_ms,
                request_id=request_id,
                response_summary=summarize_body(body),
                response_body=body_text_for_trace(body),
            )

        envelope = {
            "runner_id": runner_id,
            "upstream": {
                "method": "GET",
                "path": "/v1/models",
                "base_url": entry.base_url,
            },
            "poll": {
                "latency_ms": round(latency_ms, 2),
                "http_status": response.status_code,
            },
            "body": body,
        }
        log_response_v2(
            vlog,
            "Runner models proxy",
            envelope,
            request_id=request_id,
            runner_id=runner_id,
            http_status=response.status_code,
        )
        vlog.v1(
            "Runner models request completed",
            runner_id=runner_id,
            http_status=response.status_code,
            latency_ms=round(latency_ms, 2),
        )
        return JSONResponse(status_code=response.status_code, content=envelope)
    except httpx.TimeoutException:
        latency_ms = (time.perf_counter() - started) * 1000.0
        vlog.v0(
            "Runner models request timed out",
            runner_id=runner_id,
            request_id=request_id,
            latency_ms=round(latency_ms, 2),
        )
        if trace_bus is not None:
            await trace_bus.emit(
                direction="runner_to_gateway",
                method="GET",
                path="/v1/models",
                kind="proxy",
                runner_id=runner_id,
                status_code=504,
                latency_ms=latency_ms,
                request_id=request_id,
                response_summary="timeout",
            )
        return error_response(
            ErrorCode.AI_TIMEOUT,
            f"Runner {runner_id} did not respond to /v1/models within {POLL_TIMEOUT_S}s "
            f"(latency {latency_ms:.1f} ms)",
            request_id,
        )
    except httpx.HTTPError as exc:
        vlog.v0(
            "Runner models request HTTP error",
            runner_id=runner_id,
            request_id=request_id,
            error=str(exc),
        )
        if trace_bus is not None:
            latency_ms = (time.perf_counter() - started) * 1000.0
            await trace_bus.emit(
                direction="runner_to_gateway",
                method="GET",
                path="/v1/models",
                kind="proxy",
                runner_id=runner_id,
                status_code=503,
                latency_ms=latency_ms,
                request_id=request_id,
                response_summary=summarize_body(str(exc)),
            )
        return error_response(
            ErrorCode.AI_NO_CAPACITY,
            f"Runner {runner_id} unreachable at {entry.base_url}: {exc}",
            request_id,
        )
