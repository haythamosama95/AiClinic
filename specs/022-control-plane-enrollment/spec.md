# Feature Specification: Control-plane enrollment and installation lifecycle (B2)

**Feature Branch**: `ai/022-b2-control-plane-enrollment`

**Created**: 2026-07-31

**Status**: Draft

**Input**: Slice `B2` — "Control-plane enrollment and installation lifecycle" (delivery plan
§3.3, row B2). Not a prose feature description; it is a row of the delivery plan, so every
requirement below cites a section of `docs/architecture/17-ai-platform.md`.

> Constitution note: Specs MUST explain clinic-fit scope, layer placement, data and
> security boundaries, and degraded behavior when AI or supporting services are
> unavailable.

## Slice Contract

### Implements

Verbatim from the `Canonical` cell of slice B2 (delivery plan §3.3):

- `§4.5`
- `§8.1`

### Freezes

This slice establishes, for the first time:

- **The installation-lifecycle control-plane surface.** A small internal surface, separate from
  the client-facing API and separately authenticated by operator identity, not clinic identity, that
  performs the five installation-lifecycle actions: enroll, rotate keys, suspend, resume, delete
  (§4.5 table row "Installation lifecycle"; §8.1 enrollment sequence).
- **The control-audit rule for installation mutations.** Every control-plane mutation is journaled
  with the operator identity, as a `control_audit` row carrying that identity (§4.5 "Every
  control-plane mutation is journaled with the operator identity"; §8.1 "control_audit: enrolled by
  operator").
- **The enroll write set.** Enroll writes the `installation`, `installation_key`, and `entitlement`
  rows plus a `control_audit` row, in the platform D1 (§8.1 sequence "create installation +
  installation_key + entitlement"; "control_audit: enrolled by operator").

Later slices may extend these (e.g. add further control-plane functions, additional `control_audit`
reasons) and may not rewrite them (delivery plan §2.3).

### Consumes

- Slice **A5** freezes the platform D1 logical model with every §7.3 entity present after forward-only
  migration, including `installation`, `installation_key`, `entitlement`, and `control_audit`
  (A5 `Freezes`; delivery plan §3.2 row A5 "Done when"). B2 writes into those four entities; changing
  any of their shapes or names is out of scope by definition (delivery plan §2.3). B2's `Needs` cell
  lists only A5.
- B2 does not consume the contract surface of slice B1. The `Canonical` and `Needs` cells of B2 do
  not reference B1's keystore/issuer contracts (delivery plan §3.3 row B2 `Needs` = A5 only). Any
  coordination with the clinic-side keypair / `kid` rotations in B1 is named in §8.1 rather than in a
  frozen B1 contract, and is not redefined here.

### Open decisions relied on

- **Open Decision 7** — *Enrollment operational owner and process.* Recommended default: "Part of
  clinic onboarding, operator-driven (§8.1)". B2 assumes operator-driven enrollment — a client may not
  enroll itself — which is the recommended default and is also stated directly in §8.1 ("enrollment is
  operator-driven rather than self-service") (§15; §8.1).

## Clarifications

### Session 2026-07-31

- Q: What transport exposes the five lifecycle control-plane functions (enroll, rotate, suspend, resume, delete) on the Worker? → A: distinct HTTP routes under a `/control/` prefix (e.g. `/control/installations/{id}/{action}`) with operator-auth middleware, keeping the surface visibly separate from the client-facing API. `[implementation choice — no §citation]`
- Q: Where in `ai-platform/src/` does the control-plane lifecycle code live, and what is its export shape? → A: a new `ai-platform/src/control/` module mirroring A4's `src/manifest/` and A5's `src/context/` (sibling-per-concern), exporting the lifecycle handlers and an `OperatorAuth` port. `[implementation choice — no §citation]`
- Q: How do the integration tests observe lifecycle writes and non-operator rejections, given operator auth is external? → A: a real Miniflare D1 binding (A5 already established Miniflare D1) for the write assertions, plus a fake `OperatorAuth` port that returns a fixed operator principal or `null`; matches A5's "real binding, injected port" split and stays behavioural. `[implementation choice — no §citation]`
- Q: What signal does `duplicate_enrollment_deterministic` assert — response shape, row invariant, or both? → A: both — D1 row count is unchanged after the duplicate call and the response is a terminal non-2xx rejection, pinning the one-time invariant from both sides without inventing a response contract the architecture does not name. `[implementation choice — no §citation]`

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Control-plane enrollment and installation lifecycle (Priority: P1)

An operator enrols a clinic installation once and manages its lifecycle (suspend, resume, rotate
keys, delete). Each mutation is authenticated by operator identity and is journaled as a
`control_audit` row carrying that identity. Enroll additionally creates the installation's
`installation`, `installation_key`, and `entitlement` rows. This sits after A5 because it writes into
the D1 entities A5 froze, and it precedes the guard stages (B3) that must read installation and
entitlement state at request time.

**Why this priority**: B2 is sequenced after A5 (its only `Needs`) because the lifecycle mutations
write the `installation`, `installation_key`, and `entitlement` entities A5 froze; it precedes B3
because the guard's entitlement and kill-switch stages read the installation/entitlement state these
mutations produce (delivery plan §3.3 row B2 `Needs` = A5; §3.3 row B3 `Needs`).

**Independent Test**: Provably complete by an automated integration test against the platform D1 that
asserts each lifecycle action's row writes and the operator-identity audit row, with rejections for
non-operator credentials and deterministic handling of duplicate enrollment (delivery plan §2.2; DP-3).

**Acceptance Scenarios**:

1. **Given** operator credentials and an unenrolled organisation, **When** the operator calls control-plane
   enroll with org info, the clinic's public key, and plan, **Then** `installation`, `installation_key`,
   `entitlement`, and `control_audit` rows are created in D1, the control audit row records "enrolled by
   [operator identity]", and the operator receives an enrollment confirmation carrying the platform base
   URL (§8.1). The `entitlement` row is created `pending` with zeroed economics and the plan name
   recorded; it grants nothing until an Entitlement management mutation activates it (§8.1; §4.5).
2. **Given** an enrolled installation, **When** the operator suspends it, **Then** a `control_audit` row is
   written that carries the operator identity and asserts the suspend transition (delivery plan §3.11.2
   row B2).
3. **Given** a suspended installation, **When** the operator resumes it, **Then** a `control_audit` row is
   written that carries the operator identity and asserts the resume transition (delivery plan §3.11.2
   row B2).
4. **Given** an enrolled installation, **When** the operator rotates keys, **Then** a new `installation_key`
   row is added with a new `kid` and a `control_audit` row carrying the operator identity is written, and
   the previous key remains so the platform accepts both keys during the overlap (§8.1 "Rotation repeats
   these three steps and adds a `kid`; the platform accepts both keys during the overlap"; delivery plan
   §3.11.2 row B2).
5. **Given** an enrolled installation, **When** the operator deletes it, **Then** a `control_audit` row is
   written that carries the operator identity (delivery plan §3.11.2 row B2).
6. **Given** anything other than operator credentials, **When** any control-plane lifecycle mutation is
   attempted, **Then** the request is rejected (§4.5 "separately authenticated … operator identity, not
   clinic identity"; delivery plan §3.11.2 row B2).
7. **Given** an already-enrolled installation/organisation, **When** enroll is called again, **Then** no
   second installation is created and the duplicate is handled deterministically (§8.1 "One-time, per
   clinic installation"; delivery plan §3.11.2 row B2).

### Test plan

Every named test runs in CI on every change (§13.5). The layer designation is the one named in the
slice's row of delivery plan §3.11.2 ("Integration").

| Test name | Layer | Asserts |
| --- | --- | --- |
| `enroll_writes_all_four_tables` | Integration | Enroll writes `installation`, `installation_key`, `entitlement`, `control_audit` (§3.11.2 row B2; §8.1) |
| `enroll_entitlement_row_is_pending_and_empty` | Integration | The enrolled `entitlement` row has status `pending`, the payload's plan name, zero quota/budgets, an empty capability set, a zero soft threshold, and equal period bounds (§8.1; §7.3) |
| `lifecycle_suspend_audit` | Integration | Suspend writes a `control_audit` row carrying the operator identity (§3.11.2 row B2; §4.5) |
| `lifecycle_resume_audit` | Integration | Resume writes a `control_audit` row carrying the operator identity (§3.11.2 row B2; §4.5) |
| `lifecycle_rotate_audit` | Integration | Rotate writes a `control_audit` row carrying the operator identity and adds a new `kid` key row while the previous remains (§3.11.2 row B2; §8.1) |
| `lifecycle_delete_audit` | Integration | Delete writes a `control_audit` row carrying the operator identity (§3.11.2 row B2; §4.5) |
| `non_operator_credentials_rejected` | Integration | Requests without operator credentials are rejected on every lifecycle mutation (§3.11.2 row B2; §4.5) |
| `duplicate_enrollment_deterministic` | Integration | A second enroll for an existing installation/organisation produces no second installation and resolves deterministically (§3.11.2 row B2; §8.1) |

### Edge Cases

- **Non-operator credentials on any mutation** are rejected; the control plane is a separate surface
  authenticated by operator identity, not clinic identity (§4.5). The architecture names no
  request-path error code for the control plane; B2 does not emit a §5.4 code — rejection is the
  specified outcome (delivery plan §3.11.2 row B2 names only "rejected", no code).
- **Duplicate enrollment.** Enrollment is "One-time, per clinic installation" (§8.1); a repeated
  enroll for an already-enrolled installation/organisation must not create a second installation. The
  deterministic resolution is rejection without a duplicate row, because enrollment is one-time
  (§8.1).
- **Key rotation overlap.** Rotation adds a `kid` and the previous key must remain valid during the
  overlap so no clinic is offline for a rotation; the previous `installation_key` row is not removed
  (§8.1). Verification of both keys is the guard's concern (B3), not B2's.
- **Enroll input.** The enroll call carries operator credentials, org info, the clinic's public key,
  and plan (§8.1). The architecture specifies no format validation or rate limit for the control-plane
  surface beyond operator authentication, so none is added (R-20).

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The control plane MUST be a small internal surface separate from the client-facing API
  and separately authenticated by operator identity, not clinic identity (§4.5).
- **FR-002**: The control plane MUST provide the installation-lifecycle functions enroll, rotate keys,
  suspend, resume, and delete (§4.5 table row "Installation lifecycle").
- **FR-003**: Every control-plane mutation MUST be journaled as a `control_audit` row carrying the
  operator identity (§4.5 "Every control-plane mutation is journaled with the operator identity").
- **FR-004**: Enrollment MUST be one-time per clinic installation and operator-driven; a client MUST
  NOT be able to enroll itself, because an installation is a billing and trust boundary and
  self-enrollment would let anyone with a copy of the desktop app create a tenant (§8.1).
- **FR-005**: On enroll, the gateway MUST create the `installation`, `installation_key`, and
  `entitlement` rows in the platform D1 and write a `control_audit` row recording "enrolled by
  [operator identity]", returning the platform base URL to the operator (§8.1 sequence: "create
  installation + installation_key + entitlement"; "control_audit: enrolled by operator"; "enrollment
  confirmed + platform base URL").
- **FR-005a**: The `entitlement` row created on enroll MUST be written with status `pending`, the plan
  name from the enroll payload, a zero request quota, zero token and cost budgets, an empty
  allowed-capability set, a zero soft threshold, and period bounds both set to the enrollment instant.
  Every column is non-null and the row grants nothing; the economics are written by the later
  Entitlement management mutation, which moves the row to `active` (§8.1 "What enroll writes into the
  entitlement row"; §4.5 "The line between the first two rows"; §7.3 "Entitlement status").
- **FR-006**: The control-plane enroll call MUST be authenticated by operator credentials and carry
  org info, the clinic's public key, and plan (§8.1 sequence: "control-plane enroll (operator
  credentials, org info, public key, plan)").
- **FR-007**: Key rotation MUST add a `kid` as a new `installation_key` row without removing the
  previous one, so the platform accepts both keys during the overlap and no clinic is offline for a
  rotation, and the rotation MUST write a `control_audit` row carrying the operator identity (§8.1
  "Rotation repeats these three steps and adds a `kid`; the platform accepts both keys during the
  overlap"; §4.5).
- **FR-008**: Suspend, resume, and delete MUST each modify the installation's lifecycle state and write
  a `control_audit` row carrying the operator identity, because they are the installation-lifecycle
  functions and every control-plane mutation is journaled with the operator identity (§4.5 table row
  "Installation lifecycle"; §4.5 "Every control-plane mutation is journaled with the operator
  identity").
- **FR-009**: Any control-plane lifecycle mutation attempted without operator credentials MUST be
  rejected (§4.5; delivery plan §3.11.2 row B2).
- **FR-010**: A duplicate enroll for an already-enrolled installation/organisation MUST NOT create a
  second installation; enrollment is one-time per clinic installation and the duplicate is handled
  deterministically (§8.1; delivery plan §3.11.2 row B2).

### Key Entities *(include if feature involves data)*

Not applicable — this slice defines no entities. It writes into the `installation`,
`installation_key`, `entitlement`, and `control_audit` entities frozen by slice A5 (A5 `Freezes`;
§7.3). Their shapes and names are consumed unchanged.

## Constitution Alignment *(mandatory)*

### Architecture & Operations Impact

- **Clinic Fit**: The installation is the platform's tenant and billing boundary; lifecycle control
  is operator-driven and clinic-scale (tens of installations), so the lifecycle surface is a small
  internal API exercised rarely, not per request (§8.1 "installation is a billing and trust
  boundary"; §14). No enterprise-scale machinery is introduced.
- **Layer Placement**: This slice touches `ai-platform/` (the Cloudflare Worker control plane) only.
  The control-plane Worker writes the platform's own D1 (§8.1 sequence: the gateway creates the D1
  rows). It does not touch `backend/` (Supabase) for these writes — the clinic-side keypair generation
  and keystore belong to B1 — and it does not touch `frontend/` (Flutter). Per §14, the gateway is a
  non-primary, additive component: *"no domain logic, no business data, no write path into Supabase,
  always optional."* B2's writes are into the platform's own D1, never into the clinic database.
- **Data Integrity & Security**: Control-plane mutations are operator-authenticated (§4.5) and every
  mutation is journaled with the operator identity (§4.5). Tenant isolation is enforced by
  installation-scoped tokens and installation-scoped queries (§14, "III. Tenant isolation"). The D1
  entity shapes and forward-only migration discipline are owned by A5 and are not redefined here.
- **Failure Handling**: The control plane is an operator-invoked surface, not on the request hot path.
  Control-plane unavailability does not affect in-clinic workflows, because AI is strictly additive and
  the client hides affordances when the platform is unreachable (§14 "I. … AI is the one
  internet-dependent capability … additive"; A11). No retry, caching, or per-request state is
  introduced for these mutations (§4.4; §9.7).

## Out of Scope

- The other §4.5 control-plane functions — **entitlement management** (assign plan, set quota and
  budget, grant/revoke capabilities), **kill switches** (A8), **capability availability** (gate,
  deprecate, retire), **routing policy** (publish, canary, roll back), **support lookup** (A13), and
  **operational dashboards** — are out of scope and belong to later slices (B3, C1, F3, …). B2 only
  writes the initial `entitlement` row on enroll, in its `pending`, zero-economics form (§8.1);
  assigning quota, budget, capabilities, period bounds, or the soft threshold — and the transition to
  status `active` — is the Entitlement management function and is not implemented here (§4.5).
- The clinic-side Ed25519 keypair generation, the restricted Supabase keystore, and the AAT issuer RPC
  are slice B1. Token verification, the identity stage, replay rejection, and the guard stages belong
  to B3 and B4. The Quota Durable Object and admission stage belong to B4.
- Token contract rotation with overlapping acceptance (two `ver` values accepted) is slice J4 and is
  not pulled forward.
- The "platform accepts both keys during the overlap" verification behaviour is the guard's concern
  (B3); B2 only writes the new `kid` row and leaves the previous one in place.

Prohibitions inherited from delivery plan §6.4, copied verbatim:

- No mechanism from §9.14 added because it looks prudent (R-20).
- No prompt text, provider name, or model identifier in the Flutter client (R-12) — not applicable
  here, as B2 touches neither the client nor prompts, but the prohibition is inherited.
- No second Quota Durable Object round trip and no second R2 object per request (§7.5, §13.6).
- No guard rejection journaled as a request; no D1 row per stream chunk (§7.5).
- No per-request server-side state of any kind (§4.4, §9.7).
- No client-side assembly of a final result from chunks; no committable provisional content (§6.4, A5).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: An operator-authenticated enroll creates exactly one row each in `installation`,
  `installation_key`, `entitlement`, and `control_audit`, with the control audit row carrying the
  operator identity (delivery plan §3.3 row B2 "Done when"; §8.1).
- **SC-002**: Each lifecycle action — suspend, resume, rotate, delete — writes a `control_audit` row
  carrying the operator identity (delivery plan §3.3 row B2 "Done when"; §3.11.2 row B2).
- **SC-003**: Any control-plane lifecycle mutation attempted without operator credentials is rejected
  (delivery plan §3.11.2 row B2).
- **SC-004**: A duplicate enroll for an existing installation/organisation produces no second
  installation and resolves deterministically (delivery plan §3.11.2 row B2; §8.1 "one-time").

## Assumptions

- Operator identity is an established, out-of-band credential external to this slice; the architecture
  states "operator identity, not clinic identity" (§4.5) without specifying the operator auth scheme,
  so B2 consumes an existing operator-auth mechanism and defines none.
- The platform D1 with the `installation`, `installation_key`, `entitlement`, and `control_audit`
  entities is present and migrated by A5, so B2 writes into existing tables and does not run migrations
  of its own (A5 `Freezes`; §7.3).
- The clinic's public key and `kid` supplied on enroll/rotate arrive from the operator routine named in
  §8.1 (clinic-side keypair generation); B2 receives and stores them and does not generate keys.
- The control plane is operator-driven per Open Decision 7's recommended default and §8.1, so no
  self-service enrollment path is provided (§15 #7; §8.1).