# Agent Context

This file orients AI coding agents working in this repository. Keep the
`<!-- SPECKIT START -->` / `<!-- SPECKIT END -->` block below updated with the
**current active feature's** plan reference when running Spec Kit phases.

<!-- SPECKIT START -->
Active feature plan: `specs/033-response-validator/plan.md`
Feature spec: `specs/033-response-validator/spec.md`
Branch: `ai/033-d6-response-validator`
<!-- SPECKIT END -->

## Repo layout quick reference

- `frontend/` — Flutter desktop app (presentation, orchestration).
- `backend/` — Supabase (auth, storage, RPCs) + PostgreSQL migrations/functions.
- `ai-platform/` — Cloudflare Worker AI gateway: source, D1 migrations, prompt artifacts, tests.
  Additive and non-primary; no domain logic, no business data, no write path into Supabase.
- `specs/` — Spec Kit feature working directories (`<NNN>-<short-name>/` with `spec.md`,
  `plan.md`, `research.md`, `data-model.md`, `quickstart.md`, `contracts/`, `tasks.md`).
- `.specify/` — Spec Kit configuration, templates, scripts, memory (`constitution.md`).

## Constitution

Authoritative governance at `.specify/memory/constitution.md`. Core invariants:
- Supabase/PostgreSQL owns domain integrity (constraints, triggers, RLS, RPCs).
- The system stays simple (no microservices/queues/Kubernetes) and clinic-scale
  (small-to-mid multi-branch clinics, modest hardware).

Before any architectural change, re-read the constitution and run the gate checks.
