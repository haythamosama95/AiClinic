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
