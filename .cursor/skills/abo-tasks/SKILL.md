---
name: abo-tasks
description: >-
  Generate tasks.md from spec + plan; mandatory Implementation Waves for the
  workflow orchestrator. After plan, before implement. Never commit.
disable-model-invocation: true
---

# ABO — Tasks

Spec + plan are authoritative. **Tasks add nothing** — every task traces to both.

**Input:** unit id in `$ARGUMENTS`, or current branch. No `plan.md` → run plan.

## Paths

Resolve `specs/<NNN>-*` from unit id or `ai/<NNN>-abo-…` (do not take directory from `.specify/feature.json` alone):

```bash
SPECIFY_FEATURE_DIRECTORY="specs/<NNN>-abo-…" \
  .specify/scripts/bash/check-prerequisites.sh --json
```

Then:

```bash
SPECIFY_FEATURE_DIRECTORY="$FEATURE_DIR" .specify/scripts/bash/setup-tasks.sh --json
```

Use returned `TASKS_TEMPLATE`. Script errors → verbatim + stop. Missing plan → say run plan.

**After resolver:** read amendment; continue.

## Sources (only these)

1. `spec.md`, `plan.md`. Clarifications ≠ requirements; tasks still cite `FR-###`.
2. `06-abo-delivery-plan.md` §2–3 only (S2, S3, S8, V3).
3. `TASKS_TEMPLATE`.

`AVAILABLE_DOCS` lists `research.md`, `data-model.md`, `contracts/`, `quickstart.md` — don't read design docs. Task needing design → stop 1.

## Phases (replace template samples)

Delete sample tasks, optional-tests note, MVP/deploy. No Foundational/Polish. Prerequisites = merged units in **Consumes Binding**.

| Phase | When |
| --- | --- |
| **Setup** | Only if **Files** needs scaffold first |
| **Tests** | One task per spec Test plan E2E id + each extra test **Test Layout** names; red first; group by `[USn]`; title prefix E2E id (V3) |
| **Implementation** | One task per **Files** unit, labelled by story |
| **Verification** | One task: unit harness from Test Layout passes (not repo-wide commands unless that *is* the harness) |
| **Documentation** | After harness green: `quickstart.md` per plan **Quickstart**; one task per other doc implement must write (separate subphases if disjoint paths). Don't re-task plan-phase `research.md` / `data-model.md` / `contracts/` unless plan defers them to implement |

### Subphases (≤5 tasks)

Any `###` task list ≤5 tasks. More → split consecutive subphases (5+1, …) in **Sequencing** order; keep story labels. One `###` = one range `T00x–T00y`; tasks inside run in order; parallelism only between subphases (see waves).

Task line shape:

```text
- [ ] T012 [US2] Add failing test in ai-platform/test/foo.test.ts — red test, FR-004, E2E-P4.2-03
```

Each task: deliverable, `FR-###`, E2E id, exact path. No `[P]` for scheduling unless template header requires it.

### Header, dependencies, waves

**Header:** spec title; prerequisites `plan.md`, `spec.md`; list plan artifacts from `AVAILABLE_DOCS`.

**Dependencies & Execution Order:** Setup → tests (per story/**Sequencing**) → implementation → verification → documentation. Narrate story/path order; **do not** list parallel waves here.

**Implementation Waves** (mandatory — `abo-workflow` reads this; do not infer from order/`[P]`/headings):

- `Wave 1`, `Wave 2`, … in order.
- One bullet per subphase: full task range, story, heading, **every file path** edited in that subphase.

```text
- T004–T006 [US2] — subphase: `### User Story 2 — tests (part 1)` — paths: `ai-platform/test/foo.test.ts`
```

- Multiple bullets in one wave → parallel only if path sets disjoint and **Sequencing** allows after prior wave.
- Otherwise one bullet per wave (serial).
- Setup alone = wave 1 when present. Verification = own wave after all implementation. Documentation = one wave (several bullets only if disjoint doc paths). Include one example wave with two bullets.

Tests headings: per story, copy title + Independent Test from spec. Checkpoints name story E2E ids.

List every subphase in Tests, Implementation, Verification, Documentation exactly once; no task id gaps or duplicates.

## Rules

- No task without spec requirement. No drop/mint E2E ids. Unit tests only if **Test Layout** already names them.
- Tests before code they cover. No commit/branch.
- **S3 size** (plan S/M/L): 12–20 / 20–32 / 32–40 tasks. >40 → stop 3 (escalate split to `<ID>a`/`<ID>b`, same NNN suffix pattern S4; amend delivery plan; don't split here). Under minimum → don't invent tasks.
- Stories = spec partition (S 1–2, M 2–3, L 3–4); don't collapse or add stories.
- Subphase splits don't change S3 task count.

## Stop conditions

Only `## ESCALATION`; no partial `tasks.md`.

| # | Trigger |
| --- | --- |
| 1 | Task needs something spec/plan don't name |
| 2 | E2E has no **Files** anchor |
| 3 | Honest count >40 |

```markdown
## ESCALATION

**Stop condition:** 3 — over the task cap
**Unit:** P3.4
**Count:** 44 tasks
**Question:** Which user stories should become P3.4a and P3.4b, keeping the same E2E ids?
**Should be answered by:** rule S3 of docs/architecture/ai-billing-orchestration/06-abo-delivery-plan.md
**Blocked until:** the delivery plan is amended
```
