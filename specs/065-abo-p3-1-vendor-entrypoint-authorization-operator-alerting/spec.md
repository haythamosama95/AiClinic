# Feature Specification: `VendorEntrypoint`, authorization classes, operator credentials and platform alerting

**Feature Branch**: `ai/065-abo-p3-1-vendor-entrypoint-authorization-operator-alerting`

**Created**: 2026-10-02

**Status**: Draft

**Input**: P3.1 — `VendorEntrypoint`, authorization classes, operator credentials and platform alerting

## 1. Unit Contract

**Implements** — Read: 02 §1.3; 02 §3.3; 04 §1.1; 04 §1.3 (intro + rows register/revoke/listOperatorCredentials); 04 §1.5; 03 §3.2 rows `operator_credential`, `assertion_used`, `control_audit`, `platform_alert`; 02 §5 (decision paragraph); 04 §6.4 (vars Access/WebAuthn, `send_email`, observability).

- `VendorEntrypoint` (named `WorkerEntrypoint`) exported; one class table (M/H/HP) per method; `contract_version` checked on every argument object; results in the 04 §1.2 envelope.
- Class H: forwarded Access JWT → actor email. This unit implements no class H method. `registerOperatorCredential` and `revokeOperatorCredential` are class HP, so they include that Access JWT check. Class HP also applies the 04 §1.5 assertion rules (active credential, ≤ 5 min, single use via `assertion_used`, actor = Access email).
- `operator_credential`: bootstrap only while the table is empty; register (HP, `pending` 24 h, `approved_by`); revoke (HP); `listOperatorCredentials` (M).
- `control_audit` actor = Access email, plus `assertion_sha256`; every H/HP call that passes the Access JWT check is audited. A missing, expired, or wrong-`aud` Access JWT writes nothing.
- `src/alert`: `platform_alert` dedupe/repeat/retry; `send_email` to the fixed destination (codes + ids + decoded operation); `*/5` cron branch (alert retry, heartbeat ping); AL-13 for credential bootstrap/register/revoke.
- Observability on; JSON log lines; a failing scheduled job alerts. Platform clock module + test clock control (rule V4).
- H-AP: self service binding to `VendorEntrypoint`, `vendorCall` helper, email and heartbeat capture, Access certs fixture (rule V2 step 1).

**Freezes** — method dispatch + class table; auth refusal codes; credential lifecycle; alert body format; `platform_alert`.

**Consumes** — the message types of 04 §1.2–§1.7 and §2.1; the verification APIs; the testkit API (used by every later harness). CP-A. Changing one is out of scope (rule S7).

**Open questions relied on** — OQ-5. **Default:** accepted as described in rule V4.

**Spikes** — R-5 (rule S6). This unit's part is Access `amr` and service-binding caller identity. The named fallback is EdDSA-only credentials (05 §10, Spike-dependent items).

## 2. User Scenarios & Testing

### 2.1 User Story 1 - Entrypoint version gate and Access JWT refusal (Priority: P1)

The ABO calls the platform's named `WorkerEntrypoint` class `VendorEntrypoint` over a service binding. The entrypoint is not reachable from the internet. Every argument object carries `contract_version`. A missing or unsupported version is refused before authentication and before any write. The methods this unit implements are `registerOperatorCredential` (HP, or bootstrap), `revokeOperatorCredential` (HP), and `listOperatorCredentials` (M). `revokeOperatorCredential` takes `access_jwt`. The platform checks the forwarded `Cf-Access-Jwt-Assertion` against the Access team certificates, the `aud` tag, and expiry. A class HP call whose Access JWT is missing, expired, or has the wrong `aud` is `rejected` with code `unauthenticated` and writes nothing (02 §3.3).

**Why this priority**: This unit depends on P2.2, which freezes the result envelope, the Access JWT verification API, and the testkit. User Story 2's credential methods, and the AL-13 rows User Story 3 retries, are calls on this entrypoint. A refused `contract_version` writes nothing before those calls run.

**Independent Test**: E2E-P3.1-05 and E2E-P3.1-06 in harness H-AP.

**Acceptance Scenarios**:

1. **Given** `revokeOperatorCredential` (class HP), **When** the forwarded Access JWT is missing, expired, or has the wrong `aud`, **Then** the call is `rejected` with code `unauthenticated`, `receipt` is absent, and no state changes. [TB-6, AD-11]
2. **Given** any `VendorEntrypoint` method, **When** `contract_version` is missing or is 2, **Then** the result is `rejected` with code `contract_version_unsupported` and nothing is written, before authentication and before any write.

### 2.2 User Story 2 - Operator credentials and class HP (Priority: P2)

The operator registers a credential, and the ABO calls class HP methods with an Access JWT and a WebAuthn assertion. Bootstrap registration is allowed only while `operator_credential` is empty, without an approving assertion, and the credential stays `pending` for 24 hours. An HP call uses a credential only after that delay, when the credential is `active`. The assertion is over the exact operation, is at most 5 minutes old, is single-use through `assertion_used`, and `actor_email` equals the Access email. Revoke is class HP. `listOperatorCredentials` is class M and returns `ok` with the active keys in `detail`. Every H/HP call that passes the Access JWT check writes `control_audit` with the Access email and `assertion_sha256`. A missing, expired, or wrong-`aud` Access JWT writes nothing. Bootstrap, register, and revoke raise AL-13.

**Why this priority**: It depends on P2.2's verification APIs and testkit, and on User Story 1's entrypoint and version gate. User Story 3 retries AL-13 after `send_email` fails, and those alerts are raised by the bootstrap, register, and revoke calls in this story.

**Independent Test**: E2E-P3.1-01, E2E-P3.1-02, E2E-P3.1-03, E2E-P3.1-04, E2E-P3.1-07, and E2E-P3.1-10 in harness H-AP.

**Acceptance Scenarios**:

1. **Given** an empty `operator_credential` table, **When** `registerOperatorCredential` runs without an approving assertion, **Then** the result is `ok`, `detail` is the JSON text of the `operator_credential` row with `status` `pending`, `receipt` is absent, `code` is empty, and AL-13 is marked bootstrap. **Given** a second registration without approval, **When** it is submitted, **Then** it is `rejected`.
2. **Given** an HP call that uses a credential less than 24 hours old, **When** the call is made, **Then** it is rejected. **Given** the test clock has passed +24 h, **When** the same HP call is made, **Then** the result is `ok`, `detail` is the JSON text of the `operator_credential` row, `receipt` is absent, and `code` is empty. The production and staging wrangler environments carry no clock control.
3. **Given** a valid Access JWT and an assertion over the exact operation, **When** `revokeOperatorCredential` is called, **Then** the result is `ok`, `detail` is the JSON text of that `operator_credential` row, `receipt` is absent, `code` is empty, the result carries `contract_version`, and `control_audit` records `actor` as the Access email and `assertion_sha256`. **Given** that same assertion replayed, **When** the HP call is made again, **Then** it is rejected (`assertion_used`).
4. **Given** an assertion whose `issued_at` is 6 minutes old, **When** the HP call is made, **Then** it is rejected. **Given** an `actor_email` that does not equal the Access email, **When** the HP call is made, **Then** it is rejected.
5. **Given** credential A and credential B, **When** A revokes B, **Then** an HP call that uses B fails and AL-13 is sent. [K-7 rotation]
6. **Given** registered operator credentials, **When** `listOperatorCredentials` is called, **Then** the result is `ok` and `detail` is the JSON text of an array of `{credential_id, public_key_cose, alg}` for each row with `status` `active`. `receipt` is absent, and `code` is empty.

### 2.3 User Story 3 - Platform alerting and the five-minute cron (Priority: P3)

The platform stores alerts in `platform_alert` and sends them with `send_email` to the fixed verified destination. Bodies carry codes and ids, plus the decoded operation. Deduplicated alerts are retried from the alert table. The `*/5` cron retries an unsent alert, pings the heartbeat URL, and raises a platform alert when a job inside that run fails. Observability is on, and log lines are JSON.

**Why this priority**: It depends on P2.2 only through the frozen envelope and testkit already used to raise alerts, and on User Story 2, which raises AL-13 for credential bootstrap, register, and revoke. Those rows are what the `*/5` retry sends. Every earlier suite stays green (rule S2).

**Independent Test**: E2E-P3.1-08 and E2E-P3.1-09 in harness H-AP. Every earlier suite stays green (rule S2).

**Acceptance Scenarios**:

1. **Given** `send_email` throws, **When** an alert is handed to the binding, **Then** the alert stays unsent. **When** the next `*/5` run executes, **Then** it sends that alert exactly once. [FM-16]
2. **Given** the `*/5` cron, **When** it runs, **Then** it pings the heartbeat URL. **Given** a failing job inside that run, **When** the cron runs, **Then** it raises a platform alert.

### 2.4 Test plan

| ID | Harness | Entry point | Assertion | Proves | Story |
| --- | --- | --- | --- | --- | --- |
| E2E-P3.1-01 | H-AP | `VendorEntrypoint.registerOperatorCredential` over the H-AP self service binding, `vendorCall(method, args, {accessJwt, assertion})` in `ai-platform/test/system/harness.ts` | Empty registry: bootstrap registration without approval → `ok`; `detail` is the JSON text of the row with `status` `pending`; `receipt` absent; `code` empty; AL-13 marked bootstrap; a second unapproved registration → `rejected`. The captured `send_email` body carries codes and ids, plus the decoded operation. | FR-006, FR-009, FR-013, FR-019, FR-022, FR-025 | User Story 2 |
| E2E-P3.1-02 | H-AP | `VendorEntrypoint` class-HP method (`registerOperatorCredential` or `revokeOperatorCredential`) over the H-AP self service binding, `vendorCall` in `ai-platform/test/system/harness.ts`; test clock bound only from `ai-platform/vitest.workers.config.ts` | HP call using a credential < 24 h old → rejected; after the test clock passes +24 h → `ok`, with the row in `detail`, `receipt` absent, and `code` empty. Production and staging wrangler envs carry no clock control. No local sleep over 2 s. | FR-011, FR-014 | User Story 2 |
| E2E-P3.1-03 | H-AP | `VendorEntrypoint` class-HP method (`revokeOperatorCredential`) over the H-AP self service binding, `vendorCall` in `ai-platform/test/system/harness.ts` | HP with a valid Access JWT + assertion over the exact operation → `ok`; `detail` is the JSON text of that `operator_credential` row; `receipt` absent; `code` empty; the result carries `contract_version`; `control_audit.actor` is the Access email and `assertion_sha256` is stored; replaying the same assertion → rejected (`assertion_used`). | FR-003, FR-004, FR-010, FR-011, FR-012, FR-017 | User Story 2 |
| E2E-P3.1-04 | H-AP | `VendorEntrypoint` class-HP method (`revokeOperatorCredential`) over the H-AP self service binding, `vendorCall` in `ai-platform/test/system/harness.ts` | Assertion `issued_at` 6 min old → rejected; `actor_email` ≠ Access email → rejected. | FR-011, FR-015 | User Story 2 |
| E2E-P3.1-05 | H-AP | `VendorEntrypoint.revokeOperatorCredential` over the H-AP self service binding, `vendorCall(method, args, {accessJwt, assertion})` in `ai-platform/test/system/harness.ts` | `revokeOperatorCredential` (class HP) with a missing, expired or wrong-`aud` Access JWT → `rejected` with code `unauthenticated`; `receipt` absent; nothing written. [TB-6, AD-11] | FR-001, FR-004, FR-005, FR-016, FR-024 | User Story 1 |
| E2E-P3.1-06 | H-AP | Any `VendorEntrypoint` method over the H-AP self service binding, `vendorCall` in `ai-platform/test/system/harness.ts` | Any method with `contract_version` missing or 2 → `rejected` `contract_version_unsupported`; nothing written, before authentication and before any write. | FR-002, FR-017 | User Story 1 |
| E2E-P3.1-07 | H-AP | `VendorEntrypoint.revokeOperatorCredential`, then an HP call with credential B, over the H-AP self service binding, `vendorCall` in `ai-platform/test/system/harness.ts` | Credential A revokes B → HP with B fails; AL-13 sent. The revoke call audits `actor` as the Access email and `assertion_sha256`. [K-7 rotation] | FR-007, FR-012, FR-018, FR-022 | User Story 2 |
| E2E-P3.1-08 | H-AP | `scheduled()` cron `*/5` via `runScheduled` in `ai-platform/test/system/harness.ts`, after `send_email` throws | `send_email` throws → alert stays unsent; the next `*/5` run sends it exactly once. The captured body carries codes and ids, plus the decoded operation. [FM-16] | FR-019, FR-020, FR-025 | User Story 3 |
| E2E-P3.1-09 | H-AP | `scheduled()` cron `*/5` via `runScheduled` in `ai-platform/test/system/harness.ts` | `*/5` cron pings the heartbeat URL (captured outbound fetch to the configured URL); a failing job inside it raises a platform alert. The failing job emits a JSON log line. | FR-021, FR-023, FR-025 | User Story 3 |
| E2E-P3.1-10 | H-AP | `VendorEntrypoint.listOperatorCredentials` over the H-AP self service binding, `vendorCall` in `ai-platform/test/system/harness.ts` | `listOperatorCredentials` returns `ok`. `detail` is the JSON text of an array of `{credential_id, public_key_cose, alg}` for each row with `status` `active`. `receipt` is absent, and `code` is empty. The result carries `contract_version`. | FR-001, FR-008, FR-017 | User Story 2 |

### 2.5 Edge Cases

- A second registration without an approving assertion, while `operator_credential` is no longer empty, is `rejected`. Bootstrap without an approving assertion is allowed only while the table is empty. That result is `ok`: `detail` is the JSON text of the `operator_credential` row with `status` `pending`, `receipt` is absent, and `code` is empty. (E2E-P3.1-01, 04 §1.3)
- An HP call that uses a credential whose 24-hour activation delay has not passed is rejected. After the test clock passes +24 h, that call is `ok`: `detail` is the JSON text of the `operator_credential` row, `receipt` is absent, and `code` is empty. (E2E-P3.1-02, 04 §1.5)
- Replaying an assertion inserts a challenge hash that is already in `assertion_used`, and the call is `rejected` (`assertion_used`). (E2E-P3.1-03, 04 §1.5, 03 §3.2)
- An assertion with `issued_at` 6 minutes old is rejected. An `actor_email` that does not equal the Access email is rejected. The freshness rule is `issued_at` within 5 minutes of now. (E2E-P3.1-04, 04 §1.5)
- `revokeOperatorCredential` with a missing, expired, or wrong-`aud` Access JWT is `rejected` with code `unauthenticated` and does not change state. `receipt` is absent. Nothing is written: no `operator_credential` change, no `assertion_used` row, and no `control_audit` row. (E2E-P3.1-05, 02 §3.3, 04 §1.3) [TB-6, AD-11]
- A method whose `contract_version` is missing or is 2 is `rejected` with code `contract_version_unsupported`. Nothing is written. The refusal happens before authentication and before any write. The current channel version at launch is 1. (E2E-P3.1-06, 04 §1.1, 06 §3 V5)
- After credential A revokes B, an HP call that uses B fails, because the credential is not `active`. AL-13 is sent. (E2E-P3.1-07, 04 §1.5) [K-7 rotation]
- When `send_email` throws, the alert stays unsent. The next `*/5` run sends it exactly once. (E2E-P3.1-08, 02 §5) [FM-16]
- A failing job inside the `*/5` run raises a platform alert. That run pings the heartbeat URL. (E2E-P3.1-09, 02 §5)
- `listOperatorCredentials` returns `ok`. `detail` is the JSON text of an array of `{credential_id, public_key_cose, alg}` for each `operator_credential` with `status` `active`. `receipt` is absent, and `code` is empty. (E2E-P3.1-10, 04 §1.3)
- Production and staging wrangler environments carry no test clock control. (E2E-P3.1-02, 06 §3 V4)

## 3. Requirements

### 3.1 Functional Requirements

- **FR-001**: `VendorEntrypoint` is a named `WorkerEntrypoint`. The ABO calls it over a service binding. It is not reachable from the internet. Authentication is per method: machine, human, or human-plus-passkey (02 §3.3). (02 §1.3)
- **FR-002**: Transport is RPC methods on `VendorEntrypoint`. The platform never calls the ABO. Every argument object and every result carries `contract_version`. The platform accepts N and N−1 and answers `rejected` with code `contract_version_unsupported` otherwise. Tokens carry `ver`, checked against the existing `token_contract` table. (04 §1.1)
- **FR-003**: Every method returns `{contract_version, result, code, detail, receipt?}`. `detail` is a string. The object has no other key. `receipt` is present when `result` is `applied` or `already_applied`, and then it is a receipt (04 §1.6). On every other result, `receipt` is absent. `ok` means the read succeeded. A successful `registerOperatorCredential`, `revokeOperatorCredential`, or `listOperatorCredentials` is also `ok`: those methods do not record a grant or a reversal, so they do not return `applied` or `already_applied`. On register and revoke, `detail` is the JSON text of the `operator_credential` row. On `listOperatorCredentials`, `detail` is the JSON text of an array of `{credential_id, public_key_cose, alg}` for each active row. `code` is empty and `receipt` is absent on those `ok` results. `applied` means a change was made now and `receipt` is present. `already_applied` means the same id with the same content hash was applied before and the original `receipt` is returned. `conflict` means the same id with a different content hash. `rejected` means validation failed, `code` says why, and retrying cannot help. `transient` means storage or the DO is unavailable, or a state that will clear, and nothing was changed; `detail` is `unavailable`, `unknown_kid`, `awaiting_transfer`, or `transfer_pending`. (04 §1.2)
- **FR-004**: Every `VendorEntrypoint` method has exactly one class. Class M requires the service binding, plus an ABO signature (K-4) where the method changes coverage. Class H requires the forwarded `Cf-Access-Jwt-Assertion`, checked against the Access team certificates, the `aud` tag, and expiry; the email becomes the audit actor. Class HP requires class H plus a WebAuthn assertion whose challenge is the hash of the canonical operation, with user verification set, single use, and age at most 5 minutes. The platform verifies classes H and HP itself. (02 §3.3)
- **FR-005**: Each H and HP method takes `access_jwt`. Each HP method also takes `assertion`. (04 §1.3)
- **FR-006**: `registerOperatorCredential` is class HP, or bootstrap. The input is a WebAuthn attestation and an approving assertion. The approving assertion is absent only while the table is empty. `ok` inserts the row, `pending` for 24 hours. The same `credential_id` stored with the same `public_key_cose` is `ok` again and does not insert another row. `conflict` when it is stored with a different `public_key_cose`. On `ok`, `detail` is the JSON text of the `operator_credential` row (03 §3.2), `code` is empty, and `receipt` is absent. The method is idempotent by `credential_id`. (04 §1.3)
- **FR-007**: `revokeOperatorCredential` is class HP. The input is `credential_id`. `ok` when the row becomes `revoked`, and `ok` when it is already `revoked`. `detail` is the JSON text of that `operator_credential` row (03 §3.2). `code` is empty and `receipt` is absent. The method is idempotent by target state. (04 §1.3)
- **FR-008**: `listOperatorCredentials` is class M. It takes no argument beyond `contract_version`. The result is `ok`. `detail` is the JSON text of an array of `{credential_id, public_key_cose, alg}` for each `operator_credential` with `status` `active` (03 §3.2), so the ABO can verify assertions for its own HP actions (05 §3.2). `receipt` is absent, and `code` is empty. (04 §1.3)
- **FR-009**: `operator_credential` has `credential_id`, `operator_email`, `public_key_cose`, `alg`, `status` (`pending`, `active`, `revoked`), `activates_at`, `approved_by`, and `revoked_by`. (03 §3.2)
- **FR-010**: `assertion_used` has `challenge_sha256`, `credential_id`, and `used_at`. The challenge hash is inserted into `assertion_used` and must not already be there. A replay is `rejected` with code `assertion_used`. (03 §3.2; 04 §1.5; E2E-P3.1-03)
- **FR-011**: The platform enforces the 04 §1.5 assertion rules on a class HP call. The operation object is `{op, params, actor_email, issued_at, nonce, contract_version}`, and `params` is the exact method input, without the assertion. The challenge is base64url(SHA-256(canonical operation object)). `rpId` is the console hostname. `clientDataJSON.origin` equals `https://ops.<vendor-domain>`. `type` is `webauthn.get`. User presence and user verification are both set. The credential is `active` in `operator_credential` (its 24-hour activation delay has passed), algorithm ES256 (DER signature converted to raw) or EdDSA. `issued_at` is within 5 minutes of now. `actor_email` equals the email in the Access JWT verified for the same call. An HP call that uses a credential less than 24 hours old is rejected; after the test clock passes +24 h, the call is `ok`. An assertion whose `issued_at` is 6 minutes old is rejected. An `actor_email` that does not equal the Access email is rejected. (04 §1.5; E2E-P3.1-02; E2E-P3.1-03; E2E-P3.1-04)
- **FR-012**: `control_audit.actor` is the Access email, and the row adds `assertion_sha256`. Every H/HP call that passes the Access JWT check is audited. A missing, expired, or wrong-`aud` Access JWT writes nothing, including no `control_audit` row (FR-016). (03 §3.2; 02 §3.3; 06 §4 P3.1)
- **FR-013**: With an empty registry, bootstrap registration without approval yields `pending`, and AL-13 is marked bootstrap. A second unapproved registration is `rejected`. (04 §1.3; 06 §4 P3.1; E2E-P3.1-01)
- **FR-014**: The worker reads time through one clock module. Only the test vitest config binds a test-only clock control. A config test asserts that the production and staging wrangler envs carry no clock control. No local scenario sleeps more than 2 s of real time. The test clock is what moves a credential across the 24-hour activation delay. (06 §3 V4; 06 §4 P3.1; E2E-P3.1-02)
- **FR-015**: An assertion with `issued_at` 6 minutes old is rejected. An `actor_email` that does not equal the Access email is rejected. (04 §1.5; E2E-P3.1-04)
- **FR-016**: `revokeOperatorCredential`, the class HP method this unit calls for the Access JWT check, with a missing, expired, or wrong-`aud` Access JWT is `rejected` with code `unauthenticated` and writes nothing. `receipt` is absent. Nothing is written, including no `control_audit` row. The same refusal applies to every class H or HP call (02 §3.3). This unit implements no class H method. (02 §3.3; 04 §1.3; E2E-P3.1-05) [TB-6, AD-11]
- **FR-017**: Any method with `contract_version` missing or 2 returns `rejected` with code `contract_version_unsupported`, and nothing is written. The refusal happens before authentication and before any write. The `ok` result of `revokeOperatorCredential` and of `listOperatorCredentials` carries `contract_version`. At launch the channel version is 1. (04 §1.1; 06 §3 V5; E2E-P3.1-03; E2E-P3.1-06; E2E-P3.1-10)
- **FR-018**: Credential A revokes B. An HP call that uses B then fails. AL-13 is sent. B fails because a credential used for class HP must be `active`. (04 §1.3; 04 §1.5; 06 §4 P3.1; E2E-P3.1-07) [K-7 rotation]
- **FR-019**: `platform_alert` has the same shape as the ABO's `alert`. Alerts are sent through `send_email`, deduplicated and retried from the alert table. The destination is fixed in configuration: a `send_email` binding with the verified destination. Alert bodies carry codes and ids only. Credential alerts also carry the decoded operation. (02 §5; 03 §3.2; 04 §6.4; 06 §4 P3.1)
- **FR-020**: When `send_email` throws, the alert stays unsent. The next `*/5` run sends it exactly once. (02 §5; 06 §4 P3.1; E2E-P3.1-08) [FM-16]
- **FR-021**: The platform's 5-minute cron pings the heartbeat URL. The `*/5` cron branch pings that URL, and a failing job inside that run raises a platform alert. The ping is the captured outbound fetch to the configured URL. (02 §5; 06 §4 P3.1; E2E-P3.1-09)
- **FR-022**: AL-13 is raised for credential bootstrap, register, and revoke. Bootstrap is marked bootstrap. Revoke sends AL-13. (06 §4 P3.1; E2E-P3.1-01; E2E-P3.1-07)
- **FR-023**: `[observability] enabled = true`. JSON log lines are emitted. A failing scheduled job raises a platform alert. (04 §6.4; 06 §4 P3.1; E2E-P3.1-09)
- **FR-024**: wrangler configuration adds `ACCESS_TEAM_DOMAIN`, `ACCESS_AUD`, `WEBAUTHN_RP_ID`, and `WEBAUTHN_ORIGIN`, and a `send_email` binding with the verified destination. (04 §6.4)
- **FR-025**: H-AP has a self service binding to `VendorEntrypoint` and `vendorCall(method, args, {accessJwt, assertion})`, built on the P2.2 testkit, next to `operatorFetch`, plus email capture, heartbeat capture, and an Access certs fixture. `send_email` is asserted by capturing what is handed to the binding. Heartbeat pings are asserted by capturing the outbound fetch to the configured URL. (06 §3 V2; 06 §3 V6; 06 §4 P3.1)

### 3.2 Key Entities

- **Class table**: One class, M, H, or HP, for each `VendorEntrypoint` method. Class M is the service binding, plus an ABO signature where the method changes coverage. Class H is the forwarded Access JWT. Class HP is class H plus the 04 §1.5 assertion. (02 §3.3; 04 §1.3)
- **Result envelope**: `{contract_version, result, code, detail, receipt?}`. `detail` is a string. The object has no other key. `receipt` is present when `result` is `applied` or `already_applied`, and absent otherwise. A successful `registerOperatorCredential`, `revokeOperatorCredential`, or `listOperatorCredentials` is `ok`, and its payload is JSON text in `detail`. `result` is `ok`, `applied`, `already_applied`, `conflict`, `rejected`, or `transient`, with the meanings in FR-003. (04 §1.2)
- **Receipt**: `{contract_version, grant_id or reversal_id, installation_id, org_id, result, term_ids, applied_at, ledger_seq, envelope_sha256, kid, signature}`. The signature is by the platform key (02 K-3) over the canonical receipt without the signature. Both sides store it (SR-05). This object records a grant or a reversal. `registerOperatorCredential`, `revokeOperatorCredential`, and `listOperatorCredentials` return `ok` and do not include it (04 §1.2, §1.6). (04 §1.6)
- **`operator_credential`**: `credential_id`, `operator_email`, `public_key_cose`, `alg`, `status` (`pending`, `active`, `revoked`), `activates_at`, `approved_by`, `revoked_by`. (03 §3.2)
- **`assertion_used`**: `challenge_sha256`, `credential_id`, `used_at`. Single-use guard, swept after a day. (03 §3.2)
- **`control_audit`**: `actor` becomes the Access email; the row adds `assertion_sha256`. (03 §3.2)
- **`platform_alert`**: Same shape as the ABO's `alert`. (03 §3.2)

## 4. Constitution Alignment

### 4.1 Architecture & Operations Impact

- **Clinic Fit**: The platform entrypoint, operator-credential registry, and out-of-band alert path are the vendor-side control surface for clinic AI coverage. The codebase cell is ai-platform. The row names no wiring exception (rule S3).
- **Layer Placement**: Implementation stays in `ai-platform`. Live entries are `VendorEntrypoint` methods over the H-AP self service binding and `scheduled()` for the `*/5` cron. `plan.md` re-runs the constitution check in 02 §7 (rule S12).
- **Data Integrity & Security**: New D1 tables are `operator_credential`, `assertion_used`, and `platform_alert`. `control_audit.actor` becomes the Access email and the row gains `assertion_sha256`. Class H and class HP are verified by the platform. `contract_version` is checked on every argument object before authentication and before any write. Alert bodies carry codes and ids, plus the decoded operation on credential alerts. (02 §3.3; 02 §5; 03 §3.2; 04 §1.1; 04 §1.5)
- **Failure Handling**: A missing, expired, or wrong-`aud` Access JWT rejects `revokeOperatorCredential` with code `unauthenticated` and no state change (E2E-P3.1-05). `contract_version` missing or 2 rejects with `contract_version_unsupported` and writes nothing (E2E-P3.1-06). A credential younger than 24 hours, an assertion older than 5 minutes, an `actor_email` mismatch, a replayed assertion (`assertion_used`), and a revoked credential reject the HP call (E2E-P3.1-02, E2E-P3.1-03, E2E-P3.1-04, E2E-P3.1-07). When `send_email` throws, the alert stays unsent and the next `*/5` run sends it once (E2E-P3.1-08). A failing job inside that cron raises a platform alert (E2E-P3.1-09).

## 5. Out of Scope

issuer keys (→ P3.2), service keys and grants (→ P3.3), porting `/control/*` methods and removing them (→ P3.10), console ceremony (→ P4.7). Class H methods named in 02 §3.3 and 04 §1.3 (`suspend`, `resume`, `inspectCoverage`, `supportLookup`, `listGrantsForVoid`, kill switch, routing policy, cohort, capability lifecycle, token contract) stay with later units (P3.6, P3.7, P3.10). This unit does not implement them.

- No material from the Do not read sections: coverage methods in 04 §1.3; 03 §6.
- No rewrite of a Consumes contract: the message types of 04 §1.2–§1.7 and §2.1; the verification APIs; the testkit API (used by every later harness). CP-A. (rule S7)
- No module that no test-plan row reaches (rule S8).
- No removal of a transitional path a later unit owns (rule S9): enrollment, removed in P3.2; `/control/entitle`, which keeps test clinics admitted until P3.4; entitlement, plan, and invoice tables and all `/control/*` routes, removed in P3.10.
- No second codebase beyond ai-platform.

## 6. Success Criteria

### 6.1 Measurable Outcomes

- **SC-001**: E2E-P3.1-01, E2E-P3.1-02, E2E-P3.1-03, E2E-P3.1-04, E2E-P3.1-05, E2E-P3.1-06, E2E-P3.1-07, E2E-P3.1-08, E2E-P3.1-09, and E2E-P3.1-10 pass in harness H-AP.
- **SC-002**: Every earlier suite stays green (rule S2).

## 7. Assumptions

- OQ-5 default: accepted as described in rule V4. Local platform E2E uses a test-only clock control, absent from production and staging configs and asserted by a config test. No local scenario sleeps more than 2 s of real time.
- Rule S9: enrollment remains until P3.2; `/control/entitle` remains until P3.4; entitlement, plan, and invoice tables and `/control/*` routes remain until P3.10.
