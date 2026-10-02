# Tasks: Package core: canonical JSON, signing, identifiers, version constants

**Input**: Design documents from `specs/063-abo-p2-1-package-core-canonical-signing/`

**Prerequisites**: `plan.md` (required), `spec.md` (required for user stories), `contracts/` (`AVAILABLE_DOCS`: `contracts/`). `research.md` is omitted (Spikes is None). `data-model.md` is omitted (the spec defines no entities). `quickstart.md` is written in Documentation after verification.

**Organization**: Two user stories, as the spec partitions them (`[US1]`, `[US2]`). Tests are one task per E2E id in the spec Test plan, written to fail before the package exports and the worker gate exist. Test Layout names no extra test. Titles start with the E2E id (rule V3). Nothing ships before P8 (rule S2). Setup is Sequencing step 1: the package skeleton must exist before the H-PKG tests can load. No Foundational phase (Consumes Binding is none). No Polish phase.

**Task count**: 23. Size M is 20–32 (rule S3). The count is the honest list: the skeleton (Sequencing step 1), seven E2E tasks (steps 2–7 and step 20), the twelve implementation steps 8–19, the CI job (step 21), one verification task after that job, and `quickstart.md` (step 22). It is not padded. The direct header edits stay two tasks grouped by call site, as Sequencing states.

## 1. Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (`US1`, `US2`)
- Include exact file paths in descriptions

## 2. Path Conventions

- **Flutter desktop app**: `frontend/lib/`, `frontend/test/` — this unit does not change them
- **Supabase backend**: `backend/migrations/`, `backend/functions/`, `backend/tests/` — this unit does not change them. The backend cannot import the package (FR-001)
- **Shared package**: `packages/vendor-contracts/`
- **AI Platform**: `ai-platform/src/`, `ai-platform/test/`, `ai-platform/package.json`
- **CI**: `.github/workflows/ci.yml`
- **Spec Kit artifacts**: `specs/063-abo-p2-1-package-core-canonical-signing/`
- This unit's Files section names `packages/vendor-contracts/`, the thin `ai-platform/` header wiring, `ai-platform/test/e2e/harness/d1.ts` and `ai-platform/test/e2e/harness/control.ts` for the catalogue re-seed, and `.github/workflows/ci.yml`. `contracts/` stays a plan-phase artifact. There is no `dist/` emit. `ai-platform/src/adapter.ts` stays as it is. `GET /v1/usage` and `/control/*` stay outside the gate.

---

## 3. Setup

**Purpose**: Sequencing step 1. The package skeleton exists before any test loads it. `src/index.ts` does not yet export the APIs.

- [X] T001 Create the package skeleton in `packages/vendor-contracts/`: `package.json` (name `vendor-contracts`, `"type": "module"`, `"exports": { ".": "./src/index.ts" }`, `"test"` runs `vitest.config.ts` then `vitest.workers.config.ts`), `package-lock.json`, `tsconfig.json` (TypeScript `^5.9.2`, ESM, no `dist/` emit), `wrangler.toml` (workers-pool compatibility date `2026-05-03`), `vitest.config.ts`, and `vitest.workers.config.ts` (Vitest `~3.2.4`, `@cloudflare/vitest-pool-workers` `0.8.71`, the runner `ai-platform` already uses). Add `packages/vendor-contracts/src/index.ts` that exports nothing yet — produces the loadable package, satisfies FR-001 and FR-002, proved by E2E-P2.1-01, E2E-P2.1-02, and E2E-P2.1-03. No JCS library and no ULID library.

**Checkpoint**: The skeleton exists. The H-PKG tests are not written yet.

---

## 4. Tests

**Purpose**: One failing test per E2E id. H-PKG tests import the package exports and fail while those exports are absent. H-AP tests call `SELF.fetch` and fail while `ai-platform/src/worker.ts` does not yet refuse a missing header. T008 is Sequencing step 20: it runs after the default-header tasks, not before the package exists.

### 4.1 User Story 1 - Canonical bytes, signatures, and identifiers (Priority: P1)

**Independent Test**: E2E-P2.1-01, E2E-P2.1-02, and E2E-P2.1-03 in harness H-PKG (Node and workerd).

- [X] T002 [P] [US1] Add the failing test `E2E-P2.1-01` in `packages/vendor-contracts/test/canonical.test.ts`, and add `packages/vendor-contracts/vectors/canonical.json`, run by `vitest.config.ts` and by `vitest.workers.config.ts` — produces the red test, satisfies FR-001, FR-002, FR-003, and FR-010, proved by E2E-P2.1-01. Every object in the vector file canonicalises to the fixture bytes in that runtime. The test fails because `canonicalize` is absent. Depends on T001.

- [X] T003 [P] [US1] Add the failing test `E2E-P2.1-02` in `packages/vendor-contracts/test/jws.test.ts`, and add `packages/vendor-contracts/vectors/jws.json`, both configs — produces the red test, satisfies FR-004 and FR-010, proved by E2E-P2.1-02. The runtime reproduces the fixture compact JWS and `verifyCompactJws` accepts it. A changed payload or a changed `kid` returns false. The test fails because `signCompactJws` and `verifyCompactJws` are absent. Depends on T001.

- [X] T004 [P] [US1] Add the failing test `E2E-P2.1-03` in `packages/vendor-contracts/test/identifiers.test.ts`, and add `packages/vendor-contracts/vectors/identifiers.json`, both configs — produces the red test, satisfies FR-006, FR-007, and FR-010, proved by E2E-P2.1-03. `subscriptionRef` of the fixture `org_id` equals the vector. `grantIdPaid(paymentId)` equals the SHA-256 hex of `grant:paid:` concatenated with that `payment_id`. The test fails because `subscriptionRef` and `grantIdPaid` are absent. Depends on T001.

**Checkpoint**: E2E-P2.1-01, E2E-P2.1-02, and E2E-P2.1-03 exist and fail in Node and in the workers pool.

### 4.2 User Story 2 - Clinic route contract version (Priority: P2)

**Independent Test**: E2E-P2.1-04, E2E-P2.1-05, E2E-P2.1-06, and E2E-P2.1-07 in harness H-AP.

- [X] T005 [P] [US2] Add the failing test `E2E-P2.1-04` in `ai-platform/test/system/contract-version.system.test.ts` — produces the red test, satisfies FR-009, proved by E2E-P2.1-04. `applyAllMigrations`, then `SELF.fetch` `POST /v1/requests` with an invalid bearer and no `Aip-Contract-Version`. Status 400, body `code` is `contract_version_unsupported`, `accepted_versions` is `[0, 1]`, and `count("ai_request")` is unchanged. The test fails because a missing header is not yet HTTP 400. Depends on T001. Does not edit the H-PKG test files.

- [X] T006 [US2] Add the failing test `E2E-P2.1-05` in `ai-platform/test/system/contract-version.system.test.ts` — produces the red test, satisfies FR-008 and FR-009, proved by E2E-P2.1-05. `GET /v1/capabilities` with `Aip-Contract-Version: 1` echoes that header. The same route with value `2` returns 400 and `contract_version_unsupported`. Depends on T005 (same file). Fails because version 1 is not echoed and version 2 is not HTTP 400.

- [X] T007 [US2] Add the failing test `E2E-P2.1-06` in `ai-platform/test/system/contract-version.system.test.ts` — produces the red test, satisfies FR-009, proved by E2E-P2.1-06. After `setupPromotedFakePolicy` and `mintAat`, `SELF.fetch` `POST /v1/requests` with `Aip-Contract-Version: 1`. `response.headers.get("Aip-Contract-Version")` is `1` before the body is read. The body is `text/event-stream` and the first event is the adapter's accepted event. Depends on T006 (same file). Fails because the streamed response has no `Aip-Contract-Version` header.

- [X] T008 [US2] Run `E2E-P2.1-07` with `cd ai-platform && npm test && npm run test:e2e` — produces the green run of the existing system and e2e suites, satisfies FR-002 and FR-011, proved by E2E-P2.1-07. Titles stay the existing suite titles. Depends on T017, T018, T019, and T020. After T016 the suites that omit the header are red; this task runs once those call sites send `Aip-Contract-Version: 1`. The e2e entitle HTTP 404 is `plan_not_found` from `handleEntitle` after `resetE2eState` deletes `plan`. `/control/*` stays outside `requireAipContractVersion`. This task does not edit `ai-platform/src/worker.ts`. It may edit only `ai-platform/test/e2e/harness/d1.ts` and `ai-platform/test/e2e/harness/control.ts`, and only to apply the catalogue re-seed in the plan.md Files section (reset seeds `standard`, `professional`, `starter`, and `enterprise`; `controlFetch` and `dispatchControl` re-seed the enrolled plan from the entitle body before the handler runs). No new test file. Stay on `cd ai-platform && npm test && npm run test:e2e` until both are green.

**Checkpoint**: E2E-P2.1-04, E2E-P2.1-05, and E2E-P2.1-06 exist and fail. E2E-P2.1-07 is green once T017–T020 have set the header and T008 has re-seeded the e2e catalogue plan.

---

## 5. Implementation

**Purpose**: Sequencing steps 8–19 and 21. Each export is added only after its failing test exists. `packages/vendor-contracts/src/index.ts` re-exports the functions in the three contract files and nothing else.

### 5.1 User Story 1 - Canonical bytes, signatures, and identifiers (Priority: P1)

**Independent Test**: E2E-P2.1-01, E2E-P2.1-02, and E2E-P2.1-03 in harness H-PKG (Node and workerd).

- [X] T009 [US1] Add `canonicalize` and `sha256Hex` in `packages/vendor-contracts/src/canonical.ts` (RFC 8785; SHA-256 hex; no JCS library) and export them from `packages/vendor-contracts/src/index.ts` — produces the canonical and hash API, satisfies FR-003, proved by E2E-P2.1-01. Depends on T002–T007 existing and failing. E2E-P2.1-01 passes in Node and in the workers pool.

- [X] T010 [US1] Add `signCompactJws` and `verifyCompactJws` in `packages/vendor-contracts/src/jws.ts` (Ed25519 over the canonical bytes, compact JWS, header `{alg: "EdDSA", kid}`, WebCrypto `crypto.subtle`) and export them from `packages/vendor-contracts/src/index.ts` — produces the sign and verify API, satisfies FR-004, proved by E2E-P2.1-02. Depends on T009 (same `index.ts`). E2E-P2.1-02 passes in both runtimes. A changed payload or a changed `kid` still fails verification.

- [X] T011 [US1] Add `ulid` (80 random bits), Crockford base-32, `subscriptionRef`, `paymentId`, `grantIdPaid`, `grantIdComp`, `grantIdTransfer`, `coverageEventId`, and `humanRef` in `packages/vendor-contracts/src/identifiers.ts` and export them from `packages/vendor-contracts/src/index.ts` — produces the identifier API, satisfies FR-005, FR-006, FR-007, and FR-012, proved by E2E-P2.1-03. Depends on T010 (same `index.ts`). `subscriptionRef` is `AIC-` plus 8 Crockford characters of SHA-256(`"sub-ref:"` ‖ `org_id`). `paymentId` is SHA-256 hex of `"payment:"` ‖ `provider_id` ‖ `":"` ‖ the provider transaction reference. `grantIdPaid` is SHA-256 over `"grant:paid:"` ‖ `payment_id`. `grantIdComp` is SHA-256 over `"grant:comp:"` ‖ the operator action id. `grantIdTransfer` is SHA-256 over `"grant:transfer:"` ‖ `transfer_id` ‖ `":"` ‖ n. `coverageEventId` is `installation_id` ‖ `":"` ‖ `clinic_seq`. `humanRef` is `CK-`, `PAY-`, `REV-`, or `GR-` plus 8 Crockford characters of the record id. E2E-P2.1-03 passes in both runtimes.

**Checkpoint**: E2E-P2.1-01, E2E-P2.1-02, and E2E-P2.1-03 pass.

### 5.2 User Story 2 - Clinic route contract version (Priority: P2)

**Independent Test**: E2E-P2.1-04, E2E-P2.1-05, E2E-P2.1-06, and E2E-P2.1-07 in harness H-AP.

#### 5.2.1 User Story 2 - Clinic route contract version (part 1)

- [X] T012 [US2] Add `CHANNEL_VERSIONS`, `acceptedVersions`, and `negotiate` in `packages/vendor-contracts/src/version.ts` and export them from `packages/vendor-contracts/src/index.ts` — produces the channel constants and the negotiation helper, satisfies FR-008 and FR-009, proved by E2E-P2.1-04 and E2E-P2.1-05. Depends on T011 (same `index.ts`). Every 04 §7.1 channel constant is 1: Desktop → ABO clinic API `/v1/*` (`Abo-Contract-Version`); ABO console → ABO `/ops/*`; Desktop → backend RPCs (`p_contract_version`); Desktop → platform clinic routes (`Aip-Contract-Version`); Backend feed puller → platform feed (`Aip-Contract-Version`); ABO → `VendorEntrypoint` (`contract_version` on every argument object and every result); Platform Worker → per-clinic DO RPC (`contract_version`); browser return from Paymob → ABO `/return/{provider}` (`v`); ABO ↔ Paymob API and `/notify/{provider}`. The heartbeat ping and `send_email` alerts are not channels. `negotiate` accepts N and N−1 and answers in the request's version. A missing version, or any other version, is `{code: contract_version_unsupported, accepted_versions}`.

- [X] T013 [P] [US2] Add `"vendor-contracts": "file:../packages/vendor-contracts"` under `dependencies` in `ai-platform/package.json` and refresh `ai-platform/package-lock.json` — produces the `file:` dependency, satisfies FR-001 and FR-002, proved by E2E-P2.1-04. Depends on T001. Does not edit `packages/vendor-contracts/src/index.ts`. `ai-platform` keeps no separate copy of canonical JSON, Ed25519 JWS, or the contract-version constants.

- [X] T014 [US2] Add `requireAipContractVersion` and `withAipContractVersion` in `ai-platform/src/vendor/contract-version.ts`, calling `negotiate` from `vendor-contracts` — produces the platform header helpers, satisfies FR-009 and FR-011, proved by E2E-P2.1-04, E2E-P2.1-05, and E2E-P2.1-06. Depends on T012 and T013. `withAipContractVersion` builds a new `Response` with the same status and body and sets `Aip-Contract-Version` to the decimal of the version `negotiate` accepted.

- [X] T015 [US2] Gate the four clinic routes in `ai-platform/src/worker.ts` with `requireAipContractVersion` so a missing or unsupported version returns HTTP 400 `{code: contract_version_unsupported, accepted_versions}` before token verification and before any write — produces the refusal, satisfies FR-009, proved by E2E-P2.1-04 and the version-2 half of E2E-P2.1-05. Depends on T014. Call sites: `GET /v1/capabilities` before `handleDiscoveryRequest`; `POST /v1/requests` before `handleLivePostRequest` (exact pathname `/v1/requests` only, so `POST /v1/requests/` stays the current 404); a `GET` whose pathname starts with `/v1/requests/` and whose reference is non-empty, after the current empty-reference 404 and before `authenticateGetRequest` (`GET /v1/requests/` stays 404); `GET /v1/coverage` before the current 404. `GET /v1/usage` and `/control/*` stay outside the gate. `ai-platform/src/adapter.ts` stays as it is. E2E-P2.1-04 passes. The echo assertions still fail.

- [X] T016 [US2] Echo `Aip-Contract-Version` from `ai-platform/src/worker.ts` on each accepted clinic response by calling `withAipContractVersion`, including the SSE `Response` from `handleAdapterRequest`, before `fetch` returns — produces the echoed header, satisfies FR-009, proved by E2E-P2.1-05 and E2E-P2.1-06. Depends on T015 (same file). For `GET /v1/coverage`, an accepted version still returns the current 404, with the header echoed. The header is on the `Response` before the test reads the body. E2E-P2.1-05 and E2E-P2.1-06 pass. Existing clinic suites that omit the header go red here.

**Checkpoint**: E2E-P2.1-04, E2E-P2.1-05, and E2E-P2.1-06 pass.

#### 5.2.2 User Story 2 - Clinic route contract version (part 2)

- [X] T017 [P] [US2] Set the default header `Aip-Contract-Version: 1` when the caller did not set it, on `invoke`, `getCapabilities`, and `getRequest` in `ai-platform/test/system/harness.ts` — produces the H-AP system default, satisfies FR-011, proved by E2E-P2.1-07. Depends on T016. `operatorFetch` and `/health` do not gain the header.

- [X] T018 [P] [US2] Set the default header `Aip-Contract-Version: 1` when the caller did not set it, on `clinicFetch` in `ai-platform/test/e2e/harness/clinic.ts` — produces the H-AP e2e default, satisfies FR-011, proved by E2E-P2.1-07. Depends on T016.

- [X] T019 [P] [US2] Set `Aip-Contract-Version: 1` on the direct gated clinic `Request`s in `ai-platform/test/system/failure-taxonomy-matrix.system.test.ts`, `ai-platform/test/system/quota-admission-interplay.system.test.ts`, and `ai-platform/test/system/settlement-integrity.system.test.ts` (`POST /v1/requests` and `GET /v1/requests/${ref}`) — produces those call-site headers, satisfies FR-011, proved by E2E-P2.1-07. Depends on T016. `usage-summary.test.ts` stays as it is (`GET /v1/usage` is not a gated route).

- [X] T020 [P] [US2] Set `Aip-Contract-Version: 1` on the remaining direct gated `Request`s: `postStreamBody` in `ai-platform/test/e2e/stage-08-size-json-headers.test.ts`, the S08-059 `SELF.fetch` in `ai-platform/test/e2e/stage-08-guard-sse-adapter.test.ts`, `discoveryRequest` in `ai-platform/test/discovery-http.test.ts`, `buildPostRequest` in `ai-platform/test/worker-request-orchestrator.test.ts`, the `worker.fetch` of `/v1/requests` in `ai-platform/test/log-redaction.test.ts`, and the `POST /v1/requests` and `getRef` calls in `ai-platform/test/worker-entry.test.ts` — produces those call-site headers, satisfies FR-011, proved by E2E-P2.1-07. Depends on T016.

- [X] T021 [US2] Add the `vendor-contracts` job to `.github/workflows/ci.yml` — produces the package CI job, satisfies FR-002, proved by E2E-P2.1-01, E2E-P2.1-02, and E2E-P2.1-03. Depends on T008. The job checks out the repo, sets up Node 22, runs `npm ci` in `packages/vendor-contracts/`, then `npm test`. Existing jobs stay in place (rule V7).

**Checkpoint**: E2E-P2.1-07 passes. The package CI job is present.

---

## 6. Verification

**Purpose**: This unit's H-PKG and H-AP suites pass, then every earlier suite on this unit's harnesses is still green (rule S2). Consumes Binding is none. P1.x is a parallel track and this plan names no H-BK command. The pre-existing platform suites inside the third command are the regression.

- [X] T022 Run harness H-PKG and harness H-AP and confirm both are green — produces the green run, satisfies FR-002, FR-011, SC-001, and SC-002, proved by E2E-P2.1-01 through E2E-P2.1-07. Depends on T001–T021. Run `cd packages/vendor-contracts && npm test` (Node, then the workers pool: E2E-P2.1-01, E2E-P2.1-02, E2E-P2.1-03). Run `cd ai-platform && npx vitest run --config vitest.workers.config.ts test/system/contract-version.system.test.ts` (E2E-P2.1-04, E2E-P2.1-05, E2E-P2.1-06). Run `cd ai-platform && npm test && npm run test:e2e` (E2E-P2.1-07, the pre-existing system and e2e suites with the default header). There is no earlier package suite. A full-product `npm test` is not this command.

---

## 7. Documentation

**Purpose**: Written after T022 is green (rule S8). The plan leaves `quickstart.md` for implement. `contracts/` stays a plan-phase artifact.

- [X] T023 Create `specs/063-abo-p2-1-package-core-canonical-signing/quickstart.md` from the plan's quickstart outline — produces this unit's quickstart, satisfies FR-001 through FR-012, proved by E2E-P2.1-01 through E2E-P2.1-07. Depends on T022. Sections: (1) what was implemented — the package APIs in `contracts/`, the golden vectors, `ai-platform/src/vendor/contract-version.ts`, the clinic-route gate and echo in `ai-platform/src/worker.ts`, the H-AP default header, and the package CI job; (2) files this unit adds or modifies — the Files section of `plan.md`, with no earlier-unit files, no combined counts, and no full-suite regression (that is T022); (3) harness commands for this unit's tests only — `cd packages/vendor-contracts && npm test`, `cd ai-platform && npx vitest run --config vitest.workers.config.ts test/system/contract-version.system.test.ts`, and `cd ai-platform && npm test && npm run test:e2e`; (4) how to inspect the change; (5) the entry point → module chain per E2E id below. Every scenario is asserted by H-PKG or H-AP, so this file records harness commands only.

| ID | Chain |
| --- | --- |
| E2E-P2.1-01 | `packages/vendor-contracts/test/canonical.test.ts` (Node vitest and the workers pool) → `canonicalize` in `src/canonical.ts` → `vectors/canonical.json` |
| E2E-P2.1-02 | `packages/vendor-contracts/test/jws.test.ts` (Node vitest and the workers pool) → `signCompactJws` / `verifyCompactJws` in `src/jws.ts` → `crypto.subtle` → `vectors/jws.json` |
| E2E-P2.1-03 | `packages/vendor-contracts/test/identifiers.test.ts` (Node vitest and the workers pool) → `subscriptionRef` and `grantIdPaid` in `src/identifiers.ts` → `sha256Hex` → `vectors/identifiers.json` |
| E2E-P2.1-04 | `SELF.fetch` `POST /v1/requests` → `ai-platform/src/worker.ts` `fetch` → `requireAipContractVersion` in `src/vendor/contract-version.ts` → `negotiate` in the package → HTTP 400; `count("ai_request")` unchanged |
| E2E-P2.1-05 | `SELF.fetch` `GET /v1/capabilities` → `worker.ts` `fetch` → `requireAipContractVersion` → on version 1, `handleDiscoveryRequest` then `withAipContractVersion`; on version 2, HTTP 400 |
| E2E-P2.1-06 | `applyAllMigrations` → `setupPromotedFakePolicy` → `mintAat` → `SELF.fetch` `POST /v1/requests` → `worker.ts` `fetch` → `requireAipContractVersion` → `handleLivePostRequest` → `handleAdapterRequest` in `src/adapter.ts` → `withAipContractVersion` on that `Response` → read `Aip-Contract-Version` → then read the SSE body |
| E2E-P2.1-07 | Existing suites → `ai-platform/test/system/harness.ts` and `ai-platform/test/e2e/harness/clinic.ts` (and the direct clinic `Request`s in Files) set `Aip-Contract-Version: 1` → `worker.ts` `fetch`. E2e entitle → `ai-platform/test/e2e/harness/d1.ts` `resetPlatformState` and `ai-platform/test/e2e/harness/control.ts` re-seed `plan` → `handleEntitle` |

---

## 8. Dependencies & Execution Order

### 8.1 Phase Dependencies

- **Setup (T001)**: No dependencies. Starts immediately. Blocks every test.
- **Tests (T002–T008)**: T002, T003, T004, and T005 start once T001 is done. T006 appends after T005. T007 appends after T006. T002–T007 are observed failing before T009. T008 is Sequencing step 20 and runs after T017–T020, then T021 runs.
- **Implementation (T009–T021)**: T009–T016 follow Sequencing after T002–T007 exist and fail. T017–T020 follow T016 and touch different files. T021 follows T008.
- **Verification (T022)**: After every implementation task, including T021.
- **Documentation (T023)**: After T022 is green.

### 8.2 User Story Dependencies

- **User Story 1 (P1)**: No dependency on User Story 2. Tests T002, T003, and T004 are `[P]` after T001. Implementation T009 waits until T002–T007 are failing, because Sequencing writes E2E-P2.1-01 through E2E-P2.1-06 before the package functions. T010 waits on T009. T011 waits on T010. E2E-P2.1-01 passes at T009, E2E-P2.1-02 at T010, E2E-P2.1-03 at T011.
- **User Story 2 (P2)**: Depends on the package skeleton from User Story 1 (T001), not on T002–T004. Tests T005–T007 may start once T001 is done. T006 and T007 stay sequential on `ai-platform/test/system/contract-version.system.test.ts`. Implementation T012 waits on T011. T013 is `[P]` with T012. T014 waits on T012 and T013. T015 waits on T014. T016 waits on T015. E2E-P2.1-04 passes at T015. E2E-P2.1-05 and E2E-P2.1-06 pass at T016. T017–T020 are `[P]` after T016. T008 waits on T017–T020. T021 waits on T008.

### 8.3 Parallel Opportunities

- T002, T003, T004, and T005 are `[P]` after T001. T002–T004 edit three different files under `packages/vendor-contracts/`. T005 creates `ai-platform/test/system/contract-version.system.test.ts`. T006 and T007 append to that file and are not `[P]`.
- T009, T010, T011, and T012 all edit `packages/vendor-contracts/src/index.ts`. They are not `[P]`.
- T013 edits `ai-platform/package.json` and `ai-platform/package-lock.json`. It is `[P]` with T012 and waits for neither T009 nor T010. T014 waits for both T012 and T013.
- T015 and T016 edit `ai-platform/src/worker.ts`. They are not `[P]`.
- T017, T018, T019, and T020 are `[P]` after T016. Each edits different files.
- T008, T021, T022, and T023 are single tasks. T021 is not `[P]` with T017–T020: Sequencing places the CI job after E2E-P2.1-07 is green.

```bash
# Two User Story 1 test tasks launched together after T001.
# Different files. Neither waits on the other.
Task: "T002 [P] [US1] Add the failing test E2E-P2.1-01 in packages/vendor-contracts/test/canonical.test.ts"
Task: "T003 [P] [US1] Add the failing test E2E-P2.1-02 in packages/vendor-contracts/test/jws.test.ts"
```
