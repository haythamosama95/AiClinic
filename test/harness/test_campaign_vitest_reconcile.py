"""Vitest summary reconcile for resume exclude accuracy."""

import json
from pathlib import Path

from harness.campaign_resume import recorded_test_names_from_summary
from harness.campaign_vitest_reconcile import (
    filter_recorded_vitest_names,
    is_harness_artifact_test_name,
    reconcile_vitest_summary_log,
)


def test_is_harness_artifact_test_name() -> None:
    assert is_harness_artifact_test_name(
        "stdout | test/system/foo.test.ts > suite > case"
    )
    assert is_harness_artifact_test_name("npm-test: runner stalled (no progress)")
    assert not is_harness_artifact_test_name(
        "test/foo.test.ts > suite > case one"
    )


def test_filter_recorded_drops_suite_only_noise(tmp_path: Path) -> None:
    labels = {
        "test/support-lookup.test.ts > support_lookup_reference_input > leaf one",
    }
    raw = {
        "test/support-lookup.test.ts > support_lookup_reference_input",
        "stdout | test/system/platform-rebuild.system.test.ts > suite > case",
        "test/support-lookup.test.ts > support_lookup_reference_input > leaf one",
    }

    def fake_labels(area: str, sub: str) -> set[str]:
        return labels

    from harness import campaign_vitest_reconcile as mod

    original = mod.vitest_labels_for_subcampaign
    mod.vitest_labels_for_subcampaign = fake_labels
    try:
        out = filter_recorded_vitest_names(
            raw,
            area="ai-platform",
            subcampaign="npm-test",
        )
    finally:
        mod.vitest_labels_for_subcampaign = original
    assert out == {
        "test/support-lookup.test.ts > support_lookup_reference_input > leaf one",
    }


def test_reconcile_adds_missing_fail_rows(tmp_path: Path) -> None:
    log_dir = tmp_path / "npm-test"
    log_dir.mkdir()
    missing = "test/system/platform-rebuild.system.test.ts > suite > case one"
    (log_dir / "summary.json").write_text(
        json.dumps(
            {
                "tests": [
                    {
                        "name": "stdout | " + missing,
                        "status": "FAIL",
                        "log_file": "tests/001.log",
                    }
                ],
                "passed": 0,
                "failed": 1,
                "exit_code": 1,
            }
        ),
        encoding="utf-8",
    )

    def fake_labels(area: str, sub: str) -> set[str]:
        return {missing}

    from harness import campaign_vitest_reconcile as mod

    original = mod.vitest_labels_for_subcampaign
    mod.vitest_labels_for_subcampaign = fake_labels
    try:
        assert reconcile_vitest_summary_log(
            log_dir,
            area="ai-platform",
            subcampaign="npm-test",
            cwd=tmp_path,
        )
        payload = json.loads((log_dir / "summary.json").read_text())
        names = {t["name"] for t in payload["tests"]}
        assert missing in names
        assert payload["failed"] == 1
        assert not any(n.startswith("stdout |") for n in names)
        recorded = recorded_test_names_from_summary(
            log_dir,
            area="ai-platform",
            subcampaign="npm-test",
        )
        assert missing in recorded
    finally:
        mod.vitest_labels_for_subcampaign = original


def test_reconcile_marks_missing_outcomes_and_keeps_runner_diagnostics(
    tmp_path: Path,
) -> None:
    log_dir = tmp_path / "npm-test"
    log_dir.mkdir()
    missing = "test/system/example.system.test.ts > suite > case one"
    (log_dir / "summary.json").write_text(
        json.dumps({"tests": []}),
        encoding="utf-8",
    )
    (log_dir / "output.log").write_text(
        "WorkersTestRunner failed to pop isolated storage stack frame\n"
        "expected .sqlite, got .sqlite-shm\n",
        encoding="utf-8",
    )

    from harness import campaign_vitest_reconcile as mod

    original = mod.vitest_labels_for_subcampaign
    mod.vitest_labels_for_subcampaign = lambda area, sub: {missing}
    try:
        assert reconcile_vitest_summary_log(
            log_dir,
            area="ai-platform",
            subcampaign="npm-test",
            cwd=tmp_path,
        )
    finally:
        mod.vitest_labels_for_subcampaign = original

    payload = json.loads((log_dir / "summary.json").read_text(encoding="utf-8"))
    assert payload["tests"][0]["failure_kind"] == "runner_missing_outcome"
    assert payload["not_recorded"] == [missing]
    assert payload["diagnostics_file"] == "output.log"
    assert payload["tests"][0]["reference"] == "output.log"
    assert payload["tests"][0]["runner_exit_code"] is None
    assert any("sqlite-shm" in line for line in payload["runner_diagnostics"])


def test_reconcile_attaches_vitest_failure_detail(tmp_path: Path) -> None:
    log_dir = tmp_path / "npm-test"
    log_dir.mkdir()
    failed = "test/foo.test.ts > suite > case one"
    (log_dir / "summary.json").write_text(json.dumps({"tests": []}), encoding="utf-8")
    (log_dir / "vitest-report.json").write_text(json.dumps({
        "numFailedTests": 1,
        "testResults": [{
            "name": "test/foo.test.ts",
            "assertionResults": [{
                "ancestorTitles": ["suite"],
                "title": "case one",
                "status": "failed",
                "failureMessages": ["expected 2 to equal 3", "at test/foo.test.ts:10"],
            }],
        }],
    }), encoding="utf-8")

    from harness import campaign_vitest_reconcile as mod

    original = mod.vitest_labels_for_subcampaign
    mod.vitest_labels_for_subcampaign = lambda area, sub: {failed}
    try:
        assert reconcile_vitest_summary_log(
            log_dir, area="ai-platform", subcampaign="npm-test", cwd=tmp_path,
        )
    finally:
        mod.vitest_labels_for_subcampaign = original
    row = json.loads((log_dir / "summary.json").read_text(encoding="utf-8"))["tests"][0]
    assert row["failure_kind"] == "test_failure"
    assert row["error"] == ["expected 2 to equal 3", "at test/foo.test.ts:10"]
    assert row["report_reference"] == "vitest-report.json"


def test_reconcile_reads_normalized_report_and_ignores_malformed_report(tmp_path: Path) -> None:
    log_dir = tmp_path / "npm-test"
    log_dir.mkdir()
    failed = "test/bar.test.ts > suite > case two"
    (log_dir / "summary.json").write_text(json.dumps({"tests": []}), encoding="utf-8")
    (log_dir / "vitest-report.json").write_text("{bad json", encoding="utf-8")
    (log_dir / "vitest-report-step2.json").write_text(json.dumps({
        "tests": [{
            "name": failed,
            "file": "test/bar.test.ts",
            "status": "failed",
            "error": ["database mismatch"],
        }],
    }), encoding="utf-8")

    from harness import campaign_vitest_reconcile as mod

    original = mod.vitest_labels_for_subcampaign
    mod.vitest_labels_for_subcampaign = lambda area, sub: {failed}
    try:
        assert reconcile_vitest_summary_log(
            log_dir, area="ai-platform", subcampaign="npm-test", cwd=tmp_path,
        )
    finally:
        mod.vitest_labels_for_subcampaign = original
    row = json.loads((log_dir / "summary.json").read_text(encoding="utf-8"))["tests"][0]
    assert row["failure_kind"] == "test_failure"
    assert row["error"] == ["database mismatch"]
    assert row["report_reference"] == "vitest-report-step2.json"
