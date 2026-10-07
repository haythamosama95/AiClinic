# Feature Specification: Console passkey ceremony and ABO-side HP actions

**Feature Branch**: `ai/082-abo-p4-7-console-passkey-ceremony-abo-side-hp`

**Created**: 2026-10-07

**Status**: Draft

**Input**: P4.7 — Console passkey ceremony and ABO-side HP actions

## 1. Unit Contract

**Implements** — Read: 02 §3.3 (last paragraph); 04 §1.5; 05 §3.2 (rows manual chargeback, release withheld, publish/retire offer or terms, erase contact data); 03 §2.2 ("sellable" paragraph); 03 §2.3 (erasure paragraph); 03 §2.6 (row `payment_release`); 04 §1.3 row listOperatorCredentials.

- WebAuthn `get` ceremony in the console, building the operation object with the package; ABO-side HP verification against the platform's `listOperatorCredentials` (cached and refreshed) plus freshness and single use; actions: publish, retire and reinstate offer versions and terms versions (`offer_event`, terms text in R2, `assertion_sha256`); release a withheld payment (refused when fully reversed) → grant request; manual chargeback (`source=operator`, `detected_via=manual`) → the P4.5 effect pipeline; erase a tenant's contact data (blank every version, `erased_at`, delete raw R2 bodies, keep hashes).

**Freezes** — None. The unit row states no Outputs / freezes line.

**Consumes** — P4.6: class-H `recordOperatorAction` on `VendorEntrypoint` (05 §3.2 sentence after the action table: one `control_audit` insert, every other platform table unchanged). Consumed by this unit's retry and cancel, and by later ABO-verified actions. P3.1: method dispatch + class table; auth refusal codes; credential lifecycle; alert body format; `platform_alert`.

**Open questions relied on** — None.

**Spikes** — None.

## Clarifications

### Session 2026-10-07

- Q: Where should the passkey ceremony and the ABO-side HP actions live? → A: Extend `abo/src/ops/`, which serves `/ops/*`. The ABO worker fetch keeps delegating that prefix to it. `opsFetch` stays in `abo/test/system/harness.ts`. Publish, retire, and reinstate of offer versions and terms versions, release, manual chargeback, and erasure are actions in that module. The shared package builds the operation object and the challenge. `listOperatorCredentials` and `recordOperatorAction` stay on the existing `VendorEntrypoint` behind the `PLATFORM` binding. Reinstate has no separate E2E id. `[implementation choice — no §citation]`
- Q: When should the ABO refresh `listOperatorCredentials`? → A: Each ABO-side HP verification calls `listOperatorCredentials` once and checks the assertion against that response. E2E-P4.7-07 revokes the credential on the platform, then the next HP `opsFetch` loads the list again and is refused. `[implementation choice — no §citation]`
- Q: How should H-XW build WebAuthn assertions for these scenarios? → A: The harness uses the shared package to form the canonical operation object and challenge, and signs with a test credential that the platform lists as active. E2E-P4.7-03 submits one call with the assertion omitted, one whose operation does not match the challenge, and one whose `issued_at` the ABO test clock places more than 5 minutes in the past. `[implementation choice — no §citation]`
- Q: How should a withheld release reach an applied grant, and how should a fully reversed release be refused? → A: An accepted release appends `payment_release` and starts the same grant request the paid path already uses. The harness runs that path until the grant is applied. For the refusal, the harness uses a withheld payment that the existing reversal records already treat as fully reversed. That call appends no `payment_release` and starts no grant. E2E-P4.7-04 stays the only id. `[implementation choice — no §citation]`
- Q: How should E2E-P4.7-05 reach the P4.5 effect on the real platform? → A: The harness completes a real H-XW purchase so the payment funds the current term, then `opsFetch` records the manual chargeback (`source=operator`, `detected_via=manual`). The existing P4.5 effect pipeline, against the real platform worker, performs the void, reverses the term, holds queued, and fires AL-06. `[implementation choice — no §citation]`
- Q: Where should a spent challenge hash be stored for ABO-verified single use? → A: On acceptance the ABO inserts the challenge hash into its own D1 `assertion_used` store, the store named in 04 §1.5, and rejects a repeat with `assertion_used` before the HP write. `[implementation choice — no §citation]`
- Q: `listOperatorCredentials` returns only active `{credential_id, public_key_cose, alg}` rows. FR-002 and the edge cases require `credential_revoked` when a credential is revoked and `credential_not_active` when it is not active. Which refusal code does an ABO-side HP check use when the credential id is absent from that list? → A: `credential_not_active`. The active-only array is the whole registry the ABO may read. An id that is not in it is not `active`, whether the row is still `pending`, `revoked`, or unknown. `credential_revoked` stays the platform's code when its own credential read sees `status` `revoked` (04 §1.5). This unit does not add a platform method that returns that status. After a revoke, the next HP check loads the list again and refuses with `credential_not_active`. `[resolver assumption]`

## 2. User Scenarios & Testing

### 2.1 User Story 1 - Passkey ceremony and ABO-side verification (Priority: P1)

An operator runs a WebAuthn `get` ceremony in the console. The console builds the operation object with the package. The ABO verifies that assertion for its own HP actions against the platform's `listOperatorCredentials` list, which it caches and refreshes, and it checks freshness and single use. An HP action with no assertion, an assertion over a different operation, or a stale assertion is refused, and `operator_action` records the result. After a credential is revoked on the platform, the next refresh of that list makes the ABO refuse HP actions that use it.

**Why this priority**: Publish, retire, release, chargeback, and erasure are HP actions. They depend on this ceremony and on this verification.

**Independent Test**: E2E-P4.7-03 and E2E-P4.7-07 in harness H-XW.

**Acceptance Scenarios**:

1. **Given** an HP action with no assertion, or an assertion over a different operation, or a stale assertion, **When** the operator submits it on the console, **Then** the ABO refuses it and `operator_action` records the result. (E2E-P4.7-03)
2. **Given** a credential that has been revoked on the platform, **When** the ABO has refreshed `listOperatorCredentials` and the operator attempts an HP action with that credential, **Then** the ABO refuses the action with `credential_not_active`, because that id is absent from the active-only list. (E2E-P4.7-07)

### 2.2 User Story 2 - Publish and retire an offer (Priority: P2)

An operator publishes or retires an offer with a passkey. An offer is sellable when its latest event is `published`; the sellable version is the latest published one. Publishing offer v2 at a new price makes `/v1/offers` show v2. An open v1 checkout is still charged and granted at v1, and past prices remain in `offer_version`. Retiring an offer removes it from `/v1/offers`. A checkout on that offer is `offer_unavailable`. Existing platform terms stay unchanged.

**Why this priority**: User Story 1 is the passkey check these HP catalogue actions use. The sellable catalogue is what a later checkout reads.

**Independent Test**: E2E-P4.7-01 and E2E-P4.7-02 in harness H-XW.

**Acceptance Scenarios**:

1. **Given** a published offer v1 and an open checkout on v1, **When** the operator publishes offer v2 at a new price with a passkey, **Then** `/v1/offers` shows v2, and that open v1 checkout is still charged and granted at v1. (E2E-P4.7-01, A8, FR-04)
2. **Given** a sellable offer, **When** the operator retires it with a passkey, **Then** it is gone from `/v1/offers`, a checkout on it returns `offer_unavailable`, and existing platform terms are unchanged. (E2E-P4.7-02, A21, A33)

### 2.3 User Story 3 - Release, chargeback, and erasure (Priority: P3)

An operator releases a withheld payment, records a manual chargeback, or erases a tenant's payer contact. Release of a withheld payment writes `payment_release` and leads to a grant request that is applied. Release of a fully reversed payment is refused. A manual chargeback is `source=operator` and `detected_via=manual` and enters the P4.5 effect pipeline: on the payment funding the current term, the effect is void, the term is reversed, queued is held, and AL-06 fires. Erasure blanks `name`, `email`, and `phone` on every version of that tenant, sets `erased_at`, deletes that tenant's raw provider bodies, and keeps the hashes. The ledger export stays intact. The next checkout for that tenant is `billing_contact_required`.

**Why this priority**: User Story 1 is the passkey check. These three actions change payment disposition, the current term, or stored contact data.

**Independent Test**: E2E-P4.7-04, E2E-P4.7-05, and E2E-P4.7-06 in harness H-XW. Earlier suites stay green, and E2E-P4.7-01, E2E-P4.7-02, E2E-P4.7-03, and E2E-P4.7-07 still pass.

**Acceptance Scenarios**:

1. **Given** a withheld payment, **When** the operator releases it with a passkey, **Then** the grant is applied. **Given** a fully reversed payment, **When** the operator releases it, **Then** the ABO refuses. (E2E-P4.7-04, FR-16)
2. **Given** the payment funding the current term, **When** the operator records a manual chargeback with a passkey, **Then** the effect is void, the term is reversed, queued is held, and AL-06 fires. (E2E-P4.7-05, A15, FR-44)
3. **Given** a tenant with billing-contact versions and raw provider bodies, **When** the operator erases that tenant's contact data with a passkey, **Then** the contact fields are blank in all versions, the R2 evidence bodies are deleted, the D1 hashes and the ledger export stay intact, and the next checkout returns `billing_contact_required`. (E2E-P4.7-06, R-9)

### 2.4 Test plan

| ID | Harness | Entry point | Assertion (+ tags) | Proves | Story |
| --- | --- | --- | --- | --- | --- |
| E2E-P4.7-01 | H-XW | `opsFetch` → `SELF.fetch` on the ABO worker for `OPS_ORIGIN` + `/ops/*` (`abo/test/system/harness.ts`) publishing the offer with a passkey; outcome read by `billingFetch` → `SELF.fetch` `GET /v1/offers` and by the open v1 checkout's charge and grant | Publish offer v2 (new price) with a passkey → `/v1/offers` shows v2; an open v1 checkout is still charged and granted at v1 [A8, FR-04] | FR-005, FR-007, FR-011 | User Story 2 |
| E2E-P4.7-02 | H-XW | `opsFetch` → `SELF.fetch` on the ABO worker for `OPS_ORIGIN` + `/ops/*` retiring the offer; outcome read by `billingFetch` `GET /v1/offers` and `POST /v1/checkouts`, and by existing platform terms on the real platform worker in H-XW | Retire an offer → gone from `/v1/offers`; a checkout on it → `offer_unavailable`; existing platform terms unchanged [A21, A33] | FR-006, FR-007, FR-011 | User Story 2 |
| E2E-P4.7-03 | H-XW | `opsFetch` → `SELF.fetch` on the ABO worker for `OPS_ORIGIN` + `/ops/*` for an HP action with no assertion, with an assertion over a different operation, and with a stale assertion; `operator_action` in ABO D1 | HP action with no assertion, an assertion over a different operation, or a stale one → refused; `operator_action` records the result | FR-001, FR-002, FR-003 | User Story 1 |
| E2E-P4.7-04 | H-XW | `opsFetch` → `SELF.fetch` on the ABO worker for `OPS_ORIGIN` + `/ops/*` releasing a withheld payment, and releasing a fully reversed payment | Release a withheld payment → grant applied; releasing a fully reversed payment → refused [FR-16] | FR-008, FR-011 | User Story 3 |
| E2E-P4.7-05 | H-XW | `opsFetch` → `SELF.fetch` on the ABO worker for `OPS_ORIGIN` + `/ops/*` recording a manual chargeback; the P4.5 effect pipeline against the real platform worker in H-XW | A15: manual chargeback on the payment funding the current term → void → term reversed, queued held; AL-06 [FR-44] | FR-009, FR-011 | User Story 3 |
| E2E-P4.7-06 | H-XW | `opsFetch` → `SELF.fetch` on the ABO worker for `OPS_ORIGIN` + `/ops/*` erasing the tenant's contact data; ABO D1 contact versions and hashes, R2 evidence bodies, the ledger export, then `billingFetch` `POST /v1/checkouts` | Erasure → contact fields blank in all versions; R2 evidence bodies deleted; D1 hashes and the ledger export intact; the next checkout → `billing_contact_required` [R-9] | FR-010, FR-011 | User Story 3 |
| E2E-P4.7-07 | H-XW | Platform credential revoke, then `VendorEntrypoint.listOperatorCredentials` over the `PLATFORM` binding (`ai-platform/src/vendor/entrypoint.ts`); `opsFetch` → `SELF.fetch` on the ABO worker for `OPS_ORIGIN` + `/ops/*` for an HP action after that refresh | Credential revoked on the platform → the ABO refuses HP with it after refresh, code `credential_not_active` | FR-002, FR-004 | User Story 1 |

### 2.5 Edge Cases

- An HP action with no assertion, an assertion over a different operation, or a stale assertion is refused, and `operator_action` records the result. A stale assertion is `issued_at` older than 5 minutes, refused with `assertion_expired`. An assertion over a different operation does not match the challenge, which is base64url(SHA-256(canonical operation object)). A class HP call that omits `assertion` is `rejected` with code `assertion_required`, except bootstrap `registerOperatorCredential` while `operator_credential` is empty. (E2E-P4.7-03, 04 §1.5, 02 §3.3 last paragraph)
- A challenge hash already stored is `rejected` with code `assertion_used`. On the platform credential read, a credential still `pending` because `activates_at` is ahead is `rejected` with code `credential_not_active`, and a row with `status` `revoked` is `rejected` with code `credential_revoked`. An `actor_email` different from the Access JWT email is `rejected` with code `actor_email_mismatch`. (04 §1.5)
- A credential id absent from the active-only `listOperatorCredentials` array is `rejected` by the ABO-side HP check with code `credential_not_active`. That covers a still-`pending` row, a `revoked` row, and an unknown id. `credential_revoked` is not an ABO-side code: the list has no status, and this unit does not call another platform method to learn one. A credential revoked on the platform is therefore refused with `credential_not_active` after the list is refreshed. That list is `ok` with `detail` the JSON text of `{credential_id, public_key_cose, alg}` for each `operator_credential` with `status` `active`. `receipt` is absent and `code` is empty. (E2E-P4.7-07, 04 §1.3 row `listOperatorCredentials`, 04 §1.5)
- Releasing a fully reversed payment is refused. (E2E-P4.7-04, FR-16)
- A checkout on a retired offer is `offer_unavailable`. Existing platform terms are unchanged. (E2E-P4.7-02, A21, A33)
- After erasure, the next checkout is `billing_contact_required`. D1 hashes and the ledger export stay intact. (E2E-P4.7-06, 03 §2.3, R-9)
- An open checkout snapped at v1 is still charged and granted at v1 after v2 is published. Past prices remain in `offer_version`. (E2E-P4.7-01, 03 §2.2 sellable paragraph, A8, FR-04)

## 3. Requirements

### 3.1 Functional Requirements

- **FR-001**: The ABO console runs the WebAuthn `get` ceremony and builds the operation object with the package. The operation object is `{op, params, actor_email, issued_at, nonce, contract_version}`, and `params` is the exact action input without the assertion. The challenge is base64url(SHA-256(canonical operation object)). `rpId` is the console hostname. `clientDataJSON.origin` equals `https://ops.<vendor-domain>`. `type` is `webauthn.get`. User presence and user verification are both set. The credential algorithm is ES256 (DER signature converted to raw) or EdDSA. `actor_email` equals the email in the Access JWT verified for the same call. (Implements, 04 §1.5)
- **FR-002**: The ABO verifies its own HP actions against the platform's `listOperatorCredentials`, cached and refreshed, plus freshness and single use. `listOperatorCredentials` is class M and returns `ok`. `detail` is the JSON text of an array of `{credential_id, public_key_cose, alg}` for each `operator_credential` with `status` `active`. `receipt` is absent and `code` is empty. `issued_at` must be within 5 minutes of now. `issued_at` older than 5 minutes is `rejected` with code `assertion_expired`. The challenge hash is single-use: a challenge hash already used is `rejected` with code `assertion_used`. The ABO-side check looks up the assertion's `credential_id` in that array. When the id is absent, the check is `rejected` with code `credential_not_active`. Absence is the only fact the list gives, so a still-`pending` row, a `revoked` row, and an unknown id all use that code. `credential_revoked` remains the platform's code when its own credential read sees `status` `revoked` (04 §1.5). This unit does not call another platform method to learn that status. A different `actor_email` is `rejected` with code `actor_email_mismatch`. (Implements, 04 §1.3 row `listOperatorCredentials`, 04 §1.5)
- **FR-003**: An HP action with no assertion, an assertion over a different operation, or a stale assertion is refused, and `operator_action` records the result. A class HP call that omits `assertion` is `rejected` with code `assertion_required`, except bootstrap `registerOperatorCredential` while `operator_credential` is empty. A class H or HP call whose Access JWT is missing, expired, or has the wrong `aud` is `rejected` with code `unauthenticated` and writes nothing. (E2E-P4.7-03, 02 §3.3 last paragraph, 04 §1.5)
- **FR-004**: When a credential is revoked on the platform, the ABO refuses HP actions that use it after refreshing `listOperatorCredentials`, with code `credential_not_active`, because that id is absent from the active-only list. (E2E-P4.7-07, 04 §1.5, 04 §1.3 row `listOperatorCredentials`)
- **FR-005**: Publishing or retiring is an HP action because it changes what money buys. An offer is sellable when its latest event is `published`; the sellable version is the latest published one. Publishing offer v2 at a new price with a passkey makes `/v1/offers` show v2. An open v1 checkout is still charged and granted at v1. Past prices remain in `offer_version`. (03 §2.2 sellable paragraph, Implements, E2E-P4.7-01, A8, FR-04)
- **FR-006**: Retiring an offer removes it from `/v1/offers`. A checkout on it returns `offer_unavailable`. Existing platform terms are unchanged. (E2E-P4.7-02, 03 §2.2 sellable paragraph, A21, A33)
- **FR-007**: The same HP actions publish, retire, and reinstate offer versions and terms versions. They write `offer_event`, store terms text in R2, and record `assertion_sha256`. (Implements)
- **FR-008**: Release of a withheld payment is HP, verified by the ABO. It appends `payment_release` (`payment_id`, `operator_action_id`, `at`) and leads to a grant request. The grant is applied. Releasing a fully reversed payment is refused. (05 §3.2 row "Release a withheld payment", 03 §2.6 row `payment_release`, Implements, E2E-P4.7-04, FR-16)
- **FR-009**: Recording a manual chargeback is HP, verified by the ABO. The reversal is `source=operator` and `detected_via=manual`, and it enters the P4.5 effect pipeline. On the payment funding the current term, the effect is void, the term is reversed, queued is held, and AL-06 fires. (05 §3.2 row "Record a manual chargeback", Implements, E2E-P4.7-05, A15, FR-44)
- **FR-010**: Erasing a tenant's payer contact data and raw provider bodies is HP, verified by the ABO. It blanks `name`, `email`, and `phone` for every version of that tenant, sets `erased_at`, deletes that tenant's raw R2 bodies, and keeps the hashes. The ledger export stays intact. The next checkout returns `billing_contact_required`. The legal basis and timing of erasure follow the R-9 advice. (05 §3.2 row "Erase a tenant's payer contact data and raw provider bodies", 03 §2.3 erasure paragraph, Implements, E2E-P4.7-06, R-9)
- **FR-011**: These ABO-verified HP actions consume frozen class-H `recordOperatorAction` on `VendorEntrypoint`. That call inserts one `control_audit` row and leaves every other platform table unchanged. (P4.6 Outputs / freezes)

### 3.2 Key Entities

- **`offer_event`**: Append-only record of publish, retire, and reinstate for an offer version, written by the HP catalogue actions, with `assertion_sha256`. An offer is sellable when its latest event is `published`. Past prices remain in `offer_version`. (Implements, 03 §2.2 sellable paragraph)
- **Terms text**: Terms versions published, retired, or reinstated by the same HP actions. The text is stored in R2, with `assertion_sha256`. (Implements)
- **`payment_release`**: Append-only row for the HP release of a withheld payment. Fields are `payment_id`, `operator_action_id`, and `at`. (03 §2.6 row `payment_release`)
- **`billing_contact` erasure**: The erasure action blanks `name`, `email`, and `phone` on every version of one tenant, sets `erased_at`, and leaves the hashes. Raw provider bodies for that tenant are deleted. (03 §2.3 erasure paragraph, Implements)
- **`operator_action`**: The ABO record that stores the result of a refused HP action. (E2E-P4.7-03)

## 4. Constitution Alignment

### 4.1 Architecture & Operations Impact

- **Clinic Fit**: An operator publishes or retires what a clinic can buy, releases a withheld payment, records a manual chargeback on the payment funding the current term, and erases one tenant's payer contact. The unit adds no second clinic product and no clinic-desktop flow.
- **Layer Placement**: Codebase is `abo`. No wiring exception is named. The live entry is `opsFetch` → `SELF.fetch` on the ABO worker for the ops host `/ops/*`. Catalogue and checkout outcomes are read on the billing host through `billingFetch` (`GET /v1/offers`, `POST /v1/checkouts`). `listOperatorCredentials` and `recordOperatorAction` are called on the real platform `VendorEntrypoint` over the `PLATFORM` binding. H-XW runs that platform worker from source. `plan.md` re-runs the constitution check in 02 §7 (rule S12).
- **Data Integrity & Security**: ABO-side HP actions require a WebAuthn `get` assertion over the operation object, checked against the refreshed active-credential list, with freshness and single use. `offer_event` and `payment_release` are append-only. Erasure blanks contact fields and deletes raw provider bodies while the hashes and the ledger export stay. ABO-verified actions consume `recordOperatorAction`, which inserts one `control_audit` row and leaves every other platform table unchanged. (04 §1.5, 03 §2.2, 03 §2.3, 03 §2.6, P4.6 Outputs / freezes)
- **Failure Handling**: An HP action with no assertion, an assertion over a different operation, or a stale assertion is refused, and `operator_action` records the result (E2E-P4.7-03). A credential revoked on the platform is refused after refresh with `credential_not_active` (E2E-P4.7-07). Releasing a fully reversed payment is refused (E2E-P4.7-04). A checkout on a retired offer is `offer_unavailable` (E2E-P4.7-02). After erasure, the next checkout is `billing_contact_required` (E2E-P4.7-06).

## 5. Out of Scope

- Relays of platform HP actions (→ P4.8, P4.9).
- No Do-not-read material. The unit row names none.
- No rewrite of consumed contracts. P4.6's class-H `recordOperatorAction` stays frozen: one `control_audit` insert, every other platform table unchanged. P3.1's method dispatch, class table, auth refusal codes, credential lifecycle, alert body format, and `platform_alert` stay frozen. This unit calls `listOperatorCredentials` and `recordOperatorAction`.
- No module that no test-plan row reaches (rule S8). The ceremony and ABO-side verification are reached by E2E-P4.7-03 and E2E-P4.7-07. Publish is reached by E2E-P4.7-01. Retire is reached by E2E-P4.7-02. Reinstate is the same offer and terms HP action as publish and retire (`offer_event`, terms text in R2, `assertion_sha256`). Release is reached by E2E-P4.7-04. Manual chargeback is reached by E2E-P4.7-05. Erasure is reached by E2E-P4.7-06. The `listOperatorCredentials` refresh is reached by E2E-P4.7-07. `recordOperatorAction` is reached by the ABO-verified HP actions in E2E-P4.7-01, E2E-P4.7-02, E2E-P4.7-04, E2E-P4.7-05, and E2E-P4.7-06.
- No S9 path owned by a later unit. Relays of platform HP actions stay with P4.8 and P4.9. Enrollment removal stays with P3.2. `/control/*` removal stays with P3.10.
- No second codebase. The Codebase cell is `abo`.

## 6. Success Criteria

### 6.1 Measurable Outcomes

- **SC-001**: E2E-P4.7-01 through E2E-P4.7-07 pass in H-XW.
- **SC-002**: Every earlier suite stays green (rule S2).

## 7. Assumptions

- No §6 default is named by this unit's Read or Implements.
- No S9 transitional path is kept alive by this unit. Relays of platform HP actions stay with P4.8 and P4.9. Enrollment removal stays with P3.2. `/control/*` removal stays with P3.10 (rule S9).
