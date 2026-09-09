# AI Platform Implementation Audit — Findings (ai/master @ HEAD)

Audit of the catalog E2E implementation on `ai/master`, prompted by the discovery that
implementing agents followed "code is authoritative; fixers change the test, record a
conflict, never edit `ai-platform/src/`" — so failing tests were rewritten to match
whatever the Worker does, and the recorded `*-conflicts.md` files treat the Worker as
infallible.

## 1. Method and source-of-truth order

1. **Architecture docs** (`docs/architecture/ai-platform/01-ai-platform.md`,
   `07-…-d1-r2-storage.md`, `08-…-data-journey.md`, `09-…-request-response-flow.md`,
   `docs/architecture/14-visits-encounter-workspace.md`) — the intended behavior.
2. **`docs/testing/catalog/remediation-plan.md`** — the *already adjudicated* backlog.
   Its CODE-FIX items C-01…C-24 are prior decisions that **the code is defective** and
   must change. Its §8 explicitly ordered code fixes **before** scenario implementation;
   the implementers did the reverse and pinned buggy behavior in tests.
3. **Catalog chapters** (`docs/testing/catalog/stage-*.md`) + `registers.md`.
4. **Source code** — *not* assumed correct.

Evidence inputs: all `ai-platform/test/e2e/reports/*-conflicts.md`,
`backend/tests/catalog/reports/*-conflicts.md`, the phase-15 coverage/failure reports,
and direct verification of the current `ai-platform/src/` and `backend/supabase/migrations/`
state (every verdict below was re-checked against HEAD, not taken from the conflict
reports alone).

## 2. Summary

| Class | Count | Items |
|---|---|---|
| Confirmed `ai-platform` bugs the tests now hide | 5 | BUG-01, BUG-03…BUG-06 (§3) |
| `ai-platform` robustness issues (minor) | 2 | BUG-07, BUG-08 (§3) |
| Backend (Supabase) bugs, minor | 3 | BUG-09…BUG-11 (§4) |
| Tests that must be rewritten (they pin buggy behavior) | 4 scenarios | §5.1 |
| Catalog text stale/wrong (tests are correct, fix the catalog) | ~20 scenarios | §5.2 |
| Remediation-plan code fixes never applied | 1 (+1 partial) | C-22, C-24 (§6) |
| Harness-only limitations (acceptable, documented) | 21 skips + 6 clusters | §7 |

> **Correction (2026-09-06, post-sweep):** BUG-02 / C-04 (fabricated
> `"Prior request completed."` replay for in-flight priors) is **implemented at HEAD**
> (`worker.ts:809-811` leaves the stream open with no fabricated terminal). The residual
> issue is test-side only (dead replay assertions in S09-066/S10-017) — see BUG-02 and
> `sweep/stages-07-08-09.md`, `sweep/stages-10-11-12.md`.

The most important meta-finding stands: **remediation-plan §8 was violated** — the
catalog scenarios were implemented against the pre-fix code and tweaked to match it,
instead of the code fixes landing first. Most C-items were eventually applied anyway;
this file plus the `sweep/` directory track what remains.

---

## 3. Confirmed `ai-platform` bugs (code must change; tests currently pin the bug)

### BUG-01 — Installation purge fails with HTTP 500 and leaves a half-purged installation (HIGH)

- **Scenario:** S03-079 (`docs/testing/catalog/stage-03-installation-enrollment.md`).
- **What happens:** `purgeByInstallationId` deletes the R2 envelopes first, then runs one
  D1 batch (`ai-platform/src/retention/index.ts:287-354`) that deletes
  `ai_attempt`/`usage_event`/`ai_request`/`usage_rollup`/`platform_counter`/
  `capability_grant`/`installation_key`/`entitlement`/`installation` — but **never
  `grace_admission_queue`**, whose migration declares
  `FOREIGN KEY (installation_id) REFERENCES installation(installation_id)`
  (`ai-platform/migrations/20260821120000_grace_admission_queue.sql:18`). Any
  installation with a grace-queue row therefore fails the batch on the FK, `runPurge`
  maps it to `500 storage_error` (`ai-platform/src/control/support-purge.ts:21-26`),
  D1 rolls back — **but the R2 envelopes are already deleted**. Result: purge API is
  broken for exactly the installations that used grace admission, and the failure mode
  is a non-atomic, partially-applied purge (payloads gone, journal rows remain).
- **Architecture says:** "Operator `POST …/purge` on an installation deletes its journal
  and envelopes immediately" (`07-ai-platform-d1-r2-storage.md:717`) — a successful,
  complete purge. The catalog's "grace queue survives" sub-claim is schema-impossible
  (FK); the correct end state is that purge deletes the installation's grace rows too
  (they reference a dead installation and are useless), which also matches the
  grace-reconcile design (rows exist only to retry credit for live installations).
- **Test currently pins the bug:** `ai-platform/test/e2e/stage-03-revoke-delete-purge.test.ts:740-800`
  — titled *"Purge happy path removes the full installation footprint from D1 and R2"*
  but asserts `500 storage_error`, R2 envelopes **deleted**, and the D1 footprint
  **unchanged**. A "happy path" test asserting total failure + partial data loss.
- **Fix brief (code):** In `purgeByInstallationId`, add
  `DELETE FROM grace_admission_queue WHERE installation_id = ?` to the D1 batch **before**
  the `DELETE FROM installation` statement. Update the S03-079 catalog text: grace rows
  for the purged installation are deleted (not preserved); prior `control_audit` history
  still survives.
- **Fix brief (test):** Rewrite S03-079 to assert HTTP 200 `{}`, both purge audit rows
  (intent + completion), R2 envelopes gone, **all** D1 tables including
  `grace_admission_queue` empty for I0, and I2 untouched.

### BUG-02 — Idempotent replay of an in-flight request fabricates a fake `completed` result (HIGH — remediation C-04) — **FIXED AT HEAD; residual test weakness**

- **Scenarios:** S10-017, S08-053, S09-066; remediation plan C-04 / Register 4 #71.
- **Correction (2026-09-06 sweep):** this audit originally recorded C-04 as NOT
  IMPLEMENTED based on the canned `"Prior request completed."` block at
  `worker.ts:804`. That was wrong: the canned block only fires for
  `prior.state === "completed"` (`worker.ts:800-807` — replaying a genuinely completed
  request, which the catalog sanctions). The `admitted` (in-flight) branch at
  `worker.ts:809-811` now reads *"In-flight replay: leave the stream open after
  `accepted` — no fabricated terminal."* and returns without emitting any terminal.
  **C-04 is implemented; there is no code bug here at HEAD.**
- **Residual issue (test-side, MEDIUM):** the replay tests were not strengthened after
  the fix — S09-066's `readSseUntil` stops at `accepted`, making its
  `if (completed) assertSyntheticCompleted(…)` block dead code that passes under both
  the old (fabricating) and new (fixed) behavior; S10-017 has the same blind spot for
  later chunks. A regression re-introducing a fabricated terminal would pass silently.
- **Fix brief (test):** In S09-066 (`stage-09-admission-journal-compose.test.ts`) and
  S10-017 (`stage-10-route-retry-idempotency.test.ts`), drain the replay stream to
  close (or a bounded timeout) and assert NO terminal event arrives and no
  `"Prior request completed."` payload appears for an `admitted` prior. Refresh the
  S09-066 catalog text to describe the leave-open behavior.

### BUG-03 — Missing-handoff settlement path is broken: no attempt, no credit, no usage, no envelope (HIGH — remediation C-01 applied but defective)

- **Scenario:** S10-034 (`docs/testing/catalog/stage-10-accept-route-invoke-stream.md`).
- **What happens:** `settleMissingHandoffInternalError`
  (`ai-platform/src/worker.ts:503-566`) rebuilds a `Principal` with
  `organizationId: ""`, `role: ""`, `scopes: []` (L534-545) and then calls
  `resolveCapability`, which rejects with `forbidden_capability` (empty role/scopes fail
  the manifest's `requiredCapabilityScope` / `allowedStaffRoles` checks,
  `ai-platform/src/capability/index.ts:256-272`). The function logs
  `missing_handoff_settle_capability_unresolved` and only calls
  `recordTerminalState(Failed, internal_error)`. The catalog-required side effects —
  one synthetic `ai_attempt` (`terminal_failure`/`internal_error`), one Quota DO
  `credit` (`partial: true`), one `usage_event`, one R2 envelope — **never happen**.
  The request settles with no usage accounting and no diagnostic payload, and the DO
  admission reservation is never credited/released here.
- **Why it matters:** this is the settlement path for the "accept context lost"
  failure; as implemented it silently drops revenue accounting and leaves the
  diagnostic envelope absent, so support lookup for exactly these broken requests has
  no payload.
- **Test currently pins the bug:** `stage-10-prose-guard-stream.test.ts` S10-034 asserts
  only the `Failed`/`internal_error` terminal state and the absence of the synthetic
  attempt/credit/usage/envelope.
- **Fix brief (code):** The missing-handoff path already has the `ai_request` row
  (L513-528) with `installation_id`, `actor_id`, `branch_id`, `capability_id`,
  `capability_version`. Do not reconstruct a synthetic `Principal` for capability
  resolution — load the manifest directly from the registry by
  `capability_id@capability_version` (the request was already admitted; re-running
  access control on a hollow principal is what breaks). Then proceed to
  `settlePostAcceptInternalError` so the synthetic attempt, credit (`partial: true`),
  usage_event, and R2 envelope are written as the catalog specifies.
- **Fix brief (test):** Rewrite S10-034 to assert the catalog side effects: one
  `ai_attempt` (`outcome 'terminal_failure'`, `error_code 'internal_error'`), one
  `usage_event`, one credit observed via DO inspect, and the R2 envelope present.

### BUG-04 — `captureRawProviderBody` slices UTF-8 mid-codepoint: corrupted payload and >16 KiB re-encode (MEDIUM)

- **Scenario:** S11-018 (`docs/testing/catalog/stage-11-terminal-settlement.md`).
- **What happens:** `ai-platform/src/provider/raw-body.ts:24-25` does
  `new TextDecoder().decode(encoded.slice(0, byteLimit))`. When the 16 384-byte cut
  splits a multi-byte character, the decoder inserts U+FFFD — the stored envelope
  payload is (a) corrupted at the tail and (b) up to **16 386 bytes** when re-encoded,
  exceeding the documented `ENVELOPE_RAW_BODY_BYTE_LIMIT = 16 * 1024` the catalog pins
  ("payload is a string of at most 16 384 bytes").
- **Test currently pins the bug:** `stage-11-replay-envelope-grace.test.ts` S11-018 was
  rewritten to accept the helper's corrupted/oversized output instead of the catalog's
  ≤16 384-byte contract (the multi-byte fixture `"".padStart(40_000, "…")` was chosen
  precisely to expose this; the test now looks away).
- **Fix brief (code):** After decoding, re-clamp:
  `const decoded = new TextDecoder().decode(encoded.slice(0, byteLimit));` then store a
  payload whose UTF-8 encoding is `≤ byteLimit` — e.g. drop a trailing U+FFFD
  (`decoded.replace(/\uFFFD+$/, "")`) or loop-trim the last char until
  `TextEncoder().encode(decoded).byteLength <= byteLimit`. Keep `truncated: true`.
- **Fix brief (test):** Restore the catalog assertions in S11-018: `truncated === true`,
  payload is a string, and `new TextEncoder().encode(payload).byteLength <= 16384`,
  with no U+FFFD at the tail.

### BUG-05 — Truncation-exhausted failure discards the buffered provisional `text_delta` (MEDIUM)

- **Scenario:** S10-028 (`docs/testing/catalog/stage-10-accept-route-invoke-stream.md`).
- **What happens:** with `max_attempts: 1`, a truncated provider stream exhausts via
  `exhaustedViaTruncation` → `validation_failed`
  (`ai-platform/src/invocation/index.ts:749-754`). The worker then arms
  `ignoreBrokerSettlement = true`, calls `broker.disconnect("client_close")`, and pushes
  the `failed` terminal itself (`ai-platform/src/worker.ts:1121-1126, 1184-1192`). The
  disconnect tears the stream down **before the broker emits the buffered truncation
  chunk**, so the client sees `accepted` → `failed` and never receives the partial
  output — while the usage (30 tokens / 0.005) is still billed. The catalog expects
  `accepted` → `text_delta("Partial output…")` → `failed validation_failed`, matching
  the architecture's provisional-relay model (`09-…-request-response-flow.md:1027-1031`:
  `text_delta` events are relayed as provisional tokens). Note the catalog is
  self-inconsistent here — stage-11's chapter (S11-006 area) describes the drop — but
  the stage-10 expectation matches the architecture; the drop is the defect.
- **Test currently pins the bug:** `stage-10-prose-guard-stream.test.ts` S10-028 asserts
  **no** `text_delta` is emitted.
- **Fix brief (code):** In the worker's invocation-failure branch
  (`worker.ts:1181-1211`), flush/drain the broker's pending provisional chunks (or let
  the broker emit its buffered `text_delta` before `disconnect`) **before**
  `pushFailedTerminal`. Concretely: reorder to `await brokerRun`-settled flush → push
  failed terminal → disconnect, or add a broker `flushPending()` call prior to arming
  `ignoreBrokerSettlement`.
- **Fix brief (test):** Rewrite S10-028 to expect `accepted` →
  `text_delta("Partial output…", sequence 0, provisional: true)` → `failed`
  `validation_failed` (`retry_safe: true`), and reconcile the stage-11 catalog text.

### BUG-06 — `CONFIG_CACHE_TTL_MS=0` breaks the Worker's own preload→consult within one request (MEDIUM)

- **Scenarios:** S05-059, S07-051 (conflict reports); remediation D-02.
- **What happens:** `ConfigCache.remember` stamps `expiresAt = now + ttlMs`
  (`ai-platform/src/config-cache/index.ts:105-115`) and `consult` treats
  `now >= expiresAt` as expired (L89-103). With `ttlMs = 0` every entry expires at
  birth, so the request path `preloadRoutingPolicyForInstallation` (remember) →
  `selectCandidateChain` (consult) throws `ConfigCacheMissError` **in the same request**
  (`ai-platform/src/worker.ts:954-991`). "TTL 0 disables caching" — which remediation
  D-02 recommends as the test lever — actually breaks every invoke. The e2e pool is
  pinned to `CONFIG_CACHE_TTL_MS: "100"` (`vitest.e2e.config.ts:42`) partly because of
  this, and S05-059's catalog TTL-staleness journey (30 s window) cannot be observed.
- **Fix brief (code):** Make TTL 0 mean "no cross-request caching" without breaking
  intra-request reads: either treat `expiresAt === now` as valid in `consult`
  (`now > entry.expiresAt`), or have the preload return the row it just read so the
  same-request consumer never re-consults. Keep positive-TTL semantics unchanged.
- **Fix brief (test):** After the code fix, set the e2e pool TTL to `"0"` (or a small
  value) per D-02 and rewrite S05-059 / S07-051 to exercise real TTL expiry instead of
  the `isolateConfigCache.setTtlMs(30_000)` / `clearConfigCache()` stand-ins.

### BUG-07 — `kid` casing: enroll accepts uppercase UUID kids, all lookups are case-sensitive (LOW)

- **Scenario:** S03-070 (conflict report).
- **What happens:** enroll validates `kid` with a case-**insensitive** canonical-UUID
  regex (`ai-platform/src/platform-vocabulary.ts:20-21`) and stores it verbatim, but
  revoke-key binds `body.kid` case-sensitively
  (`ai-platform/src/control/lifecycle.ts:419-427`) and token verification looks up
  `loadConfig(…, "keys", header.kid)` case-sensitively
  (`ai-platform/src/identity/index.ts:309`). An uppercase-enrolled kid (which S03-036
  pins as accepted) 404s on a lowercase revoke and would fail verification if the
  clinic ever normalizes casing. UUIDs are semantically case-insensitive; the platform
  accepts a casing at write time that it cannot match at read time.
- **Catalog side:** S03-070's fixture (enroll uppercase, revoke lowercase) is what
  exposed this; the test now revokes with the stored uppercase kid.
- **Fix brief (code):** Normalize `kid` (and path installation ids) to lowercase at the
  control-plane write boundary (`handleEnroll`/`handleRotate` in `control/lifecycle.ts`)
  so stored kids are canonical; optionally lowercase `header.kid` before the `keys`
  lookup in `identity/index.ts` for defense in depth.
- **Fix brief (test):** After normalization, restore the catalog's original S03-070
  journey (lowercase revoke body against an uppercase-enrolled kid → HTTP 200).

### BUG-08 — Entitle is not idempotent on installation-scope grants (LOW)

- **Scenario:** S09-027 teardown (conflict report).
- **What happens:** `entitleInstallation` INSERTs `capability_grant` rows; plan-scope
  duplicates are deduped (`ai-platform/src/control/entitle.ts:239-243`, Register 4 #19)
  but installation-scope duplicates hit `idx_capability_grant_live_installation` and
  surface as `500 storage_error`. Re-entitling an installation whose entitlement row was
  reset but whose grants survive (exactly the S09-027 `[SEED] DELETE FROM entitlement`
  restore path) fails. The mainline one-shot `pending → active` contract
  (`not_pending` 409) is correct per the stage-04 catalog (S04-049/051) — this is only
  the grant-insert edge.
- **Fix brief (code):** Add `ON CONFLICT DO NOTHING` (or an existence pre-check like the
  plan-scope path) to the installation-scope grant INSERT in `control/entitle.ts`.
- **Fix brief (test):** Reinstate the S09-027 teardown re-entitle and assert it
  succeeds idempotently.

---

## 4. Backend (Supabase) bugs — minor, recorded for completeness

### BUG-09 — `set_ai_availability` upsert never sets `created_by` (LOW)

- **Scenario:** S02-024 (`backend/tests/catalog/reports/stage-02-conflicts.md`).
- Seed `INSERT` into `ai_internal.app_settings` omits `created_by`
  (`backend/supabase/migrations/20260802140000_ai_availability_flag.sql:3-8`) and the
  RPC's `ON CONFLICT (key) DO UPDATE` writes only `value_json`/`updated_at`/`updated_by`
  (`20260905120100_set_ai_availability_rpc.sql:41-50`), so after any update the row has
  `created_by NULL` — the catalog expects the first writer recorded.
- **Fix brief:** In the `ON CONFLICT` clause add
  `created_by = COALESCE(ai_internal.app_settings.created_by, EXCLUDED.created_by)`.
  Rewrite the S02-027-adjacent SQL assertion in
  `backend/tests/catalog/stage-02-availability-and-enroll.sql` to expect
  `created_by` = BOOT user.

### BUG-10 — `public.get_visit_chief_complaint` missing `REVOKE … FROM PUBLIC/anon` (LOW)

- **Scenario:** S08-069 (`backend/tests/catalog/reports/stage-08-conflicts.md`).
- The wrapper is SECURITY INVOKER and grants `EXECUTE` to `authenticated` only, but
  never revokes the PostgreSQL default `EXECUTE … TO PUBLIC`
  (`backend/supabase/migrations/20260802120000_context_provider_chief_complaint.sql:65`).
  `anon` therefore enters the wrapper and fails with `permission denied for schema
  auth_internal` instead of the intended function-level deny. Net access control still
  holds (deny either way); the leak is only error-shape/hardening. Contrast
  `get_ai_availability`, which does revoke
  (`20260821120000_fix_get_ai_availability_security_definer.sql:13`).
- **Fix brief:** New migration: `REVOKE EXECUTE ON FUNCTION
  public.get_visit_chief_complaint(uuid) FROM PUBLIC, anon;`. Update the S08-069 SQL
  test to assert `permission denied for function get_visit_chief_complaint`.

### BUG-11 — Fresh revoke returns a new `clock_timestamp()`, not the stored `revoked_at` (LOW — remediation C-22, never applied)

- `backend/supabase/migrations/20260902130100_revoke_last_active_key_guard.sql:49-55`:
  the UPDATE stamps `revoked_at = clock_timestamp()` and the success payload then
  evaluates **another** `clock_timestamp()`, which can differ by microseconds from the
  stored value; only the idempotent path (L29-31) returns the stored value.
- **Fix brief:** Return `v_row.revoked_at` (re-SELECT after the UPDATE) in the
  fresh-revoke payload, mirroring the idempotent branch.

---

## 5. Test verdicts

### 5.1 Tests that are WRONG and must be rewritten (they pin buggy code)

| Scenario | Test file | What it wrongly asserts | Underlying bug |
|---|---|---|---|
| S03-079 | `ai-platform/test/e2e/stage-03-revoke-delete-purge.test.ts:740` | "Happy path" purge → HTTP 500 `storage_error`, R2 deleted, D1 unchanged | BUG-01 |
| S10-034 | `ai-platform/test/e2e/stage-10-prose-guard-stream.test.ts` | Missing-handoff settle → terminal state only; no attempt/credit/usage/envelope | BUG-03 |
| S11-018 | `ai-platform/test/e2e/stage-11-replay-envelope-grace.test.ts` | Envelope payload may contain U+FFFD and exceed 16 384 bytes | BUG-04 |
| S10-028 | `ai-platform/test/e2e/stage-10-prose-guard-stream.test.ts` | Truncation-exhausted → no `text_delta`, straight to `failed` | BUG-05 |

(S10-017 / S08-053 were removed from this list in the post-sweep correction — the
in-flight replay fabrication is fixed at HEAD; their residual weakness is dead
assertions, tracked in BUG-02 and the sweep files. The sweep additionally found two
TEST WRONG cases outside the recorded conflicts: **SX-037** (engineered FakeAdapter
usage `{output: 0}` to make the catalog's wrong cost arithmetic pass) and **S08-063**
(unjustified `[SEED]` — a real RPC produces the state) — see `sweep/stage-X-and-coverage.md`
and `sweep/sql-track.md`.)

Each rewrite must land **with** its code fix and a catalog text edit in the same commit
(remediation-plan §8's rule, applied retroactively).

### 5.2 Catalog text stale/wrong — the tweaked tests are CORRECT (fix the catalog, keep the test)

These are the conflicts where the implementers' "code is authoritative" instinct
happened to be right, verified against the architecture docs:

| Scenario(s) | Catalog claim | Verified truth | Evidence |
|---|---|---|---|
| S05-050…S05-083 (all invoke accepts) | HTTP **202** accept | HTTP **200** `text/event-stream`; SSE `accepted` carries the semantics | `09-…-request-response-flow.md:1029` "HTTP status is already 200"; `:1226` "Post-`accepted` failures … HTTP still 200" |
| S00-008, S08-034, S08-042, S08-043 | Unknown/unpublished capability → 404 `capability_unknown` | Guard stage 3 (entitlement) runs **before** stage 5 (resolve) per the architecture's own stage table; a non-granted unknown id → 403 `forbidden_capability`. `capability_unknown` is reachable only when entitlement passes and the registry misses (S09-044/045) | `01-ai-platform.md:1923-1931` (stage 3 → `forbidden_capability`; stage 5 → `capability_unknown`) |
| S08-045 | `quota_exhausted` carries **no** `period_reset` | Remediation **C-09 was implemented**: admission computes `periodReset` and the worker forwards it (`worker.ts:1321-1322`); emitting it is the *desired* end state | `admission/index.ts:460-468`; stage-09 doc-drift #1 marked "Fixed (C-09)" |
| S09-068 | Replay of failed prior → canned `internal_error` | Remediation **C-11 was implemented**: the DO idempotency entry stores `terminalErrorCode` and replay emits the original code (`provider_unavailable`) | `worker.ts:815-817`; `quota-do/index.ts:349-359, 400-409` |
| SX-002 (and SX-028, SX-034/035 setups) | Settlement cost **0.003** for 30 tokens | Stage-11's own fixture math: `(10/1000)*0.1 + (20/1000)*0.2 = ` **0.005** with the bundled pricing table (`control/pricing/platform-default/1.json`, `fake-v1` 0.1/0.2 per 1k). Stage-X chapter arithmetic is wrong | `stage-11-terminal-settlement.md:5`; `src/pricing/index.ts` |
| S03-036/066/070/078/079 (setup) | Catalog key `XI2` (`dGhJkLzXcVbNm2QeRtYuIoPaSd8f7a9b0c1d2e3f4`) enrolls successfully | The fixture base64url-decodes to **30 bytes**; Ed25519 public keys are 32 bytes → correct 400 `invalid_payload`. Tests' `generateTestKeypair()` substitution is legitimate; fix the catalog fixture | `platform-vocabulary.ts:53-61` |
| S09-022 | Flipping the AAT signature's **last** character breaks verification | Ed25519 signatures are 64 B = 86 base64url chars with 4 unused trailing bits; a last-char flip can decode identically. The test's variant (a) (flip an earlier char too) is the correct fixture | `identity/index.ts:330-348` |
| S00-011, S00-037 | Re-entitle an **active** entitlement with `allowed_capabilities: []` → HTTP 200 | Entitle is one-shot `pending → active`; re-entitle → 409 `not_pending` is the stage-04 catalog's own pinned contract (S04-049/051). Stage-00 chapter contradicts it; stage-04 is authoritative for entitle | `control/entitle.ts:199-201` |
| S03-080 | Purge on an `active` installation succeeds | Remediation **C-14 was implemented**: non-deleted → 409 `illegal_lifecycle_transition`. Test already correct (`stage-03-revoke-delete-purge.test.ts:863`) | `control/support-purge.ts:100-105` |
| S06-019/020/026/032/040/043 | AAT lifetime 900 s (15 min seed) | Remediation **C-03 was applied**: seed + fallback are 10 min → 600 s, matching the platform's `exp − iat ≤ 600` verifier ceiling. Catalog text stale | `20260905120000_fix_aat_lifetime_minutes_seed.sql`; `20260905120300_fix_aat_lifetime_fallback.sql` |
| S06-033 | Uncoded cast → SQLSTATE `22P02` | jsonb-string→numeric cast raises **`22023`**; test correct | `stage-06-conflicts.md` #5 |
| S06 B0 usernames | `nadia.h` / `lina.k` / `rami.s` | `auth_internal.assert_valid_username` allows `[a-z0-9_-]` only; underscore substitutions correct | `20260521190000_*` |
| S02-027 | Reconstruct handoff from `kid = K0` | By that point in the journey K0/K2 are revoked; the live key is K3. Test follows the real keystore | `stage-02-conflicts.md` |
| S11-027 | Staleness compares against `visits.updated_at` | Architecture pins optimistic concurrency on **`visit_clinical_notes.updated_at`** ("one row per visit; optimistic concurrency via `updated_at`", `14-visits-encounter-workspace.md:30`). Code matches architecture; the T0−1 s test input only compensates for transaction-stable `now()` in the single-transaction SQL harness | `20260628140000_visit_documentation_redesign.sql:382-388` |
| S11-028 / S11-029 | Zero-arg stub reaches the missing-id RAISE; table-level deny message | Zero-arg functions are rejected earlier ("Domain function is not configured."); schema-level `REVOKE` produces a schema-level 42501. Both are code-consistent; tests correct | `20260802150000_ai_acceptance_recording.sql:114-117`; `20260803140000_b1_review_resolution.sql:7-8` |
| SX-035 | Two live installation-scope grants for one installation+capability | `idx_capability_grant_live_installation` intentionally forbids it; seeding the fresh control under a different capability_id is correct | `20260805190000_routing_policy_status.sql:20-22` |
| S08-053 (`authoritative` placement) | `authoritative: true` on the `completed` **data root** | The stage-11 catalog (settlement owner) puts it on `result.finalContent`; the architecture does not specify. Code matches stage-11; stage-08's orientation note is the outlier | `stage-11-terminal-settlement.md:55`; `worker.ts:804` |
| S09-065 | Replay leaves the first request's journal row "untouched" | Imprecise wording: request 1's **own settlement** legitimately mutates its row after `accepted` (`persistPostResponseDetail`, `persistRoutingDecision`, `journalTransition`). The replay itself writes no second row — which is what the test asserts. Improvement (optional): settle request 1 to terminal *before* the replay, then assert the row is frozen | `journal/index.ts`; `phase-15-conflicts.md` |
| S10-005, S10-008 | Shared FakeAdapter queue exhausts → attempt 2 `internal_error` | `resolveProviderPort` constructs a fresh adapter per attempt (`worker.ts:351-366`); production adapters are stateless, so per-attempt construction is correct and the empty-queue branch is a fixture artifact. Tests correctly assert `provider_unavailable` on both attempts | `worker.ts:366` |

---

## 6. Remediation-plan (C-01…C-24) implementation sweep at HEAD

The remediation plan demanded code fixes **before** scenario implementation. Actual
state at `ai/master` HEAD:

| Item | State | Evidence |
|---|---|---|
| C-01 settle post-accept routing/missing-policy failures | IMPLEMENTED for the routing/invocation paths (`worker.ts:1064-1081, 1146-1211`); **DEFECTIVE for the missing-handoff path** → BUG-03 | `worker.ts:503-566` |
| C-02 entitlement miss → stage-3 `internal_error` (no bare 500) | IMPLEMENTED | `entitlement/index.ts:165-178` |
| C-03 AAT lifetime seed 15 → 10 min | IMPLEMENTED (backend migrations) | `20260905120000`, `20260905120300` |
| C-04 fabricated `"Prior request completed."` replay | IMPLEMENTED at HEAD (corrected post-sweep; `admitted` priors get no fabricated terminal) | `worker.ts:809-811` |
| C-05 non-string `ver` TypeError | IMPLEMENTED | `control/token-contract.ts:32, 89` |
| C-06 non-string `successor_id` crash | IMPLEMENTED | `control/capability-lifecycle.ts:114-119` |
| C-07 purge `storage_error` mapping | IMPLEMENTED (but the purge itself still fails → BUG-01) | `control/support-purge.ts:21-26` |
| C-08 unguarded control batches | IMPLEMENTED (batch error mapping present in lifecycle handlers) | `control/capability-lifecycle.ts:250-251` et al. |
| C-09 `quota_exhausted` `period_reset` on the wire | IMPLEMENTED | `worker.ts:1321-1322` |
| C-10 `context_required` `missing_keys`/`shapes`/`manifest_version` | IMPLEMENTED | `adapter.ts:233` → `context/validator.ts:563-576` |
| C-11 replay original `terminal_error_code` | IMPLEMENTED | `worker.ts:815-817` |
| C-12 compose failure releases DO reservation | IMPLEMENTED | `pipeline/index.ts:538-556` |
| C-13 promote/rollback state-machine preconditions | IMPLEMENTED | `control/routing-policy.ts:296, 382, 470-518` |
| C-14 purge requires `deleted` status | IMPLEMENTED | `control/support-purge.ts:100-105` |
| C-15 per-job try/catch in `scheduled()` | IMPLEMENTED | `worker.ts:1689-1743` |
| C-16 `set_ai_availability` write RPC | IMPLEMENTED (backend) | `20260905120100_set_ai_availability_rpc.sql` (but see BUG-09) |
| C-17 kill-switch control route | IMPLEMENTED | `control/kill-switch.ts`, `control/index.ts:91` |
| C-18 boot registry-install fail-closed | IMPLEMENTED (rethrows except the harness "already installed" seam) | `worker.ts:152-166` |
| C-19 dedupe cohort activate ids | IMPLEMENTED | `control/cohort.ts:115` |
| C-20 persist `cohort_name` | IMPLEMENTED (in audit target) | `control/cohort.ts:127-128` |
| C-21 rejection tallies for guard stages 5–7 | IMPLEMENTED | `capability/index.ts:573-632`, `context/validator.ts:61`, `context/preflight.ts:72` |
| C-22 revoke returns stored `revoked_at` | **NOT IMPLEMENTED** → BUG-11 | `20260902130100…sql:49-55` |
| C-23 unknown-provider scripted token rename | IMPLEMENTED (`retryable:provider_unavailable`) | `worker.ts:366` |
| C-24 dead-code removal (adapter 2nd parse check; `network_drop`) | **PARTIAL** — `network_drop` remains in the `disconnect` type unions (call sites all pass `"client_close"`); cosmetic | `stream/index.ts:124, 473`, `stream/structured.ts:92, 457` |

## 7. Harness-only limitations (acceptable — no code bug)

Verified against Register 5 and the phase-15 reports; these test deviations are
legitimate and documented:

- **21 `it.skip`s** — all cite Register 5 rows (missing bindings at boot, log verbosity,
  Content-Length control, wall-clock horizons, DO/D1 fault injection, platform cron
  semantics). None hide a code bug. Coverage: 727/818 catalog IDs have a Worker E2E
  test; the remainder are SQL-track (pgTAP/backend) or deferred
  (`phase-15-coverage.md`).
- **S08-057 / S10-015** — workerd cannot construct a `Request` with an aborted signal;
  the `handleAdapterRequest` seam with an injected aborted signal is the documented
  analogue (Register 5 #38/#39).
- **S11-009/010/011** — abort-while-pending timing; S11-010/011 read SSE frames from a
  `ReadableStreamDefaultController.enqueue` spy because workerd discards the body on
  abort. The assertions verify the frames the adapter *produced*, not what a torn-down
  client socket delivered — acceptable, but note the client-visible stream is no longer
  under test there.
- **S09-073** — concurrency gate seeded via direct DO RPC (`gatewayObjectRpc`) instead
  of 16 genuinely hung requests; the e2e barrel lacks a hanging FakeAdapter seam.
  Acceptable; a hanging-adapter seam would make it end-to-end.
- **S05-059 / S07-051 TTL analogues** — `setTtlMs(30_000)` / `clearConfigCache()`
  stand-ins are acceptable *given* BUG-06; after BUG-06 is fixed, prefer real TTL
  expiry (see BUG-06 test brief).
- **S09-065** — see §5.2 last row: assertion is fine, scenario wording imprecise.

## 8. Recommended execution order (for the implementing model)

1. **BUG-01** (purge FK / partial purge) — data-loss-class; code + S03-079 test +
   catalog text.
2. **BUG-03** (missing-handoff settlement) — accounting/diagnostic loss; code +
   S10-034 test.
3. **BUG-04** (raw-body slice) — small, isolated; code + S11-018 test.
4. **BUG-05** (truncation `text_delta` drop) — code + S10-028 test + reconcile the
   stage-10/stage-11 catalog texts.
5. **BUG-06** (TTL 0) — code, then simplify S05-059/S07-051 tests and adopt D-02's
   `CONFIG_CACHE_TTL_MS=0` guidance.
6. **BUG-07 / BUG-08** (kid normalization, entitle grant idempotency) — small
   hardening; restore original S03-070 / S09-027-teardown journeys.
7. **BUG-09 / BUG-10 / BUG-11** (backend) — one migration each + SQL test assertion
   updates.
8. **Sweep follow-ups** (`sweep/` directory): fix TEST WRONG SX-037 and S08-063;
   strengthen the weak tests (S09-066/S10-017 dead replay assertions, stage-10 DO
   credit profiles, S06-019 full-row hashes); implement the 4 weak skips
   (S05-060/061/078/082) via the Register 5 #26 direct-call seam; close the 3 coverage
   gaps (S06-038, S07-039, S09-078 grace-ledger branch).
9. **Catalog text sweep** for every row in §5.2 plus the sweep's CATALOG WRONG lists
   (doc-only edits; no code, no test changes).
10. **C-24** cosmetic dead-code cleanup.

Every code fix above already has a catalog scenario pinning the *wrong* behavior; per
remediation-plan §8, edit the scenario text in the same commit as the fix.
