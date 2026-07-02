"""Liveness and readiness endpoints."""

from __future__ import annotations

from fastapi import APIRouter, Request
from fastapi.responses import JSONResponse

from gateway.api.errors import ErrorCode, error_response
from gateway.routing.registry import RunnerRegistry

router = APIRouter(tags=["health"])


def _registry(request: Request) -> RunnerRegistry:
    return request.app.state.registry


@router.get("/health")
async def health() -> JSONResponse:
    """Unauthenticated liveness — always 200 when the Gateway process is up."""
    return JSONResponse({"status": "ok"})


@router.get("/ready")
async def ready(request: Request) -> JSONResponse:
    """Readiness — 200 only when at least one runner is READY."""
    registry = _registry(request)
    if registry.ready:
        return JSONResponse({"status": "ready"})
    request_id = getattr(request.state, "request_id", "unknown")
    return error_response(
        ErrorCode.AI_NO_CAPACITY,
        "No healthy model runners available",
        request_id,
    )
