"""Runner crash detection (unhandled errors without a test result)."""

import json
import time

from harness.live_progress import (
    CrashInspectParser,
    FlutterMachineParser,
    NoOpCampaignProgressDisplay,
    RunnerCrashGuard,
    RunnerStallGuard,
    CampaignProgressDisplay,
    line_indicates_uncaught_runner_crash,
)


def test_line_indicates_crash_ignores_pass_fail_glyphs() -> None:
    assert line_indicates_uncaught_runner_crash("× expects exception in message") == (
        False,
        "",
    )
    assert line_indicates_uncaught_runner_crash(
        "Traceback (most recent call last):"
    ) == (True, "Traceback (most recent call last):")


def test_line_indicates_workerd_uncaught_exception() -> None:
    info = (
        "workerd/io/worker.c++:2168: info: uncaught exception; "
        "source = Uncaught (in promise)"
    )
    assert line_indicates_uncaught_runner_crash(info) == (False, "")
    error = (
        "workerd/io/worker.c++:2168: error: uncaught exception; "
        "source = Uncaught (in promise)"
    )
    assert line_indicates_uncaught_runner_crash(error)[0] is True


def test_line_indicates_crash_ignores_benign_exception_word() -> None:
    assert line_indicates_uncaught_runner_crash(
        "log: user saw Exception dialog and dismissed it"
    ) == (False, "")


def test_crash_guard_aborts_after_grace_when_still_running() -> None:
    stall = RunnerStallGuard(
        {"kind": "vitest", "test_timeout_ms": 120_000},
        subcampaign="unit",
    )
    stall.set_current("hung case")
    guard = RunnerCrashGuard(stall, grace_seconds=0.05, immediate_settle_seconds=0.05)
    guard.inspect_line('{"type":"error","error":"runner blew up"}\n')
    time.sleep(0.08)
    assert guard.should_abort()


def test_crash_guard_clears_when_test_finishes() -> None:
    stall = RunnerStallGuard(
        {"kind": "vitest", "test_timeout_ms": 120_000},
        subcampaign="unit",
    )
    stall.set_current("case")
    guard = RunnerCrashGuard(stall, grace_seconds=0.01)
    guard.inspect_line('{"type":"error","testID":1,"error":"boom"}\n')
    stall.note_finished("case", "FAIL")
    time.sleep(0.02)
    assert not guard.should_abort()


def test_crash_guard_ignores_flutter_test_error_with_test_id() -> None:
    stall = RunnerStallGuard(
        {"kind": "vitest", "test_timeout_ms": 120_000},
        subcampaign="unit",
    )
    stall.set_current("case")
    guard = RunnerCrashGuard(stall, grace_seconds=0.05, immediate_settle_seconds=0.05)
    inner = FlutterMachineParser(NoOpCampaignProgressDisplay())
    parser = CrashInspectParser(inner, guard)
    parser.feed(
        '{"type":"testStart","test":{"id":1,"name":"widget test"}}\n'
    )
    parser.feed('{"type":"error","testID":1,"error":"Expected: true"}\n')
    parser.feed(
        '{"type":"testStart","test":{"id":2,"name":"next case"}}\n'
    )
    time.sleep(0.08)
    assert not guard.should_abort()


def test_crash_inspect_clears_fatal_on_flutter_success() -> None:
    stall = RunnerStallGuard(
        {"kind": "vitest", "test_timeout_ms": 120_000},
        subcampaign="unit",
    )
    stall.set_current("case")
    guard = RunnerCrashGuard(stall, grace_seconds=0.01)
    inner = FlutterMachineParser(CampaignProgressDisplay("[frontend/unit]"))
    parser = CrashInspectParser(inner, guard)
    parser.feed('{"type":"error","testID":1,"error":"transient"}\n')
    parser.feed(
        '{"testID":1,"result":"success","hidden":false,"type":"testDone"}\n'
    )
    time.sleep(0.02)
    assert not guard.should_abort()


def test_flutter_error_event_finishes_test() -> None:
    display = CampaignProgressDisplay("[frontend/unit]")
    parser = FlutterMachineParser(display)
    parser.feed(
        json.dumps(
            {
                "type": "testStart",
                "test": {"id": 3, "name": "widget renders"},
            }
        )
        + "\n"
    )
    parser.feed(
        json.dumps(
            {
                "type": "error",
                "testID": 3,
                "error": "Expected: true",
                "stackTrace": "package:flutter_test/...",
            }
        )
        + "\n"
    )
    assert display.failed == 1
    assert display.passed == 0
