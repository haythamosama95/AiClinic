# Feature Specification: Launch readiness checks

**Feature Branch**: `ai/098-abo-p8-3-launch-readiness-checks`

**Created**: 2026-10-08

**Status**: Draft

**Input**: P8.3 — Launch readiness checks

## 1. Unit Contract

**Implements** — Read: 05 §6.2; 05 §10; 02 §6.

- a read-only `launch-check` against a target environment (no `/control` routes; `workers_dev`/previews off; every channel on version 1 and the backend copy matching; AL-23 clear; ≥ 2 active operator credentials; issuer and service keys registered and pinned; no terms or grants in platform D1; heartbeat and watcher live); runbooks for pre-launch installation deletion, the FR-92 pilot grant, bootstrap ceremony, rotations (02 §6), compromise response, rebuilds (05 §5); a checklist of the operational items in section 5, D3 with owners.

**Freezes** — None. The unit row states no Outputs / freezes line.

**Consumes** — P8.2: None. That unit row states no Outputs / freezes line.

**Open questions relied on** — None. The Read line and the Implements line name no §6 open question.

**Spikes** — None. Rule S6 names no spike for P8.3.

## Clarifications

### Session 2026-10-08

- Q: Where do `launch-check`, the runbooks, and the checklist live? → A: One directory in the ops-scripts codebase, not under `e2e/fullstack/`: the `launch-check` executable, one markdown runbook for each procedure (pre-launch installation deletion, the FR-92 pilot grant, the bootstrap ceremony, rotations, compromise response, rebuilds), and one checklist markdown file. The plan records that directory path. `[implementation choice — no §citation]`
- Q: How does `launch-check` report all-green versus a failed condition? → A: Exit 0 with no failed-condition lines when every FR-001 condition holds. Otherwise exit non-zero and print one line per failed condition, using that condition's existing wording. No new condition codes or report schema. `[implementation choice — no §citation]`
- Q: How does the single E2E-P8.3-02 scenario cover both bad states? → A: That one H-STG test runs the same read-only `launch-check` against each bad state named in the scenario (`workers_dev` re-enabled, and a single active operator credential). Each run must fail and name that condition. The check does not create the bad state. `[implementation choice — no §citation]`

## 2. User Scenarios & Testing

### 2.1 User Story 1 - Launch readiness check, runbooks, and checklist (Priority: P1)

An operator runs the read-only `launch-check` against a target environment. On staging configured production-like, the check is all green when the launch conditions in that check hold. The same operator keeps the launch runbooks (pre-launch installation deletion, the FR-92 pilot grant, the bootstrap ceremony, rotations, compromise response, and rebuilds) and the section 5 D3 checklist. Each checklist item has owner developer. The 05 §6.2 lines are conditions on the production state. The check evaluates a target environment. The runbooks are what the operator follows at launch.

**Why this priority**: This is the only story. Both E2E scenarios and the 05 §6.2 launch conditions sit here. P8.2 is already consumed as the prior unit.

**Independent Test**: E2E-P8.3-01 and E2E-P8.3-02, by running `launch-check`.

**Acceptance Scenarios**:

1. **Given** staging configured production-like, **When** the operator runs `launch-check` against it, **Then** the check is all green.
2. **Given** staging with `workers_dev` re-enabled, or a single operator credential, **When** the operator runs `launch-check`, **Then** the check fails and names the condition.

Earlier suites stay green (rule S2).

### 2.2 Test plan

The scenario title starts with the E2E id (rule V3). Both rows run the read-only `launch-check` ops script. The staging target is the H-STG environment (rule V1). This unit adds the script under ops scripts. It does not add a runner under `e2e/fullstack/`.

| ID | Harness | Entry point | Assertion (+ tags) | Proves | Story |
| --- | --- | --- | --- | --- | --- |
| E2E-P8.3-01 | H-STG | Read-only `launch-check` ops script against staging | Staging configured production-like → all green. Green means every condition in FR-001 holds | FR-001, FR-002 | User Story 1 |
| E2E-P8.3-02 | H-STG | Read-only `launch-check` ops script against staging | Staging with `workers_dev` re-enabled, or a single operator credential → the check fails and names the condition | FR-001, FR-003 | User Story 1 |

### 2.3 Edge Cases

- Staging with `workers_dev` re-enabled: `launch-check` fails and names that condition. (E2E-P8.3-02, Implements)
- Staging with a single operator credential: `launch-check` fails and names that condition. (E2E-P8.3-02, Implements, 05 §6.2)
- `launch-check` is read-only. The 05 §6.2 lines are conditions on the production state. Deletion, the pilot grant, bootstrap, rotation, compromise response, and rebuild stay in the runbooks. (Implements, 05 §6.2)
- A26 stays Partial. The checklist records the 02 §4.4 operating policy. The audit watcher (P8.1) detects breaches. (section 5 D3, 05 §10 SR-21, A26)
- A compromised credential is revoked in minutes by the 02 §6 emergency procedure in the compromise-response runbook. (02 §6, SR-11)

## 3. Requirements

### 3.1 Functional Requirements

- **FR-001**: `launch-check` MUST be read-only against a target environment. All green MUST mean every condition below holds (Implements, 05 §6.2):
  - No `/control/*` route, `OPERATOR_BEARER_TOKEN`, `set_ai_availability`, or manual entitle path exists (FR-91).
  - `workers_dev` and preview URLs are off.
  - Every channel runs contract version 1 on both sides, and the backend's `ai.contract_versions` matches the shared package (04 §7).
  - AL-23 is clear. The ABO's key self-check passes.
  - At least two operator credentials are active.
  - The issuer and service keys are registered. The issuer keys are pinned in the ABO's `ISSUER_KEYS`. The platform signing key is set.
  - Platform D1 holds no terms or grants.
  - The audit watcher and the heartbeat monitor are live.
- **FR-002**: E2E-P8.3-01 MUST run `launch-check` against staging configured production-like and MUST be all green. (Implements)
- **FR-003**: E2E-P8.3-02 MUST run `launch-check` against staging with `workers_dev` re-enabled, or with a single operator credential. The check MUST fail and MUST name the condition. (Implements)
- **FR-004**: The deletion runbook MUST state that pre-launch installations are deleted and that their ledgers stay, per RC-05. (05 §6.2, Implements)
- **FR-005**: The pilot-grant runbook MUST state that a pilot clinic that keeps AI gets an HP complimentary grant of 30 days (unit `day`) with reason "pre-launch pilot"; this fits the ceilings (03 §3.2), and the clinic then buys like everyone else (FR-92). (05 §6.2, Implements)
- **FR-006**: The bootstrap-ceremony runbook MUST state that the first operator credential is bootstrapped and a second one is registered (24-hour delay). (05 §6.2, Implements)
- **FR-007**: The rotation runbook MUST state the 02 §6 routine rotation for each credential. Every credential rotates without an outage (02 §6):
  - Issuer key (K-2): Generate the next `kid` as `ai_internal.issuer_key.status` `next` (03 §4); add its public key to the ABO's pinned `ISSUER_KEYS` (config deploy) and register it on the platform (HP); `auth_internal.switch_issuer_signing_kid(p_kid)` once both accept it (that row becomes `signing`, the previous `signing` row becomes `retired`); after 10 minutes (the longest token life) `retireIssuerKey` (HP) sets the old `kid` to `retiring`, and that `kid` stays accepted until `not_after`.
  - Platform key (K-3): Add the next `kid` to the ABO's configuration first; then switch signing. The receipt `signature` is the compact JWS in 04 §1.6, and that receipt's `ledger_seq` is the `clinic_seq` of the `grant_applied` or `grant_voided` event, not a `grant_ledger` column.
  - ABO grant key (K-4): Register the next public key on the platform (`registerServiceKey`); switch the secret; revoke the old one (`revokeServiceKey` sets `status` `revoked`). There is no `retiring` status. Each attempt signs with the current key, so pending grants need no rework (03 §2.8). The ABO checks at isolate start, and hourly, that its signing `kid` is `active` and not expired (`listServiceKeys`, 04 §1.3); if not, it pauses `grant` and `reverse` work and raises AL-23 instead of sending envelopes that can only answer `transient`.
  - Paymob HMAC (K-5): Rotate in the dashboard, then update the secret; callbacks fail verification in between, and inquiry sweeps recover the payments (A23 path).
  - Paymob keys (K-6): Rotate in the dashboard, then update the secrets.
  - Operator passkey (K-7): Add a new credential (approved by an existing one, active after 24 hours); revoke the old.
  - Access (K-8): Session length 1 hour.
  - Audit-watcher token (K-10): 90 days.
- **FR-008**: The compromise-response runbook MUST state that a compromised credential is revoked in minutes (SR-11), using the 02 §6 emergency revocation for that credential:
  - Issuer key (K-2): `revokeIssuerKey` (HP) sets the `kid` to `revoked`, rejected there within one config-cache TTL (≤ 30 s); remove it from the ABO's pins by config deploy (minutes). Alert 30 days before `not_after` (A25).
  - Platform key (K-3): Same sequence as routine rotation, done at once; the old `kid` is removed from the ABO's configuration.
  - ABO grant key (K-4): Revoke on the platform (HP): envelopes under the revoked `kid` are `rejected`. Deploy the new secret; parked rows are retried, re-signed with the new key. An unknown `kid` answers `transient`, so grants retry until a new key's registration is visible (04 §1.4).
  - Paymob HMAC (K-5): Same as routine rotation.
  - Paymob keys (K-6): Same as routine rotation; pending work retries.
  - Operator passkey (K-7): Any active credential revokes another at once; list and void grants by credential and window.
  - Access (K-8): Revoke sessions in Access.
  - Audit-watcher token (K-10): Revoke in Cloudflare.
- **FR-009**: The rebuild runbooks MUST state the 05 §5 procedures. Each ends with a clean reconciliation run (05 §5, Implements):
  - ABO (05 §5.1): Within 30 days of the damage, restore D1 with Time Travel to a point before it. Otherwise, create an empty D1, replay the `ledger/` NDJSON facts in `fact_seq` order (inserts pass the append-only triggers), then recompute the status tables. Fill the gap after the last exported fact: re-inquire every checkout and payment reference known to the rebuilt set, and every transaction in the provider's dashboard export for the gap window. Compare with the platform's `listGrants`. A paid grant with no payment is re-derived from the provider inquiry; a payment with no grant gets a grant row (its `grant_id` is deterministic, so the platform answers `already_applied`).
  - A clinic's DO (05 §5.2): Load the clinic's last `coverage_event` snapshot (its terms, positions, usage, holds, suspension and epoch) into an empty DO. Apply, in order, every later `grant_ledger` and `grant_void` row and every later hold, release, suspension and transfer event. Re-apply usage recorded after the snapshot from `usage_event` by `term_id`, including shipped `usage_adjustment` rows; `request_id` uniqueness prevents double counting. Retention keeps these rows while their term is unended (03 §8). Compare the result with `coverage_mirror` and alert on any difference. Reservations in flight at the loss are forfeited to the clinic's benefit.
  - Platform D1 (05 §5.3): Restore with Time Travel within 30 days. Otherwise rebuild `grant_ledger` and `grant_void` from the R2 `grant-ledger/` objects. Then ask every DO for a fresh snapshot event (an H method run once per installation), which also rebuilds `coverage_mirror`.
  - Backend projection (05 §5.4): Reset `feed_state.cursor` to 0. `coverage_event` is never purged, so the replay reproduces every clinic's latest snapshot.
- **FR-010**: The checklist MUST list the section 5 D3 operational items, each with owner developer (Implements, section 5 D3):
  - RC-06 legal confirmation of the no-refund policy, and R-9 advice on payer contact data and erasure timing (01 §7). These are launch conditions (05 §6.2). The tenancy retrofit (01 R-1) is live, and RC-06 legal confirmation is recorded (01 R-9). R-9 advice on payer contact data is recorded, and the erasure action (§3.2) has been run once in staging.
  - 02 §4.4 operating policy: production deploys and secret changes only from an interactive session with hardware-key MFA; no stored token with production rights. This checklist is the P8.3 check. The audit watcher (P8.1) detects breaches. A26 stays Partial. D1 assigns TB-10 to P8.1/P8.3; this item is the operating-policy side (05 §10 SR-21, A26; 05 §6.2; section 5 D1, D3).
  - IdP hardware-key MFA and 1-hour Access sessions (TB-7, K-8): Access configuration is in P8.1, verified by this checklist.
  - Production key generation and registration, bootstrap and second credential, pilot grant (FR-92), and deletion of pre-launch installations: the P8.3 runbooks, run at launch.
  - Paymob dashboard settings (callback URLs, integration ids) and HMAC/API key rotation in the dashboard: P8.1/P8.3 runbooks. HMAC and API key rotation follow FR-007 and FR-008 (K-5, K-6).
  - NFR-08 plan-allowance confirmation (05 §7) and D1 Time Travel (a built-in feature): recorded in P8.1.
  - FR-80 monthly payout CSV import: a routine operator action (05 §10), supported by P4.10.

### 3.2 Key Entities

Not applicable — this unit defines no entities.

## 4. Constitution Alignment

### 4.1 Architecture & Operations Impact

- **Codebase**: ops scripts + runbooks. That is the codebase cell the unit row names (rule S3). No wiring exception is named. `plan.md` re-runs the constitution check in 02 §7 (rule S12).
- **Clinic Fit**: One operator confirms launch conditions for a small-to-mid-size multi-branch clinic. The check, the runbooks, and the checklist add no clinic workflow and no second architecture. (constitution I, 05 §6.2)
- **Layer Placement**: `launch-check` is an ops script. The runbooks and the checklist are documents. This unit adds no Flutter screen, no Supabase schema, and no Worker write path. (Implements, constitution II)
- **Data Integrity & Security**: The check is read-only. It evaluates `/control` absence, `workers_dev` and previews, contract version 1, AL-23, active operator credentials, pinned issuer and service keys, an empty platform grant state, and live heartbeat and watcher. The checklist records the 02 §4.4 policy and the D3 items. (Implements, 05 §6.2, section 5 D3, constitution III, IV)
- **Failure Handling**: When `workers_dev` is re-enabled, or only one operator credential is active, `launch-check` fails and names the condition. Compromise response and rebuild stay in the runbooks. (E2E-P8.3-02, 02 §6, 05 §5)

## 5. Out of Scope

- The unit row states no Out of scope line.
- No Do-not-read material. The unit row names none.
- No rewrite of consumed contracts. P8.2 states no Outputs / freezes line.
- No module that no test-plan row reaches (rule S8). The P2.2 and package-half P2.1 exception does not apply. `launch-check` is the module both E2E rows run. The runbooks and the checklist are the documents the Implements line names.
- No S9 transitional path is named on this unit row. No later unit owns an S9 path this unit would take.
- No codebase beyond ops scripts + runbooks. This unit does not add a runner under `e2e/fullstack/`.

## 6. Success Criteria

### 6.1 Measurable Outcomes

- **SC-001**: E2E-P8.3-01 is green in H-STG.
- **SC-002**: E2E-P8.3-02 is green in H-STG.
- **SC-003**: Every earlier suite stays green (rule S2).

## 7. Assumptions

- None. The Read line and the Implements line name no §6 default. The unit row names no S9 transitional path.
