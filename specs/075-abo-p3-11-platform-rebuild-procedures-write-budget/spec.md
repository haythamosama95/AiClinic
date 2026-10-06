# Feature Specification: Platform rebuild procedures and the write budget

**Feature Branch**: `ai/075-abo-p3-11-platform-rebuild-procedures-write-budget`

**Created**: 2026-10-06

**Status**: Draft

**Input**: P3.11 — Platform rebuild procedures and the write budget

## 1. Unit Contract

**Implements** — Read: 05 §5.2; 05 §5.3; 01 §7 row R-7; 03 §6.6; 03 §6.7 (write-budget bullet); 04 §6.5 ("Add" row, concurrency test).

- an H method that emits a fresh snapshot event per installation (rebuilds `coverage_mirror`); a DO rebuild (H) from the last `coverage_event` plus later ledger, void and hold/suspension/transfer events, plus `usage_event` by `term_id`, compared with the mirror; a D1 rebuild (H) of `grant_ledger`/`grant_void` from R2 `grant-ledger/`; a load scenario for A34 measuring DO rows written per AI request against about 2 (R-7).

The D1 rebuild is a class-H `VendorEntrypoint` method, invoked over the H-AP self service binding. It is a separate method from the snapshot refresh. 05 §5.3 runs that ledger rebuild first, then the per-installation snapshot H method. No new route, cron, alarm, or RPC is added.

**Freezes** — None. The P3.11 unit row has no Outputs / freezes line.

**Consumes** — P3.10: None. The P3.10 unit row has no Outputs / freezes line.

**Open questions relied on** — None.

**Spikes** — R-7 (06 §2 S6). 01 §7 row R-7: the DO migrates from a JSON blob to SQLite tables, and DO availability becomes coverage availability. A naive table layout (a row per reservation, idempotency key or usage record, plus indexes) costs about 8 row writes per AI request instead of 2. Effect if wrong: outage behaviour; DO cost about 4× the §3.2 budget. Spike or mitigation: fallback bounded as in §3.2; load-test A34 and measure `rows_written` per AI request against the §3.2 write budget. 05 §10 "Spike-dependent items" names fallbacks for R-2, R-3, R-4, and R-5. It does not name an R-7 item. This unit's load scenario is that measurement (E2E-P3.11-05). The §3.2 fallback stays the mitigation named on the R-7 row.

## 2. User Scenarios & Testing

### 2.1 User Story 1 - Rebuild a clinic's DO, grant ledger, and coverage mirror (Priority: P1)

An operator calls three class-H methods on `VendorEntrypoint` over the H-AP self service binding. One rebuilds a clinic's DO from the last `coverage_event` plus later ledger, void, and hold, release, suspension, and transfer events, plus `usage_event` by `term_id`, and compares the result with `coverage_mirror`. One rebuilds `grant_ledger` and `grant_void` from R2 `grant-ledger/`. One emits a fresh snapshot event per installation and rebuilds `coverage_mirror`. The D1 rebuild method is separate from the snapshot method. 05 §5.3 runs the ledger rebuild first, then the snapshot method once per installation.

**Why this priority**: The load story measures the live AI request path. It does not call these methods. This is the story that recovers platform DO and D1 loss, and the snapshot method is the step 05 §5.3 runs after the D1 rebuild.

**Independent Test**: E2E-P3.11-01, E2E-P3.11-02, E2E-P3.11-03, and E2E-P3.11-04 in harness H-AP.

**Acceptance Scenarios**:

1. **Given** a clinic DO holding terms, positions, holds, and usage, **When** that clinic's DO storage is wiped and the class-H DO rebuild runs, **Then** terms, positions, holds, and usage equal the pre-loss state, in-flight reservations are forfeited, and the compare with `coverage_mirror` is clean. [FM-20] (E2E-P3.11-01, 05 §5.2)
2. **Given** a DO rebuild whose result differs from `coverage_mirror`, **When** the compare runs, **Then** the platform alerts. (E2E-P3.11-02, 05 §5.2)
3. **Given** `grant_ledger` truncated, **When** the class-H D1 rebuild runs, **Then** `grant_ledger` and `grant_void` rebuilt from R2 `grant-ledger/` are identical to the pre-truncation rows. (E2E-P3.11-03, 05 §5.3)
4. **Given** an installation, **When** the class-H snapshot method runs, **Then** one new `coverage_event` is written for that installation and `coverage_mirror` is updated. (E2E-P3.11-04, 05 §5.3)

### 2.2 User Story 2 - Measure the write budget across exhaustion (Priority: P2)

The live AI request path admits 100 concurrent requests across exhaustion. One exhaustion occurs. Overshoot is at most `w_max − 1`. Each request writes at most 2 DO rows.

**Why this priority**: It measures the write budget on `POST /v1/requests`. It does not call the rebuild methods.

**Independent Test**: E2E-P3.11-05 in the H-AP load suite. Every earlier suite stays green (rule S2).

**Acceptance Scenarios**:

1. **Given** concurrent AI requests that cross exhaustion, **When** 100 of them run, **Then** there is one exhaustion, overshoot is ≤ `w_max − 1`, and each request writes ≤ 2 DO rows. [A34, R-7] (E2E-P3.11-05, 03 §6.6, 03 §6.7 write-budget bullet, 04 §6.5 Add row concurrency test, 01 §7 row R-7)

### 2.3 Test plan

| ID | Harness | Entry point | Assertion | Proves | Story |
| --- | --- | --- | --- | --- | --- |
| E2E-P3.11-01 | H-AP | `vendorCall` on `VendorEntrypoint` (`env.VENDOR` in `ai-platform/test/system/harness.ts`) for the class-H DO rebuild. The cited design does not name that method's identifier. | FM-20: wipe a clinic's DO storage → rebuild → terms, positions, holds and usage equal the pre-loss state (in-flight reservations forfeited); compare clean. [FM-20] | FR-001 | User Story 1 |
| E2E-P3.11-02 | H-AP | `vendorCall` on `VendorEntrypoint` (`env.VENDOR`) for the same class-H DO rebuild. The platform alert is the compare outcome. | A rebuild that diverges from the mirror → platform alert. | FR-002 | User Story 1 |
| E2E-P3.11-03 | H-AP | `vendorCall` on `VendorEntrypoint` (`env.VENDOR`) for the class-H D1 rebuild of `grant_ledger` and `grant_void` from R2 `grant-ledger/`. Separate method from the snapshot refresh. | `grant_ledger` truncated → rebuilt from R2, identical. | FR-003 | User Story 1 |
| E2E-P3.11-04 | H-AP | `vendorCall` on `VendorEntrypoint` (`env.VENDOR`) for the class-H snapshot method, once per installation. Separate method from the D1 rebuild. | Snapshot refresh → one new `coverage_event` per installation; mirror updated. | FR-004 | User Story 1 |
| E2E-P3.11-05 | H-AP load suite | `SELF.fetch` `POST /v1/requests` on `ai-platform/src/worker.ts` (`pathname === "/v1/requests"` and `method === "POST"`). | Load: 100 concurrent requests across exhaustion → one exhaustion; overshoot ≤ w_max − 1; ≤ 2 DO row writes per request. [A34, R-7] | FR-005, FR-006 | User Story 2 |

### 2.4 Edge Cases

- Reservations in flight at the DO loss are forfeited to the clinic's benefit. Terms, positions, holds, and usage otherwise equal the pre-loss state, and the compare with `coverage_mirror` is clean. (05 §5.2, E2E-P3.11-01, FM-20)
- A rebuild that differs from `coverage_mirror` alerts. (05 §5.2, E2E-P3.11-02)
- Usage recorded after the snapshot is re-applied from `usage_event` by `term_id`, including shipped `usage_adjustment` rows. `request_id` uniqueness prevents double counting. Retention keeps these rows while their term is unended (03 §8). (05 §5.2)
- Within 30 days, platform D1 is restored with Time Travel. Otherwise `grant_ledger` and `grant_void` are rebuilt from R2 `grant-ledger/`. A truncated `grant_ledger` rebuilds identical. (05 §5.3, E2E-P3.11-03)
- The snapshot method writes one new `coverage_event` per installation and updates `coverage_mirror`. (05 §5.3, E2E-P3.11-04)
- Under the load of 100 concurrent requests across exhaustion, one exhaustion occurs and overshoot is ≤ `w_max − 1`. That overshoot is the normal-operation bound: `w_max − 1` credits, the one reservation that crosses. It is charged to the term that exhausted, never to the next one. (03 §6.6, E2E-P3.11-05, A34)
- Admission and settlement write `hot` once each, so there are about 2 row writes per AI request. Term, grant, and outbox rows are written only on events. The load measures ≤ 2 DO row writes per request (`rows_written` against the §3.2 write budget). (03 §6.7 write-budget bullet, 01 §7 row R-7, 04 §6.5 Add row concurrency test, E2E-P3.11-05)

## 3. Requirements

### 3.1 Functional Requirements

- **FR-001**: A class-H `VendorEntrypoint` method rebuilds one clinic's DO. It loads that clinic's last `coverage_event` snapshot (its terms, positions, usage, holds, suspension, and epoch) into an empty DO. It applies, in order, every later `grant_ledger` and `grant_void` row and every later hold, release, suspension, and transfer event. It re-applies usage recorded after the snapshot from `usage_event` by `term_id`, including shipped `usage_adjustment` rows. `request_id` uniqueness prevents double counting. Retention keeps these rows while their term is unended (03 §8). It compares the result with `coverage_mirror`. Reservations in flight at the loss are forfeited to the clinic's benefit. After a wipe of that clinic's DO storage, terms, positions, holds, and usage equal the pre-loss state, and the compare is clean. (05 §5.2, Implements, E2E-P3.11-01) [FM-20]
- **FR-002**: When the DO rebuild differs from `coverage_mirror`, the platform alerts. (05 §5.2, E2E-P3.11-02)
- **FR-003**: A class-H `VendorEntrypoint` method, separate from the snapshot method, rebuilds `grant_ledger` and `grant_void` from the R2 `grant-ledger/` objects. It is invoked over the H-AP self service binding (`vendorCall` on `env.VENDOR`). 05 §5.3 restores platform D1 with Time Travel within 30 days. Otherwise this method runs, and then the snapshot method runs once per installation. No new route, cron, alarm, or RPC is added. A truncated `grant_ledger` is identical after the rebuild. (05 §5.3, Implements, E2E-P3.11-03)
- **FR-004**: A class-H `VendorEntrypoint` method emits one fresh snapshot event per installation. That event rebuilds `coverage_mirror`. One new `coverage_event` is written per installation, and the mirror is updated. (05 §5.3, Implements, E2E-P3.11-04)
- **FR-005**: In normal operation the maximum usage beyond a term's allowance is `w_max − 1` credits (the one reservation that crosses). The overshoot is charged to the term that exhausted, never to the next one. The load scenario runs 100 concurrent requests across exhaustion and observes one exhaustion and overshoot ≤ `w_max − 1`. (03 §6.6, 04 §6.5 Add row concurrency test, E2E-P3.11-05) [A34]
- **FR-006**: Admission and settlement write `hot` once each, so there are about 2 row writes per AI request. Term, grant, and outbox rows are written only on events. The same load scenario measures `rows_written` per AI request against that budget and observes ≤ 2 DO row writes per request. (03 §6.7 write-budget bullet, 01 §7 row R-7, 04 §6.5 Add row concurrency test, E2E-P3.11-05) [A34, R-7]

### 3.2 Key Entities

Not applicable — this unit defines no entities.

## 4. Constitution Alignment

### 4.1 Architecture & Operations Impact

- **Clinic Fit**: One clinic's platform coverage is rebuilt after DO or `grant_ledger` loss, and a live AI request stays inside the write budget of about 2 DO row writes. The unit adds no second clinic product.
- **Layer Placement**: Codebase is `ai-platform` only. No wiring exception is named. Live entries are `vendorCall` on `VendorEntrypoint` (`env.VENDOR` in `ai-platform/test/system/harness.ts`) for the three class-H methods, and `SELF.fetch` `POST /v1/requests` on `ai-platform/src/worker.ts` for the load. `plan.md` re-runs the constitution check in 02 §7 (rule S12).
- **Data Integrity & Security**: The DO rebuild reads the last `coverage_event` and later `grant_ledger`, `grant_void`, hold, release, suspension, and transfer events, plus `usage_event` by `term_id`, and compares with `coverage_mirror`. The D1 rebuild copies R2 `grant-ledger/` back into `grant_ledger` and `grant_void`. Both are class-H methods on the existing entrypoint. No new route, cron, alarm, or RPC is added. (05 §5.2, 05 §5.3, Implements)
- **Failure Handling**: A wiped clinic DO rebuilds to the pre-loss terms, positions, holds, and usage, with in-flight reservations forfeited, and a clean compare. A rebuild that diverges from `coverage_mirror` raises a platform alert. A truncated `grant_ledger` rebuilds identical from R2. Across 100 concurrent requests at exhaustion there is one exhaustion, overshoot ≤ `w_max − 1`, and ≤ 2 DO row writes per request. (E2E-P3.11-01, E2E-P3.11-02, E2E-P3.11-03, E2E-P3.11-05, 05 §5.2, 05 §5.3, 03 §6.6, 03 §6.7 write-budget bullet)

## 5. Out of Scope

- The P3.11 unit row has no Out of scope line.
- No Do-not-read material. This unit row has no Do not read line.
- No rewrite of a consumed contract. P3.10 freezes nothing for this unit to consume (rule S7).
- No module that no test-plan row reaches (rule S8). The DO rebuild is reached by `vendorCall` (E2E-P3.11-01, E2E-P3.11-02). The D1 rebuild is reached by `vendorCall` (E2E-P3.11-03). The snapshot method is reached by `vendorCall` (E2E-P3.11-04). The write-budget measurement is reached by `SELF.fetch` `POST /v1/requests` (E2E-P3.11-05).
- No S9 path owned by a later unit. This unit's row names none. Enrollment, `/control/entitle`, and the entitlement, plan, and invoice tables and `/control/*` routes are already assigned to P3.2, P3.4, and P3.10 (rule S9).
- No second codebase. The Codebase cell is `ai-platform`.
- No new route, cron, alarm, or RPC. The D1 rebuild, the DO rebuild, and the snapshot refresh are class-H `VendorEntrypoint` methods. The load uses the existing `POST /v1/requests` path.
- ABO rebuild (05 §5.1) stays with P4.11. Backend projection rebuild (05 §5.4) stays with P5.2. The NFR-08 allowance check on 05 §7 stays with P8.1. Outage overshoot (03 §6.6, additionally at most 5 × `w_max`) stays with P3.9. The 03 §6.7 events bullet stays with P3.3. The 03 §6.7 alarm bullet stays with P3.5. (06 §5 D1)

## 6. Success Criteria

### 6.1 Measurable Outcomes

- **SC-001**: E2E-P3.11-01, E2E-P3.11-02, E2E-P3.11-03, and E2E-P3.11-04 pass in harness H-AP, and E2E-P3.11-05 passes in the H-AP load suite.
- **SC-002**: Every earlier suite stays green (rule S2).

## 7. Assumptions

- No §6 open question is named by this unit's Read or Implements lines.
- This unit's row names no S9 transitional path.
