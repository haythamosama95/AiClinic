---
name: abo-workflow
description: >-
  Run one ABO unit from specify through implementation by spawning a Grok 4.7
  orchestrator. The orchestrator only spawns the stage agents, commits at the
  two defined points, and on escalation spawns Kimi K3 and re-runs that step.
  Use when the user asks to run the ABO workflow for a unit id.
disable-model-invocation: true
---

# ABO — Workflow

You spawn **one** orchestrator and then wait. You do not specify, clarify, plan, task, implement, review, or commit.

**Input:** the unit id (`P1.1`, `P4.2`) in `$ARGUMENTS`. If it is empty, ask and stop.

Spawn a `generalPurpose` subagent with `model: "grok-4.7-high"` and `run_in_background: false`. Its prompt is the orchestrator prompt below, with the unit id filled in. When it returns, report its summary. Do not redo its stages.

## Orchestrator prompt

```text
You are the orchestrator for ABO unit <UNIT-ID>. You do not write the spec, the plan, the tasks, or the code. You do not review. You spawn one subagent at a time, wait for it, commit only at the two points below, and on an escalation spawn the resolver and re-run that same step.

Repository: /home/haytham/Desktop/AiClinic
Unit: <UNIT-ID>
Models: stage agents use model "grok-4.7-high". The escalation resolver uses model "kimi-k3-high". Both use subagent_type "generalPurpose" and run_in_background false. Never run two stage agents at once.

Each stage agent prompt starts with:
- Read and follow <skill path>. The unit id is <UNIT-ID>.
- Do not commit, amend, or push. Do not spawn subagents.
- If you hit a stop condition, your entire reply is the ## ESCALATION block and nothing else.

## Steps

Run 1–4 in order. A step is finished only when its agent returns without an ## ESCALATION block.

1. Specify. Skill: .cursor/skills/abo-specify/SKILL.md
2. Clarify. Skill: .cursor/skills/abo-clarify/SKILL.md
3. Plan. Skill: .cursor/skills/abo-plan/SKILL.md
4. Tasks. Skill: .cursor/skills/abo-tasks/SKILL.md

Then commit the Spec Kit docs (see Commits). Then run the implementation loop.

5. Implementation loop. Read tasks.md. A phase is a top-level section. A subsection is a heading under that phase whose body is a task list of at most 5 tasks. Walk phases in order, and subsections inside each phase in order. For each subsection, spawn one implement agent and wait. Pass a task range, not the phase name: `<UNIT-ID> T00x-T00y` covering only that subsection's ids. Skill: .cursor/skills/abo-implement/SKILL.md. Selecting the parent phase is forbidden — that runs every subsection.
6. After that implement agent returns without an escalation, spawn one review agent for that same subsection and wait. The review prompt is below. One review pass. Then commit that subsection (see Commits). Then start the next subsection.

Do not start step 5 until the Spec Kit commit exists. Do not start the next subsection until this subsection's implementation commit exists.

## Review agent

The review agent reads, for this subsection only: the task texts, the spec's requirements and test-plan rows those tasks cite, the plan's Files, Test Layout, Sequencing, and Consumes Binding, and delivery-plan sections 2 and 3 (rules S2, S7, S8, S9). It runs this subsection's tests.

It fixes defects in that subsection: a test that is green without the code, a test that fails for a missing import rather than the assertion, an E2E id that was dropped, a file the plan does not name, a Consumes contract that was rewritten, a module no test reaches, a transitional path that was removed, a skipped test. It does not add scope, start another subsection, or commit.

If it cannot fix a defect without changing the spec's behaviour, it replies with only an ## ESCALATION block.

## Escalation

An ## ESCALATION block from any stage or review agent stops that step. Do not guess and do not continue.

Spawn one kimi-k3-high agent. If API quota is exhausted, use grok-4.7-high agent. Give it the escalation block and the files it names. It amends the document named in **Blocked until** / **Should be answered by** so the question is answered. It does not run the failed step and it does not implement the unit. It does not commit.

When it returns, re-run the step that escalated, and only that step. An implement escalation re-runs that subsection's implement agent. A review escalation re-runs that subsection's review agent. Steps 1–4 re-run the same stage.

If the resolver cannot answer, or the re-run escalates again on the same question, stop the workflow and return both escalation blocks.

A tasks escalation that splits the unit (rule S3, past 40 tasks) is resolved only by the resolver amending the delivery plan. Do not invent the split yourself. After that amendment, re-run tasks.

## Commits

You are the only one who commits. Do not use --no-verify, --amend, or a git config change. Do not stage `.cursor/`, secrets, or files the step did not touch.

Before each commit, run git status, git diff, and git log -5 --oneline. Pass the message with a HEREDOC. After the commit, run git status.

Spec Kit commit — once, after step 4 returns clean, before any implement agent:

```
Submitting speckit docs for subphase: <UNIT-ID>
```

Stage the unit's `specs/<NNN>-abo-…/` files (spec.md, plan.md, tasks.md, research.md, data-model.md, contracts/) and `AGENTS.md` if specify changed it. Do not stage quickstart.md; it does not exist yet.

Implementation commit — after the review agent for that subsection returns clean:

- The phase has one subsection: `Implementing Phase <phase number>`
- The phase has more than one subsection: `Implementing Subphase <phase number>.<subsection number>`

Phase and subsection numbers follow tasks.md order, starting at 1. Example: phase 2 split in two is `Implementing Subphase 2.1` then `Implementing Subphase 2.2`. A verification phase with a single task list is `Implementing Phase 4`.

Stage the files that subsection added or modified, and the `[X]` updates in tasks.md. Review fixes are part of this commit. Do not commit the subsection before the review returns clean.

If a resolver changes Spec Kit docs after the Spec Kit commit, make the same Spec Kit commit again, with the same message, before resuming implementation.

## Done

Return: the branch, the spec directory, each stage's result, every escalation and how it was resolved, and every commit subject. The workflow is done when every subsection has an implement agent, a review agent, and an implementation commit, and no escalation is still open.
```
