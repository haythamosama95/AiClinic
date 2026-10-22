# Final Review — Stage 2: Provider, Payment and Accepted Commands (RM08–RM13)

Second-round light pass. Branch `ai/abo-remediation` tip compared against `master`. One targeted spot-check per
requirement at the branch tip. No separate whole-code audit: findings below were noticed while verifying.

## 1. Summary

| Item | Count |
| --- | --- |
| RMs HANDLED | 5 (RM08, RM09, RM11, RM12, RM13) |
| RMs PARTIAL | 1 (RM10) |
| RMs NOT HANDLED | 0 |
| RMs REGRESSED | 0 |
| Critical findings | 0 |
| Major findings | 1 (M-1) |

**Verdict: FAIL.** M-1 is a Major finding: the operator recovery action for transaction IDs refuses any checkout
that already has a recorded capture. Because of that, R3-C6 is only partly met for captures that had no callback.

## 2. Phase verification

| RM | Requirement | Status | Evidence (branch tip) |
| --- | --- | --- | --- |
| RM08 | R3-C3 origin-only Paymob base URL in all envs | HANDLED | `abo/wrangler.toml:25,66,105` = `https://accept.paymob.com` |
| RM08 | R3-C3 reject path/query/fragment/credentials/non-HTTPS; loopback HTTP only when authorized; fixed paths | HANDLED | `abo/src/provider/paymob/client.ts:74-107,121-158`; `adapter.ts:108-142,144-154` |
| RM08 | R3-C5 forward migration with unique lease token | HANDLED | `abo/migrations/0010_work_lease_token.sql:4-12` |
| RM08 | R3-C5 every confirm batch statement fenced by `state='open' AND lease_token=?` | HANDLED | `abo/src/work/runner.ts:254,348,453,589,618,687,743,784,791,812,963` (27 fenced predicates) |
| RM08 | R3-C5 step 4 forward recovery for claims missing payment/work | HANDLED | `abo/src/work/runner.ts:1605-1645` (`recoverMissingConfirmWork`) |
| RM08 | R3-M5 byte-bounded body read, 413 before rate/evidence writes | HANDLED | `abo/src/notify/intake.ts:21,454-495,620-639` |
| RM09 | R3-C2 numbered attempts committed before HTTP; `abandoned_unconfirmed`; next attempt on retry | HANDLED | `abo/src/clinic-api/checkouts.ts:655-719,742-790,978-994` |
| RM09 | R3-C2 changed intent under same key returns `idempotency_conflict` (checkout + contact) | HANDLED | `checkouts.ts:961-966,1025-1031`; `billing-contact.ts:69` |
| RM09 | R3-M2 atomic token-use cap, checkout-hour admission, notify window | HANDLED | `abo/src/clinic-api/rate.ts:38-41`; `checkouts.ts:673-674`; `notify/intake.ts:111-120` |
| RM09 | R3-M3 offers serve current global terms; checkout validates current terms | HANDLED | `abo/src/clinic-api/offers.ts:44-66`; `checkouts.ts:1002-1005` |
| RM10 | R3-C7 reserve shared slot before provider HTTP (`spent < 2`), deferred without network | HANDLED | `abo/src/provider/paymob/adapter.ts:830-847,897-901` |
| RM10 | R3-C4 step 1: remove `99001`, return `discovery_unavailable`, retain work | HANDLED | no `99001` in `abo/src`; `adapter.ts:887-895`; `work/sweep.ts:292`; `runner.ts:1102,1462` |
| RM10 | R3-C4 D-3 class-H operator transaction-ID action | HANDLED | `abo/src/ops/index.ts:3458-3550,5523-5531` |
| RM10 | R3-C6 every bound successful transaction from callbacks **and operator submissions**; null-safe duplicate classification | PARTIAL | Classification is null-safe (`runner.ts:472-491`). The operator path refuses any checkout with a recorded capture (`ops/index.ts:3491-3498`), so a second capture with no callback cannot be submitted (M-1) |
| RM10 | R3-C4 steps 3–4 auto-enumeration deferred (R-2 gate) | HANDLED (deferred as directed) | `RM10.md` deferred section; no enumeration code |
| RM11 | R3-C1 no vertical `Expanded`/`Spacer` in offers/contact/checkout | HANDLED | Only horizontal `Expanded` inside `Row` remains (`offers_screen.dart:230-235,286-294`); no `Spacer` in the three screens |
| RM11 | R3-M4 offer-unavailable returns to fresh offer selection | HANDLED | `administrator_billing_page.dart:188-195,449`; `checkout_screen.dart:247` |
| RM11 | R3-M6 minor units formatted as major units | HANDLED | `billing_money.dart:4-7` |
| RM11 | R3-M1 local token-use reservation and rotation before 60 uses | HANDLED | `billing_token_client.dart:47,60-70,133-134`; `abo_client.dart:699-708` |
| RM11 | R3-C2 step 2 typed `idempotency_conflict` | HANDLED | `abo_client.dart:578-579,778` |
| RM12 | R6-O1 accepted-command store; atomic acceptance with `assertion_used` and action | HANDLED | `abo/migrations/0012_accepted_commands_erasure_fence.sql:4-26`; `ops/index.ts:1302-1340` |
| RM12 | R8-CONSOLE3 relay reservation keyed by actor/method/target/version/args before dispatch; conflict on change | HANDLED | `ops/index.ts:745-805` |
| RM12 | R6-O2 org erasure generation, raw-evidence registry, claim → upload → finalize fence, cleanup outbox | HANDLED | `0012_…sql:28-113`; `abo/src/evidence/raw.ts:19-110`; `ops/index.ts:1284-1309` |
| RM12 | Later-phase interaction | Consistent | `recovery_*` columns used by `ops/index.ts:1311-1333` come from later `0017_command_recovery_facts.sql:2-3` |
| RM13 | R8-AUDIT1 shared audit statement (actor = operator_id, `recorded_at`, pointers) batched with transitions | HANDLED | `ai-platform/src/control/audit.ts:25-68`; batched in `kill-switch.ts:147,163`, `cohort.ts:58,215`, `capability-lifecycle.ts:55,134` |
| RM13 | R8-AUDIT1 support lookup audits normalized selector; withholds data on audit failure | HANDLED | `ai-platform/src/vendor/entrypoint.ts:7492-7537` |
| RM13 | R8-SUPPORT1 paged request IDs (default 50, 1–100, tie-safe cursor), no list envelopes | HANDLED | `ai-platform/src/support/index.ts:133-138,364-431` |

## 3. Critical findings

None.

## 4. Major findings

### 4.1 M-1 — Operator transaction-ID recovery refuses checkouts that already have a capture

- **File:** `abo/src/ops/index.ts:3491-3498` (`handlePostSubmitTransactionId`)
- **Failure scenario:** Checkout `CK-1` is paid by transaction A, and A's callback arrives, so a `paymob_txn` row
  exists. The payer is then charged again as transaction B on the same order, and B's callback is lost. Automatic
  order enumeration stays disabled (R-2 gate), so the only recovery path is for the operator to submit B through
  `POST /ops/checkouts/CK-1/transaction-id`. The handler returns 409 because *any* `paymob_txn` row exists for
  `CK-1`. Result: B is never recorded as a payment, it gets no grant work, and it is never flagged as a likely
  duplicate. The plan requires R3-C6 to process "every bound successful transaction known from callbacks and
  operator submissions."
- **Confidence:** Medium. The code path is confirmed; how often Paymob captures twice on one order is not verified.
- **Proposed fix:** In `abo/src/ops/index.ts`, refuse (or replay) only when the *submitted* `txn_id` already
  exists (`SELECT … FROM paymob_txn WHERE txn_id = ?`). Allow new transaction IDs on checkouts that already have
  captures; the existing inquiry order binding still blocks unrelated transactions. Also write the
  `operator_action` row and the `work` insert in one `DB.batch`. Add an acceptance test: one capture via callback,
  a second capture via operator submission, and assert two payments.

## 5. Could not verify

- R3-M5 chunked overflow through the Wrangler proxy (known gap in the RM08 record). Only the declared
  `Content-Length` path is covered by CI. The code (`intake.ts:473-481`) stops accumulating after the limit.
- R3-C5 completeness: every statement in the confirm batch is fenced. The spot-check sampled the predicates but
  did not trace each batch statement by statement.
- RM12 relay paths beyond `reserveRelayCommand`: begin-transfer result persistence and runner uniqueness were not
  traced end to end.
- RM13 fencing of transitions on token-contract, routing and installation handlers: only kill-switch, cohort and
  capability were spot-checked.
- Later RM28 change `0019_secretless_created_attempts.sql` allows a null `client_secret` on created attempts. The
  RM09 replay path (`checkouts.ts:970-977` → `provideCheckoutRedirect`) was not checked for recovered attempts that
  have no secret.
- No tests or CI were run (read-only review).
