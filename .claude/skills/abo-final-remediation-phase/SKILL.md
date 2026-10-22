---
name: abo-final-remediation-phase
description: Run one ABO final-review follow-up phase (FR01–FR06) from docs/review/abo-final-remediation-plan.md, using the prompt template in that plan's §2.6. Use when the user invokes this skill with an FR identifier (e.g. "FR03"), or asks to run, start, or execute a final remediation phase.
argument-hint: "FR<NN> (FR01–FR06)"
disable-model-invocation: true
---

# ABO Final Remediation Phase

## Input

The phase identifier is `$ARGUMENTS`. Accepted forms: `FR03`, `fr03`, `FR3`, `3`. Normalize it to the
two-digit form `FR<NN>` (`3` → `FR03`). Valid range: `FR01`–`FR06`. If no identifier is given, or it is
outside the range, ask for one and stop.

## Steps

1. Read the prompt template in `docs/review/abo-final-remediation-plan.md` §2.6 ("Prompt template"). Do not
   copy the template into this skill; the plan is the single source.
2. Read the plan's §3 phase overview and confirm `FR<NN>` exists. Note its "Depends on" and "Decisions"
   columns.
3. Read the plan's §2.5 decisions table and §5 status tracker:
   - If a decision on the phase's "Decisions" line is still `pending`, or its value makes the phase
     `not required`, stop. Report which decision blocks the phase, and do not start work.
   - If the phase's own §5 row is already `complete` or `not required`, stop and report that.
4. Instantiate the template: replace every `<NN>` with the phase number. The instantiated prompt is the
   entire task.
5. Execute the instantiated prompt in this session, exactly as written. The prompt governs what to read,
   implement, validate and report. Do not summarize it back; do the work.
6. Use a todo list (TodoWrite) for the items the prompt's "Before editing" step 3 asks for, and keep it
   current as you work.

## Rules

- Never edit the template, the §4 fix steps, or the §2.5 decisions to make a phase pass. Only your own §5 row
  and your `docs/review/final-remediation/FR<NN>.md` record are yours to write. FR02 has one exception:
  the single pointer line its fix steps allow in `docs/review/abo-remediation/RM01.md`.
- Validation is remote only (complete CI via `gh`). Do not run tests, builds, linters or type checks locally,
  even if a tool would let you.
- When the prompt says stop, stop and report. Do not soften stop conditions or guess past them.
- One phase per invocation. If the user asks for several, run them one at a time in numeric order, and wait
  for each to be `complete` or `not required` in §5 before starting the next.
