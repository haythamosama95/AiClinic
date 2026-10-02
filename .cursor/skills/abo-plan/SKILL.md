---
name: abo-plan
description: >-
  Plan an ABO delivery unit whose spec.md already exists, filling the Spec Kit
  plan template and binding each consumed contract to an existing module. Use
  when the user asks to plan an ABO unit or run abo-plan. Never commit.
disable-model-invocation: true
---

# ABO — Plan a Unit

The spec is authoritative. You are choosing how to satisfy it. The plan may not
introduce a requirement, file, or component the spec does not name.

The leaf is a **unit** (`P1.1`, `P4.2`). This phase runs after `/abo-clarify` and
before `/abo-tasks`.

**Input:** the unit id in `$ARGUMENTS`, or the current `ai/<NNN>-abo-…` branch. If
neither identifies exactly one `specs/<NNN>-*` directory, ask and stop.

## Relationship to Spec Kit

Same slot as `/speckit-plan`: `specs/<NNN>-abo-…/plan.md` from
`.specify/templates/plan-template.md`, same constitution gate. The feature is a
unit of `docs/architecture/ai-billing-orchestration/06-abo-delivery-plan.md`. An
unanswerable field is an `## ESCALATION`, never `NEEDS CLARIFICATION`. Phase order:
`/abo-specify` → `/abo-clarify` → `/abo-plan` → `/abo-tasks` → `/abo-implement`.

## Paths

`.specify/feature.json` outranks branch lookup. From the repository root:

```bash
SPECIFY_FEATURE_DIRECTORY="<specs/<NNN>-abo-…>" \
  .specify/scripts/bash/check-prerequisites.sh --json --paths-only
```

Parse `FEATURE_DIR`, `FEATURE_SPEC`, and `IMPL_PLAN`. If `FEATURE_SPEC` is missing,
tell the user to run `/abo-specify` and stop.

Read the sources and check the stop conditions before seeding. An escalation does
not call `setup-plan.sh` and does not write `plan.md`.

When none fire, seed from the template stack and fill that file in place. A fresh
copy discards an earlier partial plan. That is intended.

```bash
SPECIFY_FEATURE_DIRECTORY="$FEATURE_DIR" .specify/scripts/bash/setup-plan.sh --json
```

Never call `check-prerequisites.sh` or `setup-plan.sh` without
`SPECIFY_FEATURE_DIRECTORY`. Do not commit.

## Sources — read exactly these

1. The unit `spec.md` whole, including `## Unit Contract`. `## Clarifications`, when
   present, are decided implementation choices, not requirements: follow them, never
   promote one into an FR, never trace a file to one instead of an FR.
2. The delivery plan: this unit's section in section 4, plus sections 2 and 3
   (rules S1–S12, harnesses V1–V8). Section 6 only for open questions the spec's
   **Open questions relied on** names.
3. Design docs under `docs/architecture/ai-billing-orchestration/`, only the
   sections in the spec's **Implements** Read citations. For Constitution Check,
   also `02 §7` of `02-abo-architecture-and-threat-model.md`. Read the files. Do
   not use `git show`.
4. Existing modules named in **Consumes**.
5. `.specify/templates/plan-template.md` and `.specify/memory/constitution.md`.

Needing any other source is stop condition 1. A **Do not read** section from the
unit row is a stop, not a lookup.

## Repository

Code lives where the spec's **Codebase** cell says: `backend/`, `ai-platform/`,
`abo/`, `packages/vendor-contracts/`, `frontend/`, `e2e/fullstack/`. The plan
template's path conventions predate `abo/` and `packages/vendor-contracts/`.
Extend the tree. Do not force Worker or package code into `backend/`. A unit
touches one codebase unless the delivery-plan row names a wiring exception
(rule S3: P2.1 platform header wiring; P5.1 the full-stack harness; P7.1 viewer
+ scripts + docs).

## Output

Keep every mandatory template section. Add the four sections after Project
Structure and before Complexity Tracking. Delete unused source-tree branches.
Do not write `tasks.md`.

| Section | Fill with |
| --- | --- |
| Summary | Two sentences from the spec, plus where the unit sits (**Depends**, phase) |
| Technical Context | Concrete values from the spec or cited design only. Never write `NEEDS CLARIFICATION`. An unanswerable field is stop condition 1 |
| Constitution Check | Every box ticked. Read and re-run `02 §7` (rule S12) against the template boxes and `.specify/memory/constitution.md`. An uncheckable box is stop condition 4, not a Complexity Tracking row |
| Project Structure → Documentation | Always name `quickstart.md` (outline only; see below). `data-model.md` only when the spec defines entities. `contracts/` when a **Freezes** entry has a wire shape (table, payload, token, event, error body), because a later unit's **Consumes** must bind to a file, not to prose. `research.md` only per Spikes |
| Project Structure → Source Code | The real tree for this unit's **Codebase**. Delete unused template branches |
| `## Consumes Binding` | One row per **Consumes** entry, naming the existing module, file, or type. No existing implementation is stop condition 2. Depends `None` → write `None.` |
| `## Files` | Every file created or modified, each traced to an `FR-###`. An untraced file is out of scope |
| `## Test Layout` | One row per E2E id in the spec Test plan, placed in the harness the spec names (H-PKG, H-AP, H-ABO, H-PAY, H-XW, H-BK, H-FS, H-FL, H-STG). The test title starts with the E2E id (rule V3). Tests are written to fail before the code exists |
| `## Sequencing` | Tests land first and are observed failing before implementation. Never after |
| Complexity Tracking | Only a genuine constitution violation that `02 §7` already records. Not a parking lot for open questions, and not a place for an unticked box |

### quickstart.md

The plan states the sections it will contain; the implement phase writes the file
after verification. Required content: what was implemented, files this unit adds
or modifies, the harness command for this unit's tests only, and entry point →
module chain per E2E id (rule S8). No earlier-unit files, no combined test
counts, no full-suite command.

### Spikes

When **Spikes** is `None`, do not produce `research.md`. The design docs are the
research. Redoing them is how the design drifts.

When **Spikes** is not `None`, run the spike in this phase (rule S6). It is not a
separate unit. `research.md` records the spike, the outcome, and the design's
named fallback. If the spike fails and the spec names a fallback that does not
require further approval, the plan uses that fallback and says so. If the spike
fails and the spec says to stop — OQ-4: P5.1 escalates rather than adding an
Edge Function signer without approval — or the spec names no fallback, that is
stop condition 6. Do not invent a fallback.

## Rules

- The phase is not done until every documentation artifact the plan says exists
  now is on disk. `quickstart.md` is the exception: the plan names it; implement
  writes it after verification.
- `research.md`, `data-model.md`, and `contracts/` are written in this phase when
  the rules above include them.
- Every file traces to an FR. Do not choose a library, pattern, or abstraction
  the spec or the cited design does not name. One implementation needs no interface.
- Do not add a configuration surface, feature flag, or extension point the spec
  does not name.
- Do not modify anything in **Consumes**. A later unit may extend a freeze, never
  rewrite it (rule S7).
- Every module the unit adds is reached by a Test Layout entry point (rule S8).
- The implied task count must sit in the unit's rule S3 size: S 12–20, M 20–32,
  L 32–40. There is no 25-task cap. Past 40 is stop condition 5 (the split belongs
  to the tasks phase, along user stories). Do not pad tasks to hit the minimum.

## Stop conditions

Output nothing but one `## ESCALATION` block. Do not guess, do not partial-write,
do not write `NEEDS CLARIFICATION`. If several fire, name each in that one block.

1. The plan needs something the spec omitted, or a Technical Context field cannot be answered.
2. A **Consumes** entry has no existing implementation, or satisfying the spec would change one.
3. A Test-plan E2E id cannot be placed in the harness the spec names.
4. A Constitution Check box cannot be ticked (`02 §7`).
5. The plan implies more than 40 tasks, or it touches a codebase the spec's **Codebase** cell does not name.
6. A spike failed and the spec's **Spikes** subsection says to stop, or names no fallback.

```markdown
## ESCALATION

**Stop condition:** 1 — plan needs something the spec omitted
**Unit:** P4.2
**Question:** …
**Should be answered by:** spec.md, regenerated from the unit's Read sections
**Blocked until:** spec.md is amended
```
