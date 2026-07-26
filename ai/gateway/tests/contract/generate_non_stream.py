"""Non-streaming generate contract tests — scheduling command envelopes (US1)."""

from __future__ import annotations

import json
from datetime import datetime, timedelta
from typing import Any

import httpx
import jsonschema
import pytest
import respx
from httpx import ASGITransport

from gateway.agents.scheduling.schemas import build_envelope_schema
from gateway.config.settings import GatewayConfig, RunnerConfig
from gateway.main import create_app, get_poller
from gateway.routing.lifecycle import RunnerStatus
from gateway.routing.registry import LoadedModel
from tests.fixtures.fake_runner import (
    ChatScriptMode,
    FakeRunner,
    envelope_for_mode,
)
from tests.fixtures.jwt_tokens import make_hs256_token

TEST_SECRET = "generate-non-stream-secret"
GENERATE_PATH = "/v1/ai/generate"
RUNNER_URL = "http://runner-a.test:11434"
CHAT_URL = f"{RUNNER_URL}/api/chat"

ENVELOPE_SCHEMA = build_envelope_schema()
MVP_CONTEXT = {
    "now": "2026-07-18T12:00:00+03:00",
    "branch_name": "Main",
}


def _chat_response_from_envelope(envelope: dict[str, Any] | str) -> dict[str, Any]:
    content = envelope if isinstance(envelope, str) else json.dumps(envelope)
    return {
        "model": "fake",
        "message": {"role": "assistant", "content": content},
        "done": True,
        "prompt_eval_count": 100,
        "eval_count": 60,
    }


def _assert_envelope_contract(body: dict[str, Any]) -> None:
    jsonschema.validate(body, ENVELOPE_SCHEMA)
    assert body["schema_version"] == "1.0"
    assert body["task"] == "command"
    assert 0.0 <= body["confidence"] <= 1.0
    assert isinstance(body["display_summary"], str) and body["display_summary"]
    assert isinstance(body["params"], dict)
    assert isinstance(body["requires_resolution"], dict)
    assert isinstance(body["warnings"], list)
    assert isinstance(body["needs_clarification"], bool)

    for _field, directive in body["requires_resolution"].items():
        assert directive == "lookup_required"

    fabricated_id_fields = {"patient_id", "doctor_id", "appointment_id"}
    for field in fabricated_id_fields:
        assert field not in body["params"]


@pytest.fixture
async def generate_client():
    config = GatewayConfig(
        jwt_secret=TEST_SECRET,
        log_dir="/tmp/gateway-test-logs",
        streaming_enabled=True,
        runners=[RunnerConfig(id="runner-a", base_url=RUNNER_URL)],
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
            digest="sha256:generate-test",
            context_tokens=8192,
            features=["json_grammar"],
        ),
    )


@pytest.mark.asyncio
@respx.mock
@pytest.mark.parametrize(
    "mode",
    [
        ChatScriptMode.VALID_CREATE,
        ChatScriptMode.VALID_RESCHEDULE,
        ChatScriptMode.VALID_CANCEL,
        ChatScriptMode.VALID_UPDATE_STATUS,
    ],
)
async def test_generate_happy_path_per_command_type(generate_client, mode) -> None:
    client, app = generate_client
    _prime_runner(app)

    envelope = envelope_for_mode(mode, context=MVP_CONTEXT)
    respx.post(CHAT_URL).mock(
        return_value=httpx.Response(200, json=_chat_response_from_envelope(envelope))
    )

    response = await client.post(
        GENERATE_PATH,
        json={
            "task": "command",
            "prompt": "scheduling request",
            "context": MVP_CONTEXT,
            "options": {"stream": False},
        },
    )

    assert response.status_code == 200
    body = response.json()
    _assert_envelope_contract(body)
    assert body["command_type"] == envelope["command_type"]

    if body["command_type"] == "create_appointment":
        summary = body["display_summary"].lower()
        assert "ahmed" in summary
        assert "ali" in summary


@pytest.mark.asyncio
@respx.mock
async def test_mvp_book_ahmed_with_dr_ali(generate_client) -> None:
    """SC-001: book Ahmed with Dr Ali tomorrow 5pm → create_appointment proposal."""
    client, app = generate_client
    _prime_runner(app)

    fake = FakeRunner(base_url=RUNNER_URL)
    fake.script_chat(ChatScriptMode.VALID_CREATE, context=MVP_CONTEXT)
    respx.post(CHAT_URL).mock(
        side_effect=lambda request: httpx.Response(
            200, json=fake.chat_completion_response()
        )
    )

    response = await client.post(
        GENERATE_PATH,
        json={
            "task": "command",
            "prompt": "book Ahmed with Dr Ali tomorrow 5pm",
            "context": MVP_CONTEXT,
            "options": {"stream": False},
        },
    )

    assert response.status_code == 200
    body = response.json()
    _assert_envelope_contract(body)
    assert body["command_type"] == "create_appointment"
    assert body["requires_resolution"] == {
        "patient_id": "lookup_required",
        "doctor_id": "lookup_required",
    }
    assert body["needs_clarification"] is False
    assert "ahmed" in body["display_summary"].lower()
    assert "ali" in body["display_summary"].lower()
    assert body["params"]["patient_name"]
    assert body["params"]["doctor_name"]


@pytest.mark.asyncio
@respx.mock
async def test_generate_semantic_violation_returns_ai_unusable(generate_client) -> None:
    client, app = generate_client
    _prime_runner(app)

    envelope = envelope_for_mode(ChatScriptMode.SEMANTIC_VIOLATION)
    respx.post(CHAT_URL).mock(
        return_value=httpx.Response(200, json=_chat_response_from_envelope(envelope))
    )

    response = await client.post(
        GENERATE_PATH,
        json={"task": "command", "prompt": "book in the past", "options": {"stream": False}},
    )

    assert response.status_code == 422
    assert response.json()["error"]["code"] == "ai_unusable"


@pytest.mark.asyncio
@respx.mock
async def test_generate_off_catalog_returns_ai_unusable(generate_client) -> None:
    client, app = generate_client
    _prime_runner(app)

    envelope = envelope_for_mode(ChatScriptMode.OFF_CATALOG)
    respx.post(CHAT_URL).mock(
        return_value=httpx.Response(200, json=_chat_response_from_envelope(envelope))
    )

    response = await client.post(
        GENERATE_PATH,
        json={"task": "command", "prompt": "admin delete", "options": {"stream": False}},
    )

    assert response.status_code == 422
    assert response.json()["error"]["code"] == "ai_unusable"


@pytest.mark.asyncio
@respx.mock
async def test_generate_invalid_json_returns_ai_unusable(generate_client) -> None:
    client, app = generate_client
    _prime_runner(app)

    respx.post(CHAT_URL).mock(
        return_value=httpx.Response(
            200,
            json=_chat_response_from_envelope(envelope_for_mode(ChatScriptMode.INVALID_JSON)),
        )
    )

    response = await client.post(
        GENERATE_PATH,
        json={"task": "command", "prompt": "broken", "options": {"stream": False}},
    )

    assert response.status_code == 422
    assert response.json()["error"]["code"] == "ai_unusable"
