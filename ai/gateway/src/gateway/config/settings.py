"""Gateway configuration models with fail-fast validation."""

from __future__ import annotations

from typing import Any

import yaml
from pydantic import Field, field_validator, model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class ModelDef(BaseSettings):
    """Declared model definition for a runner."""

    model_config = SettingsConfigDict(extra="forbid")

    name: str
    source: str
    digest: str
    context_tokens: int = Field(gt=0)
    capabilities: list[str] = Field(default_factory=list)


class RunnerConfig(BaseSettings):
    """Static runner endpoint and declared capabilities."""

    model_config = SettingsConfigDict(extra="forbid")

    id: str
    base_url: str
    capabilities: list[str] = Field(default_factory=list)
    models: list[ModelDef] = Field(default_factory=list)


class RoleAiAccessMap(dict[str, bool]):
    """Role → ai.access allowlist. Reloadable at runtime (Phase 3)."""

    DEFAULTS: dict[str, bool] = {
        "administrator": True,
        "doctor": True,
        "receptionist": False,
        "lab_staff": False,
    }

    @classmethod
    def from_mapping(cls, mapping: dict[str, bool] | None = None) -> RoleAiAccessMap:
        merged = dict(cls.DEFAULTS)
        if mapping:
            merged.update(mapping)
        return cls(merged)


class GatewayConfig(BaseSettings):
    """Gateway configuration loaded from YAML + environment overrides."""

    model_config = SettingsConfigDict(
        extra="forbid",
        env_prefix="GATEWAY_",
        env_nested_delimiter="__",
    )

    port: int = Field(default=8090, ge=1, le=65535)
    runners: list[RunnerConfig] = Field(default_factory=list)
    health_poll_interval_s: int = Field(default=10, gt=0)
    unreachable_after_failures: int = Field(default=3, gt=0)
    queue_max_depth: int = Field(default=16, gt=0)
    queue_max_wait_s: int = Field(default=20, gt=0)
    max_inflight_per_caller: int = Field(default=2, gt=0)
    timeout_total_s: int = Field(default=45, gt=0)
    timeout_first_token_s: int = Field(default=15, gt=0)
    confidence_threshold: float = Field(default=0.6, ge=0.0, le=1.0)
    jwt_secret: str | None = None
    jwks_url: str | None = None
    allowed_origins: list[str] = Field(default_factory=lambda: ["http://localhost:3000"])
    log_verbatim: bool = False
    enable_push_registration: bool = False
    internal_shared_secret: str | None = None
    streaming_enabled: bool = True
    enable_multi_command_plans: bool = False
    model_swap_first_token_timeout_s: int = Field(default=60, gt=0)
    models_dir: str | None = None
    role_ai_access: dict[str, bool] = Field(default_factory=lambda: dict(RoleAiAccessMap.DEFAULTS))
    log_dir: str = "./logs"

    @field_validator("allowed_origins")
    @classmethod
    def reject_wildcard_origins(cls, origins: list[str]) -> list[str]:
        if "*" in origins:
            raise ValueError("allowed_origins must not contain '*'")
        return origins

    @model_validator(mode="after")
    def validate_auth_and_push(self) -> GatewayConfig:
        if not self.jwt_secret and not self.jwks_url:
            raise ValueError("At least one of jwt_secret or jwks_url must be set")
        if self.enable_push_registration and not self.internal_shared_secret:
            raise ValueError(
                "internal_shared_secret is required when enable_push_registration=true"
            )
        return self

    @property
    def role_map(self) -> RoleAiAccessMap:
        return RoleAiAccessMap.from_mapping(self.role_ai_access)

    @classmethod
    def from_yaml(cls, path: str) -> GatewayConfig:
        with open(path, encoding="utf-8") as fh:
            raw = yaml.safe_load(fh) or {}
        return cls.model_validate(raw)

    @classmethod
    def from_mapping(cls, data: dict[str, Any]) -> GatewayConfig:
        return cls.model_validate(data)


def load_config(path: str | None = None) -> GatewayConfig:
    """Load gateway config from YAML file or environment."""
    if path:
        return GatewayConfig.from_yaml(path)
    return GatewayConfig()
