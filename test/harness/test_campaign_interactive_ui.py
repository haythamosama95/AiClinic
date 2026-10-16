"""CI vs local campaign UI mode."""

from __future__ import annotations

import os

from harness.common import campaign_interactive_ui_enabled


def test_interactive_ui_off_when_ci(monkeypatch) -> None:
    monkeypatch.delenv("AICLINIC_PLAIN_CAMPAIGN_LOG", raising=False)
    monkeypatch.setenv("CI", "true")
    monkeypatch.delenv("GITHUB_ACTIONS", raising=False)
    assert campaign_interactive_ui_enabled() is False


def test_plain_campaign_log_env(monkeypatch) -> None:
    monkeypatch.delenv("CI", raising=False)
    monkeypatch.delenv("GITHUB_ACTIONS", raising=False)
    monkeypatch.setenv("AICLINIC_PLAIN_CAMPAIGN_LOG", "1")
    assert campaign_interactive_ui_enabled() is False
