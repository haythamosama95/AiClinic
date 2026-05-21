# Implementation Plan: Organization and Branch Management

**Branch**: `specs/003-org-branch-management` | **Date**: 2026-05-21 | **Spec**: `specs/003-org-branch-management/spec.md`

**Input**: Feature specification from `/specs/003-org-branch-management/spec.md`

## Summary

Deliver V1-2 administration for the single clinic tenant: organization profile settings (owner/administrator by role), full branch and staff lifecycle UI with secured RPCs, owner-editable global permission matrix (administrator read-only), branch switcher promoted to the main shell status bar, and backend verification for CRUD plus RLS. Builds on V1-1 schema and bootstrap flows without new tenancy tables; deactivation uses `is_active` only (no soft-delete UI). Clarifications lock last-active-branch hard block with edit shortcut, permission cache reload policy, and blocked shell for staff with only inactive branch assignments.

## Technical Context

**Language/Version**: Dart/Flutter stable (Windows desktop); PostgreSQL 15+ via Supabase local stack; PL/pgSQL in `auth_internal` + public RPC wrappers

**Primary Dependencies**: Supabase Flutter SDK, Riverpod, GoRouter, V1-1 `features/auth` (session, permissions, bootstrap, provisioning repositories), V1-0 startup/settings foundations

**Storage**: Existing tables `organizations`, `branches`, `staff_members`, `staff_branch_assignments`, `roles_permissions`, `audit_log`; partial unique index on branch code

**Testing**: New `backend/tests/org_branch_management_*.sql`; Flutter unit tests for repositories and permission reload; widget/integration tests for settings flows and branch switcher

**Target Platform**: Windows desktop on clinic LAN against local Supabase (V1-0 deployment profile)

**Project Type**: Desktop client + Supabase PostgreSQL (migrations, RLS, RPC); no custom API server; no AI

**Performance Goals**: Organization save confirmation within 10s (SC-001); branch list usable at 50 rows (NFR-002); branch switch perceived &lt; 2s (NFR-005); 100% last-active-branch block and cross-org denial in verification suite

**Constraints**: Single organization per installation; no soft-delete UI; organization auth by owner/admin role; branch/staff by permission keys; permission matrix owner-write only; client cache stale until login/reload but server enforces current grants; bootstrap RPCs retained for incomplete setup; no patient/appointment/billing domains

**Scale/Scope**: ~6 new RPC families + 1 index; extend `features/settings` (~8 screens/routes); relocate branch switcher to status bar; ~5 contract docs; no new core tables

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

### Pre-Research Gate

- [x] Feature scope fits small-to-mid-size multi-branch clinics; enterprise multi-tenant SaaS out of scope
- [x] No microservices, queues, Kubernetes, or custom primary backend service
- [x] Flutter UI/orchestration; Supabase auth/PostgREST; PostgreSQL owns mutations, validation, audit, RLS
- [x] Protected writes via `auth_internal` RPCs; client validation for UX only
- [x] Tenant/branch isolation, audit, soft-delete schema preserved; V1-2 UI uses deactivate not delete
- [x] No AI dependency

### Post-Design Re-Check

- [x] Phase 1 contracts keep mutations in RPC layer; reads use RLS-scoped SELECT where appropriate
- [x] `build_staff_claims` already filters inactive branches — aligns with FR-008a blocked shell
- [x] Permission matrix changes do not bypass server-side grant checks (FR-011)
- [x] Bootstrap paths unchanged; steady-state RPCs gated on `setup_required = false`
- [x] Branch switcher target documented per frontend architecture (status bar)

## Project Structure

### Documentation (this feature)

```text
specs/003-org-branch-management/
├── plan.md              # This file
├── research.md          # Phase 0
├── data-model.md        # Phase 1
├── quickstart.md        # Phase 1
├── contracts/
│   ├── organization-management.md
│   ├── branch-management.md
│   ├── staff-management.md
│   ├── role-permissions-matrix.md
│   └── branch-switcher-shell.md
└── tasks.md             # Phase 2 — /speckit-tasks (not created by /speckit-plan)
```

### Source Code (repository root)

```text
backend/
├── supabase/migrations/
│   └── 20260521100000_org_branch_management.sql   # planned timestamp
└── tests/
    ├── org_branch_management_crud.sql
    ├── org_branch_management_rls.sql
    └── run_org_branch_management_tests.sh

frontend/lib/
├── app/
│   ├── router.dart                 # settings sub-routes
│   └── app_routes.dart
├── features/
│   ├── auth/                       # existing — bootstrap, session, shell
│   │   └── presentation/widgets/shell_branch_selector.dart  # migrate to status bar
│   └── settings/
│       ├── data/
│       │   ├── organization_repository.dart
│       │   ├── branch_repository.dart
│       │   ├── staff_admin_repository.dart
│       │   └── role_permissions_repository.dart
│       ├── domain/
│       └── presentation/
│           ├── pages/
│           │   ├── settings_page.dart          # hub links
│           │   ├── organization_settings_page.dart
│           │   ├── branch_list_page.dart
│           │   ├── branch_form_page.dart
│           │   ├── staff_list_page.dart
│           │   ├── staff_form_page.dart
│           │   └── role_permissions_page.dart
│           └── widgets/
│               └── shell_status_bar.dart       # branch | user | connection
└── shared/providers/
    └── auth_session_provider.dart              # add reloadContext()

frontend/test/
├── unit/settings/
├── widget/settings/
└── integration/settings/
```

**Structure Decision**: Administration lives under `features/settings` (existing `/settings` entry) rather than expanding `auth` beyond bootstrap/provisioning. Backend follows V1-1 `auth_internal` pattern. Branch switcher moves from `AuthShellPage` AppBar to a shared status bar widget used by the authenticated shell until full sidebar navigation ships in later phases.

## Implementation Phases (high level)

### Phase A — Backend: schema delta & RPCs

1. Migration: partial unique index `branches_organization_code_unique`
2. `auth_internal.assert_owner_or_administrator()`, `assert_permission(key)`
3. RPCs: `update_organization`, `manage_create_branch`, `update_branch`, `set_branch_active`, `update_staff_member`, `set_staff_active`, `update_role_permission`
4. RLS/policy: allow `organizations` UPDATE for owner/admin via RPC only (keep direct UPDATE blocked if current); `roles_permissions` UPDATE via RPC owner-only
5. Audit log entries per data-model.md

### Phase B — Backend verification

1. `org_branch_management_crud.sql` — last active branch, org update, staff lifecycle, matrix toggle
2. `org_branch_management_rls.sql` — cross-org denial
3. Shell runner script

### Phase C — Flutter settings module

1. Repositories wrapping RPC + list queries per contracts
2. Routes and hub on `SettingsPage`
3. Organization, branch, staff, permissions pages with states from spec
4. Wire password reset from staff detail to existing `ProvisioningRepository`

### Phase D — Shell branch switcher

1. `ShellStatusBar` with branch dropdown + user + connection
2. `AuthSessionNotifier.setActiveBranch` + persist for session
3. Demote AppBar `ShellBranchSelector` when status bar active
4. `reloadContext()` after permission matrix save and on app resume

### Phase E — Tests & docs

1. Unit/widget/integration tests per spec test cases 1–13
2. Update setup docs linking settings admin flows

## Complexity Tracking

No constitution violations requiring justification.

## Phase 0 & Phase 1 Artifacts

| Artifact                                          | Status               |
| ------------------------------------------------- | -------------------- |
| `research.md`                                     | Complete             |
| `data-model.md`                                   | Complete             |
| `contracts/*`                                     | Complete (5 files)   |
| `quickstart.md`                                   | Complete             |
| Agent context (`.cursor/rules/specify-rules.mdc`) | Updated to this plan |

**Next command**: `/speckit-tasks` to generate `tasks.md`.
