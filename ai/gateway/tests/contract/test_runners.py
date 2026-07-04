"""Runner probe endpoint contract tests."""

from __future__ import annotations

import httpx
import pytest
import respx
from httpx import ASGITransport

from gateway.config.settings import GatewayConfig, RunnerConfig
from gateway.main import create_app
from tests.fixtures.jwt_tokens import make_hs256_token

TEST_SECRET = "test-secret"

MODELS_PAYLOAD = {
    "object": "list",
    "data": [
        {
            "id": "qwen3:4b",
            "object": "model",
            "digest": "sha256:abc123",
            "context_length": 8192,
        }
    ],
}


@pytest.fixture
async def runners_client():
    config = GatewayConfig(
        jwt_secret=TEST_SECRET,
        log_dir="/tmp/gateway-test-logs",
        runners=[
            RunnerConfig(
                id="runner-a",
                base_url="http://127.0.0.1:11434",
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
            yield client


@pytest.mark.asyncio
async def test_runner_models_unknown_runner(runners_client) -> None:
    response = await runners_client.get("/v1/runners/missing/models")
    assert response.status_code == 400
    body = response.json()
    assert body["error"]["code"] == "bad_request"


@pytest.mark.asyncio
@respx.mock
async def test_runner_models_proxies_upstream(runners_client) -> None:
    respx.get("http://127.0.0.1:11434/v1/models").mock(
        return_value=httpx.Response(200, json=MODELS_PAYLOAD)
    )

    response = await runners_client.get("/v1/runners/runner-a/models")
    assert response.status_code == 200
    body = response.json()
    assert body["runner_id"] == "runner-a"
    assert body["upstream"]["path"] == "/v1/models"
    assert body["poll"]["http_status"] == 200
    assert isinstance(body["poll"]["latency_ms"], int | float)
    assert body["body"] == MODELS_PAYLOAD


@pytest.mark.asyncio
@respx.mock
async def test_runner_models_timeout(runners_client) -> None:
    route = respx.get("http://127.0.0.1:11434/v1/models")
    route.mock(side_effect=httpx.TimeoutException("timed out"))

    response = await runners_client.get("/v1/runners/runner-a/models")
    assert response.status_code == 504
    body = response.json()
    assert body["error"]["code"] == "ai_timeout"


@pytest.mark.asyncio
async def test_status_catalog_includes_runner_models(runners_client) -> None:
    response = await runners_client.get("/v1/status")
    body = response.json()
    paths = {entry["path"] for entry in body["endpoints"]}
    assert "/v1/runners/runner-a/models" in paths
