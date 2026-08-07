# Tasks: Live client invoke on the first AI feature surface (I3)

**Input**: Design documents from `specs/054-live-client-invoke/`

**Prerequisites**: `plan.md` (required), `spec.md` (required for the user story). `research.md` is never produced on this platform (the research is `docs/architecture/ai-platform/01-ai-platform.md`). `data-model.md` is not produced — spec Key Entities is "Not applicable" (no D1 entities or new contract types). `contracts/` is not produced — Band I freezes no new contract (Delivery Plan §3.10; §2.3; Freezes: None). `AVAILABLE_DOCS` is empty. `quickstart.md` is written in Phase 4 (Documentation).

**Tests**: Tests are mandatory on this platform (delivery plan §3.10). Every named test in the spec's `### Test plan` (T1–T11) is covered by its own task, written to fail before the production mint/submit adapters, discovery client, and hub composition exist. Layer is **Flutter widget + integration** (delivery plan §3.12.9 row I3; §13.5 client / widget coverage; Architecture guard for T11). All cases live in `frontend/test/widget/ai/live_client_invoke_test.dart` and run via `flutter test` against spies/fakes for mint, submit, discovery, network, and ports — live Worker inference not required for the suite (spec Assumptions; DP-3). Permanent suite joins CI (delivery plan §3.11).

**Organization**: One user story (US1, P1) — I3 is one slice, one story (delivery plan §2.6, overrides). No cross-story parallelism section. No Setup phase — plan Files names no harness/config that must exist first; the widget-suite substrate lands with the first Tests task. No Foundational or Polish phase — prerequisites are already-merged Needs (E2, E3, E4, I1, I2) in the plan's Consumes Binding.

**Task count**: 17 (≤25).

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: US1 (this slice has a single user story)
- Include exact file paths in descriptions

## Path Conventions

- **Flutter desktop app**: `frontend/lib/`, `frontend/test/`
- **Supabase backend**: `backend/migrations/`, `backend/functions/`, `backend/tests/` — *not touched by I3* (Consumes Band B `public.issue_ai_token` via production mint adapter only)
- **AI gateway Worker**: `ai-platform/src/`, `ai-platform/migrations/`, `ai-platform/test/` — *not touched by I3* (Consumes I1 submit + I2 discovery as HTTPS clients only)
- **Spec Kit artifacts**: `specs/054-live-client-invoke/`
- Production adapters and the discovery client live under `frontend/lib/core/ai/` beside E2/E3; hub composition is `frontend/lib/features/ai/presentation/pages/ai_page.dart`; widget suite under `frontend/test/widget/ai/`. Consumed E2/E3/E4 modules and the Worker tree remain unmodified (delivery plan §2.3).

---

## Phase 1: Tests (written to fail before the code exists)

**Purpose**: One task per named test in the spec's `### Test plan` (§3.12.9 row I3). All cases share `frontend/test/widget/ai/live_client_invoke_test.dart` (one file — same surface under test; plan Test Layout). Reuse E4 harness patterns (`ai_surface_test_harness.dart` / fakes) where they do not leave test fakes as hub defaults under test for T8. Spy cases (T6, T8) are separate tasks. Until production adapters / hub composition exist, imports or assertions fail — the intended red state. Order follows plan Sequencing themes (live host → provisional/commit → failure reference → terminal payload → degraded → production-port spy → idempotency → discovery auth → R-12 guard).

- [X] T001 [US1] Create `frontend/test/widget/ai/live_client_invoke_test.dart` with the Flutter widget/integration substrate (spies/fakes for mint, submit, discovery, network, ports; reuse E4 harness patterns without wiring test fakes as hub defaults under T8) and named test `live_host_mints_aat_resolves_context_submits_https` (T1): enrolled + reachable host mints AAT, resolves required keys through E3, submits over HTTPS with a stable idempotency key (§3.12.9 I3; §4.1; §5.5). Fails red until production mint/submit adapters and hub composition exist. **Satisfies**: FR-001, FR-002, FR-003 / SC-001. **Proves**: T1.
- [X] T002 [US1] Add named test `live_host_consumes_sse_to_terminal_renders_provisional` (T2) to `frontend/test/widget/ai/live_client_invoke_test.dart`: SSE consumed to a terminal event; provisional draft rendered while in flight (§3.12.9 I3; §5.5; §6.4). Fails red until live submit + surface composition render provisional on the live path. **Satisfies**: FR-004, FR-005 / SC-001. **Proves**: T2.
- [X] T003 [US1] Add named test `live_host_no_commit_control_before_completed` (T3) to `frontend/test/widget/ai/live_client_invoke_test.dart`: no commit/save/accept affordance enabled before terminal `completed` (§3.12.9 I3; §6.4). Fails red until live host preserves E4 provisional rules on the composed path. **Satisfies**: FR-005 / SC-002. **Proves**: T3.
- [X] T004 [US1] Add named test `live_host_failure_displays_request_reference` (T4) to `frontend/test/widget/ai/live_client_invoke_test.dart`: failure presentation displays the request reference (§3.12.9 I3; §5.4). Fails red until live failure path surfaces the reference. **Satisfies**: FR-007, FR-011 / SC-003. **Proves**: T4.
- [X] T005 [US1] Add named test `live_host_uses_terminal_payload_not_chunk_assembly` (T5) to `frontend/test/widget/ai/live_client_invoke_test.dart`: final answer equals validated terminal payload, not client-assembled deltas (§6.4 invariant 1; Delivery Plan §6.4). Fails red until live host treats terminal payload as authoritative. **Satisfies**: FR-006 / SC-002. **Proves**: T5.
- [X] T006 [US1] Add named spy test `degraded_non_enrolled_hides_affordances_no_worker_probe` (T6) to `frontend/test/widget/ai/live_client_invoke_test.dart`: non-enrolled shows no AI affordances; spy proves zero Worker / platform network probes (§3.12.9 I3; A11; §4.2 via E4). Fails red until hub composition preserves E4 non-enrolled gate with production ports present. **Satisfies**: FR-008 / SC-004. **Proves**: T6.
- [X] T007 [US1] Add named test `degraded_unreachable_renders_normal_state_banner` (T7) to `frontend/test/widget/ai/live_client_invoke_test.dart`: unreachable platform → normal-state banner, not an error dialog; clinical non-AI workflows remain usable (A11; §3.12.9 I3). Fails red until live hub preserves unreachable degraded presentation. **Satisfies**: FR-009 / SC-004. **Proves**: T7.
- [X] T008 [US1] Add named spy test `spy_production_mint_and_submit_ports_composed_on_hub` (T8) to `frontend/test/widget/ai/live_client_invoke_test.dart`: hub default composition (outside harness overrides) wires production AAT mint and HTTPS submit ports — not unconfigured stubs or test fakes (§3.12.9 I3 *Spy*; §4.1). Fails red until `ai_page.dart` replaces `_UnconfiguredAatMintPort` / `_UnconfiguredHttpsSubmitPort` as defaults. **Satisfies**: FR-010 / SC-005. **Proves**: T8.
- [X] T009 [US1] Add named test `live_idempotency_key_stable_for_single_user_action` (T9) to `frontend/test/widget/ai/live_client_invoke_test.dart`: the idempotency key submitted for one user action remains stable across transport retries of that action (Consumes E2; §5.5; §4.1). Fails red until production submit path preserves E2 stable-key behaviour on the live host. **Satisfies**: FR-003 / SC-001. **Proves**: T9.
- [X] T010 [US1] Add named test `discovery_auth_failure_taxonomy_no_manifest_body` (T10) to `frontend/test/widget/ai/live_client_invoke_test.dart`: discovery auth failure → taxonomy error, no `{ manifests: … }` body; suspended install may yield `installation_suspended` and hide AI features via composition (`discovery_auth_failure_installation_suspended_hides_ai` + wire unit) (Consumes I2 discovery-http contract; §5.4; §5.5). Fails red until discovery client maps auth failure per I2 wire and hub hides on `installation_suspended`. **Satisfies**: FR-012 / SC-006. **Proves**: T10.
- [X] T011 [US1] Add named test `live_host_contains_no_prompt_provider_or_model_identifiers` (T11) to `frontend/test/widget/ai/live_client_invoke_test.dart` (invokes existing E1 architecture guard on this slice's composition paths under `frontend/lib/core/ai/` production adapters / discovery client and hub composition under `frontend/lib/features/ai/`): live-host composition sources pass the E1 guard (R-12; Delivery Plan §6.4; §4.1). Does not weaken or bypass `frontend/tool/architecture_guard/` (Consumes E1). Fails red until composition sources exist and are clean. **Satisfies**: FR-013 / SC-007. **Proves**: T11.

---

## Phase 2: Implementation (plan Files section)

**Purpose**: Implementation units from `plan.md` → Files not already produced as the widget suite (Phase 1) or Documentation: production `AatMintPort`, production `HttpsSubmitPort`, discovery client, hub composition in `ai_page.dart`. `live_client_invoke_test.dart` is produced by Phase 1; `quickstart.md` in Phase 4. Order follows plan Sequencing (mint → HTTPS submit → discovery → hub). Consumed modules (E2 SDK/ports, E3 Resolver, E4 surface/host/degraded/availability, I1 Worker, I2 discovery wire) are bound as clients only — not modified (delivery plan §2.3). No `ai-platform/` file is touched. Optional touch to `ai_feature_host_page.dart` is out of the default plan — prefer composer in `ai_page.dart`.

- [X] T012 [P] [US1] Create `frontend/lib/core/ai/supabase_aat_mint_port.dart` — production `AatMintPort` calling clinic `public.issue_ai_token` (Band B issuer path consumed by E2). Does not reinterpret E2 mint/cache/remint rules. **Satisfies**: FR-001, FR-010. **Proved by**: T1, T8 (and substrate for live invoke cases that mint).
- [X] T013 [P] [US1] Create `frontend/lib/core/ai/https_submit_port.dart` — production `HttpsSubmitPort`: HTTPS `POST /v1/requests` with A6 headers (`Authorization` Bearer AAT, `x-idempotency-key`, `x-trace-id`, `x-capability-version`), open SSE `SseConnection`, map pre-stream taxonomy HTTP to `PlatformHttpException`. Client of I1 live path only — does not rewrite Worker orchestration. **Satisfies**: FR-001, FR-003, FR-004, FR-010. **Proved by**: T1–T5, T8–T9.
- [X] T014 [P] [US1] Create `frontend/lib/core/ai/discovery_client.dart` — `GET /v1/capabilities` client per I2 `discovery-http.md` (Bearer AAT, etag/`If-None-Match`); extract required context keys for the first capability; auth failure → taxonomy error, no manifests body (incl. `installation_suspended`). Does not reimplement discovery filtering or etag computation. **Satisfies**: FR-002, FR-012. **Proved by**: T1 (key supply path), T10.
- [X] T015 [US1] Modify `frontend/lib/features/ai/presentation/pages/ai_page.dart` — compose production mint/submit into `_LiveVisitSummaryHost` `AiClientSdk`; supply discovery-derived (or default) required keys into `AiFeatureHostDependencies.requiredContextKeys`; enable live invoke (`autoInvoke: true` when enrolled/reachable composition applies); remove unconfigured stubs as hub defaults. First capability remains `clinic.visit_summary` / `prose` / `advisory_display` (FR-014; Open Decision 1). Preserves E4 non-enrolled (no probe) and unreachable banner behaviours (FR-008, FR-009). Depends on T012–T014. **Satisfies**: FR-001, FR-002, FR-008, FR-009, FR-010, FR-014. **Proved by**: T1–T11 (hub is the Done-when / T8 spy target; degraded and R-12 cases assert composed host behaviour).

---

## Phase 3: Verification

**Purpose**: Delivery plan §3.10 — every prior suite stays green alongside the new one, not just the latest.

- [X] T016 [US1] From `frontend/`, run this slice's Flutter suite — `flutter test test/widget/ai/live_client_invoke_test.dart` (named cases T1–T11). Confirm FR-013 / E1: composition paths under this slice still pass `dart run tool/architecture_guard/architecture_guard.dart` against clean client scan roots (Consumes E1; do not alter the guard). Keep prior Band E Flutter suites green: `flutter test test/widget/ai/first_ai_feature_surface_test.dart test/widget/ai/ai_degraded_mode_test.dart test/unit/core/ai/ai_client_sdk_test.dart test/unit/core/ai/context_resolver_test.dart test/unit/core/ai/context_contract_test.dart`. From `ai-platform/`, run every prior slice's suite: `npx vitest run` (default Node-pool prior suites) and `npx vitest run --config vitest.workers.config.ts` (workers-pool prior suites, including I1 and I2). Confirm I3's eleven named cases are green and every prior suite stays green. No new test is added here — this is the §3.10 checkpoint gate. Confirm inherited prohibitions: no prompt/provider/model identifiers in the client (R-12); no client chunk assembly; no §9.14 mechanism; no Worker/D1/DO/R2 changes from this slice (delivery plan §6.4). **Satisfies**: the §3.10 checkpoint rule (T1–T11 + prior suites). Proved by itself.

---

## Phase 4: Documentation

**Purpose**: Always present. The one documentation artifact the plan names that does not yet exist on disk (`quickstart.md`); written only after the suite is green. No other documentation artifact is named for a separate `[P]` task (no `ai-platform/README.md` — not the bootstrap slice; Freezes None — no new contract file).

- [X] T017 [US1] Create `specs/054-live-client-invoke/quickstart.md` from `.specify/templates/ai-platform-quickstart-template.md`, scoped to this slice only. **§1 Architecture context** — delivery plan §3.10 row I3; `01-ai-platform.md` §4.1 / §5.5 / §5.4 / §6.4 / A11; what the spec delivered; what the plan scoped. **§2 What was implemented** — production AAT mint + HTTPS submit adapters; discovery client binding to I2; hub composition replacing unconfigured stubs; live invoke on the first surface. **§3 Files to review** — only this slice's `frontend/lib/core/ai/` production adapters / discovery client, hub composition under `frontend/lib/features/ai/presentation/pages/ai_page.dart`, and `frontend/test/widget/ai/live_client_invoke_test.dart` (no prior-slice files). **§4 Prerequisites** — omit or keep minimal (`flutter` / Dart SDK from `frontend/pubspec.yaml`). **§5 Run the automated suite** — slice-only `flutter test test/widget/ai/live_client_invoke_test.dart` (T1–T11); no full-suite `npm test`, no combined prior-slice counts. **§6 Inspect the changes** — open hub composition, production mint/submit ports, discovery client; confirm spy on production ports; confirm E1 guard covers composition sources. **§7 Manual validation** — optional: enrolled desktop `/ai` host against a local Worker for a live stream (this slice exposes live client behaviour beyond CI); omit when widget suite alone proves Done when for CP3 review. **Slice-only scope explicit**: no prior-slice files in the review table, no combined test counts, no prior-slice regression commands. Not traced to an FR (template-mandated review surface).

---

## Dependencies & Execution Order

### Phase Dependencies

- **Tests (T001–T011)** — none beyond existing `frontend/` and Consumes Binding modules available as contracts; written to fail before production adapters / hub composition exist. T001 creates `live_client_invoke_test.dart` + substrate. T002–T011 append to the same file (sequential; not `[P]`).
- **Implementation (T012–T015)** — after tests exist (red). T012–T014 are `[P]` relative to each other (different files). T015 (hub) depends on T012–T014. Tests turn green in matching groups: T1/T8–T9 against mint+submit+hub; T2–T5 against submit+hub; T6–T7 against hub degraded composition; T10 against discovery+hub; T11 against composition sources.
- **Verification (T016)** — depends on T001–T015; runs this slice's Flutter suite plus E1 guard check plus every prior suite per §3.10.
- **Documentation (T017)** — depends on T016 (the quickstart records a green suite).

### Within the Slice

- Tests written to fail before implementation; implementation makes them pass; verification confirms the whole suite including prior slices stays green.
- Plan Sequencing maps to Implementation order: mint (T012) → HTTPS submit (T013) → discovery (T014) → hub composition (T015); Documentation last. T012–T014 may land in parallel; T015 after all three.
- Widget-suite Files-section row (`live_client_invoke_test.dart`) is produced by Phase 1. Remaining Files units are T012–T015 plus T017 (`quickstart.md`). Consumed E2/E3/E4 modules and the Worker remain unchanged aside from hub composition in `ai_page.dart`.

### Parallel Opportunities

- Phase 1: all tests share one file — T001 creates; T002–T011 append sequentially (no `[P]` within the file). Spy cases T6 and T8 remain separate tasks (call-count / absence asserts).
- Phase 2: T012, T013, and T014 are `[P]` relative to each other (different files, no mutual dependencies). T015 follows T012–T014.
- Phase 4 (T017) is a single task — no `[P]`.

---

## Notes

- [P] tasks = different files, no dependencies. Marked: T012, T013, T014.
- Every named test T1–T11 from `spec.md` is covered by its own task; no test is folded into another. Spy cases T6 and T8 are separate tasks.
- Every task traces to an `FR-###` from `spec.md` (tests also state the `SC-###` they satisfy) — or to the §3.10 checkpoint / the template-mandated quickstart. No task adds a requirement the spec does not name.
- No Polish phase and no Foundational phase — Needs are E2, E3, E4, I1, I2 (Consumes Binding).
- Consumed modules are imported/bound, not modified (delivery plan §2.3 — extend, never rewrite). No `ai-platform/` file is touched. I4 entitle-and-grant / `context_required` self-heal is out of scope.
- Tests land before or alongside their implementation, never after (delivery plan §2.2).
- Preserve R-12 / §6.4: no prompt text, provider name, or model identifier in the Flutter client; no client-side assembly of a final result from chunks; no committable provisional content; AI never blocks clinical workflows (A11).
