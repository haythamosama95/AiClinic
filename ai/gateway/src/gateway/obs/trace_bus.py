"""In-memory trace event ring buffer with SSE subscriber fan-out."""

from __future__ import annotations

import asyncio
import hashlib
import re
import uuid
from collections import deque
from collections.abc import AsyncIterator
from dataclasses import asdict, dataclass, field
from datetime import UTC, datetime
from typing import Any, Literal

from ai_common.verbose_logging import get_logger, health_poll_verbose_enabled

Direction = Literal[
    "client_to_gateway",
    "gateway_to_runner",
    "runner_to_gateway",
    "gateway_to_client",
]
TraceKind = Literal["poll", "proxy", "api", "internal"]

_MAX_EVENTS = 500
_SUMMARY_MAX_LEN = 240
_BODY_MAX_LEN = 8192

vlog = get_logger(__name__)

_PHI_PATTERNS: list[re.Pattern[str]] = [
    re.compile(r"\bpatient[_\s]?name\b", re.IGNORECASE),
    re.compile(r"\b[A-Z][a-z]+ [A-Z][a-z]+\b"),
]


def _hash_value(value: str) -> str:
    return f"sha256:{hashlib.sha256(value.encode()).hexdigest()[:16]}"


def _redact_text(
    text: str,
    *,
    max_len: int,
    log_verbatim: bool,
) -> str:
    if log_verbatim:
        return text[:max_len] + ("…" if len(text) > max_len else "")

    redacted = False
    result = text
    for pattern in _PHI_PATTERNS:
        if pattern.search(result):
            result = pattern.sub(lambda m: _hash_value(m.group(0)), result)
            redacted = True
    if len(result) > max_len:
        result = result[:max_len] + "…"
    if redacted and not result.endswith("…"):
        result = result + " [redacted]"
    return result


def redact_summary(text: str | None, *, log_verbatim: bool = False) -> str | None:
    """Truncate and PHI-redact a trace body summary."""
    if text is None:
        return None
    if not text:
        return ""
    return _redact_text(text, max_len=_SUMMARY_MAX_LEN, log_verbatim=log_verbatim)


def redact_body(text: str | None, *, log_verbatim: bool = False) -> str | None:
    """Truncate and PHI-redact a full request/response body for the trace inspector."""
    if text is None:
        return None
    if not text:
        return ""
    return _redact_text(text, max_len=_BODY_MAX_LEN, log_verbatim=log_verbatim)


@dataclass(frozen=True)
class TraceEvent:
    id: str
    ts: str
    direction: Direction
    runner_id: str | None
    method: str
    path: str
    status_code: int | None
    latency_ms: float | None
    request_summary: str | None
    response_summary: str | None
    kind: TraceKind
    request_id: str | None = None
    request_body: str | None = None
    response_body: str | None = None

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)


@dataclass
class TraceBus:
    """Thread-safe ring buffer with async subscriber queues for SSE."""

    max_events: int = _MAX_EVENTS
    log_verbatim: bool = False
    _events: deque[TraceEvent] = field(default_factory=deque, init=False)
    _lock: asyncio.Lock = field(default_factory=asyncio.Lock, init=False)
    _subscribers: set[asyncio.Queue[TraceEvent | None]] = field(
        default_factory=set,
        init=False,
    )

    async def emit(
        self,
        *,
        direction: Direction,
        method: str,
        path: str,
        kind: TraceKind,
        runner_id: str | None = None,
        status_code: int | None = None,
        latency_ms: float | None = None,
        request_summary: str | None = None,
        response_summary: str | None = None,
        request_body: str | None = None,
        response_body: str | None = None,
        request_id: str | None = None,
        event_id: str | None = None,
        ts: str | None = None,
    ) -> TraceEvent:
        poll_verbose = kind == "poll" and health_poll_verbose_enabled()
        if kind != "poll" or poll_verbose:
            vlog.v2(
                "Recording trace event",
                direction=direction,
                kind=kind,
                path=path,
                runner_id=runner_id,
                status_code=status_code,
            )
        event = TraceEvent(
            id=event_id or str(uuid.uuid4()),
            ts=ts or datetime.now(UTC).isoformat(),
            direction=direction,
            runner_id=runner_id,
            method=method,
            path=path,
            status_code=status_code,
            latency_ms=round(latency_ms, 2) if latency_ms is not None else None,
            request_summary=redact_summary(request_summary, log_verbatim=self.log_verbatim),
            response_summary=redact_summary(response_summary, log_verbatim=self.log_verbatim),
            kind=kind,
            request_id=request_id,
            request_body=redact_body(request_body, log_verbatim=self.log_verbatim),
            response_body=redact_body(response_body, log_verbatim=self.log_verbatim),
        )
        async with self._lock:
            self._events.append(event)
            while len(self._events) > self.max_events:
                self._events.popleft()
            dead: list[asyncio.Queue[TraceEvent | None]] = []
            for queue in self._subscribers:
                try:
                    queue.put_nowait(event)
                except asyncio.QueueFull:
                    dead.append(queue)
            for queue in dead:
                self._subscribers.discard(queue)
        if kind != "poll" or poll_verbose:
            vlog.v2("Trace event recorded", event_id=event.id, buffer_size=len(self._events))
        return event

    async def history(
        self,
        *,
        limit: int = 100,
        direction: str | None = None,
        kind: str | None = None,
        runner_id: str | None = None,
        status_class: str | None = None,
        path_prefix: str | None = None,
    ) -> list[dict[str, Any]]:
        vlog.v0("Fetching trace event history", limit=limit)
        async with self._lock:
            events = list(self._events)
        filtered = _apply_filters(
            events,
            direction=direction,
            kind=kind,
            runner_id=runner_id,
            status_class=status_class,
            path_prefix=path_prefix,
        )
        tail = filtered[-limit:] if limit > 0 else filtered
        result = [e.to_dict() for e in reversed(tail)]
        vlog.v1("Fetched trace event history", count=len(result))
        return result

    def subscribe(self, *, max_queue: int = 64) -> asyncio.Queue[TraceEvent | None]:
        queue: asyncio.Queue[TraceEvent | None] = asyncio.Queue(maxsize=max_queue)
        self._subscribers.add(queue)
        vlog.v2("Subscribed to live trace events", subscriber_count=len(self._subscribers))
        return queue

    def unsubscribe(self, queue: asyncio.Queue[TraceEvent | None]) -> None:
        self._subscribers.discard(queue)
        vlog.v2("Unsubscribed from live trace events", subscriber_count=len(self._subscribers))

    async def stream(
        self,
        queue: asyncio.Queue[TraceEvent | None],
        *,
        direction: str | None = None,
        kind: str | None = None,
        runner_id: str | None = None,
        status_class: str | None = None,
        path_prefix: str | None = None,
    ) -> AsyncIterator[TraceEvent]:
        try:
            while True:
                event = await queue.get()
                if event is None:
                    break
                if _matches_filters(
                    event,
                    direction=direction,
                    kind=kind,
                    runner_id=runner_id,
                    status_class=status_class,
                    path_prefix=path_prefix,
                ):
                    yield event
        finally:
            self.unsubscribe(queue)

    def filter_config(self, runner_ids: list[str]) -> dict[str, Any]:
        return {
            "directions": [
                "client_to_gateway",
                "gateway_to_runner",
                "runner_to_gateway",
                "gateway_to_client",
            ],
            "kinds": ["poll", "proxy", "api", "internal"],
            "runner_ids": runner_ids,
            "status_classes": ["ok", "client_error", "server_error", "unknown"],
            "max_buffer": self.max_events,
        }


def _status_class(status_code: int | None) -> str:
    if status_code is None:
        return "unknown"
    if status_code < 400:
        return "ok"
    if status_code < 500:
        return "client_error"
    return "server_error"


def matches_trace_filters(
    event: TraceEvent,
    *,
    direction: str | None,
    kind: str | None,
    runner_id: str | None,
    status_class: str | None,
    path_prefix: str | None,
) -> bool:
    return _matches_filters(
        event,
        direction=direction,
        kind=kind,
        runner_id=runner_id,
        status_class=status_class,
        path_prefix=path_prefix,
    )


def _matches_filters(
    event: TraceEvent,
    *,
    direction: str | None,
    kind: str | None,
    runner_id: str | None,
    status_class: str | None,
    path_prefix: str | None,
) -> bool:
    if direction and event.direction != direction:
        return False
    if kind and event.kind != kind:
        return False
    if runner_id and event.runner_id != runner_id:
        return False
    if status_class and _status_class(event.status_code) != status_class:
        return False
    if path_prefix and not event.path.startswith(path_prefix):
        return False
    return True


def _apply_filters(
    events: list[TraceEvent],
    *,
    direction: str | None,
    kind: str | None,
    runner_id: str | None,
    status_class: str | None,
    path_prefix: str | None,
) -> list[TraceEvent]:
    return [
        e
        for e in events
        if _matches_filters(
            e,
            direction=direction,
            kind=kind,
            runner_id=runner_id,
            status_class=status_class,
            path_prefix=path_prefix,
        )
    ]
