---
name: ai-platform-implement
description: Executes selected phases of tasks.md for an AI platform delivery slice whose spec.md and plan.md already exist, enforcing the delivery plan's implementation prohibitions and keeping every prior slice's suite green. Use when the user asks to implement an AI platform slice, or one or more phases of its task list, or to drive speckit.implement on one.
disable-model-invocation: true
---

# AI Platform — Implement a Slice

The spec, the plan, and the task list are authoritative. **Implementation adds nothing.** You are
executing an already-written task list, not deciding what to build.

**Input:** the slice's `specs/<NNN>-<name>/` containing `spec.md`, `plan.md`, and `tasks.md`, plus
**which phases of `tasks.md` to run**. Resolve the slice from the current branch or the slice id. If
`tasks.md` is missing, stop and say so.

## Sources — read exactly these

1. The slice's `tasks.md` — the execution order.
2. The slice's `plan.md` — the Files, Test Layout, and Sequencing sections.
3. The slice's `spec.md` — the Requirements and Test plan a task claims to satisfy.
4. `docs/architecture/17b-ai-platform-delivery-plan.md` §3.10 and §6.
5. Any `contracts/` or `data-model.md` the plan names, plus the modules in its Consumes Binding.

Do not read `17-ai-platform.md` at this phase. If you believe you need it, the spec or the plan is
incomplete — that is stop condition 1.

## Scope — which phases to run

You run **only the phases you were asked for**, never the whole file by default.

- A phase selector may be a phase number (`2`), a range (`2-3`), a phase name (`tests`,
  `implementation`, `verification`, `documentation`), or an explicit task range (`T003-T006`).
- **If no selector was given, do not assume "all".** List the phases in `tasks.md` with their task IDs
  and current `[ ]` / `[X]` state, name the next unstarted phase, and ask which to run.
- Stop at the end of the last in-scope phase and report. Do not continue into the next phase because it
  looks small, unblocked, or already half-done.
- Tasks outside the selected phases are untouched — do not create their files, and do not mark them
  `[X]`.

### Phase preconditions

Because a run may start mid-file, verify the selected phases' prerequisites before executing anything:

- Every earlier phase that the selection depends on (per Dependencies & Execution Order) is fully
  `[X]`, and its files actually exist on disk. A task marked `[X]` whose file is missing is stop
  condition 6.
- If the selection includes an Implementation phase, **the Tests phase must already exist and be
  failing red.** Run the suite and confirm before writing any implementation. Tests that are absent, or
  green before the code exists, mean the run cannot proceed — report it rather than back-filling them.

## Overrides to the standard implement workflow

The generic Spec Kit implement flow predates this platform. Where they conflict, the delivery plan
wins:

- **No Polish phase.** Performance optimization, refactoring, cleanup, and generic "security
  hardening" are forbidden — each would be work the spec does not name (R-20). If `tasks.md` has no
  Polish phase, do not invent one.
- **No project scaffolding beyond the plan's Files section.** Do not create ignore files, configs,
  linters, or CI wiring the plan does not name. `ai-platform/.gitignore` is legitimate only if a task
  names it.
- **Tests land red first.** The Tests phase completes — and the tests are observed failing — before
  any Implementation-phase task begins. A green test written after its code proves nothing.
- **One slice is one story.** There is one `[US1]` label; there is no cross-story sequencing to plan.

## Execution

1. **Resolve scope.** Establish the slice and the selected phases per Scope above, and state which
   task IDs are in scope before touching anything.
2. **Verify preconditions.** `spec.md`, `plan.md`, and `tasks.md` exist. Every Consumes Binding row
   points at code that is actually present — a missing binding is stop condition 2. Then check the
   Phase preconditions above for the selected phases.
3. **Execute the selected phases in the order `tasks.md` gives.** Complete and verify one before
   starting the next. Honour its Dependencies & Execution Order section; run `[P]` tasks together only
   when they touch different files.
4. **When a Tests phase is in scope, end it by running the suite and confirming the new tests fail**
   for the stated reason — not because a file is missing or an import is broken. Report the failures.
5. **Implement only what the plan's Files section names**, and only for in-scope tasks. A file not in
   that table is out of scope.
6. **Mark each finished task `[X]` in `tasks.md`** as you complete it, and report progress per task.
7. **When the Verification phase is in scope, run it before Documentation:** this slice's whole suite
   plus **every prior slice's suite** (delivery plan §3.10). A prior slice going red is a regression,
   not an acceptable cost. If Verification is out of scope, still report the suite's state at the
   point you stopped.
8. **When the Documentation phase is in scope, write `quickstart.md` last** — only after Verification
   is green. Fill it per `.specify/templates/ai-platform-quickstart-template.md`: a brief of what was
   implemented, the files to review, exact commands to run the suite (and any slice-specific tests),
   how to inspect the changes, and manual validation steps only when the slice exposes behaviour
   beyond CI. The quickstart documents the passing state, not the plan.
9. **Report and stop.** List the tasks completed, the tasks left in the selected phases (with why), and
   the next phase that is now runnable.

## Prohibitions — delivery plan §6.4

These are the failure modes a weak implementer produces by default. Each maps to a named risk. If a
task seems to require one, that is stop condition 1.

- No mechanism from §9.14 added because it looks prudent (R-20).
- No prompt text, provider name, or model identifier in the Flutter client (R-12).
- No second Quota Durable Object round trip and no second R2 object per request (§7.5, §13.6).
- No guard rejection journaled as a request; no D1 row per stream chunk (§7.5).
- No per-request server-side state of any kind (§4.4, §9.7).
- No client-side assembly of a final result from chunks; no committable provisional content (§6.4, A5).
- No secret, key, or signing material in a config file, a log line, or a journal row (§13.4).

## Rules

- Do not choose a library, pattern, or abstraction the plan does not name. One implementation needs no
  interface (D-15).
- Do not add a configuration surface, a feature flag, or an extension point nobody asked for (R-20).
- Do not modify anything in the plan's Consumes Binding. A later slice may extend a frozen contract,
  never rewrite it (delivery plan §2.3).
- Do not weaken, skip, or `.skip` a test to make the suite green. A test that cannot pass is a stop
  condition.
- Do not pull work forward from a later slice because the file is already open.

## Stop conditions

Delivery plan §6.3. If any is true, stop and output **nothing but** an `## ESCALATION` block. Do not
resolve it yourself, do not guess, do not proceed partially, do not leave a half-finished file behind.

1. A task cannot be completed with what the spec and the plan name, or would require a §6.4
   prohibition.
2. A Consumes Binding entry has no existing implementation, or satisfying a task would require
   changing one.
3. A named test cannot be made to pass without changing the spec's stated behaviour.
4. A prior slice's suite goes red and the cause is this slice's change.
5. The work clearly exceeds the task list — new files, new components, or a second §4 component the
   plan does not name.
6. `tasks.md` and the working tree disagree: a task is marked `[X]` but its file is absent, or an
   Implementation-phase file exists while its Tests-phase file does not.

```markdown
## ESCALATION

**Stop condition:** 1 — task needs something the plan omitted
**Slice:** A1
**Task:** T007
**Question:** The plan names no path for the health endpoint, and no test asserts one.
**Should be answered by:** plan.md Files section, or spec.md FR-005
**Blocked until:** the plan is amended
```
