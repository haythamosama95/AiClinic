# Package contracts: message types, WebAuthn, Access JWT and the testkit

**Unit**: P2.2 · **Harness**: H-PKG · **Verification**: T021 green

## 1. What was implemented

Shared package `packages/vendor-contracts/` gains message-type validators and verifiers, golden vectors, a `testkit` subpath, and a production bundle scan (FR-001 through FR-012).

- **Validators and verifiers (frozen in `contracts/`).** Result envelope, grant envelope (hash and ABO signature), receipt, coverage snapshot, feed event, operation object and challenge, WebAuthn assertion verification and registration attestation parsing, Cloudflare Access JWT verification, and AI/billing/feed token-claim validation — all exported from the package root (`src/index.ts`).
- **Golden vectors.** Fixtures under `packages/vendor-contracts/vectors/` for each message type and for token claims drive H-PKG conformance in Node and workerd.
- **`testkit` subpath.** `vendor-contracts/testkit` exports signers (ABO grant, platform receipt), token issuer minters, a software WebAuthn authenticator, and Access team JWT/certs helpers for tests only; `TESTKIT_MARKER` (`vendor-contracts-testkit`) tags testkit modules.
- **Production bundle scan.** E2E-P2.2-08 confirms `ai-platform` production dry-run bundles omit testkit code while `package.json` still exports `./testkit` for Node and Wrangler.

## 2. Files this unit adds or modifies

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
| `specs/064-abo-p2-2-package-contracts-message-types-webauthn/quickstart.md` | FR-001–FR-012 |
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

Full-suite regression is verification task T021, not this file.

## 3. Harness command for this unit's tests only

The first command is Node, including E2E-P2.2-08. The second is the workers pool for E2E-P2.2-01 through E2E-P2.2-07. Earlier P2.1 files and `npm test` of the whole package stay out of this command (rule S8).

```bash
cd packages/vendor-contracts && npx vitest run --config vitest.config.ts \
  test/grant.test.ts test/receipt.test.ts test/token-claims.test.ts \
  test/webauthn.test.ts test/access-jwt.test.ts test/bundle-scan.test.ts \
&& npx vitest run --config vitest.workers.config.ts \
  test/grant.test.ts test/receipt.test.ts test/token-claims.test.ts \
  test/webauthn.test.ts test/access-jwt.test.ts
```

Every scenario is asserted by H-PKG; this file records harness commands only.

## 4. How to inspect the change

- **Production exports:** `packages/vendor-contracts/src/index.ts` — validators and verifiers re-exported with the existing P2.1 APIs; no testkit export on the root entry.
- **Testkit subpath:** `packages/vendor-contracts/package.json` `"exports"` includes `"./testkit": "./src/testkit/index.ts"` beside `"."`.
- **Frozen contracts:** `specs/064-abo-p2-2-package-contracts-message-types-webauthn/contracts/` — message types, verification APIs, and testkit API.
- **Harness output:** run the commands in §3 and confirm E2E-P2.2-01 through E2E-P2.2-08 pass.

## 5. Entry point → module chain

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
