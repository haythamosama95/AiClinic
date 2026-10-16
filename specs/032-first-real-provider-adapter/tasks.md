# Tasks: First real provider adapter (D5)

**Input**: Design documents from `specs/032-first-real-provider-adapter/`

**Prerequisites**: `plan.md` (required), `spec.md` (required for the user story). `research.md` is never produced on this platform (the research is `docs/architecture/ai-platform/01-ai-platform.md`). `data-model.md` is not produced — D5 defines no D1 entities (spec Key Entities). `contracts/first-real-provider-adapter.md` is already frozen on disk (written during the plan phase per DP-4). `quickstart.md` is written in Phase 4 (Documentation).

**Tests**: Tests are mandatory on this platform (delivery plan §3.10). Every named test in the spec's `### Test plan` (T1–T11) is covered by its own task, written to fail before the code exists. Spy cases T8, T10, and T11 are separate tasks. T4 expands to one named subcase per DeepSeek wire error class enumerated in `contracts/first-real-provider-adapter.md` §3.1 (`auth_rejected`, `rate_limited`, `provider_server_error`, `content_filtered`) — still one task, four subcases. Review resolution (2026-08-04) amends completion evidence in place under T001–T013 (empty terminal; SSE malformed/truncation/mid-stream error; finish-reason mapping; HTTP status wins; `consumedBudget: false` on missing key; `include_usage` / `cached` / `usage_absent`; measured `provider_ms`; abort on timeout; no logger/journal sinks; buffered fixture transport; remaining-ms deadline) — no new task IDs.

**Organization**: One user story (US1, P1) — D5 is one slice, one story (delivery plan §2.6, overrides). No cross-story parallelism section. No Setup phase — contracts are already on disk; no migrations or `wrangler.toml` edits. No Foundational or Polish phase.

**Task count**: 15 (≤25).

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: US1 (this slice has a single user story)
- Include exact file paths in descriptions

## Path Conventions

- **AI gateway Worker**: `ai-platform/src/`, `ai-platform/migrations/`, `ai-platform/test/`
- **Spec Kit artifacts**: `specs/032-first-real-provider-adapter/`
- The Worker lives in `ai-platform/` at the repository root, a sibling of `frontend/` and `backend/` (delivery plan §7.1). The template's `frontend/lib/` and `backend/migrations/` conventions do not apply to this slice; D5 touches neither. No `ai-platform/migrations/` edits — D5 adds no D1 schema.

---

## Phase 1: Tests (written to fail before the code exists)

**Purpose**: One task covering each named test in the spec's `### Test plan` (§3.11.4 row D5 = "Adapter fixtures"; §13.5 Provider adapter tests — recorded provider fixtures). All 11 cases live in `ai-platform/test/deepseek-adapter.test.ts` under the default Node-pool config (`vitest.config.ts`, `include: ["test/**/*.test.ts"]`); no workers-pool registration is needed — transport and secret store are injectable (Clarifications Q3–Q4 amended; no logger/journal sinks), and the permanent suite uses recorded fixtures with no live egress. T001 creates the test file and its substrate; T002–T011 append to it. The module under test (`../src/provider/deepseek`) does not exist yet, so the file fails to compile from the first importing task onward — the intended red state. Order follows the plan's Sequencing (surface/secret → mapping → stream/usage → errors → credential spies).

- [X] T001 [US1] Add `T-D5-09 adapter_owns_no_retry_or_fallback` to `ai-platform/test/deepseek-adapter.test.ts` (adapter fixtures): create the substrate — imports of `DeepSeekAdapter` from `../src/provider/deepseek` and `ProviderPort` from `../src/provider/port`; a constructor call site taking injectable transport/fetch and secret-store ports only (Clarifications Q3–Q4 amended; no logger/journal sinks — D2 repair). Then the case: assert the DeepSeek adapter export / options surface exposes classification only — inspect exported keys / types / options for absence of retry, fallback, and logging-policy APIs (§4.3.8; §3.10 inherited prohibition; Clarification Q2). Satisfies FR-003 / SC-004. Proves T9.
- [X] T002 [US1] Add `T-D5-11 credentials_from_secret_store_only` to `ai-platform/test/deepseek-adapter.test.ts` (adapter fixtures, spy): inject a fake secret-store binding that records reads and returns a known secret value; construct `DeepSeekAdapter` with that store (and a transport stub that captures the outbound request); invoke; assert the secret was read from the store, wire `Authorization` carries that store secret (not a request-embedded value), and that credentials were not taken from config files, request input, or hard-coded literals (Clarification Q4 amended; §4.3.8). Satisfies FR-007 / SC-003. Proves T11.
- [X] T003 [US1] Add `T-D5-01 request_mapping_golden` to `ai-platform/test/deepseek-adapter.test.ts` (adapter fixtures): load a canonical request fixture and the recorded outbound wire golden under `ai-platform/test/fixtures/deepseek/request-mapping/`; inject a transport that captures the outbound request; invoke the adapter; assert the emitted wire request (URL/method/headers/body shape) matches the golden, including `stream_options.include_usage` on stream requests, with Authorization sourced from the secret-store value and the secret not placed in mapped body fields (§4.3.8; §3.11.4 D5; Clarification Q3). Satisfies FR-001, FR-002, FR-004 / SC-001. Proves T1.
- [X] T004 [US1] Add `T-D5-02 stream_normalization` to `ai-platform/test/deepseek-adapter.test.ts` (adapter fixtures): feed a recorded provider stream pair from `ai-platform/test/fixtures/deepseek/stream/` through the injectable buffered transport; invoke; assert port `chunks` are `CanonicalStreamChunk` with no provider-shaped field names (`assertNoProviderShapedFieldNames`); assert content, order, assembly, and exactly one empty `text_delta` terminal via `assertExactlyOneTerminal` (§4.3.8; §3.11.4 D5). Satisfies FR-001, FR-004 / SC-001. Proves T2.
- [X] T005 [US1] Add `T-D5-03 usage_extraction` to `ai-platform/test/deepseek-adapter.test.ts` (adapter fixtures): feed a recorded usage-bearing response from `ai-platform/test/fixtures/deepseek/usage/` through the injectable transport; invoke; assert concrete usage counters (incl. `prompt_cache_hit_tokens` → `cached`) on the result / usage chunk; assert absent-usage path yields zero-filled counters + `provider_note` `{ note: "usage_absent" }`; assert measured (non-fabricated-zero) `provider_ms` (§4.3.8; §3.11.4 D5). Satisfies FR-001, FR-004 / SC-001. Proves T3.
- [X] T006 [US1] Add `T-D5-04 provider_error_class_mapped_to_taxonomy` to `ai-platform/test/deepseek-adapter.test.ts` (adapter fixtures): one named subcase per DeepSeek wire error class in `contracts/first-real-provider-adapter.md` §3.1 — `auth_rejected` → `provider_rejected` (terminal), `rate_limited` → `rate_limited` (retryable), `provider_server_error` → `internal_error` (retryable), `content_filtered` → `provider_rejected` (terminal; structured type/code / finish_reason / explicit content-policy phrases; HTTP status wins over bare `"safety"`) — each driven by a recorded failure under `ai-platform/test/fixtures/deepseek/errors/`; assert taxonomy code and D2 retryability via `classifyFailure` / `setRetryabilityFromClassification`; cover mid-stream error frames and finish-reason `content_filter` / `insufficient_system_resource`; no new taxonomy codes (§4.3.8; §3.11.4 D5; §3.10). Satisfies FR-005 / SC-002. Proves T4.
- [X] T007 [US1] Add `T-D5-05 malformed_response` to `ai-platform/test/deepseek-adapter.test.ts` (adapter fixtures): feed a recorded malformed JSON body **and** a malformed SSE data-line fixture from `ai-platform/test/fixtures/deepseek/malformed/`; assert the outcome is port `malformed` / a classified canonical error — not an unclassified throw and not silent skip-success (§4.3.8; §3.11.4 D5). Satisfies FR-004 / SC-002. Proves T5.
- [X] T008 [US1] Add `T-D5-06 truncated_response` to `ai-platform/test/deepseek-adapter.test.ts` (adapter fixtures): feed recorded truncated cases from `ai-platform/test/fixtures/deepseek/truncated/` — `finish_reason: length` **and** SSE cut without `[DONE]` / `finish_reason`; assert port `truncation` without inventing a new taxonomy code (§4.3.8; §3.11.4 D5). Satisfies FR-004 / SC-002. Proves T6.
- [X] T009 [US1] Add `T-D5-07 timeout` to `ai-platform/test/deepseek-adapter.test.ts` (adapter fixtures): drive the adapter-owned timeout path with a recorded/simulated deadline-exceeded harness input from `ai-platform/test/fixtures/deepseek/timeout/` (or transport that never resolves within the remaining-ms deadline); assert classification into taxonomy `timeout` with D2 retryability and that the transport's abort `signal` fired; include a resolves-within-deadline async path (§4.3.8; §3.11.4 D5). Satisfies FR-006 / SC-002. Proves T7.
- [X] T010 [US1] Add `T-D5-08 credentials_absent_from_logs_and_journal` to `ai-platform/test/deepseek-adapter.test.ts` (adapter fixtures, spy): inject fake secret store (Clarification Q4 amended); invoke across success, failure, timeout, malformed, credentials-missing, and stream paths; assert the known secret value appears in no returned `CanonicalError` payload and no captured wire artifact; missing-key path asserts `consumedBudget: false` (§4.3.8; §3.11.4 D5; Done when). Satisfies FR-007, FR-008 / SC-003. Proves T8.
- [X] T011 [US1] Add `T-D5-10 adapter_owns_no_logging_policy` to `ai-platform/test/deepseek-adapter.test.ts` (adapter fixtures, spy): assert the adapter does not own logging policy (no logger/journal sink options on constructor / export) and that credential assertions still satisfy T8 (§4.3.8; §3.10; D2 repair). Satisfies FR-003 / SC-004. Proves T10.

---

## Phase 2: Implementation (plan Files section)

**Purpose**: The two implementation units named in `plan.md` → Files that do not yet exist: `deepseek.ts` (DeepSeek adapter behind async `ProviderPort`) and `test/fixtures/deepseek/**` (recorded request/response and stream pairs). Consumed modules (`provider/port.ts`, `classify.ts`, `fake.ts`, `contracts/canonical.ts`, `errors.ts`) are imported, not modified (delivery plan §2.3). Contracts are already frozen. Tests turn green in matching groups per the plan's Sequencing: T9/T11 with adapter skeleton + injectable ports; T1 with request mapping; T2/T3 with stream/usage; T4–T7 with error/malformed/truncated/timeout paths; T8/T10 with credential/wire spies (no logger/journal sinks).

- [X] T012 [US1] Create `ai-platform/src/provider/deepseek.ts` — `DeepSeekAdapter` implements D2 async `ProviderPort`. Constructor takes injectable transport/fetch and secret-store ports only (Clarifications Q3–Q4 amended) — no logger/journal sinks. Owns authentication (Authorization from secret store binding name `DEEPSEEK_API_KEY` in production wiring), canonical ↔ DeepSeek wire request/response mapping (stream requests set `stream_options.include_usage`), stream-chunk normalization onto port `chunks` (exactly one empty `text_delta` terminal), provider-specific structured-output *wire* mechanics (pipeline `structured` / `structured_atomic` remain D6), adapter-owned timeouts (remaining-ms `deadline` min'd with `timeoutMs`; caller `signal` combined; abort on timeout; no busy-wait), measured `provider_ms`, usage mapping (`prompt_cache_hit_tokens` → `cached`; absent → `usage_absent` note), and classification of every failure via D2 `classifyFailure` / `setRetryabilityFromClassification` (HTTP status wins; finish-reason / SSE malformed / stream-cut / mid-stream error rules per contract §3.2–§3.4; missing key → `consumedBudget: false`; no new taxonomy codes). Export surface exposes no retry or fallback decision API. Fixture transport is buffered (full-body string, post-hoc SSE parse). Exactly one real provider in this module (`provider_id: deepseek`); do not fold a second provider. No per-request server-side state; no Quota DO / D1 / R2 I/O. **Satisfies**: FR-001–FR-009; **proved by**: T1–T11 (T-D5-01..11).
- [X] T013 [P] [US1] Create recorded fixtures under `ai-platform/test/fixtures/deepseek/` — directories and files for `request-mapping/` (canonical request + outbound wire golden for T1, incl. `include_usage`), `stream/` (provider stream pairs for T2), `usage/` (usage-bearing and usage-absent responses for T3), `errors/` (one recorded failure per §3.1 wire error class for T4, plus finish-reason / mid-stream cases), `malformed/` (JSON + SSE for T5), `truncated/` (`length` + stream-cut for T6), and `timeout/` (T7 harness input). Fixtures are the permanent proof — no live provider egress; bodies are full-string recordings (FR-004, FR-005; Clarification Q3; Deviation 4; delivery plan §3.5 Done when). **Satisfies**: FR-004, FR-005; **proved by**: T1–T7 (T-D5-01..07). Independent of T012's source file (different paths) once test stubs exist.

---

## Phase 3: Verification

**Purpose**: Delivery plan §3.10 — every prior suite stays green alongside the new one, not just the latest.

- [X] T014 [US1] From `ai-platform/`, run `npx vitest run test/deepseek-adapter.test.ts` (this slice's named cases, all under the default Node pool — D5 is CPU-only with injectable transport and secret store), then run the full prior suite — `npx vitest run` (default Node-pool prior suites including `deepseek-adapter.test.ts` (D5), `stream-broker.test.ts` (D4), `invocation.test.ts` (D3), `provider-port.test.ts`, `router.test.ts` (D2), `prompt-registry.test.ts`, `prompt-composer.test.ts` (D1), `manifest.test.ts` (A4), `canonical.test.ts` (A3), `taxonomy.test.ts`, `reference.test.ts`, `error-body.test.ts`, `trace.test.ts`, `log-redaction.test.ts` (A2), `health.test.ts`, `env-deploys.test.ts` (A1), `context-validator.test.ts` (C2)) and `npx vitest run --config vitest.workers.config.ts` (workers-pool prior suites: `control.test.ts` (B2), `identity.test.ts`, `entitlement.test.ts`, `rate-limit.test.ts` (B3), `admission-credit.test.ts`, `quota-do.test.ts` (B4), `capability.test.ts` (C1), `journal.test.ts` (C3); `context.test.ts`, `config-cache.test.ts`, `migrations.test.ts` (A5); `adapter.test.ts` (A6)). Confirm every prior suite stays green. No new test is added here — this is the §3.10 checkpoint gate. **Satisfies**: the §3.10 checkpoint rule (wire mapping, stream normalization with empty terminal, usage extraction / `usage_absent`, one case per mapped error class, malformed JSON/SSE, truncated length/stream-cut, timeout with abort, credential absence / `consumedBudget: false` spies, no retry/fallback/logging-policy ownership). Proved by itself.

---

## Phase 4: Documentation

**Purpose**: Always present. The one documentation artifact the plan names that does not yet exist on disk (`quickstart.md`); written only after the suite is green. Contracts were already frozen during the plan phase.

- [X] T015 [US1] Create `specs/032-first-real-provider-adapter/quickstart.md` from `.specify/templates/ai-platform-quickstart-template.md`, scoped to this slice only. **§1 Architecture context** — delivery plan §3.5 row D5; `01-ai-platform.md` §4.3.8; what the spec delivered; what the plan scoped. **§2 What was implemented** — DeepSeek real adapter behind the D2 port (`src/provider/deepseek.ts`); recorded-fixture suite under `test/fixtures/deepseek/`; secret-store credential path with absence spy; frozen `contracts/first-real-provider-adapter.md`. **§3 Files to review** — only this slice's source, fixture, test, and contract files (`ai-platform/src/provider/deepseek.ts`, `ai-platform/test/deepseek-adapter.test.ts`, `ai-platform/test/fixtures/deepseek/`, `specs/032-first-real-provider-adapter/contracts/`). **§4 Prerequisites** — omit or keep minimal (`cd ai-platform && npm install` first time); CPU-only tests, no miniflare / live-provider bindings required for this slice. **§5 Run the automated suite** — `cd ai-platform && npx vitest run test/deepseek-adapter.test.ts`; slice-only (no full-suite `npm test`). **§6 Inspect the changes** — read the frozen contract; open `provider/deepseek.ts`; run the focused test file. **No §7** — CI is the only verification path (permanent suite uses recorded fixtures, not live egress). **Slice-only scope explicit**: no prior-slice files in the review table, no combined test counts, no prior-slice regression commands. Not traced to an FR (template-mandated review surface).

---

## Dependencies & Execution Order

### Phase Dependencies

- **Tests (T001–T011)** — none beyond already-frozen contracts and Consumes Binding modules; written to fail before the code exists. All append to the same file (`deepseek-adapter.test.ts`), so they are sequential (T001 creates the substrate; T002–T011 append).
- **Implementation (T012–T013)** — after tests exist. T012 (`deepseek.ts`) and T013 (fixtures) are different paths and are `[P]`-eligible relative to each other once T001+ exist. Tests turn green in matching groups per the plan's Sequencing.
- **Verification (T014)** — depends on T001–T013; runs the whole suite (this slice + every prior slice) per §3.10.
- **Documentation (T015)** — depends on T014 (the quickstart records a green suite).

### Within the Slice

- Tests written to fail before implementation; implementation makes them pass; verification confirms the whole suite including prior slices stays green.
- Adapter skeleton + injectable ports (T012) unlock T9/T11 first; request mapping unlocks T1; stream/usage unlock T2/T3; error paths unlock T4–T7; credential/wire spies unlock T8/T10 — matching plan Sequencing without splitting the Files-section units into extra tasks.
- Fixtures (T013) unlock golden/stream/error file loads for T1–T7.

### Parallel Opportunities

- Phase 1: T001–T011 all touch `deepseek-adapter.test.ts` — sequential; no `[P]` inside the test phase.
- Phase 2: T013 (`test/fixtures/deepseek/**`) is `[P]` relative to T012 (`src/provider/deepseek.ts`) — different files, no import dependency between fixture JSON/text and the adapter module source.
- Phase 4 (T015) is a single task — no `[P]`.

---

## Notes

- [P] tasks = different files, no dependencies. Only T013 is marked `[P]` (fixtures vs adapter source).
- Every named test T1–T11 from `spec.md` is covered by its own task; spy cases are not folded into outcome cases.
- Every task traces to an `FR-###` from `spec.md` (tests also state the `SC-###` they satisfy) — no task adds a requirement the spec does not name.
- No Polish phase and no Foundational phase — prerequisites are the already-merged slices in the plan's Consumes Binding (D2; A3/A2 via D2).
- Consumed modules are imported, not modified (delivery plan §2.3 — extend, never rewrite). Pipeline registration of DeepSeek into the live Worker request path is out of scope (fixture suite is the permanent proof).
- Tests land before or alongside their implementation, never after (delivery plan §2.2).
- Preserve the I/O budget: no DO, D1, or R2 I/O from this slice; permanent suite uses recorded fixtures with injectable buffered transport (§4.3.8, §4.4, §7.5, §13.6).
- **Review resolution (2026-08-04):** Implementation and suite amended in place under T001–T013 evidence — empty terminal; SSE malformed/truncation/mid-stream error; finish-reason mapping; HTTP status wins; missing-key `consumedBudget: false`; `include_usage` / `cached` / `usage_absent`; measured `provider_ms`; abort on timeout; no logger/journal sinks (D2 repair); buffered fixture transport; remaining-ms deadline. Spec/contract/plan updated to match; no new task IDs.
