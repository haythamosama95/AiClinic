"""Repair common runner envelope deviations before schema validation."""

from __future__ import annotations

from typing import Any

from gateway.agents.scheduling.schemas import LOOKUP_REQUIRED, REQUIRED_RESOLUTION_FIELDS


def normalize_scheduling_envelope(parsed: dict[str, Any]) -> dict[str, Any]:
    """Normalize runner JSON into the scheduling envelope shape when possible."""
    out = dict(parsed)

    if "command_type" not in out and "command" in out:
        out["command_type"] = out.pop("command")

    out.setdefault("schema_version", "1.0")
    out.setdefault("task", "command")
    out.setdefault("warnings", [])

    params = out.get("params")
    if isinstance(params, dict):
        for key in (
            "confidence",
            "display_summary",
            "needs_clarification",
            "requires_resolution",
        ):
            if key in params and key not in out:
                out[key] = params.pop(key)

    command_type = out.get("command_type")
    if isinstance(command_type, str):
        required = REQUIRED_RESOLUTION_FIELDS.get(command_type, ())
        req = out.get("requires_resolution")
        if not isinstance(req, dict):
            req = {}
        if not all(
            field in req and req[field] == LOOKUP_REQUIRED for field in required
        ):
            out["requires_resolution"] = {
                field: LOOKUP_REQUIRED for field in required
            }

    return out
