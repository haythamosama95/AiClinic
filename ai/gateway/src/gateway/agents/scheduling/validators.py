"""Per-command semantic validation beyond structural JSON Schema checks."""

from __future__ import annotations

from datetime import date, datetime
from typing import Any

from ai_common.verbose_logging import get_logger

from gateway.agents.base import SemanticValidator
from gateway.agents.scheduling.schemas import (
    APPOINTMENT_STATUSES,
    APPOINTMENT_TYPES,
    DESTRUCTIVE_COMMANDS,
    LOOKUP_REQUIRED,
    REQUIRED_RESOLUTION_FIELDS,
)
from gateway.api.errors import ErrorCode, GatewayError

vlog = get_logger(__name__)

_ENTITY_ID_FIELDS = frozenset({"patient_id", "doctor_id", "appointment_id"})
_AMBIGUITY_WARNING_CODES = frozenset({"ambiguous_ref", "ambiguous_resolution"})


def has_ambiguous_resolution(warnings: list[dict[str, str]]) -> bool:
    """Return ``True`` when warnings indicate unresolved entity ambiguity."""
    return any(
        isinstance(warning, dict) and warning.get("code") in _AMBIGUITY_WARNING_CODES
        for warning in warnings
    )


has_ambiguous_resolved_fields = has_ambiguous_resolution


def is_destructive_command(command_type: str, params: dict[str, Any]) -> bool:
    """Return ``True`` for destructive-class scheduling commands."""
    if command_type in DESTRUCTIVE_COMMANDS:
        return True
    return (
        command_type == "update_appointment_status"
        and params.get("status") == "cancelled"
    )


def _reference_date(context: dict[str, Any]) -> date:
    now_value = context.get("now")
    if now_value is None:
        return datetime.now().astimezone().date()
    if isinstance(now_value, datetime):
        return now_value.date()
    if isinstance(now_value, date):
        return now_value
    parsed = datetime.fromisoformat(str(now_value))
    return parsed.date()


def _parse_iso_date(value: str) -> date:
    return date.fromisoformat(value)


def _raise_unusable(message: str) -> None:
    vlog.v0("Semantic validation failed", detail=message)
    raise GatewayError(ErrorCode.AI_UNUSABLE, message)


def _require_params(parsed: dict[str, Any]) -> dict[str, Any]:
    params = parsed.get("params")
    if not isinstance(params, dict):
        _raise_unusable("params must be an object")
    return params


def _require_resolution(parsed: dict[str, Any]) -> dict[str, Any]:
    requires_resolution = parsed.get("requires_resolution")
    if not isinstance(requires_resolution, dict):
        _raise_unusable("requires_resolution must be an object")
    return requires_resolution


def _assert_no_fabricated_ids(params: dict[str, Any]) -> None:
    fabricated = sorted(_ENTITY_ID_FIELDS.intersection(params))
    if fabricated:
        _raise_unusable(f"params must not contain fabricated entity ids: {', '.join(fabricated)}")


def _assert_required_params(params: dict[str, Any], required: tuple[str, ...]) -> None:
    missing = [field for field in required if not params.get(field)]
    if missing:
        _raise_unusable(f"missing required params: {', '.join(missing)}")


def _assert_not_past_date(field_name: str, value: str, *, context: dict[str, Any]) -> None:
    try:
        candidate = _parse_iso_date(value)
    except ValueError:
        _raise_unusable(f"{field_name} must be a valid ISO date")
    if candidate < _reference_date(context):
        _raise_unusable(f"{field_name} must not be earlier than context.now")


def _assert_requires_resolution(
    requires_resolution: dict[str, Any],
    *,
    command_type: str,
) -> None:
    required_fields = REQUIRED_RESOLUTION_FIELDS[command_type]
    for field_name in required_fields:
        directive = requires_resolution.get(field_name)
        if directive != LOOKUP_REQUIRED:
            _raise_unusable(
                f"requires_resolution.{field_name} must be {LOOKUP_REQUIRED!r}, got {directive!r}"
            )


def _summary_mentions(summary: str, value: str) -> bool:
    return value.casefold() in summary.casefold()


def _appointment_ref_mentioned(summary: str, appointment_ref: str) -> bool:
    if _summary_mentions(summary, appointment_ref):
        return True
    tokens = appointment_ref.split()
    for index in range(len(tokens) - 1):
        phrase = " ".join(tokens[index : index + 2])
        if len(phrase) >= 3 and _summary_mentions(summary, phrase):
            return True
    return len(tokens) == 1 and _summary_mentions(summary, tokens[0])


def _assert_display_summary_consistency(
    parsed: dict[str, Any],
    *,
    command_type: str,
    params: dict[str, Any],
) -> None:
    display_summary = parsed.get("display_summary")
    if not isinstance(display_summary, str) or not display_summary.strip():
        return

    if command_type == "create_appointment":
        for field_name in ("patient_name", "doctor_name"):
            value = params.get(field_name)
            if isinstance(value, str) and not _summary_mentions(display_summary, value):
                _raise_unusable(
                    f"display_summary must mention params.{field_name} ({value!r})"
                )
        return

    appointment_ref = params.get("appointment_ref")
    if isinstance(appointment_ref, str) and not _appointment_ref_mentioned(
        display_summary, appointment_ref
    ):
        _raise_unusable(
            f"display_summary must mention params.appointment_ref ({appointment_ref!r})"
        )


class CreateAppointmentValidator(SemanticValidator):
    def validate(self, parsed: dict[str, Any], *, context: dict[str, Any]) -> None:
        vlog.v2("Validating scheduling command semantics", command_type="create_appointment")
        params = _require_params(parsed)
        requires_resolution = _require_resolution(parsed)
        _assert_no_fabricated_ids(params)
        _assert_required_params(
            params,
            ("patient_name", "doctor_name", "date", "time", "type"),
        )
        if params.get("type") not in APPOINTMENT_TYPES:
            _raise_unusable("params.type must be a legal appointment type")
        _assert_not_past_date("date", str(params["date"]), context=context)
        _assert_requires_resolution(requires_resolution, command_type="create_appointment")
        _assert_display_summary_consistency(
            parsed,
            command_type="create_appointment",
            params=params,
        )


class RescheduleAppointmentValidator(SemanticValidator):
    def validate(self, parsed: dict[str, Any], *, context: dict[str, Any]) -> None:
        vlog.v2("Validating scheduling command semantics", command_type="reschedule_appointment")
        params = _require_params(parsed)
        requires_resolution = _require_resolution(parsed)
        _assert_no_fabricated_ids(params)
        _assert_required_params(params, ("appointment_ref", "new_date", "new_time"))
        _assert_not_past_date("new_date", str(params["new_date"]), context=context)
        _assert_requires_resolution(requires_resolution, command_type="reschedule_appointment")
        _assert_display_summary_consistency(
            parsed,
            command_type="reschedule_appointment",
            params=params,
        )


class CancelAppointmentValidator(SemanticValidator):
    def validate(self, parsed: dict[str, Any], *, context: dict[str, Any]) -> None:
        vlog.v2("Validating scheduling command semantics", command_type="cancel_appointment")
        params = _require_params(parsed)
        requires_resolution = _require_resolution(parsed)
        _assert_no_fabricated_ids(params)
        _assert_required_params(params, ("appointment_ref",))
        _assert_requires_resolution(requires_resolution, command_type="cancel_appointment")
        _assert_display_summary_consistency(
            parsed,
            command_type="cancel_appointment",
            params=params,
        )


class UpdateAppointmentStatusValidator(SemanticValidator):
    def validate(self, parsed: dict[str, Any], *, context: dict[str, Any]) -> None:
        vlog.v2("Validating scheduling command semantics", command_type="update_appointment_status")
        params = _require_params(parsed)
        requires_resolution = _require_resolution(parsed)
        _assert_no_fabricated_ids(params)
        _assert_required_params(params, ("appointment_ref", "status"))
        if params.get("status") not in APPOINTMENT_STATUSES:
            _raise_unusable("params.status must be a legal appointment status")
        _assert_requires_resolution(
            requires_resolution,
            command_type="update_appointment_status",
        )
        _assert_display_summary_consistency(
            parsed,
            command_type="update_appointment_status",
            params=params,
        )


SEMANTIC_VALIDATORS: dict[str, SemanticValidator] = {
    "create_appointment": CreateAppointmentValidator(),
    "reschedule_appointment": RescheduleAppointmentValidator(),
    "cancel_appointment": CancelAppointmentValidator(),
    "update_appointment_status": UpdateAppointmentStatusValidator(),
}
