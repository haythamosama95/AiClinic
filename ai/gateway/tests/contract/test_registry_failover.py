"""Registry lifecycle and failover integration tests driven by fake_runner."""

from __future__ import annotations

import time

import httpx
import pytest
import respx
from httpx import ASGITransport

from gateway.config.settings import GatewayConfig, RunnerConfig
from gateway.main import create_app, get_poller
from gateway.routing.lifecycle import RunnerStatus
from gateway.routing.registry import RunnerRegistry
from tests.fixtures.fake_runner import FakeRunner, LoadedModelInfo, PollOutcome
from tests.fixtures.jwt_tokens import make_hs256_token

TEST_SECRET = "registry-failover-secret"
RUNNER_ID = "runner-a"
RUNNER_URL = "http://fake-runner.test:19999"
RUNNER_MODELS = f"{RUNNER_URL}/v1/models"
DEFAULT_MODEL = LoadedModelInfo(
    name="qwen3:4b",
    digest="sha256:failover-test",
    context_tokens=8192,
    features=["json_grammar"],
)
ELEVATED_LATENCY_MS = 2500.0
BASELINE_LATENCY_MS = 50.0


def _install_fake_runner_mock(fake: FakeRunner) -> None:
    """Wire fake_runner scripted outcomes to respx with optional latency simulation."""

    def handler(_request: httpx.Request) -> httpx.Response:
        scripted = fake.poll()
        outcome = scripted["outcome"]
        if outcome == PollOutcome.LOADING.value:
            return httpx.Response(200, json={"object": "list", "data": []})
        if outcome in (PollOutcome.ERROR.value, PollOutcome.TIMEOUT.value):
            if outcome == PollOutcome.TIMEOUT.value:
                time.sleep(2.1)
            return httpx.Response(503, json={"error": "simulated runner failure"})
        if outcome == PollOutcome.OK.value and "model" in scripted:
            latency_ms = scripted.get("latency_ms")
            if latency_ms is not None and latency_ms >= ELEVATED_LATENCY_MS:
                time.sleep(latency_ms / 1000.0)
            model = scripted["model"]
            return httpx.Response(
                200,
                json={
                    "object": "list",
                    "data": [
                        {
                            "id": model["name"],
                            "object": "model",
                            "digest": model["digest"],
                            "context_length": model.get("context_tokens"),
                        }
                    ],
                },
            )
        return httpx.Response(503, json={"error": "unexpected fake runner state"})

    respx.get(RUNNER_MODELS).mock(side_effect=handler)


@pytest.fixture
async def failover_client():
    config = GatewayConfig(
        jwt_secret=TEST_SECRET,
        log_dir="/tmp/gateway-test-logs",
        health_poll_interval_s=60,
        unreachable_after_failures=3,
        max_inflight_per_caller=1,
        runners=[
            RunnerConfig(
                id=RUNNER_ID,
                base_url=RUNNER_URL,
                capabilities=["json_grammar"],
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


async def _poll(poller) -> None:
    await poller.stop()
    await poller.poll_once()


def _entry(registry: RunnerRegistry, runner_id: str = RUNNER_ID):
    entry = registry.get(runner_id)
    assert entry is not None
    return entry


@pytest.mark.asyncio
@respx.mock
async def test_registry_walks_full_lifecycle_including_degraded_and_busy(
    failover_client,
) -> None:
    """fake_runner drives UNKNOWN→STARTING→READY→DEGRADED→READY→BUSY→READY."""
    _client, app = failover_client
    registry: RunnerRegistry = app.state.registry
    poller = get_poller()
    assert poller is not None
    fake = FakeRunner(runner_id=RUNNER_ID, base_url=RUNNER_URL)
    _install_fake_runner_mock(fake)

    assert _entry(registry).status == RunnerStatus.UNKNOWN

    fake.loading()
    await _poll(poller)
    assert _entry(registry).status == RunnerStatus.STARTING

    fake.ok(BASELINE_LATENCY_MS, DEFAULT_MODEL)
    await _poll(poller)
    assert _entry(registry).status == RunnerStatus.READY
    assert registry.ready is True

    for _ in range(3):
        fake.ok(ELEVATED_LATENCY_MS, DEFAULT_MODEL)
        await _poll(poller)
    assert _entry(registry).status == RunnerStatus.DEGRADED
    assert registry.ready is False

    fake.ok(BASELINE_LATENCY_MS, DEFAULT_MODEL)
    await _poll(poller)
    assert _entry(registry).status == RunnerStatus.READY

    registry.update_entry(RUNNER_ID, in_flight=1)
    fake.ok(BASELINE_LATENCY_MS, DEFAULT_MODEL)
    await _poll(poller)
    assert _entry(registry).status == RunnerStatus.BUSY
    assert registry.ready is False

    registry.update_entry(RUNNER_ID, in_flight=0)
    fake.ok(BASELINE_LATENCY_MS, DEFAULT_MODEL)
    await _poll(poller)
    assert _entry(registry).status == RunnerStatus.READY


@pytest.mark.asyncio
@respx.mock
async def test_ready_flips_503_when_all_unreachable_and_recovers(
    failover_client,
) -> None:
    """SC-003: /ready is 503 with no READY runners and recovers after UNREACHABLE→READY."""
    client, app = failover_client
    registry: RunnerRegistry = app.state.registry
    poller = get_poller()
    assert poller is not None
    fake = FakeRunner(runner_id=RUNNER_ID, base_url=RUNNER_URL)
    _install_fake_runner_mock(fake)

    fake.loading()
    await _poll(poller)
    fake.ok(BASELINE_LATENCY_MS, DEFAULT_MODEL)
    await _poll(poller)
    assert _entry(registry).status == RunnerStatus.READY

    ready = await client.get("/ready")
    assert ready.status_code == 200
    assert ready.json()["status"] == "ready"

    fake.error()
    fake.error()
    fake.error()
    for _ in range(3):
        await _poll(poller)

    assert _entry(registry).status == RunnerStatus.UNREACHABLE
    assert registry.ready is False

    not_ready = await client.get("/ready")
    assert not_ready.status_code == 503
    body = not_ready.json()
    assert body["error"]["code"] == "ai_no_capacity"
    assert body["error"]["request_id"]

    fake.loading()
    await _poll(poller)
    assert _entry(registry).status == RunnerStatus.STARTING

    still_not_ready = await client.get("/ready")
    assert still_not_ready.status_code == 503

    fake.ok(BASELINE_LATENCY_MS, DEFAULT_MODEL)
    await _poll(poller)
    assert _entry(registry).status == RunnerStatus.READY

    recovered = await client.get("/ready")
    assert recovered.status_code == 200
    assert recovered.json()["status"] == "ready"


@pytest.mark.asyncio
@respx.mock
async def test_unreachable_recovery_passes_through_starting_on_loading(
    failover_client,
) -> None:
    """UNREACHABLE recovery with a loading poll lands in STARTING (data-model §3)."""
    _client, app = failover_client
    registry: RunnerRegistry = app.state.registry
    poller = get_poller()
    assert poller is not None
    fake = FakeRunner(runner_id=RUNNER_ID, base_url=RUNNER_URL)
    _install_fake_runner_mock(fake)

    fake.ok(BASELINE_LATENCY_MS, DEFAULT_MODEL)
    await _poll(poller)
    assert _entry(registry).status == RunnerStatus.READY

    fake.error()
    fake.error()
    fake.error()
    for _ in range(3):
        await _poll(poller)
    assert _entry(registry).status == RunnerStatus.UNREACHABLE

    fake.loading()
    await _poll(poller)
    assert _entry(registry).status == RunnerStatus.STARTING
