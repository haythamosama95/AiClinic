"""Pull-based health poller updating the in-memory runner registry."""

from __future__ import annotations

import asyncio
import uuid
from contextlib import suppress
from typing import TYPE_CHECKING

import httpx
from ai_common.verbose_logging import get_logger, health_poll_verbose_enabled

from gateway.obs.logging import log_record
from gateway.obs.metrics import (
    observe_runner_latency,
    set_inflight,
    set_runner_health,
)
from gateway.obs.trace_bus import TraceBus
from gateway.obs.trace_helpers import body_text_for_trace, summarize_body
from gateway.routing.lifecycle import (
    LifecycleCounters,
    PollOutcome,
    RunnerStatus,
    transition,
)
from gateway.routing.registry import RunnerRegistry, utc_now
from gateway.runners.openai_client import poll_runner

if TYPE_CHECKING:
    from gateway.config.settings import GatewayConfig

vlog = get_logger(__name__)


class HealthPoller:
    """Background task that polls configured runners on a fixed cadence."""

    def __init__(
        self,
        config: GatewayConfig,
        registry: RunnerRegistry,
        *,
        trace_bus: TraceBus | None = None,
    ) -> None:
        self._config = config
        self._registry = registry
        self._trace_bus = trace_bus
        self._task: asyncio.Task[None] | None = None
        self._stop_event = asyncio.Event()
        self._client: httpx.AsyncClient | None = None
        vlog.v1(
            "Initialized health poller",
            runner_count=len(registry.runner_ids()),
            poll_interval_s=config.health_poll_interval_s,
        )

    async def start(self) -> None:
        vlog.v0("Starting runner health polling")
        if self._task is not None:
            vlog.v1("Runner health polling already active", reason="already_running")
            return
        self._stop_event.clear()
        self._client = httpx.AsyncClient()
        self._task = asyncio.create_task(self._poll_loop())
        vlog.v1("Runner health polling started")

    async def stop(self) -> None:
        vlog.v0("Stopping runner health polling")
        self._stop_event.set()
        if self._task is not None:
            self._task.cancel()
            with suppress(asyncio.CancelledError):
                await self._task
            self._task = None
        if self._client is not None:
            await self._client.aclose()
            self._client = None
        vlog.v1("Runner health polling stopped")

    async def poll_once(self) -> None:
        """Poll every configured runner once (used by tests and the background loop)."""
        poll_verbose = health_poll_verbose_enabled()
        if poll_verbose:
            vlog.v0("Polling configured runners")
        client = self._client or httpx.AsyncClient()
        owns_client = self._client is None
        polled = 0
        try:
            for runner_id in self._registry.runner_ids():
                entry = self._registry.get(runner_id)
                if entry is None:
                    if poll_verbose:
                        vlog.v2("Skipping health poll for unknown runner", runner_id=runner_id)
                    continue
                polled += 1
                old_status = entry.status
                poll_request_id = str(uuid.uuid4())
                if self._trace_bus is not None:
                    await self._trace_bus.emit(
                        direction="gateway_to_runner",
                        method="GET",
                        path="/v1/models",
                        kind="poll",
                        runner_id=runner_id,
                        request_id=poll_request_id,
                        request_summary="health poll",
                    )
                result = await poll_runner(
                    entry.base_url,
                    client=client,
                    preferred_models=[model.name for model in entry.declared_models],
                )

                response_summary: str | None = None
                response_body: str | None = None
                if result.loaded_model is not None:
                    payload = {
                        "model": result.loaded_model.name,
                        "outcome": result.outcome.value,
                    }
                    response_summary = summarize_body(payload)
                    response_body = body_text_for_trace(payload)
                elif result.outcome.value != "ok":
                    response_summary = f"outcome={result.outcome.value}"
                    response_body = response_summary

                if self._trace_bus is not None:
                    status_code = 200 if result.outcome in (
                        PollOutcome.OK,
                        PollOutcome.LOADING,
                    ) else 503
                    await self._trace_bus.emit(
                        direction="runner_to_gateway",
                        method="GET",
                        path="/v1/models",
                        kind="poll",
                        runner_id=runner_id,
                        status_code=status_code,
                        latency_ms=result.latency_ms,
                        request_id=poll_request_id,
                        response_summary=response_summary,
                        response_body=response_body,
                    )

                avg_latency = entry.avg_latency_ms
                if result.latency_ms is not None:
                    if avg_latency is None:
                        avg_latency = result.latency_ms
                    else:
                        avg_latency = (avg_latency + result.latency_ms) / 2.0
                    observe_runner_latency(runner_id, result.latency_ms / 1000.0)

                baseline_latency: float | None = None
                if entry.status in (
                    RunnerStatus.READY,
                    RunnerStatus.DEGRADED,
                    RunnerStatus.BUSY,
                ):
                    baseline_latency = entry.avg_latency_ms or entry.last_latency_ms

                counters = LifecycleCounters(consecutive_failures=entry.consecutive_failures)
                next_state = transition(
                    entry.status,
                    result.outcome,
                    counters,
                    self._config.unreachable_after_failures,
                    has_loaded_model=result.loaded_model is not None,
                    latency_ms=result.latency_ms,
                    avg_latency_ms=avg_latency,
                    in_flight=entry.in_flight,
                    max_inflight=1,
                    baseline_latency_ms=baseline_latency,
                )

                set_runner_health(
                    runner_id,
                    healthy=next_state.status == RunnerStatus.READY,
                )

                updates: dict[str, object] = {
                    "status": next_state.status,
                    "consecutive_failures": next_state.consecutive_failures,
                    "last_latency_ms": result.latency_ms,
                    "avg_latency_ms": avg_latency,
                }
                if result.loaded_model is not None:
                    updates["loaded_model"] = result.loaded_model
                    updates["last_seen_at"] = utc_now()
                self._registry.update_entry(runner_id, **updates)

                set_inflight(runner_id, entry.in_flight)

                status_change: str | None = None
                if old_status != next_state.status:
                    status_change = f"{old_status.value}→{next_state.status.value}"
                    vlog.v0(
                        "Runner health status changed",
                        runner_id=runner_id,
                        status_change=status_change,
                    )

                poll_outcome = (
                    "ok"
                    if result.outcome in (PollOutcome.OK, PollOutcome.LOADING)
                    else "error"
                )
                log_record(
                    request_id=str(uuid.uuid4()),
                    endpoint="/internal/health-poll",
                    outcome=poll_outcome,
                    runner_id=runner_id,
                    runner_status_change=status_change,
                    latency_ms=result.latency_ms,
                    poll_outcome=result.outcome.value,
                )
                if poll_verbose:
                    vlog.v2(
                        "Runner health poll result",
                        runner_id=runner_id,
                        outcome=result.outcome.value,
                        latency_ms=result.latency_ms,
                    )
        finally:
            if owns_client:
                await client.aclose()
        if poll_verbose:
            vlog.v1("Finished polling configured runners", polled=polled)

    async def _poll_loop(self) -> None:
        interval = self._config.health_poll_interval_s
        vlog.v1("Starting runner health poll loop", interval_s=interval)
        while not self._stop_event.is_set():
            await self.poll_once()
            try:
                await asyncio.wait_for(self._stop_event.wait(), timeout=interval)
            except TimeoutError:
                continue
