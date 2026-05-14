# Research: Project Scaffolding

## Decision 1: Scope V1-0 to clinic-local deployment only

- **Decision**: Implement V1-0 against the local clinic deployment model only, using the receptionist PC as the server node and exposing the Supabase gateway to other clinic devices on the LAN.
- **Rationale**: The active spec explicitly defers cloud mode, and the roadmap already lists local Supabase initialization and local environment documentation as V1-0 deliverables. This keeps the operational model simple and aligned with the constitution's local-first clinic fit.
- **Alternatives considered**: Supporting both local and cloud deployments in V1-0 was rejected because it expands scope too early and conflicts with the clarified spec. Cloud-only scaffolding was also rejected because it does not match the roadmap's local clinic-server requirements.

## Decision 2: Use a pre-auth startup experience instead of the full application shell

- **Decision**: Start the app in a safe unauthenticated entry experience that validates the local deployment profile, shows connection/system status, and redirects any protected route attempts back to that entry experience.
- **Rationale**: The spec clarification explicitly chose a pre-auth entry flow, and this preserves route-guard foundations without exposing unfinished protected workflows before `V1-1: Auth and RBAC`.
- **Alternatives considered**: Showing the full authenticated shell in V1-0 was rejected because it introduces misleading UX before auth exists. A setup-only screen with no reusable layout was rejected because the feature still needs shared UI foundations for later work.

## Decision 3: Standardize the Flutter foundation around the documented frontend architecture

- **Decision**: Build the initial runtime structure around `frontend/lib/app`, `frontend/lib/core`, `frontend/lib/shared`, and a future-ready `frontend/lib/features`, with shared theming, config, errors, widgets, and startup orchestration established in V1-0.
- **Rationale**: `docs/architecture/07-frontend.md` already defines the canonical feature-first clean architecture and identifies `SupabaseConfig`, shared widgets, and app/router/theme boundaries as first-class foundations. Reusing that shape now prevents restructuring in later features.
- **Alternatives considered**: A flatter ad hoc Flutter structure was rejected because it would create migration work once feature modules appear. Creating domain feature implementations during scaffolding was rejected because the roadmap and spec keep V1-0 foundation-only.

## Decision 4: Keep the backend model strictly Supabase-based with no custom service layer

- **Decision**: Treat Supabase as the only backend boundary in V1-0 and limit backend work to local stack configuration, connectivity readiness, and future-safe structure rather than domain schema or RPC logic.
- **Rationale**: The constitution and `docs/architecture/04-backend.md` both prohibit introducing a custom primary backend service. V1-0 has no operational write flows that justify domain RPC work yet.
- **Alternatives considered**: A custom coordinator service in front of Supabase was rejected because it violates the constitution. Inventing placeholder domain tables or RPC functions was rejected because no V1-0 acceptance criterion requires them.

## Decision 5: Use a minimal CI/CD skeleton centered on readiness, not release automation

- **Decision**: Limit the initial pipeline to lint/analyze, automated tests for startup/shared foundations, and Windows desktop build verification.
- **Rationale**: The roadmap defines the deliverable as a CI/CD skeleton containing `lint`, `test`, and `build`. This gives the project a reliable quality gate without prematurely adding installer packaging, signing, release promotion, or deployment orchestration.
- **Alternatives considered**: Full release automation was rejected because installer and deployment workflows are scheduled for later roadmap items. Deferring CI entirely was rejected because the spec explicitly requires baseline automated quality checks.

## Decision 6: Treat the missing shared deployment spec as a documented temporary assumption

- **Decision**: Use `docs/architecture/03-deployment-networking.md` and the active feature spec as the temporary source of truth for deployment and setup expectations until `specs/common/deployment-installer.spec.md` exists.
- **Rationale**: The roadmap references a shared deployment spec that is not present in the repository. Capturing that gap explicitly prevents hidden assumptions while allowing the plan to proceed.
- **Alternatives considered**: Blocking V1-0 planning until the shared deployment spec exists was rejected because it would stop roadmap progress. Inventing a full replacement deployment specification inside the plan was rejected because V1-8 still owns the richer installer/deployment scope.
