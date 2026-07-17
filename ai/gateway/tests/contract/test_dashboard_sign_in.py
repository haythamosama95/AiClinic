"""Contract tests for dashboard Supabase sign-in proxy."""

from __future__ import annotations

import base64
import json

import httpx
import pytest
import respx
from httpx import ASGITransport

from gateway.config.settings import GatewayConfig
from gateway.main import create_app
from tests.fixtures.jwt_tokens import make_hs256_token

TEST_JWT_SECRET = "test-secret-for-hs256-validation"
SUPABASE_URL = "http://127.0.0.1:55321"
ANON_KEY = "test-anon-key"


def _b64url_json(data: dict) -> str:
    raw = json.dumps(data, separators=(",", ":")).encode()
    return base64.urlsafe_b64encode(raw).decode().rstrip("=")


def _fake_access_token(staff_role: str = "administrator") -> str:
    header = _b64url_json({"alg": "HS256", "typ": "JWT"})
    payload = _b64url_json({"sub": "staff-001", "staff_role": staff_role, "exp": 9999999999})
    return f"{header}.{payload}.signature"


@pytest.fixture
def sign_in_config() -> GatewayConfig:
    return GatewayConfig(
        jwt_secret=TEST_JWT_SECRET,
        allowed_origins=["http://localhost:8090"],
        log_dir="/tmp/gateway-test-logs",
        runners=[],
        supabase_url=SUPABASE_URL,
        supabase_anon_key=ANON_KEY,
        dashboard_auto_sign_in=True,
        dashboard_dev_username="admin",
        dashboard_dev_password="admin",
    )


@pytest.fixture
async def sign_in_app(sign_in_config: GatewayConfig):
    application = create_app(sign_in_config)
    async with application.router.lifespan_context(application):
        yield application


@pytest.fixture
async def sign_in_client(sign_in_app) -> httpx.AsyncClient:
    transport = ASGITransport(app=sign_in_app)
    async with httpx.AsyncClient(transport=transport, base_url="http://test") as ac:
        yield ac


@pytest.mark.asyncio
async def test_auth_config_when_sign_in_enabled(sign_in_client: httpx.AsyncClient) -> None:
    response = await sign_in_client.get("/v1/dashboard/auth-config")
    assert response.status_code == 200
    body = response.json()
    assert body["sign_in_enabled"] is True
    assert body["auto_sign_in"] is True
    assert body["default_username"] == "admin"
    assert body["supabase_url"] == SUPABASE_URL


@pytest.mark.asyncio
async def test_auth_config_when_not_configured(gateway_config: GatewayConfig) -> None:
    app = create_app(gateway_config)
    transport = ASGITransport(app=app)
    async with app.router.lifespan_context(app), httpx.AsyncClient(
        transport=transport, base_url="http://test"
    ) as client:
        response = await client.get("/v1/dashboard/auth-config")
    assert response.status_code == 200
    assert response.json()["sign_in_enabled"] is False


@pytest.mark.asyncio
@respx.mock
async def test_auto_sign_in_success(sign_in_client: httpx.AsyncClient) -> None:
    token = _fake_access_token("administrator")
    respx.post(f"{SUPABASE_URL}/auth/v1/token?grant_type=password").mock(
        return_value=httpx.Response(200, json={"access_token": token, "expires_in": 3600})
    )

    response = await sign_in_client.post("/v1/dashboard/auto-sign-in")
    assert response.status_code == 200
    body = response.json()
    assert body["staff_role"] == "administrator"
    assert body["has_ai_access"] is True


@pytest.mark.asyncio
async def test_auto_sign_in_disabled(gateway_config: GatewayConfig) -> None:
    app = create_app(gateway_config)
    transport = ASGITransport(app=app)
    async with app.router.lifespan_context(app), httpx.AsyncClient(
        transport=transport, base_url="http://test"
    ) as client:
        response = await client.post("/v1/dashboard/auto-sign-in")
    assert response.status_code == 501


@pytest.mark.asyncio
@respx.mock
async def test_sign_in_success(sign_in_client: httpx.AsyncClient) -> None:
    token = _fake_access_token("doctor")
    respx.post(f"{SUPABASE_URL}/auth/v1/token?grant_type=password").mock(
        return_value=httpx.Response(200, json={"access_token": token, "expires_in": 3600})
    )

    response = await sign_in_client.post(
        "/v1/dashboard/sign-in",
        json={"username": "admin", "password": "admin"},
    )
    assert response.status_code == 200
    body = response.json()
    assert body["access_token"] == token
    assert body["staff_role"] == "doctor"
    assert body["has_ai_access"] is True


@pytest.mark.asyncio
@respx.mock
async def test_sign_in_forbidden_role(sign_in_client: httpx.AsyncClient) -> None:
    token = _fake_access_token("receptionist")
    respx.post(f"{SUPABASE_URL}/auth/v1/token?grant_type=password").mock(
        return_value=httpx.Response(200, json={"access_token": token, "expires_in": 3600})
    )

    response = await sign_in_client.post(
        "/v1/dashboard/sign-in",
        json={"username": "desk", "password": "desk"},
    )
    assert response.status_code == 200
    assert response.json()["has_ai_access"] is False


@pytest.mark.asyncio
@respx.mock
async def test_sign_in_invalid_credentials(sign_in_client: httpx.AsyncClient) -> None:
    respx.post(f"{SUPABASE_URL}/auth/v1/token?grant_type=password").mock(
        return_value=httpx.Response(400, json={"msg": "Invalid login credentials"})
    )

    response = await sign_in_client.post(
        "/v1/dashboard/sign-in",
        json={"username": "admin", "password": "wrong"},
    )
    assert response.status_code == 401
    assert response.json()["error"]["code"] == "unauthenticated"


@pytest.mark.asyncio
async def test_sign_in_not_configured(gateway_config: GatewayConfig) -> None:
    app = create_app(gateway_config)
    transport = ASGITransport(app=app)
    async with app.router.lifespan_context(app), httpx.AsyncClient(
        transport=transport, base_url="http://test"
    ) as client:
        response = await client.post(
            "/v1/dashboard/sign-in",
            json={"username": "admin", "password": "admin"},
        )
    assert response.status_code == 501
    assert response.json()["error"]["code"] == "not_implemented"


@pytest.mark.asyncio
async def test_sign_in_endpoint_is_public(sign_in_client: httpx.AsyncClient) -> None:
    """Sign-in must not require an existing Bearer token."""
    with respx.mock:
        respx.post(f"{SUPABASE_URL}/auth/v1/token?grant_type=password").mock(
            return_value=httpx.Response(
                200,
                json={"access_token": _fake_access_token(), "expires_in": 3600},
            )
        )
        response = await sign_in_client.post(
            "/v1/dashboard/sign-in",
            json={"username": "admin", "password": "admin"},
            headers={},
        )
    assert response.status_code == 200


@pytest.mark.asyncio
async def test_signed_in_token_works_on_protected_route(sign_in_client: httpx.AsyncClient) -> None:
    token = make_hs256_token(TEST_JWT_SECRET, staff_role="doctor")
    response = await sign_in_client.get("/ready", headers={"Authorization": f"Bearer {token}"})
    assert response.status_code in (200, 503)
