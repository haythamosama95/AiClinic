# Implementation Plan: [FEATURE]

**Branch**: `[###-feature-name]` | **Date**: [DATE] | **Spec**: [link]

**Input**: Feature specification from `/specs/[###-feature-name]/spec.md`

**Note**: This template is filled in by the `/speckit-plan` command. See `.specify/templates/plan-template.md` for the execution workflow.

## Summary

[Extract from feature spec: primary requirement + technical approach from research]

## Technical Context

<!--
  ACTION REQUIRED: Replace the content in this section with the technical details
  for the project. The structure here is presented in advisory capacity to guide
  the iteration process.
-->

**Language/Version**: [e.g., Dart/Flutter stable, PostgreSQL SQL, AI service runtime or
NEEDS CLARIFICATION]

**Primary Dependencies**: [e.g., Flutter desktop, Supabase, PostgreSQL, local AI runtime
or NEEDS CLARIFICATION]

**Storage**: [if applicable, e.g., Supabase PostgreSQL, local files/cache, or N/A]

**Testing**: [e.g., flutter test, integration tests, SQL/RPC validation, or NEEDS
CLARIFICATION]

**Target Platform**: [e.g., Windows desktop, clinic LAN, Supabase-hosted backend, local
AI service or NEEDS CLARIFICATION]

**Project Type**: [e.g., desktop application with managed backend and isolated AI service
or NEEDS CLARIFICATION]

**Performance Goals**: [domain-specific, e.g., 1000 req/s, 10k lines/sec, 60 fps or NEEDS CLARIFICATION]

**Constraints**: [domain-specific, e.g., desktop-first, branch-aware, graceful
degradation, modest clinic hardware, or NEEDS CLARIFICATION]

**Scale/Scope**: [domain-specific, e.g., 10k users, 1M LOC, 50 screens or NEEDS CLARIFICATION]

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- [ ] Feature scope still fits small-to-mid-size multi-branch clinics; hospital-scale or
      enterprise-only requirements are explicitly rejected or separately ratified
- [ ] Design keeps a simple operational model with no microservices, message queues,
      Kubernetes, or custom primary backend service
- [ ] Layer ownership is explicit: Flutter handles UI/orchestration, Supabase handles
      backend capabilities, PostgreSQL owns domain integrity, and AI stays isolated
- [ ] Protected writes, validation, permissions, and transactional rules remain enforced
      through PostgreSQL constraints, triggers, RLS, or RPC functions
- [ ] Security remains authenticated, tenant-scoped, branch-scoped, permission-gated,
      auditable, and soft-delete-preserving
- [ ] AI actions remain human-approved, have no direct database/backend access, and the
      feature still works in a degraded manual mode when AI is unavailable

## Project Structure

### Documentation (this feature)

```text
specs/[###-feature]/
├── plan.md              # This file (/speckit-plan command output)
├── research.md          # Phase 0 output (/speckit-plan command)
├── data-model.md        # Phase 1 output (/speckit-plan command)
├── quickstart.md        # Phase 1 output (/speckit-plan command)
├── contracts/           # Phase 1 output (/speckit-plan command)
└── tasks.md             # Phase 2 output (/speckit-tasks command - NOT created by /speckit-plan)
```

### Source Code (repository root)
<!--
  ACTION REQUIRED: Replace the placeholder tree below with the concrete layout
  for this feature. Delete unused options and expand the chosen structure with
  real paths (e.g., apps/admin, packages/something). The delivered plan must
  not include Option labels.
-->

```text
frontend/lib/
├── app/
├── features/
├── services/
└── widgets/

frontend/test/
├── integration/
├── unit/
└── widget/

backend/
├── migrations/
├── functions/
├── seed/
└── tests/

ai/
├── src/
└── tests/
```

**Structure Decision**: [Document the selected structure and reference the real
directories captured above; preserve replaceable Flutter, Supabase/PostgreSQL, and AI
boundaries]

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified**

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| [e.g., Custom backend service] | [current need] | [why Supabase/RPC/PostgreSQL is insufficient] |
| [e.g., AI direct write path] | [specific problem] | [why human-gated app-mediated flow is insufficient] |
