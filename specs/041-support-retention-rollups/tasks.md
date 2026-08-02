# Tasks: Support lookup, retention purges, usage rollups, and journal dashboards (F3)

**Input**: Design documents from `specs/041-support-retention-rollups/`

**Prerequisites**: `plan.md` (required), `spec.md` (required for the user story). `research.md` is never produced on this platform (the research is `docs/architecture/17-ai-platform.md`). `data-model.md` is not produced — F3 defines no new D1 entities (entity presence remains in A5 / C3). `contracts/support-lookup.md`, `contracts/retention-purge.md`, `contracts/usage-rollup-reconciliation.md`, and `contracts/journal-dashboards.md` are already frozen on disk (written during the plan phase per DP-4). `quickstart.md` is written in Phase 4 (Documentation).

**Tests**: Tests are mandatory on this platform (delivery plan §3.10). Every named test in the spec's `### Test plan` (T1–T20) is covered. Per parent workflow override for the task-cap escalation: **one Tests task per planned test file** from the plan's Test Layout, each task listing every named case that file must cover — no named test is dropped. Spy cases remain asserted inside their file tasks (T1 and T20 are spies). Layer is **Integration + scheduled job + query tests (spy)** (delivery plan §3.11.6 row F3; §13.5 Pipeline tests — fake D1/R2/DO; spy on query/GetObject/Put/Delete counts).

**Organization**: One user story (US1, P1) — F3 is one slice, one story (delivery plan §2.6, overrides). No cross-story parallelism section. No Setup phase — contracts are already on disk; plan Files are created by Tests/Implementation. No Foundational or Polish phase — prerequisites are already-merged Needs (C3, B4) in the plan's Consumes Binding.

**Task count**: 11 (≤25). Parent override combined control/worker/wrangler into one Implementation task and tests-by-file into four Tests tasks so the list fits the cap without dropping coverage.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: US1 (this slice has a single user story)
- Include exact file paths in descriptions

## Path Conventions

- **Flutter desktop app**: `frontend/lib/`, `frontend/test/` — *not touched by F3*
- **Supabase backend**: `backend/migrations/`, `backend/functions/`, `backend/tests/` — *not touched by F3*
- **AI gateway Worker**: `ai-platform/src/`, `ai-platform/migrations/`, `ai-platform/test/`
- **Spec Kit artifacts**: `specs/041-support-retention-rollups/`
- The Worker lives in `ai-platform/` at the repository root, a sibling of `frontend/` and `backend/` (delivery plan §7.1). F3 adds no `ai-platform/migrations/` edits — no new D1 entities. Consumed C3 `journal/`, A2 `reference.ts`, B4 `credit/` / `quota-do/`, and A4/C1 `manifest/` are imported unchanged.

---

## Phase 1: Tests (written to fail before the code exists)

**Purpose**: One task per planned test file from `plan.md` → Test Layout. Together the four files cover all twenty named cases T1–T20. Until `src/support/`, `src/retention/`, `src/rollup/`, `src/dashboards/`, and control/worker wiring exist, imports/assertions fail — the intended red state. Order follows plan Sequencing themes (support → retention → rollup → dashboards). Files are independent, so all four are `[P]` relative to each other.

- [ ] T001 [P] [US1] Create `ai-platform/test/support-lookup.test.ts` (integration spy) covering **T1–T3**: (T1) `support_lookup_one_d1_one_getobject` — spy that a valid reference resolves to full trace + in-horizon envelope in exactly one indexed D1 query and exactly one R2 `GetObject`; (T2) `support_lookup_expired_envelope_metadata` — expired diagnostic envelope still resolves journal metadata with envelope body absent; (T3) `support_lookup_non_operator_denied` — clinic/non-operator credentials are denied. Substrate: fake D1/R2, operator vs clinic auth doubles, import of support lookup under test. Fails red until `src/support/` + control route exist. **Satisfies**: FR-001–FR-006, FR-019 / SC-001, SC-002. **Proves**: T1, T2, T3.

- [ ] T002 [P] [US1] Create `ai-platform/test/retention.test.ts` (integration / scheduled job) covering **T4–T9**: (T4) `retention_expiry_diagnostic` — past-horizon diagnostic envelopes deleted; in-horizon kept; (T5) `retention_expiry_journal` — past-horizon `ai_request` / `ai_attempt` deleted; in-horizon kept; (T6) `retention_expiry_ledger` — past-horizon `usage_event` / `usage_rollup` / `control_audit` / `capability_grant` deleted; in-horizon kept; (T7) `retention_expiry_ephemeral` — Quota DO `jti` / idempotency expire in place with no table prune (Consumes B4); (T8) `retention_per_capability_diagnostic` — shorter-horizon capability purged while longer kept; (T9) `retention_purge_by_installation_id` — purge by installation id clears D1 + R2 for that installation only. Substrate: fake D1/R2/DO, seeded rows/objects across horizons, scheduled purge entry. Fails red until `src/retention/` + cron/purge route exist. **Satisfies**: FR-007–FR-010, FR-018 / SC-003. **Proves**: T4, T5, T6, T7, T8, T9.

- [ ] T003 [P] [US1] Create `ai-platform/test/rollup-reconciliation.test.ts` (scheduled job) covering **T10–T13**: (T10) `rollup_totals_equal_ledger` — `usage_rollup` totals equal seeded `usage_event` sums; (T11) `reconciliation_missing_attempt_rows` — terminal request with no `ai_attempt` rows flagged; (T12) `reconciliation_missing_usage_credit` — terminal request missing usage credit / settling `usage_event` flagged; (T13) `rollup_rerun_idempotent` — re-run over the same window does not duplicate rollup totals; report stays consistent. Substrate: fake D1, seeded ledger/journal rows, scheduled rollup/reconciliation entry. Fails red until `src/rollup/` + scheduled wiring exist. **Satisfies**: FR-011–FR-014 / SC-004, SC-005. **Proves**: T10, T11, T12, T13.

- [ ] T004 [P] [US1] Create `ai-platform/test/journal-dashboards.test.ts` (query + spy) covering **T14–T20**: (T14) `dashboard_ttft_by_provider`; (T15) `dashboard_validation_failure_by_prompt_version`; (T16) `dashboard_repair_rate_by_capability`; (T17) `dashboard_fallback_rate_by_provider`; (T18) `dashboard_cost_per_capability_per_installation`; (T19) `dashboard_quota_rejection_rate` — each returns the correct value against a seeded journal / rollups / `platform_counter`; (T20) `dashboard_no_second_metrics_store` — spy that no second metrics store is written. Substrate: fake D1 with seeded journal/rollup/counter rows; spy on write/put paths. Fails red until `src/dashboards/` exists. **Satisfies**: FR-015–FR-017 / SC-006. **Proves**: T14, T15, T16, T17, T18, T19, T20.

---

## Phase 2: Implementation (plan Files section)

**Purpose**: Implementation units from `plan.md` → Files not already produced as Vitest entries or Documentation. Parent override: merge `src/control/index.ts`, `src/worker.ts`, and `wrangler.toml` into **one** wiring task. Keep the four feature modules as separate tasks. Consumed C3/B4 modules are imported, not modified (delivery plan §2.3). Contracts are already frozen. Tests turn green in matching groups per plan Sequencing: support → retention → rollup → dashboards → wiring.

- [ ] T005 [P] [US1] Create `ai-platform/src/support/index.ts` — operator support lookup: normalise request-reference input (case-fold up; `I`/`L` → `1`, `O` → `0`; fixed eight-symbol Crockford format), exactly one indexed D1 lookup returning reconstructable trace (§8.9 request row + attempts), exactly one R2 `GetObject` for in-horizon envelope (omit body when outside diagnostic retention); operator-facing reconstruction only (FR-001–FR-006, FR-019). Reuse A2/C3 `normalizeRequestReference`; do not redefine C3 get-request. **Satisfies**: FR-001–FR-006, FR-019. **Proved by**: T1, T2, T3.

- [ ] T006 [P] [US1] Create `ai-platform/src/retention/index.ts` — four-class retention purge with horizons in architecture bands (diagnostic baseline **7 days**, override via manifest `retentionClass` e.g. `diagnostic_30d`; journal **90 days**; ledger **2555 days** ≈7 years; ephemeral unchanged — B4 `EPHEMERAL_HORIZON_MS`); never delete in-horizon data; per-capability diagnostic horizon; purge by installation id in D1 and R2; journal operator-audited mutations to `control_audit` where required (FR-007–FR-010, FR-018). Prove ephemeral via Consumes B4 in-place expiry — no D1/R2 prune for ephemeral. **Satisfies**: FR-007–FR-010, FR-018. **Proved by**: T4, T5, T6, T7, T8, T9.

- [ ] T007 [P] [US1] Create `ai-platform/src/rollup/index.ts` — scheduled `usage_rollup` production from `usage_event` (ledger remains evidence; rollups convenience); totals equal ledger sums; reconciliation report flags terminal requests missing `ai_attempt` rows and missing usage credit (R-6); re-run idempotent (FR-011–FR-014). **Satisfies**: FR-011–FR-014. **Proved by**: T10, T11, T12, T13.

- [ ] T008 [P] [US1] Create `ai-platform/src/dashboards/index.ts` — six named read-only diagnostic queries against `ai_request` / `ai_attempt` / `usage_rollup` / `platform_counter` only (TTFT by provider; validation-failure rate by prompt version; repair rate by capability; fallback rate by provider; cost per capability per installation; quota rejection rate); off the request path; no second metrics store (FR-015–FR-017). **Satisfies**: FR-015–FR-017. **Proved by**: T14, T15, T16, T17, T18, T19, T20.

- [ ] T009 [US1] Wire control-plane routes, Worker entry, and cron bindings in one unit — modify `ai-platform/src/control/index.ts` (dispatch support-lookup + installation-purge; reuse B2 `OperatorAuth` / `requireOperator`; FR-001, FR-005, FR-010, FR-018), modify `ai-platform/src/worker.ts` (dispatch support/purge routes; `scheduled` handler for retention + rollup/reconciliation; FR-001, FR-011, FR-013, FR-017), and modify `ai-platform/wrangler.toml` (cron triggers for retention purge and rollup/reconciliation; FR-007, FR-011). Depends on T005–T008 module APIs. **Satisfies**: FR-001, FR-005, FR-007, FR-010, FR-011, FR-013, FR-017, FR-018. **Proved by**: T1–T13 (route/cron entry paths for support, retention, rollup).

---

## Phase 3: Verification

**Purpose**: Delivery plan §3.10 — every prior suite stays green alongside the new one, not just the latest.

- [ ] T010 [US1] From `ai-platform/`, run this slice's suite — `npx vitest run test/support-lookup.test.ts test/retention.test.ts test/rollup-reconciliation.test.ts test/journal-dashboards.test.ts`. Then run every prior slice's suite: `npx vitest run` (default Node-pool) and `npx vitest run --config vitest.workers.config.ts` (workers-pool), including prior Band F entries (F1 eval under `test/eval/` as already gated; F2 clinic-side suites remain outside `ai-platform/` and stay green via their existing runners). Confirm F3's twenty named cases are green and every prior suite stays green. No new test is added here — this is the §3.10 checkpoint gate. F3 emits no new §5.4 taxonomy code for non-operator deny (control-plane auth boundary). **Satisfies**: the §3.10 checkpoint rule (T1–T20 + prior suites). Proved by itself.

---

## Phase 4: Documentation

**Purpose**: Always present. The one documentation artifact the plan names that does not yet exist on disk (`quickstart.md`); written only after the suite is green. Contracts were already frozen during the plan phase. No other documentation artifact is named for a separate `[P]` task (no `ai-platform/README.md` — not the bootstrap slice).

- [ ] T011 [US1] Create `specs/041-support-retention-rollups/quickstart.md` from `.specify/templates/ai-platform-quickstart-template.md`, scoped to this slice only. **§1 Architecture context** — delivery plan §3.7 row F3; `17-ai-platform.md` §4.5 / §8.9 / §7.6 / §7.7 / §13.1 / R-6 / A13; what the spec delivered; what the plan scoped. **§2 What was implemented** — operator support lookup; four-class retention purges + purge-by-installation; `usage_rollup` + reconciliation; six journal dashboards; frozen `contracts/*`. **§3 Files to review** — only this slice's `src/support/`, `src/retention/`, `src/rollup/`, `src/dashboards/`, control/worker/wrangler deltas, this slice's four test files, and `contracts/*` (no prior-slice files). **§4 Prerequisites** — omit or keep minimal (`cd ai-platform && npm install` first time). **§5 Run the automated suite** — slice-only `npx vitest run test/support-lookup.test.ts test/retention.test.ts test/rollup-reconciliation.test.ts test/journal-dashboards.test.ts`; no full-suite `npm test`, no combined prior-slice counts. **§6 Inspect the changes** — grep support-lookup route, retention/rollup cron handlers, dashboard query modules, focused Vitest files, frozen contracts. **§7 Manual validation** — optional: operator support-lookup against a seeded reference and inspect cron job logs when bindings are available; omit detailed deploy steps if CI is the sole primary path. **Slice-only scope explicit**: no prior-slice files in the review table, no combined test counts, no prior-slice regression commands. Not traced to an FR (template-mandated review surface).

---

## Dependencies & Execution Order

### Phase Dependencies

- **Tests (T001–T004)** — none beyond already-frozen contracts and Consumes Binding modules (C3, B4); written to fail before the code exists. All four are `[P]` — different test files.
- **Implementation (T005–T009)** — after tests exist (red). T005–T008 (`support/`, `retention/`, `rollup/`, `dashboards/`) are `[P]` relative to each other — different modules. T009 (control + worker + wrangler wiring) depends on T005–T008.
- **Verification (T010)** — depends on T001–T009; runs this slice plus every prior slice per §3.10.
- **Documentation (T011)** — depends on T010 (the quickstart records a green suite).

### Within the Slice

- Tests written to fail before implementation; implementation makes them pass; verification confirms the whole suite including prior slices stays green.
- Plan Sequencing maps to Implementation order: support (T005) → retention (T006) → rollup (T007) → dashboards (T008) → wiring (T009) → quickstart (T011). Modules may proceed in parallel; wiring waits for module APIs.
- Vitest entry Files-section rows are produced by Phase 1; not repeated as Implementation tasks. Remaining Files units: T005–T009 plus T011 (`quickstart.md`). Four contracts are already frozen — no task recreates them.

### Parallel Opportunities

- Phase 1: T001–T004 are all `[P]` — four different test files.
- Phase 2: T005–T008 are `[P]` relative to each other — different `src/` modules. T009 follows T005–T008.
- Phase 4: T011 is a single task — no `[P]`.

---

## Notes

- [P] tasks = different files, no dependencies. Marked: T001–T004 (test files); T005–T008 (feature modules).
- All twenty named tests T1–T20 from `spec.md` appear in Phase 1 Tests tasks (T001→T1–T3; T002→T4–T9; T003→T10–T13; T004→T14–T20). Spy cases T1 and T20 are not folded away — they remain explicit asserts inside their file tasks.
- Every task traces to an `FR-###` from `spec.md` (tests also state the `SC-###` they satisfy) — or to Freezes / the §3.10 checkpoint / the template-mandated quickstart. No task adds a requirement the spec does not name.
- No Polish phase and no Foundational phase — Needs are C3, B4 (already merged; Consumes Binding).
- Consumed modules are imported/bound, not modified (delivery plan §2.3 — extend, never rewrite). No `frontend/` or `backend/` file is touched.
- Parent workflow override applied: control/worker/wrangler merged into T009; tests grouped by planned test file (four tasks) so the list fits ≤25 without dropping named-test coverage.
- Tests land before or alongside their implementation, never after (delivery plan §2.2).
- Preserve §6.4: no §9.14 mechanism; no second Quota DO round trip or second R2 object per inference request; no D1-per-chunk; no per-request server-side state; no second metrics store; no Flutter prompt/provider/model strings.
