"""Resilience contract tests — queue, timeouts, retry, cancel, swap, shutdown (US3)."""

from __future__ import annotations

import asyncio
import json
import re
import time
from collections.abc import AsyncIterator
from pathlib import Path
from typing import Any

import httpx
import pytest
import respx
from httpx import ASGITransport

from gateway.config.settings import GatewayConfig, ModelDef, RunnerConfig
from gateway.api.generate import _selector_state
from gateway.main import create_app, get_poller
from gateway.routing.lifecycle import RunnerStatus
from gateway.routing.registry import LoadedModel
from tests.fixtures.fake_runner import (
    ChatFailureMode,
    ChatScriptMode,
    FakeRunner,
    LoadedModelInfo,
)
from tests.fixtures.jwt_tokens import make_hs256_token

TEST_SECRET = "resilience-contract-secret"
GENERATE_PATH = "/v1/ai/generate"
RUNNER_A_ID = "runner-a"
RUNNER_B_ID = "runner-b"
RUNNER_A_URL = "http://runner-a.test:11434"
RUNNER_B_URL = "http://runner-b.test:11434"
CHAT_A_URL = f"{RUNNER_A_URL}/api/chat"
CHAT_B_URL = f"{RUNNER_B_URL}/api/chat"
MODELS_A_URL = f"{RUNNER_A_URL}/v1/models"
MODELS_B_URL = f"{RUNNER_B_URL}/v1/models"

MVP_CONTEXT = {
    "now": "2026-07-18T12:00:00+03:00",
    "branch_name": "Main",
}
DEFAULT_MODEL = LoadedModelInfo(
    name="qwen3:4b",
    digest="sha256:resilience-test",
    context_tokens=8192,
    features=["json_grammar"],
)
SCHEDULING_MODEL = ModelDef(
    name="qwen3:4b",
    source="ollama",
    digest="sha256:resilience-test",
    context_tokens=8192,
    capabilities=["json_grammar"],
)


def _generation_payload(*, stream: bool = False) -> dict[str, Any]:
    return {
        "task": "command",
        "prompt": "book Ahmed with Dr Ali tomorrow 5pm",
        "context": MVP_CONTEXT,
        "options": {"stream": stream},
    }


def _read_log_records(log_dir: str) -> list[dict[str, Any]]:
    log_file = Path(log_dir) / "gateway.jsonl"
    if not log_file.is_file():
        return []
    return [
        json.loads(line)
        for line in log_file.read_text(encoding="utf-8").splitlines()
        if line.strip()
    ]


def _metric_value(metrics_text: str, name: str, *, capability: str | None = None) -> float | None:
    pattern = re.compile(rf"^{re.escape(name)}(?:\{{[^}}]*\}})?\s+(\S+)", re.MULTILINE)
    for match in pattern.finditer(metrics_text):
        line_start = metrics_text.rfind("\n", 0, match.start()) + 1
        line = metrics_text[line_start : match.end()]
        if capability is not None and f'capability="{capability}"' not in line:
            continue
        return float(match.group(1))
    return None


def _install_load_mock_for_runner(base_url: str) -> None:
    root = base_url.rstrip("/").rsplit("/v1", 1)[0]
    respx.post(f"{root}/api/load").mock(
        return_value=httpx.Response(200, json={"status": "success"})
    )


def _install_chat_mock(url: str, fake: FakeRunner) -> None:
    async def handler(request: httpx.Request) -> httpx.Response | BaseException:
        is_stream = b'"stream": true' in request.content or b'"stream":true' in request.content
        if fake._chat_index < len(fake._chat_scripts):
            script = fake._chat_scripts[fake._chat_index]
            fake.chat_invocations.append(fake.runner_id)
            if script.first_token_delay_s > 0:
                await asyncio.sleep(script.first_token_delay_s)
            if script.total_delay_s > 0:
                await asyncio.sleep(script.total_delay_s)
        result = fake.resolve_chat(
            stream=is_stream,
            apply_delays=False,
            record_invocation=False,
        )
        if isinstance(result, BaseException):
            raise result
        return result

    respx.post(url).mock(side_effect=handler)


def _install_models_mock(url: str, fake: FakeRunner) -> None:
    def handler(_request: httpx.Request) -> httpx.Response:
        try:
            payload = fake.models_response()
            return httpx.Response(200, json=payload)
        except RuntimeError:
            return httpx.Response(503, json={"error": "simulated runner failure"})

    respx.get(url).mock(side_effect=handler)


def _prime_runner(
    app,
    runner_id: str,
    *,
    status: RunnerStatus = RunnerStatus.READY,
    model: LoadedModel | None = None,
) -> None:
    loaded = model or LoadedModel(
        name=DEFAULT_MODEL.name,
        digest=DEFAULT_MODEL.digest,
        context_tokens=DEFAULT_MODEL.context_tokens,
        features=DEFAULT_MODEL.features,
    )
    app.state.registry.update_entry(runner_id, status=status, loaded_model=loaded)


@pytest.fixture
async def resilience_client(tmp_path: Path) -> AsyncIterator[tuple[httpx.AsyncClient, Any]]:
    log_dir = str(tmp_path / "gateway-logs")
    config = GatewayConfig(
        jwt_secret=TEST_SECRET,
        log_dir=log_dir,
        streaming_enabled=True,
        queue_max_depth=2,
        queue_max_wait_s=5,
        max_inflight_per_caller=4,
        timeout_first_token_s=1,
        timeout_total_s=2,
        model_swap_first_token_timeout_s=3,
        shutdown_grace_s=2,
        runners=[
            RunnerConfig(id=RUNNER_A_ID, base_url=RUNNER_A_URL, capabilities=["json_grammar"]),
            RunnerConfig(
                id=RUNNER_B_ID,
                base_url=RUNNER_B_URL,
                capabilities=["json_grammar"],
                models=[SCHEDULING_MODEL],
            ),
        ],
    )
    app = create_app(config)
    token = make_hs256_token(TEST_SECRET, staff_role="doctor", staff_id="staff-a")
    headers = {"Authorization": f"Bearer {token}"}
    async with app.router.lifespan_context(app):
        _selector_state._selector._round_robin_counter = 0
        poller = get_poller()
        if poller is not None:
            await poller.stop()
        transport = ASGITransport(app=app)
        async with httpx.AsyncClient(
            transport=transport,
            base_url="http://test",
            headers=headers,
            timeout=httpx.Timeout(30.0, connect=5.0),
        ) as client:
            yield client, app


def _client_for_staff(
    app,
    *,
    staff_id: str,
    log_dir: str | None = None,
) -> httpx.AsyncClient:
    token = make_hs256_token(TEST_SECRET, staff_role="doctor", staff_id=staff_id)
    headers = {"Authorization": f"Bearer {token}"}
    transport = ASGITransport(app=app)
    return httpx.AsyncClient(
        transport=transport,
        base_url="http://test",
        headers=headers,
        timeout=httpx.Timeout(30.0, connect=5.0),
    )


async def _begin_graceful_shutdown(app) -> None:
    coordinator = getattr(app.state, "shutdown_coordinator", None)
    assert coordinator is not None, "T043: graceful shutdown coordinator not wired on app.state"
    begin = getattr(coordinator, "begin_shutdown", None) or getattr(
        coordinator, "request_shutdown", None
    )
    assert begin is not None, "T043: shutdown coordinator missing begin_shutdown()"
    result = begin()
    if asyncio.iscoroutine(result):
        await result


# --- (a) Queue saturation + per-caller in-flight cap ---


@pytest.mark.asyncio
@respx.mock
async def test_queue_saturation_returns_ai_busy_with_retry_after(resilience_client) -> None:
    """SC-005: overflow rejects with 503 ai_busy + Retry-After (bounded queue)."""
    client, app = resilience_client
    _prime_runner(app, RUNNER_A_ID)
    _prime_runner(app, RUNNER_B_ID)

    fake_a = FakeRunner(runner_id=RUNNER_A_ID, base_url=RUNNER_A_URL)
    fake_b = FakeRunner(runner_id=RUNNER_B_ID, base_url=RUNNER_B_URL)
    for fake in (fake_a, fake_b):
        fake.script_chat(
            ChatScriptMode.VALID_CREATE,
            context=MVP_CONTEXT,
            total_delay_s=3.0,
        )
    _install_chat_mock(CHAT_A_URL, fake_a)
    _install_chat_mock(CHAT_B_URL, fake_b)

    tasks = [
        asyncio.create_task(client.post(GENERATE_PATH, json=_generation_payload()))
        for _ in range(4)
    ]
    results = await asyncio.gather(*tasks, return_exceptions=True)

    busy = [
        r
        for r in results
        if isinstance(r, httpx.Response)
        and r.status_code == 503
        and r.json()["error"]["code"] == "ai_busy"
    ]
    assert busy, "expected at least one 503 ai_busy when queue is saturated"
    for response in busy:
        assert "Retry-After" in response.headers
        assert int(response.headers["Retry-After"]) > 0


@pytest.mark.asyncio
@respx.mock
async def test_queue_saturation_keeps_memory_bounded(resilience_client) -> None:
    """SC-005: burst overflow fails fast — queue depth never exceeds configured max."""
    client, app = resilience_client
    _prime_runner(app, RUNNER_A_ID)

    fake = FakeRunner(runner_id=RUNNER_A_ID, base_url=RUNNER_A_URL)
    fake.script_chat(ChatScriptMode.VALID_CREATE, context=MVP_CONTEXT, total_delay_s=3.0)
    _install_chat_mock(CHAT_A_URL, fake)

    tasks = [
        asyncio.create_task(client.post(GENERATE_PATH, json=_generation_payload()))
        for _ in range(6)
    ]
    await asyncio.gather(*tasks, return_exceptions=True)

    metrics = await client.get("/metrics")
    depth = _metric_value(metrics.text, "ai_queue_depth", capability="command")
    assert depth is not None, "ai_queue_depth metric missing (T042 pipeline)"
    assert depth <= app.state.config.queue_max_depth


@pytest.mark.asyncio
@respx.mock
async def test_per_caller_inflight_cap_rejects_without_starving_others(
    tmp_path: Path,
) -> None:
    """SC-005: per-caller cap returns 429; a different caller is not starved."""
    log_dir = str(tmp_path / "gateway-logs")
    config = GatewayConfig(
        jwt_secret=TEST_SECRET,
        log_dir=log_dir,
        streaming_enabled=True,
        queue_max_depth=4,
        queue_max_wait_s=5,
        max_inflight_per_caller=1,
        timeout_first_token_s=10,
        timeout_total_s=15,
        runners=[RunnerConfig(id=RUNNER_A_ID, base_url=RUNNER_A_URL)],
    )
    app = create_app(config)
    async with app.router.lifespan_context(app):
        _selector_state._selector._round_robin_counter = 0
        poller = get_poller()
        if poller is not None:
            await poller.stop()
        _prime_runner(app, RUNNER_A_ID)

        fake = FakeRunner(runner_id=RUNNER_A_ID, base_url=RUNNER_A_URL)
        fake.script_chat(ChatScriptMode.VALID_CREATE, context=MVP_CONTEXT, total_delay_s=2.0)
        for _ in range(3):
            fake.script_chat(ChatScriptMode.VALID_CREATE, context=MVP_CONTEXT)
        _install_chat_mock(CHAT_A_URL, fake)

        async with _client_for_staff(app, staff_id="staff-a", log_dir=log_dir) as client:
            blocker = asyncio.create_task(client.post(GENERATE_PATH, json=_generation_payload()))
            await asyncio.sleep(0.25)

            capped = await client.post(GENERATE_PATH, json=_generation_payload())
            assert capped.status_code == 429
            assert capped.json()["error"]["code"] == "rate_limited"

            async with _client_for_staff(app, staff_id="staff-b", log_dir=log_dir) as other_client:
                other = await other_client.post(GENERATE_PATH, json=_generation_payload())
                assert other.status_code == 200

            await blocker


# --- (b) Slow runner → first-token and total timeouts ---


@pytest.mark.asyncio
@respx.mock
@pytest.mark.timeout(10)
async def test_first_token_timeout_returns_ai_timeout(resilience_client) -> None:
    """SC-006: no first token within timeout_first_token_s → 504 ai_timeout."""
    client, app = resilience_client
    _prime_runner(app, RUNNER_A_ID)

    fake = FakeRunner(runner_id=RUNNER_A_ID, base_url=RUNNER_A_URL)
    fake.script_chat(
        ChatScriptMode.VALID_CREATE,
        context=MVP_CONTEXT,
        first_token_delay_s=2.5,
    )
    _install_chat_mock(CHAT_A_URL, fake)

    response = await client.post(GENERATE_PATH, json=_generation_payload())
    assert response.status_code == 504
    assert response.json()["error"]["code"] == "ai_timeout"


@pytest.mark.asyncio
@respx.mock
@pytest.mark.timeout(10)
async def test_total_timeout_returns_ai_timeout(resilience_client) -> None:
    """SC-006: inference exceeds timeout_total_s → 504 ai_timeout."""
    client, app = resilience_client
    _prime_runner(app, RUNNER_A_ID)

    fake = FakeRunner(runner_id=RUNNER_A_ID, base_url=RUNNER_A_URL)
    fake.script_chat(
        ChatScriptMode.VALID_CREATE,
        context=MVP_CONTEXT,
        total_delay_s=3.0,
    )
    _install_chat_mock(CHAT_A_URL, fake)

    response = await client.post(GENERATE_PATH, json=_generation_payload())
    assert response.status_code == 504
    assert response.json()["error"]["code"] == "ai_timeout"


# --- (c) Single retry policy ---


@pytest.mark.asyncio
@respx.mock
@pytest.mark.parametrize(
    "failure_mode",
    [
        ChatFailureMode.CONNECTION_REFUSED,
        ChatFailureMode.HTTP_5XX,
    ],
)
async def test_retry_on_runner_failure_uses_different_runner(
    resilience_client,
    failure_mode: ChatFailureMode,
) -> None:
    """SC-006: single retry prefers a different healthy runner when available."""
    client, app = resilience_client
    _prime_runner(app, RUNNER_A_ID)
    _prime_runner(app, RUNNER_B_ID, status=RunnerStatus.DEGRADED)

    fake_a = FakeRunner(runner_id=RUNNER_A_ID, base_url=RUNNER_A_URL)
    fake_b = FakeRunner(runner_id=RUNNER_B_ID, base_url=RUNNER_B_URL)
    fake_a.script_chat_failure(failure_mode)
    fake_b.script_chat(ChatScriptMode.VALID_CREATE, context=MVP_CONTEXT)
    _install_chat_mock(CHAT_A_URL, fake_a)
    _install_chat_mock(CHAT_B_URL, fake_b)

    response = await client.post(GENERATE_PATH, json=_generation_payload())
    assert response.status_code == 200
    assert fake_a.chat_invocations, "expected an attempt on runner-a"
    assert fake_b.chat_invocations, "retry must hit runner-b"
    assert fake_a.chat_invocations != fake_b.chat_invocations


@pytest.mark.asyncio
@respx.mock
@pytest.mark.timeout(10)
async def test_retry_on_first_token_timeout_uses_different_runner(resilience_client) -> None:
    """SC-006: first-token timeout triggers one retry on a different runner."""
    client, app = resilience_client
    _prime_runner(app, RUNNER_A_ID)
    _prime_runner(app, RUNNER_B_ID, status=RunnerStatus.DEGRADED)

    fake_a = FakeRunner(runner_id=RUNNER_A_ID, base_url=RUNNER_A_URL)
    fake_b = FakeRunner(runner_id=RUNNER_B_ID, base_url=RUNNER_B_URL)
    fake_a.script_chat(
        ChatScriptMode.VALID_CREATE,
        context=MVP_CONTEXT,
        first_token_delay_s=2.5,
    )
    fake_b.script_chat(ChatScriptMode.VALID_CREATE, context=MVP_CONTEXT)
    _install_chat_mock(CHAT_A_URL, fake_a)
    _install_chat_mock(CHAT_B_URL, fake_b)

    response = await client.post(GENERATE_PATH, json=_generation_payload())
    assert response.status_code == 200
    assert fake_a.chat_invocations
    assert fake_b.chat_invocations


@pytest.mark.asyncio
@respx.mock
async def test_no_retry_on_ai_unusable(resilience_client) -> None:
    """FR-017: validation rejection is terminal — no runner retry."""
    client, app = resilience_client
    _prime_runner(app, RUNNER_A_ID)
    _prime_runner(app, RUNNER_B_ID, status=RunnerStatus.DEGRADED)

    fake_a = FakeRunner(runner_id=RUNNER_A_ID, base_url=RUNNER_A_URL)
    fake_b = FakeRunner(runner_id=RUNNER_B_ID, base_url=RUNNER_B_URL)
    fake_a.script_chat(ChatScriptMode.SEMANTIC_VIOLATION)
    fake_b.script_chat(ChatScriptMode.VALID_CREATE, context=MVP_CONTEXT)
    _install_chat_mock(CHAT_A_URL, fake_a)
    _install_chat_mock(CHAT_B_URL, fake_b)

    response = await client.post(GENERATE_PATH, json=_generation_payload())
    assert response.status_code == 422
    assert response.json()["error"]["code"] == "ai_unusable"
    assert len(fake_a.chat_invocations) == 1
    assert fake_b.chat_invocations == []


@pytest.mark.asyncio
@respx.mock
@pytest.mark.timeout(8)
async def test_no_retry_after_partial_stream(resilience_client) -> None:
    """SC-006: once bytes reach the client, runner failure must not retry."""
    client, app = resilience_client
    _prime_runner(app, RUNNER_A_ID)
    app.state.registry.update_entry(RUNNER_B_ID, status=RunnerStatus.UNREACHABLE, loaded_model=None)

    fake_a = FakeRunner(runner_id=RUNNER_A_ID, base_url=RUNNER_A_URL)
    fake_b = FakeRunner(runner_id=RUNNER_B_ID, base_url=RUNNER_B_URL)
    fake_a.script_chat_stream_tokens(
        ['{"schema_version": "1.0", "task": "command"'],
        inter_token_delay_s=0.5,
        failure=ChatFailureMode.NETWORK_ERROR,
    )
    fake_b.script_chat(ChatScriptMode.VALID_CREATE, context=MVP_CONTEXT)
    _install_chat_mock(CHAT_A_URL, fake_a)
    _install_chat_mock(CHAT_B_URL, fake_b)

    async with client.stream(
        "POST",
        GENERATE_PATH,
        json=_generation_payload(stream=True),
    ) as response:
        assert response.status_code == 200
        chunks = []
        async for chunk in response.aiter_bytes():
            chunks.append(chunk)
            if len(chunks) >= 1:
                break

    assert chunks, "expected at least one streamed byte before failure"
    assert len(fake_a.chat_invocations) == 1
    assert fake_b.chat_invocations == []


# --- (d) Client abort / cancellation ---


@pytest.mark.asyncio
@respx.mock
@pytest.mark.timeout(5)
async def test_client_abort_logs_cancelled_outcome(resilience_client) -> None:
    """SC-007: client abort frees resources and logs outcome=cancelled (not error)."""
    client, app = resilience_client
    log_dir = app.state.config.log_dir
    _prime_runner(app, RUNNER_A_ID)

    fake = FakeRunner(runner_id=RUNNER_A_ID, base_url=RUNNER_A_URL)
    fake.script_chat_stream(
        ChatScriptMode.VALID_CREATE,
        context=MVP_CONTEXT,
        first_token_delay_s=2.0,
    )
    _install_chat_mock(CHAT_A_URL, fake)

    try:
        async with client.stream(
            "POST",
            GENERATE_PATH,
            json=_generation_payload(stream=True),
            timeout=httpx.Timeout(5.0, read=0.2),
        ) as response:
            async for _chunk in response.aiter_bytes():
                pass
    except (httpx.ReadTimeout, AssertionError):
        pass

    await asyncio.sleep(0.5)
    records = _read_log_records(log_dir)
    cancelled = [r for r in records if r.get("outcome") == "cancelled"]
    assert cancelled, "expected a structured log with outcome=cancelled (T039/T042)"
    assert all(r.get("outcome") != "error" for r in cancelled)


@pytest.mark.asyncio
@respx.mock
@pytest.mark.timeout(10)
async def test_client_abort_frees_queue_slot(resilience_client) -> None:
    """SC-007: cancellation returns the queue depth to baseline."""
    client, app = resilience_client
    _prime_runner(app, RUNNER_A_ID)

    fake = FakeRunner(runner_id=RUNNER_A_ID, base_url=RUNNER_A_URL)
    fake.script_chat_stream(
        ChatScriptMode.VALID_CREATE,
        context=MVP_CONTEXT,
        first_token_delay_s=2.0,
    )
    fake.script_chat(ChatScriptMode.VALID_CREATE, context=MVP_CONTEXT)
    _install_chat_mock(CHAT_A_URL, fake)

    metrics_before = await client.get("/metrics")
    depth_before = _metric_value(metrics_before.text, "ai_queue_depth", capability="command") or 0.0

    try:
        async with client.stream(
            "POST",
            GENERATE_PATH,
            json=_generation_payload(stream=True),
            timeout=httpx.Timeout(5.0, read=0.2),
        ) as response:
            async for _chunk in response.aiter_bytes():
                break
    except (httpx.ReadTimeout, AssertionError):
        pass

    await asyncio.sleep(0.3)
    metrics_after = await client.get("/metrics")
    depth_after = _metric_value(metrics_after.text, "ai_queue_depth", capability="command")
    assert depth_after is not None
    assert depth_after <= depth_before


# --- (e) ai_no_capacity ---


@pytest.mark.asyncio
@respx.mock
async def test_ai_no_capacity_when_no_candidate_runner(resilience_client) -> None:
    """503 ai_no_capacity when no runner can serve the capability."""
    client, app = resilience_client
    app.state.registry.update_entry(
        RUNNER_A_ID,
        status=RunnerStatus.UNREACHABLE,
        loaded_model=None,
    )
    app.state.registry.update_entry(
        RUNNER_B_ID,
        status=RunnerStatus.UNREACHABLE,
        loaded_model=None,
    )

    response = await client.post(GENERATE_PATH, json=_generation_payload())
    assert response.status_code == 503
    body = response.json()
    assert body["error"]["code"] == "ai_no_capacity"
    assert "Retry-After" not in response.headers


@pytest.mark.asyncio
@respx.mock
@pytest.mark.timeout(10)
async def test_ai_no_capacity_when_swap_window_times_out(resilience_client) -> None:
    """503 ai_no_capacity when swap STARTING window exceeds model_swap_first_token_timeout_s."""
    client, app = resilience_client
    app.state.registry.update_entry(
        RUNNER_A_ID,
        status=RunnerStatus.UNREACHABLE,
        loaded_model=None,
    )
    app.state.registry.update_entry(
        RUNNER_B_ID,
        status=RunnerStatus.STARTING,
        loaded_model=None,
    )

    fake = FakeRunner(runner_id=RUNNER_B_ID, base_url=RUNNER_B_URL)
    for _ in range(10):
        fake.loading()
    _install_models_mock(MODELS_B_URL, fake)
    _install_load_mock_for_runner(RUNNER_B_URL)

    response = await client.post(GENERATE_PATH, json=_generation_payload())
    assert response.status_code == 503
    assert response.json()["error"]["code"] == "ai_no_capacity"
    assert "Retry-After" not in response.headers


# --- (f) Model swap auto-trigger ---


@pytest.mark.asyncio
@respx.mock
@pytest.mark.timeout(10)
async def test_model_swap_auto_trigger_succeeds_within_extended_timeout(
    resilience_client,
) -> None:
    """SC-008: auto-triggered swap serves request within model_swap_first_token_timeout_s."""
    client, app = resilience_client
    app.state.registry.update_entry(
        RUNNER_A_ID,
        status=RunnerStatus.UNREACHABLE,
        loaded_model=None,
    )
    app.state.registry.update_entry(
        RUNNER_B_ID,
        status=RunnerStatus.STARTING,
        loaded_model=None,
    )

    fake = FakeRunner(runner_id=RUNNER_B_ID, base_url=RUNNER_B_URL)
    fake.script_swap_window(starting_polls=1, ready_model=DEFAULT_MODEL)
    fake.script_chat(ChatScriptMode.VALID_CREATE, context=MVP_CONTEXT)
    _install_models_mock(MODELS_B_URL, fake)
    _install_load_mock_for_runner(RUNNER_B_URL)
    _install_chat_mock(CHAT_B_URL, fake)

    started = time.monotonic()
    response = await client.post(GENERATE_PATH, json=_generation_payload())
    elapsed = time.monotonic() - started

    assert response.status_code == 200
    assert elapsed < app.state.config.model_swap_first_token_timeout_s + 1.0
    assert response.json()["command_type"] == "create_appointment"


@pytest.mark.asyncio
@respx.mock
async def test_model_swap_never_two_models_in_ram(resilience_client) -> None:
    """SC-008: during STARTING swap, at most one model is resident in runner RAM."""
    client, app = resilience_client
    app.state.registry.update_entry(
        RUNNER_A_ID,
        status=RunnerStatus.UNREACHABLE,
        loaded_model=None,
    )
    app.state.registry.update_entry(
        RUNNER_B_ID,
        status=RunnerStatus.STARTING,
        loaded_model=None,
    )

    fake = FakeRunner(runner_id=RUNNER_B_ID, base_url=RUNNER_B_URL)
    fake.script_swap_window(starting_polls=3, ready_model=DEFAULT_MODEL)
    fake.script_chat(ChatScriptMode.VALID_CREATE, context=MVP_CONTEXT)
    _install_models_mock(MODELS_B_URL, fake)
    _install_load_mock_for_runner(RUNNER_B_URL)
    _install_chat_mock(CHAT_B_URL, fake)

    response = await client.post(GENERATE_PATH, json=_generation_payload())
    assert response.status_code == 200
    assert fake.models_in_ram_peak <= 1


# --- (g) SIGTERM graceful shutdown ---


@pytest.mark.asyncio
@respx.mock
@pytest.mark.timeout(15)
async def test_sigterm_drains_in_flight_within_shutdown_grace(resilience_client) -> None:
    """FR-020: SIGTERM drains in-flight work within shutdown_grace_s."""
    client, app = resilience_client
    _prime_runner(app, RUNNER_A_ID)

    fake = FakeRunner(runner_id=RUNNER_A_ID, base_url=RUNNER_A_URL)
    fake.script_chat(
        ChatScriptMode.VALID_CREATE,
        context=MVP_CONTEXT,
        total_delay_s=0.5,
    )
    _install_chat_mock(CHAT_A_URL, fake)

    in_flight = asyncio.create_task(client.post(GENERATE_PATH, json=_generation_payload()))
    await asyncio.sleep(0.05)
    await _begin_graceful_shutdown(app)

    response = await asyncio.wait_for(in_flight, timeout=app.state.config.shutdown_grace_s + 2.0)
    assert response.status_code == 200


@pytest.mark.asyncio
@respx.mock
@pytest.mark.timeout(15)
async def test_sigterm_rejects_queued_not_started_with_503(resilience_client) -> None:
    """FR-020: queued-but-not-started requests receive 503 during shutdown."""
    client, app = resilience_client
    _prime_runner(app, RUNNER_A_ID)

    fake = FakeRunner(runner_id=RUNNER_A_ID, base_url=RUNNER_A_URL)
    fake.script_chat(
        ChatScriptMode.VALID_CREATE,
        context=MVP_CONTEXT,
        total_delay_s=3.0,
    )
    _install_chat_mock(CHAT_A_URL, fake)

    blocker = asyncio.create_task(client.post(GENERATE_PATH, json=_generation_payload()))
    await asyncio.sleep(0.05)
    await _begin_graceful_shutdown(app)

    queued = await client.post(GENERATE_PATH, json=_generation_payload())
    assert queued.status_code == 503
    assert queued.json()["error"]["code"] in {"ai_busy", "ai_no_capacity"}

    await blocker
