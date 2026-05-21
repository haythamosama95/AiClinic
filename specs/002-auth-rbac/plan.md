# Implementation Plan: Auth and RBAC

**Branch**: `specs/002-auth-rbac` | **Date**: 2026-05-16 | **Spec**: `specs/002-auth-rbac/spec.md`

**Input**: Feature specification from `/specs/002-auth-rbac/spec.md`

## Summary

Deliver V1-1 authentication and RBAC for AiClinic: introduce tenancy and staff schema with audit infrastructure, configure GoTrue with `get_custom_claims`, enforce RLS on org/staff tables, seed role-permission mappings and bootstrap administrator, and build Flutter auth flows (login, logout, idle timeout, no session restore on app close), minimal clinic bootstrap (create single organization + branch), staff provisioning, admin password reset, permission-aware placeholder shell with branch selector, and backend verification scripts. Subscription cache is created but does not block login. Full org/branch/staff management UI, permission-matrix editor, and subscription enforcement remain deferred to later features.

## Technical Context

**Language/Version**: Dart/Flutter stable (Windows desktop); PostgreSQL 15+ via Supabase local stack; SQL migrations and PL/pgSQL functions

**Primary Dependencies**: Supabase Flutter SDK (auth + PostgREST), GoTrue, Riverpod, GoRouter, existing V1-0 startup/deployment foundations; Supabase CLI / `backend/local` Docker stack for migrations and hooks

**Storage**: Supabase PostgreSQL for all tenancy, staff, permissions, audit, settings, and subscription cache; no client-side persistence of auth session across app restarts (in-memory session only for running process)

**Testing**: `backend/tests` SQL/shell auth+RLS verification utilities; Flutter unit/widget tests for auth notifier, permission guard, idle timer; integration tests for login → bootstrap → provision → logout flows

**Target Platform**: Windows desktop on clinic LAN against local Supabase (V1-0 deployment profile)

**Project Type**: Desktop client + Supabase-managed backend (migrations, RLS, RPC); no custom API server; no AI in this feature

**Performance Goals**: 95% of valid logins reach post-login ready within 5s; 100% protected-route blocks without session; 100% cross-org RLS denial in verification suite; 15-minute idle sign-out reliable on shared workstations

**Constraints**: Single organization per installation in V1-1; no pre-seeded org/branch; bootstrap admin only for first owner; admin-mediated password recovery only; fail-closed auth; defense in depth (UI + RPC + RLS); sessions end on app close; keyboard/pointer resets idle timer; expired subscription cache must not block login

**Scale/Scope**: 8 core tables + audit triggers; ~6 RPC/bootstrap functions; 1 auth feature module in Flutter; extend router guards; placeholder authenticated shell; no patient/appointment/billing domains

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

### Pre-Research Gate

- [x] Feature scope fits small-to-mid-size multi-branch clinics; SSO/enterprise identity federation explicitly out of scope
- [x] No microservices, queues, Kubernetes, or custom primary backend service
- [x] Flutter handles UI/session orchestration; Supabase/GoTrue handles auth; PostgreSQL owns schema, RLS, RPC, and custom claims
- [x] Validation and authorization enforced in PostgreSQL (RLS, SECURITY DEFINER RPCs) with client checks for UX only
- [x] Tenant/branch isolation, audit columns, soft delete, and permission gating designed per architecture
- [x] No AI dependency; feature works when AI is absent

### Post-Design Re-Check

- [x] Phase 1 artifacts keep bootstrap and provisioning minimal (not full V1-2 management scope)
- [x] `get_custom_claims` and RLS remain source of truth; Flutter permission cache is derivative
- [x] Bootstrap path documented for pre-organization administrator without weakening post-setup isolation
- [x] Session policy (no restore on close + idle timeout) documented without bypassing backend auth

### Post-Implementation Notes (Phase 11, 2026-05-21)

- [x] **Constitution III (backend authority)**: RLS, `auth_internal` DEFINER RPCs, and JWT claims remain authoritative; Flutter repositories send contract-aligned RPC params only.
- [x] **Constitution IV (secure operations)**: Bootstrap credentials documented in `docs/setup/bootstrap-admin.md`; no subscription gate on login (FR-014a verified in `subscription_cache_nonblocking.sql`).
- [x] **FR-014a / SC-008**: Expired, missing, and null `subscription_cache` rows do not remove `staff_member_id` from claims; `get_custom_claims(event)` path covered in tests.
- [x] **Contracts**: `bootstrap_create_branch` parameter order aligned with migration `20260521110000` and `BootstrapRepository`; `rpc_contract_alignment.sql` guards regressions.
- [x] **Deferred scope unchanged**: No subscription enforcement UI, permission-matrix editor, or full staff/org management in V1-1.

## Project Structure

### Documentation (this feature)

```text
specs/002-auth-rbac/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   ├── auth-session.md
│   ├── bootstrap-provisioning.md
│   └── rbac-permissions.md
└── tasks.md             # Phase 2 — /speckit-tasks (not created by /speckit-plan)
```

### Source Code (repository root)

```text
backend/
├── supabase/
│   └── migrations/
│       ├── 20260516100000_auth_rbac_schema.sql
│       ├── 20260516100100_auth_rbac_rls.sql
│       ├── 20260516100200_auth_rbac_functions.sql
│       └── 20260516100300_auth_rbac_seed.sql
├── seed/
│   └── bootstrap_admin.env.example
└── tests/
    ├── auth_flow_smoke.sh
    └── rls_isolation.sql

frontend/lib/
├── app/
│   ├── router.dart              # extend redirects for auth states
│   └── app_routes.dart
├── core/
│   └── auth/                    # permission helpers, idle detector
├── features/
│   ├── auth/
│   │   ├── data/
│   │   ├── domain/
│   │   └── presentation/        # login, forgot-password, shell, bootstrap, provision
│   └── startup/                 # link entry → login
└── shared/
    └── providers/
        └── auth_session_provider.dart

frontend/test/
├── unit/auth/
├── widget/auth/
└── integration/auth/
```

**Structure Decision**: Auth is a dedicated feature module under `frontend/lib/features/auth` rather than scattering login across `startup`. Backend work uses Supabase migrations (new under `backend/supabase/migrations/`) applied to the existing `backend/local` stack. V1-0 `startup` feature remains for pre-auth health check; successful startup routes to `/login`. Router gains authenticated vs unauthenticated redirect logic driven by `authSessionProvider`.

## Implementation Phases (high level)

### Phase A — Backend schema & policies

1. Migration: enums (`staff_role`), tables (`organizations`, `branches`, `staff_members`, `staff_branch_assignments`, `roles_permissions`, `audit_log`, `app_settings`, `subscription_cache`)
2. Shared triggers: `set_updated_at`, audit user columns
3. RLS policies for all feature tables
4. `get_custom_claims(uid)` + GoTrue hook configuration in `config.toml`
5. Seed: `roles_permissions` matrix, bootstrap admin auth user + `staff_members` row (`is_bootstrap_admin`)
6. RPCs: `bootstrap_create_organization`, `bootstrap_create_branch`, `create_staff_account`, `admin_reset_staff_password`

### Phase B — Backend verification

1. `backend/tests/rls_isolation.sql` — cross-org denial scenarios
2. `backend/tests/auth_flow_smoke.sh` — sign-in, claims, bootstrap RPCs

### Phase C — Flutter auth core

1. `AuthRepository` wrapping `supabase.auth` (signIn, signOut, no local persistence)
2. `AuthSessionNotifier` — staff profile, permissions, active branch, setup flags
3. Idle timeout service (15 min, keyboard/pointer)
4. Extend `GoRouter` redirect: unauthenticated → login; authenticated → shell; setup required → bootstrap wizard

### Phase D — Flutter UI flows

1. Login + forgot-password message
2. First-sign-in password warning (bootstrap admin)
3. Clinic bootstrap wizard (org + first branch)
4. Staff create + password reset (owner/admin)
5. Authenticated placeholder shell + branch selector + logout

### Phase E — Tests & docs

1. Widget/unit/integration tests per spec test cases
2. Update `docs/setup/` with bootstrap admin credentials reference
3. Execute `quickstart.md` verification checklist

## Complexity Tracking

No constitution violations. Bootstrap administrator pre-organization access uses explicit `is_bootstrap_admin` + `setup_required` claim rather than bypassing RLS globally.
