# AI Platform Catalog — Implementation Review Findings

Static review of `ai-platform/` against `docs/testing/catalog/implementation-work-order.md`.
Date: 2026-09-09. Reviewer: AI agent (static only — no build/run).

**Scope of this file:** major and critical findings only. Items verified as
correctly implemented are listed in the appendix for traceability.

## Table of Contents

1. [Critical findings](#1-critical-findings)
2. [Major findings](#2-major-findings)
3. [Appendix — items verified correct](#3-appendix--items-verified-correct)
4. [Remediation required](#4-remediation-required)

---

## 1. Critical findings

_None. All §2 Worker code fixes (BUG-01, BUG-03…BUG-08) are implemented
correctly._

## 2. Major findings

### M-01 — Invocation-failed path can double-settle if the broker already terminated mid-stream (pre-existing, exposed by BUG-05 review)

- **File:** `ai-platform/src/worker.ts:1148-1215`.
- **Finding:** The invocation-failed settlement path never checks
  `brokerTerminal` and never sets `skipCredit`. If the broker already
  terminally failed mid-stream (e.g. an incremental prose-guard trip at
  `ai-platform/src/stream/index.ts:407-410`, which credits + journals while
  `ignoreBrokerSettlement` is still false) and the invocation then *also*
  fails independently, this path credits and journals a **second** time —
  double Quota DO credit and a duplicate settlement journal for one request.
- The sibling success path (`ai-platform/src/worker.ts:1220-1241`) already
  guards this with `skipCredit: true`; the failed path lacks the symmetric
  guard.
- **Reachability:** narrow — a broker guard-trip does not abort the
  invocation (it runs on `streamContext.signal`), so both must fail
  independently in the same request. Pre-existing, not introduced by the
  BUG-05 fix.
- **Recommended fix:** add `skipCredit: brokerTerminal !== undefined` (or an
  early return when `brokerTerminal` is set) to the failed path, mirroring
  the success path.

---

## 3. Appendix — items verified correct

Chunk 1 (src/ code fixes, verified by direct read):

- **BUG-01 (installation purge / grace rows)** — `ai-platform/src/retention/index.ts:350-355`
  adds `DELETE FROM grace_admission_queue WHERE installation_id = ?` to the D1
  batch before `DELETE FROM installation`. Correct.
- **BUG-04 (UTF-8 mid-codepoint slice)** — `ai-platform/src/provider/raw-body.ts:26-35`
  strips trailing U+FFFD and loop-trims until re-encoded length `<= byteLimit`;
  `truncated: true` preserved. Correct.
- **BUG-06 (TTL 0 same-request consult)** — `ai-platform/src/config-cache/index.ts:98-104`
  treats `expiresAt` inclusively (`now > entry.expiresAt`); positive-TTL
  semantics unchanged. Correct.
- **BUG-07 (kid casing)** — `toCanonicalUuid` added
  (`ai-platform/src/platform-vocabulary.ts:39-42`); applied at all six lifecycle
  handlers' path ids, enroll/rotate/revoke kids, and token-verify lookups
  (`ai-platform/src/identity/index.ts:298-299`). S03-070 restored to the
  lowercase-revoke journey asserting HTTP 200. Correct. Minor residual (not
  major): `entitle`/`support-purge`/`quota-inspect`/`cohort` path ids are not
  canonicalized — an uppercase path id there would 404 against lowercase-stored
  rows; outside the prescribed scope.
- **BUG-08 (entitle idempotency)** — existence pre-check on installation-scope
  grants (`ai-platform/src/control/entitle.ts:219-230, 259-263`) mirroring the
  plan-scope path; sidesteps the partial-unique-index `ON CONFLICT` pitfall.
  S09-027 teardown re-entitle reinstated, asserts 200 + unchanged grant ids.
  Correct.

Chunk 2 (BUG-03 / BUG-05, verified by subagent + spot-checked):

- **BUG-03 (missing-handoff settlement)** — `ai-platform/src/worker.ts:503-585`
  loads the `ai_request` row, resolves the manifest directly via the new
  `getRegisteredManifest` (`ai-platform/src/capability/index.ts:541-551`,
  bypasses access control by design for post-admit settlement), and delegates
  to `settlePostAcceptInternalError` → `settleTerminal` (credit + usage_event +
  R2 envelope + synthetic attempt). S10-034
  (`ai-platform/test/e2e/stage-10-prose-guard-stream.test.ts:1328-1395`)
  rewritten as prescribed, incl. a race-safe polling helper. Correct.
  Minor residuals (not major): two narrow fallback branches
  (capability unregistered / entitlement row missing) still settle
  state-only; entitlement `period_start` lookup is unscoped (relies on the
  one-active-entitlement invariant).
- **BUG-05 (truncation-exhausted drop)** — implemented via drain instead of
  the literal `flushPending()` prescription: the failed path no longer
  disconnects the broker first; it arms `ignoreBrokerSettlement` and awaits
  `brokerRun` before `pushFailedTerminal`
  (`ai-platform/src/worker.ts:1184-1195`). `pushable.end()` drains buffered
  events before done, and the broker-sink filter suppresses only terminal
  events — the provisional `text_delta` passes through. Semantically
  equivalent; no double-credit (broker credit/journal sinks suppressed).
  S10-028 (same file, lines 1000-1052) asserts the exact
  `accepted` → `text_delta("Partial output…", seq 0, provisional)` →
  `failed validation_failed (retry_safe)` sequence plus full settlement.
  Correct. See M-01 for a pre-existing double-settle edge in this path.

Chunk 3 (test rewrites §5/§6 + BUG-06 harness, verified by subagent):

- **T-01 (SX-037)** — FakeAdapter subclass hack and SQL period fake removed
  (`ai-platform/test/e2e/stage-X-ledger-reconciliation-sweep.test.ts:778-881`);
  real Stage 11 settlements, bundled-table pricing (10+20 tokens = 0.005),
  2026-09 period via the SX-051/052 entitlement-roll path. Correct.
- **W-01 (S09-066 / S10-017)** — both drain with `drainAfterStopMs: 250` after
  `accepted` and assert no terminal + no `"Prior request completed."`; dead
  `assertSyntheticCompleted` branch gone; catalog text updated
  (`docs/testing/catalog/stage-09-the-guard.md:785`). Correct.
- **W-02 (S05-050/053/055/056/057)** — `assertPostAcceptInternalError`
  (`stage-05-rollback-serving.test.ts:393-434`) now asserts synthetic-attempt
  fields, one `usage_event`, and the R2 envelope; wired at all five call
  sites. Correct.
- **W-03 (stage-10 credit spy)** — `ai-platform/test/e2e/stage-10-credit-spy.ts`
  exports `spyCreditUsage`/`assertCreditUsage` (call count, `partial`,
  `idempotencyState`, usage; `NO_CREDIT` profile); ~45 call sites across both
  stage-10 files. Correct.
- **W-04 (S09-078)** — injects the real grace-ledger path via
  `runAdmission` + throwing DO, citing Register 5 #28
  (`stage-09-admission-journal-compose.test.ts:928-984`). Correct.
- **W-05 (S09-084)** — unconditional `waitForR2Envelope` (flush + poll),
  leak needles via `leakNeedlesFromSystemInstruction` from the real composer,
  `correlationIds.trace_id === jti` asserted. Correct.
- **W-06 (S06-019)** — full-row `md5(string_agg(r::text …))` over
  `installation_keys`, `app_settings`, and the five `public.*` tables
  (`backend/tests/catalog/stage-06-happy-path-and-lifecycle.sql:125-139`);
  no `xmin`/`xmax`. Correct.
- **W-07 (S00-010)** — imports and calls `resolveConfigCacheTtlMs`; pins pool
  TTL via `isolateConfigCache.getTtlMs()`. Correct.
- **W-08 (S07-052)** — no cache re-seed between the stale GET and the
  post-clear GET. Correct.
- **BUG-06 tests + D-02** — S05-059 / S07-051 exercise real TTL expiry
  (short `setTtlMs` + real sleep, TTL restored in `finally`);
  `ai-platform/vitest.e2e.config.ts:46` sets pool `CONFIG_CACHE_TTL_MS: "0"`.
  Correct.

Chunk 4 (coverage §7, cosmetics §9, low-tier W-items, bug-fix test rewrites —
verified by subagent):

- **C-01 (S06-038)** — soft-deleted K1 row asserted to behave like unknown kid
  (`backend/tests/catalog/stage-06-verify-and-handoff.sql:524-630`). Correct.
- **C-02 (S07-039)** — sunset pairing seeded and asserted
  (`stage-07-etag-cache.test.ts:283-312`). Correct.
- **C-04 (S05-060/061/078/082)** — all four un-skipped via the documented
  `selectCandidateChain` / `createD1ConfigReader` seam (Register 5 #26);
  e2e skip count is exactly **17** (was 21). Correct.
  Minor residual (not major): the 8 remaining stage-00 skips
  (S00-001/002/003, S00-007 throwing arm, S00-012/013/014, S00-028) state
  their reasons inline but lack an explicit `Register 5 #N` citation comment
  (they map to #1, #3, #5, #4). All are pre-existing skips, so DoD item 6
  ("no *new* it.skip without a Register 5 citation") is not violated.
- **C-24 (network_drop)** — union narrowed to `"client_close"` at
  `ai-platform/src/adapter.ts:33`, `src/stream/index.ts:124,473`,
  `src/stream/structured.ts:92,457`. Remaining `network_drop` occurrences are
  a test-local harness option type (`test/stream-broker.test.ts`) and doc/spec
  references only. Correct.
- **S03-079 test (BUG-01)** — asserts HTTP 200 `{}`, both purge audit rows,
  R2 envelopes gone, all D1 tables incl. `grace_admission_queue` empty for I0,
  I2 untouched (`stage-03-revoke-delete-purge.test.ts:741-884`). Correct.
- **S11-018 test (BUG-04)** — asserts `truncated === true`, string payload,
  UTF-8 `byteLength <= 16384`, no U+FFFD at tail, on both captured and stored
  payloads (`stage-11-replay-envelope-grace.test.ts:1166-1236`). Correct.
- **W-09, W-10, W-18, W-19, W-22, W-25, W-28, W-34** — all implemented as
  prescribed (both-keys arm; real `verifyManifestTree`/`hashManifest`;
  post-sweep DO map emptiness; `jtiReplay` eviction; grace-queue attach
  columns; `period === "2026-07"` via `STAGE10_ENTITLE`;
  `count("usage_event") === 0`; stage-09 `afterEach` TTL restore). Correct.

Minor non-blocking observations (not findings):

- `backend/tests/catalog/reports/stage-06-failures.md:437` is a stale
  generated report (pre-C-01 title/detail); the SQL itself is correct.
- BUG-03 fallback branches (capability unregistered / entitlement missing)
  still settle state-only — defensible, genuinely exceptional.
- `entitle`/`support-purge`/`quota-inspect`/`cohort` path ids are not
  canonicalized to lowercase (outside BUG-07's prescribed scope).

---

## 4. Remediation required

### 4.1 M-01 — guard the invocation-failed path against double settlement

**What to fix:** `ai-platform/src/worker.ts:1148-1215`. When the broker has
already emitted a terminal event mid-stream (guard trip → credit + journal)
and the invocation then fails independently, this path settles again —
double Quota DO credit and a duplicate settlement journal.

**Proposed fix:** mirror the success path's guard
(`ai-platform/src/worker.ts:1220-1242`). After `await brokerRun`, check
`brokerTerminal` and skip the credit when the broker already settled:

```typescript
    const taxonomy = isTaxonomyCode(code) ? code : "provider_unavailable";
    log.error("invocation_failed", { code: taxonomy });
    ignoreBrokerSettlement = true;
    await brokerRun;
    pushFailedTerminal(
      sink,
      streamContext.requestReference,
      streamContext.traceId,
      taxonomy,
    );
    if (brokerTerminal !== undefined) {
      // Broker already journaled + credited its terminal mid-stream.
      // Only pin the D1 terminal state; do not settle a second time.
      await recordTerminalState(
        guard.requestId,
        "Failed",
        taxonomy,
        new Date().toISOString(),
        runtimeEnv.DB,
        manifest.interactionMode,
      );
      return;
    }
    await settleTerminal(runtimeEnv, {
      ...terminalBase,
      // ... unchanged ...
```

Notes on the proposal:

- `brokerTerminal !== undefined` is the same discriminator the cancelled
  path (`worker.ts:1155-1179`) and the success path (`worker.ts:1220`)
  already use, so this aligns all three branches on one invariant: **exactly
  one `settleTerminal` per request**.
- An alternative minimal change is `skipCredit: brokerTerminal !== undefined`
  on the existing `settleTerminal` call, but that still writes a second
  journal/attempt set — the early-return variant above is cleaner because the
  broker's journal row already carries the terminal taxonomy.
- **Test to add:** a stage-10 scenario that trips the prose guard mid-stream
  (broker terminal) and then forces the invocation to fail (e.g. adapter
  error after the guard trip), asserting exactly one credit (credit spy from
  `stage-10-credit-spy.ts`), one `usage_event`, and one terminal journal row.

### 4.2 Minor follow-ups (optional, not blocking)

1. **Register 5 citations on stage-00 skips** — add explicit
   `// Register 5 #N` comments to the 8 remaining skips
   (`stage-00-boot-bindings-routing.test.ts:192-200,268,438-446`;
   `stage-00-auth-schema-cron-happy.test.ts:336`), mapping to #1, #3, #5,
   #4 respectively. One-line comments; no behavior change.
2. **Lowercase-canonicalize remaining control-plane path ids** — route
   `entitle.ts:21-26`, `support-purge.ts:85`, `quota-inspect.ts:33`, and
   `cohort.ts:73` `parseInstallationId` through `toCanonicalUuid` so an
   uppercase path id cannot 404 against lowercase-stored rows (consistency
   follow-up to BUG-07).
3. **Regenerate `backend/tests/catalog/reports/stage-06-failures.md`** — the
   generated report at line 437 predates the C-01 soft-delete arm; refresh
   it from the current SQL so reports stop contradicting the suite.
