# Implementation Plan: Package contracts: message types, WebAuthn, Access JWT and the testkit

**Branch**: `ai/064-abo-p2-2-package-contracts-message-types-webauthn` | **Date**: 2026-10-02 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `specs/064-abo-p2-2-package-contracts-message-types-webauthn/spec.md`

**Note**: This template is filled in by the `/abo-plan` command. See `.specify/templates/plan-template.md` for the execution workflow.

## Summary

P2.2 adds runtime validators for the result envelope, grant envelope, receipt, coverage snapshot, feed event, operation object, and the AI, billing, and feed token claims, plus WebAuthn assertion verification, ES256 and EdDSA registration-attestation parsing, and Access JWT verification. The package exports a `testkit` subpath (software authenticator, Access team minter, issuer minters, ABO grant signer, platform receipt signer) that the production `ai-platform` bundle leaves out, and `research.md` records the R-5 spike.

The unit sits in phase P2, size M, **Depends** P2.1, in parallel with P1.x. CP-A is the checkpoint after this unit.

## Technical Context

**Language/Version**: TypeScript ESM (`"type": "module"`), TypeScript `^5.9.2`, target ES2022 (`packages/vendor-contracts/tsconfig.json`). Node `>=22` (the engines field in `ai-platform/package.json`). Workers-pool compatibility date `2026-05-03` (`packages/vendor-contracts/wrangler.toml`).

**Primary Dependencies**: The consumed package APIs `canonicalize`, `sha256Hex`, `signCompactJws`, `verifyCompactJws`, the identifier functions, and `CHANNEL_VERSIONS` (P2.1). WebCrypto `crypto.subtle` for SHA-256, Ed25519, ECDSA P-256, and RSASSA-PKCS1-v1_5. No JWT library and no WebAuthn library. Vitest `~3.2.4`, `@cloudflare/vitest-pool-workers` `0.8.71`, Wrangler `~4.86.0`, already in this package.

**Storage**: None. This unit defines no tables (spec §4.1). Golden vectors are JSON files under `packages/vendor-contracts/vectors/`.

**Testing**: H-PKG. E2E-P2.2-01 through E2E-P2.2-07 run in `packages/vendor-contracts/test/` under `vitest.config.ts` and `vitest.workers.config.ts`. E2E-P2.2-08 is the Node bundle scan in the same directory, excluded from the workers pool. Tests are written to fail before the new exports exist. The existing `vendor-contracts` CI job already runs `npm test` in this package (rule V7). This unit adds no CI job.

**Target Platform**: workerd and Node for the library. The E2E-P2.2-08 scan reads the production `ai-platform` bundle (`main = src/worker.ts`, env name `ai-platform-gateway-production`) and adds no second codebase.

**Project Type**: Library in the existing package `packages/vendor-contracts/`. Rule S8 allows library-only work here, verified by conformance vectors in Node and workerd. The testkit is the subpath later harnesses import.

**Performance Goals**: Clinic scale, a few orders a day and one operator (02 §7 principle I). These are per-call validators and verifiers. No separate throughput target.

**Constraints**: One codebase, `packages/vendor-contracts/` (spec **Codebase**, rule S3). P2.1 modules `src/canonical.ts`, `src/jws.ts`, `src/identifiers.ts`, `src/version.ts`, and the existing vector files stay as frozen. Grant and receipt signatures call `signCompactJws` and `verifyCompactJws`. Token headers follow FR-011 (`typ: "JWT"`) inside `src/token-claims.ts` because the frozen JWS header is `{alg, kid}` (`contracts/token-claims.md`). WebAuthn checks `rpId`, origin `https://ops.<vendor-domain>`, `type` `webauthn.get`, and both flags; the challenge is base64url(SHA-256(canonical operation object)). ES256 signatures are DER converted to raw; EdDSA signatures are raw (FR-009, `research.md`). Access verification uses injected team certs, issuer, the `aud` tag, and expiry, and returns the email (FR-010). Feed-event `kind` stays an unenumerated string (FR-006). Registration attestation parsing reads `alg` and the public key for ES256 and EdDSA and adds no attestation field list (FR-009). Billing lifetime ≤ 300 s; feed tokens carry no `org`; AI lifetime ≤ 600 s; feed lifetime ≤ 120 s (FR-011). Where each check is enforced on a worker stays with P3.1, P4.6, and P4.7.

**Scale/Scope**: Size M (rule S3, 20–32 tasks, 3 user stories, 8 E2E ids, 12 functional requirements). Implied task count is 21.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

Re-run of 02 §7 against this unit and `.specify/memory/constitution.md` (rule S12). `research.md` records R-5. The Phase 1 artifacts (`data-model.md`, `contracts/`) keep the same placement: package values only, no new service, no clinic-side write.

- [x] Feature scope still fits small-to-mid-size multi-branch clinics; hospital-scale or
      enterprise-only requirements are explicitly rejected or separately ratified

  One shared package holds the message types, WebAuthn and Access verification, and the testkit later clinic billing harnesses use (spec §4.1, 02 §7 principle I). Sized for a few orders a day and one operator. No hospital-scale or enterprise requirement.

- [x] Design keeps a simple operational model with no microservices, message queues,
      Kubernetes, or custom primary backend service

  The code stays inside the existing `file:` package. 02 §7 principle I rejects microservices, queues, and Kubernetes. 02 §7 principle II: no custom core backend. The testkit is a subpath export, not a service.

- [x] Layer ownership is explicit: Flutter handles UI/orchestration, Supabase handles
      backend capabilities, PostgreSQL owns domain integrity, and AI stays isolated

  Implementation stays in `packages/vendor-contracts/` (spec §4.1, 02 §7 principle II). Flutter, Supabase, and PostgreSQL are untouched. The package holds vendor message types and verification, and it has no database credential. `ai-platform` is read by the bundle scan and gains no source change in this unit.

- [x] Protected writes, validation, permissions, and transactional rules remain enforced
      through PostgreSQL constraints, triggers, RLS, or RPC functions

  This unit defines no tables and performs no clinic-side write (spec §4.1, 02 §7 principle III). Existing PostgreSQL constraints, triggers, RLS, and RPCs stay as they are. Worker-side enforcement of these checks is P3.1 and P4.6/P4.7 (spec Out of scope).

- [x] Security remains authenticated, tenant-scoped, branch-scoped, permission-gated,
      auditable, and soft-delete-preserving

  WebAuthn verification checks `rpId`, origin, `type`, and both flags, and the challenge is the hash of the canonical operation (04 §1.5, 02 §3.3). Access JWT verification uses the injected team certificates, issuer, the `aud` tag, and expiry, and yields the email (02 §3.3, FR-010). Grant and receipt signatures use the consumed JWS APIs (02 K-4 and K-3). Token claim rules keep billing lifetime ≤ 300 s and `org` off the feed token (04 §2.1). This unit adds no delete path (02 §7 principle IV).

- [x] AI actions remain human-approved, have no direct database/backend access, and the
      feature still works in a degraded manual mode when AI is unavailable

  The package has no database credential and no AI request path (02 §7 principles II and V). Clinical work does not call these functions. Lapsing AI stays outside this unit.

## Project Structure

### Documentation (this feature)

```text
specs/064-abo-p2-2-package-contracts-message-types-webauthn/
├── plan.md
├── spec.md
├── research.md
├── data-model.md
├── quickstart.md              # implement writes this after verification; outline below
├── contracts/
│   ├── result-envelope.md
│   ├── grant-envelope.md
│   ├── receipt.md
│   ├── coverage-snapshot.md
│   ├── feed-event.md
│   ├── operation-object.md
│   ├── webauthn.md
│   ├── access-jwt.md
│   ├── token-claims.md
│   └── testkit.md
└── tasks.md                   # /abo-tasks, not this phase
```

`research.md` records the R-5 spike (rule S6). `data-model.md` records the entities in spec §3.2. `contracts/` is the freeze later units bind to: message types, verification APIs, and the testkit API (CP-A).

#### quickstart.md outline

Implement writes `quickstart.md` after the H-PKG runs below are green. Sections:

1. What was implemented — the validators and verifiers in `contracts/`, the golden vectors, the `testkit` subpath, and the production bundle scan.
2. Files this unit adds or modifies — the Files section of this plan.
3. Harness command for this unit's tests only:

```bash
cd packages/vendor-contracts && npx vitest run --config vitest.config.ts \
  test/grant.test.ts test/receipt.test.ts test/token-claims.test.ts \
  test/webauthn.test.ts test/access-jwt.test.ts test/bundle-scan.test.ts \
&& npx vitest run --config vitest.workers.config.ts \
  test/grant.test.ts test/receipt.test.ts test/token-claims.test.ts \
  test/webauthn.test.ts test/access-jwt.test.ts
```

The first command is Node, including E2E-P2.2-08. The second is the workers pool for E2E-P2.2-01 through E2E-P2.2-07. Earlier P2.1 files and `npm test` of the whole package stay out of this command (rule S8).

4. Entry point → module chain per E2E id (rule S8):

| ID | Chain |
| --- | --- |
| E2E-P2.2-01 | `test/webauthn.test.ts` (Node and the workers pool) → `createSoftwareAuthenticator` → `operationChallenge` in `src/operation.ts` → `verifyAssertion` in `src/webauthn.ts` |
| E2E-P2.2-02 | Same file → authenticator `assert` with UV cleared, then with a different origin, then with a different `rpId` → `verifyAssertion` returns `{ ok: false }` for each |
| E2E-P2.2-03 | Same file → ES256 and EdDSA `attest` + `assert` → `parseRegistrationAttestation` and `verifyAssertion`; a third `alg` returns `{ ok: false }` |
| E2E-P2.2-04 | `test/access-jwt.test.ts` (both pools) → `createAccessTeam` → `verifyAccessJwt` in `src/access-jwt.ts` |
| E2E-P2.2-05 | `test/grant.test.ts` (both pools) → `grantIdPaid` and `CHANNEL_VERSIONS.vendorEntrypoint` → `validateGrantEnvelope` / `grantEnvelopeHash` → `createAboGrantSigner` → `verifyGrantSignature`; then `coverageEventId` → `validateCoverageSnapshot` and `validateFeedEvent` |
| E2E-P2.2-06 | `test/receipt.test.ts` (both pools) → `createPlatformReceiptSigner` → `validateReceipt` / `verifyReceiptSignature`; tampered `term_ids` fails; `validateResultEnvelope` on the `applied` envelope |
| E2E-P2.2-07 | `test/token-claims.test.ts` (both pools) → `createIssuer` `mintBilling` and `mintFeed` → `validateTokenClaims` |
| E2E-P2.2-08 | `test/bundle-scan.test.ts` (Node config only) → `package.json` export `./testkit` → `wrangler deploy --dry-run --outdir <tmpdir> --env production` in `ai-platform/` → bundle text omits `vendor-contracts-testkit` |

### Source Code (repository root)

```text
packages/vendor-contracts/
├── package.json
├── src/
│   ├── index.ts
│   ├── canonical.ts            # P2.1, unchanged
│   ├── jws.ts                  # P2.1, unchanged
│   ├── identifiers.ts          # P2.1, unchanged
│   ├── version.ts              # P2.1, unchanged
│   ├── base64url.ts
│   ├── result-envelope.ts
│   ├── grant-envelope.ts
│   ├── receipt.ts
│   ├── coverage-snapshot.ts
│   ├── feed-event.ts
│   ├── operation.ts
│   ├── webauthn.ts
│   ├── access-jwt.ts
│   ├── token-claims.ts
│   └── testkit/
│       ├── index.ts
│       ├── authenticator.ts
│       ├── access-team.ts
│       ├── issuer.ts
│       └── signers.ts
├── vectors/
│   ├── canonical.json          # P2.1, unchanged
│   ├── identifiers.json        # P2.1, unchanged
│   ├── jws.json                # P2.1, unchanged
│   ├── result-envelope.json
│   ├── grant-envelope.json
│   ├── receipt.json
│   ├── coverage-snapshot.json
│   ├── feed-event.json
│   ├── operation.json
│   └── token-claims.json
├── test/
│   ├── canonical.test.ts       # P2.1, unchanged
│   ├── jws.test.ts             # P2.1, unchanged
│   ├── identifiers.test.ts     # P2.1, unchanged
│   ├── grant.test.ts
│   ├── receipt.test.ts
│   ├── token-claims.test.ts
│   ├── webauthn.test.ts
│   ├── access-jwt.test.ts
│   └── bundle-scan.test.ts
├── vitest.config.ts
└── vitest.workers.config.ts
```

**Structure Decision**: Source remains TypeScript ESM loaded by Vitest and by Wrangler, with no `dist/` emit. Production imports use the package root `vendor-contracts` (`src/index.ts`). The testkit is the subpath `vendor-contracts/testkit`. Both Vitest configs alias that subpath to `src/testkit/index.ts` and keep the root alias an exact match (`find: /^vendor-contracts$/`) so the root alias does not swallow the subpath. `package.json` exports `./testkit` for Node and for Wrangler. `ai-platform` keeps its current dependency on the package root. E2E-P2.2-08 bundles that worker with `wrangler deploy --dry-run --outdir <tmpdir> --env production` and scans the output. The workers pool excludes `test/bundle-scan.test.ts` so the scan stays on Node.

## Consumes Binding

| Consumes entry | Existing module |
| --- | --- |
| Canonical, hash, and JWS APIs | `canonicalize` and `sha256Hex` in `packages/vendor-contracts/src/canonical.ts`; `signCompactJws` and `verifyCompactJws` in `packages/vendor-contracts/src/jws.ts`; re-exported from `src/index.ts`. Frozen contract: `specs/063-abo-p2-1-package-core-canonical-signing/contracts/canonical-hash-jws.md`. Vectors: `packages/vendor-contracts/vectors/canonical.json`, `packages/vendor-contracts/vectors/jws.json`. |
| Identifier functions and vectors | `grantIdPaid`, `grantIdComp`, `grantIdTransfer`, and `coverageEventId` in `packages/vendor-contracts/src/identifiers.ts`. Frozen contract: `specs/063-abo-p2-1-package-core-canonical-signing/contracts/identifiers.md`. Vector: `packages/vendor-contracts/vectors/identifiers.json`. |
| Channel constants and the refusal shape | `CHANNEL_VERSIONS` in `packages/vendor-contracts/src/version.ts`. Frozen contract: `specs/063-abo-p2-1-package-core-canonical-signing/contracts/contract-version.md`. Fixtures set `contract_version` from `CHANNEL_VERSIONS.vendorEntrypoint`. This unit leaves `negotiate` and the `contract_version_unsupported` body as P2.1 froze them. |

## Files

| File | FR |
| --- | --- |
| `specs/064-abo-p2-2-package-contracts-message-types-webauthn/research.md` | FR-009 |
| `specs/064-abo-p2-2-package-contracts-message-types-webauthn/data-model.md` | FR-001, FR-002, FR-003, FR-004, FR-005, FR-006, FR-007, FR-011 |
| `specs/064-abo-p2-2-package-contracts-message-types-webauthn/contracts/result-envelope.md` | FR-001 |
| `specs/064-abo-p2-2-package-contracts-message-types-webauthn/contracts/grant-envelope.md` | FR-002, FR-003 |
| `specs/064-abo-p2-2-package-contracts-message-types-webauthn/contracts/receipt.md` | FR-004 |
| `specs/064-abo-p2-2-package-contracts-message-types-webauthn/contracts/coverage-snapshot.md` | FR-005 |
| `specs/064-abo-p2-2-package-contracts-message-types-webauthn/contracts/feed-event.md` | FR-006 |
| `specs/064-abo-p2-2-package-contracts-message-types-webauthn/contracts/operation-object.md` | FR-007 |
| `specs/064-abo-p2-2-package-contracts-message-types-webauthn/contracts/webauthn.md` | FR-008, FR-009 |
| `specs/064-abo-p2-2-package-contracts-message-types-webauthn/contracts/access-jwt.md` | FR-010 |
| `specs/064-abo-p2-2-package-contracts-message-types-webauthn/contracts/token-claims.md` | FR-011 |
| `specs/064-abo-p2-2-package-contracts-message-types-webauthn/contracts/testkit.md` | FR-012 |
| `specs/064-abo-p2-2-package-contracts-message-types-webauthn/quickstart.md` (implement, after verification) | FR-001–FR-012 |
| `packages/vendor-contracts/package.json` | FR-012 |
| `packages/vendor-contracts/vitest.config.ts` | FR-012 |
| `packages/vendor-contracts/vitest.workers.config.ts` | FR-012 |
| `packages/vendor-contracts/src/index.ts` | FR-001, FR-002, FR-003, FR-004, FR-005, FR-006, FR-007, FR-008, FR-009, FR-010, FR-011 |
| `packages/vendor-contracts/src/base64url.ts` | FR-007, FR-008, FR-010, FR-011 |
| `packages/vendor-contracts/src/result-envelope.ts` | FR-001 |
| `packages/vendor-contracts/src/grant-envelope.ts` | FR-002, FR-003 |
| `packages/vendor-contracts/src/receipt.ts` | FR-004 |
| `packages/vendor-contracts/src/coverage-snapshot.ts` | FR-005 |
| `packages/vendor-contracts/src/feed-event.ts` | FR-006 |
| `packages/vendor-contracts/src/operation.ts` | FR-007 |
| `packages/vendor-contracts/src/webauthn.ts` | FR-008, FR-009 |
| `packages/vendor-contracts/src/access-jwt.ts` | FR-010 |
| `packages/vendor-contracts/src/token-claims.ts` | FR-011 |
| `packages/vendor-contracts/src/testkit/index.ts` | FR-012 |
| `packages/vendor-contracts/src/testkit/authenticator.ts` | FR-008, FR-009, FR-012 |
| `packages/vendor-contracts/src/testkit/access-team.ts` | FR-010, FR-012 |
| `packages/vendor-contracts/src/testkit/issuer.ts` | FR-011, FR-012 |
| `packages/vendor-contracts/src/testkit/signers.ts` | FR-003, FR-004, FR-012 |
| `packages/vendor-contracts/vectors/result-envelope.json` | FR-001 |
| `packages/vendor-contracts/vectors/grant-envelope.json` | FR-002, FR-003 |
| `packages/vendor-contracts/vectors/receipt.json` | FR-004 |
| `packages/vendor-contracts/vectors/coverage-snapshot.json` | FR-005 |
| `packages/vendor-contracts/vectors/feed-event.json` | FR-006 |
| `packages/vendor-contracts/vectors/operation.json` | FR-007 |
| `packages/vendor-contracts/vectors/token-claims.json` | FR-011 |
| `packages/vendor-contracts/test/grant.test.ts` | FR-002, FR-003, FR-005, FR-006 |
| `packages/vendor-contracts/test/receipt.test.ts` | FR-001, FR-004 |
| `packages/vendor-contracts/test/token-claims.test.ts` | FR-011 |
| `packages/vendor-contracts/test/webauthn.test.ts` | FR-007, FR-008, FR-009 |
| `packages/vendor-contracts/test/access-jwt.test.ts` | FR-010 |
| `packages/vendor-contracts/test/bundle-scan.test.ts` | FR-012 |

`package.json` gains `"exports": { ".": "./src/index.ts", "./testkit": "./src/testkit/index.ts" }`. The existing `"."` export and the `test` script stay. `src/index.ts` re-exports the new production functions and the existing P2.1 functions. It has no testkit export.

`src/canonical.ts`, `src/jws.ts`, `src/identifiers.ts`, `src/version.ts`, `vectors/canonical.json`, `vectors/identifiers.json`, `vectors/jws.json`, and `ai-platform/**` stay as they are. P3.1 composes Access email with `actor_email`, the credential registry, the 5-minute window, and `assertion_used`.

## Test Layout

Titles start with the E2E id (rule V3). H-PKG tests import the new exports and fail while those exports are absent. E2E-P2.2-08 fails while `package.json` has no `./testkit` export.

| ID | Harness | Test |
| --- | --- | --- |
| E2E-P2.2-01 | H-PKG | `packages/vendor-contracts/test/webauthn.test.ts`, both configs. Title `E2E-P2.2-01 A testkit assertion over operation O verifies; the same assertion against O′ (one param changed) fails`. The authenticator asserts over operation O from `vectors/operation.json`. `verifyAssertion` returns `{ ok: true }`. The same assertion verified against O′ (one `params` value changed) returns `{ ok: false }`. |
| E2E-P2.2-02 | H-PKG | Same file, both configs. Title `E2E-P2.2-02 UV flag cleared, wrong origin, or wrong rpId → each fails`. Three assertions, each with a valid signature over its own client data: UV flag clear, origin other than `https://ops.<vendor-domain>`, `rpId` other than the console hostname. Each returns `{ ok: false }`. |
| E2E-P2.2-03 | H-PKG | Same file, both configs. Title `E2E-P2.2-03 ES256 and EdDSA credentials both verify; another alg is rejected`. `parseRegistrationAttestation` accepts the ES256 and EdDSA attestations. `verifyAssertion` accepts both. `alg` `RS256` returns `{ ok: false }`. |
| E2E-P2.2-04 | H-PKG | `packages/vendor-contracts/test/access-jwt.test.ts`, both configs. Title `E2E-P2.2-04 Access JWT: valid → email; wrong aud tag, expired, or unknown cert kid → fails`. The valid token returns the email. A different `aud`, `exp` at or below `nowSeconds`, and a header `kid` missing from the certs document each return `{ ok: false }`. |
| E2E-P2.2-05 | H-PKG | `packages/vendor-contracts/test/grant.test.ts`, both configs. Title `E2E-P2.2-05 Grant envelope: canonical hash stable; ABO signature verifies, and fails after any field mutation`. `grantEnvelopeHash` equals the vector hex on two calls. `verifyGrantSignature` accepts the ABO signer output. Replacing each field in turn makes verification fail. The same test validates `vectors/coverage-snapshot.json` and `vectors/feed-event.json`, including a second `kind` string, so FR-005 and FR-006 are reached from this entry point. |
| E2E-P2.2-06 | H-PKG | `packages/vendor-contracts/test/receipt.test.ts`, both configs. Title `E2E-P2.2-06 Receipt signature verifies; tampered term_ids fails`. `verifyReceiptSignature` accepts the platform signer output. A changed `term_ids` array makes verification fail. The receipt sits on an `applied` result envelope that `validateResultEnvelope` accepts. |
| E2E-P2.2-07 | H-PKG | `packages/vendor-contracts/test/token-claims.test.ts`, both configs. Title `E2E-P2.2-07 Claim validators: billing token with lifetime > 300 s rejected; feed token carrying org rejected`. `mintBilling` with `exp - iat` greater than 300 returns `{ ok: false }` from `validateTokenClaims`. `mintFeed` with an `org` key returns `{ ok: false }`. |
| E2E-P2.2-08 | H-PKG | `packages/vendor-contracts/test/bundle-scan.test.ts`, Node config only. Title `E2E-P2.2-08 A production ai-platform bundle contains no testkit code`. `package.json` exports `./testkit`. `wrangler deploy --dry-run --outdir <tmpdir> --env production` from `ai-platform/` emits a bundle whose text omits `vendor-contracts-testkit`. |

## Sequencing

Tests are written and observed failing before the validators, verifiers, and testkit export exist. Each step is one task. The implied count is 21, inside size M (20–32).

1. Point both Vitest aliases at `src/testkit/index.ts` for `vendor-contracts/testkit`, and make the root alias an exact match. Add `vectors/grant-envelope.json`, `vectors/coverage-snapshot.json`, `vectors/feed-event.json`, and `test/grant.test.ts` (E2E-P2.2-05). Run it in Node and in the workers pool. It fails because the grant, snapshot, feed, and testkit signer exports are absent.
2. Add `vectors/receipt.json`, `vectors/result-envelope.json`, and `test/receipt.test.ts` (E2E-P2.2-06). Both runs fail because the receipt and result-envelope exports are absent.
3. Add `vectors/token-claims.json` and `test/token-claims.test.ts` (E2E-P2.2-07). Both runs fail because `validateTokenClaims` and `createIssuer` are absent.
4. Add `vectors/operation.json` and `test/webauthn.test.ts` with E2E-P2.2-01. Both runs fail because the authenticator and `verifyAssertion` are absent.
5. Add E2E-P2.2-02 to that file. Both runs fail on the same missing exports.
6. Add E2E-P2.2-03 to that file. Both runs fail on the same missing exports.
7. Add `test/access-jwt.test.ts` (E2E-P2.2-04). Both runs fail because `verifyAccessJwt` and `createAccessTeam` are absent.
8. Exclude `test/bundle-scan.test.ts` from `vitest.workers.config.ts`. Add that test (E2E-P2.2-08) and run the Node config. It fails because `package.json` has no `./testkit` export.
9. Add `src/result-envelope.ts` and export `validateResultEnvelope` from `src/index.ts`. E2E-P2.2-06 stays red until the receipt signature exists.
10. Add `src/grant-envelope.ts` (`validateGrantEnvelope`, `grantEnvelopeHash`, `verifyGrantSignature`) and export it. E2E-P2.2-05 stays red until the snapshot, feed event, and ABO signer exist.
11. Add `src/receipt.ts` and export it. E2E-P2.2-06 stays red until the platform signer exists.
12. Add `src/coverage-snapshot.ts` and `src/feed-event.ts` and export them. E2E-P2.2-05 still waits on the ABO signer.
13. Add `src/base64url.ts` and `src/operation.ts` (`validateOperation`, `operationChallenge`) and export the operation functions.
14. Add `src/token-claims.ts` and export `validateTokenClaims`. The module canonicalises `{ alg: "EdDSA", kid, typ: "JWT" }` and verifies Ed25519 itself. E2E-P2.2-07 stays red until `createIssuer` exists.
15. Add `src/testkit/signers.ts` (`createAboGrantSigner`, `createPlatformReceiptSigner`). Create `src/testkit/index.ts` with `TESTKIT_MARKER` (`vendor-contracts-testkit`) and those two exports; each export reads the marker. Add the `./testkit` export to `package.json`. E2E-P2.2-05 and E2E-P2.2-06 pass in both runtimes. E2E-P2.2-08 passes under the Node config: the export exists, and the production bundle omits the marker.
16. Add `src/testkit/issuer.ts` (`createIssuer`). Export it from the testkit index; the function reads `TESTKIT_MARKER`. E2E-P2.2-07 passes in both runtimes.
17. Add `verifyAssertion` in `src/webauthn.ts` (DER-to-raw for ES256, raw Ed25519 for EdDSA, flags, origin, `rpId`, `type`, challenge) and export it.
18. Add `parseRegistrationAttestation` in that file and `src/testkit/authenticator.ts`. Export the authenticator from the testkit index; it reads `TESTKIT_MARKER`. E2E-P2.2-01, E2E-P2.2-02, and E2E-P2.2-03 pass in both runtimes.
19. Add `src/access-jwt.ts` and `src/testkit/access-team.ts`. Export `verifyAccessJwt` from `src/index.ts` and `createAccessTeam` from the testkit index; the minter reads `TESTKIT_MARKER`. E2E-P2.2-04 passes in both runtimes.
20. Keep `src/index.ts` free of a testkit export after the issuer, authenticator, and Access modules are exported from the testkit index. Re-run E2E-P2.2-08 under the Node config. The production bundle still omits `vendor-contracts-testkit`.
21. Write `quickstart.md` from the outline above.

## Complexity Tracking

No constitution violation. 02 §7 records none for this unit, and every Constitution Check box is ticked.
