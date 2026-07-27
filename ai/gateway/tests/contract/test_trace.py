"""Live trace buffer and SSE stream contract tests."""

from __future__ import annotations

import asyncio
import json

import httpx
import pytest
from httpx import ASGITransport

from gateway.config.settings import GatewayConfig, RunnerConfig
from gateway.main import create_app, get_poller
from gateway.obs.trace_bus import TraceBus
from tests.fixtures.jwt_tokens import make_hs256_token

TEST_SECRET = "test-secret"

TRACE_EVENT_KEYS = frozenset(
    {
        "id",
        "ts",
        "direction",
        "runner_id",
        "method",
        "path",
        "status_code",
        "latency_ms",
        "request_summary",
        "response_summary",
        "request_body",
        "response_body",
        "kind",
        "request_id",
    }
)


@pytest.fixture
async def trace_client():
    config = GatewayConfig(
        jwt_secret=TEST_SECRET,
        log_dir="/tmp/gateway-test-logs",
        health_poll_interval_s=60,
        runners=[
            RunnerConfig(id="runner-a", base_url="http://127.0.0.1:11434"),
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
            timeout=10.0,
        ) as client:
            yield client, app


@pytest.mark.asyncio
async def test_trace_config_returns_filter_dimensions(trace_client) -> None:
    client, _app = trace_client
    response = await client.get("/v1/trace/config")
    assert response.status_code == 200
    body = response.json()
    assert "directions" in body
    assert "kinds" in body
    assert "runner_ids" in body
    assert "status_classes" in body
    assert "runner-a" in body["runner_ids"]
    assert body["max_buffer"] == 500


@pytest.mark.asyncio
async def test_trace_events_buffer_and_filters(trace_client) -> None:
    client, app = trace_client
    bus: TraceBus = app.state.trace_bus

    await bus.emit(
        direction="gateway_to_runner",
        method="GET",
        path="/v1/models",
        kind="poll",
        runner_id="runner-a",
        request_summary="health poll",
    )
    await bus.emit(
        direction="runner_to_gateway",
        method="GET",
        path="/v1/models",
        kind="poll",
        runner_id="runner-a",
        status_code=200,
        latency_ms=42.5,
        response_summary='{"model":"llama3"}',
    )
    await bus.emit(
        direction="client_to_gateway",
        method="GET",
        path="/v1/status",
        kind="api",
        status_code=200,
        latency_ms=3.1,
    )

    response = await client.get("/v1/trace/events", params={"limit": 10})
    assert response.status_code == 200
    body = response.json()
    assert body["count"] >= 3
    assert len(body["events"]) >= 3
    for event in body["events"]:
        assert set(event.keys()) >= TRACE_EVENT_KEYS

    poll_outbound = [
        e
        for e in body["events"]
        if e["direction"] == "gateway_to_runner"
        and e["kind"] == "poll"
        and e.get("request_summary") == "health poll"
    ]
    assert len(poll_outbound) == 1

    filtered = await client.get(
        "/v1/trace/events",
        params={"direction": "gateway_to_runner", "kind": "poll"},
    )
    assert filtered.status_code == 200
    events = filtered.json()["events"]
    assert len(events) == 1
    assert events[0]["direction"] == "gateway_to_runner"
    assert events[0]["kind"] == "poll"


@pytest.mark.asyncio
async def test_trace_preserves_phi_in_summaries(trace_client) -> None:
    _client, app = trace_client
    bus: TraceBus = app.state.trace_bus
    await bus.emit(
        direction="client_to_gateway",
        method="POST",
        path="/v1/ai/generate",
        kind="api",
        request_summary="patient_name: Maria Garcia",
    )
    events = await bus.history(limit=1)
    assert events
    summary = events[0]["request_summary"]
    assert "Maria Garcia" in (summary or "")


@pytest.mark.asyncio
async def test_trace_stream_sse_smoke(trace_client) -> None:
    _client, app = trace_client
    bus: TraceBus = app.state.trace_bus

    paths = [getattr(route, "path", None) for route in app.routes]
    assert "/v1/trace/stream" in paths
    assert "/v1/trace/events" in paths

    queue = bus.subscribe()
    try:
        await bus.emit(
            direction="gateway_to_client",
            method="GET",
            path="/v1/status",
            kind="api",
            status_code=200,
            latency_ms=1.2,
            request_id="sse-smoke-req",
        )
        event = await asyncio.wait_for(queue.get(), timeout=1.0)
        assert event is not None
        assert event.request_id == "sse-smoke-req"
        assert event.direction == "gateway_to_client"
    finally:
        bus.unsubscribe(queue)


@pytest.mark.asyncio
async def test_trace_requires_auth(trace_client) -> None:
    _client, app = trace_client
    transport = ASGITransport(app=app)
    async with httpx.AsyncClient(transport=transport, base_url="http://test") as unauth:
        response = await unauth.get("/v1/trace/events")
    assert response.status_code == 401


@pytest.mark.asyncio
async def test_trace_captures_root_operator_routes(trace_client) -> None:
    """Health, readiness, and metrics appear in the live trace buffer."""
    client, _app = trace_client

    health = await client.get("/health")
    assert health.status_code == 200

    metrics = await client.get("/metrics")
    assert metrics.status_code == 200

    ready = await client.get("/ready")
    assert ready.status_code in (200, 503)

    response = await client.get("/v1/trace/events", params={"limit": 50})
    assert response.status_code == 200
    paths = {e["path"] for e in response.json()["events"]}
    assert "/health" in paths
    assert "/metrics" in paths
    assert "/ready" in paths
