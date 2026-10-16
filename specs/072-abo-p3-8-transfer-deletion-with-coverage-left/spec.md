# Feature Specification: Transfer, deletion with coverage left, and ledger retention

**Feature Branch**: `ai/072-abo-p3-8-transfer-deletion-with-coverage-left`

**Created**: 2026-10-06

**Status**: Draft

**Input**: P3.8 — Transfer, deletion with coverage left, and ledger retention

## 1. Unit Contract

**Implements** — Read: 03 §5.4 (`transferred` rows + "Deletion with coverage left"); 03 §3.2 rows `tenant_binding`, `transfer`/`transfer_step`, `installation`; 03 §4 (ordering-rule paragraph); 04 §1.2 (`transient` details); 04 §1.3 rows beginTransfer, transferOut/In, deleteInstallation; 03 §8 (platform rows); 04 §6.1 rows retention, control/support-purge, control/lifecycle (delete); 05 §2 row AL-18.

- `beginTransfer` (HP: retire the source binding, new binding epoch + 1, new DO `awaiting_transfer`); `transferOut`/`transferIn` (M, idempotent by `transfer_id`) moving the package with `origin_grant_id`; the old DO is `transferred_out` and refuses grants; `deleteInstallation` (HP: no coverage → retire; coverage left → `held_for_transfer`, `transfer_pending` refusals, grants `transient`, no new binding, AL-18 daily); voiding the remaining grants retires the held binding; `voidForReversal` lineage across transfer; retention purge marks installations deleted and never touches ledgers, events, transfers or unended-term usage.

**Freezes** — The unit row states no Outputs / freezes line.

**Consumes** — void, release and listing methods; the tombstone rule.

**Open questions relied on** — None.

**Spikes** — None.

## 2. User Scenarios & Testing

### 2.1 User Story 1 - Move a clinic's coverage to a new installation (Priority: P1)

An operator calls `beginTransfer` on `VendorEntrypoint` (class HP: Access JWT and assertion). The ABO then calls `transferOut` and `transferIn` (class M) with that `transfer_id`. The new installation holds the moved terms. The old installation answers `transferred` and rejects new grants with `transferred_out`. A non-transfer grant during `awaiting_transfer` waits, then applies behind the moved terms. Retrying a step reports `already_applied`. `transferIn` before `transferOut` is `transient`.

**Why this priority**: Deletion can start a transfer from a held binding, and a later void follows the moved term. This is the story those depend on.

**Independent Test**: E2E-P3.8-01, E2E-P3.8-02, and E2E-P3.8-03 in harness H-AP.

**Acceptance Scenarios**:

1. **Given** a clinic with an active term and a queued term, **When** an operator calls `beginTransfer` and the ABO calls `transferOut` then `transferIn`, **Then** the new installation holds the terms with the same `origin_grant_id`s and remaining allowance, the old installation answers `transferred`, the old DO rejects new grants with `transferred_out`, AL-11 is raised for the transfer, and events carry epoch 2. [A14, FR-72] (E2E-P3.8-01)
2. **Given** a new installation whose DO is `awaiting_transfer`, **When** a non-transfer grant arrives, **Then** the result is `transient` with `detail` `awaiting_transfer`. **When** `transferIn` has completed and that grant is applied, **Then** it sits behind the moved terms. (E2E-P3.8-02)
3. **Given** an authorised transfer, **When** `transferOut` or `transferIn` is retried, **Then** the result is `already_applied`. **When** `transferIn` is called before `transferOut`, **Then** the result is `transient`. (E2E-P3.8-03)

### 2.2 User Story 2 - Delete an installation that may still have coverage (Priority: P2)

An operator calls `deleteInstallation` (class HP). With paid time left, the binding is `held_for_transfer`: AI is refused, a paid grant waits, a new token creates no binding, and AL-18 is raised. `beginTransfer` from that held binding then succeeds. With no coverage left, the binding is retired and the next token creates epoch 2. Voiding the remaining grants of a held binding retires it, and the next token creates the next epoch.

**Why this priority**: The held binding uses `beginTransfer` from User Story 1. The clinic-facing refusal is the deletion outcome.

**Independent Test**: E2E-P3.8-04, E2E-P3.8-05, and E2E-P3.8-06 in harness H-AP.

**Acceptance Scenarios**:

1. **Given** an installation with paid time left, **When** an operator calls `deleteInstallation`, **Then** the binding is `held_for_transfer`, an AI request is refused `coverage_lapsed` with `transfer_pending`, a paid grant is `transient` with `transfer_pending`, a new token creates no binding, and AL-18 is raised. **When** the operator calls `beginTransfer` from that held binding, **Then** the call succeeds. [A24, FM-23] (E2E-P3.8-04)
2. **Given** an installation with no coverage left, **When** an operator calls `deleteInstallation`, **Then** the binding is retired. **When** the next token for that org arrives, **Then** it creates epoch 2. (E2E-P3.8-05)
3. **Given** a binding `held_for_transfer` whose remaining grants are then voided, **When** the next token for that org arrives, **Then** the binding has been retired and the token creates epoch + 1. (E2E-P3.8-06)

### 2.3 User Story 3 - Void a paid grant after transfer (Priority: P3)

The ABO calls `voidForReversal` for a paid grant that a transfer has moved. The effect lands on the term now held by the new installation.

**Why this priority**: The void uses the moved term from User Story 1. It does not change the void method's consumed contract.

**Independent Test**: E2E-P3.8-07 in harness H-AP.

**Acceptance Scenarios**:

1. **Given** a paid grant whose term was moved by transfer, **When** the ABO calls `voidForReversal` for that grant, **Then** the effect lands on the new installation's term. (E2E-P3.8-07)

### 2.4 User Story 4 - Keep ledgers when a deleted installation is purged (Priority: P4)

Purging a deleted installation marks the installation deleted and leaves `grant_ledger`, `grant_void`, `coverage_event`, `transfer`, the installation row, and unended-term usage in place.

**Why this priority**: The purge runs against an installation this unit has marked deleted. It is the last story.

**Independent Test**: E2E-P3.8-08 in harness H-AP. Earlier H-AP suites stay green (rule S2).

**Acceptance Scenarios**:

1. **Given** a deleted installation, **When** the installation is purged, **Then** `grant_ledger`, `grant_void`, `coverage_event`, `transfer`, the installation row, and unended-term usage are kept. [RC-05, P-14] (E2E-P3.8-08)

### 2.5 Test plan

| ID | Harness | Entry point | Assertion | Proves | Story |
| --- | --- | --- | --- | --- | --- |
| E2E-P3.8-01 | H-AP | `vendorCall("beginTransfer", …)` then `vendorCall("transferOut", …)` then `vendorCall("transferIn", …)` on `VendorEntrypoint` over the H-AP self service binding (`env.VENDOR` in `ai-platform/test/system/harness.ts`). `beginTransfer` is class HP (`access_jwt`, `assertion`; `org_id`, `from_installation_id`, `reason`). `transferOut` and `transferIn` are class M (`transfer_id`). AL-11 is the captured `send_email` binding. A later grant to the old installation is `vendorCall("grant", …)`. | A14: active + queued clinic → `beginTransfer` → `transferOut` → `transferIn` → the new installation holds the terms with the same `origin_grant_id`s and remaining allowance; old answers `transferred`; the old DO rejects new grants with `transferred_out`; AL-11 transfer; events carry epoch 2. [A14, FR-72] | FR-001, FR-002, FR-003 | User Story 1 |
| E2E-P3.8-02 | H-AP | `vendorCall("grant", …)` for a non-transfer grant while the new DO is `awaiting_transfer`, then again after `vendorCall("transferIn", …)`. | Non-transfer grant during `awaiting_transfer` → `transient` `awaiting_transfer`; after `transferIn` it applies behind the moved terms. | FR-004 | User Story 1 |
| E2E-P3.8-03 | H-AP | `vendorCall("transferOut", …)` and `vendorCall("transferIn", …)` retried with the same `transfer_id`; `vendorCall("transferIn", …)` before `transferOut`. | `transferOut`/`transferIn` retried → `already_applied`; `transferIn` before `transferOut` → `transient`. | FR-002 | User Story 1 |
| E2E-P3.8-04 | H-AP | `vendorCall("deleteInstallation", …)` on `VendorEntrypoint`, class HP (`access_jwt`, `assertion`; `org_id`, `reason`). AI refusal is `SELF.fetch` `POST /v1/requests` (`ai-platform/src/worker.ts`). Paid grant is `vendorCall("grant", …)`. The new token is an issuer token on a clinic `/v1/*` route (`SELF.fetch`), the path that creates a binding. AL-18 is the captured `send_email` binding. `beginTransfer` from the held binding is `vendorCall("beginTransfer", …)`. | A24/FM-23: delete with paid time left → `held_for_transfer`; AI → `coverage_lapsed` `transfer_pending`; paid grant → `transient` `transfer_pending`; a new token creates no binding; AL-18; then `beginTransfer` from the held binding succeeds. [A24, FM-23] | FR-001, FR-005 | User Story 2 |
| E2E-P3.8-05 | H-AP | `vendorCall("deleteInstallation", …)` with no coverage left, then an issuer token on a clinic `/v1/*` route (`SELF.fetch`). | Delete with no coverage → binding retired; the next token creates epoch 2. | FR-005 | User Story 2 |
| E2E-P3.8-06 | H-AP | `vendorCall("voidGrant", …)` on `VendorEntrypoint`, class HP, for the remaining grants of a `held_for_transfer` binding, then an issuer token on a clinic `/v1/*` route (`SELF.fetch`). | Held binding whose remaining grants are voided → retired; the next token → epoch + 1. | FR-006 | User Story 2 |
| E2E-P3.8-07 | H-AP | `vendorCall("voidForReversal", …)` on `VendorEntrypoint`, class M, ABO-signed, for a paid grant moved by transfer. | `voidForReversal` for a paid grant moved by transfer → the effect lands on the new installation's term. | FR-007 | User Story 3 |
| E2E-P3.8-08 | H-AP | `vendorCall("deleteInstallation", …)`, which replaces support-purge (04 §6.1) and reaches `purgeByInstallationId` in `ai-platform/src/retention/index.ts`. | Purge of a deleted installation → `grant_ledger`, `grant_void`, `coverage_event`, `transfer`, installation row and unended-term usage kept. [RC-05, P-14] | FR-008 | User Story 4 |

### 2.6 Edge Cases

- `transfer_out` ends every term that has not ended, with `end_reason` `transferred`. Remaining value (days and allowance of the active term; queued and held terms as they are) goes into the transfer package with each `origin_grant_id`. The DO then rejects new grants with `transferred_out`. (03 §5.4 `transfer_out` row, E2E-P3.8-01)
- A DO created by a transfer starts with `awaiting_transfer` set and answers every non-transfer grant with `transient` and `detail` `awaiting_transfer` until `transferIn` completes, so moved terms keep their place ahead of new purchases. (03 §5.4, 04 §1.2, E2E-P3.8-02)
- `transferOut` and `transferIn` are idempotent by `transfer_id`. A retry is `already_applied` and returns the original receipt. `transferIn` before `transferOut` is `transient` and changes nothing. An authorised `transfer` row must already exist. (04 §1.2, 04 §1.3 rows `transferOut`, `transferIn`, E2E-P3.8-03)
- `deleteInstallation` on an identity that still has an active, grace, queued, or held term does not retire its binding. The binding becomes `held_for_transfer`, the DO sets `transfer_pending`, and AL-18 fires daily while the binding is held. Admission answers `coverage_lapsed` with reason `transfer_pending`. Grants for the org answer `transient` with `detail` `transfer_pending`. No new binding can be created for the org. The calendar keeps running, as for suspension; a complimentary grant can compensate. (03 §5.4 Deletion with coverage left, 04 §1.3 row `deleteInstallation`, 05 §2 row AL-18, E2E-P3.8-04)
- An identity with no coverage left is retired at once. The org's next token or grant creates a new binding with the next epoch. (03 §5.4, 04 §1.3 row `deleteInstallation`, E2E-P3.8-05)
- Voiding the remaining grants (HP) retires the held binding. The org's next token or grant creates a new binding with the next epoch. (03 §5.4, E2E-P3.8-06)
- `voidForReversal` for a paid grant moved by transfer applies its effect on the new installation's term. (Implements, E2E-P3.8-07)
- Purge marks the installation `deleted` and does not delete the installation row. It does not delete `grant_ledger`, `grant_void`, `coverage_event`, `transfer`, DO `term` and `grant` rows, or `usage_event` rows of terms that have not ended. (03 §8 platform rows, 04 §6.1 retention row, E2E-P3.8-08)

## 3. Requirements

### 3.1 Functional Requirements

- **FR-001**: `beginTransfer` is class HP. It takes `access_jwt`, `assertion`, `org_id`, `from_installation_id`, and `reason`. `from_installation_id` is the org's `active` or `held_for_transfer` binding, and the transfer is for that same org only. The output is `transfer_id`. The call is idempotent by assertion challenge. It atomically retires the source binding and creates the org's new active binding with the next epoch. The new DO starts `awaiting_transfer`. The call records the transfer authorisation that `transferOut` and `transferIn` require. (04 §1.3 row `beginTransfer`, 03 §5.4, Implements, E2E-P3.8-01, E2E-P3.8-04)
- **FR-002**: `transferOut` and `transferIn` are class M. Beyond `contract_version` each takes `transfer_id`, and an authorised `transfer` row must exist. The output is the package and a receipt. Each call is idempotent by `transfer_id`. A retry is `already_applied` and returns the original receipt. `receipt` is present when `result` is `applied` or `already_applied`. `transferIn` before `transferOut` is `transient` (`detail` names a state that will clear) and changes nothing. The methods move the package with each term's `origin_grant_id`. The ABO work row that retries them until both report `applied` or `already_applied` is the saga driver and is out of scope. (04 §1.2, 04 §1.3 rows `transferOut`, `transferIn` and the saga sentence, 03 §5.4 `transfer_out` row, E2E-P3.8-01, E2E-P3.8-03)
- **FR-003**: After `beginTransfer`, `transferOut`, and `transferIn` for a clinic that has an active term and a queued term, the new installation holds those terms with the same `origin_grant_id`s and the remaining allowance. `transfer_out` ends each term that has not ended with `end_reason` `transferred`. The package carries the remaining days and allowance of the active term, and queued and held terms as they are. The old installation answers `transferred`. The old DO rejects new grants with `transferred_out`. Events for the new identity carry epoch 2. A re-created identity starts a higher epoch, so its first events win even though its `clinic_seq` restarts at 1. AL-11 is raised for the transfer. (03 §5.4 `transfer_out` row, 03 §4 ordering-rule paragraph, E2E-P3.8-01)
- **FR-004**: A DO created by a transfer starts with `awaiting_transfer` set. Until `transferIn` completes, every non-transfer grant is `transient` with `detail` `awaiting_transfer`, and nothing is changed. After `transferIn`, that grant applies behind the moved terms. `transient` means nothing was changed. (03 §5.4, 04 §1.2, E2E-P3.8-02)
- **FR-005**: `deleteInstallation` is class HP. It takes `access_jwt`, `assertion`, `org_id`, and `reason`, and is idempotent by target state. The installation is marked `deleted`. The installation row is never removed. With no coverage left, its binding is retired and the org's next token or grant creates a new binding with the next epoch; for the E2E clinic that next epoch is 2. With coverage left (an active, grace, queued, or held term), the binding becomes `held_for_transfer`, the DO sets `transfer_pending`, and AL-18 fires daily while the binding is held. Admission answers `coverage_lapsed` with reason `transfer_pending`. Grants for the org, including a paid grant, answer `transient` with `detail` `transfer_pending`. No new binding is created for the org. A partial unique index allows at most one binding per `org_id` that is `active` or `held_for_transfer`. The calendar keeps running, as for suspension; a complimentary grant can compensate. `beginTransfer` from the held binding succeeds. `handleDelete` is this entrypoint method. (04 §1.3 row `deleteInstallation`, 03 §3.2 rows `tenant_binding` and `installation`, 03 §5.4 Deletion with coverage left, 04 §6.1 row `control/lifecycle`, 05 §2 row AL-18, E2E-P3.8-04, E2E-P3.8-05)
- **FR-006**: Voiding the remaining grants of a `held_for_transfer` binding (HP `voidGrant`) retires that binding. The org's next token then creates a new binding with epoch + 1. (03 §5.4, Implements, E2E-P3.8-06)
- **FR-007**: `voidForReversal` for a paid grant that transfer has moved lands its effect on the new installation's term. The call stays the consumed void method. (Implements, E2E-P3.8-07)
- **FR-008**: Purge of a deleted installation marks the installation `deleted` and keeps the installation row. It never touches `grant_ledger`, `grant_void`, `coverage_event`, `transfer`, DO `term` and `grant` rows, or unended-term usage (`usage_event` rows of terms that have not ended). `purgeByInstallationId` stops deleting `entitlement` and `installation`, marks the installation `deleted`, and never touches the grant ledger, coverage events, transfers, or DO storage. Support-purge becomes HP `deleteInstallation` and respects that retention rule. (03 §8 platform rows, 04 §6.1 rows retention and control/support-purge, E2E-P3.8-08)

### 3.2 Key Entities

- **`tenant_binding`**: `org_id`, `installation_id`, `epoch` (1 for the first binding of an org, +1 per re-creation), `status` (`active`, `held_for_transfer`, `retired`), `retired_at`, `reason`. A partial unique index allows at most one binding per `org_id` that is `active` or `held_for_transfer`. `beginTransfer` retires the source binding and inserts the next epoch as `active`. `deleteInstallation` with coverage left sets `held_for_transfer`. `deleteInstallation` with no coverage left, and voiding the remaining grants of a held binding, set `retired`. (03 §3.2 row `tenant_binding`, 03 §5.4, 04 §1.3)
- **`transfer` and `transfer_step`**: New D1 tables for transfer authorisation, the package, and the steps. `beginTransfer` records the authorisation and returns `transfer_id`. `transferOut` and `transferIn` require that authorised row and move the package with each `origin_grant_id`. (03 §3.2 row `transfer`, `transfer_step`, 04 §1.3)
- **`installation`**: The platform clinic identity. `status` already accepts `deleted`. `deleteInstallation` and purge mark the row `deleted`. The row is never removed. (03 §3.2 row `installation`, 03 §8)
- **Term `end_reason` `transferred`**: `transfer_out` ends every term that has not ended. The package holds the remaining value and each `origin_grant_id`. The new DO starts `awaiting_transfer`. While a deleted identity still has coverage, its DO has `transfer_pending`. After transfer-out, the old DO rejects new grants with `transferred_out`. (03 §5.4)

## 4. Constitution Alignment

### 4.1 Architecture & Operations Impact

- **Clinic Fit**: One clinic's remaining coverage moves to a new installation, or is held when the installation is deleted with time left. The ledger of that clinic is kept. The unit adds no second clinic product.
- **Layer Placement**: Codebase is `ai-platform` only. No wiring exception is named. Live entries are `VendorEntrypoint` methods over the H-AP self service binding (`vendorCall` / `env.VENDOR` in `ai-platform/test/system/harness.ts`), `SELF.fetch` `POST /v1/requests` and other clinic `/v1/*` routes (`ai-platform/src/worker.ts`), and `purgeByInstallationId` (`ai-platform/src/retention/index.ts`) reached from `deleteInstallation`. `plan.md` re-runs the constitution check in 02 §7 (rule S12).
- **Data Integrity & Security**: `beginTransfer` and `deleteInstallation` are class HP and take `access_jwt` and `assertion`. `transferOut` and `transferIn` are class M and require an authorised `transfer` row. An org has at most one binding that is `active` or `held_for_transfer`. `grant_ledger`, `grant_void`, `coverage_event`, `transfer`, and the installation row are kept on purge. (04 §1.3, 03 §3.2, 03 §8)
- **Failure Handling**: A non-transfer grant during `awaiting_transfer` is `transient` with `detail` `awaiting_transfer`. `transferIn` before `transferOut` is `transient`. A retried `transferOut` or `transferIn` is `already_applied`. The old DO rejects new grants with `transferred_out`. After delete with coverage left, AI is `coverage_lapsed` with `transfer_pending`, grants are `transient` with `transfer_pending`, and no new binding is created. (E2E-P3.8-01, E2E-P3.8-02, E2E-P3.8-03, E2E-P3.8-04)

## 5. Out of Scope

- The saga driver (→ P4.8); projection epoch handling (→ P5.2).
- No material from outside this unit's Read spans. This unit has no Do not read line.
- No rewrite of void, release and listing methods, or the tombstone rule (rule S7).
- No module that no test-plan row reaches (rule S8).
- No S9 path owned by a later unit. The ABO saga driver stays with P4.8. Projection handling of `(binding_epoch, clinic_seq)` stays with P5.2. Removal of the remaining `/control/*` routes stays with P3.10. This unit does replace support-purge and `handleDelete` with `deleteInstallation` (04 §6.1).
- No second codebase. The Codebase cell is `ai-platform`.

## 6. Success Criteria

### 6.1 Measurable Outcomes

- **SC-001**: E2E-P3.8-01, E2E-P3.8-02, E2E-P3.8-03, E2E-P3.8-04, E2E-P3.8-05, E2E-P3.8-06, E2E-P3.8-07, and E2E-P3.8-08 pass in harness H-AP.
- **SC-002**: Every earlier suite stays green (rule S2).

## 7. Assumptions

- No §6 open question is named by this unit's Read or Implements lines.
- The saga driver stays with P4.8 (rule S9).
- Projection epoch handling stays with P5.2 (rule S9).
- The remaining `/control/*` routes stay until P3.10 (rule S9). Support-purge and `handleDelete` become `deleteInstallation` in this unit (04 §6.1).
