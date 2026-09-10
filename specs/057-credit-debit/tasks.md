# Tasks: Declared-weight credit debit in admission (G2)

**Input**: Design documents from `specs/057-credit-debit/`

**Prerequisites**: `plan.md` (required), `spec.md` (required for the user story). `research.md` is never produced on this platform (the research is `docs/architecture/ai-platform/01-ai-platform.md`). `data-model.md` is not produced — this slice defines no D1 entity and writes no D1 schema (G1 already created `entitlement.credit_budget`). `contracts/` (`credit-budget-admission.md`, `credit-rpc-debit.md`) are already frozen on disk (written during the plan phase). `AVAILABLE_DOCS`: `contracts/`. `quickstart.md` is written in Phase 4 (Documentation).

**Tests**: Tests are mandatory on this platform (delivery plan §3.10). Every named test in the spec's `### Test plan` (ten cases) is covered by its own task, written to fail before the snapshot field, remaining-budget / credit-ratio predicates, `credits` debit, and stage-15 wiring exist. Layers are **DO unit** (`quota-do.test.ts`) and **Integration (spy)** (`admission-credit.test.ts`) (delivery plan §3.12.10 row G2; §13.5 Pipeline tests). Spy cases (`guard_rejection_debits_nothing_and_writes_no_journal_row`, `exactly_two_durable_object_round_trips_per_request`) each have their own task. Permanent suite joins CI (delivery plan §3.11).

**Organization**: One user story (US1, P1) — G2 is one slice, one story (delivery plan §2.6, overrides). No cross-story parallelism section. No Setup phase — contracts are already on disk; test files already live in the workers pool; plan Files are produced by Tests / Implementation / Documentation. No Foundational or Polish phase — prerequisites are already-merged Needs (G1, B4, F4) in the plan's Consumes Binding.

**Task count**: 18 (≤25).

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: US1 (this slice has a single user story)
- Include exact file paths in descriptions

## Path Conventions

- **Flutter desktop app**: `frontend/lib/`, `frontend/test/` — *not touched by G2*
- **Supabase backend**: `backend/migrations/`, `backend/functions/`, `backend/tests/` — *not touched by G2*
- **AI gateway Worker**: `ai-platform/src/`, `ai-platform/migrations/`, `ai-platform/test/`
- **Spec Kit artifacts**: `specs/057-credit-debit/`
- G2 extends B4's three existing modules (`src/quota-do/`, `src/admission/`, `src/credit/`) plus existing stage-15 `creditUsage` call sites (`src/pipeline/index.ts`, `src/worker.ts`). Consumed F4 `src/soft-threshold/` stays unmodified. No new D1 migration. Frozen Consumes contract files (`specs/024-quota-do-admission/contracts/quota-do-rpc.md`, `specs/042-soft-threshold-degraded-routing/contracts/*`, `specs/056-plan-catalogue/contracts/plan-catalogue.md`) are not edited (delivery plan §2.3).

---

## Phase 1: Tests (written to fail before the code exists)

**Purpose**: One task per named test in the spec's `### Test plan` (§3.12.10 row G2). Eight DO unit cases live in the existing B4 harness `ai-platform/test/quota-do.test.ts` (same Miniflare `env.DO` RPC harness). Two Integration (spy) cases live in `ai-platform/test/admission-credit.test.ts` and reuse B4's `createDoSpy(env.DO)`. Until `credit_budget` / `credits` / `creditsUsed` exist, assertions fail — the intended red state. DO-unit file vs spy file are `[P]`; within each file, append sequentially.

- [X] T001 [US1] Extend the local harness in `ai-platform/test/quota-do.test.ts` (`EntitlementSnapshot.credit_budget`, `PeriodCounters.creditsUsed`, `CreditRequest.credits`; `buildEntitlementSnapshot` default positive `credit_budget`; existing `PeriodCounters` equality includes `creditsUsed`) and add named test `credit_debits_declared_quota_weight`: after admission, stage-15 credit with `credits: W` increases `creditsUsed` by exactly W (Delivery Plan §3.12.10 G2 *Debit*; A15; §4.3.3; §5.1). Fails red until `creditRPC` adds `credits` to `creditsUsed`. Do not rewrite B4 jti / idempotency / concurrency / grace / request-quota describes. **Satisfies**: FR-002, FR-004, FR-005 / SC-001. **Proves**: `credit_debits_declared_quota_weight`.

- [X] T002 [US1] Add named test `conversational_leg_debits_per_leg` to `ai-platform/test/quota-do.test.ts`: two independently admitted-then-credited legs each with `credits: W` increase `creditsUsed` by 2W, not by a single conversation-level debit (Delivery Plan §3.12.10 G2 *Debit*; A15; §5.1). Fails red until per-call `credits` debit exists. **Satisfies**: FR-004 / SC-001. **Proves**: `conversational_leg_debits_per_leg`.

- [X] T003 [US1] Add named test `cancelled_request_debits_full_declared_weight` to `ai-platform/test/quota-do.test.ts`: stage-15 credit with `partial: true` still adds the full `credits` weight (`creditsUsed` increases by W even when `usage.tokens` / `usage.cost` are partial) (Delivery Plan §3.12.10 G2 *Debit*; A15). Fails red until `creditRPC` ignores `partial` for the credit debit. **Satisfies**: FR-006 / SC-002. **Proves**: `cancelled_request_debits_full_declared_weight`.

- [X] T004 [US1] Add named test `credit_budget_exhausted_quota_exhausted_with_reset_at` to `ai-platform/test/quota-do.test.ts`: `creditsUsed >= credit_budget` with request-quota remaining answers `quota_exhausted` carrying `period_end` (wire `{ reset_at }` via the existing F4/A2 chain); no overage; additive AI is refused and nothing hard-locks (Delivery Plan §3.12.10 G2 *Admission*; §8.8; A15; §4.3.3). Fails red until remaining-budget includes credit-budget exhaustion. **Satisfies**: FR-001, FR-008, FR-010 / SC-003. **Proves**: `credit_budget_exhausted_quota_exhausted_with_reset_at`.

- [X] T005 [US1] Add named test `credit_ratio_soft_threshold_sets_degraded_flag` to `ai-platform/test/quota-do.test.ts`: credit ratio (`creditsUsed / credit_budget`) ≥ `soft_threshold` with credit budget remaining answers `{ admitted, degraded: true }` — the flag F4 routes on — and does not refuse (Delivery Plan §3.12.10 G2 *Admission*; §8.8; §4.3.3; A15). Fails red until `isSoftThresholdCrossed` uses the credit ratio. **Satisfies**: FR-009, FR-010 / SC-003. **Proves**: `credit_ratio_soft_threshold_sets_degraded_flag`.

- [X] T006 [US1] Add named test `below_credit_soft_threshold_not_degraded` to `ai-platform/test/quota-do.test.ts`: credit ratio below the soft threshold with credit budget remaining answers admitted without `degraded` (§8.8 else-normal; Delivery Plan §3.11 every branch). Fails red until the below-threshold credit-ratio branch exists. **Satisfies**: FR-009 / SC-003. **Proves**: `below_credit_soft_threshold_not_degraded`.

- [X] T007 [US1] Add named test `token_and_cost_counters_settle_actuals_unchanged` to `ai-platform/test/quota-do.test.ts`: `tokensUsed` / `costUsed` follow `usage` (including partial usage on cancel); they do not set `credits`, remaining-budget, or the soft-threshold decision (Delivery Plan §3.12.10 G2 *Invariants*; A15; §4.3.3). Fails red until token/cost stay settlement-only beside `creditsUsed`. **Satisfies**: FR-002, FR-005, FR-011, FR-015 / SC-004. **Proves**: `token_and_cost_counters_settle_actuals_unchanged`.

- [X] T008 [US1] Add named test `credit_rpc_gains_fields_without_changing_existing_meanings` to `ai-platform/test/quota-do.test.ts`: entitlement snapshot has `credit_budget`; credit body has `credits`; period counters have `creditsUsed`; `usage.tokens` / `usage.cost` / `requestsUsed` / `partial` keep prior meanings (Delivery Plan §3.12.10 G2 *Invariants*; A15; Delivery Plan §2.3). Fails red until the three field extensions exist without rewriting existing credit-RPC fields. **Satisfies**: FR-012 / SC-005. **Proves**: `credit_rpc_gains_fields_without_changing_existing_meanings`.

- [X] T009 [P] [US1] In `ai-platform/test/admission-credit.test.ts`, apply G1 `ai-platform/migrations/20260911120000_plan_catalogue.sql` in `beforeAll` so `entitlement.credit_budget` exists; extend `seedEntitlement` with a positive `creditBudget` default and include `credit_budget` on the entitlements `SELECT`. Add named spy test `guard_rejection_debits_nothing_and_writes_no_journal_row`: credit-budget exhaustion at admission — `createDoSpy(env.DO)` shows no credit RPC (credit is not invoked) and no `ai_request` row is written (reuse B4's no-journal assertion) (Delivery Plan §3.12.10 G2 *Debit*; A15). Spy — absence of the credit call and journal row is separate from T001–T008 outcome asserts. Fails red until remaining-budget refuses on `credit_budget` before any credit call. **Satisfies**: FR-007 / SC-002. **Proves**: `guard_rejection_debits_nothing_and_writes_no_journal_row`.

- [X] T010 [US1] Add named spy test `exactly_two_durable_object_round_trips_per_request` to `ai-platform/test/admission-credit.test.ts`: admitted then credited through `runAdmission` + `creditUsage` with `createDoSpy(env.DO)` wrapping the same stub — `fetchCount() === 2` (admission + credit); no third trip (Delivery Plan §3.12.10 G2 *Invariants*; §4.3.3; Delivery Plan §6.4). Spy — call count is separate from T009's absence assert. Fails red if G2 adds a round trip. **Satisfies**: FR-013 / SC-005. **Proves**: `exactly_two_durable_object_round_trips_per_request`.

---

## Phase 2: Implementation (plan Files section)

**Purpose**: Implementation units from `plan.md` → Files not already produced as Tests (Phase 1) or Documentation. Order follows plan Sequencing (snapshot + remaining-budget + creditRPC in `quota-do` → `mapEntitlementSnapshot` → `CreditInput.credits` → stage-15 wiring → F4 fixture seed). Consumed B4 RPC discriminants, F4 `src/soft-threshold/`, G1 catalogue, and D1 schema stay unchanged aside from the listed extensions (delivery plan §2.3). Do not touch `ai-platform/src/pricing/`, B3 rate limiting, or C2 cost ceiling.

- [ ] T011 [US1] Modify `ai-platform/src/quota-do/index.ts` — add `EntitlementSnapshot.credit_budget`, `PeriodCounters.creditsUsed`, `CreditRequest.credits`; `initialPeriodCounters` includes `creditsUsed: 0`. Remaining-budget = B4 request-quota exhaustion **or** credit-budget exhaustion (`creditsUsed >= credit_budget`); token and cost counters no longer determine remaining-budget. `isSoftThresholdCrossed` uses the credit ratio (`creditsUsed / credit_budget`) with F4's used/budget rules (`credit_budget > 0`, `soft_threshold` in `(0, 1]`). `creditRPC` adds `credits` to `creditsUsed` even when `partial: true` and still adds `usage.tokens` / `usage.cost` / `requestsUsed`. Do not rewrite B4's four admission questions, one-then-one round-trip, replay, idempotency, concurrency, ephemeral store, or fail-open grace. In the same change, keep `admission_budget_exhaustion_rejected` in `ai-platform/test/quota-do.test.ts`; retarget `admission_token_budget_exhaustion_rejected` and `admission_cost_budget_exhaustion_rejected` to settlement-only; seed `admission_soft_threshold_sets_degraded` from the credit ratio. **Satisfies**: FR-001, FR-002, FR-003, FR-004, FR-005, FR-006, FR-008, FR-009, FR-010, FR-011, FR-012, FR-015. **Proved by**: `credit_debits_declared_quota_weight`, `conversational_leg_debits_per_leg`, `cancelled_request_debits_full_declared_weight`, `credit_budget_exhausted_quota_exhausted_with_reset_at`, `credit_ratio_soft_threshold_sets_degraded_flag`, `below_credit_soft_threshold_not_degraded`, `token_and_cost_counters_settle_actuals_unchanged`, `credit_rpc_gains_fields_without_changing_existing_meanings`.

- [ ] T012 [US1] Modify `ai-platform/src/admission/index.ts` — `mapEntitlementSnapshot` copies G1 `credit_budget` from the config-cache entitlement row onto the snapshot sent in the admission RPC. Outcome mapping (`quota_exhausted` + `periodReset`, `degraded`) unchanged; still exactly one DO fetch. Do not rewrite B4 `runAdmission` questions, grace, or F4 routing. Depends on T011 snapshot field. **Satisfies**: FR-001, FR-003, FR-008, FR-012. **Proved by**: `credit_budget_exhausted_quota_exhausted_with_reset_at`, `credit_ratio_soft_threshold_sets_degraded_flag`, `guard_rejection_debits_nothing_and_writes_no_journal_row`.

- [ ] T013 [P] [US1] Modify `ai-platform/src/credit/index.ts` — add `CreditInput.credits`; `invokeCreditRpc` JSON body gains `credits`. Token/cost `usage` and `partial` keep their meanings. Grace queue schema and reconcile persistence are not rewritten (Consumes B4). Do not add a Durable Object round trip. **Satisfies**: FR-002, FR-005, FR-006, FR-011, FR-012, FR-013. **Proved by**: `credit_debits_declared_quota_weight`, `cancelled_request_debits_full_declared_weight`, `token_and_cost_counters_settle_actuals_unchanged`, `exactly_two_durable_object_round_trips_per_request`.

- [ ] T014 [US1] Modify `ai-platform/src/pipeline/index.ts` — `settleHappyPath` passes existing `quotaWeight` as `credits` into `creditUsage`. Do not add a pipeline stage, a third DO trip, or a provider price on the request path. Depends on T013. **Satisfies**: FR-004, FR-005, FR-014. **Proved by**: `credit_debits_declared_quota_weight`, `credit_rpc_gains_fields_without_changing_existing_meanings`.

- [ ] T015 [P] [US1] Modify `ai-platform/src/worker.ts` — `settleTerminal`, `settleCompletedRequest`, and broker `creditSink` pass `Number(manifest.Economics.quotaWeight)` as `credits` into `creditUsage` (cancelled path included). Do not put a provider price on the request path. Depends on T013. **Satisfies**: FR-004, FR-005, FR-006, FR-014. **Proved by**: `credit_debits_declared_quota_weight`, `cancelled_request_debits_full_declared_weight`.

- [ ] T016 [US1] Modify `ai-platform/test/soft-threshold-routing.test.ts` (fixture only) — apply G1 `plan_catalogue` migration so `credit_budget` exists; seed `credit_budget` / `creditsUsed` (via `seedEntitlement` + the admit/credit helper passing `credits`) so F4 routing cases still cross the `degraded` flag G2 now sets from the credit ratio. Do not change `routing_tier` / `degraded_notice` assertions. Do not rewrite `ai-platform/src/soft-threshold/`. Depends on T011–T013. **Satisfies**: FR-009 (do not rewrite F4 routing). **Proved by**: F4 routing cases remaining green under Verification (G2 `credit_ratio_soft_threshold_sets_degraded_flag` is the credit-ratio behaviour).

---

## Phase 3: Verification

**Purpose**: Delivery plan §3.10 — every prior suite stays green alongside the new one, not just the latest.

- [ ] T017 [US1] From `ai-platform/`, run this slice's Workers suite — `npx vitest run --config vitest.workers.config.ts test/quota-do.test.ts test/admission-credit.test.ts` (named cases `credit_debits_declared_quota_weight` … `exactly_two_durable_object_round_trips_per_request`). Then run every prior slice's suite: `npx vitest run` (default Node-pool prior suites) and `npx vitest run --config vitest.workers.config.ts` (workers-pool prior suites, including F4 `soft-threshold-routing.test.ts` and G1 `plan-catalogue.test.ts`). Confirm G2's ten named cases are green and every prior suite stays green. No new test is added here — this is the §3.10 checkpoint gate. Confirm inherited prohibitions: Consumes contract files and `src/soft-threshold/` not rewritten; no D1 migration; no third DO trip; no journal row on guard rejection; no provider price on the request path; token/cost remaining-budget not folded into credit admission; B3 `rate_limited` and C2 cost ceiling untouched; no §9.14 mechanism; no per-request server-side state (delivery plan §6.4). **Satisfies**: the §3.10 checkpoint rule (ten named tests + prior suites). Proved by itself.

---

## Phase 4: Documentation

**Purpose**: Always present. The one documentation artifact the plan names that does not yet exist on disk (`quickstart.md`); written only after the suite is green. Contracts were already frozen during the plan phase. No other documentation artifact is named for a separate `[P]` task (no `ai-platform/README.md` — not the bootstrap slice).

- [ ] T018 [US1] Create `specs/057-credit-debit/quickstart.md` from `.specify/templates/ai-platform-quickstart-template.md`, scoped to this slice only. **§1 Architecture context** — delivery plan §3.13 row G2; `01-ai-platform.md` §4.3.3 / §5.1 / §8.8 / A15; what the spec delivered; what the plan scoped. **§2 What was implemented** — declared-weight `credits` debit; snapshot `credit_budget`; period `creditsUsed`; credit-budget exhaustion and credit-ratio `degraded`; token/cost settlement unchanged; two-round-trip invariant held. **§3 Files to review** — only this slice's `src/quota-do/index.ts`, `src/admission/index.ts`, `src/credit/index.ts`, stage-15 `creditUsage` wiring that passes `quotaWeight`, this slice's named tests in `test/quota-do.test.ts` and `test/admission-credit.test.ts`, and `contracts/*` (no prior-slice files). **§4 Prerequisites** — omit (`npx vitest run` against this slice's test files is sufficient). **§5 Run the automated suite** — slice-only `npx vitest run --config vitest.workers.config.ts test/quota-do.test.ts test/admission-credit.test.ts`; no full-suite `npm test`, no combined prior-slice counts. **§6 Inspect the changes** — grep `credit_budget` / `creditsUsed` / `credits:`; read the two contract files; confirm Consumes contract files and `src/soft-threshold/` are not rewritten. **No §7 Manual validation** — CI is the only verification path (plan; DP-3). Renumber remaining sections sequentially with no gaps. **Slice-only scope explicit**: no prior-slice files in the review table, no combined test counts, no prior-slice regression commands. Not traced to an FR (template-mandated review surface).

---

## Dependencies & Execution Order

### Phase Dependencies

- **Tests (T001–T010)** — none beyond already-frozen contracts and Consumes Binding modules (G1, B4, F4); written to fail before the code exists. T001–T008 share `quota-do.test.ts` (T001 creates the G2 substrate; T002–T008 append). T009 is `[P]` relative to T001–T008 (spy file vs DO-unit file) and includes the G1 migration / `seedEntitlement` substrate; T010 appends after T009 (same spy file).
- **Implementation (T011–T016)** — after tests exist (red). Order follows plan Sequencing: Quota DO fields + remaining-budget + credit debit (T011) → admission snapshot copy (T012) → `CreditInput.credits` (T013) → pipeline / worker wiring (T014–T015) → F4 fixture seed (T016).
- **Verification (T017)** — depends on T001–T016; runs this slice's workers suite plus every prior suite per §3.10.
- **Documentation (T018)** — depends on T017 (the quickstart records a green suite).

### Within the Slice

- Tests written to fail before implementation; implementation makes them pass; verification confirms the whole suite including prior slices stays green.
- Plan Sequencing maps to Implementation order: snapshot / remaining-budget / creditRPC (T011) → `mapEntitlementSnapshot` (T012) → `CreditInput.credits` (T013) → `quotaWeight` as `credits` at existing call sites (T014–T015) → F4 credit-ratio fixture (T016) → quickstart (T018).
- Test-file Files-section rows for the ten named tests are produced by Phase 1. Remaining Files units are T011–T016 plus T018 (`quickstart.md`). Two contracts are already frozen — no task recreates them.

### Parallel Opportunities

- Phase 1: T009 is `[P]` relative to T001–T008 (different file). Within each suite file, append sequentially (no `[P]`). Spy cases T009 and T010 remain separate tasks from each other and from outcome asserts T001–T008.
- Phase 2: T013 is `[P]` relative to T012 (credit module vs admission mapping — different files; both follow T011). T015 is `[P]` relative to T014 (worker vs pipeline — different files; both depend on T013). T016 follows T011–T013 (F4 cases need snapshot, debit, and `CreditInput.credits`) and is independent of T014–T015.
- Phase 4 (T018) is a single task — no `[P]`.

---

## Notes

- [P] tasks = different files, no dependencies. Marked: T009, T013, T015.
- Every named test from `spec.md` is covered by its own task; no test is folded into another. Spy cases `guard_rejection_debits_nothing_and_writes_no_journal_row` (absence) and `exactly_two_durable_object_round_trips_per_request` (call count) are each a separate task.
- Every task traces to an `FR-###` from `spec.md` (tests also state the `SC-###` they satisfy) — or to the §3.10 checkpoint / the template-mandated quickstart. No task adds a requirement the spec does not name.
- No Polish phase and no Foundational phase — Needs are G1, B4, F4 (Consumes Binding).
- Consumed modules are imported/bound, not rewritten (delivery plan §2.3 — extend, never rewrite). G2 does not absorb G1 catalogue/assignment, G3 usage gauge, G4 invoice/activation, F4 `routing_tier` / `degraded_notice`, B3 `rate_limited`, or C2 cost ceiling.
- Tests land before or alongside their implementation, never after (delivery plan §2.2).
- Preserve §6.4: no §9.14 mechanism; no second Quota DO round trip or second R2 object; no guard-rejection journal; no per-request server-side state; request path never sees a price (FR-014).
