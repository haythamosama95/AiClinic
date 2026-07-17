"""AI-internal push registration endpoints (config-gated, default off)."""

from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Depends, Request
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field

from gateway.api.errors import ErrorCode, raise_gateway_error
from gateway.config.settings import GatewayConfig, ModelDef
from gateway.routing.lifecycle import RunnerStatus
from gateway.routing.registry import LoadedModel, RunnerRegistry

INTERNAL_SECRET_HEADER = "X-Internal-Secret"

router = APIRouter(prefix="/internal/runners", tags=["internal"])


class RegisterRequest(BaseModel):
    id: str
    base_url: str
    capabilities: list[str] = Field(default_factory=list)
    models: list[ModelDef] = Field(default_factory=list)


class HeartbeatLoadedModel(BaseModel):
    name: str
    digest: str
    context_tokens: int | None = None
    features: list[str] = Field(default_factory=list)


class HeartbeatRequest(BaseModel):
    id: str
    status: RunnerStatus
    loaded_model: HeartbeatLoadedModel | None = None


def _registry(request: Request) -> RunnerRegistry:
    return request.app.state.registry


def _reject_client_origin(request: Request, cfg: GatewayConfig) -> None:
    origin = request.headers.get("Origin")
    if origin and origin in cfg.allowed_origins:
        raise_gateway_error(
            ErrorCode.FORBIDDEN,
            "Internal endpoints are not reachable from client origins",
            request,
        )


async def require_internal_auth(request: Request) -> GatewayConfig:
    """Verify push mode is enabled and the caller presents the internal secret."""
    cfg: GatewayConfig = request.app.state.config
    _reject_client_origin(request, cfg)

    secret = request.headers.get(INTERNAL_SECRET_HEADER)
    if not secret or secret != cfg.internal_shared_secret:
        raise_gateway_error(
            ErrorCode.UNAUTHENTICATED,
            "Invalid or missing internal shared secret",
            request,
        )
    return cfg


@router.post("/register")
async def register_runner(
    body: RegisterRequest,
    request: Request,
    _cfg: Annotated[GatewayConfig, Depends(require_internal_auth)],
) -> JSONResponse:
    """Register or update a runner in the dynamic registry (push mode)."""
    registry = _registry(request)
    registry.register_runner(
        body.id,
        body.base_url,
        body.capabilities,
        body.models,
    )
    return JSONResponse({"registered": True, "id": body.id})


@router.post("/heartbeat")
async def heartbeat_runner(
    body: HeartbeatRequest,
    request: Request,
    _cfg: Annotated[GatewayConfig, Depends(require_internal_auth)],
) -> JSONResponse:
    """Apply a push heartbeat for a registered runner."""
    registry = _registry(request)
    loaded = None
    if body.loaded_model is not None:
        loaded = LoadedModel(
            name=body.loaded_model.name,
            digest=body.loaded_model.digest,
            context_tokens=body.loaded_model.context_tokens,
            features=list(body.loaded_model.features),
        )
    if not registry.apply_heartbeat(body.id, body.status, loaded):
        raise_gateway_error(
            ErrorCode.BAD_REQUEST,
            f"Unknown runner: {body.id}",
            request,
        )
    return JSONResponse({"acknowledged": True, "id": body.id})
