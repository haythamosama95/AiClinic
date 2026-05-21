# Tasks: Auth and RBAC

**Input**: Design documents from `/specs/002-auth-rbac/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/, quickstart.md

**Tests**: Included — spec defines acceptance/test cases for auth flow, RLS isolation, session policy, and RBAC.

**Organization**: Tasks grouped by user story. Story labels map to `spec.md` (US6 = Create Staff Accounts §5b; US7 = Forgot Password §6; US8 = Block Unauthenticated §7).

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies on incomplete tasks in same phase)
- **[Story]**: User story label for traceability
- Include exact file paths in descriptions

## Path Conventions

- **Flutter**: `frontend/lib/`, `frontend/test/`
- **Supabase**: `backend/supabase/migrations/`, `backend/tests/`, `backend/seed/`
- **Docs**: `docs/setup/`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Create auth feature module layout and migration workspace before schema work

- [X] T001 Create Supabase migrations workspace in `backend/supabase/migrations/`
- [X] T002 Create auth feature module directories in `frontend/lib/features/auth/data/`, `frontend/lib/features/auth/domain/`, and `frontend/lib/features/auth/presentation/pages/`, `frontend/lib/features/auth/presentation/providers/`, `frontend/lib/features/auth/presentation/widgets/`
- [X] T003 [P] Create shared auth utilities directory in `frontend/lib/core/auth/`
- [X] T004 [P] Add bootstrap administrator credential template in `backend/seed/bootstrap_admin.env.example`
- [X] T005 [P] Add auth route constants in `frontend/lib/app/app_routes.dart` (`/login`, `/bootstrap`, `/home`, `/forgot-password`)

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Database schema, RLS, custom claims, bootstrap seed, auth core services, and router integration — **blocks all user stories**

**⚠️ CRITICAL**: No user story phase work until this phase is complete

- [X] T006 Add schema migration for `staff_role` enum and tables (`organizations`, `branches`, `staff_members`, `staff_branch_assignments`, `roles_permissions`, `audit_log`, `app_settings`, `subscription_cache`) in `backend/supabase/migrations/20260516100000_auth_rbac_schema.sql`
- [X] T007 Add audit triggers (`set_updated_at`, audit user columns) in `backend/supabase/migrations/20260516100100_auth_rbac_audit_triggers.sql`
- [X] T008 Add RLS policies for all auth feature tables in `backend/supabase/migrations/20260516100200_auth_rbac_rls.sql`
- [X] T009 Implement `get_custom_claims`, bootstrap RPCs, and staff RPCs in `backend/supabase/migrations/20260516100300_auth_rbac_functions.sql`
- [X] T010 Seed `roles_permissions` matrix, bootstrap admin auth user, and `staff_members` row (`is_bootstrap_admin`) in `backend/supabase/migrations/20260516100400_auth_rbac_seed.sql`
- [X] T011 [P] Register GoTrue custom access token hook for `get_custom_claims` in `backend/supabase/config.toml` and document restart steps in `backend/README.md`
- [X] T012 [P] Implement `AuthRepository` (signIn, signOut, session stream, no local persistence on cold start) in `frontend/lib/features/auth/data/auth_repository.dart`
- [X] T013 [P] Define `AuthSessionContext`, `StaffProfile`, and related domain types in `frontend/lib/features/auth/domain/auth_session.dart`
- [X] T014 Implement `AuthSessionNotifier` and `authSessionProvider` in `frontend/lib/shared/providers/auth_session_provider.dart`
- [X] T015 [P] Implement `PermissionService` (`hasPermission`, `requirePermission`) in `frontend/lib/core/auth/permission_service.dart`
- [X] T016 Configure Supabase client initialization to avoid restoring sessions after app restart in `frontend/lib/core/config/supabase_config.dart`
- [X] T017 [P] Add RLS isolation verification script in `backend/tests/rls_isolation.sql`
- [X] T018 [P] Add auth flow smoke script (sign-in, claims, bootstrap RPCs) in `backend/tests/auth_flow_smoke.sh`
- [X] T019 Integrate auth-aware `GoRouter` redirect scaffold in `frontend/lib/app/router.dart` (listen to `authSessionProvider`)
- [X] T020 Add navigation from startup entry to login in `frontend/lib/features/startup/presentation/pages/startup_entry_page.dart`

**Checkpoint**: Migrations apply cleanly; bootstrap admin can authenticate; router distinguishes unauthenticated vs authenticated paths

---

## Phase 3: User Story 8 - Block Unauthenticated Access (Priority: P1)

**Goal**: Extend V1-0 route guards so protected routes require a valid authenticated session and redirect to login

**Independent Test**: Launch without session, attempt protected navigation, confirm redirect to login; after sign-in, permitted protected routes are reachable

### Tests for User Story 8

- [X] T021 [P] [US8] Add auth route guard integration tests in `frontend/test/integration/auth/auth_route_guard_test.dart`

### Implementation for User Story 8

- [X] T022 [P] [US8] Implement `AuthRouteGuard` helpers in `frontend/lib/core/auth/auth_route_guard.dart`
- [X] T023 [US8] Complete authenticated vs unauthenticated redirect rules in `frontend/lib/app/router.dart` per `specs/002-auth-rbac/contracts/auth-session.md`

**Checkpoint**: Unauthenticated protected access always lands on login

---

## Phase 4: User Story 1 - Sign In Securely (Priority: P1) 🎯 MVP

**Goal**: Email/password login with post-login context load and navigation to placeholder shell or bootstrap when setup is required

**Independent Test**: Sign in with valid staff credentials and reach authenticated shell (or bootstrap wizard when `setup_required`)

### Tests for User Story 1

- [X] T024 [P] [US1] Add login page widget tests in `frontend/test/widget/auth/login_page_test.dart`
- [X] T025 [P] [US1] Add sign-in integration test in `frontend/test/integration/auth/sign_in_test.dart`

### Implementation for User Story 1

- [X] T026 [P] [US1] Implement `LoginPage` UI in `frontend/lib/features/auth/presentation/pages/login_page.dart`
- [X] T027 [US1] Implement sign-in and post-login context loading in `frontend/lib/features/auth/presentation/providers/auth_notifier.dart`
- [X] T028 [US1] Register `/login` route and wire `LoginPage` in `frontend/lib/app/router.dart`

**Checkpoint**: Valid credentials reach authenticated destination; invalid credentials show generic error

---

## Phase 5: User Story 5 - Bootstrap the Clinic Tenant (Priority: P1)

**Goal**: Default administrator creates exactly one organization and first branch on fresh install before staff provisioning

**Independent Test**: Fresh DB → bootstrap admin sign-in → create org + branch → records persist and appear in session context after re-login or refresh

### Tests for User Story 5

- [X] T029 [P] [US5] Add bootstrap RPC SQL tests in `backend/tests/bootstrap_rpc.sql`
- [X] T030 [P] [US5] Add clinic bootstrap wizard widget tests in `frontend/test/widget/auth/clinic_bootstrap_page_test.dart`

### Implementation for User Story 5

- [X] T031 [P] [US5] Implement `BootstrapRepository` calling `bootstrap_create_organization` and `bootstrap_create_branch` in `frontend/lib/features/auth/data/bootstrap_repository.dart`
- [X] T032 [US5] Implement `ClinicBootstrapPage` wizard in `frontend/lib/features/auth/presentation/pages/clinic_bootstrap_page.dart`
- [X] T033 [US5] Redirect `setup_required` sessions to bootstrap and block staff provisioning routes in `frontend/lib/app/router.dart`
- [X] T034 [P] [US5] Implement first-sign-in shipped-password warning dialog in `frontend/lib/features/auth/presentation/widgets/first_sign_in_warning_dialog.dart`

**Checkpoint**: Fresh install can create single org + branch; second organization creation is blocked

---

## Phase 6: User Story 6 - Create Staff Accounts (Priority: P1)

**Goal**: Owners/administrators (and bootstrap admin for first owner) create staff accounts with role, branch assignment, and initial password

**Independent Test**: After org/branch exist, create receptionist account, sign out, sign in as receptionist with correct role permissions

### Tests for User Story 6

- [X] T035 [P] [US6] Add `create_staff_account` RPC tests including owner-creation rules in `backend/tests/create_staff_rpc.sql`
- [X] T036 [P] [US6] Add staff provisioning widget tests in `frontend/test/widget/auth/staff_create_page_test.dart`

### Implementation for User Story 6

- [X] T037 [P] [US6] Implement `ProvisioningRepository` in `frontend/lib/features/auth/data/provisioning_repository.dart`
- [X] T038 [US6] Implement `StaffCreatePage` with credential confirmation display in `frontend/lib/features/auth/presentation/pages/staff_create_page.dart`
- [X] T039 [US6] Enforce FR-022c owner-creation rules in `backend/supabase/migrations/20260516100300_auth_rbac_functions.sql` and client-side guards in `frontend/lib/features/auth/presentation/providers/provisioning_notifier.dart`

**Checkpoint**: Staff creation blocked until org/branch exist; owner-creation rules enforced

---

## Phase 7: User Story 2 - Stay Signed In During a Shift (Priority: P1)

**Goal**: In-app session refresh while running; no session restore on app close; 15-minute idle sign-out on keyboard/pointer inactivity

**Independent Test**: Active use keeps session; app restart requires login; 15 minutes idle triggers sign-out

### Tests for User Story 2

- [X] T040 [P] [US2] Add idle timeout unit tests in `frontend/test/unit/auth/idle_timeout_service_test.dart`
- [X] T041 [P] [US2] Add session lifecycle integration tests in `frontend/test/integration/auth/session_lifecycle_test.dart`

### Implementation for User Story 2

- [X] T042 [P] [US2] Implement `IdleTimeoutService` (15 min, keyboard/pointer) in `frontend/lib/core/auth/idle_timeout_service.dart`
- [X] T043 [US2] Wire idle timeout and session refresh handling into `frontend/lib/shared/providers/auth_session_provider.dart` and `frontend/lib/app/app.dart`
- [X] T044 [US2] Ensure cold start clears any persisted auth storage in `frontend/lib/features/auth/data/auth_repository.dart`

**Checkpoint**: SC-004 and SC-007 scenarios pass in manual or automated tests

---

## Phase 8: User Story 3 - Access Only What My Role Allows (Priority: P2)

**Goal**: Permission cache from `roles_permissions`, client gating, placeholder shell with branch selector, blocked no-branch state

**Independent Test**: Sign in per role; permission cache matches seed matrix; denied action shows brief message; branch selector updates active branch

### Tests for User Story 3

- [ ] T045 [P] [US3] Add permission service unit tests in `frontend/test/unit/auth/permission_service_test.dart`
- [ ] T046 [P] [US3] Add placeholder shell and branch selector widget tests in `frontend/test/widget/auth/auth_shell_page_test.dart`

### Implementation for User Story 3

- [ ] T047 [US3] Load and cache role permissions after login in `frontend/lib/features/auth/data/permission_repository.dart`
- [ ] T048 [US3] Implement `AuthShellPage` (header, logout, branch selector, placeholder home) in `frontend/lib/features/auth/presentation/pages/auth_shell_page.dart`
- [ ] T049 [US3] Implement no-branch-assignment blocked state in `frontend/lib/features/auth/presentation/widgets/no_branch_blocked_panel.dart`
- [ ] T050 [US3] Implement permission-denied snackbar/dialog helper in `frontend/lib/core/auth/permission_denied_handler.dart`
- [ ] T051 [P] [US3] Add demo permission-gated control on shell for independent RBAC verification in `frontend/lib/features/auth/presentation/widgets/permission_demo_panel.dart`

**Checkpoint**: Five roles show expected grant/deny for sample permission keys

---

## Phase 9: User Story 4 - Sign Out Safely (Priority: P2)

**Goal**: Explicit logout clears session and returns to login

**Independent Test**: Sign in → logout → protected routes require login; no residual identity in UI state

### Tests for User Story 4

- [ ] T052 [P] [US4] Add logout integration test in `frontend/test/integration/auth/sign_out_test.dart`

### Implementation for User Story 4

- [ ] T053 [US4] Wire logout action in `AuthShellPage` through `auth_notifier` in `frontend/lib/features/auth/presentation/providers/auth_notifier.dart`

**Checkpoint**: Logout clears session and permission cache (SC-005)

---

## Phase 10: User Story 7 - Recover Access When Password Is Forgotten (Priority: P2)

**Goal**: Forgot-password shows contact-admin message; owners/administrators reset staff passwords and see assigned value

**Independent Test**: Forgot-password UI shows no self-service reset; admin reset allows staff sign-in with new password

### Tests for User Story 7

- [ ] T054 [P] [US7] Add forgot-password widget test in `frontend/test/widget/auth/forgot_password_page_test.dart`
- [ ] T055 [P] [US7] Add admin password reset integration test in `frontend/test/integration/auth/password_reset_test.dart`

### Implementation for User Story 7

- [ ] T056 [P] [US7] Implement `ForgotPasswordPage` (contact administrator message only) in `frontend/lib/features/auth/presentation/pages/forgot_password_page.dart`
- [ ] T057 [US7] Implement `StaffPasswordResetPage` in `frontend/lib/features/auth/presentation/pages/staff_password_reset_page.dart`
- [ ] T058 [US7] Wire `admin_reset_staff_password` RPC in `frontend/lib/features/auth/data/provisioning_repository.dart`

**Checkpoint**: No self-service reset; admin reset flow end-to-end works

---

## Phase 11: Polish & Cross-Cutting Concerns

**Purpose**: Documentation, subscription non-blocking verification, quickstart validation, governance

- [ ] T059 [P] Document bootstrap administrator credentials and first-run flow in `docs/setup/bootstrap-admin.md`
- [ ] T060 [P] Add subscription-cache non-blocking login verification to `backend/tests/auth_flow_smoke.sh`
- [ ] T061 Run full `specs/002-auth-rbac/quickstart.md` validation and update acceptance notes in `specs/002-auth-rbac/quickstart.md`
- [ ] T062 [P] Align `specs/002-auth-rbac/contracts/` with final RPC signatures if implementation diverges during build
- [ ] T063 Review constitution compliance and mark post-implementation notes in `specs/002-auth-rbac/plan.md`

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)** → **Foundational (Phase 2)** → **User story phases (3–10)** → **Polish (11)**
- Foundational **blocks** all user stories

### User Story Dependencies

| Story | Priority | Depends on                  | Notes                                        |
| ----- | -------- | --------------------------- | -------------------------------------------- |
| US8   | P1       | Foundational                | Route guard; pair with US1                   |
| US1   | P1       | Foundational, US8 (partial) | MVP login                                    |
| US5   | P1       | US1                         | Bootstrap after first login                  |
| US6   | P1       | US5                         | Staff create needs org/branch                |
| US2   | P1       | US1                         | Session policies on authenticated app        |
| US3   | P2       | US1, US6 (seed users)       | RBAC verification easier with multiple roles |
| US4   | P2       | US1                         | Logout from shell                            |
| US7   | P2       | US6                         | Reset requires staff accounts                |

### Recommended execution order (single developer)

1. Phase 1 → Phase 2
2. US8 → US1 (**MVP checkpoint**)
3. US5 → US6
4. US2 → US3 → US4 → US7
5. Phase 11

### Parallel Opportunities

- Phase 1: T003, T004, T005 in parallel
- Phase 2: T011–T013, T015, T017–T018 in parallel after T006–T010 sequential migrations
- Per story: all `[P]` test tasks can run in parallel before implementation tasks

### Parallel Example: Foundational migrations

```bash
# Apply in order (not parallel):
T006 → T007 → T008 → T009 → T010

# Then parallel:
T011 GoTrue hook config
T012 AuthRepository
T013 domain models
T017 rls_isolation.sql
T018 auth_flow_smoke.sh
```

### Parallel Example: User Story 1

```bash
T024 login_page_test.dart
T025 sign_in_test.dart
T026 login_page.dart
```

---

## Implementation Strategy

### MVP First (US8 + US1)

1. Complete Phase 1 and Phase 2
2. Complete US8 (route guard) + US1 (login)
3. **STOP and VALIDATE**: Sign-in and unauthenticated redirect per quickstart §4 steps 1–3

### Incremental delivery

1. **MVP**: Setup + Foundational + US8 + US1
2. **Bootstrap**: + US5 + US6 (full fresh-install path)
3. **Hardening**: + US2 (session/idle)
4. **RBAC UX**: + US3 + US4
5. **Recovery**: + US7
6. **Polish**: Phase 11

### Parallel team strategy

- **Developer A**: Phase 2 migrations + backend tests
- **Developer B**: Phase 2 Flutter auth core + US8/US1
- After Foundational: **C** → US5/US6, **D** → US2/US3

---

## Notes

- Migrations use `backend/supabase/migrations/` per plan (not `backend/migrations/`)
- `subscription_cache` is seeded but must not block login (FR-014a); verify in T060
- Bootstrap admin has no pre-seeded org/branch (clarification C)
- Owner creation: bootstrap admin for first owner only (FR-022c)
- Preserve constitution: RLS/RPC authority in PostgreSQL; Flutter cache is UX-only
