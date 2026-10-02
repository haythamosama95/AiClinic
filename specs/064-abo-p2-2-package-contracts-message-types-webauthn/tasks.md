# Tasks: Package contracts: message types, WebAuthn, Access JWT and the testkit

**Input**: Design documents from `specs/064-abo-p2-2-package-contracts-message-types-webauthn/`

**Prerequisites**: `plan.md` (required), `spec.md` (required for user stories), `research.md`, `data-model.md`, `contracts/` (`AVAILABLE_DOCS`: `research.md`, `data-model.md`, `contracts/`). `quickstart.md` is written in Documentation after verification.

**Organization**: Three user stories, as the spec partitions them (`[US1]`, `[US2]`, `[US3]`). Tests are one task per E2E id in the spec Test plan, written to fail before the new exports exist. Test Layout names no extra test. Titles start with the E2E id (rule V3). Nothing ships before P8 (rule S2). No Setup phase: the package skeleton already exists from P2.1. Sequencing step 1 retargets the Vitest aliases inside the first failing test. No Foundational phase (prerequisites are P2.1, already merged, listed in Consumes Binding). No Polish phase.

**Task count**: 22. Size M is 20–32 (rule S3). The count is the honest list: eight E2E tasks (Sequencing steps 1–8), twelve implementation steps (9–20), one verification task, and `quickstart.md` (step 21). The plan's implied count of 21 is those steps before the verification task this phase adds. It is not padded.

## 1. Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (`US1`, `US2`, `US3`)
- Include exact file paths in descriptions

## 2. Path Conventions

- **Flutter desktop app**: `frontend/lib/`, `frontend/test/` — this unit does not change them
- **Supabase backend**: `backend/migrations/`, `backend/functions/`, `backend/tests/` — this unit does not change them
- **Shared package**: `packages/vendor-contracts/`
- **AI Platform**: `ai-platform/` — E2E-P2.2-08 reads the production bundle (`main = src/worker.ts`, env `ai-platform-gateway-production`). This unit adds no `ai-platform` source change
- **Spec Kit artifacts**: `specs/064-abo-p2-2-package-contracts-message-types-webauthn/`
- This unit's Files section names `packages/vendor-contracts/` (validators, verifiers, `testkit` subpath, vectors, H-PKG tests, Vitest aliases) and `quickstart.md`. `research.md`, `data-model.md`, and `contracts/` stay plan-phase artifacts. `src/canonical.ts`, `src/jws.ts`, `src/identifiers.ts`, `src/version.ts`, `vectors/canonical.json`, `vectors/identifiers.json`, and `vectors/jws.json` stay as P2.1 froze them. There is no `dist/` emit.

---

## 3. Tests

**Purpose**: One failing test per E2E id, in Sequencing order. H-PKG tests import the new exports and fail while those exports are absent. E2E-P2.2-08 fails while `package.json` has no `./testkit` export. T001 retargets both Vitest aliases before any other test imports `vendor-contracts/testkit`.

### 3.1 User Story 1 - Grant envelope, receipt, and token claims (Priority: P1)

**Independent Test**: E2E-P2.2-05, E2E-P2.2-06, and E2E-P2.2-07 in harness H-PKG (Node and workerd).

- [ ] T001 [US1] Point both Vitest aliases at `packages/vendor-contracts/src/testkit/index.ts` for `vendor-contracts/testkit`, and make the root alias an exact match (`find: /^vendor-contracts$/`) so it does not swallow the subpath, in `packages/vendor-contracts/vitest.config.ts` and `packages/vendor-contracts/vitest.workers.config.ts`. Add `packages/vendor-contracts/vectors/grant-envelope.json`, `packages/vendor-contracts/vectors/coverage-snapshot.json`, `packages/vendor-contracts/vectors/feed-event.json`, and the failing test `E2E-P2.2-05 Grant envelope: canonical hash stable; ABO signature verifies, and fails after any field mutation` in `packages/vendor-contracts/test/grant.test.ts` — produces the red test, satisfies FR-002, FR-003, FR-005, FR-006, and FR-012, proved by E2E-P2.2-05. Run it with `vitest.config.ts` and with `vitest.workers.config.ts`. `grantEnvelopeHash` equals the vector hex on two calls. `verifyGrantSignature` accepts the ABO signer output. Replacing each field in turn makes verification fail. The same test validates `vectors/coverage-snapshot.json` and `vectors/feed-event.json`, including a second `kind` string. The test fails because the grant, snapshot, feed, and testkit signer exports are absent. The existing `"."` export and the `test` script in `packages/vendor-contracts/package.json` stay. This task does not add the `./testkit` export.

- [ ] T002 [P] [US1] Add `packages/vendor-contracts/vectors/receipt.json`, `packages/vendor-contracts/vectors/result-envelope.json`, and the failing test `E2E-P2.2-06 Receipt signature verifies; tampered term_ids fails` in `packages/vendor-contracts/test/receipt.test.ts` — produces the red test, satisfies FR-001, FR-004, and FR-012, proved by E2E-P2.2-06. Depends on T001. Both configs. `verifyReceiptSignature` accepts the platform signer output. A changed `term_ids` array makes verification fail. The receipt sits on an `applied` result envelope that `validateResultEnvelope` accepts. Both runs fail because the receipt and result-envelope exports are absent.

- [ ] T003 [P] [US1] Add `packages/vendor-contracts/vectors/token-claims.json` and the failing test `E2E-P2.2-07 Claim validators: billing token with lifetime > 300 s rejected; feed token carrying org rejected` in `packages/vendor-contracts/test/token-claims.test.ts` — produces the red test, satisfies FR-011 and FR-012, proved by E2E-P2.2-07. Depends on T001. Both configs. `mintBilling` with `exp - iat` greater than 300 returns `{ ok: false }` from `validateTokenClaims`. `mintFeed` with an `org` key returns `{ ok: false }`. Both runs fail because `validateTokenClaims` and `createIssuer` are absent.

**Checkpoint**: E2E-P2.2-05, E2E-P2.2-06, and E2E-P2.2-07 exist and fail in Node and in the workers pool.

### 3.2 User Story 2 - WebAuthn assertion and Access JWT (Priority: P2)

**Independent Test**: E2E-P2.2-01, E2E-P2.2-02, E2E-P2.2-03, and E2E-P2.2-04 in harness H-PKG (Node and workerd).

- [ ] T004 [P] [US2] Add `packages/vendor-contracts/vectors/operation.json` and the failing test `E2E-P2.2-01 A testkit assertion over operation O verifies; the same assertion against O′ (one param changed) fails` in `packages/vendor-contracts/test/webauthn.test.ts` — produces the red test, satisfies FR-007, FR-008, and FR-012, proved by E2E-P2.2-01. Depends on T001. Both configs. The authenticator asserts over operation O from `vectors/operation.json`. `verifyAssertion` returns `{ ok: true }`. The same assertion verified against O′ (one `params` value changed) returns `{ ok: false }`. Both runs fail because the authenticator and `verifyAssertion` are absent. Does not edit the User Story 1 test files.

- [ ] T005 [US2] Add the failing test `E2E-P2.2-02 UV flag cleared, wrong origin, or wrong rpId → each fails` in `packages/vendor-contracts/test/webauthn.test.ts` — produces the red test, satisfies FR-008, proved by E2E-P2.2-02. Depends on T004 (same file). Both configs. Three assertions, each with a valid signature over its own client data: UV flag clear, origin other than `https://ops.<vendor-domain>`, `rpId` other than the console hostname. Each returns `{ ok: false }`. Both runs fail on the same missing exports.

- [ ] T006 [US2] Add the failing test `E2E-P2.2-03 ES256 and EdDSA credentials both verify; another alg is rejected` in `packages/vendor-contracts/test/webauthn.test.ts` — produces the red test, satisfies FR-009, proved by E2E-P2.2-03. Depends on T005 (same file). Both configs. `parseRegistrationAttestation` accepts the ES256 and EdDSA attestations. `verifyAssertion` accepts both. `alg` `RS256` returns `{ ok: false }`. Both runs fail on the same missing exports.

- [ ] T007 [P] [US2] Add the failing test `E2E-P2.2-04 Access JWT: valid → email; wrong aud tag, expired, or unknown cert kid → fails` in `packages/vendor-contracts/test/access-jwt.test.ts` — produces the red test, satisfies FR-010 and FR-012, proved by E2E-P2.2-04. Depends on T001. Both configs. The valid token returns the email. A different `aud`, `exp` at or below `nowSeconds`, and a header `kid` missing from the certs document each return `{ ok: false }`. Both runs fail because `verifyAccessJwt` and `createAccessTeam` are absent. Does not edit `packages/vendor-contracts/test/webauthn.test.ts`.

**Checkpoint**: E2E-P2.2-01, E2E-P2.2-02, E2E-P2.2-03, and E2E-P2.2-04 exist and fail in Node and in the workers pool.

### 3.3 User Story 3 - Production bundle excludes the testkit (Priority: P3)

**Independent Test**: E2E-P2.2-08 in harness H-PKG.

- [ ] T008 [P] [US3] Exclude `test/bundle-scan.test.ts` from `packages/vendor-contracts/vitest.workers.config.ts`. Add the failing test `E2E-P2.2-08 A production ai-platform bundle contains no testkit code` in `packages/vendor-contracts/test/bundle-scan.test.ts` — produces the red test, satisfies FR-012, proved by E2E-P2.2-08. Depends on T001 (same workers config). Node config only. `package.json` exports `./testkit`. `wrangler deploy --dry-run --outdir <tmpdir> --env production` from `ai-platform/` emits a bundle whose text omits `vendor-contracts-testkit`. The test fails because `packages/vendor-contracts/package.json` has no `./testkit` export. The workers pool does not run this file.

**Checkpoint**: E2E-P2.2-08 exists and fails under the Node config.

---

## 4. Implementation

**Purpose**: Sequencing steps 9–20. Each export is added only after its failing test exists. `packages/vendor-contracts/src/index.ts` re-exports the new production functions and the existing P2.1 functions. It does not export the testkit.

### 4.1 User Story 1 - Grant envelope, receipt, and token claims (Priority: P1)

**Independent Test**: E2E-P2.2-05, E2E-P2.2-06, and E2E-P2.2-07 in harness H-PKG (Node and workerd).

#### 4.1.1 User Story 1 - Grant envelope, receipt, and token claims (part 1)

- [ ] T009 [US1] Add `validateResultEnvelope` in `packages/vendor-contracts/src/result-envelope.ts` and export it from `packages/vendor-contracts/src/index.ts` — produces the result-envelope validator, satisfies FR-001, proved by E2E-P2.2-06. Depends on T001–T008 existing and failing. `result` is `ok`, `applied`, `already_applied`, `conflict`, `rejected`, or `transient`. For `transient`, `detail` is `unavailable`, `unknown_kid`, `awaiting_transfer`, or `transfer_pending`. E2E-P2.2-06 stays red until the receipt signature exists.

- [ ] T010 [US1] Add `validateGrantEnvelope`, `grantEnvelopeHash`, and `verifyGrantSignature` in `packages/vendor-contracts/src/grant-envelope.ts` and export them from `packages/vendor-contracts/src/index.ts` — produces the grant validator, hash, and signature check, satisfies FR-002 and FR-003, proved by E2E-P2.2-05. Depends on T009 (same `index.ts`). The hash and the signature use the consumed `canonicalize`, `sha256Hex`, and `verifyCompactJws` APIs. E2E-P2.2-05 stays red until the snapshot, feed event, and ABO signer exist.

- [ ] T011 [US1] Add `validateReceipt` and `verifyReceiptSignature` in `packages/vendor-contracts/src/receipt.ts` and export them from `packages/vendor-contracts/src/index.ts` — produces the receipt validator and signature check, satisfies FR-004, proved by E2E-P2.2-06. Depends on T010 (same `index.ts`). The signature is over the canonical receipt without the signature and uses `verifyCompactJws`. E2E-P2.2-06 stays red until the platform signer exists.

- [ ] T012 [US1] Add `validateCoverageSnapshot` in `packages/vendor-contracts/src/coverage-snapshot.ts` and `validateFeedEvent` in `packages/vendor-contracts/src/feed-event.ts`, and export both from `packages/vendor-contracts/src/index.ts` — produces the snapshot and feed-event validators, satisfies FR-005 and FR-006, proved by E2E-P2.2-05. Depends on T011 (same `index.ts`). Feed-event `kind` stays an unenumerated string. The snapshot contains no prices, payment references, or provider ids. E2E-P2.2-05 still waits on the ABO signer.

- [ ] T013 [US1] Add `packages/vendor-contracts/src/base64url.ts` and `validateOperation` plus `operationChallenge` in `packages/vendor-contracts/src/operation.ts`, and export the operation functions from `packages/vendor-contracts/src/index.ts` — produces the operation object and its challenge, satisfies FR-007, proved by E2E-P2.2-01. Depends on T012 (same `index.ts`). The operation object is `{op, params, actor_email, issued_at, nonce, contract_version}`. `operationChallenge` is base64url(SHA-256(canonical operation object)), using the consumed canonical and hash APIs. E2E-P2.2-01 stays red until `verifyAssertion` and the authenticator exist.

**Checkpoint**: E2E-P2.2-05, E2E-P2.2-06, and E2E-P2.2-07 are still red.

#### 4.1.2 User Story 1 - Grant envelope, receipt, and token claims (part 2)

- [ ] T014 [US1] Add `validateTokenClaims` in `packages/vendor-contracts/src/token-claims.ts` and export it from `packages/vendor-contracts/src/index.ts` — produces the AI, billing, and feed claim validator, satisfies FR-011, proved by E2E-P2.2-07. Depends on T013 (same `index.ts`). The module canonicalises `{ alg: "EdDSA", kid, typ: "JWT" }` and verifies Ed25519 itself. Billing lifetime is ≤ 300 s. Feed tokens carry no `org`. AI lifetime is ≤ 600 s. Feed lifetime is ≤ 120 s. E2E-P2.2-07 stays red until `createIssuer` exists.

- [ ] T015 [P] [US1] Add `createAboGrantSigner` and `createPlatformReceiptSigner` in `packages/vendor-contracts/src/testkit/signers.ts`. Create `packages/vendor-contracts/src/testkit/index.ts` with `TESTKIT_MARKER` (`vendor-contracts-testkit`) and those two exports; each export reads the marker. Add `"./testkit": "./src/testkit/index.ts"` to `packages/vendor-contracts/package.json` next to the existing `"."` export — produces the grant and receipt signers and the testkit subpath, satisfies FR-003, FR-004, and FR-012, proved by E2E-P2.2-05, E2E-P2.2-06, and E2E-P2.2-08. Depends on T008, T009, T010, T011, and T012. Does not edit `packages/vendor-contracts/src/index.ts`. Signers call `signCompactJws`. E2E-P2.2-05 and E2E-P2.2-06 pass in both runtimes. E2E-P2.2-08 passes under the Node config: the export exists, and the production bundle omits `vendor-contracts-testkit`.

- [ ] T016 [P] [US1] Add `createIssuer` in `packages/vendor-contracts/src/testkit/issuer.ts` and export it from `packages/vendor-contracts/src/testkit/index.ts`; the function reads `TESTKIT_MARKER` — produces the issuer key set and minters for the AI, billing, and feed audiences, satisfies FR-011 and FR-012, proved by E2E-P2.2-07. Depends on T014 and T015. E2E-P2.2-07 calls `mintBilling` and `mintFeed`. E2E-P2.2-07 passes in both runtimes.

**Checkpoint**: E2E-P2.2-05, E2E-P2.2-06, and E2E-P2.2-07 pass. E2E-P2.2-08 passes under the Node config.

### 4.2 User Story 2 - WebAuthn assertion and Access JWT (Priority: P2)

**Independent Test**: E2E-P2.2-01, E2E-P2.2-02, E2E-P2.2-03, and E2E-P2.2-04 in harness H-PKG (Node and workerd).

- [ ] T017 [P] [US2] Add `verifyAssertion` in `packages/vendor-contracts/src/webauthn.ts` (DER-to-raw for ES256, raw Ed25519 for EdDSA, user-presence and user-verification flags, origin `https://ops.<vendor-domain>`, `rpId` the console hostname, `type` `webauthn.get`, challenge) and export it from `packages/vendor-contracts/src/index.ts` — produces assertion verification, satisfies FR-008 and FR-009, proved by E2E-P2.2-01, E2E-P2.2-02, and E2E-P2.2-03. Depends on T013 and T014. E2E-P2.2-01, E2E-P2.2-02, and E2E-P2.2-03 stay red until the authenticator exists.

- [ ] T018 [US2] Add `parseRegistrationAttestation` in `packages/vendor-contracts/src/webauthn.ts` and `createSoftwareAuthenticator` in `packages/vendor-contracts/src/testkit/authenticator.ts`. Export the authenticator from `packages/vendor-contracts/src/testkit/index.ts`; it reads `TESTKIT_MARKER` — produces registration-attestation parsing and the software authenticator (ES256 and EdDSA, attestation and assertion), satisfies FR-008, FR-009, and FR-012, proved by E2E-P2.2-01, E2E-P2.2-02, and E2E-P2.2-03. Depends on T016 and T017. Attestation parsing reads `alg` and the public key for ES256 and EdDSA and adds no attestation field list. `alg` `RS256` returns `{ ok: false }`. E2E-P2.2-01, E2E-P2.2-02, and E2E-P2.2-03 pass in both runtimes.

- [ ] T019 [US2] Add `verifyAccessJwt` in `packages/vendor-contracts/src/access-jwt.ts` and `createAccessTeam` in `packages/vendor-contracts/src/testkit/access-team.ts`. Export `verifyAccessJwt` from `packages/vendor-contracts/src/index.ts` and `createAccessTeam` from `packages/vendor-contracts/src/testkit/index.ts`; the minter reads `TESTKIT_MARKER` — produces Access JWT verification and the team key, JWT minter, and certs document, satisfies FR-010 and FR-012, proved by E2E-P2.2-04. Depends on T018 (same `index.ts` and testkit index). Verification uses the injected team certificates, issuer, the `aud` tag, and expiry, and returns the email. E2E-P2.2-04 passes in both runtimes.

**Checkpoint**: E2E-P2.2-01, E2E-P2.2-02, E2E-P2.2-03, and E2E-P2.2-04 pass.

### 4.3 User Story 3 - Production bundle excludes the testkit (Priority: P3)

**Independent Test**: E2E-P2.2-08 in harness H-PKG.

- [ ] T020 [US3] Keep `packages/vendor-contracts/src/index.ts` free of a testkit export after the issuer, authenticator, and Access modules are exported from `packages/vendor-contracts/src/testkit/index.ts`. Re-run E2E-P2.2-08 under the Node config — produces a production entrypoint with no testkit export, satisfies FR-012, proved by E2E-P2.2-08. Depends on T015, T016, T018, and T019. The production bundle still omits `vendor-contracts-testkit`. This task re-runs only `packages/vendor-contracts/test/bundle-scan.test.ts` on `vitest.config.ts`.

**Checkpoint**: E2E-P2.2-08 passes. `src/index.ts` has no testkit export.

---

## 5. Verification

**Purpose**: This unit's H-PKG suite passes, then every earlier suite on this unit's harness and on P2.1's H-AP harness is still green (rule S2). Consumes Binding is the P2.1 canonical, hash, JWS, identifier, and channel-constant modules; this task does not edit them. P1.x is a parallel track and this plan names no H-BK command.

- [ ] T021 Run harness H-PKG and confirm it is green, then confirm the earlier P2.1 suites are still green — produces the green run, satisfies FR-001 through FR-012, SC-001, and SC-002, proved by E2E-P2.2-01 through E2E-P2.2-08. Depends on T001–T020. This unit's harness, Node then the workers pool:

```bash
cd packages/vendor-contracts && npx vitest run --config vitest.config.ts \
  test/grant.test.ts test/receipt.test.ts test/token-claims.test.ts \
  test/webauthn.test.ts test/access-jwt.test.ts test/bundle-scan.test.ts \
&& npx vitest run --config vitest.workers.config.ts \
  test/grant.test.ts test/receipt.test.ts test/token-claims.test.ts \
  test/webauthn.test.ts test/access-jwt.test.ts
```

The package regression the plan names (the existing `vendor-contracts` CI job, `npm test`, which also re-runs E2E-P2.1-01, E2E-P2.1-02, and E2E-P2.1-03):

```bash
cd packages/vendor-contracts && npm test
```

The earlier H-AP suite (P2.1): `cd ai-platform && npx vitest run --config vitest.workers.config.ts test/system/contract-version.system.test.ts` (E2E-P2.1-04, E2E-P2.1-05, E2E-P2.1-06), then `cd ai-platform && npm test && npm run test:e2e` (E2E-P2.1-07). This unit does not edit `ai-platform` source. A full-product `npm test` is not this command.

---

## 6. Documentation

**Purpose**: Written after T021 is green (rule S8). The plan leaves `quickstart.md` for implement. `research.md`, `data-model.md`, and `contracts/` stay plan-phase artifacts.

- [ ] T022 Create `specs/064-abo-p2-2-package-contracts-message-types-webauthn/quickstart.md` from the plan's quickstart outline — produces this unit's quickstart, satisfies FR-001 through FR-012, proved by E2E-P2.2-01 through E2E-P2.2-08. Depends on T021. Sections: (1) what was implemented — the validators and verifiers in `contracts/`, the golden vectors, the `testkit` subpath, and the production bundle scan; (2) files this unit adds or modifies — the Files section of `plan.md`, with no earlier-unit files, no combined counts, and no full-suite regression (that is T021); (3) harness command for this unit's tests only — the two `vitest run` commands below; (4) how to inspect the change — read `packages/vendor-contracts/src/index.ts`, the `./testkit` export in `packages/vendor-contracts/package.json`, and the H-PKG output; (5) the entry point → module chain per E2E id below. Every scenario is asserted by H-PKG, so this file records harness commands only.

```bash
cd packages/vendor-contracts && npx vitest run --config vitest.config.ts \
  test/grant.test.ts test/receipt.test.ts test/token-claims.test.ts \
  test/webauthn.test.ts test/access-jwt.test.ts test/bundle-scan.test.ts \
&& npx vitest run --config vitest.workers.config.ts \
  test/grant.test.ts test/receipt.test.ts test/token-claims.test.ts \
  test/webauthn.test.ts test/access-jwt.test.ts
```

The first command is Node, including E2E-P2.2-08. The second is the workers pool for E2E-P2.2-01 through E2E-P2.2-07. Earlier P2.1 files and `npm test` of the whole package stay out of this command (rule S8).

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

---

## 7. Dependencies & Execution Order

### 7.1 Phase Dependencies

- **Tests (T001–T008)**: T001 starts immediately. It retargets the shared Vitest aliases and adds E2E-P2.2-05. T002, T003, T004, T007, and T008 start once T001 is done. T005 appends after T004. T006 appends after T005. T001–T008 are observed failing before T009.
- **Implementation (T009–T020)**: Starts after T001–T008 exist and fail. Within a story, implementation follows Sequencing. T015 may overlap T013 and T014. T016 and T017 may overlap each other. T020 runs after the testkit index exports the issuer, authenticator, and Access minter.
- **Verification (T021)**: After every implementation task, including T020.
- **Documentation (T022)**: After T021 is green.

### 7.2 User Story Dependencies

- **User Story 1 (P1)**: No dependency on User Story 2 or User Story 3. Tests T002 and T003 are `[P]` after T001. Implementation T009–T014 is sequential on `packages/vendor-contracts/src/index.ts`. T015 is `[P]` with T013 and T014 once T012 is done, and it also waits on T008. T016 waits on T014 and T015. E2E-P2.2-05 and E2E-P2.2-06 pass at T015. E2E-P2.2-07 passes at T016. E2E-P2.2-08 first passes at T015.
- **User Story 2 (P2)**: The failing tests do not need User Story 1 modules. T004 and T007 may start once T001 is done. T005 and T006 stay sequential on `packages/vendor-contracts/test/webauthn.test.ts`. Implementation waits on User Story 1's operation object (T013). T017 is `[P]` with T016 after T014. T018 waits on T016 and T017. T019 waits on T018. E2E-P2.2-01, E2E-P2.2-02, and E2E-P2.2-03 pass at T018. E2E-P2.2-04 passes at T019.
- **User Story 3 (P3)**: T008 may start once T001 is done. T020 waits until `createIssuer` (T016), `createSoftwareAuthenticator` (T018), and `createAccessTeam` (T019) are exported from the testkit index, and until the `./testkit` export from T015 exists. E2E-P2.2-08 stays green at T020.

### 7.3 Parallel Opportunities

- After T001, these test tasks touch different files and may launch together: T002 (`test/receipt.test.ts`), T003 (`test/token-claims.test.ts`), T004 (`test/webauthn.test.ts` and `vectors/operation.json`), T007 (`test/access-jwt.test.ts`), and T008 (`test/bundle-scan.test.ts` and `vitest.workers.config.ts`). T005 and T006 append to `test/webauthn.test.ts` and are not `[P]`.
- T009, T010, T011, T012, T013, and T014 all edit `packages/vendor-contracts/src/index.ts`. They are not `[P]` with each other.
- T015 edits `src/testkit/signers.ts`, `src/testkit/index.ts`, and `package.json`. It is `[P]` with T013 and T014 after T012. It waits on T008, T009, T010, T011, and T012.
- T016 edits `src/testkit/issuer.ts` and `src/testkit/index.ts`. T017 edits `src/webauthn.ts` and `src/index.ts`. They are `[P]` with each other after T014 and T015 (T017's index predecessor is T014; T013 is already done by then).
- T018, T019, and T020 share `src/testkit/index.ts` or `src/index.ts` with their predecessors. They are not `[P]`. T018 waits on T016 and T017. T019 waits on T018. T020 waits on T015, T016, T018, and T019.
- T021 and T022 are single tasks. T022 waits until T021 is green.

```bash
# Two User Story 1 test tasks launched together after T001.
# Different files. Neither waits on the other.
Task: "T002 [P] [US1] Add the failing test E2E-P2.2-06 in packages/vendor-contracts/test/receipt.test.ts"
Task: "T003 [P] [US1] Add the failing test E2E-P2.2-07 in packages/vendor-contracts/test/token-claims.test.ts"
```
