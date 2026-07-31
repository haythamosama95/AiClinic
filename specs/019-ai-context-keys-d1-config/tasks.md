---

description: "Task list for AI platform slice A5 — Context key vocabulary, D1 schema, and config cache"
---

# Tasks: Context key vocabulary, D1 schema, and config cache (A5)

**Input**: Design documents from `/specs/019-ai-context-keys-d1-config/`

**Prerequisites**: `plan.md` (required), `spec.md` (required). This slice's `data-model.md`, `contracts/context-key-schema.md`, `contracts/config-cache.md`, and `quickstart.md` are produced by this slice's Documentation phase; none of `research.md` or prior-slice docs are needed — the research is `docs/architecture/17-ai-platform.md` (never re-produced on this platform).

**Tests**: Mandatory, not optional (delivery plan §3.10 overrides the template). Every named test in the spec's Test plan is a task, written to fail before the implementation exists.

**Organization**: One slice, one user story (US1). No multi-story phases, no Foundational phase (prerequisites are the already-merged A4 and A2 named in the plan's Consumes Binding), no Polish phase (R-20).

**Sizing**: 35 tasks. A5 is a merged slice (delivery plan §2.6) whose Test plan is the union of the merged rows' case lists; 25–40 tasks is the correctly-sized range (§2.5) and ~40 is the §6.3 stop. 35 sits within both.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies). Test tasks that share a single file run sequentially in the order given; the first task of each of the three test files is `[P]` relative to the first task of the others.
- **[Story]**: `US1` — the slice's one user story.
- Exact file paths are in every description.

## Path Conventions

- **Flutter desktop app**: `frontend/lib/`, `frontend/test/` — not touched by this slice.
- **Supabase backend**: `backend/migrations/`, `backend/functions/`, `backend/tests/` — not touched by this slice.
- **AI platform Worker**: `ai-platform/src/`, `ai-platform/migrations/`, `ai-platform/test/` — this slice lives here.

---

## Phase 1: Tests

**Purpose**: Write every named test from the spec's Test plan into its three files (`ai-platform/test/context.test.ts`, `ai-platform/test/migrations.test.ts`, `ai-platform/test/config-cache.test.ts`), each failing before the matching implementation exists. The first task of each file establishes that file's fixture/spy substrate and is `[P]` relative to the first task of the other two files (three independent files). The modules under test (`../src/context`, `../src/config-cache`) and the migration do not exist yet, so each file fails to compile or to apply — the intended red state.

### 1.1 Context keys — `ai-platform/test/context.test.ts`

- [X] T001 [P] [US1] Create `ai-platform/test/context.test.ts` with the inline fixture layer: a `validPayload()` factory conforming to the first key's shape (field names, types, cardinality, units — per Clarification Q4's single-module shape), per-violation mutators (`withTypeViolation`, `withCardinalityViolation`, `withUnitsViolation`, `withMissingField`), and the import of `validateKey`, `validatePayload`, and the `KeyShape` type from `../src/context`. File fails to compile (module absent). Proves the fixture substrate for every later context-key test and for SC-001/SC-002. Satisfies the plan's Test Layout file for `T-A5-01..10`.
- [X] T002 [US1] Add `T-A5-01 context_key_valid_accepted` to `ai-platform/test/context.test.ts`: `validateKey("visit.vitals@v1")` (and the other §5.2 example keys) returns ok. Satisfies FR-001 / SC-001.
- [X] T003 [US1] Add `T-A5-02 context_key_malformed_format_rejected` to `ai-platform/test/context.test.ts`: keys missing the `@vN` suffix or the `domain.concept` shape are rejected by `validateKey`. Satisfies FR-001 / SC-001.
- [X] T004 [US1] Add `T-A5-03 context_key_storage_named_rejected` to `ai-platform/test/context.test.ts`: `validateKey("visits_vitals_table@v1")` and `validateKey("get_visit_vitals_rpc@v1")` are rejected — a key named after storage rather than meaning is rejected even when the referenced artefact would exist. Satisfies FR-002 / SC-001.
- [X] T005 [US1] Add `T-A5-04 context_key_unknown_version_rejected` to `ai-platform/test/context.test.ts`: `validateKey("visit.vitals@v9")` for an unpublished version is rejected. Satisfies FR-006 / SC-001.
- [X] T006 [US1] Add `T-A5-05 context_key_payload_validates` to `ai-platform/test/context.test.ts`: `validatePayload(key, validPayload())` returns ok for the first key's published shape. Satisfies FR-005 / SC-002.
- [X] T007 [US1] Add `T-A5-06 context_key_shape_violation_type` to `ai-platform/test/context.test.ts`: `validatePayload(key, withTypeViolation(validPayload()))` rejects with a type error. Satisfies FR-005 / SC-002.
- [X] T008 [US1] Add `T-A5-07 context_key_shape_violation_cardinality` to `ai-platform/test/context.test.ts`: `validatePayload(key, withCardinalityViolation(...))` rejects with a cardinality error. Satisfies FR-005 / SC-002.
- [X] T009 [US1] Add `T-A5-08 context_key_shape_violation_units` to `ai-platform/test/context.test.ts`: `validatePayload(key, withUnitsViolation(...))` rejects with a units error. Satisfies FR-005 / SC-002.
- [X] T010 [US1] Add `T-A5-09 context_key_shape_violation_missing_field` to `ai-platform/test/context.test.ts`: `validatePayload(key, withMissingField(...))` rejects naming the missing field. Satisfies FR-005 / SC-002.
- [X] T011 [US1] Add `T-A5-10 first_context_key_shape_published` to `ai-platform/test/context.test.ts`: the first key's exported `KeyShape` declares field names, types, cardinality, and units — asserted over the published shape object, for the context the OD-1 first capability requires. Satisfies FR-004 / SC-002.

### 1.2 D1 schema — `ai-platform/test/migrations.test.ts`

- [X] T012 [P] [US1] Create `ai-platform/test/migrations.test.ts` with the Miniflare D1 harness: a per-test empty local D1 (the existing `DB` binding provisioned by A1's `wrangler.toml`), `wrangler d1 migrations apply --local` invocation (per Clarification Q1), and the import of the §7.3 entity list. File fails (no migration exists). Proves the substrate for `T-A5-11..16`.
- [X] T013 [US1] Add `T-A5-11 migrations_apply_cleanly_to_empty_db` to `ai-platform/test/migrations.test.ts`: applying the migration to an empty D1 succeeds and creates every §7.3 entity. Satisfies FR-008/FR-009 / SC-003.
- [X] T014 [US1] Add `T-A5-12 migrations_rerun_is_noop` to `ai-platform/test/migrations.test.ts`: re-applying the migration is a no-op (asserted via Wrangler's own applied-migrations table, per Clarification Q1). Satisfies FR-009 / SC-003.
- [X] T015 [US1] Add `T-A5-13 schema_snapshot_matches` to `ai-platform/test/migrations.test.ts`: the post-migration `CREATE TABLE` DDL dump equals the checked-in `ai-platform/schema.snap.sql` (per Clarification Q2). Satisfies FR-010 / SC-003.
- [X] T016 [US1] Add `T-A5-14 entity_presence_<entity>` to `ai-platform/test/migrations.test.ts`: one `describe` iterating the eleven §7.3 entities (`installation`, `installation_key`, `entitlement`, `capability_grant`, `routing_policy`, `ai_request`, `ai_attempt`, `usage_event`, `usage_rollup`, `platform_counter`, `control_audit`); for each, the table exists after migration. Satisfies FR-013 / SC-003 (one case per entity, eleven cases).
- [X] T017 [US1] Add `T-A5-15 request_reference_index_exists_and_unique` to `ai-platform/test/migrations.test.ts`: the `ai_request` request-reference index exists and is unique, and the column stores the A2 format unchanged (asserted via the index DDL, importing `RequestReference` from `../src/reference`). Satisfies FR-011 / SC-004.
- [X] T018 [US1] Add `T-A5-16 conversation_id_and_turn_ordinal_nullable` to `ai-platform/test/migrations.test.ts`: `ai_request` columns `conversation_id` and `turn_ordinal` are nullable (asserted via the column DDL). Satisfies FR-012 / SC-004.

### 1.3 Config cache — `ai-platform/test/config-cache.test.ts`

- [X] T019 [P] [US1] Create `ai-platform/test/config-cache.test.ts` with the `D1Reader` spy substrate (per Clarification Q3): a `makeReader(rows | "miss")` factory returning a spy whose `.read(key)` call count is asserted, plus the import of `ConfigCache`, `loadConfig`, and the `D1Reader` port from `../src/config-cache`. File fails to compile (module absent). Proves the spy substrate for `T-A5-17..24` and for SC-005/SC-006.
- [X] T020 [US1] Add `T-A5-17 config_cache_cold_isolate_one_d1_read` to `ai-platform/test/config-cache.test.ts`: a cold `ConfigCache` calling `loadConfig` for one entity kind performs exactly one `reader.read` (spy call count === 1). Satisfies FR-017 / SC-005.
- [X] T021 [US1] Add `T-A5-18 config_cache_warm_isolate_zero_io` to `ai-platform/test/config-cache.test.ts`: a warm `ConfigCache` (already loaded) answering the same kind performs zero `reader.read` (spy call count === 0). Satisfies FR-016 / SC-005.
- [X] T022 [US1] Add `T-A5-19 config_cache_ttl_expiry_one_refetch` to `ai-platform/test/config-cache.test.ts`: after TTL expiry, consulting a previously-cached entry triggers exactly one `reader.read` (spy call count === 1). Satisfies FR-018 / SC-005.
- [X] T023 [US1] Add `T-A5-20 config_cache_entity_kind_<kind>` to `ai-platform/test/config-cache.test.ts`: one `describe` iterating the six cached kinds (installations, keys, entitlements, grants, kill switches, active routing policy); for each, a warm isolate answers from memory with zero `reader.read`. Satisfies FR-016 / SC-005 (one case per kind, six cases).
- [X] T024 [US1] Add `T-A5-21 config_cache_d1_miss_typed_failure` to `ai-platform/test/config-cache.test.ts`: a `reader` returning `"miss"` makes `loadConfig` throw a typed failure, and no empty entry is cached (a follow-up consult with a populated reader still performs one read). Satisfies FR-019 / SC-006.
- [X] T025 [US1] Add `T-A5-22 config_cache_owns_nothing` to `ai-platform/test/config-cache.test.ts`: a D1 update is observable through the cache after TTL expiry without a cache flush — the cache holds copies and is not authoritative (asserted by changing the spy's returned row and confirming the next post-TTL read sees the new value). Satisfies FR-015 / SC-006.
- [X] T026 [US1] Add `T-A5-23 config_cache_uses_in_isolate_memory_not_kv` to `ai-platform/test/config-cache.test.ts`: the `../src/config-cache` module's export surface and the Worker's bindings include no KV binding — asserted over the module exports and `ai-platform/wrangler.toml` (§9.15 rejected). Satisfies FR-014.
- [X] T027 [US1] Add `T-A5-24 no_per_request_state_introduced` to `ai-platform/test/config-cache.test.ts`: the `../src/config-cache` module exports no per-request handle; only installation-scoped `loadConfig` and the `ConfigCache`/`D1Reader` types (§4.4 "There is no store for live request state"; §9.7). Satisfies FR-015.

**Checkpoint**: all three test files exist and every `T-A5-*` block fails (modules/migration absent). Red state confirmed.

---

## Phase 2: Implementation

**Purpose**: The three implementation units named in the plan's Files section (the migration + snapshot are one unit — the snapshot is generated by running the migration, per Clarification Q2). Tests turn green as each lands. Each task is `[P]` (three different files/directories, no shared dependency).

- [X] T028 [P] [US1] Create `ai-platform/migrations/<YYYYMMDDHHMMSS>_platform_schema.sql`: the forward-only additive migration (§13.4) creating every §7.3 entity with its key fields, the uniquely-indexed request-reference column on `ai_request` (storing the A2 format unchanged — imported from `../src/reference` conceptually, encoded as a column comment referencing the format), and the nullable `conversation_id` / `turn_ordinal` columns (A14). Then generate `ai-platform/schema.snap.sql` by applying the migration to an empty Miniflare D1 and dumping the `CREATE TABLE` DDL (per Clarification Q2). Satisfies FR-008, FR-009, FR-011, FR-012, FR-013. Turns T-A5-11..16 green.
- [X] T029 [P] [US1] Create `ai-platform/src/context/index.ts` (per Clarification Q4): the `domain.concept@vN` format check, the storage-named-key rejection (a narrow named denylist mirroring §5.2's `*_table` / `get_*_rpc` examples), the `KeyShape` type (field names, types, cardinality, units), the first key's published shape (the §5.2 example key the OD-1 first capability requires), `validateKey(k)`, and `validatePayload(k, payload)`. The backward-compatible-evolution rule (FR-007) is enforced by the mandatory `@vN` suffix. Hand-rolled TS narrowing mirroring A3's `CANONICAL_FIELD_MANIFEST` and A4's `MANIFEST_FIELD_MANIFEST` — no schema-validation library (R-20). Satisfies FR-001..FR-007. Turns T-A5-01..10 green.
- [X] T030 [P] [US1] Create `ai-platform/src/config-cache/index.ts`: the `D1Reader` port (`read(key)` seam, per Clarification Q3), the `ConfigCache` with a short-TTL map per entity kind, and `loadConfig(reader, kind, key)` returning a cached entry on hit, performing exactly one `reader.read` on miss and on TTL expiry, and surfacing a typed failure (not an empty cached entry) on a D1 miss. In-isolate memory only; no KV binding (§9.15). The cache owns nothing — it returns copies (§4.4). The TTL is a plan-time `const` within the "short" constraint (§4.3.2) — not a configuration surface (R-20). Satisfies FR-014..FR-019. Turns T-A5-17..24 green.

**Checkpoint**: `npx vitest run test/context.test.ts test/migrations.test.ts test/config-cache.test.ts` green; all `T-A5-*` pass.

---

## Phase 3: Verification

**Purpose**: Confirm this slice's suite is green and every prior band-A suite is still green (delivery plan §3.10: a checkpoint requires every prior suite green, not just the latest).

- [X] T031 [US1] Run `npx vitest run` from `ai-platform/` and assert all suites green: this slice's `context.test.ts`, `migrations.test.ts`, `config-cache.test.ts` plus the prior band-A suites — `canonical.test.ts` (A3), `manifest.test.ts` (A4), `taxonomy.test.ts` (A2), `reference.test.ts` (A2), `error-body.test.ts` (A2), `trace.test.ts` (A2), `log-redaction.test.ts` (A2), `health.test.ts` (A1), `env-deploys.test.ts` (A1). No new test file is added here; this is the full-suite regression run. Proves the Verification success criterion.

**Checkpoint**: Full platform suite green. No regressions introduced into A1–A4.

---

## Phase 4: Documentation

**Purpose**: The documentation artifacts the plan names. Written only after the suite is green. All four touch different files and are `[P]`.

- [X] T032 [P] [US1] Create `specs/019-ai-context-keys-d1-config/data-model.md` documenting the D1 logical model this slice creates: the §7.3 entities and key fields, the `ai_request` request-reference unique index (storing the A2 format), the nullable `conversation_id` / `turn_ordinal` columns A14 introduces, and retention-class pointers to A10/F3. Later slices (C3 journal, H3 conversational journaling, F3 support lookup) bind to this artifact, not to prose. Satisfies the plan's `data-model.md` requirement (this slice defines D1 entities).
- [X] T033 [P] [US1] Create `specs/019-ai-context-keys-d1-config/contracts/context-key-schema.md` freezing the context-key naming rule (`domain.concept@vN`, storage-named rejection), the published-shape contract (field names, types, cardinality, units), the first key's shape, and the backward-compatible evolution rule (optional key = new `@vN+1`; required key or shape change = new key version and new capability version). Later slices (C2 validator, C3 journal, E3 Resolver) bind to this artifact. Satisfies the plan's `contracts/` requirement for a Freezes entry with a wire shape.
- [X] T034 [P] [US1] Create `specs/019-ai-context-keys-d1-config/contracts/config-cache.md` freezing the config-cache contract: the six cached entity kinds, short TTL, exactly one D1 read on miss, exactly one refetch on TTL expiry, typed failure on a D1 miss, owns-nothing, and in-isolate-memory-not-KV. Later slice B3 (guard) binds to this artifact when it consumes the cache with no D1 read on a warm isolate. Satisfies the plan's `contracts/` requirement for a Freezes entry with a wire shape.
- [X] T035 [P] [US1] Create `specs/019-ai-context-keys-d1-config/quickstart.md` from `.specify/templates/ai-platform-quickstart-template.md`, scoped to this slice only: what was implemented (context-key vocabulary + first shape, D1 schema migrations, config cache), the files to review (`ai-platform/src/context/index.ts`, `ai-platform/src/config-cache/index.ts`, `ai-platform/migrations/`, `ai-platform/schema.snap.sql`, the three test files), the slice-only test command (`npx vitest run test/context.test.ts test/migrations.test.ts test/config-cache.test.ts`), and how to inspect the changes (`wrangler d1 migrations list`, read `schema.snap.sql`, read the two contract artifacts and `data-model.md`). No Manual validation section — CI is the only verification path for this contract/schema/cache slice (template: omit when CI is the only path). Explicitly excludes prior-slice files, combined test counts, and prior-slice regression commands.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Tests (Phase 1)**: No dependencies — T001/T012/T019 each establish one file's fixture/spy substrate and are `[P]` relative to each other (three independent files); the remaining test tasks in each file run sequentially on top of their file's substrate. No test depends on another file's tests.
- **Implementation (Phase 2)**: Depends on the Tests phase existing (red state confirmed). T028/T029/T030 touch three different files/directories and are `[P]`; each turns its corresponding test file green independently.
- **Verification (Phase 3)**: Depends on Implementation green (all three test files passing).
- **Documentation (Phase 4)**: Depends on Verification green; all four tasks are `[P]` (different files).

### Within the Slice

- Tests are written and confirmed failing before any implementation.
- The fixture/spy substrate (T001, T012, T019) is established before any `T-A5-*` block is added in that file.
- The migration + snapshot (T028) lands before the migration tests can pass; the context module (T029) before the context tests; the config-cache module (T030) before the cache tests.
- The quickstart (T035) is written last and cites only this slice's files and commands.

### Parallel Opportunities

- T001, T012, T019 (Phase 1) — the three test files' substrate tasks — are `[P]` (independent files).
- T028, T029, T030 (Phase 2) — migration, context module, config-cache module — are `[P]` (independent files/directories, no shared dependency).
- T032, T033, T034, T035 (Phase 4) — the four documentation artifacts — are `[P]` (independent files).
- No other parallelism within a file: test tasks sharing one file run sequentially in the order listed.

---

## Notes

- Tests are mandatory (delivery plan §3.10 overrides the template's "Tests are OPTIONAL" note).
- One slice, one story (US1) — the template's multi-story, Foundational, and Polish phases are deleted, not left empty.
- Every task traces to an `FR-###` from `spec.md` and to a named test from its Test plan; nothing is added that the spec/plan do not name.
- No new dependency is introduced — the context-key validator and config cache are hand-rolled TS mirroring A3/A4's data-manifest pattern, and the cache uses an injected `D1Reader` port per Clarification Q3 (R-20).
- Every spy case is its own task (T020–T027): asserting a call count or an absence is separate work from asserting an outcome (delivery plan §3.10).
- Sizing: 35 tasks. A5 is a merged slice (delivery plan §2.6) whose Test plan is the union of the merged rows' case lists; 25–40 is the correctly-sized range (§2.5) and ~40 is the §6.3 stop.