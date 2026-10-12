"""Parent/child relationships between subcampaigns for --list tree display."""

from __future__ import annotations

# child -> parent (None = top-level row in the tree).
SUBCAMPAIGN_PARENT: dict[str, dict[str, str | None]] = {
    "frontend": {
        "all": None,
        "unit": "all",
        "boundary": "all",
        "boundary-auth": "boundary",
        "boundary-settings": "boundary",
        "boundary-patients": "boundary",
        "boundary-appointments": "boundary",
        "boundary-postgrest": "boundary",
        "fullstack": None,
    },
    "backend": {
        "all": None,
        "auth-rbac": "all",
        "org-branch": "all",
        "patients": "all",
        "appointments": "all",
        "visit-medical": "all",
        "billing": "all",
        "service-catalog": "all",
        "shift": "all",
        "ai-platform-trust": "all",
        "safety": "all",
        "membership": "all",
        "cross-tenant": "all",
        "p51-issuer": "all",
        "catalog": None,
    },
    "ai-platform": {
        "npm-test": None,
        "manifests": "npm-test",
        "unit": "npm-test",
        "workers": "npm-test",
        "load": None,
        "e2e": None,
        "eval": None,
        "eval-all": None,
        "version-matrix": None,
        "version-matrix-channels": "version-matrix",
        "version-matrix-do": "version-matrix",
    },
    "abo": {
        "cross-worker": None,
        "cross-worker-main": "cross-worker",
        "platform-throw": "cross-worker",
        "system": None,
        "import-boundary": None,
        "version-matrix": None,
    },
    "e2e-fullstack": {
        "all-manual": None,
        "p5-1": "all-manual",
        "p5-2": "all-manual",
        "p5-2b": "all-manual",
        "p7-2": "all-manual",
        "p7-3": "all-manual",
        "all-ci": None,
    },
    "vendor-contracts": {
        "all": None,
        "node": "all",
        "workers": "all",
    },
    "ops-launch": {
        "launch-check": None,
    },
}


def _parent_map(area: str) -> dict[str, str | None]:
    return SUBCAMPAIGN_PARENT.get(area, {})


def _roots(area: str, ids: set[str]) -> list[str]:
    parents = _parent_map(area)
    roots: list[str] = []
    for sub_id in ids:
        if sub_id not in parents:
            roots.append(sub_id)
            continue
        parent = parents[sub_id]
        if parent is None:
            roots.append(sub_id)
        elif parent not in ids:
            roots.append(sub_id)
    return sorted(set(roots))


def _children(area: str, parent: str, ids: set[str]) -> list[str]:
    parents = _parent_map(area)
    return sorted(child for child, p in parents.items() if p == parent and child in ids)


def _format_branch(
    name: str,
    verticals: list[bool],
    is_last_sibling: bool,
) -> str:
    if not verticals:
        return name
    line = ""
    for continues in verticals[:-1]:
        line += "│  " if continues else "   "
    line += "└─ " if is_last_sibling else "├─ "
    return line + name


def _walk(
    area: str,
    node: str,
    ids: set[str],
    verticals: list[bool],
    is_last_sibling: bool,
    out: list[tuple[str, str]],
) -> None:
    label = _format_branch(node, verticals, is_last_sibling)
    out.append((node, label))
    children = _children(area, node, ids)
    for index, child in enumerate(children):
        _walk(
            area,
            child,
            ids,
            verticals + [not is_last_sibling],
            index == len(children) - 1,
            out,
        )


def root_subcampaign_ids(area: str, subcampaign_ids: list[str]) -> list[str]:
    """Top-level tree nodes only (excludes indented children)."""
    return _roots(area, set(subcampaign_ids))


def tree_ordered_labels(area: str, subcampaign_ids: list[str]) -> list[tuple[str, str]]:
    """Return (subcampaign_id, display_label) in tree order."""
    ids = set(subcampaign_ids)
    roots = _roots(area, ids)
    ordered: list[tuple[str, str]] = []
    for index, root in enumerate(roots):
        _walk(area, root, ids, [], index == len(roots) - 1, ordered)

    seen = {sub_id for sub_id, _ in ordered}
    for sub_id in sorted(ids - seen):
        ordered.append((sub_id, sub_id))
    return ordered
