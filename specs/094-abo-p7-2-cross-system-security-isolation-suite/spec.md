# Feature Specification: Cross-system security and isolation suite

**Feature Branch**: `ai/094-abo-p7-2-cross-system-security-isolation-suite`

**Created**: 2026-10-08

**Status**: Draft

**Input**: P7.2 — Cross-system security and isolation suite

## 1. Unit Contract

**Implements** — Read: 02 §2; 02 §4.2; 02 §4.3; 05 §8 rows A22, A26, A27, A35, A36.

- Untrusted clinic and payment callers, one story: junk `/notify` and `/return` (E2E-P7.2-01); staff cannot mint a billing token, `/v1/coverage` is 403, and no RPC writes status (E2E-P7.2-02); org A's administrator replays B's ids on every ABO route, every RPC, and the platform routes (E2E-P7.2-03); a forged callback with a leaked HMAC secret does not confirm and creates no payment (E2E-P7.2-04).
- `VendorEntrypoint` paid grant and class H/HP, one story: a simulated compromised ABO, a paid grant beyond the plan bound rejected and one within the bound applied with AL-11, AL-17, and `grant_without_payment`, HP without an assertion rejected, and a substituted operation shown in the AL-11 body (E2E-P7.2-05); Access JWT alone allows H and rejects HP, and passkey plus session still enforces ceilings (E2E-P7.2-06); a stored CI/staging token cannot reach any HP method (E2E-P7.2-09).
- Credential isolation, one story: neither Worker's config holds a Supabase credential, and billing, AI, and feed tokens are rejected by PostgREST (E2E-P7.2-07); the Supabase session JWT never leaves for the ABO or platform (E2E-P7.2-08).

**Freezes** — None. The unit row states no Outputs / freezes line.

**Consumes** — P6.4: None. The unit row states no Outputs / freezes line. P4.11: None. The unit row states no Outputs / freezes line.

**Open questions relied on** — None.

**Spikes** — None.

## Clarifications

### Session 2026-10-08

- Q: Where do the nine H-FS scenarios live? → A: Three Node test files under `e2e/fullstack/`, one per user story. Each E2E id is one test whose title starts with that id. `[implementation choice — no §citation]`
- Q: How does the H-FS runner reach `VendorEntrypoint` for the compromised ABO, class H, and class HP scenarios? → A: A test-only worker in `e2e/fullstack` binds the real platform `VendorEntrypoint` and is called only by the Node runner. Paid grants are signed with the ABO grant key that the H-FS platform already trusts. Class H and class HP use the existing testkit Access JWT and WebAuthn assertion (rule V2 `vendorCall` shape) through that binding. The CI/staging case sends a fixture token and no assertion. No new platform or ABO route. `[implementation choice — no §citation]`
- Q: How does the Dart network capture run in this unit's codebase? → A: A Dart driver under `e2e/fullstack` invokes `DiscoveryClient`, `HttpsSubmitPort`, `usage_summary_client`, and `AboClient` and records outbound URL and Authorization headers. The story-3 Node test starts that driver against H-FS. No new file under `frontend/test/`. `[implementation choice — no §citation]`

## 2. User Scenarios & Testing

### 2.1 User Story 1 - Untrusted clinic and payment callers (Priority: P1)

An internet caller can post to `/notify` and open `/return`, and cannot create service. Clinic staff can use covered AI and cannot mint a billing token, call `/v1/coverage`, or write status. Org A's administrator can buy for A only. A forged callback with a leaked HMAC secret triggers an inquiry and does not create a payment.

**Why this priority**: This is the outsider and wrong-clinic boundary (AD-1, AD-2, AD-3/A36, AD-5). User Story 2 and User Story 3 run on the same full stack after this boundary.

**Independent Test**: E2E-P7.2-01, E2E-P7.2-02, E2E-P7.2-03, and E2E-P7.2-04 in harness H-FS.

**Acceptance Scenarios**:

1. **Given** an internet caller, **When** junk is posted to `/notify`, **Then** the request is rate-limited and nothing is stored. **When** the caller opens `/return`, **Then** that call cannot create service. (E2E-P7.2-01, AD-1, SR-01, TB-1)
2. **Given** a clinic staff user, **When** the user tries to mint a billing token, **Then** the user cannot obtain one. **When** the user calls `/v1/coverage`, **Then** the platform answers 403. **When** the user calls an RPC, **Then** no RPC writes status. (E2E-P7.2-02, AD-2, SR-07, TB-3, TB-4)
3. **Given** org A's administrator and org B's ids, **When** A replays those ids on every ABO route, every RPC, and the platform routes, **Then** the answer is not found and B is unchanged. No token can be obtained for another tenant. Nothing is locked by an open checkout. The ABO and RPCs take the tenant only from the session. (E2E-P7.2-03, AD-3, A22, A36, TB-2, TB-4)
4. **Given** a leaked HMAC secret, **When** the caller forges a callback, **Then** the inquiry does not confirm and no payment is created. (E2E-P7.2-04, AD-5, TB-1, TB-8)

### 2.2 User Story 2 - VendorEntrypoint paid grant and class H/HP (Priority: P2)

A simulated compromised ABO can ask the platform for a paid grant only inside the plan bound, and that grant is visible. Class H actions work from an Access JWT alone. Class HP actions need the operator's passkey. A stored CI/staging token cannot reach any HP method.

**Why this priority**: User Story 1 covers clinic and payment callers. This story is the operator and compromised-ABO path on `VendorEntrypoint` (AD-8, AD-11, AD-12, A27, A26 code half).

**Independent Test**: E2E-P7.2-05, E2E-P7.2-06, and E2E-P7.2-09 in harness H-FS.

**Acceptance Scenarios**:

1. **Given** a simulated compromised ABO, **When** it submits a paid grant beyond the plan bound, **Then** the grant is rejected. **When** it submits a paid grant within the bound, **Then** the grant applies and raises AL-11, AL-17, and `grant_without_payment`. **When** it calls an HP method without an assertion, **Then** the call is rejected. **When** the operator is shown one operation and the passkey signs another, **Then** the AL-11 body shows the real operation. (E2E-P7.2-05, AD-8)
2. **Given** an Access JWT and no passkey, **When** the caller performs class H actions, **Then** those actions work, and class HP actions are rejected. **Given** a passkey and a session, **When** the caller asks for a grant, **Then** ceilings are still enforced, and the 31-day ceiling blocks a year. (E2E-P7.2-06, AD-11, AD-12, A27)
3. **Given** a stored CI/staging token and no passkey, **When** the token is used against any HP method, **Then** it cannot reach that method. (E2E-P7.2-09, A26)

### 2.3 User Story 3 - Credential isolation (Priority: P3)

Neither Worker config holds a Supabase credential. Billing, AI, and feed tokens are not PostgREST credentials. The Supabase session JWT never leaves the desktop for the ABO or the platform.

**Why this priority**: User Story 1 and User Story 2 cover caller and operator boundaries. This story is credential custody (A35, K-1).

**Independent Test**: E2E-P7.2-07 and E2E-P7.2-08 in harness H-FS. Earlier suites stay green, and E2E-P7.2-01, E2E-P7.2-02, E2E-P7.2-03, E2E-P7.2-04, E2E-P7.2-05, E2E-P7.2-06, and E2E-P7.2-09 still pass.

**Acceptance Scenarios**:

1. **Given** the ABO Worker config and the platform Worker config, **When** they are inspected, **Then** neither holds a Supabase credential. **When** a billing token, an AI token, or a feed token is presented to PostgREST, **Then** PostgREST rejects it. (E2E-P7.2-07, A35)
2. **Given** a desktop session, **When** the desktop calls the ABO or the platform, **Then** a Dart network capture shows that the Supabase session JWT never leaves for those services. (E2E-P7.2-08, K-1)

### 2.4 Test plan

| ID | Harness | Entry point | Assertion (+ tags) | Proves | Story |
| --- | --- | --- | --- | --- | --- |
| E2E-P7.2-01 | H-FS | ABO worker `fetch` (`abo/src/worker.ts`): `POST /notify/paymob` and `GET /return/paymob` on `BILLING_HOST` | AD-1: junk to `/notify` is rate-limited and not stored; `/return` cannot create service [SR-01] | FR-001 | User Story 1 |
| E2E-P7.2-02 | H-FS | PostgREST `public.issue_billing_token` and staff RPCs including `get_ai_status` on local Supabase; platform worker `GET /v1/coverage` (`ai-platform/src/worker.ts`) | AD-2: staff cannot mint a billing token; `/v1/coverage` → 403; no RPC writes status [SR-07] | FR-002 | User Story 1 |
| E2E-P7.2-03 | H-FS | ABO billing-host routes in `handleBillingV1` (`abo/src/worker.ts`: `/v1/offers`, `/v1/subscription`, `/v1/payments`, `/v1/billing-contact`, `/v1/checkouts`, `/v1/checkouts/{id}`); PostgREST RPCs; platform routes `GET /v1/capabilities`, `POST /v1/requests`, `GET /v1/coverage`, `GET /v1/feed/coverage` (`ai-platform/src/worker.ts`) | AD-3/A36: org A's administrator replays B's ids on every ABO route, every RPC and the platform routes → not found; B unchanged | FR-003 | User Story 1 |
| E2E-P7.2-04 | H-FS | ABO worker `POST /notify/paymob` (`abo/src/worker.ts`), then the ABO inquiry of that callback against the H-FS Paymob stub | AD-5: forged callback with a leaked HMAC secret → the inquiry does not confirm → no payment | FR-004 | User Story 1 |
| E2E-P7.2-05 | H-FS | `VendorEntrypoint.grant` and class HP methods on the platform worker (`ai-platform/src/vendor/entrypoint.ts`). AL-11 and AL-17 are captured from `send_email` (rule V6). `grant_without_payment` is the raised finding | AD-8: simulated compromised ABO → a paid grant beyond the plan bound is rejected; one within the bound applies but raises AL-11, AL-17 and `grant_without_payment`; HP without an assertion is rejected; a substituted operation shows its real content in the AL-11 body | FR-005 | User Story 2 |
| E2E-P7.2-06 | H-FS | Class H: `VendorEntrypoint.suspend`, `VendorEntrypoint.resume`, and `VendorEntrypoint.armKillSwitch` (`ai-platform/src/vendor/entrypoint.ts`) with `Cf-Access-Jwt-Assertion`; ABO `POST /ops/checkouts/{id}/cancel` and `POST /ops/parked/{id}/retry` (`abo/src/ops/index.ts`). Class HP on `VendorEntrypoint` (`grant` for a complimentary grant, `setCeilingPolicy`, `beginTransfer`, `releaseHeld`, `voidGrant`) | AD-11: Access JWT alone → H actions work, HP rejected. AD-12: passkey + session → ceilings still enforced [A27] | FR-006 | User Story 2 |
| E2E-P7.2-07 | H-FS | Worker configs loaded for the ABO and platform (`abo/wrangler.toml`, `ai-platform/wrangler.toml`); PostgREST on local Supabase presented with a billing token, an AI token, and a feed token | A35: neither Worker's config holds a Supabase credential; billing, AI and feed tokens are rejected by PostgREST | FR-008 | User Story 3 |
| E2E-P7.2-08 | H-FS | Desktop calls from `DiscoveryClient` (`frontend/lib/core/ai/discovery_client.dart`), `HttpsSubmitPort` (`frontend/lib/core/ai/https_submit_port.dart`), `usage_summary_client` (`frontend/lib/core/ai/usage_summary_client.dart`), and `AboClient` (`frontend/lib/features/ai/billing/abo_client.dart`), captured on the H-FS run | K-1: the Supabase session JWT never leaves for the ABO or platform (Dart network capture) | FR-009 | User Story 3 |
| E2E-P7.2-09 | H-FS | Class HP methods on `VendorEntrypoint` (`ai-platform/src/vendor/entrypoint.ts`) called with a stored CI/staging token and no passkey | A26 code half: a stored CI/staging token cannot reach any HP method (no passkey); the rest is P8.3 policy | FR-007 | User Story 2 |

### 2.5 Edge Cases

- On `POST /notify/{provider}` the body cap is 1_048_576 bytes and the limit is 60 requests per 60 seconds keyed by `CF-Connecting-IP` (a missing header uses the key `unknown`). A body over the cap answers HTTP 413. The request that exceeds the limit answers HTTP 429. Both answers are an empty body and leave nothing stored or enqueued. HMAC-valid bodies are stored as evidence. Nothing is granted without the authenticated inquiry. `/return` only schedules an inquiry and cannot create or extend service. (E2E-P7.2-01, E2E-P7.2-04, TB-1, AD-1, AD-5, SR-01)
- Clinic staff cannot obtain a billing token, cannot call `/v1/coverage` (403), and cannot set the flag or status. `/v1/coverage` requires `role = administrator`. There is no write RPC for status. (E2E-P7.2-02, AD-2, TB-3, TB-4, SR-07)
- Foreign ids answer `not_found`. Org B is unchanged. No token can be obtained for another tenant. Nothing is locked by an open checkout. `org` comes from the session only. The ABO and RPCs take the tenant only from the session. (E2E-P7.2-03, AD-3, A22, A36, TB-2, TB-4)
- A forged callback triggers an inquiry and does not create a payment fact. The inquiry is the proof. Inquiry answers are matched to the checkout's stored order id, amount, and currency. (E2E-P7.2-04, AD-5, TB-8, 02 §4.3)
- A paid grant beyond the plan version's term units and allowance maximum is rejected. One within that bound applies. Platform plan bounds cap what a valid signature can buy. An HP call without an assertion is rejected. The AL-11 body carries the decoded operation, so a substituted operation shows its real content. (E2E-P7.2-05, AD-8, 02 §4.3)
- An Access JWT alone can suspend, use the kill switch, cancel a checkout, and retry work. It cannot perform a class HP action. With a passkey and a session, complimentary grants stay within ceilings (≤ 31 days, ≤ 62 days per clinic per 90 days). The 31-day ceiling blocks a year. (E2E-P7.2-06, AD-11, AD-12, A27, TB-6, TB-7)
- A stored CI/staging token has no passkey and cannot reach any HP method. (E2E-P7.2-09, A26)
- Neither service holds a database credential or a Supabase JWT. Tokens carry no PostgREST role, so billing, AI, and feed tokens are rejected by PostgREST. (E2E-P7.2-07, A35, 02 §4.3)
- The Supabase session JWT never leaves for the ABO or the platform. The ABO and the platform never receive a Supabase JWT. (E2E-P7.2-08, K-1, 02 §4.3)

## 3. Requirements

### 3.1 Functional Requirements

- **FR-001**: Junk posted to `/notify` MUST be rate-limited and MUST NOT be stored. On `POST /notify/{provider}` the cap is 1_048_576 bytes and the limit is 60 requests per 60 seconds keyed by `CF-Connecting-IP` (a missing header uses the key `unknown`). A body over the cap answers HTTP 413. The request that exceeds the limit answers HTTP 429. Both answers are an empty body and leave nothing stored or enqueued. HMAC is checked in constant time. HMAC-valid bodies are stored as evidence. Nothing is granted without the authenticated inquiry. `/return` only schedules an inquiry and MUST NOT create or extend service. (02 §2 TB-1, 02 §4.2 AD-1, 02 §4.3, E2E-P7.2-01, SR-01)
- **FR-002**: A clinic staff user MUST NOT obtain a billing token, MUST receive 403 from `/v1/coverage`, and MUST NOT be able to set the flag or status. `/v1/coverage` requires `role = administrator`. Billing-token checks re-check `role = administrator`. There is no write RPC for status. (02 §2 TB-2, TB-3, TB-4, 02 §4.2 AD-2, E2E-P7.2-02, SR-07)
- **FR-003**: Org A's administrator replaying org B's ids on every ABO route, every RPC, and the platform routes MUST be answered not found, and B MUST be unchanged. The tenant comes only from the session. Every ABO lookup is keyed by `org`. Foreign ids answer `not_found`. No token can be obtained for another tenant. Nothing is locked by an open checkout. The ABO and RPCs take the tenant only from the session and answer `not_found` across tenants. (02 §2 TB-2, TB-4, 02 §4.2 AD-3, 02 §4.3, 05 §8 A22, A36, E2E-P7.2-03)
- **FR-004**: A forged callback made with a leaked HMAC secret MUST NOT confirm through the inquiry and MUST NOT create a payment. The caller can forge callbacks that trigger inquiries. The inquiry is the proof. Inquiry answers are matched to the checkout's stored order id, amount, and currency. (02 §2 TB-1, TB-8, 02 §4.2 AD-5, 02 §4.3, E2E-P7.2-04, SR-01)
- **FR-005**: A simulated compromised ABO MUST have a paid grant beyond the plan version's term units and allowance maximum rejected. A paid grant within that bound MUST apply and MUST raise AL-11, AL-17, and `grant_without_payment`. An HP call without an assertion MUST be rejected. A substituted operation MUST show its real content in the AL-11 body. The platform alert on every grant carries the decoded operation and its target. Platform plan bounds cap what a valid ABO signature can buy. Value-moving methods need a platform-verified WebAuthn assertion. (02 §2 TB-6, 02 §4.2 AD-8, 02 §4.3, E2E-P7.2-05)
- **FR-006**: An Access JWT alone MUST allow class H actions and MUST reject class HP actions. Class H actions named for a hijacked operator session are suspend, kill switch, cancel a checkout, and retry work. A passkey plus a session MUST still enforce ceilings: complimentary grants within ≤ 31 days and ≤ 62 days per clinic per 90 days, and the 31-day ceiling blocks a year. Human methods need a platform-verified Access JWT. The Access JWT is validated in the Worker (issuer, `aud` tag, expiry). (02 §2 TB-6, TB-7, 02 §4.2 AD-11, AD-12, 05 §8 A27, E2E-P7.2-06)
- **FR-007**: A stored CI/staging token MUST NOT reach any HP method, because it has no passkey. This is the code half of A26. The rest of A26 is P8.3 policy. (05 §8 A26, E2E-P7.2-09)
- **FR-008**: Neither Worker's config MUST hold a Supabase credential. Billing, AI, and feed tokens MUST be rejected by PostgREST. Neither service holds any database credential or Supabase JWT. Tokens carry no PostgREST role. (02 §4.3, 05 §8 A35, E2E-P7.2-07)
- **FR-009**: The Supabase session JWT MUST never leave the desktop for the ABO or the platform. A Dart network capture of those calls is the proof. The ABO and the platform never receive a Supabase JWT. (02 §4.3, K-1, E2E-P7.2-08)

### 3.2 Key Entities

Not applicable — this unit defines no entities.

## 4. Constitution Alignment

### 4.1 Architecture & Operations Impact

- **Codebase**: `e2e/fullstack/` (tests; defect fixes only, with no contract change). No wiring exception is named. `plan.md` re-runs the constitution check in 02 §7 (rule S12).
- **Clinic Fit**: One clinic's staff and administrator stay inside that clinic. An internet caller cannot create service by posting to payment URLs. The suite serves small-to-mid-size multi-branch clinics by proving those boundaries on the local full stack.
- **Layer Placement**: The suite runs in harness H-FS (`e2e/fullstack/`). It calls the ABO worker `fetch`, the platform worker `fetch`, `VendorEntrypoint` on the platform worker, PostgREST RPCs, and the existing desktop clients. Defect fixes that the suite exposes do not change a contract.
- **Data Integrity & Security**: The tenant comes from the session. Foreign ids answer `not_found`. Staff cannot mint a billing token or write status. Paid grants stay inside plan bounds. Class HP needs a passkey. Worker configs hold no Supabase credential. The session JWT stays on backend RPCs. (02 §2, 02 §4.2, 02 §4.3, 05 §8)
- **Failure Handling**: Over-cap and over-limit notify calls answer 413 and 429 with an empty body and store nothing. `/v1/coverage` answers 403 for staff. Cross-tenant ids answer not found. A forged callback does not confirm. A paid grant beyond the plan bound is rejected. An HP call without an assertion is rejected. PostgREST rejects billing, AI, and feed tokens. (E2E-P7.2-01, E2E-P7.2-02, E2E-P7.2-03, E2E-P7.2-04, E2E-P7.2-05, E2E-P7.2-07)

## 5. Out of Scope

- The unit row states no Out of scope line.
- No Do-not-read material. The unit row names none.
- No rewrite of consumed contracts. P6.4 and P4.11 state no Outputs / freezes line.
- No module that no test-plan row reaches (rule S8). The P2.2 and package-half P2.1 exception does not apply. Notify and return are reached by E2E-P7.2-01 and E2E-P7.2-04. Staff billing-token mint, `/v1/coverage`, and status RPCs are reached by E2E-P7.2-02. ABO routes, RPCs, and platform routes are reached by E2E-P7.2-03. `VendorEntrypoint.grant`, AL-11, AL-17, and `grant_without_payment` are reached by E2E-P7.2-05. Class H and class HP are reached by E2E-P7.2-06 and E2E-P7.2-09. Worker config and PostgREST token rejection are reached by E2E-P7.2-07. Desktop calls to the ABO and platform are reached by E2E-P7.2-08.
- No S9 path owned by a later unit. This unit names no transitional path. The contract version matrix stays with P7.3. The rest of A26 (stored-token policy and the deploy watcher) stays with P8.3 policy and P8.1 detection.
- No second codebase beyond `e2e/fullstack/`. The suite is tests. A defect fix does not change a contract.

## 6. Success Criteria

### 6.1 Measurable Outcomes

- **SC-001**: E2E-P7.2-01, E2E-P7.2-02, E2E-P7.2-03, E2E-P7.2-04, E2E-P7.2-05, E2E-P7.2-06, E2E-P7.2-07, E2E-P7.2-08, and E2E-P7.2-09 pass in harness H-FS.
- **SC-002**: Every earlier suite stays green (rule S2).

## 7. Assumptions

- This unit relies on no §6 default. Its Read and Implements lines name none.
- Rule S9: this unit names no transitional path.
