# Silent-Workaround Sweep — Stages 04 (Entitlement & capability grants) and 05 (Routing policy)

- **Date:** 2026-09-06
- **Branch:** `ai/master` @ HEAD
- **Scope:** All 104 S04 scenarios (`docs/testing/catalog/stage-04-entitlement-capability-grants.md`
  vs `ai-platform/test/e2e/stage-04-*.test.ts`, 5 files) and all 85 S05 scenarios
  (`docs/testing/catalog/stage-05-routing-policy.md` vs
  `ai-platform/test/e2e/stage-05-*.test.ts`, 4 files).
- **Method:** Per-scenario comparison of catalog "Expected outcome" + "Side effects" against the
  test's HTTP status/error assertions, D1 side-effect assertions (entitlement columns,
  `capability_grant` rows, `control_audit` before/after pointers, `routing_policy` rows, R2
  policy documents), [SEED] justifications, and SSE terminal assertions. Reports read:
  `ai-platform/test/e2e/reports/stage-04.md`, `stage-04-failures.md` (no `stage-04-conflicts.md`
  exists — investigated, see §1.1), `stage-05.md`, `stage-05-failures.md`, `stage-05-conflicts.md`,
  `phase-15-coverage.md`. Suspected code bugs were verified against
  `ai-platform/src/` and the architecture/remediation source-of-truth order before verdicts.
- **Exclusions (already adjudicated in `implementation-audit-findings.md`):** the recorded
  stage-05 conflict blocks (HTTP 200-vs-202 for S05-050…S05-058/S05-062…S05-083;
  `routing_decision`-vs-SSE-`completed`; S05-059 TTL window) and BUG-01…BUG-11. Not re-reported.

## 1. Stage 04 — Entitlement and capability grants (S04-001 … S04-104)

### 1.1 The missing `stage-04-conflicts.md` is explained, not suspicious

104/104 scenarios passed on the first runner pass with zero fixer iterations
(`reports/stage-04.md` §3), so no conflict file was ever created. This is plausible rather than
alarming because (a) the stage-04 catalog chapter was written directly from the control-plane
source (its header lists `control/entitle.ts`, `control/cohort.ts`,
`control/capability-lifecycle.ts`, etc. as read), so expected outcomes already matched code; and
(b) stage 04 is pure control-plane request/response + D1 — no SSE, no provider invocation, no
config-cache timing — the three areas that produced every stage-05 conflict. I re-derived each
failure table (catalog §5/§7/§8/§9/§10) against the tests anyway; every HTTP status + error
string matches.

### 1.2 Per-area verification (all clean)

- **S04-001…S04-018, S04-020…S04-030, S04-034…S04-046 (validation rejections):** every test
  asserts the exact status + `{"error":"<code>"}` body *and* the catalog's shared negative side
  effects (entitlement row unchanged/`pending` with zero quotas, zero `capability_grant` rows, no
  `control_audit` `entitle` row) — e.g. `assertNoEntitleSideEffects`
  (`stage-04-entitle-auth-period.test.ts:111-124`), `assertFailureSideEffects`
  (`stage-04-entitle-quota-grants-validation.test.ts:111-126`), `assertPendingEntitleRejected`
  (`stage-04-entitle-happy-cohort-activate.test.ts:257-268`). S04-046 additionally proves the
  valid first grant is not partially applied (`…:432-437`). No weakened or inverted assertions.
- **S04-019, S04-031…S04-033, S04-037, S04-050…S04-055 (entitle successes):** full entitlement
  column assertions (periods verbatim incl. the no-millis form, quotas, `allowed_capabilities`
  JSON, `soft_threshold` boundary values 0/1, `status`, `plan` unchanged), grant-row assertions
  (`scope`, version, `revoked_at NULL`, `changed_by`, `granted_at = changed_at`, lifecycle columns
  NULL), and audit assertions (`action`, `target`, `operator_id`, `before_pointer NULL`,
  `after_pointer` = allow-list JSON). S04-052 proves `installation.status` stays `suspended`
  (`stage-04-entitle-happy-cohort-activate.test.ts:540`). S04-053/054/055 cover plan-scope
  derivation, live-plan-grant dedup (seeded row byte-compared unchanged, `…:613-615`), and the
  mixed-scope batch.
- **S04-048/049/054/056/078/096/097/098/100 [SEED] uses:** each is catalog-prescribed with the
  catalog's own justification (operator-repair states, UNIQUE probe, revoked grant, 90-day
  `retire_after` backdating per Non-automatable note 1). No seed replaces a catalog-prescribed
  real operation.
- **S04-056 (UNIQUE probe)** and **S04-057 (`wrapD1` batchThrow → 500 `storage_error`)** use the
  exact seams the catalog's Non-automatable notes propose.
- **S04-058…S04-071 (cohort activate):** update-vs-insert branches, `changed_at` re-stamp
  ordering, dedup (S04-070), `before_pointer` JSON maps incl. the `{"I0":"1.0.0","I1":null}`
  mixed-cohort shape (S04-069, `stage-04-cohort-promote-deprecate.test.ts:351-354`), and
  `cohort_name` target suffix (S04-067) all asserted exactly as the catalog pins them.
- **S04-072…S04-079 (cohort promote):** fleet sweep, plan/installation materialization,
  allow-list filter (S04-076), pending-entitlement filter (S04-077), revoked-grant ignore +
  replacement insert (S04-078), empty-fleet audit-only row with
  `before_pointer = '{"installation":[],"plan":[]}'` (S04-075), and body-ignored (S04-079) all
  match the catalog, including the audit `before_pointer` snapshot shape (S04-074,
  `…:533-545`).
- **S04-080…S04-100 (deprecate/retire state machine):** overlay row contents asserted column-by-
  column (`lifecycle_state`, `successor_id` verbatim, `deprecated_at`, `retire_after` =
  `deprecated_at + 90 days` exactly, `granted_at = revoked_at = changed_at` stamp —
  `assertDeprecatedOverlay`, `stage-04-deprecate-retire-auth.test.ts:210-229`), idempotent
  same-successor deprecate (S04-088), 409 `already_deprecated`/`already_retired`, fail-closed
  `overlap_window_active` for unparseable/NULL `retire_after` (S04-096/097), two-overlay retired
  end state with the deprecate overlay byte-compared unmutated (S04-098,
  `assertRetiredOverlayWrites` `…:259-284`), and body-ignored retire (S04-100).
- **S04-101…S04-104 (wrong-bearer auth):** 401 before route/body handling, with full no-write
  assertions including `countR2Objects() = 0` (S04-101, `…:530`).

### 1.3 Stage 04 verdict

**No silent workarounds found.** No unrecorded deviations, no tautological assertions, no
unjustified [SEED], no missing catalog-mandated side-effect assertions, no missing scenario
coverage (104/104 IDs present as real `it` blocks; verified by ID cross-check against
`phase-15-coverage.md` and by reading all five files end-to-end).

## 2. Stage 05 — Routing policy (S05-001 … S05-085)

Control-plane scenarios S05-001…S05-049 and S05-084/085 are faithful: publish warnings
(`unreferenced_policy`, `latency_class_mismatch`), R2 byte-identity and `contentType`, D1 row
columns, audit before/after pointers (incl. cross-version canary `before_pointer` in S05-025 and
`details.cohort_name` in S05-023), the canary/promote/rollback state machine (C-13
preconditions), and the S05-016/S05-020 seams all match the catalog, and both seams are the ones
the catalog's own Non-automatable notes 1–2 propose. Kill-switch scenarios S05-069/S05-070
correctly use the C-17 control route (`POST /control/kill-switches/arm`,
`stage-05-filters-kill-switch.test.ts:388-396`) rather than [SEED] D1 inserts — the catalog's
preferred path; **no CATALOG STALE finding needed there**. The findings below are the deviations
that were NOT recorded in `stage-05-conflicts.md`.

### 2.1 S05-050, S05-053, S05-055, S05-056, S05-057 — C-01 settlement side effects only half-asserted — WEAK TEST (Medium)

- **Test:** `ai-platform/test/e2e/stage-05-rollback-serving.test.ts:405-413`
  (`assertPostAcceptInternalError`), used at `:574` (S05-050), `:641` (S05-053), `:683`
  (S05-055), `:697` (S05-056), `:708` (S05-057).
- **Catalog expectation:** S05-050 Side effects (and §8 table): "Terminal settlement:
  `state = 'Failed'`, `terminal_error_code = 'internal_error'`, **synthetic `ai_attempt` +
  ledger per `settlePostAcceptInternalError` (C-01)**"; S05-053/055/056/057 repeat it.
- **Actual assertion:** `state === "Failed"`, `terminal_error_code === "internal_error"`,
  `routing_decision` null, and merely `attempts.length >= 1`. The synthetic attempt's contents
  (`outcome = 'terminal_failure'`, `error_code = 'internal_error'`), the **usage_event ledger
  row**, and the **R2 settlement envelope** are never asserted (no `usage_event` reference exists
  in any stage-05 test file).
- **Evidence:** `ai-platform/src/worker.ts:470-501` (`settlePostAcceptInternalError` →
  `settleTerminal` with `attemptsForFailedSettlement([], routing, 'internal_error')`);
  `ai-platform/src/worker.ts:688-720` (`settleTerminal` → `creditUsage` +
  `writeSettlementJournal`); `ai-platform/src/journal/index.ts:409-410` (`INSERT INTO
  usage_event`).
- **Why it matters:** this is exactly the assertion gap class that let BUG-03 (missing-handoff
  settlement silently dropping attempt/credit/usage/envelope) pass undetected in stage 10. The
  post-accept `internal_error` settlement is the same C-01 code path; if it regressed to
  journal-only (no usage_event, no envelope), these five tests would stay green.
- **FIX BRIEF:** Extend `assertPostAcceptInternalError` to assert the synthetic attempt row's
  `outcome = 'terminal_failure'` and `error_code = 'internal_error'`, exactly one `usage_event`
  for the request (zero tokens/cost), and the presence of the R2 envelope at
  `request/{request_id}/envelope` with the `no_provider_attempt` payload shape. No code or
  catalog change needed — the behavior is already correct; the test is under-asserting.

### 2.2 S05-070, S05-071, S05-074 — empty-chain "ledger" side effect not asserted — WEAK TEST (Low)

- **Test:** `ai-platform/test/e2e/stage-05-filters-kill-switch.test.ts:339-371`
  (`expectEmptyChainProviderUnavailable`), used at `:584` (S05-070), `:623` (S05-071), `:713`
  (S05-074).
- **Catalog expectation:** S05-070 Side effects: "`ai_request` terminal state `Failed` with
  `terminal_error_code='provider_unavailable'`; **journal + ledger writes per the settlement
  chapter's failed-settlement behavior**"; S05-071/S05-074 say "as S05-070".
- **Actual assertion:** SSE `failed`/`provider_unavailable`, D1 terminal state, the synthetic
  `ai_attempt` (`outcome`, `error_code`), and the R2 envelope payload
  (`reason: 'no_provider_attempt'`, `excluded` echo) via `syntheticAttemptPayload` (`:373-387`)
  — all strong. Only the **usage_event ledger row** is missing.
- **Evidence:** same `settleTerminal` path as §2.1 (`worker.ts:688-720`;
  `journal/index.ts:409-410`).
- **FIX BRIEF:** Add a one-line `usage_event` count/row assertion per request to
  `expectEmptyChainProviderUnavailable`. Low priority — attempt + envelope are already verified,
  so only the ledger column is unobserved.

### 2.3 S05-063…S05-077, S05-079…S05-081, S05-083 — every invoke bypasses the production config-reader path via unrecorded cache pinning — WEAK TEST (Low)

- **Test:** `ai-platform/test/e2e/stage-05-filters-kill-switch.test.ts:213-251`
  (`SERVE_CACHE_TTL_MS` + `pinServingRoutingPolicy`) and `:253-268` (`invokeVisitSummary` pins
  immediately before POST). Used by all 19 implemented scenarios in the file.
- **Catalog expectation:** each journey is "Publish + promote … Inst-A entitled" then
  `POST /v1/requests` — i.e. the worker's own `preloadRoutingPolicyForInstallation` →
  `createD1ConfigReader` (D1 active-row scan + R2 document load) → `selectCandidateChain` path.
  S05-069/070 additionally specify "Config cache cold so the guard reloads kill switches".
- **Actual:** the test loads the active row itself (`loadServingPolicyRow`, `:223-237` — a
  test-side re-implementation of the reader's `status='active' ORDER BY active_from DESC, rowid
  DESC` query plus R2 fetch) and writes it directly into `isolateConfigCache` with a raised
  30 s TTL. The invoke therefore never exercises the D1/R2 reader for these policy versions; a
  reader regression (wrong status filter, wrong ordering, R2 pointer handling) would be invisible
  to the entire filter/kill-switch file. The workaround (parallel files share
  `isolateConfigCache`; concurrent `clear()`/100 ms TTL expiry between preload and consult throws
  `ConfigCacheMissError`) is legitimate test-isolation engineering, but it is **not recorded** in
  `stage-05-conflicts.md` — the recorded blocks for these IDs cover only 200-vs-202 and
  `routing_decision`-vs-`completed`.
- **Mitigating coverage:** the reader path *is* exercised cold by S05-050…S05-057 in
  `stage-05-rollback-serving.test.ts` (which use `clearConfigCache()` + real preload), so the
  gap is per-policy-version, not total.
- **Evidence:** `ai-platform/src/worker.ts:954-991` (production preload→consult);
  `ai-platform/src/config-cache/index.ts:349-378` (reader scan the pin bypasses).
- **FIX BRIEF:** Record the pinning workaround in `stage-05-conflicts.md` (or the stage-05
  report §6 harness gaps). Prefer a harness fix — per-file isolate cache or a
  `resetE2eState` that does not cross-clear — so the pin can be deleted; alternatively keep one
  unpinned cold-cache invoke per file as a reader-path canary. No code bug indicated.

### 2.4 S05-052, S05-054-b — `routing_decision` read without the persistence poll; cache side effect unasserted — WEAK TEST (Low)

- **Test:** `ai-platform/test/e2e/stage-05-rollback-serving.test.ts:626-628` (S05-052) and
  `:661-663` (S05-054-b) call `parseRoutingDecision(await getAiRequest(ref))` directly, unlike
  the sibling scenarios that use `waitForPersistedDecision` (`:362-374`).
- **Catalog expectation:** S05-052: "`routing_decision.policy_version: 1` (active v1 served)" +
  Side effects "Cache key for inst-A holds the v1 document"; S05-054-b: "(b) normal v1
  routing_decision".
- **Actual:** correct values asserted, but the file's own comment (`:337-344`) states
  `persistRoutingDecision` runs in the post-stream `waitUntil` task and "the harness 150 ms flush
  is not always enough; poll D1 rather than weakening assertions" — these two reads do not poll,
  so they are latent flakes under parallel load (they passed because the failed-provider drain
  currently outlasts the persist). The S05-052 cache-key side effect is also unasserted.
- **FIX BRIEF:** Switch both reads to `waitForPersistedDecision(ref)` (one-line change each).
  Optionally assert the warmed cache key for S05-052 via `isolateConfigCache` inspection, or
  drop that clause from the catalog as unobservable-by-design. No code issue.

### 2.5 S05-051 — catalog-pinned config-cache side effects unasserted — WEAK TEST (Low)

- **Test:** `ai-platform/test/e2e/stage-05-rollback-serving.test.ts:577-611`.
- **Catalog expectation:** Side effects: "Config cache gains key
  `active_routing_policy:routing/standard/018e4f2a-…e2f` holding the v2 row+document, and
  `…/018e4f2a-…f3a` holding the v1 row+document."
- **Actual:** both `routing_decision` payloads are asserted exactly (policy_version, rule_id,
  chain) — the core of the scenario — but the cache-population side effect is not observed.
- **FIX BRIEF:** Either assert both `isolateConfigCache` keys post-invoke (the cache is
  inspectable in-pool), or amend the catalog to mark the cache keys informational. Low priority;
  the canary-vs-active serving split itself is fully verified.

### 2.6 S05-021 — "served identically" side effect not exercised — WEAK TEST (Low)

- **Test:** `ai-platform/test/e2e/stage-05-publish.test.ts:359-373`.
- **Catalog expectation:** Side effects include "When this version is later promoted and served
  (S05-051 journey shape), routing output is identical to the unmodified document — the router
  reads only known fields."
- **Actual:** verbatim R2 storage (`future_field`, rule-level `note`), D1 row, and audit row are
  asserted; the promote-and-serve half is not run.
- **FIX BRIEF:** Optional: extend the test with promote + one invoke asserting the same
  `routing_decision` shape as S05-083, or mark the clause informational in the catalog. The
  router's known-fields behavior is indirectly covered by every other serving scenario, so this
  is cosmetic.

### 2.7 Items checked and cleared (no finding)

- **S05-059 cache re-pin after rollback:** verified that the production rollback route does
  **not** clear the isolate config cache (no `ConfigCache` reference in
  `ai-platform/src/control/routing-policy.ts`; the `isolateConfigCache.clear()` in the harness
  `rollbackPolicy` helper, `test/e2e/harness/control.ts:367-369`, is harness-only). The catalog's
  30 s staleness window is therefore real, and the test's re-pin is a faithful analogue, not a
  bug-hiding workaround. (Scenario itself is already-recorded; not re-reported.)
- **S05-060/061/078/082 skips:** Register 5 #26 router-seam, documented in
  `stage-05-failures.md` and accepted by the prior audit §7. The catalog's Non-automatable note 5
  calls them automatable-via-direct-call, but the frozen harness barrel does not export
  `selectCandidateChain`/`createD1ConfigReader` — a harness limitation, not a silent workaround.
- **S05-053/054 `routing_policy_r2_miss` log:** not asserted; explicitly documented as
  HARNESS-GAP in both the tests and `stage-05.md` §6 — recorded, not silent.
- **S05-058:** catalog itself declares the scenario unreachable/defensive; the test's
  no-`no_matching_rule`-on-the-wire assertion plus a real decision is a faithful rendering.
- **S05-016/020:** seams match catalog Non-automatable notes 1–2 verbatim.
- **S05-077:** degraded-tier derivation via real quota state (`request_quota: 2`,
  `soft_threshold: 0.5`, second request degrades) — no seed; both the standard control and the
  degraded run assert `ai_request.routing_tier` matches the decision tier, as the catalog
  requires.

## 3. Coverage accounting

- **S04-001 … S04-104:** 104/104 implemented as real `it` blocks, 0 skipped, 0 missing
  (mechanical ID cross-check + `phase-15-coverage.md`: S04 104/104).
- **S05-001 … S05-085:** 81 implemented + 4 skipped (S05-060, S05-061, S05-078, S05-082 —
  Register 5 #26, documented), 0 missing (`phase-15-coverage.md`: S05 85/85 accounted).
- Every catalog ID in both chapters is accounted for above: stage 04 in §1.2/§1.3, stage 05 in
  §2.1–§2.7.

## 4. Summary

| Verdict | Count | Items |
|---|---|---|
| CODE BUG | 0 | — |
| TEST WRONG | 0 | — |
| CATALOG WRONG | 0 | — |
| CATALOG STALE | 0 | — (kill-switch tests already use the C-17 route) |
| MISSING COVERAGE | 0 | — (104/104 S04, 85/85 S05 accounted) |
| WEAK TEST | 6 findings | §2.1 (S05-050/053/055/056/057 — C-01 ledger/attempt/envelope under-asserted, **Medium**); §2.2 (S05-070/071/074 — usage_event, Low); §2.3 (S05-063…083 filter file — unrecorded config-cache pinning bypasses the D1/R2 reader, Low); §2.4 (S05-052/054-b — no persistence poll, latent flake, Low); §2.5 (S05-051 — cache side effects, Low); §2.6 (S05-021 — serve-identical clause, Low) |

**Headline:** Stage 04 is clean — the absent conflicts file is genuine (code-derived catalog +
first-pass green), with full side-effect assertion depth throughout. Stage 05 has no hidden code
bugs and no catalog contradicting beyond the already-adjudicated conflicts; the one finding worth
acting on is §2.1 (Medium): the five post-accept `internal_error` scenarios assert the terminal
state but not the C-01-mandated synthetic-attempt contents, `usage_event` ledger row, or R2
envelope — the same assertion gap that masked BUG-03 in stage 10. §2.3's unrecorded cache-pinning
workaround should at minimum be documented in `stage-05-conflicts.md`.


