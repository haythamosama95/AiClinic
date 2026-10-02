---
name: abo-specify
description: >-
  Specify an ABO delivery unit (P1.1, P4.2, …) by transcribing the design docs
  on ai/abo-master and the unit row in
  docs/architecture/ai-billing-orchestration/06-abo-delivery-plan.md into the
  Spec Kit spec template. Use when the user names a unit id and asks to specify
  it or run abo-specify. Never commit.
disable-model-invocation: true
---

# ABO — Specify a Unit

You are **transcribing an already-decided design** into a feature spec. You are not designing.
Every requirement cites a section of the design docs. If it cannot be traced, you stop.

The leaf is a **unit** (`P1.1`, `P4.2`). One unit is one Spec Kit feature (rule S2).

**Input:** the unit id in `$ARGUMENTS`. If empty, ask and stop. Refuse an `a`/`b` split id.
Splits happen at the tasks phase (rule S3), after the delivery plan is amended.

## Relationship to Spec Kit

Same slot as `/speckit-specify`: `specs/<NNN>-<name>/spec.md` from
`.specify/templates/spec-template.md`, same directory layout, same constitution gate. The feature
text is a unit of `docs/architecture/ai-billing-orchestration/06-abo-delivery-plan.md`. An
untraceable requirement is an `## ESCALATION`, never `[NEEDS CLARIFICATION]`. Phase order:
`/abo-specify` → `/abo-clarify` → `/abo-plan` → `/abo-tasks` → `/abo-implement`.

## Branch and feature directory

Spec numbers are pre-assigned (rule S4). Look the number up in the S4 table (`P1.1` = 061 …
`P8.3` = 098). Do not run `create-new-feature.sh`.

`<short-name>`: the unit title, lowercase kebab-case, drop `a`/`an`/`the`/`and`, at most five
words. Examples: P1.1 → `membership-active-org`; P4.2 → `checkout-paymob-intention`.

- Directory: `specs/<NNN>-abo-p<phase>-<n>-<short-name>/`
- Branch: `ai/<NNN>-abo-p<phase>-<n>-<short-name>`, created from `ai/abo-master`

Scan for stop conditions before creating the branch. A blank directory would occupy the number.
Do not commit, amend, or push. If the working tree is dirty outside `.cursor/skills/`, stop and ask. Leave `.cursor/skills/` untouched.

If `specs/<NNN>-*` already exists: untouched template for this unit → reuse it; filled spec for
this unit → stop; any other feature → stop condition 7.

```bash
git checkout ai/abo-master
git checkout -b ai/<NNN>-abo-p<phase>-<n>-<short-name>
mkdir -p specs/<NNN>-abo-p<phase>-<n>-<short-name>
cp .specify/templates/spec-template.md specs/<NNN>-abo-p<phase>-<n>-<short-name>/spec.md
```

Update only the `<!-- SPECKIT START -->` / `<!-- SPECKIT END -->` block in `AGENTS.md` (rule S4)
to this directory's `plan.md`, `spec.md`, and branch.

`.specify/feature.json` outranks branch lookup. Confirm before filling the spec, and abort unless
it resolves to the new directory and exactly one `specs/<NNN>-*` exists:

```bash
SPECIFY_FEATURE_DIRECTORY="specs/<NNN>-abo-p<phase>-<n>-<short-name>" \
  .specify/scripts/bash/check-prerequisites.sh --json --paths-only
```

## Sources — read exactly these

1. The delivery plan: sections 2 and 3, this unit's section in section 4, its S4 row, section 6
   only for open questions its Read or Implements line names, and from section 5 only the D1 rows
   and D2 cells that name this unit.
2. Design docs in `docs/architecture/ai-billing-orchestration/`, only the **Read** spans.
   `00`–`05` are `00-abo-requirements-seed.md`, `01-abo-design-decisions.md`,
   `02-abo-architecture-and-threat-model.md`, `03-abo-data-model-and-lifecycle.md`,
   `04-abo-contracts.md`, `05-abo-operations-and-traceability.md`. Read the files. Do not use
   `git show`. A bounded Read line ("first paragraph", "row T-1") ends at that span.
3. The **Outputs / freezes** line of each **Depends** unit, and nothing else from those units.
4. `.specify/templates/spec-template.md` and `.specify/memory/constitution.md`.
5. **Code** paths only to name the live entry point (rule S8) and to confirm a consumed contract
   exists. Requirements come from the cited section. Code that differs is the change this unit makes.

A **Do not read** section is a stop, not a lookup. Do not read another unit's Implements or E2E
list, or any architecture document outside this list.

## Output

Keep every mandatory template section. Add `## Unit Contract` after the header and `## Out of Scope`
before Assumptions. Drop the template's MVP, deploy, and demo language: nothing ships before P8
(rule S2), and tests are never optional.

| Section | Fill with |
| --- | --- |
| Header | `**Input**`: unit id and heading title. `**Feature Branch**`: the `ai/<NNN>-…` branch |
| `## Unit Contract` | **Implements** — Read citations, then Implements bullets verbatim. **Freezes** — Outputs / freezes, verbatim. **Consumes** — each Depends unit's Outputs / freezes line; Depends `—` → `None.` Changing one is out of scope (rule S7). **Open questions relied on** — section 6 defaults this unit assumes, quoted, or `None.` **Spikes** — the rule S6 spike and its named fallback, or `None.` |
| User stories | Partition below. Acceptance scenarios are that story's E2E ids, as Given / When / Then, using only that line and its cited section |
| `### Test plan` | After the last story, before Edge Cases. One row per E2E id: ID (verbatim), Harness, Entry point, Assertion (sentence + bracket tags), Proves (`FR-###`), Story. Entry point is the rule S8 live entry: route, `VendorEntrypoint` method, `scheduled()`, DO alarm, RPC, pg_cron, or a Flutter widget in the real shell. P2.2 and the package half of P2.1 may use Node and workerd vectors |
| `### Edge Cases` | Refusal codes, boundaries, and failure branches the E2E lines and Read sections name. Delete the template's placeholder questions |
| Requirements | `FR-###`, each a cited sentence, ending `(04 §2.2)` |
| Key Entities | Tables or contract types this unit defines, or `Not applicable — this unit defines no entities.` |
| Constitution Alignment | The **Codebase** cell, plus a wiring exception the row already names (rule S3). Stores and failures only as the Read sections and E2E lines name them. `plan.md` re-runs `02 §7` (rule S12) |
| `## Out of Scope` | The unit's Out of scope line, verbatim, plus: no **Do not read** material; no rewrite of a Consumes contract; no module no test-plan row reaches (rule S8; exception P2.2 and the package half of P2.1); no removal of a transitional path a later unit owns (rule S9, name it); no second codebase beyond the Codebase cell |
| Success Criteria | Every test-plan id passes in its harness, and every earlier suite stays green (rule S2). If Outputs names CP-A … CP-G, one more SC is that checkpoint's question (rule S11) |
| Assumptions | Section 6 defaults this unit relies on, and a transitional path rule S9 names. Nothing else |

The test plan is the rule S12 register. Later phases write one test per row, title prefixed with
the id (rule V3), and that test fails before the code exists. The row must already carry the entry
point, the observable outcome, and any refusal code the scenario names. Copy every E2E id. Add none.

### Story partition

Rule S3: S = 1–2 stories, M = 2–3, L = 3–4. One unit, one branch, one review.

- Each Implements bullet starts as a candidate. Attach each E2E id to the bullet its assertion proves. Every id belongs to one story.
- Merge bullets that share an entry point until the count is inside the range. Keep every scenario.
- Split a bullet only when the range's minimum requires it and its scenarios already use two entry points.
- Outside the range is stop condition 4. Do not invent a story.
- P1 is the story later stories in this unit depend on. "Why this priority" cites **Depends** and that later story. "Independent Test" names the story's E2E ids and harness. A regression-only line ("existing suites still green") sits on the last story.
- Write from the perspective the scenarios use: clinic member, administrator, operator, or the calling component.

## Rules

- Restate the design docs. Prose written to justify a requirement means delete it or stop.
- Never invent a field name, table name, error code, threshold, timeout, limit, or default.
- Never add error handling, retries, caching, abstraction, or configurability the cited sections do not name.
- Never pull a later unit's work forward.
- Coverage is checked, not extended (rules V5, V8). Every E2E id is a row. Every refusal code this unit introduces is on a row. Every FM-# a D1 owner cell assigns to this unit is on a row's tags or the Implements bullet that row proves. A channel this unit owns has both "current version accepted" and "missing or unsupported refused before auth and before any write". A gap is a stop. Do not mint an E2E id.

## Stop conditions

Output **nothing but** one `## ESCALATION` block listing every condition that fired. Do not guess,
do not write a partial spec, do not use `[NEEDS CLARIFICATION]`, and do not create the branch.

1. A requirement cannot be traced to a Read-line section, or to a section 6 default this unit is told to assume.
2. The unit would change something in **Consumes**.
3. An E2E scenario has no live entry point, or no observable outcome.
4. The Implements bullets cannot be partitioned into the rule S3 range, or the unit would touch a codebase its **Codebase** cell does not name.
5. A Read section is missing from the design docs, or the only answer is in a **Do not read** section.
6. Coverage gap (rules V5, V8): a refusal code, an assigned FM-#, or an owned version channel has no scenario line.
7. The pre-assigned spec number already belongs to a different feature directory.

```markdown
## ESCALATION

**Stop condition:** 1 — untraceable requirement
**Unit:** P1.1
**Question:** What is the required error shape when set_active_organization is called without membership?
**Should be answered by:** 01 §2 row T-1 (`docs/architecture/ai-billing-orchestration/01-abo-design-decisions.md`)
**Blocked until:** the design document or the delivery plan is amended
```
