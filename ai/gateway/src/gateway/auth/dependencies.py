"""FastAPI auth dependency — offline JWT validation + ai.access gate."""

from __future__ import annotations

from typing import Annotated

from fastapi import Depends, Request
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from gateway.api.errors import ErrorCode, raise_gateway_error
from gateway.auth.jwt_validator import CallerIdentity, JwtValidationError, JwtValidator
from gateway.auth.role_map import RoleMapStore

_bearer = HTTPBearer(auto_error=False)


def get_jwt_validator(request: Request) -> JwtValidator:
    validator = getattr(request.app.state, "jwt_validator", None)
    if validator is None:
        raise RuntimeError("JWT validator not initialized")
    return validator


def get_role_map_store(request: Request) -> RoleMapStore:
    store = getattr(request.app.state, "role_map_store", None)
    if store is None:
        raise RuntimeError("Role map store not initialized")
    return store


async def require_ai_access(
    request: Request,
    credentials: Annotated[HTTPAuthorizationCredentials | None, Depends(_bearer)],
    jwt_validator: Annotated[JwtValidator, Depends(get_jwt_validator)],
    role_map: Annotated[RoleMapStore, Depends(get_role_map_store)],
) -> CallerIdentity:
    """Authenticate via Bearer JWT, then authorize ai.access (401 before 403)."""
    if credentials is None or credentials.scheme.lower() != "bearer":
        raise_gateway_error(
            ErrorCode.UNAUTHENTICATED,
            "Missing or invalid Authorization header",
            request,
        )

    token = credentials.credentials
    try:
        identity = jwt_validator.validate(token)
    except JwtValidationError:
        raise_gateway_error(
            ErrorCode.UNAUTHENTICATED,
            "Invalid or expired token",
            request,
        )

    if not role_map.has_ai_access(identity.staff_role):
        raise_gateway_error(
            ErrorCode.FORBIDDEN,
            "Role does not have ai.access",
            request,
        )

    return identity
