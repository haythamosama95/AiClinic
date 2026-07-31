# Feature Specification: Context key vocabulary, D1 schema, and config cache (A5)

**Feature Branch**: `ai/019-a5-context-keys-d1-config`

**Created**: 2026-07-31

**Status**: Draft

**Input**: Slice `A5` — *Context key vocabulary, D1 schema, and config cache* (Delivery Plan §3.2, row A5).

> Constitution note: This slice lives entirely inside the Cloudflare AI Gateway Worker
> (`ai-platform/`), the additive, non-primary component registered by A1. Per §14 of
> `docs/architecture/17-ai-platform.md`, the gateway holds no domain logic, no business data, and has
> no write path into Supabase. This slice stays inside that boundary: it freezes a context-key
> vocabulary, the platform's own D1 schema, and an in-isolate config cache. It performs no
> request-path work and writes no clinic data.

## Slice Contract

### Implements

§5.2, §7.3, §13.4, §4.3.2, §4.4, §9.15 of `docs/architecture/17-ai-platform.md` (copied verbatim from
the A5 `Canonical` cell, Delivery Plan §3.2).

### Freezes

This slice establishes, for the first time:

- **The context-key naming contract**: a context key is a stable, versioned name of the form
  `domain.concept@vN` — e.g. `patient.demographics@v1`, `visit.vitals@v1`, `visit.chief_complaint@v1`,
  `medication.active_list@v1`, `lab.recent_results@v1`, `clinic.branch_profile@v1`. A key names what
  the data means to a clinician, never where it is stored; `visits_vitals_table@v1` or
  `get_visit_vitals_rpc@v1` are not keys (§5.2).
- **The context-key shape contract**: each key has a platform-published shape — field names, types,
  cardinality, units — which is the only schema knowledge shared between the two sides. The first
  key's shape is published by this slice (§5.2; Delivery Plan §3.2 row A5 "Done when").
- **The platform's D1 logical model**: forward-only, additive migrations create every entity named in
  §7.3, with the `ai_request` request-reference column indexed and unique, and the nullable
  `conversation_id` / `turn_ordinal` columns present. The schema is pinned by a schema snapshot test
  and applies cleanly to an empty database (Delivery Plan §3.2 row A5 "Done when"; §3.11.1 row A5).
- **The config-cache contract**: an in-isolate memory map with a short TTL, populated from D1 on a
  miss, holding installations, keys, entitlements, grants, kill switches, and the active routing
  policy. It is a latency optimization over D1 and owns nothing (§4.3.2, §4.4, §9.15).

### Consumes

- Slice A4 freezes the capability manifest schema (§5.1, §5.7), whose **Context requirements** group
  is an "ordered list of context keys with `required`/`optional`, shape reference, max size, freshness
  hint" (and a permitted key set for `conversational`). A5 publishes the key vocabulary and the first
  key's shape that those manifest references resolve to; changing A4's manifest schema is out of
  scope by definition.
- The `ai_request` request-reference column stores values in the format frozen by slice A2 (eight
  Crockford-base32 symbols, `XXXX-XXXX`). A5 stores and indexes that format; it does not redefine it
  (Delivery Plan §3.2 row A5 lists only A4 under `Needs`; A2's format is used unchanged).

### Open decisions relied on

- **Open Decision 1** — *Which capability is built first.* Recommended default: one non-clinical-record
  capability (e.g. drafting a visit summary for review). The "first key" whose shape A5 publishes is
  the context key that first capability requires, drawn from the §5.2 example keys. This relies on
  OD-1's recommended default so A5 does not invent the first capability (§15; Delivery Plan §7
  dependency "Selection of the first capability … blocks A5").

## Clarifications

### Session 2026-07-31

- Q: Where do the D1 migrations live and what applies them in the test harness? → A: `ai-platform/migrations/<YYYYMMDDHHMMSS>_<name>.sql`, applied via `wrangler d1 migrations` (Miniflare D1) in the test harness; rerun-no-op is enforced by Wrangler's own applied-migrations table. `[implementation choice — no §citation]`
- Q: How is the schema snapshot test (`schema_snapshot_matches`) constructed and compared? → A: dump each entity's `CREATE TABLE` DDL after migration to a checked-in `ai-platform/test/schema.snap.sql`; the test asserts the dump equals the snapshot. `[implementation choice — no §citation]`
- Q: How do the config-cache spy tests observe D1 calls without a real binding? → A: inject a `D1Reader` port behind the cache; a spy/test-double in vitest asserts `.read` call count and returns the canned row or a miss literal. `[implementation choice — no §citation]`
- Q: Where do the context-key vocabulary and validator module live within `ai-platform/src/`? → A: a single `ai-platform/src/context/` module mirroring A4's `src/manifest/` — exports `validateKey`, `validatePayload`, and the published `KeyShape` type. `[implementation choice — no §citation]`

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Context key vocabulary, D1 schema, and config cache (Priority: P1)

As the platform's build/review component, I need the context-key naming and shape vocabulary frozen,
the platform's D1 logical model created by forward-only migrations, and an in-isolate config cache
that answers every guard consult from memory when warm and from exactly one D1 read when cold — so
that every later stage (guard, resolver, validator, composer, journal, support lookup) is constrained
by typed contracts rather than by prose, and so that the guard's authorization reads stay off D1's
single write thread in the common case.

**Why this priority**: A5 sits in band A because nothing here handles a real request — it exists so
that everything after it is constrained (DP-4, DP-2). Its only prerequisite is A4 (the manifest schema
that references context keys); it must land before B2 (enrollment, which writes the `installation`
entity), before B3 (the guard, which reads the config cache with no D1 read on a warm isolate),
before C3 (the journal writer, which writes `ai_request` rows), and before E3 (the client Context
Resolver, whose RPC returns the first key's declared shape published here).

**Independent Test**: A contract + migration + spy-based unit test proves the `domain.concept@vN`
format is enforced (a storage-named key is rejected), the first key's shape validates a conforming
payload and rejects each shape violation, forward-only migrations create every §7.3 entity and apply
cleanly to an empty database (re-running is a no-op, a schema snapshot pins them, the request
reference is uniquely indexed, and `conversation_id`/`turn_ordinal` are nullable), and the config
cache answers all six config entity kinds from memory with zero I/O when warm and exactly one D1
read when cold, with a D1 miss surfacing as a typed failure rather than an empty cache entry. No
request is ever issued (Delivery Plan §3.11.1, row A5).

**Acceptance Scenarios**:

1. **Given** a context key of the form `domain.concept@vN`, **When** it is submitted to the key
   validator, **Then** it is accepted.
2. **Given** a malformed context key, **When** it is submitted, **Then** it is rejected.
3. **Given** a key named after storage rather than meaning (e.g. `visits_vitals_table@v1` or
   `get_visit_vitals_rpc@v1`), **When** it is submitted, **Then** it is rejected.
4. **Given** an unknown key version, **When** it is submitted, **Then** it is rejected.
5. **Given** a payload conforming to the first key's published shape, **When** it is validated,
   **Then** it passes.
6. **Given** a payload violating the shape by type, **When** it is validated, **Then** it is rejected.
7. **Given** a payload violating the shape by cardinality, **When** it is validated, **Then** it is
   rejected.
8. **Given** a payload violating the shape by units, **When** it is validated, **Then** it is
   rejected.
9. **Given** a payload violating the shape by a missing field, **When** it is validated, **Then** it
   is rejected.
10. **Given** the first key's shape publication, **When** a consumer reads it, **Then** the published
    shape declares field names, types, cardinality, and units.
11. **Given** an empty database, **When** the forward-only migrations run, **Then** they apply
    cleanly and create every entity named in §7.3.
12. **Given** a database the migrations have already been applied to, **When** the migrations run
    again, **Then** they are a no-op.
13. **Given** the migrated schema, **When** the schema snapshot test runs, **Then** it matches.
14. **Given** the migrated schema, **When** each §7.3 entity is checked, **Then** it is present (one
    case per entity: `installation`, `installation_key`, `entitlement`, `capability_grant`,
    `routing_policy`, `ai_request`, `ai_attempt`, `usage_event`, `usage_rollup`,
    `platform_counter`, `control_audit`).
15. **Given** the `ai_request` table, **When** its request-reference index is inspected, **Then** the
    index exists and is unique.
16. **Given** the `ai_request` table, **When** its `conversation_id` and `turn_ordinal` columns are
    inspected, **Then** they are nullable.
17. **Given** a warm isolate with the config cache populated, **When** it answers a consult for
    installations, keys, entitlements, grants, kill switches, and the active routing policy, **Then**
    it performs zero I/O (one case per cached entity kind).
18. **Given** a cold isolate, **When** it answers a config consult, **Then** it performs exactly one
    D1 read.
19. **Given** a populated config cache entry whose TTL has expired, **When** it is consulted,
    **Then** exactly one refetch occurs.
20. **Given** a D1 lookup for a requested config row that does not exist, **When** the cache consults
    D1, **Then** a typed failure is surfaced rather than an empty cache entry being stored.

### Test plan

Layer: Contract + migration + unit (spy) (Delivery Plan §3.11.1, row A5; §13.5). Named tests:

- `context_key_valid_accepted` — contract — a `domain.concept@vN` key is accepted (§5.2).
- `context_key_malformed_format_rejected` — contract — a malformed key is rejected (§3.11.1 row A5).
- `context_key_storage_named_rejected` — contract — a key named after storage (`visits_vitals_table@v1`, `get_visit_vitals_rpc@v1`) is rejected (§5.2; Done when).
- `context_key_unknown_version_rejected` — contract — an unknown key version is rejected (§3.11.1 row A5).
- `context_key_payload_validates` — contract — a conforming payload validates against the published shape (§3.11.1 row A5; §5.2).
- `context_key_shape_violation_type` — contract — a type violation is rejected (§3.11.1 row A5).
- `context_key_shape_violation_cardinality` — contract — a cardinality violation is rejected (§3.11.1 row A5).
- `context_key_shape_violation_units` — contract — a units violation is rejected (§3.11.1 row A5).
- `context_key_shape_violation_missing_field` — contract — a missing-field violation is rejected (§3.11.1 row A5).
- `first_context_key_shape_published` — contract — the first key's shape is published with field names, types, cardinality, and units, for the context the first capability requires (OD-1 recommended default) (§5.2; §15 OD-1).
- `migrations_apply_cleanly_to_empty_db` — migration — forward-only migrations create every §7.3 entity on an empty database (§13.4; §7.3; Done when).
- `migrations_rerun_is_noop` — migration — re-running the migrations is a no-op (§3.11.1 row A5).
- `schema_snapshot_matches` — migration/contract — a schema snapshot test pins the schema (Done when; §3.11.1 row A5).
- `entity_presence_<entity>` — migration — one presence case per §7.3 entity (`installation`, `installation_key`, `entitlement`, `capability_grant`, `routing_policy`, `ai_request`, `ai_attempt`, `usage_event`, `usage_rollup`, `platform_counter`, `control_audit`) (§7.3; §3.11.1 row A5).
- `request_reference_index_exists_and_unique` — migration — the `ai_request` request-reference index exists and is unique (§7.3; §7.6; Done when; §3.11.1 row A5).
- `conversation_id_and_turn_ordinal_nullable` — migration — `conversation_id` and `turn_ordinal` are nullable (§7.3; Done when; §3.11.1 row A5).
- `config_cache_cold_isolate_one_d1_read` — unit (spy) — a cold isolate performs exactly one D1 read (§9.15; §4.3.2; Done when).
- `config_cache_warm_isolate_zero_io` — unit (spy) — a warm isolate performs zero I/O (§9.15; §4.3.2; Done when).
- `config_cache_ttl_expiry_one_refetch` — unit (spy) — TTL expiry triggers exactly one refetch (§3.11.1 row A5).
- `config_cache_entity_kind_<kind>` — unit (spy) — one case per cached entity kind: installations, keys, entitlements, grants, kill switches, the active routing policy (§4.3.2; §4.4; Done when).
- `config_cache_d1_miss_typed_failure` — unit (spy) — a D1 miss surfaces as a typed failure rather than an empty cache entry (§3.11.1 row A5; §4.4).

Coverage additions from §3.10 (every inherited invariant and prohibition):

- `config_cache_owns_nothing` — unit (spy) — the cache is a latency optimization over D1 and is not an authoritative store; nothing outside D1 is the truth about anything (§4.4).
- `config_cache_uses_in_isolate_memory_not_kv` — contract/build — the config cache is an in-isolate memory map backed by D1 on miss; no Workers KV binding is introduced (§9.15 rejected; §4.4).
- `no_per_request_state_introduced` — unit — the schema and cache introduce no per-request server-side state; only an open connection plus a journal row represents an in-flight request, and the cache holds installation-scoped copies only (§4.4 "There is no store for live request state"; §9.7).

### Edge Cases

- **Error codes this slice can emit.** A5 is a contract + migration + cache slice; it is not on the
  request path and emits no §5.4 runtime taxonomy codes. Its failure surfaces are: build/contract-time
  rejection of a malformed, storage-named, unknown-version, or shape-violating context key; a
  migration that does not apply cleanly (fails loudly, never partially); and a typed failure returned
  by the config cache on a D1 miss (the row genuinely absent). No retry, no HTTP status, no
  quota-consumption flag applies to any of these.
- **Boundary — context-key format.** `domain.concept@vN` only; the version suffix is mandatory. A
  storage-named key is rejected even when the referenced table or RPC genuinely exists, because the
  rule is about meaning, not existence (§5.2).
- **Boundary — config-cache TTL.** The TTL is short (§4.3.2, §4.4); its exact value is an
  implementation choice of the plan, not pinned here. Expiry provokes exactly one refetch, never a
  burst.
- **Boundary — cold-vs-warm I/O budget.** A cold isolate pays exactly one same-region D1 read; a
  warm isolate pays zero. The single-read invariant is what makes the cache worth having; a second
  read on any consult is a defect (§9.15).
- **Boundary — request-reference index.** The index is unique (§7.6; §3.11.1 row A5). The request
  reference is a support handle, not a key; the request's identity is its ULID, frozen by A2. A5
  stores the A2 format unchanged and indexes it; it invents no new identifier.
- **Boundary — nullable conversation columns.** `conversation_id` and `turn_ordinal` are nullable
  because `single_shot` requests (the default) carry neither; they are populated only by
  conversational legs (§7.3, A14). A5 creates the columns; it does not implement conversational
  behaviour.
- **Failure branch — D1 miss.** A requested config row that does not exist must surface as a typed
  failure and must not be cached as an empty entry, so a later installation enrollment is visible
  without a cache flush and an unknown installation cannot be confused with a cached absence (§3.11.1
  row A5; §4.4 "owns nothing").
- **Failure branch — migration.** Migrations are forward-only and additive (§13.4); a migration that
  cannot apply cleanly fails the build, never leaves the database half-migrated.
- No retry, no caching beyond the named TTL, no abstraction, and no configurability beyond what
  §5.2, §7.3, §4.3.2, §4.4, §9.15, and §13.4 name (R-20).

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: A context key MUST follow the `domain.concept@vN` format — e.g.
  `patient.demographics@v1`, `visit.vitals@v1`, `visit.chief_complaint@v1`,
  `medication.active_list@v1`, `lab.recent_results@v1`, `clinic.branch_profile@v1` (§5.2).
- **FR-002**: A context key MUST name what the data means to a clinician, never where it is stored;
  a storage-named key such as `visits_vitals_table@v1` or `get_visit_vitals_rpc@v1` MUST be rejected
  (§5.2).
- **FR-003**: Each context key MUST have a platform-published shape — field names, types,
  cardinality, units — which is the only schema knowledge shared between the two sides (§5.2).
- **FR-004**: The first key's shape MUST be published by this slice, drawn from the §5.2 example keys
  for the context the first capability requires (Open Decision 1 recommended default) (§5.2; §15 OD-1;
  Delivery Plan §3.2 row A5 "Done when").
- **FR-005**: A payload conforming to a published shape MUST validate; a shape violation — type,
  cardinality, units, or a missing field — MUST be rejected (Delivery Plan §3.11.1 row A5; §5.2).
- **FR-006**: An unknown context-key version MUST be rejected (Delivery Plan §3.11.1 row A5).
- **FR-007**: Adding an optional context key MUST be backward compatible; adding a required key or
  changing a shape MUST require a new key version and a new capability version (§5.2 Evolution). The
  overlap/deprecation *behaviour* is out of scope (band J).
- **FR-008**: Forward-only, additive D1 migrations, versioned in the repository, MUST create every
  entity named in §7.3 (§13.4 Migrations; §7.3; Delivery Plan §3.2 row A5 "Done when").
- **FR-009**: The migrations MUST apply cleanly to an empty database, and re-running them MUST be a
  no-op (Delivery Plan §3.11.1 row A5).
- **FR-010**: A schema snapshot test MUST pin the migrated schema (Delivery Plan §3.2 row A5 "Done
  when"; §3.11.1 row A5).
- **FR-011**: `ai_request` MUST carry a request-reference column with a unique index, storing values
  in the format frozen by A2 unchanged (§7.3; §7.6; Delivery Plan §3.2 row A5 "Done when"; §3.11.1
  row A5).
- **FR-012**: `ai_request` MUST carry nullable `conversation_id` and `turn_ordinal` columns
  (§7.3; Delivery Plan §3.2 row A5 "Done when"; §3.11.1 row A5).
- **FR-013**: Every §7.3 entity MUST be present after migration — `installation`,
  `installation_key`, `entitlement`, `capability_grant`, `routing_policy`, `ai_request`,
  `ai_attempt`, `usage_event`, `usage_rollup`, `platform_counter`, `control_audit` (§7.3; Delivery
  Plan §3.11.1 row A5).
- **FR-014**: The config cache MUST be an in-isolate memory map with a short TTL, populated from D1
  on a miss, holding installations, keys, entitlements, grants, kill switches, and the active routing
  policy (§4.3.2; §4.4).
- **FR-015**: The config cache MUST own nothing; it is a latency optimization over D1 and is not an
  authoritative store (§4.4).
- **FR-016**: A warm isolate MUST answer installations, keys, entitlements, grants, kill switches,
  and the active routing policy from memory with no I/O (Delivery Plan §3.2 row A5 "Done when";
  §9.15; §4.3.2).
- **FR-017**: A cold isolate MUST perform exactly one D1 read to answer a config consult (Delivery
  Plan §3.2 row A5 "Done when"; §9.15; §3.11.1 row A5).
- **FR-018**: TTL expiry of a cached config entry MUST trigger exactly one refetch (Delivery Plan
  §3.11.1 row A5).
- **FR-019**: A D1 miss — a requested config row that does not exist — MUST surface as a typed
  failure rather than being stored as an empty cache entry (Delivery Plan §3.11.1 row A5; §4.4).

### Key Entities *(include if feature involves data)*

- **D1 logical model (§7.3)**: The platform's own relational store, created by forward-only
  migrations. Entities and their key fields are exactly those of §7.3: `installation`,
  `installation_key`, `entitlement`, `capability_grant`, `routing_policy`, `ai_request` (with the
  request-reference column, indexed and unique, and nullable `conversation_id` / `turn_ordinal`),
  `ai_attempt`, `usage_event`, `usage_rollup`, `platform_counter`, `control_audit`. Field lists in
  §7.3 indicate shape and cardinality; this slice freezes the schema, not the row-level write paths
  (those are C3 and later).
- **Context key (§5.2)**: A stable, versioned name `domain.concept@vN` with a platform-published
  shape (field names, types, cardinality, units). The first key's shape is published here; the key
  set is otherwise owned by manifest Context-requirements declarations (A4).
- **Config cache (§4.3.2, §4.4, §9.15)**: Not a store — an in-isolate memory map of short TTL backed
  by D1 on miss, holding installations, keys, entitlements, grants, kill switches, and the active
  routing policy. It owns nothing and is a latency optimization over D1.

## Constitution Alignment *(mandatory)*

### Architecture & Operations Impact

- **Clinic Fit**: Clinic-scale means tens of installations (F5), so the entire config set is a few
  kilobytes that fits in isolate memory with room to spare; a warm isolate answers in nanoseconds and
  a cold one pays a single same-region D1 read (§9.15). This is the small-to-mid multi-branch clinic
  shape the constitution assumes; no enterprise-scale machinery is introduced.
- **Layer Placement**: This slice touches only `ai-platform/` (the Cloudflare Worker). Context-key
  vocabulary, the D1 schema and its migrations, and the config cache module all live in
  `ai-platform/`. It touches neither `backend/` (Supabase) nor `frontend/` (Flutter): the platform
  owns its own D1 store (§4.4; §3.4) and the data direction is platform-internal only. Per the §14
  acknowledgement, the gateway is a non-primary, additive component — no domain logic, no business
  data, no write path into Supabase, always optional; this slice adds contracts and a store, not
  clinical behaviour.
- **Data Integrity & Security**: D1 is the only authoritative store; R2 holds bytes D1 rows point to,
  the Durable Object holds live counters that settle into D1's ledger, and the config cache holds
  copies of D1 rows — nothing outside D1 is the truth about anything (§4.4). Installation keys and
  status are read through the config cache (§4.3.2); the cache owns nothing, so a D1 update is the
  only way to change config truth. RLS is a Supabase-side concern and does not apply to the
  platform's own D1 database.
- **Failure Handling**: A D1 miss surfaces as a typed failure, never a cached empty entry, so an
  unknown installation is not confused with a cached absence (§3.11.1 row A5; §4.4). A cold isolate
  pays one same-region D1 read; if D1 is unreachable the cache cannot populate, which surfaces as
  that typed failure rather than as stale guesses. This slice performs no request-path work and emits
  no §5.4 taxonomy codes, so there is no degraded-AI behaviour to define here.

## Out of Scope

- **Neighbouring slices this one touches but does not implement.**
  - A4 (capability manifest schema) — consumed; A5 publishes the key vocabulary the manifest's
    Context-requirements group references. The manifest schema is frozen by A4 and is not changed.
  - A2 (request-reference format) — consumed; A5 stores and indexes the A2 format unchanged and
    invents no identifier.
  - B2 (enrollment) writes the `installation`, `installation_key`, and `entitlement` entities A5
    creates; B3 (guard) reads the config cache with no D1 read on a warm isolate; C3 (journal
    writer) writes `ai_request` rows against the schema A5 creates; H3 (conversational journaling)
    populates `conversation_id` / `turn_ordinal`; F3 (support lookup) uses the request-reference
    index. All are later slices; A5 creates the schema and the cache only.
- **No request-path work.** A5 freezes contracts, schema, and cache; it performs no pipeline stage,
  writes no `ai_request` row, and emits no §5.4 taxonomy codes.
- **No D1 write path on the hot path.** The journal write (stage 9) is C3; A5 defines schema and
  migrations only.
- **No Workers KV binding.** KV as a hot config cache is rejected in favour of in-isolate memory
  with a D1 read on miss (§9.15). Adding KV later is a change inside the cache lookup function
  triggered by geography or installation count, not by this slice.
- **No conversational behaviour.** A5 creates the nullable `conversation_id` / `turn_ordinal`
  columns because the schema must accommodate amendment A14; it does not implement transcripts,
  context negotiation, or turn budgets (band H).

Prohibitions copied from Delivery Plan §6.4 — none are pulled forward by this slice, all are
restated so an implementer with weak judgement does not add them:

- No mechanism from §9.14 added because it looks prudent (R-20) — in particular, no Workers KV
  binding (§9.15 rejected) and no second analytics store.
- No prompt text, provider name, or model identifier in the Flutter client (R-12) — none introduced;
  this slice touches no client code.
- No second Quota Durable Object round trip and no second R2 object per request (§7.5, §13.6) — not
  applicable to this contract/schema/cache slice, restated unchanged.
- No guard rejection journaled as a request; no D1 row per stream chunk (§7.5) — the journal write
  path is C3; A5 writes no request rows.
- No per-request server-side state of any kind (§4.4, §9.7) — the cache holds installation-scoped
  copies only; no per-request state object is introduced.
- No client-side assembly of a final result from chunks; no committable provisional content (§6.4,
  amendment A5) — not applicable to this slice, restated unchanged.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: An automated test enforces the `domain.concept@vN` format and rejects a key named after
  storage rather than meaning.
- **SC-002**: The first key's shape is published and an automated test validates a conforming payload
  while rejecting each shape violation (type, cardinality, units, missing field).
- **SC-003**: Forward-only migrations create every §7.3 entity, apply cleanly to an empty database,
  re-run as a no-op, and are pinned by a schema snapshot test.
- **SC-004**: An automated test proves the `ai_request` request-reference index exists and is unique,
  and that `conversation_id` and `turn_ordinal` are nullable.
- **SC-005**: A spy-based unit test proves a warm isolate answers all six config entity kinds
  (installations, keys, entitlements, grants, kill switches, active routing policy) with zero I/O,
  and a cold isolate performs exactly one D1 read.
- **SC-006**: A spy-based unit test proves a D1 miss surfaces as a typed failure rather than an empty
  cache entry.

## Assumptions

- The first capability is the one Open Decision 1's recommended default names — one
  non-clinical-record capability (e.g. drafting a visit summary for review). The first published
  context key is the context that capability requires, drawn from the §5.2 example keys (§15 OD-1;
  Delivery Plan §7 dependency "Selection of the first capability … blocks A5").
- The clinic schema and RPCs that can satisfy the first context key exist or will be confirmed
  before A5 fixes the first key's shape (Delivery Plan §7 dependency "The clinic schema and RPCs
  that can satisfy the first context key … blocks A5, E3"). A5 publishes the platform-side shape; the
  client-side resolution mapping is E3.
- The config-cache TTL is short (§4.3.2, §4.4); its exact value is an implementation choice left to
  the plan, not a value the architecture pins.
- Branch-aware authentication and tenant isolation patterns are Supabase-side and not relevant to
  the platform's own D1; the platform isolates tenants by installation-scoped tokens and
  installation-scoped queries (§4.4; §3.3).
- AI assistance remains optional and additive; this slice defines contracts and a store and does not
  change the product's graceful-degradation behaviour.