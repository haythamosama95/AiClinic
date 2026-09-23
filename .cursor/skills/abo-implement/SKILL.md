---
name: abo-implement
description: Execute selected phases of tasks.md for an ABO slice (slice-floor tests only in Verification). Use when the user runs abo-implement with a phase selector. Band matrix verification is abo-verify, not this skill.
disable-model-invocation: true
---

# ABO — Implement a Slice

Execute an already-written `tasks.md`. **Implementation adds nothing.**

**Input:** slice directory + phase selector (`M1 phase 2`, `tests`, `T003-T006`, etc.). If no
selector, list phases and ask.

## Subagent models

When spawning parallel workers for `[P]` tasks: **Grok 4.7 High** (`model: "grok-4.7-high"`,
`subagent_type: "generalPurpose"`). On `## ESCALATION`, stop and hand off to **Kimi K3 High**
(`model: "kimi-k3-high"`) per `abo-workflow` — do not guess past an escalation on Grok.

## Prerequisites

```bash
.specify/scripts/bash/abo-paths.sh --json --require-tasks --include-tasks
```

## Sources

1. `tasks.md`, `plan.md`, `spec.md`.
2. `docs/architecture/ai-billing-orchestration/04-abo-delivery-plan.md` §3.11–§3.12, §5.
3. `contracts/`, `data-model.md`, Consumes Binding modules.

## Scope

Run **only** requested phases. Honour Dependencies & Execution Order; run `[P]` tasks in **parallel**
when they touch different files.

### Phase preconditions

Same as `ai-platform-implement`: earlier phases `[X]` with files on disk; Implementation requires
red Tests phase.

### Verification phase scope

When Verification is in scope:

- Run **§3.12 slice-floor tests** and **all prior slices' suites** (§3.11).
- **Do not** implement or run band matrix scenarios (`*-V*`, `*-E*`, `*-X*` from §3.2.1–§3.10.1) —
  those belong to `/abo-verify`.

## Execution

Mirror `ai-platform-implement` steps 1–9 with these substitutions:

- Path conventions: four codebases per plan.
- `quickstart.md` via `.specify/templates/abo-quickstart-template.md`.
- Prohibitions: delivery plan §5.3 ABO list + AP §6.4 when touching gateway code.
- **Parallelism:** when multiple in-scope tasks are `[P]`, spawn parallel **Grok 4.7 High** subagents
  instead of serializing independent files.

## Stop conditions

Same escalation shape as `ai-platform-implement` (tasks vs plan, Consumes, regressions, missing
files). Band verification gaps are **not** stop conditions here — record them for `/abo-verify`.
