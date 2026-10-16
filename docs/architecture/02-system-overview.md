# System Overview

- Purpose: Provide the top-level mental model for layers, responsibilities, and critical request flows.
- Read this when: you need to understand how the Flutter app, Supabase backend, and PostgreSQL data layer interact.
- Canonical for: system layers and end-to-end data flows for manual UI operations.
- Usually paired with: `docs/architecture/04-backend.md`, `docs/architecture/07-frontend.md`.
- Not covered here: detailed schema definitions, deployment topology, or per-feature implementation requirements.

---

## System Architecture Overview

### System Layers

The system is composed of three distinct layers. Each layer has a single responsibility and communicates only with its adjacent layers through well-defined interfaces.

```
┌─────────────────────────────────────────────────────────┐
│                   PRESENTATION LAYER                     │
│              Flutter Desktop Application                 │
│     (UI, State Management, User Interaction)             │
└──────────────────────────┬──────────────────────────────┘
                           │
                           │ Supabase SDK
                           │
┌──────────────────────────▼──────────────────────────────┐
│                    BACKEND LAYER                          │
│                      Supabase                             │
│   (Auth, PostgREST, Storage, Realtime, RLS, RPC)         │
└──────────────────────────┬──────────────────────────────┘
                           │
                           │ SQL
                           │
┌──────────────────────────▼──────────────────────────────┐
│                     DATA LAYER                            │
│                    PostgreSQL                             │
│   (Schema, Triggers, Functions, Constraints)            │
└───────────────────────────────────────────────────────────┘
```

#### Layer Responsibilities

| Layer        | Responsibility                                                                                                                                            | Technology                      | Communicates With                |
| ------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------- | -------------------------------- |
| Presentation | UI rendering, state management, user input, navigation, form validation                                                                                   | Flutter + Riverpod              | Backend Layer (Supabase SDK)     |
| Backend      | Authentication, authorization (RLS), REST API auto-generation (PostgREST), file storage, realtime subscriptions, business logic execution (RPC functions) | Supabase (self-hosted or cloud) | Data Layer (internal PostgreSQL) |
| Data         | Schema definition, referential integrity, triggers, audit field population, complex domain validation functions                                           | PostgreSQL 15+                  | Accessed exclusively through Backend Layer |

### Critical Data Flow: Standard UI Operation

```
User interacts with Flutter UI (e.g., clicks "Register Patient")
        │
        ▼
Flutter service layer validates input client-side
        │
        ▼
Flutter calls Supabase SDK
  e.g. supabase.rpc('create_patient', params)
        │
        ▼
PostgREST routes to public.create_patient() [SECURITY INVOKER]
        │
        ▼
Delegates to auth_internal.create_patient() [SECURITY DEFINER]
  → Permission check (assert_permission)
  → Business validation
  → Duplicate detection
  → INSERT with audit log
        │
        ▼
rpc_result returned to Flutter → UI updates via Riverpod state
```

> **Note:** Direct table INSERT/UPDATE via PostgREST is blocked by RLS. All domain writes go through RPC functions.

### Critical Data Flow: App Startup

```
App launch
        │
        ▼
Load deployment-profile.json (Supabase URL, anon key)
        │
        ▼
Probe health endpoints (GoTrue /auth/v1/health, PostgREST /rest/v1/)
        │
        ├── Probes fail → show degraded-state/retry UI
        │
        ▼ (healthy)
Initialize Supabase SDK (EmptyLocalStorage — no session persistence)
        │
        ▼
Force sign-out of any stale in-memory session (cold-start safety)
        │
        ▼
Navigate to Login page → user signs in with username + password
        │
        ▼
Decode JWT custom claims → build AuthSessionContext
  (organizationId, branchIds, role, permissions, setupRequired)
        │
        ├── setupRequired = true → navigate to `/bootstrap` (SetupPage wizard)
        │       │
        │       ▼
        │   Organization step → Branch step → Staff accounts step → Review
        │       │
        │       ▼
        │   Single RPC: bootstrap_finish_setup(...) creates org + branch + all
        │   staff accounts transactionally, then refreshSession() re-issues the JWT
        │
        ▼ (normal)
Navigate to authenticated shell (sidebar + content area)
```

> **Note on bootstrap:** early migrations exposed separate `bootstrap_create_organization` / `bootstrap_create_branch` / `create_staff_account` RPCs called in sequence by the wizard. The current wizard (`frontend/lib/features/setup/`) calls a single consolidated `bootstrap_finish_setup(...)` RPC (introduced in `backend/supabase/migrations/20260611140000_allow_admin_create_owner_and_atomic_bootstrap_setup.sql`, refined by later migrations) that creates the organization, first branch, and all staff accounts (including the bootstrap admin's real login) in one transaction. The older multi-step RPCs still exist in the schema for backward compatibility/tests but are not the primary path.

### Critical Data Flow: Visit Encounter Documentation

```
Doctor opens visit from appointment queue or patient history
        │
        ▼
Flutter loads get_visit + get_patient_safety_context via RPC
        │
        ▼
Encounter workspace (guided stepper or expert accordion mode)
  → Subjective: visit_clinical_notes sections + patient safety rail
  → Objective: vital signs, investigations, attachments
  → Plan: catalog-driven medications/investigations
        │
        ▼
Edits either persist immediately (line-item RPCs) or stage in-memory
  when deferPersistence=true (in-session draft only)
        │
        ▼
Submit: save_visit_documentation + complete_visit
  → server validates documentation completeness rules
  → completes linked appointment (in_progress cannot skip via status RPC)
        │
        ▼
UI returns to visit detail / patient profile
```

Visit mutations require live Supabase connectivity. Deferred persistence is not durable offline storage.

---
