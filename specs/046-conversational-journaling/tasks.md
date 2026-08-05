---

description: "Task list for AI platform slice H3 — Conversational journaling and client chat surface"
---

# Tasks: Conversational journaling and client chat surface (H3)

**Input**: Design documents from `/specs/046-conversational-journaling/`

**Prerequisites**: `plan.md` (required), `spec.md` (required for the user story). `research.md` is never produced on this platform (the research is `docs/architecture/17-ai-platform.md`). `data-model.md` is omitted — H3 defines no D1 entity; columns were reserved in A5 (spec Key Entities; FR-002, FR-004). `contracts/conversational-journaling.md` is already frozen on disk (written during the plan phase). `quickstart.md` is named in the plan and filled in Phase 4 (Documentation).

**Tests**: Mandatory, not optional (delivery plan §3.10 overrides the template). Every named test in the spec's Test plan — including the eight §3.10 coverage additions — must appear in some task's acceptance criteria and be written to fail before the matching implementation exists. Related cases that share one test file (or one Sequencing step) are grouped into a single task where noted under **Task-cap combining**; grouping does not drop coverage.

**Task-cap combining**: Naive count was 29 (19 named-test tasks + 8 Files implementation units + verification + quickstart). Per parent-workflow authorization, only these four related merges are applied (29 → **24**); optional combinations 5–10 are **not** applied:

1. `vitest.workers.config.ts` include + `vitest.config.ts` exclude → one “register workers-pool journaling file” task (plan Sequencing step 3).
2. `ports.dart` + `sse_events.dart` + `ai_client_sdk.dart` → one SDK conversational surface task (plan Sequencing step 4).
3. `each_leg_admitted_and_credited_independently` + `context_requested_leg_credited_with_actual_usage` → one admit/credit task (same file; FR-006 / FR-007).
4. `no_conversation_table_and_no_per_request_state_object` + `platform_held_no_state_between_legs` → one no-state task (same file; FR-004 / FR-005 / FR-015).

No named tests dropped; every combined task still names every covered case.

**Organization**: One slice, one user story (US1). No multi-story phases, no Setup phase (contracts already frozen; no config/migration must exist first), no Foundational phase (prerequisites are already-merged C3/E2/E3/H1), no Polish phase (R-20).

**Task count**: 24 (≤25).

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: `US1` — the slice's one user story
- Include exact file paths in descriptions

## Path Conventions

- **Flutter desktop app**: `frontend/lib/`, `frontend/test/`
- **Supabase backend**: `backend/migrations/`, `backend/functions/`, `backend/tests/` — not touched by this slice
- **AI platform Worker**: `ai-platform/src/`, `ai-platform/migrations/`, `ai-platform/test/` — journaling + workers-pool tests live here (H3 adds no entity/column DDL; A5 follow-up index migration `20260805180000_h3_conversation_index.sql` only)
- **Spec artifacts**: `specs/046-conversational-journaling/`

---

## Phase 1: Tests

**Purpose**: Write every named test from the spec's Test plan into the three files named in `plan.md` → Test Layout / Files, each failing before the matching implementation exists. Order follows plan Sequencing themes (journaling pipeline → Conversation store → negotiation loop). First task in each primary file creates the substrate plus the first case(s); later tasks in the same file append. `fakes.dart` is extended as Flutter test substrate (not repeated in Implementation). Modules under test lack the H3 conversational branches yet, so cases fail to compile or fail assertions — the intended red state. Journaling cases run under the workers pool once T019 registers the file; Flutter cases run via `flutter test`.

### Journaling pipeline (`conversational-journaling.test.ts`)

- [X] T001 [US1] Add `conversation_id_and_turn_ordinal_written_per_leg` to `ai-platform/test/conversational-journaling.test.ts` (integration): create the substrate — workers-pool fixtures composing admission → `createRequestRow` (with client-supplied conversation fields) → fake provider → credit / R2 spies (Clarification Q3); helpers to submit multi-leg conversational requests sharing one `conversation_id` with distinct `turn_ordinal` values. Then the case: each conversational leg's `ai_request` row carries the client-supplied `conversation_id` and `turn_ordinal` (§7.3; §6.7.1; delivery plan §3.11.7 H3). **Satisfies**: FR-001, FR-002 / SC-001. **Proves**: `conversation_id_and_turn_ordinal_written_per_leg`. File fails to compile (branches/helper absent) or assertions fail.
- [X] T002 [US1] Add `one_indexed_query_returns_whole_conversation_ordered` to `ai-platform/test/conversational-journaling.test.ts` (integration): multiple legs sharing one `conversation_id` with distinct `turn_ordinal` values are returned by one indexed query (`WHERE conversation_id = ? ORDER BY turn_ordinal`) as the whole conversation ordered by `turn_ordinal` (§7.3; §6.7.1; §8.10). **Satisfies**: FR-003 / SC-002. **Proves**: `one_indexed_query_returns_whole_conversation_ordered`.
- [X] T003 [US1] Add `each_leg_admitted_and_credited_independently` and `context_requested_leg_credited_with_actual_usage` to `ai-platform/test/conversational-journaling.test.ts` (integration spy / integration): (1) N legs produce N admissions and N usage credits — no shared conversation counter is consulted (§6.7.1; §8.10); (2) a leg terminating as `context_requested` / `awaiting_context` is credited with actual usage because the inference happened (§6.7.2; §8.10). **Satisfies**: FR-006, FR-007 / SC-003. **Proves**: `each_leg_admitted_and_credited_independently`, `context_requested_leg_credited_with_actual_usage`.
- [X] T004 [US1] Add `no_conversation_table_and_no_per_request_state_object` and `platform_held_no_state_between_legs` to `ai-platform/test/conversational-journaling.test.ts` (integration spy): (1) schema has no `conversation` entity/table; runtime creates no per-request state object — only ordinary request rows with the two nullable grouping columns (§7.3; §6.7.1; §6.7.4; delivery plan §6.4); (2) after leg 1 terminal and before leg 2 submit, the platform holds no conversation state between them (§8.10; §6.7.1). **Satisfies**: FR-004, FR-005, FR-015 / SC-004. **Proves**: `no_conversation_table_and_no_per_request_state_object`, `platform_held_no_state_between_legs`.
- [X] T005 [US1] Add `no_second_r2_object_and_no_second_quota_do_round_trip_from_h3` to `ai-platform/test/conversational-journaling.test.ts` (integration spy): H3 adds no second R2 object per request and no second Quota Durable Object round trip beyond the existing per-request budget (delivery plan §6.4; §7.5; §13.6). **Satisfies**: FR-015. **Proves**: `no_second_r2_object_and_no_second_quota_do_round_trip_from_h3`.
- [X] T006 [US1] Add `single_shot_unaffected_by_h3` spanning `ai-platform/test/conversational-journaling.test.ts` and `frontend/test/unit/core/ai/conversation_store_test.dart` (integration / Flutter): a `single_shot` capability does not acquire Conversation store behaviour or journalled conversation grouping from this slice's existence — journaling half asserts null `conversation_id` / `turn_ordinal` on `single_shot` rows; Flutter half asserts no Conversation store attachment for `single_shot` (§6.7 preamble; delivery plan §3.8). **Satisfies**: FR-018. **Proves**: `single_shot_unaffected_by_h3`.

### Conversation store (`conversation_store_test.dart`)

- [X] T007 [P] [US1] Add `transcript_held_locally_and_resupplied_per_leg` to `frontend/test/unit/core/ai/conversation_store_test.dart` (Flutter): create the substrate — extend `frontend/test/unit/core/ai/fakes.dart` with conversational submit / SSE / Resolver fakes and spies; import Conversation store under test from `frontend/lib/core/ai/`. Then the case: the store holds the open-chat transcript locally and resupplies it on each submit (§4.1; §6.7.1; §8.10). **Satisfies**: FR-005, FR-012 / SC-005. **Proves**: `transcript_held_locally_and_resupplied_per_leg`. `[P]` vs `conversational-journaling.test.ts` (different file). Fails red until the store exists.
- [X] T008 [US1] Add `transcript_discarded_on_close` to `frontend/test/unit/core/ai/conversation_store_test.dart` (Flutter): closing the conversation discards the local transcript (§4.1; §8.10). **Satisfies**: FR-012 / SC-005. **Proves**: `transcript_discarded_on_close`.
- [X] T009 [US1] Add `client_never_interprets_message_or_chooses_keys` to `frontend/test/unit/core/ai/conversation_store_test.dart` (Flutter spy): free text is forwarded without interpretation; the store does not classify the message or choose which context keys are needed (§4.1; §8.10). **Satisfies**: FR-013. **Proves**: `client_never_interprets_message_or_chooses_keys`.
- [X] T010 [US1] Add `no_prompt_provider_or_model_in_conversation_store` to `frontend/test/unit/core/ai/conversation_store_test.dart` (Flutter / architecture guard): Conversation store and chat surface contain no prompt text, provider name, or model identifier — assert via source/API contract and/or E1 guard against new `conversation_*.dart` paths (R-12; §4.1; delivery plan §6.4). Does not weaken or bypass `frontend/tool/architecture_guard/` (Consumes E1). **Satisfies**: FR-016. **Proves**: `no_prompt_provider_or_model_in_conversation_store`.

### Negotiation loop (`conversation_loop_test.dart`)

- [X] T011 [P] [US1] Add `requested_keys_resolved_through_existing_resolver_no_capability_branching` to `frontend/test/unit/core/ai/conversation_loop_test.dart` (Flutter): create the substrate — import negotiation loop under test; reuse conversational fakes/spies from T007. Then the case: `context_requested` keys are resolved via the E3 Context Resolver registry; the resolution path receives no capability id and does not branch on one (§4.1; §8.10; E3 Freezes). **Satisfies**: FR-009, FR-010 / SC-005. **Proves**: `requested_keys_resolved_through_existing_resolver_no_capability_branching`. `[P]` vs journaling and store test files (different file). Depends on T007 fakes substrate. Fails red until the loop exists.
- [X] T012 [US1] Add `each_leg_uses_new_idempotency_key` to `frontend/test/unit/core/ai/conversation_loop_test.dart` (Flutter): successive legs of the same conversation carry distinct idempotency keys (§6.7.4; §8.10). **Satisfies**: FR-011 / SC-005. **Proves**: `each_leg_uses_new_idempotency_key`.
- [X] T013 [US1] Add `closing_one_leg_stream_cancels_only_that_leg` to `frontend/test/unit/core/ai/conversation_loop_test.dart` (Flutter): cancel/close of one leg's stream cancels only that leg (§6.7.4; §8.10). **Satisfies**: FR-014 / SC-006. **Proves**: `closing_one_leg_stream_cancels_only_that_leg`.
- [X] T014 [US1] Add `conversation_survives_cancelled_leg` to `frontend/test/unit/core/ai/conversation_loop_test.dart` (Flutter): after a cancelled leg the Conversation store still holds the transcript and a further leg can be submitted (§6.7.4; §8.10). **Satisfies**: FR-014 / SC-006. **Proves**: `conversation_survives_cancelled_leg`.
- [X] T015 [US1] Add `append_completed_answer_to_transcript` to `frontend/test/unit/core/ai/conversation_loop_test.dart` (Flutter): on terminal `completed`, the validated prose is appended to the local transcript (§6.7.2; §8.10). **Satisfies**: FR-008. **Proves**: `append_completed_answer_to_transcript`.
- [X] T016 [US1] Add `append_context_request_and_resolved_payload_to_transcript` to `frontend/test/unit/core/ai/conversation_loop_test.dart` (Flutter): on `context_requested`, the request and the Resolver payload are appended before the next submit (§6.7.2; §8.10). **Satisfies**: FR-009. **Proves**: `append_context_request_and_resolved_payload_to_transcript`.
- [X] T017 [US1] Add `authorization_is_users_own_rls_not_reimplemented` to `frontend/test/unit/core/ai/conversation_loop_test.dart` (Flutter / integration): resolution runs under the requesting user's session; a user who may not see a patient receives nothing for that key — empty payload, no platform re-implementation of authorization (§8.10; §6.7.2). **Satisfies**: FR-017. **Proves**: `authorization_is_users_own_rls_not_reimplemented`.

**Checkpoint**: All three H3 primary test files exist (plus fakes extension); every named case fails (red). No implementation has landed yet.

---

## Phase 2: Implementation

**Purpose**: The implementation units named in `plan.md` → Files (source / config rows). Vitest include+exclude is one registration task (combining item 1). Optional conversational invoke fields + `context_requested` client terminal across `ports.dart` / `sse_events.dart` / `ai_client_sdk.dart` are one SDK surface task (combining item 2; plan Sequencing step 4). Consumed modules (C3 journal lifecycle, B4 admission/credit, fake provider, E3 Resolver, H1 terminals) are imported/bound, not rewritten. Tests turn green in matching groups per plan Sequencing. `fakes.dart` and the three test files are produced in Phase 1; `contracts/` already frozen; `quickstart.md` in Phase 4.

- [X] T018 [US1] Extend `ai-platform/src/journal/index.ts` — confirm conversational legs write client-supplied `conversation_id` / `turn_ordinal` via existing `createRequestRow` / `RequestRowInput` (no schema migration); add `listConversationLegs(conversationId)` one-query helper `WHERE conversation_id = ? ORDER BY turn_ordinal`; leave AwaitingContext / stage-15/16 / get-request / one-envelope path unchanged (Consumes C3/H1). **Satisfies**: FR-001, FR-002, FR-003, FR-004, FR-005, FR-006, FR-007, FR-015. **Proved by**: T001–T006.
- [X] T019 [US1] Register the workers-pool journaling file — modify `ai-platform/vitest.workers.config.ts` to include `test/conversational-journaling.test.ts` and modify `ai-platform/vitest.config.ts` to exclude that workers-pool file from the unit pool (plan Files; Sequencing step 3). No new runtime dependency. **Satisfies**: SC-001–SC-004 (suite discoverability). **Proved by**: T001–T006 runnable under `npx vitest run --config vitest.workers.config.ts`.
- [X] T020 [P] [US1] Extend the E2 SDK conversational surface across `frontend/lib/core/ai/ports.dart`, `frontend/lib/core/ai/sse_events.dart`, and `frontend/lib/core/ai/ai_client_sdk.dart` (plan Sequencing step 4): optional `conversationId` / `turnOrdinal` / `transcript` on existing `CapabilityInvokeInput` (omitted/null for `single_shot`; Clarification Q2); add `ContextRequestedEvent` / `ContextRequestedTerminal` for H1's fourth terminal kind; surface `context_requested` as a client terminal; preserve a new idempotency key per `invoke()` via the existing factory; do not rewrite transport, remint, or terminal-retry rules (Consumes E2). **Satisfies**: FR-001, FR-005, FR-008, FR-009, FR-011, FR-012, FR-014, FR-018. **Proved by**: T007–T017 (invoke/terminal substrate for store + loop). `[P]` vs T018–T019 (different layer) once Phase 1 is red.
- [X] T021 [US1] Create `frontend/lib/core/ai/conversation_store.dart` — local transcript hold / resupply / discard on close; no interpretation, classification, or context-key choice; no prompt/provider/model identifiers (R-12); conversational capabilities only. Depends on T020 optional invoke fields. **Satisfies**: FR-012, FR-013, FR-016. **Proved by**: T007–T010, T006 (Flutter half).
- [X] T022 [US1] Create `frontend/lib/core/ai/conversation_loop.dart` — chat negotiation loop: submit leg via SDK; on `context_requested` resolve keys through existing E3 `resolve(keys)` with no capability id, append request + resolved payload, submit next leg with a new idempotency key; on `completed` append answer; cancel closes only that leg's stream so the conversation survives on the store. Depends on T020–T021 and Consumes E3 Resolver unchanged. **Satisfies**: FR-008, FR-009, FR-010, FR-011, FR-014, FR-017. **Proved by**: T011–T017.

**Checkpoint**: Slice-only `npx vitest run test/conversational-journaling.test.ts --config vitest.workers.config.ts` and `flutter test test/unit/core/ai/conversation_store_test.dart test/unit/core/ai/conversation_loop_test.dart` green.

---

## Phase 3: Verification

**Purpose**: Delivery plan §3.10 — every prior suite stays green alongside this slice's suite, not just the latest.

- [X] T023 [US1] From `ai-platform/`, run this slice's journaling suite — `npx vitest run test/conversational-journaling.test.ts --config vitest.workers.config.ts` — then every prior suite: `npx vitest run` (default Node-pool) and `npx vitest run --config vitest.workers.config.ts` (workers-pool prior suites). From `frontend/`, run this slice's Flutter files — `flutter test test/unit/core/ai/conversation_store_test.dart test/unit/core/ai/conversation_loop_test.dart` — and confirm FR-016 / E1: new paths under `frontend/lib/core/ai/conversation_*.dart` still pass `dart run tool/architecture_guard/architecture_guard.dart` against clean client scan roots (Consumes E1; do not alter the guard). Also keep prior E2/E3 Flutter suites green (`flutter test test/unit/core/ai/ai_client_sdk_test.dart` and the E3 context resolver/contract files as applicable). Confirm H3's named cases are green and every prior suite stays green. No new test is added here — this is the §3.10 checkpoint gate. **Satisfies**: the §3.10 checkpoint rule (journaling + client named cases + prior suites). Proved by itself.

**Checkpoint**: Full platform suite green. No regressions into C3/E2/E3/H1 or later bands.

---

## Phase 4: Documentation

**Purpose**: Always present. The one documentation artifact the plan names that is not yet complete on disk (`quickstart.md`); written only after the suite is green. The Freezes contract was already frozen during the plan phase — no separate contract task. No other documentation artifact is named for a separate `[P]` task (no `ai-platform/README.md` — not the bootstrap slice).

- [X] T024 [US1] Complete `specs/046-conversational-journaling/quickstart.md` from `.specify/templates/ai-platform-quickstart-template.md`, scoped to this slice only. **§1 Architecture context** — delivery plan §3.8 row H3; `17-ai-platform.md` §7.3, §6.7.1, §8.10, §4.1, §6.7; what the spec delivered; what the plan scoped. **§2 What was implemented** — journal column population + `listConversationLegs` ordered query; Conversation store + negotiation loop; SDK optional invoke fields / `context_requested` client terminal; frozen `contracts/conversational-journaling.md`. **§3 Files to review** — only this slice's source, test, and contract files (no prior-slice files). **§4 Prerequisites** — omit (`cd ai-platform && npm install` / Flutter SDK first time only). **§5 Run the automated suite** — slice-only `npx vitest run test/conversational-journaling.test.ts --config vitest.workers.config.ts` and `flutter test test/unit/core/ai/conversation_store_test.dart test/unit/core/ai/conversation_loop_test.dart`; no full-suite `npm test`. **§6 Inspect the changes** — read the frozen contract; open journal helper, store, loop, and SDK conversational fields; run the focused test files. **No §7** — CI / vitest / flutter test is the verification path (plan: Manual validation omitted). **Slice-only scope explicit**: no prior-slice files in the review table, no combined test counts, no prior-slice regression commands. Not traced to an FR (template-mandated review surface).

---

## Dependencies & Execution Order

### Phase Dependencies

- **Tests (T001–T017)**: No Setup phase. Written to fail before the code exists. Within each file, tasks are sequential (append order). Cross-file first tasks (T001, T007, T011) are `[P]` relative to each other (T011 depends on T007 fakes). T006's Flutter half appends to the store file after T007 substrate exists.
- **Implementation (T018–T022)**: Depends on Tests phase existing (red). T019 may follow or run with T018 (journal file must exist for include). T020 is `[P]` relative to T018–T019 (Flutter vs Worker). T021 depends on T020; T022 depends on T020–T021. Matching green groups: T018–T019 ↔ T001–T006; T020–T021 ↔ T007–T010 (+ T006 Flutter half); T022 ↔ T011–T017.
- **Verification (T023)**: Depends on Implementation green; runs this slice plus every prior slice per §3.10.
- **Documentation (T024)**: Depends on Verification green; records a green suite.

### Within the Slice

- Tests are written and confirmed failing before any implementation.
- Plan Sequencing (journal → workers registration → SDK surface → store → loop) is reflected in Implementation order and in which unit turns which cases green.
- The quickstart is written last and cites only this slice's files and commands.
- Contracts are already on disk from the plan phase — Documentation does not re-author them.

### Parallel Opportunities

- Phase 1: T007 (`conversation_store_test.dart`) is `[P]` relative to T001–T005 (`conversational-journaling.test.ts`). T011 (`conversation_loop_test.dart`) is `[P]` relative to journaling once T007 fakes exist. Within each file, append tasks are sequential.
- Phase 2: T020 may run in parallel with T018–T019 once Phase 1 is red (different layer). T021 then T022 are sequential after T020.
- Phase 4: single task — no `[P]`.

---

## Parallel Example: User Story 1

```bash
# Launch the journaling and store test-file substrates together:
Task: "conversation_id_and_turn_ordinal_written_per_leg in ai-platform/test/conversational-journaling.test.ts"
Task: "transcript_held_locally_and_resupplied_per_leg in frontend/test/unit/core/ai/conversation_store_test.dart (+ fakes)"

# After fakes exist, launch the loop substrate:
Task: "requested_keys_resolved_through_existing_resolver_no_capability_branching in conversation_loop_test.dart"

# Launch Worker journal + Flutter SDK surface together (after tests are red):
Task: "Extend ai-platform/src/journal/index.ts"
Task: "Register workers-pool journaling file in vitest configs"
Task: "Extend ports.dart + sse_events.dart + ai_client_sdk.dart conversational surface"
```

---

## Notes

- Tests are mandatory (delivery plan §3.10 overrides the template's "Tests are OPTIONAL" note).
- One slice, one story (US1) — the template's multi-story, Foundational, and Polish phases are deleted, not left empty.
- Every named Test plan / §3.10 case appears in some task's acceptance criteria; combining items 1–4 do not drop coverage; optional combinations 5–10 were not applied.
- Every task traces to an `FR-###` from `spec.md` and to named test(s) from its Test plan (or the Documentation/Verification mandate); nothing is added that the spec/plan do not name.
- No new runtime dependency; no D1 migration; no `backend/` path (R-20; FR-002).
- Consumed modules (C3 journal lifecycle, E2 transport/remint/retry, E3 Resolver registry, H1 manifest/schema/terminals) are not rewritten (delivery plan §2.3).
- H3 emits no new taxonomy codes — Edge Cases: none new.
