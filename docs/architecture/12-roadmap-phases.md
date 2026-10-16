# Roadmap and Phases

- Purpose: Sequence delivery by version and define the minimum architecture/spec context for each feature.
- Read this when: deciding what to build next, planning implementation order, or assembling the minimum context packet for a feature.
- Canonical for: feature sequencing, per-phase deliverables, and required architecture/spec references.
- Usually paired with: `docs/architecture/00-index.md`, `docs/architecture/11-spec-driven-development.md`, and the relevant spec in `docs/specs/...`.
- Not covered here: the full implementation detail for any one domain; that belongs in the feature spec and referenced architecture docs.

---

## Project Phases

The project is divided into three versions (V1, V2, V3). Development follows the feature-by-feature workflow defined in `docs/architecture/11-spec-driven-development.md` → `Development Workflow`. For each feature: define the spec, implement the backend, test the backend, implement the frontend, test end-to-end, then move to the next feature.

## V1 -- Foundation and Core Operations

V1 delivers a fully functional clinic management system. This is the MVP. Each feature below follows the cycle: **spec → backend → test → frontend → test**.

### Implementation Status

| Phase                                    | Status       |
| ---------------------------------------- | ------------ |
| V1-0: Project Scaffolding                | **Complete** |
| V1-1: Auth and RBAC                      | **Complete** |
| V1-2: Organization and Branch Management | **Complete** |
| V1-3: Patient Management                 | **Complete** |
| V1-4: Appointments                       | **Complete** |
| V1-5: Visits and Medical Records         | **Complete** |
| V1-6: Billing                            | **Backend complete**; frontend presentation pending |
| V1-7: Shifts                             | **Backend complete**; frontend pending      |
| V1-8: Deployment and Installer           | Pending      |

### V1-0: Project Scaffolding

Required architecture docs:
- `docs/architecture/03-deployment-networking.md` → `Deployment Architecture`, `Deployment Tiers`, `Hardware Requirements`, `Docker Composition`, `Local Networking Architecture`
- `docs/architecture/04-backend.md`
- `docs/architecture/07-frontend.md`
- `docs/architecture/11-spec-driven-development.md` → `Development Workflow`

Required specs:
- `docs/specs/common/deployment-installer.spec.md`

Deliverables:
- Flutter project initialization with folder structure per `docs/architecture/07-frontend.md` → `Project Structure`
- Supabase project initialization (local Docker Compose configuration with all required services)
- Development environment documentation (Docker install, Supabase CLI, Flutter setup)
- CI/CD pipeline skeleton (lint, test, build)
- Shared Dart packages: error handling, constants, theming foundation
- Supabase config resolution (`SupabaseConfig` with local/cloud modes)
- App shell with sidebar navigation per `docs/architecture/07-frontend.md` → `Navigation Architecture`
- Theme system (Material 3, light/dark mode foundation)
- Router configuration (GoRouter) with route guards for auth
- Supabase initialization from `SupabaseConfig`
- Shared widgets library: buttons, cards, data tables, dialogs, form fields, loading states
- Error handling UI: snackbars, error pages, connection-lost banner
- Status bar: current branch, user, connection status

### V1-1: Auth and RBAC

Required architecture docs:
- `docs/architecture/04-backend.md`
- `docs/architecture/05-database.md`
- `docs/architecture/07-frontend.md`
- `docs/architecture/09-security-rbac.md`
- `docs/architecture/11-spec-driven-development.md` → `Specification Directory Structure`, `Required Specification Sections`, `Development Workflow`

Required specs:
- `docs/specs/common/auth.spec.md`
- `docs/specs/common/rbac.spec.md`

Backend deliverables:
- Database migration: `organizations`, `branches`, `staff_members`, `staff_branch_assignments`, `roles_permissions` tables
- Audit infrastructure: `audit_log` table, audit trigger functions, `set_updated_at` trigger
- Schema conventions applied: all tables have audit columns per `docs/architecture/05-database.md` → `Schema Conventions`
- `subscription_cache` table, `app_settings` table
- GoTrue configuration for email/password auth
- `get_custom_claims` PostgreSQL function (populates JWT with org_id, branch_ids, role)
- GoTrue hook configuration to call `get_custom_claims` on login
- RLS policies for `organizations`, `branches`, `staff_members`, `staff_branch_assignments`, `roles_permissions`
- Seed data: default role-permission mappings for four roles (`administrator`, `doctor`, `receptionist`, `lab_staff`)
- Backend test utilities to verify auth flow and RLS enforcement

Frontend deliverables:
- Login page (username + password)
- Session management: **no persistence across restarts** (`EmptyLocalStorage`); idle timeout auto-sign-out
- Auth state provider (Riverpod)
- Route guard: redirect to login if unauthenticated
- Post-login: fetch staff profile, set active branch, cache permissions
- Logout flow

### V1-2: Organization and Branch Management

Required architecture docs:
- `docs/architecture/04-backend.md` → `Business Logic Distribution`, `Supabase Edge Functions (Cloud-Only, Optional)`, `API Access Patterns`
- `docs/architecture/05-database.md`
- `docs/architecture/07-frontend.md`
- `docs/architecture/09-security-rbac.md` → `Role-Based Access Control (RBAC)`, `Audit Trail`
- `docs/architecture/11-spec-driven-development.md` → `Specification Directory Structure`, `Required Specification Sections`, `Development Workflow`

Required specs:
- `docs/specs/common/organizations.spec.md`
- `docs/specs/common/branches.spec.md`
- `docs/specs/common/staff.spec.md`

Backend deliverables:
- RPC functions for organization and branch CRUD operations (branch create/update require `working_schedule`)
- Backend test utilities to verify CRUD and RLS

Frontend deliverables:
- Organization settings page (name, basic config)
- Branch management CRUD (list, create, edit, deactivate) with per-weekday working hours editor
- Staff management CRUD (list, create, edit, deactivate, assign to branches)
- Role/permission management UI (view/edit permission matrix per role)
- Branch switcher component (dropdown in status bar or sidebar)

### V1-3: Patient Management

Required architecture docs:
- `docs/architecture/04-backend.md` → `Business Logic Distribution`, `Supabase Edge Functions (Cloud-Only, Optional)`, `API Access Patterns`
- `docs/architecture/05-database.md` → `Core Schema Domains`, `Patients`, `Row Level Security (RLS) Strategy`, `PostgreSQL Functions (RPC Layer)`
- `docs/architecture/07-frontend.md`
- `docs/architecture/09-security-rbac.md` → `Audit Trail`, `Soft Delete`
- `docs/architecture/11-spec-driven-development.md` → `Specification Directory Structure`, `Required Specification Sections`, `Development Workflow`

Required specs:
- `docs/specs/operations/patients.spec.md`

Backend deliverables:
- Database migration: `patients` table
- RLS policies for patient table (organization-scoped via branch)
- RPC functions: patient search (cross-branch within org), patient deduplication check
- Indexes: `patients(branch_id, full_name)`, `patients(branch_id, phone)`
- Backend test utilities to verify patient CRUD and cross-branch visibility

Frontend deliverables:
- Patient list page (search, filter, pagination)
- Patient registration form (with client-side validation)
- Patient detail page (profile, medical history)
- Patient edit form
- Patient archival (soft delete with confirmation)
- Cross-branch patient search

Operator notes (Patient MRN — `docs/specs/016-patient-mrn-field/quickstart.md`):

**Desk staff notes (verified 2026-07-24)**

- Every patient now has a **Medical Record Number (MRN)** in the form `MRN-NNNNNN`, generated automatically when the patient is registered. You cannot edit it on the patient record.
- The **MRN** appears as the **first column** in the patients list so you can scan and locate a patient quickly. On a patient's detail page, it appears as a prominent chip near the name.
- When you register a patient, a toast confirms the new MRN immediately; the detail page also shows it.
- The MRN appears on **invoices** (list and detail) and **appointments** so billing and clinical staff can match records to the patient without opening the patient record.
- **Reassigning an MRN** is a restricted action available only to **administrators**. From a patient's detail page, an administrator can open the reassignment dialog, enter a new value, and the system rejects duplicates. Every reassignment is recorded in the audit log with the old and new values, who did it, and when.
- MRNs are **never reused**, even when a patient is archived.
- If the system cannot reach the database, **you cannot register a patient** — the form shows an error rather than save a patient with a locally generated MRN. Retry once connectivity returns.

**Automated verification**

- Backend: `./backend/tests/run_patient_management_tests.sh` from the repo root (requires local Supabase on port 54322).
- Flutter: `cd frontend && flutter test test/unit/patients/ test/boundary/patients/ test/integration/patients/`.

### V1-4: Appointments

Required architecture docs:
- `docs/architecture/04-backend.md` → `Business Logic Distribution`, `Supabase Edge Functions (Cloud-Only, Optional)`, `API Access Patterns`
- `docs/architecture/05-database.md` → `Core Schema Domains`, `Appointments`, `Row Level Security (RLS) Strategy`, `PostgreSQL Functions (RPC Layer)`
- `docs/architecture/07-frontend.md`
- `docs/architecture/09-security-rbac.md` → `Audit Trail`
- `docs/architecture/11-spec-driven-development.md` → `Specification Directory Structure`, `Required Specification Sections`, `Development Workflow`

Required specs:
- `docs/specs/005-appointment-management/spec.md` (authoritative for V1-4; shared `docs/specs/operations/appointments.spec.md` deferred)

Backend deliverables:
- Database migrations: `appointments` table and enums; optional `doctor_id`; `confirmed` status; branch `working_schedule` (required on branches); branch working-hours and slot/patient-day conflict enforcement
- RPC functions: `get_appointment_settings`, `set_appointment_default_duration`, `create_appointment`, `reschedule_appointment`, `cancel_appointment`, `update_appointment_status`, `list_appointments`
- RLS policies (branch-scoped; mutations via RPC only)
- Indexes: `appointments(branch_id, doctor_id, start_time)`, `appointments(branch_id, status, start_time)`, `appointments(branch_id, start_time)`
- `app_settings` key `appointment.default_duration_minutes` (branch → org resolution)
- Backend test utilities: `appointment_management_crud.sql`, `appointment_management_rls.sql`, `appointment_management_grants.sql`

Frontend deliverables:
- `features/appointments`: hub, booking, calendar (day/week), today's queue (Realtime with manual refresh fallback), doctor schedule, reschedule/cancel dialogs, status actions
- Appointment booking form (optional doctor, duration from settings with override, conflict and same-day patient error display)
- Phone confirmation (`scheduled` → `confirmed`) before check-in; day-gated check-in/start/complete/no-show aligned with server rules
- Navigation and permission gates (`appointments.create` / `appointments.cancel`)
- Dev seed helpers for appointments and doctors (local development only)

### V1-5: Visits and Medical Records

Required architecture docs:
- `docs/architecture/14-visits-encounter-workspace.md`
- `docs/architecture/05-database.md` → Visits & Medical Records, RPC layer
- `docs/architecture/07-frontend.md`, `09-security-rbac.md`

Required specs:
- `docs/specs/013-visits/spec.md` (documentation redesign)
- `docs/specs/014-visit-encounter-workspace/spec.md` (encounter workspace UI + patient safety)

Backend deliverables:
- Migrations: `visits`, `visit_clinical_notes`, vitals/investigations/catalogs, patient safety tables, attachments
- Legacy `soap_notes` backfilled and dropped
- RPCs: `create_visit`, `get_visit`, `save_visit_documentation`, `complete_visit`, treatment/vital/investigation/attachment/safety RPCs
- Storage bucket `visit-attachments` with org/branch/visit path RLS
- Tests: `run_visit_medical_records_tests.sh` (includes 014 encounter workspace tests)

Frontend deliverables:
- `features/visits/`: encounter workspace (stepper + expert mode), clinical note sections, catalogs, safety rail, deferred attachments
- Routes: `/visits/:id/document`, `/visits/:id/detail`
- Permissions: `visits.create`, `visits.edit_soap`, `visits.upload_attachment`
- Online-only save semantics; optimistic concurrency on clinical note

**Schema note:** Spec 014 P3 added then removed `diagnosis_codes`, `visit_diagnosis_codes`, and `visit_plan_details`. Current code uses free-text diagnosis and treatment plans only.

### V1-6: Billing

Required architecture docs:
- `docs/architecture/04-backend.md` → `Business Logic Distribution`, `Supabase Edge Functions (Cloud-Only, Optional)`, `API Access Patterns`
- `docs/architecture/05-database.md` → `Core Schema Domains`, `Billing`, `Row Level Security (RLS) Strategy`, `PostgreSQL Functions (RPC Layer)`
- `docs/architecture/07-frontend.md`
- `docs/architecture/09-security-rbac.md` → `Role-Based Access Control (RBAC)`, `Audit Trail`
- `docs/architecture/11-spec-driven-development.md` → `Specification Directory Structure`, `Required Specification Sections`, `Development Workflow`

Required specs:
- `docs/specs/007-billing/spec.md` (authoritative for V1-6)
- `docs/specs/operations/billing.spec.md` (placeholder — not yet authored; see FR-026)

Backend deliverables:
- Migrations under `backend/supabase/migrations/20260605180000_billing.sql` and follow-ups (US1–US8 RPCs, void, list/patient queries)
- Tables: `invoices`, `invoice_items`, `payments`, `insurance_providers`, `organization_billing_settings`, `invoice_number_sequences`
- RPCs: create/issue/discard invoice, item CRUD, line/invoice discounts, insurance coverage, record payment/refund, void, billing settings, insurance provider CRUD, `get_invoice_detail`, `list_invoices`, `list_patient_invoices`
- RLS: branch-scoped SELECT on invoices/items/payments; org-scoped insurance/settings; mutations via SECURITY DEFINER RPCs only; `REVOKE UPDATE, DELETE ON payments`
- Indexes: `invoices_branch_created_idx`, `invoices_status_branch_idx`, `invoices_patient_created_idx`, partial unique on active visit
- Tests: `backend/tests/billing_crud.sql`, `billing_rls.sql`, `billing_concurrency.sql` via `run_billing_tests.sh`

Frontend deliverables:
- `frontend/lib/features/billing/` — **repositories and domain models complete**; presentation layer not yet built (router placeholders)
- Planned: invoice editor, detail, list, insurance providers, receipt print, org settings partial-payments toggle
- Visit detail **Create invoice** / **Open invoice** action; patient profile billing tab (pending UI)

Operator notes (Billing):
- Set `branches.code` before issuing invoices (e.g. `MAIN` → `INV-MAIN-000001`). Missing code surfaces `branch_code_missing` on issue.
- **Allow partial payments** defaults **off**; only administrator can toggle it under Settings → Billing (`settings.billing.manage`).
- Line-level and invoice-level discounts are mutually exclusive on draft invoices; clear one scope before applying the other.
- Payments are append-only — corrections use refunds, not edits. Void `paid` invoices only after net payments are refunded.
- Operator verification walkthrough: `docs/specs/007-billing/quickstart.md`

### V1-7: Shifts

Required architecture docs:
- `docs/architecture/04-backend.md` → `Business Logic Distribution`, `Supabase Edge Functions (Cloud-Only, Optional)`, `API Access Patterns`
- `docs/architecture/05-database.md` → `Core Schema Domains`, `Shifts`, `Row Level Security (RLS) Strategy`, `PostgreSQL Functions (RPC Layer)`
- `docs/architecture/07-frontend.md`
- `docs/architecture/09-security-rbac.md` → `Role-Based Access Control (RBAC)`, `Audit Trail`
- `docs/architecture/11-spec-driven-development.md` → `Specification Directory Structure`, `Required Specification Sections`, `Development Workflow`

Required specs:
- `docs/specs/008-shift-management/spec.md`

Backend deliverables (**complete**):
- Database migration: `shifts`, `shift_assignments` tables
- RPC functions: `create_shift`, `list_shifts`, `get_shift_detail`, `modify_shift_assignments`, `update_shift`, `cancel_shift`
- Overlap detection for staff at same branch
- Tests: `run_shift_management_tests.sh`

Frontend deliverables (**pending**):
- Shift calendar view (branch-specific, weekly/monthly)
- Shift creation form (date, time range, staff assignment)
- Staff assignment UI (multi-select staff for a shift)
- Shift conflict display

### V1-8: Deployment and Installer

Required architecture docs:
- `docs/architecture/03-deployment-networking.md`
- `docs/architecture/07-frontend.md` → `Supabase Configuration`
- `docs/architecture/10-resilience-and-scale.md` → `Backup Strategy by Tier`, `Subscription Validation`, `Failure Modes and Recovery`, `Data Integrity Guarantees`
- `docs/architecture/11-spec-driven-development.md` → `Development Workflow`

Required specs:
- `docs/specs/common/deployment-installer.spec.md`

Deliverables:
- Windows installer (MSI or MSIX) for the Flutter desktop app
- Docker Compose package for receptionist PC (Supabase stack)
- First-run setup wizard:
  - Deployment mode selection (local / cloud)
  - Supabase URL configuration (auto-detect local or manual entry)
  - Admin account creation (first organization + administrator staff via setup wizard)
  - Branch creation
- Documentation: installation guide for clinic IT staff

## V2 -- Future Capabilities

V2 scope is pending a new architecture definition. The previous Ollama-based AI integration plan has been removed. AI platform delivery is tracked separately in `ai-platform/03-ai-platform-delivery-plan.md` and `specs/` AI feature directories. V2 will be redefined once the replacement architecture is finalized.

## V3 -- Analytics, Advanced Features, and Polish

V3 adds dashboards and remaining features. Each feature follows: backend → test → frontend → test.

### V3-1: Analytics

Required architecture docs:
- `docs/architecture/04-backend.md` → `Business Logic Distribution`, `Supabase Edge Functions (Cloud-Only, Optional)`, `API Access Patterns`
- `docs/architecture/05-database.md` → `Core Schema Domains`, `Row Level Security (RLS) Strategy`, `PostgreSQL Functions (RPC Layer)`
- `docs/architecture/07-frontend.md`
- `docs/architecture/09-security-rbac.md` → `Role-Based Access Control (RBAC)`
- `docs/architecture/10-resilience-and-scale.md` → `Scalability Boundaries`
- `docs/architecture/11-spec-driven-development.md` → `Specification Directory Structure`, `Required Specification Sections`, `Development Workflow`

Required specs:
- `docs/specs/analytics/dashboards.spec.md`

Backend deliverables:
- Define all analytics queries (SQL views or functions)
- PostgreSQL views/functions for:
  - Revenue by branch, by doctor, by period
  - Appointment counts by branch, by doctor, by status, by period
  - Busiest hours/days analysis
  - Doctor performance metrics (visit count, average visit duration)
  - Patient growth over time
  - Invoice aging (overdue analysis)
- RLS policies on analytics views (organization-scoped via branch)
- Materialized views for expensive aggregations (refreshed periodically)
- Backend test utilities to verify analytics queries

Frontend deliverables:
- Dashboard home page with summary cards (today's appointments, revenue, patient count)
- Revenue analytics page (charts: bar, line, pie by period/branch/doctor)
- Appointment analytics page (volume trends, busiest hours heatmap)
- Doctor performance page
- Date range picker, branch filter, export to CSV
- Chart library integration (e.g., fl_chart or syncfusion)

### V3-2: Advanced Billing

Required architecture docs:
- `docs/architecture/04-backend.md` → `Business Logic Distribution`, `Supabase Edge Functions (Cloud-Only, Optional)`, `API Access Patterns`
- `docs/architecture/05-database.md` → `Core Schema Domains`, `Billing`, `Row Level Security (RLS) Strategy`, `PostgreSQL Functions (RPC Layer)`
- `docs/architecture/07-frontend.md`
- `docs/architecture/09-security-rbac.md` → `Role-Based Access Control (RBAC)`, `Audit Trail`
- `docs/architecture/11-spec-driven-development.md` → `Specification Directory Structure`, `Required Specification Sections`, `Development Workflow`

Required specs:
- `docs/specs/operations/advanced-billing.spec.md`

Backend deliverables:
- Enhanced insurance workflow: insurance provider CRUD, claim reference tracking
- Invoice overdue detection: PostgreSQL function checks due dates, updates statuses
- Revenue reconciliation helpers

Frontend deliverables:
- Insurance provider management page
- Insurance coverage display in invoice creation
- Insurance visit flagging in appointment/visit flow

### V3-3: System Polish

Required architecture docs:
- `docs/architecture/03-deployment-networking.md`
- `docs/architecture/07-frontend.md` → `Desktop-First UX Principles`, `Navigation Architecture`
- `docs/architecture/10-resilience-and-scale.md`
- `docs/architecture/11-spec-driven-development.md` → `Development Workflow`

Required specs:
- `docs/specs/common/system-polish.spec.md`

Deliverables:
- Keyboard shortcut system (configurable, overlay help panel)
- Print system (invoices, appointment summaries, treatment plans)
- Data export (patient lists, appointment reports as CSV/PDF)
- Crash reporting integration (e.g., Sentry)
- Version enforcement check on app launch
- User preferences (theme, language, default branch)
- Performance optimization (lazy loading, pagination tuning, query optimization)

### V3-4: Localization

Required architecture docs:
- `docs/architecture/07-frontend.md` → `Project Structure`, `Desktop-First UX Principles`, `Navigation Architecture`
- `docs/architecture/11-spec-driven-development.md` → `Development Workflow`

Required specs:
- `docs/specs/common/localization.spec.md`

Deliverables:
- Arabic language support (RTL layout)
- English language support
- Locale-aware date/time/number formatting
- Translation infrastructure (ARB files)

## Phase Dependency Graph

Each feature follows the cycle: spec → backend → test → frontend → test. Features are sequential within a version.

```text
V1-0 (Scaffolding)
  │
  ├──► V1-1 (Auth/RBAC: spec → backend → test → frontend → test)
  │       │
  │       ├──► V1-2 (Org/Branch Mgmt: spec → backend → test → frontend → test)
  │       │       │
  │       │       ├──► V1-3 (Patients: spec → backend → test → frontend → test)
  │       │       │       │
  │       │       │       ├──► V1-4 (Appointments: spec → backend → test → frontend → test)
  │       │       │       │       │
  │       │       │       │       ├──► V1-5 (Visits: spec → backend → test → frontend → test)
  │       │       │       │       │       │
  │       │       │       │       │       ├──► V1-6 (Billing: spec → backend → test → frontend → test)
  │       │       │       │       │       │       │
  │       │       │       │       │       │       └──► V1-7 (Shifts: spec → backend → test → frontend → test)
  │       │       │       │       │       │               │
  │       │       │       │       │       │               └──► V1-8 (Deployment/Installer)
  │
  ▼ (V1 stable)
V3-1 (Analytics: spec → backend → test → frontend → test)
  │
  ├──► V3-2 (Advanced Billing: backend → test → frontend → test)
  │
  ├──► V3-3 (System Polish)
  │
  └──► V3-4 (Localization)
```

Notes:
- V1 features are strictly sequential. Each feature's backend is completed and tested before its frontend begins. Each feature is fully done before the next starts.
- V2 scope is pending architecture redesign.
- V3 begins after V1 is stable. V3-2 through V3-4 can be parallelized after V3-1 is complete.
