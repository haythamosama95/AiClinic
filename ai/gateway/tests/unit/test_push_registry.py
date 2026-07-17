"""Unit tests for push registration registry methods."""

from __future__ import annotations

from gateway.config.settings import GatewayConfig, ModelDef, RunnerConfig
from gateway.routing.lifecycle import RunnerStatus
from gateway.routing.registry import LoadedModel, RunnerRegistry


def _push_config() -> GatewayConfig:
    return GatewayConfig(
        jwt_secret="test-secret",
        enable_push_registration=True,
        internal_shared_secret="internal-push-secret",
        runners=[
            RunnerConfig(
                id="static-runner",
                base_url="http://127.0.0.1:11434",
            )
        ],
    )


def test_register_runner_adds_dynamic_entry() -> None:
    registry = RunnerRegistry(_push_config())
    registry.register_runner(
        "dynamic-runner",
        "http://127.0.0.1:11435",
        ["json_grammar"],
        [
            ModelDef(
                name="qwen3:4b",
                source="qwen3:4b",
                digest="sha256:abc",
                context_tokens=8192,
            )
        ],
    )

    entry = registry.get("dynamic-runner")
    assert entry is not None
    assert entry.base_url == "http://127.0.0.1:11435"
    assert entry.declared_capabilities == ["json_grammar"]
    assert len(entry.declared_models) == 1
    assert entry.declared_models[0].name == "qwen3:4b"


def test_register_runner_updates_existing_entry() -> None:
    registry = RunnerRegistry(_push_config())
    registry.register_runner("dynamic-runner", "http://127.0.0.1:11435", ["json_grammar"])
    registry.register_runner("dynamic-runner", "http://127.0.0.1:11436", ["streaming"])

    entry = registry.get("dynamic-runner")
    assert entry is not None
    assert entry.base_url == "http://127.0.0.1:11436"
    assert entry.declared_capabilities == ["streaming"]


def test_apply_heartbeat_updates_status_and_model() -> None:
    registry = RunnerRegistry(_push_config())
    registry.register_runner("dynamic-runner", "http://127.0.0.1:11435", [])

    model = LoadedModel(name="qwen3:4b", digest="sha256:heartbeat", context_tokens=8192)
    assert registry.apply_heartbeat("dynamic-runner", RunnerStatus.READY, model) is True

    entry = registry.get("dynamic-runner")
    assert entry is not None
    assert entry.status == RunnerStatus.READY
    assert entry.loaded_model is not None
    assert entry.loaded_model.name == "qwen3:4b"
    assert entry.last_seen_at is not None
    assert entry.consecutive_failures == 0


def test_apply_heartbeat_unknown_runner_returns_false() -> None:
    registry = RunnerRegistry(_push_config())
    assert registry.apply_heartbeat("missing", RunnerStatus.READY) is False


def test_reload_from_config_preserves_dynamic_runners() -> None:
    cfg = _push_config()
    registry = RunnerRegistry(cfg)
    registry.register_runner("dynamic-runner", "http://127.0.0.1:11435", [])

    registry.reload_from_config(cfg)
    assert registry.get("dynamic-runner") is not None
    assert registry.get("static-runner") is not None
