"""Gateway configuration models with fail-fast validation."""

from __future__ import annotations

import os
from pathlib import Path
from typing import Any

import yaml
from ai_common.verbose_logging import get_logger
from pydantic import Field, field_validator, model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict

vlog = get_logger(__name__)


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
    shutdown_grace_s: int = Field(default=10, gt=0)
    log_verbatim_retention_hours: int = Field(default=24, gt=0)
    models_dir: str | None = None
    role_ai_access: dict[str, bool] = Field(default_factory=lambda: dict(RoleAiAccessMap.DEFAULTS))
    log_dir: str = "./logs"
    dashboard_dir: str | None = None
    # Optional — enables dashboard Supabase sign-in proxy (public anon key only).
    supabase_url: str | None = None
    supabase_anon_key: str | None = None
    # Dev dashboard — sign in automatically with bootstrap admin (local only).
    dashboard_auto_sign_in: bool = False
    dashboard_dev_username: str = "admin"
    dashboard_dev_password: str = "admin"

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
        vlog.v0("Loading gateway config from YAML", path=path)
        with open(path, encoding="utf-8") as fh:
            raw = yaml.safe_load(fh) or {}
        config = cls.model_validate(raw)
        vlog.v1(
            "Loaded gateway config from YAML",
            path=path,
            runner_count=len(config.runners),
            port=config.port,
        )
        return config

    @classmethod
    def from_mapping(cls, data: dict[str, Any]) -> GatewayConfig:
        return cls.model_validate(data)


def _gateway_root() -> Path:
    return Path(__file__).resolve().parents[3]


def _resolve_config_path(path: str | None) -> Path | None:
    if path:
        return Path(path)
    env_path = os.environ.get("GATEWAY_CONFIG_PATH")
    if env_path:
        return Path(env_path)
    default = _gateway_root() / "config" / "gateway.yaml"
    if default.is_file():
        return default
    return None


def load_config(path: str | None = None) -> GatewayConfig:
    """Load gateway config from YAML (if present) or environment variables."""
    vlog.v0("Loading gateway configuration", path=path)
    config_path = _resolve_config_path(path)
    if config_path is not None:
        config = GatewayConfig.from_yaml(str(config_path))
    else:
        vlog.v1("Using default gateway configuration from environment")
        config = GatewayConfig()
    vlog.v1(
        "Gateway configuration loaded",
        runner_count=len(config.runners),
        port=config.port,
        config_path=str(config_path) if config_path else None,
    )
    return config
