"""Liveness and readiness contract tests."""

from __future__ import annotations

import httpx
import pytest
import respx
from httpx import ASGITransport

from gateway.config.settings import GatewayConfig, RunnerConfig
from gateway.main import create_app, get_poller
from gateway.routing.lifecycle import RunnerStatus
from tests.fixtures.jwt_tokens import make_hs256_token

TEST_SECRET = "test-secret"


RUNNER_URL = "http://runner.test:11434"
RUNNER_MODELS = f"{RUNNER_URL}/v1/models"


@pytest.fixture
async def ready_client():
    config = GatewayConfig(
        jwt_secret=TEST_SECRET,
        log_dir="/tmp/gateway-test-logs",
        health_poll_interval_s=60,
        runners=[
            RunnerConfig(
                id="runner-a",
                base_url=RUNNER_URL,
            )
        ],
    )
    app = create_app(config)
    token = make_hs256_token(TEST_SECRET, staff_role="doctor")
    headers = {"Authorization": f"Bearer {token}"}
    async with app.router.lifespan_context(app):
        transport = ASGITransport(app=app)
        async with httpx.AsyncClient(
            transport=transport,
            base_url="http://test",
            headers=headers,
        ) as client:
            yield client, app


@pytest.mark.asyncio
async def test_health_always_returns_200(ready_client) -> None:
    client, _app = ready_client
    response = await client.get("/health")
    assert response.status_code == 200
    assert response.json()["status"] == "ok"


@pytest.mark.asyncio
@respx.mock
async def test_ready_returns_503_when_no_runner_is_ready(ready_client) -> None:
    client, app = ready_client
    respx.get(RUNNER_MODELS).mock(
        return_value=httpx.Response(503, json={"error": "loading"})
    )
    poller = get_poller()
    assert poller is not None
    await poller.stop()
    await poller.poll_once()

    response = await client.get("/ready")
    assert response.status_code == 503
    body = response.json()
    assert body["error"]["code"] == "ai_no_capacity"
    assert body["error"]["request_id"]
    assert app.state.registry.ready is False


@pytest.mark.asyncio
async def test_ready_returns_200_when_runner_is_ready(ready_client) -> None:
    client, app = ready_client
    app.state.registry.update_entry(
        "runner-a",
        status=RunnerStatus.READY,
    )
    response = await client.get("/ready")
    assert response.status_code == 200
    assert response.json()["status"] == "ready"


@pytest.mark.asyncio
@respx.mock
async def test_poller_flips_ready_after_model_load(ready_client) -> None:
    client, app = ready_client
    respx.get(RUNNER_MODELS).mock(
        return_value=httpx.Response(
            200,
            json={
                "object": "list",
                "data": [
                    {
                        "id": "qwen3:4b",
                        "object": "model",
                        "digest": "sha256:abc123",
                        "context_length": 8192,
                    }
                ],
            },
        )
    )

    not_ready = await client.get("/ready")
    assert not_ready.status_code == 503

    poller = get_poller()
    assert poller is not None
    await poller.poll_once()

    ready = await client.get("/ready")
    assert ready.status_code == 200
