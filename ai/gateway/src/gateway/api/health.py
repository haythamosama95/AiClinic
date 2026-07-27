"""Liveness and readiness endpoints."""

from __future__ import annotations

from typing import Annotated

from ai_common.verbose_logging import get_logger
from fastapi import APIRouter, Depends, Request
from fastapi.responses import JSONResponse

from gateway.api.errors import ErrorCode, error_response
from gateway.auth.dependencies import require_ai_access
from gateway.auth.jwt_validator import CallerIdentity
from gateway.routing.registry import RunnerRegistry

router = APIRouter(tags=["health"])

vlog = get_logger(__name__)


def _registry(request: Request) -> RunnerRegistry:
    return request.app.state.registry


@router.get("/health")
async def health(request: Request) -> JSONResponse:
    """Unauthenticated liveness — 200 when accepting work, 503 during graceful shutdown."""
    vlog.v0("Checking gateway liveness")
    coordinator = getattr(request.app.state, "shutdown_coordinator", None)
    if coordinator is not None and coordinator.shutting_down:
        vlog.v0("Liveness check: gateway is shutting down")
        return JSONResponse(status_code=503, content={"status": "shutting_down"})
    vlog.v1("Liveness check passed")
    return JSONResponse({"status": "ok"})


@router.get("/ready")
async def ready(
    request: Request,
    _caller: Annotated[CallerIdentity, Depends(require_ai_access)],
) -> JSONResponse:
    """Readiness — 200 only when at least one runner is READY."""
    vlog.v0("Checking gateway readiness")
    registry = _registry(request)
    if registry.ready:
        vlog.v1("Readiness check passed")
        return JSONResponse({"status": "ready"})
    request_id = getattr(request.state, "request_id", "unknown")
    vlog.v0("Readiness check failed: no healthy runners", request_id=request_id)
    return error_response(
        ErrorCode.AI_NO_CAPACITY,
        "No healthy model runners available",
        request_id,
    )
