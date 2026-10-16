# Feature Specification: Contract version matrix

**Feature Branch**: `ai/095-abo-p7-3-contract-version-matrix`

**Created**: 2026-10-08

**Status**: Draft

**Input**: P7.3 — Contract version matrix

## 1. Unit Contract

**Implements** — Read: 04 §7; 05 §6.1 ("Version matrix" bullet); 05 §4 row FM-25.

- A matrix harness that builds receivers and senders with overridden package constants (N+1) and runs every 04 §7.1 channel with N, N−1 and unsupported.

**Freezes** — None. The unit row states no Outputs / freezes line.

**Consumes** — P6.4: None. The unit row states no Outputs / freezes line. P4.11: None. The unit row states no Outputs / freezes line.

**Open questions relied on** — None.

**Spikes** — None.

## 2. User Scenarios & Testing

### 2.1 User Story 1 - Each channel accepts N and N−1 (Priority: P1)

A caller on the current version N, or on the previous version N−1, is accepted and answered in the version it sent. A missing version, or a version outside N and N−1, receives that channel's refusal before authentication and before any write. A Worker on N calling a DO whose current version is N+1 is the gradual-rollout pairing and is accepted. A desktop below the minimum version shows the update state on the three desktop channels. An unknown `v` on the Paymob return URL still schedules an inquiry.

**Why this priority**: User Story 2 parks work and keeps the feed cursor only after these channels refuse. The matrix harness is the story those checks use.

**Independent Test**: E2E-P7.3-01, E2E-P7.3-05, E2E-P7.3-06, and E2E-P7.3-07.

**Acceptance Scenarios**:

1. **Given** each of the ten 04 §7.1 channels, with receivers and senders built from overridden package constants, **When** the sender uses N, **Then** the receiver accepts it and answers in N. **When** the sender uses N−1, **Then** the receiver accepts it and answers in N−1. **When** the version is missing or outside N and N−1, **Then** the channel's refusal is returned, the check runs before authentication and before any write, and nothing changes. The refusal is that channel's own: HTTP 400 `contract_version_unsupported` with `accepted_versions` on the ABO clinic API and on platform clinic routes; the same on the ABO console, and the console asks for a reload; error `CONTRACT_VERSION_UNSUPPORTED` on backend RPCs. Those five PostgREST functions stay the published bodies outside the case: the backend test variant replaces only their `public` gates so the accepted pair is `(1, 2)` (receiver current is the published N+1, N−1 is the published current `1`), then restores `(0, 1)` before it exits. Other channel refusals: HTTP 400 `contract_version_unsupported` on the platform feed, and the puller keeps its cursor and the stale alert fires; `rejected` with `contract_version_unsupported` on `VendorEntrypoint`; `rejected` with `contract_version_unsupported` and `accepted_versions` on the per-clinic DO, which the Worker maps to `coverage_unknown`; no refusal on the Paymob return URL; an unparseable Paymob shape is an A23 alert and the adapter records `adapter_version`; a token `ver` the platform's `token_contract` or the ABO's accepted list does not accept is `unauthenticated`. A sender that receives an answer in a version it does not know treats that answer as `contract_version_unsupported`. (E2E-P7.3-01, 04 §7.1, 04 §7.2, 05 §6.1)
2. **Given** a Worker on N and a DO whose current version is N+1, **When** the Worker calls the DO, **Then** the call is accepted and answered in N, the version the call used. That DO is the 04 §7.3 step-1 receiver: it accepts N and N+1. The Worker's N is that DO's N−1, so the 04 §7.1 gradual-rollout pairing succeeds. **When** the version is missing or outside the DO's N and N−1, **Then** the DO answers `rejected` with `contract_version_unsupported` and `accepted_versions`, and the Worker maps that refusal to `coverage_unknown`. (E2E-P7.3-05, 04 §7.1, 04 §7.3)
3. **Given** a desktop below the minimum supported version, **When** it calls the ABO clinic API, a backend RPC, or a platform clinic route, **Then** each of those three channels shows the "update the app" state and never an error dialog. (E2E-P7.3-06, 04 §7.3)
4. **Given** a Paymob return URL whose `v` query parameter is not this channel's version, **When** the browser opens that URL, **Then** an inquiry is still scheduled and the page is neutral. (E2E-P7.3-07, 04 §7.1)

### 2.2 User Story 2 - Sender ahead of the receiver (Priority: P2)

An ABO on N+1 calling a platform still on N is rejected, the work row is parked, and AL-07 fires. After the platform is deployed so it accepts N and N+1, a retry applies. A feed puller on N against a platform that accepts only N+1 keeps its cursor and stays stale. A retried work row resends the envelope it stored, in that envelope's original version.

**Why this priority**: User Story 1 fixes what N, N−1, and an unsupported version do on each channel. This story is the cross-deploy failure FM-25 and the stored-envelope retry.

**Independent Test**: E2E-P7.3-02, E2E-P7.3-03, and E2E-P7.3-04 in their harnesses. Earlier suites stay green, and E2E-P7.3-01, E2E-P7.3-05, E2E-P7.3-06, and E2E-P7.3-07 still pass.

**Acceptance Scenarios**:

1. **Given** an ABO on N+1 and a platform on N, **When** the ABO sends a `VendorEntrypoint` call, **Then** the platform answers `rejected` with `contract_version_unsupported`, nothing is written, the work row is parked, and AL-07 fires. **When** the platform is then deployed so it accepts N and N+1, and the parked row is retried, **Then** the retry applies. (E2E-P7.3-02, FM-25, 04 §7.3, 05 §4)
2. **Given** a feed puller on N and a platform that accepts only N+1, **When** the puller requests the coverage feed, **Then** the platform answers HTTP 400, the puller keeps its cursor, and the stale alert fires. Nothing is written. (E2E-P7.3-03, FM-25, 04 §7.1, 05 §4)
3. **Given** a work row whose stored envelope was written at a `contract_version`, **When** that row is retried, **Then** the resend uses that stored envelope in its original version. The stored `contract_version` is not rewritten. (E2E-P7.3-04, 04 §7.2)

### 2.3 Test plan

| ID | Harness | Entry point | Assertion (+ tags) | Proves | Story |
| --- | --- | --- | --- | --- | --- |
| E2E-P7.3-01 | H-FS and per-codebase test variants with overridden package constants (rule V5) | ABO clinic `handleBillingV1` (`abo/src/worker.ts`) via `checkContractVersion` channel `aboClinic` (`abo/src/clinic-api/version.ts`); ABO console `handleOps` (`abo/src/worker.ts`) via `checkContractVersion` channel `aboConsole`; PostgREST RPCs that take `p_contract_version` (`get_ai_status`, `issue_ai_token`, `issue_billing_token`, `get_ai_billing_status`, `request_ai_status_refresh`); platform `fetch` (`ai-platform/src/worker.ts`) `requireAipContractVersion` on `GET /v1/capabilities`, `POST /v1/requests`, and `GET /v1/coverage`; platform `GET /v1/feed/coverage` negotiating `CHANNEL_VERSIONS.platformFeed`; `VendorEntrypoint` (`ai-platform/src/vendor/entrypoint.ts`); `GatewayObject.fetch` (`ai-platform/src/worker.ts`); `GET /return/paymob` (`abo/src/notify/intake.ts` `handleGetReturnPaymob`); `POST /notify/paymob` (`abo/src/notify/intake.ts`) recording `adapter_version`; platform token check `ai-platform/src/identity/index.ts` (`token_contract` on `ver`) and ABO `authenticateBilling` (`abo/src/clinic-api/auth.ts`) | Per channel (all ten rows of 04 §7.1): N accepted and answered in N; N−1 accepted and answered in N−1; unsupported → that channel's refusal, checked before auth and before any write. Return URL refusal is none. An unparseable Paymob shape is an A23 alert. A token `ver` outside the accepted list is `unauthenticated`. The five PostgREST RPCs use the backend test variant: accepted pair `(1, 2)` for the case, published `(0, 1)` restored before the variant exits | FR-001 | User Story 1 |
| E2E-P7.3-02 | H-FS | ABO minute `scheduled()` (`abo/src/worker.ts`) → `runMinuteInquiryBudget` → `runDueGrantWork` (`abo/src/work/grant.ts`) calling `VendorEntrypoint.grant` (`ai-platform/src/vendor/entrypoint.ts`). AL-07 is captured from `send_email` (rule V6). Retry after the platform deploy is the same grant work, also reached by `POST /ops/parked/{id}/retry` (`handlePostRetry` in `abo/src/ops/index.ts`) | FM-25: ABO on N+1 against a platform on N → `rejected` → row parked + AL-07; deploy the platform accepting N and N+1 → retry applies | FR-005 | User Story 2 |
| E2E-P7.3-03 | H-FS | pg_cron `auth_internal.pull_coverage_feed()` sending `Aip-Contract-Version`, and platform `GET /v1/feed/coverage` (`ai-platform/src/worker.ts`). The cursor is `ai_internal.feed_state.cursor` | Feed puller on N against a platform accepting only N+1 → cursor kept, stale [FM-25] | FR-006 | User Story 2 |
| E2E-P7.3-04 | H-FS | ABO work retry: minute `scheduled()` → `runDueGrantWork` (`abo/src/work/grant.ts`), and `POST /ops/parked/{id}/retry` (`handlePostRetry` in `abo/src/ops/index.ts`) | A retried work row resends its stored envelope in its original version | FR-007 | User Story 2 |
| E2E-P7.3-05 | H-FS and the platform test variant with overridden package constants | Worker admission `POST /v1/requests` (`ai-platform/src/worker.ts`) calling the per-clinic DO `GatewayObject.fetch` (`ai-platform/src/worker.ts`) with `contract_version` | Worker on N with a DO whose current version is N+1 → accepted and answered in N, the version the call used. `coverage_unknown` only when the version is missing or outside the DO's N and N−1 | FR-002 | User Story 1 |
| E2E-P7.3-06 | H-FL on H-FS | Desktop ABO clinic calls `AboClient` (`frontend/lib/features/ai/billing/abo_client.dart`) shown by `AdministratorBillingPage`; RPC calls `AiAvailabilityReader`, `BillingTokenClient`, and `SubscriptionSummary` shown by `AiPage` and `CheckoutScreen`; platform clinic calls `DiscoveryClient` and `HttpsSubmitPort` shown by `AiPage`. The update state is `AiDegradedView` mode `appUpdate`, composed in `AiPage` (`frontend/lib/app/router.dart`) and `AdministratorBillingPage` | Desktop below the minimum version → update state on all three desktop channels (04 §7.3) | FR-003 | User Story 1 |
| E2E-P7.3-07 | H-FS | ABO `GET /return/paymob` (`handleGetReturnPaymob` in `abo/src/notify/intake.ts`). `v` is the query on the `return_url` from `paymobReturnUrl` (`abo/src/clinic-api/checkouts.ts`) | Unknown `v` on the return URL → inquiry still scheduled. **CP-F follows this unit.** | FR-004 | User Story 1 |

### 2.4 Edge Cases

- A missing version, or a version outside N and N−1, gets `contract_version_unsupported` with `accepted_versions`. The check runs before authentication and before any write, so nothing changes. (E2E-P7.3-01, 04 §7.2)
- The ABO console uses the clinic API's refusal, and the console asks for a reload. (E2E-P7.3-01, 04 §7.1)
- The platform feed answers HTTP 400. The puller keeps its cursor and the stale alert fires. (E2E-P7.3-01, E2E-P7.3-03, 04 §7.1)
- `VendorEntrypoint` answers `rejected` with `contract_version_unsupported`. Nothing is written and the ABO parks the row. AL-07 fires for that channel. (E2E-P7.3-01, E2E-P7.3-02, FM-25)
- The DO answers `rejected` with `contract_version_unsupported` and `accepted_versions` only when the version is missing or outside its N and N−1. The Worker maps that refusal to `coverage_unknown`. A DO whose current version is N+1 accepts the Worker's N and answers in N. (E2E-P7.3-05, 04 §7.1)
- A sender that receives an answer in a version it does not know treats it as `contract_version_unsupported`. (E2E-P7.3-01, 04 §7.2)
- An unknown `v` on `/return/{provider}` still schedules an inquiry and shows a neutral page. (E2E-P7.3-07, 04 §7.1)
- A Paymob body the adapter cannot parse is an A23 alert. The adapter records `adapter_version` on the evidence row. (E2E-P7.3-01, 04 §7.1)
- A token `ver` outside `token_contract`, or outside the ABO's accepted list, is `unauthenticated`. (E2E-P7.3-01, 04 §7.1)
- A desktop below the minimum version shows the "update the app" state on the ABO clinic API, the RPCs, and the platform clinic routes, and never an error dialog. (E2E-P7.3-06, 04 §7.3)
- A retried work row resends its stored envelope in the `contract_version` it was written in. Stored payloads are not rewritten. (E2E-P7.3-04, 04 §7.2)

## 3. Requirements

### 3.1 Functional Requirements

- **FR-001**: The matrix harness MUST build receivers and senders with overridden package constants (N+1) and MUST run every 04 §7.1 channel with N, N−1, and an unsupported version. A receiver MUST accept N and N−1 and MUST answer in the version the request used. A missing version, or a version outside N and N−1, MUST get that channel's refusal before authentication and before any write, so nothing changes. Channel refusals: ABO clinic API HTTP 400 `contract_version_unsupported` with `accepted_versions`, and `Abo-Contract-Version` plus `contract_version` in the body; ABO console the same, and the console asks for a reload; backend RPCs error `CONTRACT_VERSION_UNSUPPORTED` with `contract_version` in `rpc_result`. `get_ai_status`, `issue_ai_token`, `issue_billing_token`, `get_ai_billing_status`, and `request_ai_status_refresh` do not import the package and do not read `ai.contract_versions`. The backend test variant MUST replace those five `public` gates for the RPC cases so the accepted pair is `(1, 2)`: receiver current is `2` (published N+1) and N−1 is `1`. A missing version, or a version outside `{1, 2}`, is `CONTRACT_VERSION_UNSUPPORTED` with `accepted_versions` `[1, 2]` before authentication and before any write; an `rpc_result` refusal carries `contract_version` `2`. `issue_ai_token` still raises. `auth_internal` bodies stay published. The variant MUST restore the published `(0, 1)` public bodies before it exits. It MUST NOT add a migration, MUST NOT update `ai.contract_versions`, and MUST NOT change `packages/vendor-contracts`. Other channel refusals: platform clinic routes HTTP 400 `contract_version_unsupported`, header `Aip-Contract-Version` sent before the first byte of a stream; platform feed HTTP 400 `contract_version_unsupported`, and the puller keeps its cursor and the stale alert fires; `VendorEntrypoint` `rejected` with `contract_version_unsupported`; per-clinic DO `rejected` with `contract_version_unsupported` and `accepted_versions`. The Paymob return URL has no version refusal. A Paymob shape the adapter cannot parse is an A23 alert, and the adapter records `adapter_version`. Tokens keep their own `ver` claim (`"2"` at launch); the platform checks `token_contract` and the ABO its accepted list; a `ver` outside that list is `unauthenticated`. A sender that receives an answer in a version it does not know MUST treat it as `contract_version_unsupported`. (04 §7.1, 04 §7.2, 05 §6.1, E2E-P7.3-01)
- **FR-002**: A Worker on N calling a DO whose current version is N+1 MUST be accepted and answered in N, the version the call used. That DO is the 04 §7.3 step-1 receiver and MUST accept N and N+1. The Worker's N is that DO's N−1. The Worker MUST map a DO `rejected` `contract_version_unsupported` to `coverage_unknown` only when the version is missing or outside the DO's N and N−1. (04 §7.1, 04 §7.3, E2E-P7.3-05)
- **FR-003**: A desktop below the minimum supported version MUST show the "update the app" state, and MUST NOT show an error dialog, on all three desktop-facing channels: the ABO clinic API, the backend RPCs, and the platform clinic routes. (04 §7.3, E2E-P7.3-06)
- **FR-004**: An unknown `v` on the Paymob return URL MUST still schedule an inquiry and MUST show a neutral page. `v` is this channel's integer contract version, set to the current version when the ABO builds `return_url` (1 at launch). (04 §7.1, E2E-P7.3-07)
- **FR-005**: An ABO on N+1 against a platform on N MUST receive `rejected` with `contract_version_unsupported`. Nothing MUST be written. The ABO MUST park the row and MUST raise AL-07. After the platform is deployed so it accepts N and N+1, a retry of that parked row MUST apply. (05 §4 FM-25, 04 §7.3, E2E-P7.3-02)
- **FR-006**: A feed puller on N against a platform that accepts only N+1 MUST receive HTTP 400. The puller MUST keep its cursor, and the stale alert MUST fire. Nothing MUST be written. (04 §7.1, 05 §4 FM-25, E2E-P7.3-03)
- **FR-007**: A retried work row MUST resend its stored envelope in its original version. Stored payloads MUST keep the `contract_version` they were written in and MUST NOT be rewritten. (04 §7.2, E2E-P7.3-04)

### 3.2 Key Entities

Not applicable — this unit defines no entities.

## 4. Constitution Alignment

### 4.1 Architecture & Operations Impact

- **Codebase**: `e2e/fullstack/` + per-codebase test variants. That is the wiring the unit row names (rule S3). `plan.md` re-runs the constitution check in 02 §7 (rule S12).
- **Clinic Fit**: A clinic on the current or previous contract version keeps working. A desktop below the minimum version is told to update the app. A version the other side does not accept does not write a grant or move the feed cursor. The suite serves small-to-mid-size multi-branch clinics by proving that on the local full stack and the per-codebase variants.
- **Layer Placement**: The matrix runs in H-FS (`e2e/fullstack/`) and in per-codebase test variants with overridden package constants. It calls the ABO worker `fetch` and `scheduled()`, the platform worker `fetch`, `VendorEntrypoint`, the per-clinic DO, PostgREST RPCs, `auth_internal.pull_coverage_feed()`, and the desktop clients composed in the app shell. It defines no new store.
- **Data Integrity & Security**: The version check runs before authentication and before any write. A rejected grant parks the work row and raises AL-07. The feed cursor stays put. Stored envelopes keep their original `contract_version`. Token `ver` outside the accepted list is `unauthenticated`. (04 §7.1, 04 §7.2, 05 §4 FM-25)
- **Failure Handling**: An unsupported version receives that channel's refusal and changes nothing. FM-25 parks the ABO row or keeps the feed cursor. `coverage_unknown` is only the Worker's mapping of a DO refusal outside the DO's N and N−1. A desktop below the minimum shows the update state. An unknown return-URL `v` still schedules an inquiry. (E2E-P7.3-01, E2E-P7.3-02, E2E-P7.3-03, E2E-P7.3-05, E2E-P7.3-06, E2E-P7.3-07)

## 5. Out of Scope

- The unit row states no Out of scope line.
- No Do-not-read material. The unit row names none.
- No rewrite of consumed contracts. P6.4 and P4.11 state no Outputs / freezes line. This unit does not change the frozen package field rules or the version constants those units already published. It overrides constants only inside test variants.
- No module that no test-plan row reaches (rule S8). The P2.2 and package-half P2.1 exception does not apply. The ten 04 §7.1 channels are reached by E2E-P7.3-01. The ABO grant park, AL-07, and the retry after the platform accepts N and N+1 are reached by E2E-P7.3-02. The feed cursor is reached by E2E-P7.3-03. The stored-envelope resend is reached by E2E-P7.3-04. The Worker-to-DO call is reached by E2E-P7.3-05. The three desktop channels are reached by E2E-P7.3-06. The return URL is reached by E2E-P7.3-07.
- The heartbeat ping and `send_email` alerts carry no contract payload (04 §7.1).
- No S9 path owned by a later unit. This unit names no transitional path. Staging profile and H-STG stay with P8.1. STG-A01–STG-A36 stay with P8.2. Launch checks stay with P8.3.
- No codebase beyond `e2e/fullstack/` and the per-codebase test variants the unit row names.
- No migration and no edit to the published five PostgREST version gates or to `packages/vendor-contracts`. The RPC receiver at N+1 exists only inside the backend test variant and is restored before that variant exits.

## 6. Success Criteria

### 6.1 Measurable Outcomes

- **SC-001**: E2E-P7.3-01, E2E-P7.3-02, E2E-P7.3-03, E2E-P7.3-04, E2E-P7.3-05, E2E-P7.3-06, and E2E-P7.3-07 pass in the harness named for each row.
- **SC-002**: Every earlier suite stays green (rule S2).
- **SC-003**: CP-F holds after this unit: the version matrix is green, earlier suites stay green, and the checkpoint question is met — the design is fully implemented (diff 02–05 against the code, no `/control/*` residue, version matrix green). That is the gate to staging (rule S11).

## 7. Assumptions

- This unit relies on no §6 default. Its Read and Implements lines name none.
- Rule S9: this unit names no transitional path.
- The five PostgREST RPCs (`get_ai_status`, `issue_ai_token`, `issue_billing_token`, `get_ai_billing_status`, `request_ai_status_refresh`) accept only the literals `(0, 1)` and do not read `ai.contract_versions` or `CHANNEL_VERSIONS`. Overriding package constants cannot move their current version, and this unit does not change those published bodies. The backend per-codebase test variant overrides the receiver for the E2E-P7.3-01 RPC cases by replacing those five `public` function bodies so the accepted pair is `(1, 2)`: receiver current is the published N+1 (`2`), and N−1 is the published current (`1`). Success answers in the version the call used. A missing version, or a version outside `{1, 2}`, is `CONTRACT_VERSION_UNSUPPORTED` before authentication and before any write, with `accepted_versions` `[1, 2]`; an `rpc_result` refusal carries `contract_version` `2`. `issue_ai_token` still raises. `auth_internal` bodies stay the published functions. The variant restores the published `(0, 1)` public bodies before it exits. It writes no migration, does not update `ai.contract_versions`, and does not change `packages/vendor-contracts`. Receivers that import `CHANNEL_VERSIONS` still use overridden package constants.
