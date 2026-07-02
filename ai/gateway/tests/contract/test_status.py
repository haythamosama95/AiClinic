"""Control-plane status endpoint contract tests."""

from __future__ import annotations

import json
from typing import Any

import httpx
import pytest
from httpx import ASGITransport

from gateway.config.settings import GatewayConfig, RunnerConfig
from gateway.main import create_app
from gateway.routing.lifecycle import RunnerStatus

GATEWAY_KEYS = frozenset({"version", "ready", "phase_active", "uptime_s"})
CONFIG_SAFE_KEYS = frozenset(
    {
        "port",
        "health_poll_interval_s",
        "unreachable_after_failures",
        "allowed_origins",
        "log_dir",
        "streaming_enabled",
        "enable_multi_command_plans",
        "enable_push_registration",
        "log_verbatim",
    }
)
RUNNER_KEYS = frozenset(
    {
        "id",
        "base_url",
        "status",
        "last_seen_at",
        "last_latency_ms",
        "avg_latency_ms",
        "consecutive_failures",
        "in_flight",
        "declared_capabilities",
        "declared_models",
        "loaded_model",
    }
)
LOADED_MODEL_KEYS = frozenset({"name", "digest", "context_tokens", "features"})
ENDPOINT_KEYS = frozenset({"path", "method", "phase", "available"})


@pytest.fixture
async def status_client():
    config = GatewayConfig(
        jwt_secret="test-secret",
        log_dir="/tmp/gateway-test-logs",
        health_poll_interval_s=15,
        unreachable_after_failures=4,
        allowed_origins=["http://localhost:3000"],
        streaming_enabled=True,
        enable_multi_command_plans=False,
        enable_push_registration=False,
        log_verbatim=True,
        runners=[
            RunnerConfig(
                id="runner-a",
                base_url="http://127.0.0.1:11434",
            )
        ],
    )
    app = create_app(config)
    async with app.router.lifespan_context(app):
        transport = ASGITransport(app=app)
        async with httpx.AsyncClient(transport=transport, base_url="http://test") as client:
            yield client, app


def _collect_keys(obj: Any, *, path: str = "") -> list[str]:
    found: list[str] = []
    if isinstance(obj, dict):
        for key, value in obj.items():
            key_path = f"{path}.{key}" if path else key
            found.append(key_path)
            found.extend(_collect_keys(value, path=key_path))
    elif isinstance(obj, list):
        for index, item in enumerate(obj):
            found.extend(_collect_keys(item, path=f"{path}[{index}]"))
    return found


def _assert_no_secret_keys(obj: Any) -> None:
    for key_path in _collect_keys(obj):
        leaf = key_path.rsplit(".", 1)[-1]
        assert "jwt_secret" not in leaf
        assert "internal_shared_secret" not in leaf


@pytest.mark.asyncio
async def test_status_returns_200(status_client) -> None:
    client, _app = status_client
    response = await client.get("/v1/status")
    assert response.status_code == 200


@pytest.mark.asyncio
async def test_status_response_shape(status_client) -> None:
    client, _app = status_client
    response = await client.get("/v1/status")
    body = response.json()

    assert set(body["gateway"].keys()) >= GATEWAY_KEYS
    assert set(body["config_safe"].keys()) >= CONFIG_SAFE_KEYS
    assert isinstance(body["runners"], list)
    assert isinstance(body["endpoints"], list)
    assert "architecture" in body
    assert "poller" in body
    assert body["poller"]["estimated_failover_s"] == 60

    assert body["gateway"]["phase_active"] == 3
    assert isinstance(body["gateway"]["ready"], bool)
    assert isinstance(body["gateway"]["uptime_s"], int | float)
    assert body["gateway"]["uptime_s"] >= 0

    assert body["config_safe"]["health_poll_interval_s"] == 15
    assert body["config_safe"]["unreachable_after_failures"] == 4
    assert body["config_safe"]["allowed_origins"] == ["http://localhost:3000"]


@pytest.mark.asyncio
async def test_status_excludes_jwt_secret(status_client) -> None:
    client, _app = status_client
    response = await client.get("/v1/status")
    body = response.json()

    _assert_no_secret_keys(body)
    serialized = json.dumps(body)
    assert "jwt_secret" not in serialized
    assert "test-secret" not in serialized


@pytest.mark.asyncio
async def test_status_runners_present_and_match_registry(status_client) -> None:
    client, app = status_client
    app.state.registry.update_entry(
        "runner-a",
        status=RunnerStatus.READY,
        consecutive_failures=0,
        in_flight=1,
    )

    response = await client.get("/v1/status")
    body = response.json()

    assert len(body["runners"]) == 1
    runner = body["runners"][0]
    assert set(runner.keys()) >= RUNNER_KEYS
    assert runner["id"] == "runner-a"
    assert isinstance(runner["declared_models"], list)
    assert runner["base_url"] == "http://127.0.0.1:11434"
    assert runner["status"] == RunnerStatus.READY.value
    assert runner["in_flight"] == 1
    assert isinstance(runner["declared_capabilities"], list)

    loaded_model = runner["loaded_model"]
    assert loaded_model is None or set(loaded_model.keys()) >= LOADED_MODEL_KEYS


@pytest.mark.asyncio
async def test_status_endpoints_catalog_present(status_client) -> None:
    client, _app = status_client
    response = await client.get("/v1/status")
    body = response.json()

    assert len(body["endpoints"]) > 0
    for entry in body["endpoints"]:
        assert set(entry.keys()) >= ENDPOINT_KEYS
        assert entry["path"].startswith("/")
        assert entry["method"] in {"GET", "POST", "PUT", "PATCH", "DELETE"}
        assert isinstance(entry["phase"], int)
        assert isinstance(entry["available"], bool)

    paths = {entry["path"] for entry in body["endpoints"]}
    assert "/health" in paths
    assert "/ready" in paths
    assert "/metrics" in paths
    assert "/v1/status" in paths
    assert "/v1/runners/runner-a/models" in paths
