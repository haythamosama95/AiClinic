# P3.2 escalations

Assumptions chosen by the resolver. Each one is written into the design docs named below.

## 1. Issuer-key envelope and `public_key`

**Question:** What `result`, `code`, and `detail` do `registerIssuerKey`, `revokeIssuerKey`, and `listIssuerKeys` return in the 04 §1.2 envelope, and what is the stored form of `public_key`? The same `kid` with a different `public_key` has no `code`.

**Assumption:** These methods do not record a grant or a reversal, so a successful call is `ok` with `code` empty and no `receipt`. Register and revoke put the JSON text of the `issuer_key` row in `detail`. `listIssuerKeys` puts the JSON text of `{kid, public_key, status, not_before, not_after}` for each `active` or `retiring` row in `detail`. `public_key` is the base64url encoding of the raw 32-byte Ed25519 public key. The same `kid` with the same `public_key` is `ok` again and does not insert another row. The same `kid` with a different `public_key` is `conflict` with code `public_key_mismatch` and empty `detail`. A `public_key` that is not that encoding is `rejected` with code `public_key_invalid`.

**Why:** The result envelope already returns `ok` plus JSON `detail` for registry writes that are not grants. The replaced installation key stored base64url of the raw 32 bytes, which is what WebCrypto imports as `raw`. The shared-package hex vector is a test fixture, not the stored form. Pins and the backend key use that same string, so P4.9 and P5.1 compare equal bytes.

**Amended:** `docs/architecture/ai-billing-orchestration/04-abo-contracts.md` (§1.2, §1.3 rows `listIssuerKeys`, `registerIssuerKey`, `revokeIssuerKey`, §1.6).

## 2. First installation row and the creation cap

**Question:** On the first valid token for an unknown org, what does the new `installation` row store for `display_name` and `region`, and which stored time enforces the 50-creations-per-day cap?

**Assumption:** The new installation stores `status` `active`, `display_name` as the empty string, `region` as the empty string, and `enrolled_at` as the UTC ISO-8601 time of the insert. The new binding is `status` `active`, `epoch` 1, and `created_at` is that same time. The cap counts `tenant_binding` rows with `epoch` 1 whose `created_at` falls in the last 24 hours.

**Why:** The kept install path wrote `active` and the enrollment time, and a live row must authenticate. The token has no clinic name or region, `org_id` is already its own column, and no reader in the design uses `display_name` or `region`, so those NOT NULL columns store the empty string. `created_at` exists on every record, and epoch 1 is the first binding of an org, so that timestamp is the new-org creation time. Re-creations and transfers use a higher epoch and do not count.

**Amended:** `docs/architecture/ai-billing-orchestration/03-abo-data-model-and-lifecycle.md` (§3.2 rows `installation` and `tenant_binding`); `docs/architecture/ai-billing-orchestration/04-abo-contracts.md` (§2.1).

## 3. Refusal of the 51st new-org creation

**Question:** What HTTP status and error code are returned when the 51st new-org creation within 24 h is refused?

**Assumption:** The attempt inserts nothing. The clinic route answers 401 `unauthenticated` and the platform raises AL-20.

**Why:** No binding is created, so verification never produces a principal, which is the existing identity failure. `rate_limited` stays the unchanged request limiter. A new denial code would add a row to the desktop map in 04 §3.4.

**Amended:** `docs/architecture/ai-billing-orchestration/04-abo-contracts.md` (§2.1); `docs/architecture/ai-billing-orchestration/06-abo-delivery-plan.md` (E2E-P3.2-05).

## 4. Writer of `issuer_key.status = retiring`

**Question:** Which operation sets `issuer_key.status` to `retiring`?

**Assumption:** `retireIssuerKey` (HP, input `kid`) is the only writer of `retiring`. It moves `active` to `retiring` and is `ok` when the row is already `retiring`. `registerIssuerKey` inserts `active` and does not change status on a same-key replay. `revokeIssuerKey` sets `revoked` and does not set `retiring`. A missing `kid` is `rejected` with code `kid_not_found`. Retire of a `revoked` row is `rejected` with code `kid_revoked` and leaves the row `revoked`.

**Why:** K-2 treats retire and revoke as different steps, and a retiring `kid` stays accepted until `not_after` while a revoked `kid` does not. Two active kids must be able to coexist, so registering a new key cannot retire the old one. `retirePlanVersion` is the existing pattern for a separate retire method. The console action list and P4.9's relay now name this method so the rotation step is not SQL.

**Amended:** `docs/architecture/ai-billing-orchestration/04-abo-contracts.md` (§1.2, §1.3 rows `registerIssuerKey`, `retireIssuerKey`, `revokeIssuerKey`); `docs/architecture/ai-billing-orchestration/03-abo-data-model-and-lifecycle.md` (§3.2 row `issuer_key`); `docs/architecture/ai-billing-orchestration/02-abo-architecture-and-threat-model.md` (§6 row K-2); `docs/architecture/ai-billing-orchestration/05-abo-operations-and-traceability.md` (AL-13 and the issuer-key action row); `docs/architecture/ai-billing-orchestration/06-abo-delivery-plan.md` (P3.2 implements and read; P4.9 implements and read).

## 5. Spec re-transcription

**Question:** `spec.md` still transcribes the pre-amendment design. The Unit Contract lists only `registerIssuerKey` / `revokeIssuerKey` and a bare “refusal + AL-20.” FR-002 gives both register and revoke the input `kid`, `public_key`, and validity, and says the output is the key row. FR-003 raises AL-13 for register and revoke only. FR-001, FR-007, FR-008, and FR-009 omit `retireIssuerKey`, the `ok` / empty `code` / no `receipt` envelope, `public_key` as base64url of the raw 32-byte Ed25519 key, `public_key_mismatch`, `public_key_invalid`, `kid_not_found`, and `kid_revoked`, the first-installation values (`status` `active`, empty `display_name`, empty `region`, `enrolled_at`), `tenant_binding.created_at`, the epoch-1 24-hour count, and 401 `unauthenticated` with nothing inserted for the 51st new org. E2E-P3.2-05 says only “refused + AL-20.”

**Assumption:** Re-transcribe `spec.md` from the amended design sections so it no longer contradicts them. The four design assumptions already recorded above stay closed.

**Why:** 04 §1.2, the §1.3 rows for `registerIssuerKey`, `retireIssuerKey`, `revokeIssuerKey`, and `listIssuerKeys`, §1.6, and §2.1, 03 §3.2 rows `issuer_key`, `tenant_binding`, and `installation`, 02 §6 row K-2, 05 §2 row AL-13, and delivery-plan P3.2 (Implements and E2E-P3.2-05) already decide those behaviors. The spec was still the earlier transcription of the same sections.

**Amended:** `specs/066-abo-p3-2-issuer-tokens-registry-tenant-bindings/spec.md`

## 6. Admission, capability, and entitlement after the cache and tier-helper rows

**Question:** FR-006 says the config cache no longer reads `plan` or `entitlement`, and FR-016 removes `planTierMeetsMinimum`. `src/admission/index.ts`, `src/capability/index.ts`, and `src/entitlement/index.ts` still load those cache kinds and still call `planTierMeetsMinimum`. `/control/entitle` stays so earlier suites can admit clinics (rule S9, SC-002), and entitlement itself stays until P3.10. The spec does not say what those three modules read or check once the readers and the tier helper are gone.

**Assumption:** Those three modules are unchanged in this unit. Admission, capability, and entitlement still load the `entitlements` cache kind. Capability still loads plan-scoped grants, including the `plan:` grant fallback, and still calls `planTierMeetsMinimum`. Entitlement still requires status `active` and still calls `planTierMeetsMinimum`. The config cache still reads `plan` and `entitlement`. `PLAN_TIERS` and `planTierMeetsMinimum` stay. This unit adds the `issuer_key` and `tenant_binding` readers, removes the `installation_key` reader, and renames the key-algorithm constant for issuer keys. It does not add a coverage reader. P3.4 removes the tier checks and the request-path entitlement read, and reads `/v1/capabilities` from `coverage_mirror`. P3.10 drops the `plan` and `entitlement` tables.

**Why:** 04 §6.1 names the end state of `src/config-cache/index.ts` and `src/platform-vocabulary.ts`, and P3.2's Read includes those rows. P3.2's Implements line only adds `issuer_key` and `tenant_binding` readers and drops `installation_key`. The admission, entitlement, and capability rows of 04 §6.1 are in P3.4's Read. P3.4 stops reading entitlement on the request path and reads `/v1/capabilities` from `coverage_mirror`, which P3.3 creates. Rule S9 keeps `/control/entitle` until that switch so earlier suites still admit clinics (SC-002). Removing the readers and `planTierMeetsMinimum` here would leave the three modules with no read or check this unit assigns.

**Amended:** `specs/066-abo-p3-2-issuer-tokens-registry-tenant-bindings/spec.md`

## 7. E2e issuer credential cache and the version 2 seed

**Question:** Should the e2e harness drop the cached issuer credential when `operator_credential` is reset, and should stage 00/01/05 token-contract assertions move to the version 2 current / version 1 retired seed?

**Assumption:** Yes. When an e2e reset deletes `operator_credential`, the harness drops the cached issuer credential and does not reuse that signer. The next `registerIssuerKey` bootstraps a new signer and sets that row's `activates_at` at or before wall-clock now, so the existing signer-read promotion marks it `active` before the call. Issuer tokens stay `ver` `"2"` and still verify. The e2e config does not gain `TEST_CLOCK`, and credential status rules in the entrypoint stay as they are. Stage 00, 01, and 05 token-contract assertions, including `stage-01-rotation-retire.test.ts` and `stage-05-publish.test.ts`, expect the reset seed: version `2` current (`retired_at` NULL, `added_at` `2026-10-03T13:00:00.000Z`, `changed_by` `seed`) and version `1` retired (`retired_at` `2026-10-03T13:00:00.000Z`, `added_at` `2026-08-03T00:00:00.000Z`, `changed_by` `seed`). They do not expect or reseed a sole live version `1`. A begin-rotation of version `2` is 409 `ver_already_exists`. Opening a rotation uses a version that is not already stored and returns 200 while version `2` stays current. Retiring version `1` is 409 `ver_already_retired`. Retiring the sole live version, which is version `2` while version `1` is already retired, is 409 `no_rotation_open`. A retire that must stamp a live row first opens a new version, then retires version `2`. Counts that treated `token_contract` as one row treat it as these two seed rows.

**Why:** FR-005 already records version 2 and retires version 1, and T010 reseeds that pair after every reset. A sole live version 1 would make `ver` `"2"` fail verification. T023 already names the stage 00/01/05 files this unit migrates; the rotation and publish files read the same seed, so they follow it too. The system harness drops its issuer registry when it deletes `operator_credential` and only then calls `registerIssuerKey`, after the signer is active. The e2e pool has no `TEST_CLOCK` (T011), so the harness moves that new row's `activates_at` instead of the clock. The entrypoint still promotes a pending signer only when `activates_at` is at or before now.

**Amended:** `specs/066-abo-p3-2-issuer-tokens-registry-tenant-bindings/spec.md`; `specs/066-abo-p3-2-issuer-tokens-registry-tenant-bindings/plan.md`; `specs/066-abo-p3-2-issuer-tokens-registry-tenant-bindings/tasks.md`
