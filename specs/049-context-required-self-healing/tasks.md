# Tasks: `context_required` self-healing round trip (J2)

**Input**: Design documents from `specs/049-context-required-self-healing/`

**Prerequisites**: `plan.md` (required), `spec.md` (required for the user story). `research.md` is never produced on this platform (the research is `docs/architecture/17-ai-platform.md`). `data-model.md` is not produced — J2 defines no entities (spec Key Entities: not applicable). `contracts/` is not produced — Freezes are client behavioural rules with no new wire shape (plan Project Structure → Documentation). `quickstart.md` is written in Phase 4 (Documentation).

**Tests**: Tests are mandatory on this platform (delivery plan §3.10). Every named test in the spec's `### Test plan` (tests 1–4) is covered by its own task, written to fail before the heal helper exists. Layer is **Flutter integration** (delivery plan §3.11.8 row J2; DP-3). Cases live under `frontend/test/unit/core/ai/context_required_self_heal_test.dart` and run via `flutter test` against injectable SDK / Resolver / manifest-refresh fakes — no live Worker. Permanent suite joins CI permanently (delivery plan §3.10).

**Organization**: One user story (US1, P1) — J2 is one slice, one story (delivery plan §2.6, overrides). No cross-story parallelism section. No Setup phase — plan Files names no harness/config that must exist first; `fakes.dart` extension is produced as the Tests-phase substrate (T001); library Files units land in Implementation. No Foundational or Polish phase — prerequisites are already-merged Needs (C2, E2, E3) in the plan's Consumes Binding.

**Task count**: 8 (≤25).

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: US1 (this slice has a single user story)
- Include exact file paths in descriptions

## Path Conventions

- **Flutter desktop app**: `frontend/lib/`, `frontend/test/`, `frontend/tool/`
- **Supabase backend**: `backend/migrations/`, `backend/functions/`, `backend/tests/` — *not touched by J2*
- **AI gateway Worker**: `ai-platform/src/`, `ai-platform/migrations/`, `ai-platform/test/` — *not touched by J2* (Consumes C2 payload only)
- **Spec Kit artifacts**: `specs/049-context-required-self-healing/`
- J2 is a client-side Flutter orchestration sibling under `frontend/lib/core/ai/` composing SDK + Resolver + injectable manifest refresh (Clarification Q1). `AiClientSdk` stays transport-only. Tests and fakes live under `frontend/test/unit/core/ai/`. No `ai-platform/` or `backend/` path is modified.

---

## Phase 1: Tests (written to fail before the code exists)

**Purpose**: Cover every named test in the spec's `### Test plan` (§3.11.8 row J2). All four cases share `frontend/test/unit/core/ai/context_required_self_heal_test.dart`. T001 also extends `frontend/test/unit/core/ai/fakes.dart` (plan Files test-support row — substrate, not repeated in Implementation). Until `frontend/lib/core/ai/context_required_self_heal.dart` and the `PlatformHttpException` C2 optional fields exist, imports/assertions fail — the intended red state. Order follows plan Sequencing themes (happy-path heal → second-rejection bound → no-third-attempt spy → conversational exclusion). All tasks touch the same primary test file, so none is `[P]` relative to another within this phase.

- [ ] T001 [US1] Add named test `stale_client_context_required_refreshes_resolves_resubmits_once_same_idempotency_key_and_succeeds` (test 1) in `frontend/test/unit/core/ai/context_required_self_heal_test.dart`: extend substrate `frontend/test/unit/core/ai/fakes.dart` so `SubmitHttpErrorStep` / `PlatformHttpException` can carry C2 missing-key fields (`missingKeys` / `shapes` / `manifestVersion` / `manifestCapabilityId`) and add a `ManifestRefreshPort` spy recording call count (Clarification Q2–Q3; plan Files) — and import the heal helper under test from `frontend/lib/core/ai/`. Assert refresh spy called once; Resolver receives the missing keys; exactly one automatic resubmit; same idempotency key; success through the normal pipeline (§8.4; §5.2 Self-healing; §3.11.8 J2). Fails red until C2 fields, refresh port, and heal orchestration exist. **Satisfies**: FR-002, FR-003, FR-004, FR-005 / SC-001. **Proves**: test 1.
- [ ] T002 [US1] Add named test `second_context_required_stops_and_surfaces_request_reference` (test 2) to `frontend/test/unit/core/ai/context_required_self_heal_test.dart`: after one heal resubmit, a second `context_required` for that action stops automatic recovery and surfaces the request reference to the user (§8.4; §3.11.8 J2). **Satisfies**: FR-006 / SC-002. **Proves**: test 2.
- [ ] T003 [US1] Add named test `no_automatic_third_attempt_after_second_context_required` (test 3) to `frontend/test/unit/core/ai/context_required_self_heal_test.dart`: spy case — submit / refresh / resolve call counts prove no third automatic attempt after the second `context_required` (§8.4; §3.11.8 J2; delivery plan §3.10 spy rule). **Satisfies**: FR-007 / SC-003. **Proves**: test 3.
- [ ] T004 [US1] Add named test `conversational_capabilities_never_take_context_required_self_heal_path` (test 4) to `frontend/test/unit/core/ai/context_required_self_heal_test.dart`: `interaction_mode: conversational` never enters the §8.4 heal path (no refresh / resolve / same-key resubmit) (§8.4; §5.2 Negotiation; §3.11.8 J2). **Satisfies**: FR-001, FR-008 / SC-004. **Proves**: test 4.

---

## Phase 2: Implementation (plan Files section)

**Purpose**: Implementation units from `plan.md` → Files not already produced as test substrates or Documentation: extend `ports.dart` and create the heal sibling module. `fakes.dart` and `context_required_self_heal_test.dart` are produced in Phase 1; `quickstart.md` in Phase 4. Order follows plan Sequencing (`PlatformHttpException` C2 fields → `ManifestRefreshPort` + heal orchestration). Consumed modules (E2 SDK transport, E3 Resolver, C2 payload shape) are bound as clients only — not rewritten beyond the reserved optional-field extension (delivery plan §2.3).

- [ ] T005 [US1] Extend `frontend/lib/core/ai/ports.dart` — add optional C2 fields on `PlatformHttpException` (`missingKeys` / `shapes` / `manifestVersion` / `manifestCapabilityId`, mirroring wire `missing_keys`, `shapes`, `manifest_version`, `manifest_capability_id`) when `code` is `context_required` (Clarification Q2). Existing callers omit the fields. Does not redefine C2 validator rules, `context_invalid`, cost pre-flight, or the wire payload shape (Consumes C2). **Satisfies**: FR-002. **Proved by**: tests 1–3 (and substrate for test 4 when a typed rejection is constructed).
- [ ] T006 [US1] Create `frontend/lib/core/ai/context_required_self_heal.dart` — injectable `ManifestRefreshPort` (Clarification Q3) + `single_shot`-only heal helper (Clarification Q1): on first `context_required`, refresh once → resolve `missing_keys` via E3 `ContextResolver.resolve` → resubmit once with the **same** idempotency key; on second `context_required`, stop and surface request reference (no third attempt); refuse conversational `interaction_mode`. Composes SDK + Resolver + refresh; `AiClientSdk` stays transport-only. No prompts, providers, or model identifiers (R-12). **Satisfies**: FR-001, FR-002, FR-003, FR-004, FR-005, FR-006, FR-007, FR-008. **Proved by**: tests 1–4.

---

## Phase 3: Verification

**Purpose**: Delivery plan §3.10 — every prior suite stays green alongside the new one, not just the latest. Also confirms plan Sequencing R-12 inheritance (new paths under `frontend/lib/core/ai/` remain covered by the E1 architecture guard).

- [ ] T007 [US1] From `frontend/`, run `flutter test test/unit/core/ai/context_required_self_heal_test.dart` (this slice's named cases 1–4). Confirm R-12 / E1: new paths under `frontend/lib/core/ai/` (including `context_required_self_heal.dart` and the `ports.dart` extension) still pass `dart run tool/architecture_guard/architecture_guard.dart` against clean client scan roots (Consumes E1; do not alter the guard). Keep prior Flutter AI suites green: `flutter test test/unit/core/ai/ai_client_sdk_test.dart` and `flutter test test/unit/core/ai/context_resolver_test.dart test/unit/core/ai/context_contract_test.dart`. Then from `ai-platform/`, run every prior slice's suite: `npx vitest run` (default Node-pool prior suites) and `npx vitest run --config vitest.workers.config.ts` (workers-pool prior suites). Confirm J2's named cases are green and every prior suite stays green. No new test is added here — this is the §3.10 checkpoint gate. **Satisfies**: the §3.10 checkpoint rule (tests 1–4 + prior suites). Proved by itself.

---

## Phase 4: Documentation

**Purpose**: Always present. The one documentation artifact the plan names that does not yet exist on disk (`quickstart.md`); written only after the suite is green. No other documentation artifact is named for a separate `[P]` task (no `ai-platform/README.md` — not the bootstrap slice; no `contracts/` — Freezes introduce no new wire shape).

- [ ] T008 [US1] Create `specs/049-context-required-self-healing/quickstart.md` from `.specify/templates/ai-platform-quickstart-template.md`, scoped to this slice only. **§1 Architecture context** — delivery plan §3.9 row J2; Implements §8.4 / §5.2; what the spec delivered; what the plan scoped. **§2 What was implemented** — `single_shot` `context_required` self-heal (refresh → resolve → one same-key resubmit); second surfaces request reference; conversational exclusion; `PlatformHttpException` C2 optional fields; injectable `ManifestRefreshPort`. **§3 Files to review** — only this slice's `frontend/lib/core/ai/` and `frontend/test/unit/core/ai/` files (no prior-slice files). **§4 Prerequisites** — omit or keep minimal (`flutter` / Dart SDK from `frontend/pubspec.yaml`); no live Worker. **§5 Run the automated suite** — slice-only `flutter test test/unit/core/ai/context_required_self_heal_test.dart`; no full-suite `npm test`, no combined prior-slice counts. **§6 Inspect the changes** — open the self-heal sibling module, `PlatformHttpException` C2 fields, and the focused test file; confirm E1 guard still covers `frontend/lib/core/ai/`. **No §7 Manual validation** — CI / `flutter test` is the verification path (J2 exposes no new user-visible surface beyond request-reference surfacing already owned by feature surfaces). **Slice-only scope explicit**: no prior-slice files in the review table, no combined test counts, no prior-slice regression commands. Not traced to an FR (template-mandated review surface).

---

## Dependencies & Execution Order

### Phase Dependencies

- **Tests (T001–T004)** — none beyond existing `frontend/` and Consumes Binding modules available as contracts; written to fail before `context_required_self_heal.dart` and the `PlatformHttpException` C2 fields exist. All named cases share `context_required_self_heal_test.dart` (sequential appends after T001 substrate). No `[P]` within Phase 1 (same primary test file).
- **Implementation (T005–T006)** — after tests exist (red). T005 (`ports.dart` C2 fields) first. T006 (`context_required_self_heal.dart`) depends on T005 and turns tests 1–4 green.
- **Verification (T007)** — depends on T001–T006; runs this slice's Flutter suite plus E1 guard check plus prior Flutter AI suites plus every prior `ai-platform/` suite per §3.10.
- **Documentation (T008)** — depends on T007 (the quickstart records a green suite).

### Within the Slice

- Tests written to fail before implementation; implementation makes them pass; verification confirms the whole suite including prior slices stays green.
- Plan Sequencing maps to Implementation order: `PlatformHttpException` C2 fields (T005) → `ManifestRefreshPort` + heal orchestration (T006). Test order mirrors behavioural themes (happy path T001 → second rejection T002 → no-third-attempt spy T003 → conversational exclusion T004).
- `fakes.dart` Files-section row is produced by T001 (test substrate); not repeated as an Implementation task. Remaining Files units: T005–T006 (library) and T008 (`quickstart.md`).

### Parallel Opportunities

- Phase 1: no `[P]` — all tests share `frontend/test/unit/core/ai/context_required_self_heal_test.dart` (T001 also extends `fakes.dart`, but later cases append to the same suite file).
- Phase 2: T005 then T006 are sequential (heal depends on C2 fields on `PlatformHttpException`). No `[P]`.
- Phase 4 (T008) is a single task — no `[P]`.

---

## Notes

- [P] tasks = different files, no dependencies. Within this slice's single-file test phase and sequential implementation chain there is no `[P]`.
- Every named test 1–4 from `spec.md` is covered by its own task; test 3 is the spy companion (call-count absence) kept separate from test 2's outcome assertion. No cases dropped. No unrelated tasks merged.
- Every task traces to an `FR-###` from `spec.md` (tests also state the `SC-###` they satisfy) — or to the §3.10 checkpoint / the template-mandated quickstart. No task adds a requirement the spec does not name. Clarifications Q1–Q3 guide how (sibling heal module; optional C2 fields on `PlatformHttpException`; injectable `ManifestRefreshPort`), not what.
- No Polish phase and no Foundational phase — Needs are C2, E2, E3 (already merged; Consumes Binding).
- Consumed modules are imported/bound, not rewritten beyond the reserved `PlatformHttpException` optional-field extension (delivery plan §2.3). No `ai-platform/` or `backend/` file is touched.
- Tests land before or alongside their implementation, never after (delivery plan §2.2).
- Preserve R-12 / §6.4: no prompt text, provider name, or model identifier in the Flutter client; no per-request server-side healing session; no §9.14 mechanism added because it looks prudent.
