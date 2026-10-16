#!/usr/bin/env python3
"""Shim — delegates to frontend/tool/run_campaigns.py."""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

_TARGET = Path(__file__).resolve().parent / "tool" / "run_campaigns.py"

if __name__ == "__main__":
    raise SystemExit(
        subprocess.run([sys.executable, str(_TARGET), *sys.argv[1:]]).returncode
    )
