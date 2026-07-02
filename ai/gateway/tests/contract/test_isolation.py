"""Isolation-scanning contract tests."""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

GATEWAY_ROOT = Path(__file__).resolve().parents[2]
AI_ROOT = GATEWAY_ROOT.parent
SCAN_SCRIPT = GATEWAY_ROOT / "scripts" / "isolation_scan.py"

sys.path.insert(0, str(GATEWAY_ROOT / "scripts"))
from isolation_scan import scan_ai_tree  # noqa: E402


def test_clean_ai_tree_passes_isolation_scan() -> None:
    violations = scan_ai_tree(AI_ROOT)
    assert violations == []


def test_isolation_scan_script_exits_zero_on_clean_tree() -> None:
    result = subprocess.run(
        [sys.executable, str(SCAN_SCRIPT)],
        cwd=GATEWAY_ROOT,
        capture_output=True,
        text=True,
        check=False,
    )
    assert result.returncode == 0, result.stderr


def test_planted_db_import_is_detected(tmp_path: Path) -> None:
    planted = tmp_path / "planted.py"
    planted.write_text("import psycopg2\n", encoding="utf-8")

    violations = scan_ai_tree(tmp_path)
    assert any("psycopg2" in item for item in violations)


def test_planted_service_role_pattern_is_detected(tmp_path: Path) -> None:
    planted = tmp_path / "secrets.env"
    planted.write_text("SUPABASE_SERVICE_ROLE=super-secret\n", encoding="utf-8")

    violations = scan_ai_tree(tmp_path)
    assert any("SUPABASE_SERVICE_ROLE" in item for item in violations)
