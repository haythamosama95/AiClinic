"""Agent-agnostic semantic gate and per-agent validator dispatch."""

from __future__ import annotations

from typing import Any

from ai_common.verbose_logging import get_logger

from gateway.agents.base import Agent
from gateway.agents.scheduling.schemas import SCHEDULING_COMMANDS
from gateway.api.errors import ErrorCode, GatewayError

_SCHEDULING_COMMAND_ALLOWLIST: frozenset[str] = frozenset(SCHEDULING_COMMANDS)

vlog = get_logger(__name__)


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
    vlog.v0("Validating command semantics", command_type=command_type, request_id=request_id)
    if command_type not in _SCHEDULING_COMMAND_ALLOWLIST:
        vlog.v0("Rejected disallowed scheduling command", command_type=command_type)
        raise GatewayError(
            ErrorCode.AI_UNUSABLE,
            f"command_type {command_type!r} is not an allowed scheduling command",
            request_id,
        )

    if command_type not in agent.command_catalog:
        vlog.v0("Command type not in agent catalog", command_type=command_type)
        raise GatewayError(
            ErrorCode.AI_UNUSABLE,
            f"command_type {command_type!r} is not in the agent catalog",
            request_id,
        )

    validator = agent.semantic_validators.get(command_type)
    if validator is None:
        vlog.v0("No semantic validator for command type", command_type=command_type)
        raise GatewayError(
            ErrorCode.AI_UNUSABLE,
            f"no semantic validator registered for command_type {command_type!r}",
            request_id,
        )

    try:
        vlog.v2("Running semantic validator", command_type=command_type)
        validator.validate(parsed, context=context)
    except GatewayError as exc:
        vlog.v0("Semantic validation raised gateway error", command_type=command_type)
        if exc.request_id is None:
            exc.request_id = request_id
        raise
    except Exception as exc:
        vlog.v0("Semantic validation failed", command_type=command_type, error=str(exc))
        raise GatewayError(
            ErrorCode.AI_UNUSABLE,
            f"semantic validation failed for {command_type!r}: {exc}",
            request_id,
        ) from exc
    vlog.v1("Semantic validation passed", command_type=command_type, request_id=request_id)
