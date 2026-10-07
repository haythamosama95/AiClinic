# Feature Specification: Coverage feed puller, status projection and status RPCs

**Feature Branch**: `ai/088-abo-p5-2-coverage-feed-puller-status-projection`

**Created**: 2026-10-07

**Status**: Draft

**Input**: P5.2 — Coverage feed puller, status projection and status RPCs

## 1. Unit Contract

**Implements** — Read: 04 §4.1; 03 §4 (rows `clinic_ai_coverage`, `feed_state` + ordering rule); 04 §3.1 (rows `get_ai_status`, `get_ai_billing_status`, `request_ai_status_refresh`; "Removed", the availability part); 04 §3.2; 04 §3.3; 05 §5.4; 01 §7 row R-4 (spike); 05 §4 rows FM-10, FM-11.

- enable `pg_cron` + `pg_net`
- the two-phase 30 s pull (fresh feed token, checks for status, version, `after` = cursor and ascending order; abandon responses older than 5 min)
- projection upsert by the ordering rule
- `feed_state` failure counting
- `request_ai_status_refresh` (administrator, ≤ 1 per 10 s per tenant, immediate pull)
- `get_ai_status` read-time computation + the closed notice vocabulary
- `get_ai_billing_status` (administrator; subscription ref computed in SQL to the package vector; `abo_base_url`)
- drop `get_ai_availability`/`set_ai_availability` and `ai.availability`
- projection rebuild by cursor reset
- R-4 spike locally (confirmed in P8.1)

**Freezes** — status RPC results and notice codes (consumed by P6.x). CP-D.

**Consumes** — P3.9: the HTTP feed contract; `/v1/coverage` response; `feedConsumerHealth`. P5.1: the unit row states no Outputs / freezes line.

**Open questions relied on** — OQ-3: "If the staging Supabase project is not available, P5.2 stops at its spike step." OQ-5: "accepted as described in rule V4."

**Spikes** — R-4 (01 §7, rule S6): pg_cron at 30 s with two-phase pg_net — overlapping runs, response size limits, growth of `cron.job_run_details`. The unit spikes this locally; hosted confirmation is P8.1. Fallback if the spike fails (05 §10 Spike-dependent items, via rule S6): a longer pull interval within the bound. Under the OQ-3 default, if the staging Supabase project is not available, P5.2 stops at its spike step.

## Clarifications

### Session 2026-10-07

- Q: Where do the pull, the projection, and the status RPCs live, and how does an accepted refresh start the pull? → A: One new migration under `backend/supabase/migrations/` with a fresh timestamp. Do not edit the availability migrations named in 04 §3.1. That migration drops `get_ai_availability`, `set_ai_availability`, and `ai.availability`. `get_ai_status`, `get_ai_billing_status`, and `request_ai_status_refresh` stay `SECURITY DEFINER` in `public` and delegate to `auth_internal`. One `auth_internal` function is the `pg_cron` command and the function an accepted `request_ai_status_refresh` calls, so one two-phase step runs immediately. The plan names that function. It calls the existing P5.1 feed mint and reads `ai.platform_base_url`. No second puller and no public grant on the pull function. `[implementation choice — no §citation]`
- Q: How do the H-FS scenarios prove the pull, stale, grace, and the 10-second refresh without multi-minute sleeps? → A: The runner executes the same SQL the cron job runs, so `pg_net` reaches the platform on the host, and it checks that `cron.job` is scheduled at 30 seconds. It does not sleep 60 seconds, 2 minutes, or 5 minutes. Stale reads set `feed_state.last_success_at` older than 2 minutes. The disabled-job case also sets the platform `feed_consumer.last_pull_at` 5 minutes back so `feedConsumerHealth` shows that lag. Grace, lapse, and `ends_soon` come from snapshot `ends_at` and `grace_ends_at` placed against the database clock. The throttled refresh is a second call made at once. A later accepted refresh sets `status_refresh.requested_at` to 10 seconds ago instead of sleeping. These scenarios stay in `e2e/fullstack/`, not the backend SQL job. `[implementation choice — no §citation]`
- Q: How does E2E-P5.2-06 make the platform answer an unsupported feed version? → A: For that pull only, the backend sends a feed version the running platform rejects, then the test restores the setting. The answer is the real `GET /v1/feed/coverage`. No feed double and no new refusal code. `[implementation choice — no §citation]`
- Q: How does E2E-P5.2-09 compare the subscription ref? → A: The runner reads `subscriptionRef` from `packages/vendor-contracts` at run time and compares it to the SQL value and to the local ABO and platform values for the same org. The committed test does not copy the vector. `[implementation choice — no §citation]`
- Q: How do ordering, band 90, cursor rebuild, and the stopped-Supabase payment reach the live pull? → A: Epoch, sequence, and band 90 events arrive on the live coverage feed. The pull function applies them. The test does not write the winning `clinic_ai_coverage` row itself. Cursor rebuild sets `feed_state.cursor` to 0 as the database owner, then runs that same pull. E2E-P5.2-10 stops local Supabase while the local ABO and platform finish the payment, starts Supabase again, and runs the pull. No new E2E id. `[implementation choice — no §citation]`

## 2. User Scenarios & Testing

### 2.1 User Story 1 - Coverage pull and projection (Priority: P1)

The backend pull job reads the platform coverage feed and stores one projection row per clinic. A grant that the platform has applied shows up on `get_ai_status` within about 60 seconds. The job applies an event only when `(binding_epoch, clinic_seq)` is newer than the stored pair, counts a failed page without moving the cursor, and can rebuild every clinic by resetting the cursor to 0 and pulling again.

**Why this priority**: Status reads, notices, and the administrator refresh all read this projection. CP-D is this path.

**Independent Test**: E2E-P5.2-01 in harness H-FS.

**Acceptance Scenarios**:

1. **Given** a grant applied on the platform, **When** the 30 s pull runs, **Then** within about 60 s `get_ai_status` is available/active. The pull sends the backend's current feed version; the accepted page carries that `contract_version` on `Aip-Contract-Version` and in the body. The `get_ai_status` result carries `contract_version` for the version the request used. (E2E-P5.2-01, 04 §4.1, 04 §3.1, 06 §3 V5) [FR-62, FR-63, A2]
2. **Given** a stored projection at epoch 1, `clinic_seq` 9, **When** events arrive from epoch 2, `clinic_seq` 1, **Then** those events replace the stored snapshot and older events are ignored. (E2E-P5.2-05) [A14]
3. **Given** the platform answers an unsupported feed version, **When** the pull handles that page, **Then** the cursor is kept, the failure is counted, and status is stale. Nothing is written to the projection. (E2E-P5.2-06, 04 §4.1, 06 §3 V5) [FM-25]
4. **Given** the pull job is disabled for 5 min, **When** status is read and the platform is asked `feedConsumerHealth`, **Then** status is stale and `feedConsumerHealth` shows the lag. (E2E-P5.2-07) [FM-10]
5. **Given** `feed_state.cursor` reset to 0, **When** the pull replays the feed, **Then** the projection is identical. (E2E-P5.2-08) [RC-04]
6. **Given** Supabase is stopped during a payment, **When** the ABO and platform still provision and Supabase returns, **Then** status catches up after restart. (E2E-P5.2-10) [FM-11]

### 2.2 User Story 2 - Read-time status and notices (Priority: P2)

Every clinic member calls `get_ai_status`. The state is computed from the stored dates at read time, so grace and lapse appear on time while the platform and the ABO are stopped. Notice codes are a closed vocabulary. Staff receive no prices. A staff call to `get_ai_billing_status` is forbidden.

**Why this priority**: Members see availability from the projection story. The notice codes this story returns are the frozen vocabulary later desktops render.

**Independent Test**: E2E-P5.2-03 in harness H-FS.

**Acceptance Scenarios**:

1. **Given** the platform and the ABO are stopped and the stored dates pass, **When** a member calls `get_ai_status`, **Then** status goes to grace, then lapsed, on time, and `stale` plus `status_stale` appear after 2 min. (E2E-P5.2-03) [A10, A28, SR-13]
2. **Given** `queued_count = 0` and `days_left` is 7, 3, or 1, **When** staff call `get_ai_status`, **Then** the notice is `ends_soon`, and the result has no prices. **Given** a staff member, **When** they call `get_ai_billing_status`, **Then** the call is forbidden. (E2E-P5.2-04) [FR-61]
3. **Given** a band 90 event in the projection, **When** every role calls `get_ai_status`, **Then** the notice is `allowance_low`. (E2E-P5.2-11) [A29]

### 2.3 User Story 3 - Administrator billing status (Priority: P3)

An administrator calls `get_ai_billing_status` and receives the status view plus plan, dates, allowance figures, `queued_count`, `held_count`, `subscription_ref`, and `abo_base_url`. The subscription reference is computed in SQL and matches the package vector and the ABO and platform values.

**Why this priority**: The billing view depends on the same projection and on the status computation. It stands alone as the administrator RPC.

**Independent Test**: E2E-P5.2-09 in harness H-FS.

**Acceptance Scenarios**:

1. **Given** the package subscription-ref vector and the ABO and platform values for the org, **When** SQL computes the subscription ref, **Then** the SQL value equals the package vector and those ABO and platform values. (E2E-P5.2-09) [FR-66]

### 2.4 User Story 4 - Administrator status refresh (Priority: P4)

An administrator calls `request_ai_status_refresh` and the backend starts an immediate pull. A second call for the same tenant within 10 seconds is throttled. The RPC takes `p_contract_version` and returns `contract_version` on success.

**Why this priority**: The refresh starts the pull from story 1 on demand. It is the write among the status RPCs.

**Independent Test**: E2E-P5.2-02 in harness H-FS. Every earlier suite stays green (rule S2).

**Acceptance Scenarios**:

1. **Given** an administrator, **When** they call `request_ai_status_refresh`, **Then** an immediate pull starts and the result carries `contract_version` for the version the request used. **Given** a second call for that tenant within 10 s, **When** it is made, **Then** it is throttled. A missing version, or a version outside the accepted range, answers `CONTRACT_VERSION_UNSUPPORTED` before authentication and before any pull is requested. (E2E-P5.2-02, 04 §3.1, 06 §3 V5)

### 2.5 Test plan

| ID | Harness | Entry point | Assertion | Proves | Story |
| --- | --- | --- | --- | --- | --- |
| E2E-P5.2-01 | H-FS (compressed scale, rule V4) | H-FS Node runner (`e2e/fullstack/`, supabase-js). Live chain: platform coverage feed `GET /v1/feed/coverage` reached by the pg_cron / pg_net pull, then PostgREST `public.get_ai_status(p_contract_version)`. | Grant applied on the platform → within about 60 s `get_ai_status` is available/active. The pull sends the backend's current feed version; the accepted page echoes it on `Aip-Contract-Version` and `contract_version`. The `get_ai_status` result carries `contract_version`. [FR-62, FR-63, A2] | FR-001, FR-006, FR-014, FR-016 | User Story 1 |
| E2E-P5.2-02 | H-FS (compressed scale, rule V4) | H-FS Node runner calls PostgREST `public.request_ai_status_refresh(p_contract_version)`. | `request_ai_status_refresh` → immediate pull; a second call within 10 s → throttled. Success echoes `contract_version`. A missing or unsupported version is `CONTRACT_VERSION_UNSUPPORTED` before authentication and before any pull is requested. | FR-005, FR-016 | User Story 4 |
| E2E-P5.2-03 | H-FS (compressed scale, rule V4) | H-FS runner stops the platform and ABO workers; PostgREST `public.get_ai_status(p_contract_version)` reads stored dates. | A10/A28: platform and ABO stopped; stored dates pass → status goes to grace, then lapsed, on time; `stale` + `status_stale` after 2 min. [SR-13] | FR-007, FR-008, FR-015 | User Story 2 |
| E2E-P5.2-04 | H-FS (compressed scale, rule V4) | H-FS runner calls PostgREST `public.get_ai_status(p_contract_version)` and `public.get_ai_billing_status(p_contract_version)` as staff. | `ends_soon` at 7, 3 and 1 days only when `queued_count = 0`; staff `get_ai_status` has no prices; staff `get_ai_billing_status` → forbidden. [FR-61] | FR-006, FR-008, FR-009 | User Story 2 |
| E2E-P5.2-05 | H-FS (compressed scale, rule V4) | pg_cron / pg_net pull of `GET /v1/feed/coverage`, applying events into `ai_internal.clinic_ai_coverage`. | A14: events from epoch 2, `clinic_seq` 1 replace epoch 1, seq 9; older events ignored. | FR-003 | User Story 1 |
| E2E-P5.2-06 | H-FS (compressed scale, rule V4) | pg_cron / pg_net pull; the platform feed answers an unsupported `contract_version`. | The platform answers an unsupported feed version → cursor kept, failure counted, stale. The projection is not written. [FM-25] | FR-002, FR-014 | User Story 1 |
| E2E-P5.2-07 | H-FS (compressed scale, rule V4) | pg_cron job disabled; PostgREST `public.get_ai_status`; consumed `VendorEntrypoint.feedConsumerHealth` on the platform worker. | FM-10: job disabled 5 min → stale; platform `feedConsumerHealth` shows the lag. | FR-004, FR-015 | User Story 1 |
| E2E-P5.2-08 | H-FS (compressed scale, rule V4) | SQL sets `ai_internal.feed_state.cursor` to 0; the pg_cron / pg_net pull replays `GET /v1/feed/coverage`. | Cursor reset to 0 → identical projection. [RC-04] | FR-012 | User Story 1 |
| E2E-P5.2-09 | H-FS (compressed scale, rule V4) | H-FS runner compares the SQL subscription ref from `public.get_ai_billing_status` with `subscriptionRef` in `packages/vendor-contracts` and with the local ABO and platform values. | SQL subscription ref equals the package vector and the ABO/platform values. [FR-66] | FR-010 | User Story 3 |
| E2E-P5.2-10 | H-FS (compressed scale, rule V4) | H-FS runner stops Supabase during a payment the local ABO and platform still complete; after Supabase returns, the pg_cron / pg_net pull runs and PostgREST `public.get_ai_status` is read. | FM-11: Supabase stopped during a payment → the ABO and platform still provision; status catches up after restart. | FR-015 | User Story 1 |
| E2E-P5.2-11 | H-FS (compressed scale, rule V4) | pg_cron / pg_net pull applies a band 90 event; H-FS runner calls PostgREST `public.get_ai_status(p_contract_version)` for every membership role. | Band 90 event → `allowance_low` for every role. [A29] | FR-008 | User Story 2 |

### 2.6 Edge Cases

- The platform answers `contract_version_unsupported` on the feed: the puller keeps the cursor, counts the failure, and status is stale. The projection is not written. (E2E-P5.2-06, 04 §4.1) [FM-25]
- A feed response older than 5 minutes is abandoned and requested again. (04 §4.1, 01 §7 row R-4)
- On any pull failure the cursor stays and the failure is counted. (04 §4.1)
- Epoch 2, `clinic_seq` 1 replaces epoch 1, `clinic_seq` 9. An older pair is ignored. (E2E-P5.2-05, 03 §4 ordering rule) [A14]
- The pull job is disabled for 5 min: status is stale, dates still evaluate at read time, and `feedConsumerHealth` shows the lag. (E2E-P5.2-07, 05 §4 FM-10)
- Supabase is down during a payment: the ABO and platform still provision; status catches up when Supabase returns. (E2E-P5.2-10, 05 §4 FM-11)
- Platform and ABO are stopped and stored dates pass: status goes to grace, then lapsed, on time; after 2 min, `stale` and `status_stale`. (E2E-P5.2-03, 04 §3.3) [A10, A28, SR-13]
- No projection row: `state = none`, `available = false`. (04 §3.3)
- Suspended projection: `available = false`, `state = suspended`. (04 §3.3)
- `ends_soon` at 7, 3, and 1 days only when `queued_count = 0`. Staff `get_ai_status` has no prices. Staff `get_ai_billing_status` is forbidden. (E2E-P5.2-04, 04 §3.1, 04 §3.2) [FR-61]
- A second `request_ai_status_refresh` within 10 s for the same tenant is throttled. (E2E-P5.2-02, 04 §3.1)
- A missing `p_contract_version`, or a version outside the accepted range, on `request_ai_status_refresh` answers `CONTRACT_VERSION_UNSUPPORTED` before authentication and before a pull is requested. (E2E-P5.2-02, 04 §3.1, 06 §3 V5)
- No RPC lets a clinic user write status. `get_ai_availability` and `set_ai_availability` are dropped, and `ai.availability` is removed. (04 §3.1 Removed)
- Cursor reset to 0 replays the feed into the same projection. (E2E-P5.2-08, 05 §5.4) [RC-04]

## 3. Requirements

### 3.1 Functional Requirements

- **FR-001**: `pg_cron` and `pg_net` are enabled. Every 30 s the backend runs a two-phase pg_net pull of `GET /v1/feed/coverage?after=<feed_seq>&limit=<≤200>` with a fresh feed token and `Aip-Contract-Version` set to the backend's current feed version. A 30 s cycle applies an event within about 60 s of it reaching platform D1, inside the 2-minute bound. The feed token is the internal mint from P5.1; this unit does not change that mint. (04 §4.1, Implements, E2E-P5.2-01)
- **FR-002**: When `feed_state.pending_request_id` has a response in `net._http_response`, the pull requires HTTP status 200 and a `contract_version` the backend accepts, requires `after` equal to the stored cursor, and requires ascending `feed_seq`. A `contract_version_unsupported` answer raises the stale alert, keeps the cursor, and counts the failure, and the projection is not written. Status is stale. Any other failure also keeps the cursor and counts the failure. A response older than 5 minutes is abandoned and requested again. The next `net.http_get` uses a fresh feed token and the current feed version, and its id is stored. When `has_more` is true, the next cycle continues from the new cursor. (04 §4.1, E2E-P5.2-06)
- **FR-003**: Each accepted event upserts `ai_internal.clinic_ai_coverage` only when `(binding_epoch, clinic_seq)` is greater than the stored pair. A re-created identity starts a higher epoch, so its first events win even though `clinic_seq` restarts at 1. The row lives in the non-exposed `ai_internal` schema and is reached only through definer RPCs. Fields are `organization_id`, `installation_id`, `binding_epoch`, `clinic_seq`, `state`, `term_ref`, `plan_display_name`, `starts_at`, `ends_at`, `grace_ends_at`, `allowance`, `used`, `band`, `queued_count`, `held_count`, `suspended`, `event_at`, `applied_at`. The row has no prices and no provider data. On success the cursor becomes `next_after` and `last_success_at` becomes now. (03 §4 row `clinic_ai_coverage` and ordering rule, 04 §4.1, E2E-P5.2-05)
- **FR-004**: `ai_internal.feed_state` is a singleton: `cursor`, `pending_request_id`, `pending_since`, `last_success_at`, `consecutive_failures`. Failures increment the failure count. The row is in non-exposed `ai_internal` and is reached only through definer RPCs. (03 §4 row `feed_state`, 04 §4.1, E2E-P5.2-06, E2E-P5.2-07)
- **FR-005**: `request_ai_status_refresh(p_contract_version)` is a `SECURITY DEFINER` RPC in `public`, delegating to `auth_internal`, keyed on `current_org_id()`, for membership role `administrator` only. It returns `{requested_at}` and starts an immediate pull. At most one call per 10 seconds per tenant is accepted; a second call within 10 s is throttled. (04 §3.1 row `request_ai_status_refresh`, E2E-P5.2-02)
- **FR-006**: `get_ai_status(p_contract_version)` is a `SECURITY DEFINER` RPC in `public` for every member, keyed on `current_org_id()`. It returns `available`, `state`, `reason`, `days_left`, `band`, `notices[]`, `next_change_at`, `as_of`, `stale`, `platform_base_url`. It returns no prices, payments, or references. (04 §3.1 row `get_ai_status`, 04 §3.2, E2E-P5.2-01, E2E-P5.2-04)
- **FR-007**: For the tenant's projection row and the current time `now`: no row yields `state = none`, `available = false`; suspended yields `available = false`, `state = suspended`; stored `active` stays `active` while `now < ends_at`, stays `active` when `now` is past `ends_at` and `queued_count > 0`, becomes `grace` while `now < grace_ends_at`, and otherwise becomes `lapsed`; stored `grace` stays `grace` while `now < grace_ends_at`, then becomes `lapsed`; any other stored state is unavailable as stored. `available` is true exactly for `active` and `grace`. `next_change_at` is the next of `ends_at` and `grace_ends_at` that is still in the future. `stale` is true when `feed_state.last_success_at` is more than 2 minutes old. A lapse shows on time from stored dates alone when every vendor service is down. (04 §3.3, E2E-P5.2-03)
- **FR-008**: Notice codes are a closed vocabulary: `ends_soon` when `days_left` is 7, 3, or 1 or fewer, with `queued_count = 0`; `in_grace` when state is `grace`, carrying grace days left; `allowance_low` when the band is 75 or 90; `allowance_exhausted` when state is `exhausted`; `lapsed` when state is `lapsed`; `ended_reversed` when state is `reversed`; `suspended` when the suspended flag is set; `status_stale` when `stale = true`. E2E-P5.2-04 requires `ends_soon` at 7, 3, and 1 days only when `queued_count = 0`. A band 90 event yields `allowance_low` for every role. (04 §3.2, E2E-P5.2-04, E2E-P5.2-11)
- **FR-009**: `get_ai_billing_status(p_contract_version)` is a `SECURITY DEFINER` RPC in `public` for membership role `administrator` only, keyed on `current_org_id()`. It returns the status view plus plan, dates, allowance figures, `queued_count`, `held_count`, `subscription_ref`, and `abo_base_url`. A staff call is forbidden. (04 §3.1 row `get_ai_billing_status`, E2E-P5.2-04)
- **FR-010**: `subscription_ref` is computed in SQL so that it equals the `packages/vendor-contracts` subscription-ref vector (`subscriptionRef`) and the subscription ref the local ABO and platform return for the same org. (04 §3.1, Implements, E2E-P5.2-09)
- **FR-011**: `get_ai_availability` and `set_ai_availability` are dropped (latest definitions `20260821120000_fix_get_ai_availability_security_definer.sql:4`, `20260905120100_set_ai_availability_rpc.sql:67`, `20260905120400_fix_set_ai_availability_created_by.sql:4`), and `ai.availability` is removed. No RPC lets a clinic user write status. (04 §3.1 Removed, Implements)
- **FR-012**: Projection rebuild resets `feed_state.cursor` to 0. `coverage_event` is never purged, so the replay reproduces every clinic's latest snapshot. The projection after replay matches the projection from before the reset. (05 §5.4, E2E-P5.2-08)
- **FR-013**: The R-4 spike records whether pg_cron at 30 s with two-phase pg_net meets the freshness bound locally (overlapping runs, response size limits, growth of `cron.job_run_details`). Hosted confirmation is P8.1. If the spike fails, the fallback is a longer pull interval within the bound. If the staging Supabase project is not available, P5.2 stops at its spike step. (01 §7 row R-4, rule S6, 05 §10, 06 §6 OQ-3, Implements)
- **FR-014**: The feed channel accepts the backend's current feed version and treats the page `contract_version` and `Aip-Contract-Version` as the echo of that version. An unsupported feed version is refused before the projection write: the cursor is kept, the failure is counted, and status is stale. (04 §4.1, 06 §3 V5, E2E-P5.2-01, E2E-P5.2-06)
- **FR-015**: When the pull stops (pg_cron or pg_net), status becomes stale, enforcement on the platform is unchanged, and dates still evaluate at read time. When Supabase is down, payments already made still provision on the ABO and platform, and status catches up after Supabase returns. (05 §4 rows FM-10, FM-11, E2E-P5.2-07, E2E-P5.2-10)
- **FR-016**: `get_ai_status`, `get_ai_billing_status`, and `request_ai_status_refresh` take `p_contract_version integer` as the first argument. Results use `rpc_result` extended with `contract_version`, answered in the version the request used. A version outside the backend's accepted range answers `CONTRACT_VERSION_UNSUPPORTED`. On `request_ai_status_refresh`, a missing version or a version outside the accepted range is that refusal before authentication and before any pull is requested, so nothing is written. (04 §3.1 intro, 06 §3 V5, E2E-P5.2-02)

### 3.2 Key Entities

- **`ai_internal.clinic_ai_coverage`**: Per-tenant coverage projection. One stored snapshot, replaced only when `(binding_epoch, clinic_seq)` is greater. No prices and no provider data.
- **`ai_internal.feed_state`**: Singleton pull cursor: `cursor`, `pending_request_id`, `pending_since`, `last_success_at`, `consecutive_failures`.
- **Status RPC results**: `get_ai_status`, `get_ai_billing_status`, and `request_ai_status_refresh`, plus the closed notice codes. Frozen for P6.x.

## 4. Constitution Alignment

### 4.1 Architecture & Operations Impact

- **Codebase**: backend. The unit row names no wiring exception. `plan.md` re-runs the constitution check in 02 §7 (rule S12).
- **Clinic Fit**: A clinic member reads AI availability for the active organisation from the shared backend. An administrator reads the billing view and can request an immediate pull. Staff do not receive prices. The pull serves a clinic-scale Supabase, not a separate billing service.
- **Layer Placement**: The pull, the projection, the ordering rule, the read-time status, and the notice vocabulary live in PostgreSQL, reached through Supabase RPCs and `pg_cron` / `pg_net`. The Flutter app is outside this unit. The platform feed and `feedConsumerHealth` stay the consumed P3.9 contract. The feed-token mint stays the P5.1 function. H-FS is the harness these scenarios run in.
- **Data Integrity & Security**: Projection and feed state stay in non-exposed `ai_internal` and are reached only through `SECURITY DEFINER` RPCs keyed on `current_org_id()`. `get_ai_billing_status` and `request_ai_status_refresh` require membership role `administrator`. No RPC lets a clinic user write status. The feed page is applied only after status, version, cursor, and order checks. An unsupported feed version does not move the cursor. An unsupported refresh version does not start a pull. (03 §4, 04 §3.1, 04 §4.1)
- **Failure Handling**: A stopped pull becomes `stale` while stored dates still move status to grace and then lapsed. A feed failure keeps the cursor and counts the failure. A response older than 5 minutes is abandoned. Supabase downtime does not stop ABO and platform provisioning; the projection catches up after restart. Staff billing status is forbidden. A second refresh within 10 s is throttled. (04 §3.3, 04 §4.1, 05 §4 FM-10, FM-11)

## 5. Out of Scope

- The unit row states no Out of scope line.
- No Do-not-read material. The unit row names none.
- No rewrite of the consumed contracts: P3.9 HTTP feed, `/v1/coverage`, and `feedConsumerHealth`. P5.1 states no Outputs / freezes line.
- No module this unit's E2E scenarios do not reach (rule S8). The P2.2 and package-half P2.1 exception does not apply. The pull is reached by pg_cron / pg_net, the status RPCs by PostgREST, and the lag by the consumed `feedConsumerHealth` method.
- No S9 path owned by a later unit. Desktop rendering of notice codes is consumed by P6.x with the frozen RPC results. Hosted confirmation of the R-4 spike is P8.1. This unit removes `get_ai_availability`, `set_ai_availability`, and `ai.availability`.
- No second codebase beyond backend. H-FS (`e2e/fullstack/`) is the harness named for these scenarios, including pg_net reaching the host (06 §3 V1).

## 6. Success Criteria

### 6.1 Measurable Outcomes

- **SC-001**: E2E-P5.2-01 through E2E-P5.2-11 are green in harness H-FS.
- **SC-002**: Every earlier suite stays green (rule S2).
- **SC-003**: CP-D: a platform coverage event reaches `get_ai_status()` through local Supabase within the bound (E2E-P5.2-01, rule S11).

## 7. Assumptions

- OQ-3 default: if the staging Supabase project is not available, P5.2 stops at its spike step. The R-4 spike in this unit is local; hosted confirmation stays with P8.1.
- OQ-5 default: the H-FS compressed scale in rule V4 is accepted (1 month = 60 s, 1 day = 2 s, keeping the 30:1 ratio). These scenarios run on that scale.
- Rule S9: this unit removes the availability RPCs and `ai.availability`. Desktop notice rendering stays with P6.x, which consumes the frozen status RPC results and notice codes. Hosted R-4 confirmation stays with P8.1.
