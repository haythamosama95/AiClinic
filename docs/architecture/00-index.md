# Architecture Index

This directory replaces the legacy monolithic `docs/architecture_overview.md` with focused architecture references that can be loaded selectively during planning and implementation.

> **Last updated:** Reflects implementation through V1-3 (Patient Management). Includes divergences from original design (username auth, `auth_internal` schema pattern, patient schema changes).

## How To Use This Architecture Set

1. Start with this index to identify the smallest relevant architecture surface.
2. Load the feature spec from `specs/...`.
3. Load only the required architecture docs listed in the spec or in `docs/architecture/12-roadmap-phases.md`.
4. Avoid loading the whole architecture set unless the task is explicitly architectural.

## Architecture Documents

- `docs/architecture/01-principles.md`: core assumptions and system-wide design rules.
- `docs/architecture/02-system-overview.md`: top-level layers and critical request flows.
- `docs/architecture/03-deployment-networking.md`: deployment tiers, Docker, LAN topology, and installer-facing infrastructure.
- `docs/architecture/04-backend.md`: Supabase backend ownership and API access patterns.
- `docs/architecture/05-database.md`: tenancy model, schema conventions, core domains, RLS, and RPC patterns.
- `docs/architecture/06-ai.md`: AI service isolation, structured commands, and context strategy.
- `docs/architecture/07-frontend.md`: Flutter project structure, Riverpod state, UX principles, and navigation.
- `docs/architecture/08-automation.md`: future workflow automation architecture.
- `docs/architecture/09-security-rbac.md`: authentication, RBAC, audit, soft delete, and security principles.
- `docs/architecture/10-resilience-and-scale.md`: backups, subscription validation, failure handling, and scale boundaries.
- `docs/architecture/11-spec-driven-development.md`: how specs map to implementation work and how agents should load context.
- `docs/architecture/12-roadmap-phases.md`: phased delivery plan plus required architecture docs/specs per feature.
- `docs/architecture/13-glossary.md`: shared terminology.

## Common Routing Shortcuts

- Auth, staff, roles, and branch setup: `04-backend.md`, `05-database.md`, `07-frontend.md`, `09-security-rbac.md`, plus the relevant spec in `specs/common/`.
- Operational features like patients, appointments, visits, billing, and shifts: `04-backend.md`, `05-database.md`, `07-frontend.md`, `09-security-rbac.md`, plus the relevant spec in `specs/operations/`.
- AI features: `02-system-overview.md`, `06-ai.md`, `07-frontend.md`, optionally `04-backend.md` or `05-database.md`, plus the relevant spec in `specs/ai/`.
- Deployment and installer work: `03-deployment-networking.md`, `07-frontend.md`, `10-resilience-and-scale.md`, plus the relevant deployment spec.
- Analytics: `04-backend.md`, `05-database.md`, `06-ai.md`, `07-frontend.md`, `09-security-rbac.md`, `10-resilience-and-scale.md`, plus `specs/analytics/dashboards.spec.md`.

## Feature Routing Summary

For the authoritative per-phase routing matrix, use `docs/architecture/12-roadmap-phases.md`.
