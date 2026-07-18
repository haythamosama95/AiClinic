"""Single idempotent retry preferring a different healthy runner."""

from __future__ import annotations

from collections.abc import Awaitable, Callable
from dataclasses import dataclass
from typing import TypeVar

import httpx
import structlog

from gateway.api.errors import ErrorCode, GatewayError
from gateway.obs.logging import log_record
from gateway.pipeline.timeout import FirstTokenTimeout, TotalTimeout
from gateway.routing.lifecycle import RunnerStatus
from gateway.routing.registry import RunnerRegistryEntry
from gateway.routing.selector import RunnerSelector

T = TypeVar("T")

logger = structlog.get_logger("gateway.pipeline.retry")

_ROUTABLE = frozenset({RunnerStatus.READY, RunnerStatus.DEGRADED})


@dataclass(frozen=True)
class RetryContext:
    """Inputs that govern whether a retry is permitted."""

    request_id: str
    partial_stream_sent: bool = False
    queue_was_full: bool = False
    retried: bool = False
    endpoint: str = "/v1/ai/generate"


def is_retryable_error(exc: BaseException) -> bool:
    """Return True for connection errors, runner 5xx, or first-token timeout."""
    if isinstance(exc, FirstTokenTimeout):
        return True
    if isinstance(exc, TotalTimeout):
        return False
    if isinstance(exc, GatewayError):
        if exc.code == ErrorCode.AI_UNUSABLE:
            return False
        if exc.code == ErrorCode.AI_BUSY:
            return False
        return False
    if isinstance(exc, httpx.HTTPStatusError):
        status = exc.response.status_code
        return status >= 500
    if isinstance(exc, (httpx.ConnectError, httpx.NetworkError, httpx.RemoteProtocolError)):
        return True
    return False


def should_retry(ctx: RetryContext, exc: BaseException) -> bool:
    """Decide whether a single retry is allowed for this failure."""
    if ctx.retried:
        return False
    if ctx.partial_stream_sent:
        return False
    if ctx.queue_was_full:
        return False
    if isinstance(exc, GatewayError) and exc.code == ErrorCode.AI_UNUSABLE:
        return False
    if isinstance(exc, TotalTimeout):
        return False
    return is_retryable_error(exc)


def select_retry_runner(
    entries: list[RunnerRegistryEntry],
    *,
    failed_runner_id: str,
    required_capabilities: list[str],
    selector: RunnerSelector | None = None,
) -> RunnerRegistryEntry | None:
    """Pick a different healthy runner; fall back to same runner when none available."""
    pick = selector or RunnerSelector()

    different = [
        entry
        for entry in entries
        if entry.id != failed_runner_id
        and entry.status in _ROUTABLE
        and all(cap in entry.declared_capabilities for cap in required_capabilities)
    ]
    if different:
        return pick.select(different, required_capabilities=required_capabilities)

    same_pool = [
        entry
        for entry in entries
        if entry.id == failed_runner_id and entry.status in _ROUTABLE
    ]
    if same_pool:
        return pick.select(same_pool, required_capabilities=required_capabilities)
    return None


async def execute_with_retry(
    call: Callable[[RunnerRegistryEntry], Awaitable[T]],
    *,
    initial_runner: RunnerRegistryEntry,
    all_entries: list[RunnerRegistryEntry],
    required_capabilities: list[str],
    ctx: RetryContext,
    caller_staff_id: str | None = None,
) -> tuple[T, RunnerRegistryEntry, bool]:
    """Run ``call`` once; on retryable failure retry exactly once on a different runner."""
    retried = False
    runner = initial_runner
    try:
        result = await call(runner)
        return result, runner, retried
    except BaseException as first_exc:
        if not should_retry(ctx, first_exc):
            raise
        retry_runner = select_retry_runner(
            all_entries,
            failed_runner_id=runner.id,
            required_capabilities=required_capabilities,
        )
        if retry_runner is None:
            raise
        retried = True
        logger.info(
            "generation_retry",
            request_id=ctx.request_id,
            failed_runner=runner.id,
            retry_runner=retry_runner.id,
            retried=True,
        )
        log_record(
            request_id=ctx.request_id,
            endpoint=ctx.endpoint,
            outcome="retry",
            caller_staff_id=caller_staff_id,
            runner_id=retry_runner.id,
            retried=True,
        )
        try:
            result = await call(retry_runner)
            return result, retry_runner, retried
        except BaseException:
            raise
