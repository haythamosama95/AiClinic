# Feature Specification: Read-time status, notices and billing status

**Feature Branch**: `ai/088b-abo-p5-2b-read-time-status-notices`

**Created**: 2026-10-07

**Status**: Draft

**Input**: P5.2b — Read-time status, notices and billing status

## 1. Unit Contract

**Implements** — Read: 04 §3.1 (rows `get_ai_status`, `get_ai_billing_status`); 04 §3.2; 04 §3.3 (grace, lapse, and the rest of the read-time clock); 03 §4 (row `clinic_ai_coverage`, the columns status reads).

- `get_ai_status` read-time computation + the closed notice vocabulary as records `{code, audience: member, channel: in_app}`, with `grace_days_left` (non-negative integer; whole 24-hour days from `now` until `grace_ends_at`, floored) only when `code` is `in_grace`, and with `days_left` the whole 24-hour days from `now` until the projection `ends_at`, floored (null when the row or `ends_at` is absent or `now >= ends_at`; separate from `grace_days_left`; a null `days_left` does not raise `ends_soon`); `get_ai_status` `reason` null for returned `active`, `grace`, or `suspended`, `none` when the row is absent, `expired` when stored `active` or `grace` becomes `lapsed` at read time, otherwise the stored column written by P5.2a; `get_ai_billing_status` (administrator; a non-administrator returns `FORBIDDEN_ROLE` with no status payload; flat fields `plan_display_name`, `starts_at`, `ends_at`, `grace_ends_at`, `allowance`, `used`, `queued_count`, `held_count`, `subscription_ref`, `abo_base_url`; no `remaining` field, remaining is `allowance - used` when both are non-null, otherwise null; those plan, date, and allowance values are null when the projection row is absent or the column is null; subscription ref computed in SQL to the package vector).

**Freezes** — status RPC results and notice codes (consumed by P6.x).

**Consumes** — P5.2a: the pull, the projection, and `request_ai_status_refresh`. CP-D.

**Open questions relied on** — OQ-5: "Default: accepted as described in rule V4." The E2E harness is H-FS at the compressed scale in that rule.

**Spikes** — None.

## Clarifications

### Session 2026-10-08

- Q: How do the H-FS scenarios establish the projection and pass the grace, lapse, and stale clocks? → A: Seed `ai_internal.clinic_ai_coverage` and `ai_internal.feed_state` in SQL, and do not start the platform or ABO workers. Set `ends_at`, `grace_ends_at`, and `last_success_at` relative to database `now()` so those predicates hold on the read. Do not sleep the 2-minute stale window or a calendar day. `[implementation choice — no §citation]`
- Q: How are the two RPCs laid out in the backend? → A: One new migration. One `auth_internal` reader returns the shared status view. `public.get_ai_status` and `public.get_ai_billing_status` are the `SECURITY DEFINER` wrappers. Each wrapper rejects a missing or unsupported `p_contract_version` before any role check. The billing wrapper then allows only `administrator` and adds the flat billing fields. `[implementation choice — no §citation]`
- Q: What do the H-FS assertions require for `notices[]` order and for `as_of`? → A: Assert `notices[]` by code, and do not require an array order. Take database `now()` on the same database immediately before the call and immediately after the response, and assert `as_of` lies between those two timestamps, including when the projection row is absent. When `event_at`, `applied_at`, or `last_success_at` are seeded to other times, assert `as_of` is not those values. `[implementation choice — no §citation]`

## 2. User Scenarios & Testing

### 2.1 User Story 2 - Read-time status and notices (Priority: P1)

Every clinic member calls `get_ai_status(p_contract_version)`. The returned state, `reason`, `days_left`, and `notices[]` are computed at read time from the stored projection and `now`. Grace and lapse follow the stored dates while the platform and the ABO are stopped. Notice codes are the closed vocabulary of records. Staff receive no prices, payments, or references.

**Why this priority**: `get_ai_billing_status` returns this same status view. The notice records and `days_left` this story freezes are what later desktops consume.

**Independent Test**: E2E-P5.2-03, E2E-P5.2-04, and E2E-P5.2-11 in harness H-FS.

**Acceptance Scenarios**:

1. **Given** the platform and the ABO are stopped, the tenant's stored state is `active` or `grace`, and `queued_count` is not greater than 0 once `now` passes `ends_at`, **When** a member calls `get_ai_status` and the stored dates pass, **Then** the state becomes `grace` while `now < grace_ends_at` and then `lapsed`. `reason` is null while the result is `grace`, and `expired` when that clock returns `lapsed`. `notices[]` includes `in_grace` with `grace_days_left` during grace, and `lapsed` once lapsed. After `feed_state.last_success_at` is more than 2 minutes old, `stale` is true and `notices[]` includes `status_stale`. The result carries `contract_version` equal to the version the request used. (E2E-P5.2-03) [A10, A28, SR-13]
2. **Given** `queued_count = 0` and `days_left` is 7, 3, or 1 or fewer, **When** staff call `get_ai_status`, **Then** `notices[]` includes `ends_soon`, and the result has no prices, payments, or references. A null `days_left` does not raise `ends_soon`. (E2E-P5.2-04) [FR-61]
3. **Given** the projection band is 90, **When** every membership role calls `get_ai_status`, **Then** each result includes `allowance_low` as `{code, audience: member, channel: in_app}`. (E2E-P5.2-11) [A29]

### 2.2 User Story 3 - Administrator billing status (Priority: P2)

An administrator calls `get_ai_billing_status(p_contract_version)` and receives the status view plus the flat billing fields. A member whose role is not `administrator` receives `FORBIDDEN_ROLE` and no status payload. `subscription_ref` is computed in SQL and equals the package vector and the ABO and platform values for that org.

**Why this priority**: The billing RPC returns the status view from User Story 2 and adds the administrator fields.

**Independent Test**: E2E-P5.2-04 and E2E-P5.2-09 in harness H-FS. Every earlier suite stays green (rule S2).

**Acceptance Scenarios**:

1. **Given** a member whose membership role is not `administrator`, **When** they call `get_ai_billing_status`, **Then** the `rpc_result` has `success = false`, `error_code = 'FORBIDDEN_ROLE'`, and no status payload. (E2E-P5.2-04) [FR-61]
2. **Given** the package subscription-reference vector and the ABO and platform subscription refs for the org, **When** SQL computes `subscription_ref` and an administrator calls `get_ai_billing_status`, **Then** the SQL value equals the package vector and those ABO and platform values, and the success `data` carries that `subscription_ref` with the other flat billing fields. (E2E-P5.2-09) [FR-66]

### 2.3 Test plan

| ID | Harness | Entry point | Assertion | Proves | Story |
| --- | --- | --- | --- | --- | --- |
| E2E-P5.2-03 | H-FS (compressed scale, rule V4) | H-FS Node runner (`e2e/fullstack/`, supabase-js) stops the platform and ABO workers, then calls PostgREST `public.get_ai_status(p_contract_version)`. | A10/A28: platform and ABO stopped; stored dates pass → status goes to grace, then lapsed, on time; `reason` is null in grace and `expired` on that clock lapse; `stale` + `status_stale` after 2 min. The accepted version is echoed on `contract_version`. [SR-13] | FR-001, FR-002, FR-003, FR-005, FR-008 | User Story 2 |
| E2E-P5.2-04 | H-FS (compressed scale, rule V4) | H-FS runner calls PostgREST `public.get_ai_status(p_contract_version)` and `public.get_ai_billing_status(p_contract_version)` as staff. | `ends_soon` at 7, 3 and 1 days only when `queued_count = 0`; a null `days_left` does not raise `ends_soon`; staff `get_ai_status` has no prices, payments, or references; staff `get_ai_billing_status` → `FORBIDDEN_ROLE` with no status payload. A missing or unsupported `p_contract_version` on either RPC is `CONTRACT_VERSION_UNSUPPORTED` before authentication and before any write. [FR-61] | FR-001, FR-004, FR-005, FR-006, FR-008 | User Story 2, User Story 3 |
| E2E-P5.2-09 | H-FS (compressed scale, rule V4) | H-FS runner compares the SQL `subscription_ref` returned by PostgREST `public.get_ai_billing_status(p_contract_version)` with `subscriptionRef` in `packages/vendor-contracts` and with the local ABO and platform values. | SQL subscription ref equals the package vector and the ABO/platform values. The accepted version is echoed on `contract_version`. [FR-66] | FR-006, FR-007, FR-008 | User Story 3 |
| E2E-P5.2-11 | H-FS (compressed scale, rule V4) | H-FS runner calls PostgREST `public.get_ai_status(p_contract_version)` for every membership role against a projection whose band is 90. | Band 90 event → `allowance_low` for every role. [A29] | FR-001, FR-005 | User Story 2 |

### 2.4 Edge Cases

- No projection row: `state = none`, `available = false`, `reason = none`, `days_left` is null, and each copied billing field is null. (04 §3.3, 04 §3.1, 04 §3.2)
- Suspended wins over the stored state: `available = false`, `state = suspended`, `reason = null`. A suspended row does not take `expired` from the clock. (04 §3.3)
- Stored `active` with `now` past `ends_at` and `queued_count > 0` stays `active`. `reason` stays null. (04 §3.3)
- Stored `grace` stays `grace` while `now < grace_ends_at`, then becomes `lapsed` with `reason = expired`. (04 §3.3)
- Any other stored state is unavailable as stored. A snapshot already stored as `lapsed` with `grace_exhausted` keeps that stored `reason` after `grace_ends_at`. (04 §3.3)
- `days_left` and `grace_days_left` are whole 24-hour days, floored, so a remaining partial day is `0`. `days_left` counts toward `ends_at`. It is null when the row is absent, `ends_at` is null, or `now >= ends_at`. Null does not raise `ends_soon`. (04 §3.2)
- `ends_soon` is raised when `days_left` is 7, 3, or 1 or fewer, and only with `queued_count = 0`. (04 §3.2, E2E-P5.2-04)
- `allowance_low` is raised for band 75 or 90. E2E-P5.2-11 covers band 90 for every role. (04 §3.2)
- `grace_days_left` is present only on `in_grace`. Every other notice code omits it. The same records are returned to every member. (04 §3.2)
- The read does not update `clinic_ai_coverage.reason`. (04 §3.3, 03 §4)
- Platform and ABO stopped: grace, then lapse, still follow the stored dates; after 2 minutes without `feed_state.last_success_at`, `stale` and `status_stale`. (E2E-P5.2-03, 04 §3.3)
- Staff `get_ai_billing_status` returns `FORBIDDEN_ROLE` and no status payload. (04 §3.1, E2E-P5.2-04)
- There is no `remaining` field. Remaining is `allowance - used` when both are non-null, including when `used` exceeds `allowance`, and null when either is null. (04 §3.1)
- A missing or unsupported `p_contract_version` on `get_ai_status` or `get_ai_billing_status` answers `CONTRACT_VERSION_UNSUPPORTED` before authentication and before any write. (04 §3.1, 06 §3 V5, E2E-P5.2-04)

## 3. Requirements

### 3.1 Functional Requirements

- **FR-001**: `get_ai_status(p_contract_version)` is `SECURITY DEFINER` in `public`, delegating to `auth_internal`, keyed on `current_org_id()`, for every member. It returns `available`, `state` (§1.7 states, as §3.3 computes them), `reason`, `days_left`, `band`, `notices[]`, `next_change_at`, `as_of`, `stale`, and `platform_base_url`. It returns no prices, payments, or references. (04 §3.1 row `get_ai_status`, 04 §3.2)
- **FR-002**: For the tenant's projection row and `now`: no row yields `state = none`, `available = false`; suspended yields `available = false`, `state = suspended`, and that step wins over the stored state; stored `active` stays `active` while `now < ends_at`, stays `active` when `now` is past `ends_at` and `queued_count > 0`, becomes `grace` while `now < grace_ends_at`, and otherwise becomes `lapsed`; stored `grace` stays `grace` while `now < grace_ends_at`, then becomes `lapsed`; any other stored state is unavailable as stored. `available` is true exactly for `active` and `grace`. `next_change_at` is the next of `ends_at` and `grace_ends_at` that is still in the future. `stale` is true when `feed_state.last_success_at` is more than 2 minutes old. A lapse shows on time from stored dates alone when the platform and the ABO are down. (04 §3.3, E2E-P5.2-03)
- **FR-003**: `reason` is null when the returned state is `active`, `grace`, or `suspended`. It is `none` when the projection row is absent. It is `expired` when stored `active` or stored `grace` becomes `lapsed` at read time. Otherwise it is the stored `clinic_ai_coverage.reason` written by P5.2a: `none`, `expired`, `grace_exhausted`, `exhausted`, `reversed`, `transferred`, or `transfer_pending`. The read does not update that column. `get_ai_billing_status` returns this same `reason`. (04 §3.2, 04 §3.3, 03 §4 row `clinic_ai_coverage`)
- **FR-004**: `days_left` is the whole 24-hour days from `now` until the projection `ends_at`, floored, so a remaining partial day is `0`. It is null when the row is absent, `ends_at` is null, or `now >= ends_at`. A null `days_left` does not raise `ends_soon`. It is separate from `grace_days_left`. `get_ai_billing_status` returns this same `days_left`. (04 §3.2)
- **FR-005**: Each element of `notices[]` is `{code, audience, channel}`, and `in_grace` also carries `grace_days_left`. `audience` is `member`. `channel` is `in_app`. `grace_days_left` is present only when `code` is `in_grace`: a non-negative integer, the whole 24-hour days from `now` until `grace_ends_at`, floored. The closed codes are `ends_soon` (`days_left` is 7, 3, or 1 or fewer, null does not match, and `queued_count = 0`), `in_grace` (state `grace`), `allowance_low` (band 75 or 90), `allowance_exhausted` (state `exhausted`), `lapsed` (state `lapsed`), `ended_reversed` (state `reversed`), `suspended` (suspended flag), and `status_stale` (`stale = true`). The same records are returned to every member. `get_ai_billing_status` returns this same `notices[]`. (04 §3.2, E2E-P5.2-04, E2E-P5.2-11)
- **FR-006**: `get_ai_billing_status(p_contract_version)` is `SECURITY DEFINER` in `public`, delegating to `auth_internal`, keyed on `current_org_id()`, for membership role `administrator` only. Success `data` is the §3.2 status view plus flat fields `plan_display_name`, `starts_at`, `ends_at`, `grace_ends_at`, `allowance`, `used`, `queued_count`, `held_count`, `subscription_ref`, and `abo_base_url`. There is no `remaining` field. Remaining is `allowance - used` when both are non-null, including when `used` exceeds `allowance`, and null when either is null. When the projection row is absent, or a copied column is null, that JSON value is null. A caller whose membership role is not `administrator` returns `rpc_result` with `success = false`, `error_code = 'FORBIDDEN_ROLE'`, and no status payload. (04 §3.1 row `get_ai_billing_status`, E2E-P5.2-04)
- **FR-007**: `subscription_ref` is computed in SQL so that it equals the `packages/vendor-contracts` subscription-reference vector (`subscriptionRef`) and the subscription ref the local ABO and platform return for the same org. (04 §3.1, Implements, E2E-P5.2-09)
- **FR-008**: `get_ai_status` and `get_ai_billing_status` take `p_contract_version integer` as the first argument. Results use the `rpc_result` envelope extended with `contract_version`, set to the version the request used. A version outside the backend's accepted range, including a missing version, answers `CONTRACT_VERSION_UNSUPPORTED` before authentication and before any write. (04 §3.1, 03 §4 row `clinic_ai_coverage`, 06 §3 V5, E2E-P5.2-04)

### 3.2 Key Entities

- **Notice record**: `{code, audience, channel}`, plus `grace_days_left` only when `code` is `in_grace`. `audience` is `member`. `channel` is `in_app`. `code` is one value from the closed vocabulary in FR-005.
- **Status view**: The `get_ai_status` result fields in FR-001, including `notices[]`, `days_left`, and `reason`. `get_ai_billing_status` returns this same view.
- **Billing status fields**: Flat `data` fields `plan_display_name`, `starts_at`, `ends_at`, `grace_ends_at`, `allowance`, `used`, `queued_count`, `held_count`, `subscription_ref`, and `abo_base_url` on administrator success.

This unit defines no new table. It reads `ai_internal.clinic_ai_coverage` and `ai_internal.feed_state.last_success_at` from the P5.2a projection.

## 4. Constitution Alignment

### 4.1 Architecture & Operations Impact

- **Codebase**: backend. The unit row names no wiring exception. `plan.md` re-runs the constitution check in 02 §7 (rule S12).
- **Clinic Fit**: A clinic member reads AI status for the active organisation from the shared backend. An administrator reads the billing fields on that same status. Staff receive no prices. Grace and lapse are status results from stored dates.
- **Layer Placement**: Read-time status, the notice vocabulary, `days_left`, the `reason` mapping, and `get_ai_billing_status` live in PostgreSQL, reached through Supabase RPCs. The Flutter app is outside this unit. The pull, the projection, and `request_ai_status_refresh` stay the consumed P5.2a contract. H-FS is the harness these scenarios run in.
- **Data Integrity & Security**: Coverage rows stay in non-exposed `ai_internal` and are reached only through `SECURITY DEFINER` RPCs keyed on `current_org_id()`. `get_ai_billing_status` requires membership role `administrator`. Status reads do not rewrite `clinic_ai_coverage.reason`. An unsupported contract version does not write. (03 §4, 04 §3.1, 04 §3.3)
- **Failure Handling**: With the platform and the ABO stopped, stored dates still move status to grace and then lapsed, and `stale` plus `status_stale` follow when `feed_state.last_success_at` is more than 2 minutes old. Staff billing status returns `FORBIDDEN_ROLE` and no status payload. (04 §3.3, 04 §3.1, E2E-P5.2-03, E2E-P5.2-04)

## 5. Out of Scope

- The puller, projection writes, `request_ai_status_refresh`, the availability drop, and the R-4 spike (→ P5.2a).
- No Do-not-read material. The unit row names none.
- No rewrite of the consumed P5.2a contracts: the pull, the projection, and `request_ai_status_refresh`.
- No module this unit's E2E scenarios do not reach (rule S8). The P2.2 and package-half P2.1 exception does not apply. `get_ai_status` and `get_ai_billing_status` are reached by PostgREST from the H-FS runner. The subscription ref is the value that RPC returns, compared with the existing package vector.
- No S9 path owned by a later unit. Desktop rendering of notice codes is P6.x, which consumes these frozen RPC results. This unit does not keep a transitional path.
- No second codebase beyond backend. H-FS (`e2e/fullstack/`) is the harness named for these scenarios (06 §3 V1).

## 6. Success Criteria

### 6.1 Measurable Outcomes

- **SC-001**: E2E-P5.2-03, E2E-P5.2-04, E2E-P5.2-09, and E2E-P5.2-11 are green in harness H-FS.
- **SC-002**: Every earlier suite stays green (rule S2).

## 7. Assumptions

- OQ-5 default: the H-FS compressed scale in rule V4 is accepted (1 month = 60 s, 1 day = 2 s, keeping the 30:1 ratio). These scenarios run on that scale. Units are computed unscaled, then scaled.
- Rule S9: this unit names no transitional path. The puller, projection writes, `request_ai_status_refresh`, the availability drop, and the R-4 spike stay with P5.2a.
