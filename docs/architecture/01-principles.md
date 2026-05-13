# Principles

- Purpose: Capture the architectural assumptions and non-negotiable system design principles.
- Read this when: aligning new work with the overall product direction or checking whether a proposed change violates a core invariant.
- Canonical for: guiding principles, deployment assumptions, and system-level tradeoffs.
- Usually paired with: `docs/architecture/02-system-overview.md`, `docs/architecture/11-spec-driven-development.md`, and the relevant feature spec.
- Not covered here: detailed backend, frontend, database, AI, security, or roadmap instructions.

---

## Introduction

This document translates the Product Overview into a complete, implementation-oriented system architecture. It defines every system layer, module boundary, data flow, deployment topology, and development phase required to build the AI-first clinic operating system.

The architecture targets small-to-mid-size multi-branch clinic organizations. It prioritizes simplicity, modularity, low-cost local execution, and offline-first operation, with room for future expansion. Every layer is designed to be replaceable without cascading changes.

### Guiding Principles

- **Simplicity over sophistication**: no microservices, no message queues, no Kubernetes. A single Supabase instance (local or cloud) serves as the entire backend.
- **Uniform backend**: Supabase runs identically in all deployment tiers (self-hosted Docker for local, Supabase Cloud for online). The Flutter app uses the same SDK and API surface everywhere.
- **AI is isolated**: the AI service is a separate process that communicates only with the Flutter frontend. The backend has zero awareness of AI.
- **Deterministic execution**: all writes go through validated, permission-checked backend paths. AI produces structured commands; humans approve; the backend executes.
- **Modularity**: feature domains are isolated. Each can be specified, built, tested, and replaced independently.
- **Cost optimization**: the system runs on 8GB RAM with no GPU. Architecture decisions never assume enterprise hardware.

### Documented Assumptions

| ID  | Assumption                                                                                                                                                               | Rationale                                                                                |
| --- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ---------------------------------------------------------------------------------------- |
| A1  | Supabase is the universal backend in all deployment tiers -- self-hosted (Docker) for Tier 1/2, Supabase Cloud for Tier 3.                                               | Eliminates dual data-source implementations. Same SDK, same schema, same RLS everywhere. |
| A2  | Flutter uses the Supabase Dart SDK in all tiers. The only configuration difference is the Supabase URL and anon key.                                                     | Single codebase for all deployment modes.                                                |
| A3  | Business logic lives primarily in PostgreSQL functions (called via `supabase.rpc()`) and database constraints/triggers, with orchestration in the Flutter service layer. | PostgreSQL functions run identically in self-hosted and cloud Supabase.                  |
| A4  | AI runtime is Ollama or any compatible local inference server.                                                                                                           | Model-provider agnostic. Ollama supports CPU-only execution and multiple model formats.  |
| A5  | LAN device discovery uses static IP configuration, not mDNS or dynamic discovery.                                                                                        | Simplest and most reliable for clinic environments with non-technical staff.             |
| A6  | Tier 2 sync is backup-only (`pg_dump` to Supabase Cloud Storage), not real-time replication.                                                                             | Keeps Tier 2 simple; real-time sync is a Tier 3 concern.                                 |
| A7  | Tier 3 uses Supabase Cloud as primary database. Local Supabase fallback for connectivity gaps is a future enhancement.                                                   | Avoids bidirectional sync complexity in V1.                                              |
| A8  | No mobile application in V1 or V2.                                                                                                                                       | Desktop-first per product definition. Mobile is a future platform.                       |
| A9  | WhatsApp workflow actions use a third-party API gateway (e.g., Twilio, WATI).                                                                                            | Building a WhatsApp integration from scratch is out of scope.                            |
| A10 | Docker is required on the receptionist PC for Tier 1 and Tier 2 deployments.                                                                                             | Self-hosted Supabase runs as Docker containers.                                          |
| A11 | The system targets Windows as the primary desktop platform.                                                                                                              | Per product definition. Flutter compiles natively for Windows.                           |

---
