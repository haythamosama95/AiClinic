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

### Escalation Handling

When any stage reports an escalation:

1. Spawn a dedicated **Claude Opus 5.0 (low thinking)** subagent (`model: "claude-opus-5-thinking-low"`, `subagent_type: "generalPurpose"`) to resolve the escalation.
2. After the escalation is resolved, **re-run the stage** that reported it.
3. Only proceed to the next stage once that stage completes successfully without a new escalation.

Do **not** stop the workflow on escalation unless the Opus subagent cannot resolve it after a reasonable attempt.

---

## Workflow

### Stage 1 — Specify

Run:

```text
/ai-platform-specify @<specification-slice>
```

Read and follow `.cursor/skills/ai-platform-specify/SKILL.md`.

If the skill reports an escalation, follow **Escalation Handling** above.

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

If the skill reports an escalation, follow **Escalation Handling** above.

---

### Stage 3 — Plan

Run:

```text
/ai-platform-plan @<specification-slice>
```

Read and follow `.cursor/skills/ai-platform-plan/SKILL.md`.

If the skill reports an escalation, follow **Escalation Handling** above.

---

### Stage 4 — Generate Tasks

Run:

```text
/ai-platform-tasks @<specification-slice>
```

Read and follow `.cursor/skills/ai-platform-tasks/SKILL.md`.

If the skill reports an escalation:

- If the escalation indicates that the maximum task count was exceeded, instruct the subagent to **combine related tasks** and regenerate the task list.
- For any other escalation, follow **Escalation Handling** above.

---

### Stage 5 — Implementation

Assign a dedicated **Composer 2.5 (non-fast)** subagent (`model: "composer-2.5"`, `subagent_type: "generalPurpose"`) to run:

```text
/ai-platform-implement-all-tasks <specifications path>
```

Read and follow `.cursor/skills/ai-platform-implement-all-tasks/SKILL.md`.

Resolve `<specifications path>` from the branch created during Stage 1 (e.g. `specs/031-stream-broker`).

Wait until the implementation completes successfully.

If the skill reports an escalation, follow **Escalation Handling** above.

---

## Failure Handling

When a stage reports an escalation, follow **Escalation Handling** above: spawn a Claude Opus 5.0 (low thinking) subagent to fix it, then re-run that stage.

For the task-count escalation during **Generate Tasks**, first try combining related tasks and regenerating the task list before invoking escalation handling.

Stop the workflow only if the Opus subagent cannot resolve the escalation.

---

## Success Criteria

The workflow is complete only when:

1. Specification has been created.
2. Clarification has completed successfully.
3. Planning has completed.
4. Tasks have been generated successfully.
5. All implementation phases have been completed successfully by `/ai-platform-implement-all-tasks`.
