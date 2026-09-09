# AI Platform Catalog — Implementation Work Order

**Give this file to the implementing AI.** It is the single source of remaining
work: every confirmed code bug, every test that must be rewritten, every catalog
text correction, and every coverage gap. Date: 2026-09-06. Branch: `ai/master`.

Evidence lives in `docs/testing/catalog/implementation-audit-findings.md` and
`docs/testing/catalog/sweep/*.md`. Those files are background; this file is the
work order.

## Table of Contents

1. [Working rules](#1-working-rules)
2. [Code bugs — Worker](#2-code-bugs--worker)
3. [Code bugs — Backend](#3-code-bugs--backend)
4. [Tests that pin buggy behavior](#4-tests-that-pin-buggy-behavior)
5. [Tests that are wrong (no code bug)](#5-tests-that-are-wrong-no-code-bug)
6. [Tests that are too weak](#6-tests-that-are-too-weak)
7. [Coverage to add](#7-coverage-to-add)
8. [Catalog text corrections](#8-catalog-text-corrections)
9. [Cosmetic cleanup](#9-cosmetic-cleanup)
10. [Out of scope by design](#10-out-of-scope-by-design)
11. [Execution order](#11-execution-order)
12. [Definition of done](#12-definition-of-done)

---

## 1. Working rules

1. **This file is the spec.** Current test assertions are **not** authoritative —
   several pin buggy Worker behavior. Current `ai-platform/src/` is **not**
   assumed correct — that is why these items exist.
2. **`ai-platform/src/` and backend migrations are editable.** That is the point.
3. **Never weaken a test to make it pass.** If a finding looks wrong, stop and
   flag it. Do not invent a workaround.
4. **One commit per item (or tightly related group):** code fix + test rewrite +
   catalog text edit together (`docs/testing/catalog/remediation-plan.md` §8).
5. **After each batch, run the full suites**, not just the named test files:
   - `npx vitest run --config vitest.e2e.config.ts` from `ai-platform/`
   - `bash backend/tests/catalog/run.sh`
   Expect ripple failures in tests that depended on the old behavior.
6. Architecture citations are already inlined. Read only the cited lines, not
   the 15k-line architecture docs.

---

## 2. Code bugs — Worker

### BUG-01 — Installation purge fails with HTTP 500 and leaves a half-purged installation (HIGH)

- **Scenario:** S03-079.
- **Files:** `ai-platform/src/retention/index.ts:287-354`;
  `ai-platform/src/control/support-purge.ts:21-26`;
  `ai-platform/migrations/20260821120000_grace_admission_queue.sql:18`;
  `ai-platform/test/e2e/stage-03-revoke-delete-purge.test.ts:740-800`;
  `docs/testing/catalog/stage-03-installation-enrollment.md`.
- **Bug:** `purgeByInstallationId` deletes R2 envelopes first, then a D1 batch
  that never deletes `grace_admission_queue`. That table FKs to `installation`.
  Any installation with a grace row fails the batch → `500 storage_error`; D1
  rolls back; R2 objects are already gone. Partial, irreversible data loss.
- **Correct end state:** purge deletes the installation's grace rows too (they
  reference a dead installation). Prior `control_audit` history still survives.
- **Code fix:** In `purgeByInstallationId`, add
  `DELETE FROM grace_admission_queue WHERE installation_id = ?` to the D1 batch
  **before** `DELETE FROM installation`.
- **Test fix:** Rewrite S03-079 to assert HTTP 200 `{}`, both purge audit rows
  (intent + completion), R2 envelopes gone, **all** D1 tables including
  `grace_admission_queue` empty for I0, and I2 untouched.
- **Catalog fix:** S03-079 "grace queue survives" → grace rows for the purged
  installation are deleted.

### BUG-03 — Missing-handoff settlement drops attempt, credit, usage, and envelope (HIGH)

- **Scenario:** S10-034.
- **Files:** `ai-platform/src/worker.ts:503-566`;
  `ai-platform/src/capability/index.ts:256-272`;
  `ai-platform/test/e2e/stage-10-prose-guard-stream.test.ts` (S10-034);
  `docs/testing/catalog/stage-10-accept-route-invoke-stream.md`.
- **Bug:** `settleMissingHandoffInternalError` rebuilds a `Principal` with
  empty `organizationId`/`role`/`scopes`, then `resolveCapability` fails
  `forbidden_capability`. Only `recordTerminalState(Failed, internal_error)`
  runs. No synthetic `ai_attempt`, no Quota DO credit, no `usage_event`, no
  R2 envelope.
- **Code fix:** Do not reconstruct a hollow Principal. Load the manifest
  directly from the registry by `capability_id@capability_version` from the
  existing `ai_request` row, then call `settlePostAcceptInternalError`.
- **Test fix:** Rewrite S10-034 to assert one `ai_attempt`
  (`outcome 'terminal_failure'`, `error_code 'internal_error'`), one
  `usage_event`, one credit (DO inspect), and the R2 envelope present.

### BUG-04 — Raw-body 16 KiB slice splits UTF-8 mid-codepoint (MEDIUM)

- **Scenario:** S11-018.
- **Files:** `ai-platform/src/provider/raw-body.ts:24-25`;
  `ai-platform/test/e2e/stage-11-replay-envelope-grace.test.ts` (S11-018);
  `docs/testing/catalog/stage-11-terminal-settlement.md`.
- **Bug:** `TextDecoder().decode(encoded.slice(0, byteLimit))` on a multi-byte
  cut inserts U+FFFD; re-encoding can exceed 16 384 bytes.
- **Code fix:** After decode, re-clamp so the stored payload's UTF-8 length is
  `<= byteLimit` (drop trailing U+FFFD, or loop-trim last char until
  `TextEncoder().encode(decoded).byteLength <= byteLimit`). Keep
  `truncated: true`.
- **Test fix:** Restore catalog assertions: `truncated === true`, payload is a
  string, `new TextEncoder().encode(payload).byteLength <= 16384`, no U+FFFD
  at the tail.

### BUG-05 — Truncation-exhausted path drops the buffered `text_delta` (MEDIUM)

- **Scenario:** S10-028.
- **Files:** `ai-platform/src/worker.ts:1121-1126, 1184-1192`;
  `ai-platform/src/invocation/index.ts:749-754`;
  `ai-platform/test/e2e/stage-10-prose-guard-stream.test.ts` (S10-028);
  `docs/testing/catalog/stage-10-accept-route-invoke-stream.md`.
- **Bug:** Worker arms `ignoreBrokerSettlement`, disconnects the broker, then
  pushes `failed` — before the broker emits the buffered truncation chunk.
  Client sees `accepted` → `failed`; usage is still billed.
- **Code fix:** Flush/drain pending provisional chunks **before**
  `pushFailedTerminal` (or add `broker.flushPending()` before disconnect).
- **Test fix:** Expect `accepted` → `text_delta("Partial output…", sequence 0,
  provisional: true)` → `failed validation_failed` (`retry_safe: true`).
- **Catalog fix:** Reconcile stage-11's S11-006 text (it currently describes
  the drop) with this stage-10 / architecture expectation.

### BUG-06 — `CONFIG_CACHE_TTL_MS=0` breaks same-request preload→consult (MEDIUM)

- **Scenarios:** S05-059, S07-051.
- **Files:** `ai-platform/src/config-cache/index.ts:89-115`;
  `ai-platform/src/worker.ts:954-991`;
  `ai-platform/vitest.e2e.config.ts:42`.
- **Bug:** `remember` stamps `expiresAt = now + 0`; `consult` treats
  `now >= expiresAt` as expired. The Worker's own preload then consult throws
  `ConfigCacheMissError` in the same request. "TTL 0 disables caching" actually
  breaks every invoke.
- **Code fix:** Treat `expiresAt === now` as still valid (`now > entry.expiresAt`),
  **or** have preload return the row it just read so the same-request consumer
  never re-consults. Keep positive-TTL semantics unchanged.
- **Test fix:** After the code fix, set the e2e pool TTL to `"0"` (or a small
  value) per remediation D-02. Rewrite S05-059 / S07-051 to exercise real TTL
  expiry instead of `isolateConfigCache.setTtlMs(30_000)` / `clearConfigCache()`.

### BUG-07 — `kid` casing: enroll accepts uppercase, lookups are case-sensitive (LOW)

- **Scenario:** S03-070.
- **Files:** `ai-platform/src/platform-vocabulary.ts:20-21`;
  `ai-platform/src/control/lifecycle.ts:419-427`;
  `ai-platform/src/identity/index.ts:309`.
- **Bug:** Enroll validates kids with a case-insensitive UUID regex and stores
  them verbatim; revoke and token verify compare case-sensitively. An
  uppercase-enrolled kid 404s on a lowercase revoke.
- **Code fix:** Lowercase `kid` (and path installation ids) at the control-plane
  write boundary in `handleEnroll` / `handleRotate`. Optionally lowercase
  `header.kid` before the `keys` lookup in `identity/index.ts`.
- **Test fix:** Restore S03-070's original journey (lowercase revoke body
  against an uppercase-enrolled kid → HTTP 200).

### BUG-08 — Entitle is not idempotent on installation-scope grants (LOW)

- **Scenario:** S09-027 teardown.
- **Files:** `ai-platform/src/control/entitle.ts` (installation-scope grant INSERT).
- **Bug:** Plan-scope duplicates are skipped; installation-scope duplicates hit
  `idx_capability_grant_live_installation` → `500 storage_error`.
- **Code fix:** `ON CONFLICT DO NOTHING` (or an existence pre-check like the
  plan-scope path) on the installation-scope grant INSERT.
- **Test fix:** Reinstate the S09-027 teardown re-entitle and assert it
  succeeds idempotently.

---

## 3. Code bugs — Backend

### BUG-09 — `set_ai_availability` upsert never sets `created_by` (LOW)

- **Scenario:** S02-024.
- **Files:** `backend/supabase/migrations/20260905120100_set_ai_availability_rpc.sql:41-50`;
  `backend/supabase/migrations/20260802140000_ai_availability_flag.sql:3-8`.
- **Code fix:** In the `ON CONFLICT` clause add
  `created_by = COALESCE(ai_internal.app_settings.created_by, EXCLUDED.created_by)`.
- **Test fix:** Assert `created_by` = BOOT user in the Stage 02 SQL file.

### BUG-10 — `public.get_visit_chief_complaint` missing `REVOKE FROM PUBLIC/anon` (LOW)

- **Scenario:** S08-069.
- **Files:** `backend/supabase/migrations/20260802120000_context_provider_chief_complaint.sql:65`.
- **Code fix:** New migration:
  `REVOKE EXECUTE ON FUNCTION public.get_visit_chief_complaint(uuid) FROM PUBLIC, anon;`
- **Test fix:** S08-069 asserts `permission denied for function get_visit_chief_complaint`.

### BUG-11 — Fresh revoke returns a new `clock_timestamp()`, not the stored `revoked_at` (LOW)

- **Files:** `backend/supabase/migrations/20260902130100_revoke_last_active_key_guard.sql:49-55`.
- **Code fix:** Return `v_row.revoked_at` (re-SELECT after the UPDATE) in the
  fresh-revoke payload, matching the idempotent branch.

---

## 4. Tests that pin buggy behavior

These land **with** the matching code fix in the same commit.

| Scenario | Test file | Currently asserts | After the fix, assert |
|---|---|---|---|
| S03-079 | `stage-03-revoke-delete-purge.test.ts:740` | HTTP 500 `storage_error`, R2 gone, D1 unchanged | HTTP 200, full D1+R2 purge including grace rows (BUG-01) |
| S10-034 | `stage-10-prose-guard-stream.test.ts` | Failed/internal_error only; no attempt/credit/usage/envelope | Catalog settlement side effects (BUG-03) |
| S11-018 | `stage-11-replay-envelope-grace.test.ts` | Accepts U+FFFD / >16384-byte payload | `truncated`, `<= 16384` bytes, no U+FFFD (BUG-04) |
| S10-028 | `stage-10-prose-guard-stream.test.ts` | No `text_delta` | `accepted` → `text_delta` → `failed validation_failed` (BUG-05) |

---

## 5. Tests that are wrong (no code bug)

### T-01 — SX-037 engineers FakeAdapter so the catalog's wrong cost arithmetic passes

- **File:** `ai-platform/test/e2e/stage-X-ledger-reconciliation-sweep.test.ts:344-386`.
- **Wrong:** Subclasses FakeAdapter to return `usage {input: N, output: 0}` so
  catalog costs 0.003 / 0.004 / 0.001 / 0.0005 pass. Also fakes the `2026-09`
  period via SQL instead of a real entitlement roll.
- **Fix:** Rebuild on real Stage 11 settlements. Price with the bundled table:
  `(input/1000)*0.1 + (output/1000)*0.2`. Default fake-v1 10+20 tokens = **0.005**.
  Use the entitlement-roll path (SX-051/052) for the 2026-09 period.

### T-02 — S08-063 uses an unjustified `[SEED]`

- **File:** `backend/tests/catalog/stage-08-context-provider-rpc.sql`.
- **Wrong:** Seeds a NULL-complaint note claiming "no public RPC can create the
  state". `save_visit_documentation(visit, NULL, …)` inserts that row.
- **Fix:** Create the note via the real RPC. `[SEED]` only the `created_at` pin
  if still needed.

---

## 6. Tests that are too weak

Strengthen these. No Worker change unless a finding already has one.

### High / medium (do these)

| ID | File / scenario | Problem | Fix |
|---|---|---|---|
| W-01 | S09-066 (`stage-09-admission-journal-compose.test.ts`); also S10-017 | `readSseUntil` stops at `accepted`; `if (completed) assertSyntheticCompleted` is dead. Passes under both fabricating and fixed replay. | Drain the replay stream to close (or a bounded timeout). Assert **no** terminal and no `"Prior request completed."` for an `admitted` prior. Update S09-066 catalog text to the leave-open behavior. |
| W-02 | S05-050, S05-053, S05-055, S05-056, S05-057 | Assert `Failed`/`internal_error` + `attempts >= 1` but never the C-01 synthetic-attempt contents, `usage_event`, or R2 envelope. Same gap class that masked BUG-03. | Extend `assertPostAcceptInternalError` to assert synthetic-attempt fields, one `usage_event`, and the R2 envelope. |
| W-03 | ~22 stage-10 scenarios | Catalog pins credit count / `partial` / `idempotencyState` / usage. Only S10-028 / S10-032 assert even call count. | Shared helper that spies `creditUsage` and asserts call count, `partial`, `idempotencyState`, usage; zero calls on no-credit paths. |
| W-04 | S09-078 | Claims grace-ledger exhaustion; entitles `request_quota: 0` against the live DO so `isLedgerQuotaExhausted` never runs. | Convert to `it.skip` citing Register 5 #28, **or** inject the grace-ledger path. Do not leave it claiming a path it does not run. |
| W-05 | S09-084 | Envelope assertions conditional on R2 settle; `systemPromptLeakNeedles` and `correlationIds.trace_id === jti` never asserted. | `flushBackgroundWork()` then poll `r2Exists`; assert needles and `correlationIds.trace_id === jti`. |
| W-06 | S06-019 | "Mint writes ONLY `ai_token_issuance`" is guarded by partial-column hashes + public.* row counts. UPDATEs of unhashed columns pass. | Full-row `md5(string_agg(r::text …))` over `installation_keys`, `app_settings`, and the five `public.*` tables. Do **not** bring `xmax` back. |
| W-07 | S00-010 | Tautological: asserts its own constant table, never calls `resolveConfigCacheTtlMs`. | Import and call `resolveConfigCacheTtlMs` (the unit suite already does). Assert the pool TTL value from `isolateConfigCache.getTtlMs()`. |
| W-08 | S07-052 | Retry loop re-seeds the cache it claims to observe. | Do not re-seed between the stale GET and the post-clear GET. |

### Low (do after the mediums)

| ID | Scenario(s) | Fix |
|---|---|---|
| W-09 | S00-033 | Add the both-keys-present arm: canonical wins, alias removed. |
| W-10 | S00-030/031 | Call real `verifyManifestTree` / `hashManifest` instead of local stand-ins. |
| W-11 | S05-070/071/074 | Assert one `usage_event` per empty-chain request. |
| W-12 | S05-052 / S05-054-b | Use `waitForPersistedDecision(ref)` for `routing_decision` reads. |
| W-13 | S05-051 | Assert both `isolateConfigCache` keys post-invoke, or document why not. |
| W-14 | S09-058 | Split arms: at-maxSize variant asserts exactly 422. |
| W-15 | S09-059/060 | Assert the valid arm is exactly HTTP 200. |
| W-16 | S09-063/064 | Export `promptScaffoldByteLength` (or a test-only estimate) and pad to the real boundary instead of a tautological happy-path rerun. |
| W-17 | S09-074 | Assert the journal row at the guard boundary (immediately after accept). |
| W-18 | S09-083 | After the sweep, inspect the DO and assert the expected map emptiness. |
| W-19 | S09-085 | After the sweep, inspect DO and assert `jtiReplay` no longer holds the jti. |
| W-20 | S10-010 | Tighten elapsed to `>= 150` (or drop timing); add zero-usage `usage_event`. |
| W-21 | S10-017 residual | Drain ~250 ms after `accepted` before asserting `terminalEventTypes === []`. |
| W-22 | S11-021 | After the second `creditUsage`, re-query `grace_admission_queue` and assert attach columns. |
| W-23 | S11-012 | Assert the `creditUsage` wrapper mapping, not only the raw DO RPC `unknown_request`. |
| W-24 | S12-050 | Install a hang spy like S12-009, or drop the live-looking attempt and mark the seed as the real path. |
| W-25 | S10 `usage_event.period` | Entitle stage-10 with catalog Setup FRESH (`2026-07-01` / `2027-01-01`) and assert `period === "2026-07"`. |
| W-26 | SX-031 / SX-053 | Replace hand-written reconciliation SQL with the code's report. |
| W-27 | SX-036 / SX-039 | Assert `purged`/`payload` is defined before asserting its fields. |
| W-28 | SX-017 | Replace tautological grace-id attempt count with `expect(await count("usage_event")).toBe(0)`. |
| W-29 | SX-022 | Document the `runAdmission` substitution in `stage-X.md`, or drive a real `POST /v1/requests`. |
| W-30 | Stage-X log payloads | Extend `parseLogPayload` assertions (unconditional) to catalog-pinned log fields and the closing event. |
| W-31 | S02-024 | Add receptionist + administrator reads for "readable by every authenticated role". |
| W-32 | Stage-06 B0 | Pin only `ai.aat.lifetime_minutes`; do not pin audience/ver/ceiling/window (masks seed drift). |
| W-33 | S06-024 | Include `v_create.success` in `v_ok` (or RAISE on fallback) so the alphabetical tie-break is actually exercised. |
| W-34 | Stage-09 TTL hygiene | Restore default TTL in `afterEach` after any `setTtlMs` helper. |

---

## 7. Coverage to add

| ID | Gap | Fix |
|---|---|---|
| C-01 | S06-038 — soft-deleted key row behaves like unknown (`verify_aat` half) | Soft-delete the K1 row (`is_deleted = true`) and assert the same reject as an unknown kid. |
| C-02 | S07-039 sunset pairing | Seed `lifecycle_state = 'sunset'` on the successor and assert the pairwise listing. |
| C-03 | S09-078 grace-ledger branch | See W-04 — either skip honestly or inject the real path. |
| C-04 | S05-060, S05-061, S05-078, S05-082 (`it.skip`) | Implement via Register 5 #26's documented seam: call `selectCandidateChain` / `createD1ConfigReader` directly (both exported; stage-X files already import non-barrel src modules). Skip count should drop from 21 to 17. |

---

## 8. Catalog text corrections

Doc-only. Tests already match the verified truth. Do **not** change tests for
these rows unless a test is listed in §4–§7.

| Scenario(s) | Change the catalog to say |
|---|---|
| S05-050…S05-083 (accept) | HTTP **200** `text/event-stream` + SSE `accepted` (not 202). Architecture: `09-ai-platform-request-response-flow.md:1029, 1226`. |
| S00-008, S08-034, S08-042, S08-043 | Non-granted unknown capability → 403 `forbidden_capability`. 404 `capability_unknown` only when entitlement passes and the registry misses. Architecture: `01-ai-platform.md:1923-1931`. |
| S08-045 | `quota_exhausted` **does** carry `period_reset` (C-09 implemented). |
| S09-068 | Replay of a failed prior emits the stored taxonomy code, not canned `internal_error` (C-11). |
| SX-002, SX-028, SX-034/035 setups, SX-053, SX-056 | Cost for fake-v1 10+20 tokens is **0.005**, not 0.003. SX-053: 60 tokens / 0.010, not 70 / 0.007. SX-056 expected DO counters must include the three settlements (`{4, 97, 0.022}`). |
| S03-036/066/070/078/079 setup | Replace catalog `XI2` (`dGhJkLzXcVbNm2QeRtYuIoPaSd8f7a9b0c1d2e3f4`) with a 32-byte Ed25519 public key. |
| S09-022 | Last-char-only signature flip is not enough; flip an earlier character too. |
| S00-011, S00-037 | Re-entitle of an active entitlement is 409 `not_pending` (stage-04 S04-049/051). |
| S03-080 | Purge of a non-deleted installation is 409 `illegal_lifecycle_transition` (C-14). |
| S06-019/020/026/032/040/043 | AAT lifetime is **600 s** (10 min seed), not 900 s. |
| S06-033 | SQLSTATE **22023**, not 22P02. |
| S06 B0 usernames | `nadia_h` / `lina_k` / `rami_s` (`[a-z0-9_-]` only). |
| S02-027 | Handoff is reconstructed from the newest active key (K3), not K0. |
| S11-027 | Optimistic concurrency compares `visit_clinical_notes.updated_at`, not `visits.updated_at`. |
| S11-028 / S11-029 | Zero-arg stub is rejected as "Domain function is not configured."; schema-level deny is `permission denied for schema ai_internal`. |
| SX-035 | Unique index forbids two live installation-scope grants for the same installation+capability; seed the fresh control under a different capability_id. |
| S08-053 | `authoritative: true` lives on `result.finalContent`, not the `completed` data root. |
| S09-065 | Replay writes no second row; request 1's own settlement may still mutate its row after `accepted`. |
| S10-005, S10-008 | Per-attempt adapter construction; both bogus attempts are `provider_unavailable`, not empty-queue `internal_error`. |
| S00-032 | `Routing.provider` example throws `Malformed manifest group: Routing` (exact-key validation fires first). |
| S07-040 | Replace the `[SEED]` with the real entitle/activate operation. |
| S07-029, S07-037 | Acknowledge 400-on-empty-grants. |
| S09-045 | Catalog journey should prescribe the version-pin seed the test already uses. |
| S09-047 | Use a registered successor (or document the workaround). |
| S09-066 | In-flight replay leaves the stream open after `accepted`; no fabricated `completed`. |
| S09-070/071/072 | Entitle with the request_quota the test actually uses. |
| SX-014 | Add the missing `[SEED]` label + justification. |
| S06-006 | Setup must deactivate via `set_staff_active(false)` before `delete_staff_member`. |
| S03-079 | After BUG-01: grace rows for the purged installation are deleted (see §2). |

---

## 9. Cosmetic cleanup

- **C-24 (partial):** `AdapterDisconnectReason "network_drop"` remains in
  `ai-platform/src/stream/index.ts:124, 473` and
  `ai-platform/src/stream/structured.ts:92, 457`. All call sites pass
  `"client_close"`. Remove the unused union arm if nothing else references it.
- **Harness (optional):** After BUG-06, adopt `CONFIG_CACHE_TTL_MS=0` per
  remediation D-02. Pin or fail loudly on the silent wrangler compatibility-date
  fallback to 2025-09-06.

---

## 10. Out of scope by design

Do not invent tests for these. They are Register 5 / remediation F-items:

- Live DeepSeek/Gemini wire behavior (Register 5 #33) — `test/eval/live-smoke.test.ts`
  / manual verification.
- Multi-isolate cache divergence, timing-safe compare, real concurrency races,
  DO/D1 fault injection, platform cron triggering, wall-clock horizons
  (17 of 21 current skips).
- Conversational / structured-output / repair paths (remediation F-01…F-08)
  until such manifests ship.
- PostgREST HTTP-level shapes (Register 5 #12) — SQL-level assertions stand.
- SX-063 (`it.skip`) — workerd rejects DO construction with a mock state;
  Register 5 #45 confirmed. Keep the skip.

---

## 11. Execution order

1. **BUG-01** + S03-079 test + catalog text.
2. **BUG-03** + S10-034 test.
3. **BUG-04** + S11-018 test.
4. **BUG-05** + S10-028 test + stage-11 catalog reconcile.
5. **BUG-06** + S05-059 / S07-051 rewrite + pool TTL.
6. **BUG-07 / BUG-08** + S03-070 / S09-027 teardown.
7. **BUG-09 / BUG-10 / BUG-11** (backend migrations + SQL tests).
8. **T-01 / T-02** (SX-037, S08-063).
9. **W-01…W-08** (high/medium weak tests).
10. **§7 coverage** (S06-038, S07-039, S05-060/061/078/082).
11. **§8 catalog text sweep** (can run in parallel with 8–10; never before 1–7
    where the catalog text depends on the code fix).
12. **W-09…W-34** and §9 cosmetics.

---

## 12. Definition of done

1. All §2 and §3 code fixes landed.
2. All §4 and §5 tests rewritten against the *fixed* behavior.
3. W-01…W-08 landed; §7 coverage added (skip count 21 → 17).
4. §8 catalog sweep applied.
5. Full suites green:
   - `npx vitest run --config vitest.e2e.config.ts` (from `ai-platform/`)
   - `bash backend/tests/catalog/run.sh`
6. No new `it.skip` without a Register 5 citation. No test weakened to go green.

What this still cannot verify (and must not claim to): live provider traffic,
multi-isolate races, fault injection, and deferred conversational/structured
paths — §10.
