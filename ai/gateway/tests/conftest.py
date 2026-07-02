"""Shared test harness — in-process ASGI client and config fixtures."""

from __future__ import annotations

from collections.abc import AsyncIterator

import httpx
import pytest
from httpx import ASGITransport

from gateway.config.settings import GatewayConfig
from gateway.main import create_app


@pytest.fixture
def gateway_config() -> GatewayConfig:
    return GatewayConfig(
        jwt_secret="test-secret-for-hs256-validation",
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
async def app(gateway_config: GatewayConfig):
    return create_app(gateway_config)


@pytest.fixture
async def client(app) -> AsyncIterator[httpx.AsyncClient]:
    transport = ASGITransport(app=app)
    async with httpx.AsyncClient(transport=transport, base_url="http://test") as ac:
        yield ac
