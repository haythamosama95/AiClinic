"""Defense-in-depth JSON Schema validation (jsonschema wrapper)."""

from __future__ import annotations

from typing import Any

import jsonschema
from jsonschema import Draft202012Validator

from gateway.api.errors import ErrorCode, GatewayError


def validate_command_schema(
    *,
    command_type: str,
    payload: dict[str, Any],
    schema: dict[str, Any],
    request_id: str,
) -> None:
    """Validate ``payload`` against the per-command JSON Schema."""
    validator = Draft202012Validator(schema)
    errors = sorted(validator.iter_errors(payload), key=lambda err: err.path)
    if not errors:
        return

    detail = errors[0].message
    raise GatewayError(
        ErrorCode.AI_UNUSABLE,
        f"schema validation failed for {command_type!r}: {detail}",
        request_id,
    )


def validate_envelope_schema(
    *,
    payload: dict[str, Any],
    schema: dict[str, Any],
    request_id: str,
) -> None:
    """Validate the full model envelope against the scheduling envelope schema."""
    try:
        jsonschema.validate(payload, schema)
    except jsonschema.ValidationError as exc:
        raise GatewayError(
            ErrorCode.AI_UNUSABLE,
            f"envelope schema validation failed: {exc.message}",
            request_id,
        ) from exc
