"""First-token, total, and model-swap timeout orchestration."""

from __future__ import annotations

import asyncio
import time
from collections.abc import AsyncIterator, Awaitable, Callable
from contextlib import asynccontextmanager
from dataclasses import dataclass
from enum import Enum
from typing import TypeVar

from ai_common.verbose_logging import get_logger

from gateway.api.errors import ErrorCode, GatewayError
from gateway.config.settings import GatewayConfig
from gateway.routing.lifecycle import RunnerStatus

T = TypeVar("T")

vlog = get_logger(__name__)


class TimeoutKind(str, Enum):
    FIRST_TOKEN = "first_token"
    TOTAL = "total"
    MODEL_SWAP_FIRST_TOKEN = "model_swap_first_token"


@dataclass(frozen=True)
class TimeoutSettings:
    """Resolved timeout values from gateway config."""

    first_token_s: float
    total_s: float
    model_swap_first_token_s: float

    @classmethod
    def from_config(cls, config: GatewayConfig) -> TimeoutSettings:
        settings = cls(
            first_token_s=float(config.timeout_first_token_s),
            total_s=float(config.timeout_total_s),
            model_swap_first_token_s=float(config.model_swap_first_token_timeout_s),
        )
        vlog.v1(
            "Resolved timeout settings from config",
            first_token_s=settings.first_token_s,
            total_s=settings.total_s,
            model_swap_first_token_s=settings.model_swap_first_token_s,
        )
        return settings


class TimeoutBreached(GatewayError):
    """Runner call exceeded a configured timeout → 504 ai_timeout."""

    def __init__(
        self,
        kind: TimeoutKind,
        message: str,
        request_id: str | None = None,
    ) -> None:
        self.kind = kind
        super().__init__(ErrorCode.AI_TIMEOUT, message, request_id)


class FirstTokenTimeout(TimeoutBreached):
    def __init__(self, request_id: str | None = None) -> None:
        super().__init__(
            TimeoutKind.FIRST_TOKEN,
            "First token timeout exceeded",
            request_id,
        )


class TotalTimeout(TimeoutBreached):
    def __init__(self, request_id: str | None = None) -> None:
        super().__init__(
            TimeoutKind.TOTAL,
            "Total inference timeout exceeded",
            request_id,
        )


class ModelSwapFirstTokenTimeout(TimeoutBreached):
    def __init__(self, request_id: str | None = None) -> None:
        super().__init__(
            TimeoutKind.MODEL_SWAP_FIRST_TOKEN,
            "Model swap first-token timeout exceeded",
            request_id,
        )


def first_token_timeout_s(
    settings: TimeoutSettings,
    *,
    runner_status: RunnerStatus | None = None,
) -> float:
    """Return the applicable first-token timeout for the runner state."""
    if runner_status == RunnerStatus.STARTING:
        return settings.model_swap_first_token_s
    return settings.first_token_s


@asynccontextmanager
async def total_timeout(
    settings: TimeoutSettings,
    *,
    request_id: str | None = None,
):
    """Bound the entire runner call with the configured total timeout."""
    try:
        async with asyncio.timeout(settings.total_s):
            yield
    except TimeoutError as exc:
        vlog.v0("Total inference timeout exceeded", request_id=request_id, limit_s=settings.total_s)
        raise TotalTimeout(request_id) from exc


@asynccontextmanager
async def first_token_timeout(
    settings: TimeoutSettings,
    *,
    runner_status: RunnerStatus | None = None,
    request_id: str | None = None,
):
    """Bound time-to-first-token; uses the extended model-swap window when STARTING."""
    limit = first_token_timeout_s(settings, runner_status=runner_status)
    try:
        async with asyncio.timeout(limit):
            yield
    except TimeoutError as exc:
        if runner_status == RunnerStatus.STARTING:
            vlog.v0(
                "Model swap first-token timeout exceeded",
                request_id=request_id,
                limit_s=limit,
            )
            raise ModelSwapFirstTokenTimeout(request_id) from exc
        vlog.v0("First-token timeout exceeded", request_id=request_id, limit_s=limit)
        raise FirstTokenTimeout(request_id) from exc


async def await_first_token(
    awaitable: Awaitable[T],
    *,
    settings: TimeoutSettings,
    runner_status: RunnerStatus | None = None,
    request_id: str | None = None,
) -> T:
    """Await a first-token signal (e.g. first stream delta) within the timeout."""
    async with first_token_timeout(
        settings,
        runner_status=runner_status,
        request_id=request_id,
    ):
        return await awaitable


async def run_with_total_timeout(
    coro: Awaitable[T],
    *,
    settings: TimeoutSettings,
    request_id: str | None = None,
    on_timeout: Callable[[], None] | None = None,
) -> T:
    """Run a coroutine under total timeout; optional callback on breach."""
    try:
        async with total_timeout(settings, request_id=request_id):
            return await coro
    except TotalTimeout:
        if on_timeout is not None:
            on_timeout()
        raise


@dataclass
class FirstTokenTracker:
    """Tracks first-token latency for logging and timeout enforcement."""

    started_at: float
    first_token_at: float | None = None

    @classmethod
    def start(cls) -> FirstTokenTracker:
        vlog.v2("Started first-token latency tracking")
        return cls(started_at=time.perf_counter())

    def mark_first_token(self) -> float:
        if self.first_token_at is None:
            self.first_token_at = time.perf_counter()
            vlog.v2("Recorded first token arrival", elapsed_s=self.elapsed_first_token())
        return self.elapsed_first_token()

    @property
    def received(self) -> bool:
        return self.first_token_at is not None

    def elapsed_first_token(self) -> float:
        if self.first_token_at is None:
            return time.perf_counter() - self.started_at
        return self.first_token_at - self.started_at


async def stream_with_first_token_timeout(
    stream: AsyncIterator[T],
    *,
    settings: TimeoutSettings,
    runner_status: RunnerStatus | None = None,
    request_id: str | None = None,
    on_first: Callable[[T], None] | None = None,
) -> AsyncIterator[T]:
    """Yield stream items; enforce first-token timeout until the first item arrives."""
    tracker = FirstTokenTracker.start()
    iterator = stream.__aiter__()
    first_pending = True

    while True:
        if first_pending:
            limit = first_token_timeout_s(settings, runner_status=runner_status)
            try:
                async with asyncio.timeout(limit):
                    item = await iterator.__anext__()
            except StopAsyncIteration:
                return
            except TimeoutError as exc:
                if runner_status == RunnerStatus.STARTING:
                    vlog.v0(
                        "Streaming model swap first-token timeout exceeded",
                        request_id=request_id,
                    )
                    raise ModelSwapFirstTokenTimeout(request_id) from exc
                vlog.v0(
                    "Streaming first-token timeout exceeded",
                    request_id=request_id,
                )
                raise FirstTokenTimeout(request_id) from exc
            tracker.mark_first_token()
            first_pending = False
            if on_first is not None:
                on_first(item)
            yield item
        else:
            try:
                item = await iterator.__anext__()
            except StopAsyncIteration:
                return
            yield item
