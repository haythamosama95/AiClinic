#!/usr/bin/env python3
"""CI gate: fail if clinic-DB credentials, service-role keys, or DB drivers appear under ai/."""

from __future__ import annotations

import re
import sys
from pathlib import Path

FORBIDDEN_IMPORTS = (
    "psycopg",
    "psycopg2",
    "asyncpg",
    "supabase",
    "sqlalchemy.dialects.postgresql",
    "postgres",
)

FORBIDDEN_PATTERNS: list[tuple[str, re.Pattern[str]]] = [
    ("SUPABASE_SERVICE_ROLE assignment", re.compile(r"SUPABASE_SERVICE_ROLE\s*=")),
    ("DATABASE_URL assignment", re.compile(r"DATABASE_URL\s*=")),
    ("postgres connection string", re.compile(r"postgres(?:ql)?://[^\s\"']+", re.IGNORECASE)),
    (
        "supabase service key assignment",
        re.compile(r"supabase[_-]?service[_-]?role[_-]?key\s*=", re.IGNORECASE),
    ),
]

SKIP_DIRS = {
    ".git",
    ".venv",
    "__pycache__",
    ".pytest_cache",
    ".ruff_cache",
    "node_modules",
    "tests",
}

TEXT_SUFFIXES = {".py", ".yaml", ".yml", ".toml", ".md", ".env", ".txt", ".sh", ".json"}


def find_repo_ai_root(start: Path | None = None) -> Path:
    current = (start or Path(__file__)).resolve()
    for parent in [current, *current.parents]:
        candidate = parent / "ai"
        if candidate.is_dir() and (candidate / "gateway").is_dir():
            return candidate
    raise FileNotFoundError("Could not locate ai/ tree from isolation_scan.py")


def iter_text_files(root: Path) -> list[Path]:
    files: list[Path] = []
    for path in root.rglob("*"):
        if not path.is_file():
            continue
        if any(part in SKIP_DIRS for part in path.parts):
            continue
        if path.suffix.lower() in TEXT_SUFFIXES or path.name.startswith(".env"):
            files.append(path)
    return files


def scan_file(path: Path, ai_root: Path) -> list[str]:
    violations: list[str] = []
    rel = path.relative_to(ai_root)
    try:
        content = path.read_text(encoding="utf-8", errors="replace")
    except OSError as exc:
        return [f"{rel}: unreadable ({exc})"]

    if path.suffix == ".py":
        for forbidden in FORBIDDEN_IMPORTS:
            if re.search(rf"\b(import|from)\s+{re.escape(forbidden)}\b", content):
                violations.append(f"{rel}: forbidden import/reference to '{forbidden}'")

    for label, pattern in FORBIDDEN_PATTERNS:
        if pattern.search(content):
            violations.append(f"{rel}: matched forbidden pattern ({label})")

    return violations


def scan_ai_tree(ai_root: Path | None = None) -> list[str]:
    root = ai_root or find_repo_ai_root()
    violations: list[str] = []
    for path in iter_text_files(root):
        violations.extend(scan_file(path, root))
    return violations


def main() -> int:
    try:
        ai_root = find_repo_ai_root()
    except FileNotFoundError as exc:
        print(f"isolation_scan: {exc}", file=sys.stderr)
        return 2

    violations = scan_ai_tree(ai_root)
    if not violations:
        print(f"isolation_scan: PASS ({ai_root})")
        return 0

    print(f"isolation_scan: FAIL — {len(violations)} violation(s) under {ai_root}", file=sys.stderr)
    for item in violations:
        print(f"  - {item}", file=sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
