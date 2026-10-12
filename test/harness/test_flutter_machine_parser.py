"""Flutter machine parser label and testID handling."""

import json

from harness.flutter_machine_labels import flutter_test_label, is_loading_pseudo_test
from harness.live_progress import (
    CampaignProgressDisplay,
    FlutterMachineParser,
    should_forward_progress_stdout_line,
)


def test_skip_loading_pseudo_test() -> None:
    test = {"name": "loading /home/user/foo_test.dart", "id": 1}
    assert is_loading_pseudo_test(test)
    assert flutter_test_label(test) is None


def test_skip_compiling_pseudo_test() -> None:
    test = {"name": "compiling /home/user/foo_test.dart", "id": 1}
    assert is_loading_pseudo_test(test)
    assert flutter_test_label(test) is None


def test_forward_stdout_filters_tooling_noise() -> None:
    assert should_forward_progress_stdout_line('{"type":"testStart"}\n')
    assert not should_forward_progress_stdout_line("Compiling lib/main.dart\n")
    assert should_forward_progress_stdout_line("   PASS\n")


def test_campaign_status_does_not_change_current_test() -> None:
    display = CampaignProgressDisplay("[frontend/unit]")
    parser = FlutterMachineParser(display)
    parser.feed("CAMPAIGN_STATUS: Compiling & running Flutter unit tests…\n")
    assert display.current == "(starting…)"


def test_prefer_test_name_over_path() -> None:
    test = {
        "name": "Patient table renders rows",
        "url": "file:///home/user/patient_table_test.dart",
        "id": 2,
    }
    assert flutter_test_label(test) == "Patient table renders rows"


def test_test_done_uses_test_id() -> None:
    display = CampaignProgressDisplay("[frontend/unit]")
    parser = FlutterMachineParser(display)
    parser.feed(
        json.dumps(
            {
                "type": "testStart",
                "test": {
                    "id": 5,
                    "name": "shows loading skeleton",
                    "url": "file:///proj/patients_page_test.dart",
                },
            }
        )
        + "\n"
    )
    assert display.current == "shows loading skeleton"
    parser.feed(
        json.dumps(
            {"type": "testDone", "testID": 5, "result": "success", "hidden": False}
        )
        + "\n"
    )
    assert display.passed == 1
    assert display.failed == 0


def test_error_event_marks_failure_without_test_done() -> None:
    display = CampaignProgressDisplay("[frontend/unit]")
    parser = FlutterMachineParser(display)
    parser.feed(
        json.dumps(
            {
                "type": "testStart",
                "test": {
                    "id": 7,
                    "name": "throws in build",
                    "url": "file:///proj/broken_test.dart",
                },
            }
        )
        + "\n"
    )
    parser.feed(
        json.dumps({"type": "error", "testID": 7, "error": "Bad state: no element"})
        + "\n"
    )
    assert display.failed == 1
