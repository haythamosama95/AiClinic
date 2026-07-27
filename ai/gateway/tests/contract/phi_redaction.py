"""PHI redaction contract tests — SC-009 (US4)."""

from __future__ import annotations

import json
import logging
from collections.abc import Iterator
from logging.handlers import TimedRotatingFileHandler
from pathlib import Path

import httpx
import pytest
import respx
import structlog
from httpx import ASGITransport

from gateway.config.settings import GatewayConfig, RunnerConfig
from gateway.main import create_app, get_poller
from gateway.obs import logging as obs_logging
from gateway.obs.redaction import build_log_file_handler
from gateway.routing.lifecycle import RunnerStatus
from gateway.routing.registry import LoadedModel
from tests.fixtures.fake_runner import ChatScriptMode, envelope_for_mode
from tests.fixtures.jwt_tokens import make_hs256_token

TEST_SECRET = "phi-redaction-secret"
GENERATE_PATH = "/v1/ai/generate"
RUNNER_URL = "http://runner-a.test:11434"
CHAT_URL = f"{RUNNER_URL}/api/chat"
METRICS_PATH = "/metrics"

PATIENT_NAME_FIXTURES: list[str] = [
    "Maria Garcia",
    "James Wilson",
    "Eleanor Brooks",
    "Robert Chen",
]

GENERATION_PROMPT_FIXTURE = "Draft follow-up for Eleanor Brooks"
GENERATION_CONTEXT_FIXTURE = {
    "now": "2026-07-18T12:00:00+03:00",
    "branch_name": "Main",
    "patient_name": "Maria Garcia",
    "notes": "Triage summary for James Wilson",
}

PATIENT_FIXTURES: list[tuple[str, str]] = [
    ("prompt", "Draft follow-up for Eleanor Brooks"),
    ("context", "Triage summary for James Wilson"),
    ("params", '{"patient_name": "Maria Garcia"}'),
    ("display_summary", "Book Maria Garcia with Dr Patel tomorrow"),
    ("notes", "patient_name: Robert Chen — elevated BP"),
]


def _chat_response(envelope: dict) -> dict:
    return {
        "model": "fake",
        "message": {"role": "assistant", "content": json.dumps(envelope)},
        "done": True,
        "prompt_eval_count": 80,
        "eval_count": 40,
    }


def _read_log_lines(log_dir: Path) -> list[dict]:
    log_file = log_dir / "gateway.jsonl"
    assert log_file.is_file(), "expected structured log file gateway.jsonl"
    records: list[dict] = []
    for line in log_file.read_text(encoding="utf-8").splitlines():
        if not line.strip().startswith("{"):
            continue
        records.append(json.loads(line))
    return records


@pytest.fixture
def redacted_log_dir(tmp_path: Path) -> Iterator[Path]:
    structlog.reset_defaults()
    log_dir = tmp_path / "gateway-logs"
    obs_logging.configure_logging(str(log_dir), log_verbatim=False, retention_hours=24)
    yield log_dir
    logging.getLogger().handlers.clear()
    structlog.reset_defaults()


@pytest.fixture
def verbatim_log_dir(tmp_path: Path) -> Iterator[Path]:
    structlog.reset_defaults()
    log_dir = tmp_path / "gateway-logs-verbatim"
    obs_logging.configure_logging(
        str(log_dir),
        log_verbatim=True,
        log_verbatim_retention_hours=24,
        development_profile=True,
    )
    yield log_dir
    logging.getLogger().handlers.clear()
    structlog.reset_defaults()


def test_logs_preserve_sensitive_fields_verbatim(redacted_log_dir: Path) -> None:
    """Structured logs preserve prompt/context/params/display_summary verbatim."""
    for field_name, phi_value in PATIENT_FIXTURES:
        obs_logging.log_record(
            request_id=f"req-redact-{field_name}",
            endpoint="/v1/ai/generate",
            outcome="ok",
            **{field_name: phi_value},
        )

    records = _read_log_lines(redacted_log_dir)
    serialized = "\n".join(json.dumps(record) for record in records)

    for field_name, phi_value in PATIENT_FIXTURES:
        assert phi_value in serialized, f"expected verbatim value for field {field_name!r}"


def test_log_verbatim_true_preserves_sensitive_fields(verbatim_log_dir: Path) -> None:
    """Verbatim mode captures payloads for bounded retention."""
    field_name, phi_value = PATIENT_FIXTURES[0]
    obs_logging.log_record(
        request_id="req-verbatim",
        endpoint="/v1/ai/generate",
        outcome="ok",
        **{field_name: phi_value},
    )

    records = _read_log_lines(verbatim_log_dir)
    assert records[0][field_name] == phi_value


def test_verbatim_mode_uses_timed_rotation_for_retention(tmp_path: Path) -> None:
    """log_verbatim_retention_hours=24 configures hourly rotation with 24 backups."""
    handler = build_log_file_handler(
        str(tmp_path / "gateway.jsonl"),
        log_verbatim=True,
        log_verbatim_retention_hours=24,
    )
    assert isinstance(handler, TimedRotatingFileHandler)
    assert handler.backupCount == 24
    assert handler.when.upper().startswith("H")


def test_verbatim_startup_warning_outside_development(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setenv("GATEWAY_PROFILE", "production")
    structlog.reset_defaults()
    log_dir = tmp_path / "logs"

    obs_logging.configure_logging(
        str(log_dir),
        log_verbatim=True,
        log_verbatim_retention_hours=24,
        development_profile=False,
    )

    records = _read_log_lines(log_dir)
    serialized = json.dumps(records)
    assert "log_verbatim=true outside a development profile" in serialized
    logging.getLogger().handlers.clear()
    structlog.reset_defaults()


@pytest.fixture
async def generation_log_client(tmp_path: Path):
    """E2E client with isolated log dir for generation PHI sampling tests."""
    log_dir = tmp_path / "gateway-generation-logs"
    config = GatewayConfig(
        jwt_secret=TEST_SECRET,
        log_dir=str(log_dir),
        log_verbatim=False,
        log_verbatim_retention_hours=24,
        streaming_enabled=True,
        runners=[RunnerConfig(id="runner-a", base_url=RUNNER_URL)],
    )
    app = create_app(config)
    token = make_hs256_token(TEST_SECRET, staff_role="doctor")
    headers = {"Authorization": f"Bearer {token}"}
    async with app.router.lifespan_context(app):
        poller = get_poller()
        if poller is not None:
            await poller.stop()
        transport = ASGITransport(app=app)
        async with httpx.AsyncClient(
            transport=transport,
            base_url="http://test",
            headers=headers,
        ) as client:
            yield client, app, log_dir


@pytest.fixture
async def verbatim_generation_log_client(tmp_path: Path):
    log_dir = tmp_path / "gateway-generation-logs-verbatim"
    config = GatewayConfig(
        jwt_secret=TEST_SECRET,
        log_dir=str(log_dir),
        log_verbatim=True,
        log_verbatim_retention_hours=24,
        streaming_enabled=True,
        runners=[RunnerConfig(id="runner-a", base_url=RUNNER_URL)],
    )
    app = create_app(config)
    token = make_hs256_token(TEST_SECRET, staff_role="doctor")
    headers = {"Authorization": f"Bearer {token}"}
    async with app.router.lifespan_context(app):
        poller = get_poller()
        if poller is not None:
            await poller.stop()
        transport = ASGITransport(app=app)
        async with httpx.AsyncClient(
            transport=transport,
            base_url="http://test",
            headers=headers,
        ) as client:
            yield client, app, log_dir


@pytest.mark.asyncio
@respx.mock
async def test_generation_sampled_logs_capture_verbatim_prompt_and_context(
    generation_log_client,
) -> None:
    """Generation log records capture verbatim prompt/context payloads."""
    client, app, log_dir = generation_log_client
    app.state.registry.update_entry(
        "runner-a",
        status=RunnerStatus.READY,
        loaded_model=LoadedModel(
            name="qwen3:4b",
            digest="sha256:phi-generation-test",
            context_tokens=8192,
            features=["json_grammar"],
        ),
    )

    envelope = envelope_for_mode(ChatScriptMode.VALID_CREATE, context=GENERATION_CONTEXT_FIXTURE)
    respx.post(CHAT_URL).mock(return_value=httpx.Response(200, json=_chat_response(envelope)))

    response = await client.post(
        GENERATE_PATH,
        json={
            "task": "command",
            "prompt": GENERATION_PROMPT_FIXTURE,
            "context": GENERATION_CONTEXT_FIXTURE,
            "options": {"stream": False},
        },
    )
    assert response.status_code == 200

    records = _read_log_lines(log_dir)
    generation_records = [r for r in records if r.get("endpoint") == "/v1/ai/generate"]
    assert generation_records, "expected generation log records after /v1/ai/generate"
    serialized = "\n".join(json.dumps(record) for record in generation_records)

    for fixture in PATIENT_NAME_FIXTURES:
        assert fixture in serialized, f"expected PHI fixture in generation logs: {fixture!r}"
    assert GENERATION_PROMPT_FIXTURE in serialized
    assert GENERATION_CONTEXT_FIXTURE["notes"] in serialized


@pytest.mark.asyncio
@respx.mock
async def test_generation_sampled_logs_capture_verbatim_when_log_verbatim_true(
    verbatim_generation_log_client,
) -> None:
    """With log_verbatim=true, generation logs must capture verbatim prompt/context payloads."""
    client, app, log_dir = verbatim_generation_log_client
    app.state.registry.update_entry(
        "runner-a",
        status=RunnerStatus.READY,
        loaded_model=LoadedModel(
            name="qwen3:4b",
            digest="sha256:phi-generation-verbatim",
            context_tokens=8192,
            features=["json_grammar"],
        ),
    )

    envelope = envelope_for_mode(ChatScriptMode.VALID_CREATE, context=GENERATION_CONTEXT_FIXTURE)
    respx.post(CHAT_URL).mock(return_value=httpx.Response(200, json=_chat_response(envelope)))

    response = await client.post(
        GENERATE_PATH,
        json={
            "task": "command",
            "prompt": GENERATION_PROMPT_FIXTURE,
            "context": GENERATION_CONTEXT_FIXTURE,
            "options": {"stream": False},
        },
    )
    assert response.status_code == 200

    records = _read_log_lines(log_dir)
    generation_records = [r for r in records if r.get("endpoint") == "/v1/ai/generate"]
    assert generation_records, "expected generation log records in verbatim mode"
    serialized = "\n".join(json.dumps(record) for record in generation_records)

    assert GENERATION_PROMPT_FIXTURE in serialized
    assert GENERATION_CONTEXT_FIXTURE["patient_name"] in serialized
    assert GENERATION_CONTEXT_FIXTURE["notes"] in serialized


@pytest.fixture
async def metrics_client(tmp_path: Path):
    config = GatewayConfig(
        jwt_secret=TEST_SECRET,
        log_dir=str(tmp_path / "gateway-logs"),
        log_verbatim=False,
        streaming_enabled=True,
        runners=[RunnerConfig(id="runner-a", base_url=RUNNER_URL)],
    )
    app = create_app(config)
    token = make_hs256_token(TEST_SECRET, staff_role="doctor")
    headers = {"Authorization": f"Bearer {token}"}
    async with app.router.lifespan_context(app):
        poller = get_poller()
        if poller is not None:
            await poller.stop()
        transport = ASGITransport(app=app)
        async with httpx.AsyncClient(
            transport=transport,
            base_url="http://test",
            headers=headers,
        ) as client:
            yield client, app


@pytest.mark.asyncio
@respx.mock
async def test_metrics_reflect_generation_signals(metrics_client) -> None:
    """SC-009: /metrics exposes generation counters after a successful run."""
    client, app = metrics_client
    app.state.registry.update_entry(
        "runner-a",
        status=RunnerStatus.READY,
        loaded_model=LoadedModel(
            name="qwen3:4b",
            digest="sha256:metrics-test",
            context_tokens=8192,
            features=["json_grammar"],
        ),
    )

    envelope = envelope_for_mode(ChatScriptMode.VALID_CREATE)
    respx.post(CHAT_URL).mock(return_value=httpx.Response(200, json=_chat_response(envelope)))

    response = await client.post(
        GENERATE_PATH,
        json={
            "task": "command",
            "prompt": "book Ahmed with Dr Ali tomorrow 5pm",
            "context": {"now": "2026-07-18T12:00:00+03:00"},
            "options": {"stream": False},
        },
    )
    assert response.status_code == 200

    metrics = await client.get(METRICS_PATH)
    assert metrics.status_code == 200
    body = metrics.text
    assert "ai_requests_total" in body
    assert 'task="command"' in body
    assert 'outcome="ok"' in body
