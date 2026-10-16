# Implementation Plan: Grant pipeline to the platform: purchase to AI on

**Branch**: `ai/079-abo-p4-4-grant-pipeline-to-platform-purchase` | **Date**: 2026-10-07 | **Spec**: `specs/079-abo-p4-4-grant-pipeline-to-platform-purchase/spec.md`

**Input**: Feature specification from `specs/079-abo-p4-4-grant-pipeline-to-platform-purchase/spec.md`

## Summary

A paid checkout becomes one platform term: the ABO builds the paid grant envelope from the payment and the checkout snapshot, signs it with the current ABO `kid`, and calls platform `grant`. Depends on P4.3 and P3.4. Phase P4, size M. Subscription and payments responses are frozen here (CP-C). Spikes are none, so this phase does not write `research.md`.

## Technical Context

**Language/Version**: TypeScript on the existing `abo/` Cloudflare Worker (wrangler, workers types, vitest workers pool already in `abo/package.json`).

**Primary Dependencies**: Consumed `vendor-contracts` `grantIdPaid`, `subscriptionRef`, `canonicalize`, `sha256Hex`, `signCompactJws`, `verifyCompactJws`, and `CHANNEL_VERSIONS`. WebCrypto Ed25519. No new library.

**Storage**: ABO D1 (`DB`). New tables `grant_request`, `grant_outcome`, `reversal` (read only; no insert in this unit), and `signing_key_gate`. Consumed `payment`, `checkout`, `checkout_status`, `work`, `offer_version`, `coverage_view`, `fact_log`, and `alert`.

**Testing**: H-XW + H-PAY for E2E-P4.4-01 through E2E-P4.4-09. Titles are prefixed with the E2E id. Tests are red before the production modules exist. The ABO clock is the consumed `clockNowMs`. A local scenario spends at most 2 seconds of real time. `TEST_CLOCK` stays off production and staging wrangler envs.

**Target Platform**: `abo/` Worker. Billing hostname `SELF.fetch` for `POST /v1/checkouts`, `POST /notify/paymob`, `GET /v1/checkouts/{id}`, `GET /v1/checkouts?open=1`, `GET /v1/subscription`, and `GET /v1/payments`. `scheduled` for crons `* * * * *` and `0 * * * *`. `VendorEntrypoint.grant` and `VendorEntrypoint.listServiceKeys` over the existing `PLATFORM` service binding. `POST /v1/requests` on the platform worker fetch.

**Project Type**: One Cloudflare Worker (`abo`). No second codebase.

**Performance Goals**: Grant backoff stays at or under 15 minutes. The grant runner takes at most 50 due `grant` rows per minute run. `GET /v1/payments` returns 20 payments per page. The signing-key check runs at isolate start and on the hourly cron, not on every clinic request.

**Constraints**: `grant_id` is `grantIdPaid(payment_id)` (hex SHA-256 of `grant:paid:` ‖ `payment_id`, the 04 §1.4 / 03 §7 value the envelope field requires). Each attempt signs with the current ABO `kid`. Paid `evidence.approvals` is the one operation-object element from the amended 04 §1.4 evidence row. `grant_outcome` is written only after the receipt verifies. An unverified `applied` or `already_applied` receipt parks the work row and raises AL-07, and does not write `grant_outcome` (amended 04 §1.6). `transient` is not a `grant_outcome` result. This unit does not change `grant`, `listServiceKeys`, or the P4.3 confirm step. Clinic reads use the billing token's `org`.

**Scale/Scope**: One clinic's paid grants and the two clinic reads. Codebase `abo` only. Reversal processing stays with P4.5. Operator retry of parked rows stays with P4.6.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

Checked against `.specify/memory/constitution.md` (Version 1.0.0) and 02 §7. 02 §7 records that this design complies. No box is unchecked.

- [x] Feature scope still fits small-to-mid-size multi-branch clinics; hospital-scale or
      enterprise-only requirements are explicitly rejected or separately ratified
- [x] Design keeps a simple operational model with no microservices, message queues,
      Kubernetes, or custom primary backend service
- [x] Layer ownership is explicit: Flutter handles UI/orchestration, Supabase handles
      backend capabilities, PostgreSQL owns domain integrity, and AI stays isolated
- [x] Protected writes, validation, permissions, and transactional rules remain enforced
      through PostgreSQL constraints, triggers, RLS, or RPC functions
- [x] Security remains authenticated, tenant-scoped, branch-scoped, permission-gated,
      auditable, and soft-delete-preserving
- [x] AI actions remain human-approved, have no direct database/backend access, and the
      feature still works in a degraded manual mode when AI is unavailable

02 §7 I: one Worker, D1, R2, and crons; no queues or Kubernetes. This unit adds the grant work step and two clinic reads on that Worker. 02 §7 II: the ABO holds no clinic database credential and calls the platform only through the existing service binding. 02 §7 III: vendor-side integrity is D1 append-only triggers on `grant_request` and `grant_outcome`, one `grant_request` per payment, and one D1 batch for the outcome; this unit does not write PostgreSQL. 02 §7 IV: the clinic administrator's payment is the human action for a paid grant (02 §1.5); the amended 04 §1.4 evidence row does not add a WebAuthn ceremony on that path; the ABO signature is still verified by the frozen `grant` method; subscription and payment reads use the billing token's tenant. 02 §7 V: `transient` and an unreachable platform retry with backoff; a parked grant does not lock clinical work.

## Project Structure

### Documentation (this feature)

```text
specs/079-abo-p4-4-grant-pipeline-to-platform-purchase/
├── plan.md
├── data-model.md
├── quickstart.md              # implement writes this after the harness is green
├── contracts/
│   └── subscription-payments.md
└── tasks.md                   # not created in this phase
```

`quickstart.md` sections, written after verification:

- What was implemented, and the files added or modified
- The harness command for this unit’s tests only, from `abo/`: `node scripts/build-platform-for-hxw.mjs && npx vitest run --config vitest.cross-worker.config.ts test/system/grant.cross-worker.test.ts`
- Entry point → module chain per E2E id
- No earlier-unit files, combined counts, or full-suite commands
- No manual steps; the harness observes every scenario

### Source Code (repository root)

```text
abo/
├── migrations/0004_grant.sql
├── src/
│   ├── worker.ts                              # modify
│   ├── alert/index.ts                         # modify
│   ├── notify/intake.ts                       # modify
│   ├── clinic-api/checkouts.ts                # modify
│   ├── clinic-api/billing-reads.ts            # create
│   └── work/grant.ts                          # create
├── test/system/grant.cross-worker.test.ts     # create
├── vitest.cross-worker.config.ts              # modify
└── wrangler.toml                              # modify
```

**Structure Decision**: All of this unit lives in `abo/`. The grant step is a new module reached from the existing notify `waitUntil` and from `scheduled`. Clinic reads sit on the billing host behind the existing version, auth, and per-token rate gates. The platform worker and `VendorEntrypoint.grant` / `listServiceKeys` stay as frozen by P3.4. H-XW gains a fetch binding to that same platform worker so the test can `POST /v1/requests`. H-PAY stays the Paymob stub already on the cross-worker config.

## Consumes Binding

| Consumes | Existing module |
| --- | --- |
| P3.4 admission answer (reservation, `term_id`, snapshot, band) and clinic denial codes of 04 §4.2. CP-B | `ai-platform/src/vendor/entrypoint.ts` `grant` and `listServiceKeys`. `ai-platform/src/worker.ts` `POST /v1/requests`. This unit calls those methods. It does not modify `ai-platform/`. The issuer AI request is how E2E-P4.4-01 observes a completed admission against the granted term. |
| P4.3 (the unit row states no Outputs / freezes line) | The `grant` work row inserted in `abo/src/work/runner.ts`: `kind` `grant`, `subject_id` the `payment_id`, `dedupe_key` `grant:{payment_id}`, `state` `open`. Confirm, the lease take, the 50-row confirm query, and that insert stay as they are. This unit does not modify `abo/src/work/runner.ts`. |

## Files

| Path | Action | FR |
| --- | --- | --- |
| `abo/migrations/0004_grant.sql` | Create | FR-005, FR-006, FR-009, FR-010 |
| `abo/src/work/grant.ts` | Create | FR-001, FR-002, FR-003, FR-004, FR-006, FR-007, FR-010 |
| `abo/src/clinic-api/billing-reads.ts` | Create | FR-005, FR-009 |
| `abo/src/clinic-api/checkouts.ts` | Modify | FR-001, FR-008 |
| `abo/src/notify/intake.ts` | Modify | FR-001, FR-008 |
| `abo/src/worker.ts` | Modify | FR-001, FR-002, FR-005, FR-006, FR-008, FR-009 |
| `abo/src/alert/index.ts` | Modify | FR-002, FR-003, FR-006 |
| `abo/wrangler.toml` | Modify | FR-001, FR-007 |
| `abo/vitest.cross-worker.config.ts` | Modify | FR-001, FR-007 |
| `abo/test/system/grant.cross-worker.test.ts` | Create | FR-001, FR-002, FR-003, FR-004, FR-005, FR-006, FR-007, FR-008, FR-009 |
| `specs/079-abo-p4-4-grant-pipeline-to-platform-purchase/data-model.md` | Created this phase | FR-006, FR-010 |
| `specs/079-abo-p4-4-grant-pipeline-to-platform-purchase/contracts/subscription-payments.md` | Created this phase | FR-005, FR-009 |

`quickstart.md` is not written in this phase. `research.md` is not written: Spikes is none.

`wrangler.toml` gains `ABO_GRANT_KEY` and `PLATFORM_PUBLIC_KEYS` on development, staging, and production. Placeholders are `{}` and `[]`. No `TEST_CLOCK` var is added. No production fault binding is added.

`ABO_GRANT_KEY` is JSON `{kid, pkcs8, public_key}`. `pkcs8` and `public_key` are base64url, the same shape as the platform worker's `PLATFORM_SIGNING_KEY`. `PLATFORM_PUBLIC_KEYS` is a JSON array of `{kid, public_key}` for receipt verification. The H-XW vitest config sets a fixed test ABO key and a two-element platform key list. The second element is the public key already in that config's `PLATFORM_SIGNING_KEY` (`kid` `platform-test`). The first element is a different kid. Production placeholders fail the signing-key check closed (pause), which is the FR-006 outcome when the kid is missing.

`vitest.cross-worker.config.ts` adds the test file to `test.include`, the two ABO bindings, and a service binding `PLATFORM_HTTP` to the same auxiliary worker `platform` with no entrypoint, so the test can `fetch` `POST /v1/requests`. `PLATFORM` stays `entrypoint = "VendorEntrypoint"`.

`alert/index.ts`: extend `AlertCode` with `AL-04`, `AL-07`, and `AL-23`. `nextSendAtForCode` treats those three like `AL-01`: one hour ahead. The email text stays `{code} {detail_id}`. AL-05 and AL-09 stay send-once.

`checkouts.ts`: `POST /v1/checkouts` stays. `checkoutReadObject` still returns Waiting for `open` and Abandoned for `open_failed`. When `checkout_status.state` is `paid` or `paid_late` and that checkout's payment has a `grant_outcome.result` of `applied` or `already_applied`, `shown_state` is `Active`. Otherwise a `paid` checkout still returns no object, so `GET /v1/checkouts/{id}` stays `not_found` until the grant is accepted. `payment_reference` and `term_ref` stay null. `GET /v1/checkouts?open=1` already selects `paid` and `paid_late`; Active rows then appear.

`notify/intake.ts`: the processed-callback `waitUntil` still runs `runConfirmForWorkId`. When that promise settles, it runs `runDueGrantWork` on the same env. HMAC, rate limit, and the confirm step are unchanged.

`worker.ts`: `Env.PLATFORM` also types `grant` and `listServiceKeys`. `GET /v1/subscription` and `GET /v1/payments` go through the existing billing version, auth, and rate gates to `billing-reads.ts`. The minute cron still runs confirm, then `runDueGrantWork`. Cron `0 * * * *` calls `refreshSigningKeyCheck` and returns. Cron `0 */6 * * *` still returns immediately. Fetch and `scheduled` call `refreshSigningKeyCheck` when `signing_key_gate` has no row, and the hourly cron always calls it.

`work/grant.ts` is the grant step and the signing-key check.

Signing-key check. `refreshSigningKeyCheck` calls `PLATFORM.listServiceKeys({ contract_version: CHANNEL_VERSIONS.vendorEntrypoint })`. A successful `ok` parses `detail` as the JSON array of `{kid, status, not_before, not_after}`. The ABO kid comes from `ABO_GRANT_KEY`. The check passes only when that `kid` is listed with `status` `active` and the ABO clock is within `not_before` and `not_after` inclusive. Otherwise, and when the call throws or the result is not `ok`, the gate row is `paused = 1` and AL-23 is raised with key `AL-23:{kid}` (or `AL-23:missing` when the JSON has no kid). When the check passes, `paused = 0` and that alert row's `active` is set to 0. `runDueGrantWork` reads the gate first. While `paused = 1` it does not take `grant` or `reverse` rows. Those rows stay `open`. They are not parked.

Grant step, for one due `open` `grant` row whose `subject_id` is the payment. Skip when paused. Take the row with the same 60-second conditional lease the confirm runner uses (`lease_until` null or already past, `next_attempt_at` due). Load the payment and its checkout. Build one envelope:

- `contract_version`: `CHANNEL_VERSIONS.vendorEntrypoint`
- `grant_id`: `grantIdPaid(payment_id)`
- `org_id`: the payment's `org_id`
- `kind`: `term`
- `placement`: `queue`
- `source`: `{kind: "paid", ref: payment_id}` with `operator_email` and `reason` omitted
- `plan`: `{plan_id, plan_version}` from the checkout
- `duration`: `{unit: "month", count: checkout.term_count}` (1, 3, or 12)
- `allowance_credits`: `checkout.allowance_credits`
- `grace`: `{days: checkout.grace_days, cap_rule: checkout.grace_cap_rule}`
- `paid_at`: `payment.paid_at`
- `evidence.content_sha256`: `fact_log.row_sha256` for table `payment` and that `payment_id` (the canonical payment fact, which already includes `evidence_sha256`)
- `evidence.approvals`: one element, the operation object `{op, params, actor_email, issued_at, nonce, contract_version}` with `op` `grant`, `params` that same envelope with `evidence.approvals` omitted, `actor_email` `""`, `issued_at` `paid_at`, `nonce` `grant_id`, and `contract_version` the envelope's `contract_version`

Sign the canonical bytes of the full envelope (approvals included) with `signCompactJws` and the current `ABO_GRANT_KEY`. Call `PLATFORM.grant` with `contract_version`, `abo_kid`, `abo_signature`, and `envelope_b64` (base64 of those canonical bytes). Do not rely on a structured-clone of the envelope object: the frozen `grant` method compares the JWS payload to `envelope_b64` when that field is set.

Then:

- `applied` or `already_applied`, and `verifyCompactJws` succeeds for `receipt.signature` against the configured platform public key whose `kid` matches the JWS header: one D1 batch inserts `grant_request` if that `grant_id` is absent, inserts `grant_outcome`, inserts the two `fact_log` rows, and sets the work row `done` conditional on the held lease. `grant_request.assertion` is null. The outcome stores `abo_kid`, `abo_signature`, the receipt JSON, `term_ids` from the receipt, and `at` from the ABO clock. Clear AL-04 for that work id (`active = 0`).
- `applied` or `already_applied`, and the receipt does not verify: do not insert `grant_outcome`. Park the row (`state = parked`, `lease_until` null, `last_error` `receipt_unverified`) and raise AL-07. Still insert `grant_request` if it is absent, in that same park write.
- `conflict` or `rejected`: one batch inserts `grant_request` if absent and `grant_outcome` with that `result` and `at`. `abo_kid`, `abo_signature`, `receipt`, and `term_ids` are null. Park the work row and raise AL-07 with key `AL-07:{work_id}`.
- `transient`, or the `grant` call throws (unreachable): do not insert `grant_outcome`. Leave the row `open`. Set `last_error` to `wait:{iso}` on the first such failure and keep that timestamp on later ones. Backoff is the confirm formula: 1 minute, doubling, capped at 15 minutes; when `TEST_CLOCK` is `"1"`, the delay is 0 so the harness advances the clock instead of waiting. Raise AL-04 with key `AL-04:{work_id}` once the ABO clock is at least 5 minutes after the `wait:` timestamp. The minute cron's existing `sendDueAlerts` repeats it hourly while `active` stays 1.
- A thrown outcome batch (the harness `setD1BatchThrows` path): the platform call has already returned. Release the lease, leave the row `open`, write no outcome. The retry is the same `grant_id` and the same canonical envelope.

`runDueGrantWork` selects at most 50 due `open` `grant` rows ordered by `next_attempt_at`. It does not select `confirm` rows and does not change the confirm limit. A single row failure does not throw out of the cron. `reverse` rows are not created here; the pause check is the only `reverse` behavior.

`billing-reads.ts` implements `contracts/subscription-payments.md`. `subscriptionRef` is `subscriptionRef(org)` from `vendor-contracts`. `snapshot` is `detail.snapshot` from a live `getCoverage` (`contract_version` `CHANNEL_VERSIONS.vendorEntrypoint`, `org_id` the token `org`). When that call throws or `result` is not `ok`, `snapshot` is the parsed `coverage_view.snapshot` for that `org_id`. When that row is missing, `snapshot` is null and the HTTP status is still 200. `plan_display_name` is `copy.en.name` on the published `offer_version` that `GET /v1/offers` returns for the payment's `offer_id` (`abo/src/clinic-api/offers.ts` `listOffers`). `offer_version` is `payment.offer_version`. `term_unit` and `term_count` are the checkout columns. `reversals` is the `reversal` rows for that `payment_id`. This unit inserts none.

## Test Layout

| ID | Harness | Title prefix | Entry | Proves |
| --- | --- | --- | --- | --- |
| E2E-P4.4-01 | H-XW + H-PAY | `E2E-P4.4-01` | `SELF.fetch` `POST /v1/checkouts` and `POST /notify/paymob`; grant on `waitUntil` and `runScheduled` `* * * * *`; `PLATFORM.grant`; `PLATFORM_HTTP.fetch` `POST /v1/requests`; `GET /v1/checkouts/{id}` and `GET /v1/payments` | FR-001. For term counts 1, 3, and 12: platform term active with full allowance; issuer `POST /v1/requests` completes; checkout `shown_state` Active; payment listed |
| E2E-P4.4-02 | H-XW + H-PAY | `E2E-P4.4-02` | Grant step on `waitUntil` and `runScheduled` for `* * * * *` and `0 * * * *`; ABO test clock | FR-002. Binding `held_for_transfer` makes frozen `grant` return `transient` (`transfer_pending`) for 4 days of test clock; retries at ≤ 15 min; AL-04 hourly; then `active` and `applied`; term `starts_at` is the activation clock, not `paid_at` |
| E2E-P4.4-03 | H-XW + H-PAY | `E2E-P4.4-03` | Grant step on `waitUntil` or `runScheduled` `* * * * *` | FR-003. Plan version retired on the platform while the ABO kid stays `active` → `rejected`; work `parked`; AL-07; a later minute run does not take the row |
| E2E-P4.4-04 | H-XW + H-PAY | `E2E-P4.4-04` | Grant step; `setD1BatchThrows` after confirm has stored the payment | FR-004. Outcome batch throws after `grant` returns → no `grant_outcome`; retry is `already_applied` with the same receipt; one term |
| E2E-P4.4-05 | H-XW + H-PAY | `E2E-P4.4-05` | Two paid grants via `PLATFORM.grant`; `SELF.fetch` `GET /v1/subscription` | FR-005. Second term queued (`snapshot.queued_count` > 0); `notices` includes `duplicate_payment` |
| E2E-P4.4-06 | H-XW + H-PAY | `E2E-P4.4-06` | `PLATFORM.listServiceKeys` from isolate start (no `signing_key_gate` row) and from `runScheduled` `0 * * * *` | FR-006. ABO kid absent → grant row stays `open` (not `parked`) and AL-23; after the `service_key` insert and the hourly check, grant work runs |
| E2E-P4.4-07 | H-XW + H-PAY | `E2E-P4.4-07` | Grant step; receipt check against `PLATFORM_PUBLIC_KEYS` | FR-007. Receipt `kid` is the second configured platform kid; `grant_outcome` is stored; a later grant still runs |
| E2E-P4.4-08 | H-XW + H-PAY | `E2E-P4.4-08` | `POST /v1/checkouts` and `POST /notify/paymob`, then the grant step, with no clinic GET until `GET /v1/checkouts?open=1` | FR-008. No clinic GET after create; `?open=1` shows Active |
| E2E-P4.4-09 | H-XW + H-PAY | `E2E-P4.4-09` | `SELF.fetch` `GET /v1/payments` with tenant A and tenant B billing tokens | FR-009. 21 payments for A: first page `has_more`, `next_cursor` is that page's last `reference`; the next page follows; B's token lists none of A's payments |

All nine tests live in `abo/test/system/grant.cross-worker.test.ts`. Each title starts with the E2E id. Tests are written and run first, and they fail before `abo/src/work/grant.ts` and `abo/src/clinic-api/billing-reads.ts` exist. There is no tenth E2E id.

Shared setup in that file, using the existing H-XW helpers (`setupCrossWorkerHarness`, `billingFetch`, `mintBilling`, `pinIssuer`, `scriptPaymobStub`, `setClock`, `runScheduled`, `platformCall`, `setD1BatchThrows`):

- Register `env.ABO_GRANT_KEY.public_key` on `PLATFORM_DB.service_key` (`status` `active`, validity wide enough for the test clock), except in E2E-P4.4-06 before the resume step.
- Publish platform `plan_version` `plan-pro` / `1` (the fixture offer's plan) with `max_allowance_per_month` at least 100, `status` `published`. The ceiling migration already sets `max_paid_grace_days` 7 and `paid_cap_rule` `proportional`.
- Seed published offer versions with `term_count` 3 and 12 beside the fixture's 1-month offer, same plan, `allowance_credits` 100, `grace_days` 7, `grace_cap_rule` `proportional`.
- Insert `issuer_key` for the minted issuer (`kid`, `issuer` = `ISSUER_ID`, `public_key`, `status` `active`). Publish and promote a routing policy through `PLATFORM.publishRoutingPolicy` and `PLATFORM.promoteRoutingPolicy` (class H, access JWT from `mintVendorAccessJwt`) aimed at the platform fake provider, then `POST /v1/requests` with the visit-summary invoke body that policy admits (`capability_id`, `capability_version`, `user_intent`, `context`). Completed means HTTP 200.
- E2E-P4.4-05 opens both checkouts before either payment so they share `opened_with_coverage_through`.
- E2E-P4.4-09 seeds 21 `payment` rows for tenant A and one for tenant B. It does not run 21 grants. A cursor that is not A's `reference` is asserted `invalid_request` inside this same test.

Module chains the quickstart will record:

- E2E-P4.4-01: `worker.ts` `fetch` → `checkouts.ts` `handlePostCheckout` → `notify/intake.ts` → `work/runner.ts` `runConfirmForWorkId` → `work/grant.ts` `runDueGrantWork` → `PLATFORM.grant` → `PLATFORM_HTTP.fetch` `/v1/requests` → `checkouts.ts` `handleGetCheckout` → `billing-reads.ts` payments
- E2E-P4.4-02: `work/grant.ts` → `PLATFORM.grant` (`transient`) → `alert/index.ts`; clock; then `applied`
- E2E-P4.4-03: `work/grant.ts` → `PLATFORM.grant` (`rejected`) → park + AL-07
- E2E-P4.4-04: `work/grant.ts` → `PLATFORM.grant` → thrown batch → retry `already_applied`
- E2E-P4.4-05: `work/grant.ts` twice → `billing-reads.ts` `GET /v1/subscription`
- E2E-P4.4-06: `worker.ts` `scheduled` / first fetch → `work/grant.ts` `refreshSigningKeyCheck` → `PLATFORM.listServiceKeys` → pause → resume
- E2E-P4.4-07: `work/grant.ts` receipt verify → `grant_outcome`
- E2E-P4.4-08: `notify/intake.ts` `waitUntil` → `work/grant.ts` with no clinic GET → `checkouts.ts` `handleListOpenCheckouts`
- E2E-P4.4-09: `worker.ts` `fetch` → `billing-reads.ts` payments

## Sequencing

1. Write `abo/test/system/grant.cross-worker.test.ts` and the vitest include plus bindings. Run the harness command. The nine tests fail because the grant module and the clinic reads are absent.
2. Add `abo/migrations/0004_grant.sql` and `abo/src/work/grant.ts`. Wire `waitUntil`, the minute cron, and the hourly check in `worker.ts` and `notify/intake.ts`. Extend alert codes.
3. Extend checkout `shown_state` to Active. Add `billing-reads.ts` and the two routes.
4. Re-run the same harness command until E2E-P4.4-01 through E2E-P4.4-09 pass. Earlier suites are not part of this command.

The file list above is the whole change. It fits the size-M band (20–32 tasks) without a split and without padding.

## Complexity Tracking

02 §7 records no constitution violation for this design. Nothing is entered here.
