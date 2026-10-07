# Tasks: Desktop contract versions, token minting and AI status reads

**Input**: Design documents from `specs/089-abo-p6-1-desktop-contract-versions-token-minting/`

**Prerequisites**: `plan.md` (required), `spec.md` (required for user stories). Merged units in **Consumes Binding**: P5.2b (status RPC results and notice codes from `public.get_ai_status(integer)` and `auth_internal.get_ai_status(integer)` in `backend/supabase/migrations/20261008010000_read_time_status_notices.sql`). Plan artifacts from `AVAILABLE_DOCS`: none. `research.md` is omitted (no spike). `data-model.md` and `contracts/` are omitted (no entities, no freezes). `quickstart.md` is written in Documentation after this unit's H-FL tests are green.

**Organization**: P6.1 is User Story 1 and User Story 2 (`[US1]`, `[US2]`), size M (rule S3). Branch `ai/089-abo-p6-1-desktop-contract-versions-token-minting`. E2E ids stay `E2E-P6.1-01` through `E2E-P6.1-07`. Tests are one task per E2E id, written to fail before the production change, plus the plan sequencing red run. Titles start with the E2E id (rule V3). Nothing ships before P8 (rule S2). No Foundational phase. No Polish phase. No task line is marked `[P]`. Scheduling is **Implementation Waves** only.

**Task count**: 25. Size M is 20–32 (rule S3). Plan sequencing implies 24 steps; the existing `frontend/test/widget/ai/ai_degraded_mode_test.dart` row is its own task beside `ai_degraded_view.dart`. The count is not padded.

## 1. Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies). No task line is marked `[P]`. Scheduling is **Implementation Waves** only.
- **[Story]**: Which user story this task belongs to (`US1`, `US2`)
- Include exact file paths in descriptions

## 2. Path Conventions

- **Flutter desktop app**: `frontend/lib/`, `frontend/test/`
- **Harness H-FL**: `frontend/test/integration/`, `frontend/test/widget/ai/`. Widget scenarios and the contract test use the existing frontend test job. `E2E-P6.1-01` uses the `fullstack` tag against H-FS local Supabase
- **CI**: `frontend/dart_test.yaml`, `.github/workflows/ci.yml`
- **Consumed and not modified**: `backend/supabase/migrations/20261008010000_read_time_status_notices.sql`, `public.issue_ai_token(integer)` in `backend/supabase/migrations/20261007180000_issuer_key_custody.sql`, `packages/vendor-contracts/`
- **Package vector the contract test reads**: `packages/vendor-contracts/src/version.ts` (`CHANNEL_VERSIONS`)
- **Spec Kit artifacts**: `specs/089-abo-p6-1-desktop-contract-versions-token-minting/`

---

## 3. Setup

**Purpose**: Sequencing step 1. Declare the `fullstack` tag and keep it off the existing frontend test job before any H-FL test is added.

### 3.1 User Story 2 - Staff and administrators read AI status on the versioned channels (Priority: P2) — harness tag

**Independent Test**: E2E-P6.1-01, E2E-P6.1-02, E2E-P6.1-03, E2E-P6.1-04, E2E-P6.1-05, and E2E-P6.1-06 in harness H-FL. Every earlier suite stays green (rule S2).

- [X] T001 [US2] Declare the `fullstack` tag in `frontend/dart_test.yaml` and exclude it from the existing `frontend-quality` test step in `.github/workflows/ci.yml` — harness tag, FR-008, E2E-P6.1-01. Depends on nothing. In `frontend/dart_test.yaml`, declare `fullstack` next to `boundary` and `live`. In `.github/workflows/ci.yml`, change the existing `frontend-quality` `flutter test` step so it excludes the `fullstack` tag. Widget tests and `frontend/test/integration/contract_versions_test.dart` stay on that existing job. Do not add the Flutter `fullstack` CI job in this task (T023). Do not run `npm test` in `e2e/fullstack`. Do not start wrangler.

**Checkpoint**: The `fullstack` tag exists, and the existing frontend test job excludes it. No H-FL scenario is written yet.

---

## 4. Tests (H-FL)

**Purpose**: Sequencing steps 2–9. One failing test per E2E id. Titles are prefixed with the E2E id. Leave the production files in **Files** unchanged through T009.

Contract and widget command, from `frontend/`:

```bash
flutter test test/integration/contract_versions_test.dart test/widget/ai/ai_status_refresh_test.dart test/widget/ai/ai_status_notices_test.dart test/widget/ai/ai_contract_version_state_test.dart
```

Fullstack command, from `frontend/`, with local Supabase already started:

```bash
flutter test --tags fullstack test/integration/ai_status_fullstack_test.dart
```

Those two commands are the unit harness. `npm test` in `e2e/fullstack` is not the harness.

### 4.1 User Story 1 - Desktop contract constants match the package (Priority: P1) — tests

**Independent Test**: E2E-P6.1-07 in harness H-FL.

- [X] T002 [US1] Add the failing test `E2E-P6.1-07` in `frontend/test/integration/contract_versions_test.dart` — red test, FR-001, FR-008, E2E-P6.1-07. Depends on T001. Create the file. Title `E2E-P6.1-07`. The test reads `frontend/lib/core/contract_versions.dart` and `packages/vendor-contracts/src/version.ts`. It fails when any Dart constant differs from `CHANNEL_VERSIONS`, or when the Dart file is missing. It parses the package source. It does not contain a second copy of the integers. It is not tagged `fullstack`. The contract command fails because `frontend/lib/core/contract_versions.dart` is missing.

**Checkpoint**: E2E-P6.1-07 exists and fails.

### 4.2 User Story 2 - Staff and administrators read AI status on the versioned channels (Priority: P2) — tests (part 1)

**Independent Test**: E2E-P6.1-01, E2E-P6.1-02, E2E-P6.1-03, E2E-P6.1-04, E2E-P6.1-05, and E2E-P6.1-06 in harness H-FL. Every earlier suite stays green (rule S2).

- [X] T003 [US2] Add the failing test `E2E-P6.1-01` in `frontend/test/integration/ai_status_fullstack_test.dart` — red test, FR-002, FR-004, FR-005, FR-008, E2E-P6.1-01. Depends on T002. Create the file. Title `E2E-P6.1-01`. Tag the test `fullstack`. Entry is `AiPage` / `buildLiveVisitSummaryComposition` → `SupabaseAiAvailabilityReader.read` → PostgREST `get_ai_status`. Staff session on local Supabase. Seed an active projection for that org the way `e2e/fullstack/test/p5-2b.test.mjs` seeds `clinic_ai_coverage`, then the production reader shows active. `rpc_result.contract_version` equals the `backendRpc` constant sent as `p_contract_version`. The composition `PlatformNetworkSpy` records no ABO host URL. The test does not start wrangler. The fullstack command fails because the reader still calls `get_ai_availability`. E2E-P6.1-07 still fails.

**Checkpoint**: E2E-P6.1-01 exists and fails. E2E-P6.1-07 still fails.

- [X] T004 [US2] Add the failing test `E2E-P6.1-02` in `frontend/test/widget/ai/ai_status_refresh_test.dart` — red test, FR-005, FR-008, E2E-P6.1-02. Depends on T003. Create the file. Title `E2E-P6.1-02`. Pump `AiClinicApp` with the reader seam. Entry is `AiClinicApp.didChangeAppLifecycleState` and the `next_change_at` timer in `frontend/lib/app/app.dart` → the one refresh → `SupabaseAiAvailabilityReader.read`. Resume and the `next_change_at` timer each call that refresh. Each refresh's network is the backend RPC only. The widget command fails because that refresh is not wired. E2E-P6.1-01 and E2E-P6.1-07 still fail.

**Checkpoint**: E2E-P6.1-02 exists and fails. E2E-P6.1-01 and E2E-P6.1-07 still fail.

- [X] T005 [US2] Add the failing test `E2E-P6.1-03` in `frontend/test/widget/ai/ai_status_notices_test.dart` — red test, FR-006, FR-008, E2E-P6.1-03. Depends on T004. Create the file. Title `E2E-P6.1-03`. Pump the live surface (`liveVisitSummaryHostBody` / `AiFeatureHostPage`) with a fake reader and a staff role, then an administrator role. Fake status includes `ends_soon` with `days_left` 7, then 3, then 1. Staff sees "ask your administrator", no price text, and no purchase control. An administrator sees the renew control. The desktop does not decide the threshold. The widget command fails because those notice forms are absent. E2E-P6.1-01, E2E-P6.1-02, and E2E-P6.1-07 still fail.

**Checkpoint**: E2E-P6.1-03 exists and fails.

- [X] T006 [US2] Add the failing test `E2E-P6.1-04` in `frontend/test/widget/ai/ai_status_notices_test.dart` — red test, FR-006, FR-008, E2E-P6.1-04. Depends on T005 (same file). Title `E2E-P6.1-04`. The same live surface renders `allowance_low`. Staff sees "ask your administrator" and no price text. An administrator sees the renew control. The widget command fails because that notice form is absent. E2E-P6.1-01, E2E-P6.1-02, E2E-P6.1-03, and E2E-P6.1-07 still fail.

**Checkpoint**: E2E-P6.1-03 and E2E-P6.1-04 exist and fail. E2E-P6.1-05 and E2E-P6.1-06 are not written yet.

### 4.3 User Story 2 - Staff and administrators read AI status on the versioned channels (Priority: P2) — tests (part 2)

**Independent Test**: E2E-P6.1-01, E2E-P6.1-02, E2E-P6.1-03, E2E-P6.1-04, E2E-P6.1-05, and E2E-P6.1-06 in harness H-FL. Every earlier suite stays green (rule S2).

- [X] T007 [US2] Add the failing test `E2E-P6.1-05` in `frontend/test/widget/ai/ai_contract_version_state_test.dart` — red test, FR-002, FR-007, FR-008, E2E-P6.1-05. Depends on T006. Create the file. Title `E2E-P6.1-05`. Use the production reader and `SupabaseAatMintPort.mint` with a fake RPC, composed from `buildLiveVisitSummaryComposition`. A missing or unsupported `p_contract_version` answered as `CONTRACT_VERSION_UNSUPPORTED` shows "Update the app to use AI" inline and no dialog. The widget command fails because that inline state is not wired. E2E-P6.1-01 through E2E-P6.1-04 and E2E-P6.1-07 still fail.

**Checkpoint**: E2E-P6.1-05 exists and fails.

- [X] T008 [US2] Add the failing test `E2E-P6.1-06` in `frontend/test/widget/ai/ai_contract_version_state_test.dart` — red test, FR-002, FR-003, FR-007, FR-008, E2E-P6.1-06. Depends on T007 (same file). Title `E2E-P6.1-06`. Entry is `buildLiveVisitSummaryComposition` → `DiscoveryClient.fetchCapabilities`, `SupabaseAatMintPort.mint`, and `PlatformHttpsSubmitPort.submit`, with fake RPC and HTTP ports. The discovery request and the submit request carry `Aip-Contract-Version` set to `platformClinic`. The submit header is set before the body. Mint calls `issue_ai_token` with `p_contract_version` and the fake returns token text. An accepted discovery response carries the header and `contract_version` in the JSON body. HTTP 400 `contract_version_unsupported` shows the same inline update state and no dialog. The widget command fails because the header and the update state are absent. E2E-P6.1-01 through E2E-P6.1-05 and E2E-P6.1-07 still fail.

**Checkpoint**: E2E-P6.1-05 and E2E-P6.1-06 exist and fail.

### 4.4 User Story 2 - Staff and administrators read AI status on the versioned channels (Priority: P2) — red run

**Independent Test**: E2E-P6.1-01, E2E-P6.1-02, E2E-P6.1-03, E2E-P6.1-04, E2E-P6.1-05, and E2E-P6.1-06 in harness H-FL. Every earlier suite stays green (rule S2).

- [X] T009 [US2] Run the H-FL commands and confirm E2E-P6.1-01 through E2E-P6.1-07 fail — red run, FR-001, FR-008, E2E-P6.1-01, E2E-P6.1-02, E2E-P6.1-03, E2E-P6.1-04, E2E-P6.1-05, E2E-P6.1-06, E2E-P6.1-07. Depends on T008. From `frontend/`, run `flutter test test/integration/contract_versions_test.dart test/widget/ai/ai_status_refresh_test.dart test/widget/ai/ai_status_notices_test.dart test/widget/ai/ai_contract_version_state_test.dart` and confirm E2E-P6.1-02 through E2E-P6.1-07 fail. With local Supabase already started, run `flutter test --tags fullstack test/integration/ai_status_fullstack_test.dart` and confirm E2E-P6.1-01 fails. Leave the production files unchanged. Do not edit the test files in this task. Do not run `npm test` in `e2e/fullstack`. Do not start wrangler.

**Checkpoint**: E2E-P6.1-01 through E2E-P6.1-07 fail. `frontend/lib/core/contract_versions.dart` does not exist yet.

---

## 5. Implementation

**Purpose**: Sequencing steps 10–22. Starts after T009 has shown the seven tests fail. Within a subphase the tasks run in id order.

### 5.1 User Story 1 - Desktop contract constants match the package (Priority: P1) — constants

**Independent Test**: E2E-P6.1-07 in harness H-FL.

- [X] T010 [US1] Add `frontend/lib/core/contract_versions.dart` — produces the desktop channel versions, FR-001, FR-002, FR-003, E2E-P6.1-07. Depends on T009. Create the file. Integer constants for every key of `CHANNEL_VERSIONS` in `packages/vendor-contracts/src/version.ts`. `backendRpc` is the RPC argument. `platformClinic` is the platform header value. Do not edit `packages/vendor-contracts/`.

**Checkpoint**: E2E-P6.1-07 can pass. E2E-P6.1-01 through E2E-P6.1-06 still fail.

### 5.2 User Story 2 - Staff and administrators read AI status on the versioned channels (Priority: P2) — status model, reader, and mint

**Independent Test**: E2E-P6.1-01, E2E-P6.1-02, E2E-P6.1-03, E2E-P6.1-04, E2E-P6.1-05, and E2E-P6.1-06 in harness H-FL. Every earlier suite stays green (rule S2).

- [X] T011 [US2] Extend the status view in `frontend/lib/features/ai/availability/ai_availability.dart` — produces the consumed status fields, FR-004, FR-006, E2E-P6.1-01, E2E-P6.1-03, E2E-P6.1-04. Depends on T010. Carry `available`, `state`, `reason`, `days_left`, `band`, `notices[]`, `next_change_at`, `as_of`, `stale`, and `platform_base_url`. `fromJson` sets `enrolled` from `available` so the existing gate follows `get_ai_status`. Notice records stay `{code, audience, channel}` with optional `grace_days_left`. The desktop does not recompute notices, `days_left`, or coverage.

**Checkpoint**: The status model can parse the P5.2b payload. The reader still calls `get_ai_availability`.

- [X] T012 [US2] Point `SupabaseAiAvailabilityReader.read` at `get_ai_status` in `frontend/lib/features/ai/availability/ai_availability_reader.dart` — produces the versioned status read, FR-002, FR-004, FR-007, E2E-P6.1-01, E2E-P6.1-05. Depends on T011. Call PostgREST `get_ai_status` with `p_contract_version` set to `backendRpc` as the first argument. Stop calling `get_ai_availability`. Parse `rpc_result`. An `error_code` of `CONTRACT_VERSION_UNSUPPORTED` is the update state, not a dialog. A `withRpc` seam matches the existing mint port so widget tests can fake the RPC. Production still uses `SupabaseClient`.

**Checkpoint**: The production reader calls `get_ai_status` and exposes `withRpc`. Mint does not send `p_contract_version` yet.

- [X] T013 [US2] Pass `p_contract_version` from `SupabaseAatMintPort.mint` in `frontend/lib/core/ai/supabase_aat_mint_port.dart` — produces the versioned mint, FR-002, FR-007, E2E-P6.1-05, E2E-P6.1-06. Depends on T012. Call `issue_ai_token` with `p_contract_version` set to `backendRpc` and return the token text. `CONTRACT_VERSION_UNSUPPORTED` is the update state, not a dialog. Do not modify `public.issue_ai_token`.

**Checkpoint**: Mint sends `backendRpc` and returns token text. Platform clinic routes do not send `Aip-Contract-Version` yet.

### 5.3 User Story 2 - Staff and administrators read AI status on the versioned channels (Priority: P2) — discovery header

**Independent Test**: E2E-P6.1-01, E2E-P6.1-02, E2E-P6.1-03, E2E-P6.1-04, E2E-P6.1-05, and E2E-P6.1-06 in harness H-FL. Every earlier suite stays green (rule S2).

- [ ] T014 [US2] Send `Aip-Contract-Version` from `DiscoveryClient` in `frontend/lib/core/ai/discovery_client.dart` — produces the capabilities header, FR-003, FR-007, E2E-P6.1-06. Depends on T013. Set `Aip-Contract-Version` to `platformClinic` on `GET /v1/capabilities` before the request is sent. HTTP 400 with body code `contract_version_unsupported` is the update state. An accepted response is the one that carries that header and `contract_version` in the JSON body. The `/health` reachability probe does not gain this header.

**Checkpoint**: Discovery sends `platformClinic` and maps HTTP 400 `contract_version_unsupported` to the update state.

### 5.4 User Story 2 - Staff and administrators read AI status on the versioned channels (Priority: P2) — submit and usage headers

**Independent Test**: E2E-P6.1-01, E2E-P6.1-02, E2E-P6.1-03, E2E-P6.1-04, E2E-P6.1-05, and E2E-P6.1-06 in harness H-FL. Every earlier suite stays green (rule S2).

- [ ] T015 [US2] Send `Aip-Contract-Version` from `PlatformHttpsSubmitPort` in `frontend/lib/core/ai/https_submit_port.dart` — produces the requests header and the denial code, FR-003, FR-005, FR-007, E2E-P6.1-06. Depends on T013. Set `Aip-Contract-Version` to `platformClinic` on `POST /v1/requests` before the request body is assigned. Keep the response `code` string so the live surface can see `allowance_exhausted`, `coverage_lapsed`, and `coverage_unknown`. HTTP 400 `contract_version_unsupported` is the update state. The `/health` probe does not gain this header.

**Checkpoint**: Submit sets the header before the body and keeps the three coverage denial codes.

- [ ] T016 [US2] Send `Aip-Contract-Version` from `frontend/lib/core/ai/usage_summary_client.dart` — produces the usage header, FR-003, E2E-P6.1-06. Depends on T015 (same subphase). Set `Aip-Contract-Version` to `platformClinic` on `GET /v1/usage` before the request is sent. The `/health` probe does not gain this header.

**Checkpoint**: `GET /v1/capabilities`, `POST /v1/requests`, and `GET /v1/usage` send `platformClinic`.

### 5.5 User Story 2 - Staff and administrators read AI status on the versioned channels (Priority: P2) — refresh and notice forms

**Independent Test**: E2E-P6.1-01, E2E-P6.1-02, E2E-P6.1-03, E2E-P6.1-04, E2E-P6.1-05, and E2E-P6.1-06 in harness H-FL. Every earlier suite stays green (rule S2).

- [ ] T017 [US2] Refresh status from the app shell in `frontend/lib/app/app.dart` — produces the one status scheduler, FR-005, E2E-P6.1-02. Depends on T012 and T016. The existing lifecycle path calls `SupabaseAiAvailabilityReader.read` on open (after the current authenticated bootstrap), on resume (`didChangeAppLifecycleState`), at `next_change_at` from the last status, and every 5 minutes. One refresh function. Resume still reloads auth context. Expose that same function for the live composition. Those reads contact only the backend. Do not add a second scheduler or a second status client.

**Checkpoint**: Open, resume, `next_change_at`, and the 5-minute timer share one refresh. The live composition does not call it on a coverage-code denial yet.

- [ ] T018 [US2] Refresh after a coverage-code denial in `frontend/lib/features/ai/presentation/pages/ai_page.dart` — produces the denial refresh, FR-005, FR-006, E2E-P6.1-01, E2E-P6.1-03. Depends on T017. Pass `StaffRole.administrator` versus any other role from `authSessionProvider` into the live composition. The composition calls the app-shell refresh when it sees a coverage-code denial. A coverage code is `allowance_exhausted`, `coverage_lapsed`, or `coverage_unknown`. Do not add a scheduler or a second reader. Do not add `get_ai_billing_status`, the ABO API, or `/v1/coverage`.

**Checkpoint**: A denial whose code is `allowance_exhausted`, `coverage_lapsed`, or `coverage_unknown` calls the app-shell refresh. Notice forms are still absent.

- [ ] T019 [US2] Render staff and administrator notice forms in `frontend/lib/features/ai/host/ai_feature_host_page.dart` — produces the notice surface, FR-004, FR-006, FR-007, E2E-P6.1-03, E2E-P6.1-04. Depends on T018. Render `notices[]` from the status read. Staff form is the text "ask your administrator", with no price and no purchase control. Administrator form includes a visible renew control that has no navigation, mint, or billing call. A contract-version refusal shows the inline update state and no dialog. Leave the host gate change to T022.

**Checkpoint**: Staff and administrators see the notice forms. The renew control does not navigate, mint, or call billing.

### 5.6 User Story 2 - Staff and administrators read AI status on the versioned channels (Priority: P2) — update copy

**Independent Test**: E2E-P6.1-01, E2E-P6.1-02, E2E-P6.1-03, E2E-P6.1-04, E2E-P6.1-05, and E2E-P6.1-06 in harness H-FL. Every earlier suite stays green (rule S2).

- [ ] T020 [US2] Set the inline update copy in `frontend/lib/features/ai/degraded/ai_degraded_view.dart` — produces the update message, FR-007, E2E-P6.1-05, E2E-P6.1-06. Depends on T019. The existing `AiDegradedMode.appUpdate` message is "Update the app to use AI". It stays inline. No dialog.

**Checkpoint**: `AiDegradedMode.appUpdate` reads "Update the app to use AI".

- [ ] T021 [US2] Expect the update copy in `frontend/test/widget/ai/ai_degraded_mode_test.dart` — produces the existing expectation, FR-007, E2E-P6.1-05, E2E-P6.1-06. Depends on T020. The existing `appUpdate` text expectation uses "Update the app to use AI".

**Checkpoint**: The existing degraded-mode test expects "Update the app to use AI".

### 5.7 User Story 2 - Staff and administrators read AI status on the versioned channels (Priority: P2) — host gate

**Independent Test**: E2E-P6.1-01, E2E-P6.1-02, E2E-P6.1-03, E2E-P6.1-04, E2E-P6.1-05, and E2E-P6.1-06 in harness H-FL. Every earlier suite stays green (rule S2).

- [ ] T022 [US2] Drive the host gate from `available` in `frontend/lib/features/ai/host/ai_feature_host_page.dart` — produces the status gate, FR-004, E2E-P6.1-01. Depends on T021. Same file as T019. `available` from the status read drives the existing gate. Do not call `get_ai_availability`.

**Checkpoint**: The live surface follows `available` from `get_ai_status`. The Flutter `fullstack` CI job is not added yet.

### 5.8 User Story 2 - Staff and administrators read AI status on the versioned channels (Priority: P2) — fullstack CI job

**Independent Test**: E2E-P6.1-01, E2E-P6.1-02, E2E-P6.1-03, E2E-P6.1-04, E2E-P6.1-05, and E2E-P6.1-06 in harness H-FL. Every earlier suite stays green (rule S2).

- [ ] T023 [US2] Add the Flutter `fullstack` job in `.github/workflows/ci.yml` — produces the H-FL CI job, FR-008, E2E-P6.1-01. Depends on T022. The `frontend-quality` step already excludes `fullstack` (T001). Add one job that starts local Supabase (`supabase start` in `backend/`) and runs `flutter test --tags fullstack` in `frontend/`. That job does not run `npm test` and does not start wrangler. The Dart test does not boot workers.

**Checkpoint**: CI has a Flutter `fullstack` job aimed at local Supabase, and the existing frontend job still excludes that tag.

---

## 6. Verification (H-FL)

**Purpose**: Sequencing step 23. The unit harness passes. This is not a repo-wide command.

### 6.1 User Story 2 - Staff and administrators read AI status on the versioned channels (Priority: P2) — H-FL harness

**Independent Test**: E2E-P6.1-01, E2E-P6.1-02, E2E-P6.1-03, E2E-P6.1-04, E2E-P6.1-05, and E2E-P6.1-06 in harness H-FL. Every earlier suite stays green (rule S2).

- [ ] T024 [US2] Re-run the two H-FL commands until E2E-P6.1-01 through E2E-P6.1-07 pass — green harness, FR-001, FR-002, FR-003, FR-004, FR-005, FR-006, FR-007, FR-008, E2E-P6.1-01, E2E-P6.1-02, E2E-P6.1-03, E2E-P6.1-04, E2E-P6.1-05, E2E-P6.1-06, E2E-P6.1-07. Depends on T023. From `frontend/`, run `flutter test test/integration/contract_versions_test.dart test/widget/ai/ai_status_refresh_test.dart test/widget/ai/ai_status_notices_test.dart test/widget/ai/ai_contract_version_state_test.dart` and, with local Supabase already started, `flutter test --tags fullstack test/integration/ai_status_fullstack_test.dart`, until E2E-P6.1-01 through E2E-P6.1-07 pass. Fixes stay in the files this unit's **Files** table lists under `frontend/`. Do not run `npm test` in `e2e/fullstack`. Do not start wrangler. Do not edit `packages/vendor-contracts/` or the P5.2b migration.

**Checkpoint**: E2E-P6.1-01 through E2E-P6.1-07 pass in H-FL.

---

## 7. Documentation

**Purpose**: Sequencing step 24. `quickstart.md` after the harness is green. Plan-phase `research.md`, `data-model.md`, and `contracts/` stay omitted.

### 7.1 User Story 2 - Staff and administrators read AI status on the versioned channels (Priority: P2) — quickstart

**Independent Test**: E2E-P6.1-01, E2E-P6.1-02, E2E-P6.1-03, E2E-P6.1-04, E2E-P6.1-05, and E2E-P6.1-06 in harness H-FL. Every earlier suite stays green (rule S2).

- [ ] T025 [US2] Write `specs/089-abo-p6-1-desktop-contract-versions-token-minting/quickstart.md` — unit quickstart, FR-001, FR-008, E2E-P6.1-01, E2E-P6.1-02, E2E-P6.1-03, E2E-P6.1-04, E2E-P6.1-05, E2E-P6.1-06, E2E-P6.1-07. Depends on T024. Fill only these sections: what was implemented and the files added or modified; the harness commands for this unit's tests only, from `frontend/`, `flutter test test/integration/contract_versions_test.dart test/widget/ai/ai_status_refresh_test.dart test/widget/ai/ai_status_notices_test.dart test/widget/ai/ai_contract_version_state_test.dart` and, with local Supabase already started, `flutter test --tags fullstack test/integration/ai_status_fullstack_test.dart`; the entry point → module chain per E2E id. Do not list earlier-unit files, combined counts, or full-suite commands. Manual steps are omitted: the harness sees this behaviour.

**Checkpoint**: `quickstart.md` names the seven H-FL ids, the two unit commands, and the entry chain.

---

## 8. Dependencies & Execution Order

### 8.1 Phase Dependencies

- **Setup (Phase 3)**: T001 declares `fullstack` in `frontend/dart_test.yaml` and excludes that tag from the existing `frontend-quality` step in `.github/workflows/ci.yml`. The new CI job is T023, in the same workflow file, after the desktop changes.
- **Tests (Phase 4)**: Start after T001. T002 adds the User Story 1 contract test. T003 through T006 add E2E-P6.1-01 through E2E-P6.1-04. T007 and T008 add E2E-P6.1-05 and E2E-P6.1-06 in `frontend/test/widget/ai/ai_contract_version_state_test.dart`. T009 runs the two harness commands and confirms all seven fail before `frontend/lib/core/contract_versions.dart` exists.
- **Implementation (Phase 5)**: Starts after T009. User Story 1 adds the constants file. User Story 2 then extends the status model, points the reader at `get_ai_status`, versions the mint, sends `Aip-Contract-Version` on the three platform clinic routes, refreshes from the app shell and on a coverage-code denial, renders notice forms, sets the update copy, drives the host gate from `available`, and adds the CI job.
- **Verification (Phase 6)**: Starts after T023. Two commands from `frontend/`, as in T009, until the seven ids pass.
- **Documentation (Phase 7)**: Starts after T024 is green. One file: `quickstart.md`.

### 8.2 User Story Dependencies

- **User Story 1 (P1)**: The failing contract test is T002. The constants file is T010, after the red run. E2E-P6.1-07 is included in the red run (T009) and the green harness (T024).
- **User Story 2 (P2)**: Starts at T001 so the `fullstack` tag exists before T003. Its tests are T003 through T008. Its implementation is T011 through T023. Status reads, mint, platform headers, refresh, and notice forms use the constants from T010.

### 8.3 Within Each Phase

- T002 creates `frontend/test/integration/contract_versions_test.dart`. T003 creates `frontend/test/integration/ai_status_fullstack_test.dart`. T004 creates `frontend/test/widget/ai/ai_status_refresh_test.dart`. T005 creates `frontend/test/widget/ai/ai_status_notices_test.dart` and T006 writes that same file. T007 creates `frontend/test/widget/ai/ai_contract_version_state_test.dart` and T008 writes that same file. T009 runs the harness and does not edit those files.
- T010 creates `frontend/lib/core/contract_versions.dart`. T011 writes `frontend/lib/features/ai/availability/ai_availability.dart`. T012 writes `frontend/lib/features/ai/availability/ai_availability_reader.dart`. T013 writes `frontend/lib/core/ai/supabase_aat_mint_port.dart`. T014 writes `frontend/lib/core/ai/discovery_client.dart`. T015 writes `frontend/lib/core/ai/https_submit_port.dart`. T016 writes `frontend/lib/core/ai/usage_summary_client.dart`. T017 writes `frontend/lib/app/app.dart`. T018 writes `frontend/lib/features/ai/presentation/pages/ai_page.dart`. T019 and T022 write `frontend/lib/features/ai/host/ai_feature_host_page.dart`, in that id order. T020 writes `frontend/lib/features/ai/degraded/ai_degraded_view.dart`. T021 writes `frontend/test/widget/ai/ai_degraded_mode_test.dart`. T023 adds the job to `.github/workflows/ci.yml`.
- T024 runs after T023 and may edit only the `frontend/` files listed in this unit's **Files** table.
- T025 writes only `specs/089-abo-p6-1-desktop-contract-versions-token-minting/quickstart.md` after T024 is green.

---

## 9. Implementation Waves

T014 and T015–T016 edit different clients and both follow the mint. They share no path, so that wave has two bullets. Every other subphase is serial with the one before it.

### 9.1 Wave 1

- T001 [US2] — subphase: `### 3.1 User Story 2 - Staff and administrators read AI status on the versioned channels (Priority: P2) — harness tag` — paths: `frontend/dart_test.yaml`, `.github/workflows/ci.yml`

### 9.2 Wave 2

- T002 [US1] — subphase: `### 4.1 User Story 1 - Desktop contract constants match the package (Priority: P1) — tests` — paths: `frontend/test/integration/contract_versions_test.dart`

### 9.3 Wave 3

- T003–T006 [US2] — subphase: `### 4.2 User Story 2 - Staff and administrators read AI status on the versioned channels (Priority: P2) — tests (part 1)` — paths: `frontend/test/integration/ai_status_fullstack_test.dart`, `frontend/test/widget/ai/ai_status_refresh_test.dart`, `frontend/test/widget/ai/ai_status_notices_test.dart`

### 9.4 Wave 4

- T007–T008 [US2] — subphase: `### 4.3 User Story 2 - Staff and administrators read AI status on the versioned channels (Priority: P2) — tests (part 2)` — paths: `frontend/test/widget/ai/ai_contract_version_state_test.dart`

### 9.5 Wave 5

- T009 [US2] — subphase: `### 4.4 User Story 2 - Staff and administrators read AI status on the versioned channels (Priority: P2) — red run` — paths: `frontend/test/integration/contract_versions_test.dart`, `frontend/test/integration/ai_status_fullstack_test.dart`, `frontend/test/widget/ai/ai_status_refresh_test.dart`, `frontend/test/widget/ai/ai_status_notices_test.dart`, `frontend/test/widget/ai/ai_contract_version_state_test.dart`

### 9.6 Wave 6

- T010 [US1] — subphase: `### 5.1 User Story 1 - Desktop contract constants match the package (Priority: P1) — constants` — paths: `frontend/lib/core/contract_versions.dart`

### 9.7 Wave 7

- T011–T013 [US2] — subphase: `### 5.2 User Story 2 - Staff and administrators read AI status on the versioned channels (Priority: P2) — status model, reader, and mint` — paths: `frontend/lib/features/ai/availability/ai_availability.dart`, `frontend/lib/features/ai/availability/ai_availability_reader.dart`, `frontend/lib/core/ai/supabase_aat_mint_port.dart`

### 9.8 Wave 8

- T014 [US2] — subphase: `### 5.3 User Story 2 - Staff and administrators read AI status on the versioned channels (Priority: P2) — discovery header` — paths: `frontend/lib/core/ai/discovery_client.dart`
- T015–T016 [US2] — subphase: `### 5.4 User Story 2 - Staff and administrators read AI status on the versioned channels (Priority: P2) — submit and usage headers` — paths: `frontend/lib/core/ai/https_submit_port.dart`, `frontend/lib/core/ai/usage_summary_client.dart`

### 9.9 Wave 9

- T017–T019 [US2] — subphase: `### 5.5 User Story 2 - Staff and administrators read AI status on the versioned channels (Priority: P2) — refresh and notice forms` — paths: `frontend/lib/app/app.dart`, `frontend/lib/features/ai/presentation/pages/ai_page.dart`, `frontend/lib/features/ai/host/ai_feature_host_page.dart`

### 9.10 Wave 10

- T020–T021 [US2] — subphase: `### 5.6 User Story 2 - Staff and administrators read AI status on the versioned channels (Priority: P2) — update copy` — paths: `frontend/lib/features/ai/degraded/ai_degraded_view.dart`, `frontend/test/widget/ai/ai_degraded_mode_test.dart`

### 9.11 Wave 11

- T022 [US2] — subphase: `### 5.7 User Story 2 - Staff and administrators read AI status on the versioned channels (Priority: P2) — host gate` — paths: `frontend/lib/features/ai/host/ai_feature_host_page.dart`

### 9.12 Wave 12

- T023 [US2] — subphase: `### 5.8 User Story 2 - Staff and administrators read AI status on the versioned channels (Priority: P2) — fullstack CI job` — paths: `.github/workflows/ci.yml`

### 9.13 Wave 13

- T024 [US2] — subphase: `### 6.1 User Story 2 - Staff and administrators read AI status on the versioned channels (Priority: P2) — H-FL harness` — paths: `frontend/lib/core/contract_versions.dart`, `frontend/lib/features/ai/availability/ai_availability.dart`, `frontend/lib/features/ai/availability/ai_availability_reader.dart`, `frontend/lib/core/ai/supabase_aat_mint_port.dart`, `frontend/lib/core/ai/discovery_client.dart`, `frontend/lib/core/ai/https_submit_port.dart`, `frontend/lib/core/ai/usage_summary_client.dart`, `frontend/lib/app/app.dart`, `frontend/lib/features/ai/presentation/pages/ai_page.dart`, `frontend/lib/features/ai/host/ai_feature_host_page.dart`, `frontend/lib/features/ai/degraded/ai_degraded_view.dart`, `frontend/test/widget/ai/ai_degraded_mode_test.dart`, `frontend/test/integration/contract_versions_test.dart`, `frontend/test/integration/ai_status_fullstack_test.dart`, `frontend/test/widget/ai/ai_status_refresh_test.dart`, `frontend/test/widget/ai/ai_status_notices_test.dart`, `frontend/test/widget/ai/ai_contract_version_state_test.dart`, `frontend/dart_test.yaml`, `.github/workflows/ci.yml`

### 9.14 Wave 14

- T025 [US2] — subphase: `### 7.1 User Story 2 - Staff and administrators read AI status on the versioned channels (Priority: P2) — quickstart` — paths: `specs/089-abo-p6-1-desktop-contract-versions-token-minting/quickstart.md`
