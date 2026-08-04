# Implementation Plan: Journal writer, post-response detail, and get-request endpoint (C3)

**Branch**: `ai/027-c3-journal-writer-get-request` | **Date**: 2026-08-01 | **Spec**: [`spec.md`](./spec.md)

**Input**: Feature specification from `specs/027-journal-writer-get-request/spec.md`

**Note**: Filled in by the `/ai-platform-plan` command. The AI platform variant adds five sections (`## Consumes Binding`, `## Components Touched`, `## Files`, `## Test Layout`, `## Sequencing`) and never produces `research.md`.

## Summary

C3 makes the journal the audit backbone of the gateway: it creates the durable `ai_request` row synchronously at stage 9 before any inference work begins, stamps every §6.3 state transition (each transition overwrites `state` and stamps `updated_at`; the terminal one — including `AwaitingContext` — also stamps `completed_at`; writers no-op when already terminal), updates the row with its terminal state at stage 15 (`Failed` requires a taxonomy code), and writes the per-attempt `ai_attempt` rows, exactly one `usage_event` ledger row, and exactly one R2 payload envelope (JSON, keyed `request/{id}/envelope`, four sections `context`/`prompt`/`attempts[]`/`result`) in a `ctx.waitUntil` post-response continuation at stage 16 whose failure is logged via `console.error` and never fails the already-completed request (attempt+usage_event via `db.batch`). A guard rejection produces no row (counting owned by rate-limit/admission). Through the authenticated get-request endpoint (`Authorization: Bearer <AAT>`, §5.6 / B3 `EnrolledKeyVerifier`, scoped to `principal.installationId`), a request reference resolves — through one indexed D1 lookup on `request_reference` — to the journaled state and, for a completed request with a readable envelope, the validated result fetched from the envelope's `result` section (GetObject only when `payload_pointer` is non-null; completed-without-envelope → state only; in-flight → `{ state, pending: true }`). The slice sits in band C, after A5 froze the D1 schema and C1 froze the resolved manifest, and before D3/D4/D6 feed the writer per-attempt and validated-result data and F3 consumes the frozen journal and envelope (delivery plan §3.4, row C3).

## Technical Context

**Language/Version**: TypeScript (Cloudflare Workers runtime); `@cloudflare/workers-types` ^4.20250730.0; vitest ~3.2.4 with `@cloudflare/vitest-pool-workers` 0.8.71.

**Primary Dependencies**: `ai-platform/src/identity` (B3 — `Principal`), `ai-platform/src/manifest` (A4 — `Manifest`, `EconomicsGroup`), `ai-platform/src/capability` (C1 — `ResolveResult`), `ai-platform/src/errors` (A2 — `TaxonomyCode`, `buildErrorBody`, `liveHttpStatusForCode`), `ai-platform/src/reference` (A2 — `normalizeRequestReference`), `ai-platform/src/contracts/canonical` (A3 — `CanonicalResult`). No new dependency is introduced.

**Storage**: D1 (`ai_request`, `ai_attempt`, `usage_event`, `platform_counter`, and `idx_ai_request_request_reference`, all frozen by A5) and R2 (one object per request keyed `request/{id}/envelope`). C3 performs one D1 insert at stage 9 (including optional `routing_tier`), one D1 update per transition (conditional on non-terminal current state), one D1 update at stage 15, and the stage-16 continuation writes N `ai_attempt` inserts + one `usage_event` insert via `db.batch` + one R2 `PutObject` + one `ai_request` update setting `payload_pointer`. No Durable Object I/O (the stage-15 credit call is B4's contract; C3 updates the journal row only). No per-request server-side state (§4.4, §9.7).

**Testing**: vitest integration (ordering + spy) tests in `ai-platform/test/journal.test.ts`, running under `vitest.workers.config.ts` against real D1 + R2 (miniflare), driving the journal writer and post-response continuation with fixture inputs and a fake provider, plus spy assertions on D1/R2 call counts per §3.10. The file is added to the workers-config include list and the unit-config exclude list (it needs real bindings, unlike C2's CPU-only suite).

**Target Platform**: Cloudflare Workers (the `ai-platform/` gateway); no Flutter, no Supabase. The get-request endpoint is wired as `GET /v1/requests/{reference}` in `worker.ts`; the stage-9/15/16 writer functions are exported for the later orchestrator slice to call (matching B3/C1/C2 precedent).

**Project Type**: Additive, non-primary Worker module — one §4 component (§4.3.11 journal writer) plus its §5.5 get-request read endpoint. Per the §14 acknowledgement: no domain logic, no business data, no write path into Supabase, always optional.

**Performance Goals**: One D1 insert on the request path (stage 9); stage 16 entirely post-response via `ctx.waitUntil`, off the hot path (§6.1, §7.5). At clinic volumes (tens of requests/day/clinic, §13.6.1) the metered footprint stays proportional to requests, not a multiple of them (§7.4.1).

**Constraints**: Stages 9/15/16 emit only `internal_error` (stage 9, on D1 insert failure, with `request_reference` and `trace_id`); stage 16 emits no error to the client by construction (§6.1). Terminal error codes written to the row are produced by D3/D4/D6 and recorded, not generated, by C3 (`Failed` requires a code). The envelope is JSON (Clarification Q1), one object per request (§7.4.1). Stage 16 runs via `ctx.waitUntil`, logs failures via `console.error`, and swallows them (Clarification Q3). Get-request is AAT-authenticated and installation-scoped. Contract extensions under delivery plan §2.3 add fields/cases without changing Completed-with-result / Failed / Cancelled success meanings. No mechanism from §9.14 (R-20).

**Scale/Scope**: Clinic-scale (§13.6.1); one row per request, 1–3 attempt rows per request, one envelope per request. No enterprise scale assumption.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- [x] Feature scope still fits small-to-mid-size multi-branch clinics; hospital-scale or
      enterprise-only requirements are explicitly rejected or separately ratified — the journal keeps one row per request and one R2 object per request, so the metered footprint stays proportional to requests at clinic volumes (§7.4.1, §7.5, §13.6.1). No enterprise scale assumption is introduced.
- [x] Design keeps a simple operational model with no microservices, message queues,
      Kubernetes, or custom primary backend service — C3 adds functions to one Worker and one GET route; no new deployable, no queue, no store beyond the platform's own D1/R2, no abstraction beyond the named stages and the one-envelope-per-request rule (R-20).
- [x] Layer ownership is explicit: Flutter handles UI/orchestration, Supabase handles
      backend capabilities, PostgreSQL owns domain integrity, and AI stays isolated — C3 touches only `ai-platform/` (the Worker) and its D1/R2 bindings; no `frontend/`, no `backend/`. The gateway is the §14-acknowledged additive, non-primary component with no domain logic, no business data, and no write path into Supabase.
- [x] Protected writes, validation, permissions, and transactional rules remain enforced
      through PostgreSQL constraints, triggers, RLS, or RPC functions — C3 writes only the platform's own D1 journal/ledger tables, which are not clinic business records; the `ai_request` unique index on `request_reference` (A5) enforces reference uniqueness. No Supabase-side enforcement is implicated.
- [x] Security remains authenticated, tenant-scoped, branch-scoped, permission-gated,
      auditable, and soft-delete-preserving — C3 consumes the immutable `Principal` (B3) and the request reference (A6) as read-only arguments; get-request verifies an AAT via §5.6 / B3 `EnrolledKeyVerifier` and scopes lookup to `principal.installationId`. It holds no secrets and writes no clinic audit row. The journal row is the platform's own audit of a request's life; a guard rejection produces no row (§6.2), so refusing abuse stays cheap. The get-request endpoint exposes only journaled state and the validated result (when available) — operator-only full-trace support lookup is F3, not C3 (§5.5).
- [x] AI actions remain human-approved, have no direct database/backend access, and the
      feature still works in a degraded manual mode when AI is unavailable — C3 is the recorder, not the producer, of AI content; it never reaches a provider and has no degraded mode of its own. The get-request endpoint degrades to not found for an unknown reference and to state-only for a cancelled request; it synthesizes nothing. When AI is unavailable the guard rejects before stage 9, so no journal row exists and clinic work continues without the AI affordance (§14 "V"; A11).

The Supabase/PostgreSQL row is structurally inapplicable to a Worker-only slice that writes only the platform's own D1 tables — recorded here rather than silently dropped, per the §14 acknowledgement. No Constitution Check violation requires Complexity Tracking.

## Project Structure

### Documentation (this feature)

```text
specs/027-journal-writer-get-request/
├── plan.md              # This file
├── spec.md              # /ai-platform-specify + /ai-platform-clarify output (authoritative)
├── contracts/
│   └── journal.md      # Frozen: R2 payload envelope (key + 4 JSON sections) + get-request response shape + journal write-path contract
└── quickstart.md        # Written during the implement-phase Documentation task (sections below)
```

`data-model.md` is **not** produced — C3 defines no new D1 entity and adds no column (spec `### Key Entities`: "C3 defines no new D1 entities"; the §6.3 amendment confirms the three milestone timestamps suffice). The schema is frozen by A5 and unchanged.

`research.md` is **never** produced on this platform — the research is `docs/architecture/17-ai-platform.md`; redoing it is how architecture drift starts.

`contracts/` is produced because the spec's **Freezes** entries have wire shapes later slices' **Consumes** bind to (F3 consumes the envelope layout; D3/D4/D6 feed the write-path contract; the client consumes the get-request response shape). The plan names the artifact; the implement phase writes it.

`quickstart.md` (written during the implement-phase Documentation task, per `.specify/templates/ai-platform-quickstart-template.md`) will contain:
- **§1 Architecture context** — C3 row of the delivery plan (§3.4) and the §4.3.11 / §6.1-stages-9-15-16 / §6.3 / §7.4 / §7.4.1 / §7.6 / §5.5 sections; what the spec delivered; what the plan scoped.
- **§2 What was implemented** — the `src/journal/index.ts` stage-9 insert + transition stamping + stage-15 terminal update + stage-16 post-response continuation (envelope builder, attempt rows, usage ledger) + the `getRequest` read function; the `worker.ts` `GET /v1/requests/{reference}` route.
- **§3 Files to review** — this slice's `ai-platform/src/journal/index.ts`, `ai-platform/src/worker.ts`, `ai-platform/test/journal.test.ts`, and `contracts/journal.md`.
- **§4 Prerequisites** — `cd ai-platform && npm install` (first time); the workers-pool tests need the miniflare D1/R2 bindings from `wrangler.toml` (already configured for prior slices).
- **§5 Run the automated suite** — `cd ai-platform && npx vitest run test/journal.test.ts --config vitest.workers.config.ts`, slice-only.
- **§6 Inspect the changes** — grep for the envelope key `request/{id}/envelope`, read the frozen `contracts/journal.md`, run a focused test file, query the `ai_request` row after a fixture run.
- No §7 — CI is the only verification path (C3 exposes no user-facing behaviour beyond the suite and the get-request route, which the suite covers end-to-end).

### Source Code (repository root)

```text
ai-platform/
├── src/
│   ├── journal/
│   │   └── index.ts        # NEW (this slice — FR-001..FR-012): createRequestRow (stage 9),
│   │                       #   journalTransition (§6.3 stamping), recordTerminalState (stage 15),
│   │                       #   writePostResponseDetail (stage 16, ctx.waitUntil, envelope builder inlined),
│   │                       #   getRequest (§5.5/§7.6 read endpoint)
│   ├── identity/           # UNCHANGED (consumed from B3 — Principal)
│   ├── manifest/           # UNCHANGED (consumed from A4 — Manifest, EconomicsGroup)
│   ├── capability/         # UNCHANGED (consumed from C1 — ResolveResult)
│   ├── errors.ts           # UNCHANGED (consumed from A2 — TaxonomyCode, buildErrorBody, liveHttpStatusForCode)
│   ├── reference.ts        # UNCHANGED (consumed from A2 — normalizeRequestReference)
│   ├── contracts/canonical.ts  # UNCHANGED (consumed from A3 — CanonicalResult)
│   └── worker.ts           # MODIFIED — adds GET /v1/requests/{reference} route (FR-010, FR-011)
├── test/
│   └── journal.test.ts     # NEW — T-C3-* integration (ordering + spy) tests (fixture inputs + fake provider + real D1/R2)
├── vitest.config.ts        # MODIFIED — adds test/journal.test.ts to exclude (it runs under the workers config)
└── vitest.workers.config.ts # MODIFIED — adds test/journal.test.ts to include (needs real D1 + R2)
```

The journal writer's stage-9/15/16 functions are exported and tested directly with fixtures + spies, mirroring how B3 tested `evaluateEntitlement`, C1 tested `resolve()`, and C2 tested `validateContext()` without wiring them into the POST pipeline — the pipeline-stage attachment belongs to a later orchestrator slice. The get-request endpoint, by contrast, is a standalone §5.5 read surface C3 freezes and owns, so it is wired as a `GET /v1/requests/{reference}` route in `worker.ts` and exercised through the `getRequest()` function. This keeps C3 to one §4 component (§4.3.11) plus its §5.5 read endpoint, and avoids reworking §4.3.1 (the adapter owns the submit stream).

**Structure Decision**: One new file under a new `ai-platform/src/journal/` directory — `index.ts` — holding all five exported functions and the inlined envelope builder (Clarification Q2: "a single `journal/` module, with the envelope builder inlined as an internal helper"). A new directory follows the one-dir-per-§4.3.x convention (matching `context/`, `capability/`, `quota-do/`). The two vitest configs are edited because this slice's tests need real D1 + R2 (unlike C2's CPU-only suite), so they must run under the workers pool and be excluded from the unit pool — the same split B4/C1 used for their D1-bound tests.

## Consumes Binding

| Consumes entry | Existing module / file / type it binds to | How C3 binds to it |
| --- | --- | --- |
| **A5** — D1 schema: `ai_request`, `ai_attempt`, `usage_event`, `platform_counter` entities, their field shapes, and the unique `idx_ai_request_request_reference` index (§7.3) | `ai-platform/migrations/20260731120000_platform_schema.sql` — the `ai_request` columns (request id, request reference, installation, actor, branch, capability id+version, prompt artifact hash, idempotency key, state, created_at, updated_at, completed_at, terminal_error_code, trace_id, payload_pointer, conversation_id, turn_ordinal), `ai_attempt`, `usage_event`, `platform_counter`, and `idx_ai_request_request_reference`. Frozen artifacts: `specs/019-ai-context-keys-d1-config/data-model.md`, `schema.snap.sql`. | C3's `createRequestRow` INSERTs the `ai_request` row with the frozen columns (FR-002), `journalTransition`/`recordTerminalState` UPDATE `state`/`updated_at`/`completed_at`/`terminal_error_code` (FR-003, FR-004), `writePostResponseDetail` INSERTs `ai_attempt` + `usage_event` and UPDATEs `payload_pointer` (FR-007, FR-008), and `getRequest` runs one indexed SELECT on `request_reference` (FR-010, FR-011). C3 adds no column and no table (the §6.3 amendment confirms the three milestone timestamps suffice) and changes no existing field shape. A5's migration is imported in the test, not modified. |
| **A2** — error taxonomy as a closed set; diagnostic envelope (request reference, trace id) (§5.4, §13.1, §13.2) | `ai-platform/src/errors.ts` — `TaxonomyCode` (includes `"internal_error"`), `buildErrorBody(input): ErrorBody`, `liveHttpStatusForCode(code)`. `ai-platform/src/reference.ts` — `normalizeRequestReference(input)`. Frozen artifact: `specs/016-ai-diagnostic-envelope/contracts/` (Clarification Q1 froze the body shape `{code, request_reference, trace_id, retry_safe}`). | C3's stage 9 emits `internal_error` on a D1 insert failure (FR-001) and returns it via `buildErrorBody` so the rejection body carries the request reference and trace id (§5.4). The get-request endpoint normalises the supplied reference via `normalizeRequestReference` before the indexed lookup (§8.9). C3 adds no code to the taxonomy and changes no HTTP status; A2's `errors.ts` and `reference.ts` are read, not modified. |
| **A3** — canonical inference representation (§5.3) | `ai-platform/src/contracts/canonical.ts` — `CanonicalResult` type (the validated terminal payload shape). Frozen artifact: `specs/017-ai-canonical-inference/contracts/canonical-shapes.md`. | C3 stores the validated terminal payload (a `CanonicalResult` from D6) as the envelope's `result` section (FR-007) and returns it from the get-request endpoint for a completed request (FR-010). C3 imports the `CanonicalResult` type for the `result` section's typing; it does not construct or validate a canonical request (that is D1's stage-10 job). |
| **A4 / C1** — immutable resolved capability manifest: `interaction_mode`, pinned prompt artifact hash, Economics (quota weight), retention class (§5.1, §5.7) | `ai-platform/src/manifest/index.ts` — `Manifest` (`Identity.capabilityId`/`version`, `"Prompt binding".systemInstructionArtifactRef` hash, `Economics.quotaWeight`, `Governance.retentionClass`). `ai-platform/src/capability/index.ts` — `ResolveResult = {ok:true, manifest} | {ok:false, code}`. Frozen artifacts: `specs/018-ai-capability-manifest/contracts/manifest-schema.md` (A4), `specs/025-capability-resolver-discovery/contracts/capability-registry.md` (C1). | C3's `createRequestRow` reads the resolved `Manifest` (the `{ok:true, manifest}` branch) for the pinned prompt artifact hash (FR-002 — known at stage 9 before stage 10, per spec Edge Cases), capability id+version, and `interaction_mode` (to null `conversation_id`/`turn_ordinal` for `single_shot`, FR-002). `writePostResponseDetail` reads `Economics.quotaWeight` for the `usage_event` row (FR-008). C3 treats the manifest as read-only (C1's immutability guarantee); it does not call `resolve()` (the orchestrator does and passes the manifest). Tests build a manifest fixture with A4's `load()`. |
| **A6** — request reference carried in the `accepted` event; SSE terminal-event invariant (§4.3.1, §5.5) | `ai-platform/src/adapter.ts` — `AdapterStreamContext` (carries `requestReference`). `ai-platform/src/reference.ts` — `generateRequestReference`. Frozen artifact: `specs/020-ai-protocol-adapter-sse/contracts/sse-framing.md`. | C3 receives the request reference (A6's generated value, carried in the `accepted` event) as an argument to `createRequestRow` (FR-002) and `getRequest` (FR-010). C3 does not mint the reference and does not frame SSE; A6's adapter is untouched. The one-terminal-event invariant is A6's; C3 journals the terminal state that A6 emits. |
| **B3** — immutable request principal (installation id, actor, branch, org, trace id) (§4.3.2, §5.6) | `ai-platform/src/identity/index.ts` — `Principal` interface (`installationId`, `actorId`, `branchId`, `organizationId`, ...). Frozen artifact: `specs/023-guard-stages/contracts/request-principal.md`. | C3's `createRequestRow` reads `principal.installationId`, `actorId`, `branchId` (FR-002) for the `ai_request` row. C3 never mutates the principal and adds no field to it (the no-rework rule). The principal is a read-only argument. |
| **B4** — Quota Durable Object credit interface (§4.3.3, §6.1 stage 15) | `ai-platform/src/quota-do/index.ts` — `creditRPC`, `CreditRequest`, `CreditResponse`. Frozen artifact: `specs/024-quota-do-admission/contracts/quota-do-rpc.md`. | C3 does **not** bind to B4's credit interface — stage 15's "credit actual usage to the Quota DO" is B4's DO method (spec Out of Scope; FR-004 updates the journal row only). C3's `recordTerminalState` updates `ai_request` and returns; the orchestrator (a later slice) calls B4's `creditRPC` alongside C3's `recordTerminalState`. Listed to record the explicit non-binding: C3 performs no DO I/O (§7.5, §13.6 — two DO round trips per request, neither owned by C3). |
| **C2** — filtered, declaration-conformant context payload (§4.3.5, §5.2) | `ai-platform/src/context/validator.ts` — the filtered context payload returned by C2's `validateContext()`. Frozen artifact: `specs/026-context-validator-cost-preflight/contracts/context-validator.md`. | C3's `writePostResponseDetail` stores the filtered context payload (handed in by the pipeline) as the envelope's `context` section (FR-007). C3 does not validate context (C2's contract); it stores what C2 already filtered. Until C2 lands in the pipeline, C3's tests drive the writer with a fixture filtered context. |

No consumed entry lacks an implementation. None is modified (delivery plan §2.3). A5's migration is imported in the test, not rewritten; A2's `errors.ts`/`reference.ts` are called, not modified; A6's `adapter.ts` is untouched; B4's DO is not invoked by C3.

## Components Touched

| §4 component | What C3 changes | Behaviour added? |
| --- | --- | --- |
| §4.3.11 Journal writer | **Created** — the stage-9 `createRequestRow` (synchronous D1 insert before any work, `internal_error` on failure), the §6.3 `journalTransition` (stamps `state`+`updated_at`; terminal also stamps `completed_at`, per the §6.3 amendment), the stage-15 `recordTerminalState` (terminal state + `terminal_error_code`, no client error), the stage-16 `writePostResponseDetail` (N `ai_attempt` rows + one `usage_event` row + one R2 envelope via `ctx.waitUntil`, failure swallowed), and the inlined `buildEnvelope` JSON helper (four sections `context`/`prompt`/`attempts[]`/`result`). | Yes — this is C3's primary component. |
| §5.5 API surface — Get request | **Created** — the `getRequest(reference, { db, r2, installationId })` read function and its `GET /v1/requests/{reference}` route in `worker.ts` (AAT via §5.6 / B3 `EnrolledKeyVerifier`; Worker feeds `installationId`). One indexed D1 lookup on `request_reference` scoped to installation; for `completed` with non-null `payload_pointer` additionally one R2 `GetObject` for the `result` section; completed-without-envelope → state only; `failed` → state + terminal error code, no R2; `cancelled` / `AwaitingContext` → state only; in-flight → `{ state, pending: true }`; unknown / mismatch → 404; missing/invalid token → 401 `unauthenticated`. | Yes — the get-request endpoint is a standalone §5.5 read surface C3 freezes (distinct from F3's operator-only support lookup). |

C3 touches two §4 components: §4.3.11 (primary — the journal writer) and §5.5 (the get-request read endpoint). The reason is the spec's `Canonical` cell itself cites both (`§4.3.11, §6.1 stages 9, 15, 16, §6.3, §7.4, §7.4.1, §7.6, §5.5`), and the delivery plan §3.4 row C3 `Done when` couples the write path and the read path ("the `ai_request` row is written synchronously … a request reference resolves to its terminal state") — the journal writer and its read endpoint are the two halves of one audit backbone, tested together because the get-request endpoint reads the very row and envelope the writer produces. This is within the one-component-group sizing guidance (delivery plan §2.5: "one component, or a small set of components that cannot be tested apart") — the writer and its reader cannot be tested apart (T14–T18 assert on rows T1–T13 wrote).

## Files

| File | Created / Modified | Traces to |
| --- | --- | --- |
| `ai-platform/src/journal/index.ts` | Created | FR-001..FR-012 — `RequestRowInput` (incl. optional `routingTier`) and `createRequestRow(input, db): {ok:true} | {ok:false; code:"internal_error"; request_reference; trace_id}` (stage 9); `TransitionState`, `journalTransition` (stamps `state`+`updated_at`; terminal incl. `AwaitingContext` also stamps `completed_at`; conditional UPDATE / no-op when already terminal); `recordTerminalState` (stage 15; `Failed` requires taxonomy code; no-op when already terminal); `writePostResponseDetail` (`db.batch` for attempts+usage_event; `console.error` on failure; accepted R2-without-pointer partial); `GetRequestResult` (incl. `AwaitingContext`, pending, Completed without result) and `getRequest(reference, {db, r2, installationId})`; H3 exports `listConversationLegs`, `ConversationLegRow`, `canReachAwaitingContext`, `isJournalTerminalState`, `isJournalTransitionAllowed`, `JOURNAL_TERMINAL_IMMUTABLE_STATES`. No `recordGuardRejection` / `flushGuardRejectionCounters` on the journal surface. |
| `ai-platform/src/worker.ts` | Modified | FR-010, FR-011 — adds `GET /v1/requests/{reference}` route: verify AAT (§5.6 / B3 `EnrolledKeyVerifier`), normalise reference, call `getRequest` with `installationId`, map `GetRequestResult` to JSON `Response` (incl. 401 `unauthenticated`, Completed-without-result, AwaitingContext, pending). |
| `ai-platform/test/journal.test.ts` | Created | SC-001, SC-002, SC-003, SC-004, SC-005, SC-006, SC-007 — the 18 named tests from the spec's `### Test plan` (`T-C3-01` … `T-C3-18`, with T6 parameterised over the 10 §6.3 transitions and T10 over N attempts), integration (ordering + spy), with spy assertions on D1 inserts/updates and R2 `PutObject`/`GetObject` counts. |
| `ai-platform/vitest.workers.config.ts` | Modified | SC-001..SC-007 — adds `test/journal.test.ts` to `include` so it runs against real D1 + R2 (miniflare). |
| `ai-platform/vitest.config.ts` | Modified | SC-001..SC-007 — adds `test/journal.test.ts` to `exclude` so the unit pool skips it (it belongs to the workers pool). |
| `specs/027-journal-writer-get-request/contracts/journal.md` | Created | (freezes the R2 payload envelope — key `request/{id}/envelope`, JSON, the four sections `context`/`prompt`/`attempts[]`/`result` and their contents; the get-request response `{state, terminal_error_code?, result?}`; and the journal write-path contract — stage-9 row shape, §6.3 transition stamping, stage-15 terminal update, stage-16 detail rows + envelope + `payload_pointer`) from FR-001..FR-012, so D3/D4/D6/F3 consume a contract, not prose. |
| `specs/027-journal-writer-get-request/quickstart.md` | Created | — written during the implement-phase Documentation task (sections named in Project Structure → Documentation). Not traced to an FR (template-mandated review surface). |

Every code/contract file traces to an `FR-###`. No file is created for an unstated requirement. The consumed modules (`identity/`, `manifest/`, `capability/`, `errors.ts`, `reference.ts`, `contracts/canonical.ts`, `adapter.ts`, `quota-do/`) are unchanged.

## Test Layout

The spec's `### Test plan` names 18 tests at the §13.5 layer "Pipeline tests" (the §3.11.3 row C3 layer "Integration (ordering + spy)" realised as that §13.5 row: "Stage ordering, guard rejection paths"). All 18 run under `vitest.workers.config.ts` — C3 writes to real D1 and R2, so the workers pool (miniflare D1/R2 bindings) is required, unlike C2's CPU-only suite. The test file is `ai-platform/test/journal.test.ts`. Spy assertions verify D1 insert/update counts and R2 `PutObject`/`GetObject` counts per the §3.10 coverage rule (several of this slice's invariants are about work *not* done — one R2 object, no row per chunk, no row on rejection).

| Spec Test plan name | Test id | §13.5 layer | Config | Asserts (FR / SC) |
| --- | --- | --- | --- | --- |
| `request_row_exists_before_provider_invoked` | T-C3-01 | Pipeline tests | workers | FR-001 / SC-001 — a provider-call spy observes the `ai_request` row present (one D1 insert) before the fake provider is called (stage 9 precedes stage 11). |
| `terminal_state_completed` | T-C3-02 | Pipeline tests | workers | FR-004 / SC-001 — a completed request's row is updated to `completed` at stage 15 (`completed_at` stamped). |
| `terminal_state_failed` | T-C3-03 | Pipeline tests | workers | FR-004 / SC-001 — a failed request's row is updated to `failed` at stage 15 (`completed_at` + `terminal_error_code` stamped). |
| `terminal_state_cancelled` | T-C3-04 | Pipeline tests | workers | FR-004 / SC-001 — a cancelled request's row is updated to `cancelled` at stage 15 (`completed_at` stamped, no error code). |
| `guard_rejected_produces_no_row` | T-C3-05 | Pipeline tests | workers | FR-005 / SC-002 — a guard-rejected request produces zero `ai_request` inserts (spy on D1 inserts: 0) and one `platform_counter` increment via the rate-limit/admission live path (not journal tally helpers). |
| `every_state_transition_timestamped` | T-C3-06 | Pipeline tests | workers | FR-003 / SC-003 — each §6.3 transition stamps `state`+`updated_at` (terminal incl. `AwaitingContext` also stamps `completed_at`); second terminal write is a no-op. |
| `row_survives_failed_generation` | T-C3-07 | Pipeline tests | workers | FR-006 / SC-001 — a failed generation leaves the row present, carrying the failure's terminal state (no delete on failure). |
| `exactly_one_r2_putobject_per_request` | T-C3-08 | Pipeline tests | workers | FR-007, FR-012 / SC-004 — exactly one R2 `PutObject` per request, keyed `request/{id}/envelope` (spy on R2: 1); a second `PutObject` is provably absent. |
| `envelope_contains_all_four_sections` | T-C3-09 | Pipeline tests | workers | FR-007 / SC-004 — the envelope document (JSON) contains the `context`, `prompt`, `attempts[]`, and `result` sections. |
| `one_ai_attempt_row_per_attempt` | T-C3-10 | Pipeline tests | workers | FR-008 / SC-005 — N provider attempts produce exactly N `ai_attempt` rows (spy on D1 inserts). (Parameterised: N=2 and N=3.) |
| `exactly_one_usage_event` | T-C3-11 | Pipeline tests | workers | FR-008 / SC-005 — exactly one `usage_event` row is written per request (spy on D1 inserts: 1). |
| `stage16_failure_does_not_fail_request` | T-C3-12 | Pipeline tests | workers | FR-009 / SC-006 — an injected R2/D1 failure in stage 16 does not fail the request; `writePostResponseDetail` returns normally (failure swallowed inside `ctx.waitUntil`), the terminal event already emitted stands. |
| `stage16_runs_after_terminal_event` | T-C3-13 | Pipeline tests | workers | FR-009 / SC-006 — the terminal event spy is called before any stage-16 write (ordering spy: terminal-emit precedes `ctx.waitUntil`'s writes). |
| `get_request_completed_returns_state_and_result` | T-C3-14 | Pipeline tests | workers | FR-010 / SC-007 — authenticated completed-with-envelope returns state plus validated result (GetObject on non-null `payload_pointer` only). |
| `get_request_failed_returns_state_and_error_no_content` | T-C3-15 | Pipeline tests | workers | FR-010 / SC-007 — failed → state plus terminal error code, no R2 read. |
| `get_request_cancelled_returns_state_only` | T-C3-16 | Pipeline tests | workers | FR-010 / SC-007 — cancelled → state only, no R2 read. |
| `get_request_unknown_reference_returns_not_found` | T-C3-17 | Pipeline tests | workers | FR-010 / SC-007 — unknown reference or installation mismatch → not found; missing/invalid AAT → 401 `unauthenticated`. |
| `get_request_uses_exactly_one_indexed_query` | T-C3-18 | Pipeline tests | workers | FR-011 / SC-007 — exactly one indexed D1 lookup; no derived-key fallback; failed/cancelled/`AwaitingContext`/in-flight perform no R2 read. |

Coverage additions from §3.10: every error code the slice can emit is covered one-for-one — `internal_error` (T-C3-01, the stage-9 insert-failure path; the spec's Coverage note names this as the only code C3's own stages emit). Every branch: the happy path (T-C3-01), each terminal-state branch (T-C3-02/03/04), the guard-rejection branch (T-C3-05), the failed-generation-survival branch (T-C3-07), the stage-16-failure-isolation branch (T-C3-12), the post-response-ordering branch (T-C3-13), each get-request branch (T-C3-14/15/16/17). Every named boundary: one R2 object per request (T-C3-08), one `usage_event` per request (T-C3-11), N `ai_attempt` per N attempts (T-C3-10), exactly one indexed query (T-C3-18). The prohibitions (FR-012) are spy assertions: no row per chunk (T-C3-10 asserts attempt rows, not chunk rows), no row on rejection (T-C3-05), no second R2 object (T-C3-08), no per-request server-side state (the writer holds none — verified by the absence of any state object in the module).

Every named test places in a §13.5 layer — stop condition 3 not triggered.

## Sequencing

Tests land first or alongside their implementation, never after (delivery plan §2.2; the test file plus the diff is the review artifact). Within this slice:

1. **Contract artifact** — `contracts/journal.md` is written first alongside the type definitions (it freezes the R2 payload envelope, the get-request response shape, and the journal write-path contract), so D3/D4/D6/F3 can bind during their own plan phase. The types are the contract; the functions follow.
2. **Vitest config** — `vitest.workers.config.ts` add `test/journal.test.ts` to `include` and `vitest.config.ts` add it to `exclude` (it needs real D1 + R2, so it belongs to the workers pool, not the unit pool — the B4/C1 precedent). Written alongside step 1.
3. **Stage 9 — request row (FR-001, FR-002, FR-005, FR-006)** — `T-C3-01` first (the row-exists-before-provider ordering spy pins stage 9 precedes stage 11), then `T-C3-05` (the no-row-on-rejection spy pins the cheap-rejection invariant), then `T-C3-07` (the row-survives-failed-generation pin). These exercise `createRequestRow` against a fixture manifest + principal with real D1.
4. **§6.3 transition stamping (FR-003)** — `T-C3-06` (parameterised over the 10 transitions) pins `journalTransition`/`recordTerminalState` stamping `state`+`updated_at` (+`completed_at` on terminal), then `T-C3-02`, `T-C3-03`, `T-C3-04` pin the three terminal branches of `recordTerminalState`.
5. **Stage 16 — post-response continuation (FR-007, FR-008, FR-009, FR-012)** — `T-C3-09` first (the four-section envelope pins `buildEnvelope`'s JSON shape), then `T-C3-08` (the one-R2-`PutObject` spy pins the one-object-per-request rule), then `T-C3-10`, `T-C3-11` (the N-`ai_attempt` and one-`usage_event` counts), then `T-C3-13` (the terminal-event-before-stage-16 ordering spy), then `T-C3-12` (the stage-16-failure-isolation pin — `ctx.waitUntil` swallows the injected failure). These exercise `writePostResponseDetail` with a fake `ctx` that captures the `waitUntil` promise.
6. **Get-request endpoint (FR-010, FR-011)** — `T-C3-14`, `T-C3-15`, `T-C3-16`, `T-C3-17` (the four response branches), then `T-C3-18` (the one-indexed-query spy). These exercise `getRequest` with a spy-wrapped D1 (counting `prepare` calls) + real R2; the `worker.ts` route is wired alongside and maps `GetRequestResult` to a `Response`.
7. **Documentation** — `quickstart.md` last, during the implement-phase Documentation task, after the slice's tests pass.

Steps 3–6 interleave tests with implementation; no test is written after its implementation. The contract artifact (step 1) and the vitest config (step 2) are written alongside. The Documentation artifact (step 7) is written only after the suite is green — the plan names it here, the implement phase fills it in.

## Complexity Tracking

> Not filled — no Constitution Check violation requires justification. The one structurally-inapplicable Constitution box (Supabase/PostgreSQL protected writes) is recorded above as inapplicable to a Worker-only slice that writes only the platform's own D1 tables (per the §14 acknowledgement), not as a violation.
