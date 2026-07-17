"""Packaging security contract — FR-005/FR-022."""

from __future__ import annotations

from pathlib import Path

AI_ROOT = Path(__file__).resolve().parents[3]
DOCKERFILE = AI_ROOT / "gateway" / "Dockerfile"
GATEWAY_COMPOSE = AI_ROOT / "gateway" / "docker-compose.yaml"
OLLAMA_COMPOSE = AI_ROOT / "runners" / "ollama" / "docker-compose.yaml"


def test_gateway_dockerfile_runs_non_root() -> None:
    content = DOCKERFILE.read_text(encoding="utf-8")
    assert "useradd" in content
    assert "USER gateway" in content
    assert "no-create-home" in content


def test_gateway_dockerfile_scopes_writable_paths() -> None:
    content = DOCKERFILE.read_text(encoding="utf-8")
    assert "/var/log/gateway" in content
    assert "/app/config" in content
    assert "chmod -R a-w /app/src" in content


def test_gateway_compose_supervised_with_scoped_volumes() -> None:
    content = GATEWAY_COMPOSE.read_text(encoding="utf-8")
    assert "restart: always" in content
    assert "./config:/app/config:ro" in content.replace(" ", "")
    assert "gateway_logs:/var/log/gateway" in content.replace(" ", "")


def test_ollama_compose_supervised_localhost_only() -> None:
    content = OLLAMA_COMPOSE.read_text(encoding="utf-8")
    assert "restart: always" in content
    assert "127.0.0.1:11434:11434" in content.replace(" ", "")
