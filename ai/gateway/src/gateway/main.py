"""ASGI application bootstrap for the AI Gateway."""

from __future__ import annotations

import asyncio
import os
import signal
import time
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager, suppress
from pathlib import Path

from ai_common.verbose_logging import configure as configure_verbose_logging
from ai_common.verbose_logging import get_logger
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
from gateway.middleware.observability import ObservabilityMiddleware
from gateway.obs import logging as obs_logging
from gateway.obs.trace_bus import TraceBus
from gateway.pipeline.cancel import log_cancelled
from gateway.pipeline.queue import GenerationQueue, create_generation_queue
from gateway.routing.health_poller import HealthPoller
from gateway.routing.registry import RunnerRegistry

_config: GatewayConfig | None = None
_poller: HealthPoller | None = None
_registry: RunnerRegistry | None = None
_role_map_reloader: RoleMapReloader | None = None
_generation_queue: GenerationQueue | None = None

_vlog = get_logger(__name__)


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


def get_generation_queue() -> GenerationQueue:
    if _generation_queue is None:
        raise RuntimeError("Gateway not initialized")
    return _generation_queue


async def _graceful_shutdown(generation_queue: GenerationQueue, grace_s: float) -> None:
    """Drain in-flight requests; reject queued; cancel stragglers after grace."""
    _vlog.v0("Beginning graceful shutdown", grace_s=grace_s)
    coordinator = generation_queue.shutdown
    if not coordinator.shutting_down:
        coordinator.begin_shutdown()

    rejected = await generation_queue.reject_queued_not_started()
    for entry in rejected:
        log_cancelled(
            request_id=entry.request_id,
            caller_staff_id=entry.caller_staff_id,
        )

    await generation_queue.drain_in_flight(grace_s)

    cancelled_ids = await generation_queue.cancel_stragglers_after_grace()
    for request_id in cancelled_ids:
        log_cancelled(request_id=request_id)
    _vlog.v0(
        "Graceful shutdown finished",
        rejected_count=len(rejected),
        cancelled_count=len(cancelled_ids),
    )


def _install_shutdown_signals(
    loop: asyncio.AbstractEventLoop,
    generation_queue: GenerationQueue,
    grace_s: float,
) -> None:
    """Register SIGTERM/SIGINT to begin graceful drain then exit the process.

    Uvicorn's own handlers are replaced by ``add_signal_handler``. Without an
    explicit process exit after drain, the server keeps serving ``/health`` while
    rejecting generation with ``503 ai_busy`` — ``start.sh`` then treats the
    zombie as healthy and skips restart.
    """
    _vlog.v0("Installing shutdown signal handlers", grace_s=grace_s)

    def _on_signal() -> None:
        async def _shutdown_and_exit() -> None:
            await _graceful_shutdown(generation_queue, grace_s)
            os._exit(0)

        asyncio.create_task(_shutdown_and_exit())

    for sig in (signal.SIGTERM, signal.SIGINT):
        with suppress(AttributeError, NotImplementedError, ValueError):
            loop.add_signal_handler(sig, _on_signal)
    _vlog.v1("Shutdown signal handlers registered", signals=["SIGTERM", "SIGINT"])


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
    global _poller, _role_map_reloader, _generation_queue
    _vlog.v0("Starting gateway application lifespan")
    app.state.jwt_validator = JwtValidator(app.state.config)
    app.state.role_map_store = RoleMapStore(dict(app.state.config.role_ai_access))
    role_map_path = _resolve_role_map_path(app.state.config)
    _role_map_reloader = RoleMapReloader(
        app.state.role_map_store,
        file_path=role_map_path,
        interval_s=60,
    )
    _role_map_reloader.start()

    _generation_queue = create_generation_queue(app.state.config)
    app.state.generation_queue = _generation_queue
    app.state.shutdown_coordinator = _generation_queue.shutdown

    loop = asyncio.get_running_loop()
    _install_shutdown_signals(
        loop,
        _generation_queue,
        float(app.state.config.shutdown_grace_s),
    )

    _poller = HealthPoller(
        app.state.config,
        app.state.registry,
        trace_bus=app.state.trace_bus,
    )
    await _poller.start()
    _vlog.v1("Gateway application lifespan started", runner_count=len(app.state.registry.runner_ids()))
    yield
    _vlog.v0("Shutting down gateway application")
    await _graceful_shutdown(
        _generation_queue,
        float(app.state.config.shutdown_grace_s),
    )
    if _poller is not None:
        await _poller.stop()
        _poller = None
    if _role_map_reloader is not None:
        _role_map_reloader.stop()
        _role_map_reloader = None
    _generation_queue = None
    _vlog.v0("Gateway application lifespan ended")


def create_app(config: GatewayConfig | None = None) -> FastAPI:
    """Factory for the FastAPI application (used by tests and production)."""
    global _config, _registry
    _vlog.v0("Creating gateway application")
    cfg = config or load_config()
    _config = cfg
    _registry = RunnerRegistry(cfg)

    obs_logging.configure_logging(
        cfg.log_dir,
        cfg.log_verbatim,
        log_verbatim_retention_hours=cfg.log_verbatim_retention_hours,
        development_profile=cfg.dashboard_auto_sign_in,
    )
    configure_verbose_logging(source="gateway")

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

    _vlog.v0(
        "Gateway application created",
        port=cfg.port,
        runner_count=len(cfg.runners),
        dashboard_mounted=dashboard_mounted,
    )
    return app


def run() -> None:
    import uvicorn

    _vlog.v0("Starting gateway server")
    cfg = load_config()
    uvicorn.run(create_app(cfg), host="0.0.0.0", port=cfg.port, reload=False)
