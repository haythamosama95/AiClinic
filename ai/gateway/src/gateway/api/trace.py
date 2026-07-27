"""Live trace buffer and SSE stream for gateway↔runner traffic."""

from __future__ import annotations

import asyncio
import json
from typing import Annotated, Any

from ai_common.verbose_logging import get_logger
from fastapi import APIRouter, Depends, Query, Request
from fastapi.responses import JSONResponse, StreamingResponse

from gateway.auth.dependencies import require_ai_access
from gateway.auth.jwt_validator import CallerIdentity
from gateway.obs.trace_bus import TraceBus, matches_trace_filters

router = APIRouter(prefix="/v1/trace", tags=["trace"])

vlog = get_logger(__name__)


def _trace_bus(request: Request) -> TraceBus:
    bus = getattr(request.app.state, "trace_bus", None)
    if bus is None:
        raise RuntimeError("Trace bus not initialized")
    return bus


def _registry_runner_ids(request: Request) -> list[str]:
    return request.app.state.registry.runner_ids()


@router.get("/config")
async def get_trace_config(
    request: Request,
    _caller: Annotated[CallerIdentity, Depends(require_ai_access)],
) -> JSONResponse:
    """Available filter dimensions for the live trace panel."""
    vlog.v0("Fetching trace filter configuration")
    bus = _trace_bus(request)
    body = bus.filter_config(_registry_runner_ids(request))
    vlog.v1("Returned trace filter configuration", runner_count=len(body.get("runner_ids", [])))
    return JSONResponse(body)


@router.get("/events")
async def get_trace_events(
    request: Request,
    _caller: Annotated[CallerIdentity, Depends(require_ai_access)],
    limit: Annotated[int, Query(ge=1, le=500)] = 100,
    direction: str | None = None,
    kind: str | None = None,
    runner_id: str | None = None,
    status_class: str | None = None,
    path_prefix: str | None = None,
) -> JSONResponse:
    """Historical trace events from the in-memory ring buffer."""
    vlog.v0("Fetching trace event history", limit=limit)
    bus = _trace_bus(request)
    events = await bus.history(
        limit=limit,
        direction=direction,
        kind=kind,
        runner_id=runner_id,
        status_class=status_class,
        path_prefix=path_prefix,
    )
    vlog.v1(
        "Returned trace event history",
        count=len(events),
        direction=direction,
        kind=kind,
        runner_id=runner_id,
    )
    return JSONResponse({"events": events, "count": len(events)})


@router.get("/stream")
async def stream_trace_events(
    request: Request,
    _caller: Annotated[CallerIdentity, Depends(require_ai_access)],
    direction: str | None = None,
    kind: str | None = None,
    runner_id: str | None = None,
    status_class: str | None = None,
    path_prefix: str | None = None,
) -> StreamingResponse:
    """Server-sent events stream of live trace events (filtered)."""
    vlog.v0(
        "Starting live trace event stream",
        direction=direction,
        kind=kind,
        runner_id=runner_id,
    )
    bus = _trace_bus(request)
    queue = bus.subscribe()

    async def event_generator():
        try:
            yield ": connected\n\n"
            while True:
                if await request.is_disconnected():
                    vlog.v1("Live trace stream client disconnected")
                    break
                try:
                    event = await asyncio.wait_for(queue.get(), timeout=1.0)
                except TimeoutError:
                    vlog.v2("Sending trace stream keepalive")
                    yield ": keepalive\n\n"
                    continue
                if event is None:
                    break
                if matches_trace_filters(
                    event,
                    direction=direction,
                    kind=kind,
                    runner_id=runner_id,
                    status_class=status_class,
                    path_prefix=path_prefix,
                ):
                    payload: dict[str, Any] = event.to_dict()
                    yield f"data: {json.dumps(payload, separators=(',', ':'))}\n\n"
        finally:
            bus.unsubscribe(queue)

    return StreamingResponse(
        event_generator(),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "Connection": "keep-alive",
            "X-Accel-Buffering": "no",
        },
    )
