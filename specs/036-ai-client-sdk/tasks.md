# Tasks: AI Client SDK (E2)

**Input**: Design documents from `specs/036-ai-client-sdk/`

**Prerequisites**: `plan.md` (required), `spec.md` (required for the user story). `research.md` is never produced on this platform (the research is `docs/architecture/17-ai-platform.md`). `data-model.md` is not produced — E2 defines no entities (spec Key Entities: not applicable). `contracts/` is not produced — Freezes are client behavioural rules with no new wire shape (plan Project Structure → Documentation). `quickstart.md` is written in Phase 4 (Documentation).

**Tests**: Tests are mandatory on this platform (delivery plan §3.10). Every named test in the spec's `### Test plan` (T1–T28) is covered. Layer is **Flutter unit + integration** (delivery plan §3.11.5 row E2; DP-3). Cases live under `frontend/test/unit/core/ai/` and run via `flutter test` against injectable in-memory fakes/spies — no live Worker (Clarification Q2). Written to fail before the SDK library exists.

**Task-cap combining**: Naive one-task-per-named-test (28) plus Implementation + Verification + Documentation exceeds 25. Per parent-workflow authorization and plan Test Layout / Scale/Scope ("T7–T23 as one parameterized family"), **T7–T23** (`sdk_no_retry_after_*` for every §5.4 terminal code other than the `unauthenticated` remint path) are **one** Tests-phase task: same file, same implementation unit (`ai_client_sdk.dart`), same spy pattern (assert zero auto-retry after terminal). No named tests dropped; no unrelated work merged. Remaining named tests stay one task each (including spy/outcome companions T2, T6, T26, T27).

**Organization**: One user story (US1, P1) — E2 is one slice, one story (delivery plan §2.6, overrides). No cross-story parallelism section. No Setup phase — `fakes.dart` is produced as the Tests-phase substrate (T001); library Files units land in Implementation. No Foundational or Polish phase — prerequisites are already-merged Needs (E1, A6, C1) in the plan's Consumes Binding.

**Task count**: 18 (≤25).

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: US1 (this slice has a single user story)
- Include exact file paths in descriptions

## Path Conventions

- **Flutter desktop app**: `frontend/lib/`, `frontend/test/`, `frontend/tool/`
- **Supabase backend**: `backend/migrations/`, `backend/functions/`, `backend/tests/` — *not touched by E2*
- **AI gateway Worker**: `ai-platform/src/`, `ai-platform/migrations/`, `ai-platform/test/` — *not touched by E2* (Consumes only)
- **Spec Kit artifacts**: `specs/036-ai-client-sdk/`
- E2 is a client-side Flutter transport module under `frontend/lib/core/ai/` (Clarification Q1). Tests and in-memory fakes live under `frontend/test/unit/core/ai/` (Clarification Q2). No `ai-platform/` or `backend/` path is modified.

---

## Phase 1: Tests (written to fail before the code exists)

**Purpose**: Cover every named test in the spec's `### Test plan` (§3.11.5 row E2). All cases share `frontend/test/unit/core/ai/ai_client_sdk_test.dart`; T001 also creates `frontend/test/unit/core/ai/fakes.dart` (plan Files test-support row — substrate, not repeated in Implementation). Until `frontend/lib/core/ai/` exists, imports fail to compile — the intended red state. Order follows plan Sequencing themes (AAT/remint → idempotency/transport → stream/cancel → no-retry family → retention/unknown → Must-not / R-12). **T7–T23 are one parameterized task** (see header).

- [X] T001 [US1] Add named test `sdk_aat_acquired_and_cached` (T1) in `frontend/test/unit/core/ai/ai_client_sdk_test.dart`: create substrate `frontend/test/unit/core/ai/fakes.dart` — in-memory mint / HTTPS submit / SSE fakes and spies that emit canned A6 sequences and §5.4 codes (Clarification Q2; plan Files) — and import the SDK under test from `frontend/lib/core/ai/`. Assert token acquired and cached; a second submit reuses the cache without a second mint while the token remains valid (§4.1; §3.11.5 E2). Fails red until acquire/cache exists. **Satisfies**: FR-001, FR-003 / SC-001. **Proves**: T1.
- [X] T002 [US1] Add named test `sdk_unauthenticated_remints_once_then_succeeds` (T2) to `frontend/test/unit/core/ai/ai_client_sdk_test.dart`: on `unauthenticated`, assert exactly one silent re-mint and one retry of the same submission, then success when the new token is valid; spy shows exactly one re-mint and one retry (§5.4; §3.11.5 E2). **Satisfies**: FR-004 / SC-001. **Proves**: T2.
- [X] T003 [US1] Add named test `sdk_unauthenticated_no_remint_loop` (T3) to `frontend/test/unit/core/ai/ai_client_sdk_test.dart`: after one re-mint, a second `unauthenticated` is surfaced with no further mint (§5.4; §3.11.5 E2). **Satisfies**: FR-004 / SC-001. **Proves**: T3.
- [X] T004 [US1] Add named test `sdk_idempotency_key_stable_across_transport_retries` (T4) to `frontend/test/unit/core/ai/ai_client_sdk_test.dart`: assert the client-generated idempotency key is identical across transport retries of the same user action (§4.1; §5.5; §3.11.5 E2). **Satisfies**: FR-005 / SC-002. **Proves**: T4.
- [X] T005 [US1] Add named test `sdk_stream_consumed_to_terminal_event` (T5) to `frontend/test/unit/core/ai/ai_client_sdk_test.dart`: stream consumed through `accepted` (optional heartbeats/content) to exactly one terminal event; terminal state surfaced; completion not inferred from silence — end/error without terminal → `StreamDroppedTerminal` (Clarification Session 2026-08-05; §5.5 rules 1–4; §3.11.5 E2). **Satisfies**: FR-006, FR-007 / SC-003. **Proves**: T5.
- [X] T006 [US1] Add named test `sdk_cancel_closes_stream` (T6) to `frontend/test/unit/core/ai/ai_client_sdk_test.dart`: cancel closes the in-flight stream and synthesizes `CancelledTerminal` locally (no wire `CancelledEvent`; spy asserts no separate cancel endpoint) (Clarification Session 2026-08-05; §5.5 Cancel row and rule 5; §4.1; §3.11.5 E2). **Satisfies**: FR-008 / SC-003. **Proves**: T6.
- [X] T007 [US1] Add parameterized named tests T7–T23 in `frontend/test/unit/core/ai/ai_client_sdk_test.dart` — one case per terminal §5.4 taxonomy code other than the `unauthenticated` remint path, each proving the SDK does not auto-retry after that terminal outcome (same spy pattern / same implementation unit; plan Test Layout). Cases: `sdk_no_retry_after_installation_suspended` (T7), `sdk_no_retry_after_forbidden_capability` (T8), `sdk_no_retry_after_rate_limited` (T9), `sdk_no_retry_after_quota_exhausted` (T10), `sdk_no_retry_after_request_too_large` (T11), `sdk_no_retry_after_context_required` (T12), `sdk_no_retry_after_context_invalid` (T13), `sdk_no_retry_after_conversation_budget_exhausted` (T14), `sdk_no_retry_after_capability_unknown` (T15), `sdk_no_retry_after_capability_retired` (T16), `sdk_no_retry_after_capability_disabled` (T17), `sdk_no_retry_after_provider_unavailable` (T18), `sdk_no_retry_after_provider_rejected` (T19), `sdk_no_retry_after_validation_failed` (T20), `sdk_no_retry_after_cancelled` (T21), `sdk_no_retry_after_timeout` (T22), `sdk_no_retry_after_internal_error` (T23). For codes §5.4 marks retryable for the *caller* (`rate_limited`, `provider_unavailable`, `validation_failed`, `timeout`, `internal_error`, and `context_required` whose self-heal is J2), assert the SDK still does not invent an auto-retry loop (§4.1; §5.4; §3.11.5 E2). **Satisfies**: FR-002, FR-011 / SC-004. **Proves**: T7–T23.
- [X] T008 [US1] Add named test `sdk_last_request_reference_retained` (T24) to `frontend/test/unit/core/ai/ai_client_sdk_test.dart`: after a request that carried a request reference (`accepted` and/or terminal error body), assert the last request reference is retained for support (§4.1; §3.11.5 E2). **Satisfies**: FR-009 / SC-005. **Proves**: T24.
- [X] T009 [US1] Add named test `sdk_unknown_error_code_treated_as_internal_error` (T25) to `frontend/test/unit/core/ai/ai_client_sdk_test.dart`: an error code outside the §5.4 closed set is treated as `internal_error` (Consumes A2 via A6; §3.11.5 E2). **Satisfies**: FR-010 / SC-004. **Proves**: T25.
- [X] T010 [US1] Add named test `sdk_transport_retry_allowed` (T26) to `frontend/test/unit/core/ai/ai_client_sdk_test.dart`: transport failure before a terminal is retried with the same idempotency key within `maxTransportAttempts=3` + backoff; exhaustion → `TransportRetryExhausted` carrying the key; `cancelSignal` aborts submit-phase retries (Clarification Session 2026-08-05; T4 companion; §4.1). **Satisfies**: FR-001, FR-005 / SC-002. **Proves**: T26.
- [X] T011 [US1] Add named test `sdk_does_not_interpret_model_output` (T27) to `frontend/test/unit/core/ai/ai_client_sdk_test.dart`: spy/contract — listens to rebroadcast `session.events` and asserts stream events + terminal payload as received; no reshape / no assembly from chunks (§4.1 Must not; delivery plan §6.4; Clarification Session 2026-08-05). **Satisfies**: FR-002 / SC-006. **Proves**: T27.
- [X] T012 [US1] Add named test `sdk_contains_no_prompt_provider_or_model_identifiers` (T28) to `frontend/test/unit/core/ai/ai_client_sdk_test.dart` (and/or invoke E1 guard against SDK paths): SDK sources under `frontend/lib/core/ai/` pass the E1 architecture guard (R-12; delivery plan §6.4; §4.1 Must not). Does not weaken or bypass `frontend/tool/architecture_guard/` (Consumes E1). **Satisfies**: FR-012 / SC-006. **Proves**: T28.

---

## Phase 2: Implementation (plan Files section)

**Purpose**: Implementation units from `plan.md` → Files not already produced as test substrates or Documentation: the four Dart library files under `frontend/lib/core/ai/`. `fakes.dart` and `ai_client_sdk_test.dart` are produced in Phase 1; `quickstart.md` in Phase 4. Order follows plan Sequencing (ports → taxonomy → SSE events → SDK). Consumed modules (E1 guard, A6 wire, A2 taxonomy, C1 capability identity) are bound as clients only — not modified (delivery plan §2.3).

- [X] T013 [US1] Create `frontend/lib/core/ai/ports.dart` — injectable ports for AAT mint, HTTPS submit, and SSE stream open/close (Clarification Q2). Events may be single-subscription (SDK rebroadcasts). Include `TransportRetryExhausted`. No second cancel endpoint (cancel = stream close + local `CancelledTerminal`). **Satisfies**: FR-001, FR-003, FR-006. **Proved by**: T1–T6, T26 (and substrate for T7–T28).
- [X] T014 [P] [US1] Create `frontend/lib/core/ai/taxonomy.dart` — Dart mirror of the §5.4 closed code set; `classifyTaxonomyCode` maps any code outside the set to `internal_error`; used for client branching and for proving no auto-retry after each terminal code (except the `unauthenticated` remint path). Adds no codes and changes none (Consumes A2 via A6). **Satisfies**: FR-010, FR-011. **Proved by**: T7–T23 (T007), T25.
- [X] T015 [P] [US1] Create `frontend/lib/core/ai/sse_events.dart` — client-side A6 event kinds and terminal outcomes as received (`completed` / `failed` / local `CancelledTerminal` / `StreamDroppedTerminal`); `FailedEvent.fromWire` applies `classifyTaxonomyCode`; no reshape (FR-002; T27). H-band `ContextRequested*` postdate E2 (§2.3). Does not redefine A6 framing. **Satisfies**: FR-006, FR-007. **Proved by**: T5, T27.
- [X] T016 [US1] Create `frontend/lib/core/ai/ai_client_sdk.dart` — AI Client SDK transport component (§4.1): single-flight acquire/cache AAT; remint once on `unauthenticated` (no loop); `Random.secure()` ≥128-bit keys/trace ids; `invoke({idempotencyKey?, cancelSignal?})`; transport retry ≤3 with backoff → `TransportRetryExhausted`; rebroadcast SSE consume-to-terminal (or `StreamDroppedTerminal`); cancel closes stream + synthesizes `CancelledTerminal`; retain last request reference; never auto-retry after terminal taxonomy outcomes other than the single remint path; no prompts, providers, or model identifiers (R-12). **Satisfies**: FR-001, FR-002, FR-003, FR-004, FR-005, FR-006, FR-007, FR-008, FR-009, FR-011, FR-012. **Proved by**: T1–T28.

---

## Phase 3: Verification

**Purpose**: Delivery plan §3.10 — every prior suite stays green alongside the new one, not just the latest.

- [X] T017 [US1] From `frontend/`, run `flutter test test/unit/core/ai/ai_client_sdk_test.dart` (this slice's named cases T1–T28, including the parameterized T7–T23 family). Confirm T28 / E1: SDK paths under `frontend/lib/core/ai/` still pass `dart run tool/architecture_guard/architecture_guard.dart` against clean client scan roots (Consumes E1; do not alter the guard). Then from `ai-platform/`, run every prior slice's suite: `npx vitest run` (default Node-pool prior suites) and `npx vitest run --config vitest.workers.config.ts` (workers-pool prior suites). Confirm E2's named cases are green and every prior suite stays green. No new test is added here — this is the §3.10 checkpoint gate. **Satisfies**: the §3.10 checkpoint rule (T1–T28 + prior suites). Proved by itself.

---

## Phase 4: Documentation

**Purpose**: Always present. The one documentation artifact the plan names that does not yet exist on disk (`quickstart.md`); written only after the suite is green. No other documentation artifact is named for a separate `[P]` task (no `ai-platform/README.md` — not the bootstrap slice).

- [X] T018 [US1] Create `specs/036-ai-client-sdk/quickstart.md` from `.specify/templates/ai-platform-quickstart-template.md`, scoped to this slice only. **§1 Architecture context** — delivery plan §3.6 row E2; `17-ai-platform.md` §4.1 / §5.5 / §5.4; what the spec delivered; what the plan scoped. **§2 What was implemented** — AI Client SDK (AAT cache/remint, idempotent submit, SSE consume-to-terminal, cancel-by-close, last request-reference retention, taxonomy mapping, transport-only retry). **§3 Files to review** — only this slice's `frontend/lib/core/ai/` and `frontend/test/unit/core/ai/` files (no prior-slice files). **§4 Prerequisites** — omit or keep minimal (`flutter` / Dart SDK from `frontend/pubspec.yaml`); no live Worker. **§5 Run the automated suite** — slice-only `flutter test test/unit/core/ai/ai_client_sdk_test.dart` (and T28 guard invocation if documented separately); no full-suite `npm test`, no combined prior-slice counts. **§6 Inspect the changes** — open the SDK module, taxonomy mapping, and a focused test file; confirm E1 guard still covers `frontend/lib/core/ai/`. **No §7 Manual validation** — CI / `flutter test` is the verification path (E2 exposes no user-visible surface; E4 does). **Slice-only scope explicit**: no prior-slice files in the review table, no combined test counts, no prior-slice regression commands. Not traced to an FR (template-mandated review surface).

---

## Dependencies & Execution Order

### Phase Dependencies

- **Tests (T001–T012)** — none beyond existing `frontend/` and Consumes Binding modules available as contracts; written to fail before `frontend/lib/core/ai/` exists. All named cases share `ai_client_sdk_test.dart` (sequential appends after T001 substrate). No `[P]` within Phase 1 (same primary test file).
- **Implementation (T013–T016)** — after tests exist (red). T013 (`ports.dart`) first. T014 (`taxonomy.dart`) and T015 (`sse_events.dart`) are `[P]` relative to each other (different files, no mutual dependency) after T013. T016 (`ai_client_sdk.dart`) depends on T013–T015 and turns T1–T28 green.
- **Verification (T017)** — depends on T001–T016; runs this slice's Flutter suite plus E1 guard check plus every prior `ai-platform/` suite per §3.10.
- **Documentation (T018)** — depends on T017 (the quickstart records a green suite).

### Within the Slice

- Tests written to fail before implementation; implementation makes them pass; verification confirms the whole suite including prior slices stays green.
- Plan Sequencing maps to Implementation order: ports (T013) → taxonomy (T014) → SSE events (T015) → SDK (T016). Test order mirrors behavioural themes (AAT/remint T001–T003 → idempotency T004 → stream/cancel T005–T006 → no-retry family T007 → retention/unknown T008–T009 → transport retry T010 → Must-not / R-12 T011–T012).
- `fakes.dart` Files-section row is produced by T001 (test substrate); not repeated as an Implementation task. Remaining Files units: T013–T016 (library) and T018 (`quickstart.md`).

### Parallel Opportunities

- Phase 1: no `[P]` — all tests share `frontend/test/unit/core/ai/ai_client_sdk_test.dart` (T001 also creates `fakes.dart`, but later cases append to the same suite file).
- Phase 2: T014 and T015 are `[P]` after T013; T016 is sequential after both.
- Phase 4 (T018) is a single task — no `[P]`.

---

## Notes

- [P] tasks = different files, no dependencies. Marked: T014, T015.
- Every named test T1–T28 from `spec.md` is covered: T1–T6 and T24–T28 each have their own task; T7–T23 are one parameterized task under the hard-cap combining rule (related cases, same unit, same spy pattern). No cases dropped.
- Every task traces to an `FR-###` from `spec.md` (tests also state the `SC-###` they satisfy) — no task adds a requirement the spec does not name. Clarifications Q1–Q2 plus Session 2026-08-05 guide how (module path; ports/fakes; cancel/drop/retry ceiling/rebroadcast/single-flight/keys/`fromWire`/per-invoke override/H-band annotation), not what.
- No Polish phase and no Foundational phase — Needs are E1, A6, C1 (already merged; Consumes Binding).
- Consumed modules are imported/bound, not modified (delivery plan §2.3 — extend, never rewrite).
- Tests land before or alongside their implementation, never after (delivery plan §2.2).
- Preserve R-12 / §6.4: no prompt text, provider name, or model identifier in the Flutter client; no client-side assembly of a final result from chunks; no auto-retry after terminal platform errors except the single `unauthenticated` remint path.
