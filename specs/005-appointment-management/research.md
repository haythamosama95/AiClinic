# Research: Appointment Management

## Decision 1: `auth_internal` + public RPC wrappers (`rpc_result`)

- **Decision**: Appointment mutations and list queries run in `auth_internal` (SECURITY DEFINER) with thin `public.*` INVOKER wrappers returning `public.rpc_result`.
- **Rationale**: Constitution III/IV; conflict detection, status transitions, permission checks (`appointments.create` / `appointments.cancel`), and audit stay in PostgreSQL.
- **Alternatives considered**: Direct PostgREST writes (rejected). Edge Functions (rejected — cloud-only).

## Decision 2: Branch-scoped RLS on `appointments`

- **Decision**: RLS filters `branch_id = ANY(jwt branch_ids)` within organization; SELECT allowed for operational reads; INSERT/UPDATE/DELETE denied on table (RPC only).
- **Rationale**: `docs/architecture/05-database.md` appointments example uses branch isolation; differs from patients (org-wide).
- **Alternatives considered**: Org-wide appointment reads (rejected — contradicts architecture and spec FR-003).

## Decision 3: Conflict detection via time overlap (branch-wide)

- **Decision**: Overlap predicate `start_time < p_end AND end_time > p_start` for same `branch_id`, excluding `cancelled` and `no_show`, and excluding self on reschedule. Branch-wide slot uniqueness (not per-doctor).
- **Rationale**: FR-009; implemented and verified in `appointment_management_crud.sql`.
- **Alternatives considered**: Per-doctor-only overlap (rejected — double-booking same room/time). Advisory locks only (rejected — no DB guarantee).

## Decision 4: ENUM types for type and status

- **Decision**: `appointment_type`: `planned` only. `appointment_status`: `scheduled`, `confirmed`, `checked_in`, `in_progress`, `completed`, `cancelled`, `no_show`.
- **Rationale**: Architecture schema; spec FR-011; phone confirmation requires `confirmed` before check-in.
- **Alternatives considered**: Text columns with CHECK (rejected — weaker typing).

## Decision 5: Default duration in `app_settings`

- **Decision**: Key `appointment.default_duration_minutes` in `public.app_settings`; resolution order: row with `branch_id = active branch` → row with `branch_id IS NULL` (org-wide) → fallback **20** minutes in RPC if unset. `set_appointment_default_duration` gated by `settings.manage_branches` or organization settings access (owner/administrator).
- **Rationale**: Clarification session 2026-05-24 — configurable default, overridable per booking; reuses existing settings table from V1-1.
- **Alternatives considered**: Hard-coded 20 only (rejected). New `branch_settings` table (rejected — YAGNI).

## Decision 6: Duration bounds and end-time calculation

- **Decision**: Effective duration 5–240 minutes; `end_time = start_time + duration` unless caller supplies explicit `p_end_time` that validates after `start_time` and implies duration within bounds.
- **Rationale**: Prevents zero-length and absurd slots; supports custom end time on forms.
- **Alternatives considered**: End time only without duration field (rejected — worse UX for desk staff).

## Decision 7: Same-day patient limit

- **Decision**: `create_appointment` rejects a second non-terminal appointment for the same patient at the same branch on the same local calendar day (`PATIENT_ALREADY_BOOKED_SAME_DAY`).
- **Rationale**: Prevents duplicate same-day bookings; verified in backend tests.
- **Alternatives considered**: Unlimited same-day bookings (rejected — front-desk error risk).

## Decision 8: `queue_number` unused in V1-4

- **Decision**: Column optional/nullable in schema for architecture alignment; always NULL in V1-4 application paths; ordering uses `start_time` only (FR-015a).
- **Rationale**: Clarification removed queue_number ordering.
- **Alternatives considered**: Sequential daily counter (rejected).

## Decision 9: Status transitions in single RPC

- **Decision**: `update_appointment_status(p_appointment_id, p_new_status)` validates transition matrix; cancel/no-show require `appointments.cancel`; forward transitions require `appointments.create`; day-gating for in-day statuses; no assigned-doctor check.
- **Rationale**: Clarification — reception may complete full flow; architecture function name.
- **Alternatives considered**: Separate RPC per transition (rejected — verbose).

## Decision 10: `reschedule_appointment` for `scheduled` only

- **Decision**: Dedicated RPC updates `start_time`/`end_time` with conflict check excluding self; only when `status = scheduled`.
- **Rationale**: Clarification session 2026-05-23 option A.
- **Alternatives considered**: Cancel+rebook only (rejected by clarification).

## Decision 11: List/query RPC for calendar, queue, doctor schedule

- **Decision**: `list_appointments` with `p_branch_id`, `p_from`, `p_to`, optional `p_doctor_id`, optional `p_statuses[]`; returns rows sorted by `start_time`. Today's queue = `p_from`/`p_to` = start/end of today in organization timezone from `organizations.timezone` (or branch org join).
- **Rationale**: Single contract for calendar week view, doctor filter, and queue; branch-scoped.
- **Alternatives considered**: Direct SELECT from Flutter (acceptable for reads but RPC centralizes permission + filter rules).

## Decision 12: Realtime queue updates

- **Decision**: Flutter `Supabase.channel` postgres_changes on `public.appointments` INSERT/UPDATE; client filters events where `branch_id == activeBranch` and `start_time` is today (org TZ). Degraded manual refresh per spec.
- **Rationale**: Architecture 04-backend Realtime; FR-016; no custom websocket service.
- **Alternatives considered**: Polling only (rejected — spec requires live when available).

## Decision 13: Flutter module `features/appointments`

- **Decision**: Routes under `/appointments` (hub, book, queue, calendar, doctor schedule); shell nav when `appointments.create` OR `appointments.cancel`.
- **Rationale**: `docs/architecture/07-frontend.md` appointments folder; separation from patients/settings.
- **Alternatives considered**: Embed in patients feature (rejected).

## Decision 14: `doctor_id` references `staff_members.id` (optional)

- **Decision**: FK `doctor_id` → `staff_members(id)` nullable; RPC asserts `role = 'doctor'` and branch assignment when `doctor_id` is set.
- **Rationale**: Spec data model; supports unassigned provider slots.
- **Alternatives considered**: Separate doctors table (rejected — not in schema). Required doctor (rejected — optional assignment implemented).

## Decision 15: PermissionKeys extension

- **Decision**: Add `appointmentsCreate`, `appointmentsCancel` to `PermissionKeys`; helpers `canCreateAppointments`, `canCancelAppointments`, `canAccessAppointments` (view if either grant).
- **Rationale**: Seeds exist; frontend must gate UI like patients module.
- **Alternatives considered**: Literal strings (rejected).

## Decision 16: Default duration UI in settings

- **Decision**: Add numeric field on organization settings page (and optional per-branch override later in branch form if time permits) writing `app_settings` via `set_appointment_default_duration`; booking form reads via `get_appointment_settings(p_branch_id)`.
- **Rationale**: Clarification — user-editable default; org settings already exists in V1-2.
- **Alternatives considered**: Hidden config file (rejected).
