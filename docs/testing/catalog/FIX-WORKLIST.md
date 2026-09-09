# AI Platform Catalog — Consolidated Fix Worklist (ai/master, 2026-09-06)

**This is the single self-contained work order.** It consolidates
`implementation-audit-findings.md` (recorded-conflict adjudication + remediation-plan
sweep) and the six silent-workaround sweep reports under `sweep/`. Implement everything
here and every automatable catalog scenario verifies architecturally-correct behavior.

- **Scope:** 818 catalog scenarios; 727 Worker E2E tests + 91 SQL-track assertions
  (coverage independently verified — zero gaps, zero extras); all recorded
  `*-conflicts.md` entries adjudicated; remediation plan C-01…C-24 swept at HEAD.
- **Source-of-truth order:** architecture docs (`docs/architecture/ai-platform/`,
  `docs/architecture/14-visits-encounter-workspace.md`) → `remediation-plan.md` →
  catalog chapters → source code (**not** authoritative).

## Rules for the implementer

1. This document is the spec. Current test assertions are **not** authoritative —
   several pin buggy behavior.
2. `ai-platform/src/` and `backend/supabase/migrations/` **are editable** — Part A is
   source fixes.
3. Never weaken a test to make it pass. If a work item seems wrong, stop and flag it.
4. Each code fix lands in **one commit** with its test rewrite **and** its catalog
   text edit (remediation-plan §8).
5. After each part, run the full suites:
   `cd ai-platform && npx vitest run --config vitest.e2e.config.ts` (baseline
   710 passed / 21 skipped / 0 failed) and `bash backend/tests/catalog/run.sh`
   (baseline 8/8). Expect ripple failures beyond the named tests after Part A — fix
   them by updating expectations to the *fixed* behavior, never by weakening.
6. Backend fixes are new migrations only — never edit applied migration files.

---

## Part A — Code bugs (the only remaining source defects)

### A-1. BUG-01 — Installation purge fails with HTTP 500 and leaves a half-purged installation (HIGH)

- **Scenario:** S03-079. **Where:** `ai-platform/src/retention/index.ts:287-354`
  (`purgeByInstallationId`), `ai-platform/migrations/20260821120000_grace_admission_queue.sql:18`.
- **Problem:** the purge D1 batch deletes `ai_attempt`, `usage_event`, `ai_request`,
  `usage_rollup`, `platform_counter`, `capability_grant`, `installation_key`,
  `entitlement`, `installation` — but never `grace_admission_queue`, whose FK references
  `installation`. Any installation with a grace row fails the batch → `runPurge` maps to
  `500 storage_error` (`control/support-purge.ts:21-26`) → D1 rolls back, **but the R2
  envelopes were already deleted** (R2-first ordering). Broken purge + non-atomic
  partial data loss. Architecture expects purge to succeed and delete the footprint
  (`07-ai-platform-d1-r2-storage.md:717`).
- **Code fix:** add `DELETE FROM grace_admission_queue WHERE installation_id = ?` to the
  batch **before** `DELETE FROM installation`.
- **Test rewrite:** `ai-platform/test/e2e/stage-03-revoke-delete-purge.test.ts:740`
  (S03-079, currently titled "happy path" while asserting 500 + R2 gone + D1 unchanged):
  assert HTTP 200 `{}`, both purge audit rows (intent + completion), R2 envelopes gone,
  all D1 tables **including `grace_admission_queue`** empty for I0, I2 untouched.
- **Catalog edit:** S03-079 — grace rows for the purged installation are deleted (the
  old "grace queue survives" claim is schema-impossible under the FK); prior
  `control_audit` history still survives.

### A-2. BUG-03 — Missing-handoff settlement drops attempt, credit, usage, and envelope (HIGH)

- **Scenario:** S10-034. **Where:** `ai-platform/src/worker.ts:503-566`
  (`settleMissingHandoffInternalError`).
- **Problem:** the function rebuilds a `Principal` with `organizationId: ""`,
  `role: ""`, `scopes: []` (L534-545) and calls `resolveCapability`, which rejects
  `forbidden_capability` (`capability/index.ts:256-272`). Result: only
  `recordTerminalState(Failed, internal_error)` runs — no synthetic `ai_attempt`, no
  Quota DO credit, no `usage_event`, no R2 envelope, all of which the catalog requires.
  Revenue accounting and the diagnostic payload are silently dropped on exactly the
  requests that broke.
- **Code fix:** do not reconstruct a hollow principal. The `ai_request` row (already
  loaded at L513-528) carries `installation_id`, `actor_id`, `branch_id`,
  `capability_id`, `capability_version`. Load the manifest directly from the registry by
  `capability_id@capability_version` (the request was already admitted — re-running
  access control on a hollow principal is what breaks), then proceed to
  `settlePostAcceptInternalError` so the synthetic attempt, credit (`partial: true`),
  `usage_event`, and R2 envelope are written.
- **Test rewrite:** `stage-10-prose-guard-stream.test.ts` S10-034 — assert the full
  catalog side effects: one `ai_attempt` (`outcome 'terminal_failure'`,
  `error_code 'internal_error'`), one `usage_event`, one credit visible via DO inspect,
  R2 envelope present.

### A-3. BUG-04 — `captureRawProviderBody` slices UTF-8 mid-codepoint (MEDIUM)

- **Scenario:** S11-018. **Where:** `ai-platform/src/provider/raw-body.ts:24-25`.
- **Problem:** `new TextDecoder().decode(encoded.slice(0, byteLimit))` splits multi-byte
  characters at the 16 384-byte cut → trailing U+FFFD corruption, and the re-encoded
  payload can reach 16 386 bytes, exceeding `ENVELOPE_RAW_BODY_BYTE_LIMIT = 16 * 1024`
  that the catalog pins.
- **Code fix:** after decoding, strip trailing replacement chars
  (`decoded.replace(/\uFFFD+$/, "")`) or loop-trim the last char until
  `TextEncoder().encode(payload).byteLength <= byteLimit`. Keep `truncated: true`.
- **Test rewrite:** `stage-11-replay-envelope-grace.test.ts` S11-018 — restore the
  catalog assertions: `truncated === true`, string payload,
  `encode(payload).byteLength <= 16384`, no trailing U+FFFD (fixture
  `"".padStart(40_000, "…")`).

### A-4. BUG-05 — Truncation-exhausted failure discards the buffered provisional `text_delta` (MEDIUM)

- **Scenario:** S10-028. **Where:** `ai-platform/src/worker.ts:1121-1126, 1181-1211`;
  `invocation/index.ts:749-754`; `stream/index.ts:441-444`.
- **Problem:** with `max_attempts: 1`, truncation exhausts to `validation_failed`; the
  worker arms `ignoreBrokerSettlement`, calls `broker.disconnect("client_close")`, then
  `pushFailedTerminal` — tearing down the stream **before the broker emits the buffered
  truncation chunk**. The client sees `accepted` → `failed` and never receives the
  partial output, while 30 tokens / 0.005 are still billed. Catalog and the
  architecture's provisional-relay model (`09-…-request-response-flow.md:1027-1031`)
  expect `accepted` → `text_delta("Partial output…")` → `failed validation_failed`.
- **Code fix:** flush the broker's pending provisional chunks (or let the broker emit
  the buffered `text_delta`) **before** `pushFailedTerminal` / `disconnect` — e.g. add a
  broker `flushPending()` call before arming `ignoreBrokerSettlement`.
- **Test rewrite:** `stage-10-prose-guard-stream.test.ts` S10-028 — expect
  `accepted` → `text_delta("Partial output…", sequence 0, provisional: true)` →
  `failed` `validation_failed` (`retry_safe: true`).
- **Catalog edit:** reconcile the stage-11 chapter text (S11-006 area), which describes
  the drop, with stage-10's relay expectation — relay wins per architecture.

### A-5. BUG-06 — `CONFIG_CACHE_TTL_MS=0` breaks the Worker's own preload→consult in one request (MEDIUM)

- **Scenarios:** S05-059, S07-051. **Where:**
  `ai-platform/src/config-cache/index.ts:89-115` (`consult` treats `now >= expiresAt`
  as expired; `remember` stamps `expiresAt = now + ttlMs`); consumer
  `worker.ts:954-991`.
- **Problem:** with `ttlMs = 0` every entry expires at birth, so
  `preloadRoutingPolicyForInstallation` (remember) → `selectCandidateChain` (consult)
  throws `ConfigCacheMissError` in the **same request**. "TTL 0 disables caching" —
  which remediation D-02 recommends as the test lever — actually breaks every invoke.
  The e2e pool is pinned to `"100"` (`vitest.e2e.config.ts:42`) partly because of this.
- **Code fix:** make TTL 0 mean "no cross-request caching" without breaking
  intra-request reads: treat `expiresAt === now` as valid in `consult`
  (`now > entry.expiresAt`), or have the preload return the row it just read so the
  same-request consumer never re-consults. Positive-TTL semantics unchanged.
- **Test follow-up:** set the pool TTL to `"0"` (or a small value) per D-02 and rewrite
  S05-059 / S07-051 to exercise real TTL expiry instead of the
  `isolateConfigCache.setTtlMs(30_000)` / `clearConfigCache()` stand-ins.

### A-6. BUG-07 — `kid` casing: enroll accepts uppercase UUID kids, all lookups are case-sensitive (LOW)

- **Scenario:** S03-070. **Where:** `platform-vocabulary.ts:20-21` (case-insensitive
  `CANONICAL_UUID_RE`), `control/lifecycle.ts:419-427` (case-sensitive revoke lookup),
  `identity/index.ts:309` (case-sensitive `keys` lookup at verify).
- **Problem:** an uppercase-enrolled kid (accepted, pinned by S03-036) 404s on a
  lowercase revoke and fails verification if the clinic normalizes casing. UUIDs are
  semantically case-insensitive; the platform accepts a casing at write time it cannot
  match at read time.
- **Code fix:** normalize `kid` (and path installation ids) to lowercase at the
  control-plane write boundary (`handleEnroll`/`handleRotate`); optionally lowercase
  `header.kid` before the `keys` lookup in `identity/index.ts` for defense in depth.
- **Test follow-up:** restore the catalog's original S03-070 journey (lowercase revoke
  body against an uppercase-enrolled kid → HTTP 200).

### A-7. BUG-08 — Entitle is not idempotent on installation-scope grants (LOW)

- **Scenario:** S09-027 teardown. **Where:** `ai-platform/src/control/entitle.ts`
  (installation-scope grant INSERT; plan-scope dedup exists at L239-243).
- **Problem:** re-entitling an installation whose entitlement row was reset but whose
  grants survive hits `idx_capability_grant_live_installation` → `500 storage_error`.
  The one-shot `pending → active` contract (409 `not_pending`) is correct — this is
  only the grant-insert edge.
- **Code fix:** add `ON CONFLICT DO NOTHING` (or an existence pre-check like the
  plan-scope path) to the installation-scope grant INSERT.
- **Test follow-up:** reinstate the S09-027 teardown re-entitle; assert idempotent
  success.

### A-8. BUG-09 — `set_ai_availability` upsert never sets `created_by` (backend, LOW)

- **Scenario:** S02-024. **Where:**
  `backend/supabase/migrations/20260802140000_ai_availability_flag.sql:3-8` (seed omits
  `created_by`), `20260905120100_set_ai_availability_rpc.sql:41-50` (`ON CONFLICT`
  updates `updated_by` only).
- **Fix (new migration):** in the `ON CONFLICT (key) DO UPDATE` clause add
  `created_by = COALESCE(ai_internal.app_settings.created_by, EXCLUDED.created_by)`.
- **Test follow-up:** `backend/tests/catalog/stage-02-availability-and-enroll.sql`
  (S02-024) — assert `created_by` = BOOT user after the update.

### A-9. BUG-10 — `public.get_visit_chief_complaint` missing `REVOKE … FROM PUBLIC/anon` (backend, LOW)

- **Scenario:** S08-069. **Where:**
  `backend/supabase/migrations/20260802120000_context_provider_chief_complaint.sql:65`
  (grants EXECUTE to `authenticated`; PostgreSQL's default EXECUTE-to-PUBLIC remains, so
  `anon` enters the wrapper and fails with `permission denied for schema auth_internal`
  instead of the intended function-level deny; contrast
  `20260821120000_fix_get_ai_availability_security_definer.sql:13`).
- **Fix (new migration):** `REVOKE EXECUTE ON FUNCTION
  public.get_visit_chief_complaint(uuid) FROM PUBLIC, anon;`
- **Test follow-up:** `backend/tests/catalog/stage-08-context-provider-rpc.sql`
  (S08-069) — assert `permission denied for function get_visit_chief_complaint`.

### A-10. BUG-11 — Fresh revoke returns a new `clock_timestamp()`, not the stored `revoked_at` (backend, LOW; remediation C-22)

- **Where:** `backend/supabase/migrations/20260902130100_revoke_last_active_key_guard.sql:49-55`
  (UPDATE stamps `clock_timestamp()`; the success payload then evaluates another one —
  microseconds of drift; only the idempotent path returns the stored value).
- **Fix (new migration, `CREATE OR REPLACE`):** return the stored row's `revoked_at`
  (re-SELECT after UPDATE) on the fresh path too.

### Part A notes — already fixed at HEAD (do not re-fix)

- **C-04 (fabricated `"Prior request completed."` replay of in-flight priors):**
  IMPLEMENTED — `worker.ts:809-811` leaves the stream open with no terminal for
  `admitted` priors; the canned text at L800-807 fires only for genuinely `completed`
  priors (catalog-sanctioned). The residual issue is test-side → Part C-1.
- All other remediation C-items are implemented except C-22 (= A-10) and C-24
  (cosmetic dead code: `network_drop` in the `disconnect` type unions at
  `stream/index.ts:124,473`, `stream/structured.ts:92,457` — optional cleanup).

---

## Part B — Tests that are wrong (silent workarounds that evaded the conflict log)

### B-1. SX-037 — FakeAdapter engineered so the catalog's wrong cost arithmetic passes (MEDIUM)

- **Where:** `ai-platform/test/e2e/stage-X-ledger-reconciliation-sweep.test.ts:344-386`
  (fixture), `:837-845, :857-890` (assertions).
- **Problem:** `spyFakeInputTokens` subclasses FakeAdapter to return
  `usage: { input: N, output: 0 }` so the catalog's adjudicated-wrong figures
  (0.003/0.004/0.001/0.0005 — see SX-002: the real 10-in/20-out settlement prices 30
  tokens at **0.005** per `control/pricing/platform-default/1.json`) pass without a
  conflict record. It also fakes the `2026-09` period via `UPDATE usage_event SET
  period='2026-09'` instead of the catalog's "entitlement period rolled" — which is
  demonstrably possible in-pool (SX-051/052 do it via `entitleInstallation`).
- **Fix:** keep token scripting if varied counts are wanted, but price honestly: either
  use the default 10/20 split and assert real costs (rollups `(I0,2026-08): 2/60/0.010`,
  `(I0,2026-09): 1/30/0.005`, `(I1,2026-08): 1/30/0.005`), or compute expected costs
  from `priceUsage`. Produce the `2026-09` row by re-entitling I0 to a September period
  before the third visit. Record the conflict and fix the catalog text (Part D).

### B-2. S08-063 — `[SEED]` used for a NULL-complaint note that the real RPC creates (LOW)

- **Where:** `backend/tests/catalog/stage-08-context-provider-rpc.sql:417-427`.
- **Problem:** direct `INSERT INTO public.visit_clinical_notes` with `complaint = NULL`,
  justified as "no public RPC can create a NULL-complaint note" — factually incorrect:
  `auth_internal.save_visit_documentation` INSERTs the note with no non-null guard on
  complaint (`20260628140000_visit_documentation_redesign.sql:367-374, 405-411`).
- **Fix:** create the note via the real RPC
  (`public.save_visit_documentation(visit_063, NULL, NULL, NULL, NULL, NULL, NULL)`);
  keep only the `created_at` pin as `[SEED]` (the RPC stamps `now()`). Update the
  report's justification.

---

## Part C — Weak tests to strengthen (assertions that would pass over a regression)

Ordered by severity. Each is test-only unless noted; no code changes.

### C-1. S09-066 / S10-017 — dead replay assertions on the C-04 surface (HIGH)

- **Where:** `stage-09-admission-journal-compose.test.ts:340-390` (S09-066);
  `stage-10-route-retry-idempotency.test.ts:1358` (S10-017).
- **Problem:** `readSseUntil` stops at `accepted`, so the
  `if (completed) assertSyntheticCompleted(…)` block is unreachable — the tests pass
  under both the old (fabricated completion) and fixed (leave-open) behavior. A
  regression re-introducing a fabricated terminal would pass silently.
- **Fix:** keep reading past `accepted` for a bounded window (~250 ms idle timeout or a
  fixed event budget) and assert **no** terminal event and no
  `"Prior request completed."` payload arrives while the prior is `admitted`. Update
  the S09-066 catalog text (Part D).

### C-2. Stage-10 systematic gap — Quota DO credit profile never asserted (MEDIUM, ~22 scenarios)

- **Where:** `stage-10-route-retry-idempotency.test.ts` and
  `stage-10-prose-guard-stream.test.ts` — S10-001, S10-003…S10-010, S10-012…S10-014,
  S10-016, S10-018…S10-027, S10-029…S10-031, S10-033 (S10-028/S10-032 assert only call
  count).
- **Problem:** the catalog pins credit count / `partial` flag / `idempotencyState` /
  usage payload per scenario (e.g. S10-001: credit once, `partial: false`,
  `{tokens: 30, cost: 0.005}`; S10-016/018/019: **no** credit). None of it is asserted
  — a double-credit or wrong-flag regression passes silently. This is the money path.
- **Fix:** add a shared stage-10 helper that spies `creditUsage` (direct-import pattern
  from stage 11, e.g. `stage-11-completed-failed-cancelled.test.ts:658,701`) and
  asserts call count, `partial`, `idempotencyState`, and usage payload; for no-credit
  scenarios assert zero calls. Optionally snapshot DO counters via `gatewayObjectJson`.

### C-3. S05-050/053/055/056/057 — C-01 settlement side effects half-asserted (MEDIUM)

- **Where:** `stage-05-rollback-serving.test.ts:405-413` (`assertPostAcceptInternalError`).
- **Problem:** asserts `Failed`/`internal_error` + `attempts.length >= 1` but never the
  synthetic attempt's contents (`outcome 'terminal_failure'`,
  `error_code 'internal_error'`), the `usage_event` ledger row, or the R2 envelope —
  the same gap class that masked BUG-03.
- **Fix:** extend the helper to assert the synthetic attempt columns, exactly one
  zero-usage `usage_event`, and the R2 envelope at `request/{request_id}/envelope`
  with the `no_provider_attempt` payload shape. Behavior is already correct; the test
  under-asserts.

### C-4. S09-078 — grace-ledger exhaustion path substituted with the live-DO quota path (MEDIUM)

- **Where:** `stage-09-admission-journal-compose.test.ts:669-686`.
- **Problem:** the test entitles `request_quota: 0` against the live DO, so rejection
  comes from the ordinary quota check **before** grace admission runs;
  `isLedgerQuotaExhausted` (`admission/index.ts:507`, called only inside
  `admitUnderGrace`) has **no E2E coverage**. Its four sibling scenarios are Register 5
  #28 skips for the same limitation — S09-078 alone was "implemented" via substitution,
  unrecorded.
- **Fix:** either convert to `it.skip` citing Register 5 #28 (consistency with
  siblings), or cover the grace-ledger branch via a seam that actually enters
  `admitUnderGrace` (grace-mode entitlement + exhausted ledger seed, component-level
  `runAdmission` pattern from stage X). Record the substitution in
  `stage-09-conflicts.md` either way.

### C-5. S09-084 — prompt-leak needles never asserted; envelope assertions conditional on R2 settle (MEDIUM)

- **Where:** `stage-09-admission-journal-compose.test.ts:836-866`.
- **Problem:** the whole envelope assertion block runs only `if (await
  r2Exists(pointer))` with a log-only `else`; the catalog's security-relevant items —
  `systemPromptLeakNeedles` absent from the composed prompt, and
  `correlationIds.trace_id === AAT jti` — are never asserted.
- **Fix:** `flushBackgroundWork()` then poll `r2Exists` with a bounded retry and **fail**
  if the envelope never appears; assert unconditionally; add the leak-needle scan and
  the `trace_id === jti` assertion.

### C-6. S09-063 / S09-064 — preflight boundary scenarios don't hit the boundary (MEDIUM / LOW)

- **Where:** `stage-09-capability-context-preflight.test.ts:786-802` (S09-063 — a
  tautological happy-path rerun), `:804-831` (S09-064 — pads intent treating the
  scaffold byte length as 0, so the estimate overshoots by more than one byte).
- **Fix:** export `promptScaffoldByteLength` (or a test-only estimate helper) through
  the harness; size the intent so the estimate lands exactly on `maxInputTokens`
  (S09-063: admit) and at `maxInputTokens − S + 1` (S09-064: 413). If the export is
  refused, record a conflict and mark the boundary arm deferred — do not substitute a
  happy-path rerun.

### C-7. S07-052 — stale-after-entitle test re-seeds the cache it claims to observe (MEDIUM)

- **Where:** `stage-07-etag-cache.test.ts:558-571`.
- **Problem:** a retry loop calls `isolateConfigCache.remember("entitlements", …)` to
  re-insert the stale row before each GET — if entitle started clearing the cache, the
  loop would still force a pass.
- **Fix:** drop the loop. Warm once, entitle via raw `controlFetch`, then assert the
  next GET is served stale **without** any test-side `remember()` (assert
  `isolateConfigCache.consult("entitlements", id)` still returns the pre-entitle row
  immediately after entitle). Keep the post-`clearConfigCache()` assertion.

### C-8. SX-031 / SX-053 — reconciliation asserted against hand-written SQL, not the code's report (MEDIUM / LOW)

- **Where:** `stage-X-grace-retention.test.ts:1034-1063` (SX-031);
  `stage-X-credit-inspect-do-rpc.test.ts:746-758` (SX-053).
- **Problem:** both re-implement the reconciliation LEFT JOINs in test-local SQL and
  assert against that — tautological w.r.t. the production queries in
  `src/rollup/index.ts:146-168`. SX-040…SX-045 correctly assert on
  `runRollupAndReconciliation(...).report`.
- **Fix:** replace the hand-written SQL with a direct `runRollupAndReconciliation({
  db: env.DB })` call (stage-X precedent) and assert the seeded rows' absence from the
  code-produced report arrays.

### C-9. S06-019 — "mint writes ONLY ai_token_issuance" fingerprints still leak UPDATEs (MEDIUM, SQL track)

- **Where:** `backend/tests/catalog/stage-06-happy-path-and-lifecycle.sql:480-611`.
- **Problem:** partial-column hashes (`kid|revoked_at|updated_at`,
  `key|value_json|updated_at`) + row counts miss UPDATEs of non-fingerprinted columns
  (`secret_key`, `is_deleted`, `deleted_at`, `valid_from`) and **any** UPDATE of a
  `public.*` row. (Dropping `xmax` was correct — the ledger's FK KEY-SHARE lock moves
  it legitimately.)
- **Fix:** hash full rows — `md5(string_agg(s.r::text, E'\n' ORDER BY s.r::text))` over
  `(SELECT t.* FROM <table> t) s` — for `installation_keys`, `app_settings`, and the
  five `public.*` tables. `row::text` excludes system columns and is deterministic
  in-transaction.

### C-10. Low-severity weak tests (one-line fixes)

| Scenario | Where | Fix |
|---|---|---|
| S00-010 | `stage-00-boot-bindings-routing.test.ts:376-402` | Tautological (constant === constant). Import `resolveConfigCacheTtlMs` from `../../../src/config-cache` and assert all four variants return `30_000`; assert `isolateConfigCache.getTtlMs() === 100` |
| S00-030/031 | `stage-00-auth-schema-cron-happy.test.ts:107-131, 385-428` | Re-export the real `verifyManifestTree`/`hashManifest` through the harness barrel and call them instead of the local stand-ins |
| S00-033 | same file `:458-471` | Add the both-keys-present arm: canonical `perRequestTokenCeiling` wins, alias removed |
| S05-070/071/074 | `stage-05-filters-kill-switch.test.ts:339-371` | Add the `usage_event` row assertion to `expectEmptyChainProviderUnavailable` |
| S05-052/054-b | `stage-05-rollback-serving.test.ts:626-628, 661-663` | Switch both `routing_decision` reads to the file's own `waitForPersistedDecision(ref)` poll (latent flake) |
| S05-051 | same file `:577-611` | Optionally assert the two `isolateConfigCache` keys post-invoke, or mark the catalog clause informational |
| S05-021 | `stage-05-publish.test.ts:359-373` | Optional: extend with promote + one invoke asserting identical routing output, or mark the clause informational |
| S09-058 | `stage-09-capability-context-preflight.test.ts:640-659` | Split the either/or: at-maxSize arm asserts exactly 422 `context_invalid`; accepted arm asserts exactly 200 |
| S09-059/060 | same file `:683-695, :727-742` | Assert the valid arm is exactly 200 + `assertAcceptedSse` unconditionally (drop the `!== 422` hedge) |
| S09-074 | `stage-09-admission-journal-compose.test.ts:649-653` | Assert `periodCounters.inFlight` 0 after sweep, 1 after fresh admission (DO inspect seam already in-file) |
| S09-083 | same file `:774-788` | Add DO inspect for `jtiReplay` clearance + `r2Exists` absence check for the envelope |
| S09-085 | same file `:898-915` | Assert the four NULL columns at the guard boundary (right after `accepted`), not conditionally on final state |
| S09-047 | `stage-09-capability-context-preflight.test.ts:377-404` | Add the journaled `lifecycleState: deprecated` assertion, or drop the claim from the catalog (Part D) |
| S09-070/071/072 | `stage-09-admission-journal-compose.test.ts:530-576` | Optional: DO inspect asserting `periodCounters` untouched and no idempotency/jti residue |
| `pinServingRoutingPolicy` TTL leak | `stage-09-admission-journal-compose.test.ts:295-306` | Restore the default TTL in `afterEach` (or return an unpinner) — the helper leaves a 30 s TTL for the rest of the file |
| S10-001 (+ shared helpers) | `stage-10-route-retry-idempotency.test.ts:440`; `stage-10-prose-guard-stream.test.ts:444,457` | Entitle with the catalog's Setup FRESH period (`2026-07-01`, like stage 11's `JULY_ENTITLE`) and assert `usage_event.period === "2026-07"` instead of the `YYYY-MM` regex |
| S10-010 | `stage-10-route-retry-idempotency.test.ts:854+` | Tighten elapsed to `>= 150` (or drop timing, rely on attempt profile); add the zero-usage `usage_event` assertion |
| S11-021 | `stage-11-replay-envelope-grace.test.ts:1310-1384` | After the fallback-keyed second credit, re-query `grace_admission_queue` and assert the attach columns |
| S11-012 | same file `:739-822` | Close the documented harness gap: import `creditUsage` via `loadCreditModule()` (already used for S11-021) and assert the wrapper-mapped `{ ok: false, code: 'unknown_request' }` |
| S12-050 | `stage-12-support-lookup.test.ts:550-605` | Install the `HangFake` spy S12-009 uses so the live race is winnable; keep `seedInvokingRow` as documented fallback only |
| SX-017 | `stage-X-grace-retention.test.ts:447` | Replace the vacuous `getAttempts(graceId)` assertion with `count("usage_event") === 0` / `count("ai_request") === 0` |
| SX-036/039 | `stage-X-ledger-reconciliation-sweep.test.ts:762-766, 955-961` | Assert the log payload is defined before asserting its fields (drop the `if` guards) |
| SX-001/002/003/005/009 log fields | `stage-X-cron-flush-reconcile.test.ts:163-184` | Extend `expectLogOrder`/`expectLogContains` to assert the catalog-pinned payload fields unconditionally; investigate why `scheduled_cron_complete` needs the escape hatch under `LOG_VERBOSITY=2` |
| SX-022 | `stage-X-grace-retention.test.ts:703-714` | Note in `stage-X.md` that the re-open is component-level (`runAdmission`), not the catalog's real POST; optionally assert the `rate_limited` + `retry_after` shape on the blocked admit |
| SX-056 | `stage-X-credit-inspect-do-rpc.test.ts:813-834` | Build the grace row via `runAdmission` + `attachGraceUsage` (SX-001 pattern) instead of raw INSERT; drop the stale barrel justification |
| SX-061/062 | `stage-X-credit-inspect-do-rpc.test.ts:963-999` | Add a post-rejection `inspect` asserting the catalog's "no storage writes" side effect |
| S06 B0 settings pin | `stage-06-happy-path-and-lifecycle.sql:169-183` | Pin only `ai.aat.lifetime_minutes`, or drop the upsert and assert all five seeded values once — so seed drift fails loudly |
| S06-024 | same file `:966-994` | Include `v_create.success` in `v_ok` (fail loudly on `manage_create_branch` regression); add the alphabetical tie-break variant (clear both primary flags, mint, assert Main Branch) |
| S02-024 (role matrix) | `stage-02-revoke-rotate-availability.sql:849-857` | Add receptionist + administrator reads of `get_ai_availability()` (completeness; the function has no role branching) |
