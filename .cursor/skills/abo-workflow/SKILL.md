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

Run one agent at a time except implement agents in the same parallel batch (multiple bullets in one original wave: `run_in_background: true`, spawn in one turn, wait until all return). Serial coalesced batches use one agent.

## Agent preamble (every spawned agent)

Append to each agent prompt:

- Read and follow only the skill path given. Unit id: <UNIT-ID>.
- Do not commit, amend, or push. Do not spawn subagents unless this orchestrator prompt says otherwise.
- Do not ask the user.
- On a stop condition, reply with nothing except a `## ESCALATION` block (per that skill).

## Git (orchestrator only)

1. **Branch first.** Resolve branch name per **Branch and feature directory** in `.cursor/skills/abo-specify/SKILL.md`. `git checkout ai/abo-master` (fetch `origin` if needed). `git checkout -b ai/<NNN>-abo-…`. All later work stays on this branch. Stage agents must not create another branch; they use the current branch.
2. **After steps 1–4 finish** (and any escalations for those steps are closed): commit message exactly `Submitting speckit docs`. Stage only this unit's `specs/<NNN>-abo-…/` (spec.md, plan.md, tasks.md, research.md, data-model.md, contracts/, escalations.md), `AGENTS.md` if specify changed it, and any delivery-plan amendment the resolver wrote. Do not stage quickstart.md or `.cursor/`.
3. **After each execution batch** (step 5): commit message `Implementing subphases <N>` where `<N>` is the coalesced wave label from step C (one original wave number, or `first–last` when several waves were merged). Stage every file that batch's implement agents touched, including `[X]` updates in tasks.md. If a resolver amends Spec Kit docs after the Spec Kit commit, commit those docs with `Submitting speckit docs` before resuming implementation.
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

A test failure is not an escalation. Do not resume an agent to keep fixing tests. Use **Test-failure split**.

## Test-failure split

Applies in every phase. When an agent reports failing tests, you assign the fixes. You do not resume that agent onto the failure set.

Count distinct failing test files and failing case ids from that report.

- **One file and at most 4 failing cases:** spawn one fix agent for that file.
- **One file and more than 4 failing cases:** split the case ids into contiguous groups of at most 4. One fix agent per group. Groups do not share case ids.
- **More than one file:** one fix agent per file. If a file has more than 4 failing cases, split that file as above.

Spawn every fix agent for that report in one turn (`run_in_background: true`). Wait until all return. Model `composer-2.5` (never `composer-2.5-fast`).

Each fix prompt names only its file and its case ids. It runs only that file, filtered to those ids, at most twice. It does not run any other file, a directory, or a suite. It does not spawn subagents. It does not commit.

If a fix agent returns with any of its cases still failing, do not give it more cases and do not hand the remainder to one agent. Split what remains under the same rules.

## C — Schedule (orchestrator only; no agent)

Read **Implementation Waves** in this unit's `tasks.md`. Do not infer from task order, `[P]`, or headings.

**Parse each wave**

- One bullet under a wave = one subphase = one task range (e.g. `T004–T006`).
- Multiple bullets in the same wave = those subphases run in parallel in step 5.
- **Task count** for a bullet: inclusive count from its range (`T004–T006` → 3; lone `T004` → 1). Parse ids from each wave bullet in `tasks.md`; en-dash and hyphen both separate range endpoints.

**Coalesce into execution batches** (orchestrator only; do not edit `tasks.md`)

Walk original waves in document order (`Wave 1`, `Wave 2`, …). Build **execution batches** for step D:

1. A wave with **more than one bullet** is always its own batch (parallel subphases). Do not merge it with the wave before or after.
2. A wave with **exactly one bullet** joins the **current serial batch** when:
   - the current batch is non-empty and every wave already in the batch is single-bullet, and
   - **combined task count** (sum of bullet task counts in the batch plus this wave) is **≤ 6**.
3. Otherwise start a new batch containing only this wave.
4. When the next wave fails rule 2, close the current batch and apply rules 1–3 to the next wave.

Record for each batch: original wave number(s) (for commits and the done summary), and either one combined task range (serial coalesce) or one bullet per parallel wave.

**Serial coalesce — task range:** one implement agent gets the span from the **first task id in the batch to the last** (min and max numeric suffix across all bullets in the batch, formatted as `T###–T###`). Bullets must stay in wave order.

**Coalesce check (before step D):** If two or more consecutive single-bullet waves each have task count ≤ 6 but their sum is ≤ 6, they must share one batch (not one agent per original wave). If sum would exceed 6, split into multiple batches (greedy pack in wave order). State the batch plan in the orchestrator log (wave numbers, task ranges, task counts).

## D — Implement

For each **execution batch** from C:

- **Serial batch** (one coalesced task range): spawn **one** implement agent (`run_in_background: false` is fine).
- **Parallel batch** (one original wave, multiple bullets): spawn one implement agent per bullet, all with `run_in_background: true`, wait until all return.

Handle escalations per B. Test failures follow **Test-failure split**; do not resume the implement agent to clear them.

Each implement prompt:

- Skill: `.cursor/skills/abo-implement/SKILL.md`
- Task range from the batch (combined range or one wave bullet only — not a phase name).

Implement agents run only tests named in tasks.md for that range (unit harness per abo-implement). No full E2E suite, no repo-wide test commands unless tasks.md names them for that subphase.

After the batch completes with no open escalation: git commit **Implementing subphases <N>** (`<N>` = one wave number, or `first–last` original wave numbers when coalesced).

Do not start E until every subphase in **Implementation Waves** is done.

## E — Static review

One agent (`grok-4.7-medium`). **No tests, no build, no lint CLI.**

Read: this unit's spec.md, plan.md, tasks.md, and code/files this unit changed on the branch. Report **critical and major** findings only. No fixes in this step.

## F — Fix findings

If E reported no critical or major findings, skip to Merge prep.

Otherwise spawn one agent (`composer-2.5`, never fast). Give it E's report only. It fixes this unit's code (not earlier units' tests). It runs **only** the test commands E lists as affected by those fixes—no full E2E, no unrelated suites. If that run fails, **Test-failure split** applies; do not resume this agent onto the failures.

## Merge

Working tree clean. `git fetch origin` if `origin` exists. Checkout `ai/abo-master` (from `origin/ai/abo-master` if needed). If `ai/abo-master` does not exist locally or on remote, stop and report.

`git merge <unit-branch>`. On conflict: stop, report paths, do not push. Push `ai/abo-master` only if merge succeeded and the user has not forbidden push; otherwise say push was skipped.

## Rules

- Agents read only what their skill lists; orchestrator reads only tasks.md waves for scheduling and git state for commits.
- No full E2E in any phase unless tasks.md names that command for the subphase or step F's affected tests.
- No agent fixes failing tests outside **Test-failure split**.

## Done

Return: unit branch name, merge result, spec directory, execution batches (coalesced wave numbers, task ranges, parallel vs serial), escalations and resolutions, every commit subject.
```
