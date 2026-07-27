"""Structured logging preserves verbatim payloads (redaction disabled)."""

from __future__ import annotations

import json
import logging
from collections.abc import Iterator
from pathlib import Path

import pytest
import structlog

from gateway.obs import logging as obs_logging

PATIENT_NAME_FIXTURES: list[tuple[str, str]] = [
    ("patient_name", "Maria Garcia"),
    ("context", "Triage summary for James Wilson"),
    ("prompt", "Draft follow-up for Eleanor Brooks"),
    ("notes", "patient_name: Robert Chen — elevated BP"),
    ("extra", "Referral context for Ada Lovelace"),
]


@pytest.fixture
def log_dir(tmp_path: Path) -> Iterator[Path]:
    structlog.reset_defaults()
    log_dir = tmp_path / "gateway-logs"
    obs_logging.configure_logging(str(log_dir), log_verbatim=True)
    yield log_dir
    logging.getLogger().handlers.clear()
    structlog.reset_defaults()


def _read_log_lines(log_dir: Path) -> list[dict]:
    log_file = log_dir / "gateway.jsonl"
    assert log_file.is_file(), "expected structured log file gateway.jsonl"
    return [json.loads(line) for line in log_file.read_text(encoding="utf-8").splitlines() if line]


def test_patient_name_fixtures_are_logged_verbatim(log_dir: Path) -> None:
    for field_name, phi_value in PATIENT_NAME_FIXTURES:
        obs_logging.log_record(
            request_id=f"req-{field_name}",
            endpoint="/v1/ai/generate",
            outcome="ok",
            caller_staff_id="staff-42",
            **{field_name: phi_value},
        )

    records = _read_log_lines(log_dir)
    assert len(records) == len(PATIENT_NAME_FIXTURES)

    for field_name, phi_value in PATIENT_NAME_FIXTURES:
        matching = [r for r in records if r.get("request_id") == f"req-{field_name}"]
        assert len(matching) == 1
        assert matching[0][field_name] == phi_value
        assert "redacted" not in matching[0]
