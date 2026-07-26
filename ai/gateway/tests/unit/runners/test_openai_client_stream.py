"""Unit tests for grammar-constrained streaming runner client."""

from __future__ import annotations

import json

import httpx
import pytest
import respx

from gateway.agents.scheduling import get_scheduling_agent
from gateway.runners.openai_client import (
    GrammarStreamSession,
    _extract_json_matching_schema,
    chat_completion_grammar_stream,
)
from tests.fixtures.fake_runner import ChatScriptMode, FakeRunner

RUNNER_URL = "http://runner-stream.test:11434"
CHAT_URL = f"{RUNNER_URL}/api/chat"


def test_extract_json_matching_schema_prefers_last_valid_object() -> None:
    text = (
        'noise {"command_type":"old"} trailing '
        '{"command_type":"create_appointment","confidence":0.9}'
    )
    schema = {
        "type": "object",
        "required": ["command_type", "confidence"],
        "properties": {
            "command_type": {"type": "string"},
            "confidence": {"type": "number"},
        },
    }
    parsed = _extract_json_matching_schema(text, schema)
    assert parsed is not None
    assert parsed["command_type"] == "create_appointment"


def test_grammar_stream_session_parsed_json_with_summary_prefix() -> None:
    session = GrammarStreamSession(model="qwen3:4b", digest="sha256:test")
    session.feed('Looking up slots... {"command_type":"create_appointment","confidence":0.9}')
    parsed = session.parsed_json()
    assert parsed["command_type"] == "create_appointment"


@pytest.mark.asyncio
@respx.mock
async def test_chat_completion_grammar_stream_assembles_scripted_envelope() -> None:
    fake = FakeRunner()
    fake.script_chat_stream(
        ChatScriptMode.VALID_CREATE,
        summary_prefix="Checking availability... ",
        chunk_size=6,
    )
    respx.post(CHAT_URL).mock(
        return_value=httpx.Response(
            200,
            content=fake.chat_completion_stream_body().encode(),
            headers={"Content-Type": "application/x-ndjson"},
        )
    )

    agent = get_scheduling_agent()
    format_schema = agent.grammar.to_ollama_format(agent.envelope_schema())
    deltas: list[str] = []
    session: GrammarStreamSession | None = None

    async with httpx.AsyncClient() as http:
        async for delta, active_session in chat_completion_grammar_stream(
            RUNNER_URL,
            model="qwen3:4b",
            digest="sha256:test",
            messages=[{"role": "user", "content": "book Ahmed"}],
            format_schema=format_schema,
            client=http,
        ):
            deltas.append(delta.content)
            session = active_session

    assert session is not None
    assert session.content.startswith("Checking availability...")
    parsed = session.parsed_json_matching_schema(format_schema)
    assert parsed["command_type"] == "create_appointment"
    assert parsed["requires_resolution"]["patient_id"] == "lookup_required"
    assert "".join(deltas) == session.content
    assert session.total_seconds >= 0
