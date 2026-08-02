# Tasks: First AI feature surface and degraded mode (E4)

**Input**: Design documents from `specs/038-first-ai-feature-surface/`

**Prerequisites**: `plan.md` (required), `spec.md` (required for the user story). `research.md` is never produced on this platform (the research is `docs/architecture/17-ai-platform.md`). `data-model.md` is not produced — E4 defines no D1 entities (spec Key Entities: not applicable). `contracts/ai-availability-flag.md` is named in the plan Files section and confirmed in Phase 4 (Documentation). `quickstart.md` is written in Phase 4.

**Tests**: Tests are mandatory on this platform (delivery plan §3.10). Every named test in the spec's `### Test plan` (T1–T21) is covered. Layer is **Flutter widget (spy)** (delivery plan §3.11.5 row E4; DP-3). Cases live under `frontend/test/widget/ai/` and run via `flutter test` against injectable spies/fakes for enrollment, SDK streams, network, and persistence/export probes — no live provider (spec Assumptions). Written to fail before the Feature Surfaces library exists.

**Task-cap combining**: Naive one-task-per-named-test (21) plus one task per Files implementation unit (~11) plus Verification plus Documentation exceeds 25. Per parent-workflow authorization and plan Scale/Scope ("when taxonomy client-behaviour cases and provisional prohibitions are grouped"), related named tests that share one file and one spy/outcome pattern are combined, and tightly coupled Files units (model+reader, mode+view, host+route wiring) are merged. No named tests dropped; no unrelated work merged. Combining map:

| Combined task | Named tests / Files units | Rationale |
| --- | --- | --- |
| T001 | T1–T2 | Provisional draft rules (visually distinct + no commit before `completed`); same file; Clarification Q3 |
| T002 | T3–T4 | §3.11.5 / Done when "accept and discard both behave"; same surface file |
| T003 | T5, T13–T14 | Taxonomy show-reference client behaviour; same spy pattern / `request_reference_view` |
| T004 | T6–T7, T16–T17 | Plan-named provisional prohibitions (§6.4 inv. 2): rebuild, restart, never exported, never persisted |
| T007 | T8, T21 | Non-enrolled no-network + availability-flag companion (spec Coverage / T21) |
| T010 | T11–T12 | Distinct first-class degraded states (quota vs offline vs AI-unavailable; A11) |
| T011 | T18–T19 | §5.4 hide-features / hide-affordance client behaviours; same degraded file |
| T013 | `ai_availability.dart` + `ai_availability_reader.dart` | Model + injectable reader for FR-008/009/012 |
| T014 | `ai_degraded_mode.dart` + `ai_degraded_view.dart` | State map + first-class UI (not error dialogs) |
| T018 | `ai_feature_host_page.dart` + `app_routes.dart` + `router.dart` | Standalone host + route wiring (Clarification Q2) |

Remaining named tests (T9, T10, T15, T20) and remaining Files units stay one task each.

**Organization**: One user story (US1, P1) — E4 is one slice, one story (delivery plan §2.6, overrides). No cross-story parallelism section. No Setup phase — harness lands in the Tests phase; library/migration Files units land in Implementation; contract confirm + quickstart in Documentation. No Foundational or Polish phase — prerequisites are already-merged Needs (E2, E3) in the plan's Consumes Binding.

**Task count**: 21 (≤25).

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: US1 (this slice has a single user story)
- Include exact file paths in descriptions

## Path Conventions

- **Flutter desktop app**: `frontend/lib/`, `frontend/test/`, `frontend/tool/`
- **Supabase backend**: `backend/supabase/migrations/`, `backend/tests/`
- **AI gateway Worker**: `ai-platform/src/`, `ai-platform/migrations/`, `ai-platform/test/` — *not touched by E4* (Consumes streaming/taxonomy via E2 SDK only)
- **Spec Kit artifacts**: `specs/038-first-ai-feature-surface/`
- E4 Feature Surfaces live under `frontend/lib/features/ai/` and import SDK/Resolver from `frontend/lib/core/ai/` (Clarification Q1). Widget suite under `frontend/test/widget/ai/`. AI availability flag migration under `backend/supabase/migrations/`. No `ai-platform/` path is modified.

---

## Phase 1: Tests (written to fail before the code exists)

**Purpose**: Cover every named test in the spec's `### Test plan` (§3.11.5 row E4 + coverage expansions). Surface cases share `frontend/test/widget/ai/first_ai_feature_surface_test.dart` (T1–T7, T13–T17, T20). Degraded/flag cases share `frontend/test/widget/ai/ai_degraded_mode_test.dart` (T8–T12, T18–T19, T21). T001 also creates `frontend/test/widget/ai/ai_surface_test_harness.dart` (plan Files test-support row — substrate, not repeated in Implementation). Until `frontend/lib/features/ai/` exists, imports fail to compile — the intended red state. Order follows plan Sequencing themes (provisional → accept/discard → references → provisional prohibitions → terminal authority / R-12 → degraded/flag).

- [X] T001 [US1] Add named tests `surface_provisional_content_visually_distinct` (T1) and `surface_no_commit_control_before_completed` (T2) in `frontend/test/widget/ai/first_ai_feature_surface_test.dart`: create substrate `frontend/test/widget/ai/ai_surface_test_harness.dart` — spies/fakes for SDK streams, Resolver, availability flag, reachability/network, persistence/export probes (plan Files; spec Assumptions) — and import Feature Surfaces under test from `frontend/lib/features/ai/`. Assert live/provisional prose is visually distinct as draft via stable test `Key` / Semantics + AI draft tokens `surfaceAi` / `textAi` / `borderAi` (Clarification Q3; §6.4; §4.1), and that no commit/save/accept control exists before terminal `completed` (§6.4 inv. 2; §3.11.5 E4). Fails red until provisional view + surface exist. **Satisfies**: FR-001, FR-003, FR-005 / SC-001. **Proves**: T1–T2.
- [X] T002 [US1] Add named tests `surface_accept_after_completed_behaves` (T3) and `surface_discard_behaves` (T4) to `frontend/test/widget/ai/first_ai_feature_surface_test.dart`: after terminal `completed`, accept acknowledges the validated terminal payload under `advisory_display` with no F2 clinical acceptance write; discard clears surface content and writes nothing to a clinical record (§4.1; Open Decision 1; §3.11.5 E4). **Satisfies**: FR-014 / SC-002. **Proves**: T3–T4.
- [X] T003 [US1] Add named tests `surface_failure_displays_request_reference` (T5), `surface_internal_error_shows_request_reference` (T13), and `surface_context_invalid_shows_request_reference` (T14) to `frontend/test/widget/ai/first_ai_feature_surface_test.dart`: on terminal `failed` (generic failure path, `internal_error`, and `context_invalid`), assert the request reference is displayed (§13.2; §5.4 Client behaviour; §3.11.5 E4). Same spy/outcome pattern across taxonomy show-reference codes. **Satisfies**: FR-006, FR-007, FR-013 / SC-003. **Proves**: T5, T13–T14.
- [X] T004 [US1] Add named tests `surface_provisional_does_not_survive_rebuild` (T6), `surface_provisional_does_not_survive_restart` (T7), `surface_provisional_never_exported` (T16), and `surface_provisional_never_persisted` (T17) to `frontend/test/widget/ai/first_ai_feature_surface_test.dart`: provisional (pre-`completed`) content does not survive widget rebuild or app-restart simulation; no export path emits it; persistence probe shows it is not written to durable local or clinic storage (§6.4 inv. 2; §4.1 Must not; plan-named provisional-prohibitions family). **Satisfies**: FR-002, FR-005 / SC-004. **Proves**: T6–T7, T16–T17.
- [X] T005 [US1] Add named test `surface_uses_terminal_payload_not_chunk_assembly` (T15) to `frontend/test/widget/ai/first_ai_feature_surface_test.dart`: after streaming content events and a terminal `completed` payload, the final displayed answer equals the validated terminal payload and is not a client assembly of deltas (§6.4 inv. 1; delivery plan §6.4). **Satisfies**: FR-004 / SC-007. **Proves**: T15.
- [X] T006 [US1] Add named test `surface_contains_no_prompt_provider_or_model_identifiers` (T20) to `frontend/test/widget/ai/first_ai_feature_surface_test.dart` (and/or invoke E1 guard against `frontend/lib/features/ai/`): feature-surface sources pass the E1 architecture guard (R-12; delivery plan §6.4; §4.1). Does not weaken or bypass `frontend/tool/architecture_guard/` (Consumes E1). **Satisfies**: FR-015 / SC-007. **Proves**: T20.
- [X] T007 [P] [US1] Add named tests `degraded_non_enrolled_hides_affordances_no_network` (T8) and `availability_flag_readable_without_platform_probe` (T21) in `frontend/test/widget/ai/ai_degraded_mode_test.dart`: create the degraded/flag suite file using harness spies from T001; assert non-enrolled shows no AI affordances and spy shows zero AI-platform network calls; enrollment/availability and platform base URL are read from the clinic-side AI availability flag with no platform probe on the non-enrolled path (§4.2; §3.11.5 E4; T21 companion to T8). Depends on T001 harness. Fails red until availability gate + host exist. **Satisfies**: FR-008, FR-009 / SC-005. **Proves**: T8, T21.
- [X] T008 [US1] Add named test `degraded_unreachable_is_normal_state_not_error_dialog` (T9) to `frontend/test/widget/ai/ai_degraded_mode_test.dart`: enrolled but unreachable platform renders a normal unreachable/offline state, not an error dialog; clinical non-AI workflows remain usable (A11; §3.11.5 E4). **Satisfies**: FR-010, FR-011 / SC-006. **Proves**: T9.
- [X] T009 [US1] Add named test `degraded_enrolled_reachable_shows_affordances` (T10) to `frontend/test/widget/ai/ai_degraded_mode_test.dart`: enrolled and reachable shows AI affordances (§4.2; §3.11.5 E4). **Satisfies**: FR-012 / SC-005. **Proves**: T10.
- [X] T010 [US1] Add named tests `degraded_quota_exhausted_distinct_state` (T11) and `degraded_ai_unavailable_distinct_from_offline_and_quota` (T12) to `frontend/test/widget/ai/ai_degraded_mode_test.dart`: `quota_exhausted` shows a distinct first-class quota UI; AI-unavailable presentation is distinct from offline/unreachable and from quota exhausted (A11; §5.4). **Satisfies**: FR-010, FR-013 / SC-006. **Proves**: T11–T12.
- [X] T011 [US1] Add named tests `surface_installation_suspended_hides_ai_features` (T18) and `surface_forbidden_capability_hides_affordance` (T19) to `frontend/test/widget/ai/ai_degraded_mode_test.dart`: `installation_suspended` hides AI features with clinical workflows usable; `forbidden_capability` hides the affordance for this role (§5.4 Client behaviour; A11). **Satisfies**: FR-013 / SC-006. **Proves**: T18–T19.

---

## Phase 2: Implementation (plan Files section)

**Purpose**: Implementation units from `plan.md` → Files not already produced as test substrates or Documentation: clinic availability migration; Flutter modules under `frontend/lib/features/ai/`; host route wiring. `ai_surface_test_harness.dart` and the two widget suites are produced in Phase 1; `contracts/ai-availability-flag.md` and `quickstart.md` in Phase 4. Order follows plan Sequencing (availability flag → degraded mode → provisional view → surface → host/route). Consumed modules (E2 SDK, E3 Resolver, E1 guard, A2/A6 taxonomy via SDK) are bound as clients only — not modified (delivery plan §2.3). No `ai-platform/` file is touched.

- [X] T012 [P] [US1] Create `backend/supabase/migrations/20260802140000_ai_availability_flag.sql` — seed `ai.availability` on `ai_internal.app_settings` with `value_json` `{ enrolled, platform_base_url }`; `auth_internal` + `public.get_ai_availability()` returning that shape; default non-enrolled (Open Decision 8; `contracts/ai-availability-flag.md`). Parallel with the Flutter library chain (different layer). **Satisfies**: FR-008, FR-009. **Proved by**: T8, T10, T21 (via injectable reader doubles; migration is the production store).
- [X] T013 [US1] Create `frontend/lib/features/ai/availability/ai_availability.dart` and `frontend/lib/features/ai/availability/ai_availability_reader.dart` — `{ enrolled, platformBaseUrl }` model + injectable port, and production reader of `get_ai_availability` that never probes the AI platform to discover enrollment (FR-008/009/012; Clarification Q1). Test doubles feed T8/T10/T21. **Satisfies**: FR-008, FR-009, FR-012. **Proved by**: T8, T10, T21.
- [X] T014 [US1] Create `frontend/lib/features/ai/degraded/ai_degraded_mode.dart` and `frontend/lib/features/ai/degraded/ai_degraded_view.dart` — distinct first-class states (non-enrolled, unreachable/offline, quota exhausted, AI unavailable, installation suspended, forbidden capability) mapping §5.4 Client behaviours; normal-state UI so unreachable is not an error dialog and AI failure never blocks clinical workflows (A11; FR-010–013). **Satisfies**: FR-010, FR-011, FR-013. **Proved by**: T8–T12, T18–T19.
- [X] T015 [P] [US1] Create `frontend/lib/features/ai/surface/provisional_prose_view.dart` — live provisional prose with draft `Key` / Semantics + `surfaceAi` / `textAi` / `borderAi` tokens (Clarification Q3; FR-001, FR-003, FR-005). **Satisfies**: FR-001, FR-003, FR-005. **Proved by**: T1–T2 (and substrate for T6–T7, T16–T17).
- [X] T016 [P] [US1] Create `frontend/lib/features/ai/surface/request_reference_view.dart` — displays request reference on failure; uses SDK-retained last reference so reporting after screen close remains possible (§13.2; Consumes E2). **Satisfies**: FR-006, FR-007. **Proved by**: T5, T13–T14.
- [X] T017 [US1] Create `frontend/lib/features/ai/surface/first_ai_feature_surface.dart` — first capability surface (`clinic.visit_summary`, `prose`, `advisory_display`): resolve context via E3, invoke via E2, render provisional, enable accept/discard only after `completed`, use terminal payload (not chunk assembly), never persist/export provisional, apply taxonomy client behaviours; no prompts/providers/model identifiers (R-12). Depends on T013–T016. **Satisfies**: FR-001–FR-007, FR-013–FR-016. **Proved by**: T1–T7, T13–T17, T20.
- [X] T018 [US1] Create `frontend/lib/features/ai/host/ai_feature_host_page.dart` and modify `frontend/lib/app/app_routes.dart` + `frontend/lib/app/router.dart` — standalone host composing availability gate + surface for widget tests and CP3 entry; register route constant and route (Clarification Q2; not embedded in a production clinical screen). Depends on T013–T014 and T017. **Satisfies**: FR-001, FR-009, FR-012. **Proved by**: T8–T10, T21 (host gate); surface suite via host composition as needed.

---

## Phase 3: Verification

**Purpose**: Delivery plan §3.10 — every prior suite stays green alongside the new one, not just the latest.

- [X] T019 [US1] From `frontend/`, run `flutter test test/widget/ai/first_ai_feature_surface_test.dart test/widget/ai/ai_degraded_mode_test.dart` (this slice's named cases T1–T21). Confirm FR-015 / E1: paths under `frontend/lib/features/ai/` still pass `dart run tool/architecture_guard/architecture_guard.dart` against clean client scan roots (Consumes E1; do not alter the guard). Keep prior Band E Flutter suites green: `flutter test test/unit/core/ai/ai_client_sdk_test.dart test/unit/core/ai/context_resolver_test.dart test/unit/core/ai/context_contract_test.dart`. From `backend/`, run `bash backend/tests/run_ai_platform_trust_tests.sh` (prior SQL/RLS suites; this slice does not append a new SQL suite file — plan Files marks the trust runner UNCHANGED). Then from `ai-platform/`, run every prior slice's suite: `npx vitest run` (default Node-pool prior suites) and `npx vitest run --config vitest.workers.config.ts` (workers-pool prior suites). Confirm E4's named cases are green and every prior suite stays green. No new test is added here — this is the §3.10 checkpoint gate. **Satisfies**: the §3.10 checkpoint rule (T1–T21 + prior suites). Proved by itself.

---

## Phase 4: Documentation

**Purpose**: Always present. Documentation artifacts the plan names: confirm the Freezes contract already authored at plan time, and write `quickstart.md`. Written/confirmed after the suite is green. Contract and quickstart touch different paths, so the contract task is `[P]` relative to quickstart only if both are ready after Verification; otherwise confirm contract then write quickstart. No other documentation artifact is named for a separate task (no `ai-platform/README.md` — not the bootstrap slice).

- [X] T020 [P] [US1] Confirm frozen content of `specs/038-first-ai-feature-surface/contracts/ai-availability-flag.md` — clinic-readable shape `{ enrolled, platform_base_url }`, storage on `ai_internal.app_settings` key `ai.availability`, `get_ai_availability` read path, non-enrolled default / no platform probe rule; source-of-truth pointers to the migration and Flutter availability reader. Later slices consume this artifact, not prose (DP-4; delivery plan §2.3). **Satisfies**: Freezes — AI availability flag clinic-side store (plan Files; FR-008, FR-009, FR-012).
- [X] T021 [US1] Create `specs/038-first-ai-feature-surface/quickstart.md` from `.specify/templates/ai-platform-quickstart-template.md`, scoped to this slice only. **§1 Architecture context** — delivery plan §3.6 row E4; `17-ai-platform.md` §4.1 / §6.4 / §13.2 / §4.2 / §5.4 / A11; what the spec delivered; what the plan scoped. **§2 What was implemented** — first AI Feature Surface (`prose` / `advisory_display`); degraded-mode states; AI availability flag + read RPC; standalone host for tests/CP3. **§3 Files to review** — only this slice's `frontend/lib/features/ai/`, `frontend/test/widget/ai/`, the availability migration, route wiring touched here, and `contracts/ai-availability-flag.md` (no prior-slice files). **§4 Prerequisites** — omit or keep minimal (`flutter` / Dart SDK from `frontend/pubspec.yaml`; local Supabase only if manually exercising the RPC). **§5 Run the automated suite** — slice-only `flutter test test/widget/ai/first_ai_feature_surface_test.dart test/widget/ai/ai_degraded_mode_test.dart`; no full-suite `npm test`, no combined prior-slice counts. **§6 Inspect the changes** — open the surface widget, degraded states, availability contract, and a focused widget test; confirm E1 guard still covers `frontend/lib/features/ai/`. **§7 Manual validation** — optional: open the standalone AI host route when enrolled (CP3 entry with D4); confirm provisional draft styling and degraded states visually. Widget suite remains the primary verification path (DP-3). **Slice-only scope explicit**: no prior-slice files in the review table, no combined test counts, no prior-slice regression commands. Not traced to an FR (template-mandated review surface).

---

## Dependencies & Execution Order

### Phase Dependencies

- **Tests (T001–T011)** — none beyond existing `frontend/` and Consumes Binding modules available as contracts; written to fail before `frontend/lib/features/ai/` exists. T001 creates the harness + starts the surface suite. T002–T006 append to `first_ai_feature_surface_test.dart`. T007 creates `ai_degraded_mode_test.dart` after the harness (T001); T008–T011 append.
- **Implementation (T012–T018)** — after tests exist (red). T012 (migration) is `[P]` with the Flutter chain. T013 (availability) first on the Flutter side. T014 (degraded) after T013. T015 and T016 are `[P]` relative to each other after T013 (different surface files). T017 (surface) depends on T013–T016. T018 (host + routes) depends on T013–T014 and T017.
- **Verification (T019)** — depends on T001–T018; runs this slice's Flutter widget suite plus E1 guard check plus every prior suite per §3.10.
- **Documentation (T020–T021)** — depends on T019 (contract confirm / quickstart record a green suite). T020 is `[P]` relative to T021.

### Within the Slice

- Tests written to fail before implementation; implementation makes them pass; verification confirms the whole suite including prior slices stays green.
- Plan Sequencing maps to Implementation order: availability migration + Dart reader (T012–T013) → degraded mode/view (T014) → provisional + request-reference views (T015–T016) → surface (T017) → host/route (T018); Documentation last.
- `ai_surface_test_harness.dart` and the two widget test files are produced by Phase 1; not repeated as Implementation tasks. Remaining Files units: T012–T018 (library / migration / routes) and T020–T021 (contract + quickstart).

### Parallel Opportunities

- Phase 1: T007 `[P]` (degraded suite file) can proceed after T001's harness lands, in parallel with T002–T006. Within each shared test file, appends are sequential.
- Phase 2: T012 is `[P]` relative to T013–T018 (backend vs Flutter). T015 and T016 are `[P]` relative to each other after T013. T014 follows T013; T017 follows T013–T016; T018 follows T017.
- Phase 4: T020 and T021 are `[P]` relative to each other after Verification.

---

## Notes

- [P] tasks = different files, no dependencies. Marked: T007, T012, T015, T016, T020.
- Every named test T1–T21 from `spec.md` is covered: standalone where distinct (T9, T10, T15, T20); combined only where related, same file, and same spy/outcome family (see header combining map). No cases dropped.
- Every task traces to an `FR-###` from `spec.md` (tests also state the `SC-###` they satisfy) — or to Freezes / the §3.10 checkpoint / the template-mandated quickstart. No task adds a requirement the spec does not name. Clarifications Q1–Q3 guide how (`features/ai/`; standalone host; Key/Semantics + AI tokens), not what.
- No Polish phase and no Foundational phase — Needs are E2, E3 (already merged; Consumes Binding).
- Consumed modules are imported/bound, not modified (delivery plan §2.3 — extend, never rewrite). No `ai-platform/` file is touched.
- Tests land before or alongside their implementation, never after (delivery plan §2.2).
- Preserve R-12 / §6.4: no prompt text, provider name, or model identifier in the Flutter client; no client-side assembly of a final result from chunks; no committable provisional content; AI never blocks clinical workflows (A11).
