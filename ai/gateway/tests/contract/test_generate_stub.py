"""Generate contract tests — POST /v1/ai/generate validation and non-streaming path."""

from __future__ import annotations

import json
from typing import Any

import httpx
import pytest
import respx
from httpx import ASGITransport

from gateway.config.settings import GatewayConfig, RunnerConfig
from gateway.main import create_app, get_poller
from gateway.routing.lifecycle import RunnerStatus
from gateway.routing.registry import LoadedModel
from tests.fixtures.fake_runner import ChatScriptMode, FakeRunner, envelope_for_mode
from tests.fixtures.jwt_tokens import make_hs256_token

TEST_SECRET = "generate-stub-test-secret"
GENERATE_PATH = "/v1/ai/generate"
VALID_PAYLOAD = {"task": "command", "prompt": "book Ahmed with Dr Ali tomorrow 5pm"}
MVP_CONTEXT = {"now": "2026-07-18T12:00:00+03:00"}

RUNNER_A_URL = "http://runner-a.test:11434"
RUNNER_B_URL = "http://runner-b.test:11434"
CHAT_URL = f"{RUNNER_A_URL}/api/chat"


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
        poller = get_poller()
        if poller is not None:
            await poller.stop()
        transport = ASGITransport(app=app)
        async with httpx.AsyncClient(
            transport=transport,
            base_url="http://test",
            headers=headers,
        ) as client:
            yield client, app


def _prime_runner(app) -> None:
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


@pytest.mark.asyncio
@respx.mock
async def test_generate_returns_200_for_command_non_streaming(generate_client) -> None:
    client, app = generate_client
    _prime_runner(app)
    envelope = envelope_for_mode(ChatScriptMode.VALID_CREATE, context=MVP_CONTEXT)
    respx.post(CHAT_URL).mock(
        return_value=httpx.Response(
            200,
            json={
                "model": "fake",
                "message": {"role": "assistant", "content": json.dumps(envelope)},
                "done": True,
                "prompt_eval_count": 10,
                "eval_count": 20,
            },
        )
    )

    response = await client.post(
        GENERATE_PATH,
        json={**VALID_PAYLOAD, "context": MVP_CONTEXT, "options": {"stream": False}},
    )
    assert response.status_code == 200
    body = response.json()
    assert body["command_type"] == "create_appointment"
    assert response.headers.get("X-Request-ID")


@pytest.mark.asyncio
@respx.mock
async def test_generate_streaming_returns_sse(generate_client) -> None:
    client, app = generate_client
    _prime_runner(app)
    fake = FakeRunner(base_url=RUNNER_A_URL)
    fake.script_chat_stream(ChatScriptMode.VALID_CREATE, context=MVP_CONTEXT)
    respx.post(CHAT_URL).mock(
        return_value=httpx.Response(
            200,
            content=fake.chat_completion_stream_body().encode(),
            headers={"Content-Type": "text/event-stream"},
        )
    )
    response = await client.post(
        GENERATE_PATH,
        json={**VALID_PAYLOAD, "context": MVP_CONTEXT, "options": {"stream": True}},
    )
    assert response.status_code == 200
    assert response.headers["content-type"].startswith("text/event-stream")
    assert "event: final" in response.text


@pytest.mark.asyncio
@pytest.mark.parametrize(
    "payload",
    [
        {"task": "command", "prompt": "Summarize visit", "options": {"stream": False}},
        {
            "task": "command",
            "prompt": "with context",
            "context": {"branch_id": "550e8400-e29b-41d4-a716-446655440000", **MVP_CONTEXT},
            "options": {"stream": False},
        },
    ],
)
@respx.mock
async def test_generate_valid_body_non_streaming_returns_200(generate_client, payload) -> None:
    client, app = generate_client
    _prime_runner(app)
    envelope = envelope_for_mode(ChatScriptMode.VALID_CREATE, context=MVP_CONTEXT)
    respx.post(CHAT_URL).mock(
        return_value=httpx.Response(
            200,
            json={
                "model": "fake",
                "message": {"role": "assistant", "content": json.dumps(envelope)},
                "done": True,
                "prompt_eval_count": 10,
                "eval_count": 20,
            },
        )
    )
    response = await client.post(GENERATE_PATH, json=payload)
    assert response.status_code == 200
    assert response.json()["task"] == "command"


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
async def test_generate_no_runner_returns_no_capacity(generate_client) -> None:
    """Without a READY runner, generation returns ai_no_capacity without off-LAN calls."""
    client, app = generate_client
    app.state.registry.update_entry("runner-a", status=RunnerStatus.UNREACHABLE)

    models_route = respx.get(f"{RUNNER_A_URL}/v1/models").mock(
        return_value=httpx.Response(200, json={"object": "list", "data": []})
    )
    chat_route = respx.post(CHAT_URL).mock(
        return_value=httpx.Response(200, json={"choices": []})
    )

    response = await client.post(
        GENERATE_PATH,
        json={**VALID_PAYLOAD, "context": MVP_CONTEXT, "options": {"stream": False}},
    )

    assert response.status_code == 503
    assert response.json()["error"]["code"] == "ai_no_capacity"
    assert chat_route.call_count == 0
    assert models_route.call_count == 0


@pytest.mark.asyncio
async def test_generate_requires_auth(generate_client) -> None:
    client, _app = generate_client
    transport = client._transport
    async with httpx.AsyncClient(transport=transport, base_url="http://test") as unauthed:
        response = await unauthed.post(GENERATE_PATH, json=VALID_PAYLOAD)
    assert response.status_code == 401
    assert response.json()["error"]["code"] == "unauthenticated"
