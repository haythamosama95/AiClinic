"""Command Protocol envelope assembly."""

from __future__ import annotations

from typing import Any


def assemble_envelope(
    *,
    command_type: str,
    confidence: float,
    display_summary: str,
    params: dict[str, Any],
    requires_resolution: dict[str, str],
    warnings: list[dict[str, str]] | None = None,
    needs_clarification: bool | None = None,
) -> dict[str, Any]:
    """Assemble the single-command Command Protocol envelope.

    Threshold and destructive-command ``needs_clarification`` logic lands in US1 (T023).
    When ``needs_clarification`` is omitted, it defaults to ``False`` (skeleton only).
    """
    return {
        "schema_version": "1.0",
        "task": "command",
        "command_type": command_type,
        "confidence": confidence,
        "display_summary": display_summary,
        "params": params,
        "requires_resolution": requires_resolution,
        "warnings": warnings if warnings is not None else [],
        "needs_clarification": False if needs_clarification is None else needs_clarification,
    }
