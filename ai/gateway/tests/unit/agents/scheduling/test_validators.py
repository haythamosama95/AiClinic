"""Unit tests for scheduling semantic validators."""

from __future__ import annotations

import pytest

from gateway.agents.scheduling.validators import (
    CancelAppointmentValidator,
    CreateAppointmentValidator,
    RescheduleAppointmentValidator,
    UpdateAppointmentStatusValidator,
    has_ambiguous_resolution,
    is_destructive_command,
)
from gateway.api.errors import ErrorCode, GatewayError
from gateway.validation.envelope import assemble_envelope

CONTEXT = {"now": "2026-07-18T12:00:00+03:00"}


def _create_payload(**overrides: object) -> dict:
    payload = {
        "command_type": "create_appointment",
        "display_summary": "Book Ahmed with Dr Ali tomorrow at 5pm",
        "params": {
            "patient_name": "Ahmed",
            "doctor_name": "Dr Ali",
            "date": "2026-07-19",
            "time": "17:00",
            "type": "planned",
        },
        "requires_resolution": {
            "patient_id": "lookup_required",
            "doctor_id": "lookup_required",
        },
        "warnings": [],
    }
    payload.update(overrides)
    return payload


def test_create_validator_rejects_past_date() -> None:
    payload = _create_payload(
        params={
            "patient_name": "Ahmed",
            "doctor_name": "Dr Ali",
            "date": "2020-01-01",
            "time": "17:00",
            "type": "planned",
        }
    )
    with pytest.raises(GatewayError) as exc:
        CreateAppointmentValidator().validate(payload, context=CONTEXT)
    assert exc.value.code == ErrorCode.AI_UNUSABLE


def test_create_validator_rejects_illegal_enum() -> None:
    payload = _create_payload(
        params={
            "patient_name": "Ahmed",
            "doctor_name": "Dr Ali",
            "date": "2026-07-19",
            "time": "17:00",
            "type": "walk_in",
        }
    )
    with pytest.raises(GatewayError):
        CreateAppointmentValidator().validate(payload, context=CONTEXT)


def test_create_validator_rejects_missing_required_param() -> None:
    payload = _create_payload(
        params={
            "patient_name": "Ahmed",
            "doctor_name": "Dr Ali",
            "date": "2026-07-19",
            "time": "17:00",
        }
    )
    with pytest.raises(GatewayError):
        CreateAppointmentValidator().validate(payload, context=CONTEXT)


def test_create_validator_rejects_display_summary_mismatch() -> None:
    payload = _create_payload(display_summary="Book an appointment tomorrow")
    with pytest.raises(GatewayError):
        CreateAppointmentValidator().validate(payload, context=CONTEXT)


def test_reschedule_validator_requires_resolution_fields() -> None:
    payload = {
        "display_summary": "Reschedule Ahmed",
        "params": {
            "appointment_ref": "Ahmed tomorrow",
            "new_date": "2026-07-20",
            "new_time": "10:00",
        },
        "requires_resolution": {"appointment_id": "lookup_required"},
    }
    with pytest.raises(GatewayError):
        RescheduleAppointmentValidator().validate(payload, context=CONTEXT)


def test_cancel_validator_accepts_valid_payload() -> None:
    payload = {
        "params": {"appointment_ref": "Ahmed tomorrow"},
        "requires_resolution": {"appointment_id": "lookup_required"},
    }
    CancelAppointmentValidator().validate(payload, context=CONTEXT)


def test_update_status_validator_rejects_illegal_status() -> None:
    payload = {
        "params": {"appointment_ref": "ref", "status": "invalid"},
        "requires_resolution": {"appointment_id": "lookup_required"},
    }
    with pytest.raises(GatewayError):
        UpdateAppointmentStatusValidator().validate(payload, context=CONTEXT)


def test_destructive_command_with_ambiguous_warning_forces_clarification() -> None:
    warnings = [
        {
            "code": "ambiguous_ref",
            "message": 'Multiple doctors named "Ali" found.',
        }
    ]
    envelope = assemble_envelope(
        command_type="cancel_appointment",
        confidence=0.95,
        display_summary="Cancel Ahmed's appointment",
        params={"appointment_ref": "Ahmed tomorrow"},
        requires_resolution={"appointment_id": "lookup_required"},
        warnings=warnings,
        confidence_threshold=0.6,
    )
    assert envelope["needs_clarification"] is True
    assert is_destructive_command("cancel_appointment", envelope["params"])
    assert has_ambiguous_resolution(warnings)
