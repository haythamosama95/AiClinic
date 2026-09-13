<!--
Sync Impact Report
Version change: 1.0.0 -> 1.1.0
Modified principles:
- None
Added sections:
- Operating Constraints: Vendor-side control services (single vendor-operated
  AI Billing Orchestrator permitted for commercial provisioning; no clinic business data,
  no write path into clinic Supabase, no queue infrastructure)
Removed sections:
- None
Templates requiring updates:
- None (no template references vendor-side services)
Follow-up TODOs:
- None
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

The product MUST remain desktop-first on Windows and local-first where possible.
Mobile support, complex sync, and broad enterprise integrations are out of scope unless
they are explicitly re-ratified. This keeps deployment, support, and operator training
viable for clinics with limited IT capacity.

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

### III. Backend Authority and Data Integrity
Any rule that affects correctness, permissions, validation, or atomicity MUST live in
PostgreSQL constraints, triggers, RLS policies, or RPC functions.

The frontend MAY perform client-side validation and workflow orchestration for usability,
but it MUST NOT become the source of truth for domain rules.

All significant domain writes that require validation or transactional safety SHOULD
execute through PostgreSQL functions. When a write path does not use a function, the
design MUST explain how equivalent integrity and authorization guarantees are enforced.

The data model MUST preserve tenant isolation through the documented branch-based
multi-tenant design, and every operational table MUST follow the shared schema
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
Deployment and resilience decisions MUST support low-cost clinic hardware, LAN-based
operation, scheduled backups, and graceful degradation. Subscription enforcement MUST
never hard-lock the system or delete data; the worst allowed operational mode is
read-only access with existing data preserved. This preserves trust and continuity for
clinics with intermittent connectivity or limited hardware headroom.

## Operating Constraints

The canonical operating model is:
- Flutter desktop application
- Supabase backend
- PostgreSQL data layer

All deployment tiers MUST preserve the same application code, schema shape, and backend
logic. Tier differences may change hosting location and connectivity assumptions, but
MUST NOT introduce a second architecture.

The system SHOULD run within modest clinic hardware limits and RAM-conscious service choices.

**Vendor-side control services.** A single vendor-operated control service is permitted outside
the clinic deployment for commercial provisioning of platform features: the AI Billing Orchestrator
(`ai-billing-orchestrator/`, Cloudflare Worker + D1, outbox table + Cron Triggers — no queue infrastructure).
Such a service MUST remain vendor-side control plane only: it holds no clinic business data, has
no write path into any clinic's Supabase, and is never on the clinic's request path for domain
operations. Clinic-side authority stays in PostgreSQL (receipt-verified RPCs under deny-all
RLS); the AI platform stays additive and never learns about money. Adding any further
vendor-side service requires its own amendment. (Registered 2026-09-11 for the AI billing
orchestration architecture, `docs/architecture/ai-billing-orchestration/`.)

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

**Version**: 1.1.0 | **Ratified**: 2026-05-13 | **Last Amended**: 2026-09-11
