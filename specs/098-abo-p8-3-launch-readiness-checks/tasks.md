# Tasks: Launch readiness checks

**Input**: Design documents from `specs/098-abo-p8-3-launch-readiness-checks/`

**Prerequisites**: `plan.md` (required), `spec.md` (required for user stories). Merged units in **Consumes Binding**: P8.2 none. Plan artifacts from `AVAILABLE_DOCS`: none. `research.md` is omitted (Spikes: None). `data-model.md` is omitted (no entities). `contracts/` is omitted (Freezes: None). `quickstart.md` is written in Documentation after this unit's harness passes.

**Organization**: P8.3 is User Story 1 (`[US1]`), size S (rule S3). Branch `ai/098-abo-p8-3-launch-readiness-checks`. E2E ids stay `E2E-P8.3-01` and `E2E-P8.3-02` (rule V3). Tests are one task per Test plan id, both in `ops/launch/launch-check.test.mjs`. Nothing ships before P8 (rule S2). No Setup phase. No Foundational phase. No Polish phase. No task line is marked `[P]`. Scheduling is **Implementation Waves** only.

**Task count**: 15. Size S is 12–20 (rule S3). Plan **Files** is 13 paths, and plan **Sequencing** says that grain is 13 tasks and is not padded to the S minimum. The test file is two tasks because the Test plan has two E2E ids. The verification task edits nothing and is the harness check this phase requires. The other eleven **Files** paths are one implementation task each, and `quickstart.md` is the documentation task. The count is 2 + 11 + 1 + 1. It is not padded. `npm test` in `e2e/fullstack` is not a task. This workflow does not boot wrangler, does not deploy to Cloudflare, Supabase, or Paymob, and does not run `launch-check` against a live staging or production account. A missing live account is expected.

## 1. Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies). No task line is marked `[P]`. Scheduling is **Implementation Waves** only.
- **[Story]**: Which user story this task belongs to (`US1`)
- Include exact file paths in descriptions

## 2. Path Conventions

- **Ops scripts**: `ops/launch/launch-check.mjs`, `ops/launch/launch-check.test.mjs`, six runbooks, `ops/launch/checklist.md`, `ops/launch/fixtures/`
- **Harness H-STG**: `ops/launch/launch-check.test.mjs` (`node:test`). This unit adds no runner under `e2e/fullstack/`
- **Harness command** (this unit only; it does not boot a worker and it does not call a live account):

```bash
node --test ops/launch/launch-check.test.mjs
```

- **Unchanged by this unit**: `ops/staging/`, `e2e/fullstack/`, `abo/`, `ai-platform/`, `backend/`, `frontend/`, `packages/vendor-contracts/`. No secret value committed. No new library, package, binding, or config file
- **Spec Kit artifacts**: `specs/098-abo-p8-3-launch-readiness-checks/`

Failed-condition lines, in FR-001 order. Backticks are part of the line. `launch-check.mjs` prints a line only when that rule fails:

```text
No `/control/*` route, `OPERATOR_BEARER_TOKEN`, `set_ai_availability`, or manual entitle path exists
`workers_dev` and preview URLs are off
Every channel runs contract version 1 on both sides, and the backend's `ai.contract_versions` matches the shared package
AL-23 is clear. The ABO's key self-check passes.
At least two operator credentials are active
The issuer and service keys are registered. The issuer keys are pinned in the ABO's `ISSUER_KEYS`. The platform signing key is set.
Platform D1 holds no terms or grants.
The audit watcher and the heartbeat monitor are live.
```

---

## 3. Tests

**Purpose**: Sequencing step 1. One failing `node:test` per E2E id, both in `ops/launch/launch-check.test.mjs`. Titles start with the E2E id (rule V3). The file fails before `launch-check.mjs` and the three fixtures exist. The tests run that script on the fixture paths. They do not open a live hostname. Do not run `node --test` in this phase. Do not boot wrangler. Do not deploy. Do not call Cloudflare, Supabase, or Paymob. Do not run `npm test` in `e2e/fullstack`. Do not run `launch-check` against a live account.

### 3.1 User Story 1 - Launch readiness check, runbooks, and checklist (Priority: P1) — tests

**Independent Test**: E2E-P8.3-01 and E2E-P8.3-02, by running `launch-check`.

- [ ] T001 [US1] Add the failing test `E2E-P8.3-01` in `ops/launch/launch-check.test.mjs` — red test, FR-001, FR-002, E2E-P8.3-01. Depends on nothing. Title `E2E-P8.3-01` (`node:test`, `node:child_process`). The test runs `node ops/launch/launch-check.mjs ops/launch/fixtures/production-like.json`. It requires exit 0 and none of the eight failed-condition lines from Path Conventions on stdout. The test does not create `ops/launch/launch-check.mjs` or `ops/launch/fixtures/production-like.json`. It does not fetch. It does not write a fixture. Do not run `node --test`. Do not boot wrangler. Do not deploy. Do not call a live account.

- [ ] T002 [US1] Add the failing test `E2E-P8.3-02` in `ops/launch/launch-check.test.mjs` — red test, FR-001, FR-003, E2E-P8.3-02. Depends on T001. One `node:test` whose title is `E2E-P8.3-02`. It runs the same script twice and does not create either bad record. First: `node ops/launch/launch-check.mjs ops/launch/fixtures/workers-dev-enabled.json` exits non-zero and stdout is the `workers_dev` and preview URLs line from Path Conventions and no other failed-condition line. Second: `node ops/launch/launch-check.mjs ops/launch/fixtures/single-operator-credential.json` exits non-zero and stdout is the line `At least two operator credentials are active` and no other failed-condition line. Leave the `E2E-P8.3-01` test in the file. Do not create `launch-check.mjs` or either bad fixture. Do not run `node --test`. Do not boot wrangler. Do not deploy. Do not call a live account.

**Checkpoint**: E2E-P8.3-01 and E2E-P8.3-02 are on disk in `ops/launch/launch-check.test.mjs` and were not executed.

---

## 4. Implementation

**Purpose**: Sequencing step 2. `launch-check.mjs`, the three fixtures, the six runbooks, and `checklist.md`. Each file is the one **Files** names. The script only reads a JSON target. Do not run the harness in this phase. Do not boot wrangler. Do not deploy. Do not call a live account. Do not edit `ops/staging/` or add a file under `e2e/fullstack/`.

### 4.1 User Story 1 - Launch readiness check, runbooks, and checklist (Priority: P1) — launch-check and fixtures

**Independent Test**: E2E-P8.3-01 and E2E-P8.3-02, by running `launch-check`.

- [ ] T003 [US1] Add `ops/launch/launch-check.mjs` — read-only check, FR-001, E2E-P8.3-01, E2E-P8.3-02. Depends on T002. Plain Node `.mjs` using `node:fs/promises`. Read the JSON path given on the command line. Do not fetch. Do not write a store, a fixture, or an environment. Apply the eight FR-001 rules in Path Conventions order and print that rule's failed-condition line on stdout, one line per failed condition. Exit 0 and print no failed-condition line when every rule passes. Otherwise exit non-zero. No condition code and no report schema. Fail when any of `control_route`, `operator_bearer_token`, `set_ai_availability`, `manual_entitle_path` is true (line 1); when `workers_dev` or `preview_urls` is true (line 2); when `channels_version` is not 1 or `backend_contract_versions_match` is not true (line 3); when `al_23_clear` or `key_self_check_passes` is not true (line 4); when `active_operator_credentials` is less than 2 (line 5); when any of `issuer_keys_registered`, `service_keys_registered`, `issuer_keys_pinned`, `platform_signing_key_set` is not true (line 6); when `platform_d1_terms` or `platform_d1_grants` is not 0 (line 7); when `audit_watcher_live` or `heartbeat_monitor_live` is not true (line 8). Do not create the fixtures in this task. Do not run the script against a live account. Do not boot wrangler. Do not deploy.

- [ ] T004 [US1] Add `ops/launch/fixtures/production-like.json` — passing target, FR-002, E2E-P8.3-01. Depends on T003. Every observation passing: `control_route` false, `operator_bearer_token` false, `set_ai_availability` false, `manual_entitle_path` false, `workers_dev` false, `preview_urls` false, `channels_version` 1, `backend_contract_versions_match` true, `al_23_clear` true, `key_self_check_passes` true, `active_operator_credentials` 2, `issuer_keys_registered` true, `service_keys_registered` true, `issuer_keys_pinned` true, `platform_signing_key_set` true, `platform_d1_terms` 0, `platform_d1_grants` 0, `audit_watcher_live` true, `heartbeat_monitor_live` true. The check does not write this file. No secret value. Do not run the script. Do not call a live account.

- [ ] T005 [US1] Add `ops/launch/fixtures/workers-dev-enabled.json` — `workers_dev` true, FR-003, E2E-P8.3-02. Depends on T004. Copy the passing record and set `workers_dev` true. Every other observation stays passing. The check does not write this file. No secret value. Do not run the script. Do not call a live account.

- [ ] T006 [US1] Add `ops/launch/fixtures/single-operator-credential.json` — one active credential, FR-003, E2E-P8.3-02. Depends on T005. Copy the passing record and set `active_operator_credentials` to 1. Every other observation stays passing, including `workers_dev` false. The check does not write this file. No secret value. Do not run the script. Do not call a live account.

**Checkpoint**: E2E-P8.3-01 and E2E-P8.3-02 reach `ops/launch/launch-check.mjs` and the three fixtures. The harness was not executed. No live account was used.

### 4.2 User Story 1 - Launch readiness check, runbooks, and checklist (Priority: P1) — runbooks (part 1)

**Independent Test**: E2E-P8.3-01 and E2E-P8.3-02, by running `launch-check`.

- [ ] T007 [US1] Add `ops/launch/pre-launch-installation-deletion.md` — deletion runbook, FR-004, E2E-P8.3-01, E2E-P8.3-02. Depends on T002. State that pre-launch installations are deleted and that their ledgers stay, per RC-05. The `node:test` file does not read this runbook. Do not delete an installation. Do not call a live account. Do not deploy.

- [ ] T008 [US1] Add `ops/launch/pilot-grant.md` — pilot-grant runbook, FR-005, E2E-P8.3-01, E2E-P8.3-02. Depends on T007. State that a pilot clinic that keeps AI gets an HP complimentary grant of 30 days (unit `day`) with reason "pre-launch pilot"; this fits the ceilings (03 §3.2), and the clinic then buys like everyone else (FR-92). The `node:test` file does not read this runbook. Do not issue a grant. Do not call a live account. Do not deploy.

- [ ] T009 [US1] Add `ops/launch/bootstrap-ceremony.md` — bootstrap runbook, FR-006, E2E-P8.3-01, E2E-P8.3-02. Depends on T008. State that the first operator credential is bootstrapped and a second one is registered (24-hour delay). The `node:test` file does not read this runbook. Do not register a credential. Do not call a live account. Do not deploy.

- [ ] T010 [US1] Add `ops/launch/rotations.md` — rotation runbook, FR-007, E2E-P8.3-01, E2E-P8.3-02. Depends on T009. State the 02 §6 routine rotation for each credential. Every credential rotates without an outage. Issuer key (K-2): generate the next `kid` as `ai_internal.issuer_key.status` `next` (03 §4); add its public key to the ABO's pinned `ISSUER_KEYS` (config deploy) and register it on the platform (HP); `auth_internal.switch_issuer_signing_kid(p_kid)` once both accept it (that row becomes `signing`, the previous `signing` row becomes `retired`); after 10 minutes (the longest token life) `retireIssuerKey` (HP) sets the old `kid` to `retiring`, and that `kid` stays accepted until `not_after`. Platform key (K-3): add the next `kid` to the ABO's configuration first; then switch signing. The receipt `signature` is the compact JWS in 04 §1.6, and that receipt's `ledger_seq` is the `clinic_seq` of the `grant_applied` or `grant_voided` event, not a `grant_ledger` column. ABO grant key (K-4): register the next public key on the platform (`registerServiceKey`); switch the secret; revoke the old one (`revokeServiceKey` sets `status` `revoked`). There is no `retiring` status. Each attempt signs with the current key, so pending grants need no rework (03 §2.8). The ABO checks at isolate start, and hourly, that its signing `kid` is `active` and not expired (`listServiceKeys`, 04 §1.3); if not, it pauses `grant` and `reverse` work and raises AL-23 instead of sending envelopes that can only answer `transient`. Paymob HMAC (K-5): rotate in the dashboard, then update the secret; callbacks fail verification in between, and inquiry sweeps recover the payments (A23 path). Paymob keys (K-6): rotate in the dashboard, then update the secrets. Operator passkey (K-7): add a new credential (approved by an existing one, active after 24 hours); revoke the old. Access (K-8): session length 1 hour. Audit-watcher token (K-10): 90 days. The `node:test` file does not read this runbook. Do not rotate a live secret. Do not commit a secret value. Do not deploy.

- [ ] T011 [US1] Add `ops/launch/compromise-response.md` — compromise-response runbook, FR-008, E2E-P8.3-01, E2E-P8.3-02. Depends on T010. State that a compromised credential is revoked in minutes (SR-11), using the 02 §6 emergency revocation for that credential. Issuer key (K-2): `revokeIssuerKey` (HP) sets the `kid` to `revoked`, rejected there within one config-cache TTL (≤ 30 s); remove it from the ABO's pins by config deploy (minutes). Alert 30 days before `not_after` (A25). Platform key (K-3): same sequence as routine rotation, done at once; the old `kid` is removed from the ABO's configuration. ABO grant key (K-4): revoke on the platform (HP): envelopes under the revoked `kid` are `rejected`. Deploy the new secret; parked rows are retried, re-signed with the new key. An unknown `kid` answers `transient`, so grants retry until a new key's registration is visible (04 §1.4). Paymob HMAC (K-5): same as routine rotation. Paymob keys (K-6): same as routine rotation; pending work retries. Operator passkey (K-7): any active credential revokes another at once; list and void grants by credential and window. Access (K-8): revoke sessions in Access. Audit-watcher token (K-10): revoke in Cloudflare. The `node:test` file does not read this runbook. Do not revoke a live credential. Do not commit a secret value. Do not deploy.

**Checkpoint**: E2E-P8.3-01 and E2E-P8.3-02 still run `launch-check` on fixtures. The five runbooks are on disk. No live procedure was run.

### 4.3 User Story 1 - Launch readiness check, runbooks, and checklist (Priority: P1) — rebuilds and checklist

**Independent Test**: E2E-P8.3-01 and E2E-P8.3-02, by running `launch-check`.

- [ ] T012 [US1] Add `ops/launch/rebuilds.md` — rebuild runbook, FR-009, E2E-P8.3-01, E2E-P8.3-02. Depends on T011. State the 05 §5 procedures. Each ends with a clean reconciliation run. ABO (05 §5.1): within 30 days of the damage, restore D1 with Time Travel to a point before it. Otherwise, create an empty D1, replay the `ledger/` NDJSON facts in `fact_seq` order (inserts pass the append-only triggers), then recompute the status tables. Fill the gap after the last exported fact: re-inquire every checkout and payment reference known to the rebuilt set, and every transaction in the provider's dashboard export for the gap window. Compare with the platform's `listGrants`. A paid grant with no payment is re-derived from the provider inquiry; a payment with no grant gets a grant row (its `grant_id` is deterministic, so the platform answers `already_applied`). A clinic's DO (05 §5.2): load the clinic's last `coverage_event` snapshot (its terms, positions, usage, holds, suspension and epoch) into an empty DO. Apply, in order, every later `grant_ledger` and `grant_void` row and every later hold, release, suspension and transfer event. Re-apply usage recorded after the snapshot from `usage_event` by `term_id`, including shipped `usage_adjustment` rows; `request_id` uniqueness prevents double counting. Retention keeps these rows while their term is unended (03 §8). Compare the result with `coverage_mirror` and alert on any difference. Reservations in flight at the loss are forfeited to the clinic's benefit. Platform D1 (05 §5.3): restore with Time Travel within 30 days. Otherwise rebuild `grant_ledger` and `grant_void` from the R2 `grant-ledger/` objects. Then ask every DO for a fresh snapshot event (an H method run once per installation), which also rebuilds `coverage_mirror`. Backend projection (05 §5.4): reset `feed_state.cursor` to 0. `coverage_event` is never purged, so the replay reproduces every clinic's latest snapshot. The `node:test` file does not read this runbook. Do not restore a database. Do not call a live account. Do not deploy.

- [ ] T013 [US1] Add `ops/launch/checklist.md` — section 5 D3 checklist, FR-010, E2E-P8.3-01, E2E-P8.3-02. Depends on T012. List these seven items. Each item has owner developer. RC-06 legal confirmation of the no-refund policy, and R-9 advice on payer contact data and erasure timing (01 §7). These are launch conditions (05 §6.2). The tenancy retrofit (01 R-1) is live, and RC-06 legal confirmation is recorded (01 R-9). R-9 advice on payer contact data is recorded, and the erasure action (§3.2) has been run once in staging. 02 §4.4 operating policy: production deploys and secret changes only from an interactive session with hardware-key MFA; no stored token with production rights. This checklist is the P8.3 check. The audit watcher (P8.1) detects breaches. A26 stays Partial. IdP hardware-key MFA and 1-hour Access sessions (TB-7, K-8): Access configuration is in P8.1, verified by this checklist. Production key generation and registration, bootstrap and second credential, pilot grant (FR-92), and deletion of pre-launch installations: the P8.3 runbooks, run at launch. Paymob dashboard settings (callback URLs, integration ids) and HMAC/API key rotation in the dashboard: P8.1/P8.3 runbooks. HMAC and API key rotation follow FR-007 and FR-008 (K-5, K-6). NFR-08 plan-allowance confirmation (05 §7) and D1 Time Travel (a built-in feature): recorded in P8.1. FR-80 monthly payout CSV import: a routine operator action (05 §10), supported by P4.10. The `node:test` file does not read this checklist. Do not perform the items against a live account. Do not deploy.

**Checkpoint**: E2E-P8.3-01 and E2E-P8.3-02 still run `launch-check` on fixtures. `rebuilds.md` and `checklist.md` are on disk. No live procedure was run.

---

## 5. Verification

**Purpose**: Sequencing step 3, before `quickstart.md`. The unit harness from **Test Layout** passes. The command does not boot a worker and does not call a live account. The live H-STG command against a live account is not this command and is not executed.

### 5.1 User Story 1 - Launch readiness check, runbooks, and checklist (Priority: P1) — unit harness

**Independent Test**: E2E-P8.3-01 and E2E-P8.3-02, by running `launch-check`.

- [ ] T014 [US1] Run this unit's harness until `node --test ops/launch/launch-check.test.mjs` passes — local Node only, FR-001, FR-002, FR-003, E2E-P8.3-01, E2E-P8.3-02. Depends on T006 and T013. This task creates no file and edits no file. The two tests run `launch-check.mjs` on `ops/launch/fixtures/production-like.json`, then on `ops/launch/fixtures/workers-dev-enabled.json` and `ops/launch/fixtures/single-operator-credential.json`. Do not run `npm test` in `e2e/fullstack`. Do not boot wrangler. Do not run `wrangler dev` or `startWorker`. Do not start the H-FS or H-STG stack. Do not deploy to Cloudflare, Supabase, or Paymob. Do not run `launch-check` against a live staging or production account. Do not run earlier suites. A missing live account is expected and is not a failure of this task.

**Checkpoint**: E2E-P8.3-01 and E2E-P8.3-02 passed through `node --test ops/launch/launch-check.test.mjs`. No live account was required.

---

## 6. Documentation

**Purpose**: After the harness is green. `quickstart.md` from the plan **Quickstart** outline. `research.md`, `data-model.md`, and `contracts/` stay omitted.

### 6.1 User Story 1 - Launch readiness check, runbooks, and checklist (Priority: P1) — quickstart

**Independent Test**: E2E-P8.3-01 and E2E-P8.3-02, by running `launch-check`.

- [ ] T015 [US1] Write `specs/098-abo-p8-3-launch-readiness-checks/quickstart.md` — unit quickstart, FR-001, FR-002, FR-003, FR-004, FR-005, FR-006, FR-007, FR-008, FR-009, FR-010, E2E-P8.3-01, E2E-P8.3-02. Depends on T014. Fill only these sections: what was implemented and the files added under `ops/launch/`; the harness command for this unit's tests only (`node --test ops/launch/launch-check.test.mjs`); the entry point → module chain per E2E id. E2E-P8.3-01: `node ops/launch/launch-check.mjs ops/launch/fixtures/production-like.json` → `ops/launch/launch-check.mjs`, exit 0 and no failed-condition lines. E2E-P8.3-02: the same script on `ops/launch/fixtures/workers-dev-enabled.json`, then on `ops/launch/fixtures/single-operator-credential.json`; each run exits non-zero and names that condition. The runbooks and `checklist.md` are the documents the Implements line names. They are not steps the harness runs. State that the live H-STG command against a live account is not executed in this workflow. Do not list earlier-unit files, combined counts, or full-suite commands. Do not run `npm test` in `e2e/fullstack`. Do not boot wrangler. Do not deploy.

**Checkpoint**: `quickstart.md` names E2E-P8.3-01 and E2E-P8.3-02, the unit command, and the fixture entry chain.

---

## 7. Dependencies & Execution Order

### 7.1 Phase Dependencies

- **Tests**: No earlier phase. Author `E2E-P8.3-01`, then `E2E-P8.3-02`, in `ops/launch/launch-check.test.mjs`. Both fail before `launch-check.mjs` and the fixtures exist.
- **Implementation**: After both tests are on disk. Add `launch-check.mjs`, then the three fixtures. Add the six runbooks in **Files** order, then `checklist.md`.
- **Verification**: After the script, the three fixtures, the six runbooks, and the checklist exist. Run `node --test ops/launch/launch-check.test.mjs` until it passes.
- **Documentation**: After verification passes. `quickstart.md` only.

### 7.2 User Story Dependencies

- **User Story 1 (P1)**: The only story. P8.2 is consumed with no binding, and this unit does not modify a consumed module. E2E-P8.3-01 and E2E-P8.3-02 are written first. The script and fixtures make those tests able to pass. The runbooks and the checklist are the same story's documents. Verification then documentation follow.

### 7.3 Within Each Phase

- T001 creates `ops/launch/launch-check.test.mjs` with `E2E-P8.3-01`. T002 adds `E2E-P8.3-02` to that same file.
- T003 creates `ops/launch/launch-check.mjs`. T004 creates `ops/launch/fixtures/production-like.json`. T005 creates `ops/launch/fixtures/workers-dev-enabled.json`. T006 creates `ops/launch/fixtures/single-operator-credential.json`.
- T007 creates `ops/launch/pre-launch-installation-deletion.md`. T008 creates `ops/launch/pilot-grant.md`. T009 creates `ops/launch/bootstrap-ceremony.md`. T010 creates `ops/launch/rotations.md`. T011 creates `ops/launch/compromise-response.md`. T012 creates `ops/launch/rebuilds.md`. T013 creates `ops/launch/checklist.md`.
- T014 runs `node --test ops/launch/launch-check.test.mjs` and does not edit a file. It waits until T006 and T013 are done.
- T015 writes only `specs/098-abo-p8-3-launch-readiness-checks/quickstart.md`.

---

## 8. Implementation Waves

Scheduling lives only here. One subphase is one bullet. Tasks inside a subphase run in order.

### 8.1 Wave 1

- T001–T002 [US1] — subphase: `### 3.1 User Story 1 - Launch readiness check, runbooks, and checklist (Priority: P1) — tests` — paths: `ops/launch/launch-check.test.mjs`

### 8.2 Wave 2

- T003–T006 [US1] — subphase: `### 4.1 User Story 1 - Launch readiness check, runbooks, and checklist (Priority: P1) — launch-check and fixtures` — paths: `ops/launch/launch-check.mjs`, `ops/launch/fixtures/production-like.json`, `ops/launch/fixtures/workers-dev-enabled.json`, `ops/launch/fixtures/single-operator-credential.json`
- T007–T011 [US1] — subphase: `### 4.2 User Story 1 - Launch readiness check, runbooks, and checklist (Priority: P1) — runbooks (part 1)` — paths: `ops/launch/pre-launch-installation-deletion.md`, `ops/launch/pilot-grant.md`, `ops/launch/bootstrap-ceremony.md`, `ops/launch/rotations.md`, `ops/launch/compromise-response.md`

### 8.3 Wave 3

- T012–T013 [US1] — subphase: `### 4.3 User Story 1 - Launch readiness check, runbooks, and checklist (Priority: P1) — rebuilds and checklist` — paths: `ops/launch/rebuilds.md`, `ops/launch/checklist.md`

### 8.4 Wave 4

- T014 [US1] — subphase: `### 5.1 User Story 1 - Launch readiness check, runbooks, and checklist (Priority: P1) — unit harness` — paths: `ops/launch/launch-check.test.mjs`

### 8.5 Wave 5

- T015 [US1] — subphase: `### 6.1 User Story 1 - Launch readiness check, runbooks, and checklist (Priority: P1) — quickstart` — paths: `specs/098-abo-p8-3-launch-readiness-checks/quickstart.md`
