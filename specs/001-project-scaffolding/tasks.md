# Tasks: Project Scaffolding

**Input**: Design documents from `/specs/001-project-scaffolding/`

**Prerequisites**: plan.md (required), spec.md (required for user stories), research.md, data-model.md, contracts/

**Tests**: This feature explicitly defines acceptance tests and startup verification scenarios, so story-specific test tasks are included.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions

- **Flutter desktop app**: `frontend/lib/`, `frontend/test/`
- **Supabase backend**: `backend/local/`, `backend/tests/`
- **Documentation**: `docs/setup/`, `specs/001-project-scaffolding/`
- **CI/CD**: `.github/workflows/`

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Initialize the repository for the first runtime implementation without adding domain workflows. Initializing the flutter app can be done by flutter create utility.

- [X] T001 Initialize the Flutter desktop project scaffold in `frontend/pubspec.yaml`, `frontend/analysis_options.yaml`, `frontend/lib/main.dart`, and `frontend/windows/`
- [X] T002 Create the planned application directory structure in `frontend/lib/app/`, `frontend/lib/core/`, `frontend/lib/shared/`, `frontend/lib/features/`, `frontend/test/unit/`, `frontend/test/widget/`, and `frontend/test/integration/`
- [X] T003 [P] Create the local Supabase workspace skeleton in `backend/local/`, `backend/tests/`, and `backend/local/.env.example`
- [X] T004 [P] Add baseline repository ignores and developer tool configuration in `.gitignore` and `.vscode/settings.json`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core startup, configuration, and shared infrastructure required before any user story can be completed

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [X] T005 Implement deployment profile parsing and local-only validation in `frontend/lib/core/config/deployment_profile.dart` and `frontend/lib/core/config/supabase_config.dart`
- [X] T006 [P] Implement startup session state and health-check orchestration in `frontend/lib/shared/providers/startup_session_provider.dart` and `frontend/lib/shared/services/startup_health_service.dart`
- [X] T007 [P] Implement the app bootstrap and router scaffold in `frontend/lib/app/app.dart` and `frontend/lib/app/router.dart`
- [X] T008 [P] Implement shared startup-safe theme, failure, and loading foundations in `frontend/lib/app/theme/app_theme.dart`, `frontend/lib/core/errors/failures.dart`, `frontend/lib/core/errors/exceptions.dart`, and `frontend/lib/core/widgets/app_loading_state.dart`
- [X] T009 [P] Define the clinic-local Supabase stack and connectivity smoke harness in `backend/local/docker-compose.yml`, `backend/local/config.toml`, and `backend/tests/connectivity_smoke.sh`
- [X] T010 Create the startup feature module boundary for later story work in `frontend/lib/features/startup/presentation/pages/`, `frontend/lib/features/startup/presentation/widgets/`, and `frontend/lib/features/startup/presentation/providers/`

**Checkpoint**: Foundation ready - user story implementation can now begin in parallel

---

## Phase 3: User Story 1 - Launch a Safe Pre-Auth Entry (Priority: P1) 🎯 MVP

**Goal**: Deliver a safe unauthenticated startup experience that validates local configuration, shows connection status, and blocks protected navigation

**Independent Test**: Launch with a valid local deployment profile and confirm the unauthenticated entry experience appears, degraded startup is visible when the backend is unreachable, and protected routes redirect back to the startup experience

### Tests for User Story 1

- [X] T011 [P] [US1] Add startup configuration widget tests in `frontend/test/widget/startup/startup_entry_page_test.dart`
- [X] T012 [P] [US1] Add protected-route redirect integration tests in `frontend/test/integration/startup/protected_route_redirect_test.dart`
- [X] T013 [P] [US1] Add degraded connectivity integration tests in `frontend/test/integration/startup/degraded_startup_test.dart`

### Implementation for User Story 1

- [X] T014 [P] [US1] Implement the unauthenticated entry page and startup-check view in `frontend/lib/features/startup/presentation/pages/startup_entry_page.dart` and `frontend/lib/features/startup/presentation/pages/startup_check_page.dart`
- [X] T015 [P] [US1] Implement setup-guidance and degraded-state widgets in `frontend/lib/features/startup/presentation/pages/setup_guidance_page.dart`, `frontend/lib/features/startup/presentation/widgets/connection_status_card.dart`, and `frontend/lib/features/startup/presentation/widgets/degraded_state_notice.dart`
- [X] T016 [US1] Implement startup presentation state and validation flow in `frontend/lib/features/startup/presentation/providers/startup_notifier.dart`
- [X] T017 [US1] Wire startup routing, guarded redirects, and bootstrap state into `frontend/lib/app/router.dart`, `frontend/lib/app/app.dart`, and `frontend/lib/main.dart`

**Checkpoint**: At this point, User Story 1 should be fully functional and testable independently

---

## Phase 4: User Story 2 - Prepare a Workstation Consistently (Priority: P2)

**Goal**: Document and validate a repeatable setup path for developers, the receptionist server node, and clinic client devices

**Independent Test**: A new team member can follow the written setup guides, bring up the local Supabase stack, configure a clinic client, and reach the unauthenticated startup experience without undocumented steps

### Tests for User Story 2

- [X] T018 [P] [US2] Add a local stack validation script in `backend/tests/validate_local_stack.sh`
- [X] T019 [P] [US2] Add a setup verification checklist in `docs/setup/verification-checklist.md`

### Implementation for User Story 2

- [X] T020 [P] [US2] Document developer workstation setup in `docs/setup/developer-workstation.md`
- [X] T021 [P] [US2] Document receptionist server-node setup and LAN exposure in `docs/setup/server-node.md`
- [X] T022 [P] [US2] Document clinic client configuration and deployment-profile usage in `docs/setup/client-workstation.md`
- [X] T023 [US2] Document local backup expectations and troubleshooting flows in `docs/setup/troubleshooting.md`
- [X] T024 [US2] Align the feature quickstart and deployment profile contract with the final setup docs in `specs/001-project-scaffolding/quickstart.md` and `specs/001-project-scaffolding/contracts/deployment-profile.md`

**Checkpoint**: At this point, User Stories 1 AND 2 should both work independently

---

## Phase 5: User Story 3 - Build New Features on Shared Foundations (Priority: P3)

**Goal**: Provide reusable visual foundations, shared UI primitives, and baseline quality automation for future features

**Independent Test**: A placeholder screen can be built using the shared theme, widgets, and error/loading patterns, and the baseline quality pipeline passes analyze, test, and build verification

### Tests for User Story 3

- [X] T025 [P] [US3] Add shared foundation widget tests in `frontend/test/widget/shared/shared_foundations_test.dart`
- [X] T026 [P] [US3] Add placeholder-screen widget tests in `frontend/test/widget/shared/foundation_demo_page_test.dart`

### Implementation for User Story 3

- [X] T027 [P] [US3] Implement the shared theme system in `frontend/lib/app/theme/app_theme.dart` and `frontend/lib/app/theme/app_colors.dart`
- [X] T028 [P] [US3] Implement reusable error and loading surfaces in `frontend/lib/core/widgets/error_state_panel.dart`, `frontend/lib/core/widgets/app_loading_state.dart`, and `frontend/lib/core/widgets/snackbar_service.dart`
- [X] T029 [P] [US3] Implement reusable UI primitives in `frontend/lib/core/widgets/app_button.dart`, `frontend/lib/core/widgets/app_card.dart`, `frontend/lib/core/widgets/app_dialog.dart`, `frontend/lib/core/widgets/app_form_field.dart`, and `frontend/lib/core/widgets/app_data_table.dart`
- [X] T030 [P] [US3] Implement shared theme and connectivity providers plus a demo screen in `frontend/lib/shared/providers/theme_provider.dart`, `frontend/lib/shared/providers/connectivity_provider.dart`, and `frontend/lib/features/foundation_demo/presentation/pages/foundation_demo_page.dart`
- [X] T031 [US3] Add the baseline CI workflow for analyze, tests, and Windows build verification in `.github/workflows/ci.yml`
- [X] T032 [US3] Document quality-gate commands and shared foundation usage in `docs/setup/quality-gates.md` and `specs/001-project-scaffolding/quickstart.md`

**Checkpoint**: All user stories should now be independently functional

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Final cross-story consistency, documentation alignment, and governance checks

- T033 [P] Add a setup index and cross-link all workstation guides in `docs/setup/README.md`
- T034 Run the full quickstart validation and capture final acceptance notes in `specs/001-project-scaffolding/quickstart.md`
- T035 Review final constitution compliance and update implementation notes in `specs/001-project-scaffolding/plan.md` and `specs/001-project-scaffolding/tasks.md`

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories
- **User Stories (Phase 3+)**: All depend on Foundational phase completion
- **Polish (Phase 6)**: Depends on all desired user stories being complete

### User Story Dependencies

- **User Story 1 (P1)**: Can start after Foundational (Phase 2) - MVP story with no dependency on other user stories
- **User Story 2 (P2)**: Can start after Foundational (Phase 2) - depends on final startup/config behavior but remains independently testable
- **User Story 3 (P3)**: Can start after Foundational (Phase 2) - may share files with US1 foundations but remains independently testable via the demo screen and CI workflow

### Within Each User Story

- Story tests are written before the corresponding implementation tasks
- State and models are in place before view wiring
- Shared primitives are implemented before CI and documentation that depend on them
- Each story should pass its independent test before moving on

### Parallel Opportunities

- `T003` and `T004` can run in parallel after the initial Flutter scaffold starts
- `T006` through `T009` can run in parallel in the foundational phase
- US1 test tasks `T011` through `T013` can run in parallel
- US2 documentation tasks `T020` through `T022` can run in parallel
- US3 shared-foundation tasks `T027` through `T030` can run in parallel across different files

---

## Parallel Example: User Story 1

```bash
Task: "Add startup configuration widget tests in frontend/test/widget/startup/startup_entry_page_test.dart"
Task: "Add protected-route redirect integration tests in frontend/test/integration/startup/protected_route_redirect_test.dart"
Task: "Add degraded connectivity integration tests in frontend/test/integration/startup/degraded_startup_test.dart"
```

## Parallel Example: User Story 2

```bash
Task: "Document developer workstation setup in docs/setup/developer-workstation.md"
Task: "Document receptionist server-node setup and LAN exposure in docs/setup/server-node.md"
Task: "Document clinic client configuration and deployment-profile usage in docs/setup/client-workstation.md"
```

## Parallel Example: User Story 3

```bash
Task: "Implement the shared theme system in frontend/lib/app/theme/app_theme.dart and frontend/lib/app/theme/app_colors.dart"
Task: "Implement reusable error and loading surfaces in frontend/lib/core/widgets/error_state_panel.dart, frontend/lib/core/widgets/app_loading_state.dart, and frontend/lib/core/widgets/snackbar_service.dart"
Task: "Implement reusable UI primitives in frontend/lib/core/widgets/app_button.dart, frontend/lib/core/widgets/app_card.dart, frontend/lib/core/widgets/app_dialog.dart, frontend/lib/core/widgets/app_form_field.dart, and frontend/lib/core/widgets/app_data_table.dart"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup
2. Complete Phase 2: Foundational
3. Complete Phase 3: User Story 1
4. **STOP and VALIDATE**: Confirm valid startup, degraded startup, and protected-route redirect behavior

### Incremental Delivery

1. Complete Setup + Foundational to establish the runtime base
2. Add User Story 1 and validate the startup experience
3. Add User Story 2 and validate repeatable workstation/server/client setup
4. Add User Story 3 and validate shared UI reuse plus CI quality gates
5. Finish with cross-cutting polish and governance review

### Parallel Team Strategy

1. One developer completes the initial Flutter scaffold while another prepares the local Supabase skeleton
2. After Foundational is complete:
  - Developer A: User Story 1 startup experience
  - Developer B: User Story 2 setup documentation and validation
  - Developer C: User Story 3 shared foundations and CI skeleton

---

## Notes

- [P] tasks touch separate files and can be worked on independently
- Story labels map every implementation task back to one independently testable user story
- This feature intentionally avoids domain tables, RPC business logic, cloud deployment, and AI runtime integration
- Preserve the constitution boundaries: Flutter owns startup UX, Supabase remains the backend, PostgreSQL remains the integrity layer, and AI remains out of scope for V1-0

