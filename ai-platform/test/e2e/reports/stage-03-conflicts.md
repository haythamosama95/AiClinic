# Stage 03 catalog-vs-code conflicts

## S03-036

- **Catalog claim:** Enroll I2 with catalog `XI2` = `dGhJkLzXcVbNm2QeRtYuIoPaSd8f7a9b0c1d2e3f4` returns HTTP 200 and stores that `public_key` verbatim. Claim under test is uppercase-UUID enroll (`CANONICAL_UUID_RE` `/i`).
- **Code behavior:** `isEd25519PublicKeyByteLength` requires 32 decoded bytes. Catalog `XI2` base64url-decodes to 30 bytes → HTTP 400 `{"error":"invalid_payload"}`. Test uses `generateTestKeypair()` (32-byte key) so uppercase-UUID storage can be observed. Success body is `{ platform_base_url: GATEWAY_ORIGIN }` (see S03-037).
- **File:line:** `ai-platform/src/platform-vocabulary.ts:53-61` (`isEd25519PublicKeyByteLength`); `ai-platform/src/control/lifecycle.ts:117-119` (enroll length check); `ai-platform/src/platform-vocabulary.ts:20-21` (`CANONICAL_UUID_RE` `/i`).

## S03-037

- **Catalog claim:** Enroll success body is exactly `{"platform_base_url":"http://localhost:8787"}`.
- **Code behavior:** `handleEnroll` returns `{ platform_base_url: new URL(request.url).origin }`. Under vitest-pool-workers the request origin is harness `GATEWAY_ORIGIN` (`https://ai-gateway.test`). HTTP 200; D1 side effects match catalog.
- **File:line:** `ai-platform/src/control/lifecycle.ts:245` (`platformBaseUrl`); `ai-platform/src/control/lifecycle.ts:292` (ok body); `ai-platform/test/e2e/harness/env.ts:23` (`GATEWAY_ORIGIN`).

## S03-038

- **Catalog claim:** Same as S03-037 for the I0 enroll that is this scenario’s setup (`{"platform_base_url":"http://localhost:8787"}`). Re-enroll then returns HTTP 409 `{"error":"already_enrolled"}`.
- **Code behavior:** Setup enroll succeeds with `{ platform_base_url: GATEWAY_ORIGIN }`. Re-enroll 409 `already_enrolled` matches catalog.
- **File:line:** `ai-platform/src/control/lifecycle.ts:245` (`platformBaseUrl`); `ai-platform/src/control/lifecycle.ts:292` (ok body); `ai-platform/src/control/lifecycle.ts:230-238` (existing-row pre-check).

## S03-039

- **Catalog claim:** Same as S03-037 for the I0 enroll that is this scenario’s setup (`{"platform_base_url":"http://localhost:8787"}`). Enroll of a new installation id with the same `org_id` then returns HTTP 409 `{"error":"already_enrolled"}`.
- **Code behavior:** Setup enroll succeeds with `{ platform_base_url: GATEWAY_ORIGIN }`. Org-id conflict 409 matches catalog.
- **File:line:** `ai-platform/src/control/lifecycle.ts:245` (`platformBaseUrl`); `ai-platform/src/control/lifecycle.ts:292` (ok body); `ai-platform/src/control/lifecycle.ts:230-238` (existing-row pre-check).

## S03-040

- **Catalog claim:** Same as S03-037 for the I0 enroll that is this scenario’s setup (`{"platform_base_url":"http://localhost:8787"}`). Enroll reusing `kid = K0` then returns HTTP 409 `{"error":"duplicate_kid"}`.
- **Code behavior:** Setup enroll succeeds with `{ platform_base_url: GATEWAY_ORIGIN }`. Duplicate-kid 409 matches catalog.
- **File:line:** `ai-platform/src/control/lifecycle.ts:245` (`platformBaseUrl`); `ai-platform/src/control/lifecycle.ts:292` (ok body); `ai-platform/src/control/lifecycle.ts:162-197` (`isUniqueConstraint` / `runControlBatch`).

## S03-066

- **Catalog claim:** Setup enrolls I2 with catalog `XI2` = `dGhJkLzXcVbNm2QeRtYuIoPaSd8f7a9b0c1d2e3f4`, then revoke of lowercase `KI2` against I0 returns HTTP 404 `{"error":"key_not_found"}` (lookup scoped to installation). `KI2` stays active on I2.
- **Code behavior:** Catalog `XI2` base64url-decodes to 30 bytes; `isEd25519PublicKeyByteLength` rejects enroll as HTTP 400 `{"error":"invalid_payload"}`. Setup uses `generateTestKeypair()` (32-byte key) so the cross-installation revoke can run. After enroll, revoke of catalog lowercase `KI2` against I0 is still 404 `key_not_found` (installation-scoped `WHERE key_id = ? AND installation_id = ?`).
- **File:line:** `ai-platform/src/platform-vocabulary.ts:53-61` (`isEd25519PublicKeyByteLength`); `ai-platform/src/control/lifecycle.ts:117-119` (enroll length check); `ai-platform/src/control/lifecycle.ts:419-427` (installation-scoped key lookup).

## S03-070

- **Catalog claim:** After I2 enroll (`XI2` / uppercase stored `KI2`), suspend, and rotate `K2`, revoke body `{"kid":"1a2b3c4d-5e6f-4a7b-8c9d-0e1f2a3b4c5d"}` (lowercase catalog `KI2`) on suspended I2 returns HTTP 200 `{}`. `KI2` gets `revoked_at`; `K2` stays active; audit `after_pointer = KI2`; status stays `suspended`.
- **Code behavior:** (1) Catalog `XI2` is 30 bytes → enroll 400 unless a 32-byte key is used (`generateTestKeypair()`). (2) `handleRevokeKey` binds `body.kid` into `WHERE key_id = ? AND installation_id = ?` with no case folding. SQLite TEXT compare is case-sensitive, so lowercase catalog `KI2` does not match stored uppercase `1A2B3C4D-…` and returns 404 `key_not_found`. Test sends the stored uppercase kid so revoke-on-suspended is exercised; audit `after_pointer` is the request kid (uppercase).
- **File:line:** `ai-platform/src/platform-vocabulary.ts:53-61` (`isEd25519PublicKeyByteLength`); `ai-platform/src/control/lifecycle.ts:419-427` (exact-match key lookup); `ai-platform/src/control/lifecycle.ts:448-458` (`after_pointer = body.kid`).

## S03-078

- **Catalog claim:** After I2 enroll with catalog `XI2` and S03-070 key management, `POST …/AA10C4D2-…/delete` on suspended I2 returns HTTP 200 `{}`.
- **Code behavior:** Same `XI2` 30-byte enroll rejection as S03-066. Setup revoke (S03-070) must use the stored uppercase kid; catalog lowercase `KI2` 404s (see S03-070). Delete `suspended → deleted` matches code once setup enrolls with a 32-byte key.
- **File:line:** `ai-platform/src/platform-vocabulary.ts:53-61` (`isEd25519PublicKeyByteLength`); `ai-platform/src/control/lifecycle.ts:419-427` (exact-match key lookup); `ai-platform/src/control/lifecycle.ts:595-597` (delete blocks only `deleted`).

## S03-079

- **Catalog claim:** Setup enrolls sentinel I2 with catalog `XI2`. After I0 is deleted (plus seeded request/R2/ledger/grace footprint), `POST …/I0/purge` returns HTTP 200 `{}`. Two `purge_installation` audit rows; R2 envelopes deleted; D1 deletes of request/attempt/usage/rollup/counter/grant/keys/entitlement/installation; `grace_admission_queue` and prior `control_audit` history survive; I2 untouched.
- **Code behavior:** Catalog `XI2` is 30 bytes → I2 enroll 400 unless a 32-byte key is used (`generateTestKeypair()`). `purgeByInstallationId` deletes R2 envelopes, then a D1 batch that never touches `grace_admission_queue`. That table has `FOREIGN KEY (installation_id) REFERENCES installation (installation_id)`; with FKs on, `DELETE FROM installation` fails. `runPurge` maps the throw to HTTP 500 `{"error":"storage_error"}`. Intent `purge_installation` audit is written first; the completion audit (after the batch) is skipped. D1 batch rolls back (I0 footprint remains); grace row remains; R2 objects are already gone; I2 is untouched.
- **File:line:** `ai-platform/src/platform-vocabulary.ts:53-61` (`isEd25519PublicKeyByteLength`); `ai-platform/src/control/support-purge.ts:107-123` (intent audit then `runPurge`); `ai-platform/src/control/support-purge.ts:21-26` (`storage_error`); `ai-platform/src/retention/index.ts:303-354` (R2 then D1 batch, no grace delete); `ai-platform/migrations/20260821120000_grace_admission_queue.sql:18` (FK).
