"""Runner selection unit tests — capability, health filter, least-busy, round-robin."""

from __future__ import annotations

import pytest

from gateway.routing.lifecycle import RunnerStatus
from gateway.routing.registry import LoadedModel, RunnerRegistryEntry
from gateway.routing.selector import RunnerSelector

DEFAULT_MODEL = LoadedModel(
    name="qwen3:4b",
    digest="sha256:selector-test",
    context_tokens=8192,
    features=["json_grammar"],
)


def _entry(
    runner_id: str,
    *,
    status: RunnerStatus = RunnerStatus.READY,
    capabilities: list[str] | None = None,
    in_flight: int = 0,
    loaded_model: LoadedModel | None = DEFAULT_MODEL,
) -> RunnerRegistryEntry:
    return RunnerRegistryEntry(
        id=runner_id,
        base_url=f"http://{runner_id}.test:11434",
        status=status,
        declared_capabilities=capabilities if capabilities is not None else ["json_grammar"],
        in_flight=in_flight,
        loaded_model=loaded_model,
    )


@pytest.fixture
def selector() -> RunnerSelector:
    return RunnerSelector()


def test_capability_match_excludes_runners_without_required_capability(
    selector: RunnerSelector,
) -> None:
    capable = _entry("runner-a", capabilities=["json_grammar", "vision"])
    incapable = _entry("runner-b", capabilities=["vision"])

    chosen = selector.select(
        [incapable, capable],
        required_capabilities=["json_grammar"],
    )

    assert chosen is not None
    assert chosen.id == "runner-a"


def test_capability_match_returns_none_when_no_runner_qualifies(
    selector: RunnerSelector,
) -> None:
    entries = [
        _entry("runner-a", capabilities=["vision"]),
        _entry("runner-b", capabilities=[]),
    ]

    assert selector.select(entries, required_capabilities=["json_grammar"]) is None


def test_health_filter_prefers_ready_over_degraded(selector: RunnerSelector) -> None:
    ready = _entry("runner-ready", status=RunnerStatus.READY, in_flight=1)
    degraded = _entry("runner-degraded", status=RunnerStatus.DEGRADED, in_flight=0)

    chosen = selector.select(
        [degraded, ready],
        required_capabilities=["json_grammar"],
    )

    assert chosen is not None
    assert chosen.id == "runner-ready"


def test_health_filter_selects_degraded_when_no_ready_available(
    selector: RunnerSelector,
) -> None:
    degraded = _entry("runner-degraded", status=RunnerStatus.DEGRADED)

    chosen = selector.select(
        [
            _entry("runner-starting", status=RunnerStatus.STARTING, loaded_model=None),
            degraded,
            _entry("runner-unreachable", status=RunnerStatus.UNREACHABLE, loaded_model=None),
        ],
        required_capabilities=["json_grammar"],
    )

    assert chosen is not None
    assert chosen.id == "runner-degraded"


@pytest.mark.parametrize(
    "status",
    [RunnerStatus.STARTING, RunnerStatus.UNREACHABLE, RunnerStatus.UNKNOWN],
)
def test_health_filter_excludes_non_routable_statuses(
    selector: RunnerSelector,
    status: RunnerStatus,
) -> None:
    entries = [
        _entry("runner-blocked", status=status, loaded_model=None),
        _entry("runner-ready", status=RunnerStatus.READY),
    ]

    chosen = selector.select(entries, required_capabilities=["json_grammar"])

    assert chosen is not None
    assert chosen.id == "runner-ready"


def test_least_busy_prefers_lower_in_flight(selector: RunnerSelector) -> None:
    busy = _entry("runner-busy", status=RunnerStatus.READY, in_flight=3)
    idle = _entry("runner-idle", status=RunnerStatus.READY, in_flight=0)

    chosen = selector.select(
        [busy, idle],
        required_capabilities=["json_grammar"],
    )

    assert chosen is not None
    assert chosen.id == "runner-idle"


def test_round_robin_breaks_in_flight_ties(selector: RunnerSelector) -> None:
    runner_a = _entry("runner-a", status=RunnerStatus.READY, in_flight=0)
    runner_b = _entry("runner-b", status=RunnerStatus.READY, in_flight=0)
    entries = [runner_a, runner_b]

    first = selector.select(entries, required_capabilities=["json_grammar"])
    second = selector.select(entries, required_capabilities=["json_grammar"])
    third = selector.select(entries, required_capabilities=["json_grammar"])

    assert first is not None
    assert second is not None
    assert third is not None
    assert {first.id, second.id} == {"runner-a", "runner-b"}
    assert first.id != second.id
    assert first.id == third.id
