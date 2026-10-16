"""Vitest command filtering for partial resume."""

from __future__ import annotations

from pathlib import Path
from unittest.mock import MagicMock, patch

from harness.vitest_resume import filter_vitest_run_command, plan_vitest_resume_commands


def test_filter_vitest_returns_none_when_all_excluded(tmp_path: Path) -> None:
    cmd = ["npx", "vitest", "run", "src/foo.test.ts"]
    label_one = "src/foo.test.ts > suite > case one"
    label_two = "src/foo.test.ts > suite > case two"
    stdout = f"{label_one}\n{label_two}\n"
    mock_result = MagicMock(returncode=0, stdout=stdout, stderr="")
    with patch("subprocess.run", return_value=mock_result):
        out = filter_vitest_run_command(
            cmd,
            tmp_path,
            {label_one, label_two},
        )
    assert out is None


def test_filter_vitest_exclude_matches_normalized_summary_name(tmp_path: Path) -> None:
    cmd = ["npx", "vitest", "run"]
    label = "src/foo.test.ts > suite > case one"
    stdout = f"{label}\n"
    mock_result = MagicMock(returncode=0, stdout=stdout, stderr="")
    with patch("subprocess.run", return_value=mock_result):
        out = filter_vitest_run_command(
            cmd,
            tmp_path,
            {f"{label} 42ms]"},
        )
    assert out is None


def test_filter_vitest_keeps_remaining_cases(tmp_path: Path) -> None:
    cmd = ["npx", "vitest", "run"]
    done = "src/foo.test.ts > suite > done"
    pending = "src/foo.test.ts > suite > pending"
    stdout = f"{done}\n{pending}\n"
    mock_result = MagicMock(returncode=0, stdout=stdout, stderr="")
    with patch("subprocess.run", return_value=mock_result):
        out = filter_vitest_run_command(
            cmd,
            tmp_path,
            {done},
        )
    assert out is not None
    assert "-t" in out
    assert out[out.index("-t") + 1] == "pending"
    assert "src/foo.test.ts" in out


def test_plan_chunks_large_remaining_sets(tmp_path: Path) -> None:
    cmd = ["npx", "vitest", "run", "--config", "vitest.workers.config.ts"]
    labels = [
        f"test/w{i}.test.ts > suite > case-{j}"
        for i in range(3)
        for j in range(30)
    ]
    stdout = "\n".join(labels) + "\n"
    mock_result = MagicMock(returncode=0, stdout=stdout, stderr="")
    with patch("subprocess.run", return_value=mock_result) as run_mock:
        plan = plan_vitest_resume_commands(cmd, tmp_path, {labels[0]})
    assert plan is not None
    assert len(plan.commands) > 1
    list_cmd = run_mock.call_args[0][0]
    assert "--config" in list_cmd
    assert "vitest.workers.config.ts" in list_cmd
