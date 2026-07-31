---

description: "Task list for AI platform slice B3 — Guard stages: identity, rate limiting, entitlement and kill switches"
---

# Tasks: Guard stages: identity, rate limiting, entitlement and kill switches (B3)

**Input**: `specs/023-guard-stages/spec.md`, `specs/023-guard-stages/plan.md`

**Prerequisites**: `plan.md` (required), `spec.md` (required). The consumed slices A2 (`ai-platform/src/errors.ts`), A5 (`ai-platform/src/config-cache/`, `ai-platform/migrations/20260731120000_platform_schema.sql`), A6 (`ai-platform/src/adapter.ts`), B1 (`backend/supabase/migrations/2026080*` + `specs/021-…/contracts/aat-token.md`), and B2 (`ai-platform/src/control/` + `specs/022-…/contracts/control-plane.md`) are merged and unmodified (plan → Consumes Binding). The plan's frozen contracts `specs/023-guard-stages/contracts/token-verifier.md` and `contracts/request-principal.md` already exist on disk.

**Tests**: Mandatory (delivery plan §3.10 overrides the template). Every named test in the spec's Test plan is a task, written to fail before the code exists. Iterated cases sharing one `describe` and one assertion structure are grouped into a single task (precedent: A5 T016 eleven entity-presence cases, A5 T023 six entity-kind cases). Every spy case is its own task.

**Organization**: One slice = one user story = one `[US1]` label. No multi-story phases, no Foundational phase (prerequisites are merged slices), no Polish phase (R-20).

**Sizing**: 16 tasks. B3 is a merged slice (delivery plan §2.6 explicitly names `B3`) whose Test plan is the union of the merged rows' case lists; 25–40 tasks is the correctly-sized range (§2.5). 16 sits within it and well under the §6.3 ~40 stop.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies). The first task of each of the three test files is `[P]` relative to the first task of the others (three independent files). Spy tasks touching different files are `[P]` relative to each other.
- **[Story]**: `US1` — the slice's one user story (spec → User Story 1).
- Exact file paths in every description.

## Path Conventions

- **Flutter desktop app**: `frontend/lib/`, `frontend/test/` — not touched by this slice.
- **Supabase backend**: `backend/migrations/`, `backend/functions/`, `backend/tests/` — consumed from B1, not modified.
- **AI platform Worker**: `ai-platform/src/`, `ai-platform/migrations/`, `ai-platform/test/`, and root configs `ai-platform/vitest*.config.ts` — this slice lives here.
- Paths follow `plan.md` → Source Code; the Worker tree is authoritative for this slice.

---

## Phase 1: Setup (Test harness)

**Purpose**: Route the three new test files to the workers pool that provides the real Miniflare D1 binding B2 already wired (Clarification Q4; plan → Test Layout). Both edits must land before any test file is written.

- [ ] T001 [US1] Modify `ai-platform/vitest.workers.config.ts` — add `"test/identity.test.ts"`, `"test/entitlement.test.ts"`, `"test/rate-limit.test.ts"` to `include` alongside `"test/control.test.ts"`. Modify `ai-platform/vitest.config.ts` — add the same three files to `exclude` alongside `"test/control.test.ts"`, so the workers-pool-only files do not double-run in the default Node pool (plan → Files: vitest configs). No FR — harness; required by every named test. Prepares the Phase 2 substrates.

**Checkpoint**: both configs resolve; `npx vitest run` (default) still runs every prior suite; `npx vitest run --config vitest.workers.config.ts test/control.test.ts` still passes (B2 unaffected).

---

## Phase 2: Tests (written to fail before the code exists)

**Purpose**: One task per named test in the spec's `### Test plan` (§3.11.2 row B3 = Unit + integration (spy)). Iterated cases sharing one `describe` and one assertion structure are grouped; every spy case is its own task. The first task of each file builds the fixture/spy substrate and is `[P]` relative to the first task of the other two files.

### 2.1 Identity — `ai-platform/test/identity.test.ts`

- [ ] T002 [P] [US1] Create `ai-platform/test/identity.test.ts` with the WebCrypto `Ed25519` test-keypair fixture (`crypto.subtle.generateKey("EdDSA", …)`), a `mintToken(claims, keypair)` factory producing the three-segment `EdDSA` JWS from B1's contract (`specs/021-…/contracts/aat-token.md` §2–3), and `identity_valid_token_accepted` — assert `verify(token, ctx)` returns `{ok:true; principal}` carrying every §5.6 claim. Then add the seven remaining unit cases as a data-driven `describe`: `identity_rejects_non_eddsa_alg`, `identity_rejects_bad_signature`, `identity_rejects_wrong_audience`, `identity_rejects_expired_token`, `identity_accepts_notyetvalid_inside_skew`, `identity_rejects_outside_skew`, `identity_rejects_unknown_issuer` — each mutates the token via the factory and asserts `{ok:false; code:"unauthenticated"}` (or `{ok:true}` for the inside-skew accept). Proves FR-001, FR-002, FR-003; satisfies SC-001, SC-002. File fails to compile (`../src/identity` absent). (8 named tests, 1 task — shared fixture, data-driven mutations.)
- [ ] T003 [US1] Add `verifier_swap_changes_no_outcome` to `ai-platform/test/identity.test.ts` — run the same token set through a fake `TokenVerifier` (returning fixed results) and the `EnrolledKeyVerifier`; assert every outcome is identical. The swap is a port substitution, not a behaviour change (§4.3.2; Clarification Q3). Proves FR-001, FR-013; satisfies SC-001.
- [ ] T004 [P] [US1] Add `principal_immutable_to_later_stage` to `ai-platform/test/identity.test.ts` — spy: after identity produces a `Principal`, attempt to mutate every field and to `push`/`pop` on `scopes`; assert each attempt throws or no-ops and a later reader sees the original values. Proves FR-004; satisfies SC-001. (Spy case — its own task per the rules.)
- [ ] T005 [US1] Add `identity_rejects_suspended_installation` to `ai-platform/test/identity.test.ts` — seed `env.DB` (B2's Miniflare harness, `d1Databases:["DB"]`) with the A5 migration, insert an `installation` row with `status = "suspended"`, and assert `verify` returns `{ok:false; code:"installation_suspended"}`. Proves FR-005; satisfies SC-003.

### 2.2 Rate limiting — `ai-platform/test/rate-limit.test.ts`

- [ ] T006 [P] [US1] Create `ai-platform/test/rate-limit.test.ts` with the Rate Limiting binding fixture and `rate_limit_installation_key_trips` — overflow the `installation` composite key; assert `rate_limited` (HTTP 429) carrying `retry_after` (via A2 `supplementaryFieldsForCode`), the matching `platform_counter` row incremented with correct dimensions, and no `ai_request` row created (read-back count unchanged). Then add `rate_limit_installation_actor_key_trips` and `rate_limit_installation_capability_key_trips` as two further cases in the same `describe`, each asserting the key trips **independently** of the other two (§4.3.3 "one case per composite key tripping independently"). Proves FR-006, FR-007, FR-012; satisfies SC-004. (3 named tests, 1 task — shared fixture, iterated key.)
- [ ] T007 [US1] Add `rate_limit_rejection_no_ai_request_row` to `ai-platform/test/rate-limit.test.ts` — spy: after a rate-limit rejection, assert the `ai_request` table row count is unchanged (no journal row on guard rejection, §6.1 stage 9; §7.5) and the `platform_counter` row was incremented. Proves FR-012; satisfies SC-004. (Spy case — its own task.)
- [ ] T008 [US1] Add `rate_limit_counters_flush_bucketed` to `ai-platform/test/rate-limit.test.ts` — spy: trigger the in-isolate tally flush and assert `platform_counter` rows are written bucketed by dimension and time bucket, never one row per event (§4.3.12; §7.5). Proves FR-011; satisfies SC-007. (Spy case — its own task.)

### 2.3 Entitlement and kill switches — `ai-platform/test/entitlement.test.ts`

- [ ] T009 [P] [US1] Create `ai-platform/test/entitlement.test.ts` with the `ConfigCache` + `D1Reader`/`ReaderSpy` fixture (reusing A5's `config-cache.test.ts` spy shape per Clarification Q4) and a data-driven `describe` covering `entitlement_ai_disabled_installation_rejected`, `entitlement_plan_tier_too_low_rejected`, and `entitlement_capability_not_granted_rejected` — each seeds `env.DB` with an `installation` + `entitlement` row whose shape triggers the rejection, asserts `{ok:false; code:"forbidden_capability"}` (the only stage-3 code other than `installation_suspended`, §6.1 stage 3; §5.4), and checks the correct rejection path. Proves FR-008; satisfies SC-005. (3 named tests, 1 task — shared fixture, iterated rejection cause.)
- [ ] T010 [US1] Add `kill_switch_global_rejected`, `kill_switch_capability_rejected`, `kill_switch_installation_rejected`, and `kill_switch_provider_rejected` to `ai-platform/test/entitlement.test.ts` as a data-driven `describe` iterating the four kill-switch scopes (§4.3.4; §4.5 "Global, per capability, per installation, per provider") — each seeds the relevant kill-switch state in `env.DB`, asserts `{ok:false; code:"capability_disabled"}` (§5.4), and confirms the correct scope was consulted. Proves FR-009; satisfies SC-005. (4 named tests, 1 task — shared fixture, iterated scope.)
- [ ] T011 [P] [US1] Add `entitlement_warm_isolate_no_d1_read` to `ai-platform/test/entitlement.test.ts` — spy: warm the `ConfigCache` with installation/entitlement/grant/kill-switch rows, then run the full entitlement + four-scope evaluation; assert the `ReaderSpy.read` call count is **zero** for every consult (FR-010; §4.3.3; §4.3.2 — "warm isolate performs no D1 read"). Proves FR-010; satisfies SC-006. (Spy case — its own task.)

**Checkpoint**: all three test files exist, every named test block fails for the right reason (modules absent, spy seams unwired), no harness failure.

---

## Phase 3: Implementation (plan Files section)

**Purpose**: One task per implementation unit in `plan.md` → Files. The modules are `[P]` relative to each other (three independent files, no shared dependency); each turns its corresponding test file green independently. The consumed `errors.ts`, `config-cache/`, `adapter.ts`, `control/`, and the migration are not modified.

- [ ] T012 [P] [US1] Create `ai-platform/src/identity/index.ts` — the `TokenVerifier` port (`verify(token, ctx): Promise<VerifyResult>` discriminated union, Clarification Q3), `VerifyContext` (audience, clockSkewSeconds, now, cache, reader — Clarification Q2), `Principal` (immutable, frozen fields per `contracts/request-principal.md`), and the `EnrolledKeyVerifier` following the 12-step algorithm in `contracts/token-verifier.md` §6: split segments, pin `alg = "EdDSA"` (reject `none`/HMAC), select key by `iss`+`kid` via `loadConfig(cache, reader, "installations"|"keys", …)`, reject `installation_suspended` from B2's `installation.status`, check audience + expiry + clock-skew tolerance, verify the Ed25519 signature via WebCrypto `importKey`+`verify`, construct the frozen `Principal`. `jti` replay is **not** checked (FR-014 — B4). **Satisfies**: FR-001, FR-002, FR-003, FR-004, FR-005, FR-013, FR-014; **proved by**: `identity_valid_token_accepted`, the seven rejection/acceptance cases, `verifier_swap_changes_no_outcome`, `principal_immutable_to_later_stage`, `identity_rejects_suspended_installation`.
- [ ] T013 [P] [US1] Create `ai-platform/src/entitlement/index.ts` — `evaluateEntitlement(principal, ctx, cache, reader)` returning `{ok:true}` or `{ok:false; code:"forbidden_capability"|"capability_disabled"}`, reading AI-enablement, plan tier, and capability grant from `loadConfig(cache, reader, "entitlements"|"grants", …)` (FR-008), and the four kill-switch scopes (global, capability, installation, provider) from `loadConfig(cache, reader, "kill_switches", …)` (FR-009). No D1 read on a warm isolate (FR-010 — the cache returns from memory; proven by `entitlement_warm_isolate_no_d1_read`). No manifest lookup (C1, out of scope); no quota/concurrency check (B4, out of scope). **Satisfies**: FR-008, FR-009, FR-010; **proved by**: the three `entitlement_*` cases, the four `kill_switch_*` cases, `entitlement_warm_isolate_no_d1_read`.
- [ ] T014 [P] [US1] Create `ai-platform/src/rate-limit/index.ts` — the three composite keys (`installation`, `installation+actor`, `installation+capability`) against the Workers Rate Limiting binding (§4.3.3), `rate_limited` + `retry_after` (via A2 `supplementaryFieldsForCode`, FR-007), and the in-isolate rejection tally that flushes periodically to bucketed `platform_counter` rows (§4.3.12; §7.5) — never one row per event, never an `ai_request` row (FR-011, FR-012). No fourth composite key (spec Assumption). No quota DO contact (B4, out of scope — FR-014). **Satisfies**: FR-006, FR-007, FR-011, FR-012; **proved by**: the three `rate_limit_*_key_trips` cases, `rate_limit_rejection_no_ai_request_row`, `rate_limit_counters_flush_bucketed`.

**Checkpoint**: `npx vitest run --config vitest.workers.config.ts test/identity.test.ts test/entitlement.test.ts test/rate-limit.test.ts` green; all 24 named tests pass.

---

## Phase 4: Verification

**Purpose**: Delivery plan §3.10 — every prior suite stays green alongside the new one, not just the latest.

- [ ] T015 [US1] Run `npx vitest run --config vitest.workers.config.ts` (this slice's three files + B2's `control.test.ts`) and then `npx vitest run` (the default Node-pool config covering every prior band-A/band-B1/band-B2 suite — `config-cache.test.ts` (A5), `context.test.ts` (A5), `migrations.test.ts` (A5), `manifest.test.ts` (A4), `canonical.test.ts` (A3), `taxonomy.test.ts`, `reference.test.ts`, `error-body.test.ts`, `trace.test.ts`, `log-redaction.test.ts` (A2), `health.test.ts`, `env-deploys.test.ts` (A1), `adapter.test.ts` (A6)). Confirm every prior suite stays green. No new test is added here — this is the §3.10 checkpoint gate, not extra work. **Satisfies**: the §3.10 checkpoint rule.

**Checkpoint**: full platform suite green; no regressions in A1–A5, B1, B2.

---

## Phase 5: Documentation

**Purpose**: Plan → Documentation. The frozen contracts (`contracts/token-verifier.md`, `contracts/request-principal.md`) already exist on disk (written during the plan phase); no task rewrites them. Only `quickstart.md` remains, written after the suite is green.

- [ ] T016 [US1] Create `specs/023-guard-stages/quickstart.md` from `.specify/templates/ai-platform-quickstart-template.md`, scoped to this slice only. **§1 Architecture context** — delivery plan §3.3 row B3; the §4.3.2 / §4.2.1 / §5.6 / §4.3.3 / §4.3.4 / §4.3.12 / §7.5 / §6.1-stages-2–4 sections; what the spec delivered; what the plan scoped. **§2 What was implemented** — the three sibling modules (`src/identity/`, `src/entitlement/`, `src/rate-limit/`), the `TokenVerifier` port + `Principal`, the bucketed `platform_counter` flush. **§3 Files to review** — `ai-platform/src/identity/index.ts`, `ai-platform/src/entitlement/index.ts`, `ai-platform/src/rate-limit/index.ts`, `ai-platform/test/identity.test.ts`, `ai-platform/test/entitlement.test.ts`, `ai-platform/test/rate-limit.test.ts`, `ai-platform/vitest.workers.config.ts` diff, `specs/023-guard-stages/contracts/token-verifier.md`, `specs/023-guard-stages/contracts/request-principal.md`. **§4 Prerequisites** — kept: `--config vitest.workers.config.ts` flag + one-time `npm install` (the slice's tests need the workers-pool Miniflare D1). **§5 Run the automated suite** — `npx vitest run --config vitest.workers.config.ts test/identity.test.ts test/entitlement.test.ts test/rate-limit.test.ts` (slice-only; no `npm test` for the full platform suite). **§6 Inspect the changes** — read the verifier port, grep the `alg === "EdDSA"` pin, read the frozen `contracts/` artifacts. **No §7** — CI is the only verification path (B3 exposes no user-facing behaviour beyond the suite). **Slice-only scope explicit**: no prior-slice files in the review table, no combined test counts, no prior-slice regression commands. Not traced to an FR (template-mandated review surface).

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: no dependencies — T001 routes test files to the workers pool. Blocks Phase 2.
- **Tests (Phase 2)**: depends on Setup. The first task of each test file (T002, T006, T009) is `[P]` relative to the other two (three independent files, independent fixtures). Within each file, subsequent tasks run sequentially on top of their file's substrate. T004 and T011 are spy tasks touching their file's already-built substrate but are `[P]` relative to each other (asserting different spy seams in different files). Block Phase 3.
- **Implementation (Phase 3)**: depends on Tests (red state confirmed). T012, T013, T014 touch three different files and are `[P]`; each turns its corresponding test file green independently.
- **Verification (Phase 4)**: depends on Implementation (all three test files passing). T015 is the §3.10 full-suite gate.
- **Documentation (Phase 5)**: depends on Verification (T015 green). T016 is the only documentation task (contracts already exist).

### Within the slice

- Tests are written and confirmed failing before any implementation (T012 proved by T002–T005; T013 by T009–T011; T014 by T006–T008).
- The migration (`ai-platform/migrations/20260731120000_platform_schema.sql`) is applied in test setup, never edited — A5 owns it.
- No new binding, secret, DO class, `wrangler.toml` change, or migration is made anywhere in the slice.
- The consumed `errors.ts` (A2), `config-cache/` (A5), `adapter.ts` (A6), `control/` (B2), and the B1 keystore/issuer in `backend/supabase/` are imported, never modified.

### Parallel Opportunities

- T002, T006, T009 (Phase 2) — the three test files' substrate tasks — are `[P]` (independent files).
- T012, T013, T014 (Phase 3) — the three implementation modules — are `[P]` (independent files, no shared dependency).
- No other parallelism within a file: test tasks sharing one file run sequentially in the order listed.

---

## Notes

- `[P]` tasks = different files, no dependencies. The parallel pairs are T002 ∥ T006 ∥ T009 (Phase 2 substrates) and T012 ∥ T013 ∥ T014 (Phase 3 modules).
- The slice has one user story, `US1`; the template's multi-story, Foundational, and Polish phases are dropped (delivery plan overrides).
- No task adds a migration, a binding, a retry, a cache, a configuration surface, or any §9.14 mechanism — none is named by the spec or plan (R-20; spec → Out of Scope).
- Every spy case is its own task: T004 (`principal_immutable_to_later_stage`), T007 (`rate_limit_rejection_no_ai_request_row`), T008 (`rate_limit_counters_flush_bucketed`), T011 (`entitlement_warm_isolate_no_d1_read`) — four spy tasks, each asserting a call count or an absence (delivery plan §3.10).
- Iterated cases sharing one `describe` and one assertion structure are grouped: T002 (8 identity unit cases), T006 (3 rate-limit key cases), T009 (3 entitlement-rejection cases), T010 (4 kill-switch cases) — precedent: A5 T016 (11 entity-presence cases), A5 T023 (6 entity-kind cases).
- Sizing: 16 tasks. B3 is a merged slice (delivery plan §2.6 explicitly names `B3`); 25–40 is the correctly-sized range (§2.5) and ~40 is the §6.3 stop. 16 sits within both.