# R5 accounting source review

Target `db9244fddfddc1905335fb8c7105328c15a0cc5e` (T); baseline `c6cf2c3809a38e2a348f373e926cf2585cfcf291` (B); provenance tip `d2e7666f59d8ea7b37a5e05fae89f34d96ba1a3f`. Reviewer: GPT-6.1 Sol, explicitly configured medium. Result: **complete with findings** for this disjoint accounting assignment. All 330 assigned regions (5,384 lines: 5,081 at T and 303 deleted lines at B) were read from their specified revision. Exact indices, supporting reads, and limits are in the companion coverage JSON. No tests, builds, lint, services, source edits, or commits were performed. Review artifacts only were written.

This report owns DO reservation/settlement accounting, credit/drain, adapter, router, worker lines 1–1392 and the assigned ancillary/deleted source. The admission reviewer owns admission/pipeline/capability/config source and worker ≥1393. Necessary narrow supporting interface reads below do not transfer ownership. Inherited R4 D1/D3/D4 and PG1 findings remain canonical there and are not recounted.

## Established trace

Normal admission serializes through `blockConcurrencyWhile`, stores reservations in the single `hot` row with original term and weight, and returns a reservation id equal to the request id. Credit locates that reservation, uses positive tokens/cost as consumption, removes the reservation once, and preserves JTI replay state. Thus duplicate credit does not duplicate authoritative `hot.used`; the separate legacy mirror does increment again. Worker completion passes the provider result through `ledgerUsageFromProvider`; broker cancellation/failure passes live partial usage. `stream.handleCompleted` does not credit independently, avoiding a second successful authoritative settlement. Journal attribution uses the guard's term id.

Fallback uses the same generated request id as the attempted DO call; timeout does not cancel that call. The D1 fallback row is the recovery input. `reconcileGraceUsage` checks D1 usage, calls `settleFallback`, then writes usage and marks the row settled in a D1 batch. The DO side has no receipt for this operation. These are separate durable boundaries.

The deleted B period-close module billed monthly usage using credit prices/invoices; deleted usage-summary exposed current entitlement/period and past period rollups. T replaces those responsibilities with terms and coverage reads, rather than retaining an active period-close import in the reviewed worker. Legacy types/helpers remain, but are not alone evidence of a reachable commercial tier path. Runtime TEST_CLOCK reads are gated by the environment flag; whether production deployment ever supplies that flag belongs to R9.

## Findings

### A1 — P1: predecessor reservations spend the successor's allowance

High confidence. `quota-do/index.ts:1208–1209` activates a queued term and resets only `used`. Admission computes remaining allowance using global `hot.reserved` at 1388–1393, total usage at 1434, and exhaustion at 1435–1455. Reservations retain their own predecessor `term_id`. For example, allowance-2 term A has two live weight-1 reservations and exhausts, activating allowance-2 B with `used=0,reserved=2`; an immediate request on B is denied despite B having consumed no credit. With a larger B, its next reservation can end B early and activate another successor. Prior reservations can therefore deny or permanently consume newly purchased terms. The same inherited global reserved value crosses calendar succession (`coverage.ts:855–858`). Concurrency can remain global; billable reservation weight cannot.

Implementation-ready fix steps:
1. In `quota-do/index.ts`, add one helper summing `hot.reservations` whose `term_id` equals the specified term. Keep global reservation count for clinic concurrency, with original term ids intact.
2. Replace active/grace remaining allowance, `usageTotal`, exhaustion and band calculations in `admitOnHotRow`/`endGraceIfExhausted` with `hot.used + reservedForTerm(currentTermId)`. Do not clear old reservations on activation.
3. Use the same helper at each snapshot/band or boundary consumer that currently treats global `hot.reserved` as the current term's liability; coordinate `coverage.ts` producers with A2's settled-only ending rule. `persistParsedHot` may retain the global cache for compatibility, but it must not decide another term's allowance.
4. Preserve the one normal request crossing bound by comparing current-term settled+reserved credits before reserving and ending the term after its crossing reservation in the existing serialized operation. No new D1 schema is required; existing reservation JSON contains term ids.
5. Complete when the allowance-2 A→B example admits B's full two credits even while A's two requests run, while global concurrency is still enforced, and settlement/stale cleanup of A cannot change B's allowance.

### A2 — P1: late settlement loses or subtracts usage on calendar-ended terms

High confidence. `coverage.ts:825/833,895/898` and grace renewal at 1685 freeze `used_final=hot.used`, excluding live reservations. `index.ts:1609–1616` adds consumed weight only while its term is active; after that term ends, consumed settlement adds nothing, while a zero-capacity settlement subtracts its weight from `used_final`. Example: A has settled usage 5 and a live weight-1 request at calendar succession. A freezes at 5. Consumption later leaves it 5 instead of 6; cancellation leaves it 4 instead of 5. Stale cleanup at 1040–1053 likewise does not charge an ended term, although it emits a usage adjustment. The exhausted ending paths instead freeze used+reserved at 1098/1450, so the present settlement algorithm cannot be correct for both modes. This violates original-term attribution and makes DO history disagree with journal/rebuild inputs.

Implementation-ready fix steps (chosen policy: `used_final` stores settled consumption only):
1. Standardize every ending producer on settled-only `used_final`. Keep calendar/grace-renewal values settled-only; change exhaustion/grace-exhaustion in `index.ts:endGraceIfExhausted/admitOnHotRow` to freeze `hot.row.used`, not settled+reserved. Retain reservation rows after ending.
2. In `settleReservationOnHot`, positive-capacity settlement adds reservation weight to `hot.used` for its active term, otherwise to that reservation term's `used_final`. Zero-capacity settlement changes neither used counter. Remove the ended-term negative adjustment.
3. In `chargeStaleReservations`, add stale weight to its active term or its ended term using the same attribution helper, then remove the reservation and emit the existing request-id adjustment. A later credit with no reservation must remain a no-op.
4. `releaseOnHotRow` removes liability only, without changing settled-only `used_final`. Apply A1's term-local reservation totals for allowance decisions and keep exhaustion final even if its crossing reservation is released.
5. Coordinate all ending producers in `coverage.ts` (including R4 renewal) and hand the same invariant to R6 reversal/void/transfer exporters and R9 rebuild consumers before landing. Existing exhausted rows include provisional weight: upgrade while reservations are retained by subtracting each still-live term reservation from those provisional endings once; expired/renewed endings already exclude them. Historical stale/settled rows with missing evidence need reconciliation, not guessed counter repair.
6. Complete when consumed/cancelled/stale requests across calendar expiry, renewal and exhaustion charge exactly their original term once, successor counters remain unchanged, and DO settled history matches unique request-id usage. Historical ambiguous repairs are explicitly outside automatic migration.

### A3 — P1: fallback drain can charge the same request repeatedly

High confidence. `credit/index.ts:215–238` commits DO consumption before its D1 batch. `quota-do/index.ts:1688–1722` neither records a receipt nor checks replay/idempotency; it always increments used/used_final and returns settled. Lost DO response, D1 batch failure, or overlapping cron invocations therefore repeat the same weight. The helper `hotStillHoldsRequestId` is unused and does not scan `hot.replay`; the RPC instead removes a matching normal reservation at 1705–1712 and charges the supplied term at 1713–1718. On an exhausted term whose current provisional final already includes the reservation, this adds it again. Durable D1 uniqueness cannot undo prior duplicate DO mutations.

Implementation-ready fix steps:
1. Add a local durable fallback-settlement receipt keyed by request id in DO schema initialization. Store term and weight, reject mismatched replays, and migrate before enabling the new drain sender. Do not rely on the two-hour hot replay horizon for durable recovery.
2. In `settleFallbackRPC`, atomically inspect receipt/reservation/replay and mutate consumption with its receipt. Existing matching normal reservation/replay or a pending usage-adjustment outbox row must not receive another fallback charge; inspect both idempotency and replay answer request ids (including priorState references), plus the local outbox request id. Return an explicit already-accounted/deferred disposition so the caller can close or revisit the D1 row safely.
3. For genuinely new fallback consumption, update exactly its recorded term under A2 and insert the receipt in the same SQLite transaction. Retain sufficient receipt identity for all pending fallback rows, regardless of response loss. Compatibility: accept old sender payload, but never bypass receipt creation for it.
4. In `reconcileGraceUsage`, only terminal DO dispositions may enter the D1 usage/state batch; retry after any lost response using the same request id. D1 usage remains insert-or-ignore. On a pre-existing usage row, terminalize the fallback row too (A6).
5. Complete when two simultaneous drains, a lost DO reply, and failure between DO commit and D1 batch each cause one authoritative charge and one usage row, including a timeout that actually reserved normally. Pre-upgrade already-duplicated consumption requires reconciliation from available request evidence.

### A4 — P1: fallback requests lose their term before provider settlement

High confidence. Supporting `pipeline/index.ts:556–566` creates `termAdmission` only for normal admitted outcomes; fallback supplies dummy legacy entitlement instead. Worker `termIdFromGuard` 331–332 reads only termAdmission; `runFreshEventSource:1269–1272` returns after actually invoking a provider if it is missing. No result detail/R2 envelope/usage settlement is written for ordinary fallback completion, and no zero-consumption outcome reaches fallback accounting. The broker may mark the D1 request Completed at 1204–1215, but completion replay then cannot load its authoritative result. Cron later charges fallback weight irrespective of provider capacity. This breaks the intended usable/replayable fallback flow, including 066:10's unchanged completed-envelope invariant.

Implementation-ready fix steps:
1. Extend fallback admission's result to carry its stored `term_id`, request id, plan snapshot and an explicit fallback accounting mode. Populate those from the uncached mirror/row and propagate them through `GuardFreshSuccess`; remove the dummy entitlement as the production accounting handoff.
2. In `worker.ts:runFreshEventSource`, derive terminal attribution from that common handoff for normal and fallback requests, eliminating the missing-term return for an admitted fallback. Routing must receive its mirrored max-cost-class too, not default standard.
3. Persist fallback outcome (consumed weight or released zero) durably before closing its recovery record. Normal DO credit must not claim to settle a missing fallback reservation. Use A3's request-id receipt/drain protocol to deliver consumed fallback once, and durably release zero-capacity fallback while preserving idempotency.
4. Keep `writeSettlementJournal` and R2 result persistence for every terminal outcome using the original fallback term/request id; store zero quota weight when nothing consumed, in coordination with the lead's journal finding.
5. Complete when a fallback provider success writes a replayable result/envelope and charges its original term once; provider-unavailable before capacity and early cancellation release it without a later cron charge. Retry keeps the same request id/term and cannot run a second provider invocation.

### A5 — P1: fallback exhaustion never activates already-paid queued coverage

High confidence. `settleFallbackRPC:1713–1718` increments current-term usage but performs no band/exhaustion/successor transition. When fallback takes the last allowance, the next ordinary `admitOnHotRow:1394–1418` only returns quota_exhausted for the active term; activation occurs only in the post-reserve branch at 1449–1512, which is no longer reachable. A queued paid successor is blocked until the old calendar boundary, and coverage events/mirror retain an active exhausted term.

Implementation-ready fix steps:
1. Extract the existing active/grace exhaustion + ordered end/activation event logic from `admitOnHotRow`/`endGraceIfExhausted` into one DO transition helper using A1 term-local totals and A2 ending semantics.
2. Call it in the same receipt/consumption transaction from A3's genuine fallback charge path. For the current term crossing allowance, end it exhausted immediately, activate the oldest unheld queued term with full allowance, and emit bands/end/activation once. An ended-term late charge must never exhaust its successor.
3. Make admission's pre-reserve no-credit branch invoke that helper defensively, so previously drained active terms with no credits can transition without another successful reservation. Schedule the resulting outbox through the canonical R4-D4 repair, rather than duplicating alarm policy.
4. Complete when an outage's fallback request exhausts A and queued B activates immediately on recovery, has its full allowance, and repeated receipt delivery creates no duplicate transition/event.

### A6 — P2: an already journaled fallback row permanently occupies the outage cap

High confidence. `reconcileGraceUsage:205–213` sees a unique usage event and simply continues. Its fallback row remains pending, and admission sums pending fallback weight (admission reviewer confirmed `admission/index.ts:506–510`). This occurs when a timed-out normal reservation is later stale-charged and its outbox writes the same request id before drain. The row then never leaves the cap, reducing future fallback headroom across subsequent outages.

Implementation-ready fix steps:
1. Change the pre-existing-usage branch to durably mark that exact fallback request settled without calling the DO or inserting more usage. Key the update by request id plus installation (not merely a broad pending scan).
2. Use the same idempotent terminalization for A3's already-accounted result. Preserve pending only for a genuinely deferred/in-flight decision that still needs recovery.
3. Complete when a stale-adjustment usage row followed by repeated drain leaves the fallback row settled, adds no charge/usage, and restores pending allowance headroom. No D1 schema change is necessary.

### A7 — P2: transient denials are cached for two hours and each denial writes hot

High confidence. `returnStoredAdmission:925–936` calls `storeAnswer` for suspended, lapsed, capability, concurrency and allowance refusals (1336–1418). A fresh token retry with the same key returns the stored answer at 1256–1279 before evaluating recovered coverage/concurrency. For example, a concurrency-limited request remains refused after a running request finishes, for the full ephemeral horizon, even though it was never admitted/journaled. Every denied attempt also mutates the hot JSON, contrary to the refusal write-budget rule in 03 §6.2.

Implementation-ready fix steps:
1. Return unadmitted refusals directly from `admitOnHotRow` after persisting only actual stale-charge/boundary changes. Do not create an idempotency answer or JTI entry for an unadmitted refusal under the current no-write refusal contract.
2. Keep fresh-JTI recording and identity/fingerprint matching for admitted/journaled idempotent answers. Remove persisted legacy refusal answers on load or via a one-time hot JSON migration, retaining admitted/terminal identity records.
3. Complete when a same-key fresh-token retry after a concurrency slot frees or coverage is restored reevaluates and admits, while no unchanged denial writes hot and admitted token replay remains refused.

## Escalations and handoffs

- 066:6: tier/cache removal is admission reviewer's canonical disposition. Accounting production handoff uses terms; retained vocabulary helpers alone are not a finding.
- 066:8 and 066:10: excluded harness/assertion effects were not reviewed. Existing production envelope invariant was checked at worker settlement and is broken for fallback by A4; R9 owns actual journal/R2 durability.
- 067:1 and 095:1: credit/drain send `CHANNEL_VERSIONS.platformDo`; response decoding checks kind/status but not an echoed version. Receiver negotiation/echo and admission coverage_unknown mapping remain lead/admission owner's interface; no incompatible rollout assumption was inferred here.
- 067:7: normal band/end/activation event tokens match the amended vocabulary; A5 identifies a missing fallback producer. R7 must verify ordered projection after repair.
- 067:9: `planSnapshotForTerm` reads capability arrays, max cost class and concurrency; worker routes from that snapshot normally. A4 addresses fallback's lost snapshot.
- 068:1: calendar implementation is R4-owned and not reopened; observed duration consumers use the existing `addDuration` interface. R9 owns production exposure of staging scale/clock.
- 089:1: taxonomy includes allowance_exhausted/coverage_lapsed/coverage_unknown with their specified HTTP statuses and supplementary fields. Desktop refresh is R7-owned.

R6: apply A2's settled-only ending invariant to reversal/void/transfer and decide export treatment of still-live reservations explicitly. R9: reconcile historical counter divergence from A2/A3 and check request-id dedup after retention/rebuild; this review does not authorize guessed historical repairs. Lead owns journal usage-weight disagreement and durable journal sequencing. No source read is claimed for those unassigned consumers beyond the exact supporting excerpts logged.
