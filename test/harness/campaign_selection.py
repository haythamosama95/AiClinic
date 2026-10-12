"""Shared multi-select logic for area / subcampaign trees (TUI + GUI)."""

from __future__ import annotations

from harness.campaign_tree import SUBCAMPAIGN_PARENT, _children


def sub_ids(area: str, area_subcampaigns: dict[str, list[str]]) -> set[str]:
    return set(area_subcampaigns.get(area, []))


def subtree(area: str, node: str, ids: set[str]) -> list[str]:
    out = [node]
    for child in _children(area, node, ids):
        out.extend(subtree(area, child, ids))
    return out


def toggle_subtree(
    area: str,
    sub_id: str,
    selected: set[tuple[str, str]],
    area_subcampaigns: dict[str, list[str]],
) -> None:
    ids = sub_ids(area, area_subcampaigns)
    targets = subtree(area, sub_id, ids)
    from harness.curses_campaign_ui import selection_state

    state = selection_state(selected, area, targets)
    if state == "all":
        for sid in targets:
            selected.discard((area, sid))
    else:
        for sid in targets:
            selected.add((area, sid))


def has_picked_ancestor(
    area: str,
    sub_id: str,
    picked: set[tuple[str, str]],
) -> bool:
    """True when a selected parent subcampaign makes this pick redundant to run."""
    parents = SUBCAMPAIGN_PARENT.get(area, {})
    current = sub_id
    while current in parents:
        parent = parents[current]
        if parent is None:
            break
        if (area, parent) in picked:
            return True
        current = parent
    return False


def minimal_run_picks(
    picked: list[tuple[str, str]],
) -> list[tuple[str, str]]:
    """Drop descendants when an ancestor is also selected (one rollup run covers them)."""
    picked_set = set(picked)
    return [
        (area, sub_id)
        for area, sub_id in picked
        if not has_picked_ancestor(area, sub_id, picked_set)
    ]


def toggle_area(
    area: str,
    selected: set[tuple[str, str]],
    area_subcampaigns: dict[str, list[str]],
) -> None:
    from harness.curses_campaign_ui import selection_state

    targets = sorted(sub_ids(area, area_subcampaigns))
    state = selection_state(selected, area, targets)
    if state == "all":
        for sid in targets:
            selected.discard((area, sid))
    else:
        for sid in targets:
            selected.add((area, sid))
