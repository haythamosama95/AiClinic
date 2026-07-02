"""Runner non-routability contract tests."""

from __future__ import annotations

import re
from pathlib import Path

AI_ROOT = Path(__file__).resolve().parents[3]
COMPOSE_FILE = AI_ROOT / "runners" / "ollama" / "docker-compose.yaml"
EXAMPLE_CONFIG = AI_ROOT / "gateway" / "config" / "gateway.example.yaml"


def test_ollama_compose_binds_localhost_only() -> None:
    assert COMPOSE_FILE.is_file(), f"missing {COMPOSE_FILE}"
    content = COMPOSE_FILE.read_text(encoding="utf-8")
    assert "127.0.0.1:11434:11434" in content.replace(" ", "")


def test_example_runner_base_url_is_ai_internal() -> None:
    content = EXAMPLE_CONFIG.read_text(encoding="utf-8")
    match = re.search(r"base_url:\s*(http://[^\s#]+)", content)
    assert match is not None
    assert match.group(1).startswith("http://127.0.0.1")


def test_compose_does_not_publish_runner_on_all_interfaces() -> None:
    content = COMPOSE_FILE.read_text(encoding="utf-8")
    assert '"11434:11434"' not in content
    assert "0.0.0.0:11434" not in content
