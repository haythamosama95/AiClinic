"""Stubbed AI generation endpoint — feature-detect only, no inference."""

from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Depends, Request
from fastapi.responses import JSONResponse

from gateway.api.errors import ErrorCode, error_response
from gateway.auth.dependencies import require_ai_access
from gateway.auth.jwt_validator import CallerIdentity

router = APIRouter(prefix="/v1", tags=["generate"])

NOT_IMPLEMENTED_MESSAGE = "AI generation is not available in this deployment phase."


@router.post("/ai/generate")
async def post_generate(
    request: Request,
    _caller: Annotated[CallerIdentity, Depends(require_ai_access)],
) -> JSONResponse:
    """Stub present for feature-detection; performs no inference."""
    request_id = getattr(request.state, "request_id", "unknown")
    return error_response(
        ErrorCode.NOT_IMPLEMENTED,
        NOT_IMPLEMENTED_MESSAGE,
        request_id,
    )
