# Tasks: Response validator, bounded repair, and structured output modes (D6)

**Input**: Design documents from `specs/033-response-validator/`

**Prerequisites**: `plan.md` (required), `spec.md` (required for the user story). `research.md` is never produced on this platform (the research is `docs/architecture/17-ai-platform.md`). `data-model.md` is not produced — D6 defines no D1 entities (spec Key Entities). `contracts/response-validator.md` is already frozen on disk (written during the plan phase per DP-4). `quickstart.md` is written in Phase 4 (Documentation).

**Tests**: Tests are mandatory on this platform (delivery plan §3.10). Every named test in the spec's `### Test plan` (T1–T24) is covered. Spy cases T22 and T24 each keep their own task (skill rule). T5–T9 (five safety-guard cases in the same file, same FR-001 safety phase) are combined into one task to stay within the 25-task cap — every T-id remains named inside that task. T4 expands to one named subcase per declared business-rule category (enumerations / referential sanity / numeric ranges / required-section presence) — still one task.

**Organization**: One user story (US1, P1) — D6 is one slice, one story (delivery plan §2.6, overrides). No cross-story parallelism section. No Setup phase — the frozen contract is already on disk; no migrations or `wrangler.toml` edits. No Foundational or Polish phase.

**Task count**: 25 (≤25). Combined to fit: T5–T9 → one task (saves 4 vs one-per-named-test; natural list would be 29).

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: US1 (this slice has a single user story)
- Include exact file paths in descriptions

## Path Conventions

- **AI gateway Worker**: `ai-platform/src/`, `ai-platform/migrations/`, `ai-platform/test/`
- **Spec Kit artifacts**: `specs/033-response-validator/`
- The Worker lives in `ai-platform/` at the repository root, a sibling of `frontend/` and `backend/` (delivery plan §7.1). The template's `frontend/lib/` and `backend/migrations/` conventions do not apply to this slice; D6 touches neither. No `ai-platform/migrations/` edits — D6 adds no D1 schema. D4's `ai-platform/src/stream/prose-guards.ts` is consumed unchanged (not a Files row).

---

## Phase 1: Tests (written to fail before the code exists)

**Purpose**: Cover every named test in the spec's `### Test plan` (§3.11.4 row D6 = "Unit (ordering) + integration"; §13.5 Pipeline tests with fake provider). T1–T16 live in `ai-platform/test/response-validator.test.ts`; T17–T24 live in `ai-platform/test/structured-modes.test.ts`. Both use the default Node-pool config (`vitest.config.ts`, `include: ["test/**/*.test.ts"]`); no workers-pool registration — validator/repair use in-memory schema/rule registries and an injected `reask` port (Clarifications Q2–Q3); structured cases drive the extended broker with fake/scripted chunks and injectable sinks. T001 creates `response-validator.test.ts` and its substrate; T002–T012 append to it. T013 creates `structured-modes.test.ts` and its substrate; T014–T020 append to it. Modules under test (`../src/validate`, extended `../src/stream`) do not exist / lack structured emission yet, so the files fail to compile or fail assertions from the first importing task onward — the intended red state. Order follows the plan's Sequencing (phases → repair → structured → prohibitions).

- [ ] T001 [US1] Add `T-D6-01 valid_output_passes` to `ai-platform/test/response-validator.test.ts` (unit / integration): create the substrate — imports from `../src/validate`; in-memory schema + business-rule registries keyed by manifest `outputSchemaRef` / `businessValidationRuleRefs` (Clarification Q3); a capability Output fixture (mode, schema ref, rule refs, repair policy); assembled-output fixtures; injectable journal and usage/cost sinks for later repair cases; optional event sink for terminal success-path assertions. Then the case: transport-valid, schema-conformant, business-valid output that passes every safety guard; assert validation passes and the output may be carried on terminal `completed` (§4.3.9; §3.11.4 D6; Done when). Satisfies FR-001, FR-007, FR-012 / SC-001. Proves T1.
- [ ] T002 [US1] Add `T-D6-02 parse_failure` to `ai-platform/test/response-validator.test.ts` (unit): assembled output that fails transport/parse validity; assert failure is reported at the transport/parse phase and invalid content is not emitted (§4.3.9; §3.11.4 D6). Satisfies FR-001, FR-007 / SC-001. Proves T2.
- [ ] T003 [US1] Add `T-D6-03 schema_violation` to `ai-platform/test/response-validator.test.ts` (unit): output that parses but violates the registered schema for `outputSchemaRef`; assert failure at schema-conformance phase and no invalid emission (Clarification Q3; §4.3.9; §5.1). Satisfies FR-001, FR-007, FR-012 / SC-001. Proves T3.
- [ ] T004 [US1] Add `T-D6-04 business_rule_violation` to `ai-platform/test/response-validator.test.ts` (unit): one named subcase per declared business-rule category under test — enumerations restricted to the clinic's own vocabulary, referential sanity against the supplied context, numeric ranges, required-section presence — each registered via the in-memory rule registry; assert failure at the business-constraint phase and no invalid emission (Clarification Q3; §4.3.9; §5.1). Satisfies FR-001, FR-002, FR-007 / SC-001. Proves T4.
- [ ] T005 [US1] Add safety-guard cases `T-D6-05`–`T-D6-09` to `ai-platform/test/response-validator.test.ts` (unit) — five named cases in one task (same file, same FR-001 safety phase cluster): `safety_guard_leaked_instruction` (T5), `safety_guard_refusal` (T6), `safety_guard_empty` (T7), `safety_guard_truncated` (T8), `safety_guard_injection_echo` (T9). For each: assembled output that trips that guard; assert validation fails at the safety phase and invalid content is not emitted (§4.3.9; §3.11.4 D6). Satisfies FR-001, FR-007 / SC-001. Proves T5–T9.
- [ ] T006 [US1] Add `T-D6-10 four_phases_run_in_stated_order` to `ai-platform/test/response-validator.test.ts` (unit ordering): fixture constructed so an earlier phase and a later phase would both fail if both ran; assert the reported first failure is from the earlier phase and later phases are not treated as the first failure — proving transport/parse → schema → business → safety order (§4.3.9; §3.11.4 D6). Satisfies FR-001 / SC-002. Proves T10.
- [ ] T007 [US1] Add `T-D6-11 invalid_content_never_emitted` to `ai-platform/test/response-validator.test.ts` (unit / integration): across validation failure paths in this file, assert invalid content is never emitted on a terminal success path and never returned as the accepted payload (§4.3.9; Done when; §3.10). Satisfies FR-005, FR-007 / SC-001. Proves T11.
- [ ] T008 [US1] Add `T-D6-12 repair_allowed_one_reask_success` to `ai-platform/test/response-validator.test.ts` (integration): capability with `repairPolicy.allowed`; inject `reask(errors)` that returns valid output after one invalid assembly (Clarification Q2); assert exactly one budgeted re-ask with validation errors appended and successful completion (§4.3.9; §5.1; §3.11.4 D6). Satisfies FR-003, FR-004 / SC-003. Proves T12.
- [ ] T009 [US1] Add `T-D6-13 repair_disallowed_immediate_validation_failed` to `ai-platform/test/response-validator.test.ts` (integration): capability with repair disallowed and failing output; assert immediate `validation_failed`, zero `reask` calls, and no invalid content returned (§4.3.9; §5.1; §3.11.4 D6). Satisfies FR-004, FR-005, FR-007 / SC-003. Proves T13.
- [ ] T010 [US1] Add `T-D6-14 repair_fails_validation_failed` to `ai-platform/test/response-validator.test.ts` (integration): repair allowed; inject `reask` that still fails validation; assert terminal `validation_failed` and invalid content not returned (Clarification Q2; §4.3.9; Done when). Satisfies FR-003, FR-005, FR-007 / SC-003. Proves T14.
- [ ] T011 [US1] Add `T-D6-15 repair_attempt_cap_enforced_and_journaled` to `ai-platform/test/response-validator.test.ts` (integration, journal sink spy): drive repair to the manifest `repairPolicy.maxAttempts` cap; assert the cap is enforced, each attempt is journaled via the injectable sink, and exhaustion produces `validation_failed` (Clarification Q2; §4.3.9; §5.1). Satisfies FR-003, FR-005 / SC-004. Proves T15.
- [ ] T012 [US1] Add `T-D6-16 repair_cost_counted_against_request` to `ai-platform/test/response-validator.test.ts` (integration, usage/cost sink spy): perform a repair re-ask; assert repair cost is counted against the request via the injectable usage/cost sink (§4.3.9; Done when; §3.11.4 D6). Satisfies FR-006 / SC-005. Proves T16.
- [ ] T013 [P] [US1] Add `T-D6-17 structured_partial_events_provisional` to `ai-platform/test/structured-modes.test.ts` (integration): create the substrate — imports of extended stream broker from `../src/stream` and validator entry from `../src/validate`; A6-shaped event sink; scripted/fake provider chunks for `structured` / `structured_atomic`; capability Output fixtures with `mode`; reuse D4-style heartbeat ticker / sinks where needed without rewriting D4 prose/cancel. Then the case: `structured` capability with incrementally parseable content; assert `partial_structured` events are emitted and every one is flagged provisional (§6.4; §3.11.4 D6). Satisfies FR-008, FR-011 / SC-006. Proves T17. `[P]` vs `response-validator.test.ts` (different file).
- [ ] T014 [US1] Add `T-D6-18 structured_terminal_carries_whole_validated_document` to `ai-platform/test/structured-modes.test.ts` (integration): `structured` capability whose complete document passes validation; assert the terminal event is `completed` and carries the whole validated document (§6.4; §3.11.4 D6). Satisfies FR-008, FR-010 / SC-006. Proves T18.
- [ ] T015 [US1] Add `T-D6-19 structured_atomic_progress_only` to `ai-platform/test/structured-modes.test.ts` (integration): `structured_atomic` capability; before completion assert only progress/heartbeat events (no provisional structured document chunks); completion validation follows the same rules as `structured` (§6.4; §3.11.4 D6). Satisfies FR-009 / SC-007. Proves T19.
- [ ] T016 [US1] Add `T-D6-20 client_ignoring_chunks_still_correct` to `ai-platform/test/structured-modes.test.ts` (integration): successful `structured` or `structured_atomic` request; assert a client that ignores every non-terminal event still receives the correct validated result from the terminal payload alone (§6.4 invariant 1; §3.11.4 D6). Satisfies FR-010 / SC-008. Proves T20.
- [ ] T017 [US1] Add `T-D6-21 terminal_payload_not_assembled_from_chunks` to `ai-platform/test/structured-modes.test.ts` (integration): inspect the terminal payload of a successful structured-mode completion; assert it is self-contained and is not assembled from stream chunks (§6.4 invariant 1; Done when). Satisfies FR-010 / SC-008. Proves T21.
- [ ] T018 [US1] Add `T-D6-22 no_per_request_state_for_repair_or_structured` to `ai-platform/test/structured-modes.test.ts` (integration, spy): assert absence of any per-request server-side state object introduced by validator, repair, or structured-emission paths (§4.4, §9.7; delivery plan §6.4; §3.10). Satisfies FR-014 / SC-009. Proves T22.
- [ ] T019 [US1] Add `T-D6-23 provisional_structured_not_committable_on_emission` to `ai-platform/test/structured-modes.test.ts` (integration): assert provisional `partial_structured` content is never treated as the committed result at the emission boundary (§6.4 invariant 2; delivery plan §6.4; §3.10). Satisfies FR-011 / SC-009. Proves T23.
- [ ] T020 [US1] Add `T-D6-24 prose_path_unchanged_by_this_slice` to `ai-platform/test/structured-modes.test.ts` (integration, spy): assert D4 `prose` relay / incremental-guard / cancel contracts remain intact — D6 does not rewrite them (Consumes D4; FR-013; §3.10). Satisfies FR-013 / SC-009. Proves T24.

---

## Phase 2: Implementation (plan Files section)

**Purpose**: The three implementation units named in `plan.md` → Files that are new or extended: `validate/phases.ts`, `validate/index.ts`, and extended `stream/index.ts`. Consumed D4 modules (`stream/prose-guards.ts`, broker relay/heartbeat/cancel duties) are imported/extended, not rewritten (delivery plan §2.3). A4 Output types, A2 `validation_failed`, A3 `partial_structured`, and C3/B4 sinks are Assumptions consumers — not modified. Frozen contract `contracts/response-validator.md` constrains the surface. Order follows plan Sequencing: phases (T1–T11) → bounded repair orchestration (T12–T16) → structured emission (T17–T24).

- [ ] T021 [US1] Create `ai-platform/src/validate/phases.ts` — ordered validation phases: transport/parse validity → schema conformance (via injected/in-memory schema registry keyed by `outputSchemaRef`) → declared business-constraint checks (enumerations, referential sanity, numeric ranges, required-section presence via rule registry keyed by `businessValidationRuleRefs`) → safety guards (leaked system instructions, refusals, empty, truncated, prompt-injection echo). Earlier-phase failure is the reported first failure; later phases do not run as the first failure. No D1/R2/DO I/O; no per-request state. **Satisfies**: FR-001, FR-002, FR-012; **proved by**: T1–T10 (T-D6-01..10).
- [ ] T022 [US1] Create `ai-platform/src/validate/index.ts` — orchestrate `phases.ts`; read capability Output fields (mode, schema ref, rule refs, repair policy) from the manifest — never hard-code provider/model identity; on failure, when `repairPolicy.allowed`, invoke injected `reask(errors) => Promise<assembled output>` (Clarification Q2) within `maxAttempts`, count and journal attempts via injectable sinks, count repair cost against the request; on disallowed or exhausted repair fail with existing A2 taxonomy code `validation_failed` and never return invalid content; create no per-request server-side state. **Satisfies**: FR-001–FR-007, FR-012, FR-014; **proved by**: T1–T16 (T-D6-01..16).
- [ ] T023 [P] [US1] Extend `ai-platform/src/stream/index.ts` for `structured` and `structured_atomic` emission under commit-time validation — `structured` emits provisional `partial_structured` events; `structured_atomic` emits progress/heartbeat only; at completion validate (via `validate/`) and emit exactly one `completed` carrying the whole self-contained validated document (never assembled from chunks; provisional never treated as committed); do not rewrite D4 relay, heartbeat, one-terminal-event, `prose` incremental guards, or connection-scoped cancel; no per-request server-side state. **Satisfies**: FR-008–FR-011, FR-013, FR-014; **proved by**: T17–T24 (T-D6-17..24). `[P]` vs T021/T022 once test stubs exist (different file; structured emission extends stream while validate modules land independently).

---

## Phase 3: Verification

**Purpose**: Delivery plan §3.10 — every prior suite stays green alongside the new one, not just the latest.

- [ ] T024 [US1] From `ai-platform/`, run `npx vitest run test/response-validator.test.ts test/structured-modes.test.ts` (this slice's named cases, all under the default Node pool — D6 is CPU-only with in-memory registries, injected `reask`, and fake/scripted broker inputs), then run the full prior suite — `npx vitest run` (default Node-pool prior suites including `response-validator.test.ts`, `structured-modes.test.ts` (D6), `deepseek-adapter.test.ts` (D5), `stream-broker.test.ts` (D4), `invocation.test.ts` (D3), `provider-port.test.ts`, `router.test.ts` (D2), `prompt-registry.test.ts`, `prompt-composer.test.ts` (D1), `manifest.test.ts` (A4), `canonical.test.ts` (A3), `taxonomy.test.ts`, `reference.test.ts`, `error-body.test.ts`, `trace.test.ts`, `log-redaction.test.ts` (A2), `health.test.ts`, `env-deploys.test.ts` (A1), `context-validator.test.ts` (C2)) and `npx vitest run --config vitest.workers.config.ts` (workers-pool prior suites: `control.test.ts` (B2), `identity.test.ts`, `entitlement.test.ts`, `rate-limit.test.ts` (B3), `admission-credit.test.ts`, `quota-do.test.ts` (B4), `capability.test.ts` (C1), `journal.test.ts` (C3); `context.test.ts`, `config-cache.test.ts`, `migrations.test.ts` (A5); `adapter.test.ts` (A6)). Confirm every prior suite stays green. No new test is added here — this is the §3.10 checkpoint gate. **Satisfies**: the §3.10 checkpoint rule (ordered phases, each failure class, repair policy/cap/journal/cost, structured / structured_atomic emission, self-contained terminal, no per-request state, non-committable provisional, unchanged D4 prose). Proved by itself.

---

## Phase 4: Documentation

**Purpose**: Always present. The one documentation artifact the plan names that does not yet exist on disk (`quickstart.md`); written only after the suite is green. The contract was already frozen during the plan phase.

- [ ] T025 [US1] Create `specs/033-response-validator/quickstart.md` from `.specify/templates/ai-platform-quickstart-template.md`, scoped to this slice only. **§1 Architecture context** — delivery plan §3.5 row D6; `17-ai-platform.md` §4.3.9, §6.4, §5.1; what the spec delivered; what the plan scoped. **§2 What was implemented** — ordered validator (`src/validate/phases.ts`, `src/validate/index.ts`) with injected `reask` port; `structured` / `structured_atomic` emission extending `src/stream/index.ts`; frozen `contracts/response-validator.md`. **§3 Files to review** — only this slice's source, test, and contract files (`ai-platform/src/validate/`, extended `ai-platform/src/stream/index.ts`, `ai-platform/test/response-validator.test.ts`, `ai-platform/test/structured-modes.test.ts`, `specs/033-response-validator/contracts/`). **§4 Prerequisites** — omit or keep minimal (`cd ai-platform && npm install` first time); CPU-only tests, no miniflare / live-provider bindings required for this slice. **§5 Run the automated suite** — `cd ai-platform && npx vitest run test/response-validator.test.ts test/structured-modes.test.ts`; slice-only (no full-suite `npm test`). **§6 Inspect the changes** — read the frozen contract; open `validate/` and extended `stream/index.ts`; run the focused test files. **No §7** — CI is the only verification path (plan: Manual validation omitted). **Slice-only scope explicit**: no prior-slice files in the review table, no combined test counts, no prior-slice regression commands. Not traced to an FR (template-mandated review surface).

---

## Dependencies & Execution Order

### Phase Dependencies

- **Tests (T001–T020)** — none beyond already-frozen contracts and Consumes Binding modules; written to fail before the code exists. T001–T012 append to `response-validator.test.ts` (sequential). T013–T020 append to `structured-modes.test.ts` (sequential within that file); T013 is `[P]` relative to the response-validator file.
- **Implementation (T021–T023)** — after tests exist (red). T021 (`phases.ts`) then T022 (`validate/index.ts`, depends on T021). T023 (`stream/index.ts` extension) is `[P]` relative to T021/T022 (different file) but turns T17–T24 green only once validate is available for commit-time validation.
- **Verification (T024)** — depends on T001–T023; runs the whole suite (this slice + every prior slice) per §3.10.
- **Documentation (T025)** — depends on T024 (the quickstart records a green suite).

### Within the Slice

- Tests written to fail before implementation; implementation makes them pass; verification confirms the whole suite including prior slices stays green.
- Within Phase 1, order follows plan Sequencing: phases/failure classes (T1–T11) → repair (T12–T16) → structured emission (T17–T21) → prohibitions/spies (T22–T24).
- Three implementation units: phases (FR-001–FR-002) → validate orchestration + repair (FR-001–FR-007, FR-012, FR-014) → structured stream extension (FR-008–FR-011, FR-013–FR-014).

### Parallel Opportunities

- Phase 1: T013–T020 (`structured-modes.test.ts`) are `[P]` relative to T001–T012 (`response-validator.test.ts`) — different files. Within each file, tasks are sequential.
- Phase 2: T023 (`stream/index.ts`) is `[P]` relative to T021/T022 (`validate/*`) — different files; wire validate into structured completion when both exist.
- Phase 4 (T025) is a single task — no `[P]`.

---

## Notes

- [P] tasks = different files, no dependencies. Marked: T013 (structured test substrate vs response-validator file) and T023 (stream extension vs validate modules).
- Every named test T1–T24 from `spec.md` is covered; T5–T9 are one combined task (same file, same safety-phase FR cluster) to fit the 25-task cap; spy cases T22 and T24 remain separate tasks.
- Every task traces to an `FR-###` from `spec.md` (tests also state the `SC-###` they satisfy) — no task adds a requirement the spec does not name. Clarifications Q1–Q3 guide how (module path, `reask` port, in-memory registries), not what.
- No Polish phase and no Foundational phase — prerequisites are the already-merged slices in the plan's Consumes Binding (D4).
- Consumed modules are imported/extended, not rewritten (delivery plan §2.3). `prose-guards.ts` is not modified.
- Tests land before or alongside their implementation, never after (delivery plan §2.2).
- Preserve the I/O budget: no second Quota DO round trip, no second R2 object, no D1 row per chunk, no per-request server-side state (§4.4, §7.5, §9.7, §13.6).
