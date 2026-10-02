# Implementation Plan: Package core: canonical JSON, signing, identifiers, version constants

**Branch**: `ai/063-abo-p2-1-package-core-canonical-signing` | **Date**: 2026-10-02 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `specs/063-abo-p2-1-package-core-canonical-signing/spec.md`

**Note**: This template is filled in by the `/abo-plan` command. See `.specify/templates/plan-template.md` for the execution workflow.

## Summary

P2.1 adds `packages/vendor-contracts/`, a TypeScript ESM package that canonicalises JSON (RFC 8785), hashes with SHA-256 hex, signs and verifies Ed25519 compact JWS on WebCrypto, computes the 03 §7 identifiers, and exports the 04 §7.1 channel constants plus the negotiation helper. It sits in phase P2, size M, with **Depends** none, and it runs in parallel with P1.x.

`ai-platform` takes that package as a `file:` dependency. `src/vendor/contract-version.ts` checks `Aip-Contract-Version` on the clinic routes before token verification and echoes it on the response, including a streamed response before the SSE body is read. A package CI job runs the package tests.

## Technical Context

**Language/Version**: TypeScript ESM (`"type": "module"`), TypeScript `^5.9.2`, Node `>=22` (the engines field in `ai-platform/package.json`). The package workers pool uses Wrangler compatibility date `2026-05-03`, the date in `ai-platform/wrangler.toml`.

**Primary Dependencies**: WebCrypto `crypto.subtle` for SHA-256 and Ed25519 (04 §1.1). RFC 8785 implemented in the package. No JCS or ULID library. `ai-platform` depends on `vendor-contracts` via `file:../packages/vendor-contracts`. The workers-pool runner is the one `ai-platform` already uses (`vitest` `~3.2.4`, `@cloudflare/vitest-pool-workers` `0.8.71`).

**Storage**: None. This unit defines no entities. Golden vectors are files under `packages/vendor-contracts/vectors/`. E2E-P2.1-04 reads the existing D1 table `ai_request` and asserts no new row.

**Testing**: H-PKG for E2E-P2.1-01, E2E-P2.1-02, and E2E-P2.1-03 (`packages/vendor-contracts/test/`, Node vitest and the workers pool). H-AP for E2E-P2.1-04, E2E-P2.1-05, and E2E-P2.1-06 (`ai-platform/test/system/contract-version.system.test.ts`, `SELF.fetch` on `ai-platform/src/worker.ts`). E2E-P2.1-07 is the existing `ai-platform` unit, workers-pool, and e2e suites after the harness sends the header. Tests are written to fail before the package exports and the worker gate exist.

**Target Platform**: workerd and Node for the package. The AI Platform worker on Cloudflare for the clinic-route header. The backend does not import the package (FR-001, 04 §6.2).

**Project Type**: New shared package plus the platform header wiring named in the codebase cell (rule S3). One package CI job in the existing `.github/workflows/ci.yml` (FR-002, rule V7).

**Performance Goals**: Clinic scale, a few orders a day (02 §7 principle I). The version check is a header parse before token verification. No separate throughput target.

**Constraints**: RFC 8785 bytes, SHA-256 hex, Ed25519 compact JWS (`alg` `EdDSA`, `kid`) on WebCrypto (FR-003, FR-004). Channel constants are all 1 (FR-008). The receiver accepts N and N−1 and answers in the request's version; a missing version or any other version is HTTP 400 `{code: contract_version_unsupported, accepted_versions}` before token verification and before any write (FR-009, 04 §7.2, 04 §4.2). The streamed clinic response carries `Aip-Contract-Version` on the `Response` before the SSE body is read (FR-009). Repository has no workspace tooling; the dependency is `file:` (FR-001). Enrollment, `/control/entitle`, and the entitlement, plan, and invoice tables stay until their owning units (rule S9).

**Scale/Scope**: Size M (rule S3, 20–32 tasks, 2 user stories). Codebases: `packages/vendor-contracts/` and the thin `ai-platform/` header wiring. Implied task count is 22.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

Re-run of 02 §7 against this unit and `.specify/memory/constitution.md` (rule S12). Spikes are none, so there is no research phase. The Phase 1 artifacts (`contracts/`) use the same placement as this check.

- [x] Feature scope still fits small-to-mid-size multi-branch clinics; hospital-scale or
      enterprise-only requirements are explicitly rejected or separately ratified

  One shared package and a header check on the existing clinic routes (spec §4.1, 02 §7 principle I). Sized for a few orders a day and one operator. No hospital-scale or enterprise requirement.

- [x] Design keeps a simple operational model with no microservices, message queues,
      Kubernetes, or custom primary backend service

  The package is a `file:` dependency of the existing worker, not a service. The CI job is another job in the existing workflow. 02 §7 principle I: no microservices, queues, or Kubernetes. 02 §7 principle II: no custom core backend.

- [x] Layer ownership is explicit: Flutter handles UI/orchestration, Supabase handles
      backend capabilities, PostgreSQL owns domain integrity, and AI stays isolated

  Canonical JSON, JWS, identifiers, and the version constants live in `packages/vendor-contracts/`. `ai-platform` imports them. The backend cannot import the package (FR-001, 04 §6.2, 02 §7 principle II). Flutter is untouched. The ABO does not gain a dependency in this unit.

- [x] Protected writes, validation, permissions, and transactional rules remain enforced
      through PostgreSQL constraints, triggers, RLS, or RPC functions

  This unit adds no clinic-side write and no PostgreSQL object. A clinic `POST /v1/requests` without `Aip-Contract-Version` writes no `ai_request` row (FR-009, E2E-P2.1-04). Existing PostgreSQL constraints, triggers, RLS, and RPCs stay as they are (02 §7 principle III).

- [x] Security remains authenticated, tenant-scoped, branch-scoped, permission-gated,
      auditable, and soft-delete-preserving

  On an accepted version the existing token verification still runs. A missing or unsupported version is refused before that verification and before any write (04 §4.2, 04 §7.2, 02 §7 principle IV). Application flows gain no delete path.

- [x] AI actions remain human-approved, have no direct database/backend access, and the
      feature still works in a degraded manual mode when AI is unavailable

  The package has no database credential. The backend cannot import it (02 §7 principles II and V). Clinical work does not call these functions.

## Project Structure

### Documentation (this feature)

```text
specs/063-abo-p2-1-package-core-canonical-signing/
├── plan.md
├── spec.md
├── quickstart.md              # implement writes this after verification; outline below
├── contracts/
│   ├── canonical-hash-jws.md
│   ├── identifiers.md
│   └── contract-version.md
└── tasks.md                   # /abo-tasks, not this phase
```

`research.md` is omitted. **Spikes** is `None`; the cited design is the research (rule S6).

`data-model.md` is omitted. The spec defines no entities.

`contracts/` records the frozen canonical, hash, and JWS APIs, the identifier functions and vector schema, and the channel constants plus the refusal body. Later units bind to these files (P2.2, P3.1, P5.2, P6.1).

#### quickstart.md outline

Implement writes `quickstart.md` after the H-PKG and H-AP runs below are green. Sections:

1. What was implemented — the package APIs in `contracts/`, the golden vectors, `ai-platform/src/vendor/contract-version.ts`, the clinic-route gate and echo in `ai-platform/src/worker.ts`, the H-AP default header, and the package CI job.
2. Files this unit adds or modifies — the Files section of this plan.
3. Harness commands for this unit's tests only:

```bash
cd packages/vendor-contracts && npm test
cd ai-platform && npx vitest run --config vitest.workers.config.ts test/system/contract-version.system.test.ts
cd ai-platform && npm test && npm run test:e2e
```

The first command is H-PKG (Node, then the workers pool). The second is E2E-P2.1-04, E2E-P2.1-05, and E2E-P2.1-06. The third is E2E-P2.1-07 (existing unit, system, and e2e suites).

4. Entry point → module chain per E2E id (rule S8):

| ID | Chain |
| --- | --- |
| E2E-P2.1-01 | `packages/vendor-contracts/test/canonical.test.ts` (Node vitest and the workers pool) → `canonicalize` in `src/canonical.ts` → `vectors/canonical.json` |
| E2E-P2.1-02 | `packages/vendor-contracts/test/jws.test.ts` (Node vitest and the workers pool) → `signCompactJws` / `verifyCompactJws` in `src/jws.ts` → `crypto.subtle` → `vectors/jws.json` |
| E2E-P2.1-03 | `packages/vendor-contracts/test/identifiers.test.ts` (Node vitest and the workers pool) → `subscriptionRef` and `grantIdPaid` in `src/identifiers.ts` → `sha256Hex` → `vectors/identifiers.json` |
| E2E-P2.1-04 | `SELF.fetch` `POST /v1/requests` → `ai-platform/src/worker.ts` `fetch` → `requireAipContractVersion` in `src/vendor/contract-version.ts` → `negotiate` in the package → HTTP 400; `count("ai_request")` unchanged |
| E2E-P2.1-05 | `SELF.fetch` `GET /v1/capabilities` → `worker.ts` `fetch` → `requireAipContractVersion` → on version 1, `handleDiscoveryRequest` then `withAipContractVersion`; on version 2, HTTP 400 |
| E2E-P2.1-06 | `applyAllMigrations` → `setupPromotedFakePolicy` → `mintAat` → `SELF.fetch` `POST /v1/requests` → `worker.ts` `fetch` → `requireAipContractVersion` → `handleLivePostRequest` → `handleAdapterRequest` in `src/adapter.ts` → `withAipContractVersion` on that `Response` → read `Aip-Contract-Version` → then read the SSE body |
| E2E-P2.1-07 | Existing suites → `ai-platform/test/system/harness.ts` and `ai-platform/test/e2e/harness/clinic.ts` (and the direct clinic `Request`s in Files) set `Aip-Contract-Version: 1` → `worker.ts` `fetch` |

### Source Code (repository root)

```text
packages/vendor-contracts/
├── package.json
├── package-lock.json
├── tsconfig.json
├── wrangler.toml
├── vitest.config.ts
├── vitest.workers.config.ts
├── src/
│   ├── index.ts
│   ├── canonical.ts
│   ├── jws.ts
│   ├── identifiers.ts
│   └── version.ts
├── vectors/
│   ├── canonical.json
│   ├── identifiers.json
│   └── jws.json
└── test/
    ├── canonical.test.ts
    ├── jws.test.ts
    └── identifiers.test.ts

ai-platform/
├── package.json
├── package-lock.json
├── src/
│   ├── vendor/
│   │   └── contract-version.ts
│   └── worker.ts
└── test/
    ├── discovery-http.test.ts
    ├── log-redaction.test.ts
    ├── worker-entry.test.ts
    ├── worker-request-orchestrator.test.ts
    ├── e2e/
    │   ├── harness/
    │   │   └── clinic.ts
    │   ├── stage-08-guard-sse-adapter.test.ts
    │   └── stage-08-size-json-headers.test.ts
    └── system/
        ├── contract-version.system.test.ts
        ├── failure-taxonomy-matrix.system.test.ts
        ├── harness.ts
        ├── quota-admission-interplay.system.test.ts
        └── settlement-integrity.system.test.ts

.github/workflows/ci.yml
```

**Structure Decision**: The package source is TypeScript ESM loaded directly by Vitest and by Wrangler. There is no `dist/` emit. `ai-platform` keeps its existing `wrangler.toml`; the workers-pool run of E2E-P2.1-04 through E2E-P2.1-07 is the bundling proof (FR-002). `src/adapter.ts` stays as it is: `worker.ts` copies the adapter `Response` body and sets `Aip-Contract-Version` before `fetch` returns, so the header is on the `Response` before the SSE body is read. `GET /v1/usage` and `/control/*` are outside the gate. Message types, WebAuthn, Access, and the testkit are P2.2 and are not files in this tree.

## Consumes Binding

None.

## Files

| File | FR |
| --- | --- |
| `specs/063-abo-p2-1-package-core-canonical-signing/contracts/canonical-hash-jws.md` | FR-003, FR-004, FR-010 |
| `specs/063-abo-p2-1-package-core-canonical-signing/contracts/identifiers.md` | FR-005, FR-006, FR-007, FR-010, FR-012 |
| `specs/063-abo-p2-1-package-core-canonical-signing/contracts/contract-version.md` | FR-008, FR-009, FR-011 |
| `specs/063-abo-p2-1-package-core-canonical-signing/quickstart.md` (implement, after verification) | FR-001–FR-012 |
| `packages/vendor-contracts/package.json` | FR-001, FR-002 |
| `packages/vendor-contracts/package-lock.json` | FR-002 |
| `packages/vendor-contracts/tsconfig.json` | FR-002 |
| `packages/vendor-contracts/wrangler.toml` | FR-002 |
| `packages/vendor-contracts/vitest.config.ts` | FR-002 |
| `packages/vendor-contracts/vitest.workers.config.ts` | FR-002 |
| `packages/vendor-contracts/src/index.ts` | FR-003, FR-004, FR-005, FR-006, FR-007, FR-008, FR-009, FR-012 |
| `packages/vendor-contracts/src/canonical.ts` | FR-003 |
| `packages/vendor-contracts/src/jws.ts` | FR-004 |
| `packages/vendor-contracts/src/identifiers.ts` | FR-005, FR-006, FR-007, FR-012 |
| `packages/vendor-contracts/src/version.ts` | FR-008, FR-009 |
| `packages/vendor-contracts/vectors/canonical.json` | FR-010 |
| `packages/vendor-contracts/vectors/identifiers.json` | FR-010 |
| `packages/vendor-contracts/vectors/jws.json` | FR-010 |
| `packages/vendor-contracts/test/canonical.test.ts` | FR-003, FR-010 |
| `packages/vendor-contracts/test/jws.test.ts` | FR-004, FR-010 |
| `packages/vendor-contracts/test/identifiers.test.ts` | FR-006, FR-007, FR-010 |
| `ai-platform/package.json` | FR-001, FR-002 |
| `ai-platform/package-lock.json` | FR-001, FR-002 |
| `ai-platform/src/vendor/contract-version.ts` | FR-009, FR-011 |
| `ai-platform/src/worker.ts` | FR-009 |
| `ai-platform/test/system/contract-version.system.test.ts` | FR-008, FR-009 |
| `ai-platform/test/system/harness.ts` | FR-011 |
| `ai-platform/test/e2e/harness/clinic.ts` | FR-011 |
| `ai-platform/test/system/failure-taxonomy-matrix.system.test.ts` | FR-011 |
| `ai-platform/test/system/quota-admission-interplay.system.test.ts` | FR-011 |
| `ai-platform/test/system/settlement-integrity.system.test.ts` | FR-011 |
| `ai-platform/test/e2e/stage-08-size-json-headers.test.ts` | FR-011 |
| `ai-platform/test/e2e/stage-08-guard-sse-adapter.test.ts` | FR-011 |
| `ai-platform/test/discovery-http.test.ts` | FR-011 |
| `ai-platform/test/worker-request-orchestrator.test.ts` | FR-011 |
| `ai-platform/test/log-redaction.test.ts` | FR-011 |
| `ai-platform/test/worker-entry.test.ts` | FR-011 |
| `.github/workflows/ci.yml` | FR-002 |

`packages/vendor-contracts/package.json` name is `vendor-contracts`, `"type": "module"`, `"exports": { ".": "./src/index.ts" }`. `ai-platform/package.json` gains `"vendor-contracts": "file:../packages/vendor-contracts"` under `dependencies`. Scripts: `"test"` runs the Node config and then the workers config.

`src/index.ts` re-exports the functions in the three contract files and nothing else.

`ai-platform/src/worker.ts` calls `requireAipContractVersion` and, on success, `withAipContractVersion`:

- `GET /v1/capabilities`, before `handleDiscoveryRequest`.
- `POST /v1/requests`, before `handleLivePostRequest`. Exact pathname `/v1/requests` only, so `POST /v1/requests/` stays the current 404 (S08-002).
- `GET` whose pathname starts with `/v1/requests/` and whose reference is non-empty, after the current empty-reference 404 and before `authenticateGetRequest`. `GET /v1/requests/` stays 404.
- `GET /v1/coverage`, before the current 404. An accepted version still returns that 404, with the header echoed. This unit does not add a coverage handler.

`withAipContractVersion` builds a new `Response` with the same status and body and sets `Aip-Contract-Version` to the decimal of the version `negotiate` accepted. For the SSE path that body is the stream from `handleAdapterRequest`. The header is set before `fetch` returns and before the test reads the body.

The H-AP default is the header `Aip-Contract-Version` with value `1` when the caller did not set it:

- `invoke`, `getCapabilities`, and `getRequest` in `ai-platform/test/system/harness.ts`.
- `clinicFetch` in `ai-platform/test/e2e/harness/clinic.ts`.
- The direct clinic `Request`s that enter `worker.ts` `fetch` for a gated route: `failure-taxonomy-matrix.system.test.ts`, `quota-admission-interplay.system.test.ts`, `settlement-integrity.system.test.ts` (`POST /v1/requests` and `GET /v1/requests/${ref}`), `postStreamBody` in `stage-08-size-json-headers.test.ts`, the S08-059 `SELF.fetch` in `stage-08-guard-sse-adapter.test.ts`, `discoveryRequest` in `discovery-http.test.ts`, `buildPostRequest` in `worker-request-orchestrator.test.ts`, the `worker.fetch` of `/v1/requests` in `log-redaction.test.ts`, and the `POST /v1/requests` and `getRef` calls in `worker-entry.test.ts`.

`operatorFetch` and `/health` do not gain the header. `GET /v1/usage` is not a gated route, so `usage-summary.test.ts` stays as it is.

The CI job `vendor-contracts` is added to `.github/workflows/ci.yml` and leaves the existing jobs in place (rule V7). It checks out the repo, sets up Node 22, runs `npm ci` in `packages/vendor-contracts/`, then `npm test`.

## Test Layout

Titles start with the E2E id (rule V3). H-PKG tests import the package exports and fail while those exports are absent. H-AP tests call `SELF.fetch` and fail while `worker.ts` does not yet refuse a missing header.

| ID | Harness | Test |
| --- | --- | --- |
| E2E-P2.1-01 | H-PKG | `packages/vendor-contracts/test/canonical.test.ts`, run by `vitest.config.ts` and by `vitest.workers.config.ts`. Title `E2E-P2.1-01`. Every object in `vectors/canonical.json` canonicalises to the fixture bytes in that runtime. |
| E2E-P2.1-02 | H-PKG | `packages/vendor-contracts/test/jws.test.ts`, both configs. Title `E2E-P2.1-02`. The runtime reproduces the fixture compact JWS and `verifyCompactJws` accepts it. A changed payload or a changed `kid` returns false. |
| E2E-P2.1-03 | H-PKG | `packages/vendor-contracts/test/identifiers.test.ts`, both configs. Title `E2E-P2.1-03`. `subscriptionRef` of the fixture `org_id` equals the vector. `grantIdPaid(paymentId)` equals SHA-256 hex of `grant:paid:` concatenated with that `payment_id`. |
| E2E-P2.1-04 | H-AP | `ai-platform/test/system/contract-version.system.test.ts`. Title `E2E-P2.1-04`. `applyAllMigrations`, then `SELF.fetch` `POST /v1/requests` with an invalid bearer and no `Aip-Contract-Version`. Status 400, body `code` is `contract_version_unsupported`, `accepted_versions` is `[0, 1]`, and `count("ai_request")` is unchanged. |
| E2E-P2.1-05 | H-AP | Same file. Title `E2E-P2.1-05`. `GET /v1/capabilities` with `Aip-Contract-Version: 1` echoes that header. The same route with value `2` returns 400 and `contract_version_unsupported`. |
| E2E-P2.1-06 | H-AP | Same file. Title `E2E-P2.1-06`. After `setupPromotedFakePolicy` and `mintAat`, `SELF.fetch` `POST /v1/requests` with `Aip-Contract-Version: 1`. `response.headers.get("Aip-Contract-Version")` is `1` before the body is read. The body is `text/event-stream` and the first event is the adapter's accepted event. |
| E2E-P2.1-07 | H-AP | `cd ai-platform && npm test && npm run test:e2e`. Title is the existing suite titles. System and e2e suites pass with the default header on gated clinic routes. |

Ed25519 via WebCrypto is deterministic (RFC 8032). The JWS vector stores one compact JWS. Node and workerd each reproduce it and verify it, which is a signature made on either runtime checking on the other.

## Sequencing

Tests are written and observed failing before the package functions and the worker gate.

1. Add the package skeleton (`package.json`, lockfile, `tsconfig.json`, `wrangler.toml`, both Vitest configs) and an `src/index.ts` that does not yet export the APIs.
2. Add `vectors/canonical.json` and `test/canonical.test.ts` (E2E-P2.1-01). Run it in Node and in the workers pool. It fails because `canonicalize` is absent.
3. Add `vectors/jws.json` and `test/jws.test.ts` (E2E-P2.1-02). Both runs fail because `signCompactJws` and `verifyCompactJws` are absent.
4. Add `vectors/identifiers.json` and `test/identifiers.test.ts` (E2E-P2.1-03). Both runs fail because `subscriptionRef` and `grantIdPaid` are absent.
5. Add E2E-P2.1-04 in `ai-platform/test/system/contract-version.system.test.ts`. Run it. It fails because a missing header is not yet HTTP 400.
6. Add E2E-P2.1-05 in that file. Run it. It fails because version 1 is not echoed and version 2 is not HTTP 400.
7. Add E2E-P2.1-06 in that file. Run it. It fails because the streamed response has no `Aip-Contract-Version` header.
8. Add `src/canonical.ts` (`canonicalize`, `sha256Hex`) and export them. E2E-P2.1-01 passes in both runtimes.
9. Add `src/jws.ts` and export it. E2E-P2.1-02 passes in both runtimes.
10. Add `src/identifiers.ts` (`ulid`, Crockford, `subscriptionRef`, `paymentId`, the three `grantId*` functions, `coverageEventId`, `humanRef`) and export them. E2E-P2.1-03 passes in both runtimes.
11. Add `src/version.ts` (`CHANNEL_VERSIONS`, `acceptedVersions`, `negotiate`) and export it from `src/index.ts`.
12. Add the `file:` dependency to `ai-platform/package.json` and refresh `ai-platform/package-lock.json`.
13. Add `ai-platform/src/vendor/contract-version.ts`.
14. Gate the four clinic routes in `worker.ts` so a missing or unsupported version returns 400 before token verification. E2E-P2.1-04 passes, and the version-2 half of E2E-P2.1-05 passes. The echo assertions still fail.
15. Echo `Aip-Contract-Version` from `worker.ts` on each accepted clinic response, including the SSE `Response` from `handleAdapterRequest`, before `fetch` returns. E2E-P2.1-05 and E2E-P2.1-06 pass. Existing clinic suites that omit the header go red here.
16. Set the default header in `ai-platform/test/system/harness.ts`.
17. Set the default header in `ai-platform/test/e2e/harness/clinic.ts`.
18. Set the header on the direct gated `Request`s in the system files (`failure-taxonomy-matrix.system.test.ts`, `quota-admission-interplay.system.test.ts`, `settlement-integrity.system.test.ts`).
19. Set the header on the remaining direct gated `Request`s (`stage-08-size-json-headers.test.ts`, `stage-08-guard-sse-adapter.test.ts`, `discovery-http.test.ts`, `worker-request-orchestrator.test.ts`, `log-redaction.test.ts`, `worker-entry.test.ts`).
20. Run E2E-P2.1-07 (`npm test` and `npm run test:e2e` in `ai-platform`) and keep going until both are green.
21. Add the `vendor-contracts` CI job.
22. Write `quickstart.md` from the outline above.

Each step is one task. The implied count is 22, inside size M (20–32). The direct header edits are two tasks grouped by call site, not one task per file. The count is not padded.

## Complexity Tracking

No constitution violation. 02 §7 records none for this unit, and every Constitution Check box is ticked.
