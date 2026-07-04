"""Shared test harness — in-process ASGI client and config fixtures."""

from __future__ import annotations

from collections.abc import AsyncIterator

import httpx
import pytest
from httpx import ASGITransport

from gateway.config.settings import GatewayConfig
from gateway.main import create_app
from tests.fixtures.jwt_tokens import make_hs256_token

TEST_JWT_SECRET = "test-secret-for-hs256-validation"


@pytest.fixture
def gateway_config() -> GatewayConfig:
    return GatewayConfig(
        jwt_secret=TEST_JWT_SECRET,
        allowed_origins=["http://localhost:3000"],
        log_dir="/tmp/gateway-test-logs",
        runners=[],
    )


@pytest.fixture
def gateway_config_jwks() -> GatewayConfig:
    return GatewayConfig(
        jwks_url="https://example.test/.well-known/jwks.json",
        allowed_origins=["http://localhost:3000"],
        log_dir="/tmp/gateway-test-logs",
        runners=[],
    )


@pytest.fixture
def auth_headers() -> dict[str, str]:
    token = make_hs256_token(TEST_JWT_SECRET, staff_role="doctor")
    return {"Authorization": f"Bearer {token}"}


@pytest.fixture
async def app(gateway_config: GatewayConfig):
    application = create_app(gateway_config)
    async with application.router.lifespan_context(application):
        yield application


@pytest.fixture
async def client(app, auth_headers) -> AsyncIterator[httpx.AsyncClient]:
    transport = ASGITransport(app=app)
    async with httpx.AsyncClient(
        transport=transport,
        base_url="http://test",
        headers=auth_headers,
    ) as ac:
        yield ac
