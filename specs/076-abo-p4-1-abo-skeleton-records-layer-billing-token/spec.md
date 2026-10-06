# Feature Specification: ABO skeleton, records layer, billing-token auth and catalogue reads

**Feature Branch**: `ai/076-abo-p4-1-abo-skeleton-records-layer-billing-token`

**Created**: 2026-10-06

**Status**: Draft

**Input**: P4.1 — ABO skeleton, records layer, billing-token auth and catalogue reads

## 1. Unit Contract

**Implements** — Read: 02 §1.2 (module table); 02 §1.4; 03 §2.1; 03 §2.2; 03 §2.3 (table + first two sentences; not erasure); 04 §2.2 (rows `GET /v1/offers`, `GET`/`PUT /v1/billing-contact`, and Rules); 04 §2.3; 05 §2 row AL-16 + 02 §5 (decision paragraph).

- `abo/` Worker: wrangler with D1, R2, `send_email`, crons (minute, hourly, 6-hourly, daily 06:00 declared), `workers_dev=false`, `preview_urls=false`, observability; module folders per 02 §1.2 (code only where used).
- Hostname routing: the billing host serves `/v1`, `/notify`, `/return`; the ops host serves `/ops` only; cross-host requests rejected.
- `Abo-Contract-Version` checked before auth on `/v1` and `/ops`; error body `{code, message, contract_version}` with the 04 §2.3 codes.
- Billing-token verification against the pinned `ISSUER_KEYS` (several `kid`s): `aud=abo`, `ver`, ≤ 300 s, `role=administrator`; tenant only from `org`; 60 requests per token.
- Records: ULIDs, append-only triggers, `fact_log`, `fact_export`; minute-cron exporter to R2 `ledger/` (NDJSON per fact, no contact values); AL-16 (export > 1 h behind; daily R2 lock check).
- Tables `offer`, `offer_version`, `offer_event`, `terms_version`, `billing_contact`; `GET /v1/offers` (sellable latest versions + terms text from R2); `GET`/`PUT /v1/billing-contact` (versioned, idempotent by `client_request_id`, E.164).
- Alert engine (`alert` dedupe, repeat, send, retry) + heartbeat ping on the minute cron; ABO clock module + test clock; H-ABO harness; ABO CI job.

**Freezes** — ABO clinic-API envelope, auth and error rules; records conventions; alert engine; H-ABO.

**Consumes** — the message types of 04 §1.2–§1.7 and §2.1; the verification APIs; the testkit API (used by every later harness). CP-A.

**Open questions relied on** — None.

**Spikes** — None.

## 2. User Scenarios & Testing

### 2.1 User Story 1 - Gate clinic calls with version and billing token (Priority: P1)

The calling component sends `Abo-Contract-Version` and `Authorization: Bearer` with a billing token to `/v1` on the billing host. The ABO checks the version before authentication. It verifies the token against pinned `ISSUER_KEYS`: audience `abo`, `ver`, lifetime at most 300 seconds, and `role=administrator`. The sixty-first request in one token's life is refused. The `abo/` Worker that serves these calls declares D1, R2, `send_email`, the four crons, `workers_dev=false`, `preview_urls=false`, and observability.

**Why this priority**: Catalogue reads, contact writes, and later clinic calls depend on this gate. A missing or unsupported version is refused before authentication and before any write.

**Independent Test**: E2E-P4.1-01, E2E-P4.1-02, and E2E-P4.1-09 in harness H-ABO.

**Acceptance Scenarios**:

1. **Given** a `/v1` request and an `/ops` request on the ops host, each with no `Abo-Contract-Version` and an invalid token, **When** the ABO handles the request, **Then** the response is HTTP 400 `contract_version_unsupported` before authentication. The same refusal is returned when the version is outside N and N−1. At launch N is 1. The body is `{code, message, contract_version}` and lists the accepted versions. Nothing is written. (E2E-P4.1-01, 04 §2.3, 06 §3 V5)
2. **Given** a pinned issuer, **When** the caller presents an AI token (`aud=ai-platform`), a billing token signed by an unpinned `kid`, or a billing token with `role=doctor`, **Then** the AI token and the unpinned `kid` receive HTTP 401 `unauthenticated`, and `role=doctor` receives HTTP 403 `forbidden_role`. (E2E-P4.1-02, 04 §2.3)
3. **Given** one billing token that has already been accepted 60 times, **When** that token is presented for a 61st request within its life, **Then** the response is HTTP 429 `rate_limited`. (E2E-P4.1-09, 04 §2.2 Rules)

### 2.2 User Story 2 - Keep billing routes and ops routes on their hosts (Priority: P2)

The calling component addresses the ABO with a Host header. The billing hostname serves `/v1`, `/notify`, and `/return`. The ops hostname serves `/ops` only. A path on the other host is rejected.

**Why this priority**: The billing host is public and the ops host is the Access-protected console hostname. Cross-host paths are rejected before those modules run.

**Independent Test**: E2E-P4.1-06 in harness H-ABO.

**Acceptance Scenarios**:

1. **Given** the billing hostname and the ops hostname, **When** the caller requests `/ops/*` on the billing host or `/v1/*` on the ops host, **Then** the ABO rejects the request. (E2E-P4.1-06, 02 §1.4)

### 2.3 User Story 3 - Read sellable offers and keep a billing contact (Priority: P3)

An administrator with a billing token lists sellable offers, including terms text, and reads or replaces the clinic billing contact. The tenant is the token's `org`. Publication of offers is seeded by a D1 fixture until P4.7.

**Why this priority**: Offers and the billing contact are the clinic catalogue this unit serves after the gate in User Story 1.

**Independent Test**: E2E-P4.1-03, E2E-P4.1-04, and E2E-P4.1-05 in harness H-ABO.

**Acceptance Scenarios**:

1. **Given** a sellable offer whose latest event is `published` and a retired offer, and the current clinic-channel version on the request, **When** the administrator calls `GET /v1/offers`, **Then** the list contains the sellable latest version and its terms text, the retired offer is absent, and the response echoes that version on `Abo-Contract-Version` and in `contract_version`. (E2E-P4.1-03, 03 §2.2, 04 §2.2 row `GET /v1/offers`, 06 §3 V5)
2. **Given** an administrator, **When** `PUT /v1/billing-contact` is sent twice with the same `client_request_id`, **Then** one contact version exists. **When** a new request is sent, **Then** the current version is version 2. **When** the phone is not E.164, **Then** the response is HTTP 422 `invalid_request`. (E2E-P4.1-04, 04 §2.2, 04 §2.3)
3. **Given** tenant A has a billing contact, **When** tenant B calls with B's token, **Then** B does not receive A's contact. An `org` in the body is ignored. (E2E-P4.1-05, 04 §2.2 Rules)

### 2.4 User Story 4 - Export facts, raise AL-16, and ping the heartbeat (Priority: P4)

The minute cron writes each pending fact as one NDJSON object under R2 `ledger/`, in `fact_seq` order, without contact values. Append-only tables reject UPDATE and DELETE. When the export is more than one hour behind, AL-16 is sent once and then daily. A `send_email` failure is retried. The same minute cron pings `HEARTBEAT_URL`. The ABO clock is the time source, and the test clock advances these waits.

**Why this priority**: Records, the alert engine, and the heartbeat sit on the minute cron after the clinic writes exist. This story also carries the regression line for the earlier stories.

**Independent Test**: E2E-P4.1-07, E2E-P4.1-08, and E2E-P4.1-10 in harness H-ABO. E2E-P4.1-01 through E2E-P4.1-06 and E2E-P4.1-09 still pass.

**Acceptance Scenarios**:

1. **Given** an append-only fact table, **When** UPDATE or DELETE runs, **Then** the statement aborts. Each fact has a `fact_log` row. **When** the minute cron runs, **Then** it writes NDJSON under `ledger/` in `fact_seq` order and the objects contain no contact values. (E2E-P4.1-07, 03 §2.1)
2. **Given** the fact export is more than one hour behind, measured on the test clock, **When** the alert runs, **Then** AL-16 is sent once and then daily while the condition holds. **When** `send_email` fails, **Then** the send is retried. The captured body carries codes and ids only. (E2E-P4.1-08, 05 §2 row AL-16, 02 §5, 06 §3 V4, 06 §3 V6)
3. **Given** `HEARTBEAT_URL` is configured, **When** the minute cron runs, **Then** the ABO pings that URL. (E2E-P4.1-10, 02 §5)

### 2.5 Test plan

| ID | Harness | Entry point | Assertion (+ tags) | Proves | Story |
| --- | --- | --- | --- | --- | --- |
| E2E-P4.1-01 | H-ABO | `SELF.fetch` on the ABO worker `fetch`, Host set to the billing hostname for `/v1` and to the ops hostname for `/ops` | No `Abo-Contract-Version` (with an invalid token) → 400 `contract_version_unsupported` before auth. A version outside N and N−1 (2 at launch) gets the same refusal before authentication and before any write. Body `{code, message, contract_version}` lists the accepted versions. | FR-003 | User Story 1 |
| E2E-P4.1-02 | H-ABO | `SELF.fetch` on the ABO worker `fetch`, billing hostname, `Authorization: Bearer` | AI token (`aud=ai-platform`) → 401 `unauthenticated`; billing token signed by an unpinned `kid` → 401 `unauthenticated`; `role=doctor` → 403 `forbidden_role` [TB-2, FR-10] | FR-004 | User Story 1 |
| E2E-P4.1-03 | H-ABO | `SELF.fetch` `GET /v1/offers` on the ABO worker `fetch`, billing hostname | `GET /v1/offers` lists the sellable latest versions with terms text; a retired offer is absent. The current version (1 at launch) is accepted and echoed on `Abo-Contract-Version` and as `contract_version`. [A21, A33 listing] | FR-003, FR-006 | User Story 3 |
| E2E-P4.1-04 | H-ABO | `SELF.fetch` `PUT /v1/billing-contact` on the ABO worker `fetch`, billing hostname | `PUT` contact twice with the same `client_request_id` → one version; a new request → version 2; invalid phone → 422 `invalid_request` [FR-51] | FR-007 | User Story 3 |
| E2E-P4.1-05 | H-ABO | `SELF.fetch` `GET`/`PUT /v1/billing-contact` on the ABO worker `fetch`, billing hostname | Tenant B's token never sees A's contact; an `org` in the body is ignored [SR-03] | FR-007 | User Story 3 |
| E2E-P4.1-06 | H-ABO | `SELF.fetch` on the ABO worker `fetch`, with the billing Host and the ops Host | `/ops/*` on the billing host and `/v1/*` on the ops host → rejected [02 §1.4] | FR-002 | User Story 2 |
| E2E-P4.1-07 | H-ABO | ABO D1 binding for the append-only statement; `runScheduled` on the ABO worker `scheduled` for the minute export | UPDATE/DELETE on an append-only table aborts; each fact has a `fact_log` row; the minute cron writes NDJSON under `ledger/` in `fact_seq` order with no contact values [RC-01, RC-03] | FR-008 | User Story 4 |
| E2E-P4.1-08 | H-ABO | `runScheduled` on the ABO worker `scheduled`, test clock advanced, `send_email` capture | Export stalled > 1 h → AL-16 once, then daily; `send_email` failure retried. Captured body has codes and ids only [FM-16, TB-9] | FR-009 | User Story 4 |
| E2E-P4.1-09 | H-ABO | `SELF.fetch` on the ABO worker `fetch`, billing hostname, one billing token | 61st request within one token's life → 429 `rate_limited` | FR-005 | User Story 1 |
| E2E-P4.1-10 | H-ABO | `runScheduled` on the ABO worker `scheduled` (minute), outbound fetch capture | Minute cron pings the heartbeat URL | FR-010 | User Story 4 |

### 2.6 Edge Cases

- A `/v1` or `/ops` request with no `Abo-Contract-Version`, or with a version outside N and N−1, returns HTTP 400 `contract_version_unsupported` before authentication and before any write. An invalid token on that request still receives this refusal, and the body lists the accepted versions. (E2E-P4.1-01, 04 §2.3, 06 §3 V5)
- An AI token (`aud=ai-platform`) and a billing token whose `kid` is not pinned return HTTP 401 `unauthenticated`. `role=doctor` returns HTTP 403 `forbidden_role`. (E2E-P4.1-02, 04 §2.3)
- A phone that is not E.164 returns HTTP 422 `invalid_request`. (E2E-P4.1-04, 04 §2.3)
- Tenant B's token does not receive tenant A's contact. An `org` field in the body is ignored. The tenant is the token's `org`. (E2E-P4.1-05, 04 §2.2 Rules)
- `GET /v1/billing-contact` when the tenant has no contact returns `not_found`. (04 §2.2 row `GET /v1/billing-contact`)
- `/ops/*` on the billing hostname and `/v1/*` on the ops hostname are rejected. (E2E-P4.1-06, 02 §1.4)
- UPDATE or DELETE on a table marked append-only aborts. (E2E-P4.1-07, 03 §2.1)
- Fact export more than an hour behind raises AL-16 once, then daily. A missing R2 bucket lock raises AL-16 on the daily lock check. The check is `GET https://api.cloudflare.com/client/v4/accounts/{account_id}/r2/buckets/{bucket_name}/lock` with `Authorization: Bearer` set to `R2_LOCK_READ_TOKEN`. The lock is missing only when that call returns `success` true and `result.rules` has no enabled rule whose `condition.type` is `Indefinite` and whose `prefix` is `ledger/` or empty. `send_email` failure is retried. Alert bodies carry codes and ids only. (E2E-P4.1-08, 05 §2 row AL-16, 02 §5, Implements)
- The 61st request within one token's life returns HTTP 429 `rate_limited`. (E2E-P4.1-09, 04 §2.2 Rules)
- Production and staging wrangler configs carry no test-clock control. A local scenario spends at most 2 seconds of real time; the export lag and the daily AL-16 repeat advance the test clock. (06 §3 V4)

## 3. Requirements

### 3.1 Functional Requirements

- **FR-001**: The ABO is one Worker in a new top-level directory `abo/`. Wrangler binds D1, R2, and `send_email`, declares crons for every minute, hourly, every 6 hours, and daily 06:00, and sets `workers_dev=false`, `preview_urls=false`, and observability. Module folders follow the 02 §1.2 module table. Code exists where an E2E row in §2.5 reaches it: Clinic API for offers and billing contact, Records, and alert emission with dedupe. Hourly and 6-hourly schedules are declared. (02 §1.2 module table, 02 §1.4, Implements)
- **FR-002**: Hostname `billing.<vendor-domain>` serves `/v1/*`, `/notify/*`, and `/return/*`. Hostname `ops.<vendor-domain>` serves `/ops/*` only. The ABO rejects `/ops/*` on the billing hostname and `/v1/*` on the ops hostname. Both flags `workers_dev=false` and `preview_urls=false` are set so the ops host has no bypass hostname. (02 §1.4, E2E-P4.1-06)
- **FR-003**: Every clinic call sends `Abo-Contract-Version`. The check runs before authentication on `/v1` and on `/ops`, and before any write. The current version N and N−1 are accepted. At launch N is 1, so a missing header or version 2 is outside the accepted set. Refusal is HTTP 400 `contract_version_unsupported` even when the token is invalid. The body is `{code, message, contract_version}` and lists the accepted versions. A successful response echoes the request version on the `Abo-Contract-Version` header and in `contract_version`. `/ops/*` uses the same header and error rules. (04 §2.2, 04 §2.3, Implements, 06 §3 V5, E2E-P4.1-01, E2E-P4.1-03)
- **FR-004**: The ABO verifies the billing token against the issuer public keys pinned in `ISSUER_KEYS` (several `kid`s), and does not fetch keys from the platform. It checks `aud=abo`, `ver`, lifetime at most 300 seconds, and `role=administrator`. An AI token (`aud=ai-platform`), a missing, invalid, or expired token, or a wrong audience is HTTP 401 `unauthenticated`. A `kid` that is not pinned is HTTP 401 `unauthenticated`. A `role` other than `administrator`, including `doctor`, is HTTP 403 `forbidden_role`. H-ABO mints billing tokens with the frozen testkit. (Implements, 04 §2.2, 04 §2.3, E2E-P4.1-02)
- **FR-005**: The clinic API allows 60 requests per token. The 61st request within that token's life is HTTP 429 `rate_limited`. (04 §2.2 Rules, 04 §2.3, Implements, E2E-P4.1-09)
- **FR-006**: `GET /v1/offers` returns `offers[]` of the sellable latest versions: `offer_id`, `version`, `plan_display_name`, `term_unit`, `term_count`, `price_minor`, `currency`, `allowance_credits`, `grace_days`, localized `copy`, and `terms` with `version` and text. Terms text is read from R2. An offer is sellable when its latest `offer_event` is `published`; the sellable version is the latest published one. A retired offer is absent. Past prices remain on `offer_version`. Rows are seeded by a D1 fixture until publication exists. (03 §2.2, 04 §2.2 row `GET /v1/offers`, Implements, E2E-P4.1-03)
- **FR-007**: `GET /v1/billing-contact` returns `version`, `name`, `email`, and `phone`, or `not_found`. `PUT /v1/billing-contact` takes `client_request_id`, `name`, `email`, and `phone` (E.164) and creates a new version. The latest version is current. The same `client_request_id` for one tenant yields one version; a new request yields version 2. A phone that fails validation is HTTP 422 `invalid_request`. The tenant is the token's `org`. An `org` in the body is ignored. Tenant B's token does not receive tenant A's contact. Contact values stay off append-only tables and off the export; those records refer to a `billing_contact` version and hash. (03 §2.3 table and first two sentences, 04 §2.2 rows and Rules, 04 §2.3, E2E-P4.1-04, E2E-P4.1-05)
- **FR-008**: Ids are ULIDs with 80 random bits. Money is an integer in minor units plus an ISO 4217 currency. Times are UTC ISO-8601. Tables marked append-only have D1 `BEFORE UPDATE` and `BEFORE DELETE` triggers that abort. Every insert into an append-only table also inserts a `fact_log` row (`fact_seq`, table, key, SHA-256 of the canonical row). `fact_export` records which facts have been exported. The minute cron writes one NDJSON object per fact under the R2 prefix `ledger/`, in `fact_seq` order, with no contact values. `contract_version` on a record is the version of the message that created it. Stored payloads are read in the version they were written in. Every tenant query is keyed by `org_id` and backed by an index. (03 §2.1, Implements, E2E-P4.1-07)
- **FR-009**: Alerts go through `send_email`, deduplicated, repeated, sent, and retried from `alert`. AL-16 fires when the R2 bucket lock is missing or the fact export is more than an hour behind, raised by the ABO, repeated daily. The export-stall case sends AL-16 once, then daily while the stall holds. The lock check runs on the daily cron. It observes the lock with `GET https://api.cloudflare.com/client/v4/accounts/{account_id}/r2/buckets/{bucket_name}/lock` and header `Authorization: Bearer` set to the secret `R2_LOCK_READ_TOKEN`. `account_id` is the var `CLOUDFLARE_ACCOUNT_ID`. `bucket_name` is the var `R2_BUCKET_NAME`. That token cannot set lock rules. The lock is present when the body has `success` true and `result.rules` includes an enabled rule whose `condition.type` is `Indefinite` and whose `prefix` is `ledger/` or empty. The lock is missing, and this check raises AL-16, only when that call returns `success` true and no such rule is present. Any other response leaves the lock condition unraised. H-ABO answers this GET. Unless a scenario supplies another body, the answer is `success` true and one enabled Indefinite rule with prefix `ledger/`. A `send_email` failure is retried. Captured alert bodies carry codes and ids only. (Implements, 05 §2 row AL-16, 02 §5, 06 §3 V6, E2E-P4.1-08)
- **FR-010**: The minute cron pings `HEARTBEAT_URL`. The harness asserts the ping by capturing the outbound fetch. The ABO reads time through one clock module. Only the test vitest config binds the test-clock control. Production and staging wrangler envs carry no clock control, and a config test asserts that. Harnesses advance the test clock. No local scenario sleeps more than 2 seconds of real time. H-ABO lives at `abo/test/system/` and provides `SELF.fetch` with the billing and ops Host headers, billing-token minting, D1 and R2 helpers, `runScheduled`, and email capture. The ABO system CI job runs that harness. (02 §5, 06 §3 V1, 06 §3 V4, 06 §3 V6, 06 §3 V7, Implements, E2E-P4.1-10)

### 3.2 Key Entities

- **`offer`**: Append-only. `offer_id`, `code` (stable slug). Sellable when the latest `offer_event` is `published`. (03 §2.2)
- **`offer_version`**: Append-only. `offer_id`, `version`, `plan_id`, `plan_version`, `term_unit` (always `month`), `term_count` (1, 3, or 12), `price_minor`, `currency`, `allowance_credits`, `grace_days` (7), `grace_cap_rule` (`proportional`), `copy` (per-locale name and summary), `terms_version`, `published_by`, `assertion_sha256`. Past prices remain on this table. The sellable version is the latest published one. (03 §2.2)
- **`offer_event`**: Append-only. `offer_id`, `kind` (`published`, `retired`, `reinstated`), `version`, `actor`, `at`. (03 §2.2)
- **`terms_version`**: Append-only. `terms_version`, `locale`, `text_r2_key`, `text_sha256`, `published_by`. `GET /v1/offers` returns the terms text from R2. (03 §2.2, Implements)
- **`billing_contact`**: Insert-only. `org_id`, `version`, `name`, `email`, `phone`, `contact_sha256`, `created_by_sub`, `erased_at`, `erased_by`. The latest version is current. Contact values are absent from append-only tables and from the export. (03 §2.3 table and first two sentences)
- **`fact_log`**: One row per append-only insert: `fact_seq`, table, key, SHA-256 of the canonical row. (03 §2.1)
- **`fact_export`**: Which facts the exporter has written. The minute cron writes one NDJSON object per fact under `ledger/` in `fact_seq` order. (03 §2.1)
- **`alert`**: Dedupe, repeat, send, and retry record for ABO alerts, including AL-16. (Implements)

## 4. Constitution Alignment

### 4.1 Architecture & Operations Impact

- **Clinic Fit**: An administrator of a small-to-mid-size clinic can list that clinic's sellable offers and keep one billing contact, with the tenant taken from the billing token. The unit adds no second clinic product.
- **Layer Placement**: Codebase is `abo/` (new). No wiring exception is named. Live entries are `SELF.fetch` on the ABO worker `fetch` (billing host and ops host) and `runScheduled` on the ABO worker `scheduled`. H-ABO is `abo/test/system/`. `plan.md` re-runs the constitution check in 02 §7 (rule S12).
- **Data Integrity & Security**: Append-only tables abort UPDATE and DELETE. Facts export without contact values. The tenant is the token's `org`. Version refusal happens before authentication and before any write. Tokens are checked against pinned `ISSUER_KEYS`. `role=administrator` is required on the billing token. Alert bodies carry codes and ids only. (03 §2.1, 04 §2.2 Rules, 04 §2.3, 02 §5)
- **Failure Handling**: A missing or unsupported `Abo-Contract-Version` returns HTTP 400 `contract_version_unsupported` and writes nothing. A bad audience or unpinned `kid` returns HTTP 401 `unauthenticated`. The wrong role returns HTTP 403 `forbidden_role`. An invalid phone returns HTTP 422 `invalid_request`. The 61st request returns HTTP 429 `rate_limited`. Cross-host paths are rejected. `send_email` failure is retried. Export lag and a missing R2 lock raise AL-16. (04 §2.3, 02 §1.4, 05 §2 row AL-16, E2E-P4.1-01, E2E-P4.1-02, E2E-P4.1-04, E2E-P4.1-06, E2E-P4.1-08, E2E-P4.1-09)

## 5. Out of Scope

- Checkouts (→ P4.2); offer publication (→ P4.7; seeded by D1 fixture until then); erasure (→ P4.7); console (→ P4.6).
- No Do-not-read material (03 §2.4–§2.11, 04 §5). Checkout, subscription, and payment rows of 04 §2.2 stay with later units. The 10-checkouts limit and storing `jti` on checkout and payment facts stay with those units. Notification intake, the provider port, and Paymob stay unread here.
- No rewrite of the consumed package: the message types of 04 §1.2–§1.7 and §2.1, the verification APIs, and the testkit API (rule S7).
- No module that no test-plan row reaches (rule S8). Clinic API code for `GET /v1/offers` and `GET`/`PUT /v1/billing-contact` is reached by `SELF.fetch`. Records triggers and `fact_log` are reached by E2E-P4.1-07. The minute exporter, AL-16, and the heartbeat are reached by `runScheduled`. Hostname rejection is reached by E2E-P4.1-06. Notification intake, the pipeline, provider adapters, the operator console, and reconciliation matching have no code in this unit.
- No S9 path owned by a later unit. Offer publication stays with P4.7. Checkouts stay with P4.2. Erasure stays with P4.7. The console stays with P4.6. Enrollment, `/control/entitle`, and the entitlement, plan, and invoice tables stay on the platform track until their owning units.
- No second codebase. The Codebase cell is `abo/`.

## 6. Success Criteria

### 6.1 Measurable Outcomes

- **SC-001**: E2E-P4.1-01, E2E-P4.1-02, E2E-P4.1-03, E2E-P4.1-04, E2E-P4.1-05, E2E-P4.1-06, E2E-P4.1-07, E2E-P4.1-08, E2E-P4.1-09, and E2E-P4.1-10 pass in harness H-ABO.
- **SC-002**: Every earlier suite stays green (rule S2).

## 7. Assumptions

- No §6 open question is named by this unit's Read or Implements lines.
- Offers are seeded by a D1 fixture until offer publication in P4.7 (unit Out of scope, rule S9).
- Checkouts stay absent until P4.2. Erasure stays absent until P4.7. The operator console stays absent until P4.6 (unit Out of scope, rule S9).
