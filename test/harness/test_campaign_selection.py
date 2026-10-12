"""Tests for shared campaign selection toggles."""

from __future__ import annotations

from harness.campaign_selection import (
    minimal_run_picks,
    sub_ids,
    toggle_area,
    toggle_subtree,
)


def test_toggle_area_selects_all_subcampaigns() -> None:
    area_subs = {"backend": ["all", "patients", "billing"]}
    selected: set[tuple[str, str]] = set()
    toggle_area("backend", selected, area_subs)
    assert selected == {
        ("backend", "all"),
        ("backend", "patients"),
        ("backend", "billing"),
    }
    toggle_area("backend", selected, area_subs)
    assert selected == set()


def test_toggle_subtree_only_affects_branch() -> None:
    area_subs = {
        "frontend": ["all", "unit", "boundary", "boundary-auth"],
    }
    selected: set[tuple[str, str]] = set()
    toggle_subtree("frontend", "boundary", selected, area_subs)
    assert ("frontend", "boundary") in selected
    assert ("frontend", "boundary-auth") in selected
    assert ("frontend", "unit") not in selected
    assert sub_ids("frontend", area_subs) == {"all", "unit", "boundary", "boundary-auth"}


def test_minimal_run_picks_drops_children_when_parent_selected() -> None:
    picked = [
        ("ai-platform", "npm-test"),
        ("ai-platform", "manifests"),
        ("ai-platform", "unit"),
        ("ai-platform", "workers"),
    ]
    assert minimal_run_picks(picked) == [("ai-platform", "npm-test")]


def test_minimal_run_picks_keeps_sibling_leaves() -> None:
    picked = [("ai-platform", "unit"), ("ai-platform", "workers")]
    assert minimal_run_picks(picked) == picked
