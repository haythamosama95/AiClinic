"""Pure runner lifecycle transition function (UNKNOWN..UNREACHABLE)."""

from __future__ import annotations

from dataclasses import dataclass
from enum import Enum

DEFAULT_DEGRADED_LATENCY_MS = 2000.0


class RunnerStatus(str, Enum):
    UNKNOWN = "UNKNOWN"
    STARTING = "STARTING"
    READY = "READY"
    BUSY = "BUSY"
    DEGRADED = "DEGRADED"
    UNREACHABLE = "UNREACHABLE"


class PollOutcome(str, Enum):
    OK = "ok"
    LOADING = "loading"
    ERROR = "error"
    TIMEOUT = "timeout"


@dataclass(frozen=True)
class LifecycleCounters:
    consecutive_failures: int = 0


@dataclass(frozen=True)
class LifecycleTransition:
    status: RunnerStatus
    consecutive_failures: int


def _is_elevated_latency(
    latency_ms: float | None,
    avg_latency_ms: float | None,
    *,
    degraded_latency_ms: float,
    baseline_latency_ms: float | None,
) -> bool:
    if latency_ms is not None and latency_ms > degraded_latency_ms:
        return True
    if avg_latency_ms is not None and avg_latency_ms > degraded_latency_ms:
        return True
    if (
        avg_latency_ms is not None
        and baseline_latency_ms is not None
        and baseline_latency_ms > 0
        and avg_latency_ms > baseline_latency_ms * 2
    ):
        return True
    return False


def _healthy_status(
    current: RunnerStatus,
    *,
    elevated_latency: bool,
) -> RunnerStatus:
    if elevated_latency:
        return RunnerStatus.DEGRADED
    if current == RunnerStatus.DEGRADED:
        return RunnerStatus.READY
    return RunnerStatus.READY


def _apply_capacity(
    status: RunnerStatus,
    *,
    in_flight: int,
    max_inflight: int,
) -> RunnerStatus:
    if status in (RunnerStatus.READY, RunnerStatus.DEGRADED) and in_flight >= max_inflight:
        return RunnerStatus.BUSY
    if status == RunnerStatus.BUSY and in_flight < max_inflight:
        return RunnerStatus.READY
    return status


def transition(
    current: RunnerStatus,
    outcome: PollOutcome,
    counters: LifecycleCounters,
    unreachable_after_failures: int,
    *,
    has_loaded_model: bool = False,
    latency_ms: float | None = None,
    avg_latency_ms: float | None = None,
    in_flight: int = 0,
    max_inflight: int = 1,
    degraded_latency_ms: float = DEFAULT_DEGRADED_LATENCY_MS,
    baseline_latency_ms: float | None = None,
) -> LifecycleTransition:
    """Compute the next lifecycle state from a poll outcome.

    Pure function: (status, outcome, counters, config) → next_status.
    Covers the full state machine in data-model §3.
    """
    if outcome in (PollOutcome.ERROR, PollOutcome.TIMEOUT):
        failures = counters.consecutive_failures + 1
        if failures >= unreachable_after_failures:
            return LifecycleTransition(
                status=RunnerStatus.UNREACHABLE,
                consecutive_failures=failures,
            )
        if current == RunnerStatus.UNKNOWN:
            return LifecycleTransition(
                status=RunnerStatus.UNKNOWN,
                consecutive_failures=failures,
            )
        if current in (RunnerStatus.READY, RunnerStatus.DEGRADED, RunnerStatus.BUSY):
            return LifecycleTransition(
                status=RunnerStatus.DEGRADED,
                consecutive_failures=failures,
            )
        return LifecycleTransition(
            status=current,
            consecutive_failures=failures,
        )

    if current == RunnerStatus.UNREACHABLE:
        if outcome == PollOutcome.OK and has_loaded_model:
            next_status = RunnerStatus.READY
        else:
            next_status = RunnerStatus.STARTING
        return LifecycleTransition(
            status=_apply_capacity(
                next_status,
                in_flight=in_flight,
                max_inflight=max_inflight,
            ),
            consecutive_failures=0,
        )

    if outcome == PollOutcome.OK and has_loaded_model:
        elevated = _is_elevated_latency(
            latency_ms,
            avg_latency_ms,
            degraded_latency_ms=degraded_latency_ms,
            baseline_latency_ms=baseline_latency_ms,
        )
        next_status = _healthy_status(current, elevated_latency=elevated)
        return LifecycleTransition(
            status=_apply_capacity(
                next_status,
                in_flight=in_flight,
                max_inflight=max_inflight,
            ),
            consecutive_failures=0,
        )

    if outcome in (PollOutcome.OK, PollOutcome.LOADING) and not has_loaded_model:
        return LifecycleTransition(
            status=RunnerStatus.STARTING,
            consecutive_failures=0,
        )

    if current == RunnerStatus.BUSY and in_flight < max_inflight:
        return LifecycleTransition(
            status=RunnerStatus.READY,
            consecutive_failures=0,
        )

    return LifecycleTransition(
        status=current,
        consecutive_failures=counters.consecutive_failures,
    )
