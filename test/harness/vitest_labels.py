"""Shared Vitest test-case label normalization (list / reporter / resume)."""

from __future__ import annotations

import re

_VITEST_DURATION_MS = re.compile(r"(\d+(?:\.\d+)?)\s*ms")


def normalize_vitest_case_label(raw: str) -> str:
    name = raw.strip()
    pool_wrapped = re.match(r"^\[[^\]]+\]\s*\[(.+)\]\s*$", name)
    if pool_wrapped:
        name = pool_wrapped.group(1)
    elif name.startswith("[") and name.endswith("]"):
        name = name[1:-1].strip()
    name = re.sub(r"\s+\d+ms\]?$", "", name).rstrip("]")
    return name.strip()


def vitest_exclude_label_set(names: set[str] | None) -> set[str]:
    """Match reporter labels against resume exclude lists (raw + normalized)."""
    out: set[str] = set()
    for raw in names or ():
        if not raw:
            continue
        out.add(raw)
        out.add(normalize_vitest_case_label(raw))
    return out


def vitest_list_line_label(line: str) -> str | None:
    stripped = line.strip()
    if not stripped or " > " not in stripped:
        return None
    if stripped.startswith("WARN"):
        return None
    return normalize_vitest_case_label(stripped)
