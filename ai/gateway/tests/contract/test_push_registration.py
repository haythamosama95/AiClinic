"""Contract tests for optional push-based runner registration (FR-030)."""

from __future__ import annotations

import httpx
import pytest
from httpx import ASGITransport

from gateway.api.internal_runners import INTERNAL_SECRET_HEADER
from gateway.config.settings import GatewayConfig
from gateway.main import create_app
from gateway.routing.lifecycle import RunnerStatus

INTERNAL_SECRET = "push-test-internal-secret"


def _push_config(*, enabled: bool = True) -> GatewayConfig:
    return GatewayConfig(
        jwt_secret="test-secret",
        log_dir="/tmp/gateway-test-logs",
        allowed_origins=["http://localhost:3000"],
        enable_push_registration=enabled,
        internal_shared_secret=INTERNAL_SECRET if enabled else None,
        runners=[],
    )


@pytest.fixture
async def push_env():
    app = create_app(_push_config())
    async with app.router.lifespan_context(app):
        transport = ASGITransport(app=app)
        async with httpx.AsyncClient(transport=transport, base_url="http://test") as client:
            yield app, client


@pytest.fixture
async def push_disabled_client():
    app = create_app(_push_config(enabled=False))
    async with app.router.lifespan_context(app):
        transport = ASGITransport(app=app)
        async with httpx.AsyncClient(transport=transport, base_url="http://test") as client:
            yield client


def _internal_headers(**extra: str) -> dict[str, str]:
    headers = {INTERNAL_SECRET_HEADER: INTERNAL_SECRET}
    headers.update(extra)
    return headers


REGISTER_BODY = {
    "id": "push-runner",
    "base_url": "http://127.0.0.1:11435",
    "capabilities": ["json_grammar"],
    "models": [
        {
            "name": "qwen3:4b",
            "source": "qwen3:4b",
            "digest": "sha256:push-test",
            "context_tokens": 8192,
        }
    ],
}


@pytest.mark.asyncio
async def test_push_endpoints_absent_when_disabled(push_disabled_client) -> None:
    cfg = GatewayConfig(
        jwt_secret="test-secret",
        log_dir="/tmp/gateway-test-logs",
        enable_push_registration=False,
        runners=[],
    )
    app = create_app(cfg)
    mounted_paths = {getattr(route, "path", None) for route in app.routes}
    assert "/internal/runners/register" not in mounted_paths
    assert "/internal/runners/heartbeat" not in mounted_paths

    response = await push_disabled_client.post(
        "/internal/runners/register",
        json=REGISTER_BODY,
        headers=_internal_headers(),
    )
    assert response.status_code == 400
    assert response.json()["error"]["message"] == "Not Found"


@pytest.mark.asyncio
async def test_register_rejects_missing_secret(push_env) -> None:
    _app, client = push_env
    response = await client.post("/internal/runners/register", json=REGISTER_BODY)
    assert response.status_code == 401
    assert response.json()["error"]["code"] == "unauthenticated"


@pytest.mark.asyncio
async def test_register_rejects_wrong_secret(push_env) -> None:
    _app, client = push_env
    response = await client.post(
        "/internal/runners/register",
        json=REGISTER_BODY,
        headers={INTERNAL_SECRET_HEADER: "wrong-secret"},
    )
    assert response.status_code == 401


@pytest.mark.asyncio
async def test_register_rejects_client_origin(push_env) -> None:
    _app, client = push_env
    response = await client.post(
        "/internal/runners/register",
        json=REGISTER_BODY,
        headers=_internal_headers(Origin="http://localhost:3000"),
    )
    assert response.status_code == 403
    assert response.json()["error"]["code"] == "forbidden"


@pytest.mark.asyncio
async def test_register_and_heartbeat_update_registry(push_env) -> None:
    app, client = push_env
    register = await client.post(
        "/internal/runners/register",
        json=REGISTER_BODY,
        headers=_internal_headers(),
    )
    assert register.status_code == 200
    assert register.json() == {"registered": True, "id": "push-runner"}

    heartbeat = await client.post(
        "/internal/runners/heartbeat",
        json={
            "id": "push-runner",
            "status": "READY",
            "loaded_model": {
                "name": "qwen3:4b",
                "digest": "sha256:push-test",
                "context_tokens": 8192,
            },
        },
        headers=_internal_headers(),
    )
    assert heartbeat.status_code == 200
    assert heartbeat.json() == {"acknowledged": True, "id": "push-runner"}

    entry = app.state.registry.get("push-runner")
    assert entry is not None
    assert entry.status == RunnerStatus.READY
    assert entry.loaded_model is not None
    assert entry.loaded_model.name == "qwen3:4b"


@pytest.mark.asyncio
async def test_heartbeat_unknown_runner_returns_bad_request(push_env) -> None:
    _app, client = push_env
    response = await client.post(
        "/internal/runners/heartbeat",
        json={"id": "missing", "status": "READY"},
        headers=_internal_headers(),
    )
    assert response.status_code == 400
    assert response.json()["error"]["code"] == "bad_request"


@pytest.mark.asyncio
async def test_push_registration_does_not_require_jwt(push_env) -> None:
    """Internal endpoints use shared secret only — no Bearer JWT."""
    _app, client = push_env
    response = await client.post(
        "/internal/runners/register",
        json=REGISTER_BODY,
        headers=_internal_headers(),
    )
    assert response.status_code == 200
