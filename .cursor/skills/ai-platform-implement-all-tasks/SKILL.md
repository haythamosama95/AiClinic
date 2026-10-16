---
name: ai-platform-implement-all-tasks
description: >-
  Implement every phase in a spec's tasks.md sequentially, assigning each phase
  to a Composer 2.5 subagent that runs ai-platform-implement. Use when the user
  asks to implement a full specification, run all phases of tasks.md, or
  execute an AI platform slice end-to-end.
disable-model-invocation: true
---

# Implement Specification

## Input

- **Specification Directory:** the path given in `$ARGUMENTS` (e.g. `specs/031-stream-broker`).
  Resolve from the current branch via `.specify/scripts/bash/ai-platform-paths.sh --json --require-tasks --include-tasks`
  when no directory is provided.

## User Input

```text
$ARGUMENTS
```

Optional: a specs directory path. When empty, resolve from the current `ai/` branch.

---

## Objective

Implement every phase defined in:

`<specs-directory>/tasks.md`

Each implementation phase **must** be executed using the `ai-platform-implement` skill providing it with the phase number.

Before starting, read `.cursor/skills/ai-platform-implement/SKILL.md` so you know what each phase owner must do.

---

## Execution Rules

- Execute **one phase at a time**.
- Assign **each phase** to a dedicated **Composer 2.5 (non-fast)** subagent (`model: "composer-2.5"`).
- The phase owner must invoke the `ai-platform-implement` skill for its assigned phase.
- The phase owner may spawn additional **Composer 2.5 (non-fast)** subagents to assist.
- The `ai-platform-implement` skill is responsible for the detailed implementation workflow of that phase.

The phase owner is responsible for:
- Orchestrating all spawned subagents.
- Invoking the `ai-platform-implement` skill.
- Reviewing all generated work.
- Integrating the results.
- Ensuring the phase is fully complete before proceeding.

**Do not start the next phase until the current phase has been fully completed and validated.**

### Phase owner prompt template

When spawning a phase owner subagent, include:

```text
Specification directory: <specs-directory>
Phase: <phase-number> (<phase-name from tasks.md>)

Read and follow .cursor/skills/ai-platform-implement/SKILL.md.
Run only this phase. Pass the phase selector as: "<slice-id> phase <N>" or the phase name.
Mark every in-scope task [X] in tasks.md before reporting done.
If you hit an ESCALATION stop condition, report it verbatim and stop.
```

Use `subagent_type: "generalPurpose"` and `model: "composer-2.5"`.

---

## After Each Phase

1. Verify that every task in the phase has been completed.
2. Commit the completed work using the following commit message:

```text
Phase <phase-number> Implementation
```

3. Continue with the next phase.

---

## Final Validation

After all phases have been implemented:

1. Run the complete project test suite.
2. Fix every failing test.
3. Repeat until all tests pass.
4. Ensure the working tree is clean and every change is committed.

---

## Completion

If the entire implementation is successful:

1. Publish the current branch.
2. Merge it into the `ai/master` branch.
