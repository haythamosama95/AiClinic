"""Agent-agnostic semantic gate and per-agent validator dispatch."""

from __future__ import annotations

from typing import Any

from gateway.agents.base import Agent
from gateway.api.errors import ErrorCode, GatewayError


def validate_semantics(
    *,
    agent: Agent,
    command_type: str,
    parsed: dict[str, Any],
    context: dict[str, Any],
    request_id: str,
) -> None:
    """Ensure ``command_type`` is in the agent catalog, then run semantic validators.

    Raises ``GatewayError`` with ``ai_unusable`` on catalog or semantic failure.
    """
    if command_type not in agent.command_catalog:
        raise GatewayError(
            ErrorCode.AI_UNUSABLE,
            f"command_type {command_type!r} is not in the agent catalog",
            request_id,
        )

    validator = agent.semantic_validators.get(command_type)
    if validator is None:
        raise GatewayError(
            ErrorCode.AI_UNUSABLE,
            f"no semantic validator registered for command_type {command_type!r}",
            request_id,
        )

    try:
        validator.validate(parsed, context=context)
    except GatewayError as exc:
        if exc.request_id is None:
            exc.request_id = request_id
        raise
    except Exception as exc:
        raise GatewayError(
            ErrorCode.AI_UNUSABLE,
            f"semantic validation failed for {command_type!r}: {exc}",
            request_id,
        ) from exc
