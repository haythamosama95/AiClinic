"""Auth package for offline JWT validation and role gating."""

from gateway.auth.dependencies import require_ai_access
from gateway.auth.jwt_validator import CallerIdentity, JwtValidator
from gateway.auth.role_map import RoleMapStore

__all__ = ["CallerIdentity", "JwtValidator", "RoleMapStore", "require_ai_access"]
