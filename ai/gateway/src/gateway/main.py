"""ASGI application bootstrap for the AI Gateway."""

from __future__ import annotations

import os
import time
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles

from gateway.api.capabilities import router as capabilities_router
from gateway.api.dashboard_auth import router as dashboard_auth_router
from gateway.api.errors import install_exception_handlers
from gateway.api.generate import router as generate_router
from gateway.api.health import router as health_router
from gateway.api.internal_runners import router as internal_runners_router
from gateway.api.metrics import router as metrics_router
from gateway.api.runners import router as runners_router
from gateway.api.status import router as status_router
from gateway.api.trace import router as trace_router
from gateway.auth.jwt_validator import JwtValidator
from gateway.auth.role_map import RoleMapReloader, RoleMapStore
from gateway.config.settings import GatewayConfig, load_config
from gateway.obs import logging as obs_logging
from gateway.middleware.observability import ObservabilityMiddleware
from gateway.obs.trace_bus import TraceBus
from gateway.routing.health_poller import HealthPoller
from gateway.routing.registry import RunnerRegistry

_config: GatewayConfig | None = None
_poller: HealthPoller | None = None
_registry: RunnerRegistry | None = None
_role_map_reloader: RoleMapReloader | None = None


def get_config() -> GatewayConfig:
    if _config is None:
        raise RuntimeError("Gateway not initialized")
    return _config


def get_registry() -> RunnerRegistry:
    if _registry is None:
        raise RuntimeError("Gateway not initialized")
    return _registry


def get_poller() -> HealthPoller | None:
    return _poller


def _resolve_dashboard_dir(cfg: GatewayConfig) -> Path:
    if cfg.dashboard_dir:
        return Path(cfg.dashboard_dir)
    return Path(__file__).resolve().parents[3] / "dashboard"


def _resolve_role_map_path(cfg: GatewayConfig) -> Path | None:
    """Optional external role map file alongside gateway config."""
    config_path = _resolve_config_path(None)
    if config_path is not None:
        candidate = config_path.parent / "role_ai_access.yaml"
        if candidate.is_file():
            return candidate
    return None


def _resolve_config_path(path: str | None) -> Path | None:
    if path:
        return Path(path)
    env_path = os.environ.get("GATEWAY_CONFIG_PATH")
    if env_path:
        return Path(env_path)
    default = Path(__file__).resolve().parents[3] / "config" / "gateway.yaml"
    if default.is_file():
        return default
    return None


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncIterator[None]:
    global _poller, _role_map_reloader
    app.state.jwt_validator = JwtValidator(app.state.config)
    app.state.role_map_store = RoleMapStore(dict(app.state.config.role_ai_access))
    role_map_path = _resolve_role_map_path(app.state.config)
    _role_map_reloader = RoleMapReloader(
        app.state.role_map_store,
        file_path=role_map_path,
        interval_s=60,
    )
    _role_map_reloader.start()
    _poller = HealthPoller(
        app.state.config,
        app.state.registry,
        trace_bus=app.state.trace_bus,
    )
    await _poller.start()
    yield
    if _poller is not None:
        await _poller.stop()
        _poller = None
    if _role_map_reloader is not None:
        _role_map_reloader.stop()
        _role_map_reloader = None


def create_app(config: GatewayConfig | None = None) -> FastAPI:
    """Factory for the FastAPI application (used by tests and production)."""
    global _config, _registry
    cfg = config or load_config()
    _config = cfg
    _registry = RunnerRegistry(cfg)

    obs_logging.configure_logging(cfg.log_dir, cfg.log_verbatim)

    app = FastAPI(title="AI Gateway", version="0.1.0", lifespan=lifespan)
    app.state.config = cfg
    app.state.registry = _registry
    app.state.trace_bus = TraceBus(log_verbatim=cfg.log_verbatim)
    app.state.started_monotonic = time.monotonic()

    install_exception_handlers(app)

    app.add_middleware(
        CORSMiddleware,
        allow_origins=cfg.allowed_origins,
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )
    app.add_middleware(ObservabilityMiddleware)

    app.include_router(health_router)
    app.include_router(dashboard_auth_router)
    app.include_router(metrics_router)
    app.include_router(runners_router)
    app.include_router(status_router)
    app.include_router(capabilities_router)
    app.include_router(generate_router)
    app.include_router(trace_router)
    if cfg.enable_push_registration:
        app.include_router(internal_runners_router)

    dashboard_path = _resolve_dashboard_dir(cfg)
    dashboard_mounted = dashboard_path.is_dir()
    app.state.dashboard_mounted = dashboard_mounted
    if dashboard_mounted:
        app.mount(
            "/dashboard",
            StaticFiles(directory=str(dashboard_path), html=True),
            name="dashboard",
        )

    return app


def run() -> None:
    import uvicorn

    cfg = load_config()
    uvicorn.run(create_app(cfg), host="0.0.0.0", port=cfg.port, reload=False)
