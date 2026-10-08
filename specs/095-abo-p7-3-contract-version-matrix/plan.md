# Implementation Plan: Contract version matrix

**Branch**: `ai/095-abo-p7-3-contract-version-matrix` | **Date**: 2026-10-08 | **Spec**: `specs/095-abo-p7-3-contract-version-matrix/spec.md`

**Input**: Feature specification from `specs/095-abo-p7-3-contract-version-matrix/spec.md`

## Summary

P7.3 builds the contract-version matrix: receivers and senders at overridden package constants (published N+1) run every 04 §7.1 channel with N, N−1, and an unsupported version, then FM-25, the stored-envelope retry, the Worker-N / DO-N+1 pairing, the desktop update state, and the Paymob return URL. It depends on P6.4 and P4.11 (phase P7, size M) and adds tests only under `e2e/fullstack/` and the per-codebase variants; it does not change published constants, migrations, or the five PostgREST bodies on disk.

## Technical Context

**Language/Version**: TypeScript workers (ABO and AI Platform), SQL on local PostgreSQL, Dart/Flutter desktop tests, Node test runner in `e2e/fullstack/`

**Primary Dependencies**: Existing `vendor-contracts` package (imported, not edited), vitest workers pool already used by `abo/` and `ai-platform/`, `wrangler` `startWorker` already used by H-FS, PostgREST RPCs already published, Flutter `fullstack` tag

**Storage**: No new store. Tests read and write existing ABO D1, platform D1, and `ai_internal.feed_state` / work rows. The RPC variant does not update `ai.contract_versions`.

**Testing**: H-FS (`e2e/fullstack/test/p7-3-*.test.mjs`), ABO and platform vitest workers configs that alias `vendor-contracts`, backend SQL variant, Flutter `fullstack` test for E2E-P7.3-06. Title prefix is the E2E id (rule V3). Harness commands that boot a worker are not executed in this plan workflow: the stack is not running and this workflow does not start wrangler.

**Target Platform**: Local full stack and the existing per-codebase harnesses (H-FS, H-ABO workers pool, H-AP workers pool, H-BK SQL, H-FL on H-FS)

**Project Type**: Test harness across `e2e/fullstack/` and per-codebase test variants (the wiring the unit row names)

**Performance Goals**: None beyond the existing harness bounds. No local scenario sleeps more than 2 s of real time except H-FS, where a test clock cannot cross pg_cron (rule V4).

**Constraints**: Published N is `1` (`CHANNEL_VERSIONS` in `packages/vendor-contracts/src/version.ts`, and the SQL literals `(0, 1)`). `negotiate` accepts `current` and `current - 1` and answers in the version the request used. Package sources, `ai.contract_versions`, and the migration bodies of the five RPCs stay as published. Receivers that import `CHANNEL_VERSIONS` take the override from a test-only module alias. The five RPCs take the override only from the backend test variant's in-transaction `public` gate replacement. AL-07 is captured from `send_email` (rule V6).

**Scale/Scope**: Seven scenarios, ten 04 §7.1 channels, three desktop channels. No new product module.

### Version windows the tests build

Published current is `1`. Published previous is `0`.

| Window | How it is built | Accepted pair | Used by |
| --- | --- | --- | --- |
| Receiver current = published N+1 (`2`) | Alias replaces `vendor-contracts` with a test module that copies every channel to `published + 1` | `1` and `2` | E2E-P7.3-01 worker channels. Unsupported is missing, `0`, or `3` |
| RPC receiver current = `2` | Inside one SQL transaction, replace the five `public` gates so the literals are `(1, 2)` and an `rpc_result` refusal's `contract_version` is `2`. `issue_ai_token` still `RAISE`s with `accepted_versions` `[1, 2]`. `auth_internal` bodies stay the published functions. `ROLLBACK` restores `(0, 1)` | `1` and `2` | E2E-P7.3-01 RPC cases only |
| ABO sender at N+1, platform at N | ABO worker uses the N+1 alias (`vendorEntrypoint` is `2`). Platform uses `ai-platform/wrangler.toml` unchanged (`1`) | Platform accepts `0` and `1`, so a call at `2` is refused | E2E-P7.3-02 first half. The retry half restarts the platform on the N+1 alias so it accepts `1` and `2` |
| Worker N, DO N+1 | Two bundles. The admission worker keeps published constants and sends `contract_version` `1`. Its `DO` binding `script_name` is a receiver worker whose alias sets only `platformDo` to `2`. Both share the H-FS registry (the same registry directory H-FS already passes to `startWorker`) | DO accepts `1` and `2` and answers in `1` | E2E-P7.3-05. `coverage_unknown` only when the version is missing or outside `{1, 2}` |
| Feed puller on N, platform window starts at N+1 | Puller keeps sending published `platformFeed` `1` from `ai.contract_versions` (that row is not updated). Platform alias sets only `platformFeed` to `3`. `negotiate(3, 1)` refuses because the accepted pair is `2` and `3` | `2` and `3` | E2E-P7.3-03. The puller's `1` is outside that pair, so the platform answers HTTP 400 |
| Desktop below the minimum | Desktop clients keep their compiled constants (`1`). ABO and platform aliases set `aboClinic` and `platformClinic` to `3` (accepted `2` and `3`). For the RPC channel only, the prepare step replaces the five `public` gates so the accepted pair is `(2, 3)` and an `rpc_result` refusal's `contract_version` is `3`, then restores `(0, 1)` before exit | Desktop `1` is below minimum `2` | E2E-P7.3-06 |

The feed and desktop windows use `published + 2` because `negotiate` always keeps one previous version. A receiver whose oldest accepted version is N+1 (`2`) has current `3`. That is the override that makes published N (`1`) unsupported. E2E-P7.3-01 does not use that window: there the receiver current is `2`, and both `2` and `1` are accepted.

Token `ver` is not a `CHANNEL_VERSIONS` integer. Launch accepted ver is `"2"` (`abo/src/clinic-api/auth.ts` and platform `token_contract`). E2E-P7.3-01 asserts that a `ver` outside that list is `unauthenticated`, and that `"2"` is not refused as an unsupported contract version.

The Paymob return URL has no version refusal. E2E-P7.3-01 on the ABO N+1 variant asserts `paymobReturnUrl` puts the variant current (`2`) in `v`. E2E-P7.3-07 opens `GET /return/paymob` with a `v` that is not that channel's version and asserts an inquiry is still scheduled and the page is neutral.

A sender that receives an answer whose `contract_version` it does not accept treats that answer as `contract_version_unsupported`. E2E-P7.3-01 asserts that on the `VendorEntrypoint` result `runDueGrantWork` reads (`abo/src/work/grant.ts`).

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-checked after design. 02 §7 records no violation. This unit adds no service, queue, store, or migration.*

- [x] Feature scope still fits small-to-mid-size multi-branch clinics; hospital-scale or
      enterprise-only requirements are explicitly rejected or separately ratified
      — 02 §7 principle I and spec §4 Clinic Fit: a clinic on N or N−1 keeps working; the suite proves that on the local stack.
- [x] Design keeps a simple operational model with no microservices, message queues,
      Kubernetes, or custom primary backend service
      — 02 §7 principle I. The matrix calls the existing ABO worker, platform worker, DO, RPCs, feed puller, and desktop clients.
- [x] Layer ownership is explicit: Flutter handles UI/orchestration, Supabase handles
      backend capabilities, PostgreSQL owns domain integrity, and AI stays isolated
      — 02 §7 principle II. Flutter only shows the update state. Workers hold no Supabase credential. The test variant does not move a rule into Flutter.
- [x] Protected writes, validation, permissions, and transactional rules remain enforced
      through PostgreSQL constraints, triggers, RLS, or RPC functions
      — 02 §7 principle III. The version gate stays before authentication and before any write. The RPC override is a transaction-local replacement of the five `public` gates and is rolled back before the variant exits. Published migration bodies stay in place.
- [x] Security remains authenticated, tenant-scoped, branch-scoped, permission-gated,
      auditable, and soft-delete-preserving
      — 02 §7 principle IV. A missing or unsupported version is refused before auth. A token `ver` outside the accepted list is `unauthenticated`. FM-25 writes nothing.
- [x] AI actions remain human-approved, have no direct database/backend access, and the
      feature still works in a degraded manual mode when AI is unavailable
      — 02 §7 principles II and V. This unit adds no AI write path. A desktop below the minimum shows the inline update state (04 §7.3), not an error dialog.

## Project Structure

### Documentation (this feature)

```text
specs/095-abo-p7-3-contract-version-matrix/
├── plan.md              # This file
├── spec.md
├── escalations.md
└── quickstart.md        # Outline only here. Implement writes it after harness green
```

`research.md` is omitted (Spikes: None). `data-model.md` is omitted (no entities). `contracts/` is omitted (Freezes: None). `tasks.md` is not created in this phase.

#### Quickstart outline

Implement writes `quickstart.md` after the harness is green. Sections only:

- What was implemented; files added and modified
- Harness commands for this unit's tests only (the commands in Sequencing)
- Entry point → module chain per E2E id
- No earlier-unit files, combined counts, or full-suite commands
- Manual steps only if the harness cannot see the behaviour
- Worker-booting commands are not executed in this plan workflow

### Source Code (repository root)

```text
e2e/fullstack/test/
├── p7-3-stack.mjs
├── p7-3-01.test.mjs
├── p7-3-02.test.mjs
├── p7-3-03.test.mjs
├── p7-3-04.test.mjs
├── p7-3-05.test.mjs
├── p7-3-06-prepare.mjs
├── p7-3-07.test.mjs
└── variant/
    ├── vendor-contracts-n-plus-1.ts
    ├── vendor-contracts-do-receiver.ts
    ├── vendor-contracts-feed-window.ts
    ├── vendor-contracts-desktop-window.ts
    ├── abo-n-plus-1.toml
    ├── platform-n-plus-1.toml
    ├── platform-worker-n.toml
    ├── platform-do-receiver.toml
    ├── platform-feed-window.toml
    ├── abo-desktop-window.toml
    └── platform-desktop-window.toml

abo/
├── vitest.version-matrix.config.ts
└── test/version-matrix/
    └── channels.system.test.ts

ai-platform/
├── vitest.version-matrix.config.ts
├── vitest.version-matrix-do.config.ts
└── test/version-matrix/
    ├── channels.system.test.ts
    └── worker-do.system.test.ts

backend/tests/
└── contract_version_matrix.sql

frontend/test/integration/
└── contract_version_matrix_fullstack_test.dart
```

**Structure Decision**: Tests live in H-FS and in the ABO, platform, backend, and Flutter harnesses the scenario rows name. Variant modules and wrangler configs are test-only. They alias or replace gates; they do not edit `packages/vendor-contracts`, `abo/src/`, `ai-platform/src/`, `frontend/lib/`, or `backend/supabase/migrations/`. Default `abo` and `ai-platform` vitest configs stay pointed at their existing suites. `e2e/fullstack/package.json` `"test"` stays the existing script. Each new workers config has its own `include` under `test/version-matrix/`.

Each `vendor-contracts-*.ts` file imports `packages/vendor-contracts/src/index.ts` by relative path, re-exports every named export except `CHANNEL_VERSIONS`, and exports a new `CHANNEL_VERSIONS`. The alias key is the bare specifier `vendor-contracts`, not `vendor-contracts/testkit`. Wrangler configs are the development bindings from `abo/wrangler.toml` or `ai-platform/wrangler.toml` plus that alias. `platform-worker-n.toml` keeps published constants and sets the `DO` binding `script_name` to the receiver worker from `platform-do-receiver.toml`.

## Consumes Binding

| Consumes | Binding |
| --- | --- |
| P6.4 | None. The unit row states no Outputs / freezes line. |
| P4.11 | None. The unit row states no Outputs / freezes line. |

This unit does not modify those units' modules.

## Files

| Path | Action | FR |
| --- | --- | --- |
| `e2e/fullstack/test/variant/vendor-contracts-n-plus-1.ts` | Create. Every channel current = published + 1 | FR-001 |
| `e2e/fullstack/test/variant/vendor-contracts-do-receiver.ts` | Create. Only `platformDo` = published + 1 | FR-002 |
| `e2e/fullstack/test/variant/vendor-contracts-feed-window.ts` | Create. Only `platformFeed` = published + 2 | FR-006 |
| `e2e/fullstack/test/variant/vendor-contracts-desktop-window.ts` | Create. Only `aboClinic` and `platformClinic` = published + 2 | FR-003 |
| `e2e/fullstack/test/variant/abo-n-plus-1.toml` | Create. ABO development bindings plus N+1 alias | FR-001, FR-005 |
| `e2e/fullstack/test/variant/platform-n-plus-1.toml` | Create. Platform development bindings plus N+1 alias | FR-001, FR-005 |
| `e2e/fullstack/test/variant/platform-worker-n.toml` | Create. Published platform constants; `DO` `script_name` points at the receiver | FR-002 |
| `e2e/fullstack/test/variant/platform-do-receiver.toml` | Create. DO receiver alias | FR-002 |
| `e2e/fullstack/test/variant/platform-feed-window.toml` | Create. Feed-window alias | FR-006 |
| `e2e/fullstack/test/variant/abo-desktop-window.toml` | Create. Desktop-window alias for the ABO | FR-003 |
| `e2e/fullstack/test/variant/platform-desktop-window.toml` | Create. Desktop-window alias for the platform | FR-003 |
| `e2e/fullstack/test/p7-3-stack.mjs` | Create. Starts the worker pair a scenario names, on the existing H-FS registry and ports | FR-001, FR-002, FR-004, FR-005, FR-006, FR-007 |
| `e2e/fullstack/test/p7-3-01.test.mjs` | Create. Title prefix `E2E-P7.3-01` | FR-001 |
| `e2e/fullstack/test/p7-3-02.test.mjs` | Create. Title prefix `E2E-P7.3-02` | FR-005 |
| `e2e/fullstack/test/p7-3-03.test.mjs` | Create. Title prefix `E2E-P7.3-03` | FR-006 |
| `e2e/fullstack/test/p7-3-04.test.mjs` | Create. Title prefix `E2E-P7.3-04` | FR-007 |
| `e2e/fullstack/test/p7-3-05.test.mjs` | Create. Title prefix `E2E-P7.3-05` | FR-002 |
| `e2e/fullstack/test/p7-3-06-prepare.mjs` | Create. Starts the desktop-window workers and applies the `(2, 3)` public-gate replacement, then restores `(0, 1)` | FR-003 |
| `e2e/fullstack/test/p7-3-07.test.mjs` | Create. Title prefix `E2E-P7.3-07` | FR-004 |
| `abo/vitest.version-matrix.config.ts` | Create. Workers pool, N+1 alias, `include` `test/version-matrix/**` | FR-001 |
| `abo/test/version-matrix/channels.system.test.ts` | Create. Title prefix `E2E-P7.3-01` | FR-001 |
| `ai-platform/vitest.version-matrix.config.ts` | Create. Workers pool, N+1 alias, `include` `test/version-matrix/channels.system.test.ts` | FR-001 |
| `ai-platform/vitest.version-matrix-do.config.ts` | Create. Published main worker plus DO receiver auxiliary | FR-002 |
| `ai-platform/test/version-matrix/channels.system.test.ts` | Create. Title prefix `E2E-P7.3-01` | FR-001 |
| `ai-platform/test/version-matrix/worker-do.system.test.ts` | Create. Title prefix `E2E-P7.3-05` | FR-002 |
| `backend/tests/contract_version_matrix.sql` | Create. Title prefix `E2E-P7.3-01`. Transaction-local `(1, 2)` gates, then `ROLLBACK` | FR-001 |
| `frontend/test/integration/contract_version_matrix_fullstack_test.dart` | Create. `@Tags(['fullstack'])`, title prefix `E2E-P7.3-06` | FR-003 |
| `specs/095-abo-p7-3-contract-version-matrix/quickstart.md` | Implement writes this after harness green, from the outline above | FR-001, FR-002, FR-003, FR-004, FR-005, FR-006, FR-007 |

No file under `packages/vendor-contracts/` or `backend/supabase/migrations/`. No edit to `run_all_backend_tests.sh`, `abo/vitest.workers.config.ts`, `ai-platform/vitest.workers.config.ts`, or `e2e/fullstack/package.json`.

## Test Layout

Tests are authored first and are expected to fail before the variant they call is in place. One test per id, title prefixed with that id.

| ID | Harness | Entry → chain | Assertion |
| --- | --- | --- | --- |
| E2E-P7.3-01 | H-FS `p7-3-01.test.mjs` with `abo-n-plus-1.toml` and `platform-n-plus-1.toml`. ABO variant `channels.system.test.ts`. Platform variant `channels.system.test.ts`. Backend `contract_version_matrix.sql` | ABO `handleBillingV1` → `checkContractVersion` `aboClinic`. ABO `handleOps` → `checkContractVersion` `aboConsole` (`reload` on the refusal body). Platform `fetch` → `requireAipContractVersion` on `GET /v1/capabilities`, `POST /v1/requests`, `GET /v1/coverage`. `GET /v1/feed/coverage` → `negotiate(CHANNEL_VERSIONS.platformFeed)`. `VendorEntrypoint`. `GatewayObject.fetch`. `handleGetReturnPaymob` and `paymobReturnUrl`. `POST /notify/paymob`. Platform `ai-platform/src/identity/index.ts` `token_contract` and ABO `authenticateBilling`. H-FS also runs `runDueGrantWork` for the unknown-answer rule. SQL: the five `public` RPCs | Worker channels: request `2` accepted and answered in `2`; request `1` accepted and answered in `1`; missing, `0`, or `3` gets that channel's refusal before auth and before any write. Console refusal asks for a reload. Return URL: no version refusal; built `v` is `2`. Unparseable Paymob body: A23 alert and evidence `adapter_version` is the variant `paymobAdapter`. Token `ver` other than `"2"`: `unauthenticated`. RPC variant: `2` and `1` succeed in the version sent; missing, `0`, or `3` is `CONTRACT_VERSION_UNSUPPORTED` with `accepted_versions` `[1, 2]` before auth and before any write; `rpc_result` refusals carry `contract_version` `2`; `issue_ai_token` raises; `ROLLBACK` leaves `(0, 1)`. An answer `contract_version` outside the sender's pair is `contract_version_unsupported` |
| E2E-P7.3-02 | H-FS `p7-3-02.test.mjs` | `scheduled()` → `runMinuteInquiryBudget` → `runDueGrantWork` → `VendorEntrypoint.grant`. AL-07 from `send_email`. Retry also via `POST /ops/parked/{id}/retry` (`handlePostRetry`) | ABO on the N+1 alias against the published platform: `rejected` / `contract_version_unsupported`, nothing written, row parked, AL-07. Then platform restarted on `platform-n-plus-1.toml`: retry applies |
| E2E-P7.3-03 | H-FS `p7-3-03.test.mjs` with `platform-feed-window.toml` | `auth_internal.pull_coverage_feed()` → `GET /v1/feed/coverage`. Cursor is `ai_internal.feed_state.cursor` | Puller still sends published `1`. Platform answers HTTP 400. Cursor unchanged. Stale alert fires. Nothing written. `ai.contract_versions` unchanged |
| E2E-P7.3-04 | H-FS `p7-3-04.test.mjs` on the published ABO and platform configs | `scheduled()` → `runDueGrantWork`, and `POST /ops/parked/{id}/retry` | Retried row resends its stored envelope. Stored `contract_version` is unchanged |
| E2E-P7.3-05 | H-FS `p7-3-05.test.mjs` and platform `worker-do.system.test.ts` | `POST /v1/requests` on the published-constant worker → `DO` on the receiver bundle → `GatewayObject.fetch` | Call at `1` against DO current `2` is accepted and answered in `1`. Missing, or a version outside `{1, 2}`, is DO `rejected` with `contract_version_unsupported` and `accepted_versions`, and the worker maps that to `coverage_unknown` |
| E2E-P7.3-06 | H-FL on H-FS. Prepare script, then `contract_version_matrix_fullstack_test.dart` | `AboClient` on `AdministratorBillingPage`. `AiAvailabilityReader`, `BillingTokenClient`, and `SubscriptionSummary` on `AiPage` and `CheckoutScreen`. `DiscoveryClient` and `HttpsSubmitPort` on `AiPage`. Update state is `AiDegradedView` mode `appUpdate` | Desktop still sends `1`. Each of the three channels shows the update state and no error dialog |
| E2E-P7.3-07 | H-FS `p7-3-07.test.mjs` | `GET /return/paymob` (`handleGetReturnPaymob`). `v` is the query on the `return_url` from `paymobReturnUrl` | Unknown `v` still schedules an inquiry. Page is neutral |

E2E-P7.3-01's RPC cases run only in `contract_version_matrix.sql`. The H-FS and workers-pool files cover the channels that import `CHANNEL_VERSIONS`, plus the token, Paymob, and unknown-answer assertions. They do not replace the five `public` functions.

## Sequencing

1. Author each test file in Test Layout so it fails before its variant config or SQL replacement exists.
2. Add the variant module, wrangler config, or SQL gate that test imports or starts.
3. Worker-booting harness commands are not executed in this plan workflow. The stack is not running and this workflow does not start wrangler, so the red run is not observed here. Implement runs them until green, then writes `quickstart.md`.

Commands, this unit only:

- H-FS (boots workers; not run in this workflow): from `e2e/fullstack/`, `node --import tsx --test test/p7-3-01.test.mjs test/p7-3-02.test.mjs test/p7-3-03.test.mjs test/p7-3-04.test.mjs test/p7-3-05.test.mjs test/p7-3-07.test.mjs`
- ABO variant (boots a worker; not run in this workflow): `npx vitest run --config vitest.version-matrix.config.ts` in `abo/`
- Platform variants (boot workers; not run in this workflow): `npx vitest run --config vitest.version-matrix.config.ts` and `npx vitest run --config vitest.version-matrix-do.config.ts` in `ai-platform/`
- E2E-P7.3-06 (prepare boots workers; not run in this workflow): `node --import tsx e2e/fullstack/test/p7-3-06-prepare.mjs`, then `flutter test --tags fullstack test/integration/contract_version_matrix_fullstack_test.dart` in `frontend/`
- Backend SQL (does not boot a worker; not run in this plan workflow): `psql -h 127.0.0.1 -p 54322 -U postgres -d postgres -v ON_ERROR_STOP=1 -f backend/tests/contract_version_matrix.sql`

Do not point these commands at earlier suites or at `npm test` in `e2e/fullstack/`.

Task grain for the next phase is one task per path in Files, including the later quickstart task. That is 28 tasks, inside the M band (20–32).

## Complexity Tracking

None. 02 §7 records no constitution violation for this unit.
