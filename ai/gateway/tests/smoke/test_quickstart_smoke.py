"""Quickstart smoke tests — mirrors specs/016-ai-generation-scheduling/quickstart.md Steps 1–8.

Uses scripted fake-runner fixtures when live Ollama is unavailable or non-deterministic.
Captured request/response pairs live under ``tests/smoke/fixtures/``.
"""

from __future__ import annotations

import asyncio
import json
import sys
from pathlib import Path
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

FIXTURES_DIR = Path(__file__).resolve().parent / "fixtures"
GATEWAY_ROOT = Path(__file__).resolve().parents[2]
AI_ROOT = GATEWAY_ROOT.parent
TEST_SECRET = "quickstart-smoke-secret"
GENERATE_PATH = "/v1/ai/generate"
CAPABILITIES_PATH = "/v1/capabilities"
RUNNER_URL = "http://runner-a.test:11434"
CHAT_URL = f"{RUNNER_URL}/v1/chat/completions"
ENVELOPE_SCHEMA = build_envelope_schema()
QUICKSTART_CONTEXT = {
    "branch_name": "Main",
    "now": "2026-07-18T09:00:00+03:00",
    "active_patient": {"name": "Ahmed Hassan"},
    "doctors": [{"name": "Dr. Ali"}],
}


def _load_fixture(name: str) -> Any:
    return json.loads((FIXTURES_DIR / name).read_text(encoding="utf-8"))


def _chat_response_from_envelope(envelope: dict[str, Any] | str) -> dict[str, Any]:
    content = envelope if isinstance(envelope, str) else json.dumps(envelope)
    return {
        "choices": [{"message": {"role": "assistant", "content": content}}],
        "usage": {"prompt_tokens": 100, "completion_tokens": 60},
    }


def _parse_sse_events(raw: str) -> list[tuple[str, dict[str, Any]]]:
    events: list[tuple[str, dict[str, Any]]] = []
    event_type: str | None = None
    for line in raw.splitlines():
        if line.startswith("event:"):
            event_type = line.split(":", 1)[1].strip()
        elif line.startswith("data:") and event_type is not None:
            events.append((event_type, json.loads(line.split(":", 1)[1].strip())))
            event_type = None
    return events


@pytest.fixture
async def smoke_client():
    config = GatewayConfig(
        jwt_secret=TEST_SECRET,
        log_dir="/tmp/gateway-test-logs",
        streaming_enabled=True,
        confidence_threshold=0.6,
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
            digest="sha256:smoke-test",
            context_tokens=8192,
            features=["json_grammar"],
        ),
    )


@pytest.mark.asyncio
async def test_step01_capabilities_advertises_scheduling_agent(smoke_client) -> None:
    """Quickstart Step 1 — /v1/capabilities lists command task and four command types."""
    client, app = smoke_client
    _prime_runner(app)
    expected = _load_fixture("step01_capabilities_response.json")

    response = await client.get(CAPABILITIES_PATH)
    assert response.status_code == 200
    body = response.json()

    assert body["schema_version"] == expected["schema_version"]
    assert body["streaming"] is True
    assert "command" in body["tasks"]
    for command in expected["commands"]:
        assert command in body["commands"]
    assert body["runners"]
    assert body["runners"][0]["status"] == "READY"


@pytest.mark.asyncio
@respx.mock
async def test_step02_non_streaming_create_appointment(smoke_client) -> None:
    """Quickstart Step 2 — book Ahmed Hassan with Dr Ali tomorrow 5pm."""
    client, app = smoke_client
    _prime_runner(app)
    request_body = _load_fixture("step02_create_request.json")
    fixture_envelope = _load_fixture("step02_create_response.json")

    respx.post(CHAT_URL).mock(
        return_value=httpx.Response(
            200, json=_chat_response_from_envelope(fixture_envelope)
        )
    )

    response = await client.post(GENERATE_PATH, json=request_body)
    assert response.status_code == 200
    body = response.json()
    jsonschema.validate(body, ENVELOPE_SCHEMA)

    assert body["command_type"] == "create_appointment"
    assert body["requires_resolution"] == fixture_envelope["requires_resolution"]
    assert body["needs_clarification"] is False
    assert "ahmed" in body["display_summary"].lower()
    assert "ali" in body["display_summary"].lower()
    assert "patient_id" not in body["params"]
    assert "doctor_id" not in body["params"]


@pytest.mark.asyncio
@respx.mock
async def test_step03_streaming_matches_non_streaming_final(smoke_client) -> None:
    """Quickstart Step 3 — SSE final event matches non-streaming body for same input."""
    client, app = smoke_client
    _prime_runner(app)
    request_body = _load_fixture("step02_create_request.json")
    request_body["options"] = {"stream": True}
    fixture_envelope = _load_fixture("step02_create_response.json")

    fake = FakeRunner(base_url=RUNNER_URL)
    fake.script_chat_stream(ChatScriptMode.CUSTOM, custom=fixture_envelope)
    respx.post(CHAT_URL).mock(
        return_value=httpx.Response(
            200,
            content=fake.chat_completion_stream_body().encode(),
            headers={"Content-Type": "text/event-stream"},
        )
    )

    response = await client.post(GENERATE_PATH, json=request_body)
    assert response.status_code == 200
    assert response.headers["content-type"].startswith("text/event-stream")

    events = _parse_sse_events(response.text)
    event_types = [name for name, _ in events]
    assert "final" in event_types
    assert "error" not in event_types
    assert "token" not in event_types

    final_payload = next(payload for name, payload in events if name == "final")
    jsonschema.validate(final_payload, ENVELOPE_SCHEMA)
    assert final_payload["command_type"] == fixture_envelope["command_type"]
    assert final_payload["params"] == fixture_envelope["params"]
    assert final_payload["requires_resolution"] == fixture_envelope["requires_resolution"]


@pytest.mark.asyncio
@respx.mock
async def test_step04_past_date_returns_ai_unusable(smoke_client) -> None:
    """Quickstart Step 4 — semantic validator rejects past dates with 422."""
    client, app = smoke_client
    _prime_runner(app)
    request_body = _load_fixture("step04_past_date_request.json")

    respx.post(CHAT_URL).mock(
        return_value=httpx.Response(
            200,
            json=_chat_response_from_envelope(
                envelope_for_mode(ChatScriptMode.SEMANTIC_VIOLATION)
            ),
        )
    )

    response = await client.post(GENERATE_PATH, json=request_body)
    assert response.status_code == 422
    err = response.json()["error"]
    assert err["code"] == "ai_unusable"
    assert err["request_id"]


@pytest.mark.asyncio
@respx.mock
async def test_step05_low_confidence_sets_needs_clarification(smoke_client) -> None:
    """Quickstart Step 5 — ambiguous prompt yields needs_clarification=true."""
    client, app = smoke_client
    _prime_runner(app)
    request_body = _load_fixture("step05_ambiguous_request.json")
    fixture_envelope = _load_fixture("step05_low_confidence_response.json")

    respx.post(CHAT_URL).mock(
        return_value=httpx.Response(
            200, json=_chat_response_from_envelope(fixture_envelope)
        )
    )

    response = await client.post(GENERATE_PATH, json=request_body)
    assert response.status_code == 200
    body = response.json()
    assert body["confidence"] < 0.6
    assert body["needs_clarification"] is True


@pytest.mark.asyncio
@respx.mock
@pytest.mark.timeout(5)
async def test_step06_client_abort_logs_cancelled(smoke_client) -> None:
    """Quickstart Step 6 — client abort frees queue slot and logs cancelled."""
    client, app = smoke_client
    _prime_runner(app)
    log_dir = Path(app.state.config.log_dir)

    fake = FakeRunner(base_url=RUNNER_URL)
    fake.script_chat_stream(
        ChatScriptMode.VALID_CREATE,
        context=QUICKSTART_CONTEXT,
        first_token_delay_s=2.0,
    )

    async def _slow_stream_handler(request: httpx.Request) -> httpx.Response:
        if fake._chat_index < len(fake._chat_scripts):
            script = fake._chat_scripts[fake._chat_index]
            if script.first_token_delay_s > 0:
                await asyncio.sleep(script.first_token_delay_s)
        result = fake.resolve_chat(stream=True, apply_delays=False, record_invocation=False)
        if isinstance(result, BaseException):
            raise result
        return result

    respx.post(CHAT_URL).mock(side_effect=_slow_stream_handler)

    try:
        async with client.stream(
            "POST",
            GENERATE_PATH,
            json={
                "task": "command",
                "prompt": "slow stream",
                "context": QUICKSTART_CONTEXT,
                "options": {"stream": True},
            },
            timeout=httpx.Timeout(5.0, read=0.2),
        ) as response:
            async for _chunk in response.aiter_bytes():
                pass
    except (httpx.ReadTimeout, AssertionError):
        pass

    await asyncio.sleep(0.5)
    log_file = log_dir / "gateway.jsonl"
    records: list[dict[str, Any]] = []
    if log_file.is_file():
        for line in log_file.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if not line.startswith("{"):
                continue
            records.append(json.loads(line))
    cancelled = [r for r in records if r.get("outcome") == "cancelled"]
    assert cancelled, "expected outcome=cancelled in structured logs"


@pytest.mark.asyncio
async def test_step07_isolation_scan_passes() -> None:
    """Quickstart Step 7 — isolation scan remains green under ai/."""
    sys.path.insert(0, str(GATEWAY_ROOT / "scripts"))
    from isolation_scan import scan_ai_tree

    violations = scan_ai_tree(AI_ROOT)
    assert violations == []


@pytest.mark.asyncio
@respx.mock
async def test_step08_contract_suite_entry_point_smoke(smoke_client) -> None:
    """Quickstart Step 8 — representative contract path (generate + capabilities) is green."""
    client, app = smoke_client
    _prime_runner(app)
    fixture_envelope = _load_fixture("step02_create_response.json")
    respx.post(CHAT_URL).mock(
        return_value=httpx.Response(
            200, json=_chat_response_from_envelope(fixture_envelope)
        )
    )

    caps = await client.get(CAPABILITIES_PATH)
    assert caps.status_code == 200

    gen = await client.post(
        GENERATE_PATH,
        json=_load_fixture("step02_create_request.json"),
    )
    assert gen.status_code == 200
    jsonschema.validate(gen.json(), ENVELOPE_SCHEMA)
