---

description: "Task list for slice B4 — Quota Durable Object and admission stage"
---

# Tasks: Quota Durable Object and admission stage (B4)

**Input**: `specs/024-quota-do-admission/spec.md`, `specs/024-quota-do-admission/plan.md`

**Prerequisites**: A5, B3 (and transitive A2, A6, B1, B2) — already merged; see `plan.md` Consumes
Binding for the exact modules bound to.

**Tests**: Tests are mandatory for this platform (delivery plan §3.10). Every named test in the spec's
Test plan is a task, ordered to fail before the implementation that makes it pass.

**Organization**: One user story (US1, P1) — the spec has a single story. No cross-story parallelism.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: `US1`
- Include exact file paths in descriptions

## Path Conventions

- **Cloudflare Worker**: `ai-platform/src/`, `ai-platform/test/`, `ai-platform/migrations/`,
  `ai-platform/vitest.workers.config.ts`, `ai-platform/wrangler.toml`
- **Spec Kit artifacts**: `specs/024-quota-do-admission/`
- The Worker lives in `ai-platform/` at the repository root, a sibling of `frontend/` and `backend/`
  (delivery plan §7.1); the plan template's `frontend/lib/`, `backend/migrations/` conventions do not
  apply to this slice.

---

## Phase 1: Setup

**Purpose**: The one artifact the plan names that must exist before any test or handler binds to it —
the frozen RPC shapes later slices' `Consumes` will bind to.

- [X] T001 [US1] Write `specs/024-quota-do-admission/contracts/quota-do-rpc.md` freezing the admission
  RPC request/response shape (payload keys: `jti`, `installationId`, `idempotencyKey` plus the
  entitlement snapshot carried in), the credit RPC request/response shape (actual usage tokens/cost
  plus a `partial` flag), and the in-object ephemeral entry shape (`{expiresAt}` for the `jti` replay
  set and idempotency records). These are the `## Slice Contract → Freezes` artifacts (FR-001, FR-008,
  FR-010); the Quota DO handlers, the two callers, and the tests all bind to these shapes. Proved by
  every test below, which constructs requests in these shapes.

---

## Phase 2: Tests (written to fail before the code exists)

**Purpose**: One task per named test in the spec's Test plan (`spec.md` ### Test plan), per §3.11.2
row B4 layer "DO unit + concurrency + integration (spy)". DO unit + concurrency cases live in
`ai-platform/test/quota-do.test.ts`; integration (spy) cases live in
`ai-platform/test/admission-credit.test.ts`. The first task of each file also registers the file in
`ai-platform/vitest.workers.config.ts` `test.include`. Tests invoke the real Miniflare Durable Object
binding (`cloudflare:test` `env.DO`, `env.DO.idFromString(installationId)`) — Clarification Q3 — and
the integration spy cases wrap `env.DO` in a counting spy — Clarification Q4.

- [X] T002 [US1] `admission_fresh_jti_accepted` in `ai-platform/test/quota-do.test.ts` (DO unit): a
  previously-unseen `jti` is admitted as fresh. Also register `test/quota-do.test.ts` in
  `vitest.workers.config.ts` `test.include`. Asserts FR-004 (§3.11.2 row B4; §4.3.3; §6.1 stage 8).
- [X] T003 [US1] `admission_repeated_jti_rejected` in `ai-platform/test/quota-do.test.ts` (DO unit): a
  `jti` already seen for this installation is rejected as a replay. Asserts FR-004 (§3.11.2 row B4;
  §9.17).
- [X] T004 [US1] `admission_new_idempotency_key_accepted` in `ai-platform/test/quota-do.test.ts` (DO
  unit): a previously-unseen idempotency key is accepted as new. Asserts FR-005 (§3.11.2 row B4; §6.6).
- [X] T005 [US1] `admission_repeat_idempotency_key_returns_prior_record` in
  `ai-platform/test/quota-do.test.ts` (DO unit): a repeat idempotency key returns the existing
  request's state instead of starting a second inference. Asserts FR-005 (§3.11.2 row B4; §6.1 stage
  8; §6.6).
- [X] T006 [US1] `admission_budget_exhaustion_rejected` in `ai-platform/test/quota-do.test.ts` (DO
  unit): an installation with no remaining budget is rejected `quota_exhausted`. Asserts FR-006
  (§3.11.2 row B4; §6.1 stage 8; §5.4).
- [X] T007 [US1] `admission_concurrency_ceiling_rejected` in `ai-platform/test/quota-do.test.ts` (DO
  unit): an installation at its in-flight concurrency ceiling is rejected for lack of headroom.
  Asserts FR-007 (§3.11.2 row B4; §4.3.3; §4.4).
- [X] T008 [US1] `credit_adjusts_counters_with_actual_usage` in `ai-platform/test/quota-do.test.ts`
  (DO unit): a completed request's credit call adjusts the period counters by actual usage. Asserts
  FR-008 (§3.11.2 row B4; §6.1 stage 15; §4.3.3).
- [X] T009 [US1] `credit_adjusts_counters_with_partial_usage` in `ai-platform/test/quota-do.test.ts`
  (DO unit): a cancelled request's partial usage is credited. Asserts FR-008 (§3.11.2 row B4; §6.1
  stage 15; §6.4).
- [X] T010 [US1] `parallel_admissions_exact_final_count` in `ai-platform/test/quota-do.test.ts`
  (concurrency): N parallel admissions against one installation produce an exact final count, proving
  DO-level serialized counting (uses `ctx.storage` / `blockConcurrencyWhile`). Asserts FR-009
  (§3.11.2 row B4; §4.4).
- [X] T011 [US1] `ephemeral_entries_expire_in_place` in `ai-platform/test/quota-do.test.ts` (DO unit):
  `jti` replay and idempotency records older than the ephemeral horizon are evicted by the next
  admission's lazy sweep, with no `alarm()` handler and no table to prune. Asserts FR-010 (§3.11.2
  row B4; §7.7 `ephemeral`; §9.17; Clarification Q5).
- [X] T012 [US1] `admission_exactly_one_do_fetch_per_request` in
  `ai-platform/test/admission-credit.test.ts` (integration, spy): the pipeline admission stage makes
  exactly one Durable Object fetch per request — wrap `env.DO` in a counting spy and assert the fetch
  count. Also register `test/admission-credit.test.ts` in `vitest.workers.config.ts` `test.include`.
  Asserts FR-011 (§3.11.2 row B4; §6.1 stage 8; §7.5) — *spy case*.
- [X] T013 [US1] `admission_repeated_key_no_second_inference` in
  `ai-platform/test/admission-credit.test.ts` (integration, spy): a repeated idempotency key returns
  the original state and starts no second inference, observed through the same `env.DO` spy. Asserts
  FR-005, FR-011 (§3.11.2 row B4; §6.6) — *spy case*.
- [X] T014 [US1] `admission_expired_token_same_key_unauthenticated` in
  `ai-platform/test/admission-credit.test.ts` (integration): a transport retry whose token expired in
  the meantime carrying the same idempotency key is rejected `unauthenticated`, not returned as the
  original result, because idempotency is checked after identity. Asserts FR-012 (§3.11.2 row B4;
  §6.2).
- [X] T015 [US1] `quota_do_unavailable_capped_grace_then_rejection` in
  `ai-platform/test/admission-credit.test.ts` (integration): Quota DO unavailability serves the
  request under the capped grace allowance, then rejects once the cap is exhausted (fail-open deepened
  by stubbing `env.DO.fetch` to throw then to succeed). Asserts FR-013 (§3.11.2 row B4; §15 #3).
- [X] T016 [US1] `grace_usage_reconciled_afterwards` in
  `ai-platform/test/admission-credit.test.ts` (integration, spy): usage admitted under the fail-open
  cap is reconciled against the DO's counters afterwards — spy asserts the reconciliation credit call
  fires once the DO is reachable. Asserts FR-013 (§3.11.2 row B4; §15 #3) — *spy case*.
- [X] T017 [US1] `admission_rejection_counted_not_journaled` in
  `ai-platform/test/admission-credit.test.ts` (integration, spy): an admission rejection is tallied to
  bucketed `platform_counter` (the B3-frozen flush shape) and creates no `ai_request` row and no
  per-event row. Asserts FR-014 (§4.3.12; §7.5; B3 `Freezes`; §3.11.2 row B4) — *spy case*.

---

## Phase 3: Implementation

**Purpose**: One task per implementation unit in the plan's `## Files` section. Tests above are
written first and fail; these make them pass. Ordered so the in-object handlers exist before the DO
dispatch delegates to them, and the dispatch exists before the callers exercise it.

- [ ] T018 [US1] Write `ai-platform/src/quota-do/index.ts` — the Quota Durable Object handlers:
  `admissionRPC` (one atomic read-modify-write inside `ctx.blockConcurrencyWhile` answering `jti`
  freshness, idempotency-key novelty, remaining budget, and concurrency headroom, performing the lazy
  ephemeral sweep before answering), `creditRPC` (period counter adjustment by actual usage, including
  the `partial` flag), and the in-object ephemeral entry type. No pre-flight reservations (FR-015); no
  `alarm()` handler (Clarification Q5). Satisfies FR-001, FR-002, FR-003, FR-004, FR-005, FR-006,
  FR-007, FR-008, FR-009, FR-010, FR-015. Proved by T002–T011.
- [ ] T019 [US1] Extend `ai-platform/src/worker.ts` — implement `GatewayObject`'s `fetch`/rpc method,
  dispatching on the RPC kind from the request to `admissionRPC` / `creditRPC` from
  `src/quota-do/index.ts`. The existing `export class GatewayObject extends DurableObject { }` is
  extended in place; its name and the `DO → GatewayObject` binding in `wrangler.toml` are unchanged
  (delivery plan §2.3; spec `## Out of Scope`). Satisfies FR-001, FR-011. Proved by T002–T011 (DO
  unit cases hit this dispatch through `env.DO`). Depends on T018.
- [ ] T020 [P] [US1] Write `ai-platform/src/admission/index.ts` — the stage-8 caller: load the
  entitlement snapshot via `loadConfig(cache, reader, "entitlements", installationId)` (the A5/B3
  seam — Clarification Q2), build the admission RPC payload from the B3 `Principal.jti` /
  `Principal.installationId` and the A6-parsed idempotency key, call
  `env.DO.withId(env.DO.idFromString(installationId)).fetch(...)` exactly once, and return the
  admitted / replay / idempotent / `quota_exhausted` / concurrency-exhausted outcome. Implement the
  fail-open grace path: a DO `fetch` rejection admits under the capped grace allowance and queues
  reconciliation to the credit call (§15 #3). Satisfies FR-001, FR-004, FR-005, FR-006, FR-007,
  FR-011, FR-012, FR-013, FR-014. Proved by T012–T017.
- [ ] T021 [P] [US1] Write `ai-platform/src/credit/index.ts` — the stage-15 caller: build the credit
  RPC payload with actual usage (tokens/cost) plus the `partial` flag, and call the same DO instance
  exactly once. Satisfies FR-008, FR-016. Proved by T008, T009, T016.

---

## Phase 4: Verification

**Purpose**: The whole suite, including every prior slice's suite, green (delivery plan §3.10). A
checkpoint requires every prior suite green, not just the latest.

- [ ] T022 [US1] From `ai-platform/`, run `npx vitest run` (the full config), confirm this slice's 16
  tests pass and every prior slice's suite already registered in `vitest.workers.config.ts` /
  `vitest.config.ts` remains green. Assert no test was added to a layer §13.5 does not name. Satisfies
  the §3.10 coverage rule (every error code B4 emits — `unauthenticated`, `quota_exhausted` — every
  branch, every named boundary: one DO fetch, two DO calls per request lifecycle, ephemeral horizon,
  grace cap). Proved by itself.

---

## Phase 5: Documentation

**Purpose**: Always present. The quickstart documents this slice only.

- [ ] T023 [US1] Write `specs/024-quota-do-admission/quickstart.md` per
  `.specify/templates/ai-platform-quickstart-template.md`. **Slice-only scope**: list only this
  slice's files in the review table (`ai-platform/src/quota-do/index.ts`,
  `ai-platform/src/admission/index.ts`, `ai-platform/src/credit/index.ts`, the `worker.ts`
  `GatewayObject` extension, `ai-platform/test/quota-do.test.ts`,
  `ai-platform/test/admission-credit.test.ts`, `specs/024-quota-do-admission/contracts/quota-do-rpc.md`);
  only this slice's slice-only test command (`npx vitest run test/quota-do.test.ts
  test/admission-credit.test.ts`); no prior-slice files, no combined test counts, no full-suite
  `npm test`. Omit Prerequisites and Manual validation — CI is the only verification path. Sections:
  1. Architecture context (row B4 of `17b-…md` §3.3; `17-…md` §4.3.3 / §4.4 / §6.1 stage 8 / §9.17);
  2. What was implemented; 3. Files to review; 4. Run the automated suite; 5. Inspect the changes.
  Proved by T022.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (T001)**: none — write the frozen contract shapes first so handlers, callers, and tests
  bind to a frozen artifact, not prose (DP-4).
- **Tests (T002–T017)**: depend on T001 (request/response shapes). Written to fail before the code
  exists; the first task of each test file also registers the file in `vitest.workers.config.ts`.
- **Implementation (T018–T021)**: T018 (handlers) first; T019 (worker dispatch) depends on T018;
  T020 (admission caller) and T021 (credit caller) are independent of each other and depend on the
  contract T001 and on T019 being present at runtime (the dispatch makes `env.DO` answer).
- **Verification (T022)**: depends on T002–T021.
- **Documentation (T023)**: depends on T022 (the quickstart records a green suite).

### Within the Slice

- Contract shapes (T001) before handlers (T018) and callers (T020, T021).
- Handlers (T018) before the DO dispatch (T019) that delegates to them.
- Tests (T002–T017) written to fail before implementation; implementation (T018–T021) makes them
  pass; verification (T022) confirms the whole suite including prior slices stays green.

---

## Parallel Opportunities

- T002 (first `quota-do.test.ts` case + its vitest registration) and T012 (first
  `admission-credit.test.ts` case + its vitest registration) touch different test files and the shared
  `vitest.workers.config.ts`; the registration edits are tiny disjoint array entries, so the two may
  run in parallel if the config edit is sequenced. Within each test file the remaining cases (T003–T011
  in `quota-do.test.ts`, T013–T017 in `admission-credit.test.ts`) touch the same file and are
  sequential.
- T020 (admission caller) and T021 (credit caller) are marked [P] — different files, no
  dependencies on each other.

---

## Notes

- [P] tasks = different files, no dependencies.
- Tests are mandatory (delivery plan §3.10); every named test in the spec's Test plan is a task.
- One user story (US1, P1); no Foundational phase, no Polish phase, no MVP/deploy language (DP-1,
  DP-3).
- Preserve the I/O budget: one Quota DO round trip at admission and one credit call at stage 15 — no
  third DO call (§7.5; §13.6); no D1 read on a warm isolate beyond A5's (§4.3.2); no per-request
  server-side state (§4.4; §9.7).
- Do not modify any Consumes contract: A5's `ConfigCache`, B3's `Principal` and `platform_counter`
  bucketing, A2's `TaxonomyCode`, A6's parsed headers, B1/B2's lifecycle surface are all read-only
  here (delivery plan §2.3).
- Commit after each task or logical group; stop at the verification checkpoint to confirm the whole
  suite is green.