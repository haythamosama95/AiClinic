# Tasks: Context validator stage and cost pre-flight (C2)

**Input**: Design documents from `specs/026-context-validator-cost-preflight/`

**Prerequisites**: `plan.md` (required), `spec.md` (required for the user story). `research.md` is never produced on this platform (the research is `docs/architecture/17-ai-platform.md`). `data-model.md` is not produced (C2 defines no D1 entities — spec `### Key Entities`: "Not applicable"). `contracts/` and `quickstart.md` are written during Phase 5.

**Tests**: Tests are mandatory on this platform (delivery plan §3.10). Every named test in the spec's `### Test plan` is a task, written to fail before the code exists.

**Organization**: One user story (US1) — C2 is one slice, one story (delivery plan §2.6, overrides).

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: US1 (this slice has a single user story)
- Include exact file paths in descriptions

## Path Conventions

- **AI gateway Worker**: `ai-platform/src/`, `ai-platform/test/`
- **Spec Kit artifacts**: `specs/026-context-validator-cost-preflight/`
- The Worker lives in `ai-platform/` at the repository root, a sibling of `frontend/` and `backend/` (delivery plan §7.1). The template's `frontend/lib/` and `backend/migrations/` conventions do not apply to this slice; C2 touches neither. No `ai-platform/migrations/` edits — stages 6–7 are CPU-only (§6.1).

---

## Phase 2: Tests (written to fail before the code exists)

**Purpose**: One task per named test in the spec's `### Test plan` (§3.11.3 row C2 = Unit (spy)). The first task builds the inline-fixture substrate and is the only task that creates the file; every later test is appended to it. All tasks touch the same file (`ai-platform/test/context-validator.test.ts`), so none is `[P]` relative to another within this phase. The modules under test (`../src/context/validator` and `../src/context/preflight`) do not exist yet, so the file fails to compile from T002 onward — the intended red state. All 15 tests run under `vitest.config.ts` (C2 does no D1/DO/R2 I/O — no `vitest.workers.config.ts` cases, unlike C1).

- [ ] T001 [US1] Create `ai-platform/test/context-validator.test.ts` with the inline-fixture substrate: a `validManifest()` factory declaring all ten §5.1 field groups (reusing the shape from `test/capability.test.ts` — C1's fixture), with a `Context requirements` array declaring required keys `patient.demographics@v1` and `visit.vitals@v1` plus an optional key `visit.chief_complaint@v1`, and `Economics` with `maxInputTokens`, `maxOutputTokens`, `perRequestCostCeiling` (token-denominated); a `buildPrincipal({ organizationId, branchId })` fixture producing a B3 `Principal` (`Object.freeze`d); a `nextStage = vi.fn()` spy sink for the no-egress assertions; and the imports of `validateContext`, `buildContextRequiredResponse` from `../src/context/validator` and `estimateInputTokens`, `runCostPreflight` from `../src/context/preflight`. File fails to compile (modules absent). Proves the fixture substrate for every later test.
- [ ] T002 [US1] Add `T-C2-01 validator_accepts_complete_valid_context` to `ai-platform/test/context-validator.test.ts` (unit): a complete, well-shaped, tenant-consistent supplied context passes `validateContext(manifest, context, principal)`; the returned `filteredContext` contains exactly the manifest-declared keys and nothing else; `nextStage` is called once with the filtered payload (§4.3.5). Satisfies FR-001, FR-002, FR-003, FR-006 / SC-001.
- [ ] T003 [US1] Add `T-C2-02 validator_rejects_each_missing_required_key` to `ai-platform/test/context-validator.test.ts` (unit): for each declared required key (`patient.demographics@v1`, `visit.vitals@v1`), omitting it emits `context_required` whose payload lists exactly the missing key, its `KeyShape` (from A5's `PUBLISHED_KEY_SHAPES`), `manifest_version`, and `manifest_capability_id` (§4.3.5, §8.4). Parameterised: one case per required key. Satisfies FR-001 / SC-002.
- [ ] T004 [US1] Add `T-C2-03 validator_rejects_multiple_missing_required_keys` to `ai-platform/test/context-validator.test.ts` (unit): with both required keys missing, the `context_required` payload lists the full set (both keys + both shapes), not just the first encountered (§8.4 "missing keys + shapes"). Satisfies FR-001 / SC-002.
- [ ] T005 [US1] Add `T-C2-04 validator_rejects_each_shape_violation` to `ai-platform/test/context-validator.test.ts` (unit): for each shape-violation kind (wrong field type, wrong cardinality, wrong unit, missing required field within a key's payload), `validateContext` rejects with `context_invalid` (§5.2 Shape; §6.1 stage 6). Parameterised: one case per kind. Satisfies FR-002 / SC-001.
- [ ] T006 [US1] Add `T-C2-05 validator_rejects_oversize_key` to `ai-platform/test/context-validator.test.ts` (unit): a supplied key whose byte length exceeds the manifest's declared per-key `maxSize` rejects with `context_invalid` (§5.1 Context requirements; §6.1 stage 6). Satisfies FR-002 / SC-001.
- [ ] T007 [US1] Add `T-C2-06 validator_drops_undeclared_key_spy` to `ai-platform/test/context-validator.test.ts` (unit, spy): a supplied key not in the manifest's `Context requirements` (e.g. `medication.active_list@v1` while the manifest declares only the three fixture keys) is absent from `filteredContext`; the `nextStage` spy's call argument does not contain the undeclared key (§4.3.5; §5.2 Minimization). Satisfies FR-003 / SC-003.
- [ ] T008 [US1] Add `T-C2-07 validator_rejects_org_mismatch` to `ai-platform/test/context-validator.test.ts` (unit): `principal.organizationId` ≠ the supplied context's org (e.g. context carries `org:"org-X"` while principal carries `organizationId:"org-Y"`) rejects with `context_invalid` (§5.2 Authorization; §5.6; §6.1 stage 6). Satisfies FR-004 / SC-001.
- [ ] T009 [US1] Add `T-C2-08 validator_rejects_branch_mismatch` to `ai-platform/test/context-validator.test.ts` (unit): `principal.branchId` ≠ the supplied context's branch rejects with `context_invalid` (§5.2 Authorization; §5.6; §6.1 stage 6). Separate from T-C2-07 — org and branch are independent checks. Satisfies FR-004 / SC-001.
- [ ] T010 [US1] Add `T-C2-09 validator_passes_absent_optional_key` to `ai-platform/test/context-validator.test.ts` (unit): a manifest-declared optional key omitted from the supplied context passes; `filteredContext` omits it without rejection (§5.1 required/optional). Satisfies FR-005 / SC-001.
- [ ] T011 [US1] Add `T-C2-10 preflight_passes_under_ceiling` to `ai-platform/test/context-validator.test.ts` (unit): `runCostPreflight(manifest, serializedInput)` returns `{ok:true}` when `estimatedInputTokens + maxOutputTokens ≤ perRequestCostCeiling` AND `estimatedInputTokens ≤ maxInputTokens` (§4.3.3; §6.1 stage 7; §13.6.2). Satisfies FR-007 / SC-004.
- [ ] T012 [US1] Add `T-C2-11 preflight_rejects_over_ceiling` to `ai-platform/test/context-validator.test.ts` (unit): `estimatedInputTokens + maxOutputTokens > perRequestCostCeiling` returns `{ok:false, code:"request_too_large"}` (§4.3.3; §6.1 stage 7; §5.4). Satisfies FR-007 / SC-004.
- [ ] T013 [US1] Add `T-C2-12 preflight_estimate_includes_max_output_tokens` to `ai-platform/test/context-validator.test.ts` (unit): the ceiling comparison uses the manifest's `maxOutputTokens` — a fixture with `maxOutputTokens` set so that input-only would pass the ceiling but `input + maxOutputTokens` exceeds it rejects with `request_too_large`, proving the comparison is `estimatedInputTokens + maxOutputTokens`, not input alone (§5.1 Economics; §13.6.2). Satisfies FR-007 / SC-004.
- [ ] T014 [US1] Add `T-C2-13 preflight_no_egress_on_rejection_spy` to `ai-platform/test/context-validator.test.ts` (unit, spy): a pre-flight rejection results in zero calls to the `nextStage` (composer/provider entry) spy — the rejection is terminal, no egress occurs (§4.3.3 "before any egress"; §6.1 stage 7 precedes stage 11). Satisfies FR-008 / SC-004.
- [ ] T015 [US1] Add `T-C2-14 preflight_estimator_is_deterministic_bytes` to `ai-platform/test/context-validator.test.ts` (unit): `estimateInputTokens(serializedInput)` equals `Math.ceil(utf8ByteLength(serializedInput) / 4) * 1.15` for a fixed ASCII payload; is multi-byte-safe (a 2-byte UTF-8 character counts as 2 bytes, not 1); and is recomputed identically across calls (§13.6.2). Satisfies FR-007 / SC-004.
- [ ] T016 [US1] Add `T-C2-15 preflight_rejects_over_max_input_tokens` to `ai-platform/test/context-validator.test.ts` (unit): `estimatedInputTokens > maxInputTokens` (with `estimatedInputTokens + maxOutputTokens ≤ perRequestCostCeiling` held so only the secondary predicate fires) returns `{ok:false, code:"request_too_large"}` (§5.1 Economics; §6.1 stage 7; §13.6.2). Satisfies FR-007 / SC-004.

---

## Phase 3: Implementation (plan Files section)

**Purpose**: The two implementation units named in `plan.md` → Files. They touch different files (`ai-platform/src/context/validator.ts` and `ai-platform/src/context/preflight.ts`), so they are `[P]` relative to each other — the validator and the pre-flight are independent stages with no shared code. The consumed `context/index.ts` (A5), `errors.ts` (A2), `identity/` (B3), `manifest/` (A4), `capability/` (C1) modules are imported, not modified (delivery plan §2.3). Tests turn green in matching groups — T-C2-01..09 with T017, T-C2-10..15 with T018.

- [ ] T017 [P] [US1] Create `ai-platform/src/context/validator.ts` — export the `ValidateResult` discriminated union: `{ok:true, filteredContext: Record<string, unknown>} | {ok:false, code:"context_required", missingKeys: string[], shapes: Record<string, KeyShape>, manifestVersion: string, manifestCapabilityId: string} | {ok:false, code:"context_invalid"}`. Export `validateContext(manifest: Manifest, suppliedContext: Record<string, unknown>, principal: Principal): ValidateResult` — iterates the manifest's `"Context requirements"` array; for each declared required key absent from `suppliedContext`, accumulates it into the missing-keys set; for each supplied key, calls A5's `validatePayload(key, value)` (shape conformance) and checks the payload byte length against the manifest's per-key `maxSize` (oversize → `context_invalid`); drops any key not declared by the manifest from `filteredContext`; cross-checks `principal.organizationId` and `principal.branchId` against the supplied context's org/branch (`context_invalid` on mismatch); an absent optional key passes. If any required keys are missing, returns the `context_required` branch (the full missing set, never just the first); if any shape/size/tenant check fails, returns `context_invalid`; otherwise returns `{ok:true, filteredContext}`. Export `buildContextRequiredResponse(result, requestReference, traceId)` — calls A2's `buildErrorBody({code:"context_required", requestReference, traceId})` for the four common fields (`code`, `request_reference`, `trace_id`, `retry_safe`), then attaches the frozen snake_case missing-key manifest: `{ missing_keys: string[], shapes: Record<string, KeyShape>, manifest_version: string, manifest_capability_id: string }` (Clarification Q1). **Satisfies**: FR-001, FR-002, FR-003, FR-004, FR-005, FR-006, FR-009; **proved by**: `T-C2-01` through `T-C2-09`.
- [ ] T018 [P] [US1] Create `ai-platform/src/context/preflight.ts` — export the two platform constants `TOKENS_PER_BYTE_DIVISOR = 4` and `ESTIMATE_SAFETY_FACTOR = 1.15` (§13.6.2 — platform constants, not manifest fields, not per-provider values). Export `estimateInputTokens(serializedInput: string): number` — `Math.ceil(utf8ByteLength(serializedInput) / TOKENS_PER_BYTE_DIVISOR) * ESTIMATE_SAFETY_FACTOR`, where `utf8ByteLength` is `new TextEncoder().encode(serializedInput).byteLength` (multi-byte safe). Export the `PreflightResult` union: `{ok:true} | {ok:false, code:"request_too_large"}`. Export `runCostPreflight(manifest: Manifest, serializedInput: string): PreflightResult` — computes `estimatedInputTokens = estimateInputTokens(serializedInput)`; reads `maxOutputTokens`, `maxInputTokens`, `perRequestCostCeiling` from `manifest.Economics`; rejects with `request_too_large` when `estimatedInputTokens + maxOutputTokens > perRequestCostCeiling` OR when `estimatedInputTokens > maxInputTokens`; otherwise passes. The comparison is in tokens throughout — no token→cost conversion, no provider price (§13.6.2; §5.1 Economics). **Satisfies**: FR-007, FR-008; **proved by**: `T-C2-10` through `T-C2-15`.

---

## Phase 4: Verification

**Purpose**: Delivery plan §3.10 — every prior suite stays green alongside the new one, not just the latest. The checkpoint rule requires every prior suite green, not only this slice's.

- [ ] T019 [US1] Run `npx vitest run test/context-validator.test.ts` (this slice's 15 unit cases — all under `vitest.config.ts`, no workers-pool cases), then run the full prior suite — `npx vitest run` (default Node-pool config covering prior slices — `context.test.ts` (A5), `config-cache.test.ts` (A5), `migrations.test.ts` (A5), `capability.test.ts` is excluded from the default pool and runs under workers; `manifest.test.ts` (A4), `canonical.test.ts` (A3), `taxonomy.test.ts`, `reference.test.ts`, `error-body.test.ts`, `trace.test.ts`, `log-redaction.test.ts` (A2), `health.test.ts`, `env-deploys.test.ts` (A1), `adapter.test.ts` (A6)) and `npx vitest run --config vitest.workers.config.ts` (the workers-pool prior suites — `control.test.ts` (B2), `identity.test.ts`, `entitlement.test.ts`, `rate-limit.test.ts` (B3), `admission-credit.test.ts`, `quota-do.test.ts` (B4), `capability.test.ts` (C1)). Confirm every prior suite stays green. No new test is added here — this is the §3.10 checkpoint gate, not extra work. **Satisfies**: the §3.10 checkpoint rule.

---

## Phase 5: Documentation

**Purpose**: Plan → Documentation. The two artifacts the plan names that do not yet exist on disk (`contracts/` and `quickstart.md`); both are written only after the suite is green. They touch different files, so they are `[P]` relative to each other.

- [ ] T020 [P] [US1] Create `specs/026-context-validator-cost-preflight/contracts/context-validator.md` — the frozen stage output and wire shapes: the `ValidateResult` discriminated union (`{ok:true, filteredContext}` | `{ok:false, code:"context_required", missingKeys, shapes, manifestVersion, manifestCapabilityId}` | `{ok:false, code:"context_invalid"}`); the `context_required` wire payload (`{code, request_reference, trace_id, retry_safe, missing_keys, shapes, manifest_version, manifest_capability_id}` — the four A2 common fields plus the C2-frozen missing-key manifest from Clarification Q1); the `PreflightResult` union (`{ok:true}` | `{ok:false, code:"request_too_large"}`); the §13.6.2 estimator formula (`ceil(utf8Bytes/4)*1.15`) with the two platform constants (`TOKENS_PER_BYTE_DIVISOR = 4`, `ESTIMATE_SAFETY_FACTOR = 1.15`); the two stage-7 predicates (`estimatedInputTokens + maxOutputTokens ≤ perRequestCostCeiling` AND `estimatedInputTokens ≤ maxInputTokens`); and the source-of-truth file paths (`ai-platform/src/context/validator.ts`, `ai-platform/src/context/preflight.ts`). D1 (prompt composer), J2 (self-healing behaviour), B4 (admission), and D3 (invocation) consume this artifact, not prose (DP-4; delivery plan §2.3). **Satisfies**: the plan's `contracts/` requirement for the three Freezes entries that have wire shapes.
- [ ] T021 [P] [US1] Create `specs/026-context-validator-cost-preflight/quickstart.md` from `.specify/templates/ai-platform-quickstart-template.md`, scoped to this slice only. **§1 Architecture context** — delivery plan §3.4 row C2; the §4.3.5 / §5.2 / §4.3.3 / §6.1-stages-6-7 / §13.6.2 sections; what the spec delivered; what the plan scoped. **§2 What was implemented** — the `src/context/validator.ts` stage-6 validator + `context_required` wire builder; the `src/context/preflight.ts` stage-7 byte estimator + two-predicate pre-flight. **§3 Files to review** — `ai-platform/src/context/validator.ts`, `ai-platform/src/context/preflight.ts`, `ai-platform/test/context-validator.test.ts`, `specs/026-context-validator-cost-preflight/contracts/context-validator.md`. **§4 Prerequisites** — omitted (no wrangler/D1 needed; all tests are unit under `vitest.config.ts`). **§5 Run the automated suite** — `npx vitest run test/context-validator.test.ts`; slice-only (no `npm test` for the full platform suite). **§6 Inspect the changes** — grep `src/context/validator.ts` for `context_required` / `context_invalid`, grep `src/context/preflight.ts` for `estimateInputTokens` / `request_too_large`, read the frozen `contracts/context-validator.md` artifact. **No §7** — CI is the only verification path (C2 exposes no user-facing behaviour beyond the suite; `worker.ts` is not modified, so there is no live endpoint to `curl`). **Slice-only scope explicit**: no prior-slice files in the review table, no combined test counts, no prior-slice regression commands. Not traced to an FR (template-mandated review surface).

---

## Dependencies & Execution Order

### Phase Dependencies

- **Tests (Phase 2)** — no Setup phase (the plan's Files section names no config file that must exist first — `vitest.config.ts` is unchanged, and `test/**/*.test.ts` already covers the new file); every test is written against `../src/context/validator` and `../src/context/preflight`, which are absent, so the test file is red until the Implementation phase lands.
- **Implementation (Phase 3)** — depends on the Tests phase (turns each named test green in the groups below).
- **Verification (Phase 4)** — depends on Implementation; runs the whole suite (this slice + every prior slice) per §3.10.
- **Documentation (Phase 5)** — depends on Verification; written only after the suite is green. The two tasks are `[P]` relative to each other (different files, no shared dependency).

### Within the Implementation Phase

- T017 (validator) and T018 (preflight) touch different files and have no shared dependency — `[P]` relative to each other. Tests turn green in matching groups: T-C2-01..09 with T017 (validator), T-C2-10..15 with T018 (preflight), following the plan's Sequencing (validator happy path → validator rejections → pre-flight estimator → pre-flight predicates → pre-flight spy).

### Parallel Opportunities

- Phase 2 (T001–T016) all touch the same file (`context-validator.test.ts`) — no `[P]`; sequential, each appending to the substrate T001 created.
- Phase 3 (T017, T018) touch different files (`validator.ts`, `preflight.ts`) — `[P]` relative to each other.
- Phase 5 (T020, T021) touch different files and have no shared dependency — `[P]` relative to each other.

---

## Notes

- [P] tasks = different files, no dependencies. Within a single-file phase there is no `[P]`.
- Every task traces to an `FR-###` from `spec.md` (tests also state the `SC-###` they satisfy) — no task adds a requirement the spec does not name.
- No Polish phase and no Foundational phase — prerequisites are the already-merged slices in the plan's Consumes Binding (A2, A3, A4, A5, B3, C1, A6).
- The consumed modules (`context/index.ts`, `errors.ts`, `identity/`, `manifest/`, `capability/`, `adapter.ts`, `contracts/canonical.ts`) and `worker.ts` are not modified by any task (delivery plan §2.3 — extend, never rewrite).
- Tests land before or alongside their implementation, never after (delivery plan §2.2); the test file plus the diff is the review artifact.
- The two spy cases (T-C2-06, T-C2-13) are separate named tests that assert call counts/absences on the `nextStage` spy — separate work from asserting an outcome, per the task-out rules.