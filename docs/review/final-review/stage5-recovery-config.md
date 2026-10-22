# Stage 5 Second-Round Review — Recovery, Detection and Configuration (RM28–RM35)

Branch `ai/abo-remediation` at tip `6cae8104`, compared against `master`. Light pass: one targeted spot-check
per requirement, deeper reads only where a claim did not match or a later RM touched the same code.

## 1. Summary

- RM status: **5 HANDLED** (RM28, RM29, RM30, RM34, RM35), **3 PARTIAL** (RM31, RM32, RM33), **0 NOT HANDLED**,
  **0 REGRESSED**.
- Findings: **0 Critical**, **1 Major** (M-1).
- Verdict: **FAIL** — driven by M-1 (R9-AO2 payout reversal matching cannot clear chargebacks, and the refund
  path is unverified). No RM is NOT HANDLED or REGRESSED; the three PARTIALs are recorded, owner/orchestrator
  accepted deviations.

## 2. Phase verification

| RM | Requirement | Status | Evidence |
|---|---|---|---|
| RM28 | R9-REC1 checkout timestamp provenance; expiry-inferred / missing stops | HANDLED | `abo/src/rebuild.ts:67-100` (`resolveHistoricalCheckoutTimestamp` throws `checkout_timestamp_inferred_from_expiry` / `_unrecoverable` / `_provenance_unverified`); migration `abo/migrations/0020_recovery_provenance_and_inquiries.sql` |
| RM28 | R9-REC1 payload_version rejected before effects | HANDLED | `abo/src/rebuild.ts:239`, `:278`, `:417` (exact version checks) |
| RM28 | R9-REC1 pinned rebuild launcher | HANDLED | `abo/package.json:12,21` (`tsx` pinned `4.23.15`) |
| RM28 | R9-REC1 todo leftovers: resume/sequence, gap, tamper, conflict, fresh next sequence | HANDLED | Tests exist at `abo/test/system/digest-watch-rebuild.cross-worker.test.ts:3131,3161-3265,3290,3317,3359` (3161 asserts original `fact_seq`, fresh seq 22, immutable R2 objects unchanged). Unchecked boxes in `RM28.todo.md` are stale. |
| RM28 | R9-FACT1 reversal-request fact membership | HANDLED | `abo/src/work/reversal.ts:461,573,585`; `abo/src/ops/index.ts:2064` |
| RM28 | R9-REC3 / R9-REC2 inquiry outcomes, no replacement order | HANDLED | `abo/src/rebuild.ts:963` (`recordRebuildInquiryAttempt`); `rebuild_inquiry_attempt` in `LEDGER_TABLES` `abo/src/rebuild.ts:108`. Remaining `RM28.todo.md` open items are operator-checklist adjudications (by design, not code). RM32's skips of R9-REC1/REC2/REC3 tests are no longer present (only `it.skip` left in `abo/test` is R9-AO2 at `reconciliation.cross-worker.test.ts:2099`). |
| RM29 | R9-PDO1 nonempty target refused; marker cannot authorize wipe | HANDLED | `ai-platform/src/quota-do/coverage.ts:5933-5958` (occupied core tables + marker generation checks → `blocked`) |
| RM29 | R9-PDO1 capsule provenance checks (route/ceiling/actor) | HANDLED | `ai-platform/src/quota-do/coverage.ts:5550` (`grant_recovery_route_provenance_conflict`); seal/transfer evidence stops at `:6014`, `:6139` |
| RM29 | R9-PD1 / R4-D5 addendum | HANDLED | Per record; CI 39630980991 732/732; not re-traced in this pass |
| RM30 | R9-PUS1 accounting_seq, watermark replay, gap/unknown blocks | HANDLED | `ai-platform/src/quota-do/coverage.ts:6178-6223` (blocks `usage_accounting_identity_unknown`, `_snapshot_invalid`, `_term_identity_conflict`, `_sequence_gap`); replay-once `:5236-5247` |
| RM30 | R9-PUS1 FK-safe usage shipment | HANDLED | `ai-platform/src/quota-do/coverage.ts:4022-4059` |
| RM30 | R9-PRET1 term-ended-gated retention | HANDLED | `ai-platform/src/retention/index.ts:39-60,295-298` (`usage_term_retention`, purge only `term_state='ended'`). `RM30.todo.md` items all done; its "CI pending" note is superseded by RM30.md (run 39679626741 green). |
| RM31 | R9-PAL1 durable stored body + single leased dispatcher | HANDLED | `ai-platform/src/alert/index.ts:366-425` (lease claim on `body_state='stored'`), `:824-840`; kill-switch body in mutation batch `ai-platform/src/vendor/entrypoint.ts:7201,7241` |
| RM31 | R9-CRON1 per-job state, lease, success-only stamp, failure alert | HANDLED | `abo/src/scheduler/jobs.ts:99-155,171-235`; `abo/migrations/0021_scheduled_job_state.sql` |
| RM31 | R9-CRON1 missed (never-attempted) period recovered by later tick | PARTIAL | Deliberate deviation: `retryOnly` claim `abo/src/scheduler/jobs.ts:192` (`? = 0 OR next_attempt_at IS NOT NULL`) never starts a skipped 06:00/hourly/six-hour period. Recorded in RM31.md "Decision: minute-cron catch-up (safety)". Digest heartbeat (26 h) is the only external detector. |
| RM31 | R9-AO4 finding identity + atomic AL-10 | HANDLED | `abo/src/reconciliation/run.ts:67-150`; `abo/migrations/0022_finding_identity.sql` |
| RM31 | R9-AO5 / R9-AO6 alert clearing; paged hmac-invalid sweep | HANDLED | `abo/src/housekeeping/run.ts:24-73` (`housekeeping_r2_cursor`) |
| RM32 | R9-AO1 / R9-AO3 missing-view divergence; receipt LEFT JOIN | HANDLED | `abo/src/reconciliation/run.ts:806-811` |
| RM32 | R9-AO7 / R9-AO8 whole-file validation, file-hash idempotency, paged list | HANDLED | `abo/migrations/0023_payout_import_file_identity.sql`; per record |
| RM32 | R9-AO2 exact reversal identity matching (steps 1–3) | PARTIAL | Tables `abo/migrations/0024_*`, `0025_*` and matcher `abo/src/reconciliation/run.ts:512-596` exist and are in the rebuild ledger (`abo/src/rebuild.ts:107,135-137`). But manual reversals are excluded and chargebacks are never provider-recorded; refund test skipped (`reconciliation.cross-worker.test.ts:2099`). See M-1. |
| RM33 | R8-ROUTE1 shared strict parser at publish/serve | HANDLED | `ai-platform/src/control/routing-policy.ts:211-214`, `:54` |
| RM33 | R8-PUB1 (routing) digest-keyed content + digest check | HANDLED | `ai-platform/src/control/routing-policy.ts:216-241` (key includes sha256), `:43-44` (mismatch fails) |
| RM33 | R8-PUB1 step 3 legacy NULL-digest quarantine before strict serving | PARTIAL | Owner-accepted log-and-serve (`routing_policy_digest_absent_warning`, RM33.md operator checklist 2); quarantine/republish left to operators |
| RM33 | R8-ROLLBACK1 generation-guarded activation, known-predecessor only | HANDLED | `ai-platform/src/control/routing-policy.ts:505-535` (guarded `UPDATE … WHERE generation = ?`, audit-gated), `:612` (`rollback_predecessor_unknown`) |
| RM34 | R8-PUB1 (terms) digest key + single-batch publication + serve-time hash check | HANDLED | `abo/src/ops/index.ts:1482,1681-1738`; `abo/src/clinic-api/offers.ts:59-65` |
| RM34 | R8-CONSOLE5 input validation before approval; malformed stored offer quarantined | HANDLED | `abo/src/ops/index.ts:1642-1657`; `abo/src/clinic-api/offers.ts:111-121` |
| RM34 | R8-CONSOLE1 reinstate writes `published`; `reinstated` alias read | HANDLED | `abo/src/ops/index.ts:1756-1758`; `abo/src/clinic-api/offers.ts:79,90`; `abo/src/clinic-api/checkouts.ts:167,173` |
| RM34 | R8-CONSOLE4 org-scoped clinic action history | HANDLED | Per record (`platformGrantIdsFromCoverage`, `json_each`); not re-traced |
| RM35 | R9-RT1 launch check live mode + read-only launch-state reader | HANDLED | `ops/launch/launch-check.mjs:7` (`--target` live mode); `backend/supabase/migrations/20261022120000_rm35_launch_state_reader.sql` (NOLOGIN role, EXECUTE-only, revoked from PUBLIC/anon/authenticated/service_role) |
| RM35 | R9-RT2 per-stream heartbeats + audit watcher AL-21 | HANDLED | `ops/staging/heartbeat-monitor.mjs:6-17` (4 streams); `ai-platform/src/alert/index.ts:845-851,907`; `abo/src/worker.ts:212,275-286,538`; `ops/staging/audit-watcher.mjs:386-439` |

## 3. Critical findings

None.

## 4. Major findings

### 4.1 M-1 — R9-AO2: payout chargeback lines can never be matched, and manual reversals are excluded against the fix recipe

- **Location:** `abo/src/reconciliation/run.ts:509-596` (`matchingProviderReversal`, `checkUnrecordedReversal`);
  `abo/migrations/0025_reversal_provider_identity.sql:1-7`; test renamed to codify it at
  `abo/test/system/reconciliation.cross-worker.test.ts:2220` ("…remains after a manual chargeback…").
- **Failure scenario:** R9-AO2 step 3 requires keeping `unrecorded_reversal` "until a matching
  authoritative/manual reversal exists". The implementation matches only through `reversal_provider_identity`.
  Manual reversals never write that row, and the Paymob adapter's `reversalFromTxn` never produces `chargeback`
  (RM32 discovered issue a). So every real chargeback reported in a payout CSV raises a permanent
  `unrecorded_reversal` finding with daily AL-10 repeats, even after the operator has recorded the exact manual
  chargeback. The refund path is also unverified in production: its acceptance test is `it.skip` at `:2099`
  because the Paymob refund `transaction_id` semantics are unknown. If the identity does not line up, every
  refund line also stays unmatched. In practice the payout backstop fails closed, but its matching does nothing,
  and real discrepancies sit among findings that can never clear on their own.
- **Workaround / blast radius:** Operators can resolve each finding explicitly; `finding_identity` keeps it from
  reopening. There is no money or data corruption, so this is Major rather than Critical.
- **Confidence:** High on the behavior (code and the renamed test agree). Medium on severity, since it is
  operator load and alert noise rather than lost value.
- **Proposed fix:** Let a manual chargeback or refund satisfy a payout line on an exact payment + kind + amount
  match when that line has no other candidate, recorded as an immutable link marked `manual`, as step 3 allows.
  Alternatively, record the reversal identity from the payout line when the operator records the manual reversal
  for it. Confirm the Paymob refund id semantics and turn the skipped test back on before launch.

## 5. Could not verify

- RM29 R9-PD1 and the R4-D5 recovered-envelope addendum, RM29 F3–F5 fencing details, and RM34 R8-CONSOLE4 org
  isolation were accepted on the record plus CI evidence. I did not trace them line by line in this light pass.
- RM31's "catch-up risk" note says other tests calling the minute cron were not re-audited. Later green CI runs
  imply they pass, but I did not check them individually.
- RM34 coverage gaps listed in its record (concurrent publication, malformed-input refusal through the HP
  ceremony, CONSOLE4 isolation) have no tests. I did not verify them at runtime.
- No tests, builds or CI were run as part of this review.
