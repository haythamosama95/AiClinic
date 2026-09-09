# Silent-Workaround Sweep — SQL Track (Stages 02, 06, SQL halves of 08 & 11)

**Date:** 2026-09-06. **Branch:** `ai/master` @ HEAD.
**Scope:** the Supabase/PostgreSQL half of the catalog — `backend/tests/catalog/`
(`harness.sql`, `harness-smoke.sql`, `stage-02-availability-and-enroll.sql`,
`stage-02-revoke-rotate-availability.sql`, `stage-06-issuer-guards.sql`,
`stage-06-happy-path-and-lifecycle.sql`, `stage-06-verify-and-handoff.sql`,
`stage-08-context-provider-rpc.sql`, `stage-11-record-ai-acceptance.sql`) vs
`docs/testing/catalog/stage-02-clinic-keypair.md` (S02-001…027),
`stage-06-minting-an-aat.md` (S06-001…047),
`stage-08-request-ingress.md` §context-provider (S08-061…069),
`stage-11-terminal-settlement.md` §acceptance (S11-022…029).

**Method.** Read `implementation-audit-findings.md` first, then every report under
`backend/tests/catalog/reports/` (phase-00-sql-harness, sql-track-conflict-check,
stage-02/06/08/11 + failures + conflicts), then each SQL test file line by line,
comparing every scenario's assertions against its catalog "Expected outcome" +
"Side effects". Source-of-truth order: architecture docs → `remediation-plan.md` →
catalog chapters → migrations (verified against migration text before any CODE BUG
call). `[SEED]` blocks were checked for whether a real public RPC could have
produced the same state.

**Exclusions (already adjudicated in `implementation-audit-findings.md`, not
re-reported):** S02-024 `created_by` (BUG-09), S02-027 (K0→K3), stage-06 username
dots→underscores, AAT lifetime 600-vs-900 (C-03), S06-019 fingerprint weakening
*as recorded* (but re-judged per task — see §2.1.1), S06-026 fallback, S06-033
SQLSTATE 22023, S08-069 REVOKE (BUG-10), S11-027 (T0−1s stale), S11-028 (one-arg
stub), S11-029 (schema-level deny), BUG-01…BUG-11 generally.

**Coverage identity (verified mechanically — every ID grepped for a `record(...)`
call):** S02-001…027, S06-001…047, S08-061…069, S11-022…029 — **all present, no
catalog ID lacks a SQL assertion.** The S08-061/062/067 Worker-ingress POST halves
are Worker scenarios (covered by the E2E track), not SQL gaps.

## 1. Stage 02 — Clinic keypair & availability (S02-001…027)

### 1.1 Findings

#### 1.1.1 S02-024 — "readable by every authenticated role" checked for one role only

- **Test:** `backend/tests/catalog/stage-02-revoke-rotate-availability.sql:849-857`
- **Catalog expectation:** "`public.get_ai_availability()` … returns
  `{"enabled": false}` — readable by every authenticated role (doctor,
  receptionist, administrator alike)" (`stage-02-clinic-keypair.md` S02-024).
- **Actual assertion:** `get_ai_availability()` is exercised as DOCTOR only; no
  receptionist/administrator read is attempted. (The `created_by` half of this
  scenario is the recorded BUG-09 conflict and is excluded here.)
- **VERDICT:** WEAK TEST. **SEVERITY:** LOW.
- **Evidence:** single-role call at
  `stage-02-revoke-rotate-availability.sql:850-856`; the function is
  `SECURITY DEFINER` with no role branching
  (`20260905120100_set_ai_availability.sql:14-26`), so cross-role divergence is
  near-impossible — hence LOW.
- **Fix brief:** Add two cheap reads (receptionist, administrator) asserting the
  same envelope, or record the single-role choice in `stage-02-conflicts.md`. The
  function has no role-dependent code path, so this is completeness, not a real
  hole.

### 1.2 Stage-02 items checked and cleared

- **S02-001/002/003/007/008** — role-gate, RAISE-vs-envelope, and `FORBIDDEN`
  message assertions all match the catalog; the `FORBIDDEN`-vs-`ROLE_FORBIDDEN`
  branch distinction (is_active filter → NOT FOUND) is code-verified, and the
  catalog's own text concedes the message does not identify the branch.
- **S02-009/013/014/015** — keystore row assertions (kid, valid_from, revoked_at,
  updated_at set/unchanged), ledger/audit/app_settings no-write fingerprints, and
  idempotent re-revoke exact-equality checks all match the catalog. The
  payload-vs-row `clock_timestamp()` drift is sanctioned by catalog doc-drift #4
  and BUG-11 (excluded); the test is neutral to it (asserts both ≈ now ±5 s), so
  it does not pin the bug.
- **S02-018/022/023/025** — every `[SEED]` is catalog-prescribed (ghost
  installation_id, orphaned ledger rows, legacy NULL-installation key, ledger
  backdate); each is followed by the real RPC call the catalog names.
- **S02-024 setup simulation of stage 3** (direct INSERT of `ai.availability`)
  is disclosed in `reports/stage-02.md` and justified: the write RPC
  `set_ai_availability` did not exist when the catalog was written (C-16).
- **S02-026** — the full-matrix `is_granted=false` rows are asserted visible to
  ADMIN; the catalog's parenthetical about RLS hiding them from non-admins is not
  separately exercised, but the scenario's action is explicitly "As ADMIN".
- **BEGIN/ROLLBACK isolation:** transaction-stable `now()` does not hide anything
  here — S02-013/014/015's `updated_at` NULL/NOT-NULL/unchanged assertions remain
  meaningful because they compare against K0's pre-revoke state, not wall time.

## 2. Stage 06 — Minting an AAT (S06-001…047)

### 2.1 Findings

#### 2.1.1 S06-019 — "mint writes ONLY ai_token_issuance" fingerprints still leak UPDATEs (re-judged per task)

- **Test:** `backend/tests/catalog/stage-06-happy-path-and-lifecycle.sql:480-506`
  (before), `536-558` (after), `608-611` (comparisons)
- **Catalog expectation:** "No writes to `installation_keys`, `app_settings`,
  `audit_log`, or any `public.*` table — the issuer does not audit-log mints"
  (`stage-06-minting-an-aat.md` S06-019 Side effects).
- **Actual assertion:** `installation_keys` fingerprint = md5 over
  `kid|revoked_at|updated_at`; `app_settings` fingerprint = md5 over
  `key|value_json|updated_at`; `audit_log` = row count; the five `public.*`
  tables = **row counts only**. The recorded conflict (stage-06-conflicts.md §3)
  documents that `xmax` and `max(updated_at)` were dropped; this sweep's job is
  to judge the remainder.
- **VERDICT:** WEAK TEST. **SEVERITY:** MEDIUM.
- **Evidence:** partial-column hashes at
  `stage-06-happy-path-and-lifecycle.sql:484-505`; count-only public checks at
  `540-558`. The issuer's only write is one INSERT into the ledger
  (`20260801120200_ai_token_issuer_rpc.sql:273-289`). Dropping `xmax` was
  *correct* — the ledger's FK to `staff_members` takes a KEY SHARE lock on the
  actor's row during the INSERT, legitimately moving `xmax` and guaranteeing
  false positives.
- **Fix brief:** The remaining assertions still catch any INSERT/DELETE anywhere
  and UPDATEs of the safety-critical columns (`revoked_at`, `value_json`), but
  miss UPDATEs of non-fingerprinted columns (`secret_key`, `is_deleted`,
  `deleted_at`, `valid_from`) and *any* UPDATE of a `public.*` row. A stronger
  legitimate assertion exists and is cheap: hash **full rows** —
  `md5(string_agg(s.r::text, E'\n' ORDER BY s.r::text))` over
  `(SELECT t.* FROM <table> t) s` — for `installation_keys`, `app_settings`, and
  the five `public.*` tables. `row::text` excludes system columns (no `xmax`
  false positives) and is deterministic inside the single test transaction.
  Residual blind spot (accepted): a write that re-stamps `updated_at = now()` is
  invisible because `now()` is transaction-stable in the harness; that is a
  harness property, not a test flaw.

#### 2.1.2 S06-006 — catalog setup step is not executable as written; deviation recorded only in a SQL comment

- **Test:** `backend/tests/catalog/stage-06-issuer-guards.sql:655-669`
- **Catalog expectation:** "As postgres: delete DOC via
  `public.delete_staff_member(DOC)`" (`stage-06-minting-an-aat.md` S06-006) —
  stated as a single call.
- **Actual assertion:** the test first calls `public.set_staff_active(DOC,
  false)` and only then `delete_staff_member`, because the RPC refuses active
  staff. The deviation is explained in the file header comment (lines 11-13) but
  **was never recorded in `reports/stage-06-conflicts.md`** (which lists only
  five items, none for S06-006).
- **VERDICT:** CATALOG WRONG (test is correct; the catalog text is stale).
  **SEVERITY:** LOW.
- **Evidence:** `RAISE EXCEPTION 'STAFF_STILL_ACTIVE'` guard at
  `20260613210000_delete_staff_member.sql:140` (reaffirmed in
  `20260614100000_settings_code_review_fixes.sql:139-141`); two-step setup at
  `stage-06-issuer-guards.sql:655-669`; absent from
  `reports/stage-06-conflicts.md`.
- **Fix brief:** Amend the catalog setup to "deactivate via
  `public.set_staff_active(DOC, false)`, then delete via
  `public.delete_staff_member(DOC)`" (the production flow), and add a line to
  `stage-06-conflicts.md` so the deviation is tracked like the others. No code
  or test change needed — the test's assertions (soft-delete, no issuance row)
  match the catalog's Expected outcome.

#### 2.1.3 Stage-06 happy-path B0 — app_settings pin masks seed drift for 4 of 5 keys

- **Test:** `backend/tests/catalog/stage-06-happy-path-and-lifecycle.sql:169-183`
- **Catalog expectation:** B0 leaves `app_settings` at migration-seeded defaults;
  S06-043 pins the seed value (`ai.aat.lifetime_minutes = 10`) as the drift trip
  wire (C-03).
- **Actual assertion:** B0 upserts **all five** keys (`lifetime 10`,
  `audience 'ai-platform'`, `ver '1'`, `ceiling 100`, `window 3600`) with
  `ON CONFLICT DO UPDATE`. The comment says the pin exists for the lifetime
  conflict, but it overwrites whatever the seed migration actually wrote for the
  other four keys too — so a seed regression in `audience`/`ver`/`ceiling`/
  `window` would pass S06-019/020 silently. The unpinned verify-and-handoff file
  only re-checks the lifetime seed (S06-043); S06-041/046 override audience/ver
  before asserting them, so the seeded audience/ver values are never verified
  anywhere.
- **VERDICT:** WEAK TEST. **SEVERITY:** LOW.
- **Evidence:** five-key upsert at
  `stage-06-happy-path-and-lifecycle.sql:169-183`; S06-043 checks only lifetime
  (`stage-06-verify-and-handoff.sql:1021-1041`); S06-041/046 set the keys they
  assert (`stage-06-verify-and-handoff.sql:846-851`, `1002-1007`).
- **Fix brief:** Pin only `ai.aat.lifetime_minutes` (the conflicted value), or
  better, drop the upsert and assert the five seeded values once in B0 — turning
  seed drift into a failure instead of masking it. Keep S06-043 as-is.

#### 2.1.4 S06-024 — silent fallback to [SEED] if manage_create_branch fails; tie-break branch never exercised

- **Test:** `backend/tests/catalog/stage-06-happy-path-and-lifecycle.sql:966-994`
- **Catalog expectation:** branch resolution "prefers the primary assignment;
  with no primary flag on any assignment, the alphabetically first active branch
  name wins — Main Branch over North Branch" (`stage-06-minting-an-aat.md` §1.2
  and S06-024 parenthetical).
- **Actual assertion:** (a) if `manage_create_branch` fails, the test quietly
  falls back to a direct `INSERT INTO public.branches` — `v_ok` never includes
  `v_create.success`, so a `manage_create_branch` regression would pass this
  scenario silently (the failure surfaces only in `detail` text). (b) Only the
  primary-wins path is tested; the documented alphabetical tie-break
  (`ORDER BY sba.is_primary DESC, b.name`) is never exercised.
- **VERDICT:** WEAK TEST. **SEVERITY:** LOW.
- **Evidence:** fallback at
  `stage-06-happy-path-and-lifecycle.sql:975-984`, `v_ok` built without
  `v_create.success` at `986-994`; resolver ORDER BY at
  `20260801120200_ai_token_issuer_rpc.sql:170`.
- **Fix brief:** Include `v_create.success` in `v_ok` (or `RAISE` on fallback)
  so a broken `manage_create_branch` fails loudly. Add a tie-break variant:
  clear both primary flags, mint, assert `branch` = Main Branch's id.

#### 2.1.5 S06-038 — catalog's soft-deleted-key variant has no assertion

- **Test:** `backend/tests/catalog/stage-06-verify-and-handoff.sql:526-605`
- **Catalog expectation:** "Unknown `kid` … `verify_aat` returns false. (A
  soft-deleted key row behaves like unknown.)" (`stage-06-minting-an-aat.md`
  S06-038).
- **Actual assertion:** cases (a) unknown `kid` and (b) **revoked** `kid` are
  tested; the parenthetical soft-deleted-kid variant is not. S06-012 covers
  soft-delete invisibility on the *issuer* side, not in `verify_aat`.
- **VERDICT:** MISSING COVERAGE. **SEVERITY:** LOW.
- **Evidence:** `verify_aat` key lookup filters `is_deleted = false`
  (`20260801120200_ai_token_issuer_rpc.sql:320-328`); test cases at
  `stage-06-verify-and-handoff.sql:530-604`.
- **Fix brief:** Add a third case: soft-delete the K1 row (`is_deleted = true`)
  instead of revoking, assert `verify_aat` false, restore. One line of setup
  difference from case (b).

### 2.2 Stage-06 items checked and cleared

- **S06-001/002/003/004/005/007/008/009/010/011/012** — guard RAISEs, error
  strings, and no-issuance side effects all match; every `[SEED]` (ghost auth
  user, orphan staff, missing-org claims, soft-deleted installation, soft-deleted
  key) is catalog-prescribed. S06-011's `[SEED]` correctly avoids the
  `ALREADY_ENROLLED` / `CANNOT_REVOKE_LAST_ACTIVE_KEY` guards that post-date the
  catalog text (doc-drift #1).
- **S06-013/014/015/016** — rate-limit ceiling/window setup is
  catalog-prescribed; ledger-count assertions are actor-scoped; S06-016's
  temporary grant is catalog-prescribed and revoked via the real
  `update_role_permission` RPC.
- **S06-017/018/020/021/022/023/025/026** — claim-shape assertions (sub/org/
  branch/role/scopes/jti/iat/exp/ver/aud/kid/alg) match the catalog; the 600-vs-
  900 lifetime assertions are the recorded C-03 conflict (excluded). S06-021's
  "identical result for the NULL default" parenthetical is adequately covered by
  S06-019/020's default calls.
- **S06-027…S06-032** — ledger lifecycle (prune, revoke, re-enroll, disable/
  re-enable, availability-off) all match; the audit-log prune in S06-029 is
  catalog-prescribed and disclosed in the report.
- **S06-034…S06-047** — `verify_aat` true/false matrix (all six corruption
  inputs, unknown/revoked kid, wrong-installation, expired, tampered claims)
  matches; S06-034's extra "authenticated is denied" assertion is *stronger*
  than the catalog (fine). S06-040's `clock_timestamp()` sleep and S06-042's
  `pg_sleep` correctly work around transaction-stable `now()` without weakening
  assertions. S06-027's re-mint-if-not-stashed fallback is safe because a failed
  S06-019 is already recorded as failed.

## 3. Stage 08 SQL half — Context provider RPC (S08-061…069)

### 3.1 Findings

#### 3.1.1 S08-063 — [SEED] used for a NULL-complaint note that the real RPC creates

- **Test:** `backend/tests/catalog/stage-08-context-provider-rpc.sql:417-427`
- **Catalog expectation:** "Seed (as postgres) a `visit_clinical_notes` row for
  V with `complaint = NULL`" — the catalog prescribes `[SEED]`, but the sweep
  brief requires checking whether a real RPC can produce the state.
- **Actual assertion:** direct `INSERT INTO public.visit_clinical_notes` with
  `complaint = NULL`, justified in the report as "no public RPC can create a
  NULL-complaint note" (`reports/stage-08.md:33-34`).
- **VERDICT:** TEST WRONG (unjustified `[SEED]`; the justification is factually
  incorrect). **SEVERITY:** LOW.
- **Evidence:** `auth_internal.save_visit_documentation` INSERTs the note row
  unconditionally with `p_complaint` and has **no** non-null guard on complaint
  (`20260628140000_visit_documentation_redesign.sql:367-374` guard checks only
  `visit_id`; INSERT at `405-411`). Calling the wrapper with all-NULL sections
  creates exactly the seeded shape — a note row with `complaint = NULL`.
- **Fix brief:** Create the note via the real RPC —
  `public.save_visit_documentation(visit_063, NULL, NULL, NULL, NULL, NULL,
  NULL)` — then keep only the `created_at` pin as `[SEED]` (the pin is
  unavoidable because the RPC stamps `now()`; same pattern as S08-061). Update
  the report's justification. This also exercises the catalog's intended
  journey shape (documentation saved through the real write path).

### 3.2 Stage-08 items checked and cleared

- **S08-061/062** — payload shape, exact `recorded_at` (UTC, ms), and the
  no-note `{visit_id}`-only envelope all match; the `created_at` pins are
  disclosed and unavoidable (RPC stamps `now()`); the Worker-ingress POST halves
  belong to the E2E track, not this file.
- **S08-064** — the soft-deleted-note `[SEED]` is justified: no public RPC
  soft-deletes a clinical note (verified — archive RPCs exist only for vital
  signs and investigations).
- **S08-065/067/068** — FORBIDDEN (no `visit clinical read`), NOT_FOUND
  (nonexistent visit), and ROLE_FORBIDDEN (lab_staff) assertions match,
  including the catalog's exact message strings.
- **S08-066** — the out-of-scope-branch test drives the real mechanism: the
  doctor's JWT carries `branch_ids = [main]` while the visit is in North, and
  `assert_visit_branch_scope` reads `jwt_branch_ids()`
  (`20260531180000_visit_medical_records.sql:318`). The seeded North assignment
  is invisible to the check by design; it exists only so the North visit could
  be created through real RPCs. Appointment `status='completed'` is set by
  direct UPDATE (`s08_release_in_progress`) because `complete_visit` requires
  documentation and would pollute the note state — justified and disclosed.
- **S08-069** — recorded conflict (BUG-10), excluded.

## 4. Stage 11 SQL half — record_ai_acceptance (S11-022…029)

### 4.1 Findings

None. All three deviations in this range (S11-027 T0−1s stale, S11-028 one-arg
stub + P0001, S11-029 schema-level deny) are recorded conflicts and excluded.

### 4.2 Stage-11 items checked and cleared

- **S11-022** — success envelope, merged `data` (domain payload + acceptance
  fields), `branch_id` looked up from `visits`, `record_id ≠ note_id`
  (new-version insert), and the acceptance/audit side-effect rows all match the
  catalog. The wrapper is `SECURITY DEFINER` as the architecture requires
  (`20260802150000_ai_acceptance_recording.sql:283`).
- **S11-023** — all three malformed-reference cases (NULL, bad length, bad
  alphabet) raise the catalog's exact message; code confirms the format check
  precedes every lookup (`20260802150000_ai_acceptance_recording.sql:163-167`).
- **S11-024** — using a *duplicate* reference with an *unregistered* target and
  expecting the registry error is a strong ordering proof (registry check runs
  before the duplicate check — code order verified at
  `20260802150000_ai_acceptance_recording.sql:169-177` vs `191-197`).
- **S11-025** — both duplicate cases rejected with the catalog's exact message;
  case (b) correctly demonstrates the pre-check is broader than the UNIQUE
  constraint (which includes `record_id`).
- **S11-026** — no-org JWT → FORBIDDEN with zero writes, asserted on all three
  tables.
- **S11-027(b)** — NOT_FOUND branch asserted alongside the recorded stale
  conflict.
- **S11-028** — beyond the recorded stub-arg conflict, the rollback assertions
  (domain stub's audit row gone, no acceptance/audit rows) fully cover the
  catalog's "atomic rollback" side effects.
- **S11-029** — wrapper-gate denies both `auth_internal` functions; RLS
  visibility (cross-org 0, same-org 1, branch-excluded 0) matches the policy at
  `20260802150000_ai_acceptance_recording.sql:107-114`. The Org2 fixture inserts
  are unavoidable `[SEED]` (no public RPC creates a second organization).
- **Harness note:** the single-transaction BEGIN/ROLLBACK design does not hide
  committed-state bugs in this range — RLS, unique constraints, and the
  advisory-lock rate limiter all behave identically inside a transaction, and
  the one wall-clock dependency (S11-027) is the recorded conflict.

## 5. Summary

### 5.1 Coverage accounting

| Range | IDs | SQL assertions present | Gaps |
|---|---|---|---|
| S02-001…027 | 27 | 27 | none |
| S06-001…047 | 47 | 47 | none |
| S08-061…069 | 9 | 9 | none |
| S11-022…029 | 8 | 8 | none |

Verified mechanically (every ID has a `record('<ID> — …')` call in the stage
files). No catalog scenario in scope lacks SQL coverage.

### 5.2 Findings by verdict

| VERDICT | Count | Findings |
|---|---|---|
| CODE BUG | 0 | — |
| CATALOG WRONG | 1 | S06-006 (§2.1.2) |
| TEST WRONG | 1 | S08-063 (§3.1.1) |
| WEAK TEST | 4 | S06-019 (§2.1.1), S06 B0 pin (§2.1.3), S06-024 (§2.1.4), S02-024 (§1.1.1) |
| MISSING COVERAGE | 1 | S06-038 soft-deleted-kid variant (§2.1.5) |

### 5.3 One-line list of actionable findings

- **CATALOG WRONG — S06-006:** catalog's one-call `delete_staff_member` setup is
  not executable (RPC raises `STAFF_STILL_ACTIVE`); fix catalog text + record
  the conflict (`stage-06-issuer-guards.sql:655-669`).
- **TEST WRONG — S08-063:** NULL-complaint note is `[SEED]`ed although
  `save_visit_documentation(visit, NULL,…)` creates exactly that row; keep only
  the `created_at` pin as `[SEED]` (`stage-08-context-provider-rpc.sql:417-427`).
- **MISSING COVERAGE — S06-038:** catalog's "(soft-deleted key behaves like
  unknown)" variant of `verify_aat` is never tested
  (`stage-06-verify-and-handoff.sql:526-605`).
- **WEAK TEST (headline) — S06-019:** "mint writes ONLY ai_token_issuance" is
  guarded by partial-column hashes + row counts; a deterministic full-row
  `row::text` hash over `installation_keys`, `app_settings`, and the five
  `public.*` tables is a strictly stronger, false-positive-free assertion
  (`stage-06-happy-path-and-lifecycle.sql:480-611`).
