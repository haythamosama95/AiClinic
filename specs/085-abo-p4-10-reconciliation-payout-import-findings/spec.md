# Feature Specification: Reconciliation, payout import and findings

**Feature Branch**: `ai/085-abo-p4-10-reconciliation-payout-import-findings`

**Created**: 2026-10-07

**Status**: Draft

**Input**: P4.10 — Reconciliation, payout import and findings

## 1. Unit Contract

**Implements** — Read: 05 §3.3; 03 §2.10 rows `finding`, `finding_resolution`, `payout_import`, `payout_line`; 04 §5.1 + §5.3 rows payoutLines; 05 §3.2 row "Import a payout CSV; resolve a finding"; 05 §2 row AL-10; 05 §10 row FR-80.

- Reconciliation daily and after each import, with all ten 05 §3.3 checks; `finding` + AL-10 (daily); H resolve-finding; payout CSV import (H; file to R2 + SHA; lines parsed by the adapter; transaction ids mapped via `paymob_txn`); `feed_divergence` compares `coverage_view` with `getCoverage` for clinics with events in the last day. H-PAY payout CSV fixtures.

**Freezes** — None. The unit row states no Outputs / freezes line.

**Consumes** — P4.8: None. The unit row states no Outputs / freezes line.

**Open questions relied on** — None.

**Spikes** — None.

## Clarifications

### Session 2026-10-07

- Q: Where do reconciliation, payout import, and resolve-finding live? → A: Keep one reconciliation function. The daily run is the existing `scheduled()` handler in `abo/src/worker.ts` for cron `0 6 * * *`. The payout-import handler calls that same function before it responds. Import is `POST /ops/payout-imports` and resolve-finding is `POST /ops/findings/{findingId}/resolve`, both on the existing `handleOps` path (`OPS_ORIGIN` + `/ops/*`), with the same `opsFetch` Access session as `POST /ops/payments/{paymentId}/chargeback`. The CSV bytes are the import body. `payoutLines` stays in the Paymob adapter. The raw file is stored in R2, `file_sha256` is the SHA-256 of those bytes, and `r2_key` is that object's key. No second worker, hostname, or cron. `[implementation choice — no §citation]`
- Q: How is resolve-finding reached when this unit adds no E2E id? → A: In E2E-P4.10-02, after `grant_without_payment` and AL-10 are asserted, the same `opsFetch` session resolves that finding. Assert one `finding_resolution` row for that `finding_id`. Do not assert that AL-10 stops or that a later reconciliation is clean. No new E2E id. `[implementation choice — no §citation]`
- Q: How does E2E-P4.10-09 make the stored receipt differ? → A: Leave the platform `listGrants` receipt unchanged. Change the `signature` on the ABO `grant_outcome.receipt` for one row whose `result` is `applied` or `already_applied`. Assert `receipt_mismatch` and AL-10. Do not tamper a void receipt or a transfer receipt. A missing `listGrants` row is the same check and does not get a new E2E id. `[implementation choice — no §citation]`
- Q: How are the H-PAY payout CSVs built? → A: One committed fixture file per import scenario under `abo/test/fixtures/paymob/`. The Paymob adapter owns the column mapping; the fixtures use that mapping and it is not frozen. E2E-P4.10-05 includes a chargeback line whose transaction id resolves through `paymob_txn`. E2E-P4.10-06 includes a payment line whose amount differs from the payment, and omits a payment settled more than 7 days before the end of that file's month. Assertions stay the finding kinds and `payout_line` fields. `[implementation choice — no §citation]`

## 2. User Scenarios & Testing

### 2.1 User Story 1 - Daily reconciliation and findings (Priority: P1)

The daily reconciliation runs the ten 05 §3.3 checks. Each failed check writes a `finding` and raises AL-10. AL-10 repeats daily while the finding stands. For clinics with events in the last day, `feed_divergence` compares `coverage_view` with `getCoverage`. A stored receipt that differs from `listGrants` writes a finding. A clean month of payments, grants, complimentary grants, and a transfer writes zero findings.

**Why this priority**: Payout import re-runs this same reconciliation. The finding kinds and AL-10 exist before an operator imports a file.

**Independent Test**: E2E-P4.10-01, E2E-P4.10-02, E2E-P4.10-03, E2E-P4.10-04, E2E-P4.10-07, E2E-P4.10-08, and E2E-P4.10-09 in harness H-XW.

**Acceptance Scenarios**:

1. **Given** a clean month of payments, grants, complimentary grants, and a transfer, **When** reconciliation runs, **Then** there are zero findings. (E2E-P4.10-01, FR-81)
2. **Given** a paid grant applied on the platform with the testkit ABO key and no ABO payment, **When** reconciliation runs, **Then** the finding kind is `grant_without_payment` and AL-10 is raised. (E2E-P4.10-02, AD-8)
3. **Given** a complimentary platform grant with no ABO `operator_action`, **When** reconciliation runs, **Then** the finding kind is `grant_without_operator_action`. **Given** a transfer without an ABO `operator_action`, **When** reconciliation runs, **Then** the finding kind is `transfer_without_authorisation`. (E2E-P4.10-03)
4. **Given** a grant parked more than 15 minutes, **When** reconciliation runs, **Then** the finding kind is `payment_without_grant`. (E2E-P4.10-04)
5. **Given** an HMAC-valid success callback that was never confirmed by an inquiry, **When** reconciliation runs, **Then** the finding kind is `callback_without_confirmation`. (E2E-P4.10-07)
6. **Given** a tampered `coverage_view`, **When** reconciliation runs, **Then** the finding kind is `feed_divergence`. **Given** a full reversal without a void receipt, **When** reconciliation runs, **Then** the finding kind is `reversal_not_applied`. (E2E-P4.10-08)
7. **Given** a stored receipt that differs from `listGrants`, **When** reconciliation runs, **Then** a finding is written. (E2E-P4.10-09, AD-15)

### 2.2 User Story 2 - Payout import and resolve-finding (Priority: P2)

An operator imports a Paymob dashboard payout CSV. The action is class H, verified by the ABO. The file is stored in R2 with its SHA. The Paymob adapter `payoutLines` parses the file into lines, and transaction ids are mapped through `paymob_txn`. Reconciliation runs again after the import. Resolve a finding is the other class-H action on that same console row. H-PAY supplies the payout CSV fixtures.

**Why this priority**: User Story 1 defines the checks. This story is how a monthly payout file and a resolved finding enter that run.

**Independent Test**: E2E-P4.10-05 and E2E-P4.10-06 in harness H-XW + H-PAY. Earlier suites stay green, and E2E-P4.10-01, E2E-P4.10-02, E2E-P4.10-03, E2E-P4.10-04, E2E-P4.10-07, E2E-P4.10-08, and E2E-P4.10-09 still pass.

**Acceptance Scenarios**:

1. **Given** a payout CSV with an unrecorded chargeback, **When** the operator imports it and reconciliation runs, **Then** the finding kind is `unrecorded_reversal`. **Given** the manual chargeback for that payment, **When** it is recorded, **Then** access ends. **When** reconciliation runs again, **Then** the re-run is clean. (E2E-P4.10-05, A18)
2. **Given** a payout payment line whose amount does not match the payment, **When** reconciliation runs after the import, **Then** the finding kind is `payout_unmatched`. **Given** a payment settled more than 7 days before the end of an imported period and missing from that file, **When** reconciliation runs after the import, **Then** the finding kind is `payment_not_in_payout`. (E2E-P4.10-06)

### 2.3 Test plan

| ID | Harness | Entry point | Assertion (+ tags) | Proves | Story |
| --- | --- | --- | --- | --- | --- |
| E2E-P4.10-01 | H-XW | `runScheduled("0 6 * * *")` → `scheduled()` on the ABO worker (`abo/src/worker.ts`); grant and transfer facts are read through `VendorEntrypoint.listGrants` over the `PLATFORM` binding (`ai-platform/src/vendor/entrypoint.ts`) | A clean month (payments, grants, complimentary grants, a transfer) → zero findings [FR-81] | FR-001, FR-014 | User Story 1 |
| E2E-P4.10-02 | H-XW | A paid grant is applied on the real platform worker with the testkit ABO key and no ABO payment; `runScheduled("0 6 * * *")` → `scheduled()` calls `VendorEntrypoint.listGrants`; AL-10 is observed by capturing `send_email` (rule V6) | AD-8: paid grant applied on the platform with the testkit ABO key and no ABO payment → `grant_without_payment` + AL-10 | FR-002, FR-004 | User Story 1 |
| E2E-P4.10-03 | H-XW | `runScheduled("0 6 * * *")` → `scheduled()` calls `VendorEntrypoint.listGrants` over the `PLATFORM` binding and compares complimentary grants and transfer grants with ABO `operator_action` rows | Complimentary platform grant with no ABO `operator_action` → `grant_without_operator_action`; transfer without one → `transfer_without_authorisation` | FR-005, FR-006 | User Story 1 |
| E2E-P4.10-04 | H-XW | The H-XW test clock advances more than 15 minutes (rule V4), then `runScheduled("0 6 * * *")` → `scheduled()` | Grant parked > 15 min → `payment_without_grant` | FR-003 | User Story 1 |
| E2E-P4.10-05 | H-XW + H-PAY | `opsFetch` → `SELF.fetch` on the ABO worker for `OPS_ORIGIN` + `/ops/*` (`abo/src/worker.ts` `handleOps`) imports the H-PAY payout CSV fixture (`abo/test/fixtures/paymob/`); `payoutLines` maps transaction ids through `paymob_txn`; reconciliation runs after the import; `opsFetch` `POST /ops/payments/{paymentId}/chargeback` records the manual chargeback; `runScheduled("0 6 * * *")` re-runs reconciliation | A18: payout CSV with an unrecorded chargeback → `unrecorded_reversal`; manual chargeback (P4.7) → access ends; re-run clean | FR-001, FR-010, FR-015 | User Story 2 |
| E2E-P4.10-06 | H-XW + H-PAY | `opsFetch` → `SELF.fetch` on the ABO worker for `OPS_ORIGIN` + `/ops/*` imports the H-PAY payout CSV fixture; `payoutLines` parses lines; reconciliation runs after the import | Amount mismatch → `payout_unmatched`; a missing settled payment → `payment_not_in_payout` | FR-008, FR-009, FR-015 | User Story 2 |
| E2E-P4.10-07 | H-XW | `runScheduled("0 6 * * *")` → `scheduled()` | HMAC-valid success never confirmed → `callback_without_confirmation` | FR-011 | User Story 1 |
| E2E-P4.10-08 | H-XW | `runScheduled("0 6 * * *")` → `scheduled()` compares `coverage_view` with `VendorEntrypoint.getCoverage` over the `PLATFORM` binding for clinics with events in the last day, and checks full reversals for a void receipt or tombstone | Tampered `coverage_view` → `feed_divergence`; full reversal without a void receipt → `reversal_not_applied` | FR-007, FR-012 | User Story 1 |
| E2E-P4.10-09 | H-XW | `runScheduled("0 6 * * *")` → `scheduled()` calls `VendorEntrypoint.listGrants` over the `PLATFORM` binding and compares the stored receipt | AD-15: stored receipt that differs from `listGrants` → finding | FR-013 | User Story 1 |

### 2.4 Edge Cases

- A paid grant applied on the platform with the testkit ABO key and no ABO payment writes `grant_without_payment` and raises AL-10. (E2E-P4.10-02, 05 §3.3, 05 §2 row AL-10, AD-8)
- A complimentary platform grant with no ABO `operator_action` writes `grant_without_operator_action`. A transfer grant with no HP `beginTransfer` `operator_action` and no `transferOut` package writes `transfer_without_authorisation`. (E2E-P4.10-03, 05 §3.3)
- A payment with disposition `grant` and no `applied` outcome within 15 minutes writes `payment_without_grant`. The scenario is a grant parked more than 15 minutes. (E2E-P4.10-04, 05 §3.3)
- A payout payment line that does not match a payment by `payment_id` and amount writes `payout_unmatched`. A payment settled more than 7 days before the end of an imported period and absent from that period writes `payment_not_in_payout`. (E2E-P4.10-06, 05 §3.3)
- A payout refund or chargeback line with no recorded reversal writes `unrecorded_reversal`. After the manual chargeback, access ends and the re-run is clean. (E2E-P4.10-05, 05 §3.3, A18)
- An HMAC-valid success callback that was not confirmed by an inquiry writes `callback_without_confirmation`. (E2E-P4.10-07, 05 §3.3)
- A tampered `coverage_view` for a clinic with events in the last day writes `feed_divergence`. A full reversal with no void receipt or tombstone writes `reversal_not_applied`, unless its effect is `none`. (E2E-P4.10-08, 05 §3.3)
- A stored receipt that differs from `listGrants` writes a finding. (E2E-P4.10-09, AD-15)
- A payout line that does not match a payment stores `payment_id` null. (03 §2.10 row `payout_line`)

## 3. Requirements

### 3.1 Functional Requirements

- **FR-001**: Reconciliation runs daily, and again after each payout import. (05 §3.3, FR-80, FR-81)
- **FR-002**: Each failed check writes a `finding` and raises AL-10. AL-10 is the reconciliation finding, raised by the ABO, repeated daily, for FR-81. (05 §3.3, 05 §2 row AL-10)
- **FR-003**: Every payment with disposition `grant` has an `applied` outcome within 15 minutes. Failure writes `payment_without_grant`. A grant parked more than 15 minutes writes that kind. (05 §3.3, E2E-P4.10-04)
- **FR-004**: Every paid platform grant (`listGrants`) has `grant_id = H(payment_id)` of an ABO payment. Failure writes `grant_without_payment`. A paid grant applied on the platform with the testkit ABO key and no ABO payment writes that kind and raises AL-10. (05 §3.3, E2E-P4.10-02, AD-8)
- **FR-005**: Every complimentary platform grant matches an ABO `operator_action`. Failure writes `grant_without_operator_action`. (05 §3.3, E2E-P4.10-03)
- **FR-006**: Every transfer grant matches an HP `beginTransfer` `operator_action` and the `transferOut` package it came from. Failure writes `transfer_without_authorisation`. (05 §3.3, E2E-P4.10-03)
- **FR-007**: Every full reversal of a payment has a void receipt or tombstone, unless its effect is `none`. Failure writes `reversal_not_applied`. A full reversal without a void receipt writes that kind. (05 §3.3, E2E-P4.10-08)
- **FR-008**: Every payout payment line matches a payment by `payment_id` and amount. Failure writes `payout_unmatched`. An amount mismatch writes that kind. (05 §3.3, E2E-P4.10-06)
- **FR-009**: Every payment settled more than 7 days before the end of an imported period appears in it. Failure writes `payment_not_in_payout`. A missing settled payment writes that kind. (05 §3.3, E2E-P4.10-06)
- **FR-010**: Every payout refund or chargeback line has a recorded reversal. Failure writes `unrecorded_reversal` (A18). A payout CSV with an unrecorded chargeback writes that kind. A manual chargeback then ends access, and the re-run is clean. (05 §3.3, E2E-P4.10-05, A18)
- **FR-011**: Every HMAC-valid success callback was confirmed by an inquiry. Failure writes `callback_without_confirmation`. (05 §3.3, E2E-P4.10-07)
- **FR-012**: For clinics with events in the last day, the feed snapshot equals `getCoverage`. Failure writes `feed_divergence`. The comparison is `coverage_view` with `getCoverage`. A tampered `coverage_view` writes that kind. (05 §3.3, Implements, E2E-P4.10-08)
- **FR-013**: A stored receipt that differs from `listGrants` writes a finding. (E2E-P4.10-09, AD-15)
- **FR-014**: A clean month of payments, grants, complimentary grants, and a transfer produces zero findings. (E2E-P4.10-01, FR-81)
- **FR-015**: Import a payout CSV is class H, verified by the ABO, for FR-80. Paymob offers no payout API. The operator imports the dashboard CSV each month. It is one routine action. The file goes to R2 with its SHA. `payoutLines` takes the uploaded report file and returns `PayoutLine[]`. The Paymob adapter maps one month per file onto `PayoutLine`, and transaction ids are looked up in `paymob_txn`. The import row stores `import_id`, `provider_id`, `file_sha256`, `r2_key`, `imported_by`, and `period`. Each line stores `import_id`, `line_no`, `kind` (`payment`, `refund`, `chargeback`, `fee`, `other`), `gross_minor`, `fee_minor`, `net_minor`, `settled_at`, and `payment_id` (null if unmatched). H-PAY payout CSV fixtures live under `abo/test/fixtures/paymob/`. (05 §3.2 row "Import a payout CSV; resolve a finding", 05 §10 row FR-80, 04 §5.1 row `payoutLines`, 04 §5.3 row `payoutLines`, 03 §2.10 rows `payout_import` and `payout_line`, Implements, rule V1 harness H-PAY)
- **FR-016**: Resolve a finding is class H, verified by the ABO, on the same action row as the payout import. A resolution appends `finding_resolution` with `finding_id`, `resolved_by`, `note`, and `at`. (05 §3.2 row "Import a payout CSV; resolve a finding", 03 §2.10 row `finding_resolution`, Implements)

### 3.2 Key Entities

- **`finding`**: Append-only ABO row. Fields are `finding_id`, `kind` (05 §3), `subject`, `detail`, and `detected_at`. (03 §2.10)
- **`finding_resolution`**: Append-only ABO row. Fields are `finding_id`, `resolved_by`, `note`, and `at`. (03 §2.10)
- **`payout_import`**: Append-only ABO row. Fields are `import_id`, `provider_id`, `file_sha256`, `r2_key`, `imported_by`, and `period`. (03 §2.10)
- **`payout_line`**: Append-only ABO row. Fields are `import_id`, `line_no`, `kind` (`payment`, `refund`, `chargeback`, `fee`, `other`), `gross_minor`, `fee_minor`, `net_minor`, `settled_at`, and `payment_id` (null if unmatched). (03 §2.10)
- **`PayoutLine`**: Adapter output of `payoutLines` for one uploaded report file. The Paymob adapter maps a one-month dashboard CSV onto these lines and looks up transaction ids in `paymob_txn`. (04 §5.1 row `payoutLines`, 04 §5.3 row `payoutLines`)

## 4. Constitution Alignment

### 4.1 Architecture & Operations Impact

- **Clinic Fit**: An operator imports one monthly payout file and resolves a reconciliation finding. The daily run checks that clinic payments, grants, transfers, reversals, and the coverage feed still match. The unit adds no second clinic product and no clinic-desktop flow.
- **Layer Placement**: Codebase is `abo`. No wiring exception is named. The daily run is `scheduled()` on the ABO worker for cron `0 6 * * *` (`abo/src/worker.ts`). Import and resolve-finding are class-H actions on `opsFetch` → `SELF.fetch` for the ops host `/ops/*` (`handleOps`). Platform reads go through `VendorEntrypoint.listGrants` and `VendorEntrypoint.getCoverage` over the `PLATFORM` binding. H-XW runs that platform worker from source. H-PAY payout CSV fixtures are under `abo/test/fixtures/paymob/`. `plan.md` re-runs the constitution check in 02 §7 (rule S12).
- **Data Integrity & Security**: `finding`, `finding_resolution`, `payout_import`, and `payout_line` are append-only. The CSV is stored in R2 and recorded by `file_sha256`. Import and resolve-finding are class H, verified by the ABO. Paid-grant comparison uses `grant_id = H(payment_id)`. Transaction ids are mapped through `paymob_txn`. (03 §2.10, 05 §3.2 row "Import a payout CSV; resolve a finding", 05 §3.3, 04 §5.3 row `payoutLines`)
- **Failure Handling**: Each failed check writes a `finding` and raises AL-10, repeated daily. (05 §3.3, 05 §2 row AL-10) A full reversal whose effect is `none` does not write `reversal_not_applied`. (05 §3.3) An unrecorded payout chargeback writes `unrecorded_reversal`; after the manual chargeback, access ends and the re-run is clean. (E2E-P4.10-05) A tampered `coverage_view` writes `feed_divergence`. (E2E-P4.10-08) A grant parked more than 15 minutes writes `payment_without_grant`. (E2E-P4.10-04)

## 5. Out of Scope

- The unit row states no Out of scope line.
- No Do-not-read material. The unit row names none.
- No rewrite of consumed contracts. P4.8 states no Outputs / freezes line. This unit calls `listGrants` and `getCoverage` and reads `paymob_txn`. It does not change those contracts.
- No module that no test-plan row reaches (rule S8). The ten daily checks, `finding`, and AL-10 are reached by E2E-P4.10-01 through E2E-P4.10-04 and E2E-P4.10-07 through E2E-P4.10-09. `feed_divergence` is reached by E2E-P4.10-08. The receipt comparison with `listGrants` is reached by E2E-P4.10-09. Payout CSV import, `payoutLines`, `payout_import`, `payout_line`, the `paymob_txn` lookup, and the H-PAY payout CSV fixtures are reached by E2E-P4.10-05 and E2E-P4.10-06. Reconciliation after import is reached by those two rows. Resolve-finding is the class-H action on the same 05 §3.2 row as the import. The unit lists no E2E id for it, and this spec adds none.
- No S9 path owned by a later unit. The daily digest, platform watch, housekeeping, and ABO rebuild stay with P4.11.
- No second codebase. The Codebase cell is `abo`.
- The manual chargeback action stays with P4.7. E2E-P4.10-05 calls the existing `POST /ops/payments/{paymentId}/chargeback`.
- A Paymob payout API stays out. FR-80 closes through the CSV import on `payoutLines`. (05 §10 row FR-80)

## 6. Success Criteria

### 6.1 Measurable Outcomes

- **SC-001**: E2E-P4.10-01 through E2E-P4.10-09 pass in the harness named on each test-plan row.
- **SC-002**: Every earlier suite stays green (rule S2).

## 7. Assumptions

- No §6 default is named by this unit's Read or Implements.
- No S9 transitional path is named by this unit.
