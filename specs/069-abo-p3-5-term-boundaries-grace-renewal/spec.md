# Feature Specification: Term boundaries, grace and renewal

**Feature Branch**: `ai/069-abo-p3-5-term-boundaries-grace-renewal`

**Created**: 2026-10-06

**Status**: Draft

**Input**: P3.5 — Term boundaries, grace and renewal

## 1. Unit Contract

**Implements** — Read: 03 §5.4 (rows queued→active, active `ends_at`, grace rows, grant during grace); 03 §5.7 (`grace`, `lapsed`); 03 §6.1 (end date, scale); 03 §6.4; 03 §6.7 (alarm bullet); 03 §6.8; 05 §8 rows A9–A11.

- Alarm at the next boundary (`setAlarm` only when it moves); boundary loop on alarm and on admission (step 3); expiry with a successor (`expired`, successor starts at the old `ends_at`); expiry → grace (`grace_ends_at`, `grace_base_used`, cap ⌈A × grace_days ÷ term days⌉); `grace_exhausted`; lapse; renewal during grace (calendar from the old `ends_at`, grace term ends `renewed`); no grace after exhaustion; scaled grace windows; mirror `hard_stop_at`.

**Freezes** — clinic states `grace`/`lapsed` and reasons `expired`/`grace_exhausted` in the snapshot.

**Consumes** — admission answer (reservation, `term_id`, snapshot, band); clinic denial codes of 04 §4.2. CP-B.

**Open questions relied on** — None.

**Spikes** — None.

## 2. User Scenarios & Testing

### 2.1 User Story 1 - Apply the term boundary (Priority: P1)

The per-clinic DO runs the boundary loop on its alarm and on admission. A renewal paid while the current term is active queues. At that term's end date the successor becomes active with a full allowance from the old end date. With nothing queued, the term enters grace, stays admissible within the grace cap, and lapses at `grace_ends_at`. Using up the grace cap lapses the clinic for `grace_exhausted`. If the alarm does not fire, the next admission applies the boundary. Staging scale compresses the same boundaries. The alarm ships activate, end, and grace-start events, and the mirror records `hard_stop_at`.

**Why this priority**: A queued successor, grace, and a later grant all depend on this boundary loop.

**Independent Test**: E2E-P3.5-01, E2E-P3.5-02, E2E-P3.5-03, E2E-P3.5-06, E2E-P3.5-07, and E2E-P3.5-08 in harness H-AP, with the test clock and `runDurableObjectAlarm` (rule V4).

**Acceptance Scenarios**:

1. **Given** monthly term T1 from 1 Mar 10:00 to 1 Apr 10:00, **When** a renewal is paid on 27 Mar (5 days early), **Then** T2 is queued and T1's allowance is unchanged. **When** the alarm runs at 1 Apr 10:00, **Then** T1 ends `expired` and T2 is active from 1 Apr 10:00 to 1 May 10:00 with a full allowance. [A9] (E2E-P3.5-01)
2. **Given** an active term and nothing queued, **When** the end date is reached unpaid, **Then** the clinic is in grace. **When** a request is admitted within the grace cap, **Then** it is admitted and the usage stays on that term. **When** `grace_ends_at` is reached, **Then** the clinic is `lapsed` and admission answers `coverage_lapsed` with reason `expired`. The harness includes no ABO. [A10] (E2E-P3.5-02)
3. **Given** a term in grace, **When** a reservation takes the last of the grace allowance, **Then** the term ends `grace_exhausted`, the clinic is `lapsed`, and admission refuses with reason `grace_exhausted`. [I-6] (E2E-P3.5-03)
4. **Given** a boundary that is already due and an alarm that did not run, **When** the next admission runs, **Then** that admission evaluates the boundary and refuses on time. [FR-23, FM-12 catch-up] (E2E-P3.5-06)
5. **Given** the staging `DURATION_SCALE`, **When** a monthly term and its grace window reach their boundaries on the test clock, **Then** the monthly term lasts 30 minutes, grace lasts about 7 minutes, and the boundaries fall at those scaled times. [NFR-07] (E2E-P3.5-07)
6. **Given** a term that activates, ends, or starts grace, **When** the alarm ships, **Then** events exist for activate, end, and grace start, and mirror `hard_stop_at` equals `ends_at` while active and `grace_ends_at` while in grace. (E2E-P3.5-08)

### 2.2 User Story 2 - Grant during grace or after lapse (Priority: P2)

A paid grant during grace starts the new term's calendar at the old `ends_at` and ends the grace term `renewed`. Grace usage stays on the grace term. A lapsed clinic paid later receives a new term that starts at that payment.

**Why this priority**: Both grants run after User Story 1 has entered grace or lapse.

**Independent Test**: E2E-P3.5-04 and E2E-P3.5-05 in harness H-AP. Earlier H-AP suites stay green (rule S2).

**Acceptance Scenarios**:

1. **Given** T1 ended 1 Mar 10:00 and is in grace, **When** a grant is paid on day 3 of grace (4 Mar in the worked example), **Then** the new term is active now with `calendar_start` equal to the old `ends_at` (1 Mar 10:00, ending 1 Apr 10:00), the grace term ends `renewed`, and grace usage stays on T1. [I-5] (E2E-P3.5-04)
2. **Given** T1 ended 1 Mar 10:00, grace ran until 8 Mar 10:00, and the clinic is `lapsed`, **When** payment arrives two months later at 1 May 14:00, **Then** the new term is active from 1 May 14:00 to 1 Jun 14:00. [A11] (E2E-P3.5-05)

### 2.3 Test plan

| ID | Harness | Entry point | Assertion | Proves | Story |
| --- | --- | --- | --- | --- | --- |
| E2E-P3.5-01 | H-AP | `coverClinic()` → `VendorEntrypoint.grant` over the H-AP self service binding (`vendorCall` in `ai-platform/test/system/harness.ts`) while T1 is active; test clock to T1 `ends_at`; `runDurableObjectAlarm` on the per-clinic DO (`alarm()` in `ai-platform/src/worker.ts`) | A9: renewal paid 5 days early queues; T1 allowance unchanged; at T1's end T2 is active with a full allowance from the old end date. [A9] | FR-001, FR-002 | User Story 1 |
| E2E-P3.5-02 | H-AP | `coverClinic()` once; test clock to `ends_at`; `runDurableObjectAlarm` and `SELF.fetch` `POST /v1/requests` within the grace cap; test clock to `grace_ends_at`; `runDurableObjectAlarm`; `SELF.fetch` `POST /v1/requests`. No ABO worker in the harness. | A10: end date unpaid → grace; admitted within the cap; at `grace_ends_at` → lapsed, `coverage_lapsed reason expired`; no ABO in the harness. [A10] | FR-003, FR-004 | User Story 1 |
| E2E-P3.5-03 | H-AP | `coverClinic()`; enter grace by the boundary loop; `SELF.fetch` `POST /v1/requests` until a reservation takes the last of the grace allowance | Grace cap consumed → `grace_exhausted`; refused with that reason. [I-6] | FR-005 | User Story 1 |
| E2E-P3.5-04 | H-AP | `coverClinic()` to open grace, then `coverClinic()` on day 3 of grace (`VendorEntrypoint.grant`) | Grant on day 3 of grace → new term `calendar_start` = old `ends_at`; grace usage stays on T1. [I-5] | FR-006 | User Story 2 |
| E2E-P3.5-05 | H-AP | `coverClinic()`; test clock through grace to lapse; test clock two months later; `coverClinic()` (`VendorEntrypoint.grant`) | A11: lapsed clinic paid 2 months later → new term starts now. [A11] | FR-007 | User Story 2 |
| E2E-P3.5-06 | H-AP | Test clock past a due boundary without `runDurableObjectAlarm`; then `SELF.fetch` `POST /v1/requests` | Alarm suppressed → the next admission evaluates the boundary and refuses on time. [FR-23, FM-12 catch-up] | FR-008 | User Story 1 |
| E2E-P3.5-07 | H-AP | Staging `DURATION_SCALE` on the platform worker binding; test clock; `runDurableObjectAlarm` and `SELF.fetch` `POST /v1/requests` at the scaled boundaries | Staging `DURATION_SCALE`: monthly term 30 min, grace about 7 min, boundaries at the scaled times. [NFR-07] | FR-009 | User Story 1 |
| E2E-P3.5-08 | H-AP | Boundary transitions via `runDurableObjectAlarm` (and admission where the transition is on the request); read shipped `coverage_event` rows and `coverage_mirror.hard_stop_at` | Events for activate, end and grace start; mirror `hard_stop_at` = `ends_at` (active) or `grace_ends_at` (grace). | FR-001, FR-010 | User Story 1 |

### 2.4 Edge Cases

- A queued term whose predecessor reaches its end date becomes active with `starts_at` and `calendar_start` equal to that predecessor's `ends_at`. The predecessor ends `expired`. (03 §5.4, 03 §6.8, E2E-P3.5-01)
- An active term that reaches `ends_at` with no unheld queued term enters grace. `grace_ends_at = ends_at + grace_days`. `grace_base_used = used`. Grace allowance is min(allowance − used, `grace_cap`), and `grace_cap` is ⌈allowance × grace_days ÷ term length in days⌉. Grace usage is charged to that same term. (03 §6.4, E2E-P3.5-02)
- Grace ends at `grace_ends_at` with `end_reason` `expired`, or when the grace allowance is used with `end_reason` `grace_exhausted`. Either way the clinic becomes `lapsed` and admission answers `coverage_lapsed`, with reason `expired` or `grace_exhausted`. (03 §5.4, 03 §5.7, 03 §6.4, E2E-P3.5-02, E2E-P3.5-03)
- There is no grace after exhaustion. (03 §6.4)
- A grant during grace sets the new term's `calendar_start` to the grace term's `ends_at`, ends the grace term `renewed`, and leaves grace usage on the grace term. (03 §5.4, 03 §6.8, E2E-P3.5-04)
- A payment after lapse starts the new term at activation, at that payment's time. (03 §6.8, 05 §8 A11, E2E-P3.5-05)
- `setAlarm` is called only when the next alarm time moves. The alarm time is the earliest of the next boundary (`ends_at`, `grace_ends_at`) or a pending outbox. (03 §6.7)
- When the alarm does not run, the next admission evaluates the boundary and refuses on time. (E2E-P3.5-06)
- Staging `DURATION_SCALE` maps 1 month to 30 minutes and 1 day to 1 minute. Durations, grace windows, and allowance rules are computed in unscaled units and then scaled. Production has no scale. A monthly term under that scale lasts 30 minutes, and grace lasts about 7 minutes. (03 §6.1, 06 §3 V4, E2E-P3.5-07)
- Mirror `hard_stop_at` is the active term's `ends_at`, or `grace_ends_at` while the clinic is in grace. `coverage_mirror` is replaced only by a higher `(binding_epoch, clinic_seq)`. (03 §6.7, E2E-P3.5-08)

## 3. Requirements

### 3.1 Functional Requirements

- **FR-001**: The alarm is set to the earliest of the next boundary (`ends_at`, `grace_ends_at`) or a pending outbox. `setAlarm` is called only when that time moves. The boundary loop runs on that alarm and on admission at step 3, in order, until no transition applies. The alarm ships the outbox to D1 (`coverage_event`, `grant_ledger`, `grant_void`, `coverage_mirror`, `usage_event` for `usage_adjustment`, `platform_alert`) with `INSERT OR IGNORE` on event id or `request_id`, then deletes the shipped rows. `coverage_mirror` is replaced only by a higher `(binding_epoch, clinic_seq)`. (03 §6.7, 06 §4 Implements)
- **FR-002**: When the active term reaches `ends_at` and a successor is queued, the active term ends `expired` and the successor activates. The successor's `starts_at` and `calendar_start` are the predecessor's `ends_at`. `ends_at = add(calendar_start, duration_unit, duration_count)`. For months, that is the same day-of-month and time in UTC, clamped to the last day of a shorter month. For days, that is exact multiples of 24 hours. A renewal paid while the current term is active queues, and the current allowance is unchanged. At the current term's end the new term is active with a full allowance from the old end date. In the worked example, T1 is monthly from 1 Mar 10:00 to 1 Apr 10:00, the renewal is paid on 27 Mar, and at 1 Apr 10:00 T2 runs until 1 May 10:00 with a full allowance. (03 §5.4, 03 §6.1, 03 §6.8, 05 §8 A9, E2E-P3.5-01)
- **FR-003**: When the active term reaches `ends_at` with no unheld queued term, the clinic state is `grace`: the last term passed its end date and grace is running. `grace_ends_at = ends_at + grace_days`. The DO records `grace_base_used = used`. Grace allowance = min(allowance − used, `grace_cap`), where `grace_cap` = ⌈allowance × grace_days ÷ term length in days⌉. Grace usage is charged to the same term. There is no grace after exhaustion. (03 §5.4, 03 §5.7, 03 §6.4, E2E-P3.5-02)
- **FR-004**: During grace, a request within the grace allowance is admitted. At `grace_ends_at` the grace term ends `expired`, the clinic becomes `lapsed`, and admission answers `coverage_lapsed` with reason `expired`. The DO enters grace at the end date and ends it at `grace_ends_at` on its own alarm and on admission. The harness includes no ABO. `lapsed` means grace ended, or the grace allowance was used, with nothing queued. (03 §5.4, 03 §5.7, 03 §6.4, 05 §8 A10, E2E-P3.5-02)
- **FR-005**: A reservation that takes the last of the grace allowance ends the term `grace_exhausted`. The clinic becomes `lapsed`. Admission answers `coverage_lapsed` with reason `grace_exhausted`. (03 §5.4, 03 §6.4, E2E-P3.5-03)
- **FR-006**: A grant during grace makes the new term active with `calendar_start` equal to the grace term's `ends_at`, and the grace term ends `renewed`. Grace usage stays on the grace term. In the worked example, T1 ends 1 Mar 10:00, payment on 4 Mar (day 3 of grace) makes T2 active now with `calendar_start` 1 Mar 10:00 and `ends_at` 1 Apr 10:00. (03 §5.4, 03 §6.1, 03 §6.8, E2E-P3.5-04)
- **FR-007**: A lapsed clinic that pays later receives a new term that starts at activation, at the payment time, with `ends_at` from that `calendar_start` by the end-date rule. In the worked example, T1 ends 1 Mar 10:00, grace runs to 8 Mar 10:00, and payment at 1 May 14:00 makes T2 active from 1 May 14:00 to 1 Jun 14:00. (03 §6.1, 03 §6.8, 05 §8 A11, E2E-P3.5-05)
- **FR-008**: When the alarm does not run, the next admission evaluates the boundary and refuses on time. (E2E-P3.5-06)
- **FR-009**: Staging `DURATION_SCALE` maps 1 month to 30 minutes and 1 day to 1 minute. Every duration, grace window, and allowance rule is computed in unscaled units and then scaled. Production has no scale. Under the staging scale a monthly term lasts 30 minutes, grace lasts about 7 minutes, and boundaries fall at those scaled times. Local H-AP verifies this with the test clock. (03 §6.1, 06 §3 V4, E2E-P3.5-07)
- **FR-010**: Activate, end, and grace-start changes emit events, shipped through the alarm outbox. Mirror `hard_stop_at` equals the active term's `ends_at`, or `grace_ends_at` while the clinic is in grace. (03 §6.7, E2E-P3.5-08)

### 3.2 Key Entities

- **Term boundary**: The active term's `ends_at` and, once grace has started, `grace_ends_at`, `grace_base_used`, and the grace allowance on that same term. End reasons this unit records on these transitions are `expired`, `grace_exhausted`, and `renewed`. (03 §5.4, 03 §6.4)
- **Clinic coverage snapshot**: States `grace` and `lapsed`, with reasons `expired` and `grace_exhausted`. This is the frozen snapshot slice. (03 §5.7)
- **`coverage_mirror.hard_stop_at`**: `ends_at` while the clinic is active, and `grace_ends_at` while the clinic is in grace. (E2E-P3.5-08)

## 4. Constitution Alignment

### 4.1 Architecture & Operations Impact

- **Clinic Fit**: One clinic's paid term ends, enters grace, or accepts a renewal on that clinic's own calendar. The allowance and the grace cap are that term's. The unit adds no second clinic product.
- **Layer Placement**: Codebase is `ai-platform` only. No wiring exception is named. Live entries are the per-clinic DO `alarm()` (`ai-platform/src/worker.ts`, fired in H-AP by `runDurableObjectAlarm`), `SELF.fetch` `POST /v1/requests`, and `VendorEntrypoint.grant` over the H-AP self service binding (`coverClinic()` / `vendorCall` in `ai-platform/test/system/harness.ts`). Time advances through the platform test clock (rule V4). `plan.md` re-runs the constitution check in 02 §7 (rule S12).
- **Data Integrity & Security**: The per-clinic DO applies the boundary in its single-threaded loop. Grace usage stays on the grace term. A renewal grant still enters through the consumed paid `grant` method. `coverage_mirror` is replaced only by a higher `(binding_epoch, clinic_seq)`. (03 §6.4, 03 §6.7)
- **Failure Handling**: If the alarm does not run, the next admission evaluates the boundary and refuses on time (E2E-P3.5-06). At `grace_ends_at`, or when the grace allowance is used, admission answers `coverage_lapsed` with reason `expired` or `grace_exhausted` (E2E-P3.5-02, E2E-P3.5-03, 03 §6.4).

## 5. Out of Scope

- Reversal ends (→ P3.7); fallback reads of `hard_stop_at` (→ P3.9).
- No material outside this unit's Read spans.
- No rewrite of the consumed admission answer (reservation, `term_id`, snapshot, band) or of the clinic denial codes of 04 §4.2 (rule S7).
- No module that no test-plan row reaches (rule S8).
- No reversal-end path, which P3.7 owns, and no fallback read of `hard_stop_at`, which P3.9 owns (rule S9). Entitlement tables and `/control/*` routes stay until P3.10 (rule S9).
- No second codebase. The Codebase cell is `ai-platform`.

## 6. Success Criteria

### 6.1 Measurable Outcomes

- **SC-001**: E2E-P3.5-01, E2E-P3.5-02, E2E-P3.5-03, E2E-P3.5-04, E2E-P3.5-05, E2E-P3.5-06, E2E-P3.5-07, and E2E-P3.5-08 pass in harness H-AP.
- **SC-002**: Every earlier suite stays green (rule S2).

## 7. Assumptions

- Reversal ends of a term stay with P3.7 (rule S9).
- Fallback reads of `hard_stop_at` stay with P3.9 (rule S9).
- Entitlement tables and `/control/*` routes stay until P3.10 (rule S9).
