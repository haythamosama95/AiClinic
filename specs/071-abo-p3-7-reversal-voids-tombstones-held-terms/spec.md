# Feature Specification: Reversal voids, tombstones, held terms and operator voids

**Feature Branch**: `ai/071-abo-p3-7-reversal-voids-tombstones-held-terms`

**Created**: 2026-10-06

**Status**: Draft

**Input**: P3.7 — Reversal voids, tombstones, held terms and operator voids

## 1. Unit Contract

**Implements** — Read: 03 §5.5; 03 §5.4 (rows: full reversal of the active/grace term, queued/held reversal, held release, grant voided); 03 §5.7 (`reversed`); 03 §3.2 rows `grant_void`, `grant_ledger`; 03 §3.3 void object; 04 §1.3 rows voidForReversal, releaseHeld, voidGrant, listGrantsForVoid; 04 §1.4 step 5 (`voided`); 05 §3.2 ("Compromise response" paragraph).

- `voidForReversal` (M, ABO-signed, idempotent by `reversal_id`) resolving the live term through `origin_grant_id`; effects `end_current` (no grace; queued → held), `remove_queued`, `none`; tombstone when the grant is not yet applied, so a later grant is `rejected voided`; partial voids rejected; `voidGrant` (HP); `releaseHeld` (HP; re-appended at the end); `listGrantsForVoid` (H; credential + window); `grant_void` in D1 and R2; `held_count`.

**Freezes** — void, release and listing methods; the tombstone rule.

**Consumes** — complimentary and adjustment grant semantics; ceiling policy; `suspend`/`resume`/`inspectCoverage`.

**Open questions relied on** — None.

**Spikes** — None.

## 2. User Scenarios & Testing

### 2.1 User Story 1 - Void a paid term for a reversal (Priority: P1)

The ABO calls `voidForReversal` on `VendorEntrypoint`, signed with the ABO key and idempotent by `reversal_id`. The call takes a required boolean `partial`. When `partial` is false, the platform resolves the live term through `origin_grant_id` and applies `end_current`, `remove_queued`, or `none`. A void that arrives before the grant is a tombstone. A later grant with that id is `rejected` with `voided`. After a void is stored, the same `reversal_id` with the same `grant_id`, `reason`, `evidence_sha256`, and `partial` false is `already_applied`; any difference in those four is `conflict`. A bad ABO signature is rejected. `partial` true is `rejected` with code `partial_void` and writes nothing. A missing or non-boolean `partial` is `rejected` with code `partial_invalid` and writes nothing. A rejected call does not consume `reversal_id`. An applied void (`partial` false) is stored as `grant_void` in D1 and as the R2 object `grant-ledger/<grant_id>.void.ndjson`. When that grant already has a `grant_ledger` row, coverage events are emitted and the receipt's `installation_id` and `org_id` are that row's ids. A tombstone, a `partial` false void before any `grant_ledger` row for that `grant_id`, returns a receipt whose `installation_id` and `org_id` are both the nil UUID `00000000-0000-0000-0000-000000000000`, whose `ledger_seq` is 0, and whose `term_ids` is empty, and that call emits no coverage event. After `end_current`, a clinic request is refused `coverage_lapsed` with reason `reversed`.

**Why this priority**: `releaseHeld` acts on terms this story holds. The tombstone rule is what a later grant consults.

**Independent Test**: E2E-P3.7-01, E2E-P3.7-02, E2E-P3.7-03, E2E-P3.7-04, E2E-P3.7-08, and E2E-P3.7-09 in harness H-AP.

**Acceptance Scenarios**:

1. **Given** an active term funded by a payment and a queued term T2, **When** `voidForReversal` voids the payment funding the active term, **Then** T1 ends `reversed`, T2 is held, and a clinic request is refused `coverage_lapsed` with reason `reversed`. [A15] (E2E-P3.7-01)
2. **Given** an active term and a queued term funded by another payment, **When** `voidForReversal` voids the queued term's payment, **Then** that term is removed and the active term is unaffected. (E2E-P3.7-02)
3. **Given** an ended term, **When** `voidForReversal` voids that term's payment, **Then** the void is recorded only. [A17] (E2E-P3.7-03)
4. **Given** a paid `grant_id` that is not yet applied, **When** `voidForReversal` voids it, **Then** a tombstone is stored, the receipt's `installation_id` and `org_id` are both the nil UUID `00000000-0000-0000-0000-000000000000`, `ledger_seq` is 0, `term_ids` is empty, and no coverage event is emitted. **When** a later grant with that id arrives, **Then** the grant is `rejected` with `voided`. (E2E-P3.7-04)
5. **Given** a void already stored for a `reversal_id`, **When** the same `reversal_id` is sent again with the same `grant_id`, `reason`, `evidence_sha256`, and `partial` false, **Then** the result is `already_applied` and the original receipt is returned. **When** any of those four differs, **Then** the result is `conflict` and nothing changes. **When** the ABO signature is bad, **Then** the call is rejected. **When** `partial` is true, **Then** the call is `rejected` with code `partial_void` and writes nothing. **When** `partial` is missing or not a boolean, **Then** the call is `rejected` with code `partial_invalid` and writes nothing. A rejected call does not consume `reversal_id`. (E2E-P3.7-08)
6. **Given** a void applied by `voidForReversal` with `partial` false for a grant that already has a `grant_ledger` row, **When** the platform records it, **Then** a `grant_void` row, the R2 object `grant-ledger/<grant_id>.void.ndjson`, and coverage events are emitted, and the receipt's `installation_id` and `org_id` are that row's ids. (E2E-P3.7-09)

### 2.2 User Story 2 - Release a held term or void a grant (Priority: P2)

An operator calls `releaseHeld` or `voidGrant` (class HP: Access JWT and assertion). `releaseHeld` re-appends the held term at the end of the queue, and that term activates if nothing is active. `voidGrant` on an active complimentary term ends it `voided`, and the successor activates.

**Why this priority**: Release needs a held term from User Story 1. `voidGrant` is the operator void named with `releaseHeld` on the same method row.

**Independent Test**: E2E-P3.7-05 and E2E-P3.7-06 in harness H-AP.

**Acceptance Scenarios**:

1. **Given** a held term, **When** an operator calls `releaseHeld`, **Then** the held term is re-queued, and it activates if nothing is active. [I-3] (E2E-P3.7-05)
2. **Given** an active complimentary term with a successor, **When** an operator calls `voidGrant`, **Then** the complimentary term ends `voided` and the successor activates. The `grant_void` source is `operator`, `evidence_sha256` is the assertion challenge, and the R2 object `grant-ledger/<grant_id>.void.ndjson` is written. [SR-25] (E2E-P3.7-06)

### 2.3 User Story 3 - List grants made with one credential (Priority: P3)

An operator calls `listGrantsForVoid` (class H: Access JWT) with `credential_id` and `window` `{applied_from, applied_to}`. Both bounds are required inclusive UTC ISO-8601 timestamps on `applied_at`. The result is `ok` and lists exactly the grants made with that credential whose `applied_at` is inside the window, including when the credential is not `active`. An empty array is `ok`.

**Why this priority**: The list reads grants after void and release exist. It is the last story.

**Independent Test**: E2E-P3.7-07 in harness H-AP. Earlier H-AP suites stay green (rule S2).

**Acceptance Scenarios**:

1. **Given** grants made with one credential, **When** an operator calls `listGrantsForVoid` with that `credential_id` and a `window` `{applied_from, applied_to}`, **Then** the result is `ok` and `detail` lists exactly the matching `grant_ledger` rows inside that window, ordered by `applied_at` then `grant_id`, including when the credential is not `active`. An empty array is `ok`. A missing window field, a non-timestamp, or `applied_from` greater than `applied_to` is `rejected` with code `window_invalid`. (E2E-P3.7-07)

### 2.4 Test plan

| ID | Harness | Entry point | Assertion | Proves | Story |
| --- | --- | --- | --- | --- | --- |
| E2E-P3.7-01 | H-AP | `vendorCall("voidForReversal", …)` on `VendorEntrypoint` over the H-AP self service binding (`env.VENDOR` in `ai-platform/test/system/harness.ts`), class M, ABO-signed (`abo_kid`, `abo_signature`), for the payment funding the active term while T2 is queued. Refusal observed by `SELF.fetch` `POST /v1/requests` (`ai-platform/src/worker.ts`). | A15 platform half: void for the payment funding the active term, with T2 queued → T1 ends `reversed`, T2 held; refused `coverage_lapsed reason reversed`. [A15] | FR-001, FR-002 | User Story 1 |
| E2E-P3.7-02 | H-AP | `vendorCall("voidForReversal", …)` for the payment that funds a queued term, with another term active. | Void for a queued term's payment → that term removed; active term unaffected. | FR-001, FR-003 | User Story 1 |
| E2E-P3.7-03 | H-AP | `vendorCall("voidForReversal", …)` for the payment that funded a term that has already ended. | A17: void for an ended term → recorded only. [A17] | FR-001, FR-004 | User Story 1 |
| E2E-P3.7-04 | H-AP | `vendorCall("voidForReversal", …)` for a paid `grant_id` before `vendorCall("grant", …)` with that id. | Void before the grant → tombstone; receipt `installation_id` and `org_id` are both `00000000-0000-0000-0000-000000000000`, `ledger_seq` is 0, `term_ids` is empty, and no coverage event is emitted; the later grant with that id → `rejected voided`. | FR-001, FR-005 | User Story 1 |
| E2E-P3.7-05 | H-AP | `vendorCall("releaseHeld", …)` on `VendorEntrypoint`, class HP, with an Access JWT and an assertion (`grant_id`, `reason`). | `releaseHeld` → the held term is re-queued, and activates if nothing is active. [I-3] | FR-008 | User Story 2 |
| E2E-P3.7-06 | H-AP | `vendorCall("voidGrant", …)` on `VendorEntrypoint`, class HP, with an Access JWT and an assertion, for an active complimentary term. | `voidGrant` on an active complimentary term → ends `voided`; successor activates; `grant_void` source `operator` with `evidence_sha256` the assertion challenge; R2 object `grant-ledger/<grant_id>.void.ndjson` written. [SR-25] | FR-009, FR-007 | User Story 2 |
| E2E-P3.7-07 | H-AP | `vendorCall("listGrantsForVoid", …)` on `VendorEntrypoint`, class H, with an Access JWT (`credential_id`, `window` `{applied_from, applied_to}`). | `listGrantsForVoid(credential, window)` is `ok` and lists exactly the grants made with that credential whose `applied_at` is inside the inclusive window, ordered by `applied_at` then `grant_id`, including when the credential is not `active`. An empty array is `ok`. A bad window is `rejected` with `window_invalid`. | FR-010 | User Story 3 |
| E2E-P3.7-08 | H-AP | `vendorCall("voidForReversal", …)` replayed with the same `reversal_id` and the same `grant_id`, `reason`, `evidence_sha256`, and `partial` false; a replay that differs in one of those four; a call with a bad ABO signature; `partial` true; a missing or non-boolean `partial`. | Same `reversal_id` with the same `grant_id`, `reason`, `evidence_sha256`, and `partial` false → `already_applied`; any difference in those four → `conflict`; bad ABO signature → rejected; `partial` true → `rejected` `partial_void` and writes nothing; missing or non-boolean `partial` → `rejected` `partial_invalid` and writes nothing; a rejected call does not consume `reversal_id`. | FR-001, FR-006 | User Story 1 |
| E2E-P3.7-09 | H-AP | `vendorCall("voidForReversal", …)` with `partial` false for a grant that already has a `grant_ledger` row, then the platform D1 `grant_void` row, the R2 object `grant-ledger/<grant_id>.void.ndjson`, and the emitted coverage events. | An applied `voidForReversal` (`partial` false) for a grant that already has a `grant_ledger` row writes a `grant_void` row, the R2 object `grant-ledger/<grant_id>.void.ndjson` (one JSON line `{grant_id, reason, source, evidence_sha256, at, receipt}`), and coverage events. The receipt's `installation_id` and `org_id` are that row's ids. | FR-007 | User Story 1 |

### 2.5 Edge Cases

- A full reversal of the payment that funds the active or grace term ends that term now with `end_reason` `reversed` and no grace. Queued terms become `held`. The clinic coverage state is `reversed`, and `held_count` may be non-zero. Admission is refused `coverage_lapsed` with reason `reversed`. (03 §5.5 effect `end_current`, 03 §5.4 row active or grace, 03 §5.7 `reversed`, E2E-P3.7-01)
- A full reversal of a queued or held term's own payment ends that term `reversed` and removes it from the queue. Other terms are unaffected. (03 §5.4 row queued or held, 03 §5.5 effect `remove_queued`, E2E-P3.7-02)
- A full reversal of a payment that funds an already ended term is recorded only. Nothing else changes. (03 §5.5 effect `none`, 03 §5.4, E2E-P3.7-03)
- A void stored before its grant is a tombstone. The receipt's `installation_id` and `org_id` are both the nil UUID `00000000-0000-0000-0000-000000000000`, `ledger_seq` is 0, `term_ids` is empty, and that call emits no coverage event. A later `grant` with that id is `rejected` with code `voided`. (03 §3.2 row `grant_void`, 03 §5.5 effect `tombstone`, 04 §1.4 step 5, 04 §1.6, 03 §6.7, E2E-P3.7-04)
- After a void is stored, the same `reversal_id` with the same `grant_id`, `reason`, `evidence_sha256`, and `partial` false is `already_applied` and returns the original receipt. Any difference in those four is `conflict` and changes nothing. A bad ABO signature is rejected. `partial` true is `rejected` with code `partial_void` and `detail` empty, and writes no `grant_void` row, no R2 void object, no coverage event, and no tombstone. A missing or non-boolean `partial` is `rejected` with code `partial_invalid` and `detail` empty, and writes nothing. A rejected call stores nothing, so it does not consume `reversal_id`. (04 §1.3 row `voidForReversal`, 03 §5.5 partial row, E2E-P3.7-08)
- `releaseHeld` re-appends the held term at the end of the queue. It activates if nothing is active. (03 §5.4 row held release, E2E-P3.7-05)
- `voidGrant` on a term that has not ended ends it with `end_reason` `voided`. If it was active, the successor activates. (03 §5.4 row grant voided, E2E-P3.7-06)
- `listGrantsForVoid` takes `credential_id` and `window` `{applied_from, applied_to}`. Both fields are required UTC ISO-8601 timestamps and are inclusive bounds on `applied_at`. `applied_from` must be less than or equal to `applied_to`. The span has no maximum. `credential_id` matches `operator_credential_id`, including when that credential is not `active`. A successful call is `ok`: `detail` is the JSON text of the matching `grant_ledger` rows in ascending `applied_at` then `grant_id`. An empty array is `ok`. `code` is empty and the envelope `receipt` is absent. A missing window field, a non-timestamp, or `applied_from` greater than `applied_to` is `rejected` with code `window_invalid` and `detail` empty. (04 §1.2, 04 §1.3 row `listGrantsForVoid`, 04 §1.6, 03 §3.2 row `grant_ledger`, E2E-P3.7-07)

## 3. Requirements

### 3.1 Functional Requirements

- **FR-001**: `voidForReversal` is class M. Beyond `contract_version` it takes `grant_id` (the paid grant), `reversal_id`, `reason`, `evidence_sha256`, `partial`, `abo_kid`, and `abo_signature`. `partial` is required and is a boolean. It is ABO-signed and idempotent by `reversal_id`. When `partial` is false it resolves the live term through `origin_grant_id` and its output is a receipt. (04 §1.3 row `voidForReversal`, Implements)
- **FR-002**: Effect `end_current`: a full reversal whose payment funds the active or grace term voids that term so it ends now with `end_reason` `reversed` and no grace. Queued terms become `held`. The clinic coverage state is `reversed`, and `held_count` may be non-zero. A clinic request is then refused `coverage_lapsed` with reason `reversed`. With T2 queued, T1 ends `reversed` and T2 is held. (03 §5.5, 03 §5.4 row active or grace, 03 §5.7 `reversed`, E2E-P3.7-01)
- **FR-003**: Effect `remove_queued`: a full reversal whose payment funds a queued or held term voids that term so it ends `reversed` and is removed from the queue. Other terms are unaffected. A void for a queued term's payment removes that term and leaves the active term unchanged. (03 §5.5, 03 §5.4 row queued or held, E2E-P3.7-02)
- **FR-004**: Effect `none`: a full reversal whose payment funds an ended term is recorded only. A term ended by an old payment's reversal changes nothing else. (03 §5.5, 03 §5.4, E2E-P3.7-03)
- **FR-005**: When the paid grant is not yet applied, `voidForReversal` stores a tombstone. `grant_void` is append-only. A void may precede its grant. The call has no `org_id` or `installation_id`, and `grant_ledger` has no row, so the receipt's `installation_id` and `org_id` are both the nil UUID `00000000-0000-0000-0000-000000000000`, `ledger_seq` is 0, and `term_ids` is empty. That call writes `grant_void` and the R2 void object and emits no coverage event. A later `grant` with that id fails validation step 5 and is `rejected` with code `voided`. (03 §5.5 effect `tombstone`, 03 §3.2 row `grant_void`, 04 §1.4 step 5, 04 §1.6, 03 §6.7, E2E-P3.7-04)
- **FR-006**: `partial` true is `rejected` with code `partial_void` and `detail` empty, and writes no `grant_void` row, no R2 void object, no coverage event, and no tombstone. A missing `partial`, or a value that is not a boolean, is `rejected` with code `partial_invalid` and `detail` empty, and writes nothing. A rejected call stores nothing, so it does not consume `reversal_id` and that `reversal_id` can still be applied later with `partial` false. After a void is stored, the same `reversal_id` with the same `grant_id`, `reason`, `evidence_sha256`, and `partial` false is `already_applied` and returns the original receipt. Any difference in those four is `conflict` and changes nothing. A bad ABO signature is rejected. At launch a partial reversal is not applied: the platform action is none, and the operator is alerted. (04 §1.3 row `voidForReversal`, 03 §5.5 partial row, E2E-P3.7-08)
- **FR-007**: An applied void writes `grant_void` in D1 and the R2 object `grant-ledger/<grant_id>.void.ndjson`. When the grant already has a `grant_ledger` row, the void emits coverage events and the receipt's `installation_id` and `org_id` are that row's ids. A tombstone emits no coverage event; its receipt uses the nil UUID `00000000-0000-0000-0000-000000000000` for both ids, `ledger_seq` 0, and `term_ids` empty (FR-005). The D1 row is `grant_id`, `reason`, `source` (`reversal` or `operator`), `evidence_sha256`, and `at`, and it is append-only. The R2 object is one JSON line `{grant_id, reason, source, evidence_sha256, at, receipt}` with the `grant_void` columns plus that void's receipt. P3.7 writes that object only when `voidForReversal` with `partial` false, or `voidGrant`, applies a void. `voidForReversal` with `partial` false records source `reversal` and the call's `reason` and `evidence_sha256`. A `partial` true call writes no row and no object. (03 §3.2 row `grant_void`, 03 §3.3 void object, 04 §1.6, 03 §6.7, E2E-P3.7-09)
- **FR-008**: `releaseHeld` is class HP. It takes `access_jwt`, `assertion`, `grant_id`, and `reason`, returns a receipt, and is idempotent by assertion challenge. The held term becomes `queued` and is re-appended at the end. It activates if nothing is active. (04 §1.3 row `releaseHeld`, `voidGrant`, 03 §5.4 row held release, E2E-P3.7-05)
- **FR-009**: `voidGrant` is class HP. It takes `access_jwt`, `assertion`, `grant_id`, and `reason`, returns a receipt, and is idempotent by assertion challenge. It takes no `evidence_sha256` input. A grant voided on a term that has not ended moves that term to `ended` with `end_reason` `voided`. If it was active, the successor activates. An active complimentary term voided this way ends `voided` and its successor activates. The `grant_void` source for this call is `operator`, and `evidence_sha256` is the assertion challenge. (04 §1.3 row `releaseHeld`, `voidGrant`, 04 §1.5, 03 §5.4 row grant voided, 03 §3.2 row `grant_void`, E2E-P3.7-06)
- **FR-010**: `listGrantsForVoid` is class H. It takes `access_jwt`, `credential_id`, and `window` `{applied_from, applied_to}`. Both window fields are required UTC ISO-8601 timestamps and are inclusive bounds on `grant_ledger.applied_at`. `applied_from` must be less than or equal to `applied_to`. The span has no maximum. `credential_id` matches `operator_credential_id`, including when that credential is not `active`. A successful call is `ok`: `detail` is the JSON text of an array of `{grant_id, origin_grant_id, org_id, installation_id, kind, source_kind, operator_credential_id, envelope_sha256, receipt, applied_at}` (the `grant_ledger` columns) for rows with that `operator_credential_id` whose `applied_at` is inside the window, in ascending `applied_at` then `grant_id`. Each `receipt` is the §1.6 receipt object. An empty array is `ok`. `code` is empty and the envelope `receipt` is absent. A missing window field, a value that is not a UTC ISO-8601 timestamp, or `applied_from` greater than `applied_to` is `rejected` with code `window_invalid` and `detail` empty. The result lists exactly the grants made with that credential inside the window (SR-25). `grant_ledger` indexes `(operator_credential_id, applied_at)` for this listing. The compromise-response use of this method is to list those grants and void each one with `voidGrant`. (04 §1.2, 04 §1.3 row `listGrantsForVoid`, 04 §1.6, 03 §3.2 row `grant_ledger`, 05 §3.2 Compromise response paragraph, E2E-P3.7-07)

### 3.2 Key Entities

- **`grant_void`**: Append-only platform D1 row: `grant_id`, `reason`, `source` (`reversal` or `operator`), `evidence_sha256`, `at`. `voidForReversal` with `partial` false writes `source` `reversal` and that call's `evidence_sha256`. `voidGrant` writes `source` `operator` and sets `evidence_sha256` to the assertion challenge. An applied row's R2 object is `grant-ledger/<grant_id>.void.ndjson`: one JSON line `{grant_id, reason, source, evidence_sha256, at, receipt}`. P3.7 writes that object only for an applied `voidForReversal` (`partial` false) or `voidGrant`. A `partial` true call writes no row and no object. A row that precedes its grant is a tombstone. That call's receipt uses the nil UUID `00000000-0000-0000-0000-000000000000` for both `installation_id` and `org_id`, `ledger_seq` 0, and `term_ids` empty, and it emits no coverage event. A later `grant` with that id is `rejected` with `voided`. (03 §3.2 row `grant_void`, 03 §3.3 void object, 04 §1.4 step 5)
- **Term end for reversal and void**: `end_reason` `reversed` with queued terms moved to `held` (`end_current`), or one queued or held term removed (`remove_queued`), or an ended term recorded only (`none`). `end_reason` `voided` when an operator voids a term that has not ended. `releaseHeld` moves `held` back to `queued` at the end of the queue. (03 §5.4 named rows, 03 §5.5)
- **Clinic coverage state `reversed`**: The last term ended by a full reversal. `held_count` may be non-zero. (03 §5.7)

## 4. Constitution Alignment

### 4.1 Architecture & Operations Impact

- **Clinic Fit**: One clinic's paid term is voided when its payment is reversed, a held term can be released, and an operator can void a complimentary term or list grants made with one credential. The unit adds no second clinic product.
- **Layer Placement**: Codebase is `ai-platform` only. No wiring exception is named. Live entries are `VendorEntrypoint` methods over the H-AP self service binding (`vendorCall` / `env.VENDOR` in `ai-platform/test/system/harness.ts`) and `SELF.fetch` `POST /v1/requests` (`ai-platform/src/worker.ts`). `plan.md` re-runs the constitution check in 02 §7 (rule S12).
- **Data Integrity & Security**: `voidForReversal` is class M and ABO-signed, and it is idempotent by `reversal_id`. `releaseHeld` and `voidGrant` are class HP and take `access_jwt` and `assertion`. `listGrantsForVoid` is class H and takes `access_jwt`. `grant_void` is append-only. (04 §1.3, 03 §3.2 row `grant_void`)
- **Failure Handling**: A bad ABO signature is rejected. `partial` true is `rejected` with code `partial_void` and writes nothing. A missing or non-boolean `partial` is `rejected` with code `partial_invalid` and writes nothing. A rejected call does not consume `reversal_id`. The same `reversal_id` with the same `grant_id`, `reason`, `evidence_sha256`, and `partial` false is `already_applied`; any difference in those four is `conflict`. A grant that arrives after its tombstone is `rejected` with `voided`. After `end_current`, `POST /v1/requests` is refused `coverage_lapsed` with reason `reversed`. A bad `listGrantsForVoid` window is `rejected` with code `window_invalid`. (E2E-P3.7-01, E2E-P3.7-04, E2E-P3.7-07, E2E-P3.7-08)

## 5. Out of Scope

- Lineage across a transfer (→ P3.8); deciding the effect on the ABO side (→ P4.5).
- No material from outside this unit's Read spans. This unit has no Do not read line.
- No rewrite of complimentary and adjustment grant semantics, ceiling policy, or `suspend`/`resume`/`inspectCoverage` (rule S7).
- No module that no test-plan row reaches (rule S8).
- No S9 path owned by a later unit. `/control/*` stays until P3.10. Following `origin_grant_id` onto another installation after a transfer stays with P3.8 (03 §5.5 lineage sentence, unit Out of scope). ABO reversal effect, ABO retry of a transient void, and ABO alerting of a reversal stay with P4.5. In the compromise-response paragraph, revoking the suspect credential, revoking Access sessions, and rotating a machine key are not methods this unit adds (05 §3.2).
- No second codebase. The Codebase cell is `ai-platform`.

## 6. Success Criteria

### 6.1 Measurable Outcomes

- **SC-001**: E2E-P3.7-01, E2E-P3.7-02, E2E-P3.7-03, E2E-P3.7-04, E2E-P3.7-05, E2E-P3.7-06, E2E-P3.7-07, E2E-P3.7-08, and E2E-P3.7-09 pass in harness H-AP.
- **SC-002**: Every earlier suite stays green (rule S2).

## 7. Assumptions

- No §6 open question is named by this unit's Read or Implements lines.
- Lineage across a transfer stays with P3.8 (rule S9).
- Deciding the reversal effect on the ABO side stays with P4.5 (rule S9).
- `/control/*` stays until P3.10 (rule S9).
