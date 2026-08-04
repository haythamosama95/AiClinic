# Tasks: Soft-threshold degraded routing (F4)

**Input**: Design documents from `specs/042-soft-threshold-degraded-routing/`

**Prerequisites**: `plan.md` (required), `spec.md` (required for the user story). `research.md` is never produced on this platform (the research is `docs/architecture/17-ai-platform.md`). `data-model.md` is not produced — F4 defines no entities and introduces no schema change (A5 already owns `entitlement.soft_threshold` and nullable `ai_request.routing_tier`). `contracts/soft-threshold-admission.md` and `contracts/degraded-routing-signal.md` are already frozen on disk (written during the plan phase per DP-4). `quickstart.md` is written in Phase 4 (Documentation).

**Tests**: Tests are mandatory on this platform (delivery plan §3.10). Every named test in the spec's `### Test plan` (T1–T7) is covered by its own task, written to fail before the soft-threshold admission branch and gateway wiring exist. Spy case T6 is a separate task from outcome cases. Layer is **Integration** (delivery plan §3.11.6 row F4; §13.5 Pipeline tests — fake provider / deterministic policy; Miniflare DO + D1; spy on Quota DO fetch count). All seven cases live in `ai-platform/test/soft-threshold-routing.test.ts`. Fixtures seed Quota DO counters / entitlement snapshot into the target region before the request under test (Clarification Session 2026-08-02).

**Organization**: One user story (US1, P1) — F4 is one slice, one story (delivery plan §2.6, overrides). No cross-story parallelism section. No Setup phase — contracts are already on disk; plan Files are created by Tests/Implementation. No Foundational or Polish phase — prerequisites are already-merged Needs (D2, B4) in the plan's Consumes Binding.

**Task count**: 15 (≤25).

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: US1 (this slice has a single user story)
- Include exact file paths in descriptions

## Path Conventions

- **Flutter desktop app**: `frontend/lib/`, `frontend/test/` — *not touched by F4*
- **Supabase backend**: `backend/migrations/`, `backend/functions/`, `backend/tests/` — *not touched by F4*
- **AI gateway Worker**: `ai-platform/src/`, `ai-platform/migrations/`, `ai-platform/test/`
- **Spec Kit artifacts**: `specs/042-soft-threshold-degraded-routing/`
- The Worker lives in `ai-platform/` at the repository root, a sibling of `frontend/` and `backend/` (delivery plan §7.1). F4 adds no `ai-platform/migrations/` edits — `routing_tier` column is A5's. Consumed D2 `src/router/` and A2 `src/errors.ts` are imported unchanged.

---

## Phase 1: Tests (written to fail before the code exists)

**Purpose**: One task per named test in the spec's `### Test plan` (§3.11.6 row F4 + §3.10 coverage additions T4–T7). All seven cases share `ai-platform/test/soft-threshold-routing.test.ts` (workers-pool). Until Quota DO soft-threshold branch, admission mapping, `src/soft-threshold/`, journal `routingTier`, and adapter `degraded_notice` exist, imports/assertions fail — the intended red state. Order follows plan Sequencing themes (soft degrade → hard exhaustion → below threshold → client-injection prohibition → persist → one-DO-trip spy → sole error code). Same-file appends are sequential — no `[P]` within this phase.

- [X] T001 [US1] Add named test `soft_threshold_selects_degraded_target` (T1) to `ai-platform/test/soft-threshold-routing.test.ts` (integration): create the workers-pool substrate — seed Quota DO counters / entitlement snapshot into the soft-threshold-crossed / budget-remaining region (Clarification); load a routing policy with distinct standard and degraded target chains; compose admission → soft-threshold signal → D2 router → accepted wire. Assert Quota DO / admission returns `{ allowed, degraded: true }`, gateway `routing_tier = degraded`, router selects the degraded-tier target chain, client receives `accepted { degraded_notice: true }`, and the request is not refused (§8.8; §4.3.7; §3.11.6 F4). Fails red until soft-threshold admission + signal + adapter extensions exist. **Satisfies**: FR-002, FR-005, FR-007, FR-008 / SC-001. **Proves**: T1.

- [X] T002 [US1] Add named test `hard_exhaustion_quota_exhausted_admin_path_no_lock` (T2) to `ai-platform/test/soft-threshold-routing.test.ts` (integration): seed hard-exhausted period budget; assert gateway returns `quota_exhausted` carrying A2 `period_reset` (entitlement `period_end` — operator-addressable admin path), additive AI path is refused with that clear reason, and admission refusal emits no product-wide lock / clinical-block signal (§8.8; §4.3.3; constitution V; E4 owns UI chrome). **Satisfies**: FR-001, FR-003, FR-004 / SC-002. **Proves**: T2.

- [X] T003 [US1] Add named test `below_threshold_traffic_unaffected` (T3) to `ai-platform/test/soft-threshold-routing.test.ts` (integration): seed below-soft / budget-remaining region; assert admission allows without `degraded`, `routing_tier` is `standard`, router selects the standard-tier chain, and accepted event omits soft-threshold `degraded_notice` (§8.8; §3.11.6 F4). **Satisfies**: FR-010 / SC-003. **Proves**: T3.

- [X] T004 [US1] Add named test `soft_threshold_tier_not_accepted_from_client` (T4) to `ai-platform/test/soft-threshold-routing.test.ts` (integration): supply client-side tier / degraded trigger fields on the request; assert they are ignored and only the gateway-set `routing_tier` from admission applies (§4.3.7; §8.8; §3.10 prohibition). **Satisfies**: FR-008 / SC-004. **Proves**: T4.

- [X] T005 [US1] Add named test `soft_threshold_persists_routing_tier` (T5) to `ai-platform/test/soft-threshold-routing.test.ts` (integration): on soft-threshold path assert `ai_request.routing_tier = degraded` via C3 `createRequestRow`; on below-threshold path assert `standard` (§4.3.7; §3.10 happy path; A5 column, no migration). **Satisfies**: FR-006 / SC-004. **Proves**: T5.

- [X] T006 [US1] Add named test `soft_threshold_no_second_quota_do_round_trip` (T6) to `ai-platform/test/soft-threshold-routing.test.ts` (integration, spy): wrap Quota DO fetch in a counting spy; on soft-threshold admission assert exactly one DO round trip — no second trip for the degraded decision (§8.8; delivery plan §6.4; §3.10 inherited prohibition). **Satisfies**: FR-009 / SC-004. **Proves**: T6.

- [X] T007 [US1] Add named test `quota_exhausted_only_error_code_on_hard_exhaustion` (T7) to `ai-platform/test/soft-threshold-routing.test.ts` (integration): on hard exhaustion assert the emitted taxonomy code is exactly `quota_exhausted` and no other code from this slice's soft/hard branches (§8.8; §3.10 every error code). Soft-threshold path emits no error. **Satisfies**: FR-003 / SC-004. **Proves**: T7.

---

## Phase 2: Implementation (plan Files section)

**Purpose**: Implementation units from `plan.md` → Files not already produced as the Vitest entry or Documentation: Quota DO soft/hard extension, admission mapping, soft-threshold signal module, journal `routingTier`, adapter `degraded_notice`, and workers-pool include. Test file is produced in Phase 1; contracts already frozen; `quickstart.md` in Phase 4. Order follows plan Sequencing (Quota DO + admission → soft-threshold signal → journal + accepted → vitest include). Consumed D2 router and A2 `errors.ts` are imported unchanged (delivery plan §2.3).

- [X] T008 [US1] Modify `ai-platform/src/quota-do/index.ts` — after hard-exhaustion check fails open, evaluate soft threshold against entitlement snapshot (`soft_threshold` fraction vs period counters / budgets per `contracts/soft-threshold-admission.md`); on soft cross with budget remaining return `outcome: "admitted"` with `degraded: true`; on `quota_exhausted` include `period_end` from `entitlement.period_bounds.period_end`; still exactly one atomic admission RMW / no second DO trip (FR-003, FR-005, FR-009, FR-010). Do not rewrite B4's four questions, credit, ephemeral store, or fail-open grace. **Satisfies**: FR-003, FR-005, FR-009, FR-010. **Proved by**: T1, T2, T3, T6, T7.

- [X] T009 [US1] Modify `ai-platform/src/admission/index.ts` — map DO `degraded` onto the allow `AdmissionResult`; map exhaustion `period_end` → failure carrying `periodReset` for A2 `supplementaryFieldsForCode`; still exactly one DO fetch (FR-001, FR-003, FR-004, FR-005, FR-009). Depends on T008 response shapes. **Satisfies**: FR-001, FR-003, FR-004, FR-005, FR-009. **Proved by**: T1, T2, T3, T6, T7.

- [X] T010 [P] [US1] Create `ai-platform/src/soft-threshold/index.ts` — pure helpers: admission allow → `routing_tier` (`degraded` when `degraded: true`, else `standard`); soft allow → `degraded_notice: true` (omit below soft); ignore any client-supplied tier / degraded fields (FR-002, FR-006, FR-007, FR-008, FR-010). One implementation, no interface (D-15). Compose with unchanged D2 `selectRoute` / `RouterContext.routingTier`. **Satisfies**: FR-002, FR-006, FR-007, FR-008, FR-010. **Proved by**: T1, T3, T4. `[P]` vs T008/T009/T011/T012 — different file; binds to Freezes contracts.

- [X] T011 [P] [US1] Modify `ai-platform/src/journal/index.ts` — extend `RequestRowInput` with optional `routingTier: "standard" | "degraded"`; INSERT/bind `routing_tier` on `createRequestRow` only (FR-006). Do not rewrite C3 stage-9 timing, transitions, post-response, get-request, or persist `routing_decision`. **Satisfies**: FR-006. **Proved by**: T5. `[P]` vs T010/T012 — different file.

- [X] T012 [P] [US1] Modify `ai-platform/src/adapter.ts` — accepted-event builder accepts optional `degraded_notice` on `accepted.data` (FR-008). Do not rewrite A6 SSE vocabulary or one-terminal-event invariant. **Satisfies**: FR-008. **Proved by**: T1, T3. `[P]` vs T010/T011 — different file.

- [X] T013 [US1] Modify `ai-platform/vitest.workers.config.ts` — add `test/soft-threshold-routing.test.ts` to `include` so the suite joins CI permanently (delivery plan §3.10; plan Test Layout). Depends on T001 (file exists). **Satisfies**: CI wiring for T1–T7. **Proved by**: T1–T7 (permanent workers-pool home).

---

## Phase 3: Verification

**Purpose**: Delivery plan §3.10 — every prior suite stays green alongside the new one, not just the latest.

- [X] T014 [US1] From `ai-platform/`, run this slice's suite — `npx vitest run --config vitest.workers.config.ts test/soft-threshold-routing.test.ts`. Then run every prior slice's suite: `npx vitest run` (default Node-pool) and `npx vitest run --config vitest.workers.config.ts` (workers-pool), including prior Band F entries already gated. Confirm F4's seven named cases are green and every prior suite stays green. No new test is added here — this is the §3.10 checkpoint gate. F4's soft/hard branches emit only `quota_exhausted` (hard path); soft path is accept-with-notice. **Satisfies**: the §3.10 checkpoint rule (T1–T7 + prior suites). Proved by itself.

---

## Phase 4: Documentation

**Purpose**: Always present. The one documentation artifact the plan names that does not yet exist on disk (`quickstart.md`); written only after the suite is green. Contracts were already frozen during the plan phase. No other documentation artifact is named for a separate `[P]` task (no `ai-platform/README.md` — not the bootstrap slice).

- [X] T015 [US1] Create `specs/042-soft-threshold-degraded-routing/quickstart.md` from `.specify/templates/ai-platform-quickstart-template.md`, scoped to this slice only. **§1 Architecture context** — delivery plan §3.7 row F4; `17-ai-platform.md` §4.3.3 / §8.8 / §4.3.7; what the spec delivered; what the plan scoped. **§2 What was implemented** — soft-threshold admission branch; `routing_tier` / `degraded_notice` wiring; hard-exhaustion `period_reset` threading; persistence of `ai_request.routing_tier`; frozen `contracts/*`. **§3 Files to review** — only this slice's `src/quota-do/`, `src/admission/`, `src/soft-threshold/`, journal/adapter extensions, this slice's test file, and `contracts/*` (no prior-slice files). **§4 Prerequisites** — omit (`npx vitest run` against this slice's test file is sufficient). **§5 Run the automated suite** — slice-only `npx vitest run --config vitest.workers.config.ts test/soft-threshold-routing.test.ts`; no full-suite `npm test`, no combined prior-slice counts. **§6 Inspect the changes** — grep `degraded`, `routing_tier`, `period_end` / `period_reset`, focused Vitest file, frozen contracts. **§7 Manual validation** — omit; CI is the only verification path (DP-3). **Slice-only scope explicit**: no prior-slice files in the review table, no combined test counts, no prior-slice regression commands. Not traced to an FR (template-mandated review surface).

---

## Dependencies & Execution Order

### Phase Dependencies

- **Tests (T001–T007)** — none beyond already-frozen contracts and Consumes Binding modules (D2, B4); written to fail before the code exists. Same file — sequential appends (T001 creates the substrate; T002–T007 append).
- **Implementation (T008–T013)** — after tests exist (red). T008 (`quota-do`) first for DO response shapes; T009 (`admission`) depends on T008. T010–T012 (`soft-threshold/`, `journal/`, `adapter`) are `[P]` relative to each other and to T008 — different files, bind to Freezes. T013 (vitest include) depends on T001.
- **Verification (T014)** — depends on T001–T013; runs this slice plus every prior slice per §3.10.
- **Documentation (T015)** — depends on T014 (the quickstart records a green suite).

### Within the Slice

- Tests written to fail before implementation; implementation makes them pass; verification confirms the whole suite including prior slices stays green.
- Plan Sequencing maps to Implementation order: Quota DO soft/hard (T008) → admission map (T009) → soft-threshold signal (T010) → journal + accepted (T011–T012) → vitest include (T013) → quickstart (T015). T010–T012 may proceed in parallel.
- Vitest entry Files-section row is produced by Phase 1; not repeated as an Implementation source task. Remaining Files units: T008–T013 plus T015 (`quickstart.md`). Two contracts are already frozen — no task recreates them.

### Parallel Opportunities

- Phase 1: no `[P]` — all seven tests share one file.
- Phase 2: T010, T011, and T012 are `[P]` relative to each other (and to T008 once Freezes shapes are known). T009 follows T008. T013 follows T001.
- Phase 4: T015 is a single task — no `[P]`.

---

## Notes

- [P] tasks = different files, no dependencies. Marked: T010, T011, T012.
- Every named test T1–T7 from `spec.md` has its own Phase 1 task; spy case T6 is not folded into an outcome case.
- Every task traces to an `FR-###` from `spec.md` (tests also state the `SC-###` they satisfy) — or to Freezes / the §3.10 checkpoint / the template-mandated quickstart. No task adds a requirement the spec does not name.
- No Polish phase and no Foundational phase — Needs are D2, B4 (already merged; Consumes Binding).
- Consumed modules (`src/router/`, `src/errors.ts`) are imported/bound, not modified (delivery plan §2.3 — extend, never rewrite). No `frontend/` or `backend/` file is touched. No migration.
- Tests land before or alongside their implementation, never after (delivery plan §2.2).
- Preserve §6.4: no §9.14 mechanism; no second Quota DO round trip; no second R2 object per request; no D1-per-chunk; no per-request server-side state; no Flutter prompt/provider/model strings; client cannot inject `routing_tier`.
