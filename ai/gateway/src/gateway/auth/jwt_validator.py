"""Offline JWT validation — HS256 and JWKS (no Supabase network calls per request)."""

from __future__ import annotations

import logging
from dataclasses import dataclass
from typing import Any

import jwt
from jwt import PyJWKClient
from jwt.exceptions import InvalidTokenError

from gateway.config.settings import GatewayConfig

logger = logging.getLogger(__name__)

STAFF_ROLE_CLAIM = "staff_role"


@dataclass(frozen=True)
class CallerIdentity:
    """Transient caller identity extracted from a validated JWT."""

    staff_id: str
    staff_role: str
    exp: int
    nbf: int | None


class JwtValidationError(Exception):
    """JWT could not be validated (maps to unauthenticated)."""


class JwtValidator:
    """Validates Supabase-issued JWTs offline using HS256 or JWKS."""

    def __init__(self, config: GatewayConfig) -> None:
        self._use_jwks = bool(config.jwks_url)
        self._jwt_secret = config.jwt_secret
        self._jwks_client: PyJWKClient | None = None

        if self._use_jwks and config.jwks_url:
            if config.jwt_secret:
                logger.warning(
                    "Both jwt_secret and jwks_url are set; JWKS takes precedence (FR-015)"
                )
            self._jwks_client = PyJWKClient(config.jwks_url, cache_keys=True)
        elif not self._jwt_secret:
            raise ValueError("JwtValidator requires jwt_secret or jwks_url")

    def validate(self, token: str) -> CallerIdentity:
        """Validate signature, exp, and nbf; return caller identity."""
        try:
            if self._use_jwks:
                return self._validate_jwks(token)
            return self._validate_hs256(token)
        except InvalidTokenError as exc:
            raise JwtValidationError(str(exc)) from exc

    def _validate_hs256(self, token: str) -> CallerIdentity:
        assert self._jwt_secret is not None
        payload = jwt.decode(
            token,
            self._jwt_secret,
            algorithms=["HS256"],
            options={"require": ["exp", "sub", STAFF_ROLE_CLAIM]},
        )
        return _identity_from_payload(payload)

    def _validate_jwks(self, token: str) -> CallerIdentity:
        assert self._jwks_client is not None
        signing_key = self._jwks_client.get_signing_key_from_jwt(token)
        payload = jwt.decode(
            token,
            signing_key.key,
            algorithms=["RS256", "RS384", "RS512", "ES256", "ES384", "ES512"],
            options={"require": ["exp", "sub", STAFF_ROLE_CLAIM]},
        )
        return _identity_from_payload(payload)


def _identity_from_payload(payload: dict[str, Any]) -> CallerIdentity:
    staff_role = payload[STAFF_ROLE_CLAIM]
    if not isinstance(staff_role, str) or not staff_role:
        raise JwtValidationError(f"Missing or invalid {STAFF_ROLE_CLAIM} claim")

    staff_id = payload["sub"]
    if not isinstance(staff_id, str) or not staff_id:
        raise JwtValidationError("Missing or invalid sub claim")

    exp = payload["exp"]
    nbf = payload.get("nbf")
    return CallerIdentity(
        staff_id=staff_id,
        staff_role=staff_role,
        exp=int(exp),
        nbf=int(nbf) if nbf is not None else None,
    )
