"""Pull-based health poller updating the in-memory runner registry."""

from __future__ import annotations

import asyncio
import uuid
from contextlib import suppress
from typing import TYPE_CHECKING

import httpx

from gateway.obs.logging import log_record
from gateway.obs.metrics import (
    observe_runner_latency,
    set_inflight,
    set_runner_health,
)
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


class HealthPoller:
    """Background task that polls configured runners on a fixed cadence."""

    def __init__(self, config: GatewayConfig, registry: RunnerRegistry) -> None:
        self._config = config
        self._registry = registry
        self._task: asyncio.Task[None] | None = None
        self._stop_event = asyncio.Event()
        self._client: httpx.AsyncClient | None = None

    async def start(self) -> None:
        if self._task is not None:
            return
        self._stop_event.clear()
        self._client = httpx.AsyncClient()
        self._task = asyncio.create_task(self._poll_loop())

    async def stop(self) -> None:
        self._stop_event.set()
        if self._task is not None:
            self._task.cancel()
            with suppress(asyncio.CancelledError):
                await self._task
            self._task = None
        if self._client is not None:
            await self._client.aclose()
            self._client = None

    async def poll_once(self) -> None:
        """Poll every configured runner once (used by tests and the background loop)."""
        client = self._client or httpx.AsyncClient()
        owns_client = self._client is None
        try:
            for runner_id in self._registry.runner_ids():
                entry = self._registry.get(runner_id)
                if entry is None:
                    continue
                old_status = entry.status
                result = await poll_runner(entry.base_url, client=client)

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
        finally:
            if owns_client:
                await client.aclose()

    async def _poll_loop(self) -> None:
        interval = self._config.health_poll_interval_s
        while not self._stop_event.is_set():
            await self.poll_once()
            try:
                await asyncio.wait_for(self._stop_event.wait(), timeout=interval)
            except TimeoutError:
                continue
