# ABO final review — follow-up remediation plan

Status: ready for implementation (FR01–FR06; the FR04 refund test waits on FD-3) ·
Prepared: 2026-10-22 (Africa/Cairo).
Implements the 4 Major findings and 4 partly handled requirements from the
[final review](final-review/) of the ABO remediation (RM00–RM38) in 6 phases, `FR01`–`FR06`. Track progress
in the [status tracker](#5-status-tracker).

## Table of Contents

1. [Purpose, inputs and baseline](#1-purpose-inputs-and-baseline)
2. [Rules for implementing agents](#2-rules-for-implementing-agents)
3. [Phase overview](#3-phase-overview)
4. [Phase details](#4-phase-details)
5. [Status tracker](#5-status-tracker)
6. [Post-remediation review gate](#6-post-remediation-review-gate)
7. [Finding-to-phase index](#7-finding-to-phase-index)

---

## 1. Purpose, inputs and baseline

### 1.1 What this plan is

The second-round final review checked every RM phase at the branch tip. It found no Critical findings,
4 Major findings, and 4 requirements that are only partly handled. This plan fixes them. As in the
[remediation plan](abo-remediation-plan.md), each phase is one bounded agent session, the fix steps below are
the specification, and validation is always the complete GitHub CI workflow on the pushed commit.

Unlike the remediation plan, the fix recipes are written **in this plan** (§4), because the final-review
reports give only a short proposed fix. The reports supply the failure scenario and evidence.

### 1.2 Inputs

| Report | Scope | Verdict | Findings |
| --- | --- | --- | --- |
| [stage1-authority-trust.md](final-review/stage1-authority-trust.md) | RM00–RM07 | FAIL | M-1 → FV-M1 |
| [stage2-payment-commands.md](final-review/stage2-payment-commands.md) | RM08–RM13 | FAIL | M-1 → FV-M3; RM10 partial → FV-P1 |
| [stage3-value-conservation.md](final-review/stage3-value-conservation.md) | RM14–RM21 | PASS | — |
| [stage4-accounting-lifecycle.md](final-review/stage4-accounting-lifecycle.md) | RM22–RM27 | PASS | — |
| [stage5-recovery-config.md](final-review/stage5-recovery-config.md) | RM28–RM35 | FAIL | M-1 → FV-M4; RM31, RM32, RM33 partial → FV-P3, FV-P2, FV-P4 |
| [stage6-projection-desktop.md](final-review/stage6-projection-desktop.md) | RM36–RM38 | PASS | — |
| [backend-rls.md](final-review/backend-rls.md) | backend/, all RMs | FAIL | M-1 → FV-M2; M-2 = FV-M1 (duplicate of Stage 1 M-1) |

Phase status at the review target: 34 of 39 phases fully handled, 4 partly handled (RM10, RM31, RM32, RM33),
none unhandled or regressed.

### 1.3 Baseline revisions

| Reference | Revision | Meaning |
| --- | --- | --- |
| Final-review target | `6cae8104` on `ai/abo-remediation` | All line numbers in the final-review reports and in §4 refer to this tree |
| Integration branch | `ai/abo-remediation` | Every FR phase commits and pushes here, on top of RM38 |

### 1.4 Scope

In scope: the 4 Major findings (FV-M1…FV-M4) and the 4 partly handled requirements (FV-P1…FV-P4). FV-P1 and
FV-P2 are closed by FV-M3 and FV-M4. FV-P3 and FV-P4 are deviations the owner already accepted in RM31 and
RM33; they get conditional phases that run only if the owner reopens them (§2.5).

Out of scope: the "Could not verify" notes in the reports. They are listed in §7.2 for the review gate (§6),
and they are not findings.

## 2. Rules for implementing agents

### 2.1 Inherited rules

Every rule in [abo-remediation-plan.md §2](abo-remediation-plan.md#2-rules-for-implementing-agents) applies,
with the substitutions in §2.2. That includes: one phase per session (§2.1), scope discipline (§2.6),
cross-phase seams (§2.7), migrations and data (§2.8), remote CI only (§2.9, including the RM00 known
failures), stop conditions (§2.10) and finishing a phase (§2.11).

### 2.2 Substitutions

| In the remediation plan | Read as |
| --- | --- |
| Phase `RM<NN>`, range RM01–RM38 | Phase `FR<NN>`, range FR01–FR06 |
| Plan file `abo-remediation-plan.md` | This file, `abo-final-remediation-plan.md` |
| Phase entry in §4, tracker in §5 | §4 and §5 of this file |
| Completion record `docs/review/abo-remediation/RM<NN>.md` | `docs/review/final-remediation/FR<NN>.md` |
| Commit `RM<NN>: <title> (<finding IDs>)` | `FR<NN>: <title> (<finding IDs>)` |
| Record commit `RM<NN>: record CI result` | `FR<NN>: record CI result`; changes only this file and `docs/review/final-remediation/` |
| Recipe keys in R1–R9 reports (§2.2 "What to read") | The fix steps and completion checks in this plan's §4 entry |
| Decisions D-1…D-6 | D-1…D-6, plus FD-1…FD-4 in §2.5 |

### 2.3 What to read

1. This plan: §2 and your own §4 entry only.
2. The final-review report section named on your **Read** line, for the failure scenario and evidence.
3. The original recipe named on your **Read** line, by searching its key; read only that section.
4. The completion record of the RM phase that built the code you change, only to reuse something it built.

Do not read other §4 entries, other final-review reports, or anything else in `docs/review/` or `specs/`.

### 2.4 Precedence

Constitution > D-1…D-6 > FD-1…FD-4 > the fix steps in this plan > the original canonical recipe > the
final-review report. If the fix steps conflict with the intent of the original recipe, stop and report.

### 2.5 Decisions

| ID | Question | Status | Effect |
| --- | --- | --- | --- |
| FD-1 | Has any shared environment (staging or production) already recorded migration `20261014170500_r1_sql02_membership_role_repair.sql`? | **no** (maintainer, 2026-10-22) | FR02 edits that unmerged migration. It may start only when this row says "no". If "yes", FR02 stops and the maintainer chooses a repair path. |
| FD-2 | RM31 R9-CRON1: a period that was never attempted is not started by the minute cron (owner-accepted safety deviation). Keep it, add detection, or implement full catch-up? | **detect** (owner, 2026-10-22) | `keep` → FR05 is `not required`. `detect` → FR05 runs with the detection recipe. `catch-up` → FR05 stops: the recipe must be rewritten first. |
| FD-3 | Paymob payout CSV refund `transaction_id`: is it the refund's own id or the parent payment id? | **pending: provider evidence** | FR04 implements the manual-evidence path regardless. It re-enables the skipped refund test only when this row records the answer and its evidence source. |
| FD-4 | RM33 R8-PUB1 step 3: legacy routing rows with no digest are served with an error log (owner-accepted). Keep it, or add a launch-check gate? | **gate** (owner, 2026-10-22) | `keep` → FR06 is `not required`. `gate` → FR06 runs. |

A phase whose decision says `not required` counts as complete for dependency checks.

### 2.6 Prompt template

Start each phase in a fresh session with this prompt, replacing `<NN>`. The Claude Code skill
`abo-final-remediation-phase` instantiates and runs it.

```text
You are implementing follow-up remediation phase FR<NN> for the ABO
final review.

Plan: docs/review/abo-final-remediation-plan.md. Read only §2 (rules)
and the FR<NN> entry in §4. Do not read other phase entries. §2.1
makes docs/review/abo-remediation-plan.md §2 binding with the §2.2
substitutions: read that §2 too, and nothing else in that file.

Before editing:
1. Check out and pull ai/abo-remediation. In §5, confirm every phase
   on your "Depends on" line is complete or not required, and that
   every decision on your "Decisions" line in §2.5 allows this phase
   to start. If not, stop.
2. Read the final-review report section and the original recipe on
   your "Read" line; read only those sections.
3. Write a todo list: one item per fix step, one per completion check
   (each becomes a test), and one to search existing tests for every
   symbol you change and update those asserting the old behavior.

Implement:
- The fix steps are the specification. Completion checks are the
  acceptance tests; put the finding ID (FV-..) in each test title.
- Precedence is plan §2.4. Locate code by symbol; line numbers refer
  to 6cae8104.
- Forward migrations only, except where your entry says otherwise.
  Never guess historical data (D-5).
- Change only this phase's findings. Record other defects under
  "Discovered issues".

Validate remotely only, with the complete CI workflow, exactly as in
abo-remediation-plan.md §2.9: run nothing locally except git, gh and
allowed generators; commit, push, dispatch ci.yml, confirm headSha;
wait without hitting rate limits; green means every campaign passed
apart from unchanged RM00 known failures, and your new tests ran and
passed. Stop after three rounds failing on the same test case.

Stop and report instead of guessing if: a dependency or decision does
not allow the phase; a fix step conflicts with current source; a step
needs a choice this plan does not settle; a step needs an operational
action (implement the code part, list the action under "Operator
checklist"); or gh or CI misbehaves.

Finish per abo-remediation-plan.md §2.11 with the §2.2 substitutions:
completion record docs/review/final-remediation/FR<NN>.md, your §5 row,
docs-only record commit and push. Your final reply lists: findings
implemented, validated commit SHA and CI run URL, deferred steps,
discovered issues and operator checklist items.
```

## 3. Phase overview

| Phase | Area | Title | Findings | Depends on | Decisions |
| --- | --- | --- | --- | --- | --- |
| FR01 | Backend | Membership-based last-administrator guard | FV-M1 | — | — |
| FR02 | Backend | Recoverable role-repair migration | FV-M2 | — | FD-1 |
| FR03 | ABO payment | Operator submission of additional captures | FV-M3 (closes FV-P1) | — | — |
| FR04 | ABO reconciliation | Manual evidence for payout reversals | FV-M4 (closes FV-P2) | — | FD-3 (refund test only) |
| FR05 | ABO scheduler | Detection of never-attempted scheduled periods | FV-P3 | — | FD-2 |
| FR06 | Platform / ops | Launch gate for legacy routing digests | FV-P4 | — | FD-4 |

The phases are independent; run them in numeric order. FR01 and FR02 both touch backend migrations but
different files.

## 4. Phase details

Each entry gives the findings, what to read, the main edit targets, fix steps and completion checks. Every
phase is validated by the complete CI workflow.

### 4.1 Backend

#### 4.1.1 FR01 — Membership-based last-administrator guard

- **Findings:** FV-M1 (Major) — the last-administrator guard checks the global `staff_members.role`, while
  RM02 made the per-organization membership role the authority. A multi-org user can leave an organization
  with no administrator; recovery then needs a manual database fix.
- **Read:** `final-review/stage1-authority-trust.md` §4.1 · `final-review/backend-rls.md` §4.2 · R1 →
  `R1-SQL-04` (membership-role authority)
- **Source:** new migration `backend/supabase/migrations/20261023100000_fv_m1_membership_last_administrator_guard.sql`;
  `auth_internal.assert_not_last_administrator` (latest body `20260613210000_delete_staff_member.sql:43-89`);
  `auth_internal.update_staff_member` (latest body `20261014170400_…membership_sync.sql`); tests in
  `backend/tests/`.
- **Depends on:** —
- **Fix steps:**
  1. Add `auth_internal.assert_not_last_administrator(p_staff_member_id uuid, p_org_id uuid)`:
     `SECURITY DEFINER`, `SET search_path = ''`, and the same grants and revokes as the one-argument form.
     Resolve the target's `user_id` from a non-deleted `public.staff_members` row. If the target's
     `ai_internal.membership.role` for `p_org_id` is not `administrator`, return. Otherwise lock that
     organization's administrator membership rows (`FOR UPDATE`), so two concurrent demotions serialize. Then
     count the other administrator memberships in `p_org_id` whose staff member is active and not deleted. If
     the count is below 1, raise `LAST_ADMINISTRATOR` with `ERRCODE = 'P0002'`, as today, so existing caller
     handlers keep working.
  2. Redefine the one-argument `assert_not_last_administrator(uuid)` with the same signature, so callers and
     ACLs are unchanged. Deactivation and deletion are global, so the new body calls the two-argument form for
     **every** organization where the target holds an `administrator` membership. Remove the `LIMIT 1`
     branch-assignment organization pick.
  3. Redefine `auth_internal.update_staff_member` from its latest definition with one change only. Decide
     whether to run the guard from the target's **locked current-org membership role** (the row locked by the
     `FOR UPDATE` lookup), not `v_target.role`. When it runs, call the two-argument form with the current org.
     Keep the rest of the body identical.
  4. Grep `assert_not_last_administrator` and take the latest definition of each calling function. Known call
     sites are in `20260611170000`, `20260613210000`, `20260614100000` and `20261014170400`. If a caller other
     than `update_staff_member` decides whether to call the guard from `staff_members.role`, redefine it in the
     same migration with only that gating changed. Otherwise leave it unchanged; it now uses the all-org
     one-argument form.
- **Completion checks:**
  1. FV-M1 scenario 1: X is the only administrator membership in org A, and X's global role is `doctor`.
     X demoting themself in A is refused with `LAST_ADMINISTRATOR`, and A's membership is unchanged.
  2. FV-M1 scenario 2: Y has global role `administrator` but membership `doctor` in A. Y is not counted, and
     X's demotion is refused.
  3. Deactivating X from org B, where X is not an administrator, is refused while X is A's only
     administrator.
  4. Single-org regression: demotion succeeds when another administrator membership exists, and the existing
     last-administrator tests still pass.
- **Notes:** never flatten roles across organizations (RM01 rule). The bootstrap exception from R1-SQL-04 is
  unchanged.

#### 4.1.2 FR02 — Recoverable role-repair migration

- **Findings:** FV-M2 (Major). When held rows exist, `20261014170500_r1_sql02_membership_role_repair.sql`
  aborts, and the documented recovery cannot work. The mapping table is created in the same migration, so it
  is rolled back with the abort. Without a transaction, the re-apply fails on `CREATE POLICY`. Every later
  migration then stays unapplied.
- **Read:** `final-review/backend-rls.md` §4.1 · `docs/review/abo-remediation/RM01.md` operator checklist
  (held-row procedure) · R1 → `R1-SQL-02` step 3
- **Source:** new migration `backend/supabase/migrations/20261014170450_fv_m2_membership_role_repair_mapping.sql`;
  edit `20261014170500_r1_sql02_membership_role_repair.sql` (lines 34-53, the mapping-table DDL).
- **Depends on:** — · **Decisions:** FD-1 must say "no".
- **Migration exception:** this phase edits a migration that exists only on the unmerged integration branch.
  This is the only exception to the forward-only rule in this plan, and FD-1 gates it.
- **Fix steps:**
  1. Create `20261014170450_…` with the mapping-table DDL moved from `170500`, made idempotent:
     `CREATE TABLE IF NOT EXISTS ai_internal.membership_role_repair_mapping (…)` (columns identical),
     `ENABLE ROW LEVEL SECURITY`, `DROP POLICY IF EXISTS membership_role_repair_mapping_deny_all` then
     `CREATE POLICY …`, and the same revokes.
  2. In `170500`, remove only that DDL. Keep the repair `DO` block and its held-row abort exactly as they are.
  3. In `FR02.md`, write the corrected operator procedure under "Operator checklist": apply through
     `170450`, run the RM01 reconciliation query, insert approved mappings, then apply `170500` and the rest.
     Add one line to the RM01.md operator checklist pointing to FR02.md. That is the only edit allowed in
     RM01.md.
- **Completion checks:**
  1. Complete CI applies the full migration chain to a fresh database. That proves ordering and that
     `170500` no longer creates the table.
  2. A backend test asserts that `ai_internal.membership_role_repair_mapping` has RLS enabled, has the deny-all
     policy, and grants nothing to `anon`, `authenticated` or `PUBLIC`.
  3. A backend test runs the repair logic with an approved mapping row present and a held-row fixture, and
     asserts that the repair applies the mapping. If the repair body is not callable from a test, record that
     under "Could not verify" and add a scratch-database rehearsal to the operator checklist.

### 4.2 ABO payment and reconciliation

#### 4.2.1 FR03 — Operator submission of additional captures

- **Findings:** FV-M3 (Major), which closes FV-P1 (RM10 R3-C6 partial). `handlePostSubmitTransactionId`
  returns 409 when **any** `paymob_txn` row exists for the checkout. So a second capture whose callback was
  lost can never be recorded, because automatic order enumeration stays off (R-2 gate).
- **Read:** `final-review/stage2-payment-commands.md` §4.1 · R3 → `R3-C6`, `R3-C4` (D-3 operator
  action)
- **Source:** `abo/src/ops/index.ts` (`handlePostSubmitTransactionId`, `insertOperatorAction`);
  `abo/test/system/ops.cross-worker.test.ts`.
- **Depends on:** —
- **Fix steps:**
  1. Replace the any-capture check with an exact check, `SELECT checkout_id FROM paymob_txn WHERE txn_id = ?`.
     If the submitted id is already known for any checkout, return 409 `conflict` as today. New transaction ids
     on checkouts that already have captures proceed. The existing confirm-path order binding still refuses a
     transaction that is not bound to this checkout's order.
  2. Write the `operator_action` row and the `work` insert in **one** `env.DB.batch`. If `insertOperatorAction`
     only runs its statement, add a sibling that returns the prepared statement and use it here. Keep the
     other callers unchanged.
  3. Keep the action label string unchanged. It is catalogued in
     `docs/architecture/ai-billing-orchestration/05-abo-operations-and-traceability.md`. Record under
     "Discovered issues" that the label ("…with no known transaction") is now inaccurate; the docs owner should
     rename it.
  4. Do not change R3-C6 classification in `abo/src/work/runner.ts`. The completion checks prove that it
     handles the second capture.
- **Completion checks:**
  1. FV-M3: capture A arrives by callback and capture B by operator submission on the same checkout. The
     result is two payments, B classified as R3-C6 requires (null-safe likely-duplicate), and grant work per
     R3-C6.
  2. Resubmitting A or B returns 409 and adds no new action or work row.
  3. A submitted id that belongs to another checkout's order is refused, and no payment is recorded.
  4. If the work insert fails, the batch leaves no `operator_action` row behind (use the harness batch-failure
     helper).

#### 4.2.2 FR04 — Manual evidence for payout reversals

- **Findings:** FV-M4 (Major), which closes FV-P2 (RM32 R9-AO2 partial). `checkUnrecordedReversal` matches
  only reversals that carry a `reversal_provider_identity` row. Manual reversals never write one, and the
  Paymob adapter never produces `chargeback`. So every payout chargeback stays an open `unrecorded_reversal`
  finding with daily AL-10 repeats. R9-AO2 step 3 requires it to clear once matching authoritative or manual
  evidence exists. D-5 settles ambiguous rows with an append-only operator fact.
- **Read:** `final-review/stage5-recovery-config.md` §4.1 · R9 → `R9-AO2` · `docs/review/abo-remediation/RM32.md`
  "Deferred and skipped items" and discovered issue (a)
- **Source:** new migration `abo/migrations/0026_payout_reversal_manual_link.sql`; `abo/src/reconciliation/run.ts`;
  `abo/src/ops/index.ts` (new operator action, finding resolution helpers); `abo/src/rebuild.ts`
  (`LEDGER_TABLES` and fact mapping); `abo/test/system/reconciliation.cross-worker.test.ts`.
- **Depends on:** — · **Decisions:** FD-3, for fix step 5 only.
- **Fix steps:**
  1. Migration `0026`: add the append-only table `payout_reversal_manual_basis (import_id, line_no, action_id,
     actor_email, recorded_at)`, primary key `(import_id, line_no)`, with a foreign key to
     `payout_reversal_link` and abort-on-update/delete triggers. Copy the pattern of `0025`.
  2. Add an operator action that links one payout line to one recorded reversal, through the same accepted
     operator-command path the other ABO ops actions use. Refuse unless all of these hold: the line is a
     `refund`/`chargeback` line with a `payout_line_reversal` row (historical lines without one stay
     unmatched under D-5) and no existing link; the reversal exists; `payment_id`, `kind` and
     `amount_minor` are exactly equal; and the reversal is not already linked to another payout line. In one
     batch, write the `payout_reversal_link` row, the `payout_reversal_manual_basis` row, their fact-log
     entries, and the resolution of the line's open `unrecorded_reversal` finding. For the resolution, reuse
     the statements `handlePostResolveFinding` batches, including `prepareAlertDeactivation`.
  3. Leave automatic matching in `matchingProviderReversal` unchanged. Manual evidence is never inferred.
     Update the comment at `run.ts:509-511` so it names the manual link path.
  4. Add both new tables to the rebuild ledger (`abo/src/rebuild.ts` `LEDGER_TABLES`) and fact mapping, like
     `payout_reversal_link`.
  5. Only if FD-3 records the refund-id answer: align Paymob payout normalization with it, and re-enable the
     skipped R9-AO2 refund test (`reconciliation.cross-worker.test.ts`, the `it.skip` near line 2099).
     Otherwise leave the test skipped, and carry "confirm Paymob refund id semantics" to the operator checklist.
- **Completion checks:**
  1. FV-M4: a payout chargeback line with a recorded manual chargeback stays `unrecorded_reversal` until the
     operator links it. After the link, the finding is resolved, AL-10 is inactive, and the next
     reconciliation run neither reopens it nor re-alerts. Rename and rewrite the test that currently asserts
     the finding "remains after a manual chargeback" (near line 2220).
  2. The link is refused for a mismatched payment, kind or amount; for a line that is already linked; and for
     a reversal that is already linked to another line.
  3. An unrelated partial refund still cannot satisfy a chargeback (existing R9-AO2 identity tests pass
     unchanged).
  4. A rebuild reproduces both link tables from facts.
- **Notes:** RM32 discovered issue (b), where a zero-amount reversal line rejects the whole file, remains an
  open maintainer decision and is out of scope.

### 4.3 Conditional phases (owner-accepted deviations)

#### 4.3.1 FR05 — Detection of never-attempted scheduled periods

- **Findings:** FV-P3 (RM31 R9-CRON1 step 2 partial). The minute cron retries only attempted-and-unsuccessful
  periods (`retryOnly`). A never-attempted daily, hourly or six-hour period is never run or flagged; the
  26-hour digest heartbeat is the only external detector.
- **Read:** `final-review/stage5-recovery-config.md` §2 (RM31 row) · `docs/review/abo-remediation/RM31.md`
  "Decision: minute-cron catch-up (safety)" · R9 → `R9-CRON1`
- **Source:** `abo/src/scheduler/jobs.ts`; `abo/src/worker.ts` (minute branch); alert helpers used by
  `scheduled_job_failed`.
- **Depends on:** — · **Decisions:** FD-2 must say `detect`.
- **Fix steps (FD-2 = detect):**
  1. On each minute tick, for each scheduled job, compute the most recent period that should have started by
     now plus a grace window (5 minutes). If `scheduled_job_state` shows that period neither succeeded nor
     attempted, raise the existing `scheduled_job_failed:<job>` alert with a distinct `last_error_code`
     `scheduled_period_missed`. Do **not** start the work. The safety decision in RM31.md stays in force.
  2. The alert clears through the existing success path when the job next succeeds.
- **Completion checks:**
  1. FV-P3: no 06:00 run happens. By 06:06 the minute cron has raised `scheduled_job_failed:daily` with
     `scheduled_period_missed` and has not run the daily work.
  2. The next successful daily run clears the alert.
  3. The existing RM31 test "a never-attempted daily period is not started by the minute cron" still passes.

#### 4.3.2 FR06 — Launch gate for legacy routing digests

- **Findings:** FV-P4 (RM33 R8-PUB1 step 3 partial). Legacy routing rows with `content_sha256 IS NULL` are
  served with an error-level log instead of being quarantined and republished. Quarantine and republish remain
  an operator action.
- **Read:** `final-review/stage5-recovery-config.md` §2 (RM33 row) · `docs/review/abo-remediation/RM33.md`
  operator checklist items 2-3 · R8 → `R8-PUB1`
- **Source:** `ops/launch/launch-check.mjs` and the read-only launch-state reader added by RM35.
- **Depends on:** — · **Decisions:** FD-4 must say `gate`.
- **Fix steps (FD-4 = gate):**
  1. Add a launch-check item that fails when any published or active routing policy row has
     `content_sha256 IS NULL`. Read it through the existing read-only launch path, with no new write
     privileges.
  2. Name the failing policy ids in the check output, and point the operator to the RM33 quarantine and
     republish procedure.
- **Completion checks:**
  1. FV-P4: the launch check fails on a fixture with a NULL-digest published routing row and passes after
     that row is republished with a digest.
  2. Serving behavior is unchanged (log-and-serve stays, as the owner accepted).

## 5. Status tracker

Agents update only their own row. Status values: `not started`, `in progress`, `blocked`, `complete`,
`not required` (set only from a §2.5 decision). `complete` requires a green complete-CI run on the validated
commit.

| Phase | Status | Validated commit | CI run | Completed on | Notes |
| --- | --- | --- | --- | --- | --- |
| FR01 | complete | 1940c38a | [39811302650](https://github.com/haythamosama95/AiClinic/actions/runs/39811302650) | 2026-10-22 | Membership-based guard; no operator actions |
| FR02 | complete | 0b321c34 | [39814585550](https://github.com/haythamosama95/AiClinic/actions/runs/39814585550) | 2026-10-22 | Mapping table moved to 170450; operator rehearsal and procedure in FR02.md |
| FR03 | complete | 59a9fbcf | [39823583374](https://github.com/haythamosama95/AiClinic/actions/runs/39823583374) | 2026-10-22 | Exact txn-id check, action+work in one batch; action label now inaccurate (docs owner) |
| FR04 | not started | | | | Refund test waits on FD-3 |
| FR05 | not started | | | | FD-2 = detect |
| FR06 | not started | | | | FD-4 = gate |

## 6. Post-remediation review gate

1. When FR01–FR06 are `complete` or `not required`, pin the last CI-validated commit as the new review target.
2. Re-run the final-review prompt (`abo-final-review-prompt.md`) as a light pass, scoped to the code changed by
   the FR records. Include the §7.2 observations that touch that code.
3. Carry every FR operator checklist item into the launch-readiness work, together with the RM items.

## 7. Finding-to-phase index

### 7.1 Findings

| ID | Severity | Source report | RM | Phase |
| --- | --- | --- | --- | --- |
| FV-M1 | Major | stage1 M-1, backend-rls M-2 | RM01/RM02 | FR01 |
| FV-M2 | Major | backend-rls M-1 | RM01 | FR02 |
| FV-M3 | Major | stage2 M-1 | RM10 | FR03 |
| FV-M4 | Major | stage5 M-1 | RM32 | FR04 |
| FV-P1 | Partial | stage2 (R3-C6) | RM10 | FR03 (via FV-M3) |
| FV-P2 | Partial | stage5 (R9-AO2) | RM32 | FR04 (via FV-M4) |
| FV-P3 | Partial (owner-accepted) | stage5 (R9-CRON1) | RM31 | FR05 if FD-2 = detect |
| FV-P4 | Partial (owner-accepted) | stage5 (R8-PUB1 step 3) | RM33 | FR06 if FD-4 = gate |

### 7.2 Unverified observations (not findings)

These were noted in the reports as "could not verify" during the light pass. They are inputs to the review
gate (§6), not work items:

- Stage 3: `routePendingGrantClaim` batch does not explicitly condition the `live_value_route` UPDATE on the
  `grant_claim` UPDATE matching (`entrypoint.ts:1281-1302`); no failing scenario was found.
- Stage 2: the RM09 replay path for recovered attempts with a null `client_secret` (after RM28 `0019`).
- Stage 4: whether a held term that moved by transfer can still be released at the destination; the
  deletion dispatcher never sets `lease_until` (possible duplicate AL-18).
- Stage 5: RM34 R8-CONSOLE4 org isolation and concurrent offer publication have no tests.
- Backend: legacy `public.staff_members` writers were not each checked against the R1-SQL-01 UPDATE revoke.
