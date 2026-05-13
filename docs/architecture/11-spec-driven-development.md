# Spec-Driven Development

- Purpose: Define how architecture docs, feature specs, and implementation agents fit together.
- Read this when: planning or implementing a feature, writing a new spec, or deciding which architecture docs an implementation task should load.
- Canonical for: the implementation workflow, required spec structure, and context-loading rules for agents.
- Usually paired with: `docs/architecture/00-index.md`, `docs/architecture/12-roadmap-phases.md`, and the specific feature spec in `specs/...`.
- Not covered here: detailed domain rules that belong in backend, database, frontend, AI, or security docs.

---

## Overview

Development follows a modular, iterative specification-driven process powered by the **spec-kit** utility. Each feature gets its own specification document, and the full cycle (spec → backend → test → frontend → test) completes before moving to the next feature.

```text
Architecture docs in `docs/architecture/`
        │
        ▼
For each feature, sequentially:
    ┌──────────────────────────────────────────────┐
    │ 1. Feature Specification (spec-kit)          │
    │         │                                     │
    │         ▼                                     │
    │ 2. Backend (schema, RPC, RLS) → Test         │
    │         │                                     │
    │         ▼                                     │
    │ 3. Frontend (Flutter module) → Test          │
    │         │                                     │
    │         ▼                                     │
    │ 4. Next feature ─────────────────────────────►│
    └──────────────────────────────────────────────┘
```

## Context Loading Rules

Implementation agents do **not** read the entire architecture set by default.

1. Start with `docs/architecture/00-index.md`.
2. Open the assigned spec in `specs/...`.
3. Load only the architecture docs and headings listed in that spec.
4. Use `docs/architecture/12-roadmap-phases.md` as the fallback routing source when a spec is missing or still being authored.
5. Escalate to cross-cutting docs only when the feature explicitly depends on them, such as `09-security-rbac.md` or `10-resilience-and-scale.md`.

## Specification Directory Structure

```text
specs/
├── README.md
├── common/
│   ├── auth.spec.md
│   ├── organizations.spec.md
│   ├── branches.spec.md
│   ├── staff.spec.md
│   ├── rbac.spec.md
│   ├── deployment-installer.spec.md
│   ├── system-polish.spec.md
│   └── localization.spec.md
│
├── operations/
│   ├── patients.spec.md
│   ├── appointments.spec.md
│   ├── visits.spec.md
│   ├── billing.spec.md
│   ├── shifts.spec.md
│   └── advanced-billing.spec.md
│
├── ai/
│   ├── ai_service.spec.md
│   ├── ai_chat_frontend.spec.md
│   ├── scheduling_agent.spec.md
│   ├── billing_agent.spec.md
│   ├── soap_summarizer.spec.md
│   └── analytics_agent.spec.md
│
└── analytics/
    └── dashboards.spec.md
```

## Required Specification Sections

Every specification document must contain:

| Section                         | Content                                                                                            |
| ------------------------------- | -------------------------------------------------------------------------------------------------- |
| **Business Context**            | Why this module exists, who uses it, how it fits into clinic workflows                             |
| **Functional Requirements**     | Numbered list of what the module must do                                                           |
| **Non-Functional Requirements** | Performance, security, offline behavior requirements                                               |
| **Required Architecture Docs**  | Exact architecture files and headings that implementation agents must load                         |
| **Data Model**                  | Full table DDL with columns, types, constraints, indexes. References to shared schema conventions. |
| **RPC Functions**               | PostgreSQL function signatures, parameter types, return types, validation rules, error codes       |
| **RLS Policies**                | Row-level security policy definitions for each table in this module                                |
| **API Contracts**               | Every Supabase SDK call the Flutter app will make (table reads, RPC calls, storage operations)     |
| **UI States**                   | Every distinct screen/view state (empty, loading, loaded, error, permission-denied)                |
| **Validation Rules**            | Client-side and server-side validation rules with exact constraints                                |
| **AI Hooks**                    | What AI commands can target this module, command schema, required context                          |
| **Audit Requirements**          | Which operations are logged to audit_log, what data is captured                                    |
| **Edge Cases**                  | Numbered list of edge cases and how each is handled                                                |
| **Acceptance Criteria**         | Numbered list of testable criteria that prove the module works correctly                           |
| **Test Cases**                  | Specific test scenarios covering happy paths, edge cases, and error paths                          |
| **Implementation Constraints**  | Specific rules for implementation agents (what NOT to do, what NOT to change)                      |

## Development Workflow

Development is driven by the **spec-kit** utility and follows a strictly iterative, feature-by-feature process. Features are not batched -- each feature completes its full lifecycle before the next one begins.

### Per-Feature Cycle

```text
For each feature:
    │
    ├── 1. Define Spec ── write the specification document for this feature
    │
    ├── 2. Implement Backend ── schema migration, RPC functions, RLS policies
    │
    ├── 3. Test Backend ── validate with utilities/scripts that exercise the backend directly
    │
    ├── 4. Implement Frontend ── Flutter feature module, connected to backend
    │
    ├── 5. Test Frontend ── end-to-end validation of frontend communicating with backend
    │
    └── 6. Move to next feature
```

### Ordering Rules

1. **One feature at a time.** The spec for a feature is written immediately before its implementation, not in a bulk authoring phase.
2. **Backend first.** For every feature, the backend (schema, RPC functions, RLS policies) is implemented and tested before any frontend code is written. Backend testing uses utilities and scripts that directly call the Supabase API to verify correctness.
3. **Frontend second.** The Flutter feature module is implemented after the backend is confirmed working. Frontend is tested with the backend to ensure end-to-end correctness.
4. **AI service last.** AI capabilities are layered on only after a concrete, tested frontend and backend exist. See `docs/architecture/12-roadmap-phases.md` → `V2 -- AI Integration`.

### Implementation Inputs

Implementation agents receive:
- The specification document for their assigned feature.
- The required architecture docs and headings listed in that spec.
- Exact file paths and code structure expectations.
- Explicit constraints on what they must not modify.

Implementation agents must:
- Start with `docs/architecture/00-index.md` and route into only the minimum required docs.
- Follow the specification exactly.
- Not redesign architecture or alter schemas unless the spec is intentionally being revised.
- Not introduce new dependencies without approval.
- Not modify files outside their assigned module.
- Write tests for every acceptance criterion.
