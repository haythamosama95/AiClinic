# Feature Specification: Checkout creation, Paymob intention, coverage view and the cross-worker harness

**Feature Branch**: `ai/077-abo-p4-2-checkout-paymob-intention`

**Created**: 2026-10-06

**Status**: Draft

**Input**: P4.2 — Checkout creation, Paymob intention, coverage view and the cross-worker harness

## 1. Unit Contract

**Implements** — Read: 03 §2.4; 03 §2.11 (row `paymob_intention`); 03 §5.1 (diagram + shown-state table); 04 §2.2 (rows `POST /v1/checkouts`, `GET /v1/checkouts/{id}`, `GET /v1/checkouts?open=1`, Rules); 04 §5.1 (rows capabilities, createCheckout, cancelCheckout); 04 §5.3 (row createCheckout); 03 §2.10 rows `coverage_view`, `feed_cursor` + 03 §4 ordering rule; 05 §6.1 ("Inquiry stub" bullet).

- Provider port + registry (`provider_id`); Paymob adapter `createCheckout` (intention API, piastres, EGP, 1800 s, `special_reference`, notify URL, `return_url` with `v`), `capabilities`, `cancelCheckout` = `unsupported`; `paymob_intention`. R-2 (expiry default) recorded. Import-boundary CI check: only the adapter imports provider code [G6].
- `POST /v1/checkouts`: needs a contact, current terms and the current sellable `offer_version`; snapshot; `opened_with_coverage_through` from a live `getCoverage`, falling back to `coverage_view` (`coverage_source=view`); `starts` = `now` or `after_current` + `projected_start`; provider refusal → `open_failed` + 503; idempotent by `client_request_id`; 10 per tenant per hour; `jti` stored.
- `GET /v1/checkouts/{id}` (Waiting/Abandoned at this stage) and `GET /v1/checkouts?open=1`.
- `coverage_view` + `feed_cursor` via `readCoverageEvents` on the minute cron, using the ordering rule.
- H-PAY stub (intention + auth endpoints) and **H-XW** (real ai-platform as an auxiliary worker bound to `VendorEntrypoint`; build script; CI job).

**Freezes** — checkout API; provider-port interface; H-PAY and H-XW harnesses.

**Consumes** — ABO clinic-API envelope, auth and error rules; records conventions; alert engine; H-ABO. `grant` (paid), `getCoverage`, `listGrants`, `readCoverageEvents`, service-key and plan-version methods; DO schema; event and receipt shapes.

**Open questions relied on** — OQ-3: yes, provisioned at the start of P4.2; if not available, P4.2 and P5.2 stop at their spike step.

**Spikes** — R-2 intention expiry default (rule S6). The Paymob `createCheckout` row sets `expiration` = 1800 s (04 §5.3). E2E-P4.2-01 expects `expires_at` = +30 min. Fallback named for R-2 (05 §10 Spike-dependent items, cited by rule S6): inquiry sweeps. If the Paymob test integration is not available, this unit stops at the spike step (OQ-3).

## Clarifications

### Session 2026-10-06

- Q: How should the G6 import-boundary CI check and E2E-P4.2-09 be built? → A: A script under `abo/`, invoked by the P4.2 import-boundary CI job, fails when any module other than the Paymob adapter imports provider code, or when a domain module imports the adapter. E2E-P4.2-09 runs that script against a fixture tree outside the worker bundle. `[implementation choice — no §citation]`
- Q: How should E2E-P4.2-03 supply the `coverage_view` row the checkout fallback reads? → A: The harness inserts that row in D1, then forces the platform binding to throw on `POST /v1/checkouts`. The minute-cron update of `coverage_view` stays on E2E-P4.2-08. `[implementation choice — no §citation]`

## 2. User Scenarios & Testing

### 2.1 User Story 1 - Open a checkout and a Paymob intention (Priority: P1)

An administrator who already has a billing contact and has accepted the current terms opens a checkout for the current sellable offer version. The ABO stores the offer snapshot, asks the real platform `getCoverage` for the clinic's projected coverage end, and calls the Paymob adapter `createCheckout`. The adapter creates an intention and returns `redirect_url`. The same `client_request_id` returns that checkout again. The eleventh checkout in an hour is refused.

**Why this priority**: Listing, the coverage fallback, and later payment confirmation depend on a checkout that exists. This is the clinic call the other stories use.

**Independent Test**: E2E-P4.2-01, E2E-P4.2-02, E2E-P4.2-03, E2E-P4.2-04, E2E-P4.2-05, and E2E-P4.2-06 in harnesses H-XW and H-PAY.

**Acceptance Scenarios**:

1. **Given** an administrator with a billing contact and the current terms, and the current sellable `offer_version`, **When** the administrator calls `POST /v1/checkouts`, **Then** the response is HTTP 201 with `redirect_url`, a `CK-…` reference, and `expires_at` = +30 min. The Paymob stub received the amount in piastres and `special_reference` equal to that reference. (E2E-P4.2-01, 04 §2.2 row `POST /v1/checkouts`, 04 §5.3 row createCheckout)
2. **Given** a clinic with active coverage on the real platform worker, **When** the administrator opens a checkout, **Then** `starts` is `after_current` and `projected_start` equals `coverage_through`. (E2E-P4.2-02, 04 §2.2 row `POST /v1/checkouts`)
3. **Given** the platform binding throws, **When** the administrator opens a checkout, **Then** the checkout is still created and `coverage_source` is `view`. A `getCoverage` answer of `transient` uses the same fallback. (E2E-P4.2-03, 03 §2.4)
4. **Given** a superseded `offer_version`, **When** the administrator opens a checkout, **Then** the response is HTTP 409 `offer_unavailable` and the body includes the current version. **Given** no billing contact, **Then** the code is `billing_contact_required`. **Given** a stale `terms_version`, **Then** the code is `terms_not_accepted`. (E2E-P4.2-04, 04 §2.2 Rules)
5. **Given** the Paymob stub refuses or times out, **When** the administrator opens a checkout, **Then** the response is HTTP 503 `provider_unavailable`, an `open_failed` event is stored, and the shown state is Abandoned. (E2E-P4.2-05, 03 §5.1 shown-state table)
6. **Given** an open checkout, **When** the same `client_request_id` is posted again, **Then** the same checkout is returned. **When** the tenant posts an 11th checkout in an hour, **Then** the response is HTTP 429 `rate_limited`. (E2E-P4.2-06, 04 §2.2 Rules)

### 2.2 User Story 2 - Read one checkout and list open checkouts (Priority: P2)

An administrator reads a checkout by id and lists the tenant's open checkouts. Another tenant's id is hidden. Two open checkouts for the same tenant are both listed.

**Why this priority**: The desktop resumes a checkout only after User Story 1 has created one.

**Independent Test**: E2E-P4.2-07 in harnesses H-XW and H-PAY.

**Acceptance Scenarios**:

1. **Given** tenant A has a checkout, **When** administrator B requests A's checkout id, **Then** the response is HTTP 404 `not_found`. **Given** tenant A has two open checkouts, **When** A calls `GET /v1/checkouts?open=1`, **Then** both are listed. (E2E-P4.2-07, 04 §2.2 rows `GET /v1/checkouts/{id}` and `GET /v1/checkouts?open=1`, Rules)

### 2.3 User Story 3 - Copy platform coverage onto the minute cron (Priority: P3)

The minute cron calls `readCoverageEvents` on the real platform worker and updates `coverage_view`. `feed_cursor` holds the last `feed_seq` read. An event replaces the stored snapshot only when `(binding_epoch, clinic_seq)` is greater than the stored pair.

**Why this priority**: User Story 1 can seed `coverage_view` for the fallback. This story is the live path that fills that view from platform grant events.

**Independent Test**: E2E-P4.2-08 in harness H-XW.

**Acceptance Scenarios**:

1. **Given** platform grant events, **When** the minute cron runs, **Then** `coverage_view` is updated. An older `(binding_epoch, clinic_seq)` is ignored. (E2E-P4.2-08, 03 §2.10 rows `coverage_view` and `feed_cursor`, 03 §4 ordering rule)

### 2.4 User Story 4 - Fail the import-boundary check on a domain import (Priority: P4)

The import-boundary CI check allows only the adapter module to import provider code. A fixture where a domain module imports adapter code fails the check.

**Why this priority**: The adapter and the checkout routes already exist in the earlier stories. This story checks that boundary and carries the regression line for those stories.

**Independent Test**: E2E-P4.2-09 on the import-boundary CI check. E2E-P4.2-01 through E2E-P4.2-08 still pass.

**Acceptance Scenarios**:

1. **Given** a fixture where a domain module imports adapter code, **When** the import-boundary check runs, **Then** the check fails. (E2E-P4.2-09, Implements G6)

### 2.5 Test plan

| ID | Harness | Entry point | Assertion (+ tags) | Proves | Story |
| --- | --- | --- | --- | --- | --- |
| E2E-P4.2-01 | H-XW + H-PAY | `SELF.fetch` `POST /v1/checkouts` on the ABO worker `fetch`, billing hostname | Admin with contact and terms → 201 with `redirect_url`, `CK-…` reference, `expires_at` = +30 min; the stub received piastres and `special_reference` = reference [FR-11] | FR-001 | User Story 1 |
| E2E-P4.2-02 | H-XW + H-PAY | `SELF.fetch` `POST /v1/checkouts` on the ABO worker `fetch`, billing hostname; real ai-platform auxiliary worker bound as `PLATFORM` with `entrypoint = "VendorEntrypoint"` | A30: clinic with active coverage on the real platform → `starts=after_current`, `projected_start` = `coverage_through` [FR-30, FR-31] | FR-002 | User Story 1 |
| E2E-P4.2-03 | H-XW + H-PAY | `SELF.fetch` `POST /v1/checkouts` on the ABO worker `fetch`, billing hostname; platform binding forced to throw | FM-22: platform binding throws → checkout still created, `coverage_source=view`. `getCoverage` answering `transient` uses the same fallback (03 §2.4) | FR-003 | User Story 1 |
| E2E-P4.2-04 | H-XW + H-PAY | `SELF.fetch` `POST /v1/checkouts` on the ABO worker `fetch`, billing hostname | Superseded `offer_version` → 409 `offer_unavailable` + current version [A8, A21]; no contact → `billing_contact_required`; stale terms → `terms_not_accepted` | FR-004 | User Story 1 |
| E2E-P4.2-05 | H-XW + H-PAY | `SELF.fetch` `POST /v1/checkouts` on the ABO worker `fetch`, billing hostname; H-PAY stub scripted to refuse or time out | FM-09: stub refuses or times out → 503 `provider_unavailable`; `open_failed` event; shown Abandoned | FR-005 | User Story 1 |
| E2E-P4.2-06 | H-XW + H-PAY | `SELF.fetch` `POST /v1/checkouts` on the ABO worker `fetch`, billing hostname | Same `client_request_id` → same checkout; 11th in an hour → 429 | FR-006 | User Story 1 |
| E2E-P4.2-07 | H-XW + H-PAY | `SELF.fetch` `GET /v1/checkouts/{id}` and `GET /v1/checkouts?open=1` on the ABO worker `fetch`, billing hostname | A22: admin B gets A's checkout id → 404; two open A checkouts both listed in `?open=1` [FR-15, SR-04] | FR-007 | User Story 2 |
| E2E-P4.2-08 | H-XW | `runScheduled` on the ABO worker `scheduled` for cron `* * * * *`; real ai-platform auxiliary worker bound as `PLATFORM` with `entrypoint = "VendorEntrypoint"` | After platform grant events, the minute cron updates `coverage_view`; an older `(epoch, seq)` is ignored | FR-008 | User Story 3 |
| E2E-P4.2-09 | import-boundary CI (V7) | Import-boundary CI check | Import-boundary check fails on a fixture where a domain module imports adapter code [G6] | FR-009 | User Story 4 |

### 2.6 Edge Cases

- A superseded `offer_version` returns HTTP 409 `offer_unavailable`, and the body includes the current version. No billing contact returns `billing_contact_required`. A `terms_version` that is not current returns `terms_not_accepted`. (E2E-P4.2-04, 04 §2.2 Rules)
- The Paymob stub refuses or times out: HTTP 503 `provider_unavailable`, an `open_failed` checkout event, shown state Abandoned (`open_failed` with no payment). (E2E-P4.2-05, 03 §5.1)
- The platform binding throws, or `getCoverage` fails or answers `transient`: the checkout is still created, `coverage_source` is `view`, and `opened_with_coverage_through` comes from `coverage_view`. (E2E-P4.2-03, 03 §2.4)
- The same `client_request_id` for one tenant returns the same checkout. The 11th checkout in an hour for that tenant returns HTTP 429 `rate_limited`. (E2E-P4.2-06, 04 §2.2 Rules)
- An id belonging to another tenant returns HTTP 404 `not_found`. Two open checkouts for one tenant are both listed by `GET /v1/checkouts?open=1`. A new checkout leaves an existing open checkout payable. (E2E-P4.2-07, 03 §2.4, 04 §2.2 Rules)
- An event whose `(binding_epoch, clinic_seq)` is not greater than the stored pair leaves `coverage_view` unchanged. (E2E-P4.2-08, 03 §4 ordering rule)
- Paymob `cancelCheckout` returns `unsupported`. (04 §5.1 row cancelCheckout)
- A domain module that imports adapter code fails the import-boundary check. Only the adapter module imports provider code. (E2E-P4.2-09, Implements)
- `expires_at` is 30 minutes after creation on the ABO clock (1800 s). The test clock advances time. A local scenario spends at most 2 seconds of real time. Production and staging wrangler configs carry no test-clock control. (E2E-P4.2-01, 04 §5.3, 06 §3 V4)

## 3. Requirements

### 3.1 Functional Requirements

- **FR-001**: `POST /v1/checkouts` takes `client_request_id`, `offer_id`, `offer_version`, and `terms_version`. With a billing contact, the current terms version, and the current sellable `offer_version`, the ABO creates a checkout and returns HTTP 201 with `checkout_id`, `reference` (`CK-…`), `redirect_url`, `expires_at` (+30 min), and `starts` (`now` or `after_current`, with `projected_start`). The Paymob adapter `createCheckout` calls `POST /v1/intention/` with `Authorization: Token <secret key>`, `amount` in piastres, `currency` EGP, card integration only, one item, `billing_data` from the payer, `special_reference` equal to the checkout `reference`, `expiration` = 1800 s, the notification URL, and `return_url` carrying `v`. It stores `intention_id`, `intention_order_id`, and `client_secret` on `paymob_intention`, and the redirect goes to Unified Checkout with the public key and `client_secret`. The stub receives piastres and `special_reference` equal to the reference. The checkout snapshot stores `plan_id`, `plan_version`, `term_unit`, `term_count`, `allowance_credits`, `grace_days`, `grace_cap_rule`, `list_price_minor`, `charged_price_minor`, `adjustment_id` (null), `currency`, `terms_version`, `billing_contact_version`, and `billing_contact_sha256`. `provider_id` selects the adapter. `initiator` is `payer`. The token's `jti` is stored on the checkout. Responses use the consumed clinic-API envelope. (03 §2.4, 03 §2.11 row `paymob_intention`, 04 §2.2 row `POST /v1/checkouts` and Rules, 04 §5.1 row createCheckout, 04 §5.3 row createCheckout, Implements, E2E-P4.2-01)
- **FR-002**: `starts` comes from a live `getCoverage` on the real platform `VendorEntrypoint`. When the clinic has active coverage, `starts` is `after_current` and `projected_start` equals `coverage_through`. `opened_with_coverage_through` is that projected coverage end. `coverage_source` is `live` on this path. H-XW runs the real ai-platform worker as an auxiliary Miniflare worker, bound as `PLATFORM` with `entrypoint = "VendorEntrypoint"`, built from source before the run. (04 §2.2 row `POST /v1/checkouts`, 03 §2.4, 06 §3 V1 H-XW, E2E-P4.2-02)
- **FR-003**: If `getCoverage` fails, the platform binding throws, or `getCoverage` answers `transient`, the ABO still creates the checkout, reads `opened_with_coverage_through` from `coverage_view`, and records `coverage_source` = `view`. (03 §2.4, E2E-P4.2-03)
- **FR-004**: A checkout requires a billing contact and the current terms version. `offer_version` must be the current sellable version. A superseded `offer_version` returns HTTP 409 `offer_unavailable`, and the body includes the current version. No billing contact returns `billing_contact_required`. A `terms_version` that is not current returns `terms_not_accepted`. (04 §2.2 Rules, E2E-P4.2-04)
- **FR-005**: When the provider refuses or times out during creation, the checkout state is `open_failed`, a `checkout_event` of kind `open_failed` is stored, the response is HTTP 503 `provider_unavailable`, and the shown state is Abandoned. A created checkout whose state is `open` with no attempt is shown as Waiting. `cancelCheckout` returns `unsupported`. `capabilities` returns `{methods, cancel_checkout, refunds, mandates, payouts, pending_notifications}`. The domain sees no provider id; the adapter maps provider references in `paymob_intention`. (03 §5.1 diagram and shown-state table, 04 §5.1 rows capabilities, createCheckout, and cancelCheckout, E2E-P4.2-05)
- **FR-006**: `POST /v1/checkouts` is idempotent by `client_request_id` per tenant: the same id returns the same checkout. The limit is 10 checkouts per tenant per hour. The 11th in that hour returns HTTP 429 `rate_limited` (consumed clinic error rules). The consumed per-token limit of 60 requests stays in force. (04 §2.2 Rules, Implements, E2E-P4.2-06)
- **FR-007**: `GET /v1/checkouts/{id}` returns `reference`, the shown state, an offer summary, `payment_reference`, `term_ref`, and `updated_at`. At this stage the shown state is Waiting or Abandoned. `GET /v1/checkouts?open=1` returns this tenant's open checkouts (and recently paid checkouts when any exist). The tenant is the token's `org` only. An id of another tenant returns HTTP 404 `not_found` (consumed clinic error rules). Two open checkouts for one tenant are both listed. A new checkout leaves an existing open checkout payable. (03 §2.4, 03 §5.1 shown-state table, 04 §2.2 rows and Rules, Implements, E2E-P4.2-07)
- **FR-008**: The minute cron calls `readCoverageEvents` on the real platform worker and updates `coverage_view` (`org_id`, `binding_epoch`, `clinic_seq`, `snapshot`). `feed_cursor` stores the last platform `feed_seq` read. An event replaces the stored snapshot only when `(binding_epoch, clinic_seq)` is greater than the stored pair. An older pair is ignored. A re-created identity starts a higher epoch, so its first events win even though `clinic_seq` restarts at 1. The entry is `runScheduled` for cron `* * * * *`. (03 §2.10 rows `coverage_view` and `feed_cursor`, 03 §4 ordering rule, Implements, E2E-P4.2-08)
- **FR-009**: Only the adapter module imports provider code. The import-boundary CI check fails on a fixture where a domain module imports adapter code. H-PAY is an auxiliary worker at `abo/test/stubs/paymob/`, scripted per test, with the intention endpoint and the auth-token endpoint in this unit. The adapter points at the stub through its base URL setting. The cross-worker CI job runs H-XW. The import-boundary CI job runs the G6 check. (04 §5.1, 05 §6.1 Inquiry stub bullet, 06 §3 V1, 06 §3 V7, Implements, E2E-P4.2-09)

### 3.2 Key Entities

- **`checkout`**: Append-only. `checkout_id`, `reference`, `org_id`, `created_by_sub`, `client_request_id` (unique per org), `offer_id`, `offer_version`, snapshot fields in FR-001, `opened_with_coverage_through`, `coverage_source` (`live`, `view`), `provider_id`, `initiator` (`payer`), `expires_at`. The token `jti` is stored on the checkout fact. (03 §2.4, 04 §2.2 Rules)
- **`checkout_event`**: Append-only. `checkout_id`, `kind` (`opened`, `open_failed`, `attempt_declined`, `attempt_pending`, `paid`, `expired`, `cancelled`, `late_paid`), `source` (`callback`, `inquiry`, `operator`, `system`), `ref`, `actor`, `at`. This unit writes `opened` and `open_failed`. (03 §2.4, 03 §5.1)
- **`checkout_status`**: Mutable. `checkout_id`, `state` (`open` or `open_failed` in this unit), `last_event_at`. (03 §2.4, 03 §5.1)
- **`paymob_intention`**: Adapter table. `checkout_id`, `intention_id`, `order_id`, `client_secret`, `special_reference`, `expires_at`. Only the adapter reads or writes it. (03 §2.11 row `paymob_intention`, 04 §5.3)
- **`coverage_view`**: Mutable. `org_id`, `binding_epoch`, `clinic_seq`, `snapshot`. Applied by the 03 §4 ordering rule. Checkout fallback reads it. (03 §2.10)
- **`feed_cursor`**: Mutable. Last platform `feed_seq` read. (03 §2.10)
- **Provider port**: `capabilities`, `createCheckout`, and `cancelCheckout` (`unsupported` for Paymob), selected by `provider_id`. (04 §5.1)

## 4. Constitution Alignment

### 4.1 Architecture & Operations Impact

- **Clinic Fit**: An administrator of a small-to-mid-size clinic opens a checkout for that clinic's current offer and sees whether the term starts now or after current coverage. The unit adds no second clinic product.
- **Layer Placement**: Codebase is `abo`. No wiring exception is named. Live entries are `SELF.fetch` on the ABO worker `fetch` (billing hostname) and `runScheduled` on the ABO worker `scheduled`. Coverage reads go to the real platform `VendorEntrypoint` (`getCoverage`, `readCoverageEvents`) over H-XW. Paymob is behind the provider port; H-PAY stands in for the intention and auth endpoints. `plan.md` re-runs the constitution check in 02 §7 (rule S12).
- **Data Integrity & Security**: The tenant is the token's `org`. Another tenant's checkout id returns `not_found`. The checkout snapshot is the charged offer. Provider identifiers stay on `paymob_intention`. The token `jti` is stored on the checkout. Append-only checkout facts follow the consumed records conventions. The import-boundary check keeps provider code inside the adapter. (03 §2.4, 03 §2.11, 04 §2.2 Rules, Implements)
- **Failure Handling**: Provider refusal or timeout returns HTTP 503 `provider_unavailable` and records `open_failed` (shown Abandoned). `getCoverage` failure or `transient` still creates the checkout from `coverage_view`. A superseded offer returns HTTP 409 `offer_unavailable`. Missing contact returns `billing_contact_required`. Stale terms return `terms_not_accepted`. The 11th checkout in an hour returns HTTP 429 `rate_limited`. (03 §2.4, 04 §2.2 Rules, E2E-P4.2-03, E2E-P4.2-04, E2E-P4.2-05, E2E-P4.2-06)

## 5. Out of Scope

- Notifications and confirmation (→ P4.3); expiry sweeps (→ P4.5); operator cancel (→ P4.6).
- No Do-not-read material. This unit's row names none. Notification intake, inquiry, HMAC, `paymob_txn`, `paymob_state_seen`, grant, sweeps, and operator cancel stay with their owning units.
- No rewrite of the consumed contracts: ABO clinic-API envelope, auth and error rules, records conventions, alert engine, and H-ABO; platform `grant` (paid), `getCoverage`, `listGrants`, `readCoverageEvents`, service-key and plan-version methods, DO schema, and event and receipt shapes (rule S7).
- No module that no test-plan row reaches (rule S8). `POST /v1/checkouts` and the Paymob `createCheckout` path are reached by E2E-P4.2-01 and E2E-P4.2-05. `GET /v1/checkouts/{id}` and `GET /v1/checkouts?open=1` are reached by E2E-P4.2-07. `coverage_view` refresh is reached by `runScheduled` in E2E-P4.2-08. The import-boundary check is reached by E2E-P4.2-09. `capabilities` and `cancelCheckout` live on the adapter module that `createCheckout` already reaches.
- No S9 path owned by a later unit. Notifications and confirmation stay with P4.3. Expiry sweeps stay with P4.5. Operator cancel stays with P4.6.
- No second codebase. The Codebase cell is `abo`.

## 6. Success Criteria

### 6.1 Measurable Outcomes

- **SC-001**: E2E-P4.2-01, E2E-P4.2-02, E2E-P4.2-03, E2E-P4.2-04, E2E-P4.2-05, E2E-P4.2-06, and E2E-P4.2-07 pass in H-XW + H-PAY. E2E-P4.2-08 passes in H-XW. E2E-P4.2-09 passes on the import-boundary CI check.
- **SC-002**: Every earlier suite stays green (rule S2).

## 7. Assumptions

- OQ-3 default: the Paymob test integration is provisioned at the start of P4.2. If it is not available, P4.2 stops at the R-2 spike step.
- Notifications and confirmation stay with P4.3. Expiry sweeps stay with P4.5. Operator cancel stays with P4.6 (unit Out of scope, rule S9).
