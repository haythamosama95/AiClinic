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

### Critical Data Flow: AI Command Execution

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
        ├── setupRequired = true → navigate to Bootstrap flow
        │
        ▼ (normal)
Navigate to authenticated shell (sidebar + content area)
```

---
