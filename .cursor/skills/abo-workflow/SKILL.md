---
name: abo-workflow
description: >-
  Run one ABO unit from specify through implementation by spawning a Grok 4.7
  orchestrator. The orchestrator reads tasks.md to schedule parallel implement
  agents (no shared files or tests), merges tiny subsections, commits at the
  two defined points, merges the unit branch into ai/abo-master when done, and
  on escalation spawns Kimi K3 and re-runs that step.
  Use when the user asks to run the ABO workflow for a unit id.
disable-model-invocation: true
---

# ABO — Workflow

You spawn **one** orchestrator and then wait. You do not specify, clarify, plan, task, implement, review, or commit.

**Input:** the unit id (`P1.1`, `P4.2`) in `$ARGUMENTS`. If it is empty, ask and stop.

Spawn a `generalPurpose` Grok 4.7 High effort subagent with and `run_in_background: false`. Its prompt is the orchestrator prompt below, with the unit id filled in. When it returns, report its summary. Do not redo its stages.

**Models.** Spawn only the subagents this skill names, at the effort it names. The orchestrator is Grok 4.7 High effort subagent. Step 5 implement agents use Composer 2.5 (`composer-2.5`) — not `composer-2.5-fast`. Other stage agents and the review agent use Grok 4.7 High effort. Never spawn a fast or max variant except where this skill names `composer-2.5` explicitly for implement. Do not substitute another model, effort, or agent type.

## Orchestrator prompt

```text
You are the orchestrator for ABO unit <UNIT-ID>. You do not write the spec, the plan, the tasks, or the code. You do not review. For steps 1–4, the review agent, and the resolver, spawn one subagent at a time and wait. For step 5, read tasks.md first, build work units and waves (below), and spawn as many implement agents in parallel as a wave allows. Commit only at the two points below. On an escalation, spawn the resolver and re-run that same step.

Repository: /home/haytham/Desktop/AiClinic
Unit: <UNIT-ID>
Models: steps 1–4 and step 6 (review) use Grok 4.7 High effort subagent. Step 5 implement agents use model "composer-2.5" only — never "composer-2.5-fast". The escalation resolver uses model "kimi-k3-high". If that resolver's API quota is exhausted, use Grok 4.7 High effort subagent for that resolver only. All use subagent_type "generalPurpose". Never spawn a fast or max variant except implement agents must use composer-2.5 (non-fast). Do not substitute any other model, effort, or agent type. These are the only agents you may spawn.

Concurrency: steps 1–4, step 6, and the resolver use run_in_background false — never overlap them with each other or with step 5. Step 5 waves may overlap only implement agents in the same wave: set run_in_background true for every implement agent in that wave, spawn them together, then wait until all have returned before starting the next wave or step 6.

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

Then commit the Spec Kit docs (see Commits). Then run implementation scheduling and waves (step 5).

5. Implementation. Before spawning any implement agent, read the unit's `tasks.md` end to end, including **Dependencies & Execution Order** and **Parallel Opportunities**. Build work units and waves as in **Implementation scheduling** below. Run waves in order. Do not spawn a review agent in this step.
6. After every work unit in step 5 has finished without an escalation, spawn exactly one review agent for the full unit and wait. The review prompt is below. One review pass for the whole unit — never per work unit. Then make the implementation commit (see Commits).
7. After step 6 and the implementation commit are complete with no open escalation, merge this unit's branch into `ai/abo-master` (see **Merge to ai/abo-master**).

Do not start step 5 until the Spec Kit commit exists. Do not start step 6 until every work unit in step 5 has finished without escalation. Do not start step 7 until step 6 and the implementation commit are done. Do not start wave N+1 until every implement agent in wave N has returned.

## Implementation scheduling

You do this planning yourself from `tasks.md` and `plan.md` Test Layout — do not spawn a planner subagent.

**Terms.** A **phase** is a top-level section whose heading is a numbered phase (Tests, Implementation, Verification, Documentation, …). A **subsection** is a heading under that phase whose body is a task list (at most 5 tasks per abo-tasks). A **subphase** is the same as a subsection. A **work unit** is what one implement agent runs: a contiguous task id range `<UNIT-ID> T00x-T00y`. Skill for every implement agent: .cursor/skills/abo-implement/SKILL.md. Model: `composer-2.5` only. Pass a task range, never a phase name alone — selecting the parent phase is forbidden.

**1. List subsections.** Walk phases in document order; inside each phase, walk subsections in order. Record each subsection's task ids.

**2. Merge small subphases.** If a subsection has only one or two tasks, merge it forward when you can:
- **First try** the next subsection in document order (same top-level phase).
- If this subsection is the **last** under its top-level phase, you may merge with the **first** subsection of the **next** top-level phase instead.
- The merged range stays contiguous task ids.
- **Dependencies & Execution Order** and abo-implement Preconditions still hold: nothing in the merged block may require a task outside the block to run first; do not merge if the later block's phase must not run yet (e.g. Implementation before Tests are red on disk, Documentation before Verification is green).
If merge is impossible, keep the small subsection as its own work unit.

**3. File and test ownership.** For every task, collect:
- **Files touched**: every path in backticks in the task line, plus any file named in the plan **Files** section that the task clearly implements or edits.
- **Tests run**: every `E2E-…` id the task names, plus any harness script path the task says to run (`run_all_backend_tests.sh`, `catalog/run.sh`, a named npm/flutter test command from Test Layout when the task is Verification).

Two tasks **conflict** if they share a file or share a test/harness run. Work units in the same wave must not conflict. Tasks that only append to the same file in strict `tasks.md` order (Dependencies says T00b depends on T00a, same file) belong in one work unit, not parallel agents.

**4. Waves.** Partition work units into waves respecting:
- Document and dependency order: a work unit cannot start until every task it depends on (per **Dependencies & Execution Order** and abo-implement Preconditions) is `[X]` on disk from an earlier wave or from tasks outside this unit's scope that were already done.
- Parallelism: within one wave, spawn one implement agent per work unit in that wave, all at once (run_in_background true), with pairwise non-conflicting file and test sets.
- Maximize parallelism: greedily pack every work unit that is dependency-ready and conflict-free with everything already in the current wave into the same wave; when no more fit, close the wave and repeat.

**5. Execute.** For each wave, spawn all implement agents with model "composer-2.5" and prompts as usual (skill + task range). Wait for the whole wave. If any agent returns ## ESCALATION, stop the wave, handle escalation, then re-run only the failed work unit(s) in a new single-agent wave (composer-2.5, run_in_background false) before continuing.

Record the schedule in your final summary: work units (task ranges), waves, and which units ran together.

## Review agent

Spawn this agent only once, in step 6, after all tasks in tasks.md have been implemented. Do not spawn a review agent after individual subsections.

The review agent reads, for the full unit: every task text in tasks.md, the spec's requirements and test-plan rows those tasks cite, the plan's Files, Test Layout, Sequencing, and Consumes Binding, and delivery-plan sections 2 and 3 (rules S2, S7, S8, S9). It runs the unit's tests (all phases).

It fixes defects across the unit: a test that is green without the code, a test that fails for a missing import rather than the assertion, an E2E id that was dropped, a file the plan does not name, a Consumes contract that was rewritten, a module no test reaches, a transitional path that was removed, a skipped test. It does not add scope, implement new subsections, or commit.

If it cannot fix a defect without changing the spec's behaviour, it replies with only an ## ESCALATION block.

## Escalation

An ## ESCALATION block from any stage or review agent stops that step. Do not guess and do not continue.

Spawn one Kimi K3 High effort agent. If API quota is exhausted, use Grok 4.7 High effort agent. Give it the escalation block and the files it names. It amends the document named in **Blocked until** / **Should be answered by** so the question is answered. It does not run the failed step and it does not implement the unit. It does not commit.

When it returns, re-run the step that escalated, and only that step. An implement escalation re-runs the implement agent for that work unit's task range only (one agent, model composer-2.5, run_in_background false). A review escalation re-runs the single unit review agent (step 6). Steps 1–4 re-run the same stage.

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

Implementation commit — once, after the single review agent in step 6 returns clean:

```
Implementing subphase: <UNIT-ID>
```

Stage every file the unit's implement agents added or modified, all `[X]` updates in tasks.md, and any fixes from the review agent. Do not make an implementation commit before the review returns clean.

If a resolver changes Spec Kit docs after the Spec Kit commit, make the same Spec Kit commit again, with the same message, before resuming implementation.

## Merge to ai/abo-master

You perform this merge yourself in step 7. Do not spawn a subagent.

Record the unit branch name before checkout (the current `ai/<NNN>-abo-…` branch for this unit).

1. Ensure the working tree is clean after the implementation commit (`git status`).
2. `git fetch origin` if `origin` exists.
3. Check out `ai/abo-master`. If it exists only on the remote, `git checkout -B ai/abo-master origin/ai/abo-master`. If it does not exist locally or on the remote, stop and report — do not invent the branch.
4. Fast-forward or merge the unit branch into `ai/abo-master` with a merge commit if needed: `git merge <unit-branch>`. Do not use `--no-verify`. Do not force-push. If the merge conflicts, stop, report the conflicted paths, and do not push.
5. Optionally push `ai/abo-master` to `origin` only when the merge succeeded and the user has not forbidden push in the session; if unsure, merge locally and report that push was skipped.

After a successful merge, note the merge result in your summary (branch merged, whether push ran).

## Done

Return: the unit branch, `ai/abo-master` merge result, the spec directory, each stage's result, the implementation schedule (work units, waves, parallel groups), every escalation and how it was resolved, and every commit subject. The workflow is done when every work unit has completed, the unit has exactly one review agent (step 6), there is one implementation commit, the unit branch is merged into `ai/abo-master`, and no escalation is still open.
```
