# Tasks: Capability registry, resolver stage, and discovery endpoint (C1)

**Input**: Design documents from `specs/025-capability-resolver-discovery/`

**Prerequisites**: `plan.md` (required), `spec.md` (required for the user story). `research.md` is never produced on this platform (the research is `docs/architecture/ai-platform/01-ai-platform.md`). `data-model.md` is not produced (C1 defines no D1 entities). `contracts/` and `quickstart.md` are written during Phase 5.

**Tests**: Tests are mandatory on this platform (delivery plan §3.10). Every named test in the spec's `### Test plan` is a task, written to fail before the code exists.

**Organization**: One user story (US1) — C1 is one slice, one story (delivery plan §2.6, overrides).

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: US1 (this slice has a single user story)
- Include exact file paths in descriptions

## Path Conventions

- **AI gateway Worker**: `ai-platform/src/`, `ai-platform/migrations/`, `ai-platform/test/`
- **Spec Kit artifacts**: `specs/025-capability-resolver-discovery/`
- The Worker lives in `ai-platform/` at the repository root, a sibling of `frontend/` and `backend/` (delivery plan §7.1). The template's `frontend/lib/` and `backend/migrations/` conventions do not apply to this slice; C1 touches neither.

---

## Phase 1: Setup (Test harness)

**Purpose**: Route the new test file to the workers pool that provides the real Miniflare D1 binding B2/B3 already wired (plan → Test Layout: three integration cases read kill-switch / entitlement / grant rows). Both edits must land before any test is written, so the integration cases run under the D1-backed config and the unit cases stay in the default Node pool.

- [X] T001 [US1] Modify `ai-platform/vitest.workers.config.ts` — add `"test/capability.test.ts"` to `include` alongside `"test/control.test.ts"` / `"test/identity.test.ts"` / `"test/entitlement.test.ts"` / `"test/rate-limit.test.ts"` (B3's harness: `d1Databases: ["DB"]`, seeded from the A5 migration). Modify `ai-platform/vitest.config.ts` — add `"test/capability.test.ts"` to `exclude` alongside the same files, so the workers-pool-only cases do not double-run in the default Node pool (plan → Files: vitest configs). No FR — harness; required by every named test. Prepares the Phase 2 substrate.

---

## Phase 2: Tests (written to fail before the code exists)

**Purpose**: One task per named test in the spec's `### Test plan` (§3.11.3 row C1 = Unit + integration). The first task builds the inline-fixture substrate and is the only task that creates the file; every later test is appended to it. All tasks touch the same file (`ai-platform/test/capability.test.ts`), so none is `[P]` relative to another within this phase. The module under test (`../src/capability`) does not exist yet, so the file fails to compile from T002 onward — the intended red state.

- [X] T002 [US1] Create `ai-platform/test/capability.test.ts` with the inline-fixture substrate: a `validManifest(id, version, lifecycleState?)` factory producing a manifest declaring all ten §5.1 field groups (reusing A4's `validManifest()` shape from `test/manifest.test.ts`), an in-memory `buildRegistry(...manifests)` helper returning the `CapabilityRegistry` value under test, a `buildPrincipal({ installationId, plan, allowedCapabilities })` fixture producing a B3 `Principal` (`Object.freeze`d), and the import of `resolve`, `discover`, `buildDiscoveryResponse`, and the `CapabilityRegistry` type from `../src/capability`. File fails to compile (module absent). Proves the fixture substrate for every later test.
- [X] T003 [US1] Add `T-C1-01 resolver_exact_pin_resolves` to `ai-platform/test/capability.test.ts` (unit, `vitest.config.ts`): register a fixture manifest at `clinic.test@1.0.0`; `resolve(principal, "clinic.test", "1.0.0", cache, reader)` returns `{ok:true, manifest}` whose `Identity.version === "1.0.0"`; a request for a different version (e.g. `"1.2.0"`) on the same capability id returns `{ok:false, code:"capability_unknown"}` — the pin is honoured, not relaxed to a "compatible" version (§4.3.4). Satisfies FR-001, FR-008 / SC-001.
- [X] T004 [US1] Add `T-C1-02 resolver_unknown_capability` to `ai-platform/test/capability.test.ts` (unit): `resolve()` for a capability id not present in the registry returns `{ok:false, code:"capability_unknown"}` (§6.1 stage 5; §5.4). Satisfies FR-003, FR-010 / SC-002.
- [X] T005 [US1] Add `T-C1-03 resolver_retired_rejected` to `ai-platform/test/capability.test.ts` (unit): a fixture manifest with `Identity.lifecycleState === "retired"` makes `resolve()` return `{ok:false, code:"capability_retired"}` (§4.3.4; §5.1). Satisfies FR-004, FR-010 / SC-002.
- [X] T006 [US1] Add `T-C1-04 resolver_killed_capability_disabled` to `ai-platform/test/capability.test.ts` (integration, `vitest.workers.config.ts`): seed `env.DB` with the A5 migration, insert an active `kill_switches` row for the `capability:<id>` scope, and assert `resolve()` returns `{ok:false, code:"capability_disabled"}` — read through `loadConfig(cache, reader, "kill_switches", …)` against the real D1 (§4.3.4; §6.1 stage 5; §5.4). Satisfies FR-005, FR-006, FR-010 / SC-002.
- [X] T007 [US1] Add `T-C1-05 resolver_deprecated_serves` to `ai-platform/test/capability.test.ts` (unit): a fixture manifest with `Identity.lifecycleState === "deprecated"` is **not** rejected; `resolve()` returns its `Manifest` (§4.3.4; §5.1 — deprecation is not in the rejection list; the overlap window is J1, out of scope). Satisfies FR-007 / SC-003.
- [X] T008 [US1] Add `T-C1-06 resolver_manifest_immutable` to `ai-platform/test/capability.test.ts` (contract, `vitest.config.ts`): the `Manifest` returned by `resolve()` cannot be mutated by the caller — attempt to set a field on `manifest.Identity` and to reassign `manifest["Context requirements"]`; assert each attempt no-ops or throws and a subsequent reader sees the original values (A4's `Proxy` freeze holds, §5.1). Satisfies FR-008 / SC-004.
- [X] T009 [US1] Add `T-C1-07 discovery_only_granted_active` to `ai-platform/test/capability.test.ts` (integration, `vitest.workers.config.ts`): seed `env.DB` with an `entitlements` row whose `allowed_capabilities` includes one capability id and a `grants` row for it; register fixture manifests with `active`, `deprecated`, and `retired` lifecycle states plus one un-granted active one. Assert `discover(principal, cache, reader)` returns granted manifests whose effective lifecycle is `active` or `deprecated` (§5.5; §4.3.4; review resolution — deprecated may appear with successor). Satisfies FR-011, FR-012 / SC-005.
- [X] T010 [US1] Add `T-C1-08 discovery_etag_not_modified` to `ai-platform/test/capability.test.ts` (contract, `vitest.config.ts`): `buildDiscoveryResponse(request, manifestList, etag)` with matching `If-None-Match` (quoted strong tag / weak comparison; bare raw hash also accepted) returns a `304` response and does not re-serialise the manifest list; absent header → `200`; `Cache-Control: private, must-revalidate` on both (§5.5; §5.2; review-resolution etag quoting). Satisfies FR-013 / SC-006.
- [X] T011 [US1] Add `T-C1-09 discovery_etag_changes` to `ai-platform/test/capability.test.ts` (contract, `vitest.config.ts`): compute the etag for a filtered discovery fixture set, then swap one fixture manifest's `Identity.version` (or remove one from the granted set) and recompute; assert the two etags differ (A4 `hashManifest` SHA-256 over overlay-derived manifests, §5.5; §5.2). Satisfies FR-013 / SC-006.
- [X] T012 [US1] Add `T-C1-10 discovery_entitlement_gated_absent` to `ai-platform/test/capability.test.ts` (integration, `vitest.workers.config.ts`): seed `env.DB` with an `entitlements` row whose `allowed_capabilities` omits a capability id (or whose `plan` is below the manifest's `Access.minimumPlanTier`), and assert that capability is absent from the `discover()` result for that installation — filtered out, not emitted as an error (§4.3.4; §5.5). Note: FR-002 allowance/grant failures on `resolve()` emit stage-5 `forbidden_capability` (B3 still owns stage 3; resolve also fails closed). Satisfies FR-002, FR-012 / SC-005.

---

## Phase 3: Implementation (plan Files section)

**Purpose**: The implementation unit named in `plan.md` → Files (`ai-platform/src/capability/index.ts`). Split into two sequential tasks matching the plan's Sequencing (registry + resolve first, discover + etag after); both touch the same file, so neither is `[P]` relative to the other. The consumed `manifest/`, `config-cache/`, `identity/`, and `errors.ts` modules are imported, not modified (delivery plan §2.3).

- [X] T013 [US1] Create `ai-platform/src/capability/index.ts` — the `CapabilityRegistry` (`Map<"${capabilityId}@${version}", Manifest>` built from manifests passed through A4's `load()`, deep-frozen + unmodifiable Map; `setCapabilityRegistry` install-once / `{ replace: true }`), `resolve(…)` returning `{ok:true, manifest}` or `{ok:false, code}` where `code` is `"capability_unknown"`, `"capability_retired"` (effective lifecycle via overlay), `"forbidden_capability"` (plan-level allowance or grant-version failure), or `"capability_disabled"` (any of the four kill-switch scopes active; miss ⇒ inactive — `global`, `capability:<id>`, `installation:<id>`, `provider:<id>`). Order: lookup → retired → allowance/grant → kill switches. Honours the exact pin. Serves effective `deprecated`. May return registry reference or derived frozen copy under overlay. **Satisfies**: FR-001, FR-002, FR-003, FR-004, FR-005, FR-006, FR-007, FR-008, FR-009, FR-010; **proved by**: `T-C1-01`, `T-C1-02`, `T-C1-03`, `T-C1-04`, `T-C1-05`, `T-C1-06`.
- [X] T014 [US1] Add `discover(principal, cache, reader)`, `buildDiscoveryResponse(request, manifestList, etag)`, and the etag helper to `ai-platform/src/capability/index.ts` — `discover()` enumerates the registry, filters to effective lifecycle ∈ `{active, deprecated}` (overlay wins; `retired` excluded; kill switches **not** applied), filters by entitlement `allowed_capabilities` / plan tier / grant (including string `capability_version` match); returns overlay-derived frozen manifests plus an etag from A4 `hashManifest` (SHA-256) over that filtered set. `buildDiscoveryResponse()` emits quoted strong `ETag`, matches `If-None-Match` with weak comparison (`*`, list, bare hash), sets `Cache-Control: private, must-revalidate` on 200 and 304, and does not re-serialise on 304 (§5.5; §5.2; review resolution). **Satisfies**: FR-011, FR-012, FR-013, FR-014; **proved by**: `T-C1-07`, `T-C1-08`, `T-C1-09`, `T-C1-10`.

---

## Phase 4: Verification

**Purpose**: Delivery plan §3.10 — every prior suite stays green alongside the new one, not just the latest. The checkpoint rule requires every prior suite green, not only this slice's.

- [X] T015 [US1] Run `npx vitest run --config vitest.workers.config.ts test/capability.test.ts` (this slice's three integration cases) and `npx vitest run test/capability.test.ts` (this slice's seven unit/contract cases), then run the full prior suite — `npx vitest run` (default Node-pool config covering the prior band-A/band-B suites — `config-cache.test.ts` (A5), `context.test.ts` (A5), `migrations.test.ts` (A5), `manifest.test.ts` (A4), `canonical.test.ts` (A3), `taxonomy.test.ts`, `reference.test.ts`, `error-body.test.ts`, `trace.test.ts`, `log-redaction.test.ts` (A2), `health.test.ts`, `env-deploys.test.ts` (A1), `adapter.test.ts` (A6)) and `npx vitest run --config vitest.workers.config.ts` (the workers-pool prior suites — `control.test.ts` (B2), `identity.test.ts`, `entitlement.test.ts`, `rate-limit.test.ts` (B3), `admission-credit.test.ts`, `quota-do.test.ts` (B4)). Confirm every prior suite stays green. No new test is added here — this is the §3.10 checkpoint gate, not extra work. **Satisfies**: the §3.10 checkpoint rule.

---

## Phase 5: Documentation

**Purpose**: Plan → Documentation. The two artifacts the plan names that do not yet exist on disk (`contracts/` and `quickstart.md`); both are written only after the suite is green. They touch different files, so they are `[P]` relative to each other.

- [X] T016 [P] [US1] Create `specs/025-capability-resolver-discovery/contracts/capability-registry.md` — the frozen registry-lookup and discovery wire shape: the `ResolveResult` discriminated union (including `forbidden_capability` for allowance/grant), the `DiscoveryResult` shape, registry key format, etag over filtered overlay-derived set (A4 `hashManifest` SHA-256), quoted `ETag` / `If-None-Match` weak comparison / `Cache-Control`, unmodifiable registry + install-once setter, and overlay/`effectiveLifecycle` export surface. C2/D1/E3 consume this artifact (DP-4; delivery plan §2.3). **Satisfies**: the plan's `contracts/` requirement for the Freezes entries that have wire shapes.
- [X] T017 [P] [US1] Create `specs/025-capability-resolver-discovery/quickstart.md` from `.specify/templates/ai-platform-quickstart-template.md`, scoped to this slice only. **§1 Architecture context** — delivery plan §3.4 row C1; the §4.3.4 / §5.1 / §6.1-stage-5 / §5.5 / §5.2 sections; what the spec delivered; what the plan scoped. **§2 What was implemented** — the `src/capability/` module: the `CapabilityRegistry`, `resolve()`, `discover()`, `buildDiscoveryResponse()`, the etag helper. **§3 Files to review** — `ai-platform/src/capability/index.ts`, `ai-platform/test/capability.test.ts`, `specs/025-capability-resolver-discovery/contracts/capability-registry.md`. **§4 Prerequisites** — one-time `npm install` plus the `--config vitest.workers.config.ts` flag for the three integration cases (the slice's tests need the workers-pool Miniflare D1). **§5 Run the automated suite** — `npx vitest run test/capability.test.ts` (unit/contract cases) and `npx vitest run --config vitest.workers.config.ts test/capability.test.ts` (integration cases); slice-only (no `npm test` for the full platform suite). **§6 Inspect the changes** — grep `src/capability/index.ts` for the three resolver error codes, read the frozen `contracts/capability-registry.md` artifact. **No §7** — CI is the only verification path (C1 exposes no user-facing behaviour beyond the suite; `worker.ts` is not modified, so there is no live endpoint to exercise). **Slice-only scope explicit**: no prior-slice files in the review table, no combined test counts, no prior-slice regression commands. Not traced to an FR (template-mandated review surface).

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)** — no dependencies; blocks the Tests phase (the two pools must be wired before any test runs in the right one).
- **Tests (Phase 2)** — depends on Setup; every test is written against `../src/capability`, which is absent, so the test file is red until the Implementation phase lands.
- **Implementation (Phase 3)** — depends on the Tests phase (turns each named test green in the order below).
- **Verification (Phase 4)** — depends on Implementation; runs the whole suite (this slice + every prior slice) per §3.10.
- **Documentation (Phase 5)** — depends on Verification; written only after the suite is green. The two tasks are `[P]` relative to each other (different files, no shared dependency).

### Within the Implementation Phase

- T013 (registry + `resolve`) lands before T014 (`discover` + etag + `buildDiscoveryResponse`): T014 reuses `hashManifest` and the registry populated by T013. Tests turn green in matching order — T-C1-01..06 with T013, T-C1-07..10 with T014.

### Parallel Opportunities

- Phase 1 (T001) is a single task — no internal parallelism.
- Phase 2 (T002–T012) all touch the same file (`capability.test.ts`) — no `[P]`; sequential, each appending to the substrate T002 created.
- Phase 3 (T013–T014) all touch the same file (`src/capability/index.ts`) — no `[P]`; sequential.
- Phase 5 (T016, T017) touch different files and have no shared dependency — `[P]` relative to each other.

---

## Notes

- [P] tasks = different files, no dependencies. Within a single-file phase there is no `[P]`.
- Every task traces to an `FR-###` from `spec.md` (tests also state the `SC-###` they satisfy) — no task adds a requirement the spec does not name.
- No Polish phase and no Foundational phase — prerequisites are the already-merged slices in the plan's Consumes Binding (A4, A5, B3, A6).
- The consumed modules (`manifest/`, `config-cache/`, `identity/`, `errors.ts`, `adapter.ts`) and `worker.ts` are not modified by any task (delivery plan §2.3 — extend, never rewrite).
- Tests land before or alongside their implementation, never after (delivery plan §2.2); the test file plus the diff is the review artifact.