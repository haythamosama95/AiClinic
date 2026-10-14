"""Tests for the AI Platform campaign runner's multi-step behavior."""

from pathlib import Path
import sys


sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "ai-platform"))
import run_campaigns  # noqa: E402


def test_npm_test_runs_all_phases_after_failure_and_preserves_failure_status(
    monkeypatch, tmp_path: Path
) -> None:
    captured: dict[str, object] = {}

    monkeypatch.setattr(run_campaigns, "load_campaign_config", lambda *_: {})
    monkeypatch.setattr(run_campaigns, "_log_dir", lambda *_: tmp_path)
    monkeypatch.setattr(run_campaigns, "_merge_step_reports", lambda *_: None)

    def run_sequence(steps, *_args, **kwargs):
        captured["steps"] = steps
        captured.update(kwargs)
        # Model verify-manifests failing while later phases still execute.
        executed = []
        exit_codes = {"verify-manifests": 1, "unit": 0, "workers": 0}
        for name, _command in steps:
            executed.append(name)
        captured["executed"] = executed
        return max(exit_codes[name] for name in executed)

    monkeypatch.setattr(run_campaigns, "run_subprocess_sequence", run_sequence)

    result = run_campaigns.run_npm_test("")

    steps = captured["steps"]
    assert [name for name, _ in steps] == ["verify-manifests", "unit", "workers"]
    assert captured["executed"] == ["verify-manifests", "unit", "workers"]
    assert captured["continue_on_step_failure"] is True
    assert result == 1
