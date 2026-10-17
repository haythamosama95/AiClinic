# R5 — Live admission, accounting and fallback

Target `db9244fddfddc1905335fb8c7105328c15a0cc5e`; baseline `c6cf2c3809a38e2a348f373e926cf2585cfcf291`; history `d2e7666f59d8ea7b37a5e05fae89f34d96ba1a3f`. **2026-10-17 Africa/Cairo. Complete with findings: 0 P0, 6 P1, 5 P2.**

Lead/synthesis `/root/abo_r5_review`: explicitly **GPT-6.1 Sol/high**. Two disjoint reviewers: `/root/abo_r5_review/admission_medium` and `/root/abo_r5_review/accounting_medium`, each explicitly **GPT-6.1 Sol/medium**. [Coverage](R5-coverage.md) / [exact JSON](R5-coverage.json) closes all **555 primary regions, 10,234 final lines and 303 deleted baseline lines**, without double counting. [Admission evidence and full recipes](R5-admission-medium.md) and [accounting evidence and full recipes](R5-accounting-medium.md) supplement the canonical decisions below. This report supersedes provisional slice advice where specified.

Source-only inspection; no tests/testkit/fixtures/harness/campaign/viewer implementation analysis, builds, lint, services, live research, source fixes, commits, pushes or checkout changes. Production runtime declarations named for test overrides were inspected only for reachability/gating; excluded helper implementations were not reviewed. HEAD and production source stayed pinned. R0–R4 findings remain canonical; R6–R10 are not started. Review completion is not approval or remediation.

## Accounting trace and state/retry matrix

The verified AI principal supplies installation/org/actor/branch and JTI; it is not a live membership oracle (R1). The guard checks coverage overlays, capability/role/scope and validated canonical request fingerprint. Normal admission sends actor/branch/capability/fingerprint plus any journal replay into the serialized DO. A matching fresh-token retry traverses its JTI gate before a stored journal answer; changed identity/payload conflicts and historical fingerprint-less rows are not replayed. Explicit version rejection becomes coverage_unknown without mirror fallback. N/N−1 negotiation echoes the accepted sender version before coverage writes.

Normal reservation records original term, request id and weight; settlement locates that reservation and positive provider tokens/cost decides consumption. Worker broker cancellation supplies partial usage; ordinary completion uses provider pricing and journal attribution from the guard. Duplicate credit finds no reservation and does not increase authoritative used again. Legacy counters are compatibility state, not coverage authority. The deleted period/invoice and staff usage mechanisms are replaced by term accounting/coverage; no live monthly commercial path was established.

The required invariants are term-local settled+reserved admission, one crossing reservation, original-term final charge, zero-capacity release, stable retry identity, durable fallback deduplication, bounded pending fallback weight, and receipt-consistent usage facts. The defects below break these invariants.

| State / failure | Source result / retry consequence |
| --- | --- |
| Normal matching admitted retry | Same reservation identity; JTI replay refused; changed fingerprint conflicts |
| Denial then slot/coverage recovery | Stored denial bypasses reevaluation for two hours (R5-A7) |
| A exhausts while requests remain, B activates | A's reserved weight reduces B's allowance (R5-A1) |
| Completion/cancel/stale after calendar boundary | Original-term used_final can lose or subtract usage (R5-A2) |
| Duplicate normal credit | Authoritative reservation removal prevents repeat used charge; journal facts still require J1 |
| DO error/timeout, mirror active before hard stop | Uncached mirror admits; timed-out DO continues under the same UUID; cap race and replay exception apply |
| Fallback provider terminal outcome | Missing term handoff exits before result/detail settlement; later drain charges indiscriminately (R5-A4) |
| Drain reply lost / D1 batch fails / concurrent drains | Same DO consumption repeats without a durable receipt (R5-A3) |
| Drain crosses allowance with queued successor | No exhaustion transition; paid successor remains blocked (R5-A5) |
| Usage already exists before drain | Row stays pending indefinitely, consuming future fallback headroom (R5-A6) |
| Zero-capacity normal terminal outcome | DO releases but journal records full manifest weight (R5-J1) |

## Findings and chosen fixes

All findings are high-confidence static source diagnoses. Paths below are relative to `ai-platform/`; links identify complete slice evidence. Recipes are implementation-ready except R5-ADM3's explicit policy decision and historical data adjudication. Implement A1/A2 before A3/A5, and the common A4 handoff before its routing/journal consumers. R4-D1/D4 remain prerequisites for atomic lifecycle/event shipment and alarm recovery, rather than new R5 counts.

### R5-A1 — P1: predecessor reservations consume successor allowance

`src/quota-do/index.ts:1208–1209,1388–1393,1434–1455`; calendar successor `coverage.ts:855–858`. Two live weight-1 requests exhaust allowance-2 A; B activates with used=0 but global reserved=2, so allowance-2 B refuses immediately. Larger successors can end early. [Evidence](R5-accounting-medium.md#a1--p1-predecessor-reservations-spend-the-successors-allowance).

**Fix steps:**
1. Add `reservedForTerm(hot, termId)` over existing reservation JSON; use it for remaining allowance, grace, bands and exhaustion in `admitOnHotRow`/`endGraceIfExhausted` and corresponding snapshot producers. Keep total reservation count for clinic concurrency.
2. Preserve old reservations and original term ids across activation; global reserved may remain a compatibility cache but cannot decide the successor's budget. Apply A2's settled-only closing rule.
3. Completion: B admits its full allowance while A remains in flight, global concurrency still applies, and old settlement never changes B. No new schema is required.

### R5-A2 — P1: late original-term consumption disappears or is subtracted

`src/quota-do/coverage.ts:825–834,895–899,1685` freezes calendar/renewed used_final without reservations; `index.ts:1609–1616` then omits ended consumed usage or subtracts cancelled weight. Settled 5 plus an in-flight weight-1 becomes 5 after consumption, or 4 after cancellation. Exhaustion instead freezes used+reserved (`1098,1450`), so one settlement rule cannot match both. Stale cleanup (`1040–1053`) has the same ended-term omission.

**Fix steps:**
1. Choose **settled-only used_final everywhere**: close every term with hot.used; remove reserved from exhaustion/grace-exhaustion closing values. Preserve outstanding reservations.
2. Normal consumed or stale settlement adds weight to its own active hot.used or ended used_final. Zero-capacity settlement/release changes no settled counter. Remove ended negative adjustments; duplicate missing-reservation credit remains a no-op.
3. Align `releaseOnHotRow`, calendar/renewal producers and R6 reversal/void/transfer consumers with this rule; keep exhaustion final after a later release. Upgrade retained exhausted rows by subtracting their still-live provisional reservations once; never guess historical missing attribution. R9 must reconcile ambiguous history from request facts.
4. Completion: consumed/cancelled/stale outcomes across expiry, renewal and exhaustion affect their original term exactly once; successor usage remains unchanged.

### R5-A3 — P1: fallback recovery repeats authoritative charges

`src/credit/index.ts:215–238` charges DO before its D1 batch. `src/quota-do/index.ts:1688–1722` always increments without a receipt, so lost reply, failed D1 batch or overlapping cron recharges the same request. Removing a matching normal reservation also bypasses the promised skip rule.

**Fix steps:**
1. Add a durable DO fallback-settlement receipt keyed by request_id, binding installation/term/weight and outcome; initialize schema before the new sender. In one SQLite transaction validate replay identity, account genuine new fallback consumption and save its receipt. Old sender payloads also create receipts.
2. Defer matching live normal reservations/replay identities **and pending usage_adjustment outbox identities**; do not add another charge. Return explicit deferred/already-accounted/settled dispositions. A charged receipt must survive response loss and the entire pending-row recovery lifetime; do not rely on a two-hour replay horizon.
3. Drain retries the same id; terminal dispositions alone enter the D1 usage/state batch. Existing durable usage must terminalize the pending row without another RPC (A6). A receipt mismatch fails closed for reconciliation.
4. Completion: concurrent drains, lost replies, failed D1 batches and late normal admission create one authoritative charge/usage event. Reconcile pre-upgrade duplicate history instead of deleting guessed value.

### R5-A4 — P1: fallback loses term attribution before provider settlement

`src/pipeline/index.ts:556–566` omits fallback termAdmission; `src/worker.ts:1269–1272` consequently returns after provider execution, before result detail/R2 envelope/real outcome accounting. Broker may mark Completed without a replayable result; cron charges even zero-capacity outcomes.

**Fix steps:**
1. Return the stored fallback term/request id, explicit accounting mode and mirrored immutable plan snapshot; propagate a common admitted accounting context through admission, guard and Worker. Replace the dummy entitlement handoff. Extend mirror/parser together to carry max_cost_class, with missing historical metadata handled conservatively as economy until refreshed.
2. Worker terminal success/failure/cancellation must journal result/envelope using that context for both modes. Persist fallback consumed/released outcome durably; route consumed weight through A3 and terminalize released zero without later cron charge. Do not credit a missing normal reservation as fallback settlement.
3. Coordinate routing with ADM2 and actual journal charged weight with J1. Completion: fallback success is replayable and charged once to its stored term; zero-capacity failure/cancel remains zero after drain; retries retain identity and cannot reinvoke the provider.

### R5-A5 — P1: fallback exhaustion strands paid successors

`src/quota-do/index.ts:1713–1718` changes used without bands/exhaustion/activation. The next admission's no-credit branch (`1394–1418`) only refuses; successor activation is in the now unreachable successful-reservation branch (`1449–1512`). A paid queued term can wait until calendar expiry.

**Fix steps:**
1. Extract a shared term-local exhaustion/band/ordered end+activation helper using A1/A2.
2. Invoke it atomically with a genuine A3 fallback receipt/charge; late ended-term charges cannot exhaust the current successor. Invoke defensively before admission's no-credit refusal to repair already stranded active terms.
3. Ship generated events through canonical R4-D4 alarm repair. Completion: fallback exhaustion activates the oldest unheld successor immediately with full allowance; replay produces no second transition.

### R5-ADM1 — P1: concurrent mirror admissions exceed the outage cap

`src/admission/index.ts:504–529` separates SUM(pending) from INSERT. Six distinct simultaneous weight-w_max calls can all observe zero and pass a five-weight cap. Rate limits permit this small burst. [Full evidence](R5-admission-medium.md#adm1--p1-concurrent-fallback-admissions-exceed-the-outage-allowance-cap).

**Fix steps:**
1. Replace the read/insertion pair with one conditional `INSERT OR IGNORE … SELECT … WHERE SUM(pending installation weight)+w <= 5*w_max` statement.
2. Distinguish zero-change duplicate identity from genuinely new cap refusal; refuse new over-cap work with coverage_unknown. Only A3/A4/A6 terminalized rows release pending headroom.
3. Completion: concurrent new-key admissions never exceed the cap, exactly-at-cap succeeds, and retries add no weight.

### R5-A6 — P2: journaled fallback rows permanently occupy pending headroom

`src/credit/index.ts:205–213` simply continues when usage_event exists. A timed-out normal request stale-charged before drain leaves its fallback row pending forever.

**Fix steps:**
1. Update that exact installation/request row to settled when durable usage exists, without another DO call or event.
2. Reuse terminalization for A3 already-accounted results; reserve pending for genuinely deferred work.
3. Completion: repeated drain closes the row and restores headroom without charging again.

### R5-A7 — P2: temporary refusals become sticky and write hot

`src/quota-do/index.ts:925–936,1256–1279,1336–1418` stores denied answers before state reevaluation. A fresh-token same-key concurrency retry stays refused for two hours after a slot frees; each denial writes hot.

**Fix steps:**
1. Return never-admitted refusals without storing idempotency/JTI entries, persisting only real boundary/stale changes under the existing no-write refusal contract.
2. Remove historical refusal entries on load/forward JSON migration; preserve admitted/terminal binding and replay entries.
3. Completion: same-key fresh-token retries reevaluate restored coverage/concurrency, unchanged denials write nothing, and admitted replay remains rejected.

### R5-ADM2 — P2: fallback raises an economy plan's provider ceiling

Mirror projection/parser (`src/quota-do/coverage.ts:288–312,2558–2583`) omit cost class. Dummy fallback entitlement leads Worker (`1110–1113`) to standard; router (`308–345,557–579`) can then admit a standard target for an economy plan. Exposure is bounded by outage allowance once ADM1 is fixed.

**Fix steps:**
1. Use A4's common plan/accounting handoff: normal uses admitted immutable max_cost_class, fallback uses mirrored max_cost_class. During migration, absent fallback cost metadata means economy, never standard.
2. Pass that ceiling consistently to routing and manifest cost inputs while retaining degraded routing tier. This canonical recipe supersedes the slice's permanent economy-only fallback recommendation; it preserves paid plan behavior after mirror refresh.
3. Completion: economy fallback excludes standard targets even when degraded policy lists them; refreshed standard fallback retains its actual ceiling; missing metadata cannot raise spend authority.

### R5-ADM3 — P2: DO outage bypasses one-use token replay protection

`src/admission/index.ts:667–684,458–565` sends JTI only to the unavailable DO. Neither fallback schema nor journal stores it. The same valid token with distinct idempotency keys invokes repeatedly until the outage cap. This is bounded token replay, not a claim that same request-id retries invoke twice.

**Fix steps — not implementation-ready; architecture owner decision:**
1. Safe stop: unavailable DO authorization yields retryable coverage_unknown until policy is chosen.
2. Architecture owner must choose a common durable JTI authority consulted by **all** normal/fallback admission (including revised write budget), or explicitly approve/amend the bounded outage replay exception. New fallback-only JTI rows cannot detect a token already consumed in the hidden DO.
3. Implement the chosen rule across normal/fallback/replay/cleanup with identity/fingerprint binding. Completion requires prior-normal and prior-fallback replay rejection, or an explicitly approved revised exception. The lower-cost implementer stops at containment while unresolved.

### R5-J1 — P2: usage journal records released quota as consumed

Lead confirmed `src/worker.ts:694–719,779–814` always passes manifest weight to `src/journal/index.ts:413–430`, even for zero-use provider failure/cancellation; DO (`quota-do/index.ts:1603–1619`) releases that reservation. Consequently durable usage facts disagree with actual accounting. Unique request_id also means a zero journal row must not outrank a prior stale conservative charge.

**Fix steps:**
1. Extend DO credit acknowledgements with authoritative settled/deferred/unknown disposition and effective chargedWeight (0 or reservation weight). Store the terminal accounting receipt in the same hot mutation as settlement; preserve it until its usage fact is durably acknowledged, rather than deleting all settlement identity immediately. A stale charge returns its existing charged outcome.
2. Propagate that result through `creditUsage`, all Worker terminal/broker paths and `PostResponseInput`. Journal uses acknowledged chargedWeight, never unconditional manifest weight. Durable pending settlement intent in ai_request retains original term/request/provider outcome while DO is unavailable; retry from the existing scheduled recovery path rather than pretending success. A3 fallback receipts provide the equivalent fallback result.
3. A usage_adjustment already durable for the same request remains authoritative; do not overwrite it with a late zero outcome. Piggyback acknowledged hot-receipt cleanup on normal mutations/recovery, preserving the normal one admission/one settlement hot-write budget; retain unacknowledged receipts through outages. R9 must include pending intents and retained receipt identities in rebuild/recovery.
4. Completion: zero-capacity release produces zero durable quota, consumed capacity produces w, late stale settlement preserves the one conservative charge, and failed DO/journal delivery remains durably pending until consistent. Historical conflicting usage facts require evidence-based reconciliation.

## Escalation dispositions and forward handoffs

| ID | R5 producer/consumer disposition |
| --- | --- |
| 066:6 | Final admission/capability/config readers use coverage; live tier/entitlement cache path removed. Deleted period/usage replacements inspected; R8 owns other removed control methods. |
| 066:8 | Reference-only harness/assertion effect; excluded implementation not inspected. |
| 066:10 | Reference-only waiting/assertion amendment excluded; actual completed-envelope source invariant checked and broken for fallback by A4. |
| 067:1 | Worker version sender → before-write DO gate/echo → admission coverage_unknown mapping checked. Credit/drain decoders' lax reply acceptance remains inherited R2-C3, not a new count. |
| 067:7 | Normal band/end/activation tokens match; fallback misses producer transitions (A5). R7 owns downstream ordering/projection. |
| 067:9 | String-array capabilities and immutable snapshot membership traced through normal admission/discovery; fallback loses cost/term metadata (A4/ADM2). |
| 068:1 | R4 calendar implementation retained as prior coverage; R5 duration consumers/propagation checked, no calendar re-audit. R9 owns deployed staging-scale isolation. |
| 089:1 | Admission/taxonomy produce allowance_exhausted, coverage_lapsed, coverage_unknown with specified statuses. R7 must close Flutter refresh consumers; no frontend review claimed here. |
| 095:1 | N sender accepted/echoed by N+1 receiver's previous-version branch; missing/outside versions refuse before mutation and map to coverage_unknown. |

**R6:** apply A1/A2 settled-only/original-term accounting to reversal, void and transfer; preserve live reservation identity and prevent source/destination double value. R4-PG1 still owns global grant/epoch identity.

**R7:** consume repaired ordered band/end/activation snapshots, complete denial-triggered refresh and existing usage snapshot shape handoff. R5 closes producers only; it does not claim those client consumers reviewed.

**R9:** preserve fallback receipts, pending settlement intents, original request/term ids and usage uniqueness through retention/rebuild; reconcile A2/A3/J1 historical divergence without guessing, and finish canonical R4-D4 wake-up/alert shipment recovery. Static review does not attest production keys, flags, alarms or service settings.

The unresolved outage replay policy belongs to architecture/maintainer; ambiguous historical attribution belongs to maintainer plus frontier/R9 adjudication. These are explicit remediation limits, not unread R5 source. **R5 complete with findings; overall review remains in progress.**
