---

description: "Task list for AI platform slice A4 — Capability manifest schema and loader"
---

# Tasks: Capability manifest schema and loader (A4)

**Input**: Design documents from `/specs/018-ai-capability-manifest/`

**Prerequisites**: `plan.md` (required), `spec.md` (required). `contracts/` and `quickstart.md` are produced by this slice's Documentation phase; none of `data-model.md`, `research.md`, or prior-slice docs are needed — A4 defines no D1 entity and the research is `docs/architecture/ai-platform/01-ai-platform.md` (never re-produced on this platform).

**Tests**: Mandatory, not optional (delivery plan §3.10 overrides the template). Every named test in the spec's Test plan is a task, written to fail before the implementation exists.

**Organization**: One slice, one user story (US1). No multi-story phases, no Foundational phase (prerequisites are the already-merged A3), no Polish phase (R-20).

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies). All test tasks below touch the same single file `ai-platform/test/manifest.test.ts`, so none are `[P]`; they run sequentially in the order given.
- **[Story]**: `US1` — the slice's one user story.
- Exact file paths are in every description.

## Path Conventions

- **Flutter desktop app**: `frontend/lib/`, `frontend/test/` — not touched by this slice.
- **Supabase backend**: `backend/migrations/`, `backend/functions/`, `backend/tests/` — not touched by this slice.
- **AI platform Worker**: `ai-platform/src/`, `ai-platform/migrations/`, `ai-platform/test/` — this slice lives here.

---

## Phase 1: Tests

**Purpose**: Write every named test from the spec's Test plan into `ai-platform/test/manifest.test.ts`, each failing before the matching implementation exists. A single inline fixture builder (a valid-manifest factory plus per-group mutation helpers) is established in the first task and reused by the rest; the module under test (`../src/manifest`) does not exist yet, so the whole file fails to compile — the intended red state.

- [X] T001 [US1] Create `ai-platform/test/manifest.test.ts` with the inline fixture layer: a `validManifest()` factory producing a manifest declaring all ten §5.1 field groups, plus per-group `omitGroup(manifest, group)` / `malformGroup(manifest, group)` helpers, and the import of `load`, `hashManifest`, `verifyPublishedRegistry`, and the `Manifest` type from `../src/manifest`. File fails to compile (module absent). Proves the fixture substrate for every later test and for SC-001/SC-002.
- [X] T002 [US1] Add `T-A4-01 manifest_loads_all_ten_groups` to `ai-platform/test/manifest.test.ts`: `load(validManifest())` returns a typed `Manifest` whose ten field groups equal the fixture. Satisfies FR-001 / SC-001.
- [X] T003 [US1] Add `T-A4-02..11 manifest_missing_or_malformed_group_<group>` to `ai-platform/test/manifest.test.ts`: one `describe` iterating the ten groups (Identity, Access, Interaction, Input, Context requirements, Prompt binding, Output, Routing, Economics, Governance); for each, `load(omitGroup(...))` and `load(malformGroup(...))` throw, naming the offending group. Satisfies FR-001/FR-003 / SC-002 (one case per group, ten cases).
- [X] T004 [US1] Add `T-A4-12 in_place_edit_of_published_version_fails_build` to `ai-platform/test/manifest.test.ts`: `verifyPublishedRegistry([{capabilityId, version, hash: hashManifest(valid)}], { [id@v]: hashManifest(edited) })` rejects an on-disk manifest whose hash differs from the registry entry, and accepts the prior hash. Satisfies FR-002/FR-004 / SC-003.
- [X] T005 [US1] Add `T-A4-13 omitted_interaction_mode_defaults_to_single_shot` to `ai-platform/test/manifest.test.ts`: a manifest with `interactionMode` absent loads with `interactionMode === "single_shot"`. Satisfies FR-005 / SC-004.
- [X] T006 [US1] Add `T-A4-14 conversational_fields_rejected_on_single_shot` to `ai-platform/test/manifest.test.ts`: a `single_shot` manifest carrying any of max history turns / max context rounds per turn / transcript size limit is rejected by `load()`. Satisfies FR-006 / SC-005.
- [X] T007 [US1] Add `T-A4-15 manifest_is_data_not_code` to `ai-platform/test/manifest.test.ts`: the `../src/manifest` module's export surface contains only data/type declarations and `load`/`hashManifest`/`verifyPublishedRegistry` — no pipeline wiring, no client entry point (asserted over `Object.keys(module)` and the exported names). Satisfies FR-007 / SC-006.
- [X] T008 [US1] Add `T-A4-16 manifest_never_names_provider_or_model` to `ai-platform/test/manifest.test.ts`: a manifest whose Routing group contains a provider name or model identifier string is rejected by `load()`. Satisfies FR-008 / SC-006.
- [X] T009 [US1] Add `T-A4-17 interaction_mode_fixed_for_life_of_version` to `ai-platform/test/manifest.test.ts`: the loaded `Manifest`'s `interactionMode` field is typed read-only (a compile-time assertion via a `// @ts-expectpect` on assignment) and the loader does not mutate it; combined with T-A4-12 this covers FR-002 / SC-003.

**Checkpoint**: `manifest.test.ts` exists and every `T-A4-*` block fails (module absent). Red state confirmed.

---

## Phase 2: Implementation

**Purpose**: The two implementation units named in the plan's Files section. Tests turn green as each lands.

- [X] T010 [US1] Create `ai-platform/src/manifest/index.ts`: the ten-field-group schema as data (mirroring A3's `CANONICAL_FIELD_MANIFEST` pattern — no schema-validation library, hand-rolled TS narrowing, R-20), the `Manifest` type with `interactionMode` fixed read-only, the internal `validate()`, and `load(json): Manifest` applying (i) the `interaction_mode` default of `single_shot` when absent, (ii) the conversational-only-field rejection on `single_shot`, (iii) the never-names-provider/model check over the Routing group, (iv) per-group presence and shape checks. Satisfies FR-001, FR-002, FR-005, FR-006, FR-007, FR-008, FR-009, FR-010. Turns T-A4-01, T-A4-02..11, T-A4-13, T-A4-14, T-A4-15, T-A4-16, T-A4-17 green.
- [X] T011 [US1] Add `hashManifest(json): string` and `verifyPublishedRegistry(entries, registry)` to `ai-platform/src/manifest/index.ts`: a stable content hash over the canonical manifest encoding, and a registry check that fails when an on-disk manifest's hash differs from its published `(capability_id, version)` entry. Satisfies FR-002/FR-004. Turns T-A4-12 green.

**Checkpoint**: `npx vitest run test/manifest.test.ts` green; all `T-A4-*` pass.

---

## Phase 3: Verification

**Purpose**: Confirm this slice's suite is green and every prior band-A suite is still green (delivery plan §3.10: a checkpoint requires every prior suite green, not just the latest).

- [X] T012 [US1] Run `npx vitest run` from `ai-platform/` and assert all suites green: this slice's `manifest.test.ts` plus the prior band-A suites — `canonical.test.ts` (A3), `taxonomy.test.ts` (A2), `reference.test.ts` (A2), `error-body.test.ts` (A2), `trace.test.ts` (A2), `log-redaction.test.ts` (A2), `health.test.ts` (A1), `env-deploys.test.ts` (A1). No new test file is added here; this is the full-suite regression run. Proves the Verification success criterion.

**Checkpoint**: Full platform suite green. No regressions introduced into A1–A3.

---

## Phase 4: Documentation

**Purpose**: The documentation artifacts the plan names. Written only after the suite is green.

- [X] T013 [US1] Create `specs/018-ai-capability-manifest/contracts/manifest-schema.md` documenting the frozen manifest payload shape: the ten §5.1 field groups and their contents, the `interaction_mode` default of `single_shot`, the conversational-only-field rejection rule, the never-names-provider/model rule, and the published-version content-hash registry mechanism. Later slices (C1/C2/C5/C6/E7/H1/H5) bind to this artifact, not to prose. Satisfies the plan's `contracts/` requirement for a Freezes entry that has a wire shape.
- [X] T014 [US1] Create `specs/018-ai-capability-manifest/quickstart.md` from `.specify/templates/ai-platform-quickstart-template.md`, scoped to this slice only: what was implemented (manifest schema + loader + published-version hash check), the files to review (`ai-platform/src/manifest/index.ts`, `ai-platform/test/manifest.test.ts`), the slice-only test command (`npx vitest run test/manifest.test.ts`), and how to inspect the frozen schema (`specs/018-ai-capability-manifest/contracts/manifest-schema.md`). No Manual validation section — CI is the only verification path for this contract slice (template: omit when CI is the only path). Explicitly excludes prior-slice files, combined test counts, and prior-slice regression commands.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Tests (Phase 1)**: No dependencies — T001 establishes the fixture layer; T002–T009 each add one named test block on top of it. All tasks touch only `ai-platform/test/manifest.test.ts`, so they are strictly sequential in the order listed (no `[P]`).
- **Implementation (Phase 2)**: Depends on the Tests phase existing (red state confirmed). T010 first (turns the schema/rule tests green); T011 after T010 (turns the published-version test green — reuses `index.ts`'s stable encoding).
- **Verification (Phase 3)**: Depends on Implementation green.
- **Documentation (Phase 4)**: Depends on Verification green; T013 and T014 are `[P]` (different files).

### Within the Slice

- Tests are written and confirmed failing before any implementation.
- The fixture layer (T001) is established before any `T-A4-*` block is added.
- The manifest module's schema/rules (T010) land before the published-version hash mechanism (T011), because T011 reuses T010's canonical encoding for the hash.
- The quickstart is written last and cites only this slice's files and commands.

---

## Parallel Opportunities

- T013 and T014 (Phase 4) touch different files (`contracts/manifest-schema.md` vs `quickstart.md`) and may run in parallel.
- No other parallelism: every test task writes to the same single test file, and the two implementation tasks share one source file with a real dependency (T011 reuses T010's encoding).

---

## Notes

- Tests are mandatory (delivery plan §3.10 overrides the template's "Tests are OPTIONAL" note).
- One slice, one story (US1) — the template's multi-story, Foundational, and Polish phases are deleted, not left empty.
- Every task traces to an `FR-###` from `spec.md` and to a named test from its Test plan; nothing is added that the spec/plan do not name.
- No new dependency is introduced — the schema is hand-rolled TS narrowing mirroring A3's `CANONICAL_FIELD_MANIFEST`, per the plan (R-20).
- The CI contract-test run is the "build fails" mechanism the spec's Done-when and §3.11.1 row A4 name — a malformed group or a published-version hash mismatch fails `manifest.test.ts` and therefore fails CI.