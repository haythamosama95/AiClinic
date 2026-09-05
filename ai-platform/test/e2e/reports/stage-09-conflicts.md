# Stage 09 catalog-vs-code conflicts

## S09-027

- **Catalog claim:** After `[SEED] DELETE FROM entitlement`, restore via the Stage 4 entitle operation afterwards.
- **Code behavior:** `provisionHappyPath` already inserted live installation-scope grants. `entitleInstallation` `INSERT`s `capability_grant` again; UNIQUE on the live installation grant (`idx_capability_grant_live_installation`) maps to control `storage_error` HTTP 500. The catalog POST (HTTP 500 `internal_error`) is unchanged. Teardown omits re-entitle; `beforeEach` `resetE2eState()` isolates the next test.
- **File:line:** `ai-platform/src/control/entitle.ts` (grant INSERT / unique → `storage_error`); `ai-platform/test/e2e/stage-09-entitlement-ratelimit.test.ts` S09-027.

## S09-073

- **Catalog claim:** Sixteen full-path `POST /v1/requests` held in-flight via FakeAdapter hang (provider never completes, so credit/release never decrements `inFlight`). After the 16th, `periodCounters.inFlight = 16 = CONCURRENCY_LIMIT`. 17th POST: HTTP 429 `quota_exhausted` with `period_reset`. No 17th `ai_request` row.
- **Code behavior:** Concurrency gate is Quota DO `inFlight >= CONCURRENCY_LIMIT` (`16`). The e2e barrel has no FakeAdapter hang, so overlapping undrained `clinicFetch` still credits before the 17th. Prior `inFlight` is established via documented `gatewayObjectJson` / `gatewayObjectRpc` `kind: "admission"` (same `idFromName` object the worker uses) without credit. 17th POST still asserts HTTP 429 `quota_exhausted`, `period_reset` from entitle `period_end`, and no 17th `ai_request`.
- **File:line:** `ai-platform/src/quota-do/index.ts:5` (`CONCURRENCY_LIMIT = 16`); `ai-platform/src/quota-do/index.ts:425-431` (`inFlight >= CONCURRENCY_LIMIT`); `ai-platform/src/admission/index.ts:470-482` (concurrency → `quota_exhausted`); `ai-platform/test/e2e/harness/gateway-object.ts` (`gatewayObjectRpc`); `ai-platform/test/e2e/README.md` §4.6.

## S09-068

- **Catalog claim:** Idempotent replay after a terminal Failed prior returns HTTP 200 SSE `accepted` then `failed` whose data is the canned `internal_error` taxonomy body (`retry_safe: true`).
- **Code behavior:** `replayIdempotentTerminal` replays `prior.terminalErrorCode` when it is a taxonomy code, else defaults to `internal_error`. The journey setup uses an empty provider chain (Stage 05 S05-074); the first request stores `provider_unavailable` on the DO idempotency entry, so replay failed-event `code` is `provider_unavailable`.
- **File:line:** `ai-platform/src/worker.ts:813-819` (`prior.terminalErrorCode` when `isTaxonomyCode`, else `"internal_error"`); `ai-platform/src/quota-do/index.ts:400-409` (idempotent `priorState` carries `terminalErrorCode`); `ai-platform/src/quota-do/index.ts:349-359` (credit stores the code on `failed`).

## S09-022

- **Catalog claim:** A happy AAT whose final signature character is flipped (`${AAT%?}x`) is enough for `crypto.subtle.verify` to return false (HTTP 401 `unauthenticated`).
- **Code behavior:** Ed25519 signatures are 64 bytes, encoded as 86 base64url characters with 4 unused trailing bits. Mutating only the last character can leave the decoded 64-byte signature unchanged, so verify still succeeds. Variant (a) also flips an earlier signature character (and sets the last char to `x`) so decoded bytes change. Variant (b) (different Ed25519 keypair, header `kid` of the enrolled key) is unchanged.
- **File:line:** `ai-platform/src/identity/index.ts:330-348` (`base64urlDecode` then `crypto.subtle.verify`); catalog `docs/testing/catalog/stage-09-the-guard.md` S09-022 action.
