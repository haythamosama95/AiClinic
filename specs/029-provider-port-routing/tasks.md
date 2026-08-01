# Tasks: Provider port, fake adapter, and routing policy (D2)

**Input**: Design documents from `specs/029-provider-port-routing/`

**Prerequisites**: `plan.md` (required), `spec.md` (required for the user story). `research.md` is never produced on this platform (the research is `docs/architecture/17-ai-platform.md`). `data-model.md` is not produced — D2 defines no D1 entities and adds no columns (Consumes A5). `contracts/provider-port.md` and `contracts/routing-decision.md` are already frozen on disk (written during the plan phase per DP-4). `quickstart.md` is written in Phase 4 (Documentation).

**Tests**: Tests are mandatory on this platform (delivery plan §3.10). Every named test in the spec's `### Test plan` is covered by a task, written to fail before the code exists. Three same-file, same-concern pairs are combined into single tasks so the list stays under the 25-task cap without dropping cases: (T2+T3) retryable and terminal fake classes; (T4+T5) truncation and malformed; (T18+T21) export-surface and credential-absence prohibitions. All 21 named cases remain asserted.

**Organization**: One user story (US1, P1) — D2 is one slice, one story (delivery plan §2.6, overrides). No cross-story parallelism section. No Setup phase — contracts are already on disk; no migrations or `wrangler.toml` edits. No Foundational or Polish phase.

**Task count**: 24 (≤25).

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: US1 (this slice has a single user story)
- Include exact file paths in descriptions

## Path Conventions

- **AI gateway Worker**: `ai-platform/src/`, `ai-platform/test/`, `ai-platform/migrations/`, `ai-platform/vitest.config.ts`, `ai-platform/vitest.workers.config.ts`, `ai-platform/wrangler.toml`
- **Spec Kit artifacts**: `specs/029-provider-port-routing/`
- The Worker lives in `ai-platform/` at the repository root, a sibling of `frontend/` and `backend/` (delivery plan §7.1). The template's `frontend/lib/` and `backend/migrations/` conventions do not apply to this slice; D2 touches neither. No `ai-platform/migrations/` edits — the D1 schema (including `routing_policy`) is frozen by A5 and unchanged.

---

## Phase 1: Tests (written to fail before the code exists)

**Purpose**: One task covering each named test in the spec's `### Test plan` (§3.11.4 row D2 = "Unit"; §13.5 Provider adapter tests / Pipeline tests with fake provider). All 21 cases are CPU-only — the fake and router are pure functions with no I/O — so the default Node-pool config (`vitest.config.ts`, `include: ["test/**/*.test.ts"]`) covers them; no workers-pool registration is needed. T001 creates `test/provider-port.test.ts` and its substrate; T002–T005 append to it. T006 creates `test/router.test.ts` and its substrate; T007–T018 append to it. T006 is `[P]` relative to T001 — different file, no dependency. The modules under test (`../src/provider/*`, `../src/router`) do not exist yet, so both files fail to compile from the first importing task onward — the intended red state.

- [X] T001 [US1] Add `T-D2-01 fake_success` to `ai-platform/test/provider-port.test.ts` (unit): create the inline-fixture substrate — a minimal `CanonicalRequest` fixture (A3 fields from `../src/contracts/canonical`), a `FakeAdapter` constructor call site taking an ordered scripted-outcome queue (Clarification Q2), and imports of `FakeAdapter` / `ProviderPort` from `../src/provider/fake` and `../src/provider/port`. Then the case: configure the fake for `success`, invoke through the port, assert a `CanonicalResult` success (§4.3.8, §13.5). Satisfies FR-005 / SC-001.
- [X] T002 [US1] Add `T-D2-02 fake_retryable_<class>` and `T-D2-03 fake_terminal_<class>` to `ai-platform/test/provider-port.test.ts` (unit): one case per retryable taxonomy class and one case per terminal taxonomy class — enumerate classes from `classify` / A2's `TaxonomyCode` via `isRetrySafe`; for each, script the fake outcome, invoke through the port, and assert a `CanonicalError` whose `taxonomy code` matches and whose `retryability` is `true` (retryable) or `false` (terminal) (§4.3.8). Combined same-file failure-class coverage. Satisfies FR-004, FR-005 / SC-001, SC-002.
- [X] T003 [US1] Add `T-D2-04 fake_truncation` and `T-D2-05 fake_malformed` to `ai-platform/test/provider-port.test.ts` (unit): script `truncation` and `malformed` outcomes; invoke through the port; assert each produces the corresponding normalized truncated / malformed outcome through the port (fixture behaviours — not new taxonomy codes) (§4.3.8, §13.5). Combined same-file fixture-outcome coverage. Satisfies FR-005 / SC-001.
- [X] T004 [US1] Add `T-D2-06 classification_exhaustive_over_taxonomy` to `ai-platform/test/provider-port.test.ts` (unit, contract): import `classifyFailure` (or equivalent) from `../src/provider/classify`; enumerate every `TaxonomyCode` from `../src/errors`; assert each maps to exactly one of `retryable` / `terminal`, with no code missing and no code mapped twice; assert the boolean matches A2's `isRetrySafe(getTaxonomyEntry(code).retryable)` (§4.3.8). Satisfies FR-004 / SC-002.
- [X] T005 [US1] Add `T-D2-18 adapters_own_no_retry_or_fallback` and `T-D2-21 credentials_absent_from_fake_emissions` to `ai-platform/test/provider-port.test.ts` (unit): (a) assert the provider-port / fake export surface has no retry or fallback API — inspect exported keys / types for absence of retry/fallback symbols (Clarification Q4); (b) invoke the fake across success and error outcomes and assert returned canonical records and any fake-emitted diagnostics carry no credential fields — no logger spy (Clarification Q4) (§4.3.8). Combined same-file prohibition coverage. Satisfies FR-003, FR-006 / SC-006.
- [X] T006 [P] [US1] Add `T-D2-07 router_chain_ordered_by_policy` to `ai-platform/test/router.test.ts` (unit): create the router-fixture substrate — a fake/spy `ConfigCache` preloaded with a parsed routing-policy document under `active_routing_policy` (Clarification Q3; A5 `ConfigCache.remember`), capability-requirement fixtures (structured support, context window, language, latency class, degraded-tier signal as request inputs — D2 does not load manifests), and import `selectCandidateChain` (or equivalent) from `../src/router`. Then the case: drive the router with a multi-target rule and assert the candidate chain order matches `rules[].targets[]` order (§4.3.7). Satisfies FR-008, FR-009 / SC-003.
- [X] T007 [US1] Add `T-D2-08 router_filter_structured_support` to `ai-platform/test/router.test.ts` (unit): capability requires structured output; assert targets lacking structured-output support are excluded with `reason_code: feature_unsupported` (§4.3.7). Satisfies FR-008 / SC-003.
- [X] T008 [US1] Add `T-D2-09 router_filter_context_window` to `ai-platform/test/router.test.ts` (unit): capability declares a min context window; assert targets below that window are excluded with `reason_code: context_window_too_small` (§4.3.7). Satisfies FR-008 / SC-003.
- [X] T009 [US1] Add `T-D2-10 router_filter_language` to `ai-platform/test/router.test.ts` (unit): capability declares a language requirement; assert non-matching targets are excluded with `reason_code: language_unsupported` (§4.3.7). Satisfies FR-008 / SC-003.
- [X] T010 [US1] Add `T-D2-11 router_filter_latency_class` to `ai-platform/test/router.test.ts` (unit): capability declares a latency class; assert targets outside that class are excluded (§4.3.7). Satisfies FR-008 / SC-003.
- [X] T011 [US1] Add `T-D2-12 router_installation_override_applied` to `ai-platform/test/router.test.ts` (unit): active policy has an `overrides[]` entry for the installation; assert the override narrows/pins the chain and never widens it beyond the matched rule's targets (§4.3.7). Satisfies FR-008 / SC-003.
- [X] T012 [US1] Add `T-D2-13 router_identical_inputs_identical_chain` to `ai-platform/test/router.test.ts` (unit): run the router twice with identical capability, policy, and request inputs; assert identical candidate chains (§4.3.7). Satisfies FR-012 / SC-003.
- [X] T013 [US1] Add `T-D2-14 router_selection_reason_recorded` to `ai-platform/test/router.test.ts` (unit): assert the routing outcome carries a request-level `routing_decision` with `policy_id`, `policy_version`, `rule_id`, `effective_cost_class`, `cost_class_source`, `routing_tier`, `required_features`, `chain`, `excluded`, and `max_parallel_attempts` per `contracts/routing-decision.md` (§4.3.7). Satisfies FR-010 / SC-003.
- [X] T014 [US1] Add `T-D2-15 router_prior_failure_does_not_change_chain` to `ai-platform/test/router.test.ts` (unit): after a simulated prior provider failure, route a subsequent request with the same capability, policy, and request inputs; assert the candidate chain is unchanged — no provider history consulted (§4.3.7). Satisfies FR-011, FR-012 / SC-004.
- [X] T015 [US1] Add `T-D2-16 router_cost_class_applied` to `ai-platform/test/router.test.ts` (unit): supply differing manifest / entitlement / installation `force_cost_class` inputs; assert effective class is the lowest of the three and `cost_class_source` records which bound it (§4.3.7). Satisfies FR-008 / SC-005.
- [X] T016 [US1] Add `T-D2-17 router_degraded_tier_when_soft_threshold` to `ai-platform/test/router.test.ts` (unit): set the in-memory request `routing_tier = degraded` (soft-threshold signal already present — F4 detects later); assert the router matches `rules[].match.tiers` degraded and selects the degraded-tier chain; D2 does not read quota counters (§4.3.7). Satisfies FR-008 / SC-005.
- [X] T017 [US1] Add `T-D2-19 routing_policy_is_versioned_data` to `ai-platform/test/router.test.ts` (unit): assert the router reads the active policy from the config-cache `active_routing_policy` entry carrying versioned `policy_id` / `policy_version` (and document fields), not from code-path conditionals (§4.3.7, §7.3). Satisfies FR-009 / SC-006.
- [X] T018 [US1] Add `T-D2-20 outgoing_connection_cap_bounds_parallelism` to `ai-platform/test/router.test.ts` (unit): a policy document requesting `max_parallel_attempts` above six is rejected or clamped so the effective value stays in `1`–`6` — the per-request outgoing-connection cap of six (§4.3.8). Satisfies FR-007 / SC-006.

---

## Phase 2: Implementation (plan Files section)

**Purpose**: The four implementation units named in `plan.md` → Files: `classify.ts` (exhaustive taxonomy map), `port.ts` (typed boundary), `fake.ts` (scripted-outcome queue), `router/index.ts` (policy → chain + `routing_decision`). Consumed modules (`contracts/canonical.ts`, `errors.ts`, `config-cache/`) are imported, not modified (delivery plan §2.3). Tests turn green in matching groups per the plan's Sequencing: T-D2-06 with `classify.ts`; T-D2-01..05 / 18 / 21 with `port.ts` + `fake.ts`; T-D2-07..17 / 19 / 20 with `router/index.ts`.

- [X] T019 [US1] Create `ai-platform/src/provider/classify.ts` — exhaustive adapter classification. Export a function that maps every `TaxonomyCode` to `retryable` | `terminal` for adapter purposes, derived from A2's `getTaxonomyEntry` / `isRetrySafe` (codes whose taxonomy `retryable` is `"No"` or `"—"` are terminal; all others retryable), and a helper that sets `CanonicalError["retryability"]` accordingly. No code may be added, removed, or renamed. An unclassified code is a contract violation. **Satisfies**: FR-004; **proved by**: T-D2-06 (and T-D2-02 / T-D2-03 once the fake emits classified errors).
- [X] T020 [US1] Create `ai-platform/src/provider/port.ts` — the typed `ProviderPort` boundary. Export the port type/interface: canonical request in; canonical stream chunks / result / classified error out. Document (in types/exports only) adapter ownership (auth, mapping, stream normalization, structured-output mechanics, timeouts, classification) and non-ownership (no retry, no fallback, no logging policy). No retry or fallback symbols on the export surface. **Satisfies**: FR-001, FR-002, FR-003; **proved by**: T-D2-01..05, T-D2-18. Depends on T019 for classification types used at the error boundary.
- [X] T021 [US1] Create `ai-platform/src/provider/fake.ts` — deterministic fake adapter behind `ProviderPort`. Constructor takes an ordered queue of scripted outcomes (`success` / `retryable:<code>` / `terminal:<code>` / `truncation` / `malformed`); each invoke consumes the next (Clarification Q2). Success returns a `CanonicalResult`; classified failures return `CanonicalError` via `classify.ts`; truncation and malformed normalize through the port without inventing taxonomy codes. Returned records and diagnostics carry no credential fields. **Satisfies**: FR-005, FR-006; **proved by**: T-D2-01..05, T-D2-21. Depends on T019 and T020.
- [X] T022 [US1] Create `ai-platform/src/router/index.ts` — policy-as-data router. Export `selectCandidateChain` (or equivalent) that: reads the active policy document from a `ConfigCache` under `active_routing_policy` (no D1/R2 I/O in this slice's unit path); first-match rule selection; applies installation overrides (narrow only); filters by structured support, context window, language, latency class; takes effective cost class as the lowest of manifest / entitlement cap / installation `force_cost_class` and records `cost_class_source`; matches `routing_tier` (`standard` / `degraded`) when the request already carries the soft-threshold signal; builds ordered `chain` + `excluded` with `reason_code`s; records request-level `routing_decision` per `contracts/routing-decision.md`; bounds `max_parallel_attempts` to `1`–`6`. Pure function of capability, policy, and this request — no provider-health state, no circuit breaker, no per-request DO. **Satisfies**: FR-007..FR-012; **proved by**: T-D2-07..17, T-D2-19, T-D2-20.

---

## Phase 3: Verification

**Purpose**: Delivery plan §3.10 — every prior suite stays green alongside the new one, not just the latest.

- [X] T023 [US1] From `ai-platform/`, run `npx vitest run test/provider-port.test.ts test/router.test.ts` (this slice's named cases, all under the default Node pool — D2 is CPU-only), then run the full prior suite — `npx vitest run` (default Node-pool prior suites including `prompt-registry.test.ts`, `prompt-composer.test.ts` (D1), `manifest.test.ts` (A4), `canonical.test.ts` (A3), `taxonomy.test.ts`, `reference.test.ts`, `error-body.test.ts`, `trace.test.ts`, `log-redaction.test.ts` (A2), `health.test.ts`, `env-deploys.test.ts` (A1), `context-validator.test.ts` (C2)) and `npx vitest run --config vitest.workers.config.ts` (workers-pool prior suites: `control.test.ts` (B2), `identity.test.ts`, `entitlement.test.ts`, `rate-limit.test.ts` (B3), `admission-credit.test.ts`, `quota-do.test.ts` (B4), `capability.test.ts` (C1), `journal.test.ts` (C3); `context.test.ts`, `config-cache.test.ts`, `migrations.test.ts` (A5); `adapter.test.ts` (A6)). Confirm every prior suite stays green. No new test is added here — this is the §3.10 checkpoint gate. **Satisfies**: the §3.10 checkpoint rule (every branch and named boundary this slice covers — fake outcomes, exhaustive classification, router filters/overrides/cost/degraded/determinism/statelessness, cap of six, no retry/fallback API, no credentials). Proved by itself.

---

## Phase 4: Documentation

**Purpose**: Always present. The one documentation artifact the plan names that does not yet exist on disk (`quickstart.md`); written only after the suite is green. Contracts were already frozen during the plan phase.

- [X] T024 [US1] Create `specs/029-provider-port-routing/quickstart.md` from `.specify/templates/ai-platform-quickstart-template.md`, scoped to this slice only. **§1 Architecture context** — delivery plan §3.5 row D2; `17-ai-platform.md` §4.3.8, §4.3.7, §7.3, §13.5; what the spec delivered; what the plan scoped. **§2 What was implemented** — `src/provider/port.ts`, `classify.ts`, `fake.ts`; `src/router/index.ts`; frozen contracts. **§3 Files to review** — only this slice's source, test, and contract files (`ai-platform/src/provider/`, `ai-platform/src/router/`, `ai-platform/test/provider-port.test.ts`, `ai-platform/test/router.test.ts`, `specs/029-provider-port-routing/contracts/`). **§4 Prerequisites** — `cd ai-platform && npm install` (first time); CPU-only tests, no miniflare bindings required for this slice. **§5 Run the automated suite** — `cd ai-platform && npx vitest run test/provider-port.test.ts test/router.test.ts`; slice-only (no full-suite `npm test`). **§6 Inspect the changes** — read the frozen contracts; grep `src/router` for `routing_decision` / `max_parallel_attempts`; run a focused test file. **No §7** — CI is the only verification path. **Slice-only scope explicit**: no prior-slice files in the review table, no combined test counts, no prior-slice regression commands. Not traced to an FR (template-mandated review surface).

---

## Dependencies & Execution Order

### Phase Dependencies

- **Tests (T001–T018)** — none beyond already-frozen contracts and Consumes Binding modules; written to fail before the code exists. T006 (creates `router.test.ts`) is `[P]` relative to T001 (creates `provider-port.test.ts`) — different file, no dependency. Within each file group, tasks are sequential (each appends to the substrate the first task created).
- **Implementation (T019–T022)** — T019 (`classify.ts`) first; T020 (`port.ts`) depends on T019; T021 (`fake.ts`) depends on T019–T020; T022 (`router/index.ts`) is independent of the provider modules and can proceed once router tests exist. Tests turn green in matching groups per the plan's Sequencing.
- **Verification (T023)** — depends on T001–T022; runs the whole suite (this slice + every prior slice) per §3.10.
- **Documentation (T024)** — depends on T023 (the quickstart records a green suite).

### Within the Slice

- Tests written to fail before implementation; implementation makes them pass; verification confirms the whole suite including prior slices stays green.
- Classification (T019) before port (T020) before fake (T021).
- Router (T022) after its test file exists (T006+); no dependency on provider modules.

### Parallel Opportunities

- Phase 1: T001–T005 all touch `provider-port.test.ts` (sequential); T006–T018 all touch `router.test.ts` (sequential). T006 is `[P]` relative to T001 — the two file groups can proceed in parallel.
- Phase 2: T022 (`router/index.ts`) is `[P]`-eligible relative to T019–T021 once T006 exists — different files, no import dependency on provider modules. T019→T020→T021 remain sequential.
- Phase 4 (T024) is a single task — no `[P]`.

---

## Notes

- [P] tasks = different files, no dependencies. T006 (router test file) is `[P]` vs T001 (provider-port test file); T022 may proceed in parallel with T019–T021.
- Every named test T1–T21 from `spec.md` is covered; three same-file pairs are combined into T002, T003, and T005 so the task list is 24 (under the 25-task cap) without dropping cases.
- Every task traces to an `FR-###` from `spec.md` (tests also state the `SC-###` they satisfy) — no task adds a requirement the spec does not name.
- No Polish phase and no Foundational phase — prerequisites are the already-merged slices in the plan's Consumes Binding (A2, A3, A5; A4/C1 supply fixture-shaped capability inputs only).
- Consumed modules are imported, not modified (delivery plan §2.3 — extend, never rewrite).
- Tests land before or alongside their implementation, never after (delivery plan §2.2).
- Preserve the I/O budget: no DO, D1, or R2 I/O from this slice; router and fake are CPU-only (§4.3.7, §4.4, §7.5, §13.6).
