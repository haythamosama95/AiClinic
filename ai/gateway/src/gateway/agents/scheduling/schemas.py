"""Scheduling command param schemas and envelope JSON Schema (Draft 2020-12)."""

from __future__ import annotations

from copy import deepcopy
from enum import StrEnum
from typing import Any, Literal

from pydantic import BaseModel, ConfigDict, Field

JSON_SCHEMA_DRAFT = "https://json-schema.org/draft/2020-12/schema"
LOOKUP_REQUIRED = "lookup_required"
TIME_PATTERN = r"^([01][0-9]|2[0-3]):[0-5][0-9]$"


class CommandType(StrEnum):
    CREATE_APPOINTMENT = "create_appointment"
    RESCHEDULE_APPOINTMENT = "reschedule_appointment"
    CANCEL_APPOINTMENT = "cancel_appointment"
    UPDATE_APPOINTMENT_STATUS = "update_appointment_status"


SCHEDULING_COMMANDS: tuple[str, ...] = tuple(cmd.value for cmd in CommandType)
COMMAND_CATALOG: frozenset[str] = frozenset(SCHEDULING_COMMANDS)


class AppointmentType(StrEnum):
    PLANNED = "planned"
    EMERGENCY = "emergency"
    FOLLOW_UP = "follow_up"


class AppointmentStatus(StrEnum):
    SCHEDULED = "scheduled"
    ARRIVED = "arrived"
    COMPLETED = "completed"
    CANCELLED = "cancelled"
    NO_SHOW = "no_show"


APPOINTMENT_TYPES: tuple[str, ...] = tuple(item.value for item in AppointmentType)
APPOINTMENT_STATUSES: tuple[str, ...] = tuple(item.value for item in AppointmentStatus)

REQUIRED_RESOLUTION_FIELDS: dict[str, tuple[str, ...]] = {
    CommandType.CREATE_APPOINTMENT.value: ("patient_id", "doctor_id"),
    CommandType.RESCHEDULE_APPOINTMENT.value: (
        "appointment_id",
        "patient_id",
        "doctor_id",
    ),
    CommandType.CANCEL_APPOINTMENT.value: ("appointment_id",),
    CommandType.UPDATE_APPOINTMENT_STATUS.value: ("appointment_id",),
}

DESTRUCTIVE_COMMANDS: frozenset[str] = frozenset(
    {
        CommandType.CANCEL_APPOINTMENT.value,
        CommandType.RESCHEDULE_APPOINTMENT.value,
    }
)


class Warning(BaseModel):
    model_config = ConfigDict(extra="forbid")

    code: str
    message: str


class CreateAppointmentParams(BaseModel):
    """Human-facing reference fields precede structural decision fields."""

    model_config = ConfigDict(extra="forbid")

    patient_name: str = Field(min_length=1)
    doctor_name: str = Field(min_length=1)
    date: str = Field(json_schema_extra={"format": "date"})
    time: str = Field(pattern=TIME_PATTERN)
    type: AppointmentType
    notes: str | None = None


class RescheduleAppointmentParams(BaseModel):
    model_config = ConfigDict(extra="forbid")

    appointment_ref: str = Field(min_length=1)
    new_date: str = Field(json_schema_extra={"format": "date"})
    new_time: str = Field(pattern=TIME_PATTERN)
    reason: str | None = None


class CancelAppointmentParams(BaseModel):
    model_config = ConfigDict(extra="forbid")

    appointment_ref: str = Field(min_length=1)
    reason: str | None = None


class UpdateAppointmentStatusParams(BaseModel):
    model_config = ConfigDict(extra="forbid")

    appointment_ref: str = Field(min_length=1)
    status: AppointmentStatus


class SchedulingCommandEnvelope(BaseModel):
    """Top-level command envelope; ``display_summary`` precedes decision fields."""

    model_config = ConfigDict(extra="forbid")

    schema_version: Literal["1.0"] = "1.0"
    task: Literal["command"] = "command"
    command_type: CommandType
    confidence: float = Field(ge=0.0, le=1.0)
    display_summary: str = Field(min_length=1)
    params: (
        CreateAppointmentParams
        | RescheduleAppointmentParams
        | CancelAppointmentParams
        | UpdateAppointmentStatusParams
    )
    requires_resolution: dict[str, Literal["lookup_required"]]
    warnings: list[Warning]
    needs_clarification: bool


_PARAMS_MODELS: dict[str, type[BaseModel]] = {
    CommandType.CREATE_APPOINTMENT.value: CreateAppointmentParams,
    CommandType.RESCHEDULE_APPOINTMENT.value: RescheduleAppointmentParams,
    CommandType.CANCEL_APPOINTMENT.value: CancelAppointmentParams,
    CommandType.UPDATE_APPOINTMENT_STATUS.value: UpdateAppointmentStatusParams,
}

_PARAMS_DEF_NAMES: dict[str, str] = {
    CommandType.CREATE_APPOINTMENT.value: "create_appointment_params",
    CommandType.RESCHEDULE_APPOINTMENT.value: "reschedule_appointment_params",
    CommandType.CANCEL_APPOINTMENT.value: "cancel_appointment_params",
    CommandType.UPDATE_APPOINTMENT_STATUS.value: "update_appointment_status_params",
}


def _params_json_schema(model: type[BaseModel]) -> dict[str, Any]:
    schema = model.model_json_schema()
    schema.pop("title", None)
    return schema


CREATE_APPOINTMENT_PARAMS_SCHEMA = _params_json_schema(CreateAppointmentParams)
RESCHEDULE_APPOINTMENT_PARAMS_SCHEMA = _params_json_schema(RescheduleAppointmentParams)
CANCEL_APPOINTMENT_PARAMS_SCHEMA = _params_json_schema(CancelAppointmentParams)
UPDATE_APPOINTMENT_STATUS_PARAMS_SCHEMA = _params_json_schema(UpdateAppointmentStatusParams)

COMMAND_PARAM_SCHEMAS: dict[str, dict[str, Any]] = {
    CommandType.CREATE_APPOINTMENT.value: CREATE_APPOINTMENT_PARAMS_SCHEMA,
    CommandType.RESCHEDULE_APPOINTMENT.value: RESCHEDULE_APPOINTMENT_PARAMS_SCHEMA,
    CommandType.CANCEL_APPOINTMENT.value: CANCEL_APPOINTMENT_PARAMS_SCHEMA,
    CommandType.UPDATE_APPOINTMENT_STATUS.value: UPDATE_APPOINTMENT_STATUS_PARAMS_SCHEMA,
}


def command_params_schema(command_type: str) -> dict[str, Any]:
    """Return the per-command ``params`` JSON Schema for ``command_type``."""
    return deepcopy(COMMAND_PARAM_SCHEMAS[command_type])


def command_schemas() -> dict[str, dict[str, Any]]:
    """Per-command ``params`` schemas keyed by ``command_type``."""
    return deepcopy(COMMAND_PARAM_SCHEMAS)


def _hoist_nested_defs(schema: dict[str, Any]) -> tuple[dict[str, Any], dict[str, Any]]:
    """Split nested ``$defs`` out of a sub-schema for envelope composition.

    Pydantic emits per-model ``$defs`` (e.g. ``AppointmentType``) with ``$ref`` pointers
    at the document root. When those models are embedded under envelope ``$defs``, refs must
    resolve against the envelope root — so nested defs are hoisted and stripped here.
    """
    schema = deepcopy(schema)
    nested = schema.pop("$defs", None) or {}
    return schema, nested


def build_envelope_schema() -> dict[str, Any]:
    """Full scheduling envelope schema for Ollama ``format`` and defense-in-depth."""
    defs: dict[str, Any] = {}
    for command_type, def_name in _PARAMS_DEF_NAMES.items():
        param_schema, nested = _hoist_nested_defs(COMMAND_PARAM_SCHEMAS[command_type])
        defs.update(nested)
        defs[def_name] = param_schema
    return {
        "$schema": JSON_SCHEMA_DRAFT,
        "title": "SchedulingCommandEnvelope",
        "type": "object",
        "additionalProperties": False,
        "required": [
            "schema_version",
            "task",
            "command_type",
            "confidence",
            "display_summary",
            "params",
            "requires_resolution",
            "warnings",
            "needs_clarification",
        ],
        "properties": {
            "schema_version": {"type": "string", "const": "1.0"},
            "task": {"type": "string", "const": "command"},
            "command_type": {"type": "string", "enum": list(SCHEDULING_COMMANDS)},
            "confidence": {"type": "number", "minimum": 0, "maximum": 1},
            "display_summary": {"type": "string", "minLength": 1},
            "params": {
                "oneOf": [
                    {"$ref": f"#/$defs/{def_name}"}
                    for def_name in _PARAMS_DEF_NAMES.values()
                ]
            },
            "requires_resolution": {
                "type": "object",
                "additionalProperties": {"type": "string", "const": LOOKUP_REQUIRED},
            },
            "warnings": {
                "type": "array",
                "items": {
                    "type": "object",
                    "additionalProperties": False,
                    "required": ["code", "message"],
                    "properties": {
                        "code": {"type": "string"},
                        "message": {"type": "string"},
                    },
                },
            },
            "needs_clarification": {"type": "boolean"},
        },
        "$defs": defs,
    }


def envelope_schema() -> dict[str, Any]:
    """Alias for :func:`build_envelope_schema`."""
    return build_envelope_schema()
