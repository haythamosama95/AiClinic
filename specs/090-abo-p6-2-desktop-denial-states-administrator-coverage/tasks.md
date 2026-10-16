# Tasks: Desktop denial states and the administrator coverage view

**Input**: Design documents from `specs/090-abo-p6-2-desktop-denial-states-administrator-coverage/`

**Prerequisites**: `plan.md` (required), `spec.md` (required for user stories). Merged units in **Consumes Binding**: none. Plan summary **Depends**: P6.1. P6.1 freezes nothing for this unit. Plan artifacts from `AVAILABLE_DOCS`: none. `research.md` is omitted (no spike). `data-model.md` and `contracts/` are omitted (no entities, no freezes). `quickstart.md` is written in Documentation after this unit's H-FL tests are green.

**Organization**: P6.2 is User Story 1 and User Story 2 (`[US1]`, `[US2]`), size M (rule S3). Branch `ai/090-abo-p6-2-desktop-denial-states-administrator-coverage`. E2E ids stay `E2E-P6.2-01` through `E2E-P6.2-07`. Tests are one task per E2E id, written to fail before the production change, plus the plan sequencing red run. Titles start with the E2E id (rule V3). Nothing ships before P8 (rule S2). No Setup phase. No Foundational phase. No Polish phase. No task line is marked `[P]`. Scheduling is **Implementation Waves** only.

**Task count**: 22. Size M is 20–32 (rule S3). Plan sequencing implies 21 steps. One task per **Files** row splits the extra-field step across `frontend/lib/core/ai/ports.dart` and `frontend/lib/core/ai/https_submit_port.dart`, gives `frontend/test/widget/ai/ai_surface_test_harness.dart` its own task, and splits the two existing test files. The two re-run steps are one verification task. `frontend/lib/features/ai/surface/usage_gauge.dart` is unchanged and has no task. The count is not padded.

## 1. Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies). No task line is marked `[P]`. Scheduling is **Implementation Waves** only.
- **[Story]**: Which user story this task belongs to (`US1`, `US2`)
- Include exact file paths in descriptions

## 2. Path Conventions

- **Flutter desktop app**: `frontend/lib/`, `frontend/test/`
- **Harness H-FL**: `frontend/test/widget/ai/`. Widget scenarios use fake ports composed with `buildLiveVisitSummaryComposition`. No `integration_test/` driver (OQ-6). This unit does not change `e2e/fullstack/`
- **Unchanged**: `frontend/lib/features/ai/surface/usage_gauge.dart`, `frontend/lib/app/router.dart`
- **Spec Kit artifacts**: `specs/090-abo-p6-2-desktop-denial-states-administrator-coverage/`

---

## 3. Tests (H-FL)

**Purpose**: Sequencing steps 1–8. One failing test per E2E id, in one widget file. Titles are prefixed with the E2E id. A row that names two triggers or two sessions asserts both inside that single test. Leave the production files in **Files** unchanged through T008.

Unit command, from `frontend/`:

```bash
flutter test test/widget/ai/denial_states_coverage_gauge_test.dart
```

That command is this unit's new-scenario harness. `npm test` in `e2e/fullstack` is not the harness.

### 3.1 User Story 1 - Staff and administrators see inline AI denial states (Priority: P1) — tests (part 1)

**Independent Test**: E2E-P6.2-01, E2E-P6.2-02, E2E-P6.2-03, E2E-P6.2-04, E2E-P6.2-05, and E2E-P6.2-07 in harness H-FL.

- [X] T001 [US1] Add the failing test `E2E-P6.2-01` in `frontend/test/widget/ai/denial_states_coverage_gauge_test.dart` — red test, FR-001, FR-002, E2E-P6.2-01. Depends on nothing. Create the file. Title `E2E-P6.2-01`. Fake ports only. Compose with `buildLiveVisitSummaryComposition` and pump `AiFeatureHostPage`. `coverage_lapsed` shows staff "AI not available, contact your administrator" and no renew or buy control. The administrator session shows that sentence and a renew or buy control. No dialog in either session. The widget command fails because that inline state is absent.

**Checkpoint**: E2E-P6.2-01 exists and fails.

- [X] T002 [US1] Add the failing test `E2E-P6.2-02` in `frontend/test/widget/ai/denial_states_coverage_gauge_test.dart` — red test, FR-001, FR-002, FR-003, E2E-P6.2-02. Depends on T001 (same file). Title `E2E-P6.2-02`. The same host. `allowance_exhausted` shows staff "AI not available, contact your administrator". The administrator sees the renew or buy control. The status refresh callback runs. The widget command fails because that state and refresh are absent. E2E-P6.2-01 still fails.

**Checkpoint**: E2E-P6.2-01 and E2E-P6.2-02 exist and fail.

- [X] T003 [US1] Add the failing test `E2E-P6.2-03` in `frontend/test/widget/ai/denial_states_coverage_gauge_test.dart` — red test, FR-001, FR-002, FR-005, E2E-P6.2-03. Depends on T002 (same file). Title `E2E-P6.2-03`. The same host, with the coverage client returning `subscription_ref`. `suspended`: staff see "AI not available, contact your administrator". The administrator sees "Contact support" and that subscription reference. The widget command fails because that state is absent. E2E-P6.2-01 and E2E-P6.2-02 still fail.

**Checkpoint**: E2E-P6.2-01 through E2E-P6.2-03 exist and fail.

- [X] T004 [US1] Add the failing test `E2E-P6.2-04` in `frontend/test/widget/ai/denial_states_coverage_gauge_test.dart` — red test, FR-001, FR-002, E2E-P6.2-04. Depends on T003 (same file). Title `E2E-P6.2-04`. The same host. Fake denials carry `retry_after`. `concurrency_limited` and `rate_limited` each show "AI busy, try again shortly" and that `retry_after`, for a staff session and an administrator session. The widget command fails because that state is absent. E2E-P6.2-01 through E2E-P6.2-03 still fail.

**Checkpoint**: E2E-P6.2-01 through E2E-P6.2-04 exist and fail.

- [X] T005 [US1] Add the failing test `E2E-P6.2-05` in `frontend/test/widget/ai/denial_states_coverage_gauge_test.dart` — red test, FR-001, FR-002, E2E-P6.2-05. Depends on T004 (same file). Title `E2E-P6.2-05`. The same host. `coverage_unknown` shows "AI service unreachable". A submit port that fails with `TransportFailure` until `TransportRetryExhausted` shows the same sentence. Both sessions, no dialog. The widget command fails because that state is absent. E2E-P6.2-01 through E2E-P6.2-04 still fail.

**Checkpoint**: E2E-P6.2-01 through E2E-P6.2-05 exist and fail. E2E-P6.2-06 and E2E-P6.2-07 are not written yet.

### 3.2 User Story 2 - Administrators see live allowance; staff do not call coverage (Priority: P2) — tests

**Independent Test**: E2E-P6.2-06 in harness H-FL. Every earlier suite stays green (rule S2).

- [X] T006 [US2] Add the failing test `E2E-P6.2-06` in `frontend/test/widget/ai/denial_states_coverage_gauge_test.dart` — red test, FR-004, FR-005, E2E-P6.2-06. Depends on T005 (same file). Title `E2E-P6.2-06`. `UsageGauge` in `AiFeatureHostPage`, fed by `frontend/lib/core/ai/usage_summary_client.dart`. The administrator gauge shows `term.used` and `term.allowance` from `GET /v1/coverage`. The staff session records no `/v1/coverage` URL and no `/v1/usage` URL, and the gauge is absent. The widget command fails because the host still calls `/v1/usage`. E2E-P6.2-01 through E2E-P6.2-05 still fail.

**Checkpoint**: E2E-P6.2-06 exists and fails. E2E-P6.2-07 is not written yet.

### 3.3 User Story 1 - Staff and administrators see inline AI denial states (Priority: P1) — tests (part 2)

**Independent Test**: E2E-P6.2-01, E2E-P6.2-02, E2E-P6.2-03, E2E-P6.2-04, E2E-P6.2-05, and E2E-P6.2-07 in harness H-FL.

- [X] T007 [US1] Add the failing test `E2E-P6.2-07` in `frontend/test/widget/ai/denial_states_coverage_gauge_test.dart` — red test, FR-001, FR-002, E2E-P6.2-07. Depends on T006 (same file). Title `E2E-P6.2-07`. The same host, with the coverage client returning `term.plan_display_name`. `forbidden_capability`: the administrator sees that plan name. Staff see "Not included in your clinic's AI plan". The widget command fails because that state is absent. E2E-P6.2-01 through E2E-P6.2-06 still fail.

**Checkpoint**: E2E-P6.2-01 through E2E-P6.2-07 exist. The red run has not confirmed them yet.

- [X] T008 [US1] Run `flutter test test/widget/ai/denial_states_coverage_gauge_test.dart` from `frontend/` and confirm E2E-P6.2-01 through E2E-P6.2-07 fail — red run, FR-001, FR-002, FR-003, FR-004, FR-005, E2E-P6.2-01, E2E-P6.2-02, E2E-P6.2-03, E2E-P6.2-04, E2E-P6.2-05, E2E-P6.2-06, E2E-P6.2-07. Depends on T007. Leave the production files unchanged. Do not edit `frontend/test/widget/ai/denial_states_coverage_gauge_test.dart` in this task. Do not run `npm test` in `e2e/fullstack`. Do not start wrangler.

**Checkpoint**: E2E-P6.2-01 through E2E-P6.2-07 fail. Production files in **Files** are unchanged.

---

## 4. Implementation

**Purpose**: Sequencing steps 9–18. Starts after T008 has shown the seven tests fail. Within a subphase the tasks run in id order.

### 4.1 User Story 1 - Staff and administrators see inline AI denial states (Priority: P1) — taxonomy and denial transport

**Independent Test**: E2E-P6.2-01, E2E-P6.2-02, E2E-P6.2-03, E2E-P6.2-04, E2E-P6.2-05, and E2E-P6.2-07 in harness H-FL.

- [X] T009 [US1] Teach `frontend/lib/core/ai/taxonomy.dart` the 04 §4.2 codes, HTTP statuses, and extra fields — produces the denial-code helper, FR-001, FR-002, E2E-P6.2-01, E2E-P6.2-02, E2E-P6.2-03, E2E-P6.2-04, E2E-P6.2-05, E2E-P6.2-07. Depends on T008. Recognize `allowance_exhausted` (HTTP 403), `coverage_lapsed` (HTTP 403, `coverage_reason`), `coverage_unknown` (HTTP 503, `retry_after`), `suspended` (HTTP 403), `concurrency_limited` (HTTP 429, `retry_after`), `rate_limited` (HTTP 429, `retry_after`), and `contract_version_unsupported` (HTTP 400, `accepted_versions`). Keep the existing codes. A helper returns the code only when the HTTP status matches that row, and carries the named extra fields.

**Checkpoint**: The taxonomy helper recognizes those codes. `resolveDegradedMode` does not map them yet.

- [X] T010 [US1] Map those codes, `status_stale`, and network failure in `resolveDegradedMode` in `frontend/lib/features/ai/degraded/ai_degraded_mode.dart` — produces the FR-65 classes, FR-001, FR-002, E2E-P6.2-01, E2E-P6.2-02, E2E-P6.2-03, E2E-P6.2-04, E2E-P6.2-05, E2E-P6.2-07. Depends on T009. `status_stale` and a network failure map to the same unreachable class as `coverage_unknown`. `contract_version_unsupported` maps to the existing app-update mode.

**Checkpoint**: `resolveDegradedMode` maps the denial-table codes. `AiDegradedView` still shows the previous sentences.

- [X] T011 [US1] Render the denial-table sentences in `frontend/lib/features/ai/degraded/ai_degraded_view.dart` — produces the inline denial column, FR-001, FR-002, FR-005, E2E-P6.2-01, E2E-P6.2-02, E2E-P6.2-03, E2E-P6.2-04, E2E-P6.2-05, E2E-P6.2-07. Depends on T010. Inline column only, never a dialog. Staff and administrator sentences are the denial-table sentences. `concurrency_limited` and `rate_limited` include `retry_after`. The administrator lapsed and exhausted states show a renew or buy control with an empty `onPressed`. That control does not navigate, mint a token, or call billing. The administrator `suspended` state shows "Contact support" and the subscription reference. The administrator `forbidden_capability` state shows the plan name. `capability_disabled` and `provider_unavailable` use "AI temporarily unavailable". `coverage_unknown`, network failure, and `status_stale` use "AI service unreachable". `contract_version_unsupported` keeps "Update the app to use AI".

**Checkpoint**: `AiDegradedView` shows the denial-table sentences. Extra fields do not arrive on `PlatformHttpException` yet.

- [X] T012 [US1] Carry `retry_after`, `coverage_reason`, and `accepted_versions` on `PlatformHttpException` in `frontend/lib/core/ai/ports.dart` — produces the denial extra fields, FR-002, E2E-P6.2-01, E2E-P6.2-04. Depends on T011. The exception carries the extra fields the taxonomy recognized.

**Checkpoint**: `PlatformHttpException` can carry those extra fields. The submit port does not fill them yet.

- [X] T013 [US1] Route pre-stream denial bodies through the taxonomy helper in `frontend/lib/core/ai/https_submit_port.dart` — produces the denial exception, FR-001, FR-002, E2E-P6.2-01, E2E-P6.2-02, E2E-P6.2-03, E2E-P6.2-04, E2E-P6.2-05, E2E-P6.2-07. Depends on T012. The new codes and extra fields reach `PlatformHttpException`. `contract_version_unsupported` still throws `ContractVersionUnsupportedException`. Keep `Aip-Contract-Version` set to `platformClinic`.

**Checkpoint**: Pre-stream denials throw with the taxonomy code and extra fields. The surface does not pass them to the host yet.

### 4.2 User Story 1 - Staff and administrators see inline AI denial states (Priority: P1) — pre-stream denial handoff

**Independent Test**: E2E-P6.2-01, E2E-P6.2-02, E2E-P6.2-03, E2E-P6.2-04, E2E-P6.2-05, and E2E-P6.2-07 in harness H-FL.

- [X] T014 [US1] Pass the taxonomy code, wire code, and extra fields from `frontend/lib/features/ai/surface/first_ai_feature_surface.dart` to the host — produces the denial handoff, FR-002, FR-003, E2E-P6.2-02, E2E-P6.2-04, E2E-P6.2-05. Depends on T013. A pre-stream denial passes the taxonomy code, wire code, and extra fields to the host. `TransportRetryExhausted` tells the host this request failed on the network.

**Checkpoint**: The surface reports denial fields and a network failure to the host. The host does not call `/v1/coverage` yet.

### 4.3 User Story 2 - Administrators see live allowance; staff do not call coverage (Priority: P2) — coverage client and host

**Independent Test**: E2E-P6.2-06 in harness H-FL. Every earlier suite stays green (rule S2).

- [X] T015 [US2] Replace `fetchUsage` with `GET /v1/coverage` in `frontend/lib/core/ai/usage_summary_client.dart` — produces the only coverage client, FR-004, FR-005, E2E-P6.2-03, E2E-P6.2-06, E2E-P6.2-07. Depends on T014. This file is the only `/v1/coverage` client. It sends `Aip-Contract-Version: platformClinic` and reads `subscription_ref`, `term.allowance`, `term.used`, and `term.plan_display_name`. It does not call `/v1/usage`. Do not add a second coverage client.

**Checkpoint**: `usage_summary_client.dart` calls `GET /v1/coverage` and does not call `/v1/usage`. The host still decides when to call it.

- [X] T016 [US2] Call the coverage client only for an administrator in `frontend/lib/features/ai/host/ai_feature_host_page.dart` — produces the administrator gauge and the denial props, FR-002, FR-003, FR-004, FR-005, E2E-P6.2-01, E2E-P6.2-02, E2E-P6.2-03, E2E-P6.2-04, E2E-P6.2-05, E2E-P6.2-06, E2E-P6.2-07. Depends on T015. Call the coverage client only when `staffIsAdministrator` is true, and only to fill `UsageGauge`, the subscription reference, and the plan name. Remove the `/v1/usage` fetch and the spy fixture for that path. The spy fixture, when an administrator fetch runs, returns a coverage body whose `term.used` is 42 and `term.allowance` is 10000. Pass role, `retry_after`, subscription reference, and plan name into `AiDegradedView`. `allowance_exhausted` still calls the existing `onStatusRefresh`. Do not add a second scheduler. Do not edit `frontend/lib/features/ai/surface/usage_gauge.dart`. The host supplies `term.used` as credits used and `term.allowance` as the budget, and builds the gauge only for an administrator.

**Checkpoint**: An administrator session can fill the gauge from `/v1/coverage`. A staff session does not call `/v1/coverage` or `/v1/usage`. The composition override is not threaded yet.

- [X] T017 [US2] Pass the coverage-client override through `buildLiveVisitSummaryComposition` in `frontend/lib/features/ai/presentation/pages/ai_page.dart` — produces the test seam, FR-004, E2E-P6.2-03, E2E-P6.2-06, E2E-P6.2-07. Depends on T016. `buildLiveVisitSummaryComposition` accepts the existing `UsageSummaryClient` override and places it on `AiFeatureHostDependencies`. Do not edit `frontend/lib/app/router.dart`.

**Checkpoint**: Widget scenarios can replace the coverage client. The existing gauge test does not open an administrator session yet.

### 4.4 User Story 2 - Administrators see live allowance; staff do not call coverage (Priority: P2) — administrator gauge harness

**Independent Test**: E2E-P6.2-06 in harness H-FL. Every earlier suite stays green (rule S2).

- [X] T018 [US2] Accept `staffIsAdministrator` on `hostDependencies` in `frontend/test/widget/ai/ai_surface_test_harness.dart` — produces the administrator session seam, FR-004, E2E-P6.2-06. Depends on T017. The existing gauge test can open an administrator session through this seam.

**Checkpoint**: `hostDependencies` accepts `staffIsAdministrator`. The ready-host gauge test does not set it yet.

- [X] T019 [US2] Run the ready-host gauge as an administrator in `frontend/test/widget/ai/usage_gauge_test.dart` — produces the existing gauge expectation, FR-004, FR-005, E2E-P6.2-06. Depends on T018. The ready-host gauge test sets `staffIsAdministrator` and still expects 42 and 10000. The non-enrolled test still sees no `/v1/usage` call.

**Checkpoint**: The ready-host gauge test opens an administrator session and still expects 42 and 10000.

### 4.5 User Story 1 - Staff and administrators see inline AI denial states (Priority: P1) — provider-unavailable sentence

**Independent Test**: E2E-P6.2-01, E2E-P6.2-02, E2E-P6.2-03, E2E-P6.2-04, E2E-P6.2-05, and E2E-P6.2-07 in harness H-FL.

- [X] T020 [US1] Expect "AI temporarily unavailable" in `frontend/test/widget/ai/ai_degraded_mode_test.dart` — produces the existing sentence expectation, FR-002, E2E-P6.2-07. Depends on T011. The provider-unavailable sentence expectation is "AI temporarily unavailable". The retry key stays.

**Checkpoint**: The existing degraded-mode test expects "AI temporarily unavailable" for provider unavailable.

---

## 5. Verification (H-FL)

**Purpose**: Sequencing steps 19–20. The unit harness passes. This is not a repo-wide command.

### 5.1 User Story 2 - Administrators see live allowance; staff do not call coverage (Priority: P2) — H-FL harness

**Independent Test**: E2E-P6.2-06 in harness H-FL. Every earlier suite stays green (rule S2).

- [X] T021 [US2] Re-run the H-FL widget commands until E2E-P6.2-01 through E2E-P6.2-07 pass and the two existing widget files stay green — green harness, FR-001, FR-002, FR-003, FR-004, FR-005, E2E-P6.2-01, E2E-P6.2-02, E2E-P6.2-03, E2E-P6.2-04, E2E-P6.2-05, E2E-P6.2-06, E2E-P6.2-07. Depends on T019 and T020. From `frontend/`, run `flutter test test/widget/ai/denial_states_coverage_gauge_test.dart` until E2E-P6.2-01 through E2E-P6.2-07 pass. Re-run `flutter test test/widget/ai/usage_gauge_test.dart test/widget/ai/ai_degraded_mode_test.dart` so those existing expectations stay green. Fixes stay in the files this unit's **Files** table lists under `frontend/`. Do not edit `frontend/lib/features/ai/surface/usage_gauge.dart` or `frontend/lib/app/router.dart`. Do not run `npm test` in `e2e/fullstack`. Do not start wrangler.

**Checkpoint**: E2E-P6.2-01 through E2E-P6.2-07 pass. `usage_gauge_test.dart` and `ai_degraded_mode_test.dart` stay green.

---

## 6. Documentation

**Purpose**: Sequencing step 21. `quickstart.md` after the harness is green. Plan-phase `research.md`, `data-model.md`, and `contracts/` stay omitted.

### 6.1 User Story 2 - Administrators see live allowance; staff do not call coverage (Priority: P2) — quickstart

**Independent Test**: E2E-P6.2-06 in harness H-FL. Every earlier suite stays green (rule S2).

- [X] T022 [US2] Write `specs/090-abo-p6-2-desktop-denial-states-administrator-coverage/quickstart.md` — unit quickstart, FR-001, FR-004, E2E-P6.2-01, E2E-P6.2-02, E2E-P6.2-03, E2E-P6.2-04, E2E-P6.2-05, E2E-P6.2-06, E2E-P6.2-07. Depends on T021. Fill only these sections: what was implemented and the files added or modified; the harness command for this unit's tests only, from `frontend/`, `flutter test test/widget/ai/denial_states_coverage_gauge_test.dart`; the entry point → module chain per E2E id. Do not list earlier-unit files, combined counts, or full-suite commands. Manual steps are omitted: the harness sees this behaviour.

**Checkpoint**: `quickstart.md` names the seven H-FL ids, the unit command, and the entry chain.

---

## 7. Dependencies & Execution Order

### 7.1 Phase Dependencies

- **Tests (Phase 3)**: T001 creates `frontend/test/widget/ai/denial_states_coverage_gauge_test.dart` with E2E-P6.2-01. T002 through T005 add E2E-P6.2-02 through E2E-P6.2-05 in that file. T006 adds E2E-P6.2-06. T007 adds E2E-P6.2-07. T008 runs the widget command and confirms all seven fail before any production file in **Files** changes.
- **Implementation (Phase 4)**: Starts after T008. User Story 1 teaches the taxonomy, maps `resolveDegradedMode`, renders `AiDegradedView`, carries extra fields on `PlatformHttpException`, fills them from the submit port, and passes them through `FirstAiFeatureSurface`. User Story 2 then replaces `fetchUsage` with `GET /v1/coverage`, calls that client only for an administrator on the host, threads the client override through `buildLiveVisitSummaryComposition`, and updates the existing gauge harness. The provider-unavailable sentence expectation is updated in the existing degraded-mode test.
- **Verification (Phase 5)**: Starts after T019 and T020. Two commands from `frontend/`: the new widget file until the seven ids pass, then `usage_gauge_test.dart` and `ai_degraded_mode_test.dart`.
- **Documentation (Phase 6)**: Starts after T021 is green. One file: `quickstart.md`.

### 7.2 User Story Dependencies

- **User Story 1 (P1)**: The failing denial tests are T001 through T005 and T007. The denial path is T009 through T014. T020 updates the existing provider-unavailable sentence after T011. E2E-P6.2-01 through E2E-P6.2-05 and E2E-P6.2-07 are included in the red run (T008) and the green harness (T021).
- **User Story 2 (P2)**: The failing gauge test is T006, in the same widget file, after the User Story 1 denial tests that precede it in sequencing. The coverage client, host, composition override, and gauge harness are T015 through T019. They use the denial props from T014. E2E-P6.2-06 is included in the red run (T008) and the green harness (T021).

### 7.3 Within Each Phase

- T001 creates `frontend/test/widget/ai/denial_states_coverage_gauge_test.dart`. T002 through T007 write that same file in id order. T008 runs the widget command and does not edit that file.
- T009 writes `frontend/lib/core/ai/taxonomy.dart`. T010 writes `frontend/lib/features/ai/degraded/ai_degraded_mode.dart`. T011 writes `frontend/lib/features/ai/degraded/ai_degraded_view.dart`. T012 writes `frontend/lib/core/ai/ports.dart`. T013 writes `frontend/lib/core/ai/https_submit_port.dart`. T014 writes `frontend/lib/features/ai/surface/first_ai_feature_surface.dart`. T015 writes `frontend/lib/core/ai/usage_summary_client.dart`. T016 writes `frontend/lib/features/ai/host/ai_feature_host_page.dart`. T017 writes `frontend/lib/features/ai/presentation/pages/ai_page.dart`. T018 writes `frontend/test/widget/ai/ai_surface_test_harness.dart`. T019 writes `frontend/test/widget/ai/usage_gauge_test.dart`. T020 writes `frontend/test/widget/ai/ai_degraded_mode_test.dart`. T018 and T019 share no path with T020.
- T021 runs after T019 and T020 and may edit only the `frontend/` files listed in this unit's **Files** table, other than the unchanged `frontend/lib/features/ai/surface/usage_gauge.dart`.
- T022 writes only `specs/090-abo-p6-2-desktop-denial-states-administrator-coverage/quickstart.md` after T021 is green.

---

## 8. Implementation Waves

T018–T019 and T020 follow the host and the denial view. They share no path, so that wave has two bullets. Every other subphase is serial with the one before it.

### 8.1 Wave 1

- T001–T005 [US1] — subphase: `### 3.1 User Story 1 - Staff and administrators see inline AI denial states (Priority: P1) — tests (part 1)` — paths: `frontend/test/widget/ai/denial_states_coverage_gauge_test.dart`

### 8.2 Wave 2

- T006 [US2] — subphase: `### 3.2 User Story 2 - Administrators see live allowance; staff do not call coverage (Priority: P2) — tests` — paths: `frontend/test/widget/ai/denial_states_coverage_gauge_test.dart`

### 8.3 Wave 3

- T007–T008 [US1] — subphase: `### 3.3 User Story 1 - Staff and administrators see inline AI denial states (Priority: P1) — tests (part 2)` — paths: `frontend/test/widget/ai/denial_states_coverage_gauge_test.dart`

### 8.4 Wave 4

- T009–T013 [US1] — subphase: `### 4.1 User Story 1 - Staff and administrators see inline AI denial states (Priority: P1) — taxonomy and denial transport` — paths: `frontend/lib/core/ai/taxonomy.dart`, `frontend/lib/features/ai/degraded/ai_degraded_mode.dart`, `frontend/lib/features/ai/degraded/ai_degraded_view.dart`, `frontend/lib/core/ai/ports.dart`, `frontend/lib/core/ai/https_submit_port.dart`

### 8.5 Wave 5

- T014 [US1] — subphase: `### 4.2 User Story 1 - Staff and administrators see inline AI denial states (Priority: P1) — pre-stream denial handoff` — paths: `frontend/lib/features/ai/surface/first_ai_feature_surface.dart`

### 8.6 Wave 6

- T015–T017 [US2] — subphase: `### 4.3 User Story 2 - Administrators see live allowance; staff do not call coverage (Priority: P2) — coverage client and host` — paths: `frontend/lib/core/ai/usage_summary_client.dart`, `frontend/lib/features/ai/host/ai_feature_host_page.dart`, `frontend/lib/features/ai/presentation/pages/ai_page.dart`

### 8.7 Wave 7

- T018–T019 [US2] — subphase: `### 4.4 User Story 2 - Administrators see live allowance; staff do not call coverage (Priority: P2) — administrator gauge harness` — paths: `frontend/test/widget/ai/ai_surface_test_harness.dart`, `frontend/test/widget/ai/usage_gauge_test.dart`
- T020 [US1] — subphase: `### 4.5 User Story 1 - Staff and administrators see inline AI denial states (Priority: P1) — provider-unavailable sentence` — paths: `frontend/test/widget/ai/ai_degraded_mode_test.dart`

### 8.8 Wave 8

- T021 [US2] — subphase: `### 5.1 User Story 2 - Administrators see live allowance; staff do not call coverage (Priority: P2) — H-FL harness` — paths: `frontend/test/widget/ai/denial_states_coverage_gauge_test.dart`, `frontend/lib/core/ai/taxonomy.dart`, `frontend/lib/features/ai/degraded/ai_degraded_mode.dart`, `frontend/lib/features/ai/degraded/ai_degraded_view.dart`, `frontend/lib/core/ai/ports.dart`, `frontend/lib/core/ai/https_submit_port.dart`, `frontend/lib/features/ai/surface/first_ai_feature_surface.dart`, `frontend/lib/core/ai/usage_summary_client.dart`, `frontend/lib/features/ai/host/ai_feature_host_page.dart`, `frontend/lib/features/ai/presentation/pages/ai_page.dart`, `frontend/test/widget/ai/ai_surface_test_harness.dart`, `frontend/test/widget/ai/usage_gauge_test.dart`, `frontend/test/widget/ai/ai_degraded_mode_test.dart`

### 8.9 Wave 9

- T022 [US2] — subphase: `### 6.1 User Story 2 - Administrators see live allowance; staff do not call coverage (Priority: P2) — quickstart` — paths: `specs/090-abo-p6-2-desktop-denial-states-administrator-coverage/quickstart.md`
