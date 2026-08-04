# Implementation Plan: Context key vocabulary, D1 schema, and config cache (A5)

**Branch**: `ai/019-a5-context-keys-d1-config` | **Date**: 2026-07-31 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/019-ai-context-keys-d1-config/spec.md`

## Summary

A5 freezes three foundational surfaces of the AI gateway in a single contract slice: the
context-key naming and shape vocabulary (`domain.concept@vN` with a published shape of field names,
types, cardinality, units — plus the first key's shape), the platform's own D1 logical model as
forward-only additive migrations creating every entity named in §7.3 (with the `ai_request`
request-reference column indexed and unique and `conversation_id` / `turn_ordinal` nullable), and
the in-isolate config cache that answers installations, keys, entitlements, grants, kill switches,
and the active routing policy from memory when warm and from exactly one D1 read when cold. It sits
in band A because nothing in it handles a real request — it exists so that every later stage (the
guard in B3, the journal writer in C3, the client Context Resolver in E3, conversational journaling
in H3, support lookup in F3) is constrained by typed contracts rather than by prose (delivery plan
§3.2, row A5). It needs only A4 (the manifest schema whose Context-requirements group references
context keys) and must land before B2/B3/C3/E3/H3/F3.

## Technical Context

**Language/Version**: TypeScript 5.9 in the Cloudflare Worker (`ai-platform/`), Node ≥22 for the toolchain. D1 migrations are SQL applied by `wrangler d1 migrations` (per Clarification Q1).

**Primary Dependencies**: `vitest` ~3.2 with `@cloudflare/vitest-pool-workers` (contract + unit/spy tests, already present from A1–A4), `@cloudflare/workers-types`, and `wrangler` ~4.86 (D1 migrations + local Miniflare D1). No new dependency is introduced — the context-key validation is hand-rolled TS narrowing mirroring A3's `CANONICAL_FIELD_MANIFEST` and A4's `MANIFEST_FIELD_MANIFEST` pattern, and the config cache is plain in-isolate state behind a `D1Reader` port (per Clarification Q3). No schema-validation library and no caching library is named by §5.2/§4.3.2/§9.15; adding either would be a mechanism the spec does not name (R-20).

**Storage**: D1 only. A5 creates the platform's D1 schema — every §7.3 entity — via forward-only additive migrations at `ai-platform/migrations/`. It writes no rows in this slice (the first row writes come from B2 enrollment, C3 journal, and the platform's own control plane). R2, Durable Objects, and the secrets binding are provisioned by A1 and used by later slices; A5 defines no new binding.

**Testing**: `npx vitest run` in three layers (delivery plan §3.11.1 row A5: "Contract + migration + unit (spy)"):
- Contract tests for the context-key vocabulary + shape (`ai-platform/test/context.test.ts`).
- Migration tests applying the migrations to an empty Miniflare D1 and snapshotting schema DDL (`ai-platform/test/migrations.test.ts`, snapshot artifact `ai-platform/schema.snap.sql`).
- Spy-based unit tests for the config cache counting `D1Reader.read` calls (`ai-platform/test/config-cache.test.ts`).

The full suite runs in CI on every change (§13.5, Contract + Pipeline-test rows). No request path is exercised.

**Target Platform**: The `ai-platform/` Cloudflare Worker at the repository root, a sibling of `frontend/` and `backend/` (delivery plan §7.1). No Worker request path is exercised by this slice.

**Project Type**: Additive, non-primary AI gateway component (§14 acknowledgement) — contract surface + the platform's own relational store + an in-isolate cache. No domain logic, no business data, no write path into Supabase.

**Performance Goals**: The cache's I/O budget is the slice's performance contract: zero D1 reads on a warm isolate, exactly one D1 read on a cold isolate, exactly one refetch on TTL expiry (§9.15; spec FR-016/17/18). These are asserted by spy, not measured by timing — coverage is behavioural (delivery plan §3.10). No latency budget applies because A5 is not on the request path.

**Constraints**:
- Context keys name meaning, never storage: `visit.vitals@v1` is correct, `visits_vitals_table@v1` is not (§5.2).
- The published shape is the *only* schema knowledge shared between the two sides (§5.2). Adding an optional key is backward compatible; adding a required key or changing a shape is a new key version and a new capability version (§5.2 Evolution).
- D1 migrations are forward-only, additive, versioned in the repository like the Supabase migrations already are (§13.4 Migrations).
- The config cache is an in-isolate memory map of short TTL, D1 on miss; it is a latency optimization over D1 and **owns nothing** (§4.3.2, §4.4, §9.15). KV as a hot config cache is rejected (§9.15) — no KV binding is introduced.
- There is **no store for live request state** (§4.4, §9.7): the cache holds installation-scoped copies only; no per-request object is introduced.
- A5 is not on the request path and emits no §5.4 taxonomy code; its failure surfaces are contract/migration rejections and a typed failure on a D1 miss (spec §Edge Cases).

**Scale/Scope**: One §4-component group — §4.4 Storage ownership + §4.3.2's config cache (the cache is defined in §4.3.2 and restated as a non-store in §4.4). One context-key module, one config-cache module, one migrations directory, three test files, one contract artifact, one data-model artifact, one quickstart. Roughly 20–24 tasks (below the ~25 ceiling of delivery plan §6.3 / plan stop condition 5).

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- [x] Feature scope still fits small-to-mid-size multi-branch clinics; hospital-scale or
      enterprise-only requirements are explicitly rejected or separately ratified — the config cache exists because clinic scale means tens of installations and a few kilobytes that fit in isolate memory (§9.15); no enterprise-scale machinery (KV, sharding, Analytics Engine) is introduced.
- [x] Design keeps a simple operational model with no microservices, message queues,
      Kubernetes, or custom primary backend service — A5 adds a typed schema, an in-isolate map, and a D1-backed cache; no new service, queue, or orchestration. One Durable Object class exists (provisioned by A1) and A5 adds no per-request state to it.
- [x] Layer ownership is explicit: Flutter handles UI/orchestration, Supabase handles
      backend capabilities, PostgreSQL owns domain integrity, and AI stays isolated — A5 lives wholly in `ai-platform/` and touches neither `frontend/` nor `backend/`. The platform owns its own D1 store separately from the clinic Supabase (§4.4; §3.4; delivery plan §7.1).
- [ ] (intentionally unchecked — see note) Protected writes, validation, permissions, and transactional rules remain enforced
      through PostgreSQL constraints, triggers, RLS, or RPC functions — N/A: A5 defines the platform's own D1 schema, not the clinic Supabase. The clinic Supabase's RLS, RPCs, triggers, and audit_log are untouched; F7 still holds. This row concerns the Supabase/PostgreSQL layer and does not apply to the gateway's own store. Per the §14 acknowledgement registered for band A (delivery plan §7), the Worker is an additive, non-primary component with no domain logic, no business data, and no write path into Supabase.
- [ ] (intentionally unchecked — see note) Security remains authenticated, tenant-scoped, branch-scoped, permission-gated,
      auditable, and soft-delete-preserving — N/A: A5 has no request path, no authn/authz surface, and no tenant scoping at runtime. The `installation`/`installation_key`/`entitlement` entities it *creates* are populated by B2 (enrollment) and read by B3 (guard); A5 creates the schema only. Soft-delete is not a concept the platform's own journal adopts (retention classes are F3, §7.7).
- [ ] (intentionally unchecked — see note) AI actions remain human-approved, have no direct database/backend access, and the
      feature still works in a degraded manual mode when AI is unavailable — N/A: A5 declares no AI action, has no backend access, and has no runtime to degrade. Acceptance behaviour is F2; A5 only creates the `ai_request` table that later carries acceptance-mode columns populated by the manifest (A4) and used by the journal (C3).

The three unchecked boxes are the Supabase/PostgreSQL/authn/acceptance-runtime rows that are structurally inapplicable to a contract + schema + cache slice in the additive gateway. They are not constitution violations; they are recorded here rather than silently dropped, per the §14 acknowledgement that the gateway is non-primary, additive, and holds no domain truth.

## Project Structure

### Documentation (this feature)

```text
specs/019-ai-context-keys-d1-config/
├── plan.md              # This file
├── spec.md              # /ai-platform-specify + /ai-platform-clarify output (already present)
├── quickstart.md        # Written after implementation + verification (this slice's review surface)
├── data-model.md        # The D1 logical model this slice creates (Freezes → D1 entities, §7.3)
├── contracts/
│   ├── context-key-schema.md   # Frozen context-key naming + shape contract (Freezes → wire shape)
│   └── config-cache.md          # Frozen config-cache contract (entities held, TTL/miss behaviour, I/O budget)
└── tasks.md             # /ai-platform-tasks output (NOT created here)
```

`data-model.md` **is** produced — A5 defines every D1 entity of §7.3 (spec §Key Entities). `contracts/` carries two artifacts because A5 freezes two wire-shape contracts (the context key and the config cache) that later slices' **Consumes** must bind to (C2 validator, C3 journal, B3 guard, E3 Resolver). `research.md` is never produced on this platform; the research is `docs/architecture/17-ai-platform.md` (delivery plan §6, plan-phase protocol).

### Source Code (repository root)

```text
ai-platform/
├── migrations/                         # NEW — forward-only D1 migrations (§13.4)
│   └── <YYYYMMDDHHMMSS>_platform_schema.sql   # Creates every §7.3 entity
├── schema.snap.sql                      # NEW — checked-in DDL snapshot (schema_snapshot_matches)
├── src/
│   ├── contracts/
│   │   └── canonical.ts                 # A3 — consumed, unchanged
│   ├── manifest/
│   │   └── index.ts                     # A4 — consumed, unchanged
│   ├── context/                         # NEW — context-key vocabulary + validator (per Clarification Q4)
│   │   └── index.ts                     # exports validateKey, validatePayload, KeyShape
│   └── config-cache/                    # NEW — in-isolate config cache (§4.3.2, §4.4, §9.15)
│       └── index.ts                     # exports ConfigCache, D1Reader port, loadConfig
└── test/
    ├── context.test.ts                  # NEW — T-A5-* context-key contract tests
    ├── migrations.test.ts               # NEW — T-A5-* migration + schema snapshot tests
    └── config-cache.test.ts             # NEW — T-A5-* config-cache spy tests
```

**Structure Decision**: Each new contract surface is one directory mirroring A3's `src/contracts/` and A4's `src/manifest/` one-module-per-contract-of-slice pattern (per Clarification Q4). The `D1Reader` port lives in `src/config-cache/` so the cache reads through exactly one seam whose call count the spy tests assert (per Clarification Q3). Migrations live at `ai-platform/migrations/` and are applied via `wrangler d1 migrations` (per Clarification Q1); the rerun-no-op invariant is Wrangler's own applied-migrations table, not hand-rolled idempotency. The schema snapshot is a checked-in `ai-platform/schema.snap.sql` DDL dump compared after migration (per Clarification Q2). No `wrangler.toml` binding is added — A1 provisioned `DB`, `R2`, and `DO` per environment; A5 uses the existing `DB` binding's local Miniflare D1 in tests. The first published context key is drawn from the §5.2 example keys for the context the first capability requires (Open Decision 1 recommended default); no shipped capability is added here — D1/E4 own capability content.

## Consumes Binding

| **Consumes** entry | Existing module / file bound to | How A5 binds to it |
| --- | --- | --- |
| A4 — capability manifest schema (§5.1, §5.7). The manifest's Context-requirements group is "an ordered list of context keys with `required`/`optional`, shape reference, max size, freshness hint" (and a permitted key set for `conversational`). | `ai-platform/src/manifest/index.ts` (the `Manifest` type and its Context-requirements group, plus `load()`). | A5 publishes the key vocabulary and the first key's `KeyShape` that those manifest `shape reference` strings resolve to. A5 imports the manifest's `ContextRequirements` shape as an opaque reference and does **not** redefine it; the manifest schema is read, not modified (delivery plan §2.3). The "first key's shape is published by this slice" rule (spec FR-004) is the binding point — A4 references a `shape reference` string, A5 is the source that string resolves to. |
| A2 — request-reference format (eight Crockford-base32 symbols, `XXXX-XXXX`). | `ai-platform/src/reference.ts` (`generateReference`, the format and normalisation rules). | A5 stores and indexes the A2 format unchanged on the `ai_request` request-reference column (spec FR-011). A5 imports the `RequestReference` type / format from `reference.ts` for use in the migration's column comment and for any test fixtures; it invents no identifier. The format is read, not modified (delivery plan §2.3). |

Both bound modules exist on disk (verified during plan). No Consumes entry lacks an implementation — stop condition 2 is not triggered.

## Components Touched

| §4 component | What A5 changes | Behaviour added? |
| --- | --- | --- |
| §4.4 Storage ownership | A5 creates the platform's D1 schema (every entity the §4.4 store table enumerates) and adds the in-isolate config cache that §4.4 explicitly names ("Alongside them sits the **config cache**, which is not a store"). | No behaviour. A5 adds the schema (tables, indexes, nullable columns), the cache data structure, and the `D1Reader` port. The storage-ownership *allocation* is already decided in §4.4 — A5 realises it. Row-writing behaviour (journal at stage 9, enrollment in B2) and cache *truth* (D1 is the only authoritative store; the cache owns nothing) are unchanged. |
| §4.3.2 Identity and tenant resolution | Only its **config-cache contract surface**: the in-isolate memory map with short TTL populated from D1 on miss, holding installations, keys, entitlements, grants, kill switches, and the active routing policy. | No. A5 adds the cache module. The identity-resolution **behaviour** — verifier port, audience/expiry/skew, `jti` replay, immutable request principal — is slice B3 (guard). A5 freezes the cache contract that B3 will read through with no D1 read on a warm isolate. |

A5 touches one §4-component group — storage (§4.4) plus the cache that §4.4 explicitly places alongside it and that §4.3.2 names as its read path. The cache is defined in §4.3.2 and restated as a non-store in §4.4; treating them as one group is the seam the architecture itself draws (§4.4: "Alongside them sits the **config cache**, which is not a store"). No second component is touched; no written reason for touching multiple components is needed.

## Files

| Path | Created / Modified | Traces to |
| --- | --- | --- |
| `ai-platform/migrations/<YYYYMMDDHHMMSS>_platform_schema.sql` | Created | FR-008, FR-009, FR-011, FR-012, FR-013 (every §7.3 entity; clean apply to empty DB; request-reference unique index; nullable conversation columns; entity presence) |
| `ai-platform/schema.snap.sql` | Created | FR-010 (schema snapshot pins the migrated schema; per Clarification Q2) |
| `ai-platform/src/context/index.ts` | Created | FR-001, FR-002, FR-003, FR-004, FR-005, FR-006, FR-007 (key format; storage-named rejection; published shape with field names/types/cardinality/units; first key published; payload validates and rejects type/cardinality/units/missing-field; unknown version rejected; backward-compatible evolution rule) |
| `ai-platform/src/config-cache/index.ts` | Created | FR-014, FR-015, FR-016, FR-017, FR-018, FR-019 (in-isolate map, short TTL, D1 on miss; owns nothing; warm zero I/O; cold one D1 read; TTL expiry one refetch; D1 miss typed failure) |
| `ai-platform/test/context.test.ts` | Created | SC-001, SC-002 (T-A5-01 .. T-A5-10: key format/malformed/storage-named/unknown-version, payload valid + four shape violations, first-shape-published) |
| `ai-platform/test/migrations.test.ts` | Created | SC-003, SC-004 (T-A5-11 .. T-A5-16: clean apply, rerun no-op, snapshot matches, per-entity presence, request-reference index unique, conversation columns nullable) |
| `ai-platform/test/config-cache.test.ts` | Created | SC-005, SC-006 (T-A5-17 .. T-A5-23: cold one read, warm zero I/O, TTL one refetch, per-entity-kind zero I/O, D1 miss typed failure, owns-nothing, in-isolate-not-KV, no per-request state) |

No file traces to a Clarification entry — implementation choices are followed (migrations via `wrangler d1 migrations`, snapshot via DDL dump, spy via `D1Reader`, single `context/` module) but never promoted into a requirement (delivery plan §6 "downstream contract"). No `ai-platform/wrangler.toml` change — A1 provisioned the `DB` binding A5's migrations target; no new binding, secret, or namespace is added.

## Test Layout

All named tests from the spec's `### Test plan` are placed in the layers delivery plan §3.11.1 row A5 names ("Contract + migration + unit (spy)"), realised through the §13.5 rows "Contract tests" (CI, on every change) and "Pipeline tests" (here: the migration apply, which is a pipeline-style ordering test against Miniflare D1). Spy-based unit tests for the cache use Clarification Q3's `D1Reader` spy.

| Spec Test plan name | Test id | File | Layer | Asserts (FR / SC) |
| --- | --- | --- | --- | --- |
| `context_key_valid_accepted` | T-A5-01 | `test/context.test.ts` | Contract | FR-001 / SC-001 — `domain.concept@vN` accepted. |
| `context_key_malformed_format_rejected` | T-A5-02 | `test/context.test.ts` | Contract | FR-001 / SC-001 — malformed key rejected. |
| `context_key_storage_named_rejected` | T-A5-03 | `test/context.test.ts` | Contract | FR-002 / SC-001 — `visits_vitals_table@v1`, `get_visit_vitals_rpc@v1`, `visits.vitals_view@v1` rejected as `storage_named_key`. |
| `context_key_unknown_version_rejected` | T-A5-04 | `test/context.test.ts` | Contract | FR-006 / SC-001 — unpublished version of a known concept rejected as `unknown_version`. |
| `context_key_unknown_key_rejected` | T-A5-04b | `test/context.test.ts` | Contract | FR-006 / SC-001 — well-formed key outside vocabulary rejected as `unknown_key`. |
| `context_key_payload_validates` | T-A5-05 | `test/context.test.ts` | Contract | FR-005 / SC-002 — conforming payload passes. |
| `context_key_shape_violation_type` | T-A5-06 | `test/context.test.ts` | Contract | FR-005 / SC-002 — type violation rejected. |
| `context_key_shape_violation_cardinality` | T-A5-07 | `test/context.test.ts` | Contract | FR-005 / SC-002 — cardinality violation rejected. |
| `context_key_shape_violation_units` | T-A5-08 | `test/context.test.ts` | Contract | FR-005 / SC-002 — units violation rejected. |
| `context_key_shape_violation_missing_field` | T-A5-09 | `test/context.test.ts` | Contract | FR-005 / SC-002 — missing-field violation rejected. |
| `first_context_key_shape_published` | T-A5-10 | `test/context.test.ts` | Contract | FR-004 / SC-002 — first key's shape (the §5.2 example key the OD-1 first capability requires) is published with field names, types, cardinality, units. |
| `migrations_apply_cleanly_to_empty_db` | T-A5-11 | `test/migrations.test.ts` | Migration (pipeline) | FR-008/FR-009 / SC-003 — forward-only migrations create every §7.3 entity on empty Miniflare D1. |
| `migrations_rerun_is_noop` | T-A5-12 | `test/migrations.test.ts` | Migration | FR-009 / SC-003 — re-applying is a no-op (enforced by Wrangler's applied-migrations table per Clarification Q1). |
| `schema_snapshot_matches` | T-A5-13 | `test/migrations.test.ts` | Contract (snapshot) | FR-010 / SC-003 — post-migration DDL dump equals `ai-platform/schema.snap.sql` (per Clarification Q2). |
| `entity_presence_<entity>` (one per §7.3 entity: `installation`, `installation_key`, `entitlement`, `capability_grant`, `routing_policy`, `ai_request`, `ai_attempt`, `usage_event`, `usage_rollup`, `platform_counter`, `control_audit`) | T-A5-14a .. T-A5-14k | `test/migrations.test.ts` | Migration | FR-013 / SC-003 — each entity present after migration. |
| `request_reference_index_exists_and_unique` | T-A5-15 | `test/migrations.test.ts` | Migration | FR-011 / SC-004 — `ai_request` request-reference index is unique; column accepts and returns the A2 format via insert/select. |
| `idempotency_key_not_uniquely_indexed_on_d1` | T-A5-15b | `test/migrations.test.ts` | Migration | Out of scope — no D1 unique index on `(installation_id, idempotency_key)`; C3 Quota DO owns idempotency (§4.3.3). |
| `conversation_id_and_turn_ordinal_nullable` | T-A5-16 | `test/migrations.test.ts` | Migration | FR-012 / SC-004 — both columns nullable. |
| `config_cache_cold_isolate_one_d1_read` | T-A5-17 | `test/config-cache.test.ts` | Unit (spy) | FR-017 / SC-005 — cold isolate performs exactly one `.read` (per Clarification Q3). |
| `config_cache_warm_isolate_zero_io` | T-A5-18 | `test/config-cache.test.ts` | Unit (spy) | FR-016 / SC-005 — warm isolate performs zero `.read`. |
| `config_cache_ttl_expiry_one_refetch` | T-A5-19 | `test/config-cache.test.ts` | Unit (spy) | FR-018 / SC-005 — TTL expiry triggers exactly one refetch. |
| `config_cache_entity_kind_<kind>` (one per kind: installations, keys, entitlements, grants, kill switches, active routing policy) | T-A5-20a .. T-A5-20f | `test/config-cache.test.ts` | Unit (spy) | FR-016 / SC-005 — each cached kind answered from memory when warm. |
| `config_cache_d1_miss_typed_failure` | T-A5-21 | `test/config-cache.test.ts` | Unit (spy) | FR-019 / SC-006 — D1 miss surfaces typed failure, not an empty cached entry. |
| `config_cache_cold_load_single_flight` | T-A5-21b | `test/config-cache.test.ts` | Unit (spy) | Concurrent cold loads for the same `(kind, key)` coalesce to exactly one `reader.read`. |
| `config_cache_owns_nothing` | T-A5-22 | `test/config-cache.test.ts` | Unit (spy) | FR-015 / SC-006 — cache holds copies; a D1 update changes truth without a cache flush (§4.4). |
| `config_cache_uses_in_isolate_memory_not_kv` | T-A5-23 | `test/config-cache.test.ts` | Contract | FR-014 — no KV binding introduced; cache is in-isolate memory backed by D1 on miss (§9.15 rejected). |
| `no_per_request_state_introduced` | T-A5-24 | `test/config-cache.test.ts` | Unit | FR-015 — the cache exposes no per-request handle; only installation-scoped copies (§4.4, §9.7). |

All 24 named tests place cleanly in a §13.5 layer. No named test is left unplaced (stop condition 3 not triggered). Coverage additions from §3.10 (every inherited prohibition) are T-A5-22, T-A5-23, T-A5-24; every boundary is covered by the per-entity and index/nullable cases; A5 emits no §5.4 runtime code so there are no error-code cases (spec §Edge Cases).

## Sequencing

1. **`ai-platform/migrations/<YYYYMMDDHHMMSS>_platform_schema.sql`** — write the forward-only migration creating every §7.3 entity with the §7.3 key fields, the uniquely-indexed request-reference column on `ai_request` (storing the A2 format unchanged), and the nullable `conversation_id` / `turn_ordinal` columns. Filed first because the migration schema and the config-cache's D1-backed entities share the same §7.3 shapes; the context-key module is independent of it.
2. **`ai-platform/schema.snap.sql`** — generate the post-migration DDL snapshot from the Miniflare D1 (per Clarification Q2) and check it in; the `schema_snapshot_matches` test compares against it.
3. **`ai-platform/src/context/index.ts`** — define the `domain.concept@vN` format check, the storage-named-key rejection (a denylist of storage patterns: `*_table`, `get_*_rpc`, and `_v` suffixed storage artefacts — narrow and named by §5.2's examples), the `KeyShape` type (fields, types, cardinality, units), the first key's published shape (the §5.2 example key the OD-1 first capability requires), `validateKey(k)`, and `validatePayload(k, payload)`. The backward-compatible-evolution rule (FR-007) is enforced by the version-suffix being mandatory — adding an optional key is a new `@vN+1`; a required key or shape change forces a new key version (§5.2 Evolution). The overlap *behaviour* is out of scope (band J).
4. **`ai-platform/test/context.test.ts`** — write the inline key/payload fixtures and the T-A5-01 .. T-A5-10 tests alongside the module's matching branches (perClarification Q4's single-module shape); tests land with or before each implementation branch, never after.
5. **`ai-platform/src/config-cache/index.ts`** — define the `D1Reader` port (a `read(key)` seam), the `ConfigCache` with a short TTL map per entity kind, `loadConfig(reader, kind, key)` that returns a cached entry on hit, performs exactly one `reader.read` on miss and on TTL expiry, and surfaces a typed failure (not an empty cached entry) on a D1 miss. The cache owns nothing — it returns copies; D1 is the only authoritative store (§4.4). In-isolate memory only; no KV binding (§9.15). The TTL value is a plan-time constant left to the implement phase within the "short" constraint (§4.3.2) — not a configuration surface (R-20).
6. **`ai-platform/test/config-cache.test.ts`** — write the `D1Reader` spy (per Clarification Q3) and the T-A5-17 .. T-A5-24 tests; the spy asserts `.read` call count (0 warm, 1 cold, 1 on TTL expiry) and returns canned rows or a miss literal. `no_per_request_state_introduced` asserts the module exports no per-request handle.
7. **`ai-platform/test/migrations.test.ts`** — use `wrangler d1 migrations apply --local` against an empty Miniflare D1 (per Clarification Q1); assert clean apply, rerun no-op, snapshot match, per-entity presence, unique request-reference index, nullable conversation columns. T-A5-13 reads `ai-platform/schema.snap.sql`.
8. **Run `npx vitest run test/context.test.ts test/migrations.test.ts test/config-cache.test.ts`** — all T-A5-* tests green. The prior band-A suites (`canonical.test.ts`, `taxonomy.test.ts`, `reference.test.ts`, `trace.test.ts`, `error-body.test.ts`, `log-redaction.test.ts`, `manifest.test.ts`, `health.test.ts`, `env-deploys.test.ts`) remain green (checkpoint rule: every prior suite green, §3.10).
9. **`specs/019-ai-context-keys-d1-config/data-model.md`** — write the D1 logical model (the §7.3 entities, key fields, the request-reference unique index, the nullable `conversation_id` / `turn_ordinal` columns A14 introduces, retention class pointers to A10/F3) so C3/H3/F3 bind to an artifact, not to prose.
10. **`specs/019-ai-context-keys-d1-config/contracts/context-key-schema.md`** — freeze the context-key naming rule, the published-shape contract, the first key's shape, and the backward-compatible evolution rule, so C2 (validator), C3 (journal produces shape evidence), and E3 (Resolver returns the published shape) bind to an artifact.
11. **`specs/019-ai-context-keys-d1-config/contracts/config-cache.md`** — freeze the config-cache contract (the six cached entity kinds, short TTL, one-D1-read-on-miss, typed failure on miss, owns-nothing, in-isolate-not-KV) so B3 (guard) binds to an artifact when it consumes the cache with no D1 read on a warm isolate.
12. **`specs/019-ai-context-keys-d1-config/quickstart.md`** — fill from `.specify/templates/ai-platform-quickstart-template.md`: what was implemented (context-key vocabulary + first shape, D1 schema migrations, config cache), files to review (the three `src/` modules, the migration, the snapshot, the three test files), how to run the slice's tests (`npx vitest run test/context.test.ts test/migrations.test.ts test/config-cache.test.ts`), how to inspect the changes (`wrangler d1 migrations list`, read the schema snapshot, read the contract artifacts). No Manual validation section — CI is the only verification path (template: "Omit this section when CI is the only verification path").

Tests land alongside or before their implementation branches (steps 3–4 interleave for context, steps 5–6 interleave for the cache, the migration snapshot in step 2 precedes the migration tests in step 7); no test is written after its implementation. The Documentation artifacts (steps 9–12) are written only after the suite is green — the plan names them here, the implement phase fills them in.

## Complexity Tracking

> Not filled — no Constitution Check violation requires justification. The three unchecked Constitution boxes are recorded above as structurally inapplicable to a contract + schema + cache slice in the additive gateway (per the §14 acknowledgement), not as violations.