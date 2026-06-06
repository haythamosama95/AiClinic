# Implementation Plan: Shift Management (V1-7)

**Branch**: `specs/008-shift-management` | **Date**: 2026-06-06 | **Spec**: `specs/008-shift-management/spec.md`

**Input**: Feature specification from `/specs/008-shift-management/spec.md`

## Summary

Deliver V1-7 shift management: branch-scoped, non-recurring `shifts` and `shift_assignments` tables with derived status (`incomplete` when unassigned, `active` when staffed, `cancelled` on soft-delete), strict same-branch overlap detection with adjacent-shift allowance, past-date read-only mutations (org timezone), and read-only calendar access for all branch-assigned staff. Mutations require `shifts.manage` (owner/administrator seeded in V1-1) and route through `auth_internal` PL/pgSQL RPCs with branch RLS, audit log entries, and optimistic concurrency on edits. Flutter adds `features/shifts` with weekly/monthly calendar (`calendar_view` package), shift create/edit forms, staff multi-select assignment UI, and conflict error display. Builds on V1-1 auth, V1-2 org/branch/staff, V1-4 appointments (timezone pattern), V1-5 visits, V1-6 billing. No AI, no recurring templates, no time-clock, no workflow execution.

## Technical Context

**Language/Version**: Dart/Flutter stable (Windows desktop); PostgreSQL 15+ via Supabase local stack; PL/pgSQL in `auth_internal` + public RPC wrappers

**Primary Dependencies**: Supabase Flutter SDK (RPC), Riverpod, GoRouter, `calendar_view` 2.0.0 (`WeekView` + `MonthView`); V1-2 `AuthSessionNotifier`, `PermissionRepository`, staff list from settings domain; V1-4 appointment calendar patterns (provider bounds, backend-first fetch)

**Storage**: New `public.shifts`, `shift_assignments`; existing `shifts.manage` permission seed from V1-1; no new permission keys

**Testing**: `backend/tests/shift_management_crud.sql`, `shift_management_rls.sql`, `shift_management_concurrency.sql`, `run_shift_management_tests.sh`; Flutter unit/widget/integration under `frontend/test/**/shifts/**`

**Target Platform**: Windows desktop on clinic LAN against local Supabase (V1-0 profile)

**Project Type**: Desktop client + Supabase PostgreSQL (migrations, RLS, RPC); no custom API server; no AI

**Performance Goals**: Create shift with staff to calendar in under 2 minutes (SC-001); calendar period load ≤ 3s for ≤200 shifts (SC-003/NFR-003); responsive navigation under normal LAN (NFR-002)

**Constraints**: Branch-scoped RLS; mutations via RPC only; overlap same-branch only with strict intersection (`existing_start < new_end AND existing_end > new_start`); adjacent touching shifts allowed; shift times unconstrained by branch `working_schedule`; mutations only for today/future in org timezone; incomplete shifts allowed at create; direct table writes revoked; backend-first fetch before actionable UI (FR-022)

**Scale/Scope**: 1 migration; 6 RPCs; ~5 Flutter pages/widgets; 2 contract docs; no new permission keys (reuse `shifts.manage`)

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

### Pre-Research Gate

- [x] Scope fits small-to-mid-size multi-branch clinics; enterprise workforce management, union rules, float pools, and hospital-grade scheduling explicitly out of scope (FR-024)
- [x] No microservices, queues, Kubernetes, or custom primary backend service; same Flutter + Supabase + PostgreSQL stack as V1-0..V1-6
- [x] Flutter UI/orchestration; Supabase RPC; PostgreSQL owns mutations, overlap validation, eligibility, audit, RLS, and past-date gates
- [x] Protected writes routed through `auth_internal` PL/pgSQL functions; `REVOKE` direct INSERT/UPDATE/DELETE on domain tables
- [x] Defense in depth: UI permission checks, RPC validation, RLS isolation
- [x] No AI dependency; shift planning fully manual; AI absence does not block any acceptance scenario (AI Hooks, edge cases)

### Post-Design Re-Check

- [x] Overlap enforced only in PostgreSQL helper before commit; adjacent boundaries pass strict inequality test
- [x] Past-date mutability blocked server-side via org-timezone `get_org_today` helper (D3)
- [x] Branch isolation via `branch_id` in JWT `branch_ids`; cross-branch overlap intentionally not enforced (D11)
- [x] Derived status from assignment count — no redundant status column (D1)
- [x] Concurrent edits rejected via `p_expected_updated_at` stale check (D6)
- [x] Read path open to branch-assigned staff without `shifts.manage`; mutations gated (FR-003a)
- [x] Soft delete on shift cancel; assignments hard-deleted on remove; audit log for all sensitive mutations
- [x] No alteration to appointment, visit, billing, or patient behavior (FR-025)

## Project Structure

### Documentation (this feature)

```text
specs/008-shift-management/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   ├── shift-mutations.md
│   └── shift-queries.md
└── tasks.md              # /speckit-tasks (not created by /speckit-plan)
```

### Source Code (repository root)

```text
backend/
├── supabase/migrations/
│   └── 20260606180000_shift_management.sql
└── tests/
    ├── shift_management_crud.sql
    ├── shift_management_rls.sql
    ├── shift_management_concurrency.sql
    └── run_shift_management_tests.sh

frontend/lib/
├── app/
│   ├── router.dart
│   └── app_routes.dart                              # + /shifts/* routes + nav item
├── core/auth/
│   └── permission_service.dart                      # + canManageShifts, canViewShifts
├── features/
│   ├── auth/domain/permission_keys.dart             # shiftsManage (seed exists)
│   └── shifts/
│       ├── data/
│       │   └── shift_repository.dart
│       ├── domain/
│       │   ├── shift_list_item.dart
│       │   ├── shift_detail.dart
│       │   ├── shift_assignment.dart
│       │   ├── shift_status.dart                    # active | incomplete | cancelled
│       │   ├── shift_overlap_conflict.dart
│       │   └── shift_calendar_mode.dart             # week | month
│       └── presentation/
│           ├── pages/
│           │   ├── shift_calendar_page.dart         # WeekView + MonthView
│           │   ├── shift_create_page.dart
│           │   └── shift_detail_page.dart
│           ├── providers/
│           │   ├── shift_calendar_provider.dart
│           │   └── shift_detail_notifier.dart
│           └── widgets/
│               ├── shift_event_tile.dart
│               ├── shift_month_day_sheet.dart       # day detail for month view
│               ├── shift_staff_multi_select.dart
│               ├── shift_conflict_banner.dart
│               ├── shift_form_fields.dart             # date, start, end, notes
│               ├── shift_status_badge.dart
│               └── cancel_shift_dialog.dart

frontend/test/
├── unit/shifts/
├── widget/shifts/
└── integration/shifts/shift_acceptance_test.dart
```

**Structure Decision**: Shift domain lives under `frontend/lib/features/shifts` following the `features/appointments` calendar provider pattern. Staff picker reuses V1-2 settings staff list filtered by branch. All authoritative logic remains in PostgreSQL RPCs and policies per Principle III. App shell adds **Shift** nav entry gated by branch assignment (view) with mutation controls additionally gated by `shifts.manage`.

## Implementation Phases (high level)

### Phase A — Backend: schema, helpers, RPCs

1. Migration: tables `shifts`, `shift_assignments`, indexes per `data-model.md`, CHECK constraints (`end_time > start_time`, notes length)
2. RLS: branch-scoped SELECT; deny direct writes; `REVOKE INSERT/UPDATE/DELETE`
3. Helpers: `get_org_today`, `assert_shift_branch_scope`, `assert_shifts_manage`, `assert_shift_mutable`, `assert_shift_staff_eligible`, `assert_no_staff_shift_overlap`
4. RPCs per `contracts/shift-mutations.md` and `contracts/shift-queries.md`
5. Audit log entries per FR-015 (`shift.create`, `shift.update`, `shift.cancel`, `shift.assignment.add`, `shift.assignment.remove`)
6. GRANTs: `EXECUTE` on RPCs to `authenticated`; `SELECT` on tables via RLS

### Phase B — Backend verification

1. `shift_management_crud.sql` — create incomplete/active, adjacent allowed, overlap rejected, assign add/remove, last assignee removal → incomplete, update, cancel, past-date mutation rejected, cancelled immutable
2. `shift_management_rls.sql` — cross-branch/org denial; receptionist can list/detail read-only; administrator can mutate
3. `shift_management_concurrency.sql` — concurrent `update_shift` with stale `updated_at` rejected
4. `run_shift_management_tests.sh`

### Phase C — Flutter shifts module

1. Extend `PermissionService` with `canManageShifts()` / `canViewShifts()` (branch assignment sufficient for view)
2. `ShiftRepository` with backend-first `listShifts`, `getShiftDetail`, and mutation RPC wrappers
3. Routes under `/shifts` (`/shifts/calendar`, `/shifts/new`, `/shifts/:id`) with nav shell integration
4. `ShiftCalendarPage`: week/month toggle, period navigation, `WeekView`/`MonthView` event tiles with Unassigned badge, empty/error states per UI States
5. `ShiftCreatePage` / `ShiftDetailPage`: form fields, staff multi-select, conflict banner, read-only modes (no permission, past date, cancelled)
6. Optimistic concurrency UX on save: refresh prompt on `stale_shift`

### Phase D — Integration & polish

1. Active branch switcher reloads calendar (edge case)
2. Permission-denied and not-branch-assigned states
3. Connection error handling without optimistic persistence (NFR-005)

### Phase E — Tests & docs

1. Unit/widget/integration coverage for US1–US4 acceptance scenarios
2. `quickstart.md` operator walkthrough

## Complexity Tracking

No constitution violations requiring justification. All authoritative logic is in PostgreSQL; no new service tier introduced.

## Phase 0 & Phase 1 Artifacts

| Artifact                                          | Status               |
| ------------------------------------------------- | -------------------- |
| `research.md`                                     | Complete             |
| `data-model.md`                                   | Complete             |
| `contracts/shift-mutations.md`                    | Complete             |
| `contracts/shift-queries.md`                      | Complete             |
| `quickstart.md`                                   | Complete             |
| Agent context (`.cursor/rules/specify-rules.mdc`) | Updated to this plan |

**Next command**: `/speckit-tasks` to generate `tasks.md`.
