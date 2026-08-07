# Tasks: Worker request orchestrator on `POST /v1/requests` (I1)

**Input**: Design documents from `specs/052-worker-request-orchestrator/`

**Prerequisites**: `plan.md` (required), `spec.md` (required for the user story). `research.md` is never produced on this platform (the research is `docs/architecture/ai-platform/01-ai-platform.md`). `data-model.md` is not produced — I1 defines no D1 entities (spec Key Entities). `contracts/` is not produced — Freezes **None**. `quickstart.md` is written in Phase 5 (Documentation).

**Tests**: Tests are mandatory on this platform (delivery plan §3.10). Every named test in the spec's `### Test plan` (T1–T23) is covered. Soft-threshold / F4 is absent (FR-020). Spy cases T2–T4, T17, T23 (and spy asserts inside each guard-reject case) remain explicit.

**Task-cap combining**: Naive one-task-per-named-test (23) + Setup + 2 Implementation + Verification + Documentation = 28 (>25). Per Stage 4 parent-workflow authorization, closely related **guard-reject** cases that share one file and one FR-011 / taxonomy-HTTP spy pattern are combined into two FR-stage clusters. No named tests dropped; no unrelated work merged.

| Combined task | Named tests | Rationale |
| --- | --- | --- |
| T003 | T5, T6, T7, T8, T9, T10, T19 | Same file; FR-011; stages 2–5 identity / entitlement / rate / capability |
| T004 | T11, T12, T13, T14 | Same file; FR-011; stages 6–8 context / size / quota |

**Organization**: One user story (US1, P1) — I1 is one slice, one story (delivery plan §2.6, overrides). No cross-story parallelism section. Setup is present — workers-pool include (and Node-pool exclude pairing) must land before `SELF.fetch` cases. No Foundational or Polish phase — prerequisites are already-merged Needs (A6, B3, B4, C1, C2, C3, D1, D2, D3, D4, D6) in the plan's Consumes Binding.

**Task count**: 19 (≤25). Combined to fit: 11 guard-reject named tests → 2 tasks (saves 9 vs one-per-named-test; natural list would be 28).

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: US1 (this slice has a single user story)
- Include exact file paths in descriptions

## Path Conventions

- **AI gateway Worker**: `ai-platform/src/`, `ai-platform/migrations/`, `ai-platform/test/`
- **Spec Kit artifacts**: `specs/052-worker-request-orchestrator/`
- The Worker lives in `ai-platform/` at the repository root, a sibling of `frontend/` and `backend/` (delivery plan §7.1). The template's `frontend/lib/` and `backend/migrations/` conventions do not apply to this slice; I1 touches neither. No `ai-platform/migrations/` edits — I1 adds no D1 schema. `src/pipeline` and D4 broker modules are consumed unchanged (not Files rows). `adapter.ts` may be modified only for A6 contract §8 (`preAccept` / deferred `accepted`).

---

## Phase 1: Setup (Test harness)

**Purpose**: Register the I1 Workers-integration file in the workers pool so `SELF.fetch` exercises production `worker.ts` (plan → Files / Testing). Pair with the existing Node-pool exclude list so the file does not double-run under `vitest.config.ts` (same harness pairing as every other workers-pool suite).

- [X] T001 [US1] Modify `ai-platform/vitest.workers.config.ts` — add `"test/worker-request-orchestrator.test.ts"` to `include`. Modify `ai-platform/vitest.config.ts` — add `"test/worker-request-orchestrator.test.ts"` to `exclude`, so the workers-pool-only `SELF.fetch` cases do not double-run in the default Node pool (plan → Files; workers-pool registration precedent). No FR — harness; required by T1–T23. Prepares the Phase 2 substrate.

---

## Phase 2: Tests (written to fail before the code exists)

**Purpose**: Cover every named test in the spec's `### Test plan` (§3.12.9 row I1 = "Workers integration (spy)"; §13.5 Pipeline tests with fake provider). All 23 cases live in `ai-platform/test/worker-request-orchestrator.test.ts` under `vitest.workers.config.ts`, driven via `SELF.fetch` (or equivalent) against the live Worker with spies on D1 journal, R2, Quota DO, and provider calls. Until `adapter.ts` §8 and production `worker.ts` injectors exist, imports/assertions fail — the intended red state. Order follows the plan's Sequencing (spine → guard matrix → happy-path spies → post-guard / one-terminal → cancel + invariants). Soft-threshold / F4 cases are not asserted (FR-020).

- [X] T002 [US1] Create `ai-platform/test/worker-request-orchestrator.test.ts` with the Workers-integration substrate — `SELF.fetch` helpers for `POST /v1/requests`; fixtures for enrolled installation / valid AAT / fake-adapter routing policy; spies for D1 `ai_request` inserts, R2 envelope puts, Quota DO admit/credit round trips, and provider invoke — then named test `worker_supplies_production_event_source` (T23): assert production `worker.ts` injects non-null `preAccept` + `eventSource` and the live route is not the A6 missing-source 503 shell (Done when; §4.3.1; A6 §8). Fails red until production injectors exist. **Satisfies**: FR-001 / SC-006. **Proves**: T23.
- [X] T003 [US1] Add guard-reject cases T5–T10 and T19 to `ai-platform/test/worker-request-orchestrator.test.ts` (Workers integration, spy) — seven named cases in one task (same file, FR-011 stages 2–5 cluster): `guard_reject_unauthenticated_no_journal_no_provider` (T5), `guard_reject_rate_limited_no_journal_no_provider` (T6), `guard_reject_forbidden_capability_no_journal_no_provider` (T7), `guard_reject_capability_unknown_no_journal_no_provider` (T8), `guard_reject_capability_retired_no_journal_no_provider` (T9), `guard_reject_capability_disabled_no_journal_no_provider` (T10), `guard_reject_installation_suspended_no_journal_no_provider` (T19). For each: taxonomy **HTTP** response (no SSE stream, no `accepted`); spy zero `ai_request` inserts; spy zero provider calls (§6.1 stages 2–5; A6 §8; §3.12.9 I1). **Satisfies**: FR-011 / SC-003. **Proves**: T5–T10, T19.
- [X] T004 [US1] Add guard-reject cases T11–T14 to `ai-platform/test/worker-request-orchestrator.test.ts` (Workers integration, spy) — four named cases in one task (same file, FR-011 stages 6–8 cluster): `guard_reject_context_required_no_journal_no_provider` (T11), `guard_reject_context_invalid_no_journal_no_provider` (T12), `guard_reject_request_too_large_no_journal_no_provider` (T13), `guard_reject_quota_exhausted_no_journal_no_provider` (T14). For each: taxonomy **HTTP** (no SSE / no `accepted`); spy zero journal (when rejected before stage 9); spy zero provider calls (§6.1 stages 6–8; A6 §8; §3.12.9 I1). **Satisfies**: FR-011 / SC-003. **Proves**: T11–T14.
- [X] T005 [US1] Add `live_post_happy_path_accepted_stream_completed` (T1) to `ai-platform/test/worker-request-orchestrator.test.ts` (Workers integration, spy): valid AAT `POST /v1/requests` via `SELF.fetch` with fake-adapter routing; assert stream opens with `accepted` (after pre-accept gate), streams fake-provider chunks, ends with exactly one `completed` (§5.5 rules 1, 4; §6.1; §3.12.9 I1). **Satisfies**: FR-002, FR-006, FR-008 / SC-001. **Proves**: T1.
- [X] T006 [US1] Add `ai_request_written_before_invoke` (T2) to `ai-platform/test/worker-request-orchestrator.test.ts` (Workers integration, spy): on the happy path, assert exactly one `ai_request` D1 insert before provider invoke, and that stage 9 completes before `accepted` / stream open (§6.1 stage 9; §3.12.9 I1). **Satisfies**: FR-003, FR-010 / SC-002. **Proves**: T2.
- [X] T007 [US1] Add `one_r2_envelope_after_response` (T3) to `ai-platform/test/worker-request-orchestrator.test.ts` (Workers integration, spy): after the terminal event, assert exactly one R2 payload envelope PutObject and no second R2 object (§6.1 stage 16; §3.12.9 I1). **Satisfies**: FR-014 / SC-002. **Proves**: T3.
- [X] T008 [US1] Add `exactly_two_do_round_trips_admit_and_credit` (T4) to `ai-platform/test/worker-request-orchestrator.test.ts` (Workers integration, spy): assert exactly two Quota DO round trips (admit + credit) and no third (§6.1 stages 8, 15; §7.5; §3.12.9 I1). **Satisfies**: FR-012 / SC-002. **Proves**: T4.
- [X] T009 [US1] Add `idempotency_repeat_returns_prior_no_second_inference` (T15) to `ai-platform/test/worker-request-orchestrator.test.ts` (Workers integration, spy): repeated idempotency key for the same installation returns the prior request state; spy no second inference / no second fresh journal insert for a new request (§6.1 stage 8; §6.6; §3.12.9 I1). **Satisfies**: FR-013 / SC-004. **Proves**: T15.
- [X] T010 [US1] Add `post_guard_failed_terminal_provider_unavailable` (T20) to `ai-platform/test/worker-request-orchestrator.test.ts` (Workers integration, spy): exhausted invocation chain surfaces `provider_unavailable` as exactly one `failed` terminal SSE event (journal row exists — accepted before invoke) (§6.1 stage 11; §3.11 coverage). **Satisfies**: FR-008 / SC-001 companion. **Proves**: T20.
- [X] T011 [US1] Add `post_guard_failed_terminal_validation_failed` (T21) to `ai-platform/test/worker-request-orchestrator.test.ts` (Workers integration, spy): validation/repair exhaustion surfaces `validation_failed` as exactly one `failed` terminal; invalid content never emitted (§6.1 stage 13; §6.4; §3.11 coverage). **Satisfies**: FR-008, FR-016 / SC-001 companion. **Proves**: T21.
- [X] T012 [US1] Add `exactly_one_terminal_event_on_every_live_path` (T22) to `ai-platform/test/worker-request-orchestrator.test.ts` (Workers integration, spy): across live accepted paths exercised by this suite, assert exactly one terminal event each — never inferred from silence (§5.5 rule 4; §4.3.10; §3.11 coverage). **Satisfies**: FR-008 / SC-001. **Proves**: T22.
- [X] T013 [US1] Add `cancel_disconnect_aborts_cancelled_credits_partial` (T16) to `ai-platform/test/worker-request-orchestrator.test.ts` (Workers integration, spy): during an in-flight fake-provider stream, client disconnect aborts the provider fetch via abort signal; terminal state `cancelled`; partial usage credited when present (§4.3.10; §5.5 rule 5; §6.1 stage 12; §3.12.9 I1). **Satisfies**: FR-009, FR-018 / SC-005. **Proves**: T16.
- [X] T014 [US1] Add `no_per_request_server_side_state` (T17) to `ai-platform/test/worker-request-orchestrator.test.ts` (Workers integration, spy): assert absence of any per-request Durable Object or other server-side request state on I1 live paths (§4.3.10; delivery plan §6.4; §3.12.9 I1). **Satisfies**: FR-015, FR-019 / SC-007. **Proves**: T17.
- [X] T015 [US1] Add `provider_selection_only_via_routing_policy` (T18) to `ai-platform/test/worker-request-orchestrator.test.ts` (Workers integration, spy): routing-policy edit changes selected adapter without a pipeline/orchestrator code change; fake adapter remains the CP3 Worker half default until policy selects otherwise; D5/D7 adapters only when policy says so (D2; Done when; §3.12.9 I1). **Satisfies**: FR-017 / SC-007. **Proves**: T18.

---

## Phase 3: Implementation (plan Files section)

**Purpose**: The two production source units named in `plan.md` → Files: `adapter.ts` (A6 §8 gate) and `worker.ts` (production `preAccept` + `eventSource`). Consumed modules (`src/pipeline` `runGuard` / settle, D4 broker, D2/D3 router+invocation+FakeAdapter, D6 validate/repair, C3 journal/credit/detail, B3/B4/C1/C2 surfaces) are imported/composed, not rewritten (delivery plan §2.3; Freezes None). Soft-threshold helpers already present in pipeline remain untouched for F4 (FR-020). Order follows plan Sequencing: adapter §8 first, then worker injectors.

- [X] T016 [US1] Modify `ai-platform/src/adapter.ts` — implement A6 contract §8 pre-stream accept gate: optional `preAccept` on `HandleAdapterRequestOptions`; defer SSE open + `accepted` until `{ ok: true }`; on `{ ok: false, code }` return A2 taxonomy HTTP via existing `buildErrorBody` / `liveHttpStatusForCode` (no stream, no `accepted`, no `eventSource` call); omitted `preAccept` preserves A6 harness behaviour (existing `adapter` suites remain green — not rewritten). Does not change A6 event vocabulary, terminal invariant, or header set beyond §8. **Satisfies**: FR-001, FR-004, FR-006, FR-011. **Proved by**: T23, T5–T14, T19 (and A6 regression under Verification).
- [X] T017 [US1] Modify `ai-platform/src/worker.ts` — supply production `preAccept` and `eventSource` to `handleAdapterRequest` on live `POST /v1/requests`: `preAccept` runs `runGuard` through stage 9 journal (`GuardFailure` → `{ ok: false, code }`; fresh success → `{ ok: true }` with accepted context; `GuardIdempotentSuccess` returns prior state without a second inference); `eventSource` composes post-accept route/invoke (D2/D3, FakeAdapter via routing policy) **concurrently** with D4 broker relay (heartbeats, disconnect abort via immediate `onBrokerReady` handle) → prose validation guards → exactly one terminal → C3 settle (credit + one R2 envelope) **only when broker terminal is `completed`** (cancel/fail skip completed-path settle). Accept handoff is **request-scoped** (not a module-global map). Enforce I/O budgets (one DO admit + one D1 journal before stream; one DO credit; one R2 envelope; no third DO / second R2); no per-request server-side state; no F4 soft-threshold behaviour; no parallel HTTP path that bypasses the adapter; do not rewrite `src/pipeline` or D4 broker modules. **Satisfies**: FR-001–FR-019 (FR-020 by omission). **Proved by**: T1–T23.

---

## Phase 4: Verification

**Purpose**: Delivery plan §3.10 — every prior suite stays green alongside the new one, not just the latest. Confirm A6 harness behaviour with omitted `preAccept` remains green after the §8 extension.

- [X] T018 [US1] From `ai-platform/`, run this slice's Workers suite — `npx vitest run --config vitest.workers.config.ts test/worker-request-orchestrator.test.ts` (T1–T23). Then run every prior slice's suite: `npx vitest run` (default Node-pool prior suites, including `adapter.test.ts` A6 regression for omitted-`preAccept` harness behaviour) and `npx vitest run --config vitest.workers.config.ts` (workers-pool prior suites including control/identity/entitlement/rate-limit, quota-do/admission-credit, capability, journal, pipeline, soft-threshold-routing, conversational-journaling, token-contract-control, load-and-cost, and this slice's file). Confirm all 23 I1 named cases are green and every prior suite stays green. No new test is added here — this is the §3.10 checkpoint gate. Confirm inherited prohibitions: no guard-rejection journal; no second DO beyond admit+credit; no second R2 object; no per-request server-side state; no F4 soft-threshold assertions in the I1 file (FR-020). **Satisfies**: the §3.10 checkpoint rule. Proved by itself.

---

## Phase 5: Documentation

**Purpose**: Always present. The one documentation artifact the plan names that does not yet exist on disk (`quickstart.md`); written only after the suite is green. No other documentation artifact is named for a separate `[P]` task (no `ai-platform/README.md` — not the bootstrap slice; Freezes None — no new contract file).

- [X] T019 [US1] Create `specs/052-worker-request-orchestrator/quickstart.md` from `.specify/templates/ai-platform-quickstart-template.md`, scoped to this slice only. **§1 Architecture context** — delivery plan §3.10 row I1; `01-ai-platform.md` §6.1 stages 1–16, §4.3.1, §4.3.10, §5.5, §6.4; what the spec delivered; what the plan scoped. **§2 What was implemented** — production `preAccept` (`runGuard` through stage 9) + `eventSource` (broker/settle) in `worker.ts`; A6 §8 deferred `accepted` / taxonomy HTTP on pre-accept failure in `adapter.ts`. **§3 Files to review** — only this slice's source and test files (`ai-platform/src/adapter.ts`, `ai-platform/src/worker.ts`, `ai-platform/test/worker-request-orchestrator.test.ts`, `ai-platform/vitest.workers.config.ts` / `vitest.config.ts` harness edits). **§4 Prerequisites** — omit or keep minimal (`cd ai-platform && npm install` first time); workers-pool / Miniflare bindings required for `SELF.fetch`. **§5 Run the automated suite** — `cd ai-platform && npx vitest run --config vitest.workers.config.ts test/worker-request-orchestrator.test.ts`; expected **23** passing named tests for this slice only (no full-suite `npm test`). **§6 Inspect the changes** — open `worker.ts` production injectors and `adapter.ts` §8 gate; grep for `preAccept` / `eventSource`; run the focused workers file. **No §7** — CI / Workers integration suite is the verification path (plan: Manual validation omitted). **Slice-only scope explicit**: no prior-slice files in the review table, no combined test counts, no prior-slice regression commands. Not traced to an FR (template-mandated review surface).

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (T001)** — no dependencies; blocks Phase 2 (workers include / Node exclude must be wired before any I1 Worker test runs in the right pool).
- **Tests (T002–T015)** — depend on T001; written to fail before the code exists. All append to `worker-request-orchestrator.test.ts` (sequential — each builds on the substrate T002 created). No `[P]` within Phase 2 (same file).
- **Implementation (T016–T017)** — depends on T002–T015 existing (red). T016 (`adapter.ts` §8) lands first; T017 (`worker.ts` injectors) depends on T016's `preAccept` option and turns T1–T23 green. Consumed pipeline/broker/provider modules are not modified.
- **Verification (T018)** — depends on T001–T017; runs this slice + every prior slice per §3.10.
- **Documentation (T019)** — depends on T018 (the quickstart records a green suite).

### Within the Slice

- Tests written to fail before implementation; implementation makes them pass; verification confirms the whole suite including prior slices stays green.
- Within Phase 2, order follows plan Sequencing: spine T23 (T002) → guard matrix (T003–T004) → happy path + I/O spies T1–T4 (T005–T008) → idempotency T15 (T009) → post-guard / one-terminal T20–T22 (T010–T012) → cancel + invariants T16–T18 (T013–T015).
- Two implementation units: adapter §8 (FR-001, FR-004, FR-006, FR-011) then worker production wiring (FR-001–FR-019).

### Parallel Opportunities

- Phase 1: single task — no `[P]`.
- Phase 2: no `[P]` — all tests share `ai-platform/test/worker-request-orchestrator.test.ts`.
- Phase 3: no `[P]` — `worker.ts` depends on `adapter.ts` §8 API (sequential).
- Phase 5 (T019) is a single task — no `[P]`.

---

## Notes

- [P] tasks = different files, no dependencies. This slice has no `[P]` tasks — one test file and two sequential implementation files (plus harness + docs).
- Every named test T1–T23 from `spec.md` is covered; T5–T10+T19 and T11–T14 are two combined tasks (same file, same FR-011 / taxonomy-HTTP spy cluster) to fit the 25-task cap; happy-path spy cases T2–T4 and invariant spies T17/T23 remain separate tasks.
- Every task traces to an `FR-###` from `spec.md` (tests also state the `SC-###` they satisfy) — no task adds a requirement the spec does not name.
- No Polish phase and no Foundational phase — prerequisites are the already-merged slices in the plan's Consumes Binding.
- Consumed modules are imported/composed, not rewritten (delivery plan §2.3). `adapter.ts` §8 is the only allowed Consumes-side framing extension.
- Tests land before or alongside their implementation, never after (delivery plan §2.2).
- Preserve the I/O budget: no second Quota DO round trip beyond admit+credit, no second R2 object, no guard-rejection journal, no per-request server-side state, no F4 soft-threshold (§6.1, §7.5, delivery plan §6.4; FR-020).
