<!--
Sync Impact Report
Version change: 1.0.0 -> 2.0.0 (MAJOR: deployment direction change)
Reason:
- Product-owner decision (2026-09-30): the backend is always one remotely hosted Supabase project,
  owned and operated by the vendor and shared by all clinics as tenants. Local-first, LAN,
  self-hosted, on-premises and per-clinic backends are dropped.
Modified principles:
- I. Product Fit and Simplicity: removed "local-first where possible"; stated the hosting model.
- II. Replaceable Layer Boundaries: allowed vendor-side services (AI Platform, billing) outside
  the primary backend, with no clinical data and no database credentials.
- III. Backend Authority and Data Integrity: tenant isolation now explicitly spans all clinics in
  one shared database.
- V. Operational Continuity: replaced clinic-hardware and LAN operation with vendor-hosted
  operation and connectivity-loss handling.
Modified sections:
- Operating Constraints: replaced deployment tiers with a single deployment model.
Removed sections:
- None
Migration and compatibility:
- The product is not launched, so no clinic deployments need migration. The local Docker stack
  remains for development only and is not a supported deployment.
Security, resilience and simplicity review:
- One shared database raises the cost of any vendor-service compromise. Principle II now forbids
  vendor-side services from holding database credentials. Resilience moves from clinic hardware to
  vendor hosting and backups. Removing the tier matrix simplifies operation.
Templates requiring updates:
- ✅ `.specify/templates/plan-template.md` (Target Platform and Constraints examples)
- ✅ `.specify/templates/spec-template.md` (no change needed)
- ✅ `.specify/templates/tasks-template.md` (no change needed)
Follow-up TODOs (documents still describing LAN, self-hosted or tiered deployment):
- ⚠ `docs/architecture/01-principles.md`
- ⚠ `docs/architecture/02-system-overview.md`
- ⚠ `docs/architecture/03-deployment-networking.md`
- ⚠ `docs/architecture/10-resilience-and-scale.md`
- ⚠ `docs/architecture/ai-platform/01-ai-platform.md`
- ⚠ `docs/architecture/ai-platform/02-ai-platform-overview.md`
- ⚠ `docs/setup/*.md` (server-node, client-workstation, troubleshooting, verification-checklist)
-->
# AiClinic Constitution

## Core Principles

### I. Product Fit and Simplicity
AiClinic MUST optimize for small-to-mid-size multi-branch clinics. Proposals that
primarily serve hospital-scale, enterprise-scale, or high-operator-complexity
environments MUST be rejected unless the constitution is amended first.

The system MUST prefer the simplest architecture that satisfies clinic workflows:
- no microservices
- no message queues
- no Kubernetes
- no enterprise-only infrastructure assumptions

The product MUST remain desktop-first on Windows. The backend is one remotely hosted
Supabase project, owned and operated by the vendor and shared by all clinics as tenants.
Clinics run no servers. Mobile support, offline operation, complex sync, and broad enterprise
integrations are out of scope unless they are explicitly re-ratified. This keeps deployment,
support, and operator training viable for clinics with limited IT capacity.

### II. Replaceable Layer Boundaries
AiClinic MUST preserve clear layer boundaries:
- Flutter desktop application owns presentation, user interaction, state, and
  orchestration
- Supabase owns backend capabilities such as auth, storage, realtime, RPC access, and
  authorization enforcement
- PostgreSQL owns schema, constraints, triggers, and transactional business rules

Each layer MUST communicate only through defined interfaces and remain replaceable
without forcing cascading redesign in other layers. There MUST NOT be a custom core
backend server added for primary business logic. This boundary discipline keeps the
system understandable and prevents architectural sprawl.

Vendor-side services, such as the AI Platform and AI billing, MAY run outside Supabase. They
MUST NOT own clinic domain rules, hold clinical data, or hold credentials that can read or
write the clinic database. They interact with the backend only through narrow, authenticated
interfaces.

### III. Backend Authority and Data Integrity
Any rule that affects correctness, permissions, validation, or atomicity MUST live in
PostgreSQL constraints, triggers, RLS policies, or RPC functions.

The frontend MAY perform client-side validation and workflow orchestration for usability,
but it MUST NOT become the source of truth for domain rules.

All significant domain writes that require validation or transactional safety SHOULD
execute through PostgreSQL functions. When a write path does not use a function, the
design MUST explain how equivalent integrity and authorization guarantees are enforced.

The data model MUST preserve tenant isolation through the documented organization- and
branch-based multi-tenant design. All clinics share one database, so isolation MUST hold
between clinics as well as between branches. Every operational table MUST follow the shared schema
conventions for IDs, timestamps, audit fields, and soft deletion. This keeps correctness
and isolation enforceable even when clients misbehave.

### IV. Secure and Human-Gated Operations
All access MUST be authenticated, tenant-scoped, branch-scoped, and permission-gated.

Security MUST use defense in depth:
- UI permission checks for usability
- RPC or function validation for domain enforcement
- RLS for hard data isolation

Hard deletes MUST NOT be used by application flows. Auditability MUST be preserved
through audit fields and audit logs for sensitive operations.

### V. Operational Continuity
Deployment and resilience decisions MUST support vendor-hosted operation, scheduled
backups with tested restores, and graceful degradation. Clinics need internet access to use
the app. The desktop app MUST handle connectivity loss clearly and without data loss or
corruption, and MUST run on low-cost clinic desktops. Subscription enforcement MUST
never hard-lock the system or delete data; the worst allowed operational mode is
read-only access with existing data preserved. This preserves trust and continuity for
clinics with unreliable connectivity or limited hardware headroom.

## Operating Constraints

The canonical operating model is:
- Flutter desktop application
- Supabase backend
- PostgreSQL data layer

There is one deployment model: a single vendor-owned, remotely hosted Supabase project
shared by all clinics. Self-hosted, on-premises, LAN, and per-clinic backends are not
supported. A local stack MAY exist for development only and MUST NOT shape production
architecture.

The desktop app SHOULD run within modest clinic hardware limits and make RAM-conscious choices.

Workflow automation, when implemented, MUST remain lightweight and understandable:
- simple trigger-action rules
- narrow scope
- execution logging
- no DAG engines
- no complex branching systems

## Change Guardrails

The following changes MUST NOT be adopted without a formal constitutional amendment:
- introducing a custom primary backend service
- bypassing RLS or RPC validation for protected operations
- replacing soft delete with hard delete in normal workflows
- introducing infrastructure that assumes enterprise scale or hardware
- coupling unrelated feature domains in ways that reduce replaceability

Architecture changes SHOULD preserve:
- desktop-first UX
- branch-aware operations
- auditability
- graceful recovery
- low-operator complexity for clinic staff

Any proposal that introduces higher operational burden MUST document why simpler
alternatives fail and how the new burden will be contained.

## Governance

This constitution governs architectural and operational decisions for AiClinic. When a
proposal conflicts with this document, the constitution takes precedence unless it is
formally amended.

Amendments MUST:
1. describe the reason for the change
2. identify impacted architecture documents, templates, and implementation guidance
3. explain migration or compatibility implications
4. be reviewed for security, resilience, and operational simplicity impact

Versioning policy:
- MAJOR: incompatible governance or architectural direction changes
- MINOR: new principle or materially expanded guidance
- PATCH: clarifications that do not change intent

Compliance review for any significant design or implementation proposal MUST verify:
- product scope still fits small-to-mid-size multi-branch clinics
- layer boundaries remain intact
- backend authority is preserved
- security and audit guarantees still hold
- failure modes still degrade safely

Constitution compliance MUST be checked in feature plans before research, re-checked
after design, and reflected in implementation tasks whenever security, data integrity,
or operational continuity are affected.

**Version**: 2.0.0 | **Ratified**: 2026-05-13 | **Last Amended**: 2026-09-30
