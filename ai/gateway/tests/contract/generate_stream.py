"""SSE streaming generate contract tests — scheduling command envelopes (US2)."""

from __future__ import annotations

import json
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

TEST_SECRET = "generate-stream-secret"
GENERATE_PATH = "/v1/ai/generate"
RUNNER_URL = "http://runner-a.test:11434"
CHAT_URL = f"{RUNNER_URL}/api/chat"

ENVELOPE_SCHEMA = build_envelope_schema()
MVP_CONTEXT = {
    "now": "2026-07-18T12:00:00+03:00",
    "branch_name": "Main",
}
ALLOWED_SSE_EVENTS = frozenset({"token", "summary", "output", "final", "error"})
TERMINAL_SSE_EVENTS = frozenset({"final", "error"})
EQUIVALENCE_FIELDS = (
    "schema_version",
    "task",
    "command_type",
    "params",
    "requires_resolution",
    "display_summary",
    "needs_clarification",
    "warnings",
)


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


def _parse_sse_events(raw: str) -> list[tuple[str, dict[str, Any]]]:
    events: list[tuple[str, dict[str, Any]]] = []
    event_type: str | None = None
    for line in raw.splitlines():
        if line.startswith("event:"):
            event_type = line.split(":", 1)[1].strip()
        elif line.startswith("data:") and event_type is not None:
            payload = json.loads(line.split(":", 1)[1].strip())
            events.append((event_type, payload))
            event_type = None
    return events


def _assert_sse_contract(events: list[tuple[str, dict[str, Any]]]) -> dict[str, Any]:
    assert events, "expected at least one SSE event"
    for event_type, _payload in events:
        assert event_type in ALLOWED_SSE_EVENTS

    assert "token" not in {event_type for event_type, _ in events}

    terminal = [event_type for event_type, _ in events if event_type in TERMINAL_SSE_EVENTS]
    assert len(terminal) == 1

    terminal_type, terminal_payload = events[-1]
    assert terminal_type in TERMINAL_SSE_EVENTS

    if terminal_type == "final":
        _assert_envelope_contract(terminal_payload)
        return terminal_payload

    assert "error" in terminal_payload
    return terminal_payload


def _equivalence_subset(body: dict[str, Any]) -> dict[str, Any]:
    return {field: body[field] for field in EQUIVALENCE_FIELDS}


@pytest.fixture
async def stream_client():
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


@pytest.fixture
async def stream_disabled_client():
    config = GatewayConfig(
        jwt_secret=TEST_SECRET,
        log_dir="/tmp/gateway-test-logs",
        streaming_enabled=False,
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


def _mock_non_streaming(envelope: dict[str, Any] | str) -> None:
    respx.post(CHAT_URL).mock(
        return_value=httpx.Response(200, json=_chat_response_from_envelope(envelope))
    )


def _mock_streaming(fake: FakeRunner) -> None:
    body = fake.chat_completion_stream_body()

    respx.post(CHAT_URL).mock(
        return_value=httpx.Response(
            200,
            content=body.encode(),
            headers={"Content-Type": "text/event-stream"},
        )
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
async def test_stream_happy_path_per_command_type(stream_client, mode) -> None:
    client, app = stream_client
    _prime_runner(app)

    fake = FakeRunner(base_url=RUNNER_URL)
    fake.script_chat_stream(mode, context=MVP_CONTEXT)
    _mock_streaming(fake)

    response = await client.post(
        GENERATE_PATH,
        json={
            "task": "command",
            "prompt": "scheduling request",
            "context": MVP_CONTEXT,
            "options": {"stream": True},
        },
    )

    assert response.status_code == 200
    assert response.headers["content-type"].startswith("text/event-stream")

    events = _parse_sse_events(response.text)
    final_payload = _assert_sse_contract(events)
    expected = envelope_for_mode(mode, context=MVP_CONTEXT)
    assert isinstance(expected, dict)
    assert final_payload["command_type"] == expected["command_type"]


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
async def test_stream_matches_non_stream_for_same_input(stream_client, mode) -> None:
    """SC-002: paired tests across all four scheduling command types."""
    client, app = stream_client
    _prime_runner(app)

    envelope = envelope_for_mode(mode, context=MVP_CONTEXT)
    assert isinstance(envelope, dict)

    _mock_non_streaming(envelope)
    non_stream = await client.post(
        GENERATE_PATH,
        json={
            "task": "command",
            "prompt": "scheduling request",
            "context": MVP_CONTEXT,
            "options": {"stream": False},
        },
    )
    assert non_stream.status_code == 200
    non_stream_body = non_stream.json()

    fake = FakeRunner(base_url=RUNNER_URL)
    fake.script_chat_stream(mode, context=MVP_CONTEXT, summary_prefix="")
    _mock_streaming(fake)

    stream = await client.post(
        GENERATE_PATH,
        json={
            "task": "command",
            "prompt": "scheduling request",
            "context": MVP_CONTEXT,
            "options": {"stream": True},
        },
    )
    assert stream.status_code == 200
    events = _parse_sse_events(stream.text)
    final_payload = _assert_sse_contract(events)

    assert _equivalence_subset(final_payload) == _equivalence_subset(non_stream_body)
    assert abs(final_payload["confidence"] - non_stream_body["confidence"]) < 0.01


@pytest.mark.asyncio
@respx.mock
async def test_stream_emits_summary_events(stream_client) -> None:
    client, app = stream_client
    _prime_runner(app)

    fake = FakeRunner(base_url=RUNNER_URL)
    fake.script_chat_stream(
        ChatScriptMode.VALID_CREATE,
        context=MVP_CONTEXT,
        summary_prefix="Looking up tomorrow's availability... ",
    )
    _mock_streaming(fake)

    response = await client.post(
        GENERATE_PATH,
        json={
            "task": "command",
            "prompt": "book Ahmed with Dr Ali tomorrow 5pm",
            "context": MVP_CONTEXT,
            "options": {"stream": True},
        },
    )

    events = _parse_sse_events(response.text)
    summary_events = [payload for event_type, payload in events if event_type == "summary"]
    assert summary_events
    joined = "".join(item["delta"] for item in summary_events)
    assert "availability" in joined.lower()
    _assert_sse_contract(events)


@pytest.mark.asyncio
@respx.mock
async def test_stream_emits_output_events_for_command_json(stream_client) -> None:
    client, app = stream_client
    _prime_runner(app)

    fake = FakeRunner(base_url=RUNNER_URL)
    fake.script_chat_stream(ChatScriptMode.VALID_CREATE, context=MVP_CONTEXT, summary_prefix="")
    _mock_streaming(fake)

    response = await client.post(
        GENERATE_PATH,
        json={
            "task": "command",
            "prompt": "book Ahmed with Dr Ali tomorrow 5pm",
            "context": MVP_CONTEXT,
            "options": {"stream": True},
        },
    )

    events = _parse_sse_events(response.text)
    output_events = [payload for event_type, payload in events if event_type == "output"]
    assert output_events
    joined = "".join(item["delta"] for item in output_events)
    assert joined.startswith("{")
    assert "command_type" in joined
    _assert_sse_contract(events)


@pytest.mark.asyncio
@respx.mock
async def test_stream_semantic_violation_emits_error_event(stream_client) -> None:
    client, app = stream_client
    _prime_runner(app)

    fake = FakeRunner(base_url=RUNNER_URL)
    fake.script_chat_stream(ChatScriptMode.SEMANTIC_VIOLATION, summary_prefix="")
    _mock_streaming(fake)

    response = await client.post(
        GENERATE_PATH,
        json={
            "task": "command",
            "prompt": "book in the past",
            "context": MVP_CONTEXT,
            "options": {"stream": True},
        },
    )

    assert response.status_code == 200
    events = _parse_sse_events(response.text)
    terminal = [event_type for event_type, _ in events if event_type in TERMINAL_SSE_EVENTS]
    assert terminal == ["error"]
    event_type, payload = events[-1]
    assert event_type == "error"
    assert payload["error"]["code"] == "ai_unusable"


@pytest.mark.asyncio
@respx.mock
async def test_stream_disabled_falls_back_to_json(stream_disabled_client) -> None:
    client, app = stream_disabled_client
    _prime_runner(app)

    envelope = envelope_for_mode(ChatScriptMode.VALID_CREATE, context=MVP_CONTEXT)
    _mock_non_streaming(envelope)

    response = await client.post(
        GENERATE_PATH,
        json={
            "task": "command",
            "prompt": "book Ahmed with Dr Ali tomorrow 5pm",
            "context": MVP_CONTEXT,
            "options": {"stream": True},
        },
    )

    assert response.status_code == 200
    assert "application/json" in response.headers["content-type"]
    body = response.json()
    _assert_envelope_contract(body)
    assert body["command_type"] == "create_appointment"
