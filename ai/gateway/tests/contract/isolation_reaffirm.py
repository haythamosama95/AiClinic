"""Isolation reaffirmation — generate requests make zero Supabase / off-LAN outbound calls."""

from __future__ import annotations

import ipaddress
import json
from typing import Any
from urllib.parse import urlparse

import httpx
import pytest
import respx
from httpx import ASGITransport

from gateway.config.settings import GatewayConfig, RunnerConfig
from gateway.main import create_app, get_poller
from gateway.routing.lifecycle import RunnerStatus
from gateway.routing.registry import LoadedModel
from tests.fixtures.fake_runner import ChatScriptMode, envelope_for_mode
from tests.fixtures.jwt_tokens import make_hs256_token

TEST_SECRET = "isolation-reaffirm-secret"
GENERATE_PATH = "/v1/ai/generate"

RUNNER_A_URL = "http://runner-a.test:11434"
RUNNER_B_URL = "http://runner-b.test:11434"
CHAT_URL = f"{RUNNER_A_URL}/v1/chat/completions"
SUPABASE_PROBE_URL = "https://project-ref.supabase.co/rest/v1/"
OFF_LAN_PROBE_URL = "https://api.example.com/v1/chat/completions"

MVP_CONTEXT = {
    "now": "2026-07-18T12:00:00+03:00",
    "branch_name": "Main",
}

REPRESENTATIVE_PAYLOADS: list[tuple[dict[str, Any], int]] = [
    (
        {"task": "command", "prompt": "book Ahmed with Dr Ali tomorrow 5pm", "context": MVP_CONTEXT},
        200,
    ),
    (
        {
            "task": "command",
            "prompt": "reschedule to next week",
            "context": MVP_CONTEXT,
            "options": {"stream": False, "confidence_hint": True, "plan_mode": "single"},
        },
        200,
    ),
    (
        {
            "task": "command",
            "prompt": "cancel appointment",
            "options": {"stream": True},
            "context": {"branch_id": "550e8400-e29b-41d4-a716-446655440000"},
        },
        200,
    ),
    (
        {
            "task": "plan",
            "prompt": "plan the week",
            "conversation_id": "550e8400-e29b-41d4-a716-446655440001",
            "turn": 0,
        },
        501,
    ),
]

_outbound_requests: list[httpx.Request] = []
_original_async_client_init = httpx.AsyncClient.__init__


def _is_supabase_url(url: str) -> bool:
    return "supabase" in url.lower()


def _is_on_lan_host(host: str) -> bool:
    if not host:
        return True
    normalized = host.lower().strip("[]")
    if normalized in {"localhost", "127.0.0.1", "::1"}:
        return True
    if normalized.endswith(".local") or normalized.endswith(".test"):
        return True
    try:
        addr = ipaddress.ip_address(normalized)
    except ValueError:
        return "." not in normalized
    return addr.is_private or addr.is_loopback


def _is_off_lan_url(url: str) -> bool:
    parsed = urlparse(url)
    if parsed.scheme not in {"http", "https", ""}:
        return True
    host = parsed.hostname or ""
    return not _is_on_lan_host(host)


def _tracking_async_client_init(self, *args: Any, **kwargs: Any) -> None:
    hooks = dict(kwargs.get("event_hooks") or {})
    request_hooks = list(hooks.get("request") or [])

    async def _record_request(request: httpx.Request) -> None:
        host = (request.url.host or "").lower()
        if host in {"test", "localhost", "127.0.0.1", "::1"}:
            return
        _outbound_requests.append(request)

    request_hooks.insert(0, _record_request)
    hooks["request"] = request_hooks
    kwargs["event_hooks"] = hooks
    _original_async_client_init(self, *args, **kwargs)


def _chat_response(envelope: dict[str, Any] | str) -> dict[str, Any]:
    content = envelope if isinstance(envelope, str) else json.dumps(envelope)
    return {
        "choices": [{"message": {"role": "assistant", "content": content}}],
        "usage": {"prompt_tokens": 100, "completion_tokens": 60},
    }


def _prime_runner(app) -> None:
    app.state.registry.update_entry(
        "runner-a",
        status=RunnerStatus.READY,
        loaded_model=LoadedModel(
            name="qwen3:4b",
            digest="sha256:isolation",
            context_tokens=8192,
            features=["json_grammar"],
        ),
    )


@pytest.fixture
def track_outbound_http(monkeypatch: pytest.MonkeyPatch) -> list[httpx.Request]:
    _outbound_requests.clear()
    monkeypatch.setattr(httpx.AsyncClient, "__init__", _tracking_async_client_init)
    return _outbound_requests


@pytest.fixture
async def isolation_client(track_outbound_http: list[httpx.Request]):
    config = GatewayConfig(
        jwt_secret=TEST_SECRET,
        log_dir="/tmp/gateway-test-logs",
        streaming_enabled=True,
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
            yield client, app, track_outbound_http


def _assert_no_supabase_or_off_lan(requests: list[httpx.Request]) -> None:
    for req in requests:
        url = str(req.url)
        assert not _is_supabase_url(url), f"Supabase outbound call detected: {url}"
        assert not _is_off_lan_url(url), f"Off-LAN outbound call detected: {url}"


@pytest.mark.asyncio
@respx.mock
async def test_generate_zero_supabase_calls(isolation_client) -> None:
    client, app, outbound = isolation_client
    _prime_runner(app)

    respx.get(f"{RUNNER_A_URL}/v1/models").mock(
        return_value=httpx.Response(200, json={"object": "list", "data": []})
    )
    respx.post(CHAT_URL).mock(
        return_value=httpx.Response(
            200,
            json=_chat_response(
                envelope_for_mode(ChatScriptMode.VALID_CREATE, context=MVP_CONTEXT)
            ),
        )
    )
    respx.get(f"{RUNNER_B_URL}/v1/models").mock(
        return_value=httpx.Response(200, json={"object": "list", "data": []})
    )
    respx.get(SUPABASE_PROBE_URL).mock(return_value=httpx.Response(200, json={}))
    respx.post(OFF_LAN_PROBE_URL).mock(return_value=httpx.Response(200, json={}))

    for payload, expected_status in REPRESENTATIVE_PAYLOADS:
        outbound.clear()
        response = await client.post(GENERATE_PATH, json=payload)
        assert response.status_code == expected_status
        _assert_no_supabase_or_off_lan(outbound)
        assert all(not _is_supabase_url(str(r.url)) for r in outbound)


@pytest.mark.asyncio
@respx.mock
async def test_generate_zero_off_lan_calls(isolation_client) -> None:
    client, app, outbound = isolation_client
    _prime_runner(app)

    respx.get(f"{RUNNER_A_URL}/v1/models").mock(
        return_value=httpx.Response(200, json={"object": "list", "data": []})
    )
    respx.post(CHAT_URL).mock(
        return_value=httpx.Response(
            200,
            json=_chat_response(
                envelope_for_mode(ChatScriptMode.VALID_CREATE, context=MVP_CONTEXT)
            ),
        )
    )
    respx.get(OFF_LAN_PROBE_URL).mock(return_value=httpx.Response(200, json={}))

    outbound.clear()
    response = await client.post(
        GENERATE_PATH,
        json={
            "task": "command",
            "prompt": "must stay on-LAN",
            "context": MVP_CONTEXT,
            "options": {"stream": False},
        },
    )
    assert response.status_code == 200
    _assert_no_supabase_or_off_lan(outbound)


@pytest.mark.asyncio
@respx.mock
async def test_generate_only_contacts_on_lan_runners(isolation_client) -> None:
    """Command generation may call configured on-LAN runners but never external hosts."""
    client, app, outbound = isolation_client
    _prime_runner(app)

    runner_models = respx.get(f"{RUNNER_A_URL}/v1/models").mock(
        return_value=httpx.Response(200, json={"object": "list", "data": []})
    )
    runner_chat = respx.post(CHAT_URL).mock(
        return_value=httpx.Response(
            200,
            json=_chat_response(
                envelope_for_mode(ChatScriptMode.VALID_CREATE, context=MVP_CONTEXT)
            ),
        )
    )
    respx.get(f"{RUNNER_B_URL}/v1/models").mock(
        return_value=httpx.Response(200, json={"object": "list", "data": []})
    )

    for payload, expected_status in REPRESENTATIVE_PAYLOADS:
        outbound.clear()
        response = await client.post(GENERATE_PATH, json=payload)
        assert response.status_code == expected_status
        _assert_no_supabase_or_off_lan(outbound)

    assert runner_chat.call_count >= 2
    for req in outbound:
        host = (req.url.host or "").lower()
        assert host.endswith(".test"), f"unexpected outbound host: {host}"
    assert runner_models.call_count == 0
