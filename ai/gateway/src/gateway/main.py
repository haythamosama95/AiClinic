"""ASGI application bootstrap for the AI Gateway."""

from __future__ import annotations

import uuid
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from starlette.responses import JSONResponse

from gateway.api.errors import install_exception_handlers
from gateway.api.metrics import router as metrics_router
from gateway.config.settings import GatewayConfig, load_config
from gateway.obs import logging as obs_logging
from gateway.obs.metrics import record_request
from gateway.routing.health_poller import HealthPoller

_config: GatewayConfig | None = None
_poller: HealthPoller | None = None


def get_config() -> GatewayConfig:
    if _config is None:
        raise RuntimeError("Gateway not initialized")
    return _config


def get_poller() -> HealthPoller | None:
    return _poller


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncIterator[None]:
    global _poller
    _poller = HealthPoller(app.state.config)
    await _poller.start()
    yield
    if _poller is not None:
        await _poller.stop()
        _poller = None


def create_app(config: GatewayConfig | None = None) -> FastAPI:
    """Factory for the FastAPI application (used by tests and production)."""
    global _config
    cfg = config or load_config()
    _config = cfg

    obs_logging.configure_logging(cfg.log_dir, cfg.log_verbatim)

    app = FastAPI(title="AI Gateway", version="0.1.0", lifespan=lifespan)
    app.state.config = cfg

    install_exception_handlers(app)

    app.add_middleware(
        CORSMiddleware,
        allow_origins=cfg.allowed_origins,
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )

    @app.middleware("http")
    async def request_id_middleware(request: Request, call_next):
        request_id = request.headers.get("X-Request-ID", str(uuid.uuid4()))
        request.state.request_id = request_id
        response = await call_next(request)
        response.headers["X-Request-ID"] = request_id
        record_request(request.method, request.url.path, response.status_code)
        return response

    @app.get("/health")
    async def health() -> JSONResponse:
        return JSONResponse({"status": "ok"})

    app.include_router(metrics_router)

    return app


def run() -> None:
    import uvicorn

    cfg = load_config()
    uvicorn.run(create_app(cfg), host="0.0.0.0", port=cfg.port, reload=False)
