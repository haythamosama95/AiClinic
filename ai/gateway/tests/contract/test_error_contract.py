"""Error contract tests — auth precedence and envelope shape."""

from __future__ import annotations

import httpx
import pytest
from httpx import ASGITransport

from gateway.config.settings import GatewayConfig
from gateway.main import create_app
from tests.fixtures.jwt_tokens import make_hs256_token, tamper_token

SECRET = "error-contract-secret"
PROTECTED_PATH = "/v1/status"


@pytest.fixture
async def authed_client():
    config = GatewayConfig(
        jwt_secret=SECRET,
        log_dir="/tmp/gateway-test-logs",
        runners=[],
    )
    app = create_app(config)
    async with app.router.lifespan_context(app):
        transport = ASGITransport(app=app)
        async with httpx.AsyncClient(transport=transport, base_url="http://test") as client:
            yield client


def _assert_error_envelope(body: dict, *, code: str) -> None:
    assert "error" in body
    err = body["error"]
    assert err["code"] == code
    assert isinstance(err["message"], str) and err["message"]
    assert isinstance(err["request_id"], str) and err["request_id"]


@pytest.mark.asyncio
async def test_missing_token_is_unauthenticated_not_forbidden(authed_client) -> None:
    response = await authed_client.get(PROTECTED_PATH)
    assert response.status_code == 401
    _assert_error_envelope(response.json(), code="unauthenticated")
    assert response.headers.get("X-Request-ID")


@pytest.mark.asyncio
async def test_invalid_token_is_unauthenticated(authed_client) -> None:
    token = tamper_token(make_hs256_token(SECRET, staff_role="doctor"))
    response = await authed_client.get(
        PROTECTED_PATH,
        headers={"Authorization": f"Bearer {token}"},
    )
    assert response.status_code == 401
    _assert_error_envelope(response.json(), code="unauthenticated")


@pytest.mark.asyncio
async def test_expired_token_is_unauthenticated(authed_client) -> None:
    token = make_hs256_token(SECRET, staff_role="doctor", exp_delta_s=-120)
    response = await authed_client.get(
        PROTECTED_PATH,
        headers={"Authorization": f"Bearer {token}"},
    )
    assert response.status_code == 401
    _assert_error_envelope(response.json(), code="unauthenticated")


@pytest.mark.asyncio
async def test_role_without_access_is_forbidden(authed_client) -> None:
    token = make_hs256_token(SECRET, staff_role="lab_staff")
    response = await authed_client.get(
        PROTECTED_PATH,
        headers={"Authorization": f"Bearer {token}"},
    )
    assert response.status_code == 403
    _assert_error_envelope(response.json(), code="forbidden")


@pytest.mark.asyncio
async def test_auth_precedence_missing_never_forbidden(authed_client) -> None:
    """A missing token must yield 401, never 403."""
    response = await authed_client.get(PROTECTED_PATH)
    body = response.json()
    assert response.status_code == 401
    assert body["error"]["code"] != "forbidden"


@pytest.mark.asyncio
async def test_valid_token_returns_distinct_success(authed_client) -> None:
    token = make_hs256_token(SECRET, staff_role="administrator")
    response = await authed_client.get(
        PROTECTED_PATH,
        headers={"Authorization": f"Bearer {token}"},
    )
    assert response.status_code == 200
    assert "error" not in response.json()
