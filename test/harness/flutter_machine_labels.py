"""Display names for Flutter ``flutter test --machine`` events."""

from __future__ import annotations

from pathlib import Path
from urllib.parse import unquote, urlparse


def _filename_from_url(url: str | None) -> str | None:
    if not url:
        return None
    parsed = urlparse(url)
    if parsed.scheme != "file":
        return None
    path = unquote(parsed.path)
    if path.startswith("/") and len(path) > 2 and path[2] == ":":
        path = path[1:]
    return Path(path).name or None


def is_loading_pseudo_test(test: dict) -> bool:
    name = (test.get("name") or "").strip()
    lowered = name.lower()
    return lowered.startswith("loading ") or lowered.startswith("compiling ")


def is_flutter_hook_pseudo_test(test: dict) -> bool:
    """setUp/tearDown hooks are not user-facing test cases."""
    name = (test.get("name") or "").strip()
    if not name.startswith("(") or not name.endswith(")"):
        return False
    inner = name[1:-1]
    return inner in ("setUpAll", "tearDownAll", "setUp", "tearDown")


def flutter_test_label(test: dict) -> str | None:
    """
    Human-readable test label, or ``None`` to ignore (e.g. suite file load).
    Prefer the test ``name``; never show a full filesystem path in the UI.
    """
    if is_loading_pseudo_test(test) or is_flutter_hook_pseudo_test(test):
        return None

    name = (test.get("name") or "").strip()
    if name:
        if "/" in name or "\\" in name:
            return Path(name).name
        return name

    filename = _filename_from_url(test.get("url"))
    if filename:
        return filename

    return None


def flutter_pseudo_test_failure_label(test: dict, suite_path: str | None) -> str:
    """Label for a failed loading/hook pseudo-test, e.g. ``foo_test.dart (setUpAll)``."""
    name = (test.get("name") or "").strip()
    if is_loading_pseudo_test(test):
        loaded = name.split(" ", 1)[1] if " " in name else name
        return f"{Path(loaded).name} (loading)"
    suite_file = Path(suite_path).name if suite_path else _filename_from_url(test.get("url"))
    if suite_file:
        return f"{suite_file} {name}".strip()
    return name or "flutter hook"
