"""Runner stall detection and harness abort."""

import time

from harness.live_progress import (
    CampaignProgressDisplay,
    RunnerStallGuard,
    runner_stall_failure_name,
    synthetic_vitest_fail_line,
)


def test_runner_stall_guard_aborts_after_timeout_plus_grace() -> None:
    guard = RunnerStallGuard(
        {"kind": "vitest", "test_timeout_ms": 1000},
        subcampaign="npm-test",
        grace_seconds=0.05,
    )
    guard.set_current("suite > case one")
    time.sleep(1.1)
    assert guard.should_abort()
    assert guard.failure_test_name() == "suite > case one"
    assert "harness stalled" in guard.abort_error()


def test_runner_stall_guard_resets_on_meaningful_output_touch() -> None:
    from harness.live_progress import TouchProgressParser, VitestReporterParser

    guard = RunnerStallGuard(
        {"kind": "vitest", "test_timeout_ms": 200},
        grace_seconds=0.05,
    )
    display = CampaignProgressDisplay("[ai-platform/npm-test]")
    inner = VitestReporterParser(display)
    parser = TouchProgressParser(inner, guard)
    guard.set_current("case")
    time.sleep(0.1)
    parser.feed(" ✓ test/a.test.ts > suite > case 1ms\n")
    time.sleep(0.15)
    assert not guard.should_abort()


def test_workerd_spam_does_not_reset_stall_clock() -> None:
    from harness.live_progress import TouchProgressParser, VitestReporterParser

    guard = RunnerStallGuard(
        {"kind": "vitest", "test_timeout_ms": 100},
        grace_seconds=0.05,
    )
    display = CampaignProgressDisplay("[ai-platform/npm-test]")
    parser = TouchProgressParser(VitestReporterParser(display), guard)
    guard.set_current("hung case")
    time.sleep(0.05)
    parser.feed(
        "workerd/io/worker.c++:2168: info: uncaught exception; source = Uncaught\n"
    )
    time.sleep(0.12)
    assert guard.should_abort()


def test_runner_stall_failure_name_placeholder() -> None:
    assert runner_stall_failure_name("Collecting tests…", "npm-test") == (
        "npm-test: runner stalled (no progress)"
    )


def test_synthetic_vitest_fail_line_matches_parser() -> None:
    from harness.live_progress import VitestReporterParser

    display = CampaignProgressDisplay("[ai-platform/npm-test]")
    parser = VitestReporterParser(display)
    name = "path > suite > hung case"
    parser.feed(synthetic_vitest_fail_line(name))
    assert display.failed == 1


def test_record_dangling_failure_on_abnormal_exit() -> None:
    display = CampaignProgressDisplay(
        "[abo/system]",
        campaign_config={"kind": "vitest", "test_timeout_ms": 120_000},
    )
    display.set_current("matrix > SYS-1 case")
    dangling = display.record_dangling_failure_on_exit(1)
    assert dangling == "matrix > SYS-1 case"
    assert display.failed == 1
