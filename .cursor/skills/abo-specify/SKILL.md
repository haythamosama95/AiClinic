---
name: abo-specify
description: Specify an ABO delivery slice (M1, N2, Q3, …) by transcribing the ABO architecture and delivery plan into the Spec Kit spec template. Use when the user names a slice id and asks to specify it or run abo-specify.
disable-model-invocation: true
---

# ABO — Specify a Slice

You are **transcribing an already-decided architecture** into a feature spec. You are not designing.
Every requirement must be traceable to a cited section. If it cannot be traced, you stop.

**Input:** the slice id (`M1`, `N2`, `Q3`, …). If the user did not give one, ask for it and do
nothing else.

## User Input

```text
$ARGUMENTS
```

The first argument should be the slice id. If empty, ask for it and stop.

## Subagent models

When `/abo-workflow` runs this stage, the stage owner is **Grok 4.7 High** (`model: "grok-4.7-high"`).
If this phase outputs `## ESCALATION`, the workflow assigns **Kimi K3 High** (`model: "kimi-k3-high"`)
to resolve — do not partially specify past an escalation.

## Branch and feature directory

Before anything else, take the next feature number from Spec Kit rather than picking one, then branch
from `ai/master` with the `ai/` prefix.

`create-new-feature.sh` cannot be used to create the branch — it hardcodes `<NNN>-<name>` with no
prefix hook. Use it in `--dry-run` mode purely to allocate the number:

```bash
.specify/scripts/bash/create-new-feature.sh --dry-run --json \
  --short-name '<short-name>' '<slice name from the delivery plan>'
```

Read `FEATURE_NUM` from the JSON. Then:

```bash
git fetch origin ai/master
git checkout ai/master
git checkout -b ai/<FEATURE_NUM>-<slice-id-lowercase>-<short-name>
mkdir -p specs/<FEATURE_NUM>-<short-name>
cp .specify/templates/spec-template.md specs/<FEATURE_NUM>-<short-name>/spec.md
```

Confirm the wiring before writing anything:

```bash
.specify/scripts/bash/abo-paths.sh --json --paths-only
```

Branch and directory need not have identical slugs — Spec Kit matches on the numeric prefix — but the
prefix must be the same and exactly one `specs/<FEATURE_NUM>-*` directory may exist.

## Relationship to Spec Kit

This is the ABO variant of Spec Kit's `/speckit-specify`. The feature description is a row of
`docs/architecture/ai-billing-orchestration/04-abo-delivery-plan.md` (§3), not user prose. Phase
order for **slice work** is:

`/abo-specify` → `/abo-clarify` → `/abo-plan` → `/abo-tasks` → `/abo-implement` → (after the band's
slices are implemented) `/abo-verify` for the band verification matrix.

The band verification tables (§3.2.1–§3.10.1) are **not** Spec Kit features — they are implemented
directly by `/abo-verify`.

## Sources — read exactly these

1. `docs/architecture/ai-billing-orchestration/04-abo-delivery-plan.md` — whole file.
2. ABO architecture — **only** the sections named in the slice's `Canonical` cell: read the
   matching parts under `docs/architecture/ai-billing-orchestration/architecture/` (hub:
   `architecture/00-index.md`). When the `Canonical` cell cites AP-ARCH amendments (A15/A16/A17),
   read **only** those sections in `docs/architecture/ai-platform/01-ai-platform.md`.
3. `.specify/templates/spec-template.md` and `.specify/memory/constitution.md`.

Do not read other architecture sections. Needing one is a stop condition.

## Scope

Find the slice's row in §3 of the delivery plan. Its `Slice`, `Canonical`, `Needs`, and `Done when`
cells are the entire scope. The slice's row in §3.12 is the **slice test floor** for Spec Kit. The
band's verification subsection (§3.2.1–§3.10.1 for that band) is the expanded matrix — referenced in
the spec for traceability but implemented only via `/abo-verify`, not as extra user stories or tasks.

## Output — the Spec Kit template, filled this way

| Template section | Fill with |
| --- | --- |
| Header block | `**Input**` is the slice id and its `Slice` cell |
| **`## Slice Contract`** *(added)* | **Implements** — `Canonical` verbatim; **Freezes** — contracts this slice establishes; **Consumes** — frozen by `Needs` slices; **Open decisions relied on** — §3.13.3 items this slice must pin, if any |
| `## User Scenarios & Testing` | **Exactly one** user story (P1 only). "Independent Test" = `Done when`. Acceptance scenarios = Given/When/Then for each bullet in the slice's §3.12 row. `### Test plan` lists **only** the §3.12 floor cases for this slice (by id), with layer. Add `### Band verification (out of Spec Kit)` — one bullet pointing at the band's §3.x.1 table and `/abo-verify` |
| `### Edge Cases` | Real edge cases: every error code, boundary, failure branch this slice can emit |
| `## Requirements` | `FR-###`, each restating a cited sentence with section reference |
| `### Key Entities` | D1 / Supabase / contract types this slice defines, or "Not applicable" |
| `## Constitution Alignment` | Name every codebase touched: `ai-platform/`, `ai-billing-orchestrator/`, `backend/`, `frontend/` |
| **`## Out of Scope`** *(added)* | Neighbouring slices, band verification rows (handled by `/abo-verify`), plus §5 prohibitions |
| `## Success Criteria` | `SC-###` from `Done when`, measurable |
| `## Assumptions` | As the template intends |

## Overrides

- One slice = one user story (P1 only).
- Drop MVP/deploy/demo language (DP-L2 operating assumptions, AP plan §1.2 adopted).
- Tests are never optional.
- Non-user-facing slices still get one story from operator, reviewer, or calling-component perspective.

## Prohibitions — copy into Out of Scope

Delivery plan §5 (AP §6.4 adopted) plus ABO-specific §5.3 items:

- No shared bearer or standing unattributed credential (§8.1, §11.2).
- No plan/price/entitlement-mirror/usage table in the ABO (§4.1.6).
- No provider identifier across the adapter boundary (§7.1).
- No order state or provider data in clinic Postgres (§9.5).
- Plus AP gateway prohibitions when the slice touches `ai-platform/` (R-12, R-20, §7.5, etc.).

## Stop conditions

Delivery plan §5.2 / §6.3 (via AP adoption). Output **only** `## ESCALATION` when:

1. A requirement is untraceable.
2. The slice would change something in **Consumes**.
3. A §3.12 floor case cannot be expressed as a test.
4. The slice likely exceeds ~25 tasks or spans unrelated deployables without delivery-plan intent.

```markdown
## ESCALATION

**Stop condition:** 1 — untraceable requirement
**Slice:** O2
**Question:** …
**Should be answered by:** ABO architecture §… or AP-ARCH A16 §…
**Blocked until:** the architecture document is amended
```
