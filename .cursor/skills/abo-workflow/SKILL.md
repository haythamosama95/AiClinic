---
name: abo-workflow
description: >-
  Run one ABO unit from specify through merge by spawning one Grok 4.7
  orchestrator. Use when the user asks to run the ABO workflow for a unit id.
disable-model-invocation: true
---

# ABO — Workflow

You spawn one orchestrator and wait. You do not specify, clarify, plan, task, implement, review, or commit.

**Input:** the unit id (`P1.1`, `P4.2`) in `$ARGUMENTS`. If it is empty, ask and stop.

Spawn one `generalPurpose` subagent, model `grok-4.7-high`, `run_in_background: false`. Its prompt is the orchestrator prompt below, with `<UNIT-ID>` replaced. When it returns, report its summary. Do not redo its stages.

## Orchestrator prompt

```text
You are the orchestrator for ABO unit <UNIT-ID>. You do not write the spec, the plan, the tasks, the code, or the review. You spawn the agents below and merge into ai/abo-master. Do not return until that merge is done, or until you stop on an unresolved escalation.

Repository: /home/haytham/Desktop/AiClinic
Unit: <UNIT-ID>

Models. Every agent is subagent_type generalPurpose. Steps 1–4, the review agent, the test-fix agent, and the resolver use grok-4.7-high. Implement agents use composer-2.5, never composer-2.5-fast. Do not substitute any other model.

Steps 1–4, review, the test-fix agent, and the resolver run one at a time with run_in_background false, and never overlap step 5. In a step 5 wave, set run_in_background true on every implement agent, spawn them in one turn, and wait until all have returned. Spawn the next wave before you end that turn.

Each stage prompt starts with:
- Read and follow <skill path>. The unit id is <UNIT-ID>.
- Do not commit, amend, or push. Do not spawn subagents. Do not ask the user.
- If you hit a stop condition, your entire reply is the ## ESCALATION block and nothing else.

## Steps

Run these in order. A step is finished only when its agent returns without an ## ESCALATION block.

1. Specify. Skill: .cursor/skills/abo-specify/SKILL.md
2. Clarify. Skill: .cursor/skills/abo-clarify/SKILL.md
3. Plan. Skill: .cursor/skills/abo-plan/SKILL.md
4. Tasks. Skill: .cursor/skills/abo-tasks/SKILL.md

Then the Spec Kit commit. Then step 5.

5. Implementation. Follow Scheduling. Do not start step 6 until every work unit has finished with no open escalation.
6. One review of the whole unit (see Review). If it reports test failures, one test-fix agent for those failures only. Then the implementation commit.
7. Merge this unit's branch into ai/abo-master (see Merge).

## Scheduling

You plan this yourself from tasks.md and plan.md Test Layout. Do not spawn a planner.

A phase is a numbered top-level section (Tests, Implementation, Verification, Documentation). A subsection is a task list under that phase. A work unit is one implement agent and one contiguous task range, <UNIT-ID> T00x–T00y. Skill: .cursor/skills/abo-implement/SKILL.md. Pass a task range, never a phase name.

Build the schedule once, in this order:

1. Walk phases in document order, then subsections. Each subsection is one work unit.
2. A task marked [P] that edits a different file is its own work unit. Take it out of that subsection. The tasks left behind stay in their contiguous ranges.
3. Two work units conflict when they edit the same path, or when both execute the same harness command. "Proved by E2E-…" is not a shared run. Subsections that edit the same file run one after another.
4. A work unit starts only once every task it depends on is [X] on disk. Pack every ready, conflict-free work unit into the current wave. When none of the rest fit, close the wave and start the next.

Each implement prompt is the task range plus abo-implement. That skill runs the unit harness once at the end of the range and does not run earlier suites.

## Review

One quick pass. Read the unit's spec, plan, tasks, and any research, data-model, and contracts, plus the code this unit wrote. Do not browse the rest of the repo.

Fix only critical and major findings. Critical: a test that is green without the code, a dropped E2E id, a rewritten Consumes contract, a removed transitional path, a skipped test. Major: behaviour that contradicts the spec, a file the plan names that is missing, a module no test reaches. Do not report or fix anything else. Do not add scope, implement new subsections, or commit. If a fix would change the spec's behaviour, the reply is only an ## ESCALATION block.

After those fixes, run the unit harness once, then each earlier-suite command the plan names once. A failure that is only a flake the plan already names gets one retry of that suite. Do not escalate that single failure. Report every remaining failure: command, test name, and the assertion. Do not fix test failures.

If that report lists any failure, spawn one grok-4.7-high agent. Give it the report and nothing else to investigate. It fixes this unit's code or its harness, then re-runs only the failed commands once. It does not edit an earlier unit's tests to make them pass, add scope, or commit. If a fix would change the spec's behaviour, or the re-run still fails, the reply is only an ## ESCALATION block.

## Escalation

An ## ESCALATION block stops that step. Do not guess.

Spawn the resolver with the escalation block and the files it names. It amends the document named in Blocked until / Should be answered by. It does not run the failed step, implement the unit, or commit.

When it returns, resume the same agent that escalated. Give it the amendment and tell it to continue from where it stopped. Do not spawn a fresh agent for that step unless resume is impossible.

If the resolver cannot answer, or the resumed agent escalates again on the same question, stop and return both escalation blocks.

A tasks escalation that splits the unit (rule S3, past 40 tasks) is resolved only by the resolver amending the delivery plan. Do not invent the split. After that amendment, resume the tasks agent.

## Commits

You are the only one who commits. Do not use --no-verify, --amend, or a git config change. Do not stage .cursor/, secrets, node_modules/, or files the step did not touch.

Before each commit, run git status, git diff, and git log -5 --oneline. Pass the message with a HEREDOC. After the commit, run git status.

Spec Kit commit, once, after step 4 and before any implement agent:

Submitting speckit docs for subphase: <UNIT-ID>

Stage the unit's specs/<NNN>-abo-…/ files (spec.md, plan.md, tasks.md, research.md, data-model.md, contracts/) and AGENTS.md if specify changed it. Do not stage quickstart.md.

Implementation commit, once, after review and any test-fix agent return clean:

Implementing subphase: <UNIT-ID>

Stage every file the implement agents, the review, and the test-fix agent added or modified, including [X] updates in tasks.md.

If a resolver changes Spec Kit docs after the Spec Kit commit, commit those docs again with the same Spec Kit message before resuming implementation.

## Merge

You do this yourself in step 7.

Record the unit branch (ai/<NNN>-abo-…). The working tree must be clean. git fetch origin if origin exists. Check out ai/abo-master. If it exists only on the remote, git checkout -B ai/abo-master origin/ai/abo-master. If it exists neither locally nor on the remote, stop and report. Do not invent the branch.

git merge <unit-branch>. Do not use --no-verify. Do not force-push. If the merge conflicts, stop, report the paths, and do not push.

Push ai/abo-master only when the merge succeeded and this session has not forbidden push. If unsure, skip the push and say so.

## Done

Return the unit branch, the ai/abo-master merge result, the spec directory, each stage's result, the wave schedule and who ran together, every escalation and how it was resolved, and every commit subject.
```
