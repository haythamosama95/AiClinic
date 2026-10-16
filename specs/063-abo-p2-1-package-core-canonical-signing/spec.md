# Feature Specification: Package core: canonical JSON, signing, identifiers, version constants

**Feature Branch**: `ai/063-abo-p2-1-package-core-canonical-signing`

**Created**: 2026-10-02

**Status**: Draft

**Input**: P2.1 — Package core: canonical JSON, signing, identifiers, version constants

## 1. Unit Contract

**Implements** — Read: 02 §1.2 (opening paragraph only); 04 §1.1 ("Canonical form" bullet); 04 §6.2 (last paragraph); 04 §7 (all); 03 §7; 04 §4.2 (first paragraph + `contract_version_unsupported` row).

- Package skeleton (TypeScript ESM, builds for workerd and Node), consumed by `ai-platform` as a `file:` dependency, with wrangler bundling proven.
- RFC 8785 canonicalisation; SHA-256 hex; Ed25519 compact JWS sign/verify (`alg=EdDSA`, `kid`) on WebCrypto.
- 03 §7 identifiers: subscription ref `AIC-…`, `payment_id`, the three `grant_id` forms, coverage `event_id`, `CK-/PAY-/REV-/GR-` refs, ULID (80 random bits), Crockford base-32.
- Per-channel version constants (04 §7.1, all = 1); negotiation helper (accept N and N−1, answer in the request's version; refusal `{code: contract_version_unsupported, accepted_versions}`).
- Golden vector files (canonical bytes, hashes, identifiers, JWS) for later SQL (P5.2) and Dart (P6.1) contract tests.
- Platform wiring: `src/vendor/contract-version.ts`; `Aip-Contract-Version` checked before token verification and echoed on every clinic `/v1/*` response, sent before the first SSE byte. H-AP harness sends it by default. Package CI job.

**Freezes** — canonical, hash and JWS APIs; identifier functions + vectors; channel constants and the refusal shape.

**Consumes** — None.

**Open questions relied on** — None.

**Spikes** — None.

## 2. User Scenarios & Testing

### 2.1 User Story 1 - Canonical bytes, signatures, and identifiers (Priority: P1)

The calling component canonicalises an object, hashes it, signs and verifies a compact JWS, and computes the identifier forms. The same canonical bytes and the same signature hold in Node and in workerd.

**Why this priority**: This unit depends on no earlier unit. The clinic-route story depends on the canonical, hash, JWS, and identifier APIs this story freezes.

**Independent Test**: E2E-P2.1-01, E2E-P2.1-02, and E2E-P2.1-03 in harness H-PKG (Node and workerd).

**Acceptance Scenarios**:

1. **Given** the golden vector objects, **When** canonical bytes are produced in Node and in workerd, **Then** the canonical bytes of every vector object equal the fixture.
2. **Given** a JWS signed in Node, **When** workerd verifies it, **Then** verification succeeds, and a JWS signed in workerd verifies in Node. **Given** a changed payload or a changed `kid`, **When** verification runs, **Then** it fails.
3. **Given** the fixture org and a `payment_id`, **When** the identifier vectors are evaluated, **Then** the subscription ref matches the fixture org and `grant_id(paid)` equals SHA-256(`"grant:paid:"` ‖ `payment_id`).

### 2.2 User Story 2 - Clinic route contract version (Priority: P2)

The calling component sends `Aip-Contract-Version` on a clinic `/v1/*` route. Version 1 is echoed on the response. A missing header, including when the token is invalid, and version 2 are refused with `contract_version_unsupported` before token verification and before any write. On a streamed response the header is present before the first SSE event. The existing system and e2e suites stay green when the harness sends the header.

**Why this priority**: It depends on the package skeleton from User Story 1. This story adds the channel constants, the negotiation helper, and the clinic-route header. The regression line sits on this story.

**Independent Test**: E2E-P2.1-04, E2E-P2.1-05, E2E-P2.1-06, and E2E-P2.1-07 in harness H-AP.

**Acceptance Scenarios**:

1. **Given** `POST /v1/requests` without `Aip-Contract-Version` and with an invalid token, **When** the platform handles the request, **Then** the response is HTTP 400 `contract_version_unsupported` with `accepted_versions`, and no `ai_request` row is written.
2. **Given** `GET /v1/capabilities` with version 1, **When** the response is returned, **Then** the `Aip-Contract-Version` header is echoed. **Given** version 2, **When** the route is called, **Then** the response is HTTP 400.
3. **Given** a streamed request, **When** the response is sent, **Then** the response header is present before the first SSE event.
4. **Given** the existing system and e2e suites, **When** they run with the header, **Then** they are green.

### 2.3 Test plan

| ID | Harness | Entry point | Assertion | Proves | Story |
| --- | --- | --- | --- | --- | --- |
| E2E-P2.1-01 | H-PKG | Node and workerd vectors in `packages/vendor-contracts/test/` | Canonical bytes of every vector object equal the fixture in Node and in workerd. | FR-001, FR-002, FR-003, FR-010 | User Story 1 |
| E2E-P2.1-02 | H-PKG | Node and workerd vectors in `packages/vendor-contracts/test/` | A JWS signed in Node verifies in workerd and the reverse; a changed payload or `kid` fails. | FR-004 | User Story 1 |
| E2E-P2.1-03 | H-PKG | Node and workerd vectors in `packages/vendor-contracts/test/` | Identifier vectors: the subscription ref of the fixture org, and `grant_id(paid)` = SHA-256(`"grant:paid:"` ‖ `payment_id`). | FR-006, FR-007, FR-010 | User Story 1 |
| E2E-P2.1-04 | H-AP | `POST /v1/requests` via `SELF.fetch` on `ai-platform/src/worker.ts` `fetch` | `POST /v1/requests` without `Aip-Contract-Version` (and with an invalid token) returns 400 `contract_version_unsupported` and `accepted_versions`, and writes no `ai_request` row. [NFR-09] | FR-009 | User Story 2 |
| E2E-P2.1-05 | H-AP | `GET /v1/capabilities` via `SELF.fetch` on `ai-platform/src/worker.ts` `fetch` | Version 1 echoes `Aip-Contract-Version`; version 2 returns 400. | FR-008, FR-009 | User Story 2 |
| E2E-P2.1-06 | H-AP | Streamed `POST /v1/requests` via `SELF.fetch`; SSE body from `handleAdapterRequest` in `ai-platform/src/adapter.ts` (`content-type: text/event-stream`) | The response header is present before the first SSE event. | FR-009 | User Story 2 |
| E2E-P2.1-07 | H-AP | Existing system and e2e suites via `SELF.fetch` in `ai-platform/test/system/harness.ts` (`ai-platform/test/system/`, `ai-platform/test/e2e/`) | All existing system and e2e suites are green with the header. | FR-002, FR-011 | User Story 2 |

### 2.4 Edge Cases

- `POST /v1/requests` without `Aip-Contract-Version`, with an invalid token, returns HTTP 400 `contract_version_unsupported` and `accepted_versions`, and writes no `ai_request` row. The check runs before token verification. [NFR-09] (E2E-P2.1-04, 04 §4.2, 04 §7.2)
- `GET /v1/capabilities` with version 1 echoes `Aip-Contract-Version`. Version 2 returns HTTP 400. (E2E-P2.1-05)
- A missing version, or a version outside N and N−1, gets `contract_version_unsupported` with `accepted_versions`. The check runs before authentication and before any write. (04 §7.2)
- A changed JWS payload or a changed `kid` fails verification. (E2E-P2.1-02, 04 §1.1)
- A streamed clinic response sends `Aip-Contract-Version` before the first byte of the stream, so the header is present before the first SSE event. (E2E-P2.1-06, 04 §4.2, 04 §7.1)
- The heartbeat ping and `send_email` alerts carry no contract payload. (04 §7.1)

## 3. Requirements

### 3.1 Functional Requirements

- **FR-001**: The shared package is `packages/vendor-contracts/` at the repository root, a `file:` dependency, because the repository has no workspace tooling. `ai-platform` consumes that package and keeps no separate copy of canonical JSON, Ed25519 JWS, or the contract-version constants. The backend cannot import the package. (02 §1.2; 04 §6.2)
- **FR-002**: The package skeleton is TypeScript ESM, builds for workerd and Node, and is consumed by `ai-platform` as a `file:` dependency, with wrangler bundling proven. A package CI job runs the package tests. (06 §4 P2.1; 06 §3 V7; 04 §1.1; 04 §6.2)
- **FR-003**: Signed and hashed objects use the JSON Canonicalization Scheme (RFC 8785). Hashes are SHA-256, hex-encoded. (04 §1.1)
- **FR-004**: Signatures are Ed25519 over the canonical bytes, serialised as compact JWS (RFC 7515 compact serialization: base64url header, payload and signature joined by `.`) with header `{alg: "EdDSA", kid}`, where `kid` names the signing key in the relevant key set (02 §3.1, K-2 to K-4). Signing and verification run on WebCrypto (`crypto.subtle`), which both workerd and Node provide, so a signature made on either runtime verifies on the other. (04 §1.1; 04 §6.2)
- **FR-005**: Record ids are ULID with 80 random bits, encoded in Crockford base-32. The references below use that same Crockford base-32 encoding. (03 §7)
- **FR-006**: The subscription reference is `AIC-` plus 8 Crockford base-32 characters of SHA-256(`"sub-ref:"` ‖ `org_id`). `org_id` is the backend tenant UUID. Each system computes the reference with no lookup. The subscription ref of the fixture org equals the identifier vector. (03 §7; 06 §4 E2E-P2.1-03)
- **FR-007**: `grant_id(paid)` is SHA-256 over `"grant:paid:"` ‖ `payment_id`, and the paid vector equals that value. (03 §7; 06 §4 E2E-P2.1-03)
- **FR-008**: Each integer channel in 04 §7.1 has one version constant, and that constant is 1. The channels are Desktop → ABO clinic API `/v1/*` (`Abo-Contract-Version`); ABO console → ABO `/ops/*`; Desktop → backend RPCs (`p_contract_version`); Desktop → platform clinic routes (`Aip-Contract-Version`); Backend feed puller → platform feed (`Aip-Contract-Version`); ABO → `VendorEntrypoint` (`contract_version` on every argument object and every result); Platform Worker → per-clinic DO RPC (`contract_version`); browser return from Paymob → ABO `/return/{provider}` (`v` query parameter); ABO ↔ Paymob API and `/notify/{provider}`. Tokens keep their own `ver` claim (`"2"`, §2.1). The heartbeat ping and `send_email` alerts carry no contract payload. The version constants live in `packages/vendor-contracts/`. (04 §7.1; 04 §7.2)
- **FR-009**: A receiver accepts the current version N and the previous N−1 of each channel it receives, and answers in the version the request used. A missing version, or one outside N and N−1, gets `{code: contract_version_unsupported, accepted_versions}`. The check runs before authentication and before any write. Every clinic route (`/v1/requests`, `/v1/requests/{ref}`, `/v1/capabilities`, `/v1/coverage`) requires the `Aip-Contract-Version` request header and returns it on every response, including streamed ones, where it is sent before the first byte of the stream. On that channel the refusal is HTTP 400 `contract_version_unsupported`, checked before token verification, with extra field `accepted_versions`. `POST /v1/requests` without the header, including when the token is invalid, writes no `ai_request` row. (04 §7.2; 04 §4.2; 04 §7.1; 06 §4 E2E-P2.1-04)
- **FR-010**: Golden vector files record canonical bytes, hashes, identifiers, and JWS, for later SQL (P5.2) and Dart (P6.1) contract tests. (06 §4 P2.1; 03 §7)
- **FR-011**: Platform wiring is `ai-platform/src/vendor/contract-version.ts`. The H-AP harness sends `Aip-Contract-Version` by default. Existing system and e2e suites stay green with that header. (06 §4 P2.1; 06 §3 V1)
- **FR-012**: `payment_id` is SHA-256(`"payment:"` ‖ `provider_id` ‖ `":"` ‖ provider transaction reference), hex-encoded. `grant_id` for a complimentary grant is SHA-256 over `"grant:comp:"` ‖ operator action id. `grant_id` for a transfer is SHA-256 over `"grant:transfer:"` ‖ `transfer_id` ‖ `":"` ‖ n. Coverage `event_id` is `installation_id` ‖ `":"` ‖ `clinic_seq`, where `installation_id` is the platform clinic UUID. Human references are `CK-`, `PAY-`, `REV-`, or `GR-` plus 8 Crockford base-32 characters of the record id. (03 §7; 04 §1.1)

### 3.2 Key Entities

Not applicable — this unit defines no entities.

## 4. Constitution Alignment

### 4.1 Architecture & Operations Impact

- **Clinic Fit**: One shared package holds canonical JSON, Ed25519 JWS, and the contract-version constants, and the AI Platform worker depends on it as a `file:` dependency (02 §1.2). The codebase cell is `packages/vendor-contracts/` (new) plus thin wiring in `ai-platform/`. The row names the wiring exception: platform header wiring (rule S3).
- **Layer Placement**: `packages/vendor-contracts/` is the `file:` dependency. Clinic `/v1/*` version checks are the thin `ai-platform` wiring in `src/vendor/contract-version.ts`. The backend cannot import the package (04 §6.2). `plan.md` re-runs the constitution check in 02 §7 (rule S12).
- **Data Integrity & Security**: `Aip-Contract-Version` is checked before token verification and before any write (04 §4.2, 04 §7.2). Signatures are Ed25519 compact JWS (`alg=EdDSA`, `kid`) on WebCrypto over RFC 8785 bytes (04 §1.1).
- **Failure Handling**: A missing version, or a version outside N and N−1, returns `contract_version_unsupported` with `accepted_versions` and changes nothing (04 §7.2). `POST /v1/requests` without the header writes no `ai_request` row (E2E-P2.1-04). A changed JWS payload or `kid` fails verification (E2E-P2.1-02).

## 5. Out of Scope

message types, WebAuthn, Access, testkit (→ P2.2); entrypoint version checks (→ P3.1); feed route (→ P3.9); backend and Dart copies of the constants (→ P5.1, P6.1).

- No material from the Do not read section: 04 §1.2–§1.7 (→ P2.2).
- No Consumes contract to rewrite. This unit depends on no earlier unit.
- No module that no test-plan row reaches, except the package half, which Node and workerd vectors reach (rule S8).
- No removal of a transitional path a later unit owns (rule S9): enrollment, removed in P3.2; `/control/entitle`, which keeps test clinics admitted until P3.4; entitlement, plan, and invoice tables and all `/control/*` routes, removed in P3.10.
- No second codebase beyond `packages/vendor-contracts/` and the thin `ai-platform/` header wiring named in the codebase cell.

## 6. Success Criteria

### 6.1 Measurable Outcomes

- **SC-001**: E2E-P2.1-01, E2E-P2.1-02, and E2E-P2.1-03 pass in harness H-PKG, and E2E-P2.1-04, E2E-P2.1-05, E2E-P2.1-06, and E2E-P2.1-07 pass in harness H-AP.
- **SC-002**: Every earlier suite stays green (rule S2).

## 7. Assumptions

- Rule S9: enrollment remains until P3.2; `/control/entitle` remains until P3.4; entitlement, plan, and invoice tables and `/control/*` routes remain until P3.10.
