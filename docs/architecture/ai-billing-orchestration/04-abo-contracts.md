# AI Billing Orchestrator — Contracts

**Status:** Phase 2 design. **Date:** 2026-10-01. Requirement IDs refer to the [seed](00-abo-requirements-seed.md); "01 §n", "02 §n", "03 §n" to the [decision memo](01-abo-design-decisions.md), [architecture and threat model](02-abo-architecture-and-threat-model.md) and [data model](03-abo-data-model-and-lifecycle.md). Field lists are normative; wire encodings are JSON with snake_case keys, money in minor units, and UTC ISO-8601 times.

## Table of Contents

1. [ABO and AI Platform](#1-abo-and-ai-platform)
   - [Transport and versioning](#11-transport-and-versioning)
   - [Result envelope](#12-result-envelope)
   - [Method catalogue](#13-method-catalogue)
   - [Grant envelope and validation](#14-grant-envelope-and-validation)
   - [Operator assertion](#15-operator-assertion)
   - [Receipt](#16-receipt)
   - [Coverage snapshot](#17-coverage-snapshot)
2. [Shared backend and ABO](#2-shared-backend-and-abo)
   - [Token claims](#21-token-claims)
   - [ABO clinic API](#22-abo-clinic-api)
   - [ABO errors](#23-abo-errors)
3. [Flutter and shared backend](#3-flutter-and-shared-backend)
   - [RPCs](#31-rpcs)
   - [Status fields and notice codes](#32-status-fields-and-notice-codes)
   - [Read-time computation](#33-read-time-computation)
   - [Desktop behaviour](#34-desktop-behaviour)
   - [Affected backend and frontend files](#35-affected-backend-and-frontend-files)
4. [Shared backend and desktops to AI Platform](#4-shared-backend-and-desktops-to-ai-platform)
   - [Coverage feed](#41-coverage-feed)
   - [Clinic routes and denial codes](#42-clinic-routes-and-denial-codes)
5. [Provider port](#5-provider-port)
   - [Operations](#51-operations)
   - [Normalised types](#52-normalised-types)
   - [Paymob adapter](#53-paymob-adapter)
6. [AI Platform change list](#6-ai-platform-change-list)
   - [Existing source files](#61-existing-source-files)
   - [New source files](#62-new-source-files)
   - [D1 migrations](#63-d1-migrations)
   - [wrangler.toml](#64-wranglertoml)
   - [Tests](#65-tests)
   - [Other affected paths](#66-other-affected-paths)
7. [Contract versioning](#7-contract-versioning)
   - [Channels](#71-channels)
   - [Rules](#72-rules)
   - [Changing a version](#73-changing-a-version)

---

## 1. ABO and AI Platform

### 1.1 Transport and versioning

- **Transport.** A service binding from the ABO to the platform's named `WorkerEntrypoint` class `VendorEntrypoint`, using RPC methods. It is not reachable from the internet. The platform never calls the ABO (01 §3.7).
- **Versioning (X-10, NFR-09).** Every argument object and every result carries `contract_version`. The platform accepts N and N−1 and answers `rejected` with code `contract_version_unsupported` otherwise. Tokens carry `ver`, checked against the existing `token_contract` table. The rules for every channel are in §7.
- **Canonical form.** Signed and hashed objects use the JSON Canonicalization Scheme (RFC 8785). Signatures are Ed25519 over the canonical bytes, serialised as compact JWS (RFC 7515 compact serialization: base64url header, payload and signature joined by `.`) with header `{alg: "EdDSA", kid}`, where `kid` names the signing key in the relevant key set (02 §3.1, K-2 to K-4). Signing and verification run on WebCrypto (`crypto.subtle`), which both workerd and Node provide, so a signature made on either runtime verifies on the other. Hashes are SHA-256, hex-encoded.

### 1.2 Result envelope

Every method returns `{contract_version, result, code, detail, receipt?}`. `detail` is a string. The object has no other key. `receipt` is present when `result` is `applied` or `already_applied`, and then it is the receipt in §1.6. On every other result, `receipt` is absent.

`registerOperatorCredential`, `revokeOperatorCredential`, and `listOperatorCredentials` do not record a grant or a reversal, so they do not return `applied` or `already_applied`. A successful call is `ok`: `receipt` is absent and `code` is empty. On register and revoke, `detail` is the JSON text of the `operator_credential` row (03 §3.2). On `listOperatorCredentials`, `detail` is the JSON text of an array of `{credential_id, public_key_cose, alg}` for each row with `status` `active`. That array is what the ABO uses to verify assertions for its own HP actions (05 §3.2).

`registerIssuerKey`, `revokeIssuerKey`, `retireIssuerKey`, and `listIssuerKeys` do not record a grant or a reversal, so they do not return `applied` or `already_applied`. A successful call is `ok`: `receipt` is absent and `code` is empty. On register, revoke, and retire, `detail` is the JSON text of the `issuer_key` row (03 §3.2). On `listIssuerKeys`, `detail` is the JSON text of an array of `{kid, public_key, status, not_before, not_after}` for each row with `status` `active` or `retiring`. `public_key` is the base64url encoding of the raw 32-byte Ed25519 public key, the encoding the replaced `installation_key.public_key` stored and the encoding WebCrypto imports as `raw`. The ABO's pinned `ISSUER_KEYS` and the backend's registered issuer public key use that same string. The hourly pin comparison is the set of `{kid, public_key}` for those rows; `status` and the validity times are in the list for expiry checks (AL-14) and are not themselves a pin mismatch.

`registerServiceKey`, `revokeServiceKey`, `listServiceKeys`, `publishPlanVersion`, `retirePlanVersion`, `getCoverage`, `listGrants`, `listGrantsForVoid`, and `readCoverageEvents` do not record a grant or a reversal, so they do not return `applied` or `already_applied`. A successful call is `ok`: `receipt` is absent and `code` is empty. On `registerServiceKey`, `revokeServiceKey`, `publishPlanVersion`, and `retirePlanVersion`, `detail` is the JSON text of the stored row (03 §3.2). On `listServiceKeys`, `getCoverage`, `listGrants`, `listGrantsForVoid`, and `readCoverageEvents`, `detail` is the JSON text of the payload in that method's §1.3 row.

`beginTransfer` and `deleteInstallation` do not record a grant or a reversal, so they do not return `applied` or `already_applied`. A successful call is `ok`: `receipt` is absent and `code` is empty. On `beginTransfer`, `detail` is the JSON text of the `transfer` row (03 §3.2). On `deleteInstallation`, `detail` is the JSON text of `{installation, tenant_binding}` for those rows after the call (03 §3.2).


| `result`          | Meaning                                                                                  | ABO action                                         |
| ----------------- | ---------------------------------------------------------------------------------------- | -------------------------------------------------- |
| `ok`              | Read succeeded. A successful `registerOperatorCredential`, `revokeOperatorCredential`, `listOperatorCredentials`, `registerIssuerKey`, `revokeIssuerKey`, `retireIssuerKey`, `listIssuerKeys`, `registerServiceKey`, `revokeServiceKey`, `listServiceKeys`, `publishPlanVersion`, `retirePlanVersion`, `getCoverage`, `listGrants`, `listGrantsForVoid`, `readCoverageEvents`, `beginTransfer`, or `deleteInstallation` is also `ok`; the payload is `detail` | —                                                  |
| `applied`         | Change made now; `receipt` present                                                       | Record outcome; work done                          |
| `already_applied` | Same id with the same content hash was applied before; the original `receipt` is returned | Record outcome; work done (NFR-03)                 |
| `conflict`        | Same id with a different content hash                                                    | Park and alert; never retried automatically        |
| `rejected`        | Validation failed (`code` says why); retrying cannot help                                 | Park and alert                                     |
| `transient`       | Storage or DO unavailable, or a state that will clear (`detail` says which: `unavailable`, `unknown_kid`, `awaiting_transfer`, `awaiting_transfer_out`, `transfer_pending`); nothing was changed | Retry with backoff forever (NFR-01)                |


### 1.3 Method catalogue

The classes (M, H, HP) are defined in 02 §3.3. Each H and HP method takes `access_jwt`; each HP method also takes `assertion` (§1.5).


| Method                                         | Class | Input (beyond `contract_version`)                                          | Output                                    | Idempotent by                   |
| ---------------------------------------------- | ----- | -------------------------------------------------------------------------- | ----------------------------------------- | ------------------------------- |
| `grant`                                        | By `source.kind`: `paid` M, `complimentary` HP | Grant envelope (§1.4); `abo_kid` and `abo_signature` for `paid`; `assertion` for `complimentary` | Receipt | `grant_id` plus `envelope_sha256` |
| `voidForReversal`                              | M     | `grant_id` (the paid grant), `reversal_id`, `reason`, `evidence_sha256`, `partial`, `abo_kid`, `abo_signature`. `partial` is required and is a boolean (01 §5, X-01) | `partial` false: Receipt. Resolves the live term through `origin_grant_id` (03 §5.5); if the grant is not yet applied, stores a tombstone. Writes `grant_void` with `source` `reversal` and this call's `evidence_sha256`, plus the R2 void object (03 §3.2, §3.3). `partial` true: `rejected`, `code` `partial_void`, `detail` empty; no `grant_void` row, no R2 void object, no coverage event, and no tombstone. A missing `partial`, or a value that is not a boolean, is `rejected` with code `partial_invalid` and `detail` empty, and writes nothing. A rejected call stores nothing, so that `reversal_id` can still be applied later with `partial` false. After a void is stored, the same `reversal_id` with the same `grant_id`, `reason`, `evidence_sha256`, and `partial` false is `already_applied` and returns the original receipt; any difference in those four is `conflict` and changes nothing | `reversal_id` |
| `getCoverage`                                  | M     | `org_id`                                                                   | `ok`. `detail` is the JSON text of `{snapshot, queued_terms, recent_terms}`. `snapshot` is §1.7. `queued_terms` and `recent_terms` have the shapes in §1.7. `code` is empty and `receipt` is absent | —                               |
| `readCoverageEvents`                           | M     | `after`, `limit` ≤ 200                                                     | `ok`. `detail` is the JSON text of `{after, events, next_after, has_more}`. Each element of `events` is the §4.1 event object. `after` echoes the caller's cursor. The page contains events with `feed_seq` greater than `after`, in ascending `feed_seq`, at most `limit`. `next_after` is the last returned `feed_seq`, or `after` when `events` is empty. `has_more` is true when a further event exists beyond the page. A missing `limit`, or a `limit` outside 1 through 200, is `rejected` with code `limit_invalid` and `detail` empty. On `ok`, `code` is empty and `receipt` is absent. The page is unsigned | —                               |
| `listGrants`                                   | M     | Filter: `org_id`, `source_kind`, `credential_id`, `applied_from`, `applied_to`. A present filter constrains that column; an absent filter does not. `credential_id` matches `operator_credential_id`. `applied_from` and `applied_to` are inclusive UTC ISO-8601 bounds on `applied_at` | `ok`. `detail` is the JSON text of an array of `grant_ledger` rows (03 §3.2), in ascending `applied_at` then `grant_id`. Each row's `receipt` is the §1.6 receipt object. `code` is empty and the envelope `receipt` is absent | —                               |
| `listIssuerKeys`                               | M     | —                                                                          | `ok`. `detail` is the JSON text of an array of `{kid, public_key, status, not_before, not_after}` for each `issuer_key` with `status` `active` or `retiring`. `public_key` is the base64url raw 32-byte Ed25519 key. The ABO compares the set of `{kid, public_key}` with its pinned `ISSUER_KEYS` hourly and alerts on any difference (§2.2, AL-22); `status` and the validity times are not a pin mismatch. `receipt` is absent and `code` is empty | — |
| `listOperatorCredentials`                      | M     | —                                                                          | `ok`. `detail` is the JSON text of an array of `{credential_id, public_key_cose, alg}` for each `operator_credential` with `status` `active` (03 §3.2), so the ABO can verify assertions for its own HP actions (05 §3.2). `receipt` is absent and `code` is empty | — |
| `listServiceKeys`                              | M     | —                                                                          | `ok`. `detail` is the JSON text of an array of `{kid, status, not_before, not_after}` for every `service_key` row. `not_before` and `not_after` are the validity. `receipt` is absent and `code` is empty. The ABO checks at isolate start and hourly that its signing `kid` is listed with `status` `active` and is not expired (03 §3.2); otherwise it pauses `grant` and `reverse` work and raises AL-23 (02 §6) | — |
| `feedConsumerHealth`                           | M     | —                                                                          | `last_pull_at`, `last_cursor`             | —                               |
| `transferOut`, `transferIn`                    | M     | `transfer_id` (an authorised `transfer` row must exist)                    | `applied` stores the package on the `transfer` row (03 §3.2) and inserts that step's `transfer_step`. `detail` is the JSON text of the package. `receipt` is the §1.6 transfer receipt. A retry of the same `transfer_id` is `already_applied` and returns the original receipt. `transferIn` before `transferOut` has applied is `transient` with `detail` `awaiting_transfer_out` and changes nothing | `transfer_id`                   |
| `suspend`, `resume`                            | H     | `org_id`, `reason`                                                         | Snapshot                                  | Target state                    |
| `inspectCoverage`                              | H     | `org_id`                                                                   | Full DO ledger: terms, grants, reservations | —                             |
| `supportLookup`                                | H     | Request `reference`                                                        | Existing lookup (`ai-platform/src/support/index.ts`); envelope within retention | —             |
| Kill switch, routing policy, cohort, capability lifecycle, token contract | H | As today (`src/control/index.ts:146-211`)                           | As today                                  | As today                        |
| `grant` with `kind = term_adjustment`          | HP    | Envelope with `adjustment` fields                                          | Receipt                                   | `grant_id`                      |
| `beginTransfer`                                | HP    | `org_id`, `from_installation_id` (the org's `active` or `held_for_transfer` binding), `reason`. Same org only | `ok`. `detail` is the JSON text of the `transfer` row (03 §3.2), which includes `transfer_id`. `code` is empty and `receipt` is absent. Atomically retires the source binding and creates the org's new active binding with the next epoch; the new DO starts `awaiting_transfer` (03 §5.4). The same assertion challenge is `ok` again and does not insert another row or create another binding | Assertion challenge |
| `releaseHeld`, `voidGrant`                     | HP    | `grant_id`, `reason`                                                       | Receipt. `voidGrant` writes `grant_void` with `source` `operator` and sets `evidence_sha256` to the assertion challenge (03 §3.2, §1.5). It takes no `evidence_sha256` input. `releaseHeld` does not write `grant_void` | Assertion challenge             |
| `listGrantsForVoid`                            | H     | `credential_id`, `window`. `window` is `{applied_from, applied_to}`. Both fields are required UTC ISO-8601 timestamps and are inclusive bounds on `grant_ledger.applied_at`. `applied_from` must be less than or equal to `applied_to`. The span has no maximum. `credential_id` matches `operator_credential_id`, including when that credential is not `active` | `ok`. `detail` is the JSON text of an array of `{grant_id, origin_grant_id, org_id, installation_id, kind, source_kind, operator_credential_id, envelope_sha256, receipt, applied_at}` (the `grant_ledger` columns, 03 §3.2) for rows with that `operator_credential_id` whose `applied_at` is inside the window, in ascending `applied_at` then `grant_id`. Each `receipt` is the §1.6 receipt object. An empty array is `ok`. A missing window field, a value that is not a UTC ISO-8601 timestamp, or `applied_from` greater than `applied_to` is `rejected` with code `window_invalid` and `detail` empty. On `ok`, `code` is empty and the envelope `receipt` is absent. For SR-25 | —                               |
| `publishPlanVersion`, `retirePlanVersion`      | HP    | `publishPlanVersion`: `plan_id`, `version`, `display_name`, `capabilities`, `max_cost_class`, `concurrency_limit`, `max_allowance_per_month`. `retirePlanVersion`: `plan_id`, `version` | `publishPlanVersion` `ok` inserts `status` `published` and sets `published_by` to the Access email and `assertion_sha256` to the assertion challenge hash. The same `(plan_id, version)` with the same `display_name`, `capabilities`, `max_cost_class`, `concurrency_limit`, and `max_allowance_per_month` is `ok` again and does not insert another row or change `status` or those fields. `conflict` when that pair is stored with a different value in any of those fields: `code` is `plan_version_mismatch` and `detail` is empty. `retirePlanVersion` `ok` sets `status` from `published` to `retired`, and `ok` when it is already `retired`. A missing `(plan_id, version)` is `rejected` with code `plan_version_not_found` and `detail` empty. On `ok`, `detail` is the JSON text of the `plan_version` row (03 §3.2), `code` is empty, and `receipt` is absent. `retirePlanVersion` is the only writer of `retired` | `(plan_id, version)`; retire by target state |
| `setCeilingPolicy`                             | HP    | `per_grant_max_days`, `per_grant_max_allowance_months`, `window_days`, `window_max_days`, `window_max_allowance_months`, `max_paid_grace_days`, `paid_cap_rule` (03 §3.2) | `ok` inserts the next `version` (1 when the table is empty), sets `set_by` to the Access email and `assertion_sha256` to the assertion challenge hash, and stores those ceiling fields. The same assertion challenge is `ok` again and does not insert another row. On `ok`, `detail` is the JSON text of the `ceiling_policy` row; its `version` is the policy version. `code` is empty and `receipt` is absent | Assertion challenge             |
| `registerServiceKey`, `revokeServiceKey`       | HP    | `registerServiceKey`: `kid`, `public_key`, `not_before`, `not_after`. Those two timestamps are the validity, UTC ISO-8601. `public_key` is the base64url encoding of the raw 32-byte Ed25519 public key. `revokeServiceKey`: `kid` | `registerServiceKey` `ok` inserts `status` `active`, stores that `public_key` unchanged, sets `service` to `abo`, `not_before` and `not_after` to the supplied validity, `registered_by` to the Access email, and `assertion_sha256` to the assertion challenge hash. The same `kid` with the same `public_key` is `ok` again and does not insert another row or change `status` or the stored validity. `conflict` when that `kid` is stored with a different `public_key`: `code` is `public_key_mismatch` and `detail` is empty. A `public_key` that is not that encoding is `rejected` with code `public_key_invalid` and `detail` empty. `revokeServiceKey` `ok` sets `status` to `revoked`, and `ok` when it is already `revoked`. A missing `kid` is `rejected` with code `kid_not_found` and `detail` empty. On `ok`, `detail` is the JSON text of the `service_key` row (03 §3.2), `code` is empty, and `receipt` is absent. `revokeServiceKey` is the only writer of `revoked` | `kid`; revoke by target state |
| `registerIssuerKey`                            | HP    | `kid`, `public_key`, `not_before`, `not_after`. `public_key` is the base64url encoding of the raw 32-byte Ed25519 public key | `ok` inserts `status` `active`, stores that `public_key` unchanged, sets `issuer` to the configured issuer id, `registered_by` to the Access email, and `assertion_sha256` to the assertion challenge hash. The same `kid` with the same `public_key` is `ok` again and does not insert another row or change `status`. `conflict` when that `kid` is stored with a different `public_key`: `code` is `public_key_mismatch` and `detail` is empty. A `public_key` that is not that encoding is `rejected` with code `public_key_invalid` and `detail` empty. On `ok`, `detail` is the JSON text of the `issuer_key` row (03 §3.2), `code` is empty, and `receipt` is absent. This call does not set `retiring` | `kid` |
| `retireIssuerKey`                              | HP    | `kid`                                                                      | `ok` sets `status` from `active` to `retiring`, and `ok` when it is already `retiring`. Tokens for that `kid` stay accepted until `not_after` (02 §6 K-2). A missing `kid` is `rejected` with code `kid_not_found` and `detail` empty. A `revoked` row stays `revoked` and the result is `rejected` with code `kid_revoked` and `detail` empty. On `ok`, `detail` is the JSON text of the `issuer_key` row, `code` is empty, and `receipt` is absent. This is the only writer of `retiring` | Target state |
| `revokeIssuerKey`                              | HP    | `kid`                                                                      | `ok` sets `status` to `revoked`, and `ok` when it is already `revoked`. It does not set `retiring`. A missing `kid` is `rejected` with code `kid_not_found` and `detail` empty. On `ok`, `detail` is the JSON text of the `issuer_key` row, `code` is empty, and `receipt` is absent | Target state |
| `registerOperatorCredential`                   | HP, or bootstrap | WebAuthn attestation; approving assertion (none only while the table is empty) | `ok` inserts the row, `pending` for 24 hours, and sets `activates_at` 24 hours ahead. The insert does not set `status` to `active` (§1.5). The same `credential_id` stored with the same `public_key_cose` is `ok` again and does not insert another row. `conflict` when it is stored with a different `public_key_cose`: `code` is `public_key_cose_mismatch` and `detail` is empty. On `ok`, `detail` is the JSON text of the `operator_credential` row (03 §3.2), `code` is empty, and `receipt` is absent. When the table is not empty and the approving assertion is absent, the result is `rejected` with code `assertion_required`. A later registration that includes a valid approving assertion is the normal `ok` insert | `credential_id`             |
| `revokeOperatorCredential`                     | HP    | `credential_id`                                                            | `ok` when the row becomes `revoked`, and `ok` when it is already `revoked`. `detail` is the JSON text of that `operator_credential` row (03 §3.2). `code` is empty and `receipt` is absent | Target state                    |
| `deleteInstallation`                           | HP    | `org_id`, `reason`                                                         | `ok`. Installation marked `deleted`. With no coverage left, its binding is retired and the org's next token or grant creates a new binding with the next epoch. With coverage left, the binding becomes `held_for_transfer` and AL-18 fires: AI tokens get `coverage_lapsed` (`coverage_reason = transfer_pending`), grants get `transient` (`detail = transfer_pending`), and no new binding is created until `beginTransfer` moves the time, or the remaining grants are voided, which retires the binding (03 §5.4, A24). On `ok`, `detail` is the JSON text of `{installation, tenant_binding}` for those rows after the call (03 §3.2), `code` is empty, and `receipt` is absent. `ok` again when the installation is already `deleted` and the binding is already in the status this call left it in; a repeat does not create a binding and does not raise AL-18 again | Target state |


Removed: all `/control/*` HTTP routes and `handleEntitle`, `handleOverride`, `handleEnroll`, `handleRotate`, `handleRevokeKey`, `handlePlanCreate`/`Update`/`Delete`, `handleCreditPriceActivate` (FR-91). A transfer runs as a saga driven by an ABO work row: `beginTransfer` (HP) records the authorisation, then `transferOut` and `transferIn` (M) are retried until both report `applied` or `already_applied`.

### 1.4 Grant envelope and validation


| Field                  | Type and rule                                                                                                            |
| ---------------------- | ------------------------------------------------------------------------------------------------------------------------ |
| `contract_version`     | Integer                                                                                                                  |
| `grant_id`             | Hex SHA-256 per 03 §7                                                                                                    |
| `org_id`               | Tenant UUID; the platform resolves or creates the active binding                                                         |
| `kind`                 | `term` or `term_adjustment` (X-07)                                                                                       |
| `placement`            | `queue` only at launch; `immediate` and `replace` are rejected (`placement_not_supported`, X-06). FR-32 upgrades use `term_adjustment` |
| `source`               | `{kind: paid, complimentary or transfer, ref, operator_email, reason}`. `operator_email` and `reason` are required unless `kind = paid` (FR-36). `ref` is the ABO's `payment_id`, operator action id or `transfer_id`; never a provider id (SR-10) |
| `plan`                 | `{plan_id, plan_version}`; the platform snapshots the published version itself                                           |
| `duration`             | `{unit, count}`. `paid`: `month` with count 1, 3 or 12. `complimentary`: `month` or `day` (03 §6.1)                        |
| `allowance_credits`    | Integer ≥ 1                                                                                                              |
| `grace`                | `{days, cap_rule}`. `paid`: `days` ≤ `max_paid_grace_days` (7) and `cap_rule = proportional`                               |
| `adjustment`           | For `term_adjustment`: `{plan?, add_allowance?, extend_days?}`                                                           |
| `paid_at`              | For `paid`: the provider's payment time                                                                                  |
| `evidence`             | `{content_sha256, approvals[]}`. For `paid`, `content_sha256` is the hash of the ABO payment fact and its evidence. `approvals` holds operator assertions. The policy minimum is 1 and binds every grant (`paid`, `complimentary`, and `transfer`). A shorter list is `rejected` with code `approvals_required` and `detail` empty (step 1, X-09) |
| `ceiling_override`     | Optional; needs a second, separate assertion and is separately alerted (SR-24)                                          |


The platform validates, in order, and answers `rejected` with the named code on failure:

1. `contract_version` supported; the envelope's canonical hash matches the signed or asserted hash (`bad_signature`, `bad_assertion`). Every grant (`paid`, `complimentary`, and `transfer`) requires `evidence.approvals` to hold at least 1 element. A shorter list is `rejected` with code `approvals_required` and `detail` empty (X-09).
2. Paid: the ABO signature verifies against the named `service_key`. An unknown `kid` answers `transient` with `detail = unknown_kid` (a registration may still be propagating; the ABO's own check raises AL-23 if it persists); a `kid` with `status` `revoked`, or an expired `kid`, answers `rejected` (`bad_signature`). A `kid` is expired when `status` is `active` and now is before its `not_before` or after its `not_after` (03 §3.2). Expired is not a stored status. Complimentary: the assertion verifies (§1.5). Transfer: the `transfer` row is authorised.
3. The plan version is published (`plan_not_published`). The source, unit and count are allowed (`unit_not_allowed`, per the `duration` row). For `paid`, `allowance_credits` ≤ `max_allowance_per_month` × months and grace follows the `grace` row (`exceeds_plan_bound`). This bounds what a compromised ABO can fabricate (02 AD-8).
4. Complimentary: the grant is within the current `ceiling_policy` (greatest `version`) per grant and per clinic 90-day window, counting earlier complimentary grants and `term_adjustment` additions (03 §3.2), unless a valid override is attached (`exceeds_ceiling`). The window is anchored at this grant's `applied_at` (the time of this check): `window_days` × 24 hours ending at that instant, for its `org_id`. A complimentary `duration.unit` of `month` counts as `duration.count` × 31 days toward the per-grant and window day ceilings; `day` counts as `duration.count`.
5. The `grant_id` has no void tombstone (`voided`). The clinic's DO has not transferred out (`transferred_out`). A DO still `awaiting_transfer`, or an org whose binding is `held_for_transfer`, answers `transient` to any non-transfer grant.

On success the DO applies the grant atomically, stores the envelope and evidence, and emits the ledger mirror, the coverage event and the out-of-band alert through its outbox (01 §3.5). Every grant alerts, paid ones included (AL-11); complimentary grants, overrides and transfers are marked for attention. Paid grants also feed a velocity check: more than 3 paid grants for one clinic in 24 hours, or more than 20 across all clinics in an hour, raises a platform alert.

### 1.5 Operator assertion

The ABO console runs the WebAuthn `get` ceremony and forwards the result. The platform verifies it; the ABO's own check is only for UX.


| Element            | Rule                                                                                                                                                  |
| ------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------- |
| Operation object   | `{op, params, actor_email, issued_at, nonce, contract_version}`; `params` is the exact method input, without the assertion                            |
| Challenge          | base64url(SHA-256(canonical operation object))                                                                                                        |
| Relying party      | `rpId` is the console hostname; `clientDataJSON.origin` must equal `https://ops.<vendor-domain>`; `type` is `webauthn.get`                            |
| Flags              | User presence and user verification both set                                                                                                          |
| Credential         | `active` in `operator_credential` (its 24-hour activation delay has passed); algorithm ES256 (DER signature converted to raw) or EdDSA (01 R-5). `registerOperatorCredential` inserts `status` `pending` and `activates_at` 24 hours ahead and does not set `active` (§1.3). The only write from `pending` to `active` is this credential read, and the same read inside `listOperatorCredentials`: when `status` is `pending` and `activates_at` is at or before now, that read sets `status` to `active` and raises no alert, then this rule sees `active` and the list includes the row. A row still `pending` because `activates_at` is ahead is `rejected` with code `credential_not_active`. A row with `status` `revoked` is `rejected` with code `credential_revoked` |
| Freshness and reuse | `issued_at` within 5 minutes of now; the challenge hash is inserted into `assertion_used` and must not already be there. `issued_at` older than 5 minutes is `rejected` with code `assertion_expired`. A challenge hash already stored is `rejected` with code `assertion_used` |
| Actor              | `actor_email` equals the email in the Access JWT verified for the same call. A different `actor_email` is `rejected` with code `actor_email_mismatch` |


### 1.6 Receipt

`{contract_version, grant_id or reversal_id or transfer_id, installation_id, org_id, result, term_ids, applied_at, ledger_seq, envelope_sha256, kid, signature}`. The signature is by the platform key (02 K-3) over the canonical receipt without the signature. `signature` is a compact JWS (RFC 7515), the §1.1 serialisation: header `{alg: "EdDSA", kid}` naming that platform key, payload the RFC 8785 canonical receipt with the `signature` member omitted, and the third segment the base64url Ed25519 signature. `ledger_seq` is the integer `clinic_seq` on the coverage event for this grant (`kind` `grant_applied`) or void (`kind` `grant_voided`) (03 §3.1, §6.7). It is not a `grant_ledger` column. Both sides store the receipt (SR-05). This object records a grant, a reversal, or a transfer step. `registerOperatorCredential`, `revokeOperatorCredential`, `listOperatorCredentials`, `registerIssuerKey`, `revokeIssuerKey`, `retireIssuerKey`, `listIssuerKeys`, `registerServiceKey`, `revokeServiceKey`, `listServiceKeys`, `publishPlanVersion`, `retirePlanVersion`, `getCoverage`, `listGrants`, `listGrantsForVoid`, `readCoverageEvents`, `beginTransfer`, and `deleteInstallation` return `ok` and do not include it (§1.2). `transferOut` and `transferIn` do include it. On those receipts the id member is `transfer_id`, not `grant_id` or `reversal_id`. `installation_id` is the installation that step wrote. `envelope_sha256` is the SHA-256 of the RFC 8785 canonical package. `ledger_seq` is the `clinic_seq` of the `transfer` coverage event that step wrote (03 §6.7). `term_ids` are the terms that step ended (`transferOut`) or created (`transferIn`).

### 1.7 Coverage snapshot

Used by `getCoverage`, the feed (§4.1) and the backend projection.


| Field          | Content                                                                                                                                           |
| -------------- | ------------------------------------------------------------------------------------------------------------------------------------------------- |
| `contract_version` | Version of the snapshot shape. Every stored copy (`coverage_mirror`, `coverage_view`, the backend projection) keeps it, so old rows are read by the rules they were written with |
| `state`        | 03 §5.7                                                                                                                                           |
| `reason`       | For non-available states: `none`, `expired`, `grace_exhausted`, `exhausted`, `reversed`, `transferred`, `transfer_pending`                        |
| `suspended`    | Boolean                                                                                                                                           |
| `term`         | Null, or `{ref, plan_display_name, starts_at, ends_at, grace_ends_at, allowance, used, band}`, where `band` is `ok`, `75`, `90` or `exhausted`    |
| `queued_count` | Unheld queued terms                                                                                                                               |
| `held_count`   | Held terms (01 I-3)                                                                                                                               |
| `coverage_through` | Projected end of coverage assuming no exhaustion; read live by `getCoverage` for duplicate classification, with `coverage_view` as the fallback (03 §2.4) |
| `binding_epoch`, `clinic_seq` | Ordering key; consumers apply a snapshot only if this pair is greater than the stored one (03 §4)                                    |


There are no prices, payment references or provider ids in the snapshot (FR-53, SR-10).

`getCoverage` returns this snapshot together with two lists. They are companions of the snapshot, and they are the same lists `GET /v1/coverage` describes as queued terms (plan and duration) and the last 12 terms with usage (§4.2).

- `queued_terms`: the unheld terms in state `queued`, in ascending `position`. Each object is `{plan_id, plan_version, plan_display_name, duration_unit, duration_count}`. A queued term stores a duration and has no dates (03 §6.1).
- `recent_terms`: at most the last 12 terms whose state is `active`, `grace`, or `ended`, highest `position` first. Each object is `{term_id, state, plan_display_name, starts_at, ends_at, grace_ends_at, allowance, used}`. `used` is the `hot` row's `used` when the term is `hot.active_term_id`, and `used_final` otherwise.

## 2. Shared backend and ABO

The backend and the ABO never call each other. The only thing the backend gives the ABO is a billing token, carried by the administrator desktop. That keeps the channel limited to billing and bound to the caller (SR-09).

### 2.1 Token claims

All tokens: header `{alg: EdDSA, kid, typ: JWT}`; `iss` = the backend issuer id from `ai.issuer_id`; `ver = "2"`. `org` always comes from `current_org_id()`, never from an argument (SR-03).


| Claim    | AI token                                   | Billing token                   | Feed token           |
| -------- | ------------------------------------------ | ------------------------------- | -------------------- |
| `aud`    | `ai-platform`                              | `abo`                           | `ai-platform-feed`   |
| `sub`    | Staff member id                            | Staff member id                 | `backend-feed`       |
| `org`    | Tenant id                                  | Tenant id                       | Absent               |
| `role`   | Membership role                            | `administrator`                 | Absent               |
| `branch` | Current branch                             | Current branch                  | Absent               |
| `scopes` | `ai.*` permissions, as today (`backend/supabase/migrations/20260905120300_fix_aat_lifetime_fallback.sql:115-124`) | Absent | Absent |
| `exp − iat` | ≤ 600 s                                 | ≤ 300 s                         | ≤ 120 s              |
| `jti`    | UUID                                       | UUID                            | UUID                 |


Platform verification replaces `iss` = installation id (`ai-platform/src/identity/index.ts:146-148,298`). The platform checks `kid` in `issuer_key` (active or retiring, within validity), `iss`, `aud`, the lifetime and clock skew (as today, `:283-296`), and `ver`. It then resolves `org` through `tenant_binding`. The first valid token for an unknown `org` creates an installation and a binding at epoch 1. The installation stores `org_id` from the token, a new platform clinic UUID as `installation_id` (03 §7), `status` `active`, `display_name` as the empty string, `region` as the empty string, and `enrolled_at` as the UTC ISO-8601 time of the insert. The binding stores `status` `active`, `epoch` 1, and `created_at` as that same time. Creation is capped at 50 per day across all tenants: the count is `tenant_binding` rows with `epoch` 1 whose `created_at` falls in the last 24 hours. The 51st such attempt inserts nothing, the clinic route answers 401 `unauthenticated`, and the platform raises AL-20. That cap bounds junk from a leaked issuer key.

### 2.2 ABO clinic API

Hostname `billing.<vendor-domain>`. Every call sends `Authorization: Bearer <billing token>` and `Abo-Contract-Version`; every response, errors included, carries the same header and a `contract_version` body field (§7). The ABO verifies the token against the issuer public keys pinned in its own configuration (`ISSUER_KEYS`, 02 §6), never against keys fetched from the platform, and re-checks `role` (FR-10).


| Method and path             | Request                                                             | Response                                                                                                                                                                                                                                      |
| --------------------------- | ------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `GET /v1/offers`            | —                                                                   | `offers[]`: `offer_id`, `version`, `plan_display_name`, `term_unit`, `term_count`, `price_minor`, `currency`, `allowance_credits`, `grace_days`, localized `copy`; `terms`: `version` and text (FR-05, FR-17)                                     |
| `GET /v1/billing-contact`   | —                                                                   | `version`, `name`, `email`, `phone`, or `not_found`                                                                                                                                                                                           |
| `PUT /v1/billing-contact`   | `client_request_id`, `name`, `email`, `phone` (E.164)               | New version (FR-51)                                                                                                                                                                                                                           |
| `POST /v1/checkouts`        | `client_request_id`, `offer_id`, `offer_version`, `terms_version`   | `checkout_id`, `reference`, `redirect_url`, `expires_at`, `starts` (`now` or `after_current`, with `projected_start`). The admin sees before paying whether the term queues (FR-30, FR-31, A30). `starts` comes from a live `getCoverage`; if that fails, from `coverage_view`, and the checkout is still created (03 §2.4) |
| `GET /v1/checkouts/{id}`    | —                                                                   | `reference`, shown state (03 §5.1), offer summary, `payment_reference`, `term_ref`, `updated_at` (FR-14)                                                                                                                                      |
| `GET /v1/checkouts?open=1`  | —                                                                   | This tenant's open and recently paid checkouts, so any desktop can resume (FR-14, A2, A12)                                                                                                                                                    |
| `GET /v1/subscription`      | —                                                                   | `subscription_ref`, the snapshot (§1.7), and commercial notices: `duplicate_payment`, `late_payment_honoured`, `payment_withheld`, `reversal_recorded`, `terms_held` (FR-41, FR-43)                                                           |
| `GET /v1/payments?cursor=`  | —                                                                   | Pages of `reference`, `paid_at`, `amount_minor`, `currency`, offer name and version, term covered, `classification`, reversals (FR-50, FR-60)                                                                                                 |


Rules:

- The tenant is the token's `org` only. An id belonging to another tenant answers `not_found` (SR-04, A22, A36).
- `POST` and `PUT` are idempotent by `client_request_id` per tenant (NFR-02).
- A new checkout needs a billing contact and the current terms version. `offer_version` must be the current sellable version, so a price change between viewing and opening is shown before paying (A8).
- Limits: 10 checkouts per tenant per hour and 60 requests per token.
- The token's `jti` is stored on the checkout and payment facts for traceability.

### 2.3 ABO errors

Body `{code, message, contract_version}`.


| Code                           | HTTP | When                                                                  |
| ------------------------------ | ---- | --------------------------------------------------------------------- |
| `unauthenticated`              | 401  | Token missing, invalid, expired or wrong audience                     |
| `forbidden_role`               | 403  | `role` is not `administrator`                                         |
| `not_found`                    | 404  | Unknown id, or an id of another tenant                                |
| `offer_unavailable`            | 409  | Offer retired or version superseded; the body includes the current version (FR-06, A21, A33) |
| `billing_contact_required`     | 409  | No billing contact yet                                                |
| `terms_not_accepted`           | 409  | `terms_version` is not current                                        |
| `invalid_request`              | 422  | Field validation failed                                               |
| `rate_limited`                 | 429  | Limits in §2.2                                                        |
| `provider_unavailable`         | 503  | The provider refused or timed out when creating the checkout          |
| `contract_version_unsupported` | 400  | `Abo-Contract-Version` missing or outside N and N−1; the body lists the accepted versions. Checked before authentication, so an outdated desktop gets this and not `unauthenticated` |


The operator console's `/ops/*` calls follow the same header and error rules.

## 3. Flutter and shared backend

### 3.1 RPCs

All are `SECURITY DEFINER` in `public`, delegating to `auth_internal`, keyed on `current_org_id()` (R-1). Every RPC takes `p_contract_version integer` as its first argument (§7). Results use the existing `rpc_result` envelope (`backend/supabase/migrations/20260516100000_auth_rbac_schema.sql:54-58`), extended with a `contract_version` field, except `issue_ai_token`, which keeps returning `text`: the token's `ver` claim states its version. A version outside the backend's accepted range answers the error `CONTRACT_VERSION_UNSUPPORTED` (`issue_ai_token` raises it). The product is pre-launch, so the unversioned signatures are dropped rather than kept alongside.


| RPC                            | Who                               | Returns                                                                                                      |
| ------------------------------ | --------------------------------- | ------------------------------------------------------------------------------------------------------------ |
| `issue_ai_token(p_contract_version)` | Members with an AI scope    | AI token (§2.1). Same name and return shape as today (`frontend/lib/core/ai/supabase_aat_mint_port.dart:22-30`), plus the version argument |
| `issue_billing_token(p_contract_version)` | `administrator` only   | `{token, abo_base_url, expires_at}`; errors `FORBIDDEN_ROLE`, `RATE_LIMITED` (20 per user per 10 minutes)     |
| `get_ai_status(p_contract_version)` | Every member                 | §3.2 status view                                                                                             |
| `get_ai_billing_status(p_contract_version)` | `administrator` only | Status view plus plan, dates, allowance figures, `queued_count`, `held_count`, `subscription_ref`, `abo_base_url` (FR-60, FR-66) |
| `request_ai_status_refresh(p_contract_version)` | `administrator` only | `{requested_at}`; starts an immediate pull (FR-62); at most once per 10 seconds per tenant               |


Removed: `get_ai_availability` and `set_ai_availability` (latest definitions `20260821120000_fix_get_ai_availability_security_definer.sql:4`, `20260905120100_set_ai_availability_rpc.sql:67`, `20260905120400_fix_set_ai_availability_created_by.sql:4`), and `enroll_installation_keypair`, `rotate_installation_key`, `revoke_installation_key` (`20260803140000_b1_review_resolution.sql:284,293,302`) with their `auth_internal` bodies. No RPC lets a clinic user write status (SR-07, SR-13).

### 3.2 Status fields and notice codes

`get_ai_status()` returns `available`, `state` (§1.7 states), `reason`, `days_left`, `band`, `notices[]`, `next_change_at`, `as_of`, `stale`, `platform_base_url`. It returns no prices, payments or references (FR-61).

Notice codes are a closed vocabulary: they are records, not UI strings (X-05). The desktop renders each code in an administrator form (with a renew action) or a staff form ("ask your administrator"), with no prices (FR-26, FR-27).


| Code                    | Raised when                                                                    |
| ----------------------- | ------------------------------------------------------------------------------ |
| `ends_soon`             | `days_left` is 7, 3 or 1 or fewer, with `queued_count = 0` (01 I-10)           |
| `in_grace`              | State `grace`; carries grace days left                                         |
| `allowance_low`         | Band 75 or 90 (FR-34, A29)                                                     |
| `allowance_exhausted`   | State `exhausted`                                                              |
| `lapsed`                | State `lapsed`                                                                 |
| `ended_reversed`        | State `reversed`                                                               |
| `suspended`             | Suspended flag                                                                 |
| `status_stale`          | `stale = true`                                                                 |


### 3.3 Read-time computation

For the tenant's projection row and the current time `now`:

1. No row: `state = none`, `available = false`.
2. Suspended: `available = false`, `state = suspended`.
3. Stored `active`: if `now < ends_at`, the state is `active`. Otherwise, if `queued_count > 0`, it is `active` (the successor's details arrive with the next event, within 2 minutes). Otherwise, if `now < grace_ends_at`, it is `grace`; otherwise `lapsed`.
4. Stored `grace`: `grace` while `now < grace_ends_at`, then `lapsed`.
5. Any other stored state is unavailable as stored.
6. `available` is true exactly for `active` and `grace`. `next_change_at` is the next of `ends_at` and `grace_ends_at` that is still in the future. `stale` is true when `feed_state.last_success_at` is more than 2 minutes old.

Because of rules 3 and 4, a lapse shows on time from stored dates alone, even when every vendor service is down (A10, A28).

### 3.4 Desktop behaviour

- **When to read status.** Every desktop calls `get_ai_status()` on app open, on resume (as `frontend/lib/app/app.dart:47-57` does today), after any AI denial with a coverage code, at `next_change_at`, and every 5 minutes. This contacts only the backend (FR-61). Administrators additionally use `get_ai_billing_status()`, the ABO API, and `/v1/coverage` for live allowance.
- **Denial display.** Denials are inline states, never dialogs (FR-64), extending the existing `AiDegradedView` pattern (`frontend/lib/features/ai/degraded/ai_degraded_view.dart:33-110`):


| Platform code                                                   | FR-65 class                   | Staff sees                                            | Administrator also sees     |
| --------------------------------------------------------------- | ----------------------------- | ----------------------------------------------------- | --------------------------- |
| `allowance_exhausted`, `coverage_lapsed`                        | Not paid, lapsed or used up   | "AI not available, contact your administrator"        | Renew or buy action         |
| `suspended`                                                     | Not paid, lapsed or used up   | Same                                                  | "Contact support" and the subscription reference |
| `forbidden_capability`                                          | Paid, nothing available       | "Not included in your clinic's AI plan"               | Plan name                   |
| `capability_disabled`, `provider_unavailable`                   | Paid, nothing available       | "AI temporarily unavailable"                          | Same                        |
| `coverage_unknown`, network failure, `status_stale`             | Platform unreachable          | "AI service unreachable"                              | Same                        |
| `concurrency_limited`, `rate_limited`                           | Safety limit (FR-09)          | "AI busy, try again shortly" with `retry_after`       | Same                        |
| `contract_version_unsupported` from the platform, the ABO or an RPC | App too old (NFR-09)      | "Update the app to use AI"                            | Same; billing screens show the same state |


### 3.5 Affected backend and frontend files

These are named so the contracts can be traced to code. They are not a task list.


| Area                         | Files                                                                                                                                                                                                                      |
| ---------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Backend issuer               | `auth_internal.issue_ai_token` (latest `20260905120300_fix_aat_lifetime_fallback.sql:4`): installation lookup `:67-74` and plaintext signing `:159` replaced; new migrations for §3.1 and the projection (03 §4)          |
| Backend feed puller          | New migration enabling `pg_cron` and `pg_net` (absent today) and the 30-second job                                                                                                                                         |
| Backend tests                | `backend/tests/ai_keystore_rls.sql`, `ai_token_issuer.sql`, `catalog/stage-02-availability-and-enroll.sql`, `catalog/stage-02-revoke-rotate-availability.sql`                                                               |
| Frontend status              | `frontend/lib/features/ai/availability/ai_availability_reader.dart:17-18` and `ai_availability.dart:11-15` read `get_ai_status`; `ai_degraded_mode.dart:18-51` and `frontend/lib/core/ai/taxonomy.dart:23-42` take the §4.2 codes |
| Frontend usage               | `frontend/lib/core/ai/usage_summary_client.dart:40-53` becomes a `/v1/coverage` client; the gauge in `ai_feature_host_page.dart:280-305` is shown to administrators only (FR-61)                                             |
| Frontend billing             | New administrator feature: offers, checkout with `url_launcher` (`frontend/pubspec.yaml:60`), billing contact, history; staff notice banner; strings in `frontend/lib/l10n/app_en.arb` and `app_ar.arb`                     |


## 4. Shared backend and desktops to AI Platform

### 4.1 Coverage feed

`GET /v1/feed/coverage?after=<feed_seq>&limit=<≤200>` with a feed token and `Aip-Contract-Version`.

Response: header `Aip-Contract-Version` and body `{contract_version, after, events[], next_after, has_more}`. Each event is `{event_id, feed_seq, org_id, installation_id, binding_epoch, clinic_seq, kind, at, snapshot}` (§1.7). `kind` is `grant_applied`, `grant_voided`, `term_activated`, `term_ended`, `term_held`, `term_released`, `grace_started`, `band_crossed`, `suspension_changed`, or `transfer` (03 §6.7). Pages are not signed: they travel over TLS to an audience-bound feed token, and the projection is display-only (01 §3.4). Each call updates `feed_consumer.last_pull_at`.

`readCoverageEvents` returns those same event objects. Beyond each event, its page fields are `after`, `next_after`, and `has_more` (§1.3). `contract_version` is the result envelope's field.

Backend pull cycle (pg_cron every 30 s; two-phase pg_net):

1. If `pending_request_id` has a response in `net._http_response`: require status 200 and a `contract_version` the backend accepts (a `contract_version_unsupported` answer raises the stale alert and keeps the cursor); require `after` = the stored cursor and ascending `feed_seq`. For each event, upsert `clinic_ai_coverage` only when `(binding_epoch, clinic_seq)` is greater than the stored pair (03 §4). Set the cursor to `next_after` and `last_success_at` to now. On any failure keep the cursor and count the failure.
2. Issue the next `net.http_get` with a fresh feed token and the backend's current feed version, and store its id. When `has_more` is true, the next cycle continues from the new cursor.

A 30-second cycle applies an event within about 60 seconds of it reaching D1, inside the 2-minute bound (01 I-7). A response older than 5 minutes is abandoned and re-requested (01 R-4).

### 4.2 Clinic routes and denial codes

Every clinic route (`/v1/requests`, `/v1/requests/{ref}`, `/v1/capabilities`, `/v1/coverage`) requires the `Aip-Contract-Version` request header and returns it on every response, including streamed ones, where it is sent before the first byte of the stream (§7).


| Route                         | Change                                                                                                                                                                                                 |
| ----------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `POST /v1/requests`           | New denial codes below; admission answers carry `term_id` internally                                                                                                                                   |
| `GET /v1/capabilities`        | Lists capabilities from the active term's plan snapshot, read from `coverage_mirror` by primary key without the TTL cache, so a just-paid clinic sees its plan at once (NFR-05)                          |
| `GET /v1/coverage`            | New, `role = administrator` only: `subscription_ref`, the live snapshot from the DO (read-only, no write), queued terms (plan and duration), and the last 12 terms with usage (FR-60, P-09)             |
| `GET /v1/usage`               | Removed; staff desktops call it today (`frontend/lib/features/ai/host/ai_feature_host_page.dart:148-152`), which FR-61 forbids                                                                          |



| Code                    | HTTP | Replaces                                                                   | Extra fields                    |
| ----------------------- | ---- | -------------------------------------------------------------------------- | ------------------------------- |
| `allowance_exhausted`   | 403  | `quota_exhausted` (`ai-platform/src/errors.ts:53-58`) for allowance         | —                               |
| `coverage_lapsed`       | 403  | `quota_exhausted` on a config miss (`src/admission/index.ts:612-619`)       | `coverage_reason`               |
| `coverage_unknown`      | 503  | —                                                                          | `retry_after`                   |
| `suspended`             | 403  | `installation_suspended` (`src/errors.ts:35-40`)                            | —                               |
| `concurrency_limited`   | 429  | `quota_exhausted` for concurrency (`src/admission/index.ts:471-483`)        | `retry_after`                   |
| `rate_limited`          | 429  | Unchanged                                                                  | Unchanged                       |
| `contract_version_unsupported` | 400 | —; checked before token verification                                 | `accepted_versions`             |


The `period_reset` supplementary field (`src/errors.ts:193-200`) is removed.

## 5. Provider port

### 5.1 Operations


| Operation           | Input                                                                                                                  | Output                                                                                         | Launch                     |
| ------------------- | ---------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------- | -------------------------- |
| `capabilities`      | —                                                                                                                      | `{methods, cancel_checkout, refunds, mandates, payouts, pending_notifications}`                 | Yes                        |
| `createCheckout`    | `checkout_id`, `reference`, `amount_minor`, `currency`, `item_name`, `payer {name, email, phone}`, `expires_in_s`, `return_url`, `notify_url` | `redirect_url`, `expires_at`                                   | Yes                        |
| `cancelCheckout`    | `checkout_id`                                                                                                          | `cancelled` or `unsupported`                                                                   | Paymob: `unsupported`      |
| `parseNotification` | Raw request (method, query, headers, body)                                                                             | `{authentic, events[]}`                                                                        | Yes                        |
| `inquire`           | `{checkout_id}` or `{payment_id}`                                                                                      | `{bound, transactions[]}`; `bound` means the provider order is the one stored at creation (FR-13) | Yes                     |
| `payoutLines`       | Uploaded report file                                                                                                   | `PayoutLine[]`                                                                                 | CSV import                 |
| `refund`            | `payment_id`, `amount_minor`                                                                                           | —                                                                                              | Stub, `unsupported` (X-01) |
| `chargeMandate`     | Mandate reference, amount                                                                                              | —                                                                                              | Stub, `unsupported` (X-04) |


The domain never sees a provider id. The adapter maps provider references to `checkout_id` and `payment_id` in its private tables (03 §2.11). Adding a provider means a new adapter, registry entry and `/notify/{provider}` route (X-03).

### 5.2 Normalised types


| Type          | Fields                                                                                                                                                              |
| ------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `ProviderTxn` | `kind` (`payment_succeeded`, `payment_failed`, `payment_pending`, `reversal`), `checkout_id`, `payment_id`, `amount_minor`, `currency`, `occurred_at`, `dedupe_key`, `reversal?` |
| `reversal`    | `{kind: refund, void, chargeback or unknown; amount_minor; cumulative_reversed_minor; is_full}`                                                                      |
| `PayoutLine`  | `kind`, `payment_id` (null if unknown), `gross_minor`, `fee_minor`, `net_minor`, `settled_at`                                                                        |


Confirmation (01 §3.3 step 2) is a domain rule over `inquire` output: `bound` is true; a `payment_succeeded` transaction exists; its `amount_minor` and `currency` equal the checkout snapshot. Anything else records the payment as `withheld_mismatch` or records nothing, and alerts.

### 5.3 Paymob adapter

Sources: [callbacks and HMAC](https://developers.paymob.com/paymob-docs/developers/webhook-callbacks-and-hmac), [intention API](https://github.com/paymobaccept/paymob-ai-integration-skill/blob/main/skills/paymob-integration/references/intention-api.md), [HMAC verification](https://github.com/paymobaccept/paymob-ai-integration-skill/blob/main/skills/paymob-integration/references/hmac-verification.md), [transaction inquiry](https://github.com/paymobaccept/paymob-ai-integration-skill/blob/main/skills/paymob-integration/references/transaction-inquiry.md). Items marked R-2 are spike-dependent. Paymob's API and callbacks are not ours to version: the adapter pins the paths and the HMAC field list it was written against and records its `adapter_version` on every evidence row (§7).


| Port operation      | Paymob mechanism                                                                                                                                                                                                                                                              |
| ------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `createCheckout`    | `POST /v1/intention/` with `Authorization: Token <secret key>`; `amount` in piastres; `currency` EGP; card integration only; one item; `billing_data` from the payer; `special_reference` = checkout `reference`; `expiration` = 1800 s; notification and redirection URLs. Stores the intention id, the `intention_order_id` and `client_secret`. Redirect to Unified Checkout with the public key and `client_secret` |
| `parseNotification` | Processed callback (POST, `type = TRANSACTION`): HMAC-SHA512 with the HMAC secret over the 20 documented fields in order, compared in constant time. The response callback (GET) is authentic-checked the same way but only schedules an inquiry |
| `inquire`           | Auth token from `POST /api/auth/tokens` with the API key, cached for its life. `POST /api/ecommerce/orders/transaction_inquiry` by the stored `order_id`; `GET /api/acceptance/transactions/{id}` for a known transaction. Whether order retrieval lists every transaction is R-2 |
| Order binding       | `bound` is true only if the inquiry's `order.id` equals the stored `intention_order_id`. `merchant_order_id` is not covered by the HMAC, so it is never trusted from a callback                                                                                               |
| Normalisation       | `success` and not `pending`, not refunded, not voided: `payment_succeeded`. Not `success` and not `pending`: `payment_failed`. `pending`: `payment_pending` (inquiry only; there is no pending callback). `is_refunded`, `is_voided`, or a child with `has_parent_transaction`: a `reversal` against the parent, with the cumulative amount taken from the inquiry because `refunded_amount_cents` is not HMAC-covered |
| `payment_id` input  | The successful transaction's `id`                                                                                                                                                                                                                                              |
| `payoutLines`       | Dashboard CSV export (one month per file); columns mapped to `PayoutLine`, with transaction ids looked up in `paymob_txn`                                                                                                                                                      |
| Never called        | Update Intention; any refund or void endpoint                                                                                                                                                                                                                                 |


## 6. AI Platform change list

Every path is under `ai-platform/`. Lines refer to the current code. Files not listed are unchanged: the `context`, `contracts`, `invocation`, `logger`, `prompt`, `prompt-artifacts.d.ts`, `provider`, `reference`, `router`, `stream`, `trace`, `validate` and `wall-clock-sleeper` sources.

### 6.1 Existing source files


| File                              | Change  | Detail                                                                                                                                                                                                                                                                                                                                                    |
| --------------------------------- | ------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `src/worker.ts`                   | Modify  | Remove the `/control/*` dispatch (`:1605-1626`) and `/v1/usage` (`:1589-1598`); add `/v1/coverage` and `/v1/feed/coverage`; check and echo `Aip-Contract-Version` on every `/v1/*` route before token verification (§7); export `VendorEntrypoint`. `Env`: drop `OPERATOR_BEARER_TOKEN` (`:124`); add the platform key, issuer id, Access and WebAuthn settings, `HEARTBEAT_URL`, the staging `DURATION_SCALE`, and the `send_email` binding. Replace `periodFromIso` (`:290-292`, `:619`) and the handoff settlement's `SELECT period_start FROM entitlement` (`:553-557`) with the admission's `term_id`; take the cost class from the term snapshot instead of the hardcoded values (`:983-984`); drop `minimumPlanTier` (`:1296`). `GatewayObject` (`:1487-1561`): new RPC kinds `grant`, `void`, `transferOut`, `transferIn`, `release`, `suspend`, `resume`, `inspect`, `settleFallback`, plus `alarm()`. `scheduled` (`:1699-1787`): remove the period-close branch (`:1768-1783`); replace grace reconcile (`:1721-1730`) with a `*/5` branch that drains fallback admissions, retries platform alerts and pings the heartbeat |
| `src/quota-do/index.ts`           | Rewrite | SQLite tables of 03 §3.1 in place of `QuotaDoState` (`:57-69`) and `EntitlementSnapshot` (`:32-47`); the rules of 03 §6. Removes `maybeResetPeriod` and `isQuotaExhausted` (`:263-292`); admission reserves (`:401-441`); denial and replay paths stop writing (`:375-418`). Keeps `EPHEMERAL_HORIZON_MS` and the concurrency constant (`:5-6`), with the limit now taken from the plan snapshot |
| `src/admission/index.ts`          | Modify  | Remove `mapEntitlementSnapshot` (`:148-166`); map the DO outcomes to §4.2 codes (`:461-483`, `:510-515`, `:612-619`); fallback (`:489-575`) follows 03 §6.5 using `coverage_mirror` and `fallback_admission`, replacing `GRACE_ADMISSION_CAP` (`:26`)                                                                                                         |
| `src/credit/index.ts`             | Modify  | `creditUsage` (`:207`) settles by reservation id; `reconcileGraceUsage` (`:264`) becomes the fallback drain; remove the 2-hour drop and zero-credit reconcile (`:20-23`, `:324-336`)                                                                                                                                                                       |
| `src/entitlement/index.ts`        | Modify  | Remove the tier and status checks (`:181-189`); keep kill switches (`:221-251`); the capability check reads the plan snapshot                                                                                                                                                                                                                           |
| `src/pipeline/index.ts`           | Modify  | Stage 3 (`:359`) pre-checks against `coverage_mirror`; stage 8 (`:445`) takes `term_id`, reservation id and snapshot from the DO; stage 15 settlement (`:629-661`) passes them on                                                                                                                                                                        |
| `src/identity/index.ts`           | Rewrite | `EnrolledKeyVerifier` (`:236-383`) becomes an issuer-token verifier (§2.1); `Principal` (`:14-25`) keeps `installationId`, now resolved from the binding; audience per route                                                                                                                                                                             |
| `src/config-cache/index.ts`       | Modify  | Remove the `installation_key`, `plan` and `entitlement` readers (`:228-233`, `:242-254`); add `issuer_key` and `tenant_binding` readers; coverage is never read through the cache (P-08)                                                                                                                                                                |
| `src/capability/index.ts`         | Modify  | `discover` (`:666-810`) reads the mirror snapshot instead of the entitlement (`:674-715`); remove the tier checks (`:248-251`, `:732-737`) and the `plan:` grant fallback (`:765-771`)                                                                                                                                                                    |
| `src/platform-vocabulary.ts`      | Modify  | Remove `PLAN_TIERS` (`:2-7`) and `planTierMeetsMinimum` (`:92-99`); rename the key-algorithm constant (`:11-12`) for issuer keys                                                                                                                                                                                                                        |
| `src/manifest/index.ts`           | Modify  | `minimumPlanTier` (`:32`) no longer required; ignored if present                                                                                                                                                                                                                                                                                        |
| `src/journal/index.ts`            | Modify  | `period` becomes `term_id` in `PostResponseInput` (`:61-73`) and the insert (`:409-423`), which becomes insert-or-ignore on `request_id` (03 §6.2); `authenticateGetRequest` (`:544-577`) uses the new verifier                                                                                                                                                                                                    |
| `src/discovery/index.ts`          | Modify  | New verifier (`:69-76`)                                                                                                                                                                                                                                                                                                                                 |
| `src/usage-summary/index.ts`      | Delete  | Replaced by `src/coverage-read/index.ts`                                                                                                                                                                                                                                                                                                                |
| `src/period-close/index.ts`       | Delete  | P-13, FR-53                                                                                                                                                                                                                                                                                                                                             |
| `src/rollup/index.ts`             | Modify  | Dimensions `{installation_id, term_id}` (`:35-37`, `:45-86`)                                                                                                                                                                                                                                                                                            |
| `src/dashboards/index.ts`         | Modify  | The rejection-rate query (`:166-192`) counts the §4.2 codes                                                                                                                                                                                                                                                                                              |
| `src/retention/index.ts`          | Modify  | `purgeByInstallationId` (`:287-359`) stops deleting `entitlement` and `installation` (`:348`, `:354`) and marks the installation `deleted`; the `installation_key` delete (`:345`) goes with the table; never touches the grant ledger, coverage events, transfers or DO storage (P-14)                                                                   |
| `src/errors.ts`                   | Modify  | §4.2 codes; remove `quota_exhausted` (`:53-58`) and `period_reset` (`:193-200`); rename `installation_suspended` (`:35-40`)                                                                                                                                                                                                                              |
| `src/adapter.ts`                  | Modify  | Supplementary fields `retry_after` and `coverage_reason`                                                                                                                                                                                                                                                                                               |
| `src/soft-threshold/index.ts`     | Modify  | Reads the allowance band from the admission answer                                                                                                                                                                                                                                                                                                      |
| `src/rate-limit/index.ts`         | Modify  | Guard-rejection counters use the new codes                                                                                                                                                                                                                                                                                                             |
| `src/support/index.ts`            | Modify  | Lookup also by subscription reference and `org_id`                                                                                                                                                                                                                                                                                                      |
| `src/pricing/index.ts`            | Keep    | Provider cost ledger is vendor cost, not commercial output (FR-53)                                                                                                                                                                                                                                                                                      |
| `src/control/index.ts`            | Delete  | HTTP dispatch (`:135-259`) replaced by `src/vendor/entrypoint.ts`                                                                                                                                                                                                                                                                                       |
| `src/control/auth.ts`             | Delete  | Shared bearer (`:26-51`), P-07                                                                                                                                                                                                                                                                                                                          |
| `src/control/http.ts`             | Delete  | HTTP-only helpers                                                                                                                                                                                                                                                                                                                                       |
| `src/control/entitle.ts`          | Delete  | Manual entitle and override (`:161`, `:406`), FR-91                                                                                                                                                                                                                                                                                                     |
| `src/control/credit-price.ts`     | Delete  | P-13                                                                                                                                                                                                                                                                                                                                                    |
| `src/control/lifecycle.ts`        | Modify  | Remove enroll, rotate and revoke-key (`:201-467`) and `INSTALLATION_KEY_TTL_DAYS` (`:30-37`); `handleSuspend`, `handleResume` and `handleDelete` (`:468`, `:521`, `:571`) become entrypoint methods writing the DO flag                                                                                                                                    |
| `src/control/plan.ts`             | Rewrite | Immutable `plan_version` publish and retire (HP) instead of create, update and delete                                                                                                                                                                                                                                                                  |
| `src/control/quota-inspect.ts`    | Rewrite | `inspectCoverage`: DO ledger plus mirror, in place of the entitlement read (`:58-71`)                                                                                                                                                                                                                                                                   |
| `src/control/support-purge.ts`    | Modify  | Purge becomes HP `deleteInstallation` and respects the retention rule above                                                                                                                                                                                                                                                                             |
| `src/control/cohort.ts`           | Modify  | Plan membership from `plan_version` instead of `entitlement` (`:277-278`)                                                                                                                                                                                                                                                                              |
| `src/control/audit.ts`            | Modify  | Actor is the Access email; records `assertion_sha256`                                                                                                                                                                                                                                                                                                  |
| `src/control/types.ts`            | Modify  | Types follow the entrypoint methods                                                                                                                                                                                                                                                                                                                    |
| `src/control/kill-switch.ts`, `routing-policy.ts`, `token-contract.ts`, `capability-lifecycle.ts` | Keep logic | Exposed as class-H entrypoint methods; `token-contract` adds `ver = "2"`                                                                                                                                                                                                         |


### 6.2 New source files


| File                              | Purpose                                                                                                   |
| --------------------------------- | --------------------------------------------------------------------------------------------------------- |
| `src/vendor/entrypoint.ts`        | `VendorEntrypoint`, the methods of §1.3 with their class checks                                           |
| `src/vendor/access.ts`            | Access JWT verification against the team certificates                                                     |
| `src/vendor/webauthn.ts`          | Assertion and attestation verification (§1.5); a thin wrapper over the shared package                     |
| `src/vendor/canonical-json.ts`    | Re-exports RFC 8785 canonicalization and hashing from the shared package                                  |
| `src/vendor/contract-version.ts`  | Per-channel accepted versions and the `contract_version_unsupported` answer, from the shared package (§7) |
| `src/coverage/engine.ts`          | Pure placement, boundary, reservation, exhaustion and grace rules (03 §6), used by the DO                 |
| `src/coverage/calendar.ts`        | Month and day arithmetic with end-of-month clamping; the staging `DURATION_SCALE` (03 §6.1)               |
| `src/coverage/grant-verify.ts`    | Envelope validation (§1.4), ceilings, velocity check                                                      |
| `src/coverage/transfer.ts`        | Binding re-creation, transfer package with `origin_grant_id` lineage, and saga steps                      |
| `src/coverage-read/index.ts`      | `GET /v1/coverage`                                                                                        |
| `src/feed/index.ts`               | `GET /v1/feed/coverage` (unsigned pages, §4.1)                                                            |
| `src/signing/index.ts`            | Platform key: grant and void receipts                                                                     |
| `src/alert/index.ts`              | `send_email` delivery, `platform_alert` dedupe and retry, heartbeat ping                                  |


The shared package is `packages/vendor-contracts/` at the repository root, a `file:` dependency of both `ai-platform/` and the ABO. It holds RFC 8785 canonical JSON, Ed25519 compact JWS signing and verification on WebCrypto (§1.1), WebAuthn verification, the message types of §1 and §2, and the version constants of §7. The ABO's console uses the same WebAuthn and canonical-JSON code to build the operation object (§1.5), so both sides hash the same bytes. The backend cannot import it; its SQL verifies nothing that the package signs (01 §3.4).


### 6.3 D1 migrations

New files follow `migrations/20260911200000_invoice.sql`. Existing migrations are not edited. The product is pre-launch, so tables are dropped rather than migrated.


| New migration                                   | Content                                                                                                                                                                                                     |
| ----------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `migrations/20261001120000_drop_invoicing.sql`  | Drop `invoice` (`20260911200000_invoice.sql:1-10`) and `credit_price` (`20260911120000_plan_catalogue.sql:11-17`)                                                                                            |
| `migrations/20261001120100_issuer_identity.sql` | Create `issuer_key`, `service_key`, `tenant_binding` (with `epoch` and a unique active binding per `org_id`); drop `installation_key` (`20260731120000_platform_schema.sql`). `installation` is unchanged: its `status` already accepts `deleted` |
| `migrations/20261001120200_coverage_ledger.sql` | Create `plan_version`, `ceiling_policy`, `coverage_mirror`, `coverage_event`, `grant_ledger`, `grant_void`, `transfer`, `transfer_step`, `fallback_admission`, `feed_consumer`, `platform_alert`; drop `plan`, `entitlement` (with `20260821130000_entitlement_installation_unique.sql`) and `grace_admission_queue` (`20260821120000_grace_admission_queue.sql`); append-only triggers on the ledger tables; `grant_ledger` carries `origin_grant_id`; `coverage_mirror` and `coverage_event` carry `binding_epoch` |
| `migrations/20261001120300_usage_term.sql`      | Rebuild `usage_event` with `term_id` in place of `period` and a unique index on `request_id`, keeping the indexes from `20260805120000_f3_retention_indexes.sql`; reset `usage_rollup` dimensions |
| `migrations/20261001120400_operator_security.sql` | Create `operator_credential`, `assertion_used`; add `assertion_sha256` to `control_audit`; insert `token_contract` version `2` and retire `1` (`20260803120000_token_contract.sql`)                       |


### 6.4 wrangler.toml


| Line today                     | Change                                                                                                                                              |
| ------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------- |
| `:9-10` crons                  | Keep `0 3 * * *` and `0 4 * * *`; remove `0 5 1 * *`; add `*/5 * * * *`                                                                               |
| `:17-19` DO class              | Unchanged (already SQLite-backed); the in-DO schema migrates on first access                                                                         |
| `:24-29`, `:62-67`, `:100-105` vars | Remove `OPERATOR_ID`; add `ISSUER_ID`, `ACCESS_TEAM_DOMAIN`, `ACCESS_AUD`, `WEBAUTHN_RP_ID`, `WEBAUTHN_ORIGIN`, `HEARTBEAT_URL`; `DURATION_SCALE` in staging only (absent in production). `CONFIG_CACHE_TTL_MS` stays for non-coverage configuration. `HEARTBEAT_URL` holds the monitor URL that the `*/5` cron pings (02 §5) |
| Top level (absent today)       | `workers_dev = false`, `preview_urls = false`; `[observability] enabled = true` (02 §1.1); a `send_email` binding with the verified destination; secret `PLATFORM_SIGNING_KEY` in place of `OPERATOR_BEARER_TOKEN` |
| `:44-57`, `:82-95`, `:120-133` rate limits | Unchanged (FR-09)                                                                                                                       |


### 6.5 Tests

Paths are under `ai-platform/test/`.


| Change   | Files                                                                                                                                                                                                                                                                                                                                                      |
| -------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Delete   | `period-close.test.ts`, `price-list-activation.test.ts`, `entitle-grant.test.ts`, `e2e/stage-03-enroll-validation.test.ts`, `e2e/stage-03-lifecycle-rotate.test.ts`, `e2e/stage-04-entitle-auth-period.test.ts`, `e2e/stage-04-entitle-quota-grants-validation.test.ts`                                                                                      |
| Rewrite  | `identity.test.ts`, `config-readers.test.ts`, `config-cache.test.ts`, `quota-do.test.ts`, `admission-credit.test.ts`, `quota-inspect.test.ts`, `entitlement.test.ts`, `plan-catalogue.test.ts`, `usage-summary.test.ts` (becomes coverage-read), `control.test.ts` (becomes vendor-entrypoint), `retention.test.ts`, `support-purge.test.ts`, `taxonomy.test.ts`, `error-body.test.ts`, `rollup-reconciliation.test.ts`, `journal.test.ts`, `discovery-http.test.ts`, `capability.test.ts`, `migrations.test.ts`, `worker-entry.test.ts`, the `system/*` interplay tests and the `e2e/stage-*` tests that enroll or entitle through `/control/*`; the e2e harness `e2e/harness/control.ts` and `e2e/harness/env.ts` (they drive `/control/*` with `OPERATOR_BEARER_TOKEN`) become a harness that calls `VendorEntrypoint` with test Access JWTs and test passkey assertions, and mints issuer tokens with a test issuer key |
| Add      | Coverage engine and calendar, including grace exhaustion and the staging scale; grant verification, ceilings and key-state answers (including `unknown_kid`); void tombstones and reversal through transfer lineage; WebAuthn and Access verification; feed epoch ordering; transfer saga, `awaiting_transfer` and `held_for_transfer`; contract versions N, N−1 and unsupported on every route and entrypoint method (§7); fallback drain and `request_id` dedupe; a concurrency test for A34 that also measures rows written per AI request against the budget (01 R-7)                                                                                                       |
| Config   | `ai-platform/vitest.e2e.config.ts` and `vitest.workers.config.ts` drop the `OPERATOR_BEARER_TOKEN` binding and bind the test issuer key, Access settings and `DURATION_SCALE` |


### 6.6 Other affected paths

Outside the platform source, these paths depend on what the change removes. They are named so nothing is left pointing at `/control/*` or installation keys; they are not a task list.


| Path                                           | Why it is affected                                                                                                                  | Outcome                                                                                           |
| ---------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------- |
| `ai-platform-viewer/`                          | About 20 files call `/control/*` with the shared bearer, and its clinic pages sign with installation keys                          | Its control pages are removed; the ABO console replaces them (FR-91). Clinic-route pages use issuer tokens and send `Aip-Contract-Version` |
| `ai-platform/scripts/bootstrap-routing-policy.sh` | Seeds the routing policy through `/control/*`                                                                                    | Replaced by the console's routing-policy action (class H)                                         |
| `docs/architecture/ai-platform/`               | Describes installation keys, entitlements, periods and `/control/*`                                                                  | Marked superseded where this design changes them, with a link here                                |
| `frontend/` AI and billing clients              | Every platform, ABO and RPC call                                                                                                    | Send the channel version (§7); render `contract_version_unsupported` as the update state (§3.4)  |


## 7. Contract versioning

Every request and every response between the desktop app, the ABO console, the ABO, the shared backend and the AI Platform carries a contract version, so either side of a channel can deploy first (NFR-09, X-10).

### 7.1 Channels

Each channel has one integer version, starting at 1 at launch. Tokens keep their own `ver` claim (`"2"`, §2.1).


| Channel                                              | Where the version travels                                                                                  | Refusal                                                                  |
| ---------------------------------------------------- | ---------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------ |
| Desktop → ABO clinic API `/v1/*` (§2.2)              | `Abo-Contract-Version` request and response header; `contract_version` in every response body              | HTTP 400 `contract_version_unsupported`                                   |
| ABO console → ABO `/ops/*`                           | Same as the clinic API. The console ships with the ABO; the check catches a browser tab left open across a deploy | Same; the console asks for a reload                                  |
| Desktop → backend RPCs (§3.1)                        | `p_contract_version` argument; `contract_version` in `rpc_result`                                          | Error `CONTRACT_VERSION_UNSUPPORTED`                                     |
| Desktop → platform clinic routes (§4.2)              | `Aip-Contract-Version` request and response header, sent before the first byte of a stream; `contract_version` in JSON bodies | HTTP 400 `contract_version_unsupported`                   |
| Backend feed puller → platform feed (§4.1)           | `Aip-Contract-Version` request and response header; `contract_version` in the page                         | HTTP 400; the puller keeps its cursor and the stale alert fires          |
| ABO → `VendorEntrypoint` (§1)                        | `contract_version` in every argument object and every result                                               | `rejected` with `contract_version_unsupported`                           |
| Platform Worker → per-clinic DO RPC                  | `contract_version` in every call and answer. The DO accepts N and N−1 and answers in the version the call used, so the current version is echoed. They ship in one deployment, but a gradual rollout can pair an old Worker with a new DO | Missing or outside N and N−1: `rejected` with `contract_version_unsupported` and `accepted_versions`. The check runs before authentication and before any write, so nothing changes. The Worker maps that refusal to `coverage_unknown` for the clinic |
| Browser return from Paymob → ABO `/return/{provider}` | `v` query parameter on the `return_url` the ABO sends at checkout creation                                | None: the page is UX only, so an unknown `v` still schedules an inquiry and shows a neutral page |
| ABO ↔ Paymob API and `/notify/{provider}`            | Provider-controlled. The adapter pins the paths and HMAC field list it was written for and records `adapter_version` on each evidence row (§5.3) | A shape the adapter cannot parse is an A23 alert |
| Tokens (AI, billing, feed)                           | `ver` claim; the platform checks `token_contract`, the ABO its own accepted list                           | `unauthenticated`                                                        |


The heartbeat ping and `send_email` alerts carry no contract payload and are out of scope.

### 7.2 Rules

- A receiver accepts the current version N and the previous N−1 of each channel it receives, and answers in the version the request used.
- A missing version, or one outside N and N−1, gets `contract_version_unsupported` with `accepted_versions`. The check runs before authentication and before any write, so nothing changes.
- A sender that receives an answer in a version it does not know treats it as `contract_version_unsupported`.
- Readers ignore unknown fields. Adding an optional request field or a new response field keeps the version. Removing or renaming a field, or changing the meaning of a field, code, state or notice, needs a new version.
- Stored payloads (grant envelopes, receipts, snapshots, facts, work-row payloads) keep the `contract_version` they were written in and are never rewritten. Readers support every version still present in storage. Signed objects include the version, so it cannot change after signing.
- A retried work row resends its stored envelope in its original version.
- The version constants live in `packages/vendor-contracts/`, which both Workers import. The backend keeps its copy in `ai_internal.app_settings` (`ai.contract_versions`), the desktop in `frontend/lib/core/contract_versions.dart`. A contract test fails if either copy differs from the package.

### 7.3 Changing a version

1. Deploy every receiver of the channel so it accepts N and N+1. A receiver drops N−1 in the same deploy only if the conditions below already hold for N−1.
2. Switch the senders to N+1.
3. Drop N on the receivers once its conditions hold:
   - Vendor-internal channels (ABO → platform, Worker → DO, feed): every sender is deployed on N+1 and no open work row still holds a payload in N.
   - Desktop-facing channels (ABO clinic API, RPCs, platform clinic routes): the minimum supported desktop version sends N+1. Desktops below it show the "update the app" state (§3.4), never an error dialog.

