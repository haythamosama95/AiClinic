---
name: abo-implement
description: >-
  Execute selected phases of tasks.md for an ABO delivery unit. Tests fail
  before implementation. Every earlier unit's suite stays green. Use when the
  user asks to implement an ABO unit or run abo-implement with a phase
  selector. Never commit.
disable-model-invocation: true
---

# ABO — Implement a Unit

The spec, the plan, and `tasks.md` are authoritative. **Implementation adds nothing.** You execute the task list. You do not decide what to build.

Design docs are not read at this phase. If you believe you need a design section, the spec or the plan is incomplete — stop condition 1.

**Input:** `$ARGUMENTS` is a unit id (`P1.1`) plus an optional phase selector (`P4.2 phase 2`, `P4.2 2-3`, `P4.2 tests`, `P3.1 T003-T006`). If the unit id is empty, resolve the directory under Prerequisites. If `tasks.md` is missing, stop and say to run `/abo-tasks`.

## User Input

```text
$ARGUMENTS
```

## Relationship to Spec Kit

Same slot as `/speckit-implement`: execute this unit's `tasks.md` and mark finished tasks `[X]` in place. It is the last phase, after `/abo-tasks`. It runs only the phases it was asked for. Tests fail before the code exists. When the unit is done, its scenarios pass in the named harness and every earlier suite is still green (rule S2).

## Prerequisites

`.specify/feature.json` outranks branch lookup, so do not take the directory from that file. Resolve `specs/<NNN>-*` from the unit id in `$ARGUMENTS`, otherwise from the current `ai/<NNN>-abo-…` branch, and pass that path below. If neither identifies one directory, ask and stop. Do not create a feature directory here.

From the repository root:

```bash
SPECIFY_FEATURE_DIRECTORY="specs/<NNN>-abo-…" \
  .specify/scripts/bash/check-prerequisites.sh --json --require-tasks --include-tasks
```

Parse `FEATURE_DIR` and `AVAILABLE_DOCS`. Read only the documents `AVAILABLE_DOCS` reports. If the script fails, report the error verbatim and stop. Never call the script without `SPECIFY_FEATURE_DIRECTORY`.

`FEATURE_DIR` is the directory you implement. If `$ARGUMENTS` names a unit and `FEATURE_DIR` is a different one, stop and report both. One run is one unit.

## Sources — read exactly these

1. `tasks.md` — execution order.
2. `plan.md` — Files, Test Layout, Sequencing, Consumes Binding.
3. `spec.md` — Requirements, Test plan, Out of Scope. The task claims an FR and an E2E id.
4. `docs/architecture/ai-billing-orchestration/06-abo-delivery-plan.md`, sections 2 and 3 only: S2 (earlier suites stay green), S7 (no rewrite of a freeze), S8 (a live entry point), S9 (transitional paths).
5. `contracts/`, `data-model.md`, and `research.md` only when `AVAILABLE_DOCS` says they exist, plus the modules in Consumes Binding.

A task that needs a section outside this list is stop condition 1. Do not open it.

## Scope

Run only the phases asked for.

- A selector is a phase number, a range, a phase name (`tests`, `implementation`, `verification`, `documentation`), or a task range (`T003-T006`). A phase is a top-level section. Subsections of at most 5 tasks belong to that phase; selecting the phase runs all of them.
- If the phase selector is empty, do not assume "all". List one line per phase heading already in `tasks.md`: the heading, the task ids, and `[ ]` or `[X]` on each. Name the next unstarted phase, then ask. Do not pick it yourself.
- Stop at the end of the last in-scope phase. Do not continue because the next phase looks small.
- Out-of-scope tasks: do not create their files, and do not mark them `[X]`. A task range does not include the other tasks in that phase.

`P4.2 phase 2` is phase 2 only. `P4.2 2-3` is phases 2 and 3. `P4.2 tests` is the phase headed tests. `P3.1 T003-T006` is those tasks and no others.

An empty selector gets a listing in this shape and nothing else — no files, no `[X]`. Use that unit's headings and ids:

```text
Phase 1 — Tests: T001–T006 [ ]
Phase 2 — Implementation: T007–T014 [ ]
Phase 3 — Verification: T015–T016 [ ]
Phase 4 — Documentation: T017 [ ]
Next unstarted: Phase 1 — Tests.
Which phase should I run?
```

### Preconditions

Before executing:

- Every earlier phase the selection depends on (Dependencies & Execution Order) is fully `[X]`, and its files exist. A `[X]` whose file is missing is stop condition 6.
- If Implementation is in scope, the Tests phase must already be on disk and failing red. Run the suite first: the command `plan.md` Test Layout names for this unit. Tests that are absent, or green before the code exists, mean stop and report. Do not back-fill tests inside an implementation run.

## Overrides

- **No Polish phase.** Do not invent one.
- **No scaffolding** the plan's Files section does not name (ignore files, configs, linters, CI). A file is legitimate only if a task names it.
- **Tests land red first.** End a Tests phase by running the suite and confirming the new tests fail for the stated reason — not a missing file or a broken import. The test file loads. Report the failures.
- The unit has the stories `tasks.md` already labels (`[US1]`, `[US2]`, …). Follow the order in Dependencies & Execution Order. Do not collapse stories into one pass.

## Execution

1. State the in-scope task ids before touching anything.

```text
In scope: P4.2 tests — T003, T004, T005, T006.
```

2. Verify preconditions. Every Consumes Binding row points at code that is present. A missing binding is stop condition 2.
3. Execute in `tasks.md` order. Finish one phase before the next. Run `[P]` tasks together only when they touch different files. An FR or an E2E id a task claims must already be in `spec.md`. Do not mint one.
4. Tests phase: confirm red, for the right reason.
5. Implement only files the plan's Files section names, only for in-scope tasks.
6. Mark each finished task `[X]` as you complete it, after its file is on disk. A test task is finished only once the red run is in the report.
7. Verification, when in scope, runs before Documentation: the harness the spec's test plan names for this unit, then every earlier unit's own harness (rule S2). An earlier suite going red is a regression — stop condition 4. Do not edit that unit to make it green. If Verification is out of scope, still report the suite state where you stopped.
8. Documentation, when in scope, writes `quickstart.md` last, only after Verification is green. The quickstart documents the passing state. Include only:
   - what was implemented
   - files this unit added or modified
   - the harness command for this unit's tests only
   - how to inspect the change
   - entry point → module chain per E2E id (rule S8)
   - manual steps only when the plan says the harness cannot see the behaviour
   No earlier-unit files, no combined counts, no full-suite command — regression is the Verification task. Renumber sections if you omit one; no gaps.
9. Report and stop. Tasks completed, tasks left in the selected phases and why, the next phase that is now runnable.

```text
Completed: T003–T006 (tests). Red: E2E-P4.2-01 fails on its assertion; the file loads.
Left in scope: none.
Suite where stopped: this unit's new tests are red. Earlier suites not run — verification is still ahead.
Next runnable: implementation, once you ask for it. Tests are on disk and red.
```

## Prohibitions

Take them from the spec's Out of Scope and from rules S7–S9. If a task seems to require one, that is stop condition 1.

- Do not rewrite a Consumes contract (rule S7). A later unit may extend a frozen contract. It may not rewrite one.
- Do not add a module no in-scope test reaches from a live entry point (rule S8): an HTTP route, a `VendorEntrypoint` method over a real service binding, `scheduled()`, a DO alarm, a PostgREST RPC, a pg_cron job, or a Flutter widget in the real shell. P2.2, and the package half of P2.1, are the exception: Node and workerd conformance vectors.
- Do not remove a transitional path whose owner is a later unit (rule S9). The spec's Out of Scope names the path and that owner.
- Do not choose a library, pattern, abstraction, config flag, or extension point the plan does not name.
- Do not weaken, skip, or `.skip` a test to make the suite green.
- Do not pull a later unit's work forward because the file is open.
- Do not commit, amend, or push.

## Stop conditions

Output nothing but one `## ESCALATION` block. If several conditions fire, name each in that block. Do not guess, do not proceed partially, do not leave a half-finished file behind. Remove a file this run created, and revert an edit, that no `[X]` task names, so the tree matches the marks you leave.

1. A task cannot be completed with what the spec and the plan name, or would break a prohibition above.
2. A Consumes Binding entry has no existing implementation, or a task would change one.
3. A named test cannot pass without changing the spec's stated behaviour.
4. An earlier unit's suite goes red because of this unit's change.
5. The work exceeds the task list: new files, a second codebase the plan does not name.
6. `tasks.md` and the tree disagree: `[X]` but the file is absent, or an implementation file exists while its test file does not.

```markdown
## ESCALATION

**Stop condition:** 1 — task needs something the plan omitted
**Unit:** P1.1
**Task:** T007
**Question:** …
**Should be answered by:** plan.md Files section, or spec.md FR-001
**Blocked until:** the plan is amended
```
