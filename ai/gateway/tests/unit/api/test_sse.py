"""Unit tests for generation SSE helpers."""

from __future__ import annotations

import json

import pytest

from gateway.api.sse import (
    EventStreamEmitter,
    TerminalEventError,
    async_iter_guarded_sse_events,
    format_event,
    iter_guarded_sse_events,
)


def test_format_event_encodes_type_and_json_payload() -> None:
    block = format_event("summary", {"delta": "thinking..."})
    assert block == 'event: summary\ndata: {"delta":"thinking..."}\n\n'


def test_format_event_rejects_unknown_type() -> None:
    with pytest.raises(ValueError, match="unsupported SSE event type"):
        format_event("heartbeat", {})


def test_event_stream_emitter_allows_one_terminal_event() -> None:
    emitter = EventStreamEmitter()
    assert emitter.emit("summary", {"delta": "a"}) == format_event("summary", {"delta": "a"})
    assert emitter.emit_final({"task": "command"}) == format_event("final", {"task": "command"})
    assert emitter.terminal_emitted is True
    assert emitter.terminal_type == "final"


def test_event_stream_emitter_rejects_second_terminal_event() -> None:
    emitter = EventStreamEmitter()
    emitter.emit_error({"error": {"code": "ai_unusable", "message": "x", "request_id": "r"}})
    with pytest.raises(TerminalEventError):
        emitter.emit_final({})


def test_iter_guarded_sse_events() -> None:
    events = iter(
        [
            ("summary", {"delta": "hi"}),
            ("final", {"task": "command"}),
        ]
    )
    blocks = list(iter_guarded_sse_events(events))
    assert len(blocks) == 2
    assert blocks[0].startswith("event: summary\n")
    assert blocks[1].startswith("event: final\n")


@pytest.mark.asyncio
async def test_async_iter_guarded_sse_events() -> None:
    async def events():
        yield ("summary", {"delta": "hi"})
        yield ("final", {"task": "command"})

    blocks = [block async for block in async_iter_guarded_sse_events(events())]
    assert len(blocks) == 2
    assert json.loads(blocks[1].split("data: ", 1)[1].strip()) == {"task": "command"}
