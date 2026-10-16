---
name: ai-platform-tasks
description: Task out an AI platform delivery slice whose spec.md and plan.md already exist, one task per acceptance test plus its implementation, capped at 25. Use when the user asks to generate tasks for an AI platform slice or run ai-platform-tasks.
disable-model-invocation: true
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

## Relationship to Spec Kit

This is the AI platform variant of Spec Kit's `/speckit-tasks`, in the same slot and producing the same
artifact: `specs/<NNN>-<name>/tasks.md` from `.specify/templates/tasks-template.md`, keeping its
`[ID] [P?] [Story]` format and Path Conventions. It diverges where the delivery plan overrides the
template — tests are mandatory, one slice is one story, no Foundational or Polish phase, and a hard cap
of 25 tasks. It runs after `/ai-platform-plan` and before `/ai-platform-implement`.

## Prerequisites

Resolve the slice and validate that `spec.md` and `plan.md` both exist, once, from the repository root:

```bash
.specify/scripts/bash/ai-platform-paths.sh --json
```

That wraps `check-prerequisites.sh` — which fails when `plan.md` is absent, exactly the check this
phase needs — adding only the `ai/<NNN>-…` branch resolution `.specify/feature.json` would otherwise
override. Never call `check-prerequisites.sh` directly on an `ai/` branch. Parse `FEATURE_DIR` and
`AVAILABLE_DOCS`; the latter tells you whether `data-model.md`, `contracts/`, and `quickstart.md`
already exist. If the script fails, report its error verbatim and stop.

Then resolve the tasks template through Spec Kit's override stack rather than reading the core file
directly:

```bash
SPECIFY_FEATURE_DIRECTORY="$FEATURE_DIR" .specify/scripts/bash/setup-tasks.sh --json
```

Use the `TASKS_TEMPLATE` path it returns.

## Sources — read exactly these

1. The slice's `spec.md` and `plan.md`. The spec's `## Clarifications` section, when present, holds
   decided implementation choices, not requirements — a task still traces to an `FR-###`.
2. `docs/architecture/ai-platform/03-ai-platform-delivery-plan.md` §3.10 and §6.
3. `.specify/templates/tasks-template.md`.
4. `.specify/templates/ai-platform-quickstart-template.md`.

Do not read `01-ai-platform.md` at this phase. If you believe you need it, the spec is incomplete —
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
5. **Documentation** — always present. One task for `specs/<NNN>-<name>/quickstart.md`, filled per
   `.specify/templates/ai-platform-quickstart-template.md`: what was implemented, files to review,
   slice-only test commands (`npx vitest run` for this slice's test files — not full `npm test`),
   how to inspect the changes, and manual validation only when the slice exposes behaviour beyond CI.
   The quickstart task must state slice-only scope explicitly: no prior-slice files in the review
   table, no combined test counts, no prior-slice regression commands. Add a separate `[P]` task per
   other documentation artifact the plan names (e.g. `ai-platform/README.md` on the bootstrap slice
   only).

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
**Should be answered by:** §3.5 of docs/architecture/ai-platform/03-ai-platform-delivery-plan.md
**Blocked until:** the delivery plan is amended
```
