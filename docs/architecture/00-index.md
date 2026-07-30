# Architecture Index

This directory replaces the legacy monolithic `docs/architecture_overview.md` with focused architecture references that can be loaded selectively during planning and implementation.

> **Last updated:** Reflects implementation through V1-7 backend (shifts), V1-6 billing backend, specs 013–014 visit encounter workspace, and setup/bootstrap refactor. Includes divergences from original design (username auth, `auth_internal` schema pattern, patient schema, branch `working_schedule`, `visit_clinical_notes` replacing `soap_notes`, four staff roles without `owner`, online-only clinical saves, org-scoped insurance).

## How To Use This Architecture Set

1. Start with this index to identify the smallest relevant architecture surface.
2. Load the feature spec from `specs/00N-feature-name/`.
3. Load only the required architecture docs listed in the spec or in `docs/architecture/12-roadmap-phases.md`.
4. Avoid loading the whole architecture set unless the task is explicitly architectural.

## Architecture Documents

- `docs/architecture/01-principles.md`: core assumptions and system-wide design rules.
- `docs/architecture/02-system-overview.md`: top-level layers and critical request flows.
- `docs/architecture/03-deployment-networking.md`: deployment tiers, Docker, LAN topology, and installer-facing infrastructure.
- `docs/architecture/04-backend.md`: Supabase backend ownership and API access patterns.
- `docs/architecture/05-database.md`: tenancy model, schema conventions, core domains, RLS, and RPC patterns.
- `docs/architecture/07-frontend.md`: Flutter project structure, Riverpod state, UX principles, and navigation.
- `docs/architecture/08-automation.md`: future workflow automation architecture (not implemented).
- `docs/architecture/09-security-rbac.md`: authentication, RBAC, audit, soft delete, and security principles.
- `docs/architecture/10-resilience-and-scale.md`: backups, subscription validation, failure handling, and scale boundaries.
- `docs/architecture/11-spec-driven-development.md`: how specs map to implementation work and how agents should load context.
- `docs/architecture/12-roadmap-phases.md`: phased delivery plan plus required architecture docs/specs per feature.
- `docs/architecture/13-glossary.md`: shared terminology.
- `docs/architecture/14-visits-encounter-workspace.md`: visit lifecycle, clinical documentation, encounter workspace UI.
- `docs/architecture/15-billing.md`: billing schema, invoice lifecycle, RPC inventory, frontend status.
- `docs/architecture/16-testing.md`: backend SQL tests, Flutter test layout, CI scope.
- `docs/architecture/17-ai-platform.md`: AI platform architecture — gateway boundaries, trust model, prompt ownership, provider routing, AI data model. Proposal; supersedes earlier AI statements in this doc set.
- `docs/architecture/17a-ai-platform-overview.md`: high-level AI platform overview — components, contracts, request flow. Read this first for orientation; `17-ai-platform.md` remains canonical.
- `docs/architecture/17b-ai-platform-delivery-plan.md`: AI platform build order — slice decomposition, acceptance criteria, review checkpoints, and spec-authoring rules. Read before opening a Spec Kit feature for AI platform work.
- `docs/architecture/ARCHITECTURAL_FLAWS.md`: known architectural risks, doc/code drift, and remediation priorities.

## Common Routing Shortcuts

- Auth, staff, roles, and branch setup: `04-backend.md`, `05-database.md`, `07-frontend.md`, `09-security-rbac.md`, plus `specs/002-auth-rbac/`, `specs/003-org-branch-management/`.
- Operational features:
  - Patients: `specs/004-patient-management/`
  - Appointments: `specs/005-appointment-management/`
  - Visits / encounter workspace: `14-visits-encounter-workspace.md`, `specs/013-visits/`, `specs/014-visit-encounter-workspace/`
  - Billing: `15-billing.md`, `specs/007-billing/`
  - Shifts: `specs/008-shift-management/`
- Deployment and installer work: `03-deployment-networking.md`, `07-frontend.md`, `10-resilience-and-scale.md`.
- Analytics: `04-backend.md`, `05-database.md`, `07-frontend.md`, `09-security-rbac.md`, `10-resilience-and-scale.md` (V3-1).

## Feature Routing Summary

For the authoritative per-phase routing matrix, use `docs/architecture/12-roadmap-phases.md`.
