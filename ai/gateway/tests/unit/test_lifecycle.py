"""Runner lifecycle transition unit tests."""

from __future__ import annotations

import pytest

from gateway.routing.lifecycle import (
    LifecycleCounters,
    PollOutcome,
    RunnerStatus,
    transition,
)


@pytest.mark.parametrize(
    ("current", "outcome", "has_model", "expected_status"),
    [
        (RunnerStatus.UNKNOWN, PollOutcome.LOADING, False, RunnerStatus.STARTING),
        (RunnerStatus.UNKNOWN, PollOutcome.OK, True, RunnerStatus.READY),
        (RunnerStatus.STARTING, PollOutcome.OK, True, RunnerStatus.READY),
        (RunnerStatus.UNREACHABLE, PollOutcome.OK, True, RunnerStatus.READY),
    ],
)
def test_happy_path_transitions(
    current: RunnerStatus,
    outcome: PollOutcome,
    has_model: bool,
    expected_status: RunnerStatus,
) -> None:
    result = transition(
        current,
        outcome,
        LifecycleCounters(consecutive_failures=0),
        unreachable_after_failures=3,
        has_loaded_model=has_model,
    )
    assert result.status == expected_status
    assert result.consecutive_failures == 0


def test_unknown_to_starting_to_ready_walk() -> None:
    step1 = transition(
        RunnerStatus.UNKNOWN,
        PollOutcome.LOADING,
        LifecycleCounters(0),
        3,
        has_loaded_model=False,
    )
    assert step1.status == RunnerStatus.STARTING

    step2 = transition(
        step1.status,
        PollOutcome.OK,
        LifecycleCounters(step1.consecutive_failures),
        3,
        has_loaded_model=True,
    )
    assert step2.status == RunnerStatus.READY


def test_unreachable_after_three_failures() -> None:
    status = RunnerStatus.STARTING
    failures = 0
    for _ in range(2):
        result = transition(
            status,
            PollOutcome.ERROR,
            LifecycleCounters(failures),
            unreachable_after_failures=3,
        )
        status = result.status
        failures = result.consecutive_failures
        assert result.status == RunnerStatus.STARTING

    final = transition(
        status,
        PollOutcome.TIMEOUT,
        LifecycleCounters(failures),
        unreachable_after_failures=3,
    )
    assert final.status == RunnerStatus.UNREACHABLE
    assert final.consecutive_failures == 3


def test_success_resets_failure_counter() -> None:
    result = transition(
        RunnerStatus.STARTING,
        PollOutcome.OK,
        LifecycleCounters(consecutive_failures=2),
        unreachable_after_failures=3,
        has_loaded_model=True,
    )
    assert result.status == RunnerStatus.READY
    assert result.consecutive_failures == 0
