# ABO integrated review — remediation plan

Status: ready for implementation · Prepared: 2026-10-18 (Africa/Cairo).
Implements the 111 canonical findings of the [integrated source review](abo-integrated-source-review-plan.md)
(0 P0, 57 P1, 52 P2, 2 optional P3) in 38 phases, `RM01`–`RM38`. Track progress in the
[status tracker](#5-status-tracker).

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

Each phase is one bounded agent session. It names the findings to implement, the exact document sections
that contain their fix recipes, the source areas and the hard dependencies. Validation is always the complete
GitHub CI workflow on the pushed commit; nothing runs locally. The
review already chose every remedy; agents implement recipes, they do not redesign them.

### 1.2 Baseline revisions

| Reference | Revision | Meaning |
| --- | --- | --- |
| Review target `T` | `db9244fddfddc1905335fb8c7105328c15a0cc5e` | All line numbers in review reports refer to this tree |
| Remediation base | `ea577f9915d69cda97999512ff8c7f9d0fdbe392` | `master` when this plan was written; decisions D-1…D-6 committed |
| Integration branch | `ai/abo-remediation` | Created from `master` once this plan is committed; every phase commits and pushes here |

Between `T` and the remediation base, only commit `a2545299` changed source: five Flutter billing/AI files
(`administrator_billing_page.dart`, `offers_screen.dart`, `payment_history.dart`, `subscription_summary.dart`,
`ai_page.dart`), the `.arb` inputs with their generated localizations, and new `scripts/start-local.sh`.
Backend, platform, ABO and package source is identical to `T`.

### 1.3 Ordering and deliberate deviations from R10

Phases follow the six-stage order in [R10](abo-integrated/R10-integrated-final-review.md) (section "Canonical
findings, deduplication and implementation order"). Phase numbers are a valid dependency order. Three
deliberate deviations:

1. **R2-C2/C3 server side moves to Stage 1 (RM07).** R4-PG2, R7-A1, R7-T2 and others build on its strict
   DO response decoder; doing it first avoids reworking those consumers. Its Dart part stays in Stage 6 (RM37).
2. **R6 transfer and deletion (DM1/DM2/PT2/PT3) move after term-local accounting (RM26–RM27).** R6-DM1 step 2
   drains reservations using the R5-A1/A2 rules, which must exist first.
3. **R8-PUB1 is split by its two code sites:** routing publication in RM33, offer terms publication in RM34.
   It remains one finding; it is complete only when both phases are complete.

## 2. Rules for implementing agents

These rules apply to every phase. They exist to keep each session focused on its own findings.

### 2.1 One phase per session

Implement exactly one phase per session, strictly in numeric order, on the integration branch
`ai/abo-remediation`. Start only when the previous phase is `complete` in the
[status tracker](#5-status-tracker) and every phase in your **Depends on** line is `complete`. Phases never
run in parallel: CI validates the branch head (rule 2.9), so only one agent may push to the branch at a time.
RM01 starts only after the RM00 baseline row is `complete`.

### 2.2 What to read

Read only the following, in this order:

1. This section (§2) and your own phase entry in §4. Do not read other phase entries, except a dependency's
   completion record (rule 2.11) when you need to reuse what it built.
2. For each finding in your phase, the **recipe sections** listed in the entry's **Read** line. Open the named
   file and search for the finding's key (for example `R1-SQL-01`, `R9-REC1`, `BR1`). Read that heading or table row
   and its fix steps, up to the next finding. Never read a review file end to end.
3. The **architecture sections** listed in the **Read** line, from
   `docs/architecture/ai-billing-orchestration/` (`01`…`05`). Read the named numbered section only.
4. Any further architecture section that a recipe step you are implementing cites explicitly, and only that
   section.
5. The source files named in the recipes and in the entry's **Source** line, plus direct callers and callees
   needed to make the change correctly.
6. When writing tests, the harness table in `06-abo-delivery-plan.md` §3 (V1) and the existing tests next
   to the code you change.

File aliases used in §4 (all under `docs/review/abo-integrated/`):

| Alias | File | Alias | File |
| --- | --- | --- | --- |
| R1 | `R1-tenant-identity-authorization.md` | R6-DM | `R6-do-mutations.md` |
| R2 | `R2-contracts-perimeter-human-approval.md` | R6-PT | `R6-platform-transfer.md` |
| R2-ABO | `R2-abo-review.md` | R6-BR | `R6-abo-reversal.md` |
| R3 | `R3-checkout-confirmed-payment.md` | R6-OPS | `R6-lead-ops.md` |
| R4 | `R4-grants-coverage-term-lifecycle.md` | R7-UI | `R7-desktop_ui-review.md` |
| R5 | `R5-admission-accounting-fallback.md` | R7-TR | `R7-desktop_transport-review.md` |
| R6 | `R6-reversals-transfer-deletion.md` | R7-PS | `R7-platform_sql-review.md` |
| R7 | `R7-feed-projection-desktop-state.md` | R7-LEAD | `R7-lead-review.md` |
| R8 | `R8-operator-control-configuration.md` | R9-LEAD | `R9-lead-review.md` |
| R9 | `R9-durability-recovery-operations.md` | R9-PLAT | `R9-platform-review.md` |
| | | R9-RT | `R9-runtime-review.md` |
| | | R9-AO | `R9-aboops-review.md` |

A **Read** line entry such as `R6 + R6-DM → R6-DM1` means: read the canonical section in `R6`, then the
detailed recipe under the same key in `R6-DM`. Where a slice uses a shorter key, both are shown as
`canonical / slice`, for example `R6-BR1` / `BR1`. R6, R7 and R9 designate their slice reports as the
authoritative detailed recipe, so both are listed. For R1–R5 and R8 the canonical report alone is the recipe.

### 2.3 What not to read

Do not open these unless your phase entry names them:

- Any other file in `docs/review/abo-integrated/`: coverage, manifest, assignment, packet, escalation,
  provenance, region, candidate, checkpoint and start-state files (`.md` and `.json`); other subreports
  (`R1-sql-review.md`, `R2-platform-review.md`, `R3-*-subreport.md`, `R4-*-high-review.md`, `R5-*-medium.md`,
  `R8-*-review.md` and so on). Their provisional recipes are superseded by the canonical reports.
- `R10-integrated-final-review.md` and the R10 evidence files. This plan already encodes their ordering.
- `abo-integrated-source-review-plan.md`, `00-abo-requirements-seed.md`, `06-abo-delivery-plan.md` (except
  §3 V1) and the specs in `specs/061-*` to `specs/098-*`.
- Spec Kit context: the Spec Kit block in `AGENTS.md` and `.cursor/rules/specify-rules.mdc` point at
  unrelated features. Ignore them for remediation work, and do not run Spec Kit specify/clarify/plan. The
  recipe is the specification.
- `docs/testing/catalog/remediation-plan.md`, which is unrelated.

### 2.4 Precedence when sources disagree

1. The constitution (`.specify/memory/constitution.md`): Supabase/PostgreSQL owns domain integrity. Add no new
   services, queues or infrastructure.
2. Decisions D-1…D-6 in `01` §3.8 and the architecture sections they amended.
3. A "Decision 2026-10-18" note inside a report section.
4. The canonical report's finding text and fix steps.
5. The designated detailed recipe (R2-ABO, R6-\*, R7-\*, R9-\* slices). Follow its extra detail. If it
   contradicts levels 1–4 in substance, follow the higher level and record the conflict in your completion record.

Source code is the authority on what currently exists. It is never the authority on the intended behavior.

### 2.5 Locating code

- Review line numbers refer to `T`. Locate code by file and symbol name (function, method, SQL object), then
  confirm the described behavior before editing.
- For the five Flutter files changed in `a2545299`, ignore review line numbers. Re-read the current file and
  apply the recipe to its current structure.
- Earlier remediation phases change shared files (`vendor/entrypoint.ts`, `quota-do/coverage.ts`,
  `abo/src/ops/index.ts`). Expect line drift and use symbols.

### 2.6 Scope discipline

- Implement only your phase's findings. Do not refactor, rename or reformat unrelated code.
- If you find another defect, do not fix it. Add it to the completion record's "Discovered issues" list with
  file, symbol and a one-line description.
- Change architecture docs only where a recipe explicitly says to amend a named section. Amend that section
  in the same phase.
- Generated files (Flutter `app_localizations*.dart`, wrangler types) are regenerated with their tool, never hand-edited.

### 2.7 Cross-phase seams

- **The recipe names a helper, claim, decoder or table from an earlier phase:** reuse it. Read that phase's
  completion record to find it. Do not reimplement it.
- **The recipe names one from a later phase:** implement your own steps so the later phase can plug in.
  Record the seam in your completion record as "Seam for RMxx: …". Do not implement the later finding.
- **A hard dependency is incomplete:** stop (rule 2.10).

### 2.8 Migrations and data

- Forward migrations only. Never edit an applied migration file. Name the new file after the newest existing
  migration in that directory at the time you start: `backend/supabase/migrations/`,
  `ai-platform/migrations/`, `abo/migrations/`.
- Include the compatibility, backfill, upgrade and ordering steps a recipe specifies. Do not skip them because
  production has no data yet; staging and local data exist.
- D-5 applies everywhere: ambiguous historical rows are quarantined, marked disputed and their dependent
  mutation is blocked. Never guess a signer, order, provider correlation, predecessor or value. Never
  hard-delete as repair.
- Where a recipe says "deploy X before Y", order the code and migrations so X lands first within the phase,
  or in an earlier phase.

### 2.9 Tests and remote CI validation

#### 2.9.1 Writing tests

- Turn each finding's **completion checks** into automated tests in the owning harness (`06` §3 V1: H-BK
  backend SQL, H-PKG package, H-AP platform, H-ABO and H-PAY/H-XW ABO, H-FL Flutter, H-FS full stack).
  Put the finding ID in each test title, for example `R1-SQL-01: member cannot update staff role`.
- An existing test may encode the defective behavior. Change it only to the behavior the recipe specifies,
  and name the finding in it. Never delete or weaken a test just to make the suite pass. Do not modify harness
  files marked frozen, such as `backend/tests/catalog/harness.sql` and `run.sh`.

#### 2.9.2 No local execution

Nothing is validated locally. Do not run tests, campaign runners, harnesses, builds, linters, type checks or
dev servers on the local machine. The only local commands allowed are `git`, `gh`, and the code generators
rule 2.6 requires (for example `flutter gen-l10n`, `wrangler types`). Validation is the complete CI workflow
(`.github/workflows/ci.yml`, all jobs) on GitHub, run on the exact commit you pushed.

Prerequisite: `gh` installed and authenticated for `haythamosama95/AiClinic` with permission to dispatch
workflows. If it is not, stop (rule 2.10).

#### 2.9.3 Running CI on your commit

`ci.yml` runs only on manual dispatch, and a dispatch runs the branch head. Phases are sequential on one
branch (rule 2.1), so the head is your commit as long as you verify it:

1. Commit, then record the SHA: `git rev-parse HEAD`.
2. Push: `git push origin ai/abo-remediation`.
3. Dispatch: `gh workflow run ci.yml --repo haythamosama95/AiClinic --ref ai/abo-remediation`.
4. Find the run and confirm it is for your SHA:
   `gh run list --repo haythamosama95/AiClinic --workflow ci.yml --branch ai/abo-remediation --event workflow_dispatch --limit 5 --json databaseId,headSha,status,createdAt`.
   Use the newest run whose `headSha` equals your SHA. If none appears, wait two minutes and list again
   (at most five times); if `headSha` differs, the branch moved: stop (rule 2.10).
5. Wait for it on the polling schedule in §2.9.6. A full run usually takes 8–10 minutes.

#### 2.9.4 Reading the result

- **Green** means every `test-campaign` job concluded `success`, or its only failures are listed as known in
  the RM00 baseline record and are unchanged. The `ci-history` job only reports and does not decide.
- On failure, read `gh run view <run-id> --repo haythamosama95/AiClinic --log-failed`, plus the job summaries.
  If needed, download artifacts to a directory outside the repository with `gh run download <run-id>`.
- A failure that is in the RM00 baseline or the previous phase's validated run, with the same cause, is
  pre-existing. Record it with both run links; do not fix it. Every other failure is yours.
- A failure that looks flaky may be re-checked once by dispatching the complete workflow again on the same
  commit (§2.9.3 steps 3–5). Never re-run only the failed jobs. If the new complete run passes, record the
  flake with both run links in the completion record.
- Fix your failures with a new commit, then repeat §2.9.3. After three CI rounds still failing on the same
  test case, stop (rule 2.10).
- Every phase always runs the complete workflow; no phase selects or skips campaigns. Confirm that the tests
  you added actually ran in their harness's job and passed. A new test that no job executed counts as a
  failure.

#### 2.9.5 RM00 — CI baseline (once, before RM01)

The first agent creates `ai/abo-remediation` from `master` (which must include this plan), pushes it, and runs
§2.9.3 on that commit without code changes. It writes `docs/review/abo-remediation/RM00.md` with the commit
SHA, run URL and every failing test case (the known baseline failures). Then it fills the RM00 row in §5 and
pushes that documentation-only commit (rule 2.11 step 6).

#### 2.9.6 Waiting without hitting GitHub rate limits

Do not use `gh run watch`. It refreshes every 3 seconds by default and reads every job on each refresh,
which exhausts the API rate limit. Instead, check the run with one call:
`gh run view <run-id> --repo haythamosama95/AiClinic --json status,conclusion`, on this schedule:

1. First check 7 minutes after dispatch.
2. If the run is not complete, check again every minute, up to 5 more checks.
3. If it is still not complete 15 minutes after dispatch, stop and report the run URL and the jobs still
   running (rule 2.10). Do not cancel the run or dispatch another.

- Between checks, wait using your environment's wait or sleep facility (for example a background shell or a
  wait tool). Never call the API in a loop without waiting.
- Fetch job details and logs only once, after the run has completed.
- If a call returns HTTP 403 or 429 for rate limiting, check the reset time with
  `gh api rate_limit --jq .resources.core.reset` (this endpoint does not consume quota). Wait until that
  Unix time and resume polling. Do not dispatch a new run because of a rate-limit error.

### 2.10 Stop conditions

Stop, record the reason in the tracker row as `blocked`, and report to the human when:

- a hard dependency is not `complete`;
- a recipe conflicts with current source in a way the recipe did not anticipate (for example, the symbol it
  changes no longer exists or behaves differently);
- a step requires a choice not settled by the recipe text or D-1…D-6;
- a recipe step needs an operational action (key ceremony, secret provisioning, account or monitor setup).
  Implement the code part, list the action under "Operator checklist" in your completion record and do not
  perform it;
- `gh` is missing or unauthenticated, the dispatch fails, or the CI run's `headSha` is not your commit;
- a CI run is still not complete 15 minutes after dispatch (§2.9.6);
- the same test case still fails after three CI rounds (§2.9.4).

Never guess past a stop.

### 2.11 Finishing a phase

1. Check out `ai/abo-remediation` and pull, so you start from the previous phase's final commit.
2. Implement the findings and their tests. Write the completion record
   `docs/review/abo-remediation/RM<NN>.md`, containing:
   - findings implemented, with any recipe step intentionally deferred and why;
   - changed files and symbols, and new migrations in order;
   - tests added or changed, by finding;
   - seams left for later phases, discovered issues, operator checklist items and any precedence conflicts
     (rule 2.4).
3. Commit with message `RM<NN>: <title> (<finding IDs>)`. A phase may use several commits; CI validates the
   last one.
4. Push and run complete CI on that commit (§2.9.3).
5. Read the result (§2.9.4). Repeat steps 2–4 until green, or stop.
6. When green, add the validated SHA, the run URL and any pre-existing or flaky failures to the completion
   record. Update your row in §5 (status `complete`, validated commit, CI run, date, one-line note), changing
   nothing else in this plan. Commit as `RM<NN>: record CI result` and push. This commit changes only
   `docs/review/abo-remediation-plan.md` and `docs/review/abo-remediation/`, so it needs no further CI run.
7. Never merge into `master`, force-push or rewrite pushed history. Merging is the maintainer's decision.

### 2.12 Prompt template

Start each phase in a fresh session with the matching prompt from
[abo-remediation-prompts.md](abo-remediation-prompts.md): the phase prompt for RM01–RM38, and the baseline
prompt for RM00.

## 3. Phase overview

| Phase | Stage | Title | Findings | Depends on |
| --- | --- | --- | ---: | --- |
| RM01 | 1 Authority | Backend staff lifecycle authority | 4 | — |
| RM02 | 1 Authority | Backend org-scoped permission readers | 2 | RM01 |
| RM03 | 1 Authority | Token freshness, issuer validity and tenant cap | 4 | — |
| RM04 | 1 Authority | Platform HP binding and operator bootstrap | 3 | — |
| RM05 | 1 Authority | Console HP binding and browser ceremony | 4 | — |
| RM06 | 1 Authority | Non-development receipt signing key | 1 | — |
| RM07 | 1 Authority | Contract version metadata and strict DO decoders | 2 | — |
| RM08 | 2 Payment | Paymob configuration and evidence atomicity | 3 | — |
| RM09 | 2 Payment | Durable checkout creation | 3 | RM08 |
| RM10 | 2 Payment | Inquiry budget, discovery and multiple captures | 3 | RM08 |
| RM11 | 2 Payment | Desktop checkout flow | 4 | RM09 |
| RM12 | 2 Payment | ABO accepted operator commands and erasure fencing | 3 | RM05 |
| RM13 | 2 Payment | Platform configuration audit and support bounds | 2 | RM03 |
| RM14 | 3 Value | Global grant claims and route seals | 2 | RM07 |
| RM15 | 3 Value | Atomic DO grant commit and durable wake-up | 2 | RM14 |
| RM16 | 3 Value | ABO grant outcomes and receipt linkage | 2 | RM14 |
| RM17 | 3 Value | Accepted complimentary commands and attribution | 2 | RM04, RM14 |
| RM18 | 3 Value | Per-org complimentary and policy ceilings | 2 | RM13, RM17 |
| RM19 | 3 Value | Atomic void, release and suspension events | 2 | RM15 |
| RM20 | 3 Value | Reversal routing | 1 | RM14, RM19 |
| RM21 | 3 Value | ABO reversal evidence and retry | 4 | RM08, RM10, RM12, RM16 |
| RM22 | 4 Accounting | Term-local accounting | 3 | RM15 |
| RM23 | 4 Accounting | Lifecycle placement and catch-up | 3 | RM15, RM22 |
| RM24 | 4 Accounting | Fallback admission | 4 | RM22 |
| RM25 | 4 Accounting | Fallback settlement and usage journal | 4 | RM22, RM24 |
| RM26 | 4 Accounting | Transfer conservation | 3 | RM14, RM17, RM19, RM20, RM22 |
| RM27 | 4 Accounting | Deletion and held status | 2 | RM26 |
| RM28 | 5 Recovery | ABO ledger import and due-work recovery | 4 | RM10, RM16, RM21 |
| RM29 | 5 Recovery | Platform rebuild safety | 2 | RM14, RM15, RM26 |
| RM30 | 5 Recovery | Usage identity across recovery | 2 | RM22, RM25 |
| RM31 | 5 Recovery | Alert delivery and scheduled job health | 5 | RM12, RM13 |
| RM32 | 5 Recovery | Reconciliation and payout imports | 5 | RM12, RM20, RM21, RM31 |
| RM33 | 5 Recovery | Routing configuration integrity | 3 | RM13 |
| RM34 | 5 Recovery | Offer publication and console views | 4 | RM12 |
| RM35 | 5 Recovery | Launch check and external monitoring | 2 | RM31 |
| RM36 | 6 Visible state | Feed projection and coverage reads | 5 | RM07 |
| RM37 | 6 Visible state | Desktop AI identity, status and transport | 4 | RM07 |
| RM38 | 6 Visible state | Desktop billing refresh and notices | 2 | RM11, RM37 |

The Findings column sums to 112 because R8-PUB1 appears in both RM33 and RM34; the plan covers 111 distinct
findings. R2-C3 is counted under RM07 only, although RM37 implements its Dart step.

## 4. Phase details

Each entry lists findings in implementation order. **Read** gives recipe locations (§2.2 aliases) and
architecture sections. **Source** gives the main edit targets; recipes name the exact symbols. Every phase
is validated by the complete CI workflow (§2.9).

### 4.1 Stage 1 — Authority and trust

#### 4.1.1 RM01 — Backend staff lifecycle authority

- **Findings:** R1-SQL-01 (P1) → R1-SQL-03 (P1) → R1-SQL-02 (P1) → R1-SQL-06 (P2)
- **Read:** R1 → `R1-SQL-01`, `R1-SQL-03`, `R1-SQL-02`, `R1-SQL-06` · `01` §3.8 D-1 · `03` §4 · `04` §2.1
- **Source:** new migrations in `backend/supabase/migrations/` (staff_members grants/policy;
  `current_org_id`, `sync_active_organization`, `set_active_organization`; `auth_internal.update_staff_member`;
  `auth_internal.issue_ai_token(integer)`); read-only check of frontend `StaffAdminRepositoryImpl` callers.
- **Depends on:** —
- **Notes:** SQL-01 lands in its own migration before any membership synchronization. SQL-02 step 3 follows
  D-1: run the read-only reconciliation query and save its output in the completion record. The repair
  migration aborts while held rows lack an approved mapping; list held rows under "Operator checklist".
  Never flatten roles across orgs. SQL-03 keeps membership rows (no hard delete).

#### 4.1.2 RM02 — Backend org-scoped permission readers

- **Findings:** R1-SQL-04 (P2) → R1-SQL-05 (P1)
- **Read:** R1 → `R1-SQL-04`, `R1-SQL-05` · `03` §4
- **Source:** new migrations overriding `assert_permission`, `assert_owner_or_administrator`,
  `staff_has_visit_clinical_access`, `staff_has_visit_upload_access`, `staff_can_access_branch`, and the five
  helpers and nine inline readers in the R1-SQL-05 table.
- **Depends on:** RM01
- **Notes:** The R7 handoff in R1-SQL-04 step 4 (auth hook / `build_staff_claims` display role) is out of scope.

#### 4.1.3 RM03 — Token freshness, issuer validity and tenant cap

- **Findings:** R1-C1 (P1) → R1-C3 (P2) → R8-KEY1 (P1) → R1-C2 (P2)
- **Read:** R1 → `R1-C1`, `R1-C3`, `R1-C2` · R8 → `R8-KEY1` · `02` §3.2, §6 · `03` §3.2 · `04` §2.1, §4.1
- **Source:** `packages/vendor-contracts/src/token-claims.ts`; `abo/src/clinic-api/auth.ts`;
  `ai-platform/src/worker.ts` (`verifyFeedBearerToken`, `issuerKeyUsable`); `ai-platform/src/identity/index.ts`;
  `ai-platform/src/vendor/entrypoint.ts` (`registerIssuerKey`, `registerServiceKey`, `retireIssuerKey`);
  new `ai-platform/migrations/` (tenant_binding cap trigger, malformed issuer row cleanup).
- **Depends on:** —
- **Notes:** Keep the custom AI verifier's JSONB compatibility (R1-C1 step 3). R8-KEY1 step 2 refers to the
  AUDIT1 helper, which does not exist yet: batch the guarded transition with the existing audit write, and
  record "Seam for RM13". R1-C3 step 3's operator inventory and K-2 rotation go under "Operator checklist".

#### 4.1.4 RM04 — Platform HP binding and operator bootstrap

- **Findings:** R2-C1 (P2) → R2-P2 (P1) → R2-P3 (P1)
- **Read:** R2 → `R2-C1`, `R2-P2`, `R2-P3` · `01` §3.5 · `02` §3.3 · `04` §1.5
- **Source:** `ai-platform/src/vendor/entrypoint.ts` (`operationParamsMatch`/`stableJson`,
  `verifyCeilingOverrideAssertion`, `bootstrapRegister`).
- **Depends on:** —
- **Notes:** R2-C1 first; R2-P2 reuses its canonical comparison. R2-P2 removes the timestamp-search fallback.

#### 4.1.5 RM05 — Console HP binding and browser ceremony

- **Findings:** R2-P1 (P1) → R2-P4 (P1) → R8-CONSOLE2 (P2) → R8-LEGACY1 (P2)
- **Read:** R2 → `R2-P1`, `R2-P4` · R2-ABO → `R2-ABO-03` (ceremony design detail) · R8 → `R8-CONSOLE2`,
  `R8-LEGACY1` · `01` §3.8 D-2, §3.5 · `02` §1.4 · `04` §1.5, §2.3, §7.1 · `05` §3.2
- **Source:** `abo/src/ops/index.ts` (`verifyHpRequest`, `handleHpPost`, local HP handlers, kill-switch relays);
  new `abo/src/ops/browser/shell.ts` and `ceremony.ts`; `abo/src/worker.ts` routing;
  `packages/vendor-contracts` `operationChallenge` (use only); `ai-platform/package.json`.
- **Depends on:** —
- **Notes:** D-2 is decided and the docs are already amended, so skip R2-P4 step 1. The frozen R2-P1 param maps
  are the exact fields the P4 producer signs. Build the shell, ceremony context, bootstrap page and the local
  approval flows the recipes name; no general console redesign.

#### 4.1.6 RM06 — Non-development receipt signing key

- **Findings:** R9-RT3 (P1)
- **Read:** R9 + R9-RT → `R9-RT3` · `01` §3.8 D-6 · `02` §6 · `05` §6.2
- **Source:** `ai-platform/wrangler.toml` (staging/production vars); receipt key loaders in
  `ai-platform/src/quota-do/coverage.ts` and `ai-platform/src/vendor/entrypoint.ts`.
- **Depends on:** —
- **Notes:** Code only: remove non-development private values and reject the published key fingerprint before
  signing. Secret provisioning and the pin-first K-3 rotation go under "Operator checklist".

#### 4.1.7 RM07 — Contract version metadata and strict DO decoders

- **Findings:** R2-C2 (P2) → R2-C3 (P2, steps 1 and 3 only)
- **Read:** R2 → `R2-C2`, `R2-C3` · `04` §1.1, §1.2, §7.1–§7.3
- **Source:** new backend migration overriding `issue_billing_token(integer)`; `abo/src/ops/index.ts`
  (`verifyOpsAccess`); `ai-platform/src/worker.ts` DO dispatch; `ai-platform/src/vendor/contract-version.ts`;
  `ai-platform/src/vendor/entrypoint.ts` envelopes; `packages/vendor-contracts/src/result-envelope.ts`; every
  DO transport listed in R2-C3 step 1.
- **Depends on:** —
- **Notes:** R2-C2 (receivers) lands before R2-C3 (strict senders). Amend `04` §1.2 for the optional
  `accepted_versions` field as R2-C2 step 3 requires. R2-C3 step 2 (Dart) is RM37; record "Seam for RM37".

### 4.2 Stage 2 — Provider, payment and accepted commands

#### 4.2.1 RM08 — Paymob configuration and evidence atomicity

- **Findings:** R3-C3 (P1) → R3-C5 (P1) → R3-M5 (P2)
- **Read:** R3 → `R3-C3`, `R3-C5`, `R3-M5` · `03` §2.5, §2.9, §2.11 · `04` §5.3
- **Source:** `abo/wrangler.toml`; `abo/src/provider/paymob/client.ts`, `adapter.ts`; `abo/src/work/runner.ts`
  (`recordPaidConfirmation` and the confirm path); `abo/src/notify/intake.ts`; new `abo/migrations/` (work lease token).
- **Depends on:** —
- **Notes:** R3-C5 fences every batch statement with the lease token. Include its step 4 forward recovery pass.

#### 4.2.2 RM09 — Durable checkout creation

- **Findings:** R3-C2 (P1) → R3-M2 (P2) → R3-M3 (P2)
- **Read:** R3 → `R3-C2`, `R3-M2`, `R3-M3` · `01` §3.8 D-3 · `03` §2.3, §2.4, §2.11, §5.1 · `04` §2.2, §2.3, §5.3
- **Source:** `abo/src/clinic-api/checkouts.ts`, `billing-contact.ts`, `rate.ts`, `offers.ts`;
  `abo/src/notify/intake.ts` (notify gate); `abo/src/work/sweep.ts`; new `abo/migrations/`.
- **Depends on:** RM08
- **Notes:** R3-C2 step 4 follows D-3: commit numbered creation attempts before HTTP, and redirect only after
  the result commits. Never hold a D1 transaction across HTTP. If you add the idempotency-conflict clinic error,
  amend the `04` §2.3 error table. The desktop handling of that error is RM11; record "Seam for RM11".

#### 4.2.3 RM10 — Inquiry budget, discovery and multiple captures

- **Findings:** R3-C7 (P1) → R3-C4 (P1) → R3-C6 (P1)
- **Read:** R3 → `R3-C7`, `R3-C4`, `R3-C6` · `01` §3.8 D-3, §7 (R-2) · `03` §2.6, §5.1–§5.2 · `04` §5.1–§5.3 ·
  `05` §3.2, §4
- **Source:** `abo/src/work/inquiry-budget.ts`, `runner.ts`, `sweep.ts`; `abo/src/notify/intake.ts`;
  `abo/src/provider/paymob/adapter.ts`, `client.ts`; `abo/src/ops/index.ts` (new class-H transaction-id action);
  `abo/src/rebuild.ts` inquiry calls (routed through the new budget helper).
- **Depends on:** RM08
- **Notes:** For R3-C4, implement step 1 containment and the D-3 operator-submitted transaction action. Steps
  3–4 automatic order enumeration stay gated on recorded R-2 sandbox evidence: do not implement them, and say
  so in the completion record. R3-C6 processes every bound successful transaction known from callbacks and
  operator submissions.

#### 4.2.4 RM11 — Desktop checkout flow

- **Findings:** R3-C1 (P1) → R3-M4 (P2) → R3-M6 (P2) → R3-M1 (P2), plus the Dart handling from R3-C2 step 2
- **Read:** R3 → `R3-C1`, `R3-M4`, `R3-M6`, `R3-M1`, `R3-C2` (step 2 Dart handling only) · `04` §2.2, §3.4
- **Source:** `frontend/lib/features/ai/billing/` (`administrator_billing_page.dart`, `offers_screen.dart`,
  `billing_contact_form.dart`, `checkout_screen.dart`, `billing_token_client.dart`, `abo_client.dart`).
- **Depends on:** RM09
- **Notes:** `administrator_billing_page.dart` and `offers_screen.dart` changed after `T` (§2.5): apply the
  recipes to the current structure.

#### 4.2.5 RM12 — ABO accepted operator commands and erasure fencing

- **Findings:** R6-O1 (P1) → R8-CONSOLE3 (P2) → R6-O2 (P2)
- **Read:** R6 + R6-OPS → `R6-O1` / `O1`, `R6-O2` / `O2` · R8 → `R8-CONSOLE3` · `04` §1.5 · `05` §3.2 · `03` §2.10, §8
- **Source:** `abo/src/ops/index.ts` (local HP actions, begin-transfer relay, configuration relays);
  `abo/src/notify/intake.ts`; new `abo/migrations/` (accepted command store, erasure generation).
- **Depends on:** RM05
- **Notes:** R6-O1 step 2 refers to R4-A2 receipt linkage (RM16); record "Seam for RM16".

#### 4.2.6 RM13 — Platform configuration audit and support bounds

- **Findings:** R8-AUDIT1 (P2) → R8-SUPPORT1 (P2)
- **Read:** R8 → `R8-AUDIT1`, `R8-SUPPORT1` · `02` §3.3 · `05` §3.1–§3.2
- **Source:** `ai-platform/src/control/audit.ts` and the capability, kill-switch, token-contract, cohort and
  routing handlers; `ai-platform/src/vendor/entrypoint.ts` (`supportLookup`, issuer retire audit from RM03);
  `ai-platform/src/support/index.ts`.
- **Depends on:** RM03
- **Notes:** Move RM03's R8-KEY1 audit batch onto the shared helper. Keep the `inspectCoverage` no-audit exception (081:3).

### 4.3 Stage 3 — Value command conservation

#### 4.3.1 RM14 — Global grant claims and route seals

- **Findings:** R4-PG1 (P1) → R4-PG2 (P1)
- **Read:** R4 → `R4-PG1`, `R4-PG2` · `03` §3.1–§3.2, §5.3 · `04` §1.2–§1.4, §1.6 · `05` §4
- **Source:** new `ai-platform/migrations/` (`grant_claim`); `ai-platform/src/vendor/entrypoint.ts` (`grant`,
  `tryComplimentaryGrantIdempotency`, grant result mapping); `ai-platform/src/quota-do/coverage.ts`
  (`applyGrantRPC`, new `seal_grant_route`); `ai-platform/src/quota-do/index.ts`; Worker RPC dispatch.
- **Depends on:** RM07
- **Notes:** Amend `04` §1.4 validation order with the authenticated-replay exception, as R4-PG1 step 6 says.
  Backfill fails closed under D-5. R4-PG2 uses RM07's decoder classification.

#### 4.3.2 RM15 — Atomic DO grant commit and durable wake-up

- **Findings:** R4-D1 (P1) → R4-D4 (P1)
- **Read:** R4 → `R4-D1`, `R4-D4` · `03` §3.1, §6.7 · `04` §1.4, §1.6
- **Source:** `ai-platform/src/quota-do/coverage.ts` (`applyGrantRPC`, `applyComplimentaryTermGrant`,
  `applyTermAdjustmentGrant`, `finalizeGrantApply`, `scheduleCoverageAlarm`, `syncAlarm`);
  `ai-platform/src/quota-do/index.ts` caller.
- **Depends on:** RM14
- **Notes:** Include R4-D1's final-state event snapshot rule (paragraph after its fix steps).

#### 4.3.3 RM16 — ABO grant outcomes and receipt linkage

- **Findings:** R4-A1 (P1) → R4-A2 (P2)
- **Read:** R4 → `R4-A1`, `R4-A2` · `03` §2.8, §5.3 · `04` §1.6 · `05` §4
- **Source:** new `abo/migrations/` (`grant_outcome_event`, legacy table, compatibility view);
  `abo/src/work/grant.ts`; `abo/src/ops/index.ts` (`handlePostComplimentaryGrant`, `recordComplimentaryGrantRows`);
  `abo/src/rebuild.ts` (`replayLedger`); the view's receivers named in R4-A1 step 3.
- **Depends on:** RM14
- **Notes:** The receipt validator from R4-A2 step 2 is reused later by RM12's seam, RM21 and RM32.

#### 4.3.4 RM17 — Accepted complimentary commands and attribution

- **Findings:** R4-PG3 (P2) → R4-PG4 (P1)
- **Read:** R4 → `R4-PG3`, `R4-PG4` · `01` §3.5 · `02` §3.3 · `04` §1.4–§1.5
- **Source:** `ai-platform/src/vendor/entrypoint.ts` (`finishHpAssertion`, complimentary/adjustment branch,
  `listGrants`, `listGrantsForVoid`); `grant_claim` extension migration; five-minute scheduled path in
  `ai-platform/src/worker.ts`; `ai-platform/src/quota-do/coverage.ts` ledger outbox credential.
- **Depends on:** RM04, RM14
#### 4.3.5 RM18 — Per-org complimentary and policy ceilings

- **Findings:** R4-D5 (P2) → R8-CEILING1 (P2)
- **Read:** R4 → `R4-D5` · R8 → `R8-CEILING1` · `03` §3.2 · `04` §1.3–§1.4
- **Source:** new `ai-platform/migrations/` (per-org ceiling claims, `ceiling_policy_command`);
  `ai-platform/src/vendor/entrypoint.ts` (complimentary authorization, `setCeilingPolicy`);
  `ai-platform/src/quota-do/coverage.ts` (`windowGrantRows`, `grantExceedsCeiling`).
- **Depends on:** RM13, RM17
- **Notes:** The R4-D5 recovered-envelope addendum in R9-PLAT belongs to RM29.

#### 4.3.6 RM19 — Atomic void, release and suspension events

- **Findings:** R6-DM3 (P1) → R6-DM5 (P2)
- **Read:** R6 + R6-DM → `R6-DM3`, `R6-DM5` · `03` §5.5, §6.1–§6.4, §6.7 · `04` §1.3, §1.6
- **Source:** `ai-platform/src/quota-do/coverage.ts` (reversal, release and manual void paths; suspension event emission).
- **Depends on:** RM15
- **Notes:** Reuse RM15's commit helper and wake-up repair. R6-DM3's "R5 original-term used_final" uses
  whatever rule exists now. RM22 aligns these paths with the settled-only rule.

#### 4.3.7 RM20 — Reversal routing

- **Findings:** R6-PT1 (P1)
- **Read:** R6 + R6-PT → `R6-PT1` · `03` §2.7, §3.2, §5.5 · `04` §1.3, §1.6
- **Source:** `ai-platform/src/vendor/entrypoint.ts` (`voidForReversal` routing and tombstones); `grant_claim`
  extension migration; DO seals in `ai-platform/src/quota-do/coverage.ts`.
- **Depends on:** RM14, RM19
#### 4.3.8 RM21 — ABO reversal evidence and retry

- **Findings:** R6-BR1 (P1) → R6-BR3 (P2) → R6-BR2 (P1) → R8-RETRY1 (P2)
- **Read:** R6 + R6-BR → `R6-BR1` / `BR1`, `R6-BR3` / `BR3`, `R6-BR2` / `BR2` · R8 → `R8-RETRY1` · `01` §3.8 D-3 ·
  `03` §2.7, §5.5 · `04` §5.2–§5.3 · `05` §4
- **Source:** `abo/src/provider/paymob/adapter.ts` (reversal normalization); `abo/src/work/reversal.ts`,
  `inquiry-budget.ts`, `sweep.ts`; `abo/src/ops/index.ts` (`handlePostRetry`); new `abo/migrations/` (`reversal_request`).
- **Depends on:** RM08, RM10, RM12, RM16
- **Notes:** R6-BR1 follows D-3: full reversal only from the authenticated original-parent cumulative, otherwise
  `review_partial` plus an alert.

### 4.4 Stage 4 — Accounting, lifecycle, transfer and deletion

#### 4.4.1 RM22 — Term-local accounting

- **Findings:** R5-A1 (P1) → R5-A2 (P1) → R5-A7 (P2)
- **Read:** R5 → `R5-A1`, `R5-A2`, `R5-A7` · `03` §6.2–§6.4
- **Source:** `ai-platform/src/quota-do/index.ts` (`admitOnHotRow`, `endGraceIfExhausted`, `releaseOnHotRow`,
  settlement and idempotency storage); calendar producers in `ai-platform/src/quota-do/coverage.ts`.
- **Depends on:** RM15
- **Notes:** R5-A2 step 3 also aligns RM19's reversal/void/release paths with the settled-only rule.

#### 4.4.2 RM23 — Lifecycle placement and catch-up

- **Findings:** R4-D3 (P1) → R4-D2 (P1) → R6-DM4 (P1)
- **Read:** R4 → `R4-D3`, `R4-D2` · R6 + R6-DM → `R6-DM4` · `03` §5.4, §6.1, §6.3–§6.4, §6.8
- **Source:** `ai-platform/src/quota-do/coverage.ts` (`applyGrantRPC` placement, `applyComplimentaryTermGrant`,
  `applyDueBoundaries`, held release).
- **Depends on:** RM15, RM22
- **Notes:** Include R4-D2 step 3's explicit recovery action for already-stranded terms.

#### 4.4.3 RM24 — Fallback admission

- **Findings:** R5-ADM1 (P1) → R5-ADM3 (P2) → R5-A4 (P1) → R5-ADM2 (P2)
- **Read:** R5 → `R5-ADM1`, `R5-ADM3`, `R5-A4`, `R5-ADM2` · `01` §3.8 D-4 · `02` §4.4 · `03` §6.5–§6.6 · `04` §4.2
- **Source:** `ai-platform/src/admission/index.ts`, `pipeline/index.ts`, `worker.ts`, router;
  mirror projection/parser in `ai-platform/src/quota-do/coverage.ts`; new `ai-platform/migrations/`
  (`fallback_admission.jti`).
- **Depends on:** RM22
- **Notes:** R5-ADM3 follows D-4. Keep `coverage_unknown` containment until the `jti` storage ships in this phase.

#### 4.4.4 RM25 — Fallback settlement and usage journal

- **Findings:** R5-A3 (P1) → R5-A6 (P2) → R5-A5 (P1) → R5-J1 (P2)
- **Read:** R5 → `R5-A3`, `R5-A6`, `R5-A5`, `R5-J1` · `03` §6.5–§6.7 · `05` §4
- **Source:** `ai-platform/src/credit/index.ts`; fallback settlement in `ai-platform/src/quota-do/index.ts`;
  `ai-platform/src/journal/index.ts`; Worker terminal paths in `ai-platform/src/worker.ts`.
- **Depends on:** RM22, RM24
#### 4.4.5 RM26 — Transfer conservation

- **Findings:** R6-DM1 (P1) → R6-DM2 (P1) → R6-PT2 (P1)
- **Read:** R6 + R6-DM → `R6-DM1`, `R6-DM2` · R6 + R6-PT → `R6-PT2` · `03` §3.1–§3.3, §7–§8 · `04` §1.3 · `05` §3.2
- **Source:** transfer out/in in `ai-platform/src/quota-do/coverage.ts`; `ai-platform/src/coverage/transfer.ts`
  (begin, receivers); new `ai-platform/migrations/`.
- **Depends on:** RM14, RM17, RM19, RM20, RM22
#### 4.4.6 RM27 — Deletion and held status

- **Findings:** R6-PT3 (P1) → R7-PS1 (P2)
- **Read:** R6 + R6-PT → `R6-PT3` · R7 + R7-PS → `R7-PS1` · `03` §3.2, §5.7, §8 · `04` §1.3, §1.7
- **Source:** deletion in `ai-platform/src/coverage/transfer.ts`; `setTransferPending` and snapshot selection
  in `ai-platform/src/quota-do/coverage.ts`; `deleteInstallation` in `ai-platform/src/vendor/entrypoint.ts`.
- **Depends on:** RM26
### 4.5 Stage 5 — Recovery, detection and configuration

#### 4.5.1 RM28 — ABO ledger import and due-work recovery

- **Findings:** R9-REC1 (P1) → R9-FACT1 (P1) → R9-REC3 (P1) → R9-REC2 (P1)
- **Read:** R9 + R9-LEAD → `R9-REC1`, `R9-FACT1`, `R9-REC3`, `R9-REC2` · `01` §3.8 D-3, D-5 · `03` §1, §2.1, §2.10, §8 ·
  `05` §4, §5.1
- **Source:** `abo/src/rebuild.ts` and its rebuild script; `abo/src/records/`; append helpers used by
  `abo/src/work/runner.ts` and `abo/src/notify/intake.ts`; new `abo/migrations/`.
- **Depends on:** RM10, RM16, RM21
- **Notes:** R9-REC1 includes pinning the rebuild launcher (the unpinned `tsx` noted in R9). R9-REC2 never
  creates a new provider order; missing correlation stays disputed per D-3/D-5.

#### 4.5.2 RM29 — Platform rebuild safety

- **Findings:** R9-PDO1 (P1) → R9-PD1 (P1), plus the R4-D5 recovered-envelope addendum
- **Read:** R9 + R9-PLAT → `R9-PDO1`, `R9-PD1`, "Inherited R4-D5 recovery addendum" · R6 + R6-DM → `R6-DM5`
  (step 2 historical aliases only) · `03` §3.1–§3.3 · `05` §5.2–§5.3
- **Source:** rebuild sections of `ai-platform/src/quota-do/coverage.ts` (`rebuildClinicDoRPC` and helpers);
  rebuild methods in `ai-platform/src/vendor/entrypoint.ts`.
- **Depends on:** RM14, RM15, RM26
- **Notes:** Rebuild must preserve RM14 claims/seals, RM17 accepted commands, RM18 ceiling claims and RM26
  transfer step records. Read their completion records.

#### 4.5.3 RM30 — Usage identity across recovery

- **Findings:** R9-PUS1 (P1) → R9-PRET1 (P1)
- **Read:** R9 + R9-PLAT → `R9-PUS1`, `R9-PRET1` · `03` §6.2, §6.7, §8 · `05` §5.2
- **Source:** DO accounting sequence and snapshot watermark in `ai-platform/src/quota-do/`; journal retention
  and purge; new `ai-platform/migrations/` (usage accounting identity).
- **Depends on:** RM22, RM25
#### 4.5.4 RM31 — Alert delivery and scheduled job health

- **Findings:** R9-PAL1 (P1) → R9-CRON1 (P1) → R9-AO4 (P2) → R9-AO5 (P2) → R9-AO6 (P2)
- **Read:** R9 + R9-PLAT → `R9-PAL1` · R9 + R9-LEAD → `R9-CRON1` · R9 + R9-AO → `R9-AO4`, `R9-AO5`, `R9-AO6` ·
  `02` §5 · `05` §1, §2
- **Source:** alert outbox in `ai-platform/src/quota-do/coverage.ts`; alert dispatcher and cron in
  `ai-platform/src/worker.ts` / `ai-platform/src/alert/index.ts`; `abo/src/worker.ts` cron; `abo/src/alert/index.ts`;
  `abo/src/reconciliation/run.ts` (finding commit); `abo/src/housekeeping/run.ts`; watch handlers; new migrations
  (job state, `finding_identity`).
- **Depends on:** RM12, RM13
- **Notes:** R9-CRON1 introduces per-stream heartbeats that RM35 relies on.

#### 4.5.5 RM32 — Reconciliation and payout imports

- **Findings:** R9-AO1 (P2) → R9-AO3 (P2) → R9-AO7 (P2) → R9-AO2 (P2) → R9-AO8 (P3, optional)
- **Read:** R9 + R9-AO → `R9-AO1`, `R9-AO3`, `R9-AO7`, `R9-AO2`, `R9-AO8` · `01` §3.8 D-5 · `03` §2.10 · `05` §3.3
- **Source:** `abo/src/reconciliation/run.ts`; provider port `PayoutLine` and Paymob payout normalization;
  `abo/src/ops/index.ts` (payout import and list); new `abo/migrations/`.
- **Depends on:** RM12, RM20, RM21, RM31
#### 4.5.6 RM33 — Routing configuration integrity

- **Findings:** R8-ROUTE1 (P1) → R8-PUB1 (P1, routing site) → R8-ROLLBACK1 (P2)
- **Read:** R8 → `R8-ROUTE1`, `R8-PUB1`, `R8-ROLLBACK1` · `03` §3.2–§3.3 · `05` §3.2
- **Source:** `ai-platform/src/control/routing-policy.ts`; `ai-platform/src/router/index.ts` (shared parser);
  `ai-platform/src/config-cache/index.ts`; new `ai-platform/migrations/` (`content_sha256`, activation generation).
- **Depends on:** RM13
- **Notes:** Implement only the routing half of R8-PUB1; the terms half is RM34.

#### 4.5.7 RM34 — Offer publication and console views

- **Findings:** R8-PUB1 (P1, offer terms site) → R8-CONSOLE5 (P2) → R8-CONSOLE1 (P2) → R8-CONSOLE4 (P2)
- **Read:** R8 → `R8-PUB1`, `R8-CONSOLE5`, `R8-CONSOLE1`, `R8-CONSOLE4` · `03` §2.2 · `04` §2.2 · `05` §3.1–§3.2
- **Source:** `abo/src/ops/index.ts` (publish/reinstate offer, clinic action history); `abo/src/clinic-api/offers.ts`,
  `checkouts.ts`.
- **Depends on:** RM12
- **Notes:** Implement only the terms half of R8-PUB1. R8-PUB1 is complete once RM33 and RM34 are both complete.

#### 4.5.8 RM35 — Launch check and external monitoring

- **Findings:** R9-RT1 (P1) → R9-RT2 (P1)
- **Read:** R9 + R9-RT → `R9-RT1`, `R9-RT2` · `01` §3.8 D-6 · `02` §5 · `05` §1, §6.2
- **Source:** `ops/launch/launch-check.mjs`; `ops/staging/audit-watcher.mjs`, `heartbeat-monitor.mjs`;
  heartbeat calls in `abo/src/worker.ts` and `ai-platform/src/alert/index.ts`.
- **Depends on:** RM31
- **Notes:** Read-only API tokens, monitor accounts and the outside-account scheduler go under "Operator checklist".

### 4.6 Stage 6 — Projection and visible state

#### 4.6.1 RM36 — Feed projection and coverage reads

- **Findings:** R7-A1 (P2) → R7-PS2 (P2) → R7-PS3 (P2) → R7-PS4 (P2) → R7-A2 (P2)
- **Read:** R7 + R7-LEAD → `R7-A1`, `R7-A2` · R7 + R7-PS → `R7-PS2`, `R7-PS3`, `R7-PS4` · `03` §4, §5.7 ·
  `04` §1.7, §3.1–§3.3, §4.1
- **Source:** `abo/src/coverage/view.ts`, `abo/src/worker.ts`, `abo/src/clinic-api/billing-reads.ts`; snapshot
  builder in `ai-platform/src/quota-do/coverage.ts`; `ai-platform/src/coverage-read/index.ts`; new backend
  migration overriding `auth_internal.request_ai_status_refresh(integer)`.
- **Depends on:** RM07
#### 4.6.2 RM37 — Desktop AI identity, status and transport

- **Findings:** R7-UI1 (P1) → R7-T1 (P2) → R7-T2 (P2) → R7-T3 (P2) → R2-C3 (step 2, Dart)
- **Read:** R7 + R7-UI → `R7-UI1` · R7 + R7-TR → `R7-T1` / `T1`, `R7-T2` / `T2`, `R7-T3` / `T3` · R2 → `R2-C3`
  (step 2) · `04` §3.2–§3.4, §4.2, §7.2
- **Source:** `frontend/lib/features/ai/presentation/pages/ai_page.dart`; `host/ai_feature_host_page.dart`;
  `surface/first_ai_feature_surface.dart`; `frontend/lib/app/providers/ai_shell_status_provider.dart`;
  `frontend/lib/core/ai/usage_summary_client.dart`, `https_submit_port.dart`, `discovery_client.dart`,
  `supabase_aat_mint_port.dart`; `frontend/lib/core/rpc/rpc_result.dart`; the billing readers named in R2-C3 step 2.
- **Depends on:** RM07
- **Notes:** `ai_page.dart` changed after `T` (§2.5). Do UI1's identity guard before T2 unmasks live administrator data.

#### 4.6.3 RM38 — Desktop billing refresh and notices

- **Findings:** R7-UI2 (P2) → R7-UI3 (P3, optional)
- **Read:** R7 + R7-UI → `R7-UI2`, `R7-UI3` · `04` §2.2, §3.2, §3.4
- **Source:** `frontend/lib/features/ai/billing/administrator_billing_page.dart`, `checkout_screen.dart`,
  `commercial_notices.dart`, `payment_history.dart`, `subscription_summary.dart`; `ai_feature_host_page.dart`
  notice rendering; `frontend/lib/l10n/app_en.arb`, `app_ar.arb`.
- **Depends on:** RM11, RM37
- **Notes:** Several of these files changed after `T` (§2.5). Edit `.arb` inputs only and regenerate localizations.

## 5. Status tracker

Agents update only their own row (rule 2.11). Status values: `not started`, `in progress`, `blocked`, `complete`.
`complete` requires a green complete-CI run on the validated commit (§2.9.4). All work is on `ai/abo-remediation`.

| Phase | Status | Validated commit | CI run | Completed on | Notes |
| --- | --- | --- | --- | --- | --- |
| RM00 | complete | `5aefe777a0266c0e6b6de1fdf6598a2476e69de0` | [39104988439](https://github.com/haythamosama95/AiClinic/actions/runs/39104988439) | 2026-10-18 | CI baseline, no code changes (§2.9.5); 2 known failures: `backend/all` `appointments_patient_mrn_payload_test.sql`, `ai-platform/workers` `E2E-P3.9-01 FM-06 DO failure admits via fallback and */5 charges once` |
| RM01 | complete | `979b9246ff497ce2b869679d8856b45f58742b8d` | [39116772595](https://github.com/haythamosama95/AiClinic/actions/runs/39116772595) | 2026-10-18 | 4 findings implemented (SQL-01 → SQL-03 → SQL-02 → SQL-06); new `Staff authority RM01` test passed 20/20 in `backend/all`; test-fixture commits `79a37765`/`979b9246` on top of `bec38fee`; see docs/review/abo-remediation/RM01.md |
| RM02 | not started | — | — | — | — |
| RM03 | not started | — | — | — | — |
| RM04 | not started | — | — | — | — |
| RM05 | not started | — | — | — | — |
| RM06 | not started | — | — | — | — |
| RM07 | not started | — | — | — | — |
| RM08 | not started | — | — | — | — |
| RM09 | not started | — | — | — | — |
| RM10 | not started | — | — | — | — |
| RM11 | not started | — | — | — | — |
| RM12 | not started | — | — | — | — |
| RM13 | not started | — | — | — | — |
| RM14 | not started | — | — | — | — |
| RM15 | not started | — | — | — | — |
| RM16 | not started | — | — | — | — |
| RM17 | not started | — | — | — | — |
| RM18 | not started | — | — | — | — |
| RM19 | not started | — | — | — | — |
| RM20 | not started | — | — | — | — |
| RM21 | not started | — | — | — | — |
| RM22 | not started | — | — | — | — |
| RM23 | not started | — | — | — | — |
| RM24 | not started | — | — | — | — |
| RM25 | not started | — | — | — | — |
| RM26 | not started | — | — | — | — |
| RM27 | not started | — | — | — | — |
| RM28 | not started | — | — | — | — |
| RM29 | not started | — | — | — | — |
| RM30 | not started | — | — | — | — |
| RM31 | not started | — | — | — | — |
| RM32 | not started | — | — | — | — |
| RM33 | not started | — | — | — | — |
| RM34 | not started | — | — | — | — |
| RM35 | not started | — | — | — | — |
| RM36 | not started | — | — | — | — |
| RM37 | not started | — | — | — | — |
| RM38 | not started | — | — | — | — |

## 6. Post-remediation review gate

Completing a phase does not mark its findings as fixed. A finding is fixed only after the follow-up review:

1. When all phases are complete (or at a stage boundary the maintainer chooses), pin the last CI-validated
   commit on `ai/abo-remediation`, or `master` after the maintainer merges it, as the new review target.
2. Review each changed region listed in the completion records, plus the affected cross-component seams,
   following `abo-integrated-source-review-plan.md` §6 ("If fixes are later authorized, record a new target and
   review each changed region plus affected seams").
3. Carry every "Operator checklist" item from the completion records into the launch-readiness work. This plan
   does not perform operational actions.

## 7. Finding-to-phase index

Use this to find where a finding referenced by your recipe is implemented.

| Report | Findings → phase |
| --- | --- |
| R1 | SQL-01, SQL-02, SQL-03, SQL-06 → RM01 · SQL-04, SQL-05 → RM02 · C1, C2, C3 → RM03 |
| R2 | C1, P2, P3 → RM04 · P1, P4 → RM05 · C2, C3 (steps 1, 3) → RM07 · C3 (step 2) → RM37 |
| R3 | C3, C5, M5 → RM08 · C2, M2, M3 → RM09 · C4, C6, C7 → RM10 · C1, M1, M4, M6 → RM11 |
| R4 | PG1, PG2 → RM14 · D1, D4 → RM15 · A1, A2 → RM16 · PG3, PG4 → RM17 · D5 → RM18 · D2, D3 → RM23 |
| R5 | A1, A2, A7 → RM22 · ADM1, ADM2, ADM3, A4 → RM24 · A3, A5, A6, J1 → RM25 |
| R6 | O1, O2 → RM12 · DM3, DM5 → RM19 · PT1 → RM20 · BR1, BR2, BR3 → RM21 · DM4 → RM23 · DM1, DM2, PT2 → RM26 · PT3 → RM27 |
| R7 | PS1 → RM27 · A1, A2, PS2, PS3, PS4 → RM36 · UI1, T1, T2, T3 → RM37 · UI2, UI3 → RM38 |
| R8 | KEY1 → RM03 · CONSOLE2, LEGACY1 → RM05 · CONSOLE3 → RM12 · AUDIT1, SUPPORT1 → RM13 · CEILING1 → RM18 · RETRY1 → RM21 · ROUTE1, ROLLBACK1, PUB1 (routing) → RM33 · PUB1 (terms), CONSOLE1, CONSOLE4, CONSOLE5 → RM34 |
| R9 | RT3 → RM06 · REC1, REC2, REC3, FACT1 → RM28 · PDO1, PD1 → RM29 · PUS1, PRET1 → RM30 · PAL1, CRON1, AO4, AO5, AO6 → RM31 · AO1, AO2, AO3, AO7, AO8 → RM32 · RT1, RT2 → RM35 |
