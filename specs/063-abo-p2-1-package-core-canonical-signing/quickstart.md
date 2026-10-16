# Package core: canonical JSON, signing, identifiers, version constants

**Unit**: P2.1 · **Harness**: H-PKG, H-AP · **Verification**: T022 green

## 1. What was implemented

Shared package `packages/vendor-contracts/` and thin AI Platform header wiring (FR-001 through FR-012).

- **Package APIs (frozen in `contracts/`).** RFC 8785 `canonicalize` and `sha256Hex`; Ed25519 compact JWS `signCompactJws` / `verifyCompactJws` on WebCrypto; identifier helpers (`subscriptionRef`, `grantIdPaid`, and the rest of `identifiers.md`); `CHANNEL_VERSIONS`, `acceptedVersions`, and `negotiate` for contract-version channels (FR-003–FR-009, FR-012).
- **Golden vectors.** `packages/vendor-contracts/vectors/canonical.json`, `jws.json`, and `identifiers.json` drive H-PKG conformance in Node and workerd (FR-010).
- **Platform header helpers.** `ai-platform/src/vendor/contract-version.ts` exposes `requireAipContractVersion` and `withAipContractVersion`, calling `negotiate` from the package (FR-009, FR-011).
- **Clinic-route gate and echo.** `ai-platform/src/worker.ts` refuses missing or unsupported `Aip-Contract-Version` on `GET /v1/capabilities`, `POST /v1/requests`, non-empty `GET /v1/requests/{ref}`, and `GET /v1/coverage` before token verification and before any write; accepted responses echo the negotiated version, including streamed SSE (FR-009). `GET /v1/usage` and `/control/*` stay outside the gate.
- **H-AP default header.** System and e2e harnesses, plus direct gated `Request`s named in the plan Files section, send `Aip-Contract-Version: 1` when the caller did not set it (FR-011). E2e catalogue re-seed in `d1.ts` and `control.ts` keeps entitle paths green after platform state reset.
- **Package CI job.** `.github/workflows/ci.yml` job `vendor-contracts` runs `npm ci` and `npm test` in `packages/vendor-contracts/` on Node 22 (FR-002).

## 2. Files this unit adds or modifies

| File | FR |
| --- | --- |
| `specs/063-abo-p2-1-package-core-canonical-signing/contracts/canonical-hash-jws.md` | FR-003, FR-004, FR-010 |
| `specs/063-abo-p2-1-package-core-canonical-signing/contracts/identifiers.md` | FR-005, FR-006, FR-007, FR-010, FR-012 |
| `specs/063-abo-p2-1-package-core-canonical-signing/contracts/contract-version.md` | FR-008, FR-009, FR-011 |
| `specs/063-abo-p2-1-package-core-canonical-signing/quickstart.md` | FR-001–FR-012 |
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
| `ai-platform/test/e2e/harness/d1.ts` | FR-011 |
| `ai-platform/test/e2e/harness/control.ts` | FR-011 |
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

Full-suite regression is verification task T022, not this file.

## 3. Harness commands for this unit's tests only

The first command is H-PKG (Node, then the workers pool). The second is E2E-P2.1-04, E2E-P2.1-05, and E2E-P2.1-06. The third is E2E-P2.1-07 (existing unit, system, and e2e suites).

```bash
cd packages/vendor-contracts && npm test
cd ai-platform && npx vitest run --config vitest.workers.config.ts test/system/contract-version.system.test.ts
cd ai-platform && npm test && npm run test:e2e
```

## 4. How to inspect the change

Every scenario below is asserted by H-PKG or H-AP; use the harness commands in §3 to reproduce.

- **Frozen contracts:** `specs/063-abo-p2-1-package-core-canonical-signing/contracts/` — canonical/hash/JWS, identifiers, and channel negotiation.
- **Package implementation:** `packages/vendor-contracts/src/` and golden fixtures under `vectors/`.
- **Worker gate:** `ai-platform/src/worker.ts` (`requireAipContractVersion` / `withAipContractVersion`) and `ai-platform/src/vendor/contract-version.ts`.
- **Dedicated system tests:** `ai-platform/test/system/contract-version.system.test.ts` (E2E-P2.1-04 through E2E-P2.1-06).
- **CI:** `.github/workflows/ci.yml` job `vendor-contracts`.

## 5. Entry point → module chain

| ID | Chain |
| --- | --- |
| E2E-P2.1-01 | `packages/vendor-contracts/test/canonical.test.ts` (Node vitest and the workers pool) → `canonicalize` in `src/canonical.ts` → `vectors/canonical.json` |
| E2E-P2.1-02 | `packages/vendor-contracts/test/jws.test.ts` (Node vitest and the workers pool) → `signCompactJws` / `verifyCompactJws` in `src/jws.ts` → `crypto.subtle` → `vectors/jws.json` |
| E2E-P2.1-03 | `packages/vendor-contracts/test/identifiers.test.ts` (Node vitest and the workers pool) → `subscriptionRef` and `grantIdPaid` in `src/identifiers.ts` → `sha256Hex` → `vectors/identifiers.json` |
| E2E-P2.1-04 | `SELF.fetch` `POST /v1/requests` → `ai-platform/src/worker.ts` `fetch` → `requireAipContractVersion` in `src/vendor/contract-version.ts` → `negotiate` in the package → HTTP 400; `count("ai_request")` unchanged |
| E2E-P2.1-05 | `SELF.fetch` `GET /v1/capabilities` → `worker.ts` `fetch` → `requireAipContractVersion` → on version 1, `handleDiscoveryRequest` then `withAipContractVersion`; on version 2, HTTP 400 |
| E2E-P2.1-06 | `applyAllMigrations` → `setupPromotedFakePolicy` → `mintAat` → `SELF.fetch` `POST /v1/requests` → `worker.ts` `fetch` → `requireAipContractVersion` → `handleLivePostRequest` → `handleAdapterRequest` in `src/adapter.ts` → `withAipContractVersion` on that `Response` → read `Aip-Contract-Version` → then read the SSE body |
| E2E-P2.1-07 | Existing suites → `ai-platform/test/system/harness.ts` and `ai-platform/test/e2e/harness/clinic.ts` (and the direct clinic `Request`s in Files) set `Aip-Contract-Version: 1` → `worker.ts` `fetch`. E2e entitle → `ai-platform/test/e2e/harness/d1.ts` `resetPlatformState` and `ai-platform/test/e2e/harness/control.ts` re-seed `plan` → `handleEntitle` |
