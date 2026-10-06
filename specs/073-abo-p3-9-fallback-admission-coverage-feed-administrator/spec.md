# Feature Specification: Fallback admission, coverage feed and administrator coverage read

**Feature Branch**: `ai/073-abo-p3-9-fallback-admission-coverage-feed-administrator`

**Created**: 2026-10-06

**Status**: Draft

**Input**: P3.9 — Fallback admission, coverage feed and administrator coverage read

## 1. Unit Contract

**Implements** — Read: 03 §6.5; 03 §6.6 (outage row); 03 §3.2 rows `fallback_admission`, `feed_consumer`, `coverage_mirror`; 03 §7 (Subscription reference row only); 04 §4.1 (first two paragraphs only); 04 §4.2 rows `/v1/coverage`, `/v1/usage`; 04 §1.3 row feedConsumerHealth; 02 §3.2 (Feed row); 04 §6.1 rows admission (fallback), credit (reconcile), usage-summary, `worker.ts` (`*/5`).

- fallback when the DO errors or takes > 2 s: mirror by primary key, then the four conditions (state, not suspended, before `hard_stop_at`, capability, outage weight ≤ 5 × w_max); otherwise `coverage_unknown` + `retry_after`; `fallback_admission` rows with `request_id`; `*/5` drain with dedupe; `GRACE_ADMISSION_CAP` and `grace_admission_queue` removed. `GET /v1/feed/coverage` (feed token `aud=ai-platform-feed`, `sub=backend-feed`, no `org`; version header; pages; `feed_consumer` updated); `feedConsumerHealth` (M). `GET /v1/coverage` (administrator only: `subscription_ref` is `AIC-` plus the leading 8 Crockford base-32 characters of SHA-256(`"sub-ref:"` ‖ `org_id`), computed with no lookup; live DO snapshot read-only, queued terms, last 12 terms with usage). `/v1/usage` and `src/usage-summary` removed.

**Freezes** — the HTTP feed contract; `/v1/coverage` response; `feedConsumerHealth`.

**Consumes** — clinic states `grace`/`lapsed` and reasons `expired`/`grace_exhausted` in the snapshot.

**Open questions relied on** — None.

**Spikes** — None.

## Clarifications

### Session 2026-10-06

- Q: How should E2E-P3.9-04 time out the DO admission call after a reservation without sleeping more than 2 seconds of real time? → A: The admission deadline uses the platform test clock. The harness lets the real DO write the reservation, then advances that clock past 2 seconds while the call is still in flight, and the `*/5` drain skips that `request_id`. Production keeps the 2 second limit. `[implementation choice — no §citation]`
- Q: How should E2E-P3.9-05 obtain the coverage events it pages? → A: The harness inserts `coverage_event` rows directly in D1. It does not call grant or other entrypoint methods owned by units that may run in parallel with P3.9. `[implementation choice — no §citation]`

## 2. User Scenarios & Testing

### 2.1 User Story 1 - Admit an AI request when the clinic DO is unreachable (Priority: P1)

A clinic member calls `POST /v1/requests`. When that clinic's DO errors or takes longer than 2 seconds, admission reads `coverage_mirror` by primary key and admits only when the four conditions in 03 §6.5 all hold. A fallback admission is a `fallback_admission` row carrying `term_id` and `request_id`. The `*/5` scheduled branch drains pending rows into the DO, which charges them once. Past the outage weight, or at or after `hard_stop_at`, the member receives `coverage_unknown`.

**Why this priority**: FM-06 is the failure mode this unit owns. The weight, `hard_stop_at`, and timeout-after-reserve cases are the same admission entry and the same drain.

**Independent Test**: E2E-P3.9-01, E2E-P3.9-02, E2E-P3.9-03, and E2E-P3.9-04 in harness H-AP.

**Acceptance Scenarios**:

1. **Given** an active clinic whose DO is forced to fail, **When** the clinic member calls `POST /v1/requests`, **Then** the request is admitted via fallback and a `fallback_admission` row exists. **When** the DO has recovered and the `*/5` branch runs, **Then** the DO charges that admission once. [FM-06, P-12] (E2E-P3.9-01, 03 §6.5)
2. **Given** a DO outage whose pending `fallback_admission` weight plus this request's `w` is beyond 5 × `w_max`, **When** the clinic member calls `POST /v1/requests`, **Then** the response is HTTP 503 `coverage_unknown` with `retry_after`. (E2E-P3.9-02, 03 §6.5, 03 §6.6 outage row)
3. **Given** a DO outage at or after `hard_stop_at`, **When** the clinic member calls `POST /v1/requests`, **Then** the response is `coverage_unknown`. [FR-23] (E2E-P3.9-03, 03 §6.5)
4. **Given** a DO call that timed out after reserving, **When** the `*/5` drain runs, **Then** the drain skips that `request_id` and the request is counted once. (E2E-P3.9-04, 03 §6.5)

### 2.2 User Story 2 - Pull the coverage feed and read consumer health (Priority: P2)

The backend calls `GET /v1/feed/coverage` with a feed token (`aud=ai-platform-feed`, `sub=backend-feed`, `org` absent) and `Aip-Contract-Version`. The page lists events. Each call updates `feed_consumer.last_pull_at`. `feedConsumerHealth` on `VendorEntrypoint` (class M) returns `last_pull_at` and `last_cursor`. A feed token on `/v1/requests`, and an AI token on the feed, are refused. A missing or unsupported feed version is refused before authentication and before any write.

**Why this priority**: The HTTP feed contract and `feedConsumerHealth` are what this unit freezes. They do not depend on fallback admission.

**Independent Test**: E2E-P3.9-05 and E2E-P3.9-06 in harness H-AP.

**Acceptance Scenarios**:

1. **Given** coverage events and a feed token with the current feed contract version, **When** the caller requests `GET /v1/feed/coverage` with `after` and `limit`, **Then** the response header is `Aip-Contract-Version`, the body is `{contract_version, after, events, next_after, has_more}`, and `feedConsumerHealth` shows that last pull. **Given** that feed token, **When** it is sent to `/v1/requests`, **Then** the response is 401. **Given** an AI token, **When** it is sent to the feed, **Then** the response is 401. (E2E-P3.9-05, 04 §4.1, 02 §3.2 Feed row, 04 §1.3 row `feedConsumerHealth`, 06 §3 V5)
2. **Given** a feed call with no `Aip-Contract-Version`, or with an unsupported version, **When** `GET /v1/feed/coverage` is called, **Then** the response is HTTP 400 `contract_version_unsupported`, before authentication and before any write. (E2E-P3.9-06, 06 §3 V5)

### 2.3 User Story 3 - Read coverage as an administrator (Priority: P3)

An administrator calls `GET /v1/coverage` and receives `subscription_ref`, the live DO snapshot, queued terms, and the last 12 terms with usage. `subscription_ref` is `AIC-` plus the leading 8 Crockford base-32 characters of SHA-256(`"sub-ref:"` ‖ `org_id`), computed with no lookup. The read does not write the DO. A staff token is refused. `GET /v1/usage` is gone.

**Why this priority**: The coverage response is frozen for a later desktop client. It does not change fallback admission or the feed.

**Independent Test**: E2E-P3.9-07 and E2E-P3.9-08 in harness H-AP. Every earlier suite stays green (rule S2).

**Acceptance Scenarios**:

1. **Given** an administrator token, **When** the administrator calls `GET /v1/coverage`, **Then** the response has the live snapshot, queued terms, and the last 12 terms with usage, and the DO is not written. **Given** a staff token, **When** `GET /v1/coverage` is called, **Then** the response is 403. [FR-60, FR-61] (E2E-P3.9-07, 04 §4.2 row `/v1/coverage`)
2. **Given** any caller, **When** `GET /v1/usage` is called, **Then** the response is 404. (E2E-P3.9-08, 04 §4.2 row `/v1/usage`)

### 2.4 Test plan

| ID | Harness | Entry point | Assertion | Proves | Story |
| --- | --- | --- | --- | --- | --- |
| E2E-P3.9-01 | H-AP | `SELF.fetch` `POST /v1/requests` on `ai-platform/src/worker.ts` `fetch`, with the DO forced to throw (rule V8). After the DO recovers, `runScheduled("*/5 * * * *")` in `ai-platform/test/system/harness.ts`, which runs `scheduled` (`cron === "*/5 * * * *"`). | FM-06: DO forced to fail for an active clinic → admitted via fallback with a `fallback_admission` row; the DO recovers and `*/5` charges it once. [FM-06, P-12] | FR-001, FR-003, FR-004 | User Story 1 |
| E2E-P3.9-02 | H-AP | `SELF.fetch` `POST /v1/requests` while the DO is unreachable and pending fallback weight plus `w` is beyond 5 × `w_max`. | Fallback weight beyond 5 × w_max → 503 `coverage_unknown` + `retry_after`. | FR-002 | User Story 1 |
| E2E-P3.9-03 | H-AP | `SELF.fetch` `POST /v1/requests` while the DO is unreachable and now is not before `hard_stop_at`. | Fallback after `hard_stop_at` → `coverage_unknown`. [FR-23] | FR-002 | User Story 1 |
| E2E-P3.9-04 | H-AP | `SELF.fetch` `POST /v1/requests` whose DO call times out after reserving, then `runScheduled("*/5 * * * *")` in `ai-platform/test/system/harness.ts`. | DO timed out after reserving → the drain skips that `request_id`; counted once. | FR-004 | User Story 1 |
| E2E-P3.9-05 | H-AP | `SELF.fetch` `GET /v1/feed/coverage` on `ai-platform/src/worker.ts` `fetch` with a current `Aip-Contract-Version` and a feed token. The same feed token on `SELF.fetch` `/v1/requests`. An AI token on `SELF.fetch` `GET /v1/feed/coverage`. `vendorCall("feedConsumerHealth", …)` on `VendorEntrypoint` over the H-AP self service binding (`env.VENDOR` in `ai-platform/test/system/harness.ts`). | Feed pages with `after`/`limit`/`next_after`/`has_more`, and the response echoes `Aip-Contract-Version` with `contract_version` in the body. A feed token on `/v1/requests` → 401; an AI token on the feed → 401; `feedConsumerHealth` shows the last pull. | FR-005, FR-006, FR-007 | User Story 2 |
| E2E-P3.9-06 | H-AP | `SELF.fetch` `GET /v1/feed/coverage` with the version header absent, and again with an unsupported version. | Feed without, or with an unsupported, version → 400 `contract_version_unsupported`, before authentication and before any write. | FR-006 | User Story 2 |
| E2E-P3.9-07 | H-AP | `SELF.fetch` `GET /v1/coverage` on `ai-platform/src/worker.ts` `fetch`, once with `role = administrator` and once with a staff token. | `/v1/coverage` as administrator → snapshot, queued, last 12 terms; staff token → 403; no DO write. [FR-60, FR-61] | FR-008 | User Story 3 |
| E2E-P3.9-08 | H-AP | `SELF.fetch` `GET /v1/usage` on `ai-platform/src/worker.ts` `fetch`. | `GET /v1/usage` → 404. | FR-009 | User Story 3 |

### 2.5 Edge Cases

- The DO call errors or takes longer than 2 seconds. Admission reads `coverage_mirror` by primary key and never from a cache. It admits only when every condition holds: the state is `active` or `grace` and the clinic is not suspended; now is before `hard_stop_at` (`ends_at` of the active term, or `grace_ends_at` in grace); the capability is in the mirrored snapshot; this outage's pending `fallback_admission` weight plus `w` is at most 5 × `w_max`. `w_max` is the largest quota weight among the published capabilities. During a DO outage the extra usage is at most 5 × `w_max` per outage. (03 §6.5, 03 §6.6 outage row, E2E-P3.9-01)
- Pending fallback weight plus `w` beyond 5 × `w_max` answers HTTP 503 `coverage_unknown` with `retry_after`. (03 §6.5, E2E-P3.9-02)
- Now at or after `hard_stop_at` answers `coverage_unknown`. That timestamp is the earliest time the calendar could stop service. (03 §6.5, E2E-P3.9-03)
- A state other than `active` or `grace`, a suspended clinic, or a capability absent from the mirrored snapshot answers `coverage_unknown` (retryable). (03 §6.5)
- The drain skips a row whose `request_id` the DO still holds as a reservation or replay entry, or that already has a `usage_event`. The unique `request_id` index backs the usage check. A DO call that timed out after reserving is not charged twice. The request is counted once. (03 §6.5, E2E-P3.9-04)
- A feed token is never accepted on any other route. A feed token on `/v1/requests` is 401. An AI token on the feed is 401. (02 §3.2 Feed row, E2E-P3.9-05)
- A feed call with no version, or with an unsupported version, is HTTP 400 `contract_version_unsupported`. The check runs before authentication and before any write, so `feed_consumer` is not updated. A current version is accepted and echoed on the response header `Aip-Contract-Version` and as `contract_version` in the page. The feed channel is at version 1 at launch. (04 §4.1, E2E-P3.9-05, E2E-P3.9-06, 06 §3 V5)
- `GET /v1/coverage` with a staff token is 403. The administrator read does not write the DO. (04 §4.2 row `/v1/coverage`, E2E-P3.9-07)
- `GET /v1/usage` is 404. (04 §4.2 row `/v1/usage`, E2E-P3.9-08)

## 3. Requirements

### 3.1 Functional Requirements

- **FR-001**: When the DO call errors or takes longer than 2 seconds, admission reads `coverage_mirror` by primary key and never from a cache. The mirror is not an admission authority by itself. Fallback admission of an active clinic whose DO is forced to fail writes a `fallback_admission` row. (03 §3.2 row `coverage_mirror`, 03 §6.5, E2E-P3.9-01)
- **FR-002**: Fallback admits only when all of these hold: the state is `active` or `grace` and the clinic is not suspended; now is before `hard_stop_at`, which is the active term's `ends_at`, or `grace_ends_at` in grace; the capability is in the mirrored snapshot; this outage's pending `fallback_admission` weight plus `w` is at most 5 × `w_max`, where `w_max` is the largest quota weight among the published capabilities. Otherwise it answers `coverage_unknown` (retryable) with `retry_after`. Weight beyond 5 × `w_max` is HTTP 503 `coverage_unknown` with `retry_after`. After `hard_stop_at` the answer is `coverage_unknown`. During a DO outage, usage beyond the term allowance is additionally at most 5 × `w_max` per outage. (03 §6.5, 03 §6.6 outage row, Implements, E2E-P3.9-02, E2E-P3.9-03)
- **FR-003**: Every fallback admission is a `fallback_admission` row carrying its `term_id` and the request's `request_id`. The table replaces `grace_admission_queue`. Columns are `installation_id`, `idempotency_key`, `term_id`, `weight`, `admitted_at`, and `state` (`pending`, `settled`), with an index on `state`. `GRACE_ADMISSION_CAP` is removed. The fallback path in `src/admission/index.ts` follows 03 §6.5 using `coverage_mirror` and `fallback_admission`. (03 §3.2 row `fallback_admission`, 03 §6.5, 04 §6.1 row admission (fallback), E2E-P3.9-01)
- **FR-004**: The platform's 5-minute cron drains pending `fallback_admission` rows into the DO, which charges them to their terms. Nothing is dropped. The `scheduled` handler's `*/5 * * * *` branch is that drain. `reconcileGraceUsage` becomes the fallback drain. The 2-hour drop and the zero-credit reconcile are removed. The drain skips any row whose `request_id` the DO still holds as a reservation or replay entry, or that already has a `usage_event`. The unique `request_id` index backs that second check. A DO call that timed out after reserving is not charged twice, and that `request_id` is counted once. After the DO recovers, `*/5` charges the forced-failure admission once. (03 §6.5, 04 §6.1 rows credit (reconcile) and `worker.ts` (`*/5`), E2E-P3.9-01, E2E-P3.9-04)
- **FR-005**: `GET /v1/feed/coverage?after=<feed_seq>&limit=<≤200>` requires a feed token and `Aip-Contract-Version`. The feed token has `aud=ai-platform-feed`, lifetime ≤ 120 s, `org` absent, and `sub=backend-feed`. It is never accepted on any other route. The response header is `Aip-Contract-Version` and the body is `{contract_version, after, events, next_after, has_more}`. Each event is `{event_id, feed_seq, org_id, installation_id, binding_epoch, clinic_seq, kind, at, snapshot}`. `kind` is `grant_applied`, `grant_voided`, `term_activated`, `term_ended`, `term_held`, `term_released`, `grace_started`, `band_crossed`, `suspension_changed`, or `transfer`. Pages are not signed. Each call updates `feed_consumer.last_pull_at`. `feed_consumer` is `consumer`, `last_pull_at`, `last_cursor`. (04 §4.1 first two paragraphs, 02 §3.2 Feed row, 03 §3.2 row `feed_consumer`, E2E-P3.9-05)
- **FR-006**: On the feed channel the current version is accepted and echoed (`Aip-Contract-Version` on the response and `contract_version` in the page). The channel is at version 1 at launch. A missing version, or an unsupported version, is HTTP 400 `contract_version_unsupported`. That refusal happens before authentication and before any write, so `feed_consumer` is not updated. (04 §4.1, E2E-P3.9-05, E2E-P3.9-06, 06 §3 V5)
- **FR-007**: `feedConsumerHealth` is class M on `VendorEntrypoint`. Beyond `contract_version` it takes no input. It returns `last_pull_at` and `last_cursor`. After a feed pull it shows that last pull. A feed token presented to `/v1/requests` is 401. An AI token presented to the feed is 401. (04 §1.3 row `feedConsumerHealth`, 02 §3.2 Feed row, E2E-P3.9-05)
- **FR-008**: `GET /v1/coverage` is `role = administrator` only. The response is `subscription_ref`, the live snapshot from the DO (read-only, no write), queued terms (plan and duration), and the last 12 terms with usage. `subscription_ref` is `AIC-` plus the leading 8 Crockford base-32 characters of SHA-256(`"sub-ref:"` ‖ `org_id`), computed from `org_id` with no lookup. A staff token receives 403. The call does not write the DO. The read is served from `src/coverage-read/index.ts`, which replaces `src/usage-summary/index.ts`. (04 §4.2 row `/v1/coverage`, 03 §7 Subscription reference row, 04 §6.1 row usage-summary, E2E-P3.9-07)
- **FR-009**: `GET /v1/usage` is removed. The route answers 404. `src/usage-summary/index.ts` is deleted. (04 §4.2 row `/v1/usage`, 04 §6.1 row usage-summary, E2E-P3.9-08)

### 3.2 Key Entities

- **`fallback_admission`**: Replaces `grace_admission_queue`. `installation_id`, `idempotency_key`, `term_id`, `weight`, `admitted_at`, `state` (`pending`, `settled`), plus the request's `request_id`. Index on `state`. The `*/5` drain charges pending rows to their terms and skips a `request_id` the DO still holds or that already has a `usage_event`. (03 §3.2 row `fallback_admission`, 03 §6.5)
- **`feed_consumer`**: `consumer`, `last_pull_at`, `last_cursor`. Each feed call updates `last_pull_at`. `feedConsumerHealth` returns `last_pull_at` and `last_cursor`. The row lets the ABO alert when the backend stops pulling. (03 §3.2 row `feed_consumer`, 04 §4.1, 04 §1.3 row `feedConsumerHealth`)
- **`coverage_mirror`**: Read by primary key on fallback. Not written by this unit's admission path, and never used as a cache. Fields this unit reads: `state`, `suspended`, `hard_stop_at`, `term_snapshot`. (03 §3.2 row `coverage_mirror`, 03 §6.5)

## 4. Constitution Alignment

### 4.1 Architecture & Operations Impact

- **Clinic Fit**: One clinic can still be admitted to AI while that clinic's DO is unreachable, inside the outage cap, and an administrator can read that clinic's coverage. Staff do not receive the removed usage route. The unit adds no second clinic product.
- **Layer Placement**: Codebase is `ai-platform` only. No wiring exception is named. Live entries are `SELF.fetch` on `ai-platform/src/worker.ts` (`POST /v1/requests`, `GET /v1/feed/coverage`, `GET /v1/coverage`, `GET /v1/usage`), `runScheduled("*/5 * * * *")` in `ai-platform/test/system/harness.ts` (`scheduled`), and `vendorCall("feedConsumerHealth", …)` on `VendorEntrypoint` (`env.VENDOR`). `plan.md` re-runs the constitution check in 02 §7 (rule S12).
- **Data Integrity & Security**: Fallback reads `coverage_mirror` by primary key and does not admit from a cache. `request_id` is unique so a timed-out reservation is not charged twice. The feed token is audience `ai-platform-feed` with `sub=backend-feed` and no `org`, and it is refused on other routes. Feed pages are not signed. `GET /v1/coverage` requires `role = administrator` and does not write the DO. The feed version check runs before authentication and before any write. (03 §6.5, 02 §3.2 Feed row, 04 §4.1, 04 §4.2, 06 §3 V5)
- **Failure Handling**: A DO error or a call longer than 2 seconds either admits from the mirror under the four conditions or answers `coverage_unknown` with `retry_after`. The `*/5` drain charges pending rows and skips a `request_id` already reserved or journaled. A bad feed version is HTTP 400 `contract_version_unsupported` and writes nothing. A staff token on `/v1/coverage` is 403. `GET /v1/usage` is 404. (03 §6.5, E2E-P3.9-01, E2E-P3.9-02, E2E-P3.9-04, E2E-P3.9-06, E2E-P3.9-07, E2E-P3.9-08)

## 5. Out of Scope

- Backend puller (→ P5.2); desktop client (→ P6.2).
- No Do-not-read material. The 04 §4.1 backend pull cycle stays with P5.2.
- No rewrite of clinic states `grace`/`lapsed` or reasons `expired`/`grace_exhausted` in the snapshot (rule S7).
- No module that no test-plan row reaches (rule S8). `src/admission/index.ts` fallback is reached by `POST /v1/requests`. The `*/5` drain (`reconcileGraceUsage` as that drain) is reached by `runScheduled("*/5 * * * *")`. `GET /v1/feed/coverage` and `feedConsumerHealth` are reached by E2E-P3.9-05. `src/coverage-read/index.ts` is reached by `GET /v1/coverage`. Removal of `src/usage-summary/index.ts` is reached by `GET /v1/usage`.
- No S9 path owned by a later unit. Entitlement, plan, and invoice tables, and all `/control/*` routes, stay until P3.10. This unit does remove `grace_admission_queue`, `GRACE_ADMISSION_CAP`, and `GET /v1/usage`.
- No second codebase. The Codebase cell is `ai-platform`.

## 6. Success Criteria

### 6.1 Measurable Outcomes

- **SC-001**: E2E-P3.9-01, E2E-P3.9-02, E2E-P3.9-03, E2E-P3.9-04, E2E-P3.9-05, E2E-P3.9-06, E2E-P3.9-07, and E2E-P3.9-08 pass in harness H-AP.
- **SC-002**: Every earlier suite stays green (rule S2).

## 7. Assumptions

- No §6 open question is named by this unit's Read or Implements lines.
- Entitlement, plan, and invoice tables, and all `/control/*` routes, stay until P3.10 (rule S9).
- `grace_admission_queue` and `GRACE_ADMISSION_CAP` are removed in this unit (03 §3.2, Implements). `GET /v1/usage` is removed in this unit (04 §4.2).
- `GET /v1/coverage`'s `subscription_ref` is the 03 §7 subscription reference: `AIC-` plus the leading 8 Crockford base-32 characters of SHA-256(`"sub-ref:"` ‖ `org_id`), computed with no lookup. Only that row of 03 §7 is in scope.
