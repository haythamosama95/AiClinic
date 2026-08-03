# Feature Specification: Capability registry, resolver stage, and discovery endpoint (C1)

**Feature Branch**: `ai/025-c1-capability-resolver-discovery`

**Created**: 2026-08-01

**Status**: Draft

**Input**: C1 — "Capability registry, resolver stage, and discovery endpoint"

> Constitution note: Specs MUST explain clinic-fit scope, layer placement, data and
> security boundaries, and degraded behavior when AI or supporting services are
> unavailable.

## Slice Contract

### Implements

`§4.3.4, §5.1, §6.1 stage 5, §5.5, §5.2` (copied verbatim from the slice's `Canonical` cell
in §3.4 of `17b-ai-platform-delivery-plan.md`).

### Freezes

This slice establishes for the first time:

- **The capability-registry lookup contract**: a capability id plus a requested version
  resolves to exactly one immutable manifest honouring the client's pin
  (§4.3.4, §6.1 stage 5).
- **The resolver's four error conditions and their taxonomy codes**: unknown →
  `capability_unknown`, retired → `capability_retired`, plan-level allowance or
  grant-version failure → `forbidden_capability`, kill switch active →
  `capability_disabled` (§4.3.4, §6.1 stage 5, §5.4).
- **The discovery response shape**: discovery returns the granted manifests whose
  effective lifecycle is `active` or `deprecated` for an installation and plan,
  cacheable and revalidated by version or etag (§5.5, §5.2).
- **Immutability of the resolved manifest handed to later stages**: the manifest a
  caller receives cannot be mutated (§5.1).

### Consumes

Frozen by the slices in C1's `Needs` (`A4`, `B3`); changing any of these is out of scope
by definition:

- From **A4** — the capability manifest schema (all ten field groups), manifest
  immutability per version, the build failure on a malformed manifest or an in-place
  edit of a published version, and `interaction_mode` defaulting to `single_shot`
  (§5.1).
- From **B3** — the immutable request principal produced by the identity stage, and the
  config-cache surface that answers kill-switch scopes and entitlement from memory with
  no D1 read on a warm isolate (§4.3.4, §6.1 stage 5).
- From **A6** — the protocol adapter's parsing of the version-pin header and its
  normative mapping of taxonomy codes to HTTP statuses (§5.4). C1 emits the taxonomy
  codes; it does not re-implement the HTTP translation.

### Open decisions relied on

None. This slice is agnostic to which capability is built first (Open Decision 1) and to
plan-catalogue design (Open Decision 15): it resolves and serves whatever manifests the
registry declares, and filters discovery by the grants and plan tier that B3 already
evaluates. It enforces no deprecation overlap window — that behaviour is J1.

## Clarifications

### Session 2026-08-01

- Q: Should the capability-resolver stage and the discovery endpoint sit in one co-located module (`ai-platform/src/capability/`) or in two sibling modules (`src/capability-resolver/` + `src/discovery/`)? → A: One module `ai-platform/src/capability/` exporting `resolve()` and `discover()`, with one test file `test/capability.test.ts` `[implementation choice — no §citation]`

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Capability registry, resolver stage, and discovery endpoint (Priority: P1)

As the pipeline's stage-5 caller (and, separately, as the client's discovery fetch), I need
a capability id plus requested version to resolve to one immutable manifest honouring my
pin and my installation's plan-level allowances, and I need to fetch the granted
effective-active or effective-deprecated manifests for my installation and plan so the
client can know the context-key list before submitting. Unknown, retired, forbidden, and
killed capabilities must be rejected with distinct, actionable codes; entitlement-gated
capabilities must be absent from discovery for an ineligible installation.

**Why this priority**: C1 sits where it does because both Band D and Band E need a
resolved manifest, and nothing downstream can be built until the resolver exists — "C1 is
the unlock for parallel work in bands D and E" (`17b-ai-platform-delivery-plan.md` §3.4).
Its `Needs` (A4, B3) are already frozen.

**Independent Test**: A capability id plus requested version resolves to one immutable
manifest honouring the client's pin and plan-level allowances, distinguishing
  `capability_unknown`, `capability_retired`, `forbidden_capability`, and
  `capability_disabled`; the discovery endpoint returns the granted effective-active or
  effective-deprecated manifests for an installation and plan, cacheable and revalidated
  by version or etag (the slice's `Done when` cell).

**Acceptance Scenarios**:

1. **Given** a capability id and an exact requested version that exists and is `active`,
   **When** the resolver resolves it, **Then** exactly one immutable manifest for that
   version is returned, honouring the client's pin.
2. **Given** a capability id the registry does not know, **When** the resolver resolves
   it, **Then** it is rejected with `capability_unknown`.
3. **Given** a capability id whose version is in the `retired` lifecycle state,
   **When** the resolver resolves it, **Then** it is rejected with `capability_retired`.
4. **Given** a capability id whose kill-switch flag is active in the config cache,
   **When** the resolver resolves it, **Then** it is rejected with `capability_disabled`.
5. **Given** a capability id whose version is in the `deprecated` lifecycle state,
   **When** the resolver resolves it, **Then** it is not rejected and the manifest is
   served (deprecation is not a rejection).
6. **Given** a resolved manifest handed to a later stage, **When** that caller attempts to
   mutate it, **Then** the manifest remains immutable (§5.1).
7. **Given** an installation and plan with some capabilities granted and others not,
   **When** discovery is called, **Then** only granted manifests whose effective
   lifecycle is `active` or `deprecated` are returned (with successor identity when
   overlay/published provides it); effectively `retired` manifests are excluded.
8. **Given** a discovery response and a revalidating request whose version/etag matches,
   **When** discovery is re-called, **Then** it returns not-modified.
9. **Given** a manifest that has changed since the last discovery response,
   **When** discovery is re-called, **Then** the etag differs.
10. **Given** a capability that is entitlement-gated for the caller's plan tier,
    **When** discovery is called for an ineligible installation, **Then** that capability
    is absent from the response.

### Test plan

Layer names are from the testing-strategy table in §13.5. The slice's required layer is
"Unit + integration" (`17b-ai-platform-delivery-plan.md` §3.11.3); the closest §13.5
layers are **Pipeline tests** (stage ordering and guard rejection paths) and **Contract
tests** (manifest internal consistency and immutability).

| #   | Test                                                                                                       | §13.5 layer      |
| --- | ---------------------------------------------------------------------------------------------------------- | ---------------- |
| 1   | Resolver: exact version pin resolves to one immutable manifest                                             | Pipeline tests   |
| 2   | Resolver: unknown id → `capability_unknown`                                                                | Pipeline tests   |
| 3   | Resolver: retired → `capability_retired`                                                                   | Pipeline tests   |
| 4   | Resolver: killed → `capability_disabled`                                                                   | Pipeline tests   |
| 5   | Resolver: deprecated still serves                                                                          | Pipeline tests   |
| 6   | Resolver: the returned manifest cannot be mutated                                                          | Contract tests   |
| 7   | Discovery: only granted effective-active or effective-deprecated manifests returned                        | Pipeline tests   |
| 8   | Discovery: etag revalidation returns not-modified                                                          | Contract tests   |
| 9   | Discovery: a changed manifest changes the etag                                                             | Contract tests   |
| 10  | Discovery: an entitlement-gated capability is absent for an ineligible installation                        | Pipeline tests   |

### Edge Cases

- **Error codes this slice can emit** (§6.1 stage 5, §5.4): `capability_unknown` (404),
  `capability_retired` (404), `forbidden_capability` (403 — plan-level allowance or
  grant-version failure on resolve), `capability_disabled` (503). B3 still owns stage-3
  entitlement rejection with `forbidden_capability`; `resolve()` also fails closed with
  the same code for allowance/grant failures. For discovery an ineligible capability is
  filtered out of the response rather than emitted as an error.
- **Boundary: version pin.** Only an exact requested version resolves; the resolver
  honours the client's pin rather than picking a "compatible" version (§4.3.4).
- **Boundary: grant version mismatch on resolve.** When the grant's `capability_version`
  is a string and does not equal the pinned version, `resolve()` emits
  `forbidden_capability`.
- **Boundary: kill-switch scopes.** The kill-switch flag is read from the config cache
  established by B3/A5 with no D1 read on a warm isolate (§6.1 stage 5); a miss means
  inactive (`{ active: false }`). Kill switches are not applied to discovery (killed
  capabilities may still be advertised; etag does not change on kill-switch flip).
- **Boundary: deprecation vs retirement.** Effectively `deprecated` is served by
  `resolve()` and appears in discovery when granted (with successor identity when
  overlay/published provides it); effectively `retired` is rejected with
  `capability_retired` and excluded from discovery. A published-`deprecated` manifest
  appears in discovery when granted (effective lifecycle, not "overlay-only"). C1
  enforces no overlap window — that is J1.
- **Inherited prohibition: guard rejections are not journaled.** A request rejected at
  stage 5 produces no `ai_request` row (§7.5, §6.2); the resolver's rejections are guard
  rejections. Journaling is C3.
- **Inherited prohibition: per-request server-side state.** The resolver holds no
  per-request state (§4.4, §9.7); it is a pure resolve plus a stateless discovery read.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The capability resolver MUST resolve a capability id plus a requested
  version against the capability registry to one concrete, immutable manifest, honouring
  the client's version pin (§4.3.4).
- **FR-002**: The resolver MUST honour the installation's plan-level allowances in
  `resolve()` (not discovery-only), since a capability may be entitlement-gated; failure
  emits `forbidden_capability` (§4.3.4).
- **FR-003**: The resolver MUST reject an unknown capability (or unknown version) with
  `capability_unknown` (§4.3.4, §6.1 stage 5, §5.4).
- **FR-004**: The resolver MUST reject a retired capability with `capability_retired`
  (§4.3.4, §6.1 stage 5, §5.4).
- **FR-005**: The resolver MUST enforce kill switches (A8) at the resolver stage — the
  earliest point where a capability is identified and the last point before any real work
  happens — rejecting with `capability_disabled` (§4.3.4, §6.1 stage 5, §5.4).
- **FR-006**: The resolver MUST draw the manifest from bundled artifacts and the
  kill-switch/retired flags from the config cache (§6.1 stage 5).
- **FR-007**: The resolver MUST NOT reject an effectively `deprecated` lifecycle state; a
  deprecated version remains servable. Rejection codes are unknown, retired, forbidden
  (allowance/grant), and disabled — not deprecation (§4.3.4, §5.1).
- **FR-008**: A resolved manifest MUST be immutable per version, and the manifest handed
  to a later stage or to a discovery caller MUST NOT be mutable by that caller — including
  when `resolve()` / `discover()` return a derived frozen copy under lifecycle overlay
  (§5.1).
- **FR-009**: A manifest MUST be data, not code, and MUST never name a provider or a
  model; it names requirements (§5.1).
- **FR-010**: Stage 5 of the pipeline MUST decide which immutable manifest governs the
  request and whether it is killed, retired, or forbidden by allowance/grant, emitting
  `capability_unknown`, `capability_retired`, `forbidden_capability`, or
  `capability_disabled` (§6.1 stage 5). B3 still owns stage-3 entitlement rejection;
  `resolve()` also fails closed with `forbidden_capability` for allowance/grant failures.
- **FR-011**: The capability discovery surface MUST return the granted manifests whose
  effective lifecycle is `active` or `deprecated` for an installation and plan (§5.5).
- **FR-012**: Discovery MUST return only granted manifests with effective lifecycle in
  `{ active, deprecated }` (retired excluded), so an entitlement-gated capability is
  absent for an ineligible installation (§4.3.4, §5.5). Kill switches are not applied to
  discovery.
- **FR-013**: Discovery MUST be cacheable and revalidated by version or etag: a
  revalidating request whose version/etag matches returns not-modified, and a changed
  manifest changes the etag (§5.5, §5.2). Wire `ETag` is a quoted strong tag; matching
  follows weak comparison over `If-None-Match` lists (including `*` and bare raw hash).
- **FR-014**: Discovery MUST let the client know the context-key list before submitting
  — discovery drives the Context Resolver (§5.5, §5.2).

### Key Entities

Not applicable for D1 — this slice defines no D1 entities (the registry is bundled
artifacts; the D1 schema was frozen by A5). The contract types it freezes are listed
under **Freezes**: the registry-lookup result (capability id + version → immutable
manifest), the four resolver error conditions, and the discovery response shape.

## Constitution Alignment *(mandatory)*

### Architecture & Operations Impact

- **Clinic Fit**: This slice is part of the additive AI gateway and serves clinic-scale
  installations; it adds no enterprise-scale machinery (constitution principle I).
- **Layer Placement**: This slice touches **`ai-platform/`** (the Cloudflare Worker)
  only — the capability resolver component (§4.3.4) and the discovery HTTP surface (§5.5).
  It consumes contracts frozen by `ai-platform/` slices A4, A6, B3 and writes nothing to
  `backend/` (Supabase) or `frontend/` (Flutter). Per the §14 acknowledgement, the
  gateway is a non-primary, additive component: no domain logic, no business data, no
  write path into Supabase, always optional (§14, item 1).
- **Data Integrity & Security**: Discovery is scoped by the installation's plan-level
  allowances and grants (entitlement-gated), and the resolver's kill-switch flag is read
  from the B3/A5 config cache with no D1 read on a warm isolate. A request rejected at
  stage 5 is a guard rejection and produces no journal row (§7.5).
- **Failure Handling**: A killed capability degrades to `capability_disabled` (503, a
  temporary-unavailable state); a retired capability returns `capability_retired` so the
  client can prompt for an update; the gateway's unavailability never blocks clinical
  work, which continues without AI affordances (§14, principle V).

## Out of Scope

Neighbouring slices this one touches but does not finish:

- **A4** — capability manifest schema, loader, and build-time validation. Consumed, not
  modified.
- **A6** — protocol adapter. Parses the version-pin header and applies the normative
  HTTP-status mapping for the taxonomy codes this slice emits. C1 emits the codes; it does
  not re-implement HTTP translation.
- **B3** — guard stages (identity, rate limiting, entitlement, kill switches). C1
  consumes the immutable principal and the config-cache kill-switch/entitlement surface.
- **C2** — context validator and cost pre-flight (stages 6–7).
- **C3** — journal writer (stage 5 rejections produce no journal row; that is C3's
  invariant, consumed here).
- **D1** — prompt composer and prompt registry (consumes the manifest C1 resolves).
- **J1** — deprecation overlap window. C1 recognises effective `deprecated`, serves it on
  resolve, and may surface it in discovery with successor identity when overlay/published
  provides it; it enforces no overlap window (that remains J1).

Prohibitions (delivery plan §6.4), none of which this slice introduces:

- No mechanism from §9.14 added because it looks prudent (R-20).
- No prompt text, provider name, or model identifier in the Flutter client (R-12) — not
  applicable to this Worker slice, but inherited.
- No second Quota Durable Object round trip and no second R2 object per request (§7.5,
  §13.6) — C1 performs neither.
- No guard rejection journaled as a request; no D1 row per stream chunk (§7.5) — stage-5
  rejections produce no journal row.
- No per-request server-side state of any kind (§4.4, §9.7).
- No client-side assembly of a final result from chunks; no committable provisional
  content (§6.4, A5).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A capability id plus an exact requested version resolves to exactly one
  immutable manifest that honours the client's pin (asserted by test 1).
- **SC-002**: Unknown, retired, forbidden (allowance/grant), and killed capabilities each
  produce their distinct taxonomy code — `capability_unknown`, `capability_retired`,
  `forbidden_capability`, `capability_disabled` (asserted by tests 2–4 and the
  allowance/grant resolve path).
- **SC-003**: A deprecated version remains servable rather than rejected (asserted by test
  5).
- **SC-004**: The manifest handed to a later stage or discovery caller cannot be mutated
  by that caller (asserted by test 6).
- **SC-005**: Discovery returns only granted effective-active or effective-deprecated
  manifests, and an entitlement-gated capability is absent for an ineligible installation
  (asserted by tests 7 and 10).
- **SC-006**: Discovery is cacheable and revalidated by version or etag — a matching
  revalidation returns not-modified and a changed manifest changes the etag (asserted by
  tests 8 and 9).

## Assumptions

- A frozen, typed manifest schema from A4 and a populated capability registry (bundled
  manifests) are available at build time.
- The request principal and the config-cache kill-switch/entitlement/grant surface from B3
  are available to the resolver at stage 5; on a warm isolate these require no D1 read.
- The version-pin header is parsed by A6's protocol adapter and presented to the resolver;
  C1 consumes the parsed value.
- No deprecation overlap-window behaviour is required of this slice — that belongs to J1.
  C1 treats effective `deprecated` as "still serves" on resolve and may advertise it in
  discovery with successor identity when present.