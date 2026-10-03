---
name: abo-tasks
description: >-
  Task out an ABO delivery unit whose spec.md and plan.md already exist, one
  task per E2E scenario plus its implementation, inside the unit's S3 size.
  Use when the user asks to generate tasks for an ABO unit or run abo-tasks.
  Never commit.
disable-model-invocation: true
---

# ABO — Task Out a Unit

The spec and the plan are authoritative. **Tasks add nothing.** Every task implements something both
documents already name.

**Input:** the unit id in `$ARGUMENTS`, or the current branch. If `plan.md` is missing, stop and say
to run `/abo-plan`.

## Relationship to Spec Kit

Same slot as `/speckit-tasks`: `specs/<NNN>-abo-…/tasks.md` from the tasks template, keeping its header,
`[ID] [P?] [Story]` format, and Path Conventions. Extend Path Conventions with the codebase the plan's
**Files** section names: `backend/`, `ai-platform/`, `abo/`, `packages/vendor-contracts/`, `frontend/`,
`e2e/fullstack/`. Runs after `/abo-plan` and before `/abo-implement`.

## Paths

`.specify/feature.json` outranks branch lookup, so do not take the directory from that file.
Resolve `specs/<NNN>-*` from the unit id, otherwise from the current `ai/<NNN>-abo-…` branch, and
pass that path below. This mode requires `plan.md`.

```bash
SPECIFY_FEATURE_DIRECTORY="<specs/<NNN>-abo-…>" \
  .specify/scripts/bash/check-prerequisites.sh --json
```

Parse `FEATURE_DIR` and `AVAILABLE_DOCS`. Then:

```bash
SPECIFY_FEATURE_DIRECTORY="$FEATURE_DIR" .specify/scripts/bash/setup-tasks.sh --json
```

Use the `TASKS_TEMPLATE` path it returns. Never call those scripts without `SPECIFY_FEATURE_DIRECTORY`.
If a script fails, report its error verbatim and stop. When the error is a missing `plan.md`, also say
to run `/abo-plan`.

## Sources — read exactly these

1. `spec.md` and `plan.md`. `## Clarifications` are implementation choices, not requirements. A task
   still traces to an `FR-###`.
2. `docs/architecture/ai-billing-orchestration/06-abo-delivery-plan.md`, sections 2 and 3 only, for
   rules S2, S3, S8, and V3.
3. The tasks template at `TASKS_TEMPLATE`.

`AVAILABLE_DOCS` lists which of `research.md`, `data-model.md`, `contracts/`, and `quickstart.md`
already exist. Do not read the design docs. If a task would need a design section, the spec is
incomplete — stop condition 1.

## Output

Write `tasks.md` in `FEATURE_DIR` from the template. Keep the header, the format block, and Path
Conventions. Delete the sample tasks, the optional-tests note, and the MVP / deploy strategy. Nothing
ships before P8 (rule S2). Scan the stop conditions before writing the file.

Phases, replacing the template's:

1. **Setup** — only if **Files** names files that must exist first. Otherwise omit.
2. **Tests** — one task per E2E id in the spec Test plan, and one per extra test **Test Layout**
   already names. Mark `[P]` where tasks touch different files. Write each test so it fails before
   the code exists. Group by the story column (`[US1]`, `[US2]`, …). The test title prefix is the
   E2E id (rule V3).
3. **Implementation** — one task per implementation unit in **Files**, labelled with the story it serves.
4. **Verification** — one task. The unit harness named in Test Layout passes. Do not name `npm test`, `npm run test:e2e`, `run_all_backend_tests.sh`, or `catalog/run.sh` unless that command is the unit harness. Earlier suites are the review's run.
5. **Documentation** — always, after that harness is green. One task for `specs/<NNN>-…/quickstart.md`: what was implemented, files this unit added or modified, the harness command for this unit's tests only, how to inspect the change, and the entry point → module chain per E2E id (rule S8). No earlier-unit files, no combined counts, no full-suite command. Manual steps only when the plan says the harness cannot see the behaviour. Add a `[P]` task per other doc artifact the plan says implement must write. `research.md`, `data-model.md`, and `contracts/` are plan-phase artifacts; re-task one only when the plan explicitly leaves it for implement.

**Five tasks per subsection.** Any heading whose body is a task list holds at most 5 tasks. A phase is a section. A story heading inside Tests or Implementation is also a section. When a section has more than 5 tasks, split it into consecutive subsections of at most 5, in Sequencing order (6 tasks → 5 + 1). Keep the story label on each part. A section of 5 or fewer is one subsection. Subsections are not new phases, not new stories, and not extra tasks. Do not merge or drop tasks to fit 5.

No Foundational phase. Prerequisites are earlier units, already merged, listed in **Consumes Binding**.

No Polish phase. Cleanup, refactoring, performance work, and generic security hardening are
forbidden — the spec does not name them.

Fill **Dependencies & Execution Order** and **Parallel Opportunities** as follows. Parallelism stays
inside the unit.

Each task states what it produces, which `FR-###` it satisfies, and which E2E id proves it. Include
the exact file path:

```text
- [ ] T012 [P] [US2] Add the failing test in abo/test/system/… — produces the red test, satisfies FR-004, proved by E2E-P4.2-03
```

### Header, dependencies, parallelism

**Header.** Feature name from the spec title. Prerequisites are `plan.md` and `spec.md`. Name
`research.md`, `data-model.md`, and `contracts/` when `AVAILABLE_DOCS` lists them; they are inputs
to this phase.

**Dependencies & Execution Order.** Setup, when present, before any test. Within a story, its tests
fail before its implementation, in **Sequencing** order. A later story waits only on the story
**Sequencing** says it depends on; otherwise its tests may start once Setup is done. Verification
runs after every implementation task. Documentation runs after that verification is green.

**Parallel Opportunities.** List `[P]` tasks that touch different files. A pair in different stories
is parallel only when **Sequencing** allows it. Give one fenced example of two test tasks from the
same story launched together.

Under the Tests phase, one heading per story copies that story's title and its Independent Test
line from `spec.md`. Implementation uses the same story labels. If that story has more than 5
tasks, those headings are the subsections above, still carrying the story title. Checkpoints name
the story's E2E ids.

## Rules

- No task without a spec requirement.
- Do not drop an E2E id. Do not mint an E2E id. A unit test is a task only when **Test Layout** already
  names it. An implementer may add unit tests and must never drop an E2E id; this phase does not invent
  that test.
- Order: each test exists before the code it covers.
- Do not commit. Do not create a branch.
- **Size is rule S3.** The plan records S, M, or L. Targets: S = 12–20 tasks, M = 20–32, L = 32–40.
  Past 40 is a stop. Do not merge unrelated tasks and do not drop a test to fit. An over-40 list is a
  mis-scoped unit: escalate to split along the spec's user stories into `<ID>a` / `<ID>b`, sharing the
  spec number with suffixes (rule S4, e.g. `068a`, `068b`) and keeping the same E2E ids. Do not perform
  the split. The delivery plan must be amended. Being under the minimum is not a reason to invent tasks.
- **Stories stay as the spec partitioned them** (S 1–2, M 2–3, L 3–4). Use `[US1]`, `[US2]`, …
  matching those stories. Do not collapse to one story. Do not add a story the spec does not have.
- **Subsections hold at most 5 tasks.** Splitting a long section does not change the task count
  that rule S3 measures.

## Stop conditions

Output **nothing but** one `## ESCALATION` block. Do not guess, and do not partial-write `tasks.md`.

1. A task would be needed that neither the spec nor the plan names.
2. An E2E id has no implementation unit in the plan to attach to.
3. The honest list exceeds 40 tasks.

```markdown
## ESCALATION

**Stop condition:** 3 — over the task cap
**Unit:** P3.4
**Count:** 44 tasks
**Question:** Which user stories should become P3.4a and P3.4b, keeping the same E2E ids?
**Should be answered by:** rule S3 of docs/architecture/ai-billing-orchestration/06-abo-delivery-plan.md
**Blocked until:** the delivery plan is amended
```
