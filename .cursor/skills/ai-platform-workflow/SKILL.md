---
name: ai-platform-workflow
description: >-
  Execute the full AI Platform specification workflow (specify, clarify, plan,
  tasks, implement) for a delivery slice, assigning each stage to a dedicated
  subagent. Use when the user asks to run the AI platform workflow end-to-end,
  or invokes ai-platform-workflow with a specification slice.
disable-model-invocation: true
---

# AI Platform Specification Workflow

## Input

- **Specification Slice:** `@<specification-slice>`

## User Input

```text
$ARGUMENTS
```

The first argument is the specification slice (e.g. `D4`, `A1`). Substitute it for
`@<specification-slice>` throughout this workflow.

---

## Objective

Execute the complete AI Platform specification workflow for the provided specification slice, progressing through each stage only after the previous stage completes successfully.

---

## Execution Rules

- Execute the workflow **strictly in order**.
- Assign **each workflow stage** to a dedicated **Cursor Grok 4.5** subagent (`model: "cursor-grok-4.5-medium"`, `subagent_type: "generalPurpose"`).
- Do **not** begin the next stage until the current stage has completed successfully.

---

## Workflow

### Stage 1 — Specify

Run:

```text
/ai-platform-specify @<specification-slice>
```

Read and follow `.cursor/skills/ai-platform-specify/SKILL.md`.

If the skill reports an escalation, stop the workflow.

---

### Stage 2 — Clarify

Run:

```text
/ai-platform-clarify @<specification-slice>
```

Read and follow `.cursor/skills/ai-platform-clarify/SKILL.md`.

Rules:

- The skill may ask up to **5 clarification questions**.
- Answer **each question** using a dedicated **Cursor Grok 4.5** subagent (`model: "cursor-grok-4.5-medium"`).
- Wait until all questions have been answered before allowing the clarification stage to complete.

If the skill reports an escalation, stop the workflow.

---

### Stage 3 — Plan

Run:

```text
/ai-platform-plan @<specification-slice>
```

Read and follow `.cursor/skills/ai-platform-plan/SKILL.md`.

If the skill reports an escalation, stop the workflow.

---

### Stage 4 — Generate Tasks

Run:

```text
/ai-platform-tasks @<specification-slice>
```

Read and follow `.cursor/skills/ai-platform-tasks/SKILL.md`.

If the skill reports an escalation:

- If the escalation indicates that the maximum task count was exceeded, instruct the subagent to **combine related tasks** and regenerate the task list.
- For any other escalation, stop the workflow.

---

### Stage 5 — Implementation

Assign a dedicated **Composer 2.5 (non-fast)** subagent (`model: "composer-2.5"`, `subagent_type: "generalPurpose"`) to run:

```text
/ai-platform-implement-all-tasks <specifications path>
```

Read and follow `.cursor/skills/ai-platform-implement-all-tasks/SKILL.md`.

Resolve `<specifications path>` from the branch created during Stage 1 (e.g. `specs/031-stream-broker`).

Wait until the implementation completes successfully.

---

## Failure Handling

Immediately stop the workflow if any stage reports an escalation, except for the task-count escalation during **Generate Tasks**, which should be resolved by combining related tasks and rerunning that stage.

---

## Success Criteria

The workflow is complete only when:

1. Specification has been created.
2. Clarification has completed without escalations.
3. Planning has completed.
4. Tasks have been generated successfully.
5. All implementation phases have been completed successfully by `/ai-platform-implement-all-tasks`.
