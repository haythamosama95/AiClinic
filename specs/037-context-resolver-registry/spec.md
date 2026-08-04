# Feature Specification: Context Resolver registry, first context RPC, and client contract test

**Feature Branch**: `ai/037-e3-context-resolver-registry`

**Created**: 2026-08-02

**Status**: Draft

**Input**: Slice `E3` — "Context Resolver registry, first context RPC, and client contract test" (delivery plan §3.6, band E).

> Constitution note: Specs MUST explain clinic-fit scope, layer placement, data and
> security boundaries, and degraded behavior when AI or supporting services are
> unavailable.

## Slice Contract

### Implements

Copied verbatim from the slice's `Canonical` cell (delivery plan §3.6, row E3):

> §4.1, §5.2, §4.2, §13.5

### Freezes

Contracts this slice establishes for the first time:

- The **Context Resolver** as the Flutter client component named in §4.1: a generic
  registry that maps each requested context key to the existing Supabase RPC/query that
  produces it, assembles a payload conforming to the declared shape, and caches
  short-lived results within a screen — and nothing else from the §4.1 client table
  (§4.1 Context Resolver row; delivery plan §3.6 Done when).
- The **generic key-list API** of that registry: it receives a list of keys and returns a
  payload; it never sees a capability id and never branches on one (§4.1; delivery plan
  §3.6 Done when; §3.11.5 E3).
- The **screen-scoped cache lifetime**: short-lived results are cached within a screen and
  discarded on dispose; caching is not longer-lived than that screen (§4.1 "cache
  short-lived results within a screen"; delivery plan §3.6 Done when; §3.11.5 E3).
- The **first context provider RPC** as an ordinary clinic-side read RPC under the
  caller's own permissions and RLS, returning the first key's declared shape, with no
  AI-specific knowledge and no AI-specific parameter (§4.2 Context provider RPCs;
  §5.2 Authorization; delivery plan §3.6 Done when; §3.11.5 E3).
- The **client contract test** as an architectural CI/suite component: the Flutter test
  suite fetches live manifests and fails if the Resolver cannot satisfy every declared
  key of every active capability (§13.5 Client contract tests; delivery plan §3.6 Done
  when; §3.11.5 E3).

Later slices may extend these and may not rewrite them (delivery plan §2.3).

### Consumes

Contracts frozen by the slices in `Needs` (E2, C1). Changing any is out of scope by
definition:

- **E2 — AI Client SDK** (§4.1 AI Client SDK; §5.5; §5.4): transport-only acquire AAT,
  submit, stream, cancel, and last-N request references. E3 adds the Context Resolver
  alongside that SDK; it does not reinterpret transport, idempotency, SSE consumption,
  or terminal-error retry rules, and it does not embed those concerns into the Resolver.
- **C1 — Capability registry, resolver stage, and discovery endpoint** (§4.3.4, §5.1,
  §5.5 discovery, §5.2 Discovery): discovery returns the active manifests for an
  installation and plan, cacheable and revalidated by version or etag. E3's client
  contract test fetches those live manifests and asserts Resolver coverage of every
  declared key; it does not redefine discovery, capability resolution, or manifest
  schema.
- **A5 via §5.2 / C1 — Context key vocabulary and first key shape** (§5.2; delivery plan
  §3.2 A5 Done when; §3.11.5 E3): the `domain.concept@vN` format, platform-published
  shapes, and the first key's published shape. E3's first context provider RPC returns
  that shape and the contract test resolves declared keys against it; E3 does not rename
  keys, change shapes, or publish a new key version.

### Open decisions relied on

None. E3 does not depend on any §15 decision. The Context Resolver registry, ordinary
context provider RPC under caller RLS, and client contract test against fetched manifests
are fully specified by §4.1, §5.2, §4.2, §13.5, and delivery plan §3.6 / §3.11.5.

## Clarifications

### Session 2026-08-02

- Q: How should the Context Resolver’s short-lived cache be owned so it is screen-scoped and discarded on dispose? → A: One Resolver instance per screen; cache is instance state; disposing the screen/host discards it `[implementation choice — no §citation]`
- Q: How should context key → resolver functions be registered in the generic registry? → A: Closed static map of context key → resolver function in one registration module `[implementation choice — no §citation]`
- Q: How should the client contract suite construct the E3-T10 case where a manifest requires a key the Resolver cannot satisfy? → A: Inject a synthetic/fixture manifest that declares an unregistered context key `[implementation choice — no §citation]`
- Q: Where should the Context Resolver module live relative to the E2 AI Client SDK in `frontend/`? → A: Sibling modules under the same AI client library folder as the E2 SDK `[implementation choice — no §citation]`

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Context Resolver registry, first context RPC, and client contract test (Priority: P1)

As the Flutter AI client and the clinic backend, I want a generic context-key → resolver
registry that assembles a payload from a key list without ever seeing a capability id, an
ordinary first-key read RPC that returns the declared shape under the caller's own RLS
with no AI knowledge, and a Flutter contract suite that fetches live manifests and fails
when any active capability declares a key the Resolver cannot satisfy — so that a new
capability needing an existing key ships with zero client changes (§4.1) and the Context
Contract stays a verified interface (§13.5).

**Why this priority**: E3 has `Needs: E2, C1` (delivery plan §3.6). The SDK (E2) and
discovery of active manifests (C1) must exist before the Resolver and the contract test
can assemble context or assert coverage. Band E places this after E2 and before E4 so the
first AI surface resolves context through the registry rather than per-feature glue, and
so key drift is caught before a user-visible feature ships (delivery plan §3.6 Useful to
know).

**Independent Test**: A generic context key → resolver registry assembles a payload from
a key list, never receives or branches on a capability id, and caches only within a
screen; an ordinary read RPC returns the first key's declared shape under the caller's
own RLS with no AI-specific knowledge; the Flutter test suite fetches live manifests and
fails if the Resolver cannot satisfy every declared key of every active capability
(delivery plan §3.6 Done when).

**Acceptance Scenarios**:

1. **Given** a registered list of context keys the Resolver can produce, **When** the
   Resolver is asked to resolve that key list, **Then** it returns an assembled payload
   conforming to each key's declared shape (§4.1; §5.2 Shape; delivery plan §3.11.5 E3
   Resolver case 1).
2. **Given** a key list that includes a key with no registered resolver, **When** the
   Resolver is asked to resolve that list, **Then** it surfaces a typed failure and does
   not assemble a partial payload as success (delivery plan §3.11.5 E3 Resolver case 2;
   §4.1 Must not: send unrequested data does not license inventing data for unknown
   keys).
3. **Given** the Context Resolver public API, **When** that API is inspected for
   capability-id parameters or capability-id branching, **Then** no capability id is
   accepted or branched on — only a key list in, payload or typed failure out (§4.1;
   delivery plan §3.6 Done when; §3.11.5 E3 Resolver case 3).
4. **Given** a screen-scoped Resolver cache holding short-lived results, **When** that
   screen is disposed, **Then** the cache is discarded and does not outlive the screen
   (§4.1; delivery plan §3.6 Done when; §3.11.5 E3 Resolver case 4).
5. **Given** an authenticated caller with in-scope RLS access, **When** the first context
   provider RPC is invoked, **Then** it returns the first key's declared shape as
   published under A5 / §5.2 (§4.2 Context provider RPCs; §5.2 Shape; delivery plan
   §3.11.5 E3 RPC cases 1 and 4).
6. **Given** an authenticated caller without access to out-of-scope rows, **When** the
   first context provider RPC would otherwise return those rows, **Then** RLS denies
   them — resolution stays under the caller's own permissions (§4.2; §5.2 Authorization;
   delivery plan §3.11.5 E3 RPC case 2).
7. **Given** the first context provider RPC's signature and body, **When** they are
   inspected for AI-specific parameters or AI platform knowledge (prompts, providers,
   quotas, AI request state), **Then** none are present — it is an ordinary read RPC
   (§4.2 Context provider RPCs and Boundary note; delivery plan §3.6 Done when;
   §3.11.5 E3 RPC case 3).
8. **Given** live active capability manifests fetched via discovery, **When** the Flutter
   client contract suite runs, **Then** every declared context key of every active
   capability is resolvable by the Context Resolver (§13.5 Client contract tests;
   §5.2 Discovery; delivery plan §3.6 Done when; §3.11.5 E3 Contract case 1).
9. **Given** a manifest (fixture or live) that requires a context key the Resolver cannot
   satisfy, **When** the Flutter client contract suite runs, **Then** the suite fails
   (§13.5; delivery plan §3.11.5 E3 Contract case 2).

### Test plan

The minimum test set is the E3 row of delivery plan §3.11.5 (layer: *Flutter unit + SQL /
RLS + contract*). Tests join CI permanently (delivery plan §3.10). Named tests:

| ID | Layer | Named test | Asserts |
| --- | --- | --- | --- |
| E3-T01 | Flutter unit | `resolver_key_list_assembles_payload` | A key list resolves to a payload conforming to declared shapes (§4.1; §5.2; §3.11.5 E3) |
| E3-T02 | Flutter unit | `resolver_unknown_key_typed_failure` | An unknown key surfaces a typed failure (§3.11.5 E3) |
| E3-T03 | Flutter unit | `resolver_api_exposes_no_capability_id` | The Resolver API exposes no capability id and does not branch on one (§4.1; §3.11.5 E3) |
| E3-T04 | Flutter unit | `resolver_cache_screen_scoped_discarded_on_dispose` | Cache is screen-scoped and discarded on dispose (§4.1; §3.11.5 E3) |
| E3-T05 | SQL / RLS | `context_rpc_returns_declared_shape` | RPC returns the first key's declared shape (§4.2; §5.2; §3.11.5 E3) |
| E3-T06 | SQL / RLS | `context_rpc_rls_denies_out_of_scope` | RLS denies out-of-scope rows (§4.2; §5.2 Authorization; §3.11.5 E3) |
| E3-T07 | SQL / RLS | `context_rpc_no_ai_specific_parameter` | RPC takes no AI-specific parameter (§4.2; §3.11.5 E3) |
| E3-T08 | SQL / RLS | `context_rpc_shape_matches_a5_published_key` | Returned shape matches the key shape published in A5 (§5.2; §3.11.5 E3) |
| E3-T09 | Contract | `contract_every_active_manifest_key_resolvable` | Every declared key of every active manifest is resolvable (§13.5; §3.11.5 E3) |
| E3-T10 | Contract | `contract_manifest_unknown_key_fails_suite` | A manifest requiring an unknown key fails the suite (§13.5; §3.11.5 E3) |

Coverage rule (delivery plan §3.10): happy path of every requirement; every error / failure
branch this slice can produce (typed failure for unknown key; RLS denial); every inherited
prohibition in Out of Scope; every named boundary (screen-scoped cache; no capability id;
ordinary RPC with no AI knowledge).

### Edge Cases

- **Unknown context key on the Resolver**: surfaces a typed failure; does not succeed with
  a partial or invented payload (delivery plan §3.11.5 E3; §4.1 Must not: send unrequested
  data).
- **Capability id supplied to or inferred by the Resolver**: not accepted; the API has no
  capability-id input and does not branch on capability id (§4.1; Done when).
- **Cache after screen dispose**: discarded; no cross-screen or process-lifetime cache of
  resolved context from this component (§4.1; §3.11.5 E3).
- **RLS out-of-scope rows on the first context RPC**: denied under the caller's own
  permissions; the RPC does not bypass RLS via a privileged path (§4.2 Must not / Notes;
  §5.2 Authorization; §4.1 Must not: bypass RLS by using a privileged path).
- **AI-specific parameter or AI knowledge on the context RPC**: absent; an RPC returning
  the first key's domain payload is not "an AI RPC" (§4.2 Context provider RPCs; Boundary
  note).
- **Active manifest declares a key the Resolver cannot produce**: client contract suite
  fails before release (§13.5; §3.11.5 E3).
- **This slice emits no §5.4 taxonomy codes**: failures are client typed-failure, SQL/RLS
  denial, or contract-suite failure — not platform diagnostic-envelope codes (§5.4 is
  consumed elsewhere; E3's Canonical set does not add taxonomy codes).

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The Flutter client MUST include a Context Resolver that maps each requested
  context key to the existing Supabase RPC/query that produces it and assembles a payload
  conforming to the declared shape (§4.1 Context Resolver Responsibility).
- **FR-002**: The Context Resolver MUST be a generic registry (context key → resolver
  function), not per-feature glue code (§4.1).
- **FR-003**: The Context Resolver MUST receive a list of keys and return a payload; it
  MUST NEVER see a capability id and MUST NEVER branch on one (§4.1; delivery plan §3.6
  Done when).
- **FR-004**: The Context Resolver MUST NOT decide which keys are needed, MUST NOT send
  unrequested data, and MUST NOT bypass RLS by using a privileged path (§4.1 Must not).
- **FR-005**: The Context Resolver MUST cache short-lived results only within a screen and
  MUST discard that cache on screen dispose (§4.1; delivery plan §3.6 Done when;
  §3.11.5 E3).
- **FR-006**: Context keys MUST follow the §5.2 naming rule and `domain.concept@vN`
  format; a key names what the data means to a clinician, never where it is stored
  (§5.2).
- **FR-007**: Each resolved key's payload MUST conform to that key's platform-published
  shape (field names, types, cardinality, units) — the only schema knowledge shared
  between client and platform for context (§5.2 Shape).
- **FR-008**: Context resolution MUST happen under the caller's own Supabase permissions
  and RLS (§5.2 Authorization; §4.2 Context provider RPCs).
- **FR-009**: The clinic backend MUST provide the first context provider as an ordinary
  read RPC that returns the first key's declared shape, preferring reuse of existing RPCs
  where applicable, with no AI-specific knowledge (§4.2 Context provider RPCs; delivery
  plan §3.6 Done when).
- **FR-010**: The first context provider RPC MUST take no AI-specific parameter and MUST
  NOT encode prompts, providers, quotas, or AI request state (§4.2 Boundary note;
  §3.11.5 E3).
- **FR-011**: The Flutter test suite MUST include a client contract test that fetches live
  manifests and fails if the Context Resolver cannot satisfy every declared key of every
  active capability (§13.5 Client contract tests; delivery plan §3.6 Done when).
- **FR-012**: A manifest requiring a context key the Resolver cannot produce MUST fail
  the client contract suite (§13.5; delivery plan §3.11.5 E3).
- **FR-013**: The Context Resolver, first context RPC, and client contract test MUST NOT
  embed prompt text, provider names, or model identifiers in the Flutter client (R-12;
  §4.1 acceptance test for the client layer; delivery plan §6.4).

### Key Entities

Not applicable — this slice defines no entities. It consumes context-key shapes published
under §5.2 (frozen by A5) and registers client-side resolvers against those keys.

## Constitution Alignment *(mandatory)*

### Architecture & Operations Impact

- **Clinic Fit**: Context is assembled on the desktop client from ordinary clinic read
  RPCs under existing branch-scoped RLS, without introducing microservices, queues, or a
  privileged AI path into Supabase. Small-to-mid multi-branch clinics keep one permission
  model for clinical data whether or not AI is enrolled (§4.2; §5.2 Authorization;
  constitution I, III, IV).
- **Layer Placement**: This slice touches `frontend/` (Context Resolver registry and
  Flutter client contract tests per §4.1 and §13.5) and `backend/` (first context provider
  read RPC per §4.2). It does **not** touch `ai-platform/` (Cloudflare Worker); no
  gateway component is added or changed here, so the §14 non-primary additive
  acknowledgement for the gateway is not in scope for this slice's own code.
- **Data Integrity & Security**: The context RPC is an ordinary read under the caller's
  session; RLS remains the hard isolation boundary; the Resolver MUST NOT use a
  privileged path (§4.1 Must not; §4.2; §5.2 Authorization; constitution III, IV). The
  clinic database gains no prompts, providers, quotas, or AI request state from this slice
  (§4.2 Boundary note).
- **Failure Handling**: An unknown key yields a typed Resolver failure; out-of-scope rows
  are RLS-denied; a manifest/key coverage gap fails the Flutter contract suite before
  release (§3.11.5 E3; §13.5). This slice does not define degraded AI UI (E4) or platform
  `context_required` self-healing (J2).

## Out of Scope

Neighbouring slices and deferred work this slice must not absorb:

- **E2** — AI Client SDK transport, AAT acquire/cache, SSE consumption, cancel, last-N
  references (already frozen; do not rewrite).
- **E4** — First AI feature surface, provisional/draft UX, accept/discard, degraded mode
  for non-enrolled or unreachable platform.
- **C2** — Platform context validator stage, `context_required` / `context_invalid`, cost
  pre-flight.
- **J2** — `context_required` self-healing round trip behaviour.
- **H3** — Conversational journaling and client chat surface (Resolver reuse for
  conversational keys is later).
- **F2** — AI acceptance recording RPC.
- **A5** — Context key vocabulary, D1 schema, config cache (consumed, not rewritten);
  publishing additional key versions.
- **B1 / §4.2.1** — Installation keystore, AAT issuer, Ed25519 signing mechanism.
- Additional context provider RPCs beyond the first key's ordinary read RPC.
- AI Feature Surfaces, Conversation store, or any §4.1 component other than the Context
  Resolver.

Prohibitions copied from delivery plan §6.4:

- No mechanism from §9.14 added because it looks prudent (R-20).
- No prompt text, provider name, or model identifier in the Flutter client (R-12).
- No second Quota Durable Object round trip and no second R2 object per request (§7.5,
  §13.6).
- No guard rejection journaled as a request; no D1 row per stream chunk (§7.5).
- No per-request server-side state of any kind (§4.4, §9.7).
- No client-side assembly of a final result from chunks; no committable provisional
  content (§6.4, A5).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Given a registered key list, the Context Resolver returns one assembled
  payload conforming to declared shapes, with automated Flutter unit proof (Done when;
  E3-T01).
- **SC-002**: The Resolver public API accepts no capability id and performs no
  capability-id branching, with automated proof (Done when; E3-T03).
- **SC-003**: Resolver cache lifetime is limited to a screen and is discarded on dispose,
  with automated proof (Done when; E3-T04).
- **SC-004**: The first context provider RPC returns the A5-published first key shape
  under caller RLS, takes no AI-specific parameter, and has automated SQL/RLS proof
  including out-of-scope denial (Done when; E3-T05–E3-T08).
- **SC-005**: The Flutter client contract suite fetches live manifests and fails when any
  active capability declares a key the Resolver cannot satisfy, with automated proof
  including an unknown-key failure case (Done when; E3-T09–E3-T10; §13.5).

## Assumptions

- E2 (AI Client SDK) and C1 (capability discovery) are complete and available on the
  integration line this slice branches from (`Needs: E2, C1`).
- A5 has already published the first context key's shape under §5.2; E3 returns and
  validates against that shape without renaming or reshaping it (delivery plan §3.2 A5;
  §7 dependency on clinic schema for the first key).
- Active capability manifests returned by C1 discovery are the live manifests the client
  contract test fetches (§5.2 Discovery; §13.5).
- Clinic staff operate the Flutter desktop client under existing branch-scoped auth; the
  context RPC reuses that session and RLS model (§4.2; §5.2 Authorization).
- No §15 open-decision default is required to specify this slice.
