"""Pytest path setup for runner tests."""

from __future__ import annotations

import sys
from pathlib import Path

import pytest

_RUNNERS_ROOT = Path(__file__).resolve().parents[1]
_AI_ROOT = _RUNNERS_ROOT.parent
_AI_COMMON_SRC = _AI_ROOT / "common" / "src"

for path in (_AI_COMMON_SRC, _AI_ROOT):
    path_str = str(path)
    if path_str not in sys.path:
        sys.path.insert(0, path_str)


@pytest.fixture(autouse=True)
def _reset_verbose_level_cache() -> None:
    from ai_common.verbose_logging import _reset_for_tests

    _reset_for_tests()
    yield
    _reset_for_tests()
