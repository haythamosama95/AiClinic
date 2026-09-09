# Silent-Workaround Sweep — Stage X + Cross-Cutting Coverage (ai/master @ HEAD)

**Date:** 2026-09-06
**Scope:** Part 1 — unrecorded deviations in the four Stage X E2E files
(`stage-X-cron-flush-reconcile.test.ts`, `stage-X-grace-retention.test.ts`,
`stage-X-ledger-reconciliation-sweep.test.ts`, `stage-X-credit-inspect-do-rpc.test.ts`)
against `docs/testing/catalog/stage-X-cron-and-failure-journeys.md` (63 scenarios).
Part 2 — independent verification of `phase-15-coverage.md`, harness-level deviations
from production defaults, and the 21 repo-wide `it.skip` entries vs Register 5.
**Method:** every SX scenario's Expected outcome / Side effects compared line-by-line
against its test; every cost figure re-derived from the bundled pricing table
(`ai-platform/control/pricing/platform-default/1.json`: `fake-v1` = 0.1/0.2 per 1k;
default FakeAdapter settlement = 10 in + 20 out = 30 tokens / **0.005**,
`ai-platform/src/provider/fake.ts:37`, `src/pricing/index.ts:112-120`); catalog IDs and
test-title IDs extracted independently by script and diffed; the SX-063 skip verified
by an executable probe (a scratch pool test, since deleted).
**Source-of-truth order:** architecture docs → remediation-plan → catalog → source
(not authoritative).
**Already adjudicated and skipped here:** SX-002 and SX-035 conflicts
(`stage-X-conflicts.md`), BUG-01…BUG-11 (`implementation-audit-findings.md`).

---

## 1. Part 1 — Stage X silent-workaround findings

### 1.1 SX-037 — Test engineers the FakeAdapter to make the catalog's wrong cost arithmetic pass (headline finding)

- **Test:** `ai-platform/test/e2e/stage-X-ledger-reconciliation-sweep.test.ts:790-914`
  (fixture engineering at `:344-386`, cost assertions at `:837-845, :857-890`).
- **Catalog expectation:** "Real Stage 11 settlements: I0 period `2026-08` two Completed
  requests (tokens 30+40, cost 0.003+0.004); I0 `2026-09` one (tokens 10, cost 0.001);
  I1 `2026-08` one (tokens 5, cost 0.0005)" → rollups `cost=0.007 / 0.001 / 0.0005`.
- **Actual behavior:** `spyFakeInputTokens` subclasses `FakeAdapter` and returns
  `usage: { input: N, output: 0 }` (`:363`). With output zeroed, the pricing table
  yields exactly the catalog's figures (30×0.1/1k = 0.003, etc.). The **real** fake
  settlement (10 in + 20 out) prices 30 tokens at **0.005** — the very arithmetic the
  SX-002 conflict adjudicated as catalog-wrong. Instead of asserting the correct priced
  values and recording a conflict (as SX-002 did), this test silently re-scripts the
  provider so the catalog's wrong numbers pass. The catalog's "Real Stage 11
  settlements" setup claim is also falsified: no real settlement produces 40 tokens or
  an all-input split. Additionally the `2026-09` period row is produced by
  `UPDATE usage_event SET period='2026-09'` (`:821-824`) rather than the catalog's
  "entitlement period rolled" — an entitlement roll is demonstrably possible in-pool
  (SX-051/052 do exactly that via `entitleInstallation(P2_ENTITLE)`).
- **VERDICT:** CATALOG WRONG (unrecorded instance of the SX-002 arithmetic family) +
  TEST WRONG (fixture engineered to match the wrong catalog values; conflict record
  evaded).
- **SEVERITY:** MEDIUM. No code bug is hidden (rollup sums whatever the ledger holds,
  and the GROUP BY / upsert / idempotent-re-run logic is genuinely exercised), but the
  test falsifies its own journey setup and sets the precedent that catalog arithmetic
  can be made true by doctoring the adapter.
- **Evidence:** `stage-X-ledger-reconciliation-sweep.test.ts:349-386` (scripted
  `usage.output: 0`), `:837-845` (`toBeCloseTo(0.003/0.004/0.001/0.0005)`);
  `control/pricing/platform-default/1.json:14-17`; adjudication:
  `implementation-audit-findings.md` §5.2 row "SX-002 (and SX-028, SX-034/035 setups)".
- **FIX BRIEF:** Keep the token scripting if varied token counts are wanted, but price
  honestly: either use the default 10/20 split and assert the real costs (0.005 per
  visit; rollups `(I0,2026-08): 2/60/0.010`, `(I0,2026-09): 1/30/0.005`,
  `(I1,2026-08): 1/30/0.005`), or keep custom splits and compute expected costs from
  `priceUsage`. Produce the `2026-09` row by re-entitling I0 to a September period
  before the third visit instead of rewriting the `period` column. Record the
  catalog's 0.003/0.004/0.001/0.0005 figures as a conflict and fix the catalog text.

### 1.2 SX-053 — Test follows correct priced values; catalog's 70/0.007 never recorded as a conflict

- **Test:** `ai-platform/test/e2e/stage-X-credit-inspect-do-rpc.test.ts:719-758`.
- **Catalog expectation:** "`rollups_written=1`: `(I0,2026-08)` … `request_count=2,
  tokens=70, cost=0.007`" (30+40 tokens, 0.003+0.004 — same wrong family).
- **Actual behavior:** both settlements are standard fake (30 tokens / 0.005 each), so
  the test asserts `tokens=60`, `cost≈0.01` with an explanatory comment (`:739-743`).
  The test is correct per the SX-002 adjudication, but this deviation from the catalog
  was never recorded in `stage-X-conflicts.md` (which lists only SX-002 and SX-035).
- **VERDICT:** CATALOG WRONG (unrecorded; test correct).
- **SEVERITY:** LOW (test behavior is right; the process violation is the missing
  conflict record).
- **Evidence:** `stage-X-credit-inspect-do-rpc.test.ts:739-743`; catalog
  `stage-X-cron-and-failure-journeys.md` SX-053 Expected outcome (~L678).
- **FIX BRIEF:** Add an SX-053 entry to `stage-X-conflicts.md` and correct the catalog
  text to `tokens=60, cost=0.010` (two standard fake settlements). No test change.

### 1.3 SX-028 — Catalog setup repeats the wrong 0.003 cost; test sidesteps by round-tripping actuals

- **Test:** `ai-platform/test/e2e/stage-X-grace-retention.test.ts:871-906`.
- **Catalog expectation:** setup pins "one `ai_attempt` (tokens 30, cost 0.003), one
  `usage_event` (period `2026-08`, same totals)".
- **Actual behavior:** the test reads `tokens`/`cost` from the real settlement row
  (`:882-884`) and asserts post-purge preservation (`:895-896`) — it never asserts the
  catalog's 0.003, so it is neutral/correct. The catalog text itself carries the wrong
  arithmetic (real settlement: 0.005), unrecorded.
- **VERDICT:** CATALOG WRONG (unrecorded; test neutral).
- **SEVERITY:** LOW.
- **Evidence:** `stage-X-grace-retention.test.ts:882-896`; catalog SX-028 Journey setup
  (~L403).
- **FIX BRIEF:** Correct the SX-028 setup text to cost 0.005 (or drop the literal) and
  note it in `stage-X-conflicts.md` alongside SX-053. No test change.

### 1.4 SX-056 — Catalog's expected DO counters contradict its own journey setup; test follows reality, unrecorded

- **Test:** `ai-platform/test/e2e/stage-X-credit-inspect-do-rpc.test.ts:796-915`.
- **Catalog expectation:** "`grace-sx056.status='reconciled'` and DO counters
  `{requestsUsed:1, tokensUsed:7, costUsed:0.007, inFlight:0}`" — while the same setup
  creates **three** Completed settlements (R-old, R-diag, R-new), each of which really
  credits the same Quota DO.
- **Actual behavior:** the test asserts `{requestsUsed:4, tokensUsed:97,
  costUsed:0.022}` = 3 settlements (3 × 30/0.005) + grace (7/0.007), with a comment
  (`:884-893`). The test is right; the catalog's expected counters are impossible given
  its own setup. Not recorded as a conflict. Separately, the grace row is inserted by
  raw SQL (`:813-834`) with the justification "Catalog SX-001 inserts via
  `admitUnderGrace` against a stub — not on the barrel" — but SX-001's own test
  (`stage-X-cron-flush-reconcile.test.ts:271-305`) does exactly that via a direct
  `runAdmission` + throwing-DO import, so the seed was avoidable and its justification
  is inaccurate.
- **VERDICT:** CATALOG WRONG (unrecorded) + WEAK TEST (avoidable raw-INSERT seed).
- **SEVERITY:** LOW.
- **Evidence:** `stage-X-credit-inspect-do-rpc.test.ts:810-834, 884-893`; catalog SX-056
  Expected outcome (~L714).
- **FIX BRIEF:** Correct the catalog's expected DO counters to include the three
  settlements (or move the grace assertions to a DO instance untouched by the
  settlements). Build the grace row via `runAdmission` + `attachGraceUsage` like SX-001
  and drop the stale barrel justification. Record the conflict.

### 1.5 SX-014 — Catalog journey setup is unproducible as written and lacks its `[SEED]` label

- **Test:** `ai-platform/test/e2e/stage-X-cron-flush-reconcile.test.ts:839-875`.
- **Catalog expectation:** "Pending row `grace-sx014` whose `entitlement_json` has
  `request_quota=0`" — presented as an unlabeled journey setup.
- **Actual behavior:** `runAdmission` refuses `request_quota=0` upstream
  (`isLedgerQuotaExhausted`, 0 >= 0), so the row cannot be produced by the real path;
  the test mutates `entitlement_json` post-insert and says so in a HARNESS-GAP comment
  (`:850-858`). The test's handling and assertions (stays `pending`, retry stamp, no
  drop journal, DO untouched) are correct and complete. The deviation is the catalog's:
  a setup step that needs a seed but is not labeled `[SEED]`, contrary to the chapter's
  own conventions ("Each use carries its justification inline").
- **VERDICT:** CATALOG WRONG (missing `[SEED]` label; test correct and self-documenting).
- **SEVERITY:** LOW.
- **Evidence:** `stage-X-cron-flush-reconcile.test.ts:850-858`; catalog SX-014 Journey
  setup (~L249).
- **FIX BRIEF:** Add `[SEED]` + justification to the SX-014 setup text. No test change.

### 1.6 SX-031 / SX-053 — Reconciliation exclusions asserted against hand-written SQL, not the code's report

- **Test:** `ai-platform/test/e2e/stage-X-grace-retention.test.ts:1034-1063` (SX-031);
  `ai-platform/test/e2e/stage-X-credit-inspect-do-rpc.test.ts:746-758` (SX-053).
- **Catalog expectation:** SX-031: "Before the tick, run cron `0 4 * * *` and capture
  the reconciliation report … neither row flagged". SX-053: "`missing_usage_credit=0`".
- **Actual behavior:** both tests run the real cron tick but never read the code's
  report (neither the `usage_rollup_reconciliation` log payload nor a
  `runRollupAndReconciliation` result). Instead they re-implement the reconciliation
  LEFT JOINs in test-local SQL and assert against that. If the production queries in
  `rollup/index.ts` had wrong state filters or window predicates, these tests would
  still pass — the assertions are tautological with respect to the code under test.
  Contrast SX-040…SX-045, which correctly assert on
  `runRollupAndReconciliation(...).report`.
- **VERDICT:** WEAK TEST.
- **SEVERITY:** MEDIUM for SX-031 (the pre-purge report is the scenario's primary
  expected outcome; the purge half is properly asserted); LOW for SX-053 (the rollup
  half is asserted on real D1 state).
- **Evidence:** `stage-X-grace-retention.test.ts:1039-1063`;
  `stage-X-credit-inspect-do-rpc.test.ts:749-758`; production queries
  `src/rollup/index.ts:146-168`.
- **FIX BRIEF:** Replace the hand-written SQL with
  `runRollupAndReconciliation({ db: env.DB })` (direct call, as SX-040…SX-044 do) or
  parse the `usage_rollup_reconciliation` log payload unconditionally, and assert the
  seeded rows' absence from the code-produced arrays.

### 1.7 SX-036 / SX-039 — Conditional log-payload assertions silently pass when the log is missing

- **Test:** `ai-platform/test/e2e/stage-X-ledger-reconciliation-sweep.test.ts:762-766`
  (`if (purged) { expect(purged.counter_deleted).toBe(1); }`) and `:955-961`
  (`if (payload) { … }`).
- **Catalog expectation:** SX-036: "`counter_deleted=1`"; SX-039:
  "`usage_rollup_reconciliation{rollups_written:0, missing_attempt_rows:0,
  missing_usage_credit:0, window:{…}}`".
- **Actual behavior:** `parseLogPayload` returns `undefined` when the line is absent or
  unparseable, and the assertions are guarded by `if`, so a missing/misnamed log event
  makes the test greener, not redder. SX-039 is rescued by its direct
  `runRollupAndReconciliation` assertions (`:966-970`); SX-036's `counter_deleted=1`
  payload is asserted nowhere else (the row-level state assertions do cover the
  delete itself).
- **VERDICT:** WEAK TEST.
- **SEVERITY:** LOW (state-level assertions still catch a real purge failure).
- **Evidence:** `stage-X-ledger-reconciliation-sweep.test.ts:762-766, 955-961`;
  log emission `src/retention/index.ts:277-282`, `src/worker.ts:1735-1741`.
- **FIX BRIEF:** Assert `purged`/`payload` is defined before asserting its fields
  (drop the `if`). One line per test.

### 1.8 Systemic — catalog-pinned log payload fields and the closing log event are largely unasserted

- **Test:** `expectLogOrder` / `expectLogContains`,
  `ai-platform/test/e2e/stage-X-cron-flush-reconcile.test.ts:163-184`; used by SX-001,
  SX-002, SX-003, SX-004, SX-005, SX-009, SX-010, SX-011.
- **Catalog expectation:** e.g. SX-001 pins the full ordered chain ending in
  `scheduled_cron_complete`; SX-002 pins
  `usage_rollup_reconciliation{rollups_written:1, missing_attempt_rows:0,
  missing_usage_credit:0, window:{…}}`; SX-005 pins `Flushing guard rejection
  counters{bucket_count:2, rejection_count:4}`; SX-009(b) pins
  `retention_purge_complete{counter_deleted:1}`.
- **Actual behavior:** the assertions match event **names** only (substring), never
  payloads — and the code emits all of these fields (`src/rate-limit/index.ts:172-174`,
  `src/retention/index.ts:277-282`, `src/worker.ts:1735-1741`). Additionally
  `expectLogOrder` silently skips a missing `scheduled_cron_complete`
  (`:175-179`, "HARNESS-GAP … LOG_VERBOSITY=2"), so the final link of the catalog's
  cron log order is optional in every order assertion. SX-003 also never asserts the
  presence of the flush log line the catalog lists. D1/R2/DO state assertions are
  strong throughout, so this is a reporting-observability gap, not a correctness hole.
- **VERDICT:** WEAK TEST.
- **SEVERITY:** LOW.
- **Evidence:** `stage-X-cron-flush-reconcile.test.ts:168-184, 440-449, 493-503,
  534-549, 614`; `src/worker.ts:1735-1741`.
- **FIX BRIEF:** Extend `parseLogPayload`-style assertions (unconditional) to the
  catalog-pinned fields in SX-002/SX-005/SX-009, and either capture debug logs reliably
  (the pool runs `LOG_VERBOSITY=2`, so `scheduled_cron_complete` should be capturable —
  investigate why the escape hatch was needed) or document the limitation in the test.

### 1.9 SX-017 — Tautological assertion on a grace id that can never have attempts

- **Test:** `ai-platform/test/e2e/stage-X-grace-retention.test.ts:447`.
- **Catalog expectation:** SX-017 side effects: "Writes: grace row status UPDATE only."
- **Actual behavior:** `expect(await getAttempts(graceId)).toHaveLength(0)` queries
  `ai_attempt` by `request_id = <grace_request_id>`; a grace queue id is never an
  `ai_request`/`ai_attempt` id, so this passes vacuously regardless of code behavior.
  The meaningful assertions (status `dropped`, `reconcile_attempts=0`, drop-journal
  reason) are present and correct.
- **VERDICT:** WEAK TEST (tautological assertion).
- **SEVERITY:** LOW (cosmetic; the real side-effect assertions exist).
- **Evidence:** `stage-X-grace-retention.test.ts:447`; harness `getAttempts`
  (`harness/d1.ts:195-203`).
- **FIX BRIEF:** Replace with `expect(await count("usage_event")).toBe(0)` /
  `count("ai_request")` (the catalog's "no ledger writes" side effect), or delete the
  line.

### 1.10 SX-022 — Catalog's re-open action is a real `POST /v1/requests`; the test calls `runAdmission` directly

- **Test:** `ai-platform/test/e2e/stage-X-grace-retention.test.ts:703-714`.
- **Catalog expectation:** "Then, with the DO stubbed unavailable again, drive one real
  `POST /v1/requests` (Stage 8 behavior: `admitUnderGrace`) … HTTP 200 SSE path with
  `grace_admitted` outcome."
- **Actual behavior:** the re-open is `graceAdmit(...)` → `runAdmission` with a throwing
  DO namespace — the component-level call, not the HTTP journey. The cap-release
  assertion (pending count 5 → 0 → 1) is fully validated, but the full-path
  guard→grace mapping (`rate_limited` + `retry_after` on the wire while capped, SSE
  `grace_admitted` after) is not exercised here. This is the Register 5 #28 family
  (wrappers do not reach `SELF.fetch`; the S09-075…S09-077 full-path analogues are
  skipped for the same reason), so the weakening is harness-justified — but it is not
  recorded anywhere as a deviation.
- **VERDICT:** WEAK TEST (harness-justified, undocumented).
- **SEVERITY:** LOW.
- **Evidence:** `stage-X-grace-retention.test.ts:195-216, 703-714`; Register 5 #28;
  `implementation-audit-findings.md` §7.
- **FIX BRIEF:** Note the substitution in `stage-X.md` (the report currently claims
  SX-022 "uses `wrapDurableObjectNamespace` on `invokeCron`" without mentioning the
  re-open is component-level). Optionally assert the `rate_limited` result shape
  (`retry_after` presence) on the blocked admit to close the remaining gap.

### 1.11 SX-063 (`it.skip`) — verified legitimate Register 5 #45; not hiding a bug

- **Test:** `ai-platform/test/e2e/stage-X-credit-inspect-do-rpc.test.ts:1001-1004`.
- **Catalog expectation:** valid admission against a DO whose storage throws →
  HTTP 500 `{"error":"internal_error"}` + `gateway_object_rpc_failed` log
  (`src/worker.ts:1543-1549`).
- **Actual behavior:** skipped, citing Register 5 #45 ("Real DO storage cannot be
  forced to throw in the pool"; seam: `wrapDoStorage` storage double). I verified the
  skip's central claim with an executable probe: constructing `new GatewayObject(
  mockCtx, env)` inside the pool fails with `TypeError: Failed to construct
  'DurableObjectBase': constructor parameter 1 is not of type 'DurableObjectState'`
  (workerd enforces a genuine state object), and `runInDurableObject` only ever exposes
  real storage. So the fetch-level catch-all → 500 mapping is genuinely unreachable
  in-pool; `wrapDoStorage` reaches only the `admissionRPC`/`creditRPC`/`releaseRPC`
  functions (which the barrel exports), where a throw would prove nothing about the
  500 mapping. The sibling catch branch (`ArgValidationError` → 400) IS covered by
  SX-060…SX-062 against the real DO.
- **VERDICT:** legitimate skip (Register 5 #45 confirmed by probe). Residual: the
  catch-all 500 branch has zero coverage.
- **SEVERITY:** LOW (the branch is 3 lines; the arg-validation sibling is tested).
- **Evidence:** probe run 2026-09-06 (scratch file, deleted after the run);
  `src/worker.ts:1478, 1543-1549`; `harness/faults.ts:192-223`; Register 5 #45.
- **FIX BRIEF:** Keep the skip. Optional partial coverage: a component test asserting
  `admissionRPC(wrapDoStorage(storage, { getThrow }))` rejects, documenting that the
  500 mapping itself remains pool-untestable until workerd allows DO construction with
  a state double.

### 1.12 Minor notes (no verdict, recorded for completeness)

- **SX-019** (`stage-X-grace-retention.test.ts:532-573`): catalog pins the
  `grace_reconcile_dropped` log at **error** level; level is not asserted (the journal
  reason is). Cosmetic.
- **SX-058 / SX-059** (`stage-X-credit-inspect-do-rpc.test.ts:927-948`): catalog pins
  error logs `gateway_object_invalid_json` / `gateway_object_unknown_kind{kind}`;
  neither is asserted. The log call sites exist (`src/worker.ts:1489, 1550`).
- **SX-061 / SX-062** (`:963-999`): unlike SX-060, no post-rejection `inspect`
  asserting the catalog's "no storage writes" side effect. The 400s are asserted.
- **SX-020** (`stage-X-grace-retention.test.ts:576-627`): pins wall-clock via global
  `Date.now` override (restored in `finally`). Effective and within the `[SEED]`
  spirit; noted because it is a global mutation technique not used elsewhere.
- **Catalog nit:** SX-057's journey setup cites `DO.idFromName("quota:inst_…")`;
  production uses `idFromName(installationId)` with no prefix
  (`src/pipeline/index.ts:284`, `src/credit/index.ts:123,165`,
  `src/admission/index.ts:414`, `src/control/quota-inspect.ts:71`) and the harness
  matches production. Fix the catalog text.
- **`stage-X-conflicts.md` staleness:** its SX-002 entry cites test lines `:423`/`:455`;
  the assertions now live at `:480-481`/`:513`. Re-anchor when the file is next edited.

### 1.13 SX scenario accounting (all 63 IDs)

| ID(s) | Test | Verdict |
|---|---|---|
| SX-001 | `stage-X-cron-flush-reconcile.test.ts:411` | Covered, faithful; log-payload gap → §1.8 |
| SX-002 | `:471` | Recorded conflict (adjudicated: catalog wrong, test asserts 0.005) — skipped per scope |
| SX-003 | `:520` | Covered; minor log gaps → §1.8 |
| SX-004 | `:557` | Covered, faithful (Register 5 #28 D1 shim) |
| SX-005 | `:590` | Covered; log payload unasserted → §1.8 |
| SX-006 | `:630` | Covered, faithful |
| SX-007 | `:662` | Covered, faithful |
| SX-008 | `:673` | Covered, faithful |
| SX-009 | `:687` | Covered; `counter_deleted:1` payload unasserted → §1.8 |
| SX-010 | `:725` | Covered, faithful |
| SX-011 | `:738` | Covered, faithful (full DO + queue lifecycle asserted) |
| SX-012 | `:786` | Covered, faithful |
| SX-013 | `:809` | Covered, faithful (throwing-DO stub) |
| SX-014 | `:839` | Covered; catalog setup missing `[SEED]` label → §1.5 |
| SX-015 | `:877` | Covered, faithful |
| SX-016 | `:928` | Covered, faithful |
| SX-017 | `stage-X-grace-retention.test.ts:402` | Covered; tautological assertion → §1.9 |
| SX-018 | `:450` | Covered, faithful (tick1/tick2/sweep-probe all asserted) |
| SX-019 | `:532` | Covered; log level unasserted → §1.12 |
| SX-020 | `:576` | Covered, faithful (Date.now pin — §1.12) |
| SX-021 | `:629` | Covered, faithful |
| SX-022 | `:652` | Covered with weakened action → §1.10 |
| SX-023 | `:716` | Covered, faithful (log unasserted, branch-coverage scenario) |
| SX-024 | `:722` | Covered, faithful (log payload unasserted → §1.8) |
| SX-025 | `:749` | Covered, faithful (`[SEED]` justified) |
| SX-026 | `:795` | Covered, faithful (direct call, strict `>` boundary) |
| SX-027 | `:846` | Covered, faithful |
| SX-028 | `:871` | Covered; catalog setup cost wrong, test neutral → §1.3 |
| SX-029 | `:908` | Covered, faithful (strict `<` boundary) |
| SX-030 | `:980` | Covered, faithful (derived-key no-op) |
| SX-031 | `:1006` | Purge half covered; report half tautological → §1.6 |
| SX-032 | `:1072` | Covered, strong (byte-identical full-footprint diff incl. `capability_grant`, `control_audit`, `platform_counter`, `usage_rollup`, R2) |
| SX-033 | `stage-X-ledger-reconciliation-sweep.test.ts:528` | Covered, faithful |
| SX-034 | `:568` | Covered, faithful (lexicographic period compare) |
| SX-035 | `:622` | Recorded conflict (adjudicated: catalog seed wrong) — skipped per scope |
| SX-036 | `:736` | Covered; conditional log assertion → §1.7 |
| SX-037 | `:790` | **TEST WRONG + CATALOG WRONG** → §1.1 |
| SX-038 | `:916` | Covered, faithful (windowed touched-period re-aggregation) |
| SX-039 | `:951` | Covered via direct call; conditional log assertion → §1.7 |
| SX-040 | `:973` | Covered, faithful (real report asserted) |
| SX-041 | `:1007` | Covered, faithful |
| SX-042 | `:1040` | Covered, faithful |
| SX-043 | `:1070` | Covered, faithful (`[SEED]` justified, Register 5 #36) |
| SX-044 | `:1097` | Covered, faithful (inclusive window boundaries) |
| SX-045 | `:1151` | Covered, faithful |
| SX-046 | `:1168` | Covered, faithful (sweep + slid expiry asserted) |
| SX-047 | `:1181` | Covered, faithful (both arms) |
| SX-048 | `:1213` | Covered, faithful |
| SX-049 | `stage-X-credit-inspect-do-rpc.test.ts:462` | Covered, faithful (double-credit blocked inside + after window) |
| SX-050 | `:547` | Covered, faithful (in-memory vs persisted sweep) |
| SX-051 | `:573` | Covered, faithful (rollover preserves `inFlight`) |
| SX-052 | `:640` | Covered, faithful (credit lands in new period) |
| SX-053 | `:719` | CATALOG WRONG unrecorded (§1.2) + hand-written SQL (§1.6) |
| SX-054 | `:760` | Covered, faithful (404 empty body; support `not_found` matches Register 1B) |
| SX-055 | `:777` | Covered, faithful (`{state:"Completed"}`, no `result`; support `envelope: null`) |
| SX-056 | `:796` | CATALOG WRONG unrecorded + avoidable seed → §1.4 |
| SX-057 | `:917` | Covered, faithful (405 plain text) |
| SX-058 | `:927` | Covered; log unasserted → §1.12 |
| SX-059 | `:938` | Covered; log unasserted → §1.12 |
| SX-060 | `:949` | Covered, faithful (400 + no-storage-write inspect) |
| SX-061 | `:963` | Covered; side-effect inspect missing → §1.12 |
| SX-062 | `:990` | Covered; side-effect inspect missing → §1.12 |
| SX-063 | `:1001` (`it.skip`) | Legitimate skip, probe-verified → §1.11 |

**No SX scenario is missing a test; no test asserts a catalog value that pins a code
bug; no new CODE BUG was found in the stage-X surface** (the cron/retention/DO code
matches the catalog wherever the tests check real state; the two recorded conflicts
were already adjudicated).

---

## 2. Part 2 — Cross-cutting coverage audit

### 2.1 Independent verification of `phase-15-coverage.md`

Method: catalog IDs from `grep '^## Scenario' docs/testing/catalog/*.md` (818 unique,
consecutive per chapter, matching the register footer counts). Test IDs extracted with
a title-aware parser over all 40 `ai-platform/test/e2e/**/*.test.ts` files (handles
multi-line titles, `it`/`test`/`it.skip`; the two `.test(` RegExp false positives
excluded by construction).

**Result — the coverage report is accurate in every independently checkable claim:**

| Metric | phase-15 claim | Independent result |
|---|---|---|
| Catalog IDs | 818 | 818 ✓ |
| Unique IDs with a real `it` | 707 | 707 ✓ (727 union − 20 skip-only) |
| `it.skip` calls | 21 | 21 ✓ |
| Skip-only IDs | 20 | 20 ✓ |
| Mixed (skip + real `it`) | 1 (S00-007) | 1 (S00-007) ✓ |
| IDs tested in >1 file | 0 | 0 ✓ |
| Test IDs not in catalog | 0 | 0 ✓ |
| Catalog IDs with no test | 91, exactly the pgTAP-deferred ranges | 91 ✓ = S02-001…027 (27) + S06-001…047 (47) + S08-061…069 (9) + S11-022…029 (8) |
| Automatable gaps | 0 | 0 ✓ |

No catalog ID lacks a test outside the documented pgTAP deferrals; no test invents an
ID. The three untagged `P00-*` exemplars in `phase-00-exemplars.test.ts` are harness
smoke tests, as the report states.

### 2.2 Harness-level deviations from production defaults

Sources: `ai-platform/vitest.e2e.config.ts`, `ai-platform/wrangler.toml` (development /
staging / production envs), `ai-platform/test/e2e/harness/{env,d1,clinic,gateway-object,cron,faults,control,aat,scenario}.ts`, `ai-platform/test/e2e/setup.ts`.

| # | Deviation | Production default | Catalog expectations bent | Could it mask a code bug? |
|---|---|---|---|---|
| H1 | `CONFIG_CACHE_TTL_MS: "100"` (`vitest.e2e.config.ts:38-41`; also wrangler `[env.development.vars]`) | `"30000"` (staging + production vars) | S05-059 / S07-051 / S12-039 / S12-040 TTL-staleness windows are exercised via `isolateConfigCache.setTtlMs(30_000)` / `clearConfigCache()` stand-ins, never the real 30 s TTL | **Yes — already has.** The config comment admits TTL `"0"` was avoided because it breaks preload→consult in one request (BUG-06). A stale-cache-serving bug inside the real 30 s window is invisible to the suite |
| H2 | `LOG_VERBOSITY=2` (development env) | `"0"` (production), `"1"` (staging) | Debug-level events (`scheduled_cron_complete`, `gateway_object_rpc_received`, `usage_rollup_reconciliation_detail`) are visible in tests but never emitted in production; produced the `expectLogOrder` escape hatch (§1.8) | No (logging only), but log-order assertions are softer than the catalog pins |
| H3 | Requested `compatibilityDate "2026-05-03"` falls back to `2025-09-06` (`[mf:warn]` observed on every run, incl. the SX-063 probe) | wrangler.toml requests `2026-05-03`; the real platform runs current workerd | None directly | Low but real: tests execute on an ~8-month-older runtime than the configured target; runtime-behavior differences (e.g. `Request`/`Content-Length` handling, Register 5 #37) are evaluated on the fallback runtime |
| H4 | Rate-limiter miniflare bindings 600/120/300 per 60 s | Identical in all three wrangler envs | None | **No deviation** — checked, clean |
| H5 | `fileParallelism: false` + single shared isolate; in-isolate globals (`rejectionTally`, dropped-grace journal, config cache) leak across tests → `drainRejectionTally` / `drainDroppedGraceJournal` / `drainFlushTally` helpers | Production runs many isolates | SX-005…SX-008's tally semantics; S00-024 | Accepted (Register 5 #6): multi-isolate tally loss is document-only. The drain helpers are correct but mean no test ever observes cross-isolate behavior |
| H6 | `setup.ts` clears `isolateConfigCache` before every test; `resetPlatformState` wipes all 14 tables + R2 and reseeds `token_contract` (`d1.ts:114-138`) | No production analogue | Any cache-persistence-across-requests expectation | Necessary isolation; low risk. The reseed mirrors the migration seed (`ver='1'`, `added_at` fixed `2026-08-03`) |
| H7 | `applySql` swallows bootstrap errors matching `/already exists\|UNIQUE constraint failed\|duplicate column/i` (`d1.ts:43-58`) | Migrations run once via platform tracking | S00-027/S00-028 (schema bootstrap) | Low: a genuine unexpected UNIQUE failure during bootstrap would be silently ignored; acceptable for idempotent re-apply, worth a comment |
| H8 | `emptyExecutionContext().waitUntil` is a no-op (`env.ts:108-112`) for `invokeCron`; `SELF.fetch` background work is observed via `flushBackgroundWork(ms)` sleeps / polling | Platform `waitUntil` keeps the isolate alive until settle | All post-response write timing (envelope, `usage_event`); SX tests poll with `waitForRequestCompleted` / `waitForUsageEvent` | Partially: a bug where `waitUntil` work is dropped on response-close would not be detected; mitigated by polling helpers that do observe the writes eventually |
| H9 | `DEFAULT_ENTITLE_PAYLOAD` period `2026-01-01→2027-01-01` (`control.ts:216-218`) | Catalog P1 = `2026-08-01→2026-09-01` | Every scenario pinning period `2026-08`: SX-002 rewrites `usage_event.period` by SQL; SX-053/056 use `AUGUST_COVERING_NOW` (`stage-X-credit-inspect-do-rpc.test.ts:63-69`) | Low: forces period-rewriting seeds that would be unnecessary if the harness default matched the catalog's P1; quota values (1000/500000/50.0/0.8) do match P1 |
| H10 | `fakePolicyDocument` routes to `FakeAdapter` (`fake`/`fake-v1`); `vi.spyOn(fakeMod, "FakeAdapter")` re-scripts provider outcomes | Production providers deepseek/gemini | All provider-wire behavior (Register 5 #33, documented) | Documented gap. **Abused once**: SX-037's `spyFakeInputTokens` zeroes output tokens to reproduce wrong catalog costs (§1.1) |
| H11 | `gatewayObjectRpc` addresses the DO via `idFromName(installationId)` (`gateway-object.ts:23`) | Identical in production (`pipeline/index.ts:284` etc.) | None — the catalog's `"quota:"` prefix mention (SX-057) is the outlier | No deviation; catalog nit recorded in §1.12 |
| H12 | `mintAat` mints `iat = now−30 s`, `exp = iat+330` (330 s lifetime) and polls `installation_key.valid_from` (`aat.ts:49-64, 69-81`) | Clinic tokens ≤ 600 s lifetime | AAT-lifetime boundary scenarios use explicit claim overrides; defaults are in-range | No |
| H13 | `installEnvOverrides` (`faults.ts:270-286`) cannot reach `SELF.fetch` — the worker reads `env` from `cloudflare:workers`, not the mutable `cloudflare:test` env | — | S09-075…S09-079, S09-082 full-path journeys (skipped); SX-022 re-open (component-level instead) | No — this is the documented Register 5 #28/#29 boundary, correctly cited by the skips |

### 2.3 The 21 `it.skip` entries vs Register 5

All 21 skip calls were extracted and compared against Register 5 rows. **Every skip
cites a real register limitation** (row number and/or verbatim Why text):

| Skip(s) | Register 5 row | Assessment |
|---|---|---|
| S00-001, S00-002, S00-003 | #1 (pool always supplies bindings) | Legitimate |
| S00-007 (throwing-load arm) | #3 (static JSON import) | Legitimate; the ID's other arm is implemented via the registry seam |
| S00-012, S00-013, S00-014 | #5 (per-isolate console capture) | Legitimate |
| S00-028 | #4 (migration re-apply is platform behavior) | Legitimate |
| S08-003, S08-005, S08-009 | #37 (workerd Content-Length normalization) | Legitimate in-pool; register's raw-TCP/undici seam is out-of-pool by definition |
| S09-075, S09-076, S09-077, S09-079 | #28 (in-pool `env.DO` frozen; wrappers don't reach `SELF.fetch`) | Legitimate for the full-path journeys. Note: stage-X covers the same DO-down behaviors at component level (`runAdmission` + throwing DO, SX-013/017/018/022), so a partial component-level re-expression exists but would not be the catalog's full-path journey |
| S09-082 | #29 (in-pool `env.DB` frozen) | Legitimate (same boundary) |
| SX-063 | #45 (DO storage fault) | **Legitimate — probe-verified** (§1.11): workerd rejects DO construction with a mock state, so the catch-all 500 mapping is genuinely unreachable in-pool |
| **S05-060, S05-061, S05-078, S05-082** | **#26 (router seam)** | **FLAGGED — implementable with the documented seam.** See below |

**Flagged skips (S05-060/061/078/082).** Register 5 #26's proposed seam is "Call
`selectCandidateChain`/`createD1ConfigReader` directly against real migrated D1 + real
R2", and the catalog scenarios themselves specify exactly that ("Seam: call
`createD1ConfigReader(DB, R2).read(...)` directly", S05-060; "drive
`selectCandidateChain` with … via the router seam", S05-061/078/082). Both functions
are exported from source (`src/router/index.ts:583`, `src/config-cache/index.ts:202`).
The skip titles cite only "not exported by the frozen harness barrel" — but the four
stage-X files import nine non-barrel production modules directly with `HARNESS-GAP`
comments (`runAdmission`, `attachGraceUsage`, `drainDroppedGraceJournal`,
`reconcileGraceUsage`, `createD1ConfigReader`, `dashboardQuotaRejectionRate`,
`runRetentionPurge`, `runRollupAndReconciliation`, `recordGuardRejection` /
`flushRejectionCounters`, FakeAdapter), precedent-set and runner-accepted. A one-line
`import { selectCandidateChain } from "../../src/router"` makes all four scenarios
implementable exactly as the register and catalog prescribe.

- **VERDICT:** WEAK SKIPS (4) — real register row cited, but the register's own
  documented seam was available and used elsewhere in the same suite.
- **SEVERITY:** MEDIUM — four catalog scenarios of pure router logic
  (`@vN` suffix stripping, structured-output exclusion, multi-language match clause,
  cost-class source priority) have zero coverage despite a sanctioned seam; the router
  is pure and these are cheap, deterministic tests.
- **Evidence:** `stage-05-rollback-serving.test.ts` / `stage-05-filters-kill-switch.test.ts`
  skip titles; catalog `stage-05-routing-policy.md` S05-060/061/078/082 Journey setup
  seams; Register 5 #26; stage-X import precedent
  (`stage-X-cron-flush-reconcile.test.ts:38-50`).
- **FIX BRIEF:** Implement the four scenarios as direct-call tests following the
  stage-X HARNESS-GAP import pattern: publish/promote the fixture policies through the
  real control plane, then call `createD1ConfigReader(env.DB, env.R2)` /
  `selectCandidateChain` with the catalog's inputs and assert the pinned chains /
  exclusions. Delete the four `it.skip`s.

---

## 3. Summary

| Verdict | Count | Items |
|---|---|---|
| CODE BUG | 0 (new) | — (BUG-01…BUG-11 from the prior audit stand; none in the stage-X surface) |
| CATALOG WRONG (unrecorded) | 5 | SX-037 (§1.1), SX-053 (§1.2), SX-028 (§1.3), SX-056 (§1.4), SX-014 (§1.5) — plus two catalog text nits (§1.12: `quota:` idFromName prefix; stale conflict-report line anchors) |
| TEST WRONG | 1 | SX-037 (§1.1) — FakeAdapter engineered (output=0) so the catalog's adjudicated-wrong 0.003/0.004/0.001/0.0005 arithmetic passes; conflict record evaded |
| WEAK TEST | 7 | §1.6 (SX-031, SX-053 hand-written SQL), §1.7 (SX-036, SX-039 conditional log assertions), §1.8 (systemic log-payload / closing-event under-assertion), §1.9 (SX-017 tautology), §1.10 (SX-022 component-level re-open) |
| WEAK SKIPS (could use the documented seam) | 4 | S05-060, S05-061, S05-078, S05-082 (§2.3) |
| MISSING COVERAGE | 0 scenarios | All 818 catalog IDs accounted for (727 Worker E2E + 91 pgTAP-deferred); residual uncovered *branch*: GatewayObject catch-all → 500 (SX-063, probe-verified non-automatable in-pool) |
| HARNESS DEVIATION | 13 catalogued (§2.2) | H1 (TTL 100 vs 30 000 — masks real-TTL behavior, tied to BUG-06) and H3 (compatibility-date fallback to 2025-09-06) are the two with genuine bug-masking potential; H10's FakeAdapter seam was abused once (SX-037); the rest are documented/justified |
| Coverage report verification | — | `phase-15-coverage.md` confirmed accurate in every independently checkable number (§2.1) |
| Skips vs Register 5 | 21/21 cite real rows | 17 legitimate (SX-063 probe-verified); 4 flagged (§2.3) |

**Every SX scenario ID (SX-001…SX-063) is accounted for in §1.13.** The two recorded
conflicts (SX-002, SX-035) were excluded per scope; both remain correctly adjudicated.


