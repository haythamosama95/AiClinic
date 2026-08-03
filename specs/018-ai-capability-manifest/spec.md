# Feature Specification: Capability manifest schema and loader

**Feature Branch**: `ai/018-a4-capability-manifest`

**Created**: 2026-07-30

**Status**: Draft

**Input**: Slice `A4` — "Capability manifest schema and loader" (delivery plan §3.2, row A4)

> Constitution note: Specs MUST explain clinic-fit scope, layer placement, data and
> security boundaries, and degraded behavior when AI or supporting services are
> unavailable.

## Slice Contract

### Implements

§5.1, §5.7

### Freezes

- The capability manifest schema covering all ten field groups named in §5.1 (Identity, Access, Interaction, Input, Context requirements, Prompt binding, Output, Routing, Economics, Governance), including the field contents and "Consumed by" mapping of each group.
- The loader contract: a valid manifest loads; a malformed manifest fails the build; an in-place edit to a published version fails the build.
- The `interaction_mode` default of `single_shot` when the field is omitted, and the rule that conversational-only fields are rejected on a `single_shot` manifest.
- The two load-bearing manifest properties: a manifest is data not code, and a manifest never names a provider or a model (§5.1).

### Consumes

- Slice A3 freezes the canonical inference representation (§5.3): canonical request, stream chunk, result, and error types, and the guard that no field name is provider-shaped. A4's manifest declares an output schema ref and prompt binding refs but does not redefine the canonical types; changing A3's contract is out of scope by definition.

### Open decisions relied on

None. A4 does not depend on any §15 recommended default; the manifest schema and the `single_shot` default are decisions already settled in §5.1 and §5.7. (The conversational-only fields belong to amendment A14, which is already recorded in §5.1's Interaction row, not to an open decision.)

## Clarifications

### Session 2026-07-30

- Q: What on-disk source encoding do capability manifests use? → A: JSON files under `ai-platform/`, validated by a TypeScript schema module at build and load time; the runtime schema layer is an implementation detail of the plan. `[implementation choice — no §citation]`
- Q: How does the build prove "an in-place edit to a published version fails the build"? → A: A checked-in append-only registry mapping `(capability_id, version)` → manifest content hash; the build computes the manifest hash and fails if it differs from the registry entry. `[implementation choice — no §citation]`
- Q: Where do published manifests and the registry live, and what runs the gate? → A: JSON files under `ai-platform/manifests/published/` plus `ai-platform/manifests/published-registry.json`; `npm run verify-manifests` (and therefore `npm test`) runs `verifyManifestTree` against that tree. Hash algorithm is WebCrypto SHA-256 over canonical JSON. `[implementation choice — review resolution A4]`
- Q: How is runtime immutability of a loaded manifest enforced? → A: `load()` returns a deeply `Object.freeze`d object; mutation throws in strict mode rather than being silently discarded. `[implementation choice — review resolution A4]`
- Q: How are unknown keys and provider/model hints rejected? → A: Each group uses exact key-set equality against `MANIFEST_FIELD_MANIFEST`; a recursive denylist rejects any key matching `/provider|model/i` except the allowlisted `requiredProviderFeatures` key name. Enum fields `lifecycleState`, `Output.mode`, and `acceptanceMode` are validated at load time. `[implementation choice — review resolution A4]`
- Q: Where does the manifest loader live, and what is its export surface within `ai-platform/src/`? → A: A single `ai-platform/src/manifest/` module exporting `load()` and the `Manifest` type; the validator is kept internal to the module. `[implementation choice — no §citation]`

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Capability manifest schema and loader (Priority: P1)

As the platform's build/review component, I need an immutable, schema-validated
manifest declaring every field group of a capability version, so that every later
stage (resolver, validator, composer, router, journal) is constrained by a typed
contract rather than by prose, and so that an in-place edit to a published version
is caught at build time before it can drift.

**Why this priority**: A4 sits in band A because nothing in this slice handles a
real request — it exists so that everything after it (band C onwards) is
constrained. Its only prerequisite is A3 (the canonical types); it must land
before A5 (context key vocabulary, which the manifest's Context-requirements
group references) and before C1 (the capability resolver, which loads the
manifest). Contract slices come first by DP-4/DP-2.

**Independent Test**: A build-time contract + build test proves a valid manifest
loads with all ten field groups, each omitted/malformed group fails the build, an
in-place edit to a published version fails the build, an omitted `interaction_mode`
defaults to `single_shot`, and conversational-only fields are rejected on a
`single_shot` manifest. No request is ever issued (delivery plan §3.11.1, row A4).

**Acceptance Scenarios**:

1. **Given** a manifest declaring all ten field groups of §5.1 with valid contents, **When** the loader/build runs, **Then** the manifest loads and is available to consuming stages.
2. **Given** a manifest with one field group omitted or malformed, **When** the build runs, **Then** the build fails identifying that group (one case per group, ten cases).
3. **Given** a published capability version, **When** a semantically meaningful field of that version is edited in place, **Then** the build fails rather than producing an updated published version.
4. **Given** a manifest that omits `interaction_mode`, **When** the loader loads it, **Then** `interaction_mode` resolves to `single_shot`.
5. **Given** a manifest declaring `interaction_mode: single_shot` that also carries a conversational-only field (max history turns, max context rounds per turn, or transcript size limit), **When** the build runs, **Then** the build fails.

### Test plan

Layer: Contract + build (delivery plan §3.11.1, row A4; §13.5). Named tests:

- `manifest_loads_all_ten_groups` — contract/build — a valid manifest loads with all ten §5.1 field groups present and well-formed.
- `manifest_missing_or_malformed_group_<group>` — contract/build — one failure case per field group (Identity, Access, Interaction, Input, Context requirements, Prompt binding, Output, Routing, Economics, Governance); the build fails and names the offending group.
- `in_place_edit_of_published_version_fails_build` — build — editing a semantically meaningful field of an already-published version fails the build (§5.7: "Changing a capability between `single_shot` and `conversational` is a new capability version, never an in-place edit"; §5.1: "changing anything semantically meaningful produces a new version").
- `omitted_interaction_mode_defaults_to_single_shot` — contract — an omitted `interaction_mode` field resolves to `single_shot` (§5.1).
- `conversational_fields_rejected_on_single_shot` — contract — a `single_shot` manifest carrying any of max history turns / max context rounds per turn / transcript size limit fails the build (§5.1 Interaction row: those fields are "for `conversational` only").

Coverage additions from §3.10 (every branch, every inherited prohibition, every named boundary):

- `manifest_is_data_not_code` — contract — the manifest contributes no executable pipeline/client code; reusing existing context keys, routing policy, and validation rules needs no pipeline or client change (§5.1).
- `manifest_never_names_provider_or_model` — contract — the manifest schema permits no provider name or model identifier; it names requirements only (§5.1).
- `interaction_mode_fixed_for_life_of_version` — contract — a loaded manifest's `interaction_mode` is immutable for that version; changing it is a new version, not a mutation (§5.7). Deep-freeze rejects runtime writes.
- `unknown_extra_keys_rejected` / `provider_model_denylist_across_groups` — contract — unknown group keys and provider/model-shaped keys (including nested) fail `load()`.
- `content_enum_validation` — contract — invalid `lifecycleState`, `Output.mode`, or `acceptanceMode` fail `load()`.
- `deep_freeze_rejects_group_mutation` — contract — mutating any group field on a loaded manifest throws.
- `content_hash_is_sha256` — contract — `hashManifest` returns a 64-char hex SHA-256 digest.
- `registry_gate_runs_in_build` — build — `package.json` declares `verify-manifests`; checked-in manifests match `published-registry.json`; an in-place edit fails the gate.

### Edge Cases

- A4 is a contract + build slice; it emits no §5.4 taxonomy codes and performs no request-path work, so there are no runtime error codes, retries, or degraded behaviour to cover. Its failure modes are all build-time validation failures, enumerated above.
- Build-time failure: a published version is edited in place. The build must fail; there is no "patch published version" path.
- Build-time failure: a `single_shot` manifest carries a conversational-only field. Rejected; there is no silent-stripping path.
- Boundary: `interaction_mode` is the only switch that changes a request's shape, and it defaults to `single_shot`; an omitted value is a valid default, not a malformed manifest.
- Boundary: a manifest that names a provider or model is rejected at schema time; the Routing group names *requirements* (structured output, context window, language, latency class, degraded-tier policy), never targets (§5.1).
- No retry, no caching, no abstraction, and no configurability beyond what §5.1 and §5.7 name (R-20).

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The manifest schema MUST cover all ten field groups — Identity, Access, Interaction, Input, Context requirements, Prompt binding, Output, Routing, Economics, Governance — with the contents and "Consumed by" mapping stated for each in §5.1 (§5.1).
- **FR-002**: The manifest MUST be immutable per version; changing anything semantically meaningful MUST produce a new version (§5.1).
- **FR-003**: The build MUST fail on a malformed manifest (delivery plan §3.2, row A4 "Done when").
- **FR-004**: The build MUST fail on an in-place edit to a published version (delivery plan §3.2, row A4 "Done when"; §5.7 — a capability's interaction mode is "fixed for the life of a capability version … never an in-place edit").
- **FR-005**: When `interaction_mode` is omitted, the loader MUST default it to `single_shot` (delivery plan §3.2, row A4 "Done when"; §5.1 — "Interaction mode is the only switch that changes a request's shape, and it defaults to `single_shot`").
- **FR-006**: A `single_shot` manifest carrying any conversational-only field (max history turns, max context rounds per turn, transcript size limit) MUST be rejected (delivery plan §3.2 row A4 and §3.11.1 row A4; §5.1 Interaction row — those fields apply "for `conversational` only").
- **FR-007**: The manifest MUST be data, not code — adding a capability that reuses existing context keys, an existing routing policy, and an existing validation rule set MUST require no pipeline change and no client change (§5.1).
- **FR-008**: The manifest MUST never name a provider or a model; it MUST name requirements only (structured output, context window, language, latency class, degraded-tier policy in the Routing group), leaving target selection to the routing policy (§5.1).
- **FR-009**: The Output field group MUST carry mode (`prose` / `structured` / `structured_atomic`), output schema ref, business validation rule refs, and repair policy (allowed, max attempts) (§5.1).
- **FR-010**: The Governance field group MUST carry acceptance mode (`advisory_display`, `human_accept_required`, `auto_apply` — the last disallowed for clinical content per A5), retention class, and eval suite ref (§5.1).

### Key Entities *(include if feature involves data)*

- **Capability manifest**: The immutable declaration of a capability version. Schema is the ten field groups of §5.1 with the field contents and "Consumed by" mapping of each. The loader produces a typed, immutable manifest object available to consuming stages; no D1 entity is defined by this slice (storage/migrations are A6).

## Constitution Alignment *(mandatory)*

### Architecture & Operations Impact

- **Clinic Fit**: This slice serves small-to-mid multi-branch clinics indirectly: it freezes the contract that every later clinic-facing capability stage is constrained by, keeping the platform clinic-scale and simple (constitution: optimize for small-to-mid multi-branch clinics). No enterprise or hospital-specific needs are introduced.
- **Layer Placement**: This slice touches only `ai-platform/` (the Cloudflare Worker source, where the manifest schema and loader live). It touches neither `backend/` (Supabase/PostgreSQL) nor `frontend/` (Flutter). Per the architecture §14 acknowledgement registered for band A (delivery plan §7), the AI platform gateway is a non-primary, additive component with a separate store and no write path into Supabase; this slice adds contract surface only and adds no domain logic and no business data.
- **Data Integrity & Security**: A4 defines no stored domain data and writes nothing to D1, R2, or Supabase. Integrity here is build-time: the manifest's immutability and schema validation enforce that later stages cannot drift from a frozen contract. No RLS, RPCs, or audit fields are introduced by this slice.
- **Failure Handling**: A4 has no runtime request path and therefore no AI/network/backend degraded behaviour. Its only failure mode is the build: a malformed manifest, an in-place edit to a published version, or a `single_shot` manifest carrying conversational-only fields each fail the build. There is no fall-back, retry, or degraded path, and none is added (R-20).

## Out of Scope

- Slice A3 — canonical inference representation (§5.3): consumed, not modified.
- Slice A5 — context key vocabulary and shape registry (§5.2): the manifest's Context-requirements group references context keys by their `domain.concept@vN` form, but defining/validating key shapes is A5.
- Slice A6 — D1 schema and migrations (§7.3): A4 defines no D1 entity; manifest storage/persistence belongs to A6.
- Slice C1 — capability resolver stage (§4.3.4, §6.1 stage 5): resolving a capability id plus requested version to a manifest and distinguishing `capability_unknown` / `capability_retired` / `capability_disabled` is C1. A4 provides the typed manifest object; it does not perform resolution or lifecycle-state handling at request time.
- Slice H1 — conversational manifest fields (§5.1, §5.7, §6.7.4, A14): A4 enforces that `single_shot` rejects conversational-only fields and that `interaction_mode` defaults to `single_shot`; it does not own the *contents* rules for conversational fields beyond presence/absence. Vocabulary validation of `permittedKeySet` entries is the H1 extension co-located in the A4 loader (H1 Consumes A4; `specs/044-conversational-manifest-schema`).
- Slice D1 — prompt registry and artifacts (§4.3.6, §5.7, §9.5): the manifest's Prompt-binding group references prompt artifact refs; loading/pinning artifacts by hash is D1.
- No mechanism from §9.14 added because it looks prudent (R-20).
- No prompt text, provider name, or model identifier in the Flutter client (R-12) — not applicable to this slice beyond the manifest's own never-names-provider/model rule, which is in scope above.
- No second Quota Durable Object round trip and no second R2 object per request (§7.5, §13.6) — not applicable to a build/contract slice.
- No guard rejection journaled as a request; no D1 row per stream chunk (§7.5) — not applicable.
- No per-request server-side state of any kind (§4.4, §9.7) — A4 introduces no request-path state.
- No client-side assembly of a final result from chunks; no committable provisional content (§6.4, A5) — not applicable.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A contract + build test proves a manifest declaring all ten §5.1 field groups loads successfully (delivery plan §3.2 row A4 "Done when").
- **SC-002**: A contract + build test proves the build fails for each of the ten field groups when omitted or malformed (one named case per group) (delivery plan §3.11.1 row A4).
- **SC-003**: A build test proves an in-place edit to a published version fails the build (delivery plan §3.2 row A4 "Done when"; §5.7).
- **SC-004**: A contract test proves an omitted `interaction_mode` resolves to `single_shot` (delivery plan §3.2 row A4 "Done when"; §5.1).
- **SC-005**: A contract test proves conversational-only fields are rejected on a `single_shot` manifest (delivery plan §3.11.1 row A4; §5.1).
- **SC-006**: A contract test proves the manifest schema permits no provider name or model identifier (§5.1) and contributes no executable pipeline/client code (§5.1).

## Assumptions

- The manifest and its loader live in `ai-platform/` (Cloudflare Worker source), alongside D1 migrations and prompt artifacts, as a sibling of `frontend/` and `backend/` (delivery plan §7.1).
- A4 is exercised purely by contract + build tests; no Worker request is issued and no live D1/R2 binding is needed to prove its acceptance criteria (delivery plan §3.11.1 row A4, "Contract + build" layer).
- The conversational-only field rule (reject on `single_shot`) is already encoded in §5.1's Interaction row and does not require H1 to have landed; A4 enforces the presence/absence rule, H1 validates the field contents.
- The manifest is data deployed with the Worker; its on-disk/wire encoding is an implementation detail of the loader, not a contract frozen by this slice beyond the ten field groups and the rules above.