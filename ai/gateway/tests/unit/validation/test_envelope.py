"""Unit tests for Command Protocol envelope assembly."""

from __future__ import annotations

from gateway.validation.envelope import assemble_envelope, compute_needs_clarification


def _base_kwargs() -> dict:
    return {
        "command_type": "create_appointment",
        "display_summary": "Book Ahmed with Dr Ali",
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


def test_needs_clarification_true_below_threshold() -> None:
    envelope = assemble_envelope(confidence=0.4, confidence_threshold=0.6, **_base_kwargs())
    assert envelope["needs_clarification"] is True
    assert envelope["confidence"] == 0.4


def test_needs_clarification_false_at_threshold() -> None:
    envelope = assemble_envelope(confidence=0.6, confidence_threshold=0.6, **_base_kwargs())
    assert envelope["needs_clarification"] is False


def test_destructive_cancel_with_ambiguity_forces_clarification() -> None:
    warnings = [{"code": "ambiguous_ref", "message": "ambiguous"}]
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


def test_destructive_reschedule_with_ambiguity_forces_clarification() -> None:
    warnings = [{"code": "ambiguous_ref", "message": "ambiguous"}]
    assert compute_needs_clarification(
        confidence=0.9,
        command_type="reschedule_appointment",
        params={"appointment_ref": "x", "new_date": "2026-07-20", "new_time": "10:00"},
        warnings=warnings,
        confidence_threshold=0.6,
    ) is True


def test_cancelled_status_update_destructive_with_ambiguity() -> None:
    warnings = [{"code": "ambiguous_ref", "message": "ambiguous"}]
    envelope = assemble_envelope(
        command_type="update_appointment_status",
        confidence=0.9,
        display_summary="Cancel Ahmed's appointment",
        params={"appointment_ref": "ref", "status": "cancelled"},
        requires_resolution={"appointment_id": "lookup_required"},
        warnings=warnings,
        confidence_threshold=0.6,
    )
    assert envelope["needs_clarification"] is True


def test_confidence_always_emitted() -> None:
    envelope = assemble_envelope(confidence=0.55, confidence_threshold=0.6, **_base_kwargs())
    assert "confidence" in envelope
    assert envelope["confidence"] == 0.55
