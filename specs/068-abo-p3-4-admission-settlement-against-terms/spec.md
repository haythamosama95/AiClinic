# Feature Specification: Admission and settlement against terms

**Feature Branch**: `ai/068-abo-p3-4-admission-settlement-against-terms`

**Created**: 2026-10-06

**Status**: Draft

**Input**: P3.4 — Admission and settlement against terms

## 1. Unit Contract

**Implements** — Read: 03 §6.2; 03 §6.3; 03 §6.6 ("Normal operation" row); 03 §3.1 (`hot` row); 03 §3.2 rows `usage_event`, `usage_rollup`; 04 §4.2 (rows `/v1/requests`, `/v1/capabilities`, and the denial-code table); 04 §6.1 rows quota-do, admission (not fallback), credit (`creditUsage`), entitlement, pipeline, capability, journal, rollup, dashboards, errors, adapter, soft-threshold, rate-limit, manifest, `worker.ts` (settlement, `periodFromIso`, cost class, `minimumPlanTier`); 04 §6.3 row usage_term.

- DO admission steps 1–7 and settlement by reservation id; blob state removed; reservations older than 15 min charged; concurrency limit and capabilities from the plan snapshot.
- Exhaustion and successor activation in the same transaction; band events at 75 % and 90 %, once per term per band.
- Denial codes `allowance_exhausted`, `coverage_lapsed` + `coverage_reason`, `forbidden_capability`, `concurrency_limited` + `retry_after` (`suspended` mapped, and set in P3.6); `quota_exhausted` and `period_reset` removed; a DO `rejected` version answer → `coverage_unknown`.
- Pipeline stages 3, 8 and 15 carry `term_id`, reservation and snapshot; cost class from the snapshot.
- `usage_event.term_id` + unique `request_id` (insert-or-ignore); outbox `usage_adjustment`; rollup by `{installation_id, term_id}`; dashboards, rate-limit counters and soft-threshold on the new codes and band.
- `/v1/capabilities` from `coverage_mirror` by primary key, never the TTL cache. Entitlement no longer read on the request path.
- H-AP `coverClinic()` (paid grant over the entrypoint) replaces `entitleScenario`; every entitling suite migrated (rule V2 step 3).

**Freezes** — admission answer (reservation, `term_id`, snapshot, band); clinic denial codes of 04 §4.2. CP-B.

**Consumes** — `grant` (paid), `getCoverage`, `listGrants`, `readCoverageEvents`, service-key and plan-version methods; DO schema; event and receipt shapes. Changing one is out of scope (rule S7).

**Open questions relied on** — None.

**Spikes** — None.

## 2. User Scenarios & Testing

### 2.1 User Story 1 - Complete a request charged to a term (Priority: P1)

The harness covers a clinic with a paid grant over `VendorEntrypoint`. The clinic client, holding an issuer token, calls `GET /v1/capabilities` and then `POST /v1/requests`. Capabilities list that plan at once. The completed request is journaled with `term_id`, and the term's `used` increases by the capability weight `w`.

**Why this priority**: Denial, exhaustion, and settlement stories call the same admission. This story is the one they depend on, and it is checkpoint CP-B.

**Independent Test**: E2E-P3.4-01 in harness H-AP.

**Acceptance Scenarios**:

1. **Given** a paid grant over the real entrypoint and an issuer token, **When** the clinic client calls `GET /v1/capabilities` and then `POST /v1/requests` and that request completes, **Then** `/v1/capabilities` lists the plan at once, `usage_event` has `term_id`, and `used` increases by `w`. [NFR-05] (E2E-P3.4-01, CP-B)

### 2.2 User Story 2 - Refuse a request the term does not allow (Priority: P2)

The clinic client calls `POST /v1/requests`. A clinic that was never granted is refused `coverage_lapsed`. A capability outside the plan is refused `forbidden_capability`. A 17th concurrent in-flight request, when the snapshot limit is 16, is refused `concurrency_limited`. A DO version rejection is returned to the client as `coverage_unknown`.

**Why this priority**: These refusals are the admission answers once User Story 1's term path exists. They do not require a completed provider call.

**Independent Test**: E2E-P3.4-02, E2E-P3.4-03, E2E-P3.4-04, and E2E-P3.4-12 in harness H-AP.

**Acceptance Scenarios**:

1. **Given** an org that was never granted, **When** the clinic client calls `POST /v1/requests`, **Then** the response is 403 `coverage_lapsed` with reason `none`, and there is no journal row. (E2E-P3.4-02)
2. **Given** a covered clinic whose plan snapshot does not include the requested capability, **When** the clinic client calls `POST /v1/requests`, **Then** the response is 403 `forbidden_capability`. (E2E-P3.4-03)
3. **Given** a snapshot concurrency limit of 16 and 16 in-flight requests, **When** a 17th concurrent in-flight request arrives, **Then** the response is 429 `concurrency_limited` with `retry_after`, distinct from `rate_limited`. [FR-09, P-11] (E2E-P3.4-04)
4. **Given** the per-clinic DO answers `rejected` for version, **When** the clinic client calls `POST /v1/requests`, **Then** the client receives 503 `coverage_unknown`. (E2E-P3.4-12)

### 2.3 User Story 3 - Exhaust a term and activate the successor (Priority: P3)

A request that reaches the allowance ends the active term in that same admission. With nothing queued, the clinic is `exhausted` and the next request is `allowance_exhausted`. With a queued term, that term becomes active at that instant. Two concurrent requests near the limit produce one exhaustion. Crossing 75 % and 90 % emits one band event for each band.

**Why this priority**: Exhaustion and bands run on an active term placed by User Story 1. User Story 4's late settlement still applies after a term has ended.

**Independent Test**: E2E-P3.4-05, E2E-P3.4-06, E2E-P3.4-07, and E2E-P3.4-08 in harness H-AP.

**Acceptance Scenarios**:

1. **Given** an active term and nothing queued, **When** a request reaches the allowance, **Then** the term ends `exhausted`. **When** the next request arrives, **Then** it is refused `allowance_exhausted`, the state is `exhausted`, and there is no grace. [A31] (E2E-P3.4-05)
2. **Given** an active term and a queued term, **When** a request reaches the allowance, **Then** the queued term activates at that instant with a full allowance, and `ends_at` is that instant plus 1 month. [A32] (E2E-P3.4-06)
3. **Given** two concurrent requests near the allowance, **When** both are admitted, **Then** there is one exhaustion event, overshoot is at most `w_max − 1`, and the other request is charged to the successor or refused. [A34] (E2E-P3.4-07)
4. **Given** an active term, **When** usage crosses 75 % and 90 %, **Then** one band event is emitted for each band, and a later crossing of the same band emits nothing further. [A29 platform half, FR-34] (E2E-P3.4-08)

### 2.4 User Story 4 - Settle each request once (Priority: P4)

Settlement converts the reservation from User Story 1. A request that consumed nothing releases it. A reservation still open after 15 minutes is charged at the next admission, and a later settlement does not change the DO or add a second `usage_event`. A replayed `jti` or idempotency key returns the stored answer. Every suite that used `entitleScenario` now uses `coverClinic()`.

**Why this priority**: Settlement, the 15-minute charge, and replay are defined on a reservation the earlier stories already admit. The harness migration is the regression line for this unit.

**Independent Test**: E2E-P3.4-09, E2E-P3.4-10, and E2E-P3.4-11 in harness H-AP. Every H-AP suite that entitles runs through `coverClinic()` and stays green (rule V2, rule S2).

**Acceptance Scenarios**:

1. **Given** an admitted request, **When** the provider consumed nothing, **Then** the reservation is released and `used` is unchanged. (E2E-P3.4-09)
2. **Given** a reservation unsettled for more than 15 minutes, **When** the next admission runs and a late settlement for that request arrives, **Then** the next admission charges it, the late settlement changes nothing in the DO, and there is one `usage_event` for that `request_id`. [NFR-06] (E2E-P3.4-10)
3. **Given** a stored answer for a `jti` or idempotency key, **When** that `jti` or idempotency key is replayed, **Then** the stored answer is returned and the DO does not write. (E2E-P3.4-11)

### 2.5 Test plan

| ID | Harness | Entry point | Assertion | Proves | Story |
| --- | --- | --- | --- | --- | --- |
| E2E-P3.4-01 | H-AP | `coverClinic()` → `VendorEntrypoint.grant` over the H-AP self service binding (`vendorCall` in `ai-platform/test/system/harness.ts`); issuer token from `newClinic()`; `SELF.fetch` `GET /v1/capabilities`; `SELF.fetch` `POST /v1/requests` | CP-B: paid grant → issuer token → `/v1/capabilities` lists the plan at once → `POST /v1/requests` completes → `usage_event` has `term_id`; `used` += w. [NFR-05] | FR-004, FR-010, FR-011, FR-013, FR-014 | User Story 1 |
| E2E-P3.4-02 | H-AP | `SELF.fetch` `POST /v1/requests` for an org with no paid grant | Org never granted → 403 `coverage_lapsed` reason `none`; no journal row. | FR-005, FR-011 | User Story 2 |
| E2E-P3.4-03 | H-AP | `coverClinic()` then `SELF.fetch` `POST /v1/requests` for a capability outside the plan snapshot | Capability outside the plan → 403 `forbidden_capability`. | FR-005 | User Story 2 |
| E2E-P3.4-04 | H-AP | `coverClinic()` with a plan snapshot whose `concurrency_limit` is 16, then 17 concurrent `SELF.fetch` `POST /v1/requests` | 17th concurrent in-flight request (limit 16 from the snapshot) → 429 `concurrency_limited` + `retry_after`, distinct from `rate_limited`. [FR-09, P-11] | FR-005, FR-012 | User Story 2 |
| E2E-P3.4-05 | H-AP | `coverClinic()` then `SELF.fetch` `POST /v1/requests` until the request reaches the allowance, then one more `POST /v1/requests`. Test clock (rule V4). | A31: request reaching the allowance with nothing queued → term ends `exhausted`; next request `allowance_exhausted`; state `exhausted`; no grace. | FR-005, FR-007 | User Story 3 |
| E2E-P3.4-06 | H-AP | `coverClinic()` twice so one term is active and one is queued, then `SELF.fetch` `POST /v1/requests` that reaches the allowance. Test clock (rule V4). | A32: with a queued term, exhaustion activates it at that instant with full allowance; `ends_at` = instant + 1 month. | FR-007 | User Story 3 |
| E2E-P3.4-07 | H-AP | `coverClinic()` twice (active term and queued term), then two concurrent `SELF.fetch` `POST /v1/requests` near the allowance | A34: two concurrent requests near the limit → one exhaustion event; overshoot ≤ w_max − 1; the other is charged to the successor or refused. | FR-007, FR-008 | User Story 3 |
| E2E-P3.4-08 | H-AP | `coverClinic()` then `SELF.fetch` `POST /v1/requests` that cross 75 % and 90 %, then a further request still in a band already crossed | Crossing 75 % and 90 % emits one band event each; no repeats. [A29 platform half, FR-34] | FR-009, FR-012 | User Story 3 |
| E2E-P3.4-09 | H-AP | `coverClinic()` then `SELF.fetch` `POST /v1/requests` whose provider call consumes nothing | Provider consumed nothing → reservation released, `used` unchanged. | FR-004 | User Story 4 |
| E2E-P3.4-10 | H-AP | `coverClinic()` then `SELF.fetch` `POST /v1/requests` left unsettled; test clock advanced past 15 minutes (rule V4); the next `SELF.fetch` `POST /v1/requests` admission; then the late settlement of the first request. Outbox `usage_adjustment` ships to `usage_event` on the existing DO alarm (`runDurableObjectAlarm`). | Reservation unsettled > 15 min → charged at the next admission; the late settlement changes nothing; one `usage_event` (`request_id` dedupe). [NFR-06] | FR-003, FR-011 | User Story 4 |
| E2E-P3.4-11 | H-AP | `SELF.fetch` `POST /v1/requests` replayed with the same `jti` or idempotency key | Replayed `jti`/idempotency key → stored answer; no DO write. | FR-002 | User Story 4 |
| E2E-P3.4-12 | H-AP | `SELF.fetch` `POST /v1/requests` while H-AP makes the per-clinic DO answer `rejected` for version (rule V8) | DO answers `rejected` (version) → client gets 503 `coverage_unknown`. | FR-006 | User Story 2 |

### 2.6 Edge Cases

- Admission returns a stored answer for a replayed `jti` or idempotency key and does not write. Replay and idempotency entries are swept on each write and kept at least the 2-hour horizon. (03 §6.2, 03 §3.1, E2E-P3.4-11)
- A refusal writes nothing unless step 2 or step 3 changed state. An org that was never granted receives 403 `coverage_lapsed` with `coverage_reason` `none` and no journal row. (03 §6.2, 04 §4.2, E2E-P3.4-02)
- Refusal order is `suspended`, then no active or grace term (`allowance_exhausted` when the last term ended by exhaustion, otherwise `coverage_lapsed` with `coverage_reason` `none`, `expired`, `grace_exhausted`, `reversed`, `transferred`, or `transfer_pending`), then `forbidden_capability`, then `concurrency_limited` with `retry_after`. `suspended` is mapped here; the flag is set in P3.6. (03 §6.2, 04 §4.2)
- `allowance_exhausted` is HTTP 403 and replaces `quota_exhausted` for allowance. `coverage_lapsed` is HTTP 403 and replaces `quota_exhausted` on a config miss, with extra field `coverage_reason`. `coverage_unknown` is HTTP 503 with extra field `retry_after`. `suspended` is HTTP 403 and replaces `installation_suspended`. `concurrency_limited` is HTTP 429 with extra field `retry_after`. `rate_limited` stays HTTP 429 and is unchanged. `forbidden_capability` is HTTP 403. (04 §4.2, E2E-P3.4-03, E2E-P3.4-04, E2E-P3.4-05)
- `quota_exhausted` and the `period_reset` supplementary field are removed. (04 §4.2, 04 §6.1 `errors.ts`)
- A DO answer of `rejected` for version is returned to the client as 503 `coverage_unknown`. (E2E-P3.4-12, 04 §4.2)
- The reservation that reaches the allowance ends the active term as `exhausted` in the same DO transaction. The next unheld queued term activates at that instant with its full allowance. With nothing queued, the clinic is `exhausted` and gets no grace. Because the DO serializes admissions, exhaustion is recorded once. (03 §6.3, E2E-P3.4-05, E2E-P3.4-06, E2E-P3.4-07)
- Normal-operation usage beyond a term's allowance is at most `w_max − 1` credits, the one reservation that crosses. That overshoot is charged to the term that exhausted. (03 §6.6, E2E-P3.4-07)
- If the exhausting request later settles as having consumed nothing, its credits are released on the ended term and the term stays ended. (03 §6.3, E2E-P3.4-09)
- A request that consumed provider capacity adds `w` to `used`. A request that consumed nothing releases the reservation. The reservation stays attributed to its `term_id` after that term has ended. (03 §6.2, E2E-P3.4-01, E2E-P3.4-09)
- Reservations older than 15 minutes are charged to their terms at the next admission. That charge emits `usage_adjustment`. A settlement that arrives after the step-2 charge changes nothing in the DO. The journal row and that adjustment share one `usage_event` by insert-or-ignore on `request_id`. (03 §6.2, 03 §3.2, E2E-P3.4-10)
- Crossing 75 % emits one band event and crossing 90 % emits one band event. Each band emits once per term. (E2E-P3.4-08)
- Admission requires at least one credit left before reserving. The concurrency limit and the capabilities used at admission come from the plan snapshot. `hot.reservations` holds at most 16. (03 §6.2, 03 §3.1, 04 §6.1, E2E-P3.4-03, E2E-P3.4-04)

## 3. Requirements

### 3.1 Functional Requirements

- **FR-001**: The per-clinic DO admits on the `hot` row and removes the JSON blob that stayed for live admission. `hot` holds `suspended`, `transferred_out_to`, `awaiting_transfer`, `transfer_pending`, `active_term_id`, `used`, `reserved`, `grace_base_used`, `reservations` (at most 16: id, weight, term id, capability, admitted at), `replay` and `idempotency` entries (swept on each write, kept at least the 2-hour horizon), `band_emitted`, `binding_epoch`, `clinic_seq`, and `next_alarm_at`. The quota DO keeps `EPHEMERAL_HORIZON_MS` and the concurrency constant, and takes the concurrency limit from the plan snapshot. It removes `maybeResetPeriod` and `isQuotaExhausted`. Denial and replay paths do not write unless admission step 2 or step 3 changed state. Step 3 evaluates boundaries at the current time, in order, until no transition applies. These rules are 03 §6.2, 03 §6.3, and the normal-operation row of 03 §6.6. (03 §3.1, 03 §6.2, 04 §6.1, 06 §2 S9)
- **FR-002**: One admission per AI request runs after rate limits. Step 1 returns a stored answer for a replayed `jti` or idempotency key and does not write. (03 §6.2, E2E-P3.4-11)
- **FR-003**: Step 2 charges reservations older than 15 minutes to their terms. A reservation charged in step 2 has no journal row yet, so the DO emits `usage_adjustment` through the outbox, shipped to `usage_event` with that request's `request_id`. A settlement that arrives after the step-2 charge changes nothing in the DO. Insert-or-ignore on the unique `request_id` counts the request once. (03 §6.2, 03 §3.2, E2E-P3.4-10)
- **FR-004**: Step 5 reserves the capability's quota weight `w` against the active or grace term. Admission requires at least one credit left before reserving. Settlement converts the reservation: a request that consumed provider capacity adds `w` to `used`; a request that consumed nothing releases it. The reservation stays attributed to its `term_id` after that term has ended. `creditUsage` settles by reservation id. The journal's `usage_event` carries the same `term_id`. (03 §6.2, 04 §6.1, E2E-P3.4-01, E2E-P3.4-09)
- **FR-005**: Step 4 refuses in this order: `suspended`; then no active or grace term, which is `allowance_exhausted` if the last term ended by exhaustion, otherwise `coverage_lapsed` with `coverage_reason` (`none`, `expired`, `grace_exhausted`, `reversed`, `transferred`, `transfer_pending`); then a capability outside the term's plan, which is `forbidden_capability`; then in-flight requests at the term's concurrency limit, which is `concurrency_limited` with `retry_after`. HTTP status is 403 for `allowance_exhausted`, `coverage_lapsed`, `suspended`, and `forbidden_capability`, and 429 for `concurrency_limited`. `allowance_exhausted` replaces `quota_exhausted` for allowance. `coverage_lapsed` replaces `quota_exhausted` on a config miss. `suspended` replaces `installation_suspended`. `rate_limited` stays 429 and is unchanged. `suspended` is mapped in this unit and set in P3.6. Capabilities and the concurrency limit come from the plan snapshot. (03 §6.2, 04 §4.2, 04 §6.1, E2E-P3.4-02, E2E-P3.4-03, E2E-P3.4-04, E2E-P3.4-05)
- **FR-006**: A DO answer of `rejected` for version is returned to the clinic client as 503 `coverage_unknown`. `coverage_unknown` carries `retry_after`. (04 §4.2, E2E-P3.4-12)
- **FR-007**: Step 6, for an active term, ends the term `exhausted` in the same DO transaction when `used + reserved ≥ allowance`. The next unheld queued term activates at that instant with its full allowance. In the E2E-P3.4-06 case that successor's `ends_at` is the activation instant plus 1 month. With nothing queued, the clinic state is `exhausted` and there is no grace. The next request is `allowance_exhausted`. Exactly one request records exhaustion. If that request later settles as having consumed nothing, its credits are released on the ended term and the term stays ended. (03 §6.2, 03 §6.3, E2E-P3.4-05, E2E-P3.4-06, E2E-P3.4-07)
- **FR-008**: Under normal operation, usage beyond a term's allowance is at most `w_max − 1` credits, the one reservation that crosses. That overshoot is charged to the term that exhausted. Two concurrent requests near the limit produce one exhaustion event; the other request is charged to the successor or refused. (03 §6.6, 03 §6.3, E2E-P3.4-07)
- **FR-009**: Crossing 75 % emits one band event and crossing 90 % emits one band event, once per term per band. Step 7 returns the reservation id, the `term_id`, the plan snapshot (capabilities, max cost class), and the allowance band. (03 §6.2, E2E-P3.4-08)
- **FR-010**: Pipeline stage 3 pre-checks against `coverage_mirror`. Stage 8 takes `term_id`, reservation id, and snapshot from the DO. Stage 15 settlement passes them on. `periodFromIso` and the handoff settlement's `period_start` read from `entitlement` are replaced by the admission's `term_id`. The cost class comes from the term snapshot. `minimumPlanTier` is dropped on the worker, and a manifest `minimumPlanTier` is ignored when present. (04 §6.1)
- **FR-011**: `usage_event.term_id` replaces `period`, with a unique index on `request_id`, so the journal row and a DO `usage_adjustment` for the same request cannot both count. The journal insert is insert-or-ignore on `request_id`. `usage_rollup` dimensions are `{installation_id, term_id}`. The usage_term migration rebuilds `usage_event` that way, keeps the indexes from `20260805120000_f3_retention_indexes.sql`, and resets `usage_rollup` dimensions. The 04 §6.3 file name is indicative (rule S7). `authenticateGetRequest` uses the new verifier. (03 §3.2, 03 §6.2, 04 §6.1, 04 §6.3)
- **FR-012**: The dashboard rejection-rate query counts the 04 §4.2 codes. Guard-rejection counters use those codes. Soft-threshold reads the allowance band from the admission answer. The adapter carries supplementary fields `retry_after` and `coverage_reason`. `quota_exhausted` and `period_reset` are removed. (04 §4.2, 04 §6.1)
- **FR-013**: `GET /v1/capabilities` lists capabilities from the active term's plan snapshot, read from `coverage_mirror` by primary key, so a just-paid clinic sees its plan at once. Capability `discover` reads that mirror snapshot. Tier checks and the `plan:` grant fallback are removed. Entitlement is not read on the request path: `mapEntitlementSnapshot` is removed, and the entitlement tier and status checks are removed. Kill switches stay. The capability check reads the plan snapshot. (04 §4.2, 04 §6.1, E2E-P3.4-01)
- **FR-014**: H-AP `coverClinic()` submits a paid grant signed with the testkit ABO key over `VendorEntrypoint` and replaces `entitleScenario`. Every suite that entitles is migrated to `coverClinic()`. (06 §3 V2, E2E-P3.4-01)

### 3.2 Key Entities

- **`hot`**: The per-clinic DO row written on the request path. This unit admits and settles through the fields in FR-001, on the DO schema consumed from P3.3. (03 §3.1)
- **Admission answer**: Reservation id, `term_id`, plan snapshot (capabilities, max cost class), and allowance band. This is the frozen admission answer. (03 §6.2)
- **`usage_event`**: D1 journal row. `term_id` replaces `period`. Unique index on `request_id`. (03 §3.2, 04 §6.3)
- **`usage_rollup`**: D1 rollup whose dimensions are `{installation_id, term_id}`. (03 §3.2, 04 §6.1)
- **`usage_adjustment`**: Outbox payload this unit emits when step 2 charges a reservation that has no journal row yet. The consumed alarm ships it to `usage_event`. (03 §6.2)

## 4. Constitution Alignment

### 4.1 Architecture & Operations Impact

- **Clinic Fit**: Admission charges one clinic's AI request to that clinic's active term. The concurrency limit and the capability list are the ones snapshotted for that clinic's plan. The unit adds no second clinic product.
- **Layer Placement**: Codebase is `ai-platform` only. No wiring exception is named. Live entries are `SELF.fetch` `POST /v1/requests`, `SELF.fetch` `GET /v1/capabilities`, and `VendorEntrypoint.grant` over the H-AP self service binding (`coverClinic()` / `vendorCall` in `ai-platform/test/system/harness.ts`). The 15-minute case advances the platform test clock and fires the existing DO alarm with `runDurableObjectAlarm` (rule V4). `plan.md` re-runs the constitution check in 02 §7 (rule S12).
- **Data Integrity & Security**: The per-clinic DO is the authority for `hot` admission and settlement. `usage_event` and `usage_adjustment` count a `request_id` once. `/v1/capabilities` reads `coverage_mirror` by primary key. A paid grant still enters through the consumed `grant` method. The JSON blob used for live admission is removed in this unit. (03 §3.1, 03 §6.2, 04 §4.2)
- **Failure Handling**: Never-granted, capability, concurrency, and allowance refusals return the 04 §4.2 codes and write nothing unless step 2 or step 3 changed state (E2E-P3.4-02, E2E-P3.4-03, E2E-P3.4-04, E2E-P3.4-05, 03 §6.2). A DO `rejected` version answer returns 503 `coverage_unknown` (E2E-P3.4-12). A replay returns the stored answer and does not write (E2E-P3.4-11). A reservation older than 15 minutes is charged once (E2E-P3.4-10, 03 §6.2).

## 5. Out of Scope

- Expiry, grace, alarms (→ P3.5); setting suspension (→ P3.6); fallback (→ P3.9); dropping entitlement tables and routes (→ P3.10); load and write budget (→ P3.11).
- No 03 §6.4–§6.5 material, and no 04 §1.3 material.
- No rewrite of the consumed `grant` (paid), `getCoverage`, `listGrants`, `readCoverageEvents`, service-key and plan-version methods, DO schema, or event and receipt shapes (rule S7).
- No module that no test-plan row reaches (rule S8).
- No removal of entitlement tables or the remaining `/control/*` routes, which P3.10 owns (rule S9).
- No second codebase. The Codebase cell is `ai-platform`.

## 6. Success Criteria

### 6.1 Measurable Outcomes

- **SC-001**: E2E-P3.4-01, E2E-P3.4-02, E2E-P3.4-03, E2E-P3.4-04, E2E-P3.4-05, E2E-P3.4-06, E2E-P3.4-07, E2E-P3.4-08, E2E-P3.4-09, E2E-P3.4-10, E2E-P3.4-11, and E2E-P3.4-12 pass in harness H-AP.
- **SC-002**: Every earlier suite stays green (rule S2).
- **SC-003**: CP-B holds: a paid grant over the real entrypoint, then an issuer token, gives a completed live `POST /v1/requests` charged to a term (E2E-P3.4-01, rule S11).

## 7. Assumptions

- The quota DO JSON blob is removed in this unit. Live admission uses the term ledger (rule S9).
- `/control/entitle` no longer admits H-AP test clinics. `coverClinic()` does (rule S9, rule V2).
- Entitlement tables and the remaining `/control/*` routes stay until P3.10 (rule S9).
