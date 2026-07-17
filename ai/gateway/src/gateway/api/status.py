"""Read-only control-plane status snapshot for the dashboard."""

from __future__ import annotations

import time
from datetime import datetime
from typing import Annotated, Any

from fastapi import APIRouter, Depends, Request
from fastapi.responses import JSONResponse

from gateway.auth.dependencies import require_ai_access
from gateway.auth.jwt_validator import CallerIdentity
from gateway.config.settings import GatewayConfig
from gateway.routing.registry import LoadedModel, RunnerRegistry, RunnerRegistryEntry

router = APIRouter(prefix="/v1", tags=["status"])

_GATEWAY_VERSION = "0.1.0"
_PHASE_ACTIVE = 6


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


def _declared_models_for(cfg: GatewayConfig, runner_id: str) -> list[dict[str, Any]]:
    for runner in cfg.runners:
        if runner.id == runner_id:
            return [
                {
                    "name": model.name,
                    "digest": model.digest,
                    "context_tokens": model.context_tokens,
                    "capabilities": list(model.capabilities),
                }
                for model in runner.models
            ]
    return []


def _serialize_runner(entry: RunnerRegistryEntry, *, cfg: GatewayConfig) -> dict[str, Any]:
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
        "declared_models": _declared_models_for(cfg, entry.id),
        "loaded_model": _serialize_loaded_model(entry.loaded_model),
    }


def _config_safe(cfg: GatewayConfig) -> dict[str, Any]:
    return {
        "port": cfg.port,
        "health_poll_interval_s": cfg.health_poll_interval_s,
        "unreachable_after_failures": cfg.unreachable_after_failures,
        "allowed_origins": list(cfg.allowed_origins),
        "log_dir": cfg.log_dir,
        "streaming_enabled": cfg.streaming_enabled,
        "enable_multi_command_plans": cfg.enable_multi_command_plans,
        "enable_push_registration": cfg.enable_push_registration,
        "log_verbatim": cfg.log_verbatim,
    }


def _architecture(cfg: GatewayConfig) -> dict[str, Any]:
    runner_urls = [runner.base_url for runner in cfg.runners]
    return {
        "gateway": {
            "role": "client_facing",
            "default_port": cfg.port,
            "reachable_by": "clinic clients on the LAN",
        },
        "runners": {
            "role": "ai_internal",
            "default_base_url": "http://127.0.0.1:11434",
            "reachable_by": "gateway only — not client-routable",
            "configured_base_urls": runner_urls,
        },
    }


def _poller_summary(cfg: GatewayConfig) -> dict[str, Any]:
    interval = cfg.health_poll_interval_s
    failures = cfg.unreachable_after_failures
    return {
        "health_poll_interval_s": interval,
        "unreachable_after_failures": failures,
        "estimated_failover_s": interval * failures,
    }


def _endpoint_catalog(
    *,
    dashboard_mounted: bool,
    runner_ids: list[str],
    push_registration_enabled: bool = False,
) -> list[dict[str, Any]]:
    entries: list[dict[str, Any]] = [
        {"path": "/health", "method": "GET", "phase": 2, "available": True},
        {"path": "/metrics", "method": "GET", "phase": 2, "available": True},
        {"path": "/ready", "method": "GET", "phase": 3, "available": True},
        {"path": "/v1/status", "method": "GET", "phase": 3, "available": True},
        {"path": "/v1/dashboard/auth-config", "method": "GET", "phase": 4, "available": True},
        {"path": "/v1/dashboard/sign-in", "method": "POST", "phase": 4, "available": True},
        {"path": "/v1/dashboard/auto-sign-in", "method": "POST", "phase": 4, "available": True},
        {"path": "/dashboard", "method": "GET", "phase": 3, "available": dashboard_mounted},
    ]
    for runner_id in runner_ids:
        entries.append(
            {
                "path": f"/v1/runners/{runner_id}/models",
                "method": "GET",
                "phase": 3,
                "available": True,
                "runner_id": runner_id,
                "description": "Proxy GET /v1/models to runner (control plane)",
            }
        )
    entries.extend(
        [
            {"path": "/v1/capabilities", "method": "GET", "phase": 5, "available": True},
            {"path": "/v1/ai/generate", "method": "POST", "phase": 5, "available": True},
        ]
    )
    if push_registration_enabled:
        entries.extend(
            [
                {
                    "path": "/internal/runners/register",
                    "method": "POST",
                    "phase": 6,
                    "available": False,
                    "description": "AI-internal push registration (X-Internal-Secret)",
                },
                {
                    "path": "/internal/runners/heartbeat",
                    "method": "POST",
                    "phase": 6,
                    "available": False,
                    "description": "AI-internal push heartbeat (X-Internal-Secret)",
                },
            ]
        )
    return entries


@router.get("/status")
async def get_status(
    request: Request,
    _caller: Annotated[CallerIdentity, Depends(require_ai_access)],
) -> JSONResponse:
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
        "architecture": _architecture(cfg),
        "poller": _poller_summary(cfg),
        "config_safe": _config_safe(cfg),
        "runners": [_serialize_runner(entry, cfg=cfg) for entry in registry.snapshot()],
        "endpoints": _endpoint_catalog(
            dashboard_mounted=dashboard_mounted,
            runner_ids=registry.runner_ids(),
            push_registration_enabled=cfg.enable_push_registration,
        ),
    }
    return JSONResponse(body)
