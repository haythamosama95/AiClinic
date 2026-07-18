"""Command Protocol envelope assembly."""

from __future__ import annotations

from typing import Any

from gateway.agents.scheduling.validators import (
    has_ambiguous_resolution,
    is_destructive_command,
)


def compute_needs_clarification(
    *,
    confidence: float,
    command_type: str,
    params: dict[str, Any],
    warnings: list[dict[str, str]],
    confidence_threshold: float,
) -> bool:
    """Gateway-set clarification flag per command-protocol.md §1.1."""
    if confidence < confidence_threshold:
        return True
    if is_destructive_command(command_type, params) and has_ambiguous_resolution(warnings):
        return True
    return False


def assemble_envelope(
    *,
    command_type: str,
    confidence: float,
    display_summary: str,
    params: dict[str, Any],
    requires_resolution: dict[str, str],
    warnings: list[dict[str, str]] | None = None,
    needs_clarification: bool | None = None,
    confidence_threshold: float = 0.6,
) -> dict[str, Any]:
    """Assemble the single-command Command Protocol envelope."""
    resolved_warnings = warnings if warnings is not None else []
    clarification = (
        compute_needs_clarification(
            confidence=confidence,
            command_type=command_type,
            params=params,
            warnings=resolved_warnings,
            confidence_threshold=confidence_threshold,
        )
        if needs_clarification is None
        else needs_clarification
    )
    return {
        "schema_version": "1.0",
        "task": "command",
        "command_type": command_type,
        "confidence": confidence,
        "display_summary": display_summary,
        "params": params,
        "requires_resolution": requires_resolution,
        "warnings": resolved_warnings,
        "needs_clarification": clarification,
    }
