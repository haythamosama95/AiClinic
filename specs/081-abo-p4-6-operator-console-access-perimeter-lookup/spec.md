# Feature Specification: Operator console: Access perimeter, lookup, views and class-H ABO actions

**Feature Branch**: `ai/081-abo-p4-6-operator-console-access-perimeter-lookup`

**Created**: 2026-10-07

**Status**: Draft

**Input**: P4.6 — Operator console: Access perimeter, lookup, views and class-H ABO actions

## 1. Unit Contract

**Implements** — Read: 05 §3.1; 05 §3.2 (rows "Retry parked work", "Cancel an open checkout", and the sentence after the table); 02 §2 row TB-7; 02 §3.1 row K-8; 03 §2.10 row `operator_action`; 04 §7.1 row "ABO console".

- `/ops/*` on the ops host with Access JWT validation in the Worker (package); console pages served by the ABO; lookup by subscription ref, `org_id`, billing email, `CK-`/`PAY-`/`GR-` refs; clinic page (`inspectCoverage` forwarded with the operator's Access JWT; checkouts + events, payments, reversals, grant requests + receipts, operator actions, findings, alerts); global views (parked work, open findings, recent grants by source and credential via `listGrants`, payout imports, key and credential registries); H actions retry-parked and cancel-checkout; `operator_action` with actor email + `access_jti`; version header + reload prompt.

**Freezes** — None. The unit row states no Outputs / freezes line.

**Consumes** — P4.5: None. The unit row states no Outputs / freezes line. P3.6: complimentary and adjustment grant semantics; ceiling policy; `suspend`/`resume`/`inspectCoverage`.

**Open questions relied on** — None.

**Spikes** — None.

## Clarifications

### Session 2026-10-07

- Q: Where should the ops console and the platform wiring live? → A: One module at `abo/src/ops/` serves `/ops/*` (pages, lookup, retry, and cancel) and the ABO worker fetch delegates that prefix to it. `opsFetch` stays in `abo/test/system/harness.ts` and sends Access JWTs the shared-package verifier accepts; the worker does not grow a second checker. The wiring exception adds `recordOperatorAction` only on the existing `VendorEntrypoint` the `PLATFORM` binding already uses. No second worker and no stub. `[implementation choice — no §citation]`
- Q: How should E2E-P4.6-04 park a grant and then show it applied? → A: The harness inserts one parked grant work row in ABO D1 for the clinic under test. Retry goes through `opsFetch` and moves that row to open. The harness then runs the existing grant work-row runner with the real platform `grant` call succeeding, and the grant becomes applied. No new E2E id. `[implementation choice — no §citation]`
- Q: How should lookup keys and global views that have no scenario id of their own be checked? → A: Do not add E2E ids. E2E-P4.6-03 also resolves the same clinic by `org_id`, `CK-`, and `GR-`. E2E-P4.6-02's clinic page shows coverage, checkouts and events, payments, reversals, grant requests and receipts, operator actions, findings, and alerts. That same `/ops/*` session opens parked work, open findings, recent grants by source and by credential via `listGrants`, payout imports, and the key and credential registries. E2E-P4.6-04 retries from the parked-work view. `[implementation choice — no §citation]`
- Q: Where should the frozen method's repeated `action_id` and bad Access JWT be asserted? → A: Keep the existing E2E ids. E2E-P4.6-04 and E2E-P4.6-05 call the real entrypoint again with the same `action_id` and expect no second `control_audit` row. E2E-P4.6-01 also calls `recordOperatorAction` on that entrypoint with no JWT, an expired JWT, and a wrong-`aud` JWT, and expects that call's rejection and no inserted row. No stub. `[implementation choice — no §citation]`
- Q: What does E2E-P4.6-07 observe for the actor email on the `inspectCoverage` relay? → A: The frozen P3.6 call. The ABO forwards the operator's Access JWT as `access_jwt`. That method already verifies the JWT, including its `email` claim, and on success returns `ok` with `detail` JSON `{ terms, grants, reservations }`. The result does not echo the email. The call inserts no `control_audit` row and no other actor-email record. A missing Access JWT stays `rejected` with `unauthenticated` and still writes nothing. `[escalation 3]`

## 2. User Scenarios & Testing

### 2.1 User Story 1 - Open the ops console and look up a clinic (Priority: P1)

An operator opens the console on the ops host. The ABO Worker validates the Access JWT with the package before it serves a console page. Lookup by subscription reference (`AIC-…`), `org_id`, billing email, or a `CK-`, `PAY-`, or `GR-` reference opens one clinic page. That page shows live platform coverage from `inspectCoverage` and the ABO's checkouts and payments. The relay sends the operator's Access JWT as `access_jwt`. The frozen call verifies that JWT, including its `email` claim, and returns terms, grants, and reservations. The result does not echo the email, and the call inserts no `control_audit` row and no other actor-email record.

The clinic page also shows terms, grants, reservations, and suspension from `inspectCoverage`; checkouts with their events; payments with classification and disposition; reversals; grant requests with outcomes and receipts; operator actions on this clinic; and open findings and alerts. Global views list parked work, open findings, recent grants by source and by credential via `listGrants`, payout imports, and key and credential registries.

**Why this priority**: Retry and cancel run from this console, on a clinic this lookup has found. A request that fails the Access JWT check never reaches those pages.

**Independent Test**: E2E-P4.6-01, E2E-P4.6-02, E2E-P4.6-03, and E2E-P4.6-07 in harness H-XW.

**Acceptance Scenarios**:

1. **Given** a request to the ops host with no Access JWT, or with an expired Access JWT, or with an Access JWT whose `aud` is wrong, **When** the ABO Worker validates it, **Then** the request is rejected. The same validation checks the issuer. (E2E-P4.6-01, SR-22, TB-7, K-8)
2. **Given** a valid Access JWT, **When** the operator looks up `AIC-…`, **Then** the clinic page shows platform terms from `inspectCoverage` and the ABO checkouts and payments. The current console contract version is accepted and echoed. (E2E-P4.6-02, FR-70, 05 §3.1, 04 §7.1)
3. **Given** that same clinic, **When** the operator looks it up by billing email and by its `PAY-` reference, **Then** both lookups reach that clinic. (E2E-P4.6-03)
4. **Given** a clinic-page read, **When** the ABO forwards `inspectCoverage`, **Then** the relay carries the operator's Access JWT as `access_jwt`. The frozen call verifies that JWT, including its `email` claim, and returns `ok` with terms, grants, and reservations. The result does not echo the email. The call inserts no `control_audit` row and no other actor-email record. A missing Access JWT is `rejected` with `unauthenticated` and still writes nothing. (E2E-P4.6-07, FR-73)

### 2.2 User Story 2 - Retry parked work and cancel an open checkout (Priority: P2)

An operator retries parked grant work and cancels an open checkout. Both are class H and are verified by the ABO. Retry moves the parked grant to open, and it becomes applied after the cause is fixed. Cancel moves the open checkout to `cancelled`. A later payment on that checkout becomes `paid_late`, and the sweeps continue. Each action writes `operator_action` with the actor email and `access_jti`, and writes `control_audit` on the platform with the Access email as actor.

**Why this priority**: User Story 1 is how the operator reaches the clinic and the parked-work view. These two actions are the class-H ABO actions on that console.

**Independent Test**: E2E-P4.6-04 and E2E-P4.6-05 in harness H-XW.

**Acceptance Scenarios**:

1. **Given** a parked grant, **When** the operator retries it and the cause is then fixed, **Then** the grant goes from parked to open and then to applied, and `operator_action` is recorded with the actor email and `access_jti`. (E2E-P4.6-04, FR-71, FM-05, 05 §3.2 row "Retry parked work")
2. **Given** an open checkout, **When** the operator cancels it, **Then** the checkout is `cancelled`, `operator_action` records the actor email and `access_jti`, and `control_audit` on the platform records the Access email. **Given** a later payment on that checkout, **When** the sweeps run, **Then** the checkout is `paid_late` and the sweeps continue. (E2E-P4.6-05, 05 §3.2 row "Cancel an open checkout", 05 §3.2 sentence after the table)

### 2.3 User Story 3 - Reload the console when the contract version is stale (Priority: P3)

The console sends `Abo-Contract-Version` on `/ops/*`. The current version is accepted and echoed. A stale version is refused with `contract_version_unsupported` before authentication and before any write, and the console asks for a reload.

**Why this priority**: User Stories 1 and 2 are console calls on this same channel. A browser tab left open across a deploy is refused and reloaded instead of being served.

**Independent Test**: E2E-P4.6-06 in harness H-XW. Earlier suites stay green, and E2E-P4.6-01 through E2E-P4.6-05 and E2E-P4.6-07 still pass.

**Acceptance Scenarios**:

1. **Given** a console request whose `Abo-Contract-Version` is stale, or is missing, **When** the ABO handles `/ops/*`, **Then** the response is `contract_version_unsupported`, the check ran before authentication and before any write, and the console shows the reload state. (E2E-P4.6-06, 04 §7.1, 06 §3 V5)

### 2.4 Test plan

| ID | Harness | Entry point | Assertion (+ tags) | Proves | Story |
| --- | --- | --- | --- | --- | --- |
| E2E-P4.6-01 | H-XW | `opsFetch` → `SELF.fetch` on the ABO worker for `OPS_ORIGIN` + `/ops/*` (`abo/test/system/harness.ts`), with no Access JWT, with an expired Access JWT, and with a wrong-`aud` Access JWT | Ops host without, or with an expired or wrong-`aud`, Access JWT → rejected. Issuer is checked in that same validation [SR-22, TB-7] | FR-001 | User Story 1 |
| E2E-P4.6-02 | H-XW | `opsFetch` → `SELF.fetch` on the ABO worker for `OPS_ORIGIN` + `/ops/*`; lookup by `AIC-…`; `VendorEntrypoint.inspectCoverage` over the `PLATFORM` binding | Lookup by `AIC-…` → the clinic page shows platform terms (`inspectCoverage`) and ABO checkouts and payments. Current version 1 is accepted and echoed on the `Abo-Contract-Version` response header and as `contract_version` [FR-70] | FR-002, FR-003, FR-008 | User Story 1 |
| E2E-P4.6-03 | H-XW | `opsFetch` → `SELF.fetch` on the ABO worker for `OPS_ORIGIN` + `/ops/*`; lookup by billing email and by `PAY-` ref | Lookup by billing email and by `PAY-` ref reaches the same clinic | FR-002 | User Story 1 |
| E2E-P4.6-04 | H-XW | `opsFetch` → `SELF.fetch` on the ABO worker for `OPS_ORIGIN` + `/ops/*`; retry parked work; `operator_action` in ABO D1 | Parked grant → retry → open → applied after the cause is fixed; `operator_action` recorded with actor email and `access_jti`; `control_audit` on the platform records the Access email [FR-71, FM-05] | FR-005, FR-007 | User Story 2 |
| E2E-P4.6-05 | H-XW | `opsFetch` → `SELF.fetch` on the ABO worker for `OPS_ORIGIN` + `/ops/*` cancel of an open checkout; a later payment still follows the existing sweeps | Cancel an open checkout → `cancelled`; a later payment → `paid_late` (sweeps continue). `operator_action` records the actor email and `access_jti`; `control_audit` on the platform records the Access email | FR-006, FR-007 | User Story 2 |
| E2E-P4.6-06 | H-XW | `opsFetch` → `SELF.fetch` on the ABO worker for `OPS_ORIGIN` + `/ops/*` with a stale `Abo-Contract-Version`, and with the header missing | Stale `Abo-Contract-Version` from the console → `contract_version_unsupported` → reload state. A missing version gets the same refusal before authentication and before any write | FR-008 | User Story 3 |
| E2E-P4.6-07 | H-XW | `opsFetch` → `SELF.fetch` on the ABO worker for `OPS_ORIGIN` + `/ops/*` relay to `VendorEntrypoint.inspectCoverage` over the `PLATFORM` binding | `inspectCoverage` relay carries the operator's Access JWT as `access_jwt`. The frozen call verifies that JWT, including its `email` claim, and returns `ok` with `{ terms, grants, reservations }`. The result does not echo the email. No `control_audit` row and no other actor-email record is inserted. A missing Access JWT is `rejected` with `unauthenticated` and still writes nothing [FR-73] | FR-003 | User Story 1 |

### 2.5 Edge Cases

- An ops-host `/ops/*` request with no Access JWT, an expired Access JWT, a wrong `aud`, or an issuer that fails validation is rejected. The Access session lifetime is 1 hour. (E2E-P4.6-01, 02 §2 row TB-7, 02 §3.1 row K-8, SR-22)
- A console `/ops/*` request with a stale `Abo-Contract-Version`, or with the header missing, is `contract_version_unsupported`. The check runs before authentication and before any write, so nothing is written. The console asks for a reload. (E2E-P4.6-06, 04 §7.1, 06 §3 V5)
- Cancelling an open checkout sets it to `cancelled`. A later payment becomes `paid_late`. Sweeps continue. (E2E-P4.6-05)
- Retry of a parked grant does not apply it until the cause is fixed. After that fix, the grant is open and then applied, and `operator_action` records the actor email and `access_jti`. (E2E-P4.6-04, FR-71, FM-05)

## 3. Requirements

### 3.1 Functional Requirements

- **FR-001**: `/ops/*` is served on the ops host. The ABO Worker validates the Access JWT with the package before serving a console page. Validation covers issuer, the `aud` tag, and expiry. A request with no Access JWT, an expired Access JWT, or a wrong `aud` is rejected. The Access session lifetime is 1 hour. (Implements, 02 §2 row TB-7, 02 §3.1 row K-8, E2E-P4.6-01, SR-22)
- **FR-002**: The operator finds one clinic page by subscription reference (`AIC-…`), `org_id`, billing email, or a checkout, payment, or grant reference (`CK-`, `PAY-`, `GR-`). Lookup by billing email and by `PAY-` reaches the same clinic as lookup by `AIC-…`. (05 §3.1, Implements, E2E-P4.6-02, E2E-P4.6-03, FR-70)
- **FR-003**: The clinic page shows live coverage from `inspectCoverage`: terms, grants, reservations, and suspension. It shows checkouts with their events, payments with classification and disposition, reversals, grant requests with outcomes and receipts, operator actions on this clinic, and open findings and alerts. The ABO forwards `inspectCoverage` with the operator's Access JWT as `access_jwt`. The frozen method verifies that JWT, including its `email` claim, and returns terms, grants, and reservations. That `email` claim is the actor identity the verification already accepts. The result does not echo the email. The call inserts no `control_audit` row and no other actor-email record. A missing Access JWT is `rejected` with `unauthenticated` and still writes nothing. The page reached by `AIC-…` shows the platform terms and the ABO checkouts and payments. (05 §3.1, Implements, E2E-P4.6-02, E2E-P4.6-07, FR-70, FR-73)
- **FR-004**: Global views list parked work, open findings, recent grants by source and by credential via `listGrants`, payout imports, and key and credential registries. Console pages are served by the ABO. (05 §3.1, Implements)
- **FR-005**: Retry parked work is class H and is verified by the ABO. A parked grant that the operator retries becomes open, and becomes applied after the cause is fixed. (05 §3.2 row "Retry parked work", Implements, E2E-P4.6-04, FR-71, FM-05)
- **FR-006**: Cancel an open checkout is class H and is verified by the ABO. The checkout becomes `cancelled`. A later payment becomes `paid_late`. Sweeps continue. (05 §3.2 row "Cancel an open checkout", Implements, E2E-P4.6-05, FR-71)
- **FR-007**: Every action writes append-only `operator_action` in the ABO and `control_audit` on the platform, with the Access email as actor. `operator_action` records `action_id`, `actor_email`, `access_jti`, `action`, `subject`, `params_sha256`, `assertion_sha256`, and `result`. This unit's actions record the actor email and `access_jti`. (05 §3.2 sentence after the table, 03 §2.10 row `operator_action`, Implements, E2E-P4.6-04, FR-73)
- **FR-008**: The ABO console → ABO `/ops/*` channel sends `Abo-Contract-Version` on the request and on the response, and `contract_version` in every response body, the same as the clinic API. At launch the channel version is 1. The current version is accepted and echoed. A missing version, or a stale version, is HTTP 400 `contract_version_unsupported`. That check runs before authentication and before any write. The console asks for a reload. (04 §7.1 row "ABO console", 06 §3 V5, Implements, E2E-P4.6-02, E2E-P4.6-06)

### 3.2 Key Entities

- **`operator_action`**: Append-only ABO table this unit writes. Fields are `action_id`, `actor_email`, `access_jti`, `action`, `subject`, `params_sha256`, `assertion_sha256`, and `result`. (03 §2.10 row `operator_action`, FR-73)

## 4. Constitution Alignment

### 4.1 Architecture & Operations Impact

- **Clinic Fit**: An operator looks up one clinic and sees that clinic's coverage, checkouts, and payments, then retries parked grant work or cancels an open checkout. The unit adds no second clinic product and no clinic-desktop flow.
- **Layer Placement**: Codebase is `abo`. No wiring exception is named. The live entry is `opsFetch` → `SELF.fetch` on the ABO worker for the ops host `/ops/*`. `inspectCoverage` and `listGrants` are called on the real platform `VendorEntrypoint` over the `PLATFORM` binding. H-XW runs that platform worker from source. `plan.md` re-runs the constitution check in 02 §7 (rule S12).
- **Data Integrity & Security**: `operator_action` is append-only and stores the actor email and `access_jti`. Every action also writes `control_audit` on the platform with the Access email as actor. The Access JWT is validated in the Worker before a console page is served. A missing or stale `Abo-Contract-Version` is refused before authentication and before any write. (03 §2.10, 05 §3.2 sentence after the table, 02 §2 row TB-7, 04 §7.1, 06 §3 V5)
- **Failure Handling**: A missing, expired, or wrong-`aud` Access JWT is rejected (E2E-P4.6-01). A stale or missing console contract version returns `contract_version_unsupported` and the console reloads, with nothing written (E2E-P4.6-06). A cancelled checkout still accepts a later payment as `paid_late` because sweeps continue (E2E-P4.6-05). A parked grant stays unapplied until the cause is fixed, then retry takes it to open and applied (E2E-P4.6-04).

## 5. Out of Scope

- Passkey ceremony and HP actions (→ P4.7–P4.9); findings content (→ P4.10).
- No Do-not-read material. The unit row names none.
- No rewrite of consumed contracts. P3.6's complimentary and adjustment grant semantics, ceiling policy, and `suspend`/`resume`/`inspectCoverage` stay as frozen. This unit calls `inspectCoverage`; it does not change that method, `suspend`, or `resume`. P4.5 states no Outputs / freezes line. `paid_late` after a later payment, and the sweeps that continue, stay as they are.
- No module that no test-plan row reaches (rule S8). Access JWT validation is reached by E2E-P4.6-01. Lookup, the clinic page, and the `inspectCoverage` relay are reached by E2E-P4.6-02, E2E-P4.6-03, and E2E-P4.6-07. Retry parked work and `operator_action` are reached by E2E-P4.6-04. Cancel checkout is reached by E2E-P4.6-05. The version check, the refusal, and the reload prompt are reached by E2E-P4.6-06. Echo of the current version is reached by E2E-P4.6-02. The parked-work global view is the console surface E2E-P4.6-04 retries from. Open findings, recent grants via `listGrants`, payout imports, and key and credential registries are the other global views on that same `/ops/*` console (05 §3.1).
- No S9 path owned by a later unit. Passkey ceremony and HP actions stay with P4.7–P4.9. Findings content stays with P4.10. Enrollment removal stays with P3.2. `/control/*` removal stays with P3.10.
- No second codebase. The Codebase cell is `abo`.

## 6. Success Criteria

### 6.1 Measurable Outcomes

- **SC-001**: E2E-P4.6-01 through E2E-P4.6-07 pass in H-XW.
- **SC-002**: Every earlier suite stays green (rule S2).

## 7. Assumptions

- No §6 default is named by this unit's Read or Implements.
- No S9 transitional path is kept alive by this unit. Passkey ceremony and HP actions stay with P4.7–P4.9. Findings content stays with P4.10. Enrollment removal stays with P3.2. `/control/*` removal stays with P3.10 (rule S9).
