"""Dashboard helper — Supabase staff sign-in (dev control plane only)."""

from __future__ import annotations

import base64
import json
import logging
from typing import Any

import httpx
from ai_common.verbose_logging import get_logger
from fastapi import APIRouter, Request
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field

from gateway.api.errors import ErrorCode, GatewayError, raise_gateway_error
from gateway.config.settings import GatewayConfig

logger = logging.getLogger(__name__)
vlog = get_logger(__name__)

router = APIRouter(prefix="/v1/dashboard", tags=["dashboard"])

_SIGN_IN_TIMEOUT_S = 10.0


class SignInRequest(BaseModel):
    username: str = Field(min_length=1, max_length=64)
    password: str = Field(min_length=1, max_length=256)


def _sign_in_configured(cfg: GatewayConfig) -> bool:
    return bool(cfg.supabase_url and cfg.supabase_anon_key)


def _staff_role_from_token(access_token: str) -> str | None:
    parts = access_token.split(".")
    if len(parts) < 2:
        return None
    try:
        payload_b64 = parts[1]
        padding = "=" * (-len(payload_b64) % 4)
        payload = json.loads(base64.urlsafe_b64decode(payload_b64 + padding))
    except (json.JSONDecodeError, ValueError, UnicodeDecodeError):
        return None
    role = payload.get("staff_role")
    return role if isinstance(role, str) and role else None


@router.get("/auth-config")
async def get_auth_config(request: Request) -> JSONResponse:
    """Public hint for the dashboard — whether Supabase sign-in is configured."""
    vlog.v0("Fetching dashboard auth configuration")
    cfg: GatewayConfig = request.app.state.config
    body = {
        "sign_in_enabled": _sign_in_configured(cfg),
        "auto_sign_in": bool(cfg.dashboard_auto_sign_in and _sign_in_configured(cfg)),
        "default_username": cfg.dashboard_dev_username if cfg.dashboard_auto_sign_in else None,
        "supabase_url": cfg.supabase_url,
    }
    vlog.v1("Returned dashboard auth configuration", sign_in_enabled=body["sign_in_enabled"])
    return JSONResponse(body)


@router.post("/auto-sign-in")
async def auto_sign_in(request: Request) -> JSONResponse:
    """Sign in with gateway-configured dev credentials (dashboard bootstrap)."""
    vlog.v0("Attempting dashboard auto sign-in")
    cfg: GatewayConfig = request.app.state.config
    if not cfg.dashboard_auto_sign_in:
        vlog.v0("Dashboard auto sign-in is disabled")
        raise_gateway_error(
            ErrorCode.NOT_IMPLEMENTED,
            "Dashboard auto sign-in is disabled (set dashboard_auto_sign_in: true)",
            request,
        )
    return await _sign_in_with_credentials(
        request,
        cfg,
        cfg.dashboard_dev_username,
        cfg.dashboard_dev_password,
    )


@router.post("/sign-in")
async def sign_in(request: Request, body: SignInRequest) -> JSONResponse:
    """Exchange staff username/password for a Supabase access token (same-origin proxy)."""
    vlog.v0("Processing dashboard sign-in request", username=body.username.strip())
    cfg: GatewayConfig = request.app.state.config
    if not _sign_in_configured(cfg):
        vlog.v0("Dashboard sign-in is not configured")
        raise_gateway_error(
            ErrorCode.NOT_IMPLEMENTED,
            "Supabase sign-in is not configured (set supabase_url and supabase_anon_key)",
            request,
        )
    return await _sign_in_with_credentials(request, cfg, body.username.strip(), body.password)


async def _sign_in_with_credentials(
    request: Request,
    cfg: GatewayConfig,
    username: str,
    password: str,
) -> JSONResponse:
    vlog.v0("Authenticating dashboard user with Supabase", username=username)
    if not _sign_in_configured(cfg):
        vlog.v0("Supabase sign-in is not configured")
        raise_gateway_error(
            ErrorCode.NOT_IMPLEMENTED,
            "Supabase sign-in is not configured (set supabase_url and supabase_anon_key)",
            request,
        )

    assert cfg.supabase_url is not None
    assert cfg.supabase_anon_key is not None

    url = f"{cfg.supabase_url.rstrip('/')}/auth/v1/token?grant_type=password"
    headers = {
        "apikey": cfg.supabase_anon_key,
        "Authorization": f"Bearer {cfg.supabase_anon_key}",
        "Content-Type": "application/json",
    }
    payload = {"email": username, "password": password}

    try:
        async with httpx.AsyncClient(timeout=_SIGN_IN_TIMEOUT_S) as client:
            response = await client.post(url, headers=headers, json=payload)
    except httpx.RequestError as exc:
        logger.warning("Supabase sign-in request failed: %s", exc)
        vlog.v0("Supabase sign-in request failed", error=str(exc))
        rid = getattr(request.state, "request_id", "unknown")
        raise GatewayError(
            ErrorCode.AI_NO_CAPACITY,
            "Could not reach Supabase auth — is the clinic stack running?",
            rid,
        ) from exc

    if response.status_code == 404:
        vlog.v0("Supabase auth endpoint not found")
        raise_gateway_error(
            ErrorCode.AI_NO_CAPACITY,
            (
                f"Supabase auth not found at {cfg.supabase_url} "
                "(404). Is the clinic stack running? "
                "Local dev usually uses http://127.0.0.1:54321 from `supabase start`."
            ),
            request,
        )

    if response.status_code >= 400:
        detail = _extract_supabase_error(response)
        vlog.v0("Supabase authentication failed", status_code=response.status_code)
        raise_gateway_error(ErrorCode.UNAUTHENTICATED, detail, request)

    data = response.json()
    access_token = data.get("access_token")
    if not isinstance(access_token, str) or not access_token:
        vlog.v0("Supabase response missing access token")
        raise_gateway_error(
            ErrorCode.BAD_REQUEST,
            "Supabase response did not include an access_token",
            request,
        )

    staff_role = _staff_role_from_token(access_token)
    if not staff_role:
        vlog.v0("JWT missing staff_role claim")
        raise_gateway_error(
            ErrorCode.BAD_REQUEST,
            "JWT missing staff_role claim — check GoTrue custom access token hook",
            request,
        )

    has_ai_access = bool(cfg.role_map.get(staff_role, False))
    expires_in = data.get("expires_in")
    body_out: dict[str, Any] = {
        "access_token": access_token,
        "expires_in": int(expires_in) if isinstance(expires_in, int | float) else None,
        "staff_role": staff_role,
        "has_ai_access": has_ai_access,
    }
    vlog.v1(
        "Dashboard sign-in succeeded",
        staff_role=staff_role,
        has_ai_access=has_ai_access,
    )
    return JSONResponse(body_out)


def _extract_supabase_error(response: httpx.Response) -> str:
    if response.status_code == 404:
        return "Supabase auth endpoint not found — check supabase_url in gateway.yaml"
    try:
        payload = response.json()
    except json.JSONDecodeError:
        text = (response.text or "").strip()
        if text:
            return text[:200]
        return "Invalid username or password"
    if isinstance(payload, dict):
        msg = payload.get("msg") or payload.get("error_description") or payload.get("message")
        if isinstance(msg, str) and msg.strip():
            return msg.strip()
    return "Invalid username or password"
