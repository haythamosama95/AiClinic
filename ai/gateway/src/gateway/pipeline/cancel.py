"""Cancellation propagation: client disconnect → runner abort → queue slot free."""

from __future__ import annotations

import asyncio
from collections.abc import AsyncIterator, Awaitable, Callable
from typing import TypeVar

import httpx
import structlog

from gateway.obs.logging import log_record
from gateway.pipeline.queue import QueueSlot

T = TypeVar("T")

logger = structlog.get_logger("gateway.pipeline.cancel")


def log_cancelled(
    *,
    request_id: str,
    endpoint: str = "/v1/ai/generate",
    caller_staff_id: str | None = None,
    runner_id: str | None = None,
    agent: str | None = None,
    **extra: object,
) -> None:
    """Emit a structured log with outcome=cancelled (not error)."""
    log_record(
        request_id=request_id,
        endpoint=endpoint,
        outcome="cancelled",
        caller_staff_id=caller_staff_id,
        runner_id=runner_id,
        agent=agent,
        **extra,
    )


async def abort_httpx_call(client: httpx.AsyncClient | None) -> None:
    """Close the httpx client to abort any in-flight runner HTTP request."""
    if client is not None:
        await client.aclose()


class CancellableRunnerCall:
    """Wraps a runner HTTP call with cancellation and queue-slot cleanup."""

    def __init__(
        self,
        *,
        queue_slot: QueueSlot | None,
        request_id: str,
        endpoint: str = "/v1/ai/generate",
        caller_staff_id: str | None = None,
    ) -> None:
        self._queue_slot = queue_slot
        self._request_id = request_id
        self._endpoint = endpoint
        self._caller_staff_id = caller_staff_id
        self._http_client: httpx.AsyncClient | None = None
        self._runner_id: str | None = None

    def bind_client(self, client: httpx.AsyncClient) -> None:
        self._http_client = client

    def bind_runner(self, runner_id: str) -> None:
        self._runner_id = runner_id

    async def run(self, coro: Awaitable[T]) -> T:
        """Execute ``coro``; on cancellation abort runner and free the queue slot."""
        try:
            return await coro
        except asyncio.CancelledError:
            await self._handle_cancel()
            raise

    async def _handle_cancel(self) -> None:
        await abort_httpx_call(self._http_client)
        if self._queue_slot is not None:
            self._queue_slot.release()
        log_cancelled(
            request_id=self._request_id,
            endpoint=self._endpoint,
            caller_staff_id=self._caller_staff_id,
            runner_id=self._runner_id,
        )
        logger.info(
            "generation_cancelled",
            request_id=self._request_id,
            runner_id=self._runner_id,
            outcome="cancelled",
        )


async def run_cancellable(
    fn: Callable[[], Awaitable[T]],
    *,
    queue_slot: QueueSlot | None,
    request_id: str,
    http_client: httpx.AsyncClient | None = None,
    endpoint: str = "/v1/ai/generate",
    caller_staff_id: str | None = None,
    runner_id: str | None = None,
) -> T:
    """Run ``fn`` with cancellation propagation and queue-slot cleanup."""
    wrapper = CancellableRunnerCall(
        queue_slot=queue_slot,
        request_id=request_id,
        endpoint=endpoint,
        caller_staff_id=caller_staff_id,
    )
    if http_client is not None:
        wrapper.bind_client(http_client)
    if runner_id is not None:
        wrapper.bind_runner(runner_id)
    return await wrapper.run(fn())


async def cancellable_stream(
    stream: AsyncIterator[T],
    *,
    queue_slot: QueueSlot | None,
    request_id: str,
    http_client: httpx.AsyncClient | None = None,
    endpoint: str = "/v1/ai/generate",
    caller_staff_id: str | None = None,
    runner_id: str | None = None,
) -> AsyncIterator[T]:
    """Yield from ``stream``; on cancellation abort runner and free the queue slot."""
    wrapper = CancellableRunnerCall(
        queue_slot=queue_slot,
        request_id=request_id,
        endpoint=endpoint,
        caller_staff_id=caller_staff_id,
    )
    if http_client is not None:
        wrapper.bind_client(http_client)
    if runner_id is not None:
        wrapper.bind_runner(runner_id)
    try:
        async for item in stream:
            yield item
    except asyncio.CancelledError:
        await wrapper._handle_cancel()
        raise
