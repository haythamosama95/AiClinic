"""Unit tests for live progress display helpers."""

from harness.live_progress import (
    CampaignProgressDisplay,
    NoOpCampaignProgressDisplay,
    NodeTestParser,
    StepProgressParser,
    VitestReporterParser,
    _FailureTree,
    _render_failure_tree_plain,
)

_render_failure_tree = _render_failure_tree_plain


def test_failure_tree_nested_paths() -> None:
    tree = _FailureTree()
    tree.insert(("unit",), "widget test")
    tree.insert(("boundary", "boundary-auth"), "auth test")
    lines = _render_failure_tree(tree)
    assert lines == [
        "├─ boundary",
        "│  └─ boundary-auth",
        "│     └─ auth test",
        "└─ unit",
        "   └─ widget test",
    ]


def test_failure_tree_groups_colon_separated_step_names() -> None:
    display = CampaignProgressDisplay("[backend/all]")
    display.add_finished("Visit medical records: visit_medical_records_crud.sql", "FAIL")
    display.add_finished("Visit medical records: visit_medical_records_rls.sql", "FAIL")
    lines = display._status_lines()
    assert lines[-1] == "Passed 0  Failed 2"
    assert "⏱" in lines[0]
    assert not any(line == "Failures" for line in lines)
    assert not any(
        line.strip().startswith("└─ Visit medical records") for line in lines
    )


def test_activity_labels_split_group_and_case() -> None:
    display = CampaignProgressDisplay("[backend/all]")
    display.set_current("Visit medical records: visit_medical_records_crud.sql")
    assert display._activity_labels() == (
        "Visit medical records",
        "visit_medical_records_crud.sql",
    )
    display.set_nested_subcampaign("unit")
    display.set_current("widget renders name")
    assert display._activity_labels() == ("unit", "widget renders name")


def test_config_shown_in_campaign_queue_panel() -> None:
    display = CampaignProgressDisplay(
        "[frontend/unit]",
        campaign_config={
            "kind": "flutter",
            "parallel_tests": 15,
            "coverage": True,
        },
    )
    lines = display._status_lines()
    queue_block = "\n".join(lines[:6])
    assert "Parallel tests: 15" in queue_block
    assert "Coverage: on" in queue_block
    assert any("Passed" in line for line in lines)


def test_frontend_all_nested_step_populates_config_panel() -> None:
    from harness.campaign_config import governor_config_area

    display = CampaignProgressDisplay(
        "[frontend/all]",
        config_area=governor_config_area("frontend"),
    )
    display.set_nested_subcampaign("unit")
    lines = display._status_lines()
    assert any("Parallel tests: 15" in line for line in lines)
    assert any("Coverage: on" in line for line in lines)


def test_run_directory_in_queue_panel_not_separate_box() -> None:
    from pathlib import Path

    from harness.batch_queue_display import batch_queue_from_picked, plain_queue_lines

    run_root = Path("/tmp/governor-run")
    picked = [("backend", "all")]
    state = batch_queue_from_picked(picked, {"backend": ["all"]})
    lines = plain_queue_lines(state, run_directory=run_root)
    joined = "\n".join(lines)
    assert "Run directory: /tmp/governor-run" in joined
    assert "Run plan" not in joined


def test_vitest_pass_resets_case_timer_and_uses_reported_duration() -> None:
    import time

    display = CampaignProgressDisplay(
        "[abo/system]",
        campaign_config={"kind": "vitest", "test_timeout_ms": 120_000},
    )
    parser = VitestReporterParser(display)
    parser.feed("\n RUN  v3.2.7 /tmp/project\n")
    time.sleep(0.05)
    parser.feed(
        "✓ [workers] [test/system/foo.system.test.ts > suite > case one 2000ms]\n"
    )
    assert display._case_elapsed_seconds() < 5.0


def test_vitest_stdout_capture_does_not_set_current_test() -> None:
    display = CampaignProgressDisplay("[ai-platform/npm-test]")
    parser = VitestReporterParser(display)
    parser.feed(
        "stdout | test/system/platform-rebuild.system.test.ts > suite > case one\n"
    )
    assert display.current == "(starting…)"


def test_vitest_verbose_fail_file_line_counts_failure() -> None:
    display = CampaignProgressDisplay("[ai-platform/npm-test]")
    parser = VitestReporterParser(display)
    parser.feed(
        " FAIL  test/discovery-http.test.ts > T1 discovery_http_granted_active_manifests > returns only granted effective-active or deprecated manifests\n"
    )
    display.tick()
    assert display.failed == 1


def test_vitest_unit_pool_pass_line_shows_case_name() -> None:
    display = CampaignProgressDisplay("[ai-platform/unit]")
    parser = VitestReporterParser(display)
    parser.feed(
        " ✓ test/control-plane/admission.test.ts > admission credit > grants on first use 42ms\n"
    )
    assert display.passed == 1
    assert display._phase == "running"
    sub, case = display._activity_labels()
    assert case == "grants on first use"
    assert "admission credit" in sub


def test_vitest_workers_pass_line_shows_case_name() -> None:
    display = CampaignProgressDisplay("[abo/system]")
    parser = VitestReporterParser(display)
    line = (
        "✓ [workers] [test/system/foo.system.test.ts > failure taxonomy matrix > "
        "SYS-6.16 — Rate-limit burst → rate_limited 23493ms]"
    )
    parser.feed(line + "\n")
    assert display.passed == 1
    assert display._phase == "running"
    assert "SYS-6.16" in display.current
    assert "running…" not in display._plain_activity_label("00:01")


def test_step_parser_skip_resumed_after_header() -> None:
    display = CampaignProgressDisplay("[backend/all]")
    parser = StepProgressParser(display)
    display.seed_prior_results(10, 2)
    parser.feed("== [3] Patient management: patient_mrn_generation.sql ==\n")
    parser.feed("   SKIP (resumed)\n")
    assert display.passed == 10
    assert display.failed == 2


def test_add_finished_from_worker_thread_updates_on_tick() -> None:
    import threading

    display = CampaignProgressDisplay("[ai-platform/npm-test]")
    display._use_rich = False
    display.begin(clear_screen=False)
    display._ui_thread_id = threading.main_thread().ident

    def worker() -> None:
        display.add_finished("case from worker", "PASS")

    thread = threading.Thread(target=worker)
    thread.start()
    thread.join()
    display.tick()
    assert display.passed == 1


def test_resume_seed_counts_retry_without_full_map() -> None:
    display = CampaignProgressDisplay("[ai-platform/npm-test]")
    display.seed_prior_results(10, 2, failure_names=["case a", "case b"])
    assert (display.passed, display.failed) == (10, 2)
    display.add_finished("case a", "PASS")
    assert (display.passed, display.failed) == (11, 1)


def test_add_finished_upserts_by_test_name_on_retry() -> None:
    display = CampaignProgressDisplay("[ai-platform/npm-test]")
    display.add_finished("case a", "FAIL")
    display.add_finished("case b", "PASS")
    assert (display.passed, display.failed) == (1, 1)
    display.add_finished("case a", "PASS")
    assert (display.passed, display.failed) == (2, 0)


def test_seed_prior_results_renders_failed_count() -> None:
    display = CampaignProgressDisplay("[backend/all]")
    display.seed_prior_results(72, 10)
    lines = display._status_lines()
    assert lines[-1] == "Passed 72  Failed 10"


def test_vitest_reporter_noop_display_accepts_duration() -> None:
    """Governor resume routes vitest output through NoOpCampaignProgressDisplay."""
    display = NoOpCampaignProgressDisplay()
    parser = VitestReporterParser(display)
    parser.feed("  × failing case 42ms\n")
    parser.feed("  ✓ passing case 12ms\n")


def test_vitest_bootstrap_sets_runtime_status() -> None:
    display = CampaignProgressDisplay("[abo/system]")
    parser = VitestReporterParser(display)
    parser.feed("[vpw:info] Starting isolated runtimes for vitest.workers.config.ts...\n")
    assert display.current == "Starting worker runtime…"
    parser.feed("\n RUN  v3.2.7 /tmp/project\n")
    assert display.current == "Collecting tests…"


def test_governor_run_root_is_sole_log_footer_path() -> None:
    from pathlib import Path

    run_root = Path("/tmp/governor-run")
    display = CampaignProgressDisplay(
        "[backend/auth-rbac]",
        run_log_root=run_root,
    )
    display.prepare_run("[backend/patients]", Path("/tmp/governor-run/backend/patients"))
    assert display._log_dirs_for_footer() == [run_root]


def test_display_counts_failures_without_listing_names() -> None:
    display = CampaignProgressDisplay("[frontend/all]")
    display.set_nested_subcampaign("unit")
    display.add_finished("ok test", "PASS")
    display.add_finished("bad test", "FAIL")
    assert display.passed == 1
    assert display.failed == 1
    lines = display._status_lines()
    assert lines[0].startswith("[frontend] [all]")
    assert lines[-1] == "Passed 1  Failed 1"


def test_node_tap_wrangler_diagnostics_leave_starting_phase() -> None:
    display = CampaignProgressDisplay("[e2e-fullstack/all-ci]")
    parser = NodeTestParser(display)
    assert display._phase == "starting"
    parser.feed("# Using secrets defined in ../../ai-platform/.dev.vars.development\n")
    assert display._phase == "running"
    assert "Using secrets" in display.current
    parser.feed("# Subtest: example case\n")
    assert display.current == "example case"
    parser.feed("# ⎔ Connection status updated\n")
    assert display.current == "example case"


def test_vitest_checkmark_counted_once_with_orchestrator_parsers() -> None:
    import sys
    from pathlib import Path

    from harness.live_progress import parser_for_command

    display = CampaignProgressDisplay("[ai-platform/npm-test]")
    cmd = [sys.executable, str(Path("ai-platform/run_campaigns.py")), "npm-test"]
    parser = parser_for_command(cmd, display)
    parser.feed("  ✔ worker case 12ms\n")
    assert display.passed == 1


def test_e2e_fullstack_orchestrator_parses_node_subtests() -> None:
    import sys
    from pathlib import Path

    from harness.live_progress import parser_for_command

    display = CampaignProgressDisplay("[e2e-fullstack/all-ci]")
    cmd = [
        sys.executable,
        str(Path("e2e/fullstack/run_campaigns.py")),
        "all-ci",
    ]
    parser = parser_for_command(cmd, display)
    parser.feed("# Subtest: boots platform worker\n")
    assert display.current == "boots platform worker"
    parser.feed("ok 1 - boots platform worker\n")
    assert display.passed == 1
    parser.feed("  ✔ nested case name\n")
    assert display.passed == 2
