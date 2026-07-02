"""Pull-based health poller — full implementation in US1 (T022)."""

from __future__ import annotations

import asyncio
from contextlib import suppress
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from gateway.config.settings import GatewayConfig


class HealthPoller:
    """Background task that polls configured runners on a fixed cadence."""

    def __init__(self, config: GatewayConfig) -> None:
        self._config = config
        self._task: asyncio.Task[None] | None = None
        self._stop_event = asyncio.Event()

    async def start(self) -> None:
        if self._task is not None:
            return
        self._stop_event.clear()
        self._task = asyncio.create_task(self._poll_loop())

    async def stop(self) -> None:
        self._stop_event.set()
        if self._task is not None:
            self._task.cancel()
            with suppress(asyncio.CancelledError):
                await self._task
            self._task = None

    async def _poll_loop(self) -> None:
        interval = self._config.health_poll_interval_s
        while not self._stop_event.is_set():
            # Registry polling wired in US1 (T022)
            try:
                await asyncio.wait_for(self._stop_event.wait(), timeout=interval)
            except TimeoutError:
                continue
