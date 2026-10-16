# Agent F — analysis of e1a42092 ("Restore CI campaign fixes"), reverted by cb99ded0

Repo HEAD: `953e5e6e` (branch `ai/abo-master`). Analysis only; no repo files were modified and no tests were run.

## 0. TL;DR

- **Every hunk of e1a42092 applies cleanly at HEAD.** `git diff e1a42092^ HEAD -- <all 9 files>` is empty, and `git apply --check` of the full patch passes at HEAD.
- **Seven of the eight file hunks are needed** by target tests (P5.1, P5.2, P7.2-01..09, P7.3-01..07, frontend P6.3/P6.4/P7.3-06). None of them breaks a currently-green suite, as far as static tracing can show.
- **Drop hunk 8 (`test/harness/test_campaign_live_stats.py`).** It adds tests that call `apply_campaign_stats(..., batch_queue=None)`, and `campaign_progress_finished(state=None, …)` then dereferences `state` (`_subcampaign_test_total(state, …)`, `state.resume_display`). The tests would fail at HEAD because the production fix they test was never committed. This is the most likely *concrete* reason for the revert (a red harness test). The other likely reason is that the commit spans four areas while frontend/fullstack was still red for unrelated reasons.
- **Re-applying e1a42092 is not sufficient.** The same bug classes exist in files it did not touch:
  - `receipt.ts:135` uses `Buffer`, which breaks paid grants under wrangler.
  - `issue_feed_token` produces non-canonical JWT JSON, which gives feed 401s.
  - `p7-3-stack`, `p5-1` and `p5-2` pass vars via env instead of `--var`, have no `Host` header in the abo readiness wait (p5-*), use a non-idempotent org bootstrap (p7-3), and have a `stop()` leak (p5-*).

  See §4.
- **Ready-to-apply patch (hunks 1–7 only):** `notes/agent-F-e1a42092-recommended.patch`. It was produced with `git show e1a42092 --format= -- <7 paths>`, and `git apply --check` at HEAD passes.
  - Equivalent alternative: `git checkout e1a42092 -- <the 8 paths in §1 rows 1–7>`. This is exact because HEAD's copies equal `e1a42092^`.

## 1. Per-hunk table

| # | File (hunk) | Needed? | By which test(s) | Cross-impact on green suites | Applies cleanly at HEAD? | Action |
|---|---|---|---|---|---|---|
| 1 | `abo/src/worker.ts`: import `clinicErrorResponse`; GET `/v1/checkouts` without `open=1` returns JSON `not_found` 404 instead of an empty 404 | Yes | E2E-P7.2-03 `assertAboNotFound("/v1/checkouts", …)` does `response.json()` and checks `code==="not_found"` | No abo/test does GET `/v1/checkouts` without `open=1`; every `billingFetch("/v1/checkouts", …)` in abo/test is a POST, and `?open=1` is unchanged. Frontend always uses `?open=1`. `staging/stg-a02.mjs` only checks string literals. abo/system and version-matrix are unaffected. | Yes | Apply verbatim |
| 2a | `backend/supabase/migrations/20261014170000_canonical_billing_jwt_json.sql` (new): `auth_internal.canonical_issuer_jwt_json(jsonb)` plus `issue_billing_token` re-emitted with JCS header and payload | Yes | Every real billing-token path that abo validates with `validateTokenClaims` (byte-equality with `canonicalize`): P5.1-02, P7.2-03/04/08, P7.3-01/02/04, frontend P6.3/P6.4 (`_issueBillingToken` → abo). `jsonb::text` adds `": "`/`", "` spacing and orders keys by length, so it never matches. | It is the newest migration and nothing later redefines `issue_billing_token`. The body is identical to `20261007180000:1134-1303` except for serialization. `p7-3-06-prepare.mjs` only re-applies the **public** wrapper, so there's no conflict. `contract_version_matrix.sql` redefines only the public wrapper. No test depends on token JSON whitespace or key order; backend tests decode to jsonb. The helper is IMMUTABLE STRICT, REVOKEd from PUBLIC/anon/authenticated/service_role, and called from a SECURITY DEFINER function owned by postgres (same pattern as `issue_feed_token`, which `ai_keystore_rls.sql` already exercises as postgres). The escaping matches `JSON.stringify`: PG `escape_json` emits lowercase `\u00XX`, `\n`, `\t`, `\"`, `\\`, and raw non-ASCII. Integers are safe-int only; there are no floats in tokens. | Yes | Apply verbatim **together with 2b** |
| 2b | `backend/tests/issuer_rpc.sql`: `pg_temp.decode_jws_segment`, escaping DO block, `billing_token_canonical` check in E2E-P5.1-04 | Yes (guards 2a) | backend/all "Issuer RPC" step | It runs as postgres (the owner), so the REVOKE doesn't block it. It needs a UTF-8 client encoding for `clínic+ø` (fine on CI Linux). It fails if 2a is absent, so the two must land together. | Yes | Apply verbatim with 2a |
| 3 | `e2e/fullstack/dart/bin/session_jwt_capture.dart`: drop `supabase_flutter`-tainted imports; mint via RPC; abo call with host `billing.vendor.test` | Yes | E2E-P7.2-08 (the plain Dart VM can't compile `dart:ui` imports) | Only used by P7.2-08. CI still needs the Flutter-provided `dart` and `pub get` for `ai_clinic` in the e2e-fullstack job (ci.yml matrix has `flutter: false` there; see agent C). | Yes | Apply verbatim, and enable Flutter for e2e-fullstack in CI |
| 4 | `e2e/fullstack/test/p7-2-stack.mjs` (large hunk) | Yes | Every P7.2 file (01..09) | Imported only by the P7.2 tests. The new import of `prepareAboD1`/`ABO_D1_SEED_PERSIST`/`PAYMOB_PERSIST` comes from hunk 6, so both must land together. `applyAboMigrations` is removed but was only used inside p7-2-stack (p5-*/p7-3 have their own copies). | Yes | Apply verbatim with 5 and 6 |
| 5 | `e2e/fullstack/test/p7-2-untrusted-callers.test.mjs`: `ensurePlatformActiveCoverage`; schema-valid `context` instead of `input`; `org` → `org_id` | Yes | E2E-P7.2-03 | At HEAD the request fails with `context_required`/coverage denial, which doesn't match `/not_found|context_invalid|forbidden|unauthenticated/i`. The `checkout.org` column doesn't exist (`abo/migrations/0002_checkout.sql` uses `org_id`). Test-only change. | Yes | Apply verbatim (needs 4) |
| 6 | `e2e/fullstack/test/wrangler-persist.mjs`: pinned wrangler CLI; `ABO_D1_SEED_PERSIST`, `PAYMOB_PERSIST`; WAL checkpoint copy; seed wipe; `execPlatformD1Sql` writes directly into the runtime DB; `prepareAboD1` | Yes | All e2e files that call `execPlatformD1Sql` after the platform is running (p5-1, p5-2, p7-2, p7-3 operator-credential inserts). HEAD writes to the seed and then copies it over the live DB, which clobbers runtime writes such as the registered issuer key. Also P7.2 abo D1 prep. | Importers p5-1, p5-2, p7-2-stack, p7-3-stack and `hfl-run-flutter` (through p7-3-stack) all call `execPlatformD1Sql(sql)` with no options, so they stay compatible. Frontend `administrator_subscription_fullstack_test.dart:765` reads the `.wrangler/abo/...` path directly and is unchanged. **Hard requires `e2e/fullstack/node_modules/wrangler/bin/wrangler.js`**, so every area that imports this file must `npm ci` in `e2e/fullstack`, including frontend/fullstack. The seed wipe at the top of `preparePlatformD1` is harmful under parallel all-manual; agree with agent C B.4a (one step per file, sequential). | Yes | Apply verbatim, **plus** agent C B.4a sequential steps, **plus** e2e/fullstack `npm ci` in the frontend area |
| 7 | `packages/vendor-contracts/src/token-claims.ts`: `Buffer.from` → `atob` loop | Yes | Every token validated in a wrangler/workerd process without `nodejs_compat`: abo billing (P5.1-02, P7.2-03/04/08, P7.3-01/02/04, P6.3/P6.4) and platform feed (P5.2-01, P7.3-01 `feedOk`) | `Buffer` raises a ReferenceError inside try/catch, which returns null and silently fails validation. `atob` exists in Node ≥16 and in workerd, and the regex `^[A-Za-z0-9_-]*$` guards the input. The same pattern already exists in `jws.ts`, `access-jwt.ts`, `grant-envelope.ts` and abo `auth.ts`. The vendor-contracts node and workers pools, ai-platform and abo/system stay green. | Yes | Apply verbatim |
| 8 | `test/harness/test_campaign_live_stats.py`: two tests for queue-less stats | No | — | **Red at HEAD.** `apply_campaign_stats(stats, …, batch_queue=None)` calls `campaign_progress_finished(None, …)`, which calls `_subcampaign_test_total(None, …)` and reads `state.resume_display`, raising AttributeError. Also `total=4` is ignored when `batch_queue is None`, so the `== 4` assertion is wrong even after a None-guard. | Yes | **Do not apply** (or write the matching `campaign_live_stats.py` / `batch_queue_display.py` None-guards first; out of scope) |

## 2. Exact edits

Easiest path: `git apply notes/agent-F-e1a42092-recommended.patch` (hunks 1–7, already checked). Without git, use the content below. The three large hunks are in scratch files in this notes directory, and each is a complete unified diff with full content:

- `e1a-backend.diff` (359 lines): the whole new migration `20261014170000_canonical_billing_jwt_json.sql` (250 lines, every line is `+`) plus the `issuer_rpc.sql` hunks.
- `e1a-p72stack.diff` (479 lines): `p7-2-stack.mjs`.
- `e1a-persist-dart.diff` (242 lines): `session_jwt_capture.dart` and `wrangler-persist.mjs`.

### Hunk 1 — `abo/src/worker.ts`

Before (line 17):
```ts
import { checkContractVersion } from "./clinic-api/version.js";
```
After:
```ts
import {
  checkContractVersion,
  clinicErrorResponse,
} from "./clinic-api/version.js";
```
Before (in `handleBillingV1`, GET `/v1/checkouts` branch, ~line 275):
```ts
    if (url.searchParams.get("open") === "1") {
      return handleListOpenCheckouts(env, auth.claims.org, versionGate.version);
    }
    return emptyNotFound();
```
After:
```ts
    if (url.searchParams.get("open") === "1") {
      return handleListOpenCheckouts(env, auth.claims.org, versionGate.version);
    }
    return clinicErrorResponse("not_found", 404, versionGate.version);
```

### Hunk 5 — `e2e/fullstack/test/p7-2-untrusted-callers.test.mjs`

1. In the import list from `./p7-2-stack.mjs`, add `ensurePlatformActiveCoverage,` after `countAboWork,`.
2. After `const checkoutA = await openCheckout(billingTokenA, "p72-org-a-checkout");`, insert:
```js

  // Keep the checkout under test open, but give Org A an independent paid
  // grant so its later request reaches tenant-context validation instead of
  // being rejected first for missing coverage.
  await ensurePlatformActiveCoverage(
    stack,
    orgA.orgId,
    orgA.installationId,
  );
```
3. Replace `    input: { visit_id: orgB.branchId },` with:
```js
    // Supply a schema-valid Org B visit context so validation reaches the
    // tenant binding check. A missing required context key would only prove
    // the request-shape guard, not cross-tenant isolation.
    context: {
      org: orgB.orgId,
      branch: orgB.branchId,
      "visit.chief_complaint@v1": {
        visit_id: orgB.branchId,
        complaint: "Persistent headache for three days.",
        recorded_at: "2026-07-31T12:00:00Z",
      },
    },
```
4. In the two `queryAboD1One(\`SELECT checkout_id FROM checkout WHERE checkout_id = … AND org = …\`)` calls, replace `AND org = ` with `AND org_id = ` (2 occurrences).

### Hunk 7 — `packages/vendor-contracts/src/token-claims.ts` (lines 23–27)

Before:
```ts
  try {
    return Uint8Array.from(Buffer.from(padded, "base64"));
  } catch {
```
After:
```ts
  try {
    const binary = atob(padded);
    const bytes = new Uint8Array(binary.length);
    for (let index = 0; index < binary.length; index += 1) {
      bytes[index] = binary.charCodeAt(index);
    }
    return bytes;
  } catch {
```

### Hunks 2a/2b, 3, 4, 6

Apply the corresponding file sections of `e1a-backend.diff`, `e1a-p72stack.diff` and `e1a-persist-dart.diff` verbatim. Summary of hunk 4 (`p7-2-stack.mjs`), so a reviewer knows what to expect:

- **Imports:** `canonicalize, grantIdPaid, sha256Hex, signCompactJws` from vendor-contracts, and `ABO_D1_SEED_PERSIST, PAYMOB_PERSIST, prepareAboD1` from `wrangler-persist.mjs` (re-exported).
- **`waitForHttp(url, {timeoutMs, accept, headers, child, childLabel})`:**
  - passes `headers` through (the abo wait sends `Host: BILLING_HOST`; HEAD waits 120 s on an empty 404 from host-gated abo);
  - fails fast on spawn error or early exit.
- **`spawnDevProcess`:**
  - runs `process.execPath FULLSTACK_ROOT/node_modules/wrangler/bin/wrangler.js` instead of `npx`;
  - sets `detached` on non-Windows;
  - records startup output and errors.
- **`stopChild`:** process-group SIGTERM, then SIGKILL, then waits for the group to exit (same as `p7-3-stack.mjs:233-286`). This fixes orphan workerd processes holding 8787/8788 and the exit-130 path.
- **`createOrgClinic`:** idempotent.
  - Reuses the org by name; on `ORG_ALREADY_EXISTS` falls back to a psql insert.
  - Reuses the branch by code.
  - Calls `set_active_organization` before staff creation.
  - At HEAD org B always fails, so every P7.2 `before()` throws.
- **`spawnAboProcess`:** passes `--var PAYMOB_BASE_URL:…`, `--var ISSUER_KEYS:…`, `--var ABO_GRANT_KEY:…` and `--var PLATFORM_PUBLIC_KEYS:…` instead of an env object.
- **`startStack`:**
  - paymob gets `--persist-to PAYMOB_PERSIST`;
  - `await prepareAboD1({ aboConfig: ABO_CONFIG })` replaces `applyAboMigrations`;
  - adds a `stackStopped` guard;
  - `stop()` uses `stopChild(stackRef.abo)`. HEAD stops the *original* abo and leaks the restarted one into the next file.
- **`restartAbo`:** stopped guard, Host header, and it cleans up the restarted process on failure.
- **New export `ensurePlatformActiveCoverage(stackRef, orgId, installationId)`:** signs a paid term envelope with `ABO_GRANT_KEY.pkcs8` and POSTs it to `${HARNESS_URL}/vendor-call` with `{method:"grant", …}`. It requires `result==="applied"`.

## 3. Cross-impact summary (currently-green suites)

| Suite | Touched by | Verdict |
|---|---|---|
| backend/all (73) | 2a, 2b | Stays green. The Issuer RPC step gains the `billing_token_canonical` check, which passes with 2a. `ai_keystore_rls.sql` is unaffected by 2a (and by §4.2 if the REVOKE is re-issued). `contract_versions.mjs` is unaffected. |
| backend/catalog (8) | 2a | No catalog check enumerates migrations or `auth_internal` ACLs; the only `pg_proc` lint found is in the public schema. |
| vendor-contracts/all | 7 (and §4.1) | `atob` exists in both the node and workers pools. |
| abo/system, import-boundary, version-matrix | 1, 7 | No test does GET `/v1/checkouts` without `open=1`. Import-boundary is unaffected (the import comes from the same module). |
| ai-platform eval / version-matrix | 7 | Same function semantics. |
| ops-launch | 1 | Staging `.mjs` files check string literals only. |

## 4. Sibling fixes (not in e1a42092; needed for the target campaigns)

### 4.1 `packages/vendor-contracts/src/receipt.ts:135` uses `Buffer` (confidence: high)

This is in `payloadBytesFromJws`, used by `abo/src/work/grant.ts:496` (`verifyGrantReceipt`) and `abo/src/work/reversal.ts:436`. Under wrangler (no `nodejs_compat`) it returns null, so grant or reversal work is parked with `last_error='receipt_unverified'`. That breaks E2E-P7.3-02 (expects `grant_outcome.result==="applied"`, not parked), and likely P7.3-01/04, the P5.2 paid flow and P7.2 paid flows. The fixture call to `ensurePlatformActiveCoverage` goes through the harness worker, not abo, so it isn't affected.

Before:
```ts
  try {
    return Uint8Array.from(Buffer.from(padded, "base64"));
  } catch {
    return null;
  }
```
After:
```ts
  try {
    const binary = atob(padded);
    const bytes = new Uint8Array(binary.length);
    for (let index = 0; index < binary.length; index += 1) {
      bytes[index] = binary.charCodeAt(index);
    }
    return bytes;
  } catch {
    return null;
  }
```
Cross-impact: none. `receipt.test.ts` runs in both pools, and `ai-platform/test/system/paid-grant-coverage.system.test.ts:832` has the same semantics. The `e2e/fullstack/test/variant/vendor-contracts-*.ts` re-exports pick it up automatically.

### 4.2 `auth_internal.issue_feed_token()` produces non-canonical JSON (confidence: high)

In `20261007180000_issuer_key_custody.sql:1377-1391`, both the header and the payload use `jsonb_build_object(...)::text`. The platform feed auth (`ai-platform/src/worker.ts` ~2234) validates with `validateTokenClaims`, which requires JCS bytes, and has no lenient fallback.

Tests that need this fix:
- E2E-P5.2-01: the pg_net feed pull must get a 200.
- E2E-P7.3-01 `feedOk`: 200 from `/v1/feed/coverage?after=0&limit=1`.
- Any feed-success precondition in p5-2 or the frontend P6.1 status tests (not traced).

Tests that don't need it:
- P7.3-03: it expects a 400 from the version gate before auth.
- P7.2-03: the `/v1/feed/coverage/<id>` route misses and returns 404 regardless.
- P7.2-07: it only checks that PostgREST rejects the token.

Fix: add a new migration **after** 20261014170000, because it depends on the helper.

`backend/supabase/migrations/20261014170100_canonical_feed_jwt_json.sql`:
```sql
-- Re-emit the internal feed token with RFC 8785 canonical header/payload bytes
-- so ai-platform validateTokenClaims byte-equality accepts it.

CREATE OR REPLACE FUNCTION auth_internal.issue_feed_token()
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, ai_internal, pgsodium, vault, auth_internal
AS $$
DECLARE
  v_signing_key ai_internal.issuer_key%ROWTYPE;
  v_secret_key bytea;
  v_jti uuid;
  v_iat bigint;
  v_exp bigint;
  v_header_text text;
  v_payload_text text;
  v_header_b64 text;
  v_payload_b64 text;
  v_signing_input text;
  v_signature bytea;
  v_token text;
BEGIN
  SELECT ik.*
  INTO v_signing_key
  FROM ai_internal.issuer_key ik
  WHERE ik.status = 'signing'
  LIMIT 1;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'ISSUER_KEY_NOT_CONFIGURED';
  END IF;

  SELECT decode(ds.decrypted_secret, 'base64')
  INTO v_secret_key
  FROM vault.decrypted_secrets ds
  WHERE ds.id = v_signing_key.secret_ref;

  IF v_secret_key IS NULL THEN
    RAISE EXCEPTION 'ISSUER_KEY_NOT_CONFIGURED';
  END IF;

  v_jti := gen_random_uuid();
  v_iat := extract(epoch FROM now())::bigint;
  v_exp := v_iat + 120;

  v_header_text := auth_internal.canonical_issuer_jwt_json(jsonb_build_object(
    'alg', 'EdDSA',
    'kid', v_signing_key.kid,
    'typ', 'JWT'
  ));

  v_payload_text := auth_internal.canonical_issuer_jwt_json(jsonb_build_object(
    'iss', auth_internal.ai_app_setting_text('ai.issuer_id', 'issuer-test'),
    'aud', 'ai-platform-feed',
    'sub', 'backend-feed',
    'jti', v_jti::text,
    'iat', v_iat,
    'exp', v_exp,
    'ver', '2'
  ));

  v_header_b64 := auth_internal.base64url_encode(convert_to(v_header_text, 'utf8'));
  v_payload_b64 := auth_internal.base64url_encode(convert_to(v_payload_text, 'utf8'));
  v_signing_input := v_header_b64 || '.' || v_payload_b64;

  v_signature := pgsodium.crypto_sign_detached(
    convert_to(v_signing_input, 'utf8'),
    v_secret_key
  );

  RETURN v_signing_input || '.' || auth_internal.base64url_encode(v_signature);
END;
$$;

REVOKE ALL ON FUNCTION auth_internal.issue_feed_token() FROM PUBLIC, anon, authenticated, service_role;
```
The body is byte-identical to HEAD apart from the two serialization lines.

Cross-impact:
- `backend/tests/ai_keystore_rls.sql:1395-1426` decodes the payload to jsonb (aud, sub, no org, exp−iat=120), so it is unaffected. It also expects `insufficient_privilege` for authenticated, which is kept by `CREATE OR REPLACE` plus the re-REVOKE.
- `pull_coverage_feed` (SECURITY DEFINER, owner postgres) still works.
- Optional guard: add a `feed_token_canonical` check to `ai_keystore_rls.sql` mirroring 2b. Not required.

`issue_ai_token` stays non-canonical. That's fine, because ai-platform identity parses AATs leniently.

### 4.3 e2e stack siblings (record only; agent C owns p5-*/all-manual)

| File:line | Bug | Fix | Confidence |
|---|---|---|---|
| `p5-1.test.mjs:528-530`, `:578-580`; `p5-2.test.mjs:546-548`, `:596-598` | The abo readiness `waitForHttp(\`${ABO_URL}/v1/offers\`, …)` sends no `Host` header. Abo's host gate returns an empty 404 for `127.0.0.1`, which is never in `[401,403,400]`, so it times out after 120 s. | Give the local `waitForHttp` (p5-1 ~:80, p5-2 :129) a `headers` option passed to `fetch`, and call it with `headers: { Host: "billing.vendor.test" }` (BILLING_HOST). This is the same fix as hunk 4 and b68299b9 in p7-3-stack. | Medium-high. Wrangler local dev doesn't rewrite the host without routes, and two independent fixes (b68299b9, e1a42092) added exactly this. |
| `p5-1.test.mjs:523-527`, `:573-576`; `p5-2.test.mjs` same block (~:539-545, ~:589-595); `p7-3-stack.mjs:698-723` | abo vars (`PAYMOB_BASE_URL`, `ISSUER_KEYS`, and in p7-3 also `PLATFORM_PUBLIC_KEYS` and `ABO_GRANT_KEY`) are passed through the process env. Wrangler 4.x local dev does not forward process env into Worker vars unless `CLOUDFLARE_INCLUDE_PROCESS_ENV=true`. | Pass `"--var", \`PAYMOB_BASE_URL:${PAYMOB_URL}\`, "--var", \`ISSUER_KEYS:${JSON.stringify(keys)}\`` and so on in the args, as hunk 4 does. Alternative: set `CLOUDFLARE_INCLUDE_PROCESS_ENV: "true"` in `wranglerLocalEnv`. | Medium. Unverifiable locally because node_modules are skeletons, but the e1a42092 author switched to `--var` deliberately. |
| `p5-1.test.mjs:548-551`; `p5-2.test.mjs:564-566` | `stop()` calls `stopChild(abo)` (the original abo, already stopped by `restartAbo`) instead of `stopChild(stackRef.abo)`. The restarted abo leaks ports 8788/9231 into the next file. | Use `await stopChild(stackRef.abo);`. | High |
| `p5-1.test.mjs:95-119`; `p5-2.test.mjs:146-170`; `p7-3-stack.mjs:222` | `spawn("npx", ["wrangler", …])` with no `detached`. SIGTERM reaches npx, not workerd, so orphans hold 8787/8788 ("Address already in use"), and RunnerCrashGuard SIGINT gives exit 130. p7-3-stack already has group-kill `stopChild` but spawns via npx. | Copy hunk 4's `spawnDevProcess` (pinned `process.execPath` + `WRANGLER_CLI`, `detached: process.platform !== "win32"`) and the group-kill `stopChild` from `p7-3-stack.mjs:233-286` into p5-1/p5-2. For p7-3-stack only, change `spawnDevProcess`. | High for p5-*, medium for p7-3 (its group kill may already cover it if npx is the group leader). |
| `p7-3-stack.mjs:597-680` (`createOrgClinic`) | Not idempotent. `bootstrap_create_organization` is global (`auth_internal.organization_exists()`), so org B always fails with ORG_ALREADY_EXISTS. This affects every P7.3 file with the default `createClinics=true`. | Port hunk 4's `findTestOrganizationId` / `insertTestOrganization` / `findTestBranchId` and the idempotent `createOrgClinic` (including `set_active_organization` before staff creation) into p7-3-stack. | High |
| `p7-3-stack.mjs:317` (`applyAboMigrations` straight onto ABO_PERSIST) | Inconsistent with the hunk 6 seed approach. | Optional: switch to `prepareAboD1({ aboConfig: activeAboConfig })`. Restarts at `:880` that re-apply migrations to the live DB should keep the current behaviour. | Low priority |

**Agreement with agent C:** no FOLLOW-UP section existed in `agent-C-abo-e2efullstack.md` when I read it. I agree with its B.4a: give all-manual one sequential step per file. Agent C notes that hunk 6's seed wipe makes the parallel D1-migration race worse. Hunk 6 is still needed: the direct runtime write fixes the issuer-key clobber. So hunk 6 depends on B.4a or `test_concurrency: 1`.

There is one point where I go further than agent C. Agent C's analysis doesn't flag the missing p5-* Host header or the `--var` issue. If those are real, P5.1-02 and P5.2-* cannot pass even after B.4a.

### 4.4 CI setup (record only)

- The e2e-fullstack area needs `npm ci` in `ai-platform` and `abo` (the variant configs and the abo worker source), and a Flutter-provided `dart` for P7.2-08.
- The frontend area (frontend/fullstack via `hfl-run-flutter.mjs` → p7-3-stack → wrangler-persist) needs `npm ci` in `e2e/fullstack`, `packages/vendor-contracts`, `ai-platform` and `abo`. After hunk 6, `e2e/fullstack/node_modules/wrangler/bin/wrangler.js` is a hard requirement.
- frontend/fullstack starts the stack with `{ createClinics: false, registerIssuer: false }`, so it depends on hunks 2a and 7, §4.1, and the `--var` fix in p7-3-stack.

## 5. Why it was probably reverted, and the recommended subset

Likely reasons, most likely first:
1. **Hunk 8 is a red test at HEAD** (AttributeError on `batch_queue=None`, and the `total=4` expectation is wrong). If the harness unit tests run anywhere, the commit turns them red.
2. **It wasn't sufficient.** P7.3, P5.* and frontend/fullstack stayed red because of the siblings in §4 (receipt `Buffer`, feed-token JCS, p7-3/p5 env vars and org bootstrap, p5 Host header) and missing CI installs. That makes the commit look ineffective.
3. **Hunk 6 depends on parallelism.** Wiping `D1_SEED_PERSIST` under parallel all-manual makes the existing migration race worse.
4. **Hunk 6 hard-requires `e2e/fullstack/node_modules/wrangler`.** frontend/fullstack doesn't install it, but that area was already red for missing deps.

Nothing in hunks 1–7 breaks backend/all, catalog, vendor-contracts, abo/*, ai-platform eval/version-matrix or ops-launch, as far as static tracing can show.

**Recommended subset and order:**
1. Hunk 7 (token-claims) and §4.1 (receipt): pure and safe.
2. Hunks 2a and 2b together, then the §4.2 feed migration (`20261014170100`).
3. Hunk 1 (abo `not_found`).
4. Hunks 6, 4, 5 and 3 together (the e2e harness), plus agent C B.4a (sequential all-manual) and the §4.4 CI installs and Flutter.
5. The §4.3 siblings in p7-3-stack, p5-1 and p5-2.
6. Skip hunk 8.

## 6. Residual risks

- **Direct `node:sqlite` writes into a live workerd D1 file** (hunk 6 `execPlatformD1Sql`) can hit workerd's own locking or WAL; `wal_checkpoint` throws if busy. If it flakes, add a busy-timeout retry. Medium.
- **`--var` behaviour and env forwarding in wrangler ~4.86** couldn't be verified locally (skeleton node_modules). `--var KEY:VALUE` is believed to split on the first `:`, so JSON values with colons are fine. Medium.
- **Undici `fetch` honouring a custom `Host` header** is assumed. `billingFetch` already relies on it in p7-3-stack, and the frontend uses `HttpClient` with a host header. Low.
- **Feed-token consumers beyond P5.2-01 and P7.3-01** (other p5-2 tests, frontend P6.1 stale or refresh paths) were not traced. The §4.2 fix covers them either way.
- **The `issuer_rpc.sql` escaping test needs a UTF-8 client encoding** (`clínic+ø`). Fine on Linux CI; could fail on a Windows `psql` with a non-UTF-8 code page.
- **Per-file timeout (180 s):** P7.2 `before()` now runs `prepareAboD1` and the abo restart. That should fit, but it's not measured.
- **Dart in the e2e-fullstack CI job:** without Flutter's SDK, `pub get` for `ai_clinic` fails and P7.2-08 stays red regardless of hunk 3.
- **`ensurePlatformActiveCoverage` assumes the harness `/vendor-call` grant accepts a stub approval** (`assertion: "stub"`) under the variant config, and that `ABO_GRANT_KEY` matches the platform's registered abo kid. Both are constants in p7-2-stack, but this is not runtime-verified.
