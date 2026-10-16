"""Vitest summary reconcile for resume exclude accuracy."""

import json
from pathlib import Path

from harness.campaign_resume import recorded_test_names_from_summary
from harness.campaign_vitest_reconcile import (
    filter_recorded_vitest_names,
    is_harness_artifact_test_name,
    reconcile_vitest_summary_log,
    should_reconcile_vitest_campaign,
)


def test_is_harness_artifact_test_name() -> None:
    assert is_harness_artifact_test_name(
        "stdout | test/system/foo.test.ts > suite > case"
    )
    assert is_harness_artifact_test_name("npm-test: runner stalled (no progress)")
    assert not is_harness_artifact_test_name(
        "test/foo.test.ts > suite > case one"
    )


def test_reconcile_eligibility_does_not_discover_labels(monkeypatch) -> None:
    from harness import campaign_vitest_reconcile as mod

    def unexpected_discovery(*args, **kwargs):
        raise AssertionError("eligibility must not run Vitest discovery")

    monkeypatch.setattr(mod, "vitest_labels_for_subcampaign", unexpected_discovery)
    assert should_reconcile_vitest_campaign(
        ["npx", "vitest", "run"],
        area="ai-platform",
        subcampaign="npm-test",
        campaign_config=None,
    )


def test_reconcile_interrupt_is_recorded_without_masking_test_failure(
    tmp_path: Path, monkeypatch
) -> None:
    from harness import campaign_vitest_reconcile as reconcile_mod
    from harness import common

    log_dir = tmp_path / "npm-test"
    log_dir.mkdir()
    initial = {"exit_code": 1, "interrupted": False, "tests": []}
    encoded = json.dumps(initial)
    (log_dir / "summary.json").write_text(encoded, encoding="utf-8")
    (log_dir / "meta.json").write_text(encoded, encoding="utf-8")
    monkeypatch.setattr(
        reconcile_mod, "should_reconcile_vitest_campaign", lambda *a, **k: True
    )

    def interrupt(*args, **kwargs):
        raise KeyboardInterrupt

    monkeypatch.setattr(reconcile_mod, "reconcile_vitest_summary_log", interrupt)
    try:
        common._maybe_reconcile_vitest_summary(
            log_dir,
            ["npx", "vitest", "run"],
            cwd=tmp_path,
            area="ai-platform",
            subcampaign="npm-test",
            campaign_config=None,
        )
    except SystemExit as exc:
        assert exc.code == 1
    else:
        raise AssertionError("expected reconciliation interruption exit")

    for filename in ("summary.json", "meta.json"):
        payload = json.loads((log_dir / filename).read_text(encoding="utf-8"))
        assert payload["reconciliation_interrupted"] is True
        assert payload["exit_code"] == 1
        assert payload["interrupted"] is False


def test_reconcile_interrupt_marks_success_as_interrupted(
    tmp_path: Path, monkeypatch
) -> None:
    from harness import campaign_vitest_reconcile as reconcile_mod
    from harness import common

    log_dir = tmp_path / "npm-test"
    log_dir.mkdir()
    (log_dir / "summary.json").write_text(json.dumps({"exit_code": 0}))
    monkeypatch.setattr(
        reconcile_mod, "should_reconcile_vitest_campaign", lambda *a, **k: True
    )
    monkeypatch.setattr(
        reconcile_mod,
        "reconcile_vitest_summary_log",
        lambda *a, **k: (_ for _ in ()).throw(KeyboardInterrupt()),
    )

    try:
        common._maybe_reconcile_vitest_summary(
            log_dir,
            ["npx", "vitest", "run"],
            cwd=tmp_path,
            area="ai-platform",
            subcampaign="npm-test",
            campaign_config=None,
        )
    except SystemExit as exc:
        assert exc.code == 130
    else:
        raise AssertionError("expected reconciliation interruption exit")
    payload = json.loads((log_dir / "summary.json").read_text(encoding="utf-8"))
    assert payload["reconciliation_interrupted"] is True
    assert payload["interrupted"] is True
    assert payload["exit_code"] == 130


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


def test_reconcile_marks_missing_outcomes_as_infrastructure_errors(tmp_path: Path) -> None:
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
        assert payload["failed"] == 0
        assert payload["tests"][0]["status"] == "NOT_RECORDED"
        assert payload["tests"][0]["skipped"] is False
        assert payload["tests"][0]["failure_kind"] == "infrastructure_error"
        assert payload["campaign_infrastructure_error"] is True
        assert payload["exit_code"] == 1
        assert payload["runner_exit_code"] == 1
        assert "error" not in payload["tests"][0]
        assert not any(n.startswith("stdout |") for n in names)
        recorded = recorded_test_names_from_summary(
            log_dir,
            area="ai-platform",
            subcampaign="npm-test",
        )
        assert missing not in recorded
    finally:
        mod.vitest_labels_for_subcampaign = original


def test_reconcile_marks_missing_outcomes_unrun_without_runner_cause(
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
    assert payload["tests"][0]["status"] == "NOT_RECORDED"
    assert payload["tests"][0]["skipped"] is False
    assert payload["tests"][0]["failure_kind"] == "infrastructure_error"
    assert "error" not in payload["tests"][0]
    assert payload["not_recorded"] == [missing]
    assert payload["diagnostics_file"] == "output.log"
    assert any("sqlite-shm" in line for line in payload["runner_diagnostics"])


def test_reconcile_preserves_intentional_skip_rows(tmp_path: Path) -> None:
    log_dir = tmp_path / "npm-test"
    log_dir.mkdir()
    skipped = "test/foo.test.ts > suite > deliberately skipped"
    missing = "test/foo.test.ts > suite > missing outcome"
    (log_dir / "summary.json").write_text(json.dumps({"tests": [{
        "name": skipped, "status": "SKIP", "skipped": True,
        "log_file": None, "started_at": None, "finished_at": None,
    }]}), encoding="utf-8")

    from harness import campaign_vitest_reconcile as mod

    original = mod.vitest_labels_for_subcampaign
    mod.vitest_labels_for_subcampaign = lambda area, sub: {skipped, missing}
    try:
        assert reconcile_vitest_summary_log(
            log_dir, area="ai-platform", subcampaign="npm-test", cwd=tmp_path,
        )
    finally:
        mod.vitest_labels_for_subcampaign = original

    payload = json.loads((log_dir / "summary.json").read_text(encoding="utf-8"))
    by_name = {row["name"]: row for row in payload["tests"]}
    assert by_name[skipped]["status"] == "SKIP"
    assert by_name[skipped]["skipped"] is True
    assert by_name[missing]["status"] == "NOT_RECORDED"
    assert payload["not_recorded"] == [missing]


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
