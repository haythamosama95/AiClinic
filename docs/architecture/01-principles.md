# Principles

- Purpose: Capture the architectural assumptions and non-negotiable system design principles.
- Read this when: aligning new work with the overall product direction or checking whether a proposed change violates a core invariant.
- Canonical for: guiding principles, deployment assumptions, and system-level tradeoffs.
- Usually paired with: `docs/architecture/02-system-overview.md`, `docs/architecture/11-spec-driven-development.md`, and the relevant feature spec.
- Not covered here: detailed backend, frontend, database, AI, security, or roadmap instructions.

---

## Introduction

This document translates the Product Overview into a complete, implementation-oriented system architecture. It defines every system layer, module boundary, data flow, deployment topology, and development phase required to build the AI-first clinic operating system.

The architecture targets small-to-mid-size multi-branch clinic organizations. It prioritizes simplicity, modularity, low-cost local execution, and **LAN-connected operation** with graceful degradation when connectivity is lost — not full offline clinical workflows. Every layer is designed to be replaceable without cascading changes.

### Guiding Principles

- **Simplicity over sophistication**: no microservices, no message queues, no Kubernetes. A single Supabase instance (local or cloud) serves as the entire backend.
- **Online-required mutations**: daily clinic operations require LAN or cloud connectivity to Supabase. The client may cache reads and defer in-progress visit edits in memory, but there is no offline write queue in V1. Tier 2 sync is backup-only, not live replication.
- **Online-first clinical writes**: visit documentation and domain mutations require an active Supabase connection. Tier 1/2 run Supabase on the LAN so daily operations continue when WAN is down; there is no offline draft sync queue in V1.
- **Uniform backend**: Supabase runs identically in all deployment tiers (self-hosted Docker for local, Supabase Cloud for online). The Flutter app uses the same SDK and API surface everywhere.
- **AI is isolated (target, not yet built)**: the product design reserves a fully isolated AI service that would communicate only with the Flutter frontend, with zero backend awareness of AI. As of this writing no AI service exists in the codebase (no `ai/` folder, no Ollama integration, no chat UI) — see `docs/architecture/06-ai.md` and `docs/architecture/12-roadmap-phases.md` (`V2 -- AI Integration`). The `ai.access` permission key is seeded in `roles_permissions` as a reservation for this future capability.
- **Deterministic execution**: all writes go through validated, permission-checked backend paths (RPC functions). This principle already governs 100% of implemented writes today, independent of whether AI ever calls the same RPCs.
- **Modularity**: feature domains are isolated. Each can be specified, built, tested, and replaced independently.
- **Cost optimization**: the system runs on 8GB RAM with no GPU. Architecture decisions never assume enterprise hardware.

### Documented Assumptions

| ID  | Assumption                                                                                                                                                               | Rationale                                                                                |
| --- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ---------------------------------------------------------------------------------------- |
| A1  | Supabase is the universal backend in all deployment tiers -- self-hosted (Docker) for Tier 1/2, Supabase Cloud for Tier 3.                                               | Eliminates dual data-source implementations. Same SDK, same schema, same RLS everywhere. |
| A2  | Flutter uses the Supabase Dart SDK in all tiers. The only configuration difference is the Supabase URL and anon key.                                                     | Single codebase for all deployment modes.                                                |
| A3  | Business logic lives primarily in PostgreSQL functions (called via `supabase.rpc()`) and database constraints/triggers, with orchestration in the Flutter service layer. | PostgreSQL functions run identically in self-hosted and cloud Supabase.                  |
| A4  | AI runtime is Ollama or any compatible local inference server (not yet implemented; target for V2).                                                                      | Model-provider agnostic. Ollama supports CPU-only execution and multiple model formats.  |
| A5  | LAN device discovery uses static IP configuration, not mDNS or dynamic discovery.                                                                                        | Simplest and most reliable for clinic environments with non-technical staff.             |
| A6  | Tier 2 sync is backup-only (`pg_dump` to Supabase Cloud Storage), not real-time replication. Not yet implemented in code (no backup scheduler exists today).             | Keeps Tier 2 simple; real-time sync is a Tier 3 concern.                                 |
| A7  | Tier 3 uses Supabase Cloud as primary database. Local Supabase fallback for connectivity gaps is a future enhancement.                                                   | Avoids bidirectional sync complexity in V1.                                              |
| A8  | No mobile application in V1 or V2.                                                                                                                                       | Desktop-first per product definition. Mobile is a future platform.                       |
| A9  | WhatsApp workflow actions use a third-party API gateway (e.g., Twilio, WATI). Not yet implemented; see `08-automation.md`.                                               | Building a WhatsApp integration from scratch is out of scope.                            |
| A10 | Docker is required on the receptionist PC for Tier 1 and Tier 2 deployments.                                                                                             | Self-hosted Supabase runs as Docker containers.                                          |
| A11 | The system targets Windows as the primary desktop platform.                                                                                                              | Per product definition. Flutter compiles natively for Windows.                           |
| A12 | **Exactly one active organization exists per Supabase instance/database.** JWT claims resolution (`auth_internal.build_staff_claims`) selects the single oldest non-deleted `organizations` row rather than scoping by the caller; the `organization_id`/`branch_id` columns exist on every table for RLS convenience and possible future multi-tenancy, but the current auth layer does not support more than one organization safely in a shared cloud database. | Matches the Tier 1/2 "one clinic per Supabase instance" deployment model. Documented explicitly here because it is a real constraint on Tier 3 (see `docs/architecture/ARCHITECTURAL_FLAWS.md`). |
| A13 | The staff role set is fixed to four roles (`administrator`, `doctor`, `receptionist`, `lab_staff`). There is no `owner` role; the original owner/administrator distinction was collapsed during V1-1 hardening (`backend/tests/owner_role_migration.sql` documents the removal). The first bootstrap account is simply an `administrator` flagged `is_bootstrap_admin = true`. | Simplifies RBAC to what the product actually needed; avoids a redundant top role. |
| A14 | Clinical documentation saves (visit workspace) and all domain RPC writes require live connectivity to Supabase. There is no durable offline mutation queue or draft sync in V1. | Spec 014 online-only save semantics; LAN-tier Supabase keeps clinic ops running when WAN is down. |

---
