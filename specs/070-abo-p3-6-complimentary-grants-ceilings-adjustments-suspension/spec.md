# Feature Specification: Complimentary grants, ceilings, term adjustments and suspension

**Feature Branch**: `ai/070-abo-p3-6-complimentary-grants-ceilings-adjustments-suspension`

**Created**: 2026-10-06

**Status**: Draft

**Input**: P3.6 — Complimentary grants, ceilings, term adjustments and suspension

## 1. Unit Contract

**Implements** — Read: 03 §5.3; 03 §3.2 row `ceiling_policy`; 04 §1.4 (validation step 4, rows `source`, `ceiling_override`, `adjustment`); 04 §1.3 rows grant (complimentary), grant `term_adjustment`, setCeilingPolicy, suspend, resume, inspectCoverage; 03 §6.1 (units, adjustments bullets); 05 §2 rows AL-11, AL-12, AL-19; 05 §8 rows A19, A20, A27.

- Complimentary grant (HP; `month` or `day`; `operator_email` + `reason` required; assertion over the envelope); `ceiling_policy` (versioned, HP `setCeilingPolicy`), per-grant and 90-day-window checks counting adjustments; `ceiling_override` with a second, separate assertion + AL-12; `term_adjustment` (HP: plan change, added allowance, later end only; never queued terms); `suspend`/`resume` (H; DO flag; refused first; calendar runs; AL-19); `inspectCoverage` (H); the FR-92 pilot grant fits the default policy.

**Freezes** — complimentary and adjustment grant semantics; ceiling policy; `suspend`/`resume`/`inspectCoverage`.

**Consumes** — clinic states `grace`/`lapsed` and reasons `expired`/`grace_exhausted` in the snapshot.

**Open questions relied on** — None.

**Spikes** — None.

## 2. User Scenarios & Testing

### 2.1 User Story 1 - Grant complimentary coverage within ceilings (Priority: P1)

An operator applies an HP complimentary term (`month` or `day`) with `operator_email`, `reason`, and an assertion. The platform queues it after a paying clinic's current coverage, rejects a grant over the ceiling, accepts a valid second-assertion override, counts adjustment extensions in the 90-day window, and accepts the 30-day pilot grant under the default policy. An HP `term_adjustment` changes the active term's plan, adds allowance, or moves `ends_at` later. `setCeilingPolicy` writes a version of `ceiling_policy`.

**Why this priority**: Suspension and inspection act on coverage this story grants. The ceiling checks and the adjustment both go through `grant`.

**Independent Test**: E2E-P3.6-01, E2E-P3.6-02, E2E-P3.6-03, E2E-P3.6-04, E2E-P3.6-05, E2E-P3.6-07, and E2E-P3.6-09 in harness H-AP.

**Acceptance Scenarios**:

1. **Given** a paying clinic with current coverage, **When** an operator applies an HP complimentary grant of 14 days (unit `day`) with `operator_email` and `reason`, **Then** the grant is queued after that coverage, and AL-11 is marked for attention with that operator and reason. [A20] (E2E-P3.6-01)
2. **Given** the default per-grant ceiling, **When** a complimentary grant of 365 days is applied, **Then** the result is `exceeds_ceiling`. **When** that grant carries a valid `ceiling_override` with a second, separate assertion, **Then** the result is `applied` and AL-12 is raised. **When** the first assertion is reused as the override, **Then** the grant is rejected. [A27, SR-24] (E2E-P3.6-02)
3. **Given** the 90-day window, **When** complimentary grants of 31 days and 31 days are applied, **Then** both are accepted. **When** a further 1 day is applied, **Then** the result is `exceeds_ceiling`. Adjustment extensions count in that window. (E2E-P3.6-03)
4. **Given** a complimentary grant envelope, **When** `reason` or `operator_email` is missing, **Then** the grant is rejected. [FR-36] (E2E-P3.6-04)
5. **Given** an active term, **When** an HP `term_adjustment` adds 7 days, **Then** `ends_at` moves later. **When** the adjustment would shorten the term, **Then** it is rejected. **When** the adjustment changes the plan, **Then** the next `GET /v1/capabilities` shows that plan. [FR-32] (E2E-P3.6-05)
6. **Given** a clinic with no overlapping paid term yet, **When** an operator applies a 14-day complimentary trial and then a paid grant, **Then** the paid term queues after the trial, with no gap and no overlap. [A19] (E2E-P3.6-07)
7. **Given** the default ceiling policy, **When** an operator applies a pilot complimentary grant of 30 days (unit `day`), **Then** the grant is accepted. [FR-92] (E2E-P3.6-09)

### 2.2 User Story 2 - Suspend and resume a clinic (Priority: P2)

An operator suspends a clinic. Admission answers 403 `suspended` before any other refusal, and the term calendar keeps running. Resume admits the clinic again. Both changes raise AL-19.

**Why this priority**: Admission of the coverage from User Story 1 depends on this flag being refused first.

**Independent Test**: E2E-P3.6-06 in harness H-AP.

**Acceptance Scenarios**:

1. **Given** a clinic with coverage, **When** an operator suspends it, **Then** `POST /v1/requests` answers 403 `suspended` before any other refusal, and the calendar keeps running. **When** the operator resumes it, **Then** a request is admitted. AL-19 is raised for the suspension and for the resume. [FR-74, I-4] (E2E-P3.6-06)

### 2.3 User Story 3 - Inspect a clinic's coverage ledger (Priority: P3)

An operator with an Access JWT reads the clinic's terms, grants, and reservations. The same call without an Access JWT is rejected.

**Why this priority**: Inspection reads the ledger after grants and suspension exist. It is the last story.

**Independent Test**: E2E-P3.6-08 in harness H-AP. Earlier H-AP suites stay green (rule S2).

**Acceptance Scenarios**:

1. **Given** a clinic ledger, **When** an operator calls `inspectCoverage` with an Access JWT, **Then** the result returns that clinic's terms, grants, and reservations. **When** the call has no Access JWT, **Then** it is rejected. (E2E-P3.6-08)

### 2.4 Test plan

| ID | Harness | Entry point | Assertion | Proves | Story |
| --- | --- | --- | --- | --- | --- |
| E2E-P3.6-01 | H-AP | `vendorCall("grant", …)` on `VendorEntrypoint` over the H-AP self service binding (`env.VENDOR` in `ai-platform/test/system/harness.ts`), class HP, with an Access JWT and an assertion; the clinic already has paid coverage. AL-11 observed on the captured `send_email` binding (`getCapturedVendorEmails`, rule V6). | A20: 14-day complimentary grant to a paying clinic → queued after current coverage; AL-11 marked for attention with operator + reason. [A20] | FR-001, FR-002 | User Story 1 |
| E2E-P3.6-02 | H-AP | `vendorCall("grant", …)` for a 365-day complimentary grant; again with `ceiling_override` and a second assertion; again reusing the first assertion as the override. AL-12 on `getCapturedVendorEmails`. | A27: 365-day complimentary grant → `exceeds_ceiling`; with a valid override → `applied` + AL-12; reusing the first assertion as the override → rejected. [SR-24] | FR-003, FR-004 | User Story 1 |
| E2E-P3.6-03 | H-AP | `vendorCall("grant", …)` for two 31-day complimentary grants, then a further 1-day grant; a `term_adjustment` extension is included in the same 90-day window. | 90-day window: 31 + 31 days accepted; a further 1 day → `exceeds_ceiling`; adjustment extensions counted. | FR-003, FR-005 | User Story 1 |
| E2E-P3.6-04 | H-AP | `vendorCall("grant", …)` with `reason` omitted, and with `operator_email` omitted. | Missing `reason` or `operator_email` → rejected. [FR-36] | FR-006 | User Story 1 |
| E2E-P3.6-05 | H-AP | `vendorCall("grant", …)` with `kind = term_adjustment` (`extend_days` 7, then a shortening adjustment, then a plan change). Plan change observed by `SELF.fetch` `GET /v1/capabilities` (`ai-platform/src/worker.ts`). | `term_adjustment`: +7 days moves `ends_at` later; shortening → rejected; a plan change shows in `/v1/capabilities` on the next call. [FR-32] | FR-007 | User Story 1 |
| E2E-P3.6-06 | H-AP | `vendorCall` `suspend` then `resume` on `VendorEntrypoint` (`org_id`, `reason`, Access JWT). While suspended, `SELF.fetch` `POST /v1/requests` and the platform test clock (`setTestClock`). After resume, `SELF.fetch` `POST /v1/requests`. AL-19 on `getCapturedVendorEmails`. | Suspend → 403 `suspended` before any other refusal; calendar keeps running; resume → admitted; AL-19 for both. [FR-74, I-4] | FR-008 | User Story 2 |
| E2E-P3.6-07 | H-AP | `vendorCall("grant", …)` complimentary 14-day trial (HP), then the existing paid `vendorCall("grant", …)`. | A19 platform half: 14-day trial grant, then a paid grant → paid term queues after the trial; no gap or overlap. [A19] | FR-009 | User Story 1 |
| E2E-P3.6-08 | H-AP | `vendorCall` `inspectCoverage` on `VendorEntrypoint` with an Access JWT, then the same call without one. | `inspectCoverage` returns terms, grants and reservations; without an Access JWT → rejected. | FR-010 | User Story 3 |
| E2E-P3.6-09 | H-AP | `vendorCall("grant", …)` complimentary, duration unit `day`, count 30, under the default `ceiling_policy`. | Pilot grant of 30 days (unit `day`) accepted under the default policy. [FR-92] | FR-003, FR-011 | User Story 1 |

### 2.5 Edge Cases

- A complimentary grant over the per-grant ceiling (365 days against ≤ 31 days) is `exceeds_ceiling`. A valid `ceiling_override` with a second, separate assertion applies it and raises AL-12. Reusing the first assertion as that override is rejected. (04 §1.4 step 4, 04 §1.4 row `ceiling_override`, 03 §3.2 `ceiling_policy`, E2E-P3.6-02)
- In a 90-day window, 31 days plus 31 days is accepted (≤ 62 days). A further 1 day is `exceeds_ceiling`. `term_adjustment` extensions count in that window. (03 §3.2 `ceiling_policy`, 04 §1.4 step 4, E2E-P3.6-03)
- A complimentary grant missing `reason` or `operator_email` is rejected. Both are required unless `source.kind` is `paid`. (03 §5.3, 04 §1.4 row `source`, E2E-P3.6-04)
- A `term_adjustment` may move `ends_at` later and must not move it earlier, and it must not touch queued terms. Shortening is rejected. A paid source on `term_adjustment` is rejected at launch. `placement = immediate` is rejected at launch; an immediate upgrade is a `term_adjustment`. (03 §5.3, 03 §6.1 adjustments bullet, E2E-P3.6-05)
- Suspend sets the DO flag. Admission answers 403 `suspended` before any other refusal. The calendar keeps running. Resume admits again. AL-19 fires for both. (E2E-P3.6-06, 05 §2 AL-19)
- `inspectCoverage` without an Access JWT is rejected. (E2E-P3.6-08)
- The default policy accepts a 30-day (unit `day`) pilot grant, which is within the per-grant ceiling of ≤ 31 days. (03 §6.1 units bullet, 03 §3.2 `ceiling_policy`, E2E-P3.6-09)

## 3. Requirements

### 3.1 Functional Requirements

- **FR-001**: A complimentary grant is kind `term` and source `complimentary`, authorization class HP, with an assertion over the envelope. It appends a term for trials, goodwill, corrections, and extensions. `operator_email` and `reason` are required. Complimentary duration unit is `month` or `day`. The `grant` method is idempotent by `grant_id` plus `envelope_sha256` and returns a receipt. A complimentary grant that passes validation is `applied`. (03 §5.3, 03 §6.1 units bullet, 04 §1.3 row `grant`)
- **FR-002**: An HP complimentary grant of 14 days (unit `day`), within the 31-day ceiling, to a paying clinic is queued after existing coverage. AL-11 is raised once by the AI Platform for the applied grant. Non-paid grants are marked for attention. The body carries the decoded operation and its target, including the operator and the reason. (05 §8 A20, 05 §2 AL-11, E2E-P3.6-01)
- **FR-003**: `ceiling_policy` is a versioned D1 table. Allowance is counted in months of the plan's `max_allowance_per_month`. Per complimentary grant: ≤ 31 days and ≤ 1 month of allowance. Per clinic per 90-day window: ≤ 62 days (including adjustment extensions) and ≤ 2 months of allowance (including adjustment additions). Paid grants on the policy: `grace.days` ≤ 7 and `cap_rule = proportional`. The row stores `set_by` and `assertion_sha256`. HP `setCeilingPolicy` takes the ceiling fields and an assertion, returns the policy version, and is idempotent by assertion challenge. (03 §3.2 row `ceiling_policy`, 04 §1.3 row `setCeilingPolicy`)
- **FR-004**: Validation step 4: a complimentary grant must sit within the ceiling policy per grant and per clinic 90-day window, counting earlier complimentary grants and `term_adjustment` additions, unless a valid `ceiling_override` is attached. Otherwise the result is `rejected` with code `exceeds_ceiling`. `ceiling_override` is optional, needs a second, separate assertion, and is separately alerted. A 365-day complimentary grant is `exceeds_ceiling`. With a valid override the result is `applied` and AL-12 is raised once. Reusing the first assertion as the override is rejected. (04 §1.4 step 4, 04 §1.4 row `ceiling_override`, 05 §2 AL-12, 05 §8 A27, E2E-P3.6-02)
- **FR-005**: In one 90-day window, complimentary grants of 31 days and 31 days are accepted. A further 1 day is `exceeds_ceiling`. Adjustment extensions count toward the window. (03 §3.2 row `ceiling_policy`, 04 §1.4 step 4, E2E-P3.6-03)
- **FR-006**: `source.operator_email` and `source.reason` are required unless `source.kind` is `paid`. A complimentary grant missing either is rejected. (03 §5.3, 04 §1.4 row `source`, E2E-P3.6-04)
- **FR-007**: `grant` with `kind = term_adjustment` is class HP. The envelope carries `adjustment` fields `{plan?, add_allowance?, extend_days?}`. It changes the active term's plan version, adds allowance, or extends its end date. It is idempotent by `grant_id` and returns a receipt. A paid source is rejected at launch. Adjustments can move `ends_at` later but never earlier, and never touch queued terms. Adding 7 days moves `ends_at` later. Shortening is rejected. A plan change shows on the next `GET /v1/capabilities`. `placement = immediate` is rejected at launch; the immediate upgrade is this `term_adjustment`. (03 §5.3, 03 §6.1 adjustments bullet, 04 §1.3 row `grant` with `kind = term_adjustment`, 04 §1.4 row `adjustment`, E2E-P3.6-05)
- **FR-008**: `suspend` and `resume` are class H. Each takes `access_jwt`, `org_id`, and `reason`, returns a snapshot, and is idempotent by target state. Suspend sets the clinic DO flag. Admission then answers 403 `suspended` before any other refusal, and the calendar keeps running. Resume admits the clinic. AL-19 is raised once for the suspension and once for the resume. (04 §1.3 rows `suspend`, `resume`, 05 §2 AL-19, E2E-P3.6-06)
- **FR-009**: A 14-day complimentary trial is a complimentary term. A following paid grant queues after that trial, so there is no gap and no overlap. (05 §8 A19, E2E-P3.6-07)
- **FR-010**: `inspectCoverage` is class H, takes `access_jwt` and `org_id`, and returns the full DO ledger: terms, grants, and reservations. Without an Access JWT the call is rejected. (04 §1.3 row `inspectCoverage`, E2E-P3.6-08)
- **FR-011**: A pilot complimentary grant of 30 days (unit `day`) is accepted under the default policy. Complimentary terms may use `day` for the FR-92 pilot grant, bounded by the ceilings. (03 §6.1 units bullet, 03 §3.2 row `ceiling_policy`, E2E-P3.6-09)

### 3.2 Key Entities

- **`ceiling_policy`**: Versioned platform D1 policy. Per complimentary grant: ≤ 31 days and ≤ 1 month of allowance. Per clinic per 90-day window: ≤ 62 days, including adjustment extensions, and ≤ 2 months of allowance, including adjustment additions. Paid grants: `grace.days` ≤ 7 and `cap_rule = proportional`. Allowance is counted in months of the plan's `max_allowance_per_month`. Writers store `set_by` and `assertion_sha256`. `setCeilingPolicy` returns the policy version. (03 §3.2 row `ceiling_policy`, 04 §1.3 row `setCeilingPolicy`)
- **Complimentary `term` grant**: Source `complimentary`, class HP, duration `month` or `day`, with `operator_email`, `reason`, and an assertion. Optional `ceiling_override` with a second assertion. (03 §5.3, 04 §1.3 row `grant`, 04 §1.4 rows `source`, `ceiling_override`)
- **`term_adjustment`**: Source `complimentary`, class HP. `adjustment` is `{plan?, add_allowance?, extend_days?}`. It changes the active term only, and only by a later `ends_at`, added allowance, or a new plan version. (03 §5.3, 03 §6.1 adjustments bullet, 04 §1.4 row `adjustment`)
- **Clinic suspension flag**: The DO flag `suspend` sets and `resume` clears. While it is set, admission answers 403 `suspended` before any other refusal, and the calendar keeps running. (E2E-P3.6-06, 04 §1.3 rows `suspend`, `resume`)

## 4. Constitution Alignment

### 4.1 Architecture & Operations Impact

- **Clinic Fit**: An operator grants one clinic complimentary days or months inside the ceiling, adjusts that clinic's active term, or suspends that clinic. The ceilings are per grant and per clinic per 90-day window. The unit adds no second clinic product.
- **Layer Placement**: Codebase is `ai-platform` only. No wiring exception is named. Live entries are `VendorEntrypoint` methods over the H-AP self service binding (`vendorCall` / `env.VENDOR` in `ai-platform/test/system/harness.ts`) and `SELF.fetch` `GET /v1/capabilities` and `POST /v1/requests` (`ai-platform/src/worker.ts`). Paid grants used as setup call the existing `VendorEntrypoint.grant`. `plan.md` re-runs the constitution check in 02 §7 (rule S12).
- **Data Integrity & Security**: Complimentary and adjustment grants are class HP and carry an assertion. `operator_email` and `reason` are required on complimentary grants. A ceiling override needs a second, separate assertion. `ceiling_policy` stores `set_by` and `assertion_sha256`. `suspend`, `resume`, and `inspectCoverage` are class H and take `access_jwt`. (04 §1.3, 04 §1.4, 03 §3.2)
- **Failure Handling**: Over-ceiling complimentary grants are `rejected` with `exceeds_ceiling` unless a valid override is attached (E2E-P3.6-02, E2E-P3.6-03). A missing `reason` or `operator_email`, a shortened term, a reused override assertion, and `inspectCoverage` without an Access JWT are rejected (E2E-P3.6-04, E2E-P3.6-05, E2E-P3.6-02, E2E-P3.6-08). A suspended clinic's `POST /v1/requests` answers 403 `suspended` before any other refusal (E2E-P3.6-06).

## 5. Out of Scope

- Voids (→ P3.7); console relays (→ P4.8).
- No material from outside this unit's Read spans.
- No rewrite of the consumed snapshot states `grace`/`lapsed` or reasons `expired`/`grace_exhausted` (rule S7).
- No module that no test-plan row reaches (rule S8).
- No void path, which P3.7 owns, and no console relay, which P4.8 owns. Entitlement, plan, and invoice tables and `/control/*` routes stay until P3.10 (rule S9). Transfer-source grants stay with P3.8 (03 §5.3, D1). Kill-switch changes that share AL-19 stay with P3.10 (05 §2 AL-19, D1).
- No second codebase. The Codebase cell is `ai-platform`.

## 6. Success Criteria

### 6.1 Measurable Outcomes

- **SC-001**: E2E-P3.6-01, E2E-P3.6-02, E2E-P3.6-03, E2E-P3.6-04, E2E-P3.6-05, E2E-P3.6-06, E2E-P3.6-07, E2E-P3.6-08, and E2E-P3.6-09 pass in harness H-AP.
- **SC-002**: Every earlier suite stays green (rule S2).

## 7. Assumptions

- Voids stay with P3.7 (rule S9).
- Console relays stay with P4.8 (rule S9).
- Entitlement, plan, and invoice tables and `/control/*` routes stay until P3.10 (rule S9).
