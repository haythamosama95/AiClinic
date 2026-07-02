"""Config fail-fast unit tests."""

from __future__ import annotations

import pytest
from pydantic import ValidationError

from gateway.config.settings import GatewayConfig, ModelDef, RunnerConfig, load_config


def test_valid_config_parses_with_defaults() -> None:
    cfg = GatewayConfig(jwt_secret="test-secret")
    assert cfg.port == 8090
    assert cfg.health_poll_interval_s == 10
    assert cfg.unreachable_after_failures == 3
    assert cfg.role_map["doctor"] is True
    assert cfg.role_map["receptionist"] is False


def test_valid_config_with_runners() -> None:
    cfg = GatewayConfig(
        jwt_secret="test-secret",
        runners=[
            RunnerConfig(
                id="runner-a",
                base_url="http://127.0.0.1:11434",
                models=[
                    ModelDef(
                        name="qwen3:4b",
                        source="qwen3:4b",
                        digest="sha256:abc",
                        context_tokens=8192,
                    )
                ],
            )
        ],
    )
    assert len(cfg.runners) == 1
    assert cfg.runners[0].id == "runner-a"


def test_missing_auth_material_fails_fast() -> None:
    with pytest.raises(ValidationError) as exc:
        GatewayConfig()
    message = str(exc.value)
    assert "jwt_secret" in message or "jwks_url" in message


def test_unknown_key_fails_fast() -> None:
    with pytest.raises(ValidationError) as exc:
        GatewayConfig.model_validate({"jwt_secret": "x", "not_a_key": True})
    assert "not_a_key" in str(exc.value)


def test_invalid_port_type_fails_fast() -> None:
    with pytest.raises(ValidationError) as exc:
        GatewayConfig.model_validate({"jwt_secret": "x", "port": "not-a-number"})
    assert "port" in str(exc.value)


def test_wildcard_origin_rejected() -> None:
    with pytest.raises(ValidationError) as exc:
        GatewayConfig(jwt_secret="x", allowed_origins=["*"])
    assert "allowed_origins" in str(exc.value)


def test_push_registration_requires_internal_secret() -> None:
    with pytest.raises(ValidationError) as exc:
        GatewayConfig(
            jwt_secret="x",
            enable_push_registration=True,
            internal_shared_secret=None,
        )
    assert "internal_shared_secret" in str(exc.value)


def test_load_config_from_yaml_path(tmp_path) -> None:
    config_file = tmp_path / "gateway.yaml"
    config_file.write_text(
        "jwt_secret: from-file\nport: 9001\nrunners: []\n",
        encoding="utf-8",
    )
    cfg = load_config(str(config_file))
    assert cfg.jwt_secret == "from-file"
    assert cfg.port == 9001
