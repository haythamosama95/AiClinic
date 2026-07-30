# Feature Specification: Worker skeleton and environments (A1)

**Feature Branch**: `ai/017-a1-worker-skeleton`

**Created**: 2026-07-30

**Status**: Draft

**Input**: Slice `A1` — *Worker skeleton and environments* (Delivery Plan §3.2, row A1).

> Constitution note: This slice provisions a new deployable component — the Cloudflare AI
> Gateway Worker — and its three associated stores. Per §14 acknowledgement of `17-ai-platform.md`,
> the gateway is an additive, non-primary component: it holds no domain logic, no business data,
> and has no write path into Supabase. It is always optional; if it vanishes, no business rule
> is lost. This slice stays inside that boundary.

## Slice Contract

### Implements

§13.4, §1.4 of `docs/architecture/17-ai-platform.md` (copied verbatim from the A1 `Canonical`
cell, Delivery Plan §3.2).

### Freezes

This slice establishes, for the first time:

- The Worker environment topology: three named environments (dev, staging, production), each with
  its own D1 database, R2 bucket, and Durable Object namespace, and its own secret bindings
  (§13.4 *Environments*).
- The health endpoint contract surface: a single endpoint that reports build identity and
  environment identity (Delivery Plan §3.2 A1 `Done when`; §3.11.1 A1).
- The required-binding contract: the bindings a Worker environment must have (D1, R2, DO, secrets)
  and the failure mode when one is absent (§13.4 *Environments*; §3.11.1 A1).

Later slices may extend these and may not rewrite them (Delivery Plan §2.3).

### Consumes

None. A1 has `Needs: —` (Delivery Plan §3.2). It is the first slice; it consumes no frozen
contract from any earlier slice. Changing any contract A1 freezes is, by definition, out of
scope for every later slice.

### Open decisions relied on

None. A1 does not depend on any of the fourteen §15 decisions. Environments, bindings, and the
health endpoint are fully specified by §13.4 and §1.4.

## Clarifications

### Session 2026-07-30

- Q: What concrete values does `health_returns_build_and_environment_identity` assert for build and environment identity (§13.4/§1.4 name neither)? → A: build = git commit SHA; env = wrangler environment name.
- Q: Does T4 (missing-required-binding startup failure) include the missing-secret branch at A1, where no secret is consumed yet? → A: No — T4 covers D1, R2, DO namespace only at A1; missing-secret coverage is deferred to the slice that first introduces a secret binding.

## User Scenarios & Testing

### User Story 1 — A1: Worker skeleton and environments (Priority: P1)

As the platform operator, I want a bare Cloudflare Worker skeleton deployed as three isolated
environments — development, staging, and production — each wired to its own D1, R2, and Durable
Object bindings and carrying its own secrets, so that every later slice can build against
bindings that are already separated and cannot accidentally share state with another
environment.

**Why this priority**: A1 sits at the head of Band A (Delivery Plan §3.2 *Band A — Foundations
and frozen contracts*). It has `Needs: —`: nothing precedes it. Every later slice that touches a
binding (A6 D1 schema, A7 config cache, B6 Quota DO, D1 lives in D1, etc.) presumes three
isolated environments already exist. Without A1 there is nothing to configure against and no
place to hang the binding-separation invariant that the rest of the guard leans on.

**Independent Test**: Provable by an automated test — three Worker environments deploy; the
health endpoint of each returns its build and environment identity; a test fails if any
infrastructure binding (D1, R2, DO namespace) is shared between any two environments; and a
missing required infrastructure binding fails the environment at startup rather than at first use
(Delivery Plan §3.2 A1 `Done when`, §3.11.1 A1). No user-facing behaviour is demonstrated (DP-3).

**Acceptance Scenarios**:

1. **Given** the three Worker environments (dev, staging, production) are configured, **When**
   each is deployed, **Then** all three deploy successfully, each provisioned with its own D1
   database, R2 bucket, and Durable Object namespace (§13.4 *Environments*; §3.11.1 A1 case 1).
2. **Given** a deployed Worker environment, **When** its health endpoint is called, **Then** it
   returns the build identity (the git commit SHA of the deployed build) and the environment
   identity (the wrangler environment name, e.g. `production`) (§3.11.1 A1 case 2; Delivery Plan
   §3.2 A1 `Done when`).
3. **Given** any two of the three environments, **When** their bindings are compared, **Then**
   no D1 database, R2 bucket, or Durable Object namespace is shared between them (§13.4
   *Environments* "No shared state"; §3.11.1 A1 case 3).
4. **Given** an environment definition missing a required infrastructure binding (D1, R2, or DO
   namespace), **When** that environment is started, **Then** it fails at startup rather than
   proceeding and failing on first use (§3.11.1 A1 case 4).

### Test plan

The minimum test set is the A1 row of Delivery Plan §3.11.1 (layer: *Infra / config*). Tests run
in CI and join the suite permanently (Delivery Plan §3.10).

| # | Named test | Layer | Asserts |
| --- | --- | --- | --- |
| T1 | `env_each_environment_deploys` | Infra / config | dev, staging, and production all deploy successfully, each with its own D1, R2, and DO namespace (§3.11.1 A1; §13.4 *Environments*) |
| T2 | `health_returns_build_and_environment_identity` | Infra / config | the health endpoint reports build identity (git commit SHA) and environment identity (wrangler environment name) (§3.11.1 A1) |
| T3 | `env_no_binding_shared_between_environments` | Infra / config | no binding (D1, R2, DO namespace) is shared by any two environments; the test fails if one is (Delivery Plan §3.2 A1 `Done when`; §3.11.1 A1) |
| T4 | `env_missing_required_binding_fails_at_startup` | Infra / config | a missing required binding (D1, R2, or DO namespace) fails the environment at startup rather than at first use (§3.11.1 A1) |

Coverage (Delivery Plan §3.10): the happy path of every requirement (T1, T2); the single failure
branch this slice can reach — a missing required binding failing at startup (T4); the one
binding boundary the architecture names — no binding shared between environments (T3). A1 emits
no §5.4 error codes; the error taxonomy is frozen in A2, not here.

### Edge Cases

- **Missing required binding**: an environment definition that omits D1, R2, or DO namespace
  must fail at startup. This is the only failure branch A1 can reach; it is the test in T4 and it
  is the sole "error code" surface of this slice (a startup-time deployment failure, not a §5.4
  platform error code — those arrive in A2). A missing-secret case is not asserted at A1: §13.4
  *Secrets* applies to provider keys and signing material that arrive in later slices (D8, B2),
  so missing-secret coverage is deferred to the slice that first introduces a secret binding.
- **Shared binding**: if any of D1 database, R2 bucket, or DO namespace is the same resource
  between two environments, the environment-separation invariant (§13.4 "No shared state") is
  violated. T3 fails on this. There is no remediation path inside A1; correcting it is an
  infrastructure configuration change.
- **Environment identity ambiguity**: the health endpoint must report the *environment*
  identity distinctly from the *build* identity, so two environments running the same build are
  still distinguishable. §13.4 *Environments* establishes separate Worker environments; the
  health endpoint is the observable surface for that separation (§3.11.1 A1).
- **Free-plan workload**: §1.4 states the Workers Free plan is not viable (10 ms CPU, 50
  subrequests) and the platform targets the Workers Paid plan. Provisioning against the Free plan
  is out of scope and treated as a mis-configuration, not a runtime branch A1 handles.
- **Secret exposure**: §13.4 *Secrets* holds provider keys and signing material in the platform
  secret store only — never in config files, never journaled, never logged. The health endpoint
  reports build and environment identity only and must not surface secret material.

## Requirements

### Functional Requirements

- **FR-001**: The platform MUST deploy as separate Worker environments — development, staging,
  and production — each with its own D1 database, R2 bucket, and Durable Object namespace.
  `(§13.4 Environments)`
- **FR-002**: The Worker environments MUST share no state and no installations; no binding may
  be a resource shared between two environments. `(§13.4 Environments)`
- **FR-003**: When a later slice introduces a provider key or signing material, it MUST live in
  the platform secret store only — never in config files, never journaled, never logged — and
  rotate without redeploy; the environment topology A1 freezes must not prevent per-environment
  secret isolation. A1 itself defines no secret and does not test missing-secret startup failure;
  that coverage belongs to the slice that first introduces a secret binding. `(§13.4 Secrets)`
- **FR-004**: The Worker platform MUST run under the Workers Paid subscription capability budget,
  which bundles Workers, D1, Durable Objects, the Rate Limiting binding, and Worker secrets, with
  R2 metered separately as the only non-bundled store; the Free plan is not viable for this
  workload. `(§1.4, §1.4.1)`
- **FR-005**: A health endpoint MUST report the build identity (the git commit SHA of the
  deployed build) and the environment identity (the wrangler environment name, e.g. `production`)
  of the Worker it is served from, so that the binding-separation invariant is observable per
  environment. `(§13.4 Environments; Delivery Plan §3.2 A1 Done when, §3.11.1 A1)`
- **FR-006**: A Worker environment missing a required infrastructure binding — D1, R2, or
  Durable Object namespace — MUST fail at startup rather than succeeding at startup and failing
  on first use. Missing-secret coverage is deferred to the slice that first introduces a secret
  binding. `(§13.4 Environments; Delivery Plan §3.11.1 A1)`

### Key Entities

Not applicable — this slice defines no D1 entities or contract types. The D1 logical model
(§7.3) is frozen in A6; this slice provisions only the environment topology and the bindings
those entities will later live behind.

## Constitution Alignment

### Architecture & Operations Impact

- **Clinic Fit**: This slice serves small-to-mid multi-branch clinics by keeping the AI
  platform on a single low-cost serverless subscription (the Workers Paid plan, §1.4.1),
  with a recurring R2 free allowance that does not expire, and no fixed capacity to operate.
  Enterprise-scale or hospital-scale needs are explicitly out of scope.

- **Layer Placement**: This slice touches only `ai-platform/` — the Cloudflare Worker skeleton,
  its `wrangler` environment definitions, its D1 / R2 / Durable Object namespace bindings, and
  its secret bindings (Delivery Plan §7.1 — the gateway lives in `ai-platform/` at the repo
  root as a sibling of `frontend/` and `backend/`). It touches neither `backend/` (Supabase)
  nor `frontend/` (Flutter). Per the §14 acknowledgement in `17-ai-platform.md`, the gateway
  is a new, additive, non-primary deployable component; its acceptable boundary is *no domain
  logic, no business data, no write path into Supabase, always optional*. A1 introduces only
  empty environments and bindings and carries no behaviour, so it stays squarely inside that
  boundary.

- **Data Integrity & Security**: §13.4 *Secrets* places provider keys and signing material in
  the platform secret store only — never in config files, never journaled, never logged (FR-003,
  FR edge case). Tenant isolation at this layer is enforced by environment separation: §13.4
  *Environments* requires no shared state and no shared installations, so a non-production or
  dev-clinic environment never touches production quota or journals (§13.4 *Development clinics*).
  This slice provisions no tables and writes no audit rows; auditability of the platform journal
  is established later in A6/C5.

- **Failure Handling**: The only failure A1 can reach is a missing required binding, and it must
  fail at startup rather than at first use (FR-006). Because the environment carries no behaviour
  yet, A1 has no request-path degradation to handle. Constitutional graceful degradation
  (V: Operational Continuity) is a property of later guard slices; A1's contribution is that
  mis-configuration is loud at deploy time, not silent at runtime.

## Out of Scope

Explicit exclusions (Delivery Plan §2.4, §6.4):

- **D1 logical model and migrations (A6)**: §13.4 *Migrations* — forward-only, additive D1
  migrations versioned in the repository — is its own slice (A6, Delivery Plan §3.2). A1
  provisions the D1 *binding* per environment; it creates no tables and writes no migration.
- **Config cache (A7)**: §13.4 *Configuration* — prompts, manifests, and schemas as deployed
  artifacts and volatile policy in D1 read through the config cache — is A7. A1 holds no
  configuration data and performs no cache reads.
- **Control-plane enrollment and installation lifecycle (B3)**: §13.4 *Development clinics* —
  enrolling non-production installations against non-production environments — is B3 (Delivery
  Plan §3.3). A1 provides the non-production *environments*; it does not enroll installations.
- **Diagnostic envelope, error taxonomy, request reference, trace propagation (A2)**: A1 emits
  no §5.4 error codes and defines no request reference. The startup/missing-binding failure in
  FR-006 is a deployment-time failure, not a runtime platform error.
- **The D1 region pin itself is stated in §13.4 (*D1 region*) and is exercised in A6/A7's
  cold-isolate read tests; A1 only ensures each environment has its own D1 binding.**

Prohibitions inherited from Delivery Plan §6.4 that A1 must not introduce:

- No mechanism from §9.14 added because it looks prudent (R-20).
- No prompt text, provider name, or model identifier in the Flutter client (R-12) — A1 touches
  no client code.
- No second Quota Durable Object round trip and no second R2 object per request (§7.5, §13.6).
- No guard rejection journaled as a request; no D1 row per stream chunk (§7.5).
- No per-request server-side state of any kind (§4.4, §9.7).
- No client-side assembly of a final result from chunks; no committable provisional content
  (§6.4, A5).

A1 carries no request path, so most of these are vacuous here — they are restated because the
coverage rule (Delivery Plan §3.10 item 4) requires every inherited prohibition to be acknowledged.

## Success Criteria

- **SC-001**: Three isolate-distinguished Worker environments (dev, staging, production) each
  deploy, each with its own D1, R2, and Durable Object binding, provable by `env_each_environment_deploys`.
- **SC-002**: The health endpoint of each environment returns a build identity and an environment
  identity distinct from the build identity, provable by `health_returns_build_and_environment_identity`.
- **SC-003**: No binding (D1 database, R2 bucket, or Durable Object namespace) is shared by any
  two of the three environments, provable — as a failing-on-violation test — by
  `env_no_binding_shared_between_environments`.
- **SC-004**: An environment missing a required infrastructure binding (D1, R2, or DO namespace)
  fails at startup and never reaches first use, provable by
  `env_missing_required_binding_fails_at_startup`.

## Assumptions

- The Cloudflare account used has the Workers Paid subscription enabled; §1.4 verifies limits for
  that plan and states the Free plan is not viable. Provisioning/account setup is outside the
  platform code and outside this slice.
- The three environment names are development, staging, and production, as named in the A1
  `Done when` cell (Delivery Plan §3.2). No fourth environment is implied.
- The `ai-platform/` directory is the gateway's home (Delivery Plan §7.1); the Worker skeleton,
  `wrangler` configuration, and binding definitions live there as a sibling of `frontend/` and
  `backend/`, not inside `backend/`.
- The constitution amendment registering the new deployable component (Delivery Plan §7, §14
  acknowledgement) is made before or as part of this slice, so A1 is not itself architectural
  drift.
- The health endpoint's *path* is not named by §13.4 or §1.4; the contract A1 freezes is that a
  health endpoint exists and reports build + environment identity. The path is an implementation
  detail chosen to be stable, not a value the architecture specifies. The *content* of those two
  identities — build = git commit SHA, env = wrangler environment name — is fixed by Clarifications
  (Session 2026-07-30); §13.4 names neither token.
- No §15 open decision is relied upon; if product input later requires more environments or a
  different region topology, that is an extension of A1's frozen contract, not a change inside it.