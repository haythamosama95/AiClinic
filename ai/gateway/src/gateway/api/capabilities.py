"""Capabilities report endpoint — mirrors the live runner registry."""

from __future__ import annotations

from typing import Annotated, Any

from fastapi import APIRouter, Depends, Request
from fastapi.responses import JSONResponse

from gateway.auth.dependencies import require_ai_access
from gateway.auth.jwt_validator import CallerIdentity
from gateway.agents.scheduling import SCHEDULING_COMMANDS
from gateway.config.settings import GatewayConfig
from gateway.routing.registry import RunnerRegistry, RunnerRegistryEntry

router = APIRouter(prefix="/v1", tags=["capabilities"])

SCHEMA_VERSION = "1.0"
SCHEDULING_TASKS: list[str] = ["command"]


def _runner_capability(entry: RunnerRegistryEntry) -> dict[str, Any]:
    loaded = entry.loaded_model
    return {
        "id": entry.id,
        "status": entry.status.value,
        "model": loaded.name if loaded is not None else None,
        "digest": loaded.digest if loaded is not None else None,
        "features": list(loaded.features) if loaded is not None else [],
        "context_tokens": loaded.context_tokens if loaded is not None else None,
    }


def build_capabilities_report(
    registry: RunnerRegistry,
    config: GatewayConfig,
) -> dict[str, Any]:
    """Build the aggregate capabilities snapshot from the live registry."""
    return {
        "schema_version": SCHEMA_VERSION,
        "streaming": config.streaming_enabled,
        "tasks": list(SCHEDULING_TASKS),
        "commands": list(SCHEDULING_COMMANDS),
        "runners": [_runner_capability(entry) for entry in registry.snapshot()],
    }


@router.get("/capabilities")
async def get_capabilities(
    request: Request,
    _caller: Annotated[CallerIdentity, Depends(require_ai_access)],
) -> JSONResponse:
    """Aggregate AI-layer capability snapshot mirroring the live registry."""
    registry: RunnerRegistry = request.app.state.registry
    config: GatewayConfig = request.app.state.config
    return JSONResponse(build_capabilities_report(registry, config))
