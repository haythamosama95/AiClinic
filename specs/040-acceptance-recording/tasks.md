# Tasks: Acceptance recording RPC and client accept path (F2)

**Input**: Design documents from `specs/040-acceptance-recording/`

**Prerequisites**: `plan.md` (required), `spec.md` (required for the user story). `research.md` is never produced on this platform (the research is `docs/architecture/17-ai-platform.md`). `data-model.md` is not produced — F2 defines clinic-side Supabase entities, not D1 entities (entity shapes live in `contracts/acceptance-recording.md`). `contracts/acceptance-recording.md` is already frozen on disk (written during the plan phase per DP-4). `quickstart.md` is written in Phase 4 (Documentation).

**Tests**: Tests are mandatory on this platform (delivery plan §3.10). Every named test in the spec's `### Test plan` (T1–T10) is covered by its own task, written to fail before the RPC and clinical accept path exist. Spy cases T6, T7, and T8 are separate tasks from outcome cases. Layer is **SQL + Flutter** (delivery plan §3.11.6 row F2; DP-3). SQL cases live under `backend/tests/ai_acceptance_recording.sql`; Flutter widget/spy cases under `frontend/test/widget/ai/clinical_accept_path_test.dart` (unit support under `frontend/test/unit/ai/clinical_acceptance_client_test.dart`).

**Organization**: One user story (US1, P1) — F2 is one slice, one story (delivery plan §2.6, overrides). No cross-story parallelism section. No Setup phase — contracts are already on disk; plan Files are created by Tests/Implementation. No Foundational or Polish phase — prerequisites are already-merged Needs (E4, C3) in the plan's Consumes Binding.

**Task count**: 19 (≤25).

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: US1 (this slice has a single user story)
- Include exact file paths in descriptions

## Path Conventions

- **Flutter desktop app**: `frontend/lib/`, `frontend/test/`
- **Supabase backend**: `backend/supabase/migrations/`, `backend/tests/`
- **AI gateway Worker**: `ai-platform/src/`, `ai-platform/migrations/`, `ai-platform/test/` — *not touched by F2* (acceptance is clinic-side only; no D1 journal of acceptance)
- **Spec Kit artifacts**: `specs/040-acceptance-recording/`
- Clinic acceptance lives under `backend/` (migration + SQL suite) and `frontend/lib/features/ai/acceptance/` (clinical accept library — harness/tests; not a production Feature Surface). Demonstration proof uses existing `public.save_visit_documentation` (not modified). No `ai-platform/` path is modified.

---

## Phase 1: Tests (written to fail before the code exists)

**Purpose**: One task per named test in the spec's `### Test plan` (§3.11.6 row F2 + §3.10 coverage additions T6–T10). SQL cases share `backend/tests/ai_acceptance_recording.sql` (T1–T2, T5–T6, T9–T10, plus SQL-side asserts for T3–T4). Flutter cases share `frontend/test/widget/ai/clinical_accept_path_test.dart` (T1, T3–T4, T7–T8). Until the migration and `frontend/lib/features/ai/acceptance/` exist, SQL assertions fail and Flutter imports fail to compile — the intended red state. Order follows plan Sequencing themes (unregistered / provenance / boundary / delegated / demo → atomicity → discard / unaccepted → no auto-commit → advisory_display unchanged), with the first SQL suite file and the first Flutter suite file marked `[P]` relative to each other.

- [X] T001 [US1] Add named test `unregistered_target_key_rejected` (T5) to `backend/tests/ai_acceptance_recording.sql`: create the SQL suite substrate (existing `BEGIN … CREATE TEMP TABLE … DO $$ … RAISE EXCEPTION on failure … COMMIT … SELECT` pattern used by other `backend/tests/*.sql` trust suites). Assert `public.record_ai_acceptance` with a `p_target_key` absent from `ai_internal.acceptance_targets` is rejected before any write — no domain change, no `ai_accepted_output` row, no `audit_log` entry (§4.2.2; §3.11.6 F2). Fails red until registry + RPC exist. **Satisfies**: FR-003, FR-004 / SC-005. **Proves**: T5.
- [X] T002 [P] [US1] Add named test `clinical_accept_never_auto_commits` (T7) to `frontend/test/widget/ai/clinical_accept_path_test.dart`: create the Flutter widget/spy suite substrate with injectable doubles for the clinical acceptance port and E4 surface affordances. Assert no path auto-commits AI output into a clinical record without the explicit human accept action (A5; §4.1 Must not; delivery plan §6.4) — spy shows zero `record_ai_acceptance` invocations until accept is pressed. Fails red until port/controller exist. **Satisfies**: FR-012, FR-014 / SC-006. **Proves**: T7. `[P]` vs T001 — different test file.
- [X] T003 [US1] Add named test `acceptance_audit_log_bidirectional_provenance` (T2) to `backend/tests/ai_acceptance_recording.sql`: after a successful acceptance against `visit_clinical_notes` → `public.save_visit_documentation`, assert an `audit_log` entry with `action = 'ai.acceptance_record'` exists and provenance resolves both ways between the domain row `(table_name, record_id)` and `ai_request_reference` via `ai_accepted_output` / `audit_log.new_data_json` (§4.2.2; §3.11.6 F2). **Satisfies**: FR-008, FR-010 / SC-002. **Proves**: T2.
- [X] T004 [US1] Add named test `acceptance_rpc_does_not_store_ai_request_state` (T6) to `backend/tests/ai_acceptance_recording.sql` (spy): assert the clinic DB gains the acceptance fact only — `ai_accepted_output` columns match §4.2.2 and deliberately omit capability id, model, provider, prompt, token counts, cost, and request state; no prompts/providers/quotas/AI request-state columns beyond those named (§4.2 boundary note; §4.2.2; §3.10). **Satisfies**: FR-007, FR-016 / SC-006. **Proves**: T6.
- [X] T005 [US1] Add named test `delegated_rpc_errors_pass_through_unchanged` (T9) to `backend/tests/ai_acceptance_recording.sql`: on delegated domain RPC failure, assert `record_ai_acceptance` returns that RPC's `error_code` / `error_message` unchanged, writes nothing (no domain / acceptance / audit rows), and adds no new clinic or platform error vocabulary (§4.2.2). **Satisfies**: FR-005 / SC-006. **Proves**: T9.
- [X] T006 [US1] Add named test `demonstration_target_does_not_promote_capability` (T10) to `backend/tests/ai_acceptance_recording.sql` (+ pin against `specs/040-acceptance-recording/contracts/acceptance-recording.md`): assert registry row `visit_clinical_notes` → `public.save_visit_documentation` (table `public.visit_clinical_notes`) exists for proof only, and this slice does not grant any product capability `human_accept_required` writing (Open Decision 1; §4.2.2; Done when). **Satisfies**: FR-011, FR-018 / SC-006. **Proves**: T10.
- [X] T007 [US1] Add named test `acceptance_writes_domain_change_and_request_reference_together` (T1) to `backend/tests/ai_acceptance_recording.sql` and `frontend/test/widget/ai/clinical_accept_path_test.dart`: against `visit_clinical_notes` → `public.save_visit_documentation`, assert the domain change, `ai_accepted_output` row (carrying the AI request reference), and acceptance `audit_log` commit together or not at all; Flutter half drives explicit accept through the clinical accept **library** (harness/tests, not a production Feature Surface) invoking `record_ai_acceptance` with demonstration-target args (§4.2.2; Done when; §3.11.6 F2). **Satisfies**: FR-001, FR-002, FR-006, FR-009, FR-013 / SC-001. **Proves**: T1.
- [X] T008 [US1] Add named test `discard_path_writes_nothing` (T3) to `backend/tests/ai_acceptance_recording.sql` (precondition/count) and `frontend/test/widget/ai/clinical_accept_path_test.dart`: when the user discards validated or still-visible draft AI content, assert no domain change, no `ai_accepted_output` row, and no acceptance `audit_log` entry (§4.1; §3.11.6 F2). **Satisfies**: FR-013 / SC-003. **Proves**: T3.
- [X] T009 [US1] Add named test `unaccepted_content_never_persisted` (T4) to `backend/tests/ai_acceptance_recording.sql` and `frontend/test/widget/ai/clinical_accept_path_test.dart`: for provisional, discarded, or merely displayed AI content, assert durable clinic storage and clinical records show no clinical write of that unaccepted content (§4.1 Must not; A5; §3.11.6 F2). **Satisfies**: FR-013, FR-014 / SC-004. **Proves**: T4.
- [X] T010 [US1] Add named test `advisory_display_accept_unchanged` (T8) to `frontend/test/widget/ai/clinical_accept_path_test.dart` (spy): assert first-capability `advisory_display` accept from E4 still does not invoke `record_ai_acceptance` / the clinical acceptance recording write (Open Decision 1; §4.2.2; Consumes E4). Does not redefine E4 provisional styling or degraded-mode UX. **Satisfies**: FR-018 / SC-006. **Proves**: T8.

---

## Phase 2: Implementation (plan Files section)

**Purpose**: Implementation units from `plan.md` → Files not already produced as test substrates or Documentation: clinic migration (registry, `ai_accepted_output`, `record_ai_acceptance`, demonstration seed); Flutter clinical accept module family; unit coverage for RPC arg mapping; CI wiring of the SQL suite. Test files `ai_acceptance_recording.sql` and `clinical_accept_path_test.dart` are produced in Phase 1; `contracts/acceptance-recording.md` and `quickstart.md` in Phase 4. Order follows plan Sequencing (clinic schema + RPC → Flutter accept path → CI wiring). Consumed modules (E4 surfaces, C3/E2 request reference) are bound as clients only — not modified (delivery plan §2.3). `public.save_visit_documentation` is not modified. No `ai-platform/` file is touched.

- [X] T011 [US1] Create `backend/supabase/migrations/20260802150000_ai_acceptance_recording.sql` — `ai_internal.acceptance_targets(target_key, domain_function, table_name)`; `public.ai_accepted_output` with §4.2.2 columns/types/constraints (unique on `(table_name, record_id, ai_request_reference)`; indexes on `ai_request_reference` and `(table_name, record_id)`; §8.9-format CHECK on `ai_request_reference`; RLS); `auth_internal.record_ai_acceptance` `SECURITY DEFINER` + `public.record_ai_acceptance` INVOKER wrapper `(p_request_reference text, p_target_key text, p_target_args jsonb) RETURNS public.rpc_result`; seed demonstration target `visit_clinical_notes` → `public.save_visit_documentation` / table `visit_clinical_notes`; atomic transaction writes delegated domain change + `ai_accepted_output` + `audit_log` (`action = 'ai.acceptance_record'`) together or not at all; success `data` merges `{"acceptance_id","table_name","record_id","audit_log_id"}` with delegated `data`; delegated failures pass through unchanged; unregistered keys rejected pre-write (FR-001–FR-011, FR-015–FR-016, FR-019). **Satisfies**: FR-001–FR-011, FR-015–FR-016, FR-019. **Proved by**: T1, T2, T5, T6, T9, T10.
- [X] T012 [P] [US1] Create `frontend/lib/features/ai/acceptance/clinical_acceptance_port.dart` — injectable port for invoking `record_ai_acceptance` (test doubles for widget spies). No prompts, providers, models, or AI business rules (FR-017; R-12). **Satisfies**: FR-012–FR-014, FR-017. **Proved by**: T1, T3, T4, T7. `[P]` vs T011 — different layer/path.
- [X] T013 [US1] Create `frontend/lib/features/ai/acceptance/clinical_acceptance_client.dart` — production Supabase RPC caller for `public.record_ai_acceptance` with request reference + registered `p_target_key` + `p_target_args`; no prompts/providers/models/business rules (FR-017; R-12). Depends on T012. **Satisfies**: FR-001, FR-012–FR-013, FR-017. **Proved by**: T1 (unit support via T015).
- [X] T014 [US1] Create `frontend/lib/features/ai/acceptance/clinical_accept_controller.dart` — clinical accept library invokes the port/RPC with the retained request reference and registered demonstration target; discard writes nothing; not wired into E4 `advisory_display` acknowledge path (FR-018). Depends on T012–T013. **Satisfies**: FR-012–FR-014, FR-018. **Proved by**: T1, T3, T4, T7, T8.
- [X] T015 [P] [US1] Create `frontend/test/unit/ai/clinical_acceptance_client_test.dart` — unit coverage for RPC parameter mapping / no auto-commit helper behaviour (supports T1 and T7). **Satisfies**: FR-013, FR-017. **Proved by**: T1, T7. `[P]` vs T011–T014 once client API shape is stubbed — different path from migration/controller sources.
- [X] T016 [US1] Modify `backend/tests/run_ai_platform_trust_tests.sh` — append `ai_acceptance_recording.sql` so this slice's SQL suite joins CI permanently (delivery plan §3.10). **Satisfies**: CI wiring for T1–T2, T5–T6, T9–T10. **Proved by**: T1, T2, T5, T6, T9, T10 (permanent SQL home).

---

## Phase 3: Verification

**Purpose**: Delivery plan §3.10 — every prior suite stays green alongside the new one, not just the latest.

- [X] T017 [US1] From `backend/`, run `bash backend/tests/run_ai_platform_trust_tests.sh` (includes this slice's `ai_acceptance_recording.sql` plus prior SQL/RLS trust suites). From `frontend/`, run `flutter test test/widget/ai/clinical_accept_path_test.dart test/unit/ai/clinical_acceptance_client_test.dart` (this slice's Flutter named cases T1/T3/T4/T7/T8 + unit support). Confirm FR-017 / E1: paths under `frontend/lib/features/ai/acceptance/` still pass `dart run tool/architecture_guard/architecture_guard.dart` against clean client scan roots (Consumes E1; do not alter the guard). Keep prior Band E Flutter suites green: `flutter test test/widget/ai/first_ai_feature_surface_test.dart test/widget/ai/ai_degraded_mode_test.dart` (and prior E2/E3 unit suites as already wired). Then from `ai-platform/`, run every prior slice's suite: `npx vitest run` (default Node-pool) and `npx vitest run --config vitest.workers.config.ts` (workers-pool), including F1 eval entries under `test/eval/` as already gated. Confirm F2's ten named cases are green and every prior suite stays green. No new test is added here — this is the §3.10 checkpoint gate. **Satisfies**: the §3.10 checkpoint rule (T1–T10 + prior suites). Proved by itself.

---

## Phase 4: Documentation

**Purpose**: Always present. Documentation artifacts the plan names: confirm the Freezes contract already authored at plan time, and write `quickstart.md`. Written/confirmed after the suite is green. Contract and quickstart touch different paths, so the contract task is `[P]` relative to quickstart. No other documentation artifact is named for a separate task (no `ai-platform/README.md` — not the bootstrap slice).

- [X] T018 [P] [US1] Confirm frozen content of `specs/040-acceptance-recording/contracts/acceptance-recording.md` — RPC signature and success/failure contract; `ai_internal.acceptance_targets` registry; `public.ai_accepted_output` columns/constraints/indexes and deliberate omissions; `ai.acceptance_record` audit join; demonstration target `visit_clinical_notes` → `public.save_visit_documentation`; single shared acceptance path (Open Decision 14). Later slices consume this artifact, not prose (DP-4; delivery plan §2.3). **Satisfies**: Freezes (plan Files; FR-001–FR-011, FR-015–FR-016, FR-019).
- [X] T019 [US1] Create `specs/040-acceptance-recording/quickstart.md` from `.specify/templates/ai-platform-quickstart-template.md`, scoped to this slice only. **§1 Architecture context** — delivery plan §3.7 row F2; `17-ai-platform.md` §4.2 / §4.2.2 / §4.1 / A5; what the spec delivered; what the plan scoped. **§2 What was implemented** — `record_ai_acceptance`, registry + demonstration target, `ai_accepted_output`, clinical accept **library** beside E4 (harness/tests; not wired into the E4 `advisory_display` surface). **§3 Files to review** — only this slice's migration(s) including `20260805150000_f2_review_resolution.sql`, `frontend/lib/features/ai/acceptance/`, SQL + Flutter test files, and `contracts/acceptance-recording.md` (no prior-slice files). **§4 Prerequisites** — omit or keep minimal (local Supabase for SQL; Flutter/Dart SDK from `frontend/pubspec.yaml`). **§5 Run the automated suite** — slice-only SQL (`psql -f backend/tests/ai_acceptance_recording.sql` / trust-runner entry for this slice's SQL file) and `flutter test test/widget/ai/clinical_accept_path_test.dart test/unit/ai/clinical_acceptance_client_test.dart`; no full-suite `npm test`, no combined prior-slice counts. **§6 Inspect the changes** — `\df+ public.record_ai_acceptance`, registry row, `ai_accepted_output` columns, clinical accept library, focused SQL/Flutter tests. **§7 Manual validation** — optional: drive the clinical accept harness (test fixture / library, not a runnable product surface) against a local visit documentation save via the demonstration target. Omit detailed deploy steps — SQL + Flutter suites are the primary verification path (DP-3). **Slice-only scope explicit**: no prior-slice files in the review table, no combined test counts, no prior-slice regression commands. Not traced to an FR (template-mandated review surface).

---

## Dependencies & Execution Order

### Phase Dependencies

- **Tests (T001–T010)** — none beyond already-frozen contracts and Consumes Binding modules (E4, C3/E2); written to fail before the migration and acceptance library exist. T001 creates `ai_acceptance_recording.sql`. T002 `[P]` creates `clinical_accept_path_test.dart`. T003–T006 append to the SQL file. T007–T009 append to both SQL and Flutter files as needed. T010 appends to the Flutter file.
- **Implementation (T011–T016)** — after tests exist (red). T011 (migration) first on the clinic side. T012 `[P]` (port) relative to T011 (Flutter vs backend). T013 (client) after T012. T014 (controller) after T012–T013. T015 `[P]` (unit test) after client API is available. T016 (trust runner) after the SQL suite file exists (T001).
- **Verification (T017)** — depends on T001–T016; runs this slice plus every prior slice per §3.10.
- **Documentation (T018–T019)** — depends on T017 (contract confirm / quickstart record a green suite). T018 is `[P]` relative to T019.

### Within the Slice

- Tests written to fail before implementation; implementation makes them pass; verification confirms the whole suite including prior slices stays green.
- Plan Sequencing maps to Implementation order: clinic schema + RPC (T011) unlocks SQL cases T1/T2/T5/T6/T9/T10 → Flutter port/client/controller (T012–T014) unlocks T1/T3/T4/T7/T8 → unit support (T015) → CI wiring (T016) → quickstart (T019).
- SQL and Flutter test files are produced by Phase 1; not repeated as Implementation tasks. Remaining Files units: T011–T016 (migration / Flutter modules / unit / trust runner) and T018–T019 (contract confirm + quickstart).

### Parallel Opportunities

- Phase 1: T002 `[P]` (`clinical_accept_path_test.dart`) can proceed in parallel with T001 (`ai_acceptance_recording.sql`) — different files. Within each shared test file, appends are sequential.
- Phase 2: T012 is `[P]` relative to T011 (backend vs Flutter). T015 is `[P]` relative to controller work once the client shape exists. T013 follows T012; T014 follows T013; T016 follows the SQL suite file.
- Phase 4: T018 and T019 are `[P]` relative to each other after Verification.

---

## Notes

- [P] tasks = different files, no dependencies. Marked: T002, T012, T015, T018.
- Every named test T1–T10 from `spec.md` is covered by its own task; spy cases T6, T7, and T8 are not folded into outcome cases.
- Every task traces to an `FR-###` from `spec.md` (tests also state the `SC-###` they satisfy) — or to Freezes / the §3.10 checkpoint / the template-mandated quickstart. No task adds a requirement the spec does not name.
- No Polish phase and no Foundational phase — Needs are E4, C3 (already merged; Consumes Binding).
- Consumed modules are imported/bound, not modified (delivery plan §2.3 — extend, never rewrite). No `ai-platform/` file is touched. `public.save_visit_documentation` is not modified.
- Tests land before or alongside their implementation, never after (delivery plan §2.2).
- Preserve §6.4 / A5: no auto-commit; discard writes nothing; unaccepted content never persisted; no prompt/provider/model identifiers in Flutter (R-12); no second acceptance path; clinic stores the request-reference handle only.
