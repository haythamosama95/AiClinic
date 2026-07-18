"""Phase 1 regression suite — core endpoints and contracts remain stable after feature 016."""

from __future__ import annotations

from collections.abc import Callable
from typing import Any
from unittest.mock import patch

import httpx
import pytest
import respx
from httpx import ASGITransport
from jwt import PyJWKClient

from gateway.api.capabilities import SCHEDULING_COMMANDS, SCHEDULING_TASKS
from gateway.config.settings import GatewayConfig, RunnerConfig
from gateway.main import create_app, get_poller
from gateway.routing.lifecycle import RunnerStatus
from gateway.routing.registry import LoadedModel, RunnerRegistry
from tests.fixtures.jwt_tokens import (
    jwks_document,
    make_hs256_token,
    make_rs256_token,
    tamper_token,
)

HS256_SECRET = "phase1-regression-hs256-secret"
JWKS_URL = "https://supabase.test/auth/v1/.well-known/jwks.json"
PROTECTED_PATH = "/v1/status"
CAPABILITIES_PATH = "/v1/capabilities"
RUNNER_URL = "http://runner.test:11434"
RUNNER_MODELS = f"{RUNNER_URL}/v1/models"

CAPABILITIES_TOP_KEYS = frozenset(
    {"schema_version", "streaming", "tasks", "commands", "runners"}
)


def _auth_header(token: str | None) -> dict[str, str]:
    if token is None:
        return {}
    return {"Authorization": f"Bearer {token}"}


def _assert_error_envelope(body: dict[str, Any], *, code: str) -> None:
    assert "error" in body
    err = body["error"]
    assert err["code"] == code
    assert isinstance(err["message"], str) and err["message"]
    assert isinstance(err["request_id"], str) and err["request_id"]


@pytest.fixture
async def regression_client():
    config = GatewayConfig(
        jwt_secret=HS256_SECRET,
        log_dir="/tmp/gateway-test-logs",
        streaming_enabled=True,
        health_poll_interval_s=60,
        runners=[
            RunnerConfig(id="runner-a", base_url=RUNNER_URL),
        ],
    )
    app = create_app(config)
    token = make_hs256_token(HS256_SECRET, staff_role="doctor")
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


# --- /health ---


@pytest.mark.asyncio
async def test_health_returns_200(regression_client) -> None:
    client, _app = regression_client
    response = await client.get("/health")
    assert response.status_code == 200
    assert response.json()["status"] == "ok"


# --- /ready ---


@pytest.mark.asyncio
@respx.mock
async def test_ready_returns_503_when_no_runner_is_ready(regression_client) -> None:
    client, app = regression_client
    respx.get(RUNNER_MODELS).mock(
        return_value=httpx.Response(503, json={"error": "loading"})
    )
    poller = get_poller()
    assert poller is not None
    await poller.stop()
    await poller.poll_once()

    response = await client.get("/ready")
    assert response.status_code == 503
    body = response.json()
    assert body["error"]["code"] == "ai_no_capacity"
    assert body["error"]["request_id"]
    assert app.state.registry.ready is False


@pytest.mark.asyncio
async def test_ready_returns_200_when_runner_is_ready(regression_client) -> None:
    client, app = regression_client
    app.state.registry.update_entry("runner-a", status=RunnerStatus.READY)
    response = await client.get("/ready")
    assert response.status_code == 200
    assert response.json()["status"] == "ready"


# --- /v1/capabilities (Phase 1 shape) ---


def _expected_capabilities(registry: RunnerRegistry, config: GatewayConfig) -> dict[str, Any]:
    runners = []
    for entry in registry.snapshot():
        loaded = entry.loaded_model
        runners.append(
            {
                "id": entry.id,
                "status": entry.status.value,
                "model": loaded.name if loaded is not None else None,
                "digest": loaded.digest if loaded is not None else None,
                "features": list(loaded.features) if loaded is not None else [],
                "context_tokens": loaded.context_tokens if loaded is not None else None,
            }
        )
    return {
        "schema_version": "1.0",
        "streaming": config.streaming_enabled,
        "tasks": list(SCHEDULING_TASKS),
        "commands": list(SCHEDULING_COMMANDS),
        "runners": runners,
    }


@pytest.mark.asyncio
async def test_capabilities_phase1_shape(regression_client) -> None:
    client, app = regression_client
    registry: RunnerRegistry = app.state.registry
    registry.update_entry(
        "runner-a",
        status=RunnerStatus.READY,
        loaded_model=LoadedModel(
            name="qwen3:4b",
            digest="sha256:phase1",
            context_tokens=8192,
            features=["json_grammar"],
        ),
    )

    response = await client.get(CAPABILITIES_PATH)
    assert response.status_code == 200
    body = response.json()

    assert set(body.keys()) == CAPABILITIES_TOP_KEYS
    assert body["schema_version"] == "1.0"
    assert body["tasks"] == list(SCHEDULING_TASKS)
    assert body["commands"] == list(SCHEDULING_COMMANDS)
    assert body == _expected_capabilities(registry, app.state.config)


# --- auth matrix basics ---


async def _assert_auth_matrix(
    client: httpx.AsyncClient,
    token_factory: Callable[..., str],
) -> None:
    valid = token_factory(staff_role="doctor")
    response = await client.get(PROTECTED_PATH, headers=_auth_header(valid))
    assert response.status_code == 200

    tampered = tamper_token(valid)
    response = await client.get(PROTECTED_PATH, headers=_auth_header(tampered))
    assert response.status_code == 401
    assert response.json()["error"]["code"] == "unauthenticated"

    expired = token_factory(staff_role="doctor", exp_delta_s=-60)
    response = await client.get(PROTECTED_PATH, headers=_auth_header(expired))
    assert response.status_code == 401
    assert response.json()["error"]["code"] == "unauthenticated"

    response = await client.get(PROTECTED_PATH)
    assert response.status_code == 401
    assert response.json()["error"]["code"] == "unauthenticated"

    no_access = token_factory(staff_role="receptionist")
    response = await client.get(PROTECTED_PATH, headers=_auth_header(no_access))
    assert response.status_code == 403
    assert response.json()["error"]["code"] == "forbidden"


@pytest.mark.asyncio
async def test_auth_matrix_hs256(regression_client) -> None:
    client, app = regression_client
    transport = ASGITransport(app=app)

    def token_factory(**kwargs: object) -> str:
        return make_hs256_token(HS256_SECRET, **kwargs)

    async with httpx.AsyncClient(transport=transport, base_url="http://test") as matrix_client:
        await _assert_auth_matrix(matrix_client, token_factory)


@pytest.mark.asyncio
async def test_auth_matrix_jwks() -> None:
    doc = jwks_document()
    with patch.object(PyJWKClient, "fetch_data", return_value=doc):
        config = GatewayConfig(
            jwks_url=JWKS_URL,
            log_dir="/tmp/gateway-test-logs",
            runners=[],
        )
        app = create_app(config)
        async with app.router.lifespan_context(app):
            transport = ASGITransport(app=app)

            def token_factory(**kwargs: object) -> str:
                return make_rs256_token(**kwargs)

            async with httpx.AsyncClient(transport=transport, base_url="http://test") as client:
                await _assert_auth_matrix(client, token_factory)


# --- error contract (Phase 1 codes) ---


@pytest.mark.asyncio
async def test_error_contract_unauthenticated(regression_client) -> None:
    client, _app = regression_client
    transport = client._transport
    async with httpx.AsyncClient(transport=transport, base_url="http://test") as unauthed:
        response = await unauthed.get(PROTECTED_PATH)
    assert response.status_code == 401
    _assert_error_envelope(response.json(), code="unauthenticated")
    assert response.headers.get("X-Request-ID")


@pytest.mark.asyncio
async def test_error_contract_forbidden(regression_client) -> None:
    client, _app = regression_client
    token = make_hs256_token(HS256_SECRET, staff_role="lab_staff")
    transport = client._transport
    async with httpx.AsyncClient(
        transport=transport,
        base_url="http://test",
        headers=_auth_header(token),
    ) as restricted:
        response = await restricted.get(PROTECTED_PATH)
    assert response.status_code == 403
    _assert_error_envelope(response.json(), code="forbidden")


@pytest.mark.asyncio
async def test_error_contract_auth_precedence(regression_client) -> None:
    """Missing token must yield 401, never 403."""
    client, _app = regression_client
    transport = client._transport
    async with httpx.AsyncClient(transport=transport, base_url="http://test") as unauthed:
        response = await unauthed.get(PROTECTED_PATH)
    assert response.status_code == 401
    assert response.json()["error"]["code"] != "forbidden"
