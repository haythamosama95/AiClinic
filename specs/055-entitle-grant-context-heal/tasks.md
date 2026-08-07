# Tasks: Entitle-and-grant operator path and live `context_required` self-heal (I4)

**Input**: Design documents from `specs/055-entitle-grant-context-heal/`

**Prerequisites**: `plan.md` (required), `spec.md` (required for the user story). `research.md` is never produced on this platform (the research is `docs/architecture/ai-platform/01-ai-platform.md`). `data-model.md` is not produced — spec Key Entities is "Not applicable" (writes into existing §7.3 / A5 shapes; no new entities). `contracts/` is not produced — Band I freezes no new contract (Delivery Plan §3.10; §2.3; Freezes: None). `AVAILABLE_DOCS` is empty. `quickstart.md` is written in Phase 5 (Documentation).

**Tests**: Tests are mandatory on this platform (delivery plan §3.10). Every named test in the spec's `### Test plan` (T1–T8) is covered by its own task, written to fail before the entitle handler and live heal hosting exist. Layers are **Workers integration** (T1–T4) and **Flutter widget + integration** (T5–T8) (delivery plan §3.12.9 row I4; §13.5). Workers cases live in `ai-platform/test/entitle-grant.test.ts` (Miniflare D1 + operator auth / `SELF.fetch` — same pattern as B2 `control.test.ts`). Flutter cases live in `frontend/test/widget/ai/live_context_required_self_heal_test.dart` (spies for heal / refresh / SDK — live Worker not required for the Flutter suite). Spy case T7 is its own task. Permanent suite joins CI (delivery plan §3.11).

**Organization**: One user story (US1, P1) — I4 is one slice, one story (delivery plan §2.6, overrides). No cross-story parallelism section. Setup is present — plan Files names `vitest.workers.config.ts` so the entitle workers file joins the workers pool. No Foundational or Polish phase — prerequisites are already-merged Needs (B2, I3, J2) in the plan's Consumes Binding.

**Task count**: 18 (≤25).

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: US1 (this slice has a single user story)
- Include exact file paths in descriptions

## Path Conventions

- **Flutter desktop app**: `frontend/lib/`, `frontend/test/`
- **Supabase backend**: `backend/migrations/`, `backend/functions/`, `backend/tests/` — *not touched by I4* (no entitlement writes into Supabase; self-heal key resolution stays under caller RLS via E3)
- **AI gateway Worker**: `ai-platform/src/`, `ai-platform/migrations/`, `ai-platform/test/`
- **Spec Kit artifacts**: `specs/055-entitle-grant-context-heal/`
- Entitle lands under `ai-platform/src/control/` beside B2 lifecycle; production `ManifestRefreshPort` under `frontend/lib/core/ai/`; live heal hosting under `frontend/lib/features/ai/` (surface / host / hub). Consumed B2 lifecycle/auth, I3 mint/submit/discovery, and J2 heal modules stay unmodified aside from the listed composition hooks (delivery plan §2.3).

---

## Phase 1: Setup (Test harness)

**Purpose**: Plan Files names `ai-platform/vitest.workers.config.ts` so this slice's entitle integration file joins the workers pool before or alongside the Tests phase.

- [X] T001 [US1] Modify `ai-platform/vitest.workers.config.ts` — add `"test/entitle-grant.test.ts"` to `include` so T1–T4 join the workers pool permanently (delivery plan §3.11; plan → Files). No FR — harness; required by T1–T4. Prepares the Phase 2 workers substrate.

---

## Phase 2: Tests (written to fail before the code exists)

**Purpose**: One task per named test in the spec's `### Test plan` (§3.12.9 row I4). T1–T4 share `ai-platform/test/entitle-grant.test.ts`; T5–T8 share `frontend/test/widget/ai/live_context_required_self_heal_test.dart`. Until `handleEntitle` / dispatch wiring and live surface heal hosting exist, imports or assertions fail — the intended red state. Order follows plan Sequencing themes (entitle happy path → budgets → pending boundary → non-operator; then live heal happy path → second reject → no-third-attempt spy → conversational exclusion). Within each file, append sequentially; the Flutter suite file is `[P]` relative to the workers suite file.

- [X] T002 [US1] Create `ai-platform/test/entitle-grant.test.ts` with the Workers integration substrate (Miniflare D1 + operator auth / `SELF.fetch` — same pattern as B2 `control.test.ts`; when extending harnesses that seed entitlement for guard paths, keep I1's kill_switch migration `beforeAll` where that suite already applies it) and named test `entitle_activate_writes_entitlement_grant_and_audit` (T1): operator activate/grant writes entitlement and `capability_grant` rows and a `control_audit` entry with operator identity (§3.12.9 I4 *Entitle*; §4.5; §7.3). Fails red until `handleEntitle` and dispatch wiring exist. **Satisfies**: FR-002, FR-003, FR-004 / SC-001. **Proves**: T1.
- [X] T003 [US1] Add named test `entitle_sets_budget_fields_admission_reads` (T2) to `ai-platform/test/entitle-grant.test.ts`: activate writes the budget fields admission already reads (period bounds, request quota, token/cost budget, soft threshold, allowed capability set) and moves status to `active` (A5 columns / `EntitlementSnapshot`; see plan Technical Context note on `max_cost_class` — do not add that column) (§7.3 `entitlement`; Done when; §4.5). Fails red until entitle writes those fields. **Satisfies**: FR-002 / SC-002. **Proves**: T2.
- [X] T004 [US1] Add named test `pending_enroll_fails_entitlement_until_activated` (T3) to `ai-platform/test/entitle-grant.test.ts`: pending enroll still fails entitlement / is not admitted until activated (via `evaluateEntitlement` or equivalent stage-3 check against D1 state) (§3.12.9 I4 *Entitle*; §4.5; §7.3 Entitlement status). Fails red until pending boundary is asserted against pre-entitle D1 state. **Satisfies**: FR-005 / SC-003. **Proves**: T3.
- [X] T005 [US1] Add named test `entitle_non_operator_rejected` (T4) to `ai-platform/test/entitle-grant.test.ts`: non-operator credentials rejected; no entitlement or grant row mutation (§3.12.9 I4 *Entitle*; §4.5; existing B2 control rejection shape). Fails red until route is operator-gated. **Satisfies**: FR-001, FR-006 / SC-004. **Proves**: T4.
- [X] T006 [P] [US1] Create `frontend/test/widget/ai/live_context_required_self_heal_test.dart` with the Flutter widget/integration substrate (spies for heal / refresh / SDK on the I3 live surface composition; reuse I3/E4 harness patterns where helpful) and named test `live_self_heal_refreshes_resolves_resubmits_once_same_key` (T5): live submit path refreshes on first `context_required`, resolves named keys, resubmits once with the same idempotency key (§3.12.9 I4 *Self-heal*; §8.4; §5.2; Consumes J2). Fails red until `FirstAiFeatureSurface._invoke` hosts `ContextRequiredSelfHeal` with a production `ManifestRefreshPort`. **Satisfies**: FR-008 / SC-005. **Proves**: T5.
- [X] T007 [US1] Add named test `live_self_heal_second_context_required_surfaces_reference` (T6) to `frontend/test/widget/ai/live_context_required_self_heal_test.dart`: second `context_required` stops automatic recovery and surfaces the request reference (§3.12.9 I4 *Self-heal*; §8.4). Fails red until live heal hosting preserves J2's second-reject branch. **Satisfies**: FR-009 / SC-006. **Proves**: T6.
- [X] T008 [US1] Add named spy test `live_self_heal_no_automatic_third_attempt` (T7) to `frontend/test/widget/ai/live_context_required_self_heal_test.dart`: spy — submit / refresh / resolve call counts prove no automatic third attempt after the second `context_required` (§8.4; Consumes J2; §3.11 coverage of the one-resubmission bound). Fails red until live path bound is observable via spies. **Satisfies**: FR-009 / SC-006. **Proves**: T7.
- [X] T009 [US1] Add named test `live_self_heal_conversational_never_takes_path` (T8) to `frontend/test/widget/ai/live_context_required_self_heal_test.dart`: conversational capabilities never take the §8.4 self-healing path on the live submit path (§3.12.9 I4 *Self-heal*; §8.4; §5.2). Fails red until live host respects `interaction_mode: conversational` exclusion. **Satisfies**: FR-010 / SC-006. **Proves**: T8.

---

## Phase 3: Implementation (plan Files section)

**Purpose**: Implementation units from `plan.md` → Files not already produced as Setup (T001), Tests (Phase 2), or Documentation: entitle handler + types + dispatch; production `ManifestRefreshPort`; surface/host/hub composition. Order follows plan Sequencing (entitle handler → control dispatch → ManifestRefreshPort → live host wiring). Consumed B2 lifecycle/auth, I3 mint/submit/discovery, and J2 heal sources are bound only — not rewritten (delivery plan §2.3). No new D1 migration; no Band G catalogue/billing/usage-summary UI (FR-007).

- [ ] T010 [P] [US1] Modify `ai-platform/src/control/types.ts` — add `EntitlePayload` (and related) types for the combined mutation: period bounds, quotas/budgets, soft threshold, allowed capabilities, grant list (FR-002, FR-003; Clarification Q1). Soft threshold stays in `[0, 1]` via existing `isSoftThresholdFraction` / `coerceSoftThreshold` contract. Does not alter B2 lifecycle payload types. **Satisfies**: FR-002, FR-003. **Proved by**: T1–T2 (and substrate for T3–T4 request bodies).
- [ ] T011 [US1] Create `ai-platform/src/control/entitle.ts` — `handleEntitle` for combined operator entitle: require operator identity; activate entitlement budget fields admission already reads (`period_start`, `period_end`, `request_quota`, `token_budget`, `cost_budget`, `allowed_capabilities`, `soft_threshold`, `status` → `active`); write `capability_grant` row(s) at `installation` or `plan` scope; journal `control_audit` with operator identity in one mutation (Clarification Q1; use B2 `runControlBatch` / audit helpers — Consumes, do not rewrite). Reject non-operator with existing B2 control rejection shape; no entitlement/grant mutation. Does not add `max_cost_class` column or change B3/B4. Depends on T010. **Satisfies**: FR-001–FR-006. **Proved by**: T1–T4.
- [ ] T012 [US1] Modify `ai-platform/src/control/index.ts` — extend `isControlRoute` / `dispatchControlRequest` for `POST /control/installations/{id}/entitle` without altering lifecycle, capability-lifecycle, or other control routes (Consumes B2 barrel). Depends on T011. **Satisfies**: FR-001, FR-006. **Proved by**: T1–T4.
- [ ] T013 [P] [US1] Create `frontend/lib/core/ai/discovery_manifest_refresh_port.dart` — production `ManifestRefreshPort` using I3 `DiscoveryClient` (refresh + `interactionModeFor` from cached manifests). Does not reimplement discovery filtering or J2 heal semantics. **Satisfies**: FR-008. **Proved by**: T5–T8 (refresh port substrate on the live path).
- [ ] T014 [US1] Modify `frontend/lib/features/ai/host/ai_feature_host_page.dart` — pass `ManifestRefreshPort` through `AiFeatureHostDependencies` into the surface (minimal composition hook). Does not reimplement mint/submit/degraded UX (Consumes I3). Depends on T013 for the port type under test; may land with T015. **Satisfies**: FR-008. **Proved by**: T5–T8.
- [ ] T015 [US1] Modify `frontend/lib/features/ai/surface/first_ai_feature_surface.dart` — `_invoke` calls `ContextRequiredSelfHeal.invoke` instead of raw `sdk.invoke`; inject refresh port + existing resolver (Clarification Q2). Preserves J2 one-resubmission bound, second-`context_required` reference surfacing, and conversational exclusion (FR-009–FR-010). Does not redefine J2 heal helper or I3 mint/submit adapters. Depends on T013–T014. **Satisfies**: FR-008–FR-010. **Proved by**: T5–T8.
- [ ] T016 [US1] Modify `frontend/lib/features/ai/presentation/pages/ai_page.dart` — construct production `ManifestRefreshPort` beside existing discovery composition and wire it through host deps into the live surface. Does not replace I3 production mint/submit composition. Depends on T013–T015. **Satisfies**: FR-008. **Proved by**: T5–T8.

---

## Phase 4: Verification

**Purpose**: Delivery plan §3.10 — every prior suite stays green alongside the new one, not just the latest.

- [ ] T017 [US1] From `ai-platform/`, run this slice's Workers suite — `npx vitest run --config vitest.workers.config.ts test/entitle-grant.test.ts` (named cases T1–T4). From `frontend/`, run this slice's Flutter suite — `flutter test test/widget/ai/live_context_required_self_heal_test.dart` (named cases T5–T8). Confirm R-12 / E1: new composition paths under `frontend/lib/core/ai/discovery_manifest_refresh_port.dart` and `frontend/lib/features/ai/` still pass `dart run tool/architecture_guard/architecture_guard.dart` against clean client scan roots (Consumes E1; do not alter the guard). Keep prior Flutter AI suites green, including I3/J2 hosts: `flutter test test/widget/ai/live_client_invoke_test.dart test/widget/ai/first_ai_feature_surface_test.dart test/widget/ai/ai_degraded_mode_test.dart test/unit/core/ai/context_required_self_heal_test.dart test/unit/core/ai/ai_client_sdk_test.dart test/unit/core/ai/context_resolver_test.dart test/unit/core/ai/context_contract_test.dart`. From `ai-platform/`, run every prior slice's suite: `npx vitest run` (default Node-pool prior suites) and `npx vitest run --config vitest.workers.config.ts` (workers-pool prior suites, including B2 control and this slice's file). Confirm I4's eight named cases are green and every prior suite stays green. No new test is added here — this is the §3.10 checkpoint gate. Confirm inherited prohibitions: no plan catalogue / billing period close / usage-summary UI (FR-007; Band G); no prompt/provider/model identifiers in the Flutter client (R-12); no per-request server-side healing session; no second Quota DO / R2; no §9.14 mechanism; Consumes modules (B2 lifecycle, I3 mint/submit/discovery, J2 heal) not rewritten (delivery plan §6.4 / §2.3). Keep I1 kill_switch migration `beforeAll` intact where that suite already applies it. **Satisfies**: the §3.10 checkpoint rule (T1–T8 + prior suites). Proved by itself.

---

## Phase 5: Documentation

**Purpose**: Always present. The one documentation artifact the plan names that does not yet exist on disk (`quickstart.md`); written only after the suite is green. No other documentation artifact is named for a separate `[P]` task (no `ai-platform/README.md` — not the bootstrap slice; Freezes None — no new contract file).

- [ ] T018 [US1] Create `specs/055-entitle-grant-context-heal/quickstart.md` from `.specify/templates/ai-platform-quickstart-template.md`, scoped to this slice only. **§1 Architecture context** — delivery plan §3.10 row I4; `01-ai-platform.md` §4.5 / §7.3 / §8.4 / §5.2; what the spec delivered; what the plan scoped; CP6. **§2 What was implemented** — combined `POST /control/installations/{id}/entitle` mutation; production `ManifestRefreshPort`; `FirstAiFeatureSurface._invoke` hosting `ContextRequiredSelfHeal`. **§3 Files to review** — only this slice's `ai-platform/src/control/` entitle touch points, `ai-platform/test/entitle-grant.test.ts`, this slice's Flutter production refresh port + surface/host/hub composition, and `frontend/test/widget/ai/live_context_required_self_heal_test.dart` (no prior-slice files). **§4 Prerequisites** — Node/workers pool for entitle tests; Flutter SDK for widget tests; `OPERATOR_*` bindings when exercising `SELF.fetch` control e2e (same as B2). **§5 Run the automated suite** — slice-only `npx vitest run --config vitest.workers.config.ts test/entitle-grant.test.ts` and `flutter test test/widget/ai/live_context_required_self_heal_test.dart` (T1–T8); no full-suite `npm test`, no combined prior-slice counts. **§6 Inspect the changes** — open entitle handler + dispatch route; open surface `_invoke` heal wiring and production `ManifestRefreshPort`; confirm Consumes modules not rewritten. **§7 Manual validation** — optional: operator `curl` entitle against local Worker then enrolled desktop `/ai` host for a stale-manifest self-heal (CP6 review); omit when the automated suite alone proves Done when for CI. **Slice-only scope explicit**: no prior-slice files in the review table, no combined test counts, no prior-slice regression commands. Not traced to an FR (template-mandated review surface).

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (T001)** — none; can start immediately. Workers-pool include for `entitle-grant.test.ts`.
- **Tests (T002–T009)** — T001 before or alongside T002 (workers file must be include-listed for CI). T002 creates `entitle-grant.test.ts`; T003–T005 append sequentially. T006 `[P]` creates the Flutter suite file (different file from workers); T007–T009 append after T006. Written to fail before entitle handler / live heal hosting exist.
- **Implementation (T010–T016)** — after tests exist (red). Worker chain: T010 → T011 → T012 turns T1–T4 green. Flutter chain: T013 `[P]` relative to the worker chain → T014 → T015 → T016 turns T5–T8 green.
- **Verification (T017)** — depends on T001–T016; runs this slice's workers + Flutter suites plus E1 guard check plus every prior suite per §3.10.
- **Documentation (T018)** — depends on T017 (the quickstart records a green suite).

### Within the Slice

- Tests written to fail before implementation; implementation makes them pass; verification confirms the whole suite including prior slices stays green.
- Plan Sequencing maps to Implementation order: EntitlePayload types (T010) → `handleEntitle` (T011) → control dispatch (T012) → production `ManifestRefreshPort` (T013) → host deps (T014) → surface `_invoke` heal (T015) → hub constructs port (T016); Documentation last.
- Test-file and harness Files-section rows are produced by Phase 1–2. Remaining Files units are T010–T016 plus T018 (`quickstart.md`). Consumed B2/I3/J2 modules remain unchanged aside from listed composition hooks.

### Parallel Opportunities

- Phase 2: T006 is `[P]` relative to T002–T005 (different test file). Within each suite file, append sequentially (no `[P]`). Spy case T7 remains a separate task from T6's outcome assertion.
- Phase 3: T010 is `[P]` relative to T013 (Worker types vs Flutter refresh port — different files, no mutual dependency). T013 is `[P]` relative to T010–T012 (Flutter port vs Worker entitle chain). T011 depends on T010; T012 on T011; T014–T016 follow T013 in host → surface → hub order.
- Phase 5 (T018) is a single task — no `[P]`.

---

## Notes

- [P] tasks = different files, no dependencies. Marked: T006, T010, T013.
- Every named test T1–T8 from `spec.md` is covered by its own task; no test is folded into another. Spy case T7 is a separate task (call-count / absence asserts).
- Every task traces to an `FR-###` from `spec.md` (tests also state the `SC-###` they satisfy) — or to the §3.10 checkpoint / the template-mandated quickstart / harness Setup. No task adds a requirement the spec does not name. Clarifications Q1–Q2 guide how (combined `/entitle` mutation; heal inside `FirstAiFeatureSurface._invoke`), not what.
- No Polish phase and no Foundational phase — Needs are B2, I3, J2 (Consumes Binding).
- Consumed modules are imported/bound, not rewritten (delivery plan §2.3 — extend, never rewrite). I4 does not absorb Band G (FR-007).
- Tests land before or alongside their implementation, never after (delivery plan §2.2).
- Preserve R-12 / §6.4: no prompt text, provider name, or model identifier in the Flutter client; no per-request server-side healing session; no second Quota DO or R2 object; no §9.14 mechanism; AI never blocks clinical workflows (A11).
