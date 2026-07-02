---
description: "Task list for AI Layer Foundation — Isolated Gateway Spine + Model Runner (015)"
---

# Tasks: AI Layer Foundation — Isolated Gateway Spine + Model Runner

**Input**: Design documents from `/specs/015-ai-layer-foundation/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/ (all present)

**Tests**: INCLUDED. The spec and plan make a heavy `pytest` suite central to this feature and
several behaviors are constitution-sensitive (offline auth matrix, AI↔DB isolation scan, health
honesty, PHI-redaction). Test tasks are therefore first-class, not optional.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies on incomplete tasks)
- **[Story]**: Which user story this task belongs to (US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions

- **AI Gateway (Python 3.12 / FastAPI)**: `ai/gateway/src/gateway/`, tests in `ai/gateway/tests/`
- **Model Runner (vanilla Ollama)**: `ai/runners/ollama/`
- No Flutter, Supabase, or PostgreSQL code changes in this feature (isolation invariant)

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Create the isolated `ai/` tree and the Python Gateway project skeleton

- [X] T001 Create the isolated `ai/` tree structure per plan.md (directories: `ai/gateway/src/gateway/{config,api,auth,routing,runners,obs}`, `ai/gateway/{config,scripts,tests/{unit,contract,fixtures}}`, `ai/runners/ollama/`)
- [X] T002 Initialize the Gateway Python 3.12 project in `ai/gateway/pyproject.toml` with pinned runtime deps (`fastapi`, `uvicorn`, `httpx`, `pyjwt`, `cryptography`, `pydantic>=2`, `pydantic-settings`, `pyyaml`, `prometheus-client`, `structlog`) and dev deps (`pytest`, `pytest-asyncio`, `respx`, `ruff`)
- [X] T003 [P] Configure `ruff` (lint + format) and `pytest`/`pytest-asyncio` settings inside `ai/gateway/pyproject.toml`
- [X] T004 [P] Create `ai/README.md` documenting the AI layer overview and the three security invariants (AI proposes only / no clinic-DB creds / manual UI works with AI down)
- [X] T005 [P] Create the Gateway `ai/gateway/Dockerfile` (Python 3.12 base, least-privilege non-root user, `restart: always`-friendly entrypoint running Uvicorn on `8090`) per FR-005/FR-022

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core plumbing every user story depends on — typed config, uniform error contract, observability, ASGI bootstrap, and shared test harness

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [X] T006 Implement `GatewayConfig`, `RunnerConfig`, and `ModelDef` pydantic-settings models with fail-fast validation (port range, ≥1 of `jwt_secret`/`jwks_url`, no `*` in `allowed_origins`, `internal_shared_secret` required when push enabled, unknown-key/type errors naming the key) in `ai/gateway/src/gateway/config/settings.py` (FR-003/FR-004, data-model §1)
- [X] T007 [P] Create `ai/gateway/config/gateway.example.yaml` documenting every §14 config key with its default (data-model §1)
- [X] T008 Implement the typed `ErrorEnvelope` (`{error:{code,message,request_id}}`) and FastAPI exception handlers covering `bad_request`/`unauthenticated`/`forbidden`/`not_implemented`/`rate_limited`/`ai_no_capacity`/`ai_timeout` with the §10.4 code↔status map in `ai/gateway/src/gateway/api/errors.py` (FR-020, contracts/error-contract.md)
- [X] T009 [P] Implement `structlog` JSON logging to local rotating files with a PHI-redaction processor (active unless `log_verbatim=true`) and the `LogRecord` field set in `ai/gateway/src/gateway/obs/logging.py` (FR-033/FR-034, data-model §7)
- [X] T010 [P] Implement Prometheus collectors (request rate, error rate by code, per-runner health/latency, in-flight) in `ai/gateway/src/gateway/obs/metrics.py` (FR-035)
- [X] T011 Implement the ASGI app bootstrap in `ai/gateway/src/gateway/main.py`: load config, install exception handlers, CORS allowlist middleware (no wildcard), per-request `request_id` middleware, `lifespan` hook to start/stop the health poller, and mount `GET /metrics` (FR-021/FR-035)
- [X] T012 [P] Create the shared test harness `ai/gateway/tests/conftest.py` with an in-process ASGI client (`httpx.ASGITransport`) and config fixtures
- [X] T013 [P] Create the scriptable fake runner fixture in `ai/gateway/tests/fixtures/fake_runner.py` that can return `ok(latency,model)`/`loading`/`error`/`timeout` poll outcomes on demand to drive lifecycle walks

**Checkpoint**: Foundation ready — user story implementation can now begin

---

## Phase 3: User Story 1 - Stand up an isolated, health-reportable AI layer (Priority: P1) 🎯 MVP

**Goal**: A running, isolated Gateway + one Model Runner where liveness is honest immediately and readiness turns positive only once a runner has loaded its model, provably separated from the clinic DB and non-client-routable.

**Independent Test**: Start the Gateway + one runner; `/health` returns healthy immediately, `/ready` turns positive only after the model loads; the isolation scan finds zero DB creds/drivers; the runner refuses connections from a client subnet.

### Tests for User Story 1 ⚠️

> Write these tests FIRST and confirm they FAIL before implementation.

- [ ] T014 [P] [US1] Isolation-scan contract test asserting a clean tree passes and a planted DB credential/driver import fails, in `ai/gateway/tests/contract/test_isolation.py` (SC-005, FR-002)
- [ ] T015 [P] [US1] Liveness/readiness contract test: `/health` = 200 always; `/ready` = 200 only when ≥1 runner READY, else 503 envelope, in `ai/gateway/tests/contract/test_health.py` (SC-002)
- [ ] T016 [P] [US1] Runner non-routability contract test asserting the runner binds AI-internal only and refuses a client-subnet origin, in `ai/gateway/tests/contract/test_runner_contract.py` (SC-008, FR-010)
- [ ] T017 [P] [US1] Lifecycle transition unit tests for the pure `(status, outcome, counters, config) → next_status` function incl. `UNKNOWN→STARTING→READY` and `→UNREACHABLE` after 3 failures, in `ai/gateway/tests/unit/test_lifecycle.py` (FR-025, data-model §3)
- [ ] T018 [P] [US1] Config fail-fast unit test: valid config parses with defaults; invalid key/type and missing auth material fail fast naming the key, in `ai/gateway/tests/unit/test_config.py` (SC-009, FR-004)

### Implementation for User Story 1

- [ ] T019 [P] [US1] Implement the OpenAI-compatible runner poll client (`GET /v1/models` and optional `/health`, bounded ≤2s timeout, capture loaded model id+digest+context) in `ai/gateway/src/gateway/runners/openai_client.py` (FR-006/FR-013, contracts/runner-poll.md)
- [ ] T020 [P] [US1] Implement the pure runner lifecycle transition function (`UNKNOWN→STARTING→READY→UNREACHABLE`, failure counting) in `ai/gateway/src/gateway/routing/lifecycle.py` (FR-025)
- [ ] T021 [US1] Implement the in-memory `RunnerRegistryEntry` registry (status, last-seen, latency, loaded model, consecutive failures) with atomic reads and a `ready == any(READY)` derivation in `ai/gateway/src/gateway/routing/registry.py` (FR-023/FR-024, data-model §2)
- [ ] T022 [US1] Implement the pull-based health poller loop (per-runner cadence `health_poll_interval_s`, updates registry via lifecycle+poll client) in `ai/gateway/src/gateway/routing/health_poller.py`, started from the `main.py` lifespan (FR-023)
- [ ] T023 [US1] Implement `GET /health` (unauthenticated liveness) and `GET /ready` (readiness = ≥1 READY runner, else 503 envelope) in `ai/gateway/src/gateway/api/health.py` (FR-014)
- [ ] T024 [US1] Implement the isolation scan (static import + secret/service-role pattern scan over `ai/`, non-zero exit on any hit) in `ai/gateway/scripts/isolation_scan.py` (FR-002, SC-005)
- [ ] T025 [P] [US1] Create `ai/runners/ollama/docker-compose.yaml` binding Ollama to `127.0.0.1:11434` with `restart: always` (FR-010/FR-005)
- [ ] T026 [P] [US1] Create `ai/runners/ollama/Modelfile` defining the default Qwen3-4B Q4_K_M model (FR-008)
- [ ] T027 [P] [US1] Create `ai/runners/ollama/digests.md` recording the pinned model `sha256:` digest (FR-008, §11.6)
- [ ] T028 [P] [US1] Create `ai/runners/README.md` runbook: model install via pull and via local GGUF path, model store location, and digest pinning (FR-012)

**Checkpoint**: US1 is independently deployable and testable — the isolated AI spine is up and honest.

---

## Phase 4: User Story 2 - Authenticate and authorize every AI caller (Priority: P2)

**Goal**: Every protected endpoint is gated by offline Supabase-JWT validation (HS256 and JWKS) plus a coarse `ai.access` role check, with a consistent typed error contract, no network call to Supabase.

**Independent Test**: Run the token matrix (valid / tampered / expired / not-yet-valid / missing / valid-but-no-`ai.access`) against a protected endpoint under BOTH validation configs; each maps to the correct 200/401/403; confirm zero Supabase network calls.

### Tests for User Story 2 ⚠️

> Write these tests FIRST and confirm they FAIL before implementation.

- [ ] T029 [P] [US2] Auth matrix contract test run under BOTH HS256 and JWKS configs (valid/tampered/expired/nbf-future/missing/no-`ai.access`) asserting 200/401/403 with zero Supabase network calls, in `ai/gateway/tests/contract/test_auth_matrix.py` (SC-004/SC-010)
- [ ] T030 [P] [US2] Role-map reload unit test: changing the role→`ai.access` map is reflected atomically in subsequent decisions, in `ai/gateway/tests/unit/test_role_map.py` (FR-018)
- [ ] T031 [P] [US2] Error-contract test: authentication (401) precedes authorization (403); every failure body carries stable `code`, `message`, and `request_id`, in `ai/gateway/tests/contract/test_error_contract.py` (FR-020, contracts/error-contract.md)

### Implementation for User Story 2

- [ ] T032 [P] [US2] Implement offline JWT validation supporting HS256 (`jwt_secret`) and JWKS (`jwks_url`, `PyJWKClient` with local cache), validating signature + `exp` + `nbf`, extracting `CallerIdentity`, with documented JWKS precedence, in `ai/gateway/src/gateway/auth/jwt_validator.py` (FR-015/FR-016, data-model §4)
- [ ] T033 [P] [US2] Implement the reloadable role→`ai.access` map (file-watch/SIGHUP/periodic re-read, atomic swap) in `ai/gateway/src/gateway/auth/role_map.py` (FR-017/FR-018, data-model §5)
- [ ] T034 [US2] Implement the FastAPI auth dependency wiring `jwt_validator` + `role_map` into a single gate emitting typed `unauthenticated`/`forbidden` outcomes (depends on T032, T033)
- [ ] T035 [US2] Apply the auth gate to all client-facing endpoints except `/health` and `/metrics` (protect `/ready`, `/v1/capabilities`, `/v1/ai/generate`) in `ai/gateway/src/gateway/api/` (FR-019)

**Checkpoint**: US1 and US2 both work independently — the front door is locked with a tested typed contract.

---

## Phase 5: User Story 3 - Discover, monitor, and route among Model Runners (Priority: P3)

**Goal**: The Gateway tracks every configured runner through the full lifecycle, applies capability→health→least-busy routing selection, and reports aggregate capabilities mirroring the live registry; the generate route is a feature-detectable 501 stub.

**Independent Test**: Point the Gateway at scripted fake runners; confirm the registry reflects each lifecycle transition, readiness flips negative when all runners are unreachable and recovers, a runner missing a required capability is excluded from selection, and `/v1/capabilities` mirrors the registry.

### Tests for User Story 3 ⚠️

> Write these tests FIRST and confirm they FAIL before implementation.

- [ ] T036 [P] [US3] Registry/failover integration test using `fake_runner` to walk the full lifecycle (incl. DEGRADED/BUSY/recovery) and assert `/ready` flips 503 when all UNREACHABLE and recovers, in `ai/gateway/tests/contract/test_registry_failover.py` (SC-003, FR-025)
- [ ] T037 [P] [US3] Selector unit tests: capability match (required), health filter (READY preferred, DEGRADED deprioritized, exclude STARTING/UNREACHABLE), least-busy with round-robin tie-break, in `ai/gateway/tests/unit/test_selector.py` (FR-026/FR-027)
- [ ] T038 [P] [US3] Capabilities-mirror contract test asserting `/v1/capabilities` matches the live registry (per-runner status/model/digest/features/context) with empty `tasks`/`commands`, in `ai/gateway/tests/contract/test_capabilities.py` (SC-006/SC-011)
- [ ] T039 [P] [US3] Generate-stub contract test asserting `POST /v1/ai/generate` always returns 501 `not_implemented` and performs zero inference, in `ai/gateway/tests/contract/test_generate_stub.py` (SC-011, FR-031)

### Implementation for User Story 3

- [ ] T040 [US3] Extend `ai/gateway/src/gateway/routing/lifecycle.py` with the remaining edges (READY↔BUSY, READY↔DEGRADED on elevated latency/sporadic errors, DEGRADED→UNREACHABLE, UNREACHABLE→STARTING recovery) (FR-025, data-model §3)
- [ ] T041 [US3] Implement runner selection (capability match → health filter → least-busy + round-robin tie-break; clients cannot select runner addresses) in `ai/gateway/src/gateway/routing/selector.py` (FR-026/FR-027/FR-028)
- [ ] T042 [US3] Implement `GET /v1/capabilities` and the report builder that mirrors the registry with `tasks:[]`/`commands:[]` while generation is stubbed in `ai/gateway/src/gateway/api/capabilities.py` (FR-029/FR-031)
- [ ] T043 [US3] Implement the `POST /v1/ai/generate` stub returning 501 `not_implemented` (no inference) in `ai/gateway/src/gateway/api/generate_stub.py` (FR-031)

**Checkpoint**: All user stories are independently functional — the control plane discovers, monitors, routes (in test), and advertises capabilities.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Observability wiring, security hardening, and end-to-end verification across all stories

- [ ] T044 [P] Emit per-request and per-runner metrics/log records across endpoints and the poller (request rate, error rate by code, per-runner health/latency, in-flight) via the `obs/` modules (FR-035/FR-033)
- [ ] T045 [P] PHI-redaction verification unit test asserting patient-name fixtures never appear verbatim in logs when `log_verbatim=false`, in `ai/gateway/tests/unit/test_redaction.py` (SC-012, FR-034)
- [ ] T046 [P] Implement optional push registration (`/internal/runners/register|heartbeat`) behind `enable_push_registration` (default off), guarded by `internal_shared_secret`, AI-internal only, in `ai/gateway/src/gateway/routing/registry.py` (FR-030)
- [ ] T047 Security hardening pass: confirm least-privilege OS account / filesystem scope (config, log dir, model store only) in Dockerfile/compose and supervised auto-restart (FR-022/FR-005)
- [ ] T048 Run the developer/CI gate from quickstart §5: `ruff check`, `isolation_scan.py`, and full `pytest` suite all green
- [ ] T049 [P] Validate `quickstart.md` operator happy path end-to-end (deploy, `/health`, `/ready`, `/v1/capabilities`, 501 stub, `/metrics`, failover) and reconcile any drift
- [ ] T050 Review constitution compliance for the final architecture (isolation scan gates build, runner non-routable, no DB objects, generate stubbed, PHI-minimized logs, both JWT modes offline)

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — start immediately
- **Foundational (Phase 2)**: Depends on Setup — BLOCKS all user stories
- **User Stories (Phase 3–5)**: All depend on Foundational
  - US1 (P1) is the MVP and should be delivered first
  - US2 (P2) depends on Foundational; integrates with US1 endpoints but is independently testable
  - US3 (P3) depends on Foundational and reuses US1's registry/lifecycle/poller; independently testable with fake runners
- **Polish (Phase 6)**: Depends on the desired user stories being complete

### User Story Dependencies

- **US1 (P1)**: Foundational only. No dependency on other stories.
- **US2 (P2)**: Foundational only. Protects US1's endpoints but its auth logic is independently testable against any protected route.
- **US3 (P3)**: Foundational + reuses US1's `registry`/`lifecycle`/`health_poller` (extended here). Independently testable via `fake_runner`.

### Within Each User Story

- Tests are written first and must FAIL before implementation
- `lifecycle`/`registry`/`poll client` before `health_poller` before `health` endpoints (US1)
- `jwt_validator` + `role_map` before the auth dependency before applying it to endpoints (US2)
- `lifecycle` edges + `selector` before `capabilities` reporting (US3)

### Parallel Opportunities

- All `[P]` Setup tasks (T003–T005) can run together
- Foundational `[P]` tasks (T007, T009, T010, T012, T013) can run together after T006
- All `[P]` test tasks within a story can run together before that story's implementation
- US1 `[P]` implementation files (T019, T020 and the runner-tree files T025–T028) can run together
- US2 `[P]` implementation files (T032, T033) can run together
- Once Foundational completes, US1/US2/US3 can be staffed in parallel (US3 coordinates on the shared registry files with US1)

---

## Parallel Example: User Story 1

```bash
# Launch all US1 tests together (write first, expect FAIL):
Task: "Isolation-scan contract test in ai/gateway/tests/contract/test_isolation.py"
Task: "Liveness/readiness contract test in ai/gateway/tests/contract/test_health.py"
Task: "Runner non-routability contract test in ai/gateway/tests/contract/test_runner_contract.py"
Task: "Lifecycle transition unit tests in ai/gateway/tests/unit/test_lifecycle.py"
Task: "Config fail-fast unit test in ai/gateway/tests/unit/test_config.py"

# Launch independent US1 implementation files together:
Task: "Runner poll client in ai/gateway/src/gateway/runners/openai_client.py"
Task: "Lifecycle transition function in ai/gateway/src/gateway/routing/lifecycle.py"
Task: "Ollama docker-compose in ai/runners/ollama/docker-compose.yaml"
Task: "Modelfile in ai/runners/ollama/Modelfile"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup
2. Complete Phase 2: Foundational (CRITICAL — blocks all stories)
3. Complete Phase 3: User Story 1
4. **STOP and VALIDATE**: Gateway + runner up, `/health` immediate, `/ready` honest, isolation scan green, runner non-routable
5. Deploy/demo the isolated spine

### Incremental Delivery

1. Setup + Foundational → foundation ready
2. Add US1 → isolated, health-honest AI layer (MVP!)
3. Add US2 → authenticated, authorized front door with typed errors
4. Add US3 → discovery, routing selection, capabilities report + generate stub
5. Polish → observability wiring, PHI-redaction proof, push mode, CI gate, quickstart validation

### Parallel Team Strategy

1. Team completes Setup + Foundational together
2. Then:
   - Developer A: US1 (spine + runner tree + isolation)
   - Developer B: US2 (auth)
   - Developer C: US3 (routing/capabilities, coordinating on shared registry files with A)
3. Stories integrate independently; run the CI gate (T048) before merge

---

## Notes

- `[P]` tasks = different files, no dependencies
- `[Story]` label maps each task to its user story for traceability
- Verify tests FAIL before implementing
- Commit after each task or logical group
- Preserve the isolation invariant: nothing in `ai/` may import or hold clinic-DB creds/drivers (T024 gates this)
- The runner stays non-client-routable and holds no DB access; the Gateway validates JWTs offline only
- No functional AI generation this phase — the generate route is a 501 stub and capabilities advertise no tasks
