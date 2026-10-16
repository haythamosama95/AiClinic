# Feature Specification: Console relays: complimentary grants, adjustments, voids, suspension, deletion and the transfer saga

**Feature Branch**: `ai/083-abo-p4-8-console-relays-complimentary-grants-adjustments`

**Created**: 2026-10-07

**Status**: Draft

**Input**: P4.8 — Console relays: complimentary grants, adjustments, voids, suspension, deletion and the transfer saga

## 1. Unit Contract

**Implements** — Read: 05 §3.2 (rows suspend/resume, complimentary/adjustment, ceiling override, transfer/release/void, delete) + "Compromise response"; 04 §1.3 rows grant (complimentary), term_adjustment, beginTransfer, transferOut/In, releaseHeld, voidGrant, listGrantsForVoid, suspend, resume, deleteInstallation; 03 §2.8; 03 §7 (`grant_id` comp/transfer forms).

- Console forms and relays (Access JWT + assertion forwarded; the platform verifies) for complimentary grants (`grant_request` with `grant_id` from the operator action id), term adjustments, ceiling override (second assertion), suspend/resume (H), `releaseHeld`, `voidGrant`, `listGrantsForVoid` → void flow, `deleteInstallation`, `beginTransfer` → `transfer_step` work rows driving `transferOut`/`transferIn` until both are applied; transfer grant requests recorded; one `operator_action` per action.

**Freezes** — None. The unit row states no Outputs / freezes line.

**Consumes** — P4.7: None. The unit row states no Outputs / freezes line. P3.8: None. The unit row states no Outputs / freezes line.

**Open questions relied on** — None.

**Spikes** — None.

## Clarifications

### Session 2026-10-07

- Q: Where should these console relays and the transfer saga live? → A: Keep them on the existing `handleOps` path for `OPS_ORIGIN` + `/ops/*` in `abo/src/worker.ts`. Do not add a worker, a hostname, or a second scheduler. `scheduled()` on that worker drives `transfer_step`. Platform calls stay `VendorEntrypoint` methods over the `PLATFORM` binding. `[implementation choice — no §citation]`
- Q: How should one transfer drive `transferOut` and `transferIn`, and when should the transfer `grant_request` rows be written? → A: One `transfer_step` work row per `transfer_id`. Each `scheduled()` run calls `transferOut` until it is `applied` or `already_applied`, then `transferIn`. A `transient` result leaves that row for the next run and does not add a retry schedule. When `transferOut` returns `applied` or `already_applied`, write one `grant_request` per element of the package it stored. 03 §7 already fixes `n` and the row count, including none when the package is empty. A later run does not insert a second row for the same `n`. `[implementation choice — no §citation]`
- Q: How should E2E-P4.8-04 show a retry through `transient` and epoch 2? → A: The fixture binding starts at epoch 1. The saga calls `transferIn` before `transferOut` has applied, observes `transient` with `detail` `awaiting_transfer_out`, and `scheduled()` retries until both are `applied` or `already_applied`. The clinic page on `/ops/clinics/` shows epoch 2. No new E2E id. `[implementation choice — no §citation]`
- Q: How should E2E-P4.8-08 forward an HP relay with no assertion? → A: The test calls an existing HP ops relay through `opsFetch` with the assertion omitted. `handleOps` forwards that call on the `PLATFORM` binding. The platform rejects it. No test-only route and no added refusal code. `[implementation choice — no §citation]`
- Q: How should E2E-P4.8-01 reach both the 14-day extension and a term adjustment? → A: One id. The same `opsFetch` session submits the 14-day extension the scenario asserts and one term adjustment. Assertions stay applied, AL-11, and the `operator_action` / `grant_request` link. `[implementation choice — no §citation]`
- Q: What window does E2E-P4.8-06 send to `listGrantsForVoid`? → A: The inclusive UTC ISO-8601 `applied_from` and `applied_to` that cover the grants under test. This is fixture data, not a product default. `[implementation choice — no §citation]`

## 2. User Scenarios & Testing

### 2.1 User Story 1 - Complimentary grants, adjustments, voids, and suspension (Priority: P1)

An operator uses the console to relay complimentary grants, term adjustments, and a ceiling override. The console forwards the Access JWT and the assertion. The AI Platform verifies them. A complimentary `grant_request` uses `grant_id` from the operator action id. A 14-day extension is applied, AL-11 fires, and `operator_action` and `grant_request` are linked. A 365-day grant is shown as `exceeds_ceiling`; a second passkey override applies it and raises AL-12. A trial grant, then a purchase through the clinic API, queues the paid term after the trial. The same console relays `listGrantsForVoid` and `voidGrant` for the SR-25 drill, and class-H suspend and resume. `releaseHeld` is the same platform-verified HP relay. One `operator_action` is written per action. A compromised ABO that forwards an HP relay with no assertion is rejected by the platform.

**Why this priority**: Deletion and the transfer saga move or hold coverage that these grants create. Void and suspend act on that same clinic.

**Independent Test**: E2E-P4.8-01, E2E-P4.8-02, E2E-P4.8-03, E2E-P4.8-06, E2E-P4.8-07, and E2E-P4.8-08 in harness H-XW.

**Acceptance Scenarios**:

1. **Given** a clinic and an operator at the console, **When** the operator submits a 14-day extension, **Then** it is applied, AL-11 fires, and `operator_action` and `grant_request` are linked. (E2E-P4.8-01, A20, FR-35)
2. **Given** a 365-day grant that the console shows as `exceeds_ceiling`, **When** the operator overrides it with a second passkey, **Then** the grant is applied and AL-12 fires. (E2E-P4.8-02, A27)
3. **Given** a trial grant from the console, **When** the clinic buys through the clinic API, **Then** the paid term queues after the trial. (E2E-P4.8-03, A19, FR-37)
4. **Given** credential Y has revoked credential X, **When** the operator lists X's grants in a window and voids each one, **Then** those terms end `voided`. (E2E-P4.8-06, SR-25)
5. **Given** a clinic, **When** the operator suspends it from the console, **Then** the clinic is refused `suspended`. **When** the operator resumes it, **Then** the clinic is restored. (E2E-P4.8-07, FR-74)
6. **Given** a simulated compromised ABO, **When** it forwards an HP relay without an assertion, **Then** the platform rejects it. (E2E-P4.8-08, TB-6, SR-21)

### 2.2 User Story 2 - Deletion and the transfer saga (Priority: P2)

An operator starts `beginTransfer` from the console. The ABO records the authorisation and drives `transferOut` and `transferIn` with `transfer_step` work rows until both are applied. Steps that answer `transient` are retried. The clinic page shows epoch 2. Transfer grant requests are recorded. Deleting an installation that still has time left holds the binding. A transfer can then start from that held binding. One `operator_action` is written per action.

**Why this priority**: User Story 1 creates the complimentary coverage this saga moves and the held binding this deletion leaves.

**Independent Test**: E2E-P4.8-04 and E2E-P4.8-05 in harness H-XW. Earlier suites stay green, and E2E-P4.8-01, E2E-P4.8-02, E2E-P4.8-03, E2E-P4.8-06, E2E-P4.8-07, and E2E-P4.8-08 still pass.

**Acceptance Scenarios**:

1. **Given** a clinic the operator starts with `beginTransfer`, **When** saga steps are retried through `transient` until both sides are applied, **Then** the clinic page shows epoch 2. (E2E-P4.8-04, A14, FR-72)
2. **Given** an installation with time left, **When** the operator deletes it, **Then** the binding is held. **When** the operator transfers from that held binding, **Then** the transfer runs from the held binding. (E2E-P4.8-05, A24)

### 2.3 Test plan

| ID | Harness | Entry point | Assertion (+ tags) | Proves | Story |
| --- | --- | --- | --- | --- | --- |
| E2E-P4.8-01 | H-XW | `opsFetch` → `SELF.fetch` on the ABO worker for `OPS_ORIGIN` + `/ops/*` (`abo/src/worker.ts` `handleOps`); the relay calls `VendorEntrypoint.grant` over the `PLATFORM` binding (`ai-platform/src/vendor/entrypoint.ts`) | A20 via the console: 14-day extension → applied; AL-11; `operator_action` and `grant_request` linked [FR-35] | FR-001, FR-010, FR-011 | User Story 1 |
| E2E-P4.8-02 | H-XW | `opsFetch` → `SELF.fetch` on the ABO worker for `OPS_ORIGIN` + `/ops/*`; the relay calls `VendorEntrypoint.grant` over the `PLATFORM` binding, first without the override and then with a second assertion | A27: 365-day grant → `exceeds_ceiling` shown; with an override (second passkey) → applied + AL-12 | FR-002, FR-010, FR-011 | User Story 1 |
| E2E-P4.8-03 | H-XW | `opsFetch` → `SELF.fetch` on the ABO worker for `OPS_ORIGIN` + `/ops/*` for the trial grant; then `billingFetch` → `SELF.fetch` `POST /v1/checkouts` on `BILLING_HOST` (`abo/src/worker.ts`) and the existing paid-grant path on the real platform worker | A19: trial grant, then the clinic buys through the clinic API → the paid term queues after the trial [FR-37] | FR-003, FR-010 | User Story 1 |
| E2E-P4.8-04 | H-XW | `opsFetch` → `SELF.fetch` on the ABO worker for `OPS_ORIGIN` + `/ops/*` calling `VendorEntrypoint.beginTransfer`; `scheduled()` on the ABO worker (`abo/src/worker.ts`) retries `transfer_step` through `VendorEntrypoint.transferOut` and `VendorEntrypoint.transferIn`; the clinic page is read on `OPS_ORIGIN` + `/ops/clinics/` | A14: `beginTransfer` → saga steps retried through `transient` until both applied; the clinic page shows epoch 2 [FR-72] | FR-004, FR-005, FR-010, FR-011 | User Story 2 |
| E2E-P4.8-05 | H-XW | `opsFetch` → `SELF.fetch` on the ABO worker for `OPS_ORIGIN` + `/ops/*` calling `VendorEntrypoint.deleteInstallation`, then `beginTransfer` from the held binding and the same `scheduled()` `transfer_step` driver | A24: delete with time left → held; then a transfer from the held binding | FR-006, FR-004, FR-010 | User Story 2 |
| E2E-P4.8-06 | H-XW | `VendorEntrypoint.revokeOperatorCredential` on the real platform worker (`ai-platform/src/vendor/entrypoint.ts`); then `opsFetch` → `SELF.fetch` on the ABO worker for `OPS_ORIGIN` + `/ops/*` calling `listGrantsForVoid` and `voidGrant` | SR-25 drill: credential Y revokes X; list X's grants in a window; void each → terms end `voided` | FR-007, FR-010 | User Story 1 |
| E2E-P4.8-07 | H-XW | `opsFetch` → `SELF.fetch` on the ABO worker for `OPS_ORIGIN` + `/ops/*` calling `VendorEntrypoint.suspend` and `VendorEntrypoint.resume`; the clinic refusal is observed on the real platform worker | Suspend from the console → the clinic is refused `suspended`; resume restores it [FR-74] | FR-008, FR-010 | User Story 1 |
| E2E-P4.8-08 | H-XW | The ABO forwards an HP relay to `VendorEntrypoint` over the `PLATFORM` binding with no assertion | Simulated compromised ABO forwards an HP relay without an assertion → the platform rejects it [TB-6, SR-21] | FR-009 | User Story 1 |

### 2.4 Edge Cases

- A 365-day grant is shown as `exceeds_ceiling`. With a second passkey the override is applied and AL-12 fires. (E2E-P4.8-02, 05 §3.2 row "Ceiling override (second assertion)")
- Suspend from the console refuses the clinic with `suspended`. Resume restores it. (E2E-P4.8-07, FR-74)
- An HP relay forwarded with no assertion is rejected by the platform. Each HP method takes `assertion`. (E2E-P4.8-08, 04 §1.3, TB-6, SR-21)
- `listGrantsForVoid` with a missing window field, a value that is not a UTC ISO-8601 timestamp, or `applied_from` greater than `applied_to` is `rejected` with code `window_invalid` and `detail` empty. An empty array is `ok`. `credential_id` matches `operator_credential_id`, including when that credential is not `active`. (04 §1.3 row `listGrantsForVoid`)
- `transferIn` before `transferOut` has applied is `transient` with `detail` `awaiting_transfer_out` and changes nothing. A retry of the same `transfer_id` is `already_applied` and returns the original receipt. Saga steps are retried through `transient` until both report `applied` or `already_applied`. (E2E-P4.8-04, 04 §1.3 rows `transferOut`, `transferIn`)
- `deleteInstallation` with coverage left sets the binding to `held_for_transfer` and fires AL-18. AI tokens get `coverage_lapsed` (`coverage_reason = transfer_pending`). Grants get `transient` (`detail = transfer_pending`). No new binding is created until `beginTransfer` moves the time, or the remaining grants are voided, which retires the binding. A repeat when the installation is already `deleted` and the binding is already in the status this call left it in is `ok` again, does not create a binding, and does not raise AL-18 again. (E2E-P4.8-05, 04 §1.3 row `deleteInstallation`, A24)
- `beginTransfer` accepts `from_installation_id` only when it is the org's `active` or `held_for_transfer` binding, and only for the same org. The same assertion challenge is `ok` again and does not insert another row or create another binding. (04 §1.3 row `beginTransfer`)

## 3. Requirements

### 3.1 Functional Requirements

- **FR-001**: The console relays a complimentary grant and a term adjustment. The platform verifies them. `grant` with `source.kind` `complimentary` is class HP: the input is the grant envelope, and the call takes `assertion`. The result is a receipt. It is idempotent by `grant_id` plus `envelope_sha256`. `grant` with `kind = term_adjustment` is class HP: the input is the envelope with `adjustment` fields, the result is a receipt, and it is idempotent by `grant_id`. The ABO writes `grant_request` with `source_kind` `complimentary`, `source_ref` the operator action, the canonical envelope, `envelope_sha256`, and `assertion`. `grant_id` is SHA-256 over `"grant:comp:"` ‖ the operator action id. A 14-day extension submitted on the console is applied, AL-11 fires, and `operator_action` and `grant_request` are linked. (Implements, 05 §3.2 row "Complimentary grant; term adjustment", 04 §1.3 rows `grant` and `grant` with `kind = term_adjustment`, 03 §2.8, 03 §7, E2E-P4.8-01, A20, FR-35)
- **FR-002**: A ceiling override is a second assertion, class HP, verified by the AI Platform. A 365-day grant is shown as `exceeds_ceiling`. With the override it is applied and AL-12 fires. (05 §3.2 row "Ceiling override (second assertion)", E2E-P4.8-02, A27)
- **FR-003**: A trial grant from the console, then a purchase through the clinic API, queues the paid term after the trial. (E2E-P4.8-03, A19, FR-37)
- **FR-004**: `beginTransfer` is class HP. The input beyond `contract_version` is `org_id`, `from_installation_id` (the org's `active` or `held_for_transfer` binding), and `reason`. Same org only. Each HP method takes `access_jwt` and `assertion`. Success is `ok`. `detail` is the JSON text of the `transfer` row, which includes `transfer_id`. `code` is empty and `receipt` is absent. The call atomically retires the source binding and creates the org's new active binding with the next epoch. The new DO starts `awaiting_transfer`. The same assertion challenge is `ok` again and does not insert another row or create another binding. It is idempotent by the assertion challenge. (04 §1.3 row `beginTransfer`)
- **FR-005**: A transfer runs as a saga driven by an ABO work row. `beginTransfer` records the authorisation, then `transfer_step` work rows drive `transferOut` and `transferIn` until both report `applied` or `already_applied`. Those two methods are class M. The input is `transfer_id` (an authorised `transfer` row must exist). `applied` stores the package on the `transfer` row and inserts that step's `transfer_step`. `detail` is the JSON text of the package. `receipt` is the transfer receipt. A retry of the same `transfer_id` is `already_applied` and returns the original receipt. `transferIn` before `transferOut` has applied is `transient` with `detail` `awaiting_transfer_out` and changes nothing. They are idempotent by `transfer_id`. Saga steps are retried through `transient` until both are applied. The clinic page shows epoch 2. Transfer `grant_request` rows are recorded with `source_kind` `transfer` and `source_ref` the transfer. `grant_id` is SHA-256 over `"grant:transfer:"` ‖ `transfer_id` ‖ `":"` ‖ n. `assertion` on `grant_request` is for complimentary only. (Implements, 04 §1.3 rows `transferOut`, `transferIn` and the saga sentence, 03 §2.8, 03 §7, E2E-P4.8-04, A14, FR-72)
- **FR-006**: `deleteInstallation` is class HP. The input is `org_id` and `reason`. Success is `ok`. The installation is marked `deleted`. With no coverage left, its binding is retired and the org's next token or grant creates a new binding with the next epoch. With coverage left, the binding becomes `held_for_transfer` and AL-18 fires: AI tokens get `coverage_lapsed` (`coverage_reason = transfer_pending`), grants get `transient` (`detail = transfer_pending`), and no new binding is created until `beginTransfer` moves the time, or the remaining grants are voided, which retires the binding. On `ok`, `detail` is the JSON text of `{installation, tenant_binding}` for those rows after the call, `code` is empty, and `receipt` is absent. `ok` again when the installation is already `deleted` and the binding is already in the status this call left it in; a repeat does not create a binding and does not raise AL-18 again. It is idempotent by target state. Delete with time left holds the binding, and a transfer then runs from that held binding. (04 §1.3 row `deleteInstallation`, Implements, E2E-P4.8-05, A24)
- **FR-007**: The SR-25 drill revokes the suspect credential from another credential, lists that credential's grants in a window, and voids each one. `listGrantsForVoid` is class H. The input is `credential_id` and `window`. `window` is `{applied_from, applied_to}`. Both fields are required UTC ISO-8601 timestamps and are inclusive bounds on `grant_ledger.applied_at`. `applied_from` must be less than or equal to `applied_to`. The span has no maximum. `credential_id` matches `operator_credential_id`, including when that credential is not `active`. Success is `ok`. `detail` is the JSON text of an array of `{grant_id, origin_grant_id, org_id, installation_id, kind, source_kind, operator_credential_id, envelope_sha256, receipt, applied_at}` for rows with that `operator_credential_id` whose `applied_at` is inside the window, in ascending `applied_at` then `grant_id`. Each `receipt` is the receipt object. An empty array is `ok`. A missing window field, a value that is not a UTC ISO-8601 timestamp, or `applied_from` greater than `applied_to` is `rejected` with code `window_invalid` and `detail` empty. On `ok`, `code` is empty and the envelope `receipt` is absent. `voidGrant` is class HP. The input is `grant_id` and `reason`. The result is a receipt. It writes `grant_void` with `source` `operator` and sets `evidence_sha256` to the assertion challenge. It takes no `evidence_sha256` input. It is idempotent by the assertion challenge. Voiding each listed grant ends those terms `voided`. `releaseHeld` is the same platform-verified HP relay on this action row: input `grant_id` and `reason`, result a receipt, it does not write `grant_void`, and it is idempotent by the assertion challenge. (05 §3.2 "Compromise response" and the row "Transfer or re-create identity; release held terms; void a grant", 04 §1.3 rows `listGrantsForVoid`, `voidGrant`, `releaseHeld`, Implements, E2E-P4.8-06, SR-25)
- **FR-008**: Suspend or resume a clinic is class H, verified by the AI Platform. The input is `org_id` and `reason`. The output is a snapshot. It is idempotent by target state. Each H method takes `access_jwt`. Suspend from the console refuses the clinic with `suspended`. Resume restores it. (05 §3.2 row "Suspend or resume a clinic; kill switches; routing", 04 §1.3 row `suspend`, `resume`, E2E-P4.8-07, FR-74)
- **FR-009**: A simulated compromised ABO that forwards an HP relay without an assertion is rejected by the platform. Each HP method takes `assertion`. (E2E-P4.8-08, 04 §1.3, TB-6, SR-21)
- **FR-010**: The console forwards the Access JWT and the assertion. The platform verifies the action. Every action writes one `operator_action` in the ABO with the Access email as actor. When the AI Platform verifies the action, that class-H or class-HP call writes `control_audit` with the Access email as `actor` (and `assertion_sha256` on HP). (Implements, 05 §3.2 paragraph after the action table)
- **FR-011**: `grant_outcome` records the attempt: `grant_id`, `result` (`applied`, `already_applied`, `conflict`, `rejected`), `abo_kid` and `abo_signature` used by the accepted attempt (paid only), the platform-signed `receipt`, `term_ids`, and `at`. (03 §2.8)

### 3.2 Key Entities

- **`grant_request`**: Append-only ABO row for a complimentary or transfer grant. Fields are `grant_id` (03 §7), `org_id`, `source_kind` (`complimentary` or `transfer` for this unit), `source_ref` (operator action or transfer), `envelope` (canonical JSON), `envelope_sha256`, and `assertion` (complimentary only). Complimentary `grant_id` is SHA-256 over `"grant:comp:"` ‖ the operator action id. Transfer `grant_id` is SHA-256 over `"grant:transfer:"` ‖ `transfer_id` ‖ `":"` ‖ n. (03 §2.8, 03 §7, Implements)
- **`grant_outcome`**: Append-only ABO row for the platform result of a grant attempt. Fields are `grant_id`, `result` (`applied`, `already_applied`, `conflict`, `rejected`), `abo_kid` and `abo_signature` used by the accepted attempt (paid only), `receipt`, `term_ids`, and `at`. (03 §2.8)
- **`transfer_step` work row**: The ABO work row that drives `transferOut` and `transferIn` until both are applied. (Implements, 04 §1.3 saga sentence)
- **`operator_action`**: One ABO row per console action, with the Access email as actor. (Implements, 05 §3.2)

## 4. Constitution Alignment

### 4.1 Architecture & Operations Impact

- **Clinic Fit**: An operator grants complimentary coverage, adjusts a term, overrides the ceiling, suspends or resumes a clinic, voids grants, deletes an installation, and transfers the remaining coverage. The unit adds no second clinic product and no clinic-desktop flow.
- **Layer Placement**: Codebase is `abo`. No wiring exception is named. The live entry is `opsFetch` → `SELF.fetch` on the ABO worker for the ops host `/ops/*` (`abo/src/worker.ts`). The transfer saga is also reached by `scheduled()` on that worker. The clinic purchase in E2E-P4.8-03 is the existing `POST /v1/checkouts` on the billing host. Relays call the real platform `VendorEntrypoint` over the `PLATFORM` binding. H-XW runs that platform worker from source. `plan.md` re-runs the constitution check in 02 §7 (rule S12).
- **Data Integrity & Security**: These relays are verified by the AI Platform. The console forwards the Access JWT, and each HP method also forwards `assertion`. Complimentary and transfer grants are append-only `grant_request` and `grant_outcome` rows. `grant_id` is the deterministic comp or transfer form. One `operator_action` is written per action. The platform call writes `control_audit` with the Access email as actor. (05 §3.2, 04 §1.3, 03 §2.8, 03 §7)
- **Failure Handling**: A 365-day grant is shown as `exceeds_ceiling` until a second assertion overrides it (E2E-P4.8-02). Suspend refuses the clinic with `suspended` until resume (E2E-P4.8-07). An HP relay with no assertion is rejected by the platform (E2E-P4.8-08). `transferIn` before `transferOut` is `transient` and the saga retries until both are applied (E2E-P4.8-04). Delete with time left holds the binding (E2E-P4.8-05). A bad `listGrantsForVoid` window is `window_invalid` (04 §1.3).

## 5. Out of Scope

- The unit row states no Out of scope line.
- No Do-not-read material. The unit row names none.
- No rewrite of consumed contracts. P4.7 and P3.8 state no Outputs / freezes line. This unit calls the platform methods named in the Read rows. It does not change those methods.
- No module that no test-plan row reaches (rule S8). Complimentary grant and term adjustment are reached by E2E-P4.8-01. The ceiling override is reached by E2E-P4.8-02. The trial grant and the following clinic purchase are reached by E2E-P4.8-03. `beginTransfer`, `transfer_step`, `transferOut`, and `transferIn` are reached by E2E-P4.8-04. `deleteInstallation` and a transfer from the held binding are reached by E2E-P4.8-05. `listGrantsForVoid` and `voidGrant` are reached by E2E-P4.8-06. `releaseHeld` is the same ops-host HP relay as `voidGrant` on the 05 §3.2 row "Transfer or re-create identity; release held terms; void a grant". Suspend and resume are reached by E2E-P4.8-07. The assertion-less HP forward is reached by E2E-P4.8-08. `operator_action` is reached by every action scenario.
- No S9 path owned by a later unit. Configuration relays, registries, and bootstrap stay with P4.9. Reconciliation and findings stay with P4.10. The daily digest stays with P4.11. `/control/*` removal stays with P3.10.
- No second codebase. The Codebase cell is `abo`.
- Access-session revocation and machine-key rotation, named in the 05 §3.2 compromise-response sentence, are not relays in this unit's Implements line.

## 6. Success Criteria

### 6.1 Measurable Outcomes

- **SC-001**: E2E-P4.8-01 through E2E-P4.8-08 pass in H-XW.
- **SC-002**: Every earlier suite stays green (rule S2).

## 7. Assumptions

- No §6 default is named by this unit's Read or Implements.
- No S9 transitional path is kept alive by this unit. `/control/*` removal stays with P3.10 (rule S9).
