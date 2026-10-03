# Feature Specification: Issuer tokens, issuer-key registry and tenant bindings

**Feature Branch**: `ai/066-abo-p3-2-issuer-tokens-registry-tenant-bindings`

**Created**: 2026-10-03

**Status**: Draft

**Input**: P3.2 — Issuer tokens, issuer-key registry and tenant bindings

## 1. Unit Contract

**Implements** — Read: 02 §3.2; 04 §2.1; 03 §3.2 rows `issuer_key`, `tenant_binding`, `installation`; 04 §1.3 rows register/retire/revokeIssuerKey, listIssuerKeys; 04 §6.1 rows identity, config-cache, discovery, journal (`authenticateGetRequest`), platform-vocabulary, control/lifecycle (enroll removal), control/token-contract; 02 §6 row K-2; 05 §2 row AL-20.

- `issuer_key`; `registerIssuerKey`/`retireIssuerKey`/`revokeIssuerKey` (HP, AL-13); `listIssuerKeys` (M). `retireIssuerKey` is the only writer of `retiring`.
- Issuer-token verifier replacing `EnrolledKeyVerifier`: `kid` active or retiring within validity, `iss = ISSUER_ID`, `aud` per route, lifetime ≤ 600 s, skew, `ver = "2"` via `token_contract` (insert 2, retire 1); existing replay rules.
- `tenant_binding`: the first valid token for an unknown org creates installation + binding epoch 1; at most 50 creations per day across all tenants, then refusal + AL-20. `Principal.installationId` resolved through the binding.
- Config-cache readers for `issuer_key` and `tenant_binding`; revocation effective within one cache TTL. The `installation_key` reader goes with that table. The `plan` and `entitlement` readers stay. `src/admission/index.ts`, `src/capability/index.ts`, and `src/entitlement/index.ts` are unchanged: they keep loading the `entitlements` cache kind, and capability and entitlement keep calling `planTierMeetsMinimum`. `PLAN_TIERS` and `planTierMeetsMinimum` stay. This unit renames the key-algorithm constant for issuer keys. Coverage is never read through the cache.
- Drop `installation_key`, the enroll/rotate/revoke handlers and routes, and `INSTALLATION_KEY_TTL_DAYS`.
- H-AP `newClinic()` (registers the test issuer key, mints issuer tokens); every suite that enrolls is migrated (rule V2 step 2). `/control/entitle` stays for admitting test clinics (transitional, rule S9).

**Freezes** — AI-token verification rules; `tenant_binding` model (epoch); issuer-key methods.

**Consumes** — method dispatch + class table; auth refusal codes; credential lifecycle; alert body format; `platform_alert`. Changing one is out of scope (rule S7).

**Open questions relied on** — None.

**Spikes** — None.

## 2. User Scenarios & Testing

### 2.1 User Story 1 - Issuer-key registry (Priority: P1)

An operator registers, retires, and revokes issuer public keys on the platform, and lists the active and retiring keys. `registerIssuerKey`, `retireIssuerKey`, and `revokeIssuerKey` are class HP. `listIssuerKeys` is class M. `retireIssuerKey` is the only writer of `retiring`. These methods do not record a grant or a reversal. A successful call is `ok`, `code` is empty, and `receipt` is absent. On register, retire, and revoke, `detail` is the JSON text of the `issuer_key` row. On `listIssuerKeys`, `detail` is the JSON text of an array of `{kid, public_key, status, not_before, not_after}` for each row with `status` `active` or `retiring`. `public_key` is the base64url encoding of the raw 32-byte Ed25519 public key. Registration, retirement, and revocation raise AL-13. The registration alert carries the decoded operation and the `kid`.

**Why this priority**: This unit depends on P3.1, which freezes method dispatch, the class table, auth refusal codes, the alert body format, and `platform_alert`. User Story 2 accepts a token only when its `kid` is in this registry, and it accepts a retiring `kid` only after `retireIssuerKey` has set that status. User Story 3's `newClinic()` registers the test issuer key through `registerIssuerKey`.

**Independent Test**: E2E-P3.2-08 in harness H-AP.

**Acceptance Scenarios**:

1. **Given** `registerIssuerKey` (class HP), **When** an issuer key is registered, **Then** AL-13 carries the decoded operation and `kid`.

### 2.2 User Story 2 - Issuer-token verification and tenant binding (Priority: P2)

A clinic member presents an AI token. The platform verifies it with the issuer-token verifier that replaces `EnrolledKeyVerifier`: the `kid` is active or retiring and within validity, `iss` is `ISSUER_ID`, `aud` matches the route, the lifetime is at most 600 s, the clock skew matches today's check, `ver` is `"2"`, and the existing replay rules still apply. The first valid token for an unknown org creates an installation and a binding at epoch 1. The installation stores `org_id` from the token, a new platform clinic UUID as `installation_id`, `status` `active`, `display_name` as the empty string, `region` as the empty string, and `enrolled_at` as the UTC ISO-8601 time of the insert. The binding stores `status` `active`, `epoch` 1, and `created_at` as that same time. A later token for that org resolves `Principal.installationId` through that binding. A revoked `kid` is rejected after one config-cache TTL. Creation is capped at 50 per day across all tenants: the count is `tenant_binding` rows with `epoch` 1 whose `created_at` falls in the last 24 hours. The 51st such attempt inserts nothing, the clinic route answers 401 `unauthenticated`, and the platform raises AL-20.

**Why this priority**: It depends on P3.1 for class HP revocation, the `unauthenticated` refusal code, and alert capture, and on User Story 1 because only a registered `kid` verifies and only `retireIssuerKey` writes `retiring`. User Story 3 migrates every suite that enrolls onto tokens this story verifies.

**Independent Test**: E2E-P3.2-01, E2E-P3.2-02, E2E-P3.2-03, E2E-P3.2-04, E2E-P3.2-05, and E2E-P3.2-06 in harness H-AP.

**Acceptance Scenarios**:

1. **Given** a registered `kid` and a new org, **When** a token from that `kid` with `ver="2"` is presented, **Then** it authenticates, an installation and a binding at epoch 1 are created, and a second token resolves to the same installation. The installation stores `status` `active`, `display_name` as the empty string, `region` as the empty string, and `enrolled_at` as the UTC ISO-8601 time of the insert. The binding stores `status` `active`, `epoch` 1, and `created_at` as that same time.
2. **Given** an unknown `kid`, **When** a token with that `kid` is presented, **Then** the response is 401 `unauthenticated`. **Given** a `kid` revoked through HP, **When** one cache TTL has passed, **Then** a token with that `kid` is rejected.
3. **Given** a token whose `aud` is `abo`, or whose `aud` is `ai-platform-feed`, or whose lifetime is 601 s, or whose `ver` is `"1"`, **When** it is presented on an AI route, **Then** the response is 401. [TB-3]
4. **Given** two active `kid`s, **When** tokens of both are presented, **Then** both are accepted. **Given** a `kid` that `retireIssuerKey` has set to `retiring`, still before `not_after`, **When** a token with that `kid` is presented, **Then** it is accepted, and the tenant binding is unchanged. [A13, K-2]
5. **Given** 50 new-org creations within 24 h, **When** a 51st new org presents a valid token, **Then** the attempt inserts nothing, the clinic route answers 401 `unauthenticated`, and AL-20 is raised.
6. **Given** a request reference owned by one org, **When** `GET /v1/requests/{ref}` is called with that org's token, **Then** the response is 200. **When** the same reference is called with another org's token, **Then** the response is not found.

### 2.3 User Story 3 - Enrollment removal and harness migration (Priority: P3)

The platform removes per-clinic installation keys. `POST /control/installations/{id}/enroll` answers 404, and the `installation_key` table is gone, along with the rotate and revoke-key handlers and `INSTALLATION_KEY_TTL_DAYS`. H-AP replaces `enrollScenario` with `newClinic()`, which registers the test issuer key and mints issuer tokens. Every suite that enrolls is migrated. `/control/entitle` stays so test clinics can still be admitted. Admission, capability, and entitlement are unchanged, so an entitled clinic is still admitted the way those suites already require: they still load the `entitlements` cache kind, and capability and entitlement still call `planTierMeetsMinimum`.

**Why this priority**: It depends on User Story 1 and User Story 2. `newClinic()` registers the issuer key and mints tokens the verifier accepts, which is what replaces enrollment (rule S9). Every earlier suite stays green (rule S2).

**Independent Test**: E2E-P3.2-07 in harness H-AP. Every earlier suite stays green (rule S2).

**Acceptance Scenarios**:

1. **Given** the installation enroll route, **When** `/control/installations/*/enroll` is called, **Then** the response is 404 and there is no `installation_key` table.

### 2.4 Test plan

| ID | Harness | Entry point | Assertion | Proves | Story |
| --- | --- | --- | --- | --- | --- |
| E2E-P3.2-01 | H-AP | `GET /v1/capabilities` via `SELF.fetch` | Token from a registered `kid` for a new org, with `ver="2"`, authenticates; installation + binding epoch 1 created; a second token → same installation. | FR-004, FR-005, FR-007, FR-008, FR-009 | User Story 2 |
| E2E-P3.2-02 | H-AP | `GET /v1/capabilities` via `SELF.fetch`; `VendorEntrypoint.revokeIssuerKey` over the H-AP self service binding, `vendorCall` in `ai-platform/test/system/harness.ts` | Unknown `kid` → 401 `unauthenticated`. A `kid` revoked through HP → rejected after one config-cache TTL (≤ 30 s), observed by advancing the test clock (rule V4). | FR-006, FR-011, FR-019 | User Story 2 |
| E2E-P3.2-03 | H-AP | `GET /v1/capabilities` via `SELF.fetch` | `aud=abo` or `aud=ai-platform-feed`, lifetime 601 s, or `ver="1"` → 401, before any installation or `tenant_binding` write. [TB-3] | FR-005, FR-011 | User Story 2 |
| E2E-P3.2-04 | H-AP | `GET /v1/capabilities` via `SELF.fetch`; `VendorEntrypoint.retireIssuerKey` over the H-AP self service binding, `vendorCall` in `ai-platform/test/system/harness.ts` | Two active `kid`s: tokens of both accepted; a retiring `kid` accepted until `not_after`. The tenant binding is unchanged. [A13, K-2] | FR-004, FR-013, FR-018 | User Story 2 |
| E2E-P3.2-05 | H-AP | `GET /v1/capabilities` via `SELF.fetch` | 51st new-org creation within 24 h → 401 `unauthenticated`; nothing created; AL-20. The test clock stays inside that 24 h window (rule V4). | FR-008, FR-014 | User Story 2 |
| E2E-P3.2-06 | H-AP | `GET /v1/requests/{reference}` via `SELF.fetch` (`authenticateGetRequest`) | `GET /v1/requests/{ref}` with the owner org's token → 200; another org's token → not found. | FR-009, FR-010 | User Story 2 |
| E2E-P3.2-07 | H-AP | `POST /control/installations/{id}/enroll` via `SELF.fetch` | `/control/installations/*/enroll` → 404; no `installation_key` table. | FR-015 | User Story 3 |
| E2E-P3.2-08 | H-AP | `VendorEntrypoint.registerIssuerKey` over the H-AP self service binding, `vendorCall` in `ai-platform/test/system/harness.ts` | AL-13 on issuer-key registration carries the decoded operation and `kid`. | FR-001, FR-002, FR-003 | User Story 1 |

### 2.5 Edge Cases

- An unknown `kid` returns 401 `unauthenticated`. (E2E-P3.2-02, 04 §2.1)
- A `kid` revoked through HP is rejected after one config-cache TTL. That TTL is at most 30 s. `revokeIssuerKey` sets `status` to `revoked`, and `ok` when the row is already `revoked`. It does not set `retiring`. (E2E-P3.2-02, 02 §6 K-2, 04 §1.3)
- A token with `aud=abo`, `aud=ai-platform-feed`, a lifetime of 601 s, or `ver="1"` returns 401. Those checks run before `org` is resolved, so no installation and no `tenant_binding` are written. (E2E-P3.2-03, 04 §2.1) [TB-3]
- The current token version is `"2"`. `ver="1"` is the retired version and is refused before any write. (E2E-P3.2-01, E2E-P3.2-03, 04 §2.1, 06 §3 V5)
- `retireIssuerKey` is the only writer of `retiring`. It sets `status` from `active` to `retiring`, and it is `ok` when the row is already `retiring`. A retiring `kid` is accepted until `not_after`. Outside validity it is not accepted. Two active `kid`s are both accepted. Rotation does not change the tenant binding. (E2E-P3.2-04, 02 §6 K-2, 04 §1.3, 04 §2.1, 05 §8 A13) [A13, K-2]
- A missing `kid` on `retireIssuerKey` or `revokeIssuerKey` is `rejected` with code `kid_not_found` and `detail` empty. Retire of a `revoked` row is `rejected` with code `kid_revoked` and `detail` empty, and the row stays `revoked`. (04 §1.3)
- The same `kid` with the same `public_key` is `ok` again and does not insert another row or change `status`. The same `kid` with a different `public_key` is `conflict` with code `public_key_mismatch` and empty `detail`. A `public_key` that is not the base64url encoding of the raw 32-byte Ed25519 public key is `rejected` with code `public_key_invalid` and `detail` empty. `registerIssuerKey` inserts `status` `active` and does not set `retiring`. (04 §1.3)
- `registerIssuerKey`, `retireIssuerKey`, `revokeIssuerKey`, and `listIssuerKeys` do not record a grant or a reversal. A successful call is `ok`, `code` is empty, and `receipt` is absent. (04 §1.2, 04 §1.6)
- The 51st new-org creation within 24 h inserts nothing. The clinic route answers 401 `unauthenticated`, and the platform raises AL-20. The cap counts `tenant_binding` rows with `epoch` 1 whose `created_at` falls in the last 24 hours. At most 50 such creations per day are stored, across all tenants. (E2E-P3.2-05, 04 §2.1, 03 §3.2, 05 §2)
- `GET /v1/requests/{ref}` with another org's token is not found. The owner org's token returns 200. (E2E-P3.2-06, 04 §6.1)
- `/control/installations/*/enroll` returns 404. The `installation_key` table is absent. (E2E-P3.2-07, 04 §6.1)
- `src/admission/index.ts`, `src/capability/index.ts`, and `src/entitlement/index.ts` are unchanged. Admission, capability, and entitlement still load the `entitlements` cache kind. Capability and entitlement still call `planTierMeetsMinimum`. The config cache still reads `plan` and `entitlement`. `PLAN_TIERS` and `planTierMeetsMinimum` stay. (06 §2 S9, 06 §4 P3.4, SC-002)
- A second valid token for an org that already has a binding returns the same installation and does not create a second binding. The first binding's epoch is 1, its `status` is `active`, and its `created_at` is the insert time. (E2E-P3.2-01, 03 §3.2, 04 §2.1)
- The first installation for an unknown org stores `status` `active`, `display_name` as the empty string, `region` as the empty string, and `enrolled_at` as the UTC ISO-8601 time of the insert. (E2E-P3.2-01, 03 §3.2, 04 §2.1)
- Clock skew is checked as the verifier does today (`src/identity/index.ts:283-296`). The existing replay rules still apply. (04 §2.1, 02 §3.2)

## 3. Requirements

### 3.1 Functional Requirements

- **FR-001**: `issuer_key` is a new D1 table with `kid`, `issuer`, `public_key`, `status` (`active`, `retiring`, `revoked`), `not_before`, `not_after`, `registered_by`, and `assertion_sha256`. `public_key` is the base64url encoding of the raw 32-byte Ed25519 public key. `registerIssuerKey` inserts `status` `active`. `retireIssuerKey` is the only writer of `retiring`. `revokeIssuerKey` sets `revoked`. (03 §3.2)
- **FR-002**: `registerIssuerKey` is class HP. Beyond `contract_version`, the input is `kid`, `public_key`, `not_before`, and `not_after`. `public_key` is the base64url encoding of the raw 32-byte Ed25519 public key. `ok` inserts `status` `active`, stores that `public_key` unchanged, sets `issuer` to the configured issuer id, `registered_by` to the Access email, and `assertion_sha256` to the assertion challenge hash. The same `kid` with the same `public_key` is `ok` again and does not insert another row or change `status`. `conflict` when that `kid` is stored with a different `public_key`: `code` is `public_key_mismatch` and `detail` is empty. A `public_key` that is not that encoding is `rejected` with code `public_key_invalid` and `detail` empty. On `ok`, `detail` is the JSON text of the `issuer_key` row, `code` is empty, and `receipt` is absent. This call does not set `retiring`. The method is idempotent by `kid`. (04 §1.3)
- **FR-003**: `registerIssuerKey`, `retireIssuerKey`, and `revokeIssuerKey` raise AL-13. AL-13 covers an issuer key registered, retired, or revoked. The body carries the decoded operation and its target. On issuer-key registration the alert carries the decoded operation and `kid`. The repeat is once. (05 §2, 06 §4 P3.2, E2E-P3.2-08)
- **FR-004**: The issuer-token verifier replaces `EnrolledKeyVerifier`. It checks that `kid` is in `issuer_key` and is active or retiring, within validity; that `iss` equals `ISSUER_ID` (the backend issuer id from `ai.issuer_id`), replacing `iss` = installation id; that `aud` matches the route; that the lifetime is at most 600 s; that clock skew matches the check at `src/identity/index.ts:283-296`; and that `ver` is `"2"`. AI tokens are compact JWS, `alg = EdDSA`, with header `kid`. The AI audience is `ai-platform`. (02 §3.2, 04 §2.1, 04 §6.1)
- **FR-005**: `token_contract` records version 2 and retires version 1, so `ver = "2"`. A token with `ver="1"` is refused with 401 before `org` is resolved and before any installation or `tenant_binding` write. (04 §2.1, 04 §6.1, 06 §4 P3.2, E2E-P3.2-03)
- **FR-006**: Revocation of a `kid` is effective within one config-cache TTL, and that TTL is at most 30 s. After that TTL, a token for the revoked `kid` is rejected. Config-cache reads `issuer_key` and `tenant_binding`. It no longer reads `installation_key`. It still reads `plan` and `entitlement`. Coverage is never read through the cache: this unit adds no coverage reader. `src/admission/index.ts`, `src/capability/index.ts`, and `src/entitlement/index.ts` are unchanged. Admission, capability, and entitlement still load the `entitlements` cache kind. Capability still loads plan-scoped grants through the `grants` kind, including the `plan:` grant fallback. Those three modules do not read `coverage_mirror` in this unit. (02 §6, 04 §6.1, 06 §2 S9, 06 §4 P3.4, E2E-P3.2-02)
- **FR-007**: `tenant_binding` is a new D1 table with `org_id`, `installation_id`, `epoch` (1 for the first binding of an org, +1 per re-creation), `status` (`active`, `held_for_transfer`, `retired`), `retired_at`, and `reason`. A partial unique index allows at most one binding per `org_id` that is `active` or `held_for_transfer`. The first binding of an org is `status` `active` and `epoch` 1. `created_at` is the insert time. The 50-creations-per-day cap counts rows with `epoch` 1 whose `created_at` falls in the last 24 hours. (03 §3.2)
- **FR-008**: The first valid token for an unknown `org` creates an installation and a binding at epoch 1. The installation stores `org_id` from the token, a new platform clinic UUID as `installation_id`, `status` `active`, `display_name` as the empty string, `region` as the empty string, and `enrolled_at` as the UTC ISO-8601 time of the insert. The binding stores `status` `active`, `epoch` 1, and `created_at` as that same time. Creation is capped at 50 per day across all tenants: the count is `tenant_binding` rows with `epoch` 1 whose `created_at` falls in the last 24 hours. The 51st such attempt inserts nothing, the clinic route answers 401 `unauthenticated`, and the platform raises AL-20. (03 §3.2, 04 §2.1, 05 §2, E2E-P3.2-01, E2E-P3.2-05)
- **FR-009**: `installation` remains the platform clinic identity. Its `status` is unconstrained text, and the row is never removed. The first valid token for an unknown org inserts `status` `active`, `display_name` as the empty string, `region` as the empty string, and `enrolled_at` as the UTC ISO-8601 time of the insert. `Principal.installationId` is resolved through `tenant_binding`. (03 §3.2, 04 §6.1)
- **FR-010**: Discovery and `authenticateGetRequest` use the issuer-token verifier. `GET /v1/requests/{ref}` with the owner org's token returns 200. The same reference with another org's token is not found. (04 §6.1, E2E-P3.2-06)
- **FR-011**: An unknown `kid` returns 401 `unauthenticated`. On an AI route, a token with `aud=abo`, `aud=ai-platform-feed`, or a lifetime of 601 s returns 401. A billing token cannot run AI. (02 §2 TB-3, 02 §3.2, 04 §2.1, E2E-P3.2-02, E2E-P3.2-03)
- **FR-012**: The verifier keeps the existing replay rules. (02 §3.2)
- **FR-013**: Tokens of two active `kid`s are both accepted. `retireIssuerKey` (HP) sets the old `kid` to `retiring`, and that `kid` stays accepted until `not_after`. `revokeIssuerKey` (HP) sets the `kid` to `revoked`. Issuer-key rotation does not change the tenant binding. (02 §6, 04 §2.1, 05 §8 A13, E2E-P3.2-04)
- **FR-014**: AL-20 is the platform alert for tenant-binding creation above 50 per day. The platform raises it, and the repeat interval is daily. (05 §2, E2E-P3.2-05)
- **FR-015**: The platform drops `installation_key`, the enroll, rotate, and revoke-key handlers and routes, and `INSTALLATION_KEY_TTL_DAYS`. `/control/installations/*/enroll` returns 404, and there is no `installation_key` table. (04 §6.1, 06 §4 P3.2, E2E-P3.2-07)
- **FR-016**: `src/platform-vocabulary.ts` renames the key-algorithm constant for issuer keys. It keeps `PLAN_TIERS` and `planTierMeetsMinimum`. `src/capability/index.ts` and `src/entitlement/index.ts` keep calling `planTierMeetsMinimum`. Entitlement still rejects a row whose status is not `active`, and it still rejects a plan that fails `planTierMeetsMinimum`. Capability still applies that same tier check at its existing call sites. P3.4 removes those checks when entitlement is no longer read on the request path. (04 §6.1, 06 §2 S9, 06 §4 P3.4)
- **FR-017**: H-AP `newClinic()` registers the test issuer key and mints issuer tokens. Every suite that enrolls is migrated. `/control/entitle` stays for admitting test clinics. When an e2e reset deletes `operator_credential`, the harness drops the cached issuer credential and does not reuse that signer. The next `registerIssuerKey` bootstraps a new signer and sets that row's `activates_at` at or before wall-clock now, so the existing signer-read promotion marks it `active` before the call. Issuer tokens stay `ver` `"2"` and still verify. The e2e config does not gain `TEST_CLOCK`, and credential status rules in the entrypoint stay as they are. Stage 00, 01, and 05 token-contract assertions expect the reset seed: version 2 current and version 1 retired (FR-005). They do not expect or reseed a sole live version 1. (06 §3 V2, 06 §4 P3.2)
- **FR-018**: `retireIssuerKey` is class HP. Beyond `contract_version`, the input is `kid`. `ok` sets `status` from `active` to `retiring`, and `ok` when it is already `retiring`. Tokens for that `kid` stay accepted until `not_after`. A missing `kid` is `rejected` with code `kid_not_found` and `detail` empty. A `revoked` row stays `revoked` and the result is `rejected` with code `kid_revoked` and `detail` empty. On `ok`, `detail` is the JSON text of the `issuer_key` row, `code` is empty, and `receipt` is absent. This is the only writer of `retiring`. The method is idempotent by target state. (04 §1.3, 02 §6)
- **FR-019**: `revokeIssuerKey` is class HP. Beyond `contract_version`, the input is `kid`. `ok` sets `status` to `revoked`, and `ok` when it is already `revoked`. It does not set `retiring`. A missing `kid` is `rejected` with code `kid_not_found` and `detail` empty. On `ok`, `detail` is the JSON text of the `issuer_key` row, `code` is empty, and `receipt` is absent. The method is idempotent by target state. (04 §1.3, 02 §6)
- **FR-020**: `listIssuerKeys` is class M. It takes no input beyond `contract_version`. The result is `ok`. `detail` is the JSON text of an array of `{kid, public_key, status, not_before, not_after}` for each `issuer_key` with `status` `active` or `retiring`. `public_key` is the base64url encoding of the raw 32-byte Ed25519 public key. `status` and the validity times are in the list and are not themselves a pin mismatch. `receipt` is absent and `code` is empty. (04 §1.2, 04 §1.3)
- **FR-021**: `registerIssuerKey`, `revokeIssuerKey`, `retireIssuerKey`, and `listIssuerKeys` do not record a grant or a reversal, so they do not return `applied` or `already_applied`. A successful call is `ok`: `receipt` is absent and `code` is empty. On register, revoke, and retire, `detail` is the JSON text of the `issuer_key` row. On `listIssuerKeys`, `detail` is the JSON text of an array of `{kid, public_key, status, not_before, not_after}` for each row with `status` `active` or `retiring`. The receipt records a grant or a reversal. These methods return `ok` and do not include it. (04 §1.2, 04 §1.6)

### 3.2 Key Entities

- **`issuer_key`**: `kid`, `issuer`, `public_key`, `status` (`active`, `retiring`, `revoked`), `not_before`, `not_after`, `registered_by`, `assertion_sha256`. `public_key` is the base64url encoding of the raw 32-byte Ed25519 public key. `registerIssuerKey` inserts `status` `active`. `retireIssuerKey` is the only writer of `retiring`. `revokeIssuerKey` sets `revoked`. (03 §3.2)
- **`tenant_binding`**: `org_id`, `installation_id`, `epoch` (1 for the first binding of an org, +1 per re-creation), `status` (`active`, `held_for_transfer`, `retired`), `retired_at`, `reason`, `created_at`. At most one binding per `org_id` is `active` or `held_for_transfer`. The first binding of an org is `status` `active` and `epoch` 1. `created_at` is the insert time. The 50-creations-per-day cap counts rows with `epoch` 1 whose `created_at` falls in the last 24 hours. (03 §3.2)
- **`installation`**: The platform clinic identity. `status` is unconstrained text. The row is never removed. The first valid token for an unknown org inserts `status` `active`, `display_name` as the empty string, `region` as the empty string, and `enrolled_at` as the UTC ISO-8601 time of the insert. `Principal.installationId` comes from the binding. (03 §3.2, 04 §6.1)
- **Issuer-key methods**: `registerIssuerKey` (class HP; input `kid`, `public_key`, `not_before`, `not_after`), `retireIssuerKey` (class HP; input `kid`; the only writer of `retiring`), `revokeIssuerKey` (class HP; input `kid`), and `listIssuerKeys` (class M; no further input). A successful call is `ok` with `code` empty and no `receipt`. On register, retire, and revoke, `detail` is the JSON text of the `issuer_key` row. On `listIssuerKeys`, `detail` is the JSON text of an array of `{kid, public_key, status, not_before, not_after}` for each `active` or `retiring` row. `public_key` is the base64url encoding of the raw 32-byte Ed25519 public key. The same `kid` with a different `public_key` is `conflict` with code `public_key_mismatch`. A `public_key` that is not that encoding is `rejected` with code `public_key_invalid`. A missing `kid` on retire or revoke is `rejected` with code `kid_not_found`. Retire of a `revoked` row is `rejected` with code `kid_revoked`. (04 §1.2, 04 §1.3, 04 §1.6)

## 4. Constitution Alignment

### 4.1 Architecture & Operations Impact

- **Clinic Fit**: Issuer tokens, the issuer-key registry, and tenant bindings are how a clinic member's desktop reaches the AI platform. The codebase cell is ai-platform. The row names no wiring exception (rule S3).
- **Layer Placement**: Implementation stays in `ai-platform`. Live entries are `VendorEntrypoint.registerIssuerKey`, `VendorEntrypoint.retireIssuerKey`, `VendorEntrypoint.revokeIssuerKey`, and `VendorEntrypoint.listIssuerKeys` over the H-AP self service binding, `GET /v1/capabilities` and `GET /v1/requests/{reference}` via `SELF.fetch`, and `POST /control/installations/{id}/enroll` via `SELF.fetch`. `plan.md` re-runs the constitution check in 02 §7 (rule S12).
- **Data Integrity & Security**: New D1 tables are `issuer_key` and `tenant_binding`. `installation` stays and is not removed. `installation_key` is dropped. `public_key` is the base64url encoding of the raw 32-byte Ed25519 public key. A partial unique index allows at most one live binding per `org_id`. The first installation stores `status` `active`, `display_name` as the empty string, `region` as the empty string, and `enrolled_at` as the UTC ISO-8601 time of the insert. The first binding stores `status` `active`, `epoch` 1, and `created_at` as that same time. The verifier checks `kid`, `iss`, `aud`, lifetime, clock skew, and `ver` before it resolves `org`. Alert bodies keep the frozen format: codes and ids, plus the decoded operation; AL-13 on registration also carries `kid`. (02 §3.2, 02 §6, 03 §3.2, 04 §1.3, 04 §2.1)
- **Failure Handling**: An unknown `kid` returns 401 `unauthenticated` (E2E-P3.2-02). A revoked `kid` is rejected after one config-cache TTL (E2E-P3.2-02). `aud=abo`, `aud=ai-platform-feed`, a lifetime of 601 s, or `ver="1"` returns 401 before any installation or binding write (E2E-P3.2-03). The 51st new-org creation within 24 h inserts nothing, the clinic route answers 401 `unauthenticated`, and the platform raises AL-20 (E2E-P3.2-05, 04 §2.1). The same `kid` with a different `public_key` is `conflict` with code `public_key_mismatch`. A `public_key` that is not the base64url raw 32-byte encoding is `rejected` with code `public_key_invalid`. A missing `kid` on retire or revoke is `rejected` with code `kid_not_found`. Retire of a `revoked` row is `rejected` with code `kid_revoked` and leaves the row `revoked` (04 §1.3). Another org's token on `GET /v1/requests/{ref}` is not found (E2E-P3.2-06). The enroll route returns 404 (E2E-P3.2-07).

## 5. Out of Scope

feed audience (→ P3.9); `/v1/coverage` role check (→ P3.9); `held_for_transfer` binding states (→ P3.8); removing entitlement (→ P3.10).

- This unit names no Do not read section. No architecture material outside its Read spans.
- No rewrite of a Consumes contract: method dispatch + class table; auth refusal codes; credential lifecycle; alert body format; `platform_alert`. (rule S7)
- No module that no test-plan row reaches (rule S8).
- No removal of a transitional path a later unit owns (rule S9): `/control/entitle`, which keeps test clinics admitted until P3.4; the `plan` and `entitlement` config-cache readers, `PLAN_TIERS`, and `planTierMeetsMinimum`, which `src/admission/index.ts`, `src/capability/index.ts`, and `src/entitlement/index.ts` keep using until P3.4 stops reading entitlement on the request path; entitlement, plan, and invoice tables and the remaining `/control/*` routes, removed in P3.10.
- No second codebase beyond ai-platform.

## 6. Success Criteria

### 6.1 Measurable Outcomes

- **SC-001**: E2E-P3.2-01, E2E-P3.2-02, E2E-P3.2-03, E2E-P3.2-04, E2E-P3.2-05, E2E-P3.2-06, E2E-P3.2-07, and E2E-P3.2-08 pass in harness H-AP.
- **SC-002**: Every earlier suite stays green (rule S2).

## 7. Assumptions

- Rule S9: this unit removes enrollment. `/control/entitle` remains until P3.4. Entitlement, plan, and invoice tables and the remaining `/control/*` routes remain until P3.10.
- `src/admission/index.ts`, `src/capability/index.ts`, and `src/entitlement/index.ts` are unchanged in this unit. Admission, capability, and entitlement still load the `entitlements` cache kind. Capability still loads plan-scoped grants, including the `plan:` grant fallback, and still calls `planTierMeetsMinimum`. Entitlement still requires status `active` and still calls `planTierMeetsMinimum`. The config cache still reads `plan` and `entitlement`. `PLAN_TIERS` and `planTierMeetsMinimum` stay. This unit adds the `issuer_key` and `tenant_binding` readers, removes the `installation_key` reader, and renames the key-algorithm constant for issuer keys. P3.4 removes the tier checks and the request-path entitlement read, and reads `/v1/capabilities` from `coverage_mirror`. P3.10 drops the `plan` and `entitlement` tables.
