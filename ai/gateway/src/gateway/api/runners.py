"""Read-only runner probe endpoints for the control plane."""

from __future__ import annotations

import time
from typing import Annotated, Any

import httpx
from fastapi import APIRouter, Depends, Request
from fastapi.responses import JSONResponse

from gateway.api.errors import ErrorCode, error_response
from gateway.auth.dependencies import require_ai_access
from gateway.auth.jwt_validator import CallerIdentity
from gateway.routing.registry import RunnerRegistry
from gateway.runners.openai_client import POLL_TIMEOUT_S

router = APIRouter(prefix="/v1/runners", tags=["runners"])


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
    registry = _registry(request)
    entry = registry.get(runner_id)
    request_id = getattr(request.state, "request_id", "unknown")

    if entry is None:
        return error_response(
            ErrorCode.BAD_REQUEST,
            f"Unknown runner: {runner_id}",
            request_id,
        )

    url = entry.base_url.rstrip("/") + "/v1/models"
    started = time.perf_counter()

    try:
        async with httpx.AsyncClient() as client:
            response = await client.get(url, timeout=POLL_TIMEOUT_S)
        latency_ms = (time.perf_counter() - started) * 1000.0

        content_type = response.headers.get("content-type", "")
        body: Any = response.json() if "application/json" in content_type else response.text

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
        return JSONResponse(status_code=response.status_code, content=envelope)
    except httpx.TimeoutException:
        latency_ms = (time.perf_counter() - started) * 1000.0
        return error_response(
            ErrorCode.AI_TIMEOUT,
            f"Runner {runner_id} did not respond to /v1/models within {POLL_TIMEOUT_S}s "
            f"(latency {latency_ms:.1f} ms)",
            request_id,
        )
    except httpx.HTTPError as exc:
        return error_response(
            ErrorCode.AI_NO_CAPACITY,
            f"Runner {runner_id} unreachable at {entry.base_url}: {exc}",
            request_id,
        )
