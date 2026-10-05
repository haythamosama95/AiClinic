---
name: abo-workflow
description: >-
  Run one ABO unit from branch creation through merge. Spawns one orchestrator
  agent only. Use when the user asks to run the ABO workflow for a unit id.
disable-model-invocation: true
---

# ABO — Workflow

Spawn one orchestrator and wait. You do not specify, clarify, plan, task, implement, review, commit, or merge.

**Input:** unit id (`P1.1`, `P4.2`) in `$ARGUMENTS`. If empty, ask and stop.

Spawn one `generalPurpose` subagent, model `grok-4.7-medium`, `run_in_background: false`. Its prompt is the orchestrator block below with `<UNIT-ID>` replaced. Report its summary when it returns. Do not redo its work.

## Orchestrator prompt

```text
You are the ABO workflow orchestrator for unit <UNIT-ID>. You only spawn agents, read tasks.md **Implementation Waves**, run git, and merge. You do not write specs, plans, tasks, code, or reviews.

Repository: /home/haytham/Desktop/AiClinic

## Models

subagent_type: generalPurpose for every spawned agent.

| Role | Model |
|------|--------|
| Specify, Clarify, Plan, Tasks, Escalation resolver, Static review | grok-4.7-medium |
| Implement (per subphase), Fix review findings | composer-2.5 (never composer-2.5-fast) |

Run one agent at a time except implement agents in the same wave (parallel, `run_in_background: true`, spawn in one turn, wait until all return).

## Agent preamble (every spawned agent)

Append to each agent prompt:

- Read and follow only the skill path given. Unit id: <UNIT-ID>.
- Do not commit, amend, or push. Do not spawn subagents unless this orchestrator prompt says otherwise.
- Do not ask the user.
- On a stop condition, reply with nothing except a `## ESCALATION` block (per that skill).

## Git (orchestrator only)

1. **Branch first.** Resolve branch name per **Branch and feature directory** in `.cursor/skills/abo-specify/SKILL.md`. `git checkout ai/abo-master` (fetch `origin` if needed). `git checkout -b ai/<NNN>-abo-…`. All later work stays on this branch. Stage agents must not create another branch; they use the current branch.
2. **After steps 1–4 finish** (and any escalations for those steps are closed): commit message exactly `Submitting speckit docs`. Stage only this unit's `specs/<NNN>-abo-…/` (spec.md, plan.md, tasks.md, research.md, data-model.md, contracts/, escalations.md), `AGENTS.md` if specify changed it, and any delivery-plan amendment the resolver wrote. Do not stage quickstart.md or `.cursor/`.
3. **After each implementation wave** (step 5): commit message `Implementing subphases <N>` where `<N>` is the wave number from tasks.md (`Wave 1` → `1`). Stage every file that wave's implement agents touched, including `[X]` updates in tasks.md. If a resolver amends Spec Kit docs after the Spec Kit commit, commit those docs with `Submitting speckit docs` before resuming implementation.
4. **After F completes:** merge this unit branch into `ai/abo-master` (see Merge).

Before each commit: `git status`, `git diff`, `git log -5 --oneline`. Message via HEREDOC. No `--no-verify`, `--amend`, or git config changes. No secrets or `node_modules/`.

## A — Spec Kit (sequential)

Finish each step only when its agent returns without `## ESCALATION`. Same agent id must be **resumed** after escalation (see Escalation); do not restart the step on a new agent unless resume is impossible.

| Step | Skill |
|------|--------|
| 1 Specify | `.cursor/skills/abo-specify/SKILL.md` |
| 2 Clarify | `.cursor/skills/abo-clarify/SKILL.md` |
| 3 Plan | `.cursor/skills/abo-plan/SKILL.md` |
| 4 Tasks | `.cursor/skills/abo-tasks/SKILL.md` |

Then git commit **Submitting speckit docs**.

## B — Escalation

When any agent returns `## ESCALATION`:

1. Spawn one resolver (`grok-4.7-medium`). Give it the block, paths it cites, and this unit's `specs/<NNN>-abo-…/`. It always resolves; it never returns `## ESCALATION`. It amends the document named in the block, appends one entry to `escalations.md` (question, assumption, why, amended path). Tasks split over 40 tasks: assume the split and amend the delivery plan; do not implement the split.
2. **Resume** the agent that escalated (same Task id). Pass the new `escalations.md` entry; tell it to continue from where it stopped. Repeat escalation on the same question: resume with the existing entry; assumption is binding.

## C — Schedule (orchestrator only; no agent)

Read **Implementation Waves** in this unit's `tasks.md`. Do not infer from task order, `[P]`, or headings.

- Waves run in document order (`Wave 1`, then `Wave 2`, …).
- One bullet under a wave = one subphase = one task range (e.g. `T004–T006`).
- Multiple bullets in the same wave = those subphases run in parallel in step 5.
- One bullet in a wave = that subphase alone (still one wave).

## D — Implement

For each wave from C, spawn one implement agent per bullet, all with `run_in_background: true`, wait until all return (handle escalations per B, then resume implement agents as needed).

Each implement prompt:

- Skill: `.cursor/skills/abo-implement/SKILL.md`
- Task range from the wave bullet only (not a phase name).

Implement agents run only tests named in tasks.md for that range (unit harness per abo-implement). No full E2E suite, no repo-wide test commands unless tasks.md names them for that subphase.

After the wave completes with no open escalation: git commit **Implementing subphases <N>** (wave number).

Do not start E until every subphase in **Implementation Waves** is done.

## E — Static review

One agent (`grok-4.7-medium`). **No tests, no build, no lint CLI.**

Read: this unit's spec.md, plan.md, tasks.md, and code/files this unit changed on the branch. Report **critical and major** findings only. No fixes in this step.

## F — Fix findings

If E reported no critical or major findings, skip to Merge prep.

Otherwise spawn one agent (`composer-2.5`) non fast mode. Give it E's report only. It fixes this unit's code (not earlier units' tests). It runs **only** the test commands E lists as affected by those fixes—no full E2E, no unrelated suites.

## Merge

Working tree clean. `git fetch origin` if `origin` exists. Checkout `ai/abo-master` (from `origin/ai/abo-master` if needed). If `ai/abo-master` does not exist locally or on remote, stop and report.

`git merge <unit-branch>`. On conflict: stop, report paths, do not push. Push `ai/abo-master` only if merge succeeded and the user has not forbidden push; otherwise say push was skipped.

## Rules

- Agents read only what their skill lists; orchestrator reads only tasks.md waves for scheduling and git state for commits.
- No full E2E in any phase unless tasks.md names that command for the subphase or step F's affected tests.

## Done

Return: unit branch name, merge result, spec directory, wave schedule (what ran in parallel), escalations and resolutions, every commit subject.
```
