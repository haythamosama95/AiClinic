# Implementation Plan: Project Scaffolding

**Branch**: `001-project-scaffolding` | **Date**: 2026-05-13 | **Spec**: `specs/001-project-scaffolding/spec.md`

**Input**: Feature specification from `/specs/001-project-scaffolding/spec.md`

**Note**: This template is filled in by the `/speckit-plan` command. See `.specify/templates/plan-template.md` for the execution workflow.

## Summary

Deliver the V1-0 local-first foundation for AiClinic: initialize the Flutter desktop project layout, establish the clinic-local Supabase stack and deployment-profile handling, build a safe pre-auth startup experience with guarded routing and degraded-state messaging, add shared theme/widget/error foundations, and introduce a minimal CI/CD skeleton for lint, test, and build readiness. Cloud deployment, the authenticated app shell, installer wizard richness, AI features, and all clinic domain workflows remain out of scope.

## Technical Context

**Language/Version**: Dart with Flutter stable for the desktop client; SQL/PostgreSQL through the Supabase local stack; Markdown/YAML/JSON for setup docs, configuration, and CI

**Primary Dependencies**: Flutter desktop, Material 3 theming, GoRouter, Riverpod-based state management foundations, Supabase Flutter client, Supabase local services (PostgreSQL, GoTrue, PostgREST, Storage, Realtime, Kong), Docker, Supabase CLI or equivalent checked-in local stack wrapper

**Storage**: Supabase PostgreSQL for backend capabilities; per-device local settings file for the clinic-local deployment profile; local disk for setup docs and local backup expectations

**Testing**: Flutter static analysis, unit/widget/integration tests for startup and shared UI behavior, startup smoke checks against the local Supabase stack, and Windows desktop build verification

**Target Platform**: Windows desktop clients on a clinic LAN; receptionist PC hosts the local Supabase stack and exposes it to other clinic devices through the LAN gateway

**Project Type**: Desktop application foundation with a managed Supabase backend and no active AI workflow in this feature

**Performance Goals**: Reach the unauthenticated startup experience within 10 seconds in at least 95% of valid launches; block 100% of protected-route access without auth context; enable a new workstation to reach the startup experience within 60 minutes using documentation alone

**Constraints**: Desktop-first, local-first, clinic-local only in V1-0, no custom backend service, no domain workflows, no cloud dependency, graceful degraded startup, route guards before auth, modest clinic hardware assumptions, and AI must remain non-blocking

**Scale/Scope**: One startup flow, one local deployment mode, one local Supabase stack, shared Flutter foundations, setup documentation, and a minimal CI skeleton; no operational tables, no RPC domain logic, no RLS feature work, and no AI runtime integration

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

### Pre-Research Gate

- [x] Feature scope still fits small-to-mid-size multi-branch clinics; hospital-scale or enterprise-only requirements are explicitly rejected or separately ratified
- [x] Design keeps a simple operational model with no microservices, message queues, Kubernetes, or custom primary backend service
- [x] Layer ownership is explicit: Flutter handles UI/orchestration, Supabase handles backend capabilities, PostgreSQL owns domain integrity, and AI stays isolated
- [x] Protected writes, validation, permissions, and transactional rules remain enforced through PostgreSQL constraints, triggers, RLS, or RPC functions
- [x] Security remains authenticated, tenant-scoped, branch-scoped, permission-gated, auditable, and soft-delete-preserving
- [x] AI actions remain human-approved, have no direct database/backend access, and the feature still works in a degraded manual mode when AI is unavailable

### Post-Design Re-Check

- [x] Research keeps V1-0 local-only, desktop-first, and clinic-simple rather than expanding into cloud or enterprise deployment concerns
- [x] Planned structure keeps Flutter, Supabase, PostgreSQL, and future AI boundaries replaceable without adding a custom backend service
- [x] Startup contracts, route guards, and degraded states block unsafe protected use until later authenticated context exists
- [x] No Phase 1 artifact introduces direct AI writes, bypasses backend authority, or weakens audit/security expectations

## Project Structure

### Documentation (this feature)

```text
specs/001-project-scaffolding/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   ├── deployment-profile.md
│   └── startup-experience.md
└── tasks.md
```

### Source Code (repository root)

```text
frontend/
├── pubspec.yaml
├── analysis_options.yaml
├── lib/
│   ├── main.dart
│   ├── app/
│   │   ├── app.dart
│   │   ├── router.dart
│   │   └── theme/
│   ├── core/
│   │   ├── config/
│   │   ├── constants/
│   │   ├── errors/
│   │   ├── utils/
│   │   └── widgets/
│   ├── shared/
│   │   ├── providers/
│   │   └── services/
│   └── features/
├── test/
│   ├── integration/
│   ├── unit/
│   └── widget/
└── windows/

backend/
├── local/
└── tests/

docs/
└── setup/

.github/
└── workflows/
```

**Structure Decision**: V1-0 introduces the first runtime source tree into a repository that currently only contains documentation and specs. The main implementation surface for this feature will live in `frontend/lib/app`, `frontend/lib/core`, and `frontend/lib/shared`; `frontend/lib/features` is created as a future-ready boundary but remains free of domain workflows in V1-0. Local Supabase stack configuration and connectivity smoke checks live under `backend/`, setup instructions live under `docs/setup/`, and the CI skeleton lives under `.github/workflows/`. No `ai/` directory is added in this feature because AI remains out of scope.

## Complexity Tracking

No constitution violations or justified complexity exceptions were identified for this plan.
