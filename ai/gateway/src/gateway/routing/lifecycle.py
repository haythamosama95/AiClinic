"""Pure runner lifecycle transition function (UNKNOWN..UNREACHABLE)."""

from __future__ import annotations

from dataclasses import dataclass
from enum import Enum


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


def transition(
    current: RunnerStatus,
    outcome: PollOutcome,
    counters: LifecycleCounters,
    unreachable_after_failures: int,
    *,
    has_loaded_model: bool = False,
) -> LifecycleTransition:
    """Compute the next lifecycle state from a poll outcome.

    Pure function: (status, outcome, counters, config) → next_status.
    US1 covers UNKNOWN→STARTING→READY and UNREACHABLE after N failures.
    """
    if outcome == PollOutcome.OK and has_loaded_model:
        return LifecycleTransition(
            status=RunnerStatus.READY,
            consecutive_failures=0,
        )

    if outcome in (PollOutcome.OK, PollOutcome.LOADING) and not has_loaded_model:
        return LifecycleTransition(
            status=RunnerStatus.STARTING,
            consecutive_failures=0,
        )

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
        return LifecycleTransition(
            status=current,
            consecutive_failures=failures,
        )

    return LifecycleTransition(
        status=current,
        consecutive_failures=counters.consecutive_failures,
    )
