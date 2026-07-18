"""Generate contract tests — POST /v1/ai/generate validates body and returns 501 skeleton."""

from __future__ import annotations

from typing import Any

import httpx
import pytest
import respx
from httpx import ASGITransport

from gateway.config.settings import GatewayConfig, RunnerConfig
from gateway.main import create_app
from gateway.routing.lifecycle import RunnerStatus
from gateway.routing.registry import LoadedModel
from tests.fixtures.jwt_tokens import make_hs256_token

TEST_SECRET = "generate-stub-test-secret"
GENERATE_PATH = "/v1/ai/generate"
VALID_PAYLOAD = {"task": "command", "prompt": "book Ahmed with Dr Ali tomorrow 5pm"}

RUNNER_A_URL = "http://runner-a.test:11434"
RUNNER_B_URL = "http://runner-b.test:11434"


def _assert_not_implemented_envelope(body: dict[str, Any]) -> None:
    assert "error" in body
    err = body["error"]
    assert err["code"] == "not_implemented"
    assert isinstance(err["message"], str) and err["message"]
    assert isinstance(err["request_id"], str) and err["request_id"]


def _assert_bad_request_envelope(body: dict[str, Any]) -> None:
    assert "error" in body
    err = body["error"]
    assert err["code"] == "bad_request"
    assert isinstance(err["message"], str) and err["message"]
    assert isinstance(err["request_id"], str) and err["request_id"]


@pytest.fixture
async def generate_client():
    config = GatewayConfig(
        jwt_secret=TEST_SECRET,
        log_dir="/tmp/gateway-test-logs",
        runners=[
            RunnerConfig(id="runner-a", base_url=RUNNER_A_URL),
            RunnerConfig(id="runner-b", base_url=RUNNER_B_URL),
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
async def test_generate_returns_501_not_implemented(generate_client) -> None:
    client, _app = generate_client
    response = await client.post(GENERATE_PATH, json=VALID_PAYLOAD)
    assert response.status_code == 501
    _assert_not_implemented_envelope(response.json())
    assert response.headers.get("X-Request-ID")


@pytest.mark.asyncio
@pytest.mark.parametrize(
    "payload",
    [
        {"task": "command", "prompt": "Summarize visit"},
        {"task": "command", "prompt": "test", "options": {"stream": True}},
        {
            "task": "command",
            "prompt": "with context",
            "context": {"branch_id": "550e8400-e29b-41d4-a716-446655440000"},
        },
    ],
)
async def test_generate_valid_body_returns_501(generate_client, payload) -> None:
    client, _app = generate_client
    response = await client.post(GENERATE_PATH, json=payload)
    assert response.status_code == 501
    _assert_not_implemented_envelope(response.json())


@pytest.mark.asyncio
@pytest.mark.parametrize(
    "payload",
    [
        {},
        {"task": "draft_note"},
        {"task": "command"},
        {"prompt": "missing task"},
        {"task": "command", "prompt": ""},
        {"task": "command", "prompt": "x", "turn": -1},
    ],
)
async def test_generate_invalid_body_returns_400(generate_client, payload) -> None:
    client, _app = generate_client
    response = await client.post(GENERATE_PATH, json=payload)
    assert response.status_code == 400
    _assert_bad_request_envelope(response.json())


@pytest.mark.asyncio
@respx.mock
async def test_generate_performs_zero_inference(generate_client) -> None:
    """Skeleton must not call runners — no /v1/models, /v1/chat/completions, or /health."""
    client, app = generate_client
    app.state.registry.update_entry(
        "runner-a",
        status=RunnerStatus.READY,
        loaded_model=LoadedModel(
            name="qwen3:4b",
            digest="sha256:stub-test",
            context_tokens=8192,
            features=["json_grammar"],
        ),
    )

    models_route = respx.get(f"{RUNNER_A_URL}/v1/models").mock(
        return_value=httpx.Response(200, json={"object": "list", "data": []})
    )
    chat_route = respx.post(f"{RUNNER_A_URL}/v1/chat/completions").mock(
        return_value=httpx.Response(200, json={"choices": []})
    )
    health_route = respx.get(f"{RUNNER_A_URL}/health").mock(
        return_value=httpx.Response(200, json={"status": "ok"})
    )
    runner_b_models = respx.get(f"{RUNNER_B_URL}/v1/models").mock(
        return_value=httpx.Response(200, json={"object": "list", "data": []})
    )

    response = await client.post(
        GENERATE_PATH,
        json={"task": "command", "prompt": "must not reach runner"},
    )

    assert response.status_code == 501
    _assert_not_implemented_envelope(response.json())
    assert models_route.call_count == 0
    assert chat_route.call_count == 0
    assert health_route.call_count == 0
    assert runner_b_models.call_count == 0


@pytest.mark.asyncio
async def test_generate_requires_auth(generate_client) -> None:
    client, _app = generate_client
    transport = client._transport
    async with httpx.AsyncClient(transport=transport, base_url="http://test") as unauthed:
        response = await unauthed.post(GENERATE_PATH, json=VALID_PAYLOAD)
    assert response.status_code == 401
    assert response.json()["error"]["code"] == "unauthenticated"
