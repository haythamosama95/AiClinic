# ABO remediation — agent prompts

Prompts for the phases of the [remediation plan](abo-remediation-plan.md). Start one fresh session per phase
and send the matching prompt as its first message. Do not paste recipe text into the prompt; the plan is the
single source and tells the agent exactly which sections to read.

## Table of Contents

1. [Phase prompt (RM01–RM38)](#1-phase-prompt-rm01rm38)
2. [Baseline prompt (RM00)](#2-baseline-prompt-rm00)

---

## 1. Phase prompt (RM01–RM38)

Replace `<NN>` with the values from the plan's §3 phase overview.

```text
You are implementing remediation phase RM<NN> — for the ABO
integrated review.

Plan: docs/review/abo-remediation-plan.md. Read only §2 (rules) and the
RM<NN> entry in §4. Do not read other phase entries. Read a dependency's
completion record (docs/review/abo-remediation/RMxx.md) only when you
need to reuse something it built.

Before editing:
1. Check out and pull ai/abo-remediation. In §5, confirm the previous
   phase and every phase on your "Depends on" line are complete.
   If not, stop.
2. Read each recipe on your "Read" line by searching its key in the named
   file; read only that section. Then read the listed architecture
   sections. Open nothing else in docs/review/ or specs/.
3. Write a todo list: one item per fix step of each finding, in the
   entry's order, plus one item per completion check to turn into a test.

Implement:
- Fix steps are the specification. Completion checks are the acceptance
  tests; put the finding ID in each test title.
- When sources disagree: constitution > 01 §3.8 decisions > "Decision
  2026-10-18" notes > canonical report > detail report.
- Review line numbers refer to db9244fd; locate code by symbol.
- Forward migrations only. Never guess historical data (decision D-5).
- Change only this phase's findings. Record other defects under
  "Discovered issues" and later-phase dependencies as "Seam for RMxx".

Validate remotely only, with the complete CI workflow:
- Run nothing locally except git, gh and the code generators the plan
  allows. No tests, builds, linters or type checks.
- Commit, push to ai/abo-remediation, dispatch ci.yml (the complete
  workflow; never select or skip campaigns), and confirm the run's
  headSha is your commit (plan §2.9.3).
- Wait without hitting GitHub rate limits (plan §2.9.6). Never use
  `gh run watch`. Check with one
  `gh run view <run-id> --json status,conclusion` call: first 9 minutes
  after dispatch, then every minute for up to 5 more checks, then every
  5 minutes. If the run is not complete 2 hours after dispatch, stop and
  report. Wait between checks with your wait or sleep tool. Fetch job
  details and logs only once the run has completed. On a rate-limit
  error, wait until the reset time and resume.
- Green means every test-campaign job passed, apart from unchanged known
  failures in the RM00 baseline. Confirm your new tests actually ran and
  passed. Fix your own failures with a new commit and run the complete
  workflow again. Stop after three rounds failing on the same test case.

Stop and report instead of guessing if: a dependency is incomplete; a
recipe conflicts with current source; a step needs a choice the recipe
and decisions D-1…D-6 don't settle; a step needs an operational action
(implement the code part and list the action under "Operator
checklist"); or gh or CI misbehaves.

Finish per plan §2.11: completion record, your §5 row, docs-only commit
and push. Your final reply lists: findings implemented, validated commit
SHA and CI run URL, deferred steps, seams, discovered issues and operator
checklist items.
```

## 2. Baseline prompt (RM00)

Run once, before RM01, after the remediation plan is committed to `master`.

```text
Perform RM00 (CI baseline) of docs/review/abo-remediation-plan.md.
Read only §2.9 and §2.11 of that plan. Change no code and run nothing
locally except git and gh.

1. Create ai/abo-remediation from master and push it.
2. Dispatch the complete ci.yml workflow on it and confirm the run's
   headSha matches the pushed commit (plan §2.9.3).
3. Wait without hitting GitHub rate limits (plan §2.9.6). Never use
   `gh run watch`. Check with one
   `gh run view <run-id> --json status,conclusion` call: first 9 minutes
   after dispatch, then every minute for up to 5 more checks, then every
   5 minutes. If the run is not complete 2 hours after dispatch, stop and
   report. Fetch job details and logs only once the run has completed.
4. Write docs/review/abo-remediation/RM00.md with the commit SHA, the run
   URL and every failing test case (these become the known baseline
   failures). Fill the RM00 row in the plan's §5, then commit and push.
```
