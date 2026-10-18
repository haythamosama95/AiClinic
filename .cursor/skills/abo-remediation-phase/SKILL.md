---
name: abo-remediation-phase
description: Run one ABO remediation phase (RM01–RM38) using the phase prompt template from docs/review/abo-remediation-prompts.md. Use when the user invokes this skill with an RM identifier (e.g. "RM07"), or asks to run, start, or execute a remediation phase.
disable-model-invocation: true
---

# ABO Remediation Phase

## Input

The user supplies one RM identifier with the invocation — the text right after the skill name, e.g.
`abo-remediation-phase RM07`. Accepted forms: `RM07`, `rm07`, `RM7`, `7`. Normalize it to the two-digit
form `RM<NN>` (`7` → `RM07`). Valid range: `RM01`–`RM38`. If no identifier is given, or it is outside the
range, ask for one and stop.

This skill covers phase prompts only (RM01–RM38). For the CI baseline use the baseline prompt
(`abo-remediation-prompts.md` §2) — it is already complete and must not be re-run.

## Steps

1. Read the phase prompt template in `docs/review/abo-remediation-prompts.md` §1 ("Phase prompt
   (RM01–RM38)"). Do not embed or copy the template here — the committed file is the single source.
2. Read the phase overview table in `docs/review/abo-remediation-plan.md` §3 and confirm `RM<NN>` exists;
   note its title and "Depends on" line.
3. Instantiate the template: replace every `<NN>` with the phase number. Output nothing else — the
   instantiated prompt is the entire task.
4. Execute the instantiated prompt in this session, exactly as written. The prompt itself governs what to
   read, implement, validate, and report. Do not summarize it back; do the work.
5. Before starting work, the template's own step 1 (dependency check in plan §5) decides whether the
   phase may start. If it says stop, stop and report — do not soften that rule.

## Rules

- Never edit the template or the plan to make a phase pass.
- One phase per invocation; if the user asks for several, run them one at a time, in numeric order,
  waiting for each to finish (`complete` in plan §5) before the next.
