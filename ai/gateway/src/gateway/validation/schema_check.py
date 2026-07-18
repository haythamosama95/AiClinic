"""Defense-in-depth JSON Schema validation (jsonschema wrapper)."""

from __future__ import annotations

from typing import Any


def validate_command_schema(
    *,
    command_type: str,
    payload: dict[str, Any],
    schema: dict[str, Any],
) -> None:
    """Validate ``payload`` against the per-command JSON Schema.

    Full ``jsonschema.validate`` integration lands in US1 (T021).
    """
    raise NotImplementedError(
        f"schema validation for command_type={command_type!r} is not implemented yet"
    )
