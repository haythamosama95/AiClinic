"""Capabilities-mirror contract tests — GET /v1/capabilities vs live registry."""

from __future__ import annotations

from typing import Any

import httpx
import pytest
from httpx import ASGITransport

from gateway.config.settings import GatewayConfig, RunnerConfig
from gateway.main import create_app, get_poller
from gateway.routing.lifecycle import RunnerStatus
from gateway.routing.registry import LoadedModel, RunnerRegistry
from tests.fixtures.jwt_tokens import make_hs256_token

TEST_SECRET = "capabilities-test-secret"
CAPABILITIES_PATH = "/v1/capabilities"

CAPABILITIES_TOP_KEYS = frozenset(
    {"schema_version", "streaming", "tasks", "commands", "runners"}
)
RUNNER_CAPABILITY_KEYS = frozenset(
    {"id", "status", "model", "digest", "features", "context_tokens"}
)


def _expected_runner_capability(entry) -> dict[str, Any]:
    """Build the per-runner slice the capabilities report must mirror from the registry."""
    loaded = entry.loaded_model
    return {
        "id": entry.id,
        "status": entry.status.value,
        "model": loaded.name if loaded is not None else None,
        "digest": loaded.digest if loaded is not None else None,
        "features": list(loaded.features) if loaded is not None else [],
        "context_tokens": loaded.context_tokens if loaded is not None else None,
    }


def _expected_capabilities(registry: RunnerRegistry, config: GatewayConfig) -> dict[str, Any]:
    return {
        "schema_version": "1.0",
        "streaming": config.streaming_enabled,
        "tasks": [],
        "commands": [],
        "runners": [_expected_runner_capability(entry) for entry in registry.snapshot()],
    }


@pytest.fixture
async def capabilities_client():
    config = GatewayConfig(
        jwt_secret=TEST_SECRET,
        log_dir="/tmp/gateway-test-logs",
        streaming_enabled=True,
        runners=[
            RunnerConfig(
                id="runner-a",
                base_url="http://runner-a.test:11434",
                capabilities=["json_grammar"],
            ),
            RunnerConfig(
                id="runner-b",
                base_url="http://runner-b.test:11434",
                capabilities=["json_grammar", "vision"],
            ),
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


@pytest.mark.asyncio
async def test_capabilities_returns_200(capabilities_client) -> None:
    client, _app = capabilities_client
    response = await client.get(CAPABILITIES_PATH)
    assert response.status_code == 200


@pytest.mark.asyncio
async def test_capabilities_top_level_shape(capabilities_client) -> None:
    client, _app = capabilities_client
    response = await client.get(CAPABILITIES_PATH)
    body = response.json()

    assert set(body.keys()) == CAPABILITIES_TOP_KEYS
    assert body["schema_version"] == "1.0"
    assert body["streaming"] is True
    assert body["tasks"] == []
    assert body["commands"] == []
    assert isinstance(body["runners"], list)


@pytest.mark.asyncio
async def test_capabilities_mirrors_registry_with_loaded_models(capabilities_client) -> None:
    client, app = capabilities_client
    registry: RunnerRegistry = app.state.registry

    registry.update_entry(
        "runner-a",
        status=RunnerStatus.READY,
        loaded_model=LoadedModel(
            name="qwen3:4b",
            digest="sha256:aaa111",
            context_tokens=8192,
            features=["json_grammar"],
        ),
    )
    registry.update_entry(
        "runner-b",
        status=RunnerStatus.DEGRADED,
        loaded_model=LoadedModel(
            name="qwen3:4b",
            digest="sha256:bbb222",
            context_tokens=4096,
            features=["json_grammar", "vision"],
        ),
    )

    response = await client.get(CAPABILITIES_PATH)
    assert response.status_code == 200
    body = response.json()

    assert body["tasks"] == []
    assert body["commands"] == []
    assert body == _expected_capabilities(registry, app.state.config)


@pytest.mark.asyncio
async def test_capabilities_mirrors_registry_without_loaded_models(capabilities_client) -> None:
    client, app = capabilities_client
    registry: RunnerRegistry = app.state.registry

    registry.update_entry("runner-a", status=RunnerStatus.STARTING)
    registry.update_entry("runner-b", status=RunnerStatus.UNREACHABLE)

    response = await client.get(CAPABILITIES_PATH)
    assert response.status_code == 200
    body = response.json()

    assert len(body["runners"]) == 2
    for runner in body["runners"]:
        assert set(runner.keys()) == RUNNER_CAPABILITY_KEYS
        assert runner["model"] is None
        assert runner["digest"] is None
        assert runner["context_tokens"] is None
        assert runner["features"] == []

    assert body == _expected_capabilities(registry, app.state.config)


@pytest.mark.asyncio
async def test_capabilities_reflects_registry_status_transitions(capabilities_client) -> None:
    client, app = capabilities_client
    registry: RunnerRegistry = app.state.registry

    for status in (
        RunnerStatus.UNKNOWN,
        RunnerStatus.STARTING,
        RunnerStatus.READY,
        RunnerStatus.BUSY,
        RunnerStatus.DEGRADED,
        RunnerStatus.UNREACHABLE,
    ):
        registry.update_entry(
            "runner-a",
            status=status,
            loaded_model=LoadedModel(
                name="qwen3:4b",
                digest="sha256:transition",
                context_tokens=8192,
                features=["json_grammar"],
            ),
        )
        registry.update_entry("runner-b", status=RunnerStatus.UNREACHABLE)

        response = await client.get(CAPABILITIES_PATH)
        assert response.status_code == 200
        body = response.json()
        runner_a = next(r for r in body["runners"] if r["id"] == "runner-a")
        assert runner_a["status"] == status.value
        assert body == _expected_capabilities(registry, app.state.config)
