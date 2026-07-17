"""Auth matrix contract tests — HS256 and JWKS validation modes."""

from __future__ import annotations

from collections.abc import Callable
from unittest.mock import patch

import httpx
import pytest
from httpx import ASGITransport
from jwt import PyJWKClient

from gateway.config.settings import GatewayConfig
from gateway.main import create_app
from tests.fixtures.jwt_tokens import (
    jwks_document,
    make_hs256_token,
    make_rs256_token,
    tamper_token,
)

HS256_SECRET = "matrix-test-hs256-secret"
JWKS_URL = "https://supabase.test/auth/v1/.well-known/jwks.json"
PROTECTED_PATH = "/v1/status"


def _auth_header(token: str | None) -> dict[str, str]:
    if token is None:
        return {}
    return {"Authorization": f"Bearer {token}"}


@pytest.fixture
def hs256_token_factory() -> Callable[..., str]:
    return lambda **kwargs: make_hs256_token(HS256_SECRET, **kwargs)


@pytest.fixture
def rs256_token_factory() -> Callable[..., str]:
    return lambda **kwargs: make_rs256_token(**kwargs)


@pytest.fixture
async def hs256_client(hs256_token_factory):
    config = GatewayConfig(
        jwt_secret=HS256_SECRET,
        log_dir="/tmp/gateway-test-logs",
        runners=[],
    )
    app = create_app(config)
    async with app.router.lifespan_context(app):
        transport = ASGITransport(app=app)
        async with httpx.AsyncClient(transport=transport, base_url="http://test") as client:
            yield client, hs256_token_factory


@pytest.fixture
async def jwks_client(rs256_token_factory):
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
            async with httpx.AsyncClient(transport=transport, base_url="http://test") as client:
                yield client, rs256_token_factory


async def _assert_matrix(
    client: httpx.AsyncClient,
    token_factory: Callable[..., str],
) -> None:
    """Run the full auth matrix against a protected endpoint."""

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

    nbf_future = token_factory(staff_role="doctor", nbf_delta_s=3600)
    response = await client.get(PROTECTED_PATH, headers=_auth_header(nbf_future))
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
async def test_auth_matrix_hs256(hs256_client) -> None:
    client, token_factory = hs256_client
    await _assert_matrix(client, token_factory)


@pytest.mark.asyncio
async def test_auth_matrix_jwks(jwks_client) -> None:
    client, token_factory = jwks_client
    with patch.object(PyJWKClient, "fetch_data", return_value=jwks_document()) as fetch:
        warm = token_factory(staff_role="doctor")
        await client.get(PROTECTED_PATH, headers=_auth_header(warm))
        assert fetch.call_count == 1
        await _assert_matrix(client, token_factory)
        assert fetch.call_count == 1, "JWKS must be cached — no per-request fetches"
