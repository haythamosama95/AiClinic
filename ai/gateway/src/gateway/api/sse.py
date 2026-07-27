"""SSE event encoding for generation streaming (US2)."""

from __future__ import annotations

import json
from collections.abc import AsyncIterator, Iterator
from typing import Any

from ai_common.verbose_logging import get_logger

vlog = get_logger(__name__)

TERMINAL_EVENT_TYPES = frozenset({"final", "error"})
ALLOWED_EVENT_TYPES = frozenset({"token", "summary", *TERMINAL_EVENT_TYPES})


class TerminalEventError(RuntimeError):
    """Raised when a stream violates terminal-event discipline."""


def format_event(event_type: str, payload: Any) -> str:
    """Encode one SSE event block: ``event: <type>\\ndata: <json>\\n\\n``."""
    if event_type not in ALLOWED_EVENT_TYPES:
        vlog.v0("Rejected unsupported SSE event type", event_type=event_type)
        raise ValueError(f"unsupported SSE event type: {event_type!r}")
    vlog.v2("Formatting SSE event", event_type=event_type)
    data = json.dumps(payload, separators=(",", ":"), ensure_ascii=False)
    return f"event: {event_type}\ndata: {data}\n\n"


class EventStreamEmitter:
    """Enforces exactly one terminal event (``final`` or ``error``) per stream."""

    def __init__(self) -> None:
        self._terminal_emitted = False
        self._terminal_type: str | None = None
        vlog.v1("Initialized SSE event stream emitter")

    @property
    def terminal_emitted(self) -> bool:
        return self._terminal_emitted

    @property
    def terminal_type(self) -> str | None:
        return self._terminal_type

    def emit(self, event_type: str, payload: Any) -> str:
        if self._terminal_emitted:
            vlog.v0(
                "SSE stream violated terminal event discipline",
                event_type=event_type,
                terminal_type=self._terminal_type,
            )
            raise TerminalEventError(
                f"cannot emit {event_type!r} after terminal {self._terminal_type!r}"
            )
        if event_type in TERMINAL_EVENT_TYPES:
            self._terminal_emitted = True
            self._terminal_type = event_type
            vlog.v1("Emitted terminal SSE event", event_type=event_type)
        else:
            vlog.v2("Emitted SSE event", event_type=event_type)
        return format_event(event_type, payload)

    def emit_final(self, payload: Any) -> str:
        return self.emit("final", payload)

    def emit_error(self, payload: Any) -> str:
        return self.emit("error", payload)


def iter_guarded_sse_events(
    events: Iterator[tuple[str, Any]],
) -> Iterator[str]:
    """Yield formatted SSE blocks with terminal-event discipline."""
    emitter = EventStreamEmitter()
    for event_type, payload in events:
        yield emitter.emit(event_type, payload)


async def async_iter_guarded_sse_events(
    events: AsyncIterator[tuple[str, Any]],
) -> AsyncIterator[str]:
    """Async variant of :func:`iter_guarded_sse_events`."""
    emitter = EventStreamEmitter()
    async for event_type, payload in events:
        yield emitter.emit(event_type, payload)
