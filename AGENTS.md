# Agent Context

This file orients AI coding agents working in this repository. Keep the
`<!-- SPECKIT START -->` / `<!-- SPECKIT END -->` block below updated with the
**current active feature's** plan reference when running Spec Kit phases.

<!-- SPECKIT START -->
Active feature plan: `specs/016-ai-generation-scheduling/plan.md`
Feature spec: `specs/016-ai-generation-scheduling/spec.md`
Branch: `ai/016-generation-scheduling`
<!-- SPECKIT END -->

## Repo layout quick reference

- `frontend/` — Flutter desktop app (presentation, orchestration).
- `backend/` — Supabase (auth, storage, RPCs) + PostgreSQL migrations/functions.
- `ai/` — **Isolated AI layer** (`gateway/` + `runners/`). No Supabase/DB credentials, no DB
  client imports, no service-role keys anywhere in this tree (enforced by
  `ai/gateway/scripts/isolation_scan.py`).
- `specs/` — Spec Kit feature working directories (`<NNN>-<short-name>/` with `spec.md`,
  `plan.md`, `research.md`, `data-model.md`, `quickstart.md`, `contracts/`, `tasks.md`).
- `.specify/` — Spec Kit configuration, templates, scripts, memory (`constitution.md`).

## Constitution

Authoritative governance at `.specify/memory/constitution.md`. Core invariants:
- AI is isolated (no DB creds, no direct writes, structured outputs only, human-gated).
- Supabase/PostgreSQL owns domain integrity (constraints, triggers, RLS, RPCs).
- The system stays simple (no microservices/queues/Kubernetes) and clinic-scale
  (small-to-mid multi-branch clinics, modest hardware).
- Standard clinic workflows MUST continue to work with the AI layer fully down.

Before any architectural change, re-read the constitution and run the gate checks.