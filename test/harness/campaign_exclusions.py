"""User-managed campaign exclusions shared by the root and child runners.

Configure ``test/campaign-exclusions.json`` with campaign area ids, ``area/subcampaign``
ids, and per-subcampaign test labels. Test labels are the names shown in campaign
reports (for example the full Vitest test name).
"""

from __future__ import annotations

import json
from functools import lru_cache
from pathlib import Path
from typing import Any

from harness.common import REPO_ROOT

EXCLUSIONS_FILE = REPO_ROOT / "test" / "campaign-exclusions.json"


@lru_cache(maxsize=1)
def _load() -> dict[str, Any]:
    if not EXCLUSIONS_FILE.is_file():
        return {}
    try:
        payload = json.loads(EXCLUSIONS_FILE.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise ValueError(
            f"invalid campaign exclusions file {EXCLUSIONS_FILE}: {exc}"
        ) from exc
    if not isinstance(payload, dict):
        raise ValueError(
            f"campaign exclusions file must contain a JSON object: {EXCLUSIONS_FILE}"
        )
    return payload


def reload_exclusions() -> None:
    """Clear cached settings (useful when a runner is embedded in another process)."""
    _load.cache_clear()


def excluded_campaigns() -> set[str]:
    values = _load().get("campaigns", [])
    return (
        {value for value in values if isinstance(value, str)}
        if isinstance(values, list)
        else set()
    )


def excluded_subcampaigns() -> set[tuple[str, str]]:
    values = _load().get("subcampaigns", [])
    result: set[tuple[str, str]] = set()
    if isinstance(values, list):
        for value in values:
            if not isinstance(value, str) or "/" not in value:
                continue
            area, subcampaign = value.split("/", 1)
            if area and subcampaign:
                result.add((area, subcampaign))
    return result


def excluded_test_cases(area: str, subcampaign: str) -> set[str]:
    values = _load().get("test_cases", {})
    if not isinstance(values, dict):
        return set()
    names = values.get(f"{area}/{subcampaign}", [])
    return (
        {name for name in names if isinstance(name, str) and name}
        if isinstance(names, list)
        else set()
    )


def campaign_is_excluded(area: str) -> bool:
    return area in excluded_campaigns()


def subcampaign_is_excluded(area: str, subcampaign: str) -> bool:
    return campaign_is_excluded(area) or (area, subcampaign) in excluded_subcampaigns()
