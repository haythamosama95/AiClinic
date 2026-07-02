# System Overview

- Purpose: Provide the top-level mental model for layers, responsibilities, and critical request flows.
- Read this when: you need to understand how the Flutter app, Supabase backend, PostgreSQL data layer, and AI service interact.
- Canonical for: system layers and end-to-end data flows for manual UI operations and AI-assisted commands.
- Usually paired with: `docs/architecture/04-backend.md`, `docs/architecture/06-ai.md`, `docs/architecture/07-frontend.md`.
- Not covered here: detailed schema definitions, deployment topology, or per-feature implementation requirements.

---

## System Architecture Overview

### System Layers

The system is composed of four distinct layers. Each layer has a single responsibility and communicates only with its adjacent layers through well-defined interfaces.

```
┌─────────────────────────────────────────────────────────┐
│                   PRESENTATION LAYER                     │
│              Flutter Desktop Application                 │
│   (UI, State Management, User Interaction, AI Chat UI)   │
└──────────────┬──────────────────────┬───────────────────┘
               │                      │
               │ Supabase SDK         │ HTTP REST
               │                      │
┌──────────────▼──────────────┐ ┌─────▼───────────────────┐
│       BACKEND LAYER         │ │     AI SERVICE LAYER     │
│         Supabase            │ │   Local Inference Server  │
│  (Auth, PostgREST, Storage, │ │  (Ollama + HTTP Wrapper)  │
│   Realtime, RLS, RPC)       │ │  Structured Commands Only │
└──────────────┬──────────────┘ └─────────────────────────┘
               │                        ▲
               │ SQL                    │ NEVER connects
               │                        │ to backend
┌──────────────▼──────────────┐         │
│        DATA LAYER           │         │
│       PostgreSQL            │         │
│  (Schema, Triggers,         │         │
│   Functions, Constraints)   │         │
└─────────────────────────────┘
```

#### Layer Responsibilities

| Layer        | Responsibility                                                                                                                                            | Technology                      | Communicates With                                     |
| ------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------- | ----------------------------------------------------- |
| Presentation | UI rendering, state management, user input, AI chat interface, command approval UI, navigation, form validation                                           | Flutter + Riverpod              | Backend Layer (Supabase SDK), AI Service Layer (HTTP) |
| Backend      | Authentication, authorization (RLS), REST API auto-generation (PostgREST), file storage, realtime subscriptions, business logic execution (RPC functions) | Supabase (self-hosted or cloud) | Data Layer (internal PostgreSQL)                      |
| AI Service   | Natural language parsing, intent extraction, structured command generation, SOAP summarization, analytics query generation                                | Ollama + HTTP wrapper           | Presentation Layer only (responds to HTTP requests)   |
| Data         | Schema definition, referential integrity, triggers, audit field population, complex domain validation functions                                           | PostgreSQL 15+                  | Accessed exclusively through Backend Layer            |

> **Implementation status:** The AI Service Layer shown below is a target-architecture placeholder. As of this writing there is no AI service, no chat UI, and no HTTP client code for it anywhere in the codebase. The diagram and flow describe the intended shape for V2 (`docs/architecture/12-roadmap-phases.md`), not current behavior. Everything else on this page (Presentation, Backend, Data layers and their two data flows below) is implemented and current.

### Critical Data Flow: AI Command Execution (target design — not implemented)

```
User types prompt in Flutter AI chat
        │
        ▼
Flutter sends HTTP POST to AI Service
  (prompt + minimal context from current UI state)
        │
        ▼
AI Service parses intent, returns structured JSON command
  e.g. { "action": "create_appointment", "params": { "patient_id": "...", "doctor_id": "...", "datetime": "..." } }
        │
        ▼
Flutter renders command preview card for human review
        │
        ▼
User approves or rejects
        │
        ▼ (if approved)
Flutter calls Supabase SDK (same path as standard UI action)
  e.g. supabase.rpc('create_appointment', params)
        │
        ▼
Supabase PostgREST → PostgreSQL function validates and executes
        │
        ▼
Result returned to Flutter → UI updates
```

The backend never knows whether a request originated from manual UI interaction or AI-generated command. Both paths are identical from the backend's perspective.

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
Load deployment-profile.json (Supabase URL, anon key, AI URL)
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
