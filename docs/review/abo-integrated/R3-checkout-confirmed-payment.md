# R3 — Administrator checkout through confirmed payment

Target `db9244fddfddc1905335fb8c7105328c15a0cc5e`; baseline `c6cf2c3809a38e2a348f373e926cf2585cfcf291`; history `d2e7666f59d8ea7b37a5e05fae89f34d96ba1a3f`. 2026-10-16 Africa/Cairo. GPT-6.1 Sol source review with two bounded same-phase reviewers and coordinator source verification/synthesis.

**Complete with findings: 0 P0, 7 P1, 6 P2.** No application changes or execution validation. These are static causal findings, not runtime reproductions. This report is canonical; linked subreports retain detailed evidence but their provisional IDs/counts are superseded here. [Coverage and escalation closure](R3-coverage.md), [machine coverage](R3-coverage.json), [checkout/UI evidence](R3-checkout-ui-subreport.md), [provider evidence](R3-provider-subreport.md).

## Established flow and limits

The actual worker gates clinic version, authenticated administrator token and per-JTI uses before offers/contact/checkout dispatch. Org/sub/JTI come from verified claims; contact/detail/list lookups constrain org, and foreign checkout IDs return not_found. R1-C1 remains unfixed: authentic expired billing tokens remain usable; do not count that again here. R2-C2/C3 own negotiated reply metadata and sender validation; R2 owns browser-return version exceptions.

Offers supply immutable commercial version and terms; checkout reads current contact and coverage (live then view), snapshots price/plan/contact hash, creates a Paymob intention and returns a hosted URL. The supplied provider base is inconsistent with its builders (C3). Creation is not durably claimed before HTTP (C2). Flutter launches the hosted page and polls ABO; browser navigation never supplies payment authority. Return GET schedules inquiry and shows neutral HTML. HMAC-valid notifications are evidence/hints; the current confirmation path requires authenticated API inquiry. Both order and acceptance inquiry order IDs must equal the stored intention order; amount/currency mismatch produces withheld payment without a grant. This establishes the implemented account boundary through configured API credentials and stored-order equality, not an independent attestation of deployed merchant ownership.

The runner takes a conditional 60-second work lease. Backoff is one minute doubling to 15 minutes, with open-row alerts after five minutes. R2 body storage precedes D1. Notification+confirm are batched, but their dedupe claim is separate. Confirmation records state/evidence before payment and next work, causing C5. Eligible payment+fact+paid event/status+grant work are batched inside recordPaidConfirmation, with payment identity unique per provider transaction. The consumer grants only disposition=grant or an explicit release, requires checkout and payment fact hash, and uses a deterministic paid grant ID; R4 owns further signature/receipt/value application. Late cancelled/expired checkouts are intended to be honoured; sweeps rematerialize +2/+5/+10/+20-minute, expiry and widening post-expiry work. Missing callback discovery and shared budgets defeat these intended guarantees (C4/C7). Paid checkout is not a valid reason to discard another captured payment (C6).

No P0 conclusion is supported. Confirmed defects can lose legitimate purchases, block buying or recovery, bypass cost bounds and misstate accepted terms. Live provider expiration, discovery completeness, actual environment overrides, secrets/account ownership and deployment settings cannot be proved from source. Creation ambiguity recovery and callback-free discovery need the explicit external decisions below; source coverage itself is closed.

## Major findings

### R3-C1 — P1: real administrator billing layout fails before purchasing

High confidence; implementation-ready. `frontend/lib/features/ai/billing/administrator_billing_page.dart:128–168` nests every billing step in SingleChildScrollView/Column. `offers_screen.dart:123–140` has vertical Expanded, contact form uses vertical flex, and `checkout_screen.dart:416` has Spacer. The scroll parent supplies unbounded vertical height, so these nonzero-flex Columns cannot lay out. This breaks the actual parent flow, including loading, regardless of provider state.

**Fix steps**
1. Keep AdministratorBillingPage as the scroll owner. In offers_screen.dart, billing_contact_form.dart and checkout_screen.dart remove vertical Expanded/Spacer; use ordinary content and explicit spacing.
2. Replace the offers nested ListView with a shrink-wrapped non-scroll list/Column so offer and long terms content flow through the outer scroll view. Retain horizontal Expanded inside bounded rows.
3. Completion: each step's loading/error/offer/contact/new/resumed checkout content lays out within the real parent at short/tall window heights; long terms remain reachable and purchasing controls visible.

### R3-C2 — P1: provider creation precedes durable checkout identity and retry ownership

High confidence; **local remedy ready; external ambiguous-outcome recovery not implementation-ready**. `abo/src/clinic-api/checkouts.ts:540–547` reads the request key; `578–604` generates a new ID and calls provider; `637–759` only later writes checkout/status, then fact/event separately. `provider/paymob/adapter.ts:183–207` stores the intention first. Concurrent same-key calls create different intentions before the unique org/key constraint rejects one. A crash after intention storage or an HTTP timeout causes a new attempt with a new identity; a crash after checkout/status but before fact/opened event returns an apparently valid replay missing export evidence and sweep recovery (`work/sweep.ts:123–126`). Existing-key handling does not compare payloads. Contact writes likewise return old data for a reused key (`billing-contact.ts:107–116`); the form retains its key when edited after error, silently saving the previous values on lost-success retry.

**Fix steps**
1. Add a forward D1 migration for durable checkout creation state keyed `(org_id,client_request_id)`, stable checkout ID, canonical intent fingerprint and creation lease/token. Atomically reserve the immutable snapshot, fact and creation event before HTTP; store the actual starts decision/projected_start rather than reconstruct it from any nonnull historical coverage end.
2. Have matching retries resume that operation and contenders reread it; changed payload must return a documented idempotency conflict (add one additive clinic error/typed Dart handling, without rewriting stored messages). Pin the entire id/version/terms intent for a retry. Do the same payload comparison for contacts; edits after a pending save require a new key, and contact MAX+1 insertion must retry version collisions atomically while rereading same-key winners.
3. Use the creation lease for one provider attempt and stable reference; commit provider result/status/event/fact and durable recovery scheduling together. Never hold a D1 transaction across HTTP. Make schedule rematerialization derive from the durable creation state so a lost response does not require a second purchase.
4. **Maintainer/provider integration owner must establish an idempotent-create or stable-reference lookup contract for crash-after-HTTP-before-store.** Stop before assuming a Paymob capability. Until resolved, retain ambiguous creation in a visible recoverable/held state and alert; do not blindly POST another intention. Final callback discovery decision is C4.
5. Completion: concurrent matching requests have one durable operation and redirect; every crash boundary retains facts and resumable work; changed payload cannot return misleading old success. Deploy migration/receiver/error support before updated desktop handling. Full restoration of automatic ambiguous recovery awaits step 4.

### R3-C3 — P1: supplied Paymob configuration composes the wrong endpoints

High confidence; implementation-ready. `abo/wrangler.toml:25,66,105` sets base `https://accept.paymob.com/api`. `provider/paymob/client.ts:89–105` appends `/v1/intention/` and `/api/...`; adapter `97–104` appends `/unifiedcheckout/`. This produces `/api/v1/intention/`, `/api/api/auth/tokens` and `/api/unifiedcheckout/`, inconsistent with the pinned contract paths, breaking checkout/inquiry for the supplied configuration. No live endpoint result is claimed.

**Fix steps**
1. Define PAYMOB_BASE_URL as an HTTPS origin and change all three wrangler values to `https://accept.paymob.com`.
2. Have client/adapter URL helpers parse and reject unexpected pathname/query/fragment; retain the explicitly authorized local transport separately. Keep the current pinned absolute API/hosted-page paths and encoded parameters.
3. Completion: supplied configurations produce exactly `/v1/intention/`, `/api/auth/tokens`, `/api/ecommerce/orders/transaction_inquiry`, `/api/acceptance/transactions/{id}` and `/unifiedcheckout/`, including trailing-slash inputs.

### R3-C4 — P1: callback-free recovery queries a hardcoded unrelated transaction

High confidence; **discovery remedy not implementation-ready**. `client.ts:175–194` discards transaction identities from order responses. `adapter.ts:730–739` selects callback/stored transaction or literal `99001`, and returns only one transaction (`767`). A paid checkout with no callback has neither source identity: all sweeps query 99001 and cannot discover its actual captured payment. Order binding prevents granting that unrelated transaction but does not recover the sale. FM-02 recovery and early FM-01 recovery fail.

**Fix steps**
1. Ready containment: remove 99001; return explicit discovery-unavailable/deferred status, preserve due confirmation/sweep work and raise one recovery alert per checkout. Never report this as a completed empty order.
2. **Decision owner: maintainer/provider integration owner with frontier validation.** Resolve R-2: freeze the authoritative order-scoped transaction enumeration response, pagination/completeness and stable identity semantics. Stop before coding guessed response fields; source-only review cannot supply this external fact.
3. Then retain/validate all transaction identities in the client decoder; fetch and bind each to the stored order. Callback IDs are hints, not the only discovery mechanism. Complete-empty differs from unavailable/incomplete.
4. Return/process the complete success set using C6; payment_id inquiries must resolve that exact parent transaction rather than the latest callback of its checkout. R6 owns reversal-specific effects. Completion: zero-callback captured payments and two captures are both discoverable, while unrelated IDs cannot grant.

### R3-C5 — P1: dedupe markers can commit without the payment/work they suppress

High confidence; implementation-ready. `work/runner.ts:595–597` treats an existing state marker as completed. Yet `816–818` commits that marker/inquiry before `819–826` records payment and grant work. A process failure or D1 failure between them leaves no payment; every retry marks confirm done and sweeps eventually hit the same marker. Separately `notify/intake.ts:229` commits body claim before notification+work batch `235–263`; a crash turns redelivery into duplicate without creating its original confirm work. Both violate 03 §2.9 step atomicity. The first gap persists even with perfectly working callback discovery.

**Fix steps**
1. Refactor recordPaidConfirmation to prepare statements rather than commit internally. Commit state marker, retained inquiry/evidence reference, payment+fact, paid event+fact/status, next grant work and current confirm completion in one D1 batch. Use payment identity as idempotent outcome, not marker existence alone.
2. Fence **every statement**, including fact_log and the final work UPDATE, with `EXISTS (SELECT 1 FROM work WHERE work_id=? AND state='open' AND lease_token=?)` using a unique token added in a forward migration; acquire a fresh token on every take. Because a D1 batch is atomic, this predicate either permits the complete batch for its owner or makes all its statements no-ops for a replaced owner. A final UPDATE returning zero followed by a JavaScript throw does not roll back an already committed batch. Do not rely on the earlier leaseStillHeld SELECT across network awaits.
3. Move notification body reservation into its notification+confirm+fact batch using one unique body identity; a collision rereads the already committed original work. Store raw R2 body first; an orphan raw object is acceptable, an orphan dedupe claim is not.
4. Add a forward recovery pass that identifies existing seen/body claims missing their corresponding payment or original work and reopens/requeues them for authoritative inquiry. Do not clear claims for already applied payments/grants or blindly create value from callback text.
5. Completion: crashes between any former writes leave either the complete outcome or due work; two workers/replayed bodies create one payment per identity and one grant work; a stale lease cannot commit facts. Coordinate R9 export/rebuild and R4 deterministic grant replay.

### R3-C6 — P1: already-paid checkout silently loses another successful charge

High confidence; implementation-ready, discovery depends on C4. `runner.ts:564–567` marks success work done solely because checkout state is paid, before inspecting payment_id. Lifecycle 03 §5.1 explicitly permits paid→paid and every captured transaction must be recorded. Distinct valid success callbacks on one order therefore acknowledge the second charge but create neither payment nor grant. Adapter returns one transaction and consumers inspect `[0]`, compounding discovery loss.

**Fix steps**
1. Remove checkout-state success shortcut; process each bound successful transaction from the complete inquiry set. Deduplicate only by payment_id/state identity, not checkout paid status. Keep amount/currency checks for each capture.
2. Apply C5's atomic payment/outcome batch per transaction; existing payment must have matching immutable checkout/provider/amount/currency identity and existing grant work before returning done. Treat conflicting immutable identity as invariant error, never overwrite it.
3. Keep checkout paid/paid_late as summary; record every capture and deterministic grant work, and classify subsequent same-coverage payments consistently (including a second capture of this checkout; current classification query excludes it at `306`). Require an actual earlier payment identity; null coverage endpoints compare null-safely for duplicate labeling.
4. Completion: two different successful IDs produce two payment facts and grants; duplicate same ID produces one; mismatched amount stays withheld; cancelled/expired capture stays late and is honoured once. R4 owns term stacking after this boundary.

### R3-C7 — P1: shared inquiry cap is bypassed and cannot reserve concurrent work

High confidence; implementation-ready. Intake `466–472` runs confirmation before budget. `inquiry-budget.ts:148–176,202–215` reads local spend then increments after calls; concurrent inline/cron workers overspend. Sweep `288,361` and runner `864,891` perform nested inquiries but report one boolean; unbound/error paths may report false after HTTP. Grants consume a fictitious unit (`184–196`) although they never inquire, and reversal verification runs before confirmations (`153–159`), allowing repeat reversals to starve purchases. This defeats 080:3 cap=2 and priority under ordinary callback/concurrent scheduling.

**Fix steps**
1. At provider inquiry entry acquire one shared logical-attempt reservation **before** HTTP: initialize minute row with INSERT ON CONFLICT DO NOTHING, then atomic `UPDATE inquiry_spend SET spent=spent+1 WHERE minute_key=? AND spent<2 RETURNING spent`. No slot returns typed deferred without network. Never refund for timeout/unbound/crash.
2. Route all inline, confirm, sweep, reversal verification and rebuild inquiries through this helper; remove post-hoc boolean accounting. Deferred callers retain open/due work. R9 applies this to rebuild.ts628/635/646/684.
3. Reuse the typed authoritative result when sweep invokes confirmation and when no-notification confirmation proceeds; do not inquire again to enter its commit function. Guard/remove the alternate runDueConfirmWork bypass.
4. Schedule confirms first, grants independently without provider spend, then reversal/sweep inquiries. Keep existing cap meaning of two logical provider inquiries; external per-HTTP quotas (each inquiry currently uses order+transaction and optional auth calls) remain a separately unverified rate assumption.
5. Completion: concurrent inline/cron/rebuild admit at most two attempts per minute; failures consume their reservation; grants do not starve sweeps; pending reversals cannot take confirmation priority; overflow is retained due.

## Moderate findings

### R3-M1 — P2: one-second polling outlives its token's use budget

`checkout_screen.dart:155` polls every second; rate.ts41 refuses after 60 uses, while billing_token_client.dart47–64 reuses for roughly 270 seconds. Other page reads accelerate exhaustion. Progress then stalls on 429 for several minutes although payment may have succeeded. High confidence; implementation-ready.

**Fix steps:** (1) Centralize concurrency-safe local token-use reservation in BillingTokenClient/AboClient and rotate before 60 sends, retaining mint coalescing/expiry renewal. (2) Permit only one in-flight checkout refresh; back off on 429, invalidate unexpected exhausted token and retry a GET once with a fresh token. Mutations retain their frozen key/payload. (3) Completion: multi-minute waiting continues observing state without a blind interval, overlapping refreshes or mint storms.

### R3-M2 — P2: request and checkout admission bounds race

`clinic-api/rate.ts:36–59` reads then inserts/increments, so last-slot concurrent calls exceed 60 and first-use overlaps can throw. `checkouts.ts:207–225,549` checks ten/hour separately from creation. Notify IP gate also reads/checks/updates separately (`intake.ts:56–95`). High confidence; implementation-ready; R1's per-JTI handoff closed here.

**Fix steps:** (1) Replace token read/write with atomic conditional upsert/increment returning a row only below 60; no row returns existing 429. (2) Serialize hourly admission in C2's durable reservation transaction using authoritative creation timestamp, not separately appended fact_log; matching replay consumes no new slot. (3) Make notify window reset/increment/admission one atomic conditional statement, retaining missing-IP unknown key. (4) Completion: overlapping last-slot requests admit exactly one, first uses do not 500, window rollover is correct and refused requests store/enqueue nothing.

### R3-M3 — P2: displayed, accepted and stored sale terms disagree

Offers serve historical offer.terms_version (`offers.ts:108–118`); POST requires global MAX (`checkouts.ts:558–560`) yet stores offer terms (`626,734`). Publishing newer terms while an older offer remains sellable causes a permanent terms_not_accepted loop; a direct current-version request records the wrong accepted text. High confidence; implementation-ready.

**Fix steps:** (1) Follow the current-global-terms contract: offers must serve current text/version independently of historical offer version. (2) Validate that same current selection on creation and snapshot parsed.terms_version in canonical and SQL row; retain immutable old terms records. (3) Newer terms between GET/POST returns existing 409 and requires acceptance. Completion: unchanged offers remain purchasable after terms publication and the checkout exactly names accepted text.

### R3-M4 — P2: offer recovery substitutes an undisplayed package

Checkout screen `262–280` refreshes only price/version (even falling back to a different offer's version), then `190–194` submits it with original offer/terms. New duration/allowance/copy need not be shown or selected. OffersScreen147 also changes selection without clearing accepted terms. High confidence; implementation-ready.

**Fix steps:** (1) Remove override/fallback; add parent onOfferUnavailable callback returning to OffersScreen with cleared selection/acceptance/request ID. (2) Show/select the full new offer and accept its current terms before a fresh purchase intent. Reset acceptance whenever offer/terms identity changes. (3) Freeze old payload for transport retries only. Completion: no POST sells a package whose complete displayed details were not selected.

### R3-M5 — P2: notification byte cap checks characters after unbounded allocation

Intake329–332 calls request.text then compares body.length to 1 MiB; multibyte UTF-8 exceeds the byte cap while passing character count. High confidence; implementation-ready.

**Fix steps:** (1) Stream bytes, cancel after limit+1; Content-Length may fast-refuse but is not authoritative. (2) Return empty 413 before rate/evidence/work writes on overflow, decode only bounded valid bytes and hash exact stored bytes. (3) Completion: 1 MiB boundary holds for ASCII/multibyte bodies and overflow stores/enqueues nothing.

### R3-M6 — P2: checkout shows minor units as full currency amounts

OffersScreen222 and CheckoutScreen399 interpolate integer priceMinor with currency directly. A 10000-minor-unit EGP offer displays 10000 EGP while provider charges 100.00 EGP. Bounded presentation/consent defect; high confidence; implementation-ready.

**Fix steps:** (1) Add one billing monetary formatter for supported EGP two-decimal major units, using locale formatting and retaining integer wire/storage values. (2) Use it in offer selection and checkout, including refreshed/resumed snapshot amounts; share with R7 history presentation when that consumer is reviewed. (3) Completion: 10000→100.00 EGP and 1→0.01 EGP, without changing charge or grant data.

## Handoffs and residual boundaries

**R4:** Eligible normal path is bound authenticated success, matching amount/currency, payment disposition grant + fact hash and queued grant work. C5/C6 must be consumed before relying on exactly-once grant inputs. Withheld payments need explicit HP release; reversed-before-grant has no grant work. Review full reversal-before-grant/grant race and receipt/term placement there, not in this phase.

**R6:** Provider payment_id inquiries resolve checkout then latest callback/first transaction rather than exact parent (C4 fix propagation). Callback reversal normalization reads unsigned refunded_amount_cents (`adapter.ts:535–547`), parent fallback guesses local first transaction (`471–520`), and child acceptance fullness compares its amount (`418–440`). Intake420 can record callback reversal before inquiry. R6 owns authoritative cumulative/fullness/dedupe and effects together; these are precise seam obligations, not assertions that the full reversal phase was reviewed. 080:2 disposition stays bounded accordingly.

**R9:** Notification/inquiry inserts lack fact_log despite append-only schema. Runner shouldWriteInquiryResult compares only checkout subject/kind/cumulative; a new inquiryId may be used by payment even when no inquiry row was written (`625–650,819–824`), especially differing transaction successes after C6. Preserve/reuse an existing exact evidence identity or always store the decisive per-transaction inquiry, including raw authenticated provider response rather than only normalized txn JSON. Provider occurred_at is inquiry clock (`adapter.ts:602`), so paid_at is not an externally established payment time; provider timestamp schema is another external decoder fact, not guessed here. Cancel/retry commits state before operator_action/platform audit (`ops/index.ts:1980–2014,2041–2087`) and cancellation lacks fact_log on its event; R9 must cover audit outbox/recovery and rebuild implications; R8 owns remaining console policy. R9 also owns invalid-HMAC list pagination/retention assumptions and actual secret/test override isolation. No remediation to these later-phase algorithms was performed.

**R5 inventory correction:** the R3 manifest includes quota-do ReleaseRequest/releaseRPC admission rollback regions. They were read as assigned but do not participate in checkout or confirmed payment; retain their business ownership in R5 and do not infer an admission review from this phase.

All ten escalations have dispositions in coverage. Browser-return URL version and billing JTI are propagated; no return query directly grants value. Resuming by CK reference works for polling but exposes no hosted redirect, so reopening a lost browser page is a frozen-contract/product recovery limit for maintainer/R7, not an invented endpoint finding.

The target and tracked source remained unchanged. No tests/builds/lint/campaigns/services/live provider research or excluded code correctness review occurred. A full read of the mixed records/append.ts file incidentally displayed fixture helper content beyond insertFactLog; only its production helper was analyzed, and excluded helper content was not used as evidence. This disclosure qualifies the narrower claim of no excluded-material exposure. R0/R1/R2 remain complete; R4–R10 remain not started; overall review remains in progress.
