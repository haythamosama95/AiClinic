"""Defense-in-depth JSON Schema validation (jsonschema wrapper)."""

from __future__ import annotations

from typing import Any

import jsonschema
from ai_common.verbose_logging import get_logger
from jsonschema import Draft202012Validator

from gateway.api.errors import ErrorCode, GatewayError

vlog = get_logger(__name__)


def validate_command_schema(
    *,
    command_type: str,
    payload: dict[str, Any],
    schema: dict[str, Any],
    request_id: str,
) -> None:
    """Validate ``payload`` against the per-command JSON Schema."""
    vlog.v0("Validating command params against schema", command_type=command_type, request_id=request_id)
    validator = Draft202012Validator(schema)
    errors = sorted(validator.iter_errors(payload), key=lambda err: err.path)
    if not errors:
        vlog.v1("Command params schema validation passed", command_type=command_type)
        return

    detail = errors[0].message
    vlog.v0("Command params schema validation failed", command_type=command_type, detail=detail)
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
    vlog.v0("Validating envelope against schema", request_id=request_id)
    try:
        jsonschema.validate(payload, schema)
    except jsonschema.ValidationError as exc:
        vlog.v0("Envelope schema validation failed", detail=exc.message)
        raise GatewayError(
            ErrorCode.AI_UNUSABLE,
            f"envelope schema validation failed: {exc.message}",
            request_id,
        ) from exc
    vlog.v1("Envelope schema validation passed", request_id=request_id)
