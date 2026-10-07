# AI Billing Orchestrator — Operations, Failure Modes and Traceability

**Status:** Phase 2 design. **Date:** 2026-10-01. Requirement IDs refer to the [seed](00-abo-requirements-seed.md); "01 §n" to "04 §n" to the [decision memo](01-abo-design-decisions.md), [architecture and threat model](02-abo-architecture-and-threat-model.md), [data model](03-abo-data-model-and-lifecycle.md) and [contracts](04-abo-contracts.md).

## Table of Contents

1. [Scheduled work](#1-scheduled-work)
2. [Alerts](#2-alerts)
3. [Operator console](#3-operator-console)
   - [Views](#31-views)
   - [Actions](#32-actions)
   - [Reconciliation](#33-reconciliation)
   - [Daily digest](#34-daily-digest)
4. [Failure modes and recovery](#4-failure-modes-and-recovery)
5. [Rebuild procedures](#5-rebuild-procedures)
6. [Staging and launch](#6-staging-and-launch)
   - [Staging profile](#61-staging-profile)
   - [Launch conditions](#62-launch-conditions)
   - [Delivery sequence](#63-delivery-sequence)
7. [Operating cost and moving parts](#7-operating-cost-and-moving-parts)
8. [Acceptance walkthrough](#8-acceptance-walkthrough)
9. [Traceability matrix](#9-traceability-matrix)
10. [Unmet and partly met requirements](#10-unmet-and-partly-met-requirements)

---

## 1. Scheduled work

Every scheduled query is index-backed (01 §3.3). Each job is idempotent, so a repeated or overlapping run is harmless (NFR-02). All provider inquiries, from sweeps and work rows alike, draw on one per-minute budget set from Paymob's rate limit (01 §3.3, R-2); work rows for confirmation and grants go first.


| System      | Schedule                   | Job                                                                                                                                                                                        |
| ----------- | -------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| ABO         | Inline (`waitUntil`)       | First attempt of every new work row                                                                                                                                                        |
| ABO         | Every minute               | Due work rows by `(state, next_attempt_at)`, at most 50 per run; checkout sweeps (+2, +5, +10, +20 min, then every 10 min to expiry, then widening to 7 days); read platform coverage events; evaluate alert conditions; send due alerts; export pending facts to R2; heartbeat ping |
| ABO         | Hourly                     | Reversal inquiry of every payment in its first 7 days or whose grant is not yet applied; comparison of the platform's issuer keys with the ABO's pinned `ISSUER_KEYS`, and of `listOperatorCredentials` with the ABO's last-seen operator-credential list (AL-22); check that the ABO's signing `kid` is active (`listServiceKeys`, AL-23). That last-seen list is each `{credential_id, public_key_cose, alg}` the ABO stored from the `detail` of its own `ok` `registerOperatorCredential` call, including bootstrap — the operation AL-13 announces. The platform's `send_email` is not an intake, and this comparison adds no new read |
| ABO         | Every 6 hours              | Reversal inquiry of every payment that funds an active, grace, queued or held term                                                                                                        |
| ABO         | Daily 06:00 UTC (`scheduled()`, `0 6 * * *`) | Weekly reversal inquiry of all other paid transactions up to 180 days old, one seventh each day, spread across the day; reconciliation (§3.3); R2 lock check; key-expiry check; digest (§3.4); heartbeat ping; housekeeping (03 §8): delete completed work rows and sent alerts older than 90 days, and invalid-HMAC samples older than 30 days; commercial facts are not deleted |
| AI Platform | DO alarm                   | Next term boundary, and outbox shipping (03 §6.7)                                                                                                                                          |
| AI Platform | Every 5 minutes            | Drain `fallback_admission`; retry `platform_alert`; heartbeat ping                                                                                                                         |
| AI Platform | `0 3 * * *`, `0 4 * * *`   | Retention purge and rollup, as today (`ai-platform/src/worker.ts:1733-1767`), keyed by `term_id`                                                                                          |
| Backend     | pg_cron every 30 s         | Two-phase feed pull (04 §4.1)                                                                                                                                                              |
| External    | Hourly                     | Audit-log watcher (02 §4.4); the heartbeat monitor alerts on any missing ping                                                                                                               |


## 2. Alerts

Alerts go through `send_email` (02 §5), deduplicated by `alert_key` and repeated at the stated interval while the condition holds (NFR-04). Every alert also appears in the digest.


| #     | Condition                                                                  | Raised by   | Repeat       | Requirement             |
| ----- | -------------------------------------------------------------------------- | ----------- | ------------ | ----------------------- |
| AL-01 | A work row open for more than 5 minutes                                    | ABO         | Hourly       | G3, NFR-04              |
| AL-02 | 3 or more HMAC failures within 15 minutes                                  | ABO         | Hourly       | A23                     |
| AL-03 | A payment confirmed by inquiry with no verified callback                   | ABO         | Once         | A3, A23                 |
| AL-04 | The platform answers `transient` or cannot be reached for 5 minutes        | ABO         | Hourly       | A4                      |
| AL-05 | Amount, currency or order mismatch; payment withheld                       | ABO         | Once         | FR-16                   |
| AL-06 | Reversal detected or recorded                                              | ABO         | Once         | FR-43                   |
| AL-07 | Grant or reversal void parked (`conflict` or `rejected`)                   | ABO         | Hourly       | NFR-03                  |
| AL-08 | Late payment honoured on an expired or cancelled checkout                  | ABO         | Once         | G3                      |
| AL-09 | Payment classified `likely_duplicate`                                      | ABO         | Once         | FR-41                   |
| AL-10 | Reconciliation finding (§3.3)                                              | ABO         | Daily        | FR-81                   |
| AL-11 | Any grant applied: paid, complimentary, term adjustment or transfer; non-paid ones marked for attention. The body carries the decoded operation and its target (02 AD-8) | AI Platform | Once | SR-23 |
| AL-12 | Ceiling override used                                                      | AI Platform | Once         | SR-24                   |
| AL-13 | Issuer key, service key or operator credential registered, retired, or revoked; bootstrap credential. The body carries the decoded operation and its target | AI Platform | Once | SR-11, SR-25 |
| AL-14 | A key is within 30 days of `not_after`                                     | ABO         | Daily        | A25                     |
| AL-15 | The backend has not pulled the feed for 5 minutes (`feedConsumerHealth`)   | ABO         | Hourly       | FR-63, 01 R-4           |
| AL-16 | R2 bucket lock missing, or fact export more than an hour behind            | ABO         | Daily        | RC-03                   |
| AL-17 | Paid-grant velocity above the 04 §1.4 thresholds                           | AI Platform | Hourly       | 02 AD-8                 |
| AL-18 | Installation deleted with coverage remaining; binding held for transfer (03 §5.4) | AI Platform | Daily while held | A24              |
| AL-19 | Suspension, resume or kill-switch change                                   | AI Platform | Once         | FR-74                   |
| AL-20 | Tenant-binding creation above 50 per day                                   | AI Platform | Daily        | 04 §2.1                 |
| AL-21 | Heartbeat missing, or audit event: production deploy, secret change, D1 export, Access policy edit | External | Per event | NFR-04, A26 |
| AL-22 | The platform's issuer keys differ from the ABO's pinned `ISSUER_KEYS`, or `listOperatorCredentials` returns an active `{credential_id, public_key_cose, alg}` that is absent from the ABO's last-seen list. The ABO fills that list only from the `detail` of its own `ok` `registerOperatorCredential` calls, including bootstrap (the operation AL-13 announces). A credential still `pending` at register time is stored then, so its later promotion to `active` is not a new appearance. The platform's `send_email` is not that intake | ABO | Hourly | SR-11, 02 AD-9 |
| AL-23 | The ABO's signing `kid` is not active on the platform; `grant` and `reverse` work is paused until it is | ABO | Hourly | NFR-04, 02 §6 |

## 3. Operator console

The console is on `ops.<vendor-domain>`, behind Access (02 §1.4). No routine task needs SQL (G7).

### 3.1 Views

One clinic page, found by subscription reference, `org_id`, billing email, or checkout, payment or grant reference (FR-70). It shows:

- the live coverage from `inspectCoverage`: terms, grants, reservations and suspension;
- checkouts with their events; payments with classification and disposition; reversals; grant requests with outcomes and receipts;
- operator actions on this clinic, and open findings and alerts.

Global views list parked work, open findings, recent grants by source and by credential, payout imports, and key and credential registries.

### 3.2 Actions

HP actions run the passkey ceremony in the console. "Verified by" says which system checks the evidence; the other system's check is only for UX.


| Action                                          | Class | Verified by | Requirement         |
| ----------------------------------------------- | ----- | ----------- | ------------------- |
| Retry parked work                               | H     | ABO         | FR-71               |
| Cancel an open checkout                         | H     | ABO         | FR-71               |
| Import a payout CSV; resolve a finding          | H     | ABO         | FR-80               |
| Record a manual chargeback                      | HP    | ABO         | FR-44, A18          |
| Release a withheld payment                      | HP    | ABO         | FR-16               |
| Publish or retire an offer or terms version     | HP    | ABO         | FR-01, FR-06        |
| Suspend or resume a clinic; kill switches; routing | H  | AI Platform | FR-74               |
| Complimentary grant; term adjustment            | HP    | AI Platform | FR-32, FR-35, A20   |
| Ceiling override (second assertion)             | HP    | AI Platform | SR-24               |
| Transfer or re-create identity; release held terms; void a grant | HP | AI Platform | FR-72, SR-25, 01 I-3 |
| Publish or retire a plan version; set the ceiling policy | HP | AI Platform | FR-01, SR-24     |
| Register, retire, or revoke an issuer key; register or revoke a service key or operator credential | HP | AI Platform | SR-11, SR-25 |
| Delete an installation                          | HP    | AI Platform | A24                 |
| Erase a tenant's payer contact data and raw provider bodies (03 §2.3) | HP | ABO   | 01 R-9              |


Every action writes `operator_action` in the ABO with the Access email as actor (FR-73). When the AI Platform verifies the action, that class-H or class-HP call writes `control_audit` with the Access email as `actor` (and `assertion_sha256` on HP), the audit every H/HP call already records. When the ABO verifies the action, the ABO writes `control_audit` by calling class-H `recordOperatorAction` on `VendorEntrypoint` after it commits `operator_action`. The arguments are `access_jwt` plus `action`, `subject`, and `action_id` from that row. The call inserts one `control_audit` row and leaves every other platform table unchanged: `actor` and `operator_id` are the Access email, `action` is the `action` argument, `target` is the `action_id`, and `assertion_sha256` is null. A repeated `action_id` returns `ok` and inserts no second row. `ok` has an empty `code`, an empty `detail`, and no `receipt`. A missing, expired, or wrong-`aud` Access JWT is `rejected` with code `unauthenticated` and inserts no row. Retry parked work and cancel an open checkout are ABO-verified, so they use this call. Cancel an open checkout has this call as its only platform call.

**Compromise response (SR-25):** revoke the suspect credential from another credential; list grants by credential and window (`listGrantsForVoid`); void each one; revoke Access sessions; rotate any machine key involved (02 §6).

### 3.3 Reconciliation

Runs daily, and again after each payout import (FR-80, FR-81). Each failed check writes a `finding` and raises AL-10.


| Check                                                                                         | Finding kind                    |
| --------------------------------------------------------------------------------------------- | ------------------------------- |
| Every payment with disposition `grant` has an `applied` outcome within 15 minutes             | `payment_without_grant`         |
| Every paid platform grant (`listGrants`) has `grant_id = H(payment_id)` of an ABO payment     | `grant_without_payment`         |
| Every complimentary platform grant matches an ABO `operator_action`                           | `grant_without_operator_action` |
| Every transfer grant matches an HP `beginTransfer` `operator_action` and the `transferOut` package it came from | `transfer_without_authorisation` |
| Every full reversal of a payment has a void receipt or tombstone, unless its effect is `none`  | `reversal_not_applied`          |
| Every payout payment line matches a payment by `payment_id` and amount                         | `payout_unmatched`              |
| Every payment settled more than 7 days before the end of an imported period appears in it      | `payment_not_in_payout`         |
| Every payout refund or chargeback line has a recorded reversal                                 | `unrecorded_reversal` (A18)     |
| Every HMAC-valid success callback was confirmed by an inquiry                                  | `callback_without_confirmation` |
| For clinics with events in the last day, the feed snapshot equals `getCoverage`                | `feed_divergence`               |
| Every `grant_outcome` receipt (`applied` or `already_applied`) equals the `receipt` `listGrants` returns for that `grant_id` | `receipt_mismatch` (AD-15) |


### 3.4 Daily digest

Proves the jobs are alive (NFR-04) and lists every grant (SR-23). It contains:

- 24-hour counts of checkouts, payments by classification, grants by source, reversals and alerts;
- every grant; complimentary, adjustment and transfer grants with operator, reason, length and allowance;
- open findings, parked work and open alerts;
- the last run time of each scheduled job, including the backend's last feed pull;
- the R2 lock status and export lag, and keys expiring within 30 days;
- per channel, the contract versions received and the count of `contract_version_unsupported` answers, which show when an old version can be dropped (04 §7.3).

## 4. Failure modes and recovery

Recovery never needs database surgery (G3, NFR-01).


| #     | Failure                                              | Detection               | Automatic behaviour                                                                                                               | Operator step                                            |
| ----- | ---------------------------------------------------- | ----------------------- | --------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------- |
| FM-01 | ABO crashes after receiving a callback               | AL-01 if a row stalls   | The callback was answered with 5xx or the row is open; the sweep inquires within 2–20 minutes                                     | None                                                     |
| FM-02 | Callback lost or delayed (A3)                        | AL-03                   | Checkout sweep finds the payment by inquiry                                                                                       | None                                                     |
| FM-03 | HMAC verification fails for every callback (A23)     | AL-02                   | Sweeps keep confirming by inquiry                                                                                                 | Fix the adapter or secret; deploy                        |
| FM-04 | Platform unreachable or failing (A4)                 | AL-04 hourly            | Grant rows retry with backoff up to 15 minutes, forever; the term starts at activation (01 I-2)                                    | None                                                     |
| FM-05 | Platform answers `conflict` or `rejected`            | AL-07                   | Row parked                                                                                                                        | Inspect; fix the cause; retry                            |
| FM-06 | One clinic's DO unavailable                          | Platform logs           | Bounded fallback (03 §6.5); drained later                                                                                          | None                                                     |
| FM-07 | ABO D1 unavailable                                   | AL-01, AL-21 heartbeat  | Callbacks get 5xx; sweeps recover once D1 returns                                                                                 | None                                                     |
| FM-08 | ABO R2 unavailable                                   | AL-01                   | Evidence write fails, so the callback gets 5xx and nothing is enqueued; sweeps recover                                           | None                                                     |
| FM-09 | Paymob API down                                      | AL-01                   | Checkout creation answers `provider_unavailable`; inquiries retry                                                                 | None                                                     |
| FM-10 | Backend pull stops (pg_cron or pg_net)               | AL-15; `stale` in status | Enforcement is unaffected; dates still evaluate at read time                                                                     | Restart the job                                          |
| FM-11 | Supabase down                                        | Clinic app down (C-04)  | Payments already made still provision (the ABO and platform do not depend on the backend); status catches up on return           | None                                                     |
| FM-12 | Cloudflare down                                      | Heartbeat (AL-21)       | Nothing runs; on return, sweeps and alarms catch up; lapses already due apply on the next admission                              | None                                                     |
| FM-13 | Bad ABO deploy                                       | AL-01, AL-07            | Rows stay open or parked; no fact is lost                                                                                         | Roll back; retry parked rows                             |
| FM-14 | Bad platform deploy                                  | AL-04, AL-07            | Grants retry                                                                                                                      | Roll back                                                |
| FM-15 | Two runners pick the same work row                   | —                       | The lease update admits one; the platform deduplicates by `grant_id`                                                              | None                                                     |
| FM-16 | Alert email not delivered                            | Missing digest; external heartbeat | `alert` rows retry                                                                                                    | Check Email Routing                                      |
| FM-17 | Issuer key nearing expiry (A25)                      | AL-14                   | —                                                                                                                                 | Rotate (02 §6)                                           |
| FM-18 | Paymob HMAC secret rotated in the dashboard          | AL-02                   | As FM-03                                                                                                                          | Update the secret                                        |
| FM-19 | ABO data loss or bad restore                         | AL-16, reconciliation   | —                                                                                                                                 | §5.1                                                     |
| FM-20 | Platform D1 or DO state loss                         | Reconciliation, AL-10   | —                                                                                                                                 | §5.2, §5.3                                               |
| FM-21 | ABO fails partway through a step                     | AL-01 if a row stalls   | Each step commits in one D1 batch (03 §2.9), so either all of its facts and its next work row exist or none do; the row is retried | None                                                     |
| FM-22 | `getCoverage` fails while a checkout opens           | Logs; AL-04 if it persists | The checkout uses `coverage_view` and records `coverage_source = view` (03 §2.4); the sale proceeds                            | None                                                     |
| FM-23 | Installation deleted with paid time left             | AL-18                   | Binding `held_for_transfer`: AI refused with `transfer_pending`, grants wait as `transient`, no second binding (03 §5.4)          | `beginTransfer`, or void the remaining grants            |
| FM-24 | ABO signing key not registered or revoked on the platform | AL-23              | `grant` and `reverse` work pauses; nothing is parked                                                                              | Register the key or deploy the right secret (02 §6)      |
| FM-25 | One side deployed with a contract version the other does not accept | `contract_version_unsupported` answers; AL-07 or AL-15 by channel | Nothing is written; the ABO parks the row, the feed puller keeps its cursor | Deploy the receiver first (04 §7.3), or roll back; retry parked rows |


## 5. Rebuild procedures

These satisfy RC-04. Each ends with a clean reconciliation run.

### 5.1 ABO

1. Within 30 days of the damage: restore D1 with Time Travel to a point before it.
2. Otherwise: create an empty D1, replay the `ledger/` NDJSON facts in `fact_seq` order (inserts pass the append-only triggers), then recompute the status tables.
3. Fill the gap after the last exported fact: re-inquire every checkout and payment reference known to the rebuilt set, and every transaction in the provider's dashboard export for the gap window.
4. Compare with the platform's `listGrants`. A paid grant with no payment is re-derived from the provider inquiry; a payment with no grant gets a grant row (its `grant_id` is deterministic, so the platform answers `already_applied`).

### 5.2 A clinic's DO

1. Load the clinic's last `coverage_event` snapshot (its terms, positions, usage, holds, suspension and epoch) into an empty DO.
2. Apply, in order, every later `grant_ledger` and `grant_void` row and every later hold, release, suspension and transfer event.
3. Re-apply usage recorded after the snapshot from `usage_event` by `term_id`, including shipped `usage_adjustment` rows; `request_id` uniqueness prevents double counting. Retention keeps these rows while their term is unended (03 §8).
4. Compare the result with `coverage_mirror` and alert on any difference. Reservations in flight at the loss are forfeited to the clinic's benefit.

### 5.3 Platform D1

Restore with Time Travel within 30 days. Otherwise rebuild `grant_ledger` and `grant_void` from the R2 `grant-ledger/` objects. Then ask every DO for a fresh snapshot event (an H method run once per installation), which also rebuilds `coverage_mirror`.

### 5.4 Backend projection

Reset `feed_state.cursor` to 0. `coverage_event` is never purged, so the replay reproduces every clinic's latest snapshot.

## 6. Staging and launch

### 6.1 Staging profile

Staging runs the full lifecycle in compressed real time (NFR-07). Offers use the production units and validation; the staging platform's `DURATION_SCALE` maps 1 month to 30 minutes and 1 day to 1 minute (03 §6.1). The Paymob test integration supplies test cards.


| Test offer          | Offer term | Runs for   | Grace (7 days) | Allowance   | Covers                                                                        |
| ------------------- | ---------- | ---------- | -------------- | ----------- | ----------------------------------------------------------------------------- |
| "Monthly" test      | 1 month    | 30 minutes | About 7 minutes | 20 credits | Purchase, early renewal, lapse, grace, reactivation, exhaustion with and without a prepaid term |
| "Quarterly" test    | 3 months   | 90 minutes | About 7 minutes | 60 credits | Purchase for the quarterly length                                             |
| "Annual" test       | 12 months  | 6 hours    | About 7 minutes | 240 credits | Purchase for the annual length; low-allowance warnings                       |


Duplicate payment, reversal (a test-card refund made from the dashboard), a manual chargeback, a lost callback (blocked notify URL) and a platform outage (platform route disabled) are run against these offers. Every scenario in §8 is a staging test (FR-90).

Before staging, the same flows run locally with `wrangler dev` and no Paymob account:

- **HMAC replay fixture.** Recorded Paymob callback bodies (test integration, no real card data), re-signed with a local HMAC secret, are posted to `/notify/paymob`. It covers success, decline, refund as parent flags, refund as a child transaction, a bad HMAC, and a replayed body.
- **Inquiry stub.** A local stand-in for Paymob's auth, order-inquiry and transaction endpoints, scripted per test: bound or unbound order, amount mismatch, pending, reversed, timeout, rate limit. The adapter points at it through its base URL setting.
- **Version matrix.** Each channel is exercised with N, N−1 and an unsupported version (04 §7), including an ABO on N+1 against a platform still on N.

### 6.2 Launch conditions

These are conditions on the production state, not tasks.

- The tenancy retrofit (01 R-1) is live, and RC-06 legal confirmation is recorded (01 R-9).
- No `/control/*` route, `OPERATOR_BEARER_TOKEN`, `set_ai_availability` or manual entitle path exists (FR-91).
- Production platform D1 holds no terms or grants. Pre-launch installations are deleted (their ledgers stay, per RC-05). A pilot clinic that keeps AI gets an HP complimentary grant of 30 days (unit `day`) with reason "pre-launch pilot"; this fits the ceilings (03 §3.2), and the clinic then buys like everyone else (FR-92).
- The first operator credential is bootstrapped and a second one is registered (24-hour delay). The issuer and service keys are registered, the platform signing key is set, and the issuer keys are pinned in the ABO's `ISSUER_KEYS`; the ABO's key self-check passes (AL-23 clear).
- Every channel runs contract version 1 on both sides, and the backend's `ai.contract_versions` matches the shared package (04 §7).
- R-9 advice on payer contact data is recorded, and the erasure action (§3.2) has been run once in staging.
- `workers_dev` and preview URLs are off. The audit watcher and heartbeat monitor are live. No stored token has production rights (02 §4.4).

### 6.3 Delivery sequence

The design ships as separate Spec Kit features, in this order. Each one is a precondition of the next and passes its own constitution check.

1. **Tenancy retrofit (01 R-1).** Membership, active organisation and `current_org_id()` in the backend. Nothing tenant-scoped in the later features is safe without it (SR-03, A36).
2. **Shared contract package and versioning.** `packages/vendor-contracts/` with canonical JSON, JWS, WebAuthn, message types and the version constants (04 §6.2, §7).
3. **AI Platform rework.** Issuer tokens, tenant bindings, the per-clinic coverage ledger, `VendorEntrypoint`, the feed and the removal of `/control/*` (04 §6).
4. **ABO.** Offers, checkouts, the Paymob adapter, the work pipeline, the ledger copy and the console (02 §1.2, 03 §2).
5. **Backend.** Issuer signing, the feed puller and projection, and the RPCs of 04 §3.1.
6. **Desktop.** Status reads, denial states, the administrator billing feature and version headers (04 §3.4, §3.5).
7. **Clean-up of dependent paths.** The viewer, the bootstrap script and the superseded platform documents (04 §6.6).
8. **Staging acceptance.** Every §8 scenario on the staging profile (§6.1), then the §6.2 launch conditions.

Steps 3 and 4 can overlap once step 2 is merged, because they meet only through the shared package and the entrypoint contract.

## 7. Operating cost and moving parts

New runtime parts: one Worker (the ABO), one D1 database, one R2 bucket, the `pg_cron` and `pg_net` extensions, an external heartbeat monitor and an external watcher job. There are no new servers, queues or databases outside Cloudflare and Supabase (constitution; C-06). At a few orders per day (C-08), the steady load is:

- about 1,440 ABO cron runs;
- 288 platform cron runs;
- 2,880 backend pulls, each writing one `feed_consumer` row;
- about 168·o + 4·L + P/7 reversal inquiries a day, where o is new payments per day, L is payments funding a live, queued or held term, and P is other payments under 180 days old (01 §3.3). At o = 5, L = 300 and P = 1,500 that is about 2,250 a day, or under 2 a minute, plus the checkout sweeps. The per-minute budget (§1) keeps bursts under Paymob's limit;
- about two DO row writes per AI request (01 §3.2).

That should stay inside the included allowances of the Cloudflare Workers Paid plan and the Supabase project; confirm against the account's plan (NFR-08).

## 8. Acceptance walkthrough

Each row is the defined, tested outcome (FR-90). "Status" marks rows whose outcome depends on something outside the design (§10).


| #   | Path through the design                                                                                                                                                                                             | Status      |
| --- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------- |
| A1  | Checkout (04 §2.2), then callback, inquiry and grant (02 §1.5). The term is active at once with the full offer allowance (03 §6.1). The payment appears in `GET /v1/payments`. The admin desktop shows Active by polling the checkout, then calls `request_ai_status_refresh()`. Tested for 1, 3 and 12 months | Met |
| A2  | Nothing on the provisioning path needs the desktop. Any desktop's `get_ai_status()` shows active on open; `GET /v1/checkouts?open=1` shows the outcome                                                              | Met         |
| A3  | The checkout sweep inquires at +2, +5, +10 and +20 minutes and provisions; AL-03 is raised                                                                                                                          | Met         |
| A4  | The grant row retries every 15 minutes for 4 days; AL-04 is raised hourly. When the platform returns, the grant applies; the term starts at activation, so no paid days are lost (01 I-2)                             | Met         |
| A5  | The declined attempt is an `attempt_declined` event and the checkout stays open. The later success is one payment and one grant. Nothing is cancelled                                                               | Met         |
| A6  | Two payments. The second is `likely_duplicate` (03 §5.2), stacks as the next term, and raises a `duplicate_payment` notice and AL-09                                                                                | Met         |
| A7  | The payment is bound to the monthly checkout's order and snapshot, so the monthly term is granted at the monthly price. The annual checkout expires unpaid                                                          | Met         |
| A8  | The intention amount is fixed at creation from the checkout snapshot, and the grant uses the same snapshot                                                                                                          | Met         |
| A9  | The renewal queues. The current allowance is unchanged; the new term starts at the old end date with its own allowance (03 §6.8)                                                                                    | Met         |
| A10 | The DO enters grace at the end date and ends it at `grace_ends_at` on its own alarm and on admission, with no ABO involvement. The backend computes the lapse from dates                                          | Met         |
| A11 | The new term starts at activation, seconds after payment (03 §6.8)                                                                                                                                                  | Met         |
| A12 | The tenant comes from the backend session; nothing is stored on the desktop                                                                                                                                         | Met         |
| A13 | Issuer-key rotation (02 §6) does not touch the tenant binding or the terms                                                                                                                                          | Met         |
| A14 | Same-org `beginTransfer` (HP) retires the old binding and creates a new one with the next epoch; the new DO waits in `awaiting_transfer`. `transferOut` and `transferIn` then move the terms with their `origin_grant_id`. The old identity ends `transferred` and refuses new grants; the status projection follows the higher epoch (03 §4). AL-11 is raised, and reconciliation matches the transfer to its authorisation (§3.3) | Met |
| A15 | Manual chargeback (HP), effect `end_current`. The grant is voided, the term ends `reversed` with no grace, and queued terms are held. AL-06 is raised                                                               | Met         |
| A16 | The refund arrives as parent flags or a child transaction. The adapter folds it into a `reversal`, never a payment; inquiry confirms; the effect follows 03 §5.5, through transfer lineage if the term moved; AL-06. A lost callback is caught within an hour in the payment's first 7 days, within 6 hours while it funds a live, queued or held term, and within a week otherwise up to 180 days (§1) | Met |
| A17 | Effect `none`: recorded and alerted, with no service change                                                                                                                                                         | Met         |
| A18 | Payout import raises `unrecorded_reversal`. The operator records the chargeback (HP) and the effect applies. Once linked to the payout line, reconciliation is clean                                               | Met         |
| A19 | The trial is a complimentary term. The purchase queues after it, so there is no gap and no overlap                                                                                                                  | Met         |
| A20 | An HP complimentary grant of 14 days (unit `day`), within the 31-day ceiling, queued after existing coverage. AL-11 and the digest report it; reconciliation matches it to the `operator_action`                                | Met         |
| A21 | The retired offer leaves `/v1/offers`. Existing terms keep their plan snapshot until they end. A stale offer id answers `offer_unavailable`                                                                        | Met         |
| A22 | No token can be obtained for another tenant; foreign ids answer `not_found`; nothing is locked by an open checkout                                                                                                  | Met         |
| A23 | AL-02 within 15 minutes; sweeps confirm by inquiry                                                                                                                                                                  | Met         |
| A24 | HP delete marks the installation `deleted`. With paid time left, the binding is `held_for_transfer` and AL-18 is raised: AI is refused with `transfer_pending`, a renewal paid meanwhile waits as `transient`, and no second binding appears. The operator moves the time with `beginTransfer` from the held binding, or voids the remaining grants, which retires it (03 §5.4, 04 §1.3) | Met |
| A25 | No per-clinic credential exists. Issuer keys raise AL-14 30 days ahead and rotate without an outage                                                                                                                 | Met         |
| A26 | Stored tokens have no production rights by policy; HP needs a passkey; the watcher alerts on deploys                                                                                                                | Partial     |
| A27 | Without the passkey, no grant is possible. With it, the 31-day ceiling blocks a year, an override needs a second assertion and raises AL-12, AL-11 fires within minutes, and grants can be listed and voided      | Met         |
| A28 | Staff get `ends_soon` at 7, 3 and 1 days in the staff form. The lapse shows from stored dates. Staff cannot mint billing tokens, `/v1/coverage` refuses them, and `/v1/usage` is gone                             | Met         |
| A29 | Band events at 75 % and 90 % produce `allowance_low` for every role; admission continues                                                                                                                           | Met         |
| A30 | The app offers the change for the next term only; `POST /v1/checkouts` answers `starts: after_current`; nothing changes now                                                                                        | Met         |
| A31 | Exhaustion ends the term on that request with no grace. A new purchase starts at activation; the rest of the calendar is forfeited (03 §6.8)                                                                       | Met         |
| A32 | The prepaid term activates at the exhaustion instant with its full allowance and runs one month from then (03 §6.8)                                                                                                | Met         |
| A33 | Retired offers are not listed; the owner picks a current offer                                                                                                                                                      | Met         |
| A34 | The DO serializes admissions: one crosses, exhaustion is recorded once, overshoot is at most `w_max − 1` (03 §6.6), and the other request goes to the successor or is refused `allowance_exhausted`              | Met         |
| A35 | Neither service holds any database credential or Supabase JWT; the backend only pulls (02 §4.3)                                                                                                                    | Met         |
| A36 | The ABO and RPCs take the tenant only from the session and answer `not_found` across tenants                                                                                                                        | Conditional |


## 9. Traceability matrix

A bare § refers to this document. Status values: **Met**. **Met (I-n)** means met as interpreted in 01 §4. **Seam** means the expansion seam exists, as required. **Conditional** means it depends on the tenancy retrofit (01 R-1). **Partial** and **Not met** are explained in §10.


| ID     | Satisfied in                                  | Status      |
| ------ | --------------------------------------------- | ----------- |
| G1     | 02 §1.5; 04 §2.2                              | Met         |
| G2     | 02 §4.3                                       | Met         |
| G3     | 03 §5.6; §2; §4                               | Met         |
| G4     | 03 §2                                         | Met         |
| G5     | 04 §3.4; 03 §6.5                              | Met         |
| G6     | 02 §1.2; 04 §5                                | Met         |
| G7     | §3                                            | Met         |
| G8     | §7; 01 §6                                     | Met         |
| FR-01  | 03 §2.2; §3.2                                 | Met         |
| FR-02  | 03 §2.2; 04 §1.4                              | Met         |
| FR-03  | 03 §2.2                                       | Met         |
| FR-04  | 03 §2.2, §2.4                                 | Met         |
| FR-05  | 04 §2.2                                       | Met         |
| FR-06  | 03 §2.2; 04 §2.3                              | Met         |
| FR-07  | 03 §6.2, §6.3                                 | Met         |
| FR-08  | 03 §5.4, §6.4                                 | Met         |
| FR-09  | 03 §6.2; 04 §4.2                              | Met         |
| FR-10  | 04 §2.1, §3.1                                 | Met (I-1)   |
| FR-11  | 04 §5.3                                       | Met         |
| FR-12  | 02 §1.5; 01 §3.3                              | Met         |
| FR-13  | 04 §5.1, §5.3                                 | Met         |
| FR-14  | 03 §5.1; 04 §2.2                              | Met         |
| FR-15  | 03 §5.1                                       | Met         |
| FR-16  | 04 §5.2; 03 §2.6                              | Met         |
| FR-17  | 04 §2.2                                       | Met (I-9)   |
| FR-20  | 04 §5.1                                       | Met         |
| FR-21  | 03 §6.1, §6.3                                 | Met         |
| FR-22  | 03 §6.4                                       | Met (I-6)   |
| FR-23  | 03 §6.2, §6.5; 02 §4.3                        | Met         |
| FR-24  | 03 §5.4; 04 §2.1                              | Met (I-2)   |
| FR-25  | 02 §6; 03 §7                                  | Met         |
| FR-26  | 04 §3.2                                       | Met         |
| FR-27  | 04 §3.2, §3.4                                 | Met         |
| FR-30  | 04 §2.2                                       | Met         |
| FR-31  | 04 §2.2; 03 §6.1                              | Met         |
| FR-32  | 03 §5.3                                       | Met         |
| FR-33  | 03 §6.3                                       | Met (I-2)   |
| FR-34  | 03 §6.7; 04 §3.2                              | Met         |
| FR-35  | 03 §5.3                                       | Met         |
| FR-36  | 04 §1.4; §3.2, §3.3                           | Met         |
| FR-37  | 03 §6.1; §8 A19                               | Met         |
| FR-38  | 02 §3.3                                       | Met         |
| FR-40  | 03 §5.1                                       | Met         |
| FR-41  | 03 §5.2                                       | Met (I-8)   |
| FR-42  | 04 §5.3; 03 §2.7                              | Met         |
| FR-43  | 03 §5.5                                       | Met (I-3)   |
| FR-44  | §3.2                                          | Met         |
| FR-45  | 04 §5.1; 03 §2.7                              | Seam        |
| FR-50  | 03 §2.6, §2.7, §7                             | Met         |
| FR-51  | 03 §2.3; 04 §2.2                              | Met         |
| FR-53  | 04 §1.7, §6.1                                 | Met         |
| FR-60  | 04 §3.1, §4.2                                 | Met         |
| FR-61  | 04 §3.4, §4.2                                 | Met         |
| FR-62  | 04 §3.1, §4.1                                 | Met         |
| FR-63  | 04 §4.1; 03 §4                                | Met (I-7), with the desktop lag in §10 |
| FR-64  | 04 §3.4                                       | Met         |
| FR-65  | 04 §3.4                                       | Met         |
| FR-66  | 03 §7                                         | Met         |
| FR-70  | §3.1                                          | Met         |
| FR-71  | §3.2                                          | Met         |
| FR-72  | 04 §1.3; 03 §5.4                              | Met         |
| FR-73  | 03 §2.10; §3.2                                | Met         |
| FR-74  | 03 §5.7; §3.2                                 | Met (I-4)   |
| FR-80  | §3.3                                          | Partial     |
| FR-81  | §2, §3.3                                      | Met         |
| FR-82  | §1; 01 §3.3                                   | Partial     |
| FR-90  | §6.1, §8                                      | Met         |
| FR-91  | 04 §1.3, §3.1, §6.1; §6.2                     | Met         |
| FR-92  | §6.2                                          | Met         |
| SR-01  | 02 §4.3                                       | Met         |
| SR-02  | 03 §2.11, §7                                  | Met         |
| SR-03  | 02 §4.3; 04 §2.1                              | Conditional |
| SR-04  | 04 §2.2                                       | Met         |
| SR-05  | 04 §1.4, §1.6                                 | Met         |
| SR-06  | 02 §3.3                                       | Met         |
| SR-07  | 04 §3.1; 03 §4                                | Met         |
| SR-08  | 02 §4.3; 04 §2.2, §3.1                        | Conditional |
| SR-09  | 02 §4.3                                       | Met         |
| SR-10  | 03 §2.11; 04 §1.7                             | Met         |
| SR-11  | 02 §6                                         | Met         |
| SR-12  | 02 §4                                         | Met         |
| SR-13  | 04 §3.3; 02 §4.2 AD-15                        | Met         |
| SR-20  | 02 §2 TB-7, §3.3                              | Met         |
| SR-21  | 02 §3.3, §4.4                                 | Partial     |
| SR-22  | 02 §1.4                                       | Met         |
| SR-23  | 02 §5; §2 AL-11; §3.4                         | Met         |
| SR-24  | 04 §1.4; 03 §3.2                              | Met         |
| SR-25  | 04 §1.3; §3.2                                 | Met         |
| NFR-01 | 03 §5.6; §4                                   | Met         |
| NFR-02 | 03 §7; 04 §2.2; §1                            | Met         |
| NFR-03 | 04 §1.2                                       | Met         |
| NFR-04 | §2; 02 §5                                     | Met         |
| NFR-05 | 03 §6.5; 04 §4.2                              | Met         |
| NFR-06 | 03 §6.2–§6.6                                  | Met         |
| NFR-07 | §6.1                                          | Met         |
| NFR-08 | §7                                            | Met         |
| NFR-09 | 04 §7; 04 §3.4; §6.1                          | Met         |
| RC-01  | 03 §2.1, §8                                   | Met         |
| RC-02  | 03 §2.5                                       | Met         |
| RC-03  | 03 §8; 02 §4.4                                | Met, with the lock limit in §10 |
| RC-04  | §5                                            | Met         |
| RC-05  | 03 §8; 04 §6.1                                | Met         |
| RC-06  | 01 R-9; §6.2                                  | Not met     |
| C-01   | 04 §6                                         | Respected   |
| C-02   | 02 §1.1; 01 R-1                               | Respected   |
| C-03   | 04 §2.1                                       | Respected   |
| C-04   | 04 §3.4; §4 FM-11, FM-12                      | Respected   |
| C-05   | 04 §5.3                                       | Respected   |
| C-06   | 02 §1.1                                       | Respected   |
| C-07   | 02 §1.2                                       | Respected   |
| C-08   | §7                                            | Respected   |
| P-01   | 03 §6.2, §6.4                                 | Closed      |
| P-02   | 03 §6.1                                       | Closed      |
| P-03   | 03 §5.4, §6.3                                 | Closed      |
| P-04   | 03 §3.2 `plan_version`; 04 §6.1               | Closed      |
| P-05   | 04 §6.1 `src/worker.ts`                       | Closed      |
| P-06   | 02 §3.1; 04 §6.1                              | Closed      |
| P-07   | 02 §3.3; 04 §6.1                              | Closed      |
| P-08   | 03 §6.5; 04 §4.2, §6.1                        | Closed      |
| P-09   | 04 §4.2                                       | Closed      |
| P-10   | 04 §2.1                                       | Closed      |
| X-01   | 04 §5.1; 03 §2.7                              | Seam        |
| X-03   | 03 §2.4; 04 §5.1                              | Seam        |
| X-04   | 03 §2.4; 04 §5.1                              | Seam        |
| X-05   | 04 §3.2                                       | Seam        |
| X-06   | 04 §1.4 `placement`; 03 §5.3                  | Seam        |
| X-07   | 04 §1.4 `kind`; 03 §5.3                       | Seam        |
| X-08   | 03 §2.4                                       | Seam        |
| X-09   | 04 §1.4 `approvals`                           | Seam        |
| X-10   | 04 §7                                         | Seam        |
| A1–A36 | §8                                            | Met, except A26 (Partial) and A36 (Conditional) |


Phase 2 refines 01 in these places; none reverses a [Decided] item:

- **X-06 and X-07 share one mechanism.** FR-32 needs an operator-only `term_adjustment` at launch, and a later paid adjustment reuses it. The X-06 seam therefore accepts only `placement = queue` at launch; `immediate` is rejected rather than accepted (04 §1.4).
- **Checkout states.** There is no `superseded` state: a new checkout leaves an open one payable (03 §2.4, FR-15).
- **Coverage events.** The ABO reads the platform's coverage events (01 §3.7) for its console and grant-origin reconciliation. Duplicate classification reads `getCoverage` live instead. Nothing depends on the platform calling the ABO.
- **Ceilings (01 I-10).** Allowance ceilings are counted in months of the plan's `max_allowance_per_month`, and `term_adjustment` additions and extensions count toward the 90-day window (03 §3.2).
- **Issuer keys at the ABO.** The ABO verifies billing tokens against issuer keys pinned in its own configuration, not the platform registry (02 §6, 04 §2.2).
- **Unsigned feed.** Feed pages are not signed, because the projection is display-only and TLS plus the feed token cover transport; the platform key signs receipts only (01 §3.4, 04 §4.1).
- **Deletion with paid time left.** The binding is held for transfer instead of retired, so an org never has two live identities (03 §5.4).
- **Payer contact data.** Contact values live only in the erasable `billing_contact` table; facts and the ledger copy hold its version and hash (03 §2.3).
- **Versioning on every channel.** X-10 covered the ABO–platform channel and tokens; NFR-09 extends it to every request and response (04 §7).
- **Reversal sweep cadence.** Tiered by payment age and whether it funds live coverage, under one inquiry budget (01 §3.3, §1).
- **Checkout without the platform.** A failed `getCoverage` falls back to `coverage_view` instead of blocking the sale (03 §2.4).

## 10. Unmet and partly met requirements


| ID                     | Gap                                                                                                                                                                                                                                  | Why, and what closes it                                                                                                                                       |
| ---------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| FR-80                  | Payout matching needs the operator to import Paymob's dashboard CSV each month; it is not automatic                                                                                                                                  | Paymob offers no payout API (01 R-2). The import is one routine action, after which matching and drift alerts are automatic. It closes when a provider offers an API, through `payoutLines` |
| SR-21, A26             | A leaked deploy or D1-write credential bypasses every in-code check                                                                                                                                                                 | This is inherent (SR-12). It holds only under the 02 §4.4 policy, with the external audit watcher; spike R-6                                                  |
| SR-03, SR-08, A36      | Tenant isolation in the backend depends on the membership, active-org claim and `current_org_id()` retrofit                                                                                                                         | The backend is single-tenant today (01 T-1, T-2). The ABO and platform sides are complete; the retrofit is a separate precondition feature (01 R-1)            |
| RC-06                  | Legal confirmation of the no-refund policy                                                                                                                                                                                           | Outside the design. It is a launch condition (§6.2); the terms shown at checkout are a versioned record (03 §2.2), so the text can follow the advice          |
| 01 R-9 (personal data) | How long payer contact data and raw provider bodies may be kept, and when they must be erased, is not yet confirmed under Egypt's Personal Data Protection Law                                                                        | Outside the design. The data is already confined to one erasable table and an unlocked R2 prefix, with an HP erasure action (03 §2.3, §3.2), so any retention period the advice sets can be applied |
| RC-03                  | An account-level token can remove the R2 bucket lock                                                                                                                                                                                 | Detected by the daily lock check (AL-16); the platform's grant ledger in its own bucket is a second copy                                                      |
| FR-82                  | Lost payment callbacks are recovered within minutes by the checkout sweeps. Lost reversal notices are recovered within an hour in a payment's first 7 days, within 6 hours while it funds a live, queued or held term, and within a week for older payments | Paymob has no event list to replay, so a lost refund callback is found only by inquiring each payment. Minute-level polling of every live payment would multiply inquiry volume for little gain; a reversal of an old payment has no service effect (A17). It closes when a provider offers a reversal event feed |
| FR-63                  | The 2-minute bound applies to the backend projection. A desktop can show the change up to 5 minutes later unless it opens, resumes or sees a denial first                                                                             | Approved in 01 §3.4; FR-64 covers the lag                                                                                                                     |
| Spike-dependent items  | R-2 (Paymob redelivery, second success on one intention, order listing; expiry default bound at 1800 s, 06 §6 OQ-3); R-3 (issuer key custody without pgsodium); R-4 (pg_cron and pg_net limits); R-5 (WebAuthn and Access details)                               | The design names a fallback for each: inquiry sweeps for R-2; an Edge Function signer for R-3; a longer pull interval within the bound for R-4; EdDSA-only credentials for R-5 |
| 02 AD-8                | A compromised ABO can fabricate paid grants within the plan bounds until velocity alerts or reconciliation catch it                                                                                                                  | Inherent: the platform cannot verify payments without provider data, which SR-10 and FR-53 forbid                                                             |

