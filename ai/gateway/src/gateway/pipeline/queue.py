"""Per-capability bounded FIFO queue with backpressure and per-caller in-flight caps."""

from __future__ import annotations

import asyncio
import threading
import time
from collections import deque
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from dataclasses import dataclass, field
from typing import Any

from gateway.api.errors import ErrorCode, GatewayError
from gateway.config.settings import GatewayConfig
from gateway.obs.metrics import set_ai_inflight, set_ai_queue_depth


@dataclass
class QueueEntry:
    """One waiting request in a capability-class FIFO."""

    capability: str
    request_id: str
    caller_staff_id: str
    enqueue_at: float
    task: asyncio.Task[Any]
    started: bool = False


@dataclass
class QueueSlot:
    """An acquired queue slot; release when the generation reaches a terminal state."""

    capability: str
    request_id: str
    caller_staff_id: str
    queue_wait_seconds: float
    _manager: GenerationQueue
    _released: bool = field(default=False, init=False)

    def release(self) -> None:
        if self._released:
            return
        self._released = True
        self._manager._release_slot(self)


class ShutdownCoordinator:
    """Coordinates graceful drain: stop accepting, reject queued, cancel stragglers."""

    def __init__(self, grace_s: float) -> None:
        self.grace_s = grace_s
        self._shutting_down = False
        self._shutdown_started_at: float | None = None
        self._in_flight: set[str] = set()
        self._lock = asyncio.Lock()

    @property
    def shutting_down(self) -> bool:
        return self._shutting_down

    def begin_shutdown(self) -> None:
        self._shutting_down = True
        self._shutdown_started_at = time.monotonic()

    def register_in_flight(self, request_id: str) -> None:
        self._in_flight.add(request_id)

    def unregister_in_flight(self, request_id: str) -> None:
        self._in_flight.discard(request_id)

    @property
    def in_flight_request_ids(self) -> frozenset[str]:
        return frozenset(self._in_flight)

    def grace_elapsed(self) -> bool:
        if self._shutdown_started_at is None:
            return False
        return (time.monotonic() - self._shutdown_started_at) >= self.grace_s

    def remaining_grace_s(self) -> float:
        if self._shutdown_started_at is None:
            return self.grace_s
        elapsed = time.monotonic() - self._shutdown_started_at
        return max(0.0, self.grace_s - elapsed)


class _CapabilityQueue:
    """Bounded FIFO for one capability class."""

    def __init__(
        self,
        capability: str,
        *,
        max_depth: int,
        max_wait_s: float,
    ) -> None:
        self.capability = capability
        self._max_depth = max_depth
        self._max_wait_s = max_wait_s
        self._waiting: deque[QueueEntry] = deque()
        self._active = 0
        self._lock = asyncio.Lock()

    @property
    def depth(self) -> int:
        return len(self._waiting) + self._active

    def _update_metrics(self) -> None:
        set_ai_queue_depth(self.capability, len(self._waiting))
        set_ai_inflight(self.capability, self._active)

    async def acquire(self, entry: QueueEntry) -> float:
        """Wait for a slot; return queue wait seconds. Raises GatewayError on overflow/timeout."""
        started_wait = time.monotonic()
        async with self._lock:
            if self._active + len(self._waiting) >= self._max_depth:
                raise GatewayError(
                    ErrorCode.AI_BUSY,
                    "AI queue is full",
                    entry.request_id,
                    headers={"Retry-After": "5"},
                )
            self._waiting.append(entry)
            self._update_metrics()

        try:
            while True:
                async with self._lock:
                    at_front = self._waiting and self._waiting[0] is entry
                    if at_front and self._active < self._max_depth:
                        self._waiting.popleft()
                        self._active += 1
                        entry.started = True
                        self._update_metrics()
                        return time.monotonic() - started_wait

                    waited = time.monotonic() - started_wait
                    if waited >= self._max_wait_s:
                        if entry in self._waiting:
                            self._waiting.remove(entry)
                            self._update_metrics()
                        raise GatewayError(
                            ErrorCode.AI_BUSY,
                            "AI queue wait timeout exceeded",
                            entry.request_id,
                            headers={"Retry-After": "5"},
                        )

                await asyncio.sleep(0.05)
        except asyncio.CancelledError:
            async with self._lock:
                if entry in self._waiting:
                    self._waiting.remove(entry)
                    self._update_metrics()
            raise

    def release(self) -> None:
        self._active = max(0, self._active - 1)
        self._update_metrics()

    async def reject_queued_not_started(self) -> list[QueueEntry]:
        """Reject all entries still waiting (not yet started)."""
        rejected: list[QueueEntry] = []
        async with self._lock:
            while self._waiting:
                entry = self._waiting.popleft()
                if not entry.started:
                    rejected.append(entry)
            self._update_metrics()
        return rejected


class GenerationQueue:
    """Manages per-capability queues and per-caller in-flight tracking."""

    def __init__(
        self,
        config: GatewayConfig,
        *,
        shutdown: ShutdownCoordinator | None = None,
    ) -> None:
        self._max_depth = config.queue_max_depth
        self._max_wait_s = float(config.queue_max_wait_s)
        self._max_inflight_per_caller = config.max_inflight_per_caller
        self._shutdown = shutdown or ShutdownCoordinator(float(config.shutdown_grace_s))
        self._queues: dict[str, _CapabilityQueue] = {}
        self._caller_inflight: dict[str, int] = {}
        self._caller_lock = threading.Lock()
        self._active_tasks: dict[str, asyncio.Task[Any]] = {}

    @property
    def shutdown(self) -> ShutdownCoordinator:
        return self._shutdown

    def _queue_for(self, capability: str) -> _CapabilityQueue:
        if capability not in self._queues:
            self._queues[capability] = _CapabilityQueue(
                capability,
                max_depth=self._max_depth,
                max_wait_s=self._max_wait_s,
            )
        return self._queues[capability]

    def _check_caller_cap(self, caller_staff_id: str, request_id: str) -> None:
        with self._caller_lock:
            count = self._caller_inflight.get(caller_staff_id, 0)
            if count >= self._max_inflight_per_caller:
                raise GatewayError(
                    ErrorCode.RATE_LIMITED,
                    "Per-caller in-flight limit exceeded",
                    request_id,
                )

    def _increment_caller(self, caller_staff_id: str) -> None:
        with self._caller_lock:
            self._caller_inflight[caller_staff_id] = (
                self._caller_inflight.get(caller_staff_id, 0) + 1
            )

    def _decrement_caller(self, caller_staff_id: str) -> None:
        with self._caller_lock:
            count = self._caller_inflight.get(caller_staff_id, 0)
            if count <= 1:
                self._caller_inflight.pop(caller_staff_id, None)
            else:
                self._caller_inflight[caller_staff_id] = count - 1

    def _reject_shutdown(self, request_id: str) -> None:
        if self._shutdown.shutting_down:
            raise GatewayError(
                ErrorCode.AI_BUSY,
                "Gateway is shutting down",
                request_id,
                headers={"Retry-After": "5"},
            )

    @asynccontextmanager
    async def acquire(
        self,
        *,
        capability: str,
        request_id: str,
        caller_staff_id: str,
    ) -> AsyncIterator[QueueSlot]:
        """Acquire a queue slot (per-caller cap → 429, overflow/wait → 503 ai_busy)."""
        self._reject_shutdown(request_id)
        self._check_caller_cap(caller_staff_id, request_id)

        current = asyncio.current_task()
        if current is None:
            raise RuntimeError("acquire must be called from an asyncio task")

        entry = QueueEntry(
            capability=capability,
            request_id=request_id,
            caller_staff_id=caller_staff_id,
            enqueue_at=time.monotonic(),
            task=current,
        )

        self._increment_caller(caller_staff_id)
        cap_queue = self._queue_for(capability)
        slot: QueueSlot | None = None
        try:
            queue_wait = await cap_queue.acquire(entry)
            self._shutdown.register_in_flight(request_id)
            self._active_tasks[request_id] = current
            slot = QueueSlot(
                capability=capability,
                request_id=request_id,
                caller_staff_id=caller_staff_id,
                queue_wait_seconds=queue_wait,
                _manager=self,
            )
            yield slot
        except GatewayError:
            self._decrement_caller(caller_staff_id)
            raise
        except asyncio.CancelledError:
            self._decrement_caller(caller_staff_id)
            raise
        finally:
            if slot is not None and not slot._released:
                slot.release()

    def _release_slot(self, slot: QueueSlot) -> None:
        self._shutdown.unregister_in_flight(slot.request_id)
        self._active_tasks.pop(slot.request_id, None)
        cap_queue = self._queue_for(slot.capability)
        cap_queue.release()
        self._decrement_caller(slot.caller_staff_id)

    async def cancel_stragglers_after_grace(self) -> list[str]:
        """Cancel in-flight tasks still running after the shutdown grace period."""
        cancelled: list[str] = []
        for request_id in list(self._shutdown.in_flight_request_ids):
            task = self._active_tasks.get(request_id)
            if task is not None and not task.done():
                task.cancel()
            cancelled.append(request_id)
        return cancelled

    async def reject_queued_not_started(self) -> list[QueueEntry]:
        """Cancel all queued-but-not-started entries during shutdown."""
        rejected: list[QueueEntry] = []
        for cap_queue in self._queues.values():
            entries = await cap_queue.reject_queued_not_started()
            rejected.extend(entries)
        for entry in rejected:
            if not entry.task.done():
                entry.task.cancel()
            self._decrement_caller(entry.caller_staff_id)
        return rejected

    async def drain_in_flight(self, grace_s: float) -> list[str]:
        """Wait up to grace_s for in-flight requests; return IDs still running."""
        deadline = time.monotonic() + grace_s
        while time.monotonic() < deadline:
            if not self._shutdown.in_flight_request_ids:
                return []
            await asyncio.sleep(0.1)
        return list(self._shutdown.in_flight_request_ids)


def create_generation_queue(config: GatewayConfig) -> GenerationQueue:
    """Factory used by application bootstrap."""
    shutdown = ShutdownCoordinator(float(config.shutdown_grace_s))
    return GenerationQueue(config, shutdown=shutdown)
