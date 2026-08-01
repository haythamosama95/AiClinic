# Tasks: Invocation with bounded retry and fallback (D3)

**Input**: Design documents from `specs/030-invocation-retry-fallback/`

**Prerequisites**: `plan.md` (required), `spec.md` (required for the user story). `research.md` is never produced on this platform (the research is `docs/architecture/17-ai-platform.md`). `data-model.md` is not produced — D3 defines no D1 entities and adds no columns. `contracts/invocation-attempt-loop.md` is already frozen on disk (written during the plan phase per DP-4). `quickstart.md` is written in Phase 4 (Documentation).

**Tests**: Tests are mandatory on this platform (delivery plan §3.10). Every named test in the spec's `### Test plan` (T1–T13) is covered by its own task, written to fail before the code exists. T11 is a spy case and is its own task (skill rule). No same-file merges are required — 13 tests + 1 implementation + 1 verification + 1 documentation = 16 tasks (≤25).

**Organization**: One user story (US1, P1) — D3 is one slice, one story (delivery plan §2.6, overrides). No cross-story parallelism section. No Setup phase — the frozen contract is already on disk; no migrations or `wrangler.toml` edits. No Foundational or Polish phase.

**Task count**: 16 (≤25).

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: US1 (this slice has a single user story)
- Include exact file paths in descriptions

## Path Conventions

- **AI gateway Worker**: `ai-platform/src/`, `ai-platform/test/`, `ai-platform/migrations/`, `ai-platform/vitest.config.ts`, `ai-platform/vitest.workers.config.ts`, `ai-platform/wrangler.toml`
- **Spec Kit artifacts**: `specs/030-invocation-retry-fallback/`
- The Worker lives in `ai-platform/` at the repository root, a sibling of `frontend/` and `backend/` (delivery plan §7.1). The template's `frontend/lib/` and `backend/migrations/` conventions do not apply to this slice; D3 touches neither. No `ai-platform/migrations/` edits — A5 schema and C3 write-path are unchanged.

---

## Phase 1: Tests (written to fail before the code exists)

**Purpose**: One task covering each named test in the spec's `### Test plan` (§3.11.4 row D3 = "Integration"; §13.5 Pipeline tests with fake provider). All 13 cases are CPU-only against D2's fake (plus a test-only streaming harness for T6) with an in-memory sink and injectable sleeper — no I/O — so the default Node-pool config (`vitest.config.ts`, `include: ["test/**/*.test.ts"]`) covers them; no workers-pool registration is needed. T001 creates `test/invocation.test.ts` and its substrate; T002–T013 append to it. The module under test (`../src/invocation`) does not exist yet, so the file fails to compile from the first importing task onward — the intended red state. Order follows the plan's Sequencing (happy-path substrate first, then bounded retry, fallback walk, journal feed, regenerating).

- [ ] T001 [US1] Add `T-D3-08 first_attempt_success_no_fallback` to `ai-platform/test/invocation.test.ts` (integration): create the substrate — a minimal `CanonicalRequest` fixture (A3), a two-entry `ChainEntry[]` / `routing_decision.chain` fixture carrying `max_attempts` / `timeout_ms` (D2 shapes from `../src/router`), a port resolver mapping `provider_id` → `FakeAdapter` (D2 `../src/provider/fake`, production fake unchanged), an in-memory event/attempt sink (Clarification Q4), an injectable recording sleeper (Clarification Q3), and import of the invocation entry point from `../src/invocation`. Then the case: first target succeeds on attempt 1; assert success, exactly one sink attempt, `selection_reason = primary`, no fallback (§4.3.7; §3.10). Satisfies FR-001, FR-004 / SC-008.
- [ ] T002 [US1] Add `T-D3-01 retryable_retried_to_cap_then_fallback` to `ai-platform/test/invocation.test.ts` (integration): script the first target to fail retryably up to its `max_attempts` and the second to succeed; assert retries to the cap, fallback to the second target, success, and attempt `selection_reason` values `primary` then `fallback_after_retryable_error` (§8.6; §3.11.4 D3). Satisfies FR-001, FR-002, FR-004 / SC-001.
- [ ] T003 [US1] Add `T-D3-03 jitter_applied_on_backoff` to `ai-platform/test/invocation.test.ts` (integration): drive multiple same-target retryable retries with the recording sleeper; assert requested delays across retries are not all identical (Clarification Q3; §6.6; §8.6). Satisfies FR-002 / SC-003.
- [ ] T004 [US1] Add `T-D3-07 retry_budget_never_exceeded` to `ai-platform/test/invocation.test.ts` (integration): under any failure script with declared `max_attempts`, assert no target is invoked more times than its `max_attempts` and the walk never exceeds the chain's retry budget (§4.3.7; §3.11.4 D3). Satisfies FR-010 / SC-007.
- [ ] T005 [US1] Add `T-D3-12 internal_retry_same_request_not_user_retry` to `ai-platform/test/invocation.test.ts` (integration): across platform-internal retries, assert the same request identity / idempotency key is retained — not a new user-initiated request (§6.6; §3.10). Satisfies FR-009 / SC-008.
- [ ] T006 [US1] Add `T-D3-02 terminal_failure_not_retried` to `ai-platform/test/invocation.test.ts` (integration): first target returns an adapter-classified terminal failure; assert that target is not retried, the chain is not continued for fallback, and the request fails with that terminal error (§6.6; §4.3.7). Satisfies FR-003 / SC-002.
- [ ] T007 [US1] Add `T-D3-05 exhausted_chain_provider_unavailable` to `ai-platform/test/invocation.test.ts` (integration): every chain target exhausts retryable attempts; assert the request fails with taxonomy code `provider_unavailable` (§8.6; Done when). Satisfies FR-005 / SC-005.
- [ ] T008 [US1] Add `T-D3-09 timeout_exhaustion_fallback_reason` to `ai-platform/test/invocation.test.ts` (integration): first target exhausts via timeout-classified retryable failures then second succeeds; assert the fallback attempt's `selection_reason = fallback_after_timeout` (§4.3.7; §8.6; §3.10). Satisfies FR-004 / SC-008.
- [ ] T009 [US1] Add `T-D3-10 fallback_only_walks_given_chain` to `ai-platform/test/invocation.test.ts` (integration): assert fallback invokes only router-supplied chain targets — no invented / widened targets outside the given chain (§8.6; §3.10). Satisfies FR-007 / SC-008.
- [ ] T010 [US1] Add `T-D3-11 no_provider_history_consulted` to `ai-platform/test/invocation.test.ts` (integration, spy): supply a spy provider-history / circuit-breaker store; assert next-target choice performs zero reads of that store — routing during the walk stays explainable from this request alone (§4.3.7; §8.6; R-20 / §9.14). Satisfies FR-008 / SC-008.
- [ ] T011 [US1] Add `T-D3-13 repair_retry_reason_not_emitted` to `ai-platform/test/invocation.test.ts` (integration): under retry and fallback scripts, assert no sink attempt records `selection_reason = repair_retry` (reserved for D6) (§4.3.7; §3.10). Satisfies FR-011 / SC-008.
- [ ] T012 [US1] Add `T-D3-04 every_attempt_journaled_separately` to `ai-platform/test/invocation.test.ts` (integration): for a request that performs N provider invokes (retries and/or fallbacks), assert the sink receives exactly N separately journaled attempts — one per invoke (Clarification Q4; §6.6). Satisfies FR-002 / SC-004.
- [ ] T013 [US1] Add `T-D3-06 fallback_after_partial_stream_emits_regenerating` to `ai-platform/test/invocation.test.ts` (integration): use a **test-only** port double/harness that yields partial chunks then a retryable error (Clarification Q2 — production `FakeAdapter` unchanged); on fallback assert an explicit `regenerating` sink event, discarded earlier partial text, and no splice of the two providers' text (§8.6). Satisfies FR-006 / SC-006.

---

## Phase 2: Implementation (plan Files section)

**Purpose**: The one implementation unit named in `plan.md` → Files: `ai-platform/src/invocation/index.ts`. Consumed modules (`provider/port.ts`, `provider/fake.ts`, `provider/classify.ts`, `router/index.ts`) are imported, not modified (delivery plan §2.3). The frozen contract `contracts/invocation-attempt-loop.md` constrains the surface. Tests turn green together once the module lands (plan Sequencing groups are implementation order within this single unit, not separate files).

- [ ] T014 [US1] Create `ai-platform/src/invocation/index.ts` — platform-internal attempt loop. Export the invocation entry that: walks `routing_decision.chain[]` in order through a port resolver (`provider_id` → `ProviderPort`); bounds per-target invokes by `max_attempts`; retries only adapter-classified retryable failures with jittered backoff via an injectable sleeper (Clarification Q3); does not retry or fall back after a terminal failure; on retryable exhaustion advances with `selection_reason` `primary` | `fallback_after_retryable_error` | `fallback_after_timeout` as appropriate; on exhausted chain fails with `provider_unavailable`; feeds one attempt record per invoke to an in-memory event/attempt sink (Clarification Q4) including target identity, outcome, and `selection_reason`; keeps the same request identity across internal retries; never consults provider history or a circuit breaker; never emits `repair_retry`; on fallback after partial streamed text emits `regenerating`, discards earlier text, and never splices providers (test-only streaming harness for T6 — production fake unchanged, Clarification Q2). No D1/R2/DO I/O. Speculative parallel walk out of scope. **Satisfies**: FR-001–FR-011; **proved by**: T-D3-01..T-D3-13.

---

## Phase 3: Verification

**Purpose**: Delivery plan §3.10 — every prior suite stays green alongside the new one, not just the latest.

- [ ] T015 [US1] From `ai-platform/`, run `npx vitest run test/invocation.test.ts` (this slice's named cases, all under the default Node pool — D3 is CPU-only), then run the full prior suite — `npx vitest run` (default Node-pool prior suites including `invocation.test.ts` (D3), `provider-port.test.ts`, `router.test.ts` (D2), `prompt-registry.test.ts`, `prompt-composer.test.ts` (D1), `manifest.test.ts` (A4), `canonical.test.ts` (A3), `taxonomy.test.ts`, `reference.test.ts`, `error-body.test.ts`, `trace.test.ts`, `log-redaction.test.ts` (A2), `health.test.ts`, `env-deploys.test.ts` (A1), `context-validator.test.ts` (C2)) and `npx vitest run --config vitest.workers.config.ts` (workers-pool prior suites: `control.test.ts` (B2), `identity.test.ts`, `entitlement.test.ts`, `rate-limit.test.ts` (B3), `admission-credit.test.ts`, `quota-do.test.ts` (B4), `capability.test.ts` (C1), `journal.test.ts` (C3); `context.test.ts`, `config-cache.test.ts`, `migrations.test.ts` (A5); `adapter.test.ts` (A6)). Confirm every prior suite stays green. No new test is added here — this is the §3.10 checkpoint gate. **Satisfies**: the §3.10 checkpoint rule (every branch and named boundary this slice covers — bounded retry/fallback, terminal no-retry, jitter, per-attempt journal feed, exhausted → `provider_unavailable`, regenerating/no-splice, retry budget, timeout fallback reason, chain-only walk, no history spy, same-request internal retry, no `repair_retry`). Proved by itself.

---

## Phase 4: Documentation

**Purpose**: Always present. The one documentation artifact the plan names that does not yet exist on disk (`quickstart.md`); written only after the suite is green. The contract was already frozen during the plan phase.

- [ ] T016 [US1] Create `specs/030-invocation-retry-fallback/quickstart.md` from `.specify/templates/ai-platform-quickstart-template.md`, scoped to this slice only. **§1 Architecture context** — delivery plan §3.5 row D3; `17-ai-platform.md` §4.3.7, §8.6, §6.6; what the spec delivered; what the plan scoped. **§2 What was implemented** — `src/invocation/index.ts`; frozen `contracts/invocation-attempt-loop.md`. **§3 Files to review** — only this slice's source, test, and contract files (`ai-platform/src/invocation/`, `ai-platform/test/invocation.test.ts`, `specs/030-invocation-retry-fallback/contracts/`). **§4 Prerequisites** — `cd ai-platform && npm install` (first time); CPU-only tests, no miniflare bindings required for this slice. **§5 Run the automated suite** — `cd ai-platform && npx vitest run test/invocation.test.ts`; slice-only (no full-suite `npm test`). **§6 Inspect the changes** — read the frozen contract; grep `src/invocation` for `selection_reason` / `regenerating` / `provider_unavailable`; run the focused test file. **No §7** — CI is the only verification path. **Slice-only scope explicit**: no prior-slice files in the review table, no combined test counts, no prior-slice regression commands. Not traced to an FR (template-mandated review surface).

---

## Dependencies & Execution Order

### Phase Dependencies

- **Tests (T001–T013)** — none beyond already-frozen contracts and Consumes Binding modules; written to fail before the code exists. All touch `invocation.test.ts` (sequential — each appends to the substrate T001 created). No `[P]` within Phase 1 (same file).
- **Implementation (T014)** — depends on T001–T013 existing (red); lands `src/invocation/index.ts` and turns T-D3-01..13 green. Consumed D2 modules are not modified.
- **Verification (T015)** — depends on T001–T014; runs the whole suite (this slice + every prior slice) per §3.10.
- **Documentation (T016)** — depends on T015 (the quickstart records a green suite).

### Within the Slice

- Tests written to fail before implementation; implementation makes them pass; verification confirms the whole suite including prior slices stays green.
- Within Phase 1, order follows plan Sequencing: T8 substrate → bounded retry (T1/T3/T7/T12) → fallback walk (T2/T5/T9/T10/T11/T13) → journal feed (T4) → regenerating (T6).
- Single implementation unit covers FR-001–FR-011.

### Parallel Opportunities

- Phase 1: no `[P]` — all tests share `ai-platform/test/invocation.test.ts`.
- Phase 2: single task (T014) — no `[P]`.
- Phase 4 (T016) is a single task — no `[P]`.

---

## Notes

- [P] tasks = different files, no dependencies. This slice has no `[P]` tasks — one test file and one implementation file.
- Every named test T1–T13 from `spec.md` is covered by its own task (including spy T11); no cases dropped; task list is 16 (under the 25-task cap).
- Every task traces to an `FR-###` from `spec.md` (tests also state the `SC-###` they satisfy) — no task adds a requirement the spec does not name. Clarifications Q1–Q4 guide how (module path, harness, sleeper, sink), not what.
- No Polish phase and no Foundational phase — prerequisites are the already-merged slices in the plan's Consumes Binding (D2).
- Consumed modules are imported, not modified (delivery plan §2.3 — extend, never rewrite).
- Tests land before or alongside their implementation, never after (delivery plan §2.2).
- Preserve the I/O budget: no DO, D1, or R2 I/O from this slice; attempt loop is CPU-only with an in-memory sink (§6.1, §7.5, §13.6).
