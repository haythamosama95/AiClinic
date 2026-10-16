# Feature Specification: Package contracts: message types, WebAuthn, Access JWT and the testkit

**Feature Branch**: `ai/064-abo-p2-2-package-contracts-message-types-webauthn`

**Created**: 2026-10-02

**Status**: Draft

**Input**: P2.2 — Package contracts: message types, WebAuthn, Access JWT and the testkit

## 1. Unit Contract

**Implements** — Read: 04 §1.2; 04 §1.4 (field table only); 04 §1.5; 04 §1.6; 04 §1.7; 04 §2.1; 04 §4.1 (the sentence defining each event, only); 02 §3.3; 01 §7 row R-5 (spike).

- Types + runtime validators: result envelope, grant envelope, receipt, coverage snapshot, feed event, operation object, AI/billing/feed token claims.
- WebAuthn: assertion verification (rpId, origin, `type`, UP+UV flags, ES256 DER→raw, EdDSA); attestation parsing for registration; challenge = base64url(SHA-256(canonical operation object)).
- Access JWT verification (team certs injected, issuer, `aud` tag, expiry) → email. Deviation recorded in rule S7: in the package, not per Worker.
- `testkit` subpath export, which production code must never import: a software authenticator (ES256 + EdDSA; attestation and assertion), an Access team key + JWT minter + certs document, an issuer key set + minters for the three audiences, an ABO grant-key signer, a platform receipt signer.
- R-5 spike result recorded (ES256 conversion, whether `amr` is meaningful).

**Freezes** — the message types of 04 §1.2–§1.7 and §2.1; the verification APIs; the testkit API (used by every later harness). CP-A.

**Consumes** — canonical, hash and JWS APIs; identifier functions + vectors; channel constants and the refusal shape. Changing one is out of scope (rule S7).

**Open questions relied on** — None.

**Spikes** — R-5 (01 §7; rule S6). This unit records the WebAuthn ES256 DER-to-raw conversion and whether Access `amr` is meaningful. P3.1 also takes Access `amr` and service-binding caller identity. The R-5 mitigation cell says "Spike" and names no alternate fallback.

## 2. User Scenarios & Testing

### 2.1 User Story 1 - Grant envelope, receipt, and token claims (Priority: P1)

The calling component validates a grant envelope, a receipt, and AI, billing, and feed token claims. The package defines the result envelope, the coverage snapshot, the feed event, and the operation object that later checks use. Canonical bytes, hashes, and Ed25519 signatures come from the consumed P2.1 APIs. The testkit ABO grant-key signer, platform receipt signer, and issuer minters produce the objects under test.

**Why this priority**: This unit depends on P2.1, which freezes the canonical, hash, and JWS APIs this story uses. User Story 2 depends on the operation object defined here, because the WebAuthn challenge is base64url(SHA-256(canonical operation object)).

**Independent Test**: E2E-P2.2-05, E2E-P2.2-06, and E2E-P2.2-07 in harness H-PKG (Node and workerd).

**Acceptance Scenarios**:

1. **Given** a grant envelope and an ABO signature over it, **When** the canonical hash is computed and the signature is verified, **Then** the hash is stable and the signature verifies. **Given** any field of that envelope mutated, **When** verification runs, **Then** it fails.
2. **Given** a receipt signed by the platform key over the canonical receipt without the signature, **When** the signature is verified, **Then** it verifies. **Given** `term_ids` tampered, **When** verification runs, **Then** it fails.
3. **Given** a billing token whose `exp − iat` is greater than 300 s, **When** the claim validator runs, **Then** the token is rejected. **Given** a feed token carrying `org`, **When** the claim validator runs, **Then** the token is rejected.

### 2.2 User Story 2 - WebAuthn assertion and Access JWT (Priority: P2)

The calling component verifies a WebAuthn assertion and an Access JWT. The testkit software authenticator (ES256 and EdDSA, attestation and assertion) and the Access team key, JWT minter, and certs document produce the objects under test. The challenge is base64url(SHA-256(canonical operation object)). The R-5 spike result records the ES256 DER-to-raw conversion and whether Access `amr` is meaningful.

**Why this priority**: It depends on User Story 1's operation object and on the canonical hash frozen by P2.1. User Story 3 scans the production bundle for the `testkit` subpath this story uses.

**Independent Test**: E2E-P2.2-01, E2E-P2.2-02, E2E-P2.2-03, and E2E-P2.2-04 in harness H-PKG (Node and workerd).

**Acceptance Scenarios**:

1. **Given** a testkit assertion over operation object O (`{op, params, actor_email, issued_at, nonce, contract_version}`), with challenge base64url(SHA-256(canonical O)), **When** the assertion is verified, **Then** it verifies. **Given** the same assertion against O′ with one param changed, **When** verification runs, **Then** it fails.
2. **Given** an assertion with the UV flag cleared, or with `clientDataJSON.origin` other than `https://ops.<vendor-domain>`, or with an `rpId` other than the console hostname, **When** verification runs, **Then** each fails.
3. **Given** an ES256 credential whose DER signature is converted to raw, and an EdDSA credential, **When** assertions are verified, **Then** both verify. **Given** another algorithm, **When** verification runs, **Then** it is rejected.
4. **Given** a valid Access JWT checked against the injected team certificates, **When** verification runs, **Then** the result is the email. **Given** a wrong `aud` tag, an expired token, or an unknown cert kid, **When** verification runs, **Then** each fails.

### 2.3 User Story 3 - Production bundle excludes the testkit (Priority: P3)

The calling component scans the production `ai-platform` bundle. The bundle contains no testkit code. Production code never imports the `testkit` subpath.

**Why this priority**: It depends on the `testkit` subpath export that User Story 1 and User Story 2 use to build signatures, assertions, and tokens.

**Independent Test**: E2E-P2.2-08 in harness H-PKG.

**Acceptance Scenarios**:

1. **Given** the production `ai-platform` bundle, **When** the bundle is scanned, **Then** it contains no testkit code.

### 2.4 Test plan

| ID | Harness | Entry point | Assertion | Proves | Story |
| --- | --- | --- | --- | --- | --- |
| E2E-P2.2-01 | H-PKG | Node and workerd vectors in `packages/vendor-contracts/test/` | A testkit assertion over operation O verifies; the same assertion against O′ (one param changed) fails. [AD-8 substitution] | FR-007, FR-008, FR-012 | User Story 2 |
| E2E-P2.2-02 | H-PKG | Node and workerd vectors in `packages/vendor-contracts/test/` | UV flag cleared, wrong origin, or wrong rpId → each fails. | FR-008 | User Story 2 |
| E2E-P2.2-03 | H-PKG | Node and workerd vectors in `packages/vendor-contracts/test/` | ES256 and EdDSA credentials both verify; another alg is rejected. [R-5] | FR-009 | User Story 2 |
| E2E-P2.2-04 | H-PKG | Node and workerd vectors in `packages/vendor-contracts/test/` | Access JWT: valid → email; wrong `aud` tag, expired, or unknown cert kid → fails. | FR-010, FR-012 | User Story 2 |
| E2E-P2.2-05 | H-PKG | Node and workerd vectors in `packages/vendor-contracts/test/` | Grant envelope: canonical hash stable; ABO signature verifies, and fails after any field mutation. | FR-002, FR-003, FR-012 | User Story 1 |
| E2E-P2.2-06 | H-PKG | Node and workerd vectors in `packages/vendor-contracts/test/` | Receipt signature verifies; tampered `term_ids` fails. | FR-004, FR-012 | User Story 1 |
| E2E-P2.2-07 | H-PKG | Node and workerd vectors in `packages/vendor-contracts/test/` | Claim validators: billing token with lifetime > 300 s rejected; feed token carrying `org` rejected. | FR-011, FR-012 | User Story 1 |
| E2E-P2.2-08 | H-PKG | Node bundle scan of the production `ai-platform` worker bundle (`ai-platform/wrangler.toml`, `main = src/worker.ts`, production env `ai-platform-gateway-production`) | A production `ai-platform` bundle contains no testkit code (bundle scan). | FR-012 | User Story 3 |

### 2.5 Edge Cases

- The same testkit assertion against O′ (one param changed) fails. [AD-8 substitution] (E2E-P2.2-01, 04 §1.5, 02 §3.3)
- UV flag cleared, wrong origin, or wrong `rpId` each fails. Origin must equal `https://ops.<vendor-domain>`. `rpId` is the console hostname. (E2E-P2.2-02, 04 §1.5)
- `type` other than `webauthn.get` fails. User presence cleared fails. User presence and user verification are both set. (04 §1.5)
- An algorithm other than ES256 (DER signature converted to raw) or EdDSA is rejected. [R-5] (E2E-P2.2-03, 04 §1.5, 01 §7 R-5)
- Access JWT with a wrong `aud` tag, an expired token, or an unknown cert kid fails. A valid token yields the email. (E2E-P2.2-04, 02 §3.3)
- Any mutated grant-envelope field fails ABO signature verification. (E2E-P2.2-05, 02 §3.3)
- A receipt with tampered `term_ids` fails signature verification. (E2E-P2.2-06, 04 §1.6)
- A billing token with `exp − iat` greater than 300 s is rejected. A feed token carrying `org` is rejected. AI token lifetime is ≤ 600 s. Feed token lifetime is ≤ 120 s. (E2E-P2.2-07, 04 §2.1)
- A production `ai-platform` bundle that contains testkit code fails the bundle scan. (E2E-P2.2-08)

## 3. Requirements

### 3.1 Functional Requirements

- **FR-001**: Every method returns `{contract_version, result, code, detail, receipt?}`. `result` is `ok` (read succeeded), `applied` (change made now; `receipt` present), `already_applied` (same id with the same content hash was applied before; the original `receipt` is returned), `conflict` (same id with a different content hash), `rejected` (validation failed; `code` says why; retrying cannot help), or `transient` (storage or DO unavailable, or a state that will clear; nothing was changed). For `transient`, `detail` is `unavailable`, `unknown_kid`, `awaiting_transfer`, or `transfer_pending`. (04 §1.2)
- **FR-002**: The grant envelope type has the 04 §1.4 field-table fields and rules. `contract_version` is an integer. `grant_id` is hex SHA-256 per 03 §7. `org_id` is the tenant UUID. `kind` is `term` or `term_adjustment`. `placement` is `queue` only at launch; `immediate` and `replace` are rejected (`placement_not_supported`). `source` is `{kind: paid, complimentary or transfer, ref, operator_email, reason}`; `operator_email` and `reason` are required unless `kind = paid`; `ref` is the ABO's `payment_id`, operator action id, or `transfer_id`, and is never a provider id. `plan` is `{plan_id, plan_version}`. `duration` is `{unit, count}`; `paid` is `month` with count 1, 3, or 12; `complimentary` is `month` or `day`. `allowance_credits` is an integer ≥ 1. `grace` is `{days, cap_rule}`; for `paid`, `days` ≤ `max_paid_grace_days` (7) and `cap_rule = proportional`. `adjustment`, for `term_adjustment`, is `{plan?, add_allowance?, extend_days?}`. `paid_at`, for `paid`, is the provider's payment time. `evidence` is `{content_sha256, approvals[]}`; for `paid`, the hash is of the ABO payment fact and its evidence; `approvals` holds operator assertions and the policy minimum is 1. `ceiling_override` is optional and needs a second, separate assertion. (04 §1.4)
- **FR-003**: The grant envelope's canonical hash is stable. An ABO signature (K-4) over that envelope verifies, and verification fails after any field mutation. Class M evidence for a coverage-changing method includes that ABO signature. The hash and the signature use the consumed canonical, hash, and JWS APIs. (04 §1.4; 02 §3.3; E2E-P2.2-05)
- **FR-004**: A receipt is `{contract_version, grant_id or reversal_id, installation_id, org_id, result, term_ids, applied_at, ledger_seq, envelope_sha256, kid, signature}`. The signature is by the platform key (02 K-3) over the canonical receipt without the signature. The signature verifies, and a tampered `term_ids` fails. (04 §1.6; E2E-P2.2-06)
- **FR-005**: A coverage snapshot carries `contract_version` (the snapshot shape version; every stored copy keeps it), `state` (03 §5.7), `reason` for non-available states (`none`, `expired`, `grace_exhausted`, `exhausted`, `reversed`, `transferred`, `transfer_pending`), `suspended` (boolean), `term` (null, or `{ref, plan_display_name, starts_at, ends_at, grace_ends_at, allowance, used, band}` with `band` of `ok`, `75`, `90`, or `exhausted`), `queued_count` (unheld queued terms), `held_count` (held terms), `coverage_through`, and the ordering key `binding_epoch`, `clinic_seq`. The snapshot contains no prices, payment references, or provider ids. (04 §1.7)
- **FR-006**: Each feed event is `{event_id, feed_seq, org_id, installation_id, binding_epoch, clinic_seq, kind, at, snapshot}`, and `snapshot` is the coverage snapshot of 04 §1.7. (04 §4.1)
- **FR-007**: The operation object is `{op, params, actor_email, issued_at, nonce, contract_version}`. `params` is the exact method input, without the assertion. The challenge is base64url(SHA-256(canonical operation object)). (04 §1.5)
- **FR-008**: WebAuthn assertion verification checks `rpId` (the console hostname), `clientDataJSON.origin` (`https://ops.<vendor-domain>`), `type` (`webauthn.get`), and both the user-presence and user-verification flags. A testkit assertion over operation O verifies. The same assertion against O′ (one param changed) fails. UV flag cleared, wrong origin, or wrong `rpId` each fails. Class HP evidence includes a WebAuthn assertion whose challenge is the hash of the canonical operation, with user verification set. (04 §1.5; 02 §3.3; E2E-P2.2-01; E2E-P2.2-02)
- **FR-009**: The credential algorithm is ES256, with the DER signature converted to raw, or EdDSA. ES256 and EdDSA credentials both verify. Another algorithm is rejected. The package parses a registration attestation for those algorithms. The R-5 spike result records the ES256 conversion and whether Access `amr` is meaningful. (04 §1.5; 01 §7 R-5; 06 §4 P2.2; E2E-P2.2-03)
- **FR-010**: Access JWT verification checks the forwarded `Cf-Access-Jwt-Assertion` against the injected Access team certificates, the `aud` tag, and expiry, and yields the email. A valid token yields the email. A wrong `aud` tag, an expired token, or an unknown cert kid fails. Verification lives in the shared package, next to WebAuthn, so both Workers use one copy. (02 §3.3; 06 §2 S7; E2E-P2.2-04)
- **FR-011**: All tokens use header `{alg: EdDSA, kid, typ: JWT}`, `iss` equal to the backend issuer id from `ai.issuer_id`, and `ver = "2"`. `org` comes from `current_org_id()`, never from an argument. Claim rules are: AI `aud` `ai-platform`, `sub` staff member id, `org` tenant id, `role` membership role, `branch` current branch, `scopes` `ai.*` permissions, `exp − iat` ≤ 600 s, `jti` UUID; billing `aud` `abo`, `sub` staff member id, `org` tenant id, `role` `administrator`, `branch` current branch, `scopes` absent, `exp − iat` ≤ 300 s, `jti` UUID; feed `aud` `ai-platform-feed`, `sub` `backend-feed`, `org` absent, `role` absent, `branch` absent, `scopes` absent, `exp − iat` ≤ 120 s, `jti` UUID. A billing token with lifetime greater than 300 s is rejected. A feed token carrying `org` is rejected. (04 §2.1; E2E-P2.2-07)
- **FR-012**: The package exports a `testkit` subpath, which production code must never import. The testkit provides a software authenticator (ES256 + EdDSA; attestation and assertion), an Access team key + JWT minter + certs document, an issuer key set + minters for the three audiences, an ABO grant-key signer, and a platform receipt signer. A production `ai-platform` bundle contains no testkit code. (06 §4 P2.2; 06 §2 S8; E2E-P2.2-08)

### 3.2 Key Entities

- **Result envelope**: `{contract_version, result, code, detail, receipt?}`. `result` is `ok`, `applied`, `already_applied`, `conflict`, `rejected`, or `transient`, with the meanings in FR-001. `transient` `detail` is `unavailable`, `unknown_kid`, `awaiting_transfer`, or `transfer_pending`. (04 §1.2)
- **Grant envelope**: The field table in FR-002. (04 §1.4)
- **Operation object**: `{op, params, actor_email, issued_at, nonce, contract_version}`. `params` is the exact method input, without the assertion. Challenge is base64url(SHA-256(canonical operation object)). (04 §1.5)
- **Receipt**: `{contract_version, grant_id or reversal_id, installation_id, org_id, result, term_ids, applied_at, ledger_seq, envelope_sha256, kid, signature}`. The platform key signs the canonical receipt without the signature. (04 §1.6)
- **Coverage snapshot**: The fields in FR-005. No prices, payment references, or provider ids. (04 §1.7)
- **Feed event**: `{event_id, feed_seq, org_id, installation_id, binding_epoch, clinic_seq, kind, at, snapshot}`. `snapshot` is the coverage snapshot. (04 §4.1)
- **Token claims**: AI, billing, and feed claims in FR-011. Header `{alg: EdDSA, kid, typ: JWT}`; `iss` from `ai.issuer_id`; `ver = "2"`. (04 §2.1)

## 4. Constitution Alignment

### 4.1 Architecture & Operations Impact

- **Clinic Fit**: One shared package holds the message types, WebAuthn and Access verification, and the testkit used by later clinic billing and coverage harnesses (06 §2 S7, S8). The codebase cell is `packages/vendor-contracts/`. The row names no wiring exception (rule S3).
- **Layer Placement**: Implementation stays in `packages/vendor-contracts/`. Node and workerd vectors in `packages/vendor-contracts/test/` reach the library (rule S8). The E2E-P2.2-08 scan reads the existing production `ai-platform` bundle and adds no second codebase. `plan.md` re-runs the constitution check in 02 §7 (rule S12).
- **Data Integrity & Security**: WebAuthn verification checks `rpId`, origin, `type`, and UP+UV, and the challenge is the hash of the canonical operation (04 §1.5, 02 §3.3). Access JWT verification uses injected team certificates, the `aud` tag, and expiry, and yields the email (02 §3.3). Grant and receipt signatures use the consumed JWS APIs (02 §3.3, 04 §1.6). A billing token lifetime is ≤ 300 s, and a feed token has no `org` (04 §2.1). This unit defines no tables.
- **Failure Handling**: Assertion verification fails when one param changes, when UV is cleared, when origin or `rpId` is wrong, or when the algorithm is neither ES256 nor EdDSA (E2E-P2.2-01, E2E-P2.2-02, E2E-P2.2-03). Access JWT verification fails on a wrong `aud` tag, expiry, or an unknown cert kid (E2E-P2.2-04). ABO signature verification fails after any grant-envelope field mutation (E2E-P2.2-05). Receipt verification fails when `term_ids` is tampered (E2E-P2.2-06). Claim validators reject a billing token lifetime above 300 s and a feed token that carries `org` (E2E-P2.2-07).

## 5. Out of Scope

where each check is enforced (→ P3.1 platform, P4.6/P4.7 ABO).

- No material from the Do not read sections: 04 §1.3 method semantics (names only), 03 §6.
- No rewrite of a Consumes contract: canonical, hash and JWS APIs; identifier functions + vectors; channel constants and the refusal shape (rule S7).
- No module that no test-plan row reaches, except this unit's library, which Node and workerd vectors and the bundle scan reach (rule S8).
- No removal of a transitional path a later unit owns (rule S9): enrollment, removed in P3.2; `/control/entitle`, which keeps test clinics admitted until P3.4; entitlement, plan, and invoice tables and all `/control/*` routes, removed in P3.10.
- No second codebase beyond `packages/vendor-contracts/`.

## 6. Success Criteria

### 6.1 Measurable Outcomes

- **SC-001**: E2E-P2.2-01, E2E-P2.2-02, E2E-P2.2-03, E2E-P2.2-04, E2E-P2.2-05, E2E-P2.2-06, and E2E-P2.2-07 pass in harness H-PKG in Node and in workerd, and E2E-P2.2-08 passes in harness H-PKG.
- **SC-002**: Every earlier suite stays green (rule S2).
- **SC-003**: CP-A — Do the frozen package contracts work in both runtimes, and are the vectors consumable by SQL/Dart? (rule S11)

## 7. Assumptions

- Rule S9: enrollment remains until P3.2; `/control/entitle` remains until P3.4; entitlement, plan, and invoice tables and `/control/*` routes remain until P3.10.
