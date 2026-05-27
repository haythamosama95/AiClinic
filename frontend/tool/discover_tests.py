#!/usr/bin/env python3
"""Fast filesystem discovery of Flutter test files (find + regex; no flutter glob)."""

from __future__ import annotations

import re
import subprocess
from pathlib import Path

_TEST_DECL = re.compile(r"^\s*(test|testWidgets)\s*\(", re.MULTILINE)
_FOR_ENUM_VALUES = re.compile(
    r"\bfor\s*\([^)]*\bin\s+([A-Za-z_]\w*)\.values\s*\)\s*\{",
    re.MULTILINE,
)
_ENUM_DECL = re.compile(r"enum\s+(\w+)\s*\{([^}]*)\}", re.DOTALL)
_ENUM_LENGTH_CACHE: dict[str, int] = {
    "StaffRole": 5,
    "StaffListFilter": 3,
    "PatientGender": 5,
    "PatientMaritalStatus": 4,
    "BranchFormFieldsMode": 3,
    "PatientListScope": 2,
}

UNIT_TEST_ROOTS = ("test/unit", "test/widget", "test/integration")

BOUNDARY_DEFAULT_ROOT = "test/boundary"

BOUNDARY_SUBSET_ROOTS: dict[str, tuple[str, ...]] = {
    "auth": ("test/boundary/auth",),
    "settings": ("test/boundary/settings",),
    "patients": ("test/boundary/patients",),
    "postgrest": ("test/boundary/postgrest_reads_boundary_test.dart",),
}


def discover_test_files(cwd: Path, *roots: str) -> list[str]:
    """Return sorted repo-relative paths to *_test.dart under roots (~milliseconds)."""
    if not roots:
        return []

    found: set[str] = set()
    for root in roots:
        path = cwd / root
        if path.is_file():
            if path.name.endswith("_test.dart"):
                found.add(root)
            continue
        if not path.is_dir():
            continue

        result = subprocess.run(
            ["find", root, "-name", "*_test.dart", "-type", "f"],
            capture_output=True,
            text=True,
            cwd=cwd,
            check=False,
        )
        if result.returncode != 0:
            continue
        for line in result.stdout.splitlines():
            line = line.strip()
            if line:
                found.add(line)

    return sorted(found)


def count_test_declarations(cwd: Path, relative_paths: list[str]) -> int:
    """Count test / testWidgets lines (static; ignores loop expansion)."""
    total = 0
    for rel in relative_paths:
        total += len(_TEST_DECL.findall((cwd / rel).read_text(encoding="utf-8")))
    return total


def _matching_brace_end(text: str, open_index: int) -> int:
    depth = 0
    for i in range(open_index, len(text)):
        ch = text[i]
        if ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0:
                return i
    return len(text) - 1


def _enum_value_count(enum_name: str, cwd: Path) -> int:
    if enum_name in _ENUM_LENGTH_CACHE:
        return _ENUM_LENGTH_CACHE[enum_name]

    lib_root = cwd / "lib"
    enum_pattern = re.compile(
        rf"enum\s+{re.escape(enum_name)}\s*\{{([^}}]*)\}}",
        re.DOTALL,
    )
    if lib_root.is_dir():
        for dart_file in lib_root.rglob("*.dart"):
            match = enum_pattern.search(dart_file.read_text(encoding="utf-8"))
            if match:
                body = match.group(1)
                members = re.findall(
                    r"^\s*([A-Za-z_]\w*)\s*(?:,|;)", body, re.MULTILINE
                )
                if members:
                    _ENUM_LENGTH_CACHE[enum_name] = len(members)
                    return len(members)

    return 1


def _count_expected_tests_in_source(source: str, cwd: Path) -> int:
    """Expand `for (x in Enum.values)` loops that register tests at runtime."""
    loops: list[tuple[int, int, str, str]] = []
    for match in _FOR_ENUM_VALUES.finditer(source):
        enum_name = match.group(1)
        brace_start = match.end() - 1
        brace_end = _matching_brace_end(source, brace_start)
        body = source[brace_start + 1 : brace_end]
        loops.append((match.start(), brace_end + 1, enum_name, body))

    if not loops:
        return len(_TEST_DECL.findall(source))

    covered: list[tuple[int, int]] = [(start, end) for start, end, _, _ in loops]

    def inside_loop(index: int) -> bool:
        return any(start <= index < end for start, end in covered)

    outside = sum(1 for m in _TEST_DECL.finditer(source) if not inside_loop(m.start()))
    expanded = 0
    for _, _, enum_name, body in loops:
        inner = _count_expected_tests_in_source(body, cwd)
        if inner > 0:
            enum_len = _enum_value_count(enum_name, cwd)
            expanded += inner * enum_len

    return outside + expanded


def count_expected_tests(cwd: Path, relative_paths: list[str]) -> int:
    """Fast static count matching flutter test runner (includes dynamic loop tests)."""
    total = 0
    for rel in relative_paths:
        total += _count_expected_tests_in_source(
            (cwd / rel).read_text(encoding="utf-8"),
            cwd,
        )
    return total


def unit_test_files(cwd: Path) -> list[str]:
    return discover_test_files(cwd, *UNIT_TEST_ROOTS)


def boundary_test_files(cwd: Path, subset: str | None) -> list[str]:
    if subset:
        roots = BOUNDARY_SUBSET_ROOTS.get(subset)
        if roots is None:
            raise ValueError(f"unknown boundary subset: {subset}")
        return discover_test_files(cwd, *roots)
    return discover_test_files(cwd, BOUNDARY_DEFAULT_ROOT)
