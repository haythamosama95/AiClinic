---
description: Task out an AI platform delivery slice whose spec.md and plan.md already exist, one task per acceptance test plus its implementation, capped at 25. Pass the slice id or spec path as the argument.
---

# AI Platform — Task Out a Slice

The spec and the plan are authoritative. **Tasks add nothing.** Every task implements something both
documents already name.

**Input:** the slice's `specs/<NNN>-<name>/` containing `spec.md` and `plan.md`. Resolve it from the
slice id given as `$ARGUMENTS` or the current branch. If `plan.md` is missing, stop and say so.

## User Input

```text
$ARGUMENTS
```

The first argument should be the slice id. If empty, resolve from the current branch or ask.

## Sources — read exactly these

1. The slice's `spec.md` and `plan.md`.
2. `docs/architecture/17b-ai-platform-delivery-plan.md` §3.10 and §6.
3. `.specify/templates/tasks-template.md`.

Do not read `17-ai-platform.md` at this phase. If you believe you need it, the spec is incomplete —
that is stop condition 1.

## Overrides to the template

The tasks template predates the delivery plan. Where they conflict, the delivery plan wins:

- **Tests are never optional.** Ignore the template's "Tests are OPTIONAL" note entirely. Every case
  in the spec's Test plan is a task.
- **One slice is one story.** The spec has a single user story, so there is one `[US1]` label and no
  cross-story parallelism section. Delete the template's multi-story phases rather than leaving them
  empty.
- **No Foundational phase.** Prerequisites are other slices, already merged, listed in the plan's
  Consumes Binding.
- **No Polish phase.** Cleanup, refactoring, performance optimization, and "security hardening" as a
  generic task are forbidden — each would be work the spec does not name (R-20).

## Output — the Spec Kit tasks template, filled this way

Keep the header, the `[ID] [P?] [Story]` format block, and Path Conventions. Extend Path Conventions
with the Worker: `ai-platform/src/`, `ai-platform/migrations/`, `ai-platform/test/`.

Phases, replacing the template's:

1. **Setup** — only if the plan's Files section names files that must exist first. Otherwise omit.
2. **Tests** — one task per named test in the spec's Test plan, each marked `[P]` where it touches a
   different file. Written to fail before the code exists.
3. **Implementation** — one task per implementation unit in the plan's Files section.
4. **Verification** — a final task running the whole suite, including every prior slice's suite
   (delivery plan §3.10).

Then keep Dependencies & Execution Order and Parallel Opportunities, scoped to this one slice.

Each task states what it produces, which `FR-###` it satisfies, and which named test proves it.

## Rules

- **Hard cap: 25 tasks.** If the list exceeds it, stop and report. Never merge unrelated tasks to fit
  the cap, and never drop a test to fit it — an over-cap slice is a mis-scoped slice.
- No task without a spec requirement behind it.
- Every *spy* case in the spec becomes its own task; asserting a call count or an absence is separate
  work from asserting an outcome.
- Tasks are ordered so each test exists before or alongside the code it covers.

## Stop conditions

Delivery plan §6.3. If any is true, output **nothing but** an `## ESCALATION` block. Do not resolve
it yourself, do not guess, do not proceed partially.

1. A task would be needed that neither the spec nor the plan names.
2. A named test has no implementation unit in the plan to attach to.
3. The list exceeds 25 tasks.

```markdown
## ESCALATION

**Stop condition:** 3 — over the task cap
**Slice:** D5
**Count:** 34 tasks
**Question:** Should retry and fallback be split into two slices?
**Should be answered by:** §3.5 of docs/architecture/17b-ai-platform-delivery-plan.md
**Blocked until:** the delivery plan is amended
```
