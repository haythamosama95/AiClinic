"""Liveness and readiness endpoints."""

from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Depends, Request
from fastapi.responses import JSONResponse

from gateway.api.errors import ErrorCode, error_response
from gateway.auth.dependencies import require_ai_access
from gateway.auth.jwt_validator import CallerIdentity
from gateway.routing.registry import RunnerRegistry

router = APIRouter(tags=["health"])


def _registry(request: Request) -> RunnerRegistry:
    return request.app.state.registry


@router.get("/health")
async def health(request: Request) -> JSONResponse:
    """Unauthenticated liveness — 200 when accepting work, 503 during graceful shutdown."""
    coordinator = getattr(request.app.state, "shutdown_coordinator", None)
    if coordinator is not None and coordinator.shutting_down:
        return JSONResponse(status_code=503, content={"status": "shutting_down"})
    return JSONResponse({"status": "ok"})


@router.get("/ready")
async def ready(
    request: Request,
    _caller: Annotated[CallerIdentity, Depends(require_ai_access)],
) -> JSONResponse:
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
