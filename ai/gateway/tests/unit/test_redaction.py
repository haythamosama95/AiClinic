"""PHI-redaction verification — patient-name fixtures must not appear verbatim (SC-012, FR-034)."""

from __future__ import annotations

import json
import logging
from collections.abc import Iterator
from pathlib import Path

import pytest
import structlog

from gateway.obs import logging as obs_logging

# Realistic caller-supplied PHI fixtures that must never reach logs verbatim.
PATIENT_NAME_FIXTURES: list[tuple[str, str]] = [
    ("patient_name", "Maria Garcia"),
    ("context", "Triage summary for James Wilson"),
    ("prompt", "Draft follow-up for Eleanor Brooks"),
    ("notes", "patient_name: Robert Chen — elevated BP"),
    ("extra", "Referral context for Ada Lovelace"),
]


@pytest.fixture
def redacted_log_dir(tmp_path: Path) -> Iterator[Path]:
    """Configure gateway logging with PHI redaction enabled (default)."""
    structlog.reset_defaults()
    log_dir = tmp_path / "gateway-logs"
    obs_logging.configure_logging(str(log_dir), log_verbatim=False)
    yield log_dir
    logging.getLogger().handlers.clear()
    structlog.reset_defaults()


@pytest.fixture
def verbatim_log_dir(tmp_path: Path) -> Iterator[Path]:
    """Configure gateway logging with verbatim PHI logging explicitly enabled."""
    structlog.reset_defaults()
    log_dir = tmp_path / "gateway-logs-verbatim"
    obs_logging.configure_logging(str(log_dir), log_verbatim=True)
    yield log_dir
    logging.getLogger().handlers.clear()
    structlog.reset_defaults()


def _read_log_lines(log_dir: Path) -> list[dict]:
    log_file = log_dir / "gateway.jsonl"
    assert log_file.is_file(), "expected structured log file gateway.jsonl"
    return [json.loads(line) for line in log_file.read_text(encoding="utf-8").splitlines() if line]


def test_patient_name_fixtures_never_appear_verbatim_when_log_verbatim_false(
    redacted_log_dir: Path,
) -> None:
    """With log_verbatim=false, patient-name fixtures are hashed and never logged verbatim."""
    for field_name, phi_value in PATIENT_NAME_FIXTURES:
        obs_logging.log_record(
            request_id=f"req-redact-{field_name}",
            endpoint="/v1/ai/generate",
            outcome="ok",
            caller_staff_id="staff-42",
            **{field_name: phi_value},
        )

    records = _read_log_lines(redacted_log_dir)
    assert len(records) == len(PATIENT_NAME_FIXTURES)

    serialized = "\n".join(json.dumps(record) for record in records)

    for field_name, phi_value in PATIENT_NAME_FIXTURES:
        assert phi_value not in serialized, (
            f"verbatim PHI leaked for field {field_name!r}: {phi_value!r}"
        )

    for record in records:
        assert record.get("redacted") is True
        for field_name, phi_value in PATIENT_NAME_FIXTURES:
            if record.get("request_id") != f"req-redact-{field_name}":
                continue
            redacted_value = record[field_name]
            assert redacted_value != phi_value
            assert redacted_value.startswith("sha256:")


def test_log_verbatim_true_allows_patient_names(verbatim_log_dir: Path) -> None:
    """Verbatim mode is opt-in: fixtures appear when log_verbatim=true."""
    field_name, phi_value = PATIENT_NAME_FIXTURES[0]
    obs_logging.log_record(
        request_id="req-verbatim",
        endpoint="/v1/ai/generate",
        outcome="ok",
        **{field_name: phi_value},
    )

    records = _read_log_lines(verbatim_log_dir)
    assert len(records) == 1
    assert records[0][field_name] == phi_value
    assert "redacted" not in records[0]
