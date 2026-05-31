# Roadmap and Phases

- Purpose: Sequence delivery by version and define the minimum architecture/spec context for each feature.
- Read this when: deciding what to build next, planning implementation order, or assembling the minimum context packet for a feature.
- Canonical for: feature sequencing, per-phase deliverables, and required architecture/spec references.
- Usually paired with: `docs/architecture/00-index.md`, `docs/architecture/11-spec-driven-development.md`, and the relevant spec in `specs/...`.
- Not covered here: the full implementation detail for any one domain; that belongs in the feature spec and referenced architecture docs.

---

## Project Phases

The project is divided into three versions (V1, V2, V3). Development follows the feature-by-feature workflow defined in `docs/architecture/11-spec-driven-development.md` → `Development Workflow`. For each feature: define the spec, implement the backend, test the backend, implement the frontend, test end-to-end, then move to the next feature. AI service capabilities are added only after a concrete, tested frontend and backend exist.

## V1 -- Foundation and Core Operations

V1 delivers a fully functional clinic management system with no AI. This is the MVP. Each feature below follows the cycle: **spec → backend → test → frontend → test**.

### Implementation Status

| Phase                                    | Status       |
| ---------------------------------------- | ------------ |
| V1-0: Project Scaffolding                | **Complete** |
| V1-1: Auth and RBAC                      | **Complete** |
| V1-2: Organization and Branch Management | **Complete** |
| V1-3: Patient Management                 | **Complete** |
| V1-4: Appointments                       | **Complete** |
| V1-5: Visits and Medical Records         | Pending      |
| V1-6: Billing                            | Pending      |
| V1-7: Shifts                             | Pending      |
| V1-8: Deployment and Installer           | Pending      |

### V1-0: Project Scaffolding

Required architecture docs:
- `docs/architecture/03-deployment-networking.md` → `Deployment Architecture`, `Deployment Tiers`, `Hardware Requirements`, `Docker Composition`, `Local Networking Architecture`
- `docs/architecture/04-backend.md`
- `docs/architecture/07-frontend.md`
- `docs/architecture/11-spec-driven-development.md` → `Development Workflow`

Required specs:
- `specs/common/deployment-installer.spec.md`

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
- `specs/common/auth.spec.md`
- `specs/common/rbac.spec.md`

Backend deliverables:
- Database migration: `organizations`, `branches`, `staff_members`, `staff_branch_assignments`, `roles_permissions` tables
- Audit infrastructure: `audit_log` table, audit trigger functions, `set_updated_at` trigger
- Schema conventions applied: all tables have audit columns per `docs/architecture/05-database.md` → `Schema Conventions`
- `subscription_cache` table, `app_settings` table
- GoTrue configuration for email/password auth
- `get_custom_claims` PostgreSQL function (populates JWT with org_id, branch_ids, role)
- GoTrue hook configuration to call `get_custom_claims` on login
- RLS policies for `organizations`, `branches`, `staff_members`, `staff_branch_assignments`, `roles_permissions`
- Seed data: default role-permission mappings for all five roles
- Backend test utilities to verify auth flow and RLS enforcement

Frontend deliverables:
- Login page (email + password)
- Session management (auto-refresh, persist session)
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
- `specs/common/organizations.spec.md`
- `specs/common/branches.spec.md`
- `specs/common/staff.spec.md`

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
- `specs/operations/patients.spec.md`

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

### V1-4: Appointments

Required architecture docs:
- `docs/architecture/04-backend.md` → `Business Logic Distribution`, `Supabase Edge Functions (Cloud-Only, Optional)`, `API Access Patterns`
- `docs/architecture/05-database.md` → `Core Schema Domains`, `Appointments`, `Row Level Security (RLS) Strategy`, `PostgreSQL Functions (RPC Layer)`
- `docs/architecture/07-frontend.md`
- `docs/architecture/09-security-rbac.md` → `Audit Trail`
- `docs/architecture/11-spec-driven-development.md` → `Specification Directory Structure`, `Required Specification Sections`, `Development Workflow`

Required specs:
- `specs/005-appointment-management/spec.md` (authoritative for V1-4; shared `specs/operations/appointments.spec.md` deferred)

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
- `docs/architecture/04-backend.md` → `Business Logic Distribution`, `Supabase Edge Functions (Cloud-Only, Optional)`, `API Access Patterns`
- `docs/architecture/05-database.md` → `Core Schema Domains`, `Visits & Medical Records`, `Row Level Security (RLS) Strategy`, `PostgreSQL Functions (RPC Layer)`
- `docs/architecture/07-frontend.md`
- `docs/architecture/09-security-rbac.md` → `Audit Trail`
- `docs/architecture/11-spec-driven-development.md` → `Specification Directory Structure`, `Required Specification Sections`, `Development Workflow`

Required specs:
- `specs/operations/visits.spec.md`

Backend deliverables:
- Database migration: `visits`, `soap_notes`, `treatment_plans`, `visit_attachments` tables
- RPC functions: `create_visit` (from a **completed** appointment; V1-4 leaves appointments at `completed` without creating visits), `save_soap_note`
- Supabase Storage bucket configuration for visit attachments
- RLS policies (branch-scoped, doctor-specific for SOAP)
- Indexes on visit lookups by patient and by branch/date
- Backend test utilities to verify visit creation and attachment storage

Frontend deliverables:
- Visit creation from appointment (transition from appointment to visit)
- SOAP note editor (structured form with S/O/A/P sections)
- Specialty form support (JSON-schema-driven dynamic forms)
- Treatment plan CRUD within visit context
- Visit attachment upload/download (lab PDFs, scans, examination documents)
- Visit history view within patient profile

### V1-6: Billing

Required architecture docs:
- `docs/architecture/04-backend.md` → `Business Logic Distribution`, `Supabase Edge Functions (Cloud-Only, Optional)`, `API Access Patterns`
- `docs/architecture/05-database.md` → `Core Schema Domains`, `Billing`, `Row Level Security (RLS) Strategy`, `PostgreSQL Functions (RPC Layer)`
- `docs/architecture/07-frontend.md`
- `docs/architecture/09-security-rbac.md` → `Role-Based Access Control (RBAC)`, `Audit Trail`
- `docs/architecture/11-spec-driven-development.md` → `Specification Directory Structure`, `Required Specification Sections`, `Development Workflow`

Required specs:
- `specs/operations/billing.spec.md`

Backend deliverables:
- Database migration: `invoices`, `invoice_items`, `payments`, `insurance_providers` tables
- RPC functions: `create_invoice`, `apply_payment`, `apply_discount` (with permission check), `get_invoice_balance`
- RLS policies (branch-scoped, discount permission check)
- Indexes on invoice lookups
- Backend test utilities to verify invoice creation and payment flow

Frontend deliverables:
- Invoice creation form (link to visit, multi-line items, auto-calculation)
- Invoice list/search page
- Payment recording form (partial payment support)
- Discount application (with permission gate)
- Insurance provider selection and coverage split display
- Invoice print preview
- Invoice status tracking (visual indicators)

### V1-7: Shifts

Required architecture docs:
- `docs/architecture/04-backend.md` → `Business Logic Distribution`, `Supabase Edge Functions (Cloud-Only, Optional)`, `API Access Patterns`
- `docs/architecture/05-database.md` → `Core Schema Domains`, `Shifts`, `Row Level Security (RLS) Strategy`, `PostgreSQL Functions (RPC Layer)`
- `docs/architecture/07-frontend.md`
- `docs/architecture/09-security-rbac.md` → `Role-Based Access Control (RBAC)`, `Audit Trail`
- `docs/architecture/11-spec-driven-development.md` → `Specification Directory Structure`, `Required Specification Sections`, `Development Workflow`

Required specs:
- `specs/operations/shifts.spec.md`

Backend deliverables:
- Database migration: `shifts`, `shift_assignments` tables
- RPC functions: `create_shift` (with overlap detection), `assign_staff_to_shift`
- RLS policies (branch-scoped)
- Backend test utilities to verify shift creation and overlap detection

Frontend deliverables:
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
- `specs/common/deployment-installer.spec.md`

Deliverables:
- Windows installer (MSI or MSIX) for the Flutter desktop app
- Docker Compose package for receptionist PC (Supabase stack)
- First-run setup wizard:
  - Deployment mode selection (local / cloud)
  - Supabase URL configuration (auto-detect local or manual entry)
  - Admin account creation (first organization + owner user)
  - Branch creation
- Documentation: installation guide for clinic IT staff

## V2 -- AI Integration

V2 adds the AI interaction layer on top of the concrete, tested V1 foundation. The standard UI from V1 continues to work unchanged. Development follows: backend (AI service infra) → frontend (AI chat UI) → AI layer (agent tuning).

### V2-1: AI Service Infrastructure

Required architecture docs:
- `docs/architecture/02-system-overview.md` → `Critical Data Flow: AI Command Execution`
- `docs/architecture/03-deployment-networking.md`
- `docs/architecture/04-backend.md` → `API Access Patterns`
- `docs/architecture/06-ai.md`
- `docs/architecture/11-spec-driven-development.md` → `Specification Directory Structure`, `Required Specification Sections`, `Development Workflow`

Required specs:
- `specs/ai/ai_service.spec.md`
- `specs/ai/scheduling_agent.spec.md`
- `specs/ai/billing_agent.spec.md`
- `specs/ai/soap_summarizer.spec.md`
- `specs/ai/analytics_agent.spec.md`

Backend deliverables (AI service is backend infra):
- Write specifications for AI modules:
  - `specs/ai/ai_service.spec.md`
  - `specs/ai/scheduling_agent.spec.md`
  - `specs/ai/billing_agent.spec.md`
  - `specs/ai/soap_summarizer.spec.md`
  - `specs/ai/analytics_agent.spec.md`
- Define the structured command protocol (JSON schemas for all command types)
- Define the AI HTTP API contract (endpoints, request/response formats)
- Ollama installation script/Docker container for the receptionist PC
- HTTP wrapper service (lightweight Python or Go service) that:
  - Receives prompt + context from Flutter
  - Routes to the correct agent (based on intent classification)
  - Loads the appropriate system prompt
  - Calls Ollama inference API
  - Parses and validates structured output
  - Returns structured JSON command
- Health check endpoint (`GET /health`)
- Configuration: model selection, port, allowed origins
- Test utilities to verify AI service endpoints and structured output parsing

### V2-2: AI Chat Frontend

Required architecture docs:
- `docs/architecture/02-system-overview.md` → `Critical Data Flow: AI Command Execution`, `Critical Data Flow: Standard UI Operation`
- `docs/architecture/06-ai.md` → `Structured Command Protocol`, `Context Strategy`
- `docs/architecture/07-frontend.md`
- `docs/architecture/09-security-rbac.md` → `Role-Based Access Control (RBAC)`
- `docs/architecture/11-spec-driven-development.md` → `Development Workflow`

Required specs:
- `specs/ai/ai_chat_frontend.spec.md`

Frontend deliverables:
- AI chat panel (can be opened as an overlay or sidebar from any screen)
- Chat message history (session-only, not persisted)
- Prompt input with send button
- AI response rendering:
  - Text responses displayed as chat bubbles
  - Structured commands rendered as approval cards
- Approval card UI:
  - Shows action summary (e.g., "Book Ahmed with Dr. Ali tomorrow at 5 PM")
  - Shows resolved parameters
  - Approve / Reject buttons
  - On approve: executes the Supabase RPC call, shows result
  - On reject: discards command, shows "cancelled" message
- Entity resolution:
  - When AI returns `lookup_required`, Flutter searches and presents disambiguation
- Context assembly:
  - Reads current branch, current patient (if applicable), current date/time
  - Pre-fetches doctor list for the branch
  - Sends assembled context with each prompt

### V2-3: AI Agent Integration

Required architecture docs:
- `docs/architecture/02-system-overview.md` → `Critical Data Flow: AI Command Execution`
- `docs/architecture/05-database.md` → `Core Schema Domains`
- `docs/architecture/06-ai.md`
- `docs/architecture/07-frontend.md`
- `docs/architecture/09-security-rbac.md` → `Role-Based Access Control (RBAC)`
- `docs/architecture/11-spec-driven-development.md` → `Specification Directory Structure`, `Required Specification Sections`, `Development Workflow`

Required specs:
- `specs/ai/scheduling_agent.spec.md`
- `specs/ai/billing_agent.spec.md`
- `specs/ai/soap_summarizer.spec.md`
- `specs/ai/analytics_agent.spec.md`

AI layer deliverables:
- Define and tune system prompts for each agent
- Select and document recommended models per agent
- Scheduling agent: create/cancel appointments via AI
- Billing agent: create invoices via AI
- SOAP summarizer: generate SOAP draft from free-text, present for doctor approval
- Shift agent: create shifts and assign staff via AI
- Analytics agent: answer operational questions with pre-built query templates
- End-to-end testing of each agent through the full pipeline (prompt → AI service → Flutter approval → Supabase execution)

## V3 -- Analytics, Advanced Features, and Polish

V3 adds dashboards, AI-powered analytics, and remaining features. Each feature follows: backend → test → frontend → test.

### V3-1: Analytics

Required architecture docs:
- `docs/architecture/04-backend.md` → `Business Logic Distribution`, `Supabase Edge Functions (Cloud-Only, Optional)`, `API Access Patterns`
- `docs/architecture/05-database.md` → `Core Schema Domains`, `Row Level Security (RLS) Strategy`, `PostgreSQL Functions (RPC Layer)`
- `docs/architecture/06-ai.md` → `Structured Command Protocol`, `Context Strategy`
- `docs/architecture/07-frontend.md`
- `docs/architecture/09-security-rbac.md` → `Role-Based Access Control (RBAC)`
- `docs/architecture/10-resilience-and-scale.md` → `Scalability Boundaries`
- `docs/architecture/11-spec-driven-development.md` → `Specification Directory Structure`, `Required Specification Sections`, `Development Workflow`

Required specs:
- `specs/analytics/dashboards.spec.md`

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

AI layer deliverables:
- Natural language queries in AI chat that return analytics results
- AI maps questions to pre-built analytics query identifiers
- Results rendered as inline charts or tables in the chat

### V3-2: Advanced Billing

Required architecture docs:
- `docs/architecture/04-backend.md` → `Business Logic Distribution`, `Supabase Edge Functions (Cloud-Only, Optional)`, `API Access Patterns`
- `docs/architecture/05-database.md` → `Core Schema Domains`, `Billing`, `Row Level Security (RLS) Strategy`, `PostgreSQL Functions (RPC Layer)`
- `docs/architecture/07-frontend.md`
- `docs/architecture/09-security-rbac.md` → `Role-Based Access Control (RBAC)`, `Audit Trail`
- `docs/architecture/11-spec-driven-development.md` → `Specification Directory Structure`, `Required Specification Sections`, `Development Workflow`

Required specs:
- `specs/operations/advanced-billing.spec.md`

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
- `specs/common/system-polish.spec.md`

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
- `specs/common/localization.spec.md`

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
V2-1 (AI Service Infra: spec → backend → test)
  │
  ├──► V2-2 (AI Chat Frontend: implement → test)
  │       │
  │       └──► V2-3 (AI Agent Integration: tune → test end-to-end)
  │
  ▼ (V2 stable)
V3-1 (Analytics: spec → backend → test → frontend → test → AI layer)
  │
  ├──► V3-2 (Advanced Billing: backend → test → frontend → test)
  │
  ├──► V3-3 (System Polish)
  │
  └──► V3-4 (Localization)
```

Notes:
- V1 features are strictly sequential. Each feature's backend is completed and tested before its frontend begins. Each feature is fully done before the next starts.
- V2 begins only after V1 is stable. AI service infrastructure (backend) is built and tested first, then the Flutter AI chat UI, then agent tuning.
- V3 begins only after V2 is stable. V3-2 through V3-4 can be parallelized after V3-1 is complete.
