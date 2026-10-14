"""Vitest list subprocess lifecycle tests."""

from contextlib import nullcontext
from pathlib import Path
from unittest.mock import Mock

import pytest

from harness import common
from harness import vitest_list_count as mod


def test_list_labels_terminates_and_reaps_child_on_interrupt(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    proc = Mock()
    proc.communicate.side_effect = KeyboardInterrupt
    monkeypatch.setattr(mod.subprocess, "Popen", Mock(return_value=proc))
    monkeypatch.setattr(common, "_monitored_subprocess", lambda _proc: nullcontext())
    terminate = Mock()
    monkeypatch.setattr(common, "_terminate_process", terminate)

    with pytest.raises(KeyboardInterrupt):
        mod.list_vitest_labels(tmp_path, ["test/example.test.ts"])

    terminate.assert_called_once_with(proc)

