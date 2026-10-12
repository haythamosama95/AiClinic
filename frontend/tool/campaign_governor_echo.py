"""Forward Flutter machine output to the root test campaign governor."""

from __future__ import annotations

import os
import sys


def governor_live_progress() -> bool:
    return os.environ.get("AICLINIC_LIVE_PROGRESS") == "1"


def echo_stdout_line(line: str) -> None:
    """Mirror Flutter machine JSON(L) to stdout for ``test/run_campaigns.py`` parsers."""
    if not governor_live_progress():
        return
    stripped = line.strip()
    if not stripped or not (stripped.startswith("{") or stripped.startswith("[")):
        return
    sys.stdout.write(line if line.endswith("\n") else f"{line}\n")
    sys.stdout.flush()
