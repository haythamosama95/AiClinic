"""Human-readable names and descriptions for test campaign listings."""

from __future__ import annotations

import textwrap
from dataclasses import dataclass

from harness.campaign_counts import (
    area_root_tests_total,
    catalog_list_test_count,
    format_test_count,
    test_count,
)
from harness.campaign_tree import tree_ordered_labels

MAX_COLUMN_WIDTH = 80
_HEADING_RULE_WIDTH = 78


@dataclass(frozen=True)
class AreaCatalog:
    """One top-level test area (directory campaign)."""

    title: str
    description: str
    subcampaigns: dict[str, str]


# Keys must match area ids in test/run_campaigns.py AREA_SCRIPTS and each runner's AREA.
CATALOG: dict[str, AreaCatalog] = {
    "frontend": AreaCatalog(
        title="frontend",
        description=(
            "Automated checks for the Flutter desktop app: isolated tests that mock "
            "dependencies, and live checks that talk to a local Supabase instance."
        ),
        subcampaigns={
            "unit": (
                "Fast tests for widgets, business logic, and integration flows that do not "
                "require the full billing stack."
            ),
            "unit-1": "First balanced shard of frontend unit, widget, and isolated integration tests.",
            "unit-2": "Second balanced shard of frontend unit, widget, and isolated integration tests.",
            "unit-3": "Third balanced shard of frontend unit, widget, and isolated integration tests.",
            "unit-4": "Fourth balanced shard of frontend unit, widget, and isolated integration tests.",
            "fullstack": (
                "End-to-end UI flows that call a running billing worker and platform worker "
                "on the machine, plus local database state those flows expect."
            ),
            "boundary": (
                "All live Supabase integration tests: repositories, auth, and reads against "
                "a real local database."
            ),
            "boundary-auth": "Live tests for sign-in, sessions, permissions, and provisioning.",
            "boundary-settings": "Live tests for organisation, branches, staff, and role settings.",
            "boundary-patients": "Live tests for patient records, MRN rules, and isolation.",
            "boundary-appointments": "Live tests for appointment booking and calendars.",
            "boundary-postgrest": "Live tests for PostgREST-shaped read paths at the API boundary.",
            "all": "Runs isolated tests first, then the full live Supabase suite in one run.",
        },
    ),
    "backend": AreaCatalog(
        title="backend",
        description=(
            "Database and API contract checks against a local Supabase Postgres instance: "
            "SQL scenarios, small shell smoke flows, and one Node contract check."
        ),
        subcampaigns={
            "all": (
                "Every backend suite in order: authentication, org structure, clinical and "
                "billing data, AI trust tables, safety guards, tenancy, and issuer contracts."
            ),
            "auth-rbac": (
                "Password sign-in smoke, JWT claim shape, bootstrap and staff RPCs, row-level "
                "security for auth, and creating a staff user then signing in as them."
            ),
            "org-branch": (
                "Creating and editing organisations and branches, role matrices, staff username "
                "changes, and staff deletion."
            ),
            "patients": (
                "Patient CRUD, medical record numbers, transfers, search, role visibility, and "
                "concurrent updates."
            ),
            "appointments": (
                "Booking, slots, calendars, queues, patient filters, and appointment row-level "
                "security."
            ),
            "visit-medical": (
                "Visit documentation, attachments, encounter workspace, vitals backfill, and "
                "completion rules."
            ),
            "billing": "Invoices and payments: create, read, row-level rules, and concurrency.",
            "service-catalog": (
                "Clinic services and pricing: catalog CRUD, lists, row-level rules, and "
                "concurrent edits."
            ),
            "shift": "Staff shifts: CRUD, row-level rules, and concurrent updates.",
            "ai-platform-trust": (
                "Keys stored for AI, token issuance and rotation, context for AI calls, and "
                "recording clinician acceptance of AI output."
            ),
            "safety": "Ensures destructive reset helpers cannot run in unsafe environments.",
            "membership": (
                "Active organisation on a membership and claim behaviour when staff switch org."
            ),
            "cross-tenant": (
                "Two organisations on one database: data and RPCs must not leak across tenants."
            ),
            "p51-issuer": (
                "Issuer key RPC behaviour and numeric contract version expectations exposed to "
                "clients."
            ),
            "catalog": (
                "SQL scenarios for AI availability, enrollment, issuer guards, context RPCs, "
                "and recording acceptance in the database."
            ),
        },
    ),
    "ai-platform": AreaCatalog(
        title="ai-platform",
        description=(
            "Tests for the Cloudflare AI gateway worker: plain Node logic, worker runtime "
            "with D1 and durable objects, staged multi-step flows, and prompt quality checks."
        ),
        subcampaigns={
            "unit-1": "First half of the AI Platform unit tests.",
            "unit-2": "Second half of the AI Platform unit tests.",
            "manifests": "Registered prompts and manifests are valid and internally consistent.",
            "unit": "Pure TypeScript behaviour without booting a worker (routing helpers, parsers, taxonomies).",
            "workers": (
                "Worker runtime tests: quotas, entitlements, journals, pipelines, retention, and "
                "similar control-plane behaviour in Miniflare."
            ),
            "npm-test": "Manifest gates, then unit tests, then worker-pool tests in sequence.",
            "load": "Synthetic load and cost accounting under worker limits.",
            "e2e": (
                "Longer staged flows: boot, auth, enrollment, routing, streaming, settlement, "
                "and support lookups as one worker would serve them."
            ),
            "eval": (
                "Fixed golden transcripts, multi-turn conversations, and prohibited-content rules "
                "for model output."
            ),
            "eval-all": "Every prompt evaluation test file in the eval suite.",
            "version-matrix": (
                "Negotiated API versions across channels and durable-object receivers."
            ),
            "version-matrix-channels": "Version negotiation on HTTP channel surfaces only.",
            "version-matrix-do": "Version negotiation when traffic hits a durable object receiver.",
        },
    ),
    "abo": AreaCatalog(
        title="abo",
        description=(
            "Tests for the billing orchestration worker: behaviour inside one worker, and "
            "scenarios that also start a bundled platform worker and payment stub."
        ),
        subcampaigns={
            "system": (
                "In-process worker tests for catalogue, notifications, and scheduled clock "
                "behaviour without leaving the ABO bundle."
            ),
            "cross-worker": (
                "Builds a local platform worker, runs cross-service billing flows, then runs "
                "checkout tests where the platform deliberately returns errors."
            ),
            "cross-worker-main": (
                "Builds a local platform worker and runs cross-service billing flows only."
            ),
            "platform-throw": (
                "Checkout and return-url behaviour when the platform worker signals failure."
            ),
            "import-boundary": (
                "Ensures production code does not import modules outside allowed dependency edges."
            ),
            "version-matrix": (
                "Clinic and console API version checks on the billing worker."
            ),
        },
    ),
    "e2e-fullstack": AreaCatalog(
        title="e2e-fullstack",
        description=(
            "Node-driven scenarios that start local Supabase and Wrangler workers, then "
            "exercise billing, platform, and database behaviour together."
        ),
        subcampaigns={
            "p5-1": (
                "Issuer key custody and installation token issuance through the full local stack."
            ),
            "p5-2": (
                "Coverage feed pull, projection into the database, and administrator status paths."
            ),
            "p5-core": (
                "The CI core pair: issuer key custody followed by coverage feed projection."
            ),
            "p5-2b": (
                "Read-time billing status, notices, and administrator-facing status refresh."
            ),
            "p7-3": (
                "Contract version negotiation across billing worker, platform worker, database "
                "RPCs, and desktop UI gates."
            ),
            "p7-2": (
                "Vendor entrypoint wiring, credential isolation, and untrusted caller rejection."
            ),
            "all-ci": "Compatibility rollup for the P5.1 and P5.2 CI core pair.",
            "all-manual": (
                "Remaining enabled Node scenario files in one run; P5.1 and P5.2 are covered by all-ci."
            ),
        },
    ),
    "vendor-contracts": AreaCatalog(
        title="vendor-contracts",
        description=(
            "Shared cryptographic and billing contract primitives used by multiple workers."
        ),
        subcampaigns={
            "node": "Signatures, grants, tokens, and identifiers under the Node test runner.",
            "workers": "The same checks executed inside the worker test pool.",
            "all": "Node runner first, then worker pool.",
        },
    ),
    "ops-launch": AreaCatalog(
        title="ops-launch",
        description=(
            "Read-only launch readiness script tested against fixture configs; does not "
            "contact production."
        ),
        subcampaigns={
            "launch-check": (
                "Runs the launch checklist script on good and bad fixture JSON and asserts "
                "exit codes and reported failure reasons."
            ),
        },
    ),
}


def _missing_description(area: str, sub_id: str) -> str:
    return "Registered in the runner; description not yet added to the catalog."


def _wrap_cell(text: str, width: int) -> list[str]:
    if width < 1:
        width = 1
    stripped = text.strip()
    if not stripped:
        return [""]
    lines = textwrap.wrap(
        stripped,
        width=width,
        break_long_words=False,
        break_on_hyphens=True,
    )
    return lines if lines else [""]


def _column_widths(headers: list[str], rows: list[list[str]]) -> list[int]:
    widths = [len(h) for h in headers]
    for row in rows:
        for index, cell in enumerate(row):
            widths[index] = max(widths[index], len(cell))
    return [min(MAX_COLUMN_WIDTH, w) for w in widths]


def _row_block(cells: list[str], widths: list[int]) -> list[str]:
    wrapped = [_wrap_cell(cells[i], widths[i]) for i in range(len(cells))]
    height = max(len(part) for part in wrapped)
    block: list[str] = []
    for line_index in range(height):
        parts: list[str] = []
        for col_index, col_lines in enumerate(wrapped):
            segment = col_lines[line_index] if line_index < len(col_lines) else ""
            parts.append(f" {segment.ljust(widths[col_index])} ")
        block.append("|" + "|".join(parts) + "|")
    return block


def _format_table(headers: list[str], rows: list[list[str]]) -> str:
    """ASCII grid table with per-column wrap (max width MAX_COLUMN_WIDTH)."""
    if not rows:
        return ""

    widths = _column_widths(headers, rows)
    sep = "+".join("-" * (w + 2) for w in widths)
    border = f"+{sep}+"

    lines = [border]
    lines.extend(_row_block(headers, widths))
    lines.append(border)
    for row in rows:
        lines.extend(_row_block(row, widths))
    lines.append(border)
    return "\n".join(lines)


def _sorted_area_keys() -> list[str]:
    return sorted(CATALOG.keys())


def _section_number(area: str) -> int | None:
    keys = _sorted_area_keys()
    if area not in keys:
        return None
    return keys.index(area) + 1


def _print_section_heading(
    area: str,
    *,
    section_number: int | None = None,
    test_total: int | None = None,
) -> None:
    entry = CATALOG.get(area)
    title = entry.title if entry else area
    number = section_number if section_number is not None else _section_number(area)
    label = f"{number}. {title}" if number is not None else title
    if test_total is not None:
        label = f"{label} · {test_total} tests"

    print("╭" + "─" * (_HEADING_RULE_WIDTH - 2) + "╮")
    print(f"│ {label:<{_HEADING_RULE_WIDTH - 4}} │")
    print("╰" + "─" * (_HEADING_RULE_WIDTH - 2) + "╯")

    if entry and entry.description:
        print()
        for line in textwrap.wrap(
            entry.description,
            width=_HEADING_RULE_WIDTH,
            break_long_words=False,
            break_on_hyphens=True,
        ):
            print(f"  {line}")
    elif not entry:
        print()
        print("  No catalog entry for this area.")
    print()


def _subcampaign_rows(area: str, subcampaign_ids: list[str]) -> list[list[str]]:
    entry = CATALOG.get(area)
    rows: list[list[str]] = []
    for sub_id, tree_label in tree_ordered_labels(area, subcampaign_ids):
        if entry:
            desc = entry.subcampaigns.get(sub_id, _missing_description(area, sub_id))
        else:
            desc = _missing_description(area, sub_id)
        rows.append(
            [tree_label, format_test_count(catalog_list_test_count(area, sub_id)), desc]
        )
    return rows


def print_area_table(
    area: str,
    subcampaign_ids: list[str] | None = None,
    *,
    show_heading: bool = True,
    section_number: int | None = None,
) -> None:
    """One directory: heading plus a Subcampaign / Description table."""
    from harness.campaign_exclusions import campaign_is_excluded, subcampaign_is_excluded

    if campaign_is_excluded(area):
        return
    entry = CATALOG.get(area)
    catalog_keys = set(entry.subcampaigns.keys()) if entry else set()
    ids = subcampaign_ids if subcampaign_ids else sorted(catalog_keys)
    merged = sorted(
        sub for sub in (catalog_keys | set(ids))
        if not subcampaign_is_excluded(area, sub)
    )
    if not merged:
        return
    rows = _subcampaign_rows(area, merged)
    title_count = area_root_tests_total(area, merged)

    if show_heading:
        _print_section_heading(
            area,
            section_number=section_number,
            test_total=title_count,
        )

    print(_format_table(["Subcampaign", "Tests", "Description"], rows))


def print_full_table(title: str = "AiClinic test campaigns") -> None:
    """One table per directory campaign."""
    from harness.campaign_exclusions import (
        campaign_is_excluded,
        subcampaign_is_excluded,
    )

    print(title)
    print()
    areas = [
        area
        for area in _sorted_area_keys()
        if not campaign_is_excluded(area)
        and any(
            not subcampaign_is_excluded(area, sub)
            for sub in CATALOG[area].subcampaigns
        )
    ]
    for index, area in enumerate(areas):
        if index > 0:
            print()
        print_area_table(area, show_heading=True, section_number=index + 1)


def list_subcampaign_ids(area: str, runner_keys: list[str]) -> None:
    """Table for an area runner, merging catalog with actual runner keys."""
    catalog_keys = set(CATALOG.get(area, AreaCatalog(area, "", {})).subcampaigns.keys())
    merged = sorted(catalog_keys | set(runner_keys))
    print_area_table(area, list(merged))
