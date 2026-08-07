# Feature Specification: Discovery HTTP route and production config-cache readers (I2)

**Feature Branch**: `ai/053-i2-discovery-http-config-readers`

**Created**: 2026-08-07

**Status**: Draft

**Input**: I2 — "Discovery HTTP route and production config-cache readers"

> Constitution note: Specs MUST explain clinic-fit scope, layer placement, data and
> security boundaries, and degraded behavior when AI or supporting services are
> unavailable. This slice lives entirely inside the Cloudflare AI Gateway Worker
> (`ai-platform/`), the additive, non-primary component acknowledged in §14 of
> `docs/architecture/ai-platform/01-ai-platform.md`: no domain logic, no business data,
> and no write path into Supabase.

## Slice Contract

### Implements

`§5.5, §4.3.4, §4.3.2, §13.4` (copied verbatim from the slice's `Canonical` cell in
§3.10 of `03-ai-platform-delivery-plan.md`).

### Freezes

This slice establishes for the first time:

- **The live capability-discovery HTTP wire**: `GET /v1/capabilities`, authenticated
  with Bearer AAT on `Authorization` (installation-scoped; same verifier as submit),
  with conditional revalidation via request `If-None-Match` against the prior response
  `ETag`, and response `Cache-Control: private, must-revalidate` (§5.5).
- **Production D1 config-cache readers for every request-path kind**: the production
  reader that populates the in-isolate config cache on a miss serves installations,
  keys, entitlements, grants (including the grant / lifecycle overlay data the
  resolver and discovery consult), kill switches, the active routing policy, and the
  global `token_contract` accepted-`ver` set, so a cold isolate still pays exactly one
  same-region D1 read pattern already frozen by A5 (§4.3.2, §13.4; Delivery Plan §3.10
  Done when).

### Consumes

Frozen by the slices in I2's `Needs` (`A5`, `C1`); changing any of these is out of scope
by definition:

- From **A5** — the config-cache contract: an in-isolate memory map with a short TTL,
  populated from D1 on a miss, owning nothing; the platform D1 logical model that holds
  the volatile policy entities; and the cold-isolate single same-region D1 read pattern
  (§4.3.2, §13.4; A5 `Freezes`). I2 wires production readers for the full kind set
  §4.3.2 now names; it does not change the cache mechanics A5 froze.
- From **C1** — `discover()` / `resolve()` as library exports, the discovery response
  shape (granted manifests whose effective lifecycle is `active` or `deprecated`),
  cacheable revalidation by version or etag at the library boundary, and the rule that
  entitlement-gated capabilities are absent for an ineligible installation (§4.3.4,
  §5.5; C1 `Freezes`). I2 exposes `discover()` over the §5.5 HTTP wire; it does not
  redefine the library contract.

### Open decisions relied on

None. This slice wires already-frozen discovery and config-cache contracts onto the live
Worker fetch path. It does not choose a first capability (Open Decision 1), a plan
catalogue (Open Decision 15), or token-contract rotation behaviour (J4).

## Clarifications

### Session 2026-08-07

- Q: Should I2 add the additive D1 `kill_switch` migration (and update `schema.snap.sql`) so the production reader can serve a present row, given §7.3 now names the entity but A5’s shipped schema has no table? → A: I2 adds `kill_switch` migration + schema snapshot update; `createD1ConfigReader` SELECTs it `[implementation choice — no §citation]`
- Q: How should `GET /v1/capabilities` authenticate the Bearer AAT and share config-cache state with `discover()` on the same request? → A: Shared cache/reader in a discovery handler; verify then `discover()` `[implementation choice — no §citation]`
- Q: How should the I2 Workers integration suite be organised on disk? → A: Two files: `test/discovery-http.test.ts` (T1–T5) and `test/config-readers.test.ts` (T6–T14) `[implementation choice — no §citation]`
- Q: How should T6–T12 (presence per kind) and T14 (miss typed failure) be constructed, given discovery HTTP does not consult every request-path kind (e.g. kill switches are not applied in discovery)? → A: Direct Miniflare D1 + `createD1ConfigReader`/`loadConfig` per kind `[implementation choice — no §citation]`
- Q: How should T13 assert A5’s cold-isolate single config-read pattern under Workers integration? → A: Spy/wrapper on `D1Reader.read` around `createD1ConfigReader` `[implementation choice — no §citation]`

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Discovery HTTP route and production config-cache readers (Priority: P1)

As an authenticated clinic installation (and as the guard / resolver on a warm or cold
isolate), I need capability discovery reachable over HTTP so I can fetch only the
manifests my installation is granted without supplying a capability id, revalidate with
etag when nothing changed, and have every config kind the guard and resolver consult
served by the production D1 config reader under A5's single cold-isolate read pattern —
including the global `token_contract` accepted-`ver` set.

**Why this priority**: I2 sits where it does because Band I closes the composition gap
left when C1 froze `discover()` as a library and A5 froze the config-cache contract
without production HTTP wiring — "I2 exposes C1's `discover()` over HTTP and ensures
the production config-cache D1 reader covers every entity kind" (`03-ai-platform-delivery-plan.md`
§3.10). Its `Needs` (A5, C1) are already frozen; live client invoke (I3) cannot proceed
until discovery is reachable over HTTP.

**Independent Test**: Capability discovery is reachable over HTTP for an authenticated
installation, returns only granted active manifests, supports etag/version
revalidation, and never requires a capability id from the client beyond the
installation's entitlements; the production D1 config reader serves every kind the
guard and resolver consult on the request path (installations, keys, entitlements,
grants / lifecycle overlay, kill switches, active routing policy, token contracts) so a
cold isolate still pays exactly one D1 read pattern already frozen by A5 (the slice's
`Done when` cell).

**Acceptance Scenarios**:

1. **Given** an enrolled installation with a valid AAT, **When** the client `GET`s
   `/v1/capabilities` with `Authorization: Bearer <AAT>` and no capability id, **Then**
   the response returns only the granted manifests whose effective lifecycle is
   `active` or `deprecated` for that installation/plan. *(Discovery HTTP — granted
   active manifests)*
2. **Given** a prior discovery response carrying an `ETag`, **When** the client
   revalidates with `If-None-Match` matching that `ETag`, **Then** the response is
   not-modified and still carries `Cache-Control: private, must-revalidate`. *(etag
   not-modified)*
3. **Given** a granted manifest that has changed since the last discovery response,
   **When** discovery is fetched again, **Then** the response `ETag` differs from the
   prior one. *(changed manifest changes etag)*
4. **Given** a capability that is entitlement-gated for the caller's plan tier,
   **When** an ineligible installation discovers capabilities, **Then** that capability
   is absent from the response. *(ungated capability absent for ineligible plan)*
5. **Given** a request with a missing or invalid AAT, **When** `GET /v1/capabilities`
   is issued, **Then** the response is the taxonomy `unauthenticated` error.
   *(unauthenticated → taxonomy unauthorized)*
6. **Given** the production D1 config reader and a present row for each request-path
   kind (installations, keys, entitlements, grants / lifecycle overlay, kill switches,
   active routing policy, token contracts), **When** the config cache loads on a miss,
   **Then** each kind is served through that production reader. *(Config readers — one
   presence case per kind)*
7. **Given** a cold isolate with an empty in-isolate config map, **When** the first
   guard or resolver consult triggers a config load, **Then** exactly one same-region
   D1 read pattern (the A5-frozen pattern) populates the cache. *(cold isolate single
   config read pattern)*
8. **Given** a miss for a required request-path config kind, **When** the production
   reader is consulted, **Then** the miss is a typed failure and is not treated as an
   empty grant set that silently admits. *(miss is typed failure, not silent admit)*

### Test plan

Layer: Workers integration (Delivery Plan §3.12.9 row I2). Named tests:

| ID | Name | Layer | Covers |
| --- | --- | --- | --- |
| T1 | `discovery_http_granted_active_manifests` | Workers integration | Enrolled installation with valid AAT receives only granted effective-`active`/`deprecated` manifests from `GET /v1/capabilities` with no capability id (§3.12.9 I2; §5.5; C1 `Freezes`) |
| T2 | `discovery_http_etag_not_modified` | Workers integration | Matching `If-None-Match` yields not-modified; response carries `Cache-Control: private, must-revalidate` (§3.12.9 I2; §5.5) |
| T3 | `discovery_http_changed_manifest_changes_etag` | Workers integration | Changed granted manifest changes response `ETag` (§3.12.9 I2; §5.5) |
| T4 | `discovery_http_ineligible_plan_capability_absent` | Workers integration | Entitlement-gated capability absent for ineligible plan (§3.12.9 I2; §4.3.4; §5.5; C1 `Freezes`) |
| T5 | `discovery_http_unauthenticated` | Workers integration | Missing/invalid AAT → taxonomy `unauthenticated` (§3.12.9 I2; §5.5; §4.3.2) |
| T6 | `config_reader_presence_installation` | Workers integration | Present installation row served through production D1 config reader (§3.12.9 I2; §4.3.2) |
| T7 | `config_reader_presence_keys` | Workers integration | Present installation keys served through production D1 config reader (§3.12.9 I2; §4.3.2) |
| T8 | `config_reader_presence_entitlements` | Workers integration | Present entitlement served through production D1 config reader (§3.12.9 I2; §4.3.2) |
| T9 | `config_reader_presence_grants_lifecycle_overlay` | Workers integration | Present grants / lifecycle overlay served through production D1 config reader (§3.12.9 I2; §4.3.2; Done when) |
| T10 | `config_reader_presence_kill_switches` | Workers integration | Present kill switches served through production D1 config reader (§3.12.9 I2; §4.3.2) |
| T11 | `config_reader_presence_active_routing_policy` | Workers integration | Present active routing policy served through production D1 config reader (§3.12.9 I2; §4.3.2) |
| T12 | `config_reader_presence_token_contract` | Workers integration | Present global `token_contract` accepted-`ver` set served through production D1 config reader (§3.12.9 I2; §4.3.2; §13.4) |
| T13 | `config_reader_cold_isolate_single_d1_read_pattern` | Workers integration | Cold isolate performs A5's single config read pattern (§3.12.9 I2; §4.3.2; A5 `Freezes`) |
| T14 | `config_reader_miss_typed_failure_not_silent_admit` | Workers integration | A miss is a typed failure, not an empty grant set that silently admits (§3.12.9 I2; Done when) |

### Edge Cases

- **Unauthenticated discovery.** Missing `Authorization`, non-Bearer scheme, or an AAT
  that fails the same verifier as submit → taxonomy `unauthenticated`; no discovery
  body (§5.5, §4.3.2).
- **No capability id on the wire.** `GET /v1/capabilities` never requires the client to
  name a capability id; the installation's entitlements and grants alone determine the
  returned set (Done when; §5.5).
- **Conditional revalidation match.** `If-None-Match` equal to the prior `ETag` →
  not-modified with `Cache-Control: private, must-revalidate` (§5.5).
- **Conditional revalidation mismatch.** A changed granted manifest set produces a
  different `ETag` and a full discovery body (§5.5).
- **Ineligible plan.** An entitlement-gated capability is absent from discovery for an
  ineligible installation — not returned as an error code on this surface (§4.3.4,
  §5.5; C1 `Freezes`).
- **Config kind miss fails closed.** A production-reader miss for a request-path kind is
  a typed failure; it must not surface as an empty grant set that silently admits
  (Done when; §4.3.2).
- **Cold versus warm isolate.** A cold isolate pays exactly one D1 read pattern on
  config miss; a warm isolate answers from the in-isolate map (§4.3.2; A5 `Freezes`).
- **Inherited prohibitions.** Discovery and config reads introduce no per-request
  server-side state, no second Quota DO round trip, no second R2 object, and no journal
  row for auth failure on this surface (Delivery Plan §6.4).

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The Worker MUST expose capability discovery as `GET /v1/capabilities`
  (§5.5).
- **FR-002**: Discovery MUST authenticate with Bearer AAT on the `Authorization`
  header, installation-scoped, using the same verifier as submit (§5.5, §4.3.2).
- **FR-003**: Discovery MUST support conditional revalidation: the client MAY send
  `If-None-Match` against the prior response `ETag`, and every discovery response MUST
  carry `Cache-Control: private, must-revalidate` (§5.5).
- **FR-004**: Discovery MUST return only the granted manifests whose effective
  lifecycle is `active` or `deprecated` for the authenticated installation/plan, and
  MUST NOT require a capability id from the client beyond that installation's
  entitlements (§5.5, §4.3.4; Done when; C1 `Freezes`).
- **FR-005**: An unauthenticated discovery request MUST fail with taxonomy
  `unauthenticated` (§5.5, §4.3.2).
- **FR-006**: The live discovery HTTP route MUST invoke C1's `discover()` library
  contract rather than re-implementing registry filtering (§4.3.4, §5.5; C1 `Freezes`).
- **FR-007**: The production D1 config reader MUST serve every kind the guard and
  resolver consult on the request path: installations, keys, entitlements, grants /
  lifecycle overlay, kill switches, the active routing policy, and the global
  `token_contract` accepted-`ver` set (§4.3.2, §13.4; Done when).
- **FR-008**: On a cold isolate, populating the config cache MUST still pay exactly one
  same-region D1 read pattern already frozen by A5; the cache remains an in-isolate
  memory map with short TTL that owns nothing (§4.3.2, §13.4; A5 `Freezes`).
- **FR-009**: A production-reader miss for a required request-path kind MUST be a typed
  failure and MUST NOT be interpreted as an empty grant set that silently admits
  (Done when; §4.3.2).
- **FR-010**: Only genuinely volatile policy (kill switches, capability grants, routing
  policy version, token-contract accepted-`ver` set) is data in D1 read through the
  config cache; prompts, manifests, and schemas remain deployed artifacts (§13.4).

### Key Entities

Not applicable — this slice defines no new D1 entities or contract types. The D1
logical model and config-cache mechanics were frozen by A5; the `discover()` response
shape was frozen by C1. I2 wires production readers and the live HTTP surface over
those contracts. The request-path kinds the production reader must serve are named
under **Freezes**.

## Constitution Alignment *(mandatory)*

### Architecture & Operations Impact

- **Clinic Fit**: This slice is part of the additive AI gateway and serves clinic-scale
  installations; the entire config set remains a few kilobytes so a warm isolate answers
  from memory and a cold one pays one same-region D1 read — no distributed cache and no
  enterprise-scale machinery (constitution principle I; §4.3.2).
- **Layer Placement**: This slice touches **`ai-platform/`** (Cloudflare Worker) only —
  the live discovery HTTP surface (§5.5) and production config-cache D1 readers
  (§4.3.2, §13.4), composing C1's capability-resolver library (§4.3.4). It writes
  nothing to `backend/` (Supabase) or `frontend/` (Flutter). Per the §14
  acknowledgement, the gateway is a non-primary, additive component: no domain logic,
  no business data, no write path into Supabase (§14; Delivery Plan §7.1).
- **Data Integrity & Security**: Discovery is scoped by the authenticated installation's
  entitlements and grants; AAT verification uses the same verifier as submit (§5.5,
  §4.3.2). Volatile policy (including the `token_contract` accepted-`ver` set) is read
  from D1 through the config cache; secrets remain in the platform secret store only
  (§13.4).
- **Failure Handling**: Unauthenticated discovery fails closed with `unauthenticated`.
  A config-kind miss is a typed failure that does not silently admit. Gateway
  unavailability never blocks clinical work — AI remains additive (constitution
  principle V; §14).

## Out of Scope

Neighbouring slices this one touches but does not finish:

- **A5** — D1 schema, context-key vocabulary, and config-cache mechanics. Consumed; I2
  does not redefine the schema or the single-read pattern.
- **C1** — `resolve()` / `discover()` library contracts and discovery response shape.
  Consumed; I2 exposes `discover()` over HTTP only.
- **I1** — live `POST /v1/requests` orchestrator. Sibling Band I slice; out of scope.
- **I3** — Flutter live invoke composing discovery results. Blocked on I2; not this
  slice.
- **I4** — entitle-and-grant operator path and live `context_required` self-heal.
- **B3** — identity / entitlement / kill-switch guard stages that *consult* the cache;
  I2 supplies production readers, not the guard stages themselves.
- **J4** — token-contract rotation control-plane mutations; I2 only reads the accepted
  set through the config cache.

Prohibitions (delivery plan §6.4), none of which this slice introduces:

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

- **SC-001**: An authenticated enrolled installation can `GET /v1/capabilities` and
  receive only its granted effective-`active`/`deprecated` manifests without supplying
  a capability id (Done when; §5.5).
- **SC-002**: Matching `If-None-Match` revalidation returns not-modified; a changed
  granted manifest set changes the `ETag`; responses carry
  `Cache-Control: private, must-revalidate` (Done when; §5.5).
- **SC-003**: Unauthenticated discovery returns taxonomy `unauthenticated` and no
  manifest body (Done when; §3.12.9 I2).
- **SC-004**: Automated Workers integration tests prove one presence case per
  request-path config kind through the production D1 reader, including
  `token_contract` (Done when; §4.3.2; §13.4).
- **SC-005**: A cold-isolate config load performs exactly one D1 read pattern as frozen
  by A5; a miss is a typed failure, never a silent empty grant admit (Done when;
  §4.3.2).

## Assumptions

- A5's config-cache mechanics and D1 logical model are available to compose; I2 adds
  production readers for the full §4.3.2 kind set (including `token_contract` as named
  by the architecture amendment) without altering A5's single-read pattern.
- C1's `discover()` library and response shape are available; I2 mounts that library on
  `GET /v1/capabilities` and does not change filtering rules.
- The AAT verifier used by submit (§4.3.2) is the verifier discovery reuses; I2 does not
  introduce a second auth path.
- Architecture amendments to §5.5 (discovery wire) and to §4.3.2 / §13.4
  (`token_contract` in the config-cache set) are prerequisites for this slice and are
  present on this branch.
- FEATURE_NUM `053` was chosen because Spec Kit dry-run against `docs/specs/` returned
  colliding `020`; `053` is the next free prefix under `specs/` and is unique for
  `ai-platform-paths.sh`.
