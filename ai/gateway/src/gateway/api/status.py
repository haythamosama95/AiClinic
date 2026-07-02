"""Read-only control-plane status snapshot for the dashboard."""

from __future__ import annotations

import time
from datetime import datetime
from typing import Any

from fastapi import APIRouter, Request
from fastapi.responses import JSONResponse

from gateway.config.settings import GatewayConfig
from gateway.routing.registry import LoadedModel, RunnerRegistry, RunnerRegistryEntry

router = APIRouter(prefix="/v1", tags=["status"])

_GATEWAY_VERSION = "0.1.0"
_PHASE_ACTIVE = 3


def _serialize_datetime(value: datetime | None) -> str | None:
    if value is None:
        return None
    return value.isoformat()


def _serialize_loaded_model(model: LoadedModel | None) -> dict[str, Any] | None:
    if model is None:
        return None
    return {
        "name": model.name,
        "digest": model.digest,
        "context_tokens": model.context_tokens,
        "features": list(model.features),
    }


def _serialize_runner(entry: RunnerRegistryEntry) -> dict[str, Any]:
    return {
        "id": entry.id,
        "base_url": entry.base_url,
        "status": entry.status.value,
        "last_seen_at": _serialize_datetime(entry.last_seen_at),
        "last_latency_ms": entry.last_latency_ms,
        "avg_latency_ms": entry.avg_latency_ms,
        "consecutive_failures": entry.consecutive_failures,
        "in_flight": entry.in_flight,
        "declared_capabilities": list(entry.declared_capabilities),
        "loaded_model": _serialize_loaded_model(entry.loaded_model),
    }


def _config_safe(cfg: GatewayConfig) -> dict[str, Any]:
    return {
        "health_poll_interval_s": cfg.health_poll_interval_s,
        "unreachable_after_failures": cfg.unreachable_after_failures,
        "allowed_origins": list(cfg.allowed_origins),
        "streaming_enabled": cfg.streaming_enabled,
        "enable_multi_command_plans": cfg.enable_multi_command_plans,
        "enable_push_registration": cfg.enable_push_registration,
        "log_verbatim": cfg.log_verbatim,
    }


def _endpoint_catalog(*, dashboard_mounted: bool) -> list[dict[str, Any]]:
    return [
        {"path": "/health", "method": "GET", "phase": 2, "available": True},
        {"path": "/metrics", "method": "GET", "phase": 2, "available": True},
        {"path": "/ready", "method": "GET", "phase": 3, "available": True},
        {"path": "/v1/status", "method": "GET", "phase": 3, "available": True},
        {"path": "/dashboard", "method": "GET", "phase": 3, "available": dashboard_mounted},
        {"path": "/v1/capabilities", "method": "GET", "phase": 5, "available": False},
        {"path": "/v1/ai/generate", "method": "POST", "phase": 5, "available": False},
    ]


@router.get("/status")
async def get_status(request: Request) -> JSONResponse:
    """Safe JSON snapshot of gateway health, config, runners, and endpoint catalog."""
    cfg: GatewayConfig = request.app.state.config
    registry: RunnerRegistry = request.app.state.registry
    started = getattr(request.app.state, "started_monotonic", None)
    uptime_s = int(time.monotonic() - started) if started is not None else 0
    dashboard_mounted = bool(getattr(request.app.state, "dashboard_mounted", False))

    body = {
        "gateway": {
            "version": _GATEWAY_VERSION,
            "ready": registry.ready,
            "phase_active": _PHASE_ACTIVE,
            "uptime_s": uptime_s,
        },
        "config_safe": _config_safe(cfg),
        "runners": [_serialize_runner(entry) for entry in registry.snapshot()],
        "endpoints": _endpoint_catalog(dashboard_mounted=dashboard_mounted),
    }
    return JSONResponse(body)
