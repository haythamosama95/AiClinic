# R6 — Reversals, operator value changes, transfer and deletion

**Complete with findings: 0 P0, 10 P1, 3 P2.** Target `db9244fddfddc1905335fb8c7105328c15a0cc5e`; baseline `c6cf2c3809a38e2a348f373e926cf2585cfcf291`; history `d2e7666f59d8ea7b37a5e05fae89f34d96ba1a3f`. Completed 2026-10-17 Africa/Cairo. HEAD/master and tracked source remain T. T/H differences remain workflow/captured-artifact paths only; these were metadata, not review inputs.

Lead/synthesis `/root/abo_r6_review`: explicitly **GPT-6.1 Sol/high**. Three bounded reviewers, `abo_reversal`, `do_mutations`, `platform_transfer`: explicitly **GPT-6.1 Sol/medium**. [Coverage](R6-coverage.md) / [JSON](R6-coverage.json) closes all **230 manifest tuples / 6,044 primary lines**, assigned disjointly before reads; no unread primary or required R6 seam remains. Lead independently verified targeted material conclusions; these supporting verification reads do not duplicate primary ownership. Exact recipes and source evidence are retained in four compact slice reports linked below.

## Established flow and invariants

Authenticated provider evidence should resolve the original payment parent, derive cumulative fullness against the original amount, and create one immutable reversal per parent/state/cumulative. Callback-first records currently precede inquiry; BR1 shows why signed transport alone does not establish financial truth. A full reversal selects a tombstone before grant, ends current/grace and holds successors, removes its queued/held term, or records no service effect for genuinely ended value. Partial reversal is deliberately refused automatically and remains an operator review case. DO derives actual effect from current term state; the ABO reason is audit/replay input. Exact retry preserves original receipt.result=applied under outer already_applied. Nil org/installation, seq0 and empty terms are the intentional before-grant tombstone shape.

Coverage authority resides in the per-installation DO; asynchronously shipped D1/R2 ledger rows cannot prove absence or current location. Grant lineage must retain original grant identity across every transfer. PT1 adds authoritative stable/moving routes to R4-PG1's global identity repair so delayed grants/voids cannot recreate or miss transferred/deleted value. New/late mutations must verify exact org, installation, epoch and route generation; terminal receipt replay must not depend on the current live binding.

Transfer is HP begin authorization followed by M out/in work, same org, next binding epoch. Package order is term position; transfer grant IDs use stable zero-based decimal package index, and origin_grant_id survives. Conservation requires destination remaining allowance/time to equal frozen source remaining value, queued/held full value to remain unchanged, and pending requests to settle/release on their original source terms before immutable export. The current implementation neither drains pending work nor durably replays local transfer steps; DM1/DM2/PT2 repair those connected boundaries without silently deleting reservations.

Suspend/resume changes an availability overlay while calendars run and existing requests retain accounting identity. Adjustment adds value only to active coverage; grant atomicity, lifecycle catch-up, ceilings and verified credential attribution remain canonical R4 findings. Release during grace is independently wrong (DM4); the chosen remedy uses the existing grace-renewal placement rule: close old grace renewed, anchor released coverage at the old ends_at, and retain one current term.

Deletion must first prove and freeze authoritative inventory, hold any remaining value, and retire only a proved empty/no-pending-value installation. Purge must preserve immutable commercial facts, live-term usage, lineage and command receipts. Contact erasure blanks all contact versions and deletes raw payer bodies while keeping hashes/payment facts; O2 addresses later asynchronous bodies after erasure. No legal retention period is inferred.

## Major findings and exact remedies

Every finding is high-confidence static source reasoning. Recipes below are implementation-ready except BR1's explicitly named external cumulative decision and historical-data adjudication limits. Detailed ordered recipes are authoritative at the linked slice heading; no fixes were applied.

### R6-DM1 — P1: transfer restores spent allowance

Active export stores remaining allowance plus original plan_allowance (`ai-platform/src/quota-do/coverage.ts:2913–2927`); import selects the full allowance and sets used0 (`3166–3169,3188–3191`). Transferring after consuming40 of100 restores100 instead of60. [Evidence and full recipe](R6-do-mutations.md#r6-dm1--p1-active-transfer-restores-already-consumed-allowance).

**Fix steps:**
1. Preserve full allowance and derive used=full−remaining, validating finite integer bounds before any writes; preserve exact grace usage/base/cap and all calendar deadlines.
2. Freeze every admission path and drain original-term reservations/fallback intents before export using R5 accounting; never drop them to make transfer finish. Commit/replay through DM2.
3. Completion: repeated transfers retain60 of100 after40 consumed, identical grace remaining budget, and unchanged queued/held value; late source settlement cannot change already-exported destination value.

### R6-DM2 — P1: lost transfer replies lose or duplicate moved terms

Out mutates before signing and stores no replay (`coverage.ts:2991–3030`); retry exports an empty package. In inserts a random term before deterministic grant PK (`3159–3186,3227–3237`), so retry leaves orphan terms before conflict. Receiver persists D1 step only after DO reply (`coverage/transfer.ts:350–401,454–491`). [Full recipe](R6-do-mutations.md#r6-dm2--p1-transfer-steps-lack-durable-do-replay-and-can-lose-or-duplicate-moved-terms).

**Fix steps:**
1. Add permanent DO `(transfer_id,step)` records binding endpoints/epochs/package hash and original package/terms/receipt; prepare/sign before a synchronous transaction commits all local changes plus replay. Enforce one imported term per transfer grant and expose historical conflicts.
2. Receivers accept local applied/already_applied, copy the original evidence once, and CAS matching D1 steps. Store each canonical package element as its per-grant envelope matching envelope_sha256, with accepted transfer authorization linkage; retain it in recovery. Emit the named per-grant grant_applied event for each signed ledger_seq, then final transfer event.
3. Completion: missing reply/D1 step returns identical original package/term IDs/receipt, with no empty overwrite, orphan term or duplicate value. R9 preserves records across rebuild.

### R6-PT1 — P1: refunds can miss applied, transferred or held value

Receiver picks current location from delayed grant_ledger (`vendor/entrypoint.ts:4008–4025`), requires an active binding (`4085–4108`), or writes a nil tombstone when ledger absent (`4115–4143`). A grant already applied but not shipped survives an acknowledged refund; a transfer can route to ended source; deleted held value is rejected. Tombstone D1-before-R2 also leaves no recoverable receipt after R2 failure. [Full recipe](R6-platform-transfer.md#r6-pt1--p1-reversal-routing-treats-lagging-copies-and-active-bindings-as-authoritative).

**Fix steps:**
1. Extend R4-PG1 claims with durable reversal commands and original-grant value routes `(installation,epoch,generation,stable/moving/retired)`. Atomically claim tombstone versus grant identity; ledger absence never establishes no DO value.
2. Serialize source void/export via durable local seals; moving routes keep reversal due/transient, then CAS to imported destination. Accept exact held routes for void, fence all mutations by endpoint/epoch/generation, and replay terminal evidence without live-binding dependence.
3. Persist receipt plus R2 export obligation with command completion; never sign a replacement or scan all void objects. Completion: refunds racing apply/shipment/transfer/deletion remove actual remaining value once; R2 outage retains replayable original receipt.

### R6-BR1 — P1: partial child/callback evidence can trigger a full void

Adapter compares child cumulative to child amount (`abo/src/provider/paymob/adapter.ts:418–440`); recorder ORs that flag with parent comparison (`work/reversal.ts:535–536`). A20 refund of a100 payment can void all coverage. Callback unsigned cumulative and guessed parent are persisted before inquiry; later verification accepts a lower-bound comparison without replacing callback-derived effect (`674–699`). Pending child flags also precede pending classification. [Full recipe and decision stop](R6-abo-reversal.md#br1--p1-childcallback-evidence-can-authorize-a-full-void-of-a-partial-refund).

**Fix steps:**
1. Store callbacks only as durable inquiry hints. Bind authenticated child→exact parent→original payment/order/currency; pending/unknown results defer. Remove adapter fullness override and derive full exclusively as authoritative cumulative≥original payment amount.
2. Construct final reversal/effect/dedupe only from that inquiry; batch evidence/fact/next work under R3-C5 fencing. Parent resend/child delivery share one key. Historical guessed rows require explicit adjudication.
3. Completion:20/100 remains partial; cumulative100 creates one full reversal; changed parent/unknown/pending cannot void coverage. **Not fully implementation-ready for provider cumulative decoding:** provider integration owner plus frontier reviewer must resolve exact terminal parent cumulative/missing-field semantics under R3-C4. Safe stop is defer+alert, never invent cumulative from child amount.

### R6-BR2 — P1: partial or dismissed reversal disables later refund discovery

Any reversal closes payment sweeps (`reversal.ts:557–562`) and central due selection excludes every payment with any reversal (`work/inquiry-budget.ts:101–105`). A later full refund with lost callback is never discovered. Six-hour population additionally chooses one live payment per org (`sweep.ts:672–709`), skipping other queued/held payments. [Full recipe](R6-abo-reversal.md#br2--p1-one-reversal-permanently-removes-the-payment-from-future-discovery).

**Fix steps:**
1. Remove any-reversal anti-joins and blanket sweep completion; finish only the verified attempt. Continue monitoring to the stated180-day horizon using cumulative dedupe.
2. Schedule every live-funded payment, retaining per-org response caching but removing seenOrgs suppression. Use R3-C7's single atomic budget; overflow remains due.
3. Completion: partial→full without callback is discovered; dismissed hints cannot disable inquiry; each queued/held purchase gets six-hour eligibility without duplicate reversal.

### R6-PT2 — P1: destination becomes live before transfer admission fences exist

Begin retires source/publishes active destination (`coverage/transfer.ts:254–293`), then opens awaiting_transfer (`295–300`). New grants can beat initialization; failed initialization replay only returns the row. [Full recipe](R6-platform-transfer.md#r6-pt2--p1-transfer-publishes-its-destination-before-the-destination-admission-fence-exists).

**Fix steps:**
1. Persist one accepted preparation per source epoch with reserved destination/next epoch, actor and immutable authorization, using R4-PG3 acceptance. Initialize destination fenced to that transfer, then freeze/drain source; replay resumes each acknowledged phase.
2. Only after both acknowledgements CAS source retirement and destination publication atomically. Grant dispatch honors preparation and PG1 seals; successor lifecycle actions wait for completion or proved no-effect cancellation.
3. Completion: unknown initialization never exposes destination, new purchases cannot overtake moved value, and stale sources cannot retire successors. Bounded scheduled recovery plus O1 provides eventual progress.

### R6-PT3 — P1: deletion retires unknown coverage and skips unfinished purge

Inspection unavailable/malformed becomes empty (`coverage/transfer.ts:580–594`); delete retires (`652–687`) or ignores freeze response (`673–676`). Deleted+held replay returns before incomplete purge (`641–648,705–715`). Existing value becomes detached or payloads persist despite successful retry. [Full recipe](R6-platform-transfer.md#r6-pt3--p1-deletion-can-retire-unknown-coverage-and-reports-incomplete-deletion-as-complete).

**Fix steps:**
1. Persist a target-pinned deletion command/phase under lifecycle exclusivity; distinguish successful snapshot from unknown. Serialized DO freeze returns stable open-term/pending-request inventory; unknown remains due and cannot retire, including retireHeldBindingIfEmpty.
2. CAS D1 deletion/held-or-retired only after acknowledgement, preserve open-term usage, and persist alert/purge obligations. Resume purge after binding retirement using original target; success requires purge completion, not only status flags.
3. Completion: interruption at inspection/freeze/purge resumes same epoch; no unknown coverage retirement or newer-epoch deletion; held AL-18 logical alert occurs once.

### R6-DM3 — P1: void/release effects precede replayable evidence

Reversal, release and manual void change terms/events before asynchronous signing and replay (`coverage.ts:2165–2259,2364–2412,2458–2540`). Interruption makes release/void retry reject or reversal sign a changed no-effect receipt. This is the independently implemented R6 mutation root; R4-D1 remains canonical for grants. [Full recipe](R6-do-mutations.md#r6-dm3--p1-reversal-release-and-manual-void-commit-effects-before-replayable-evidence).

**Fix steps:**
1. Prepare complete state/events/sequences and sign before value writes under concurrency serialization. Commit terms/hot/events/void export and permanent request-bound receipt in one synchronous SQLite transaction, including R5 original-term used_final.
2. Bind replay to exact reversal body or HP arguments, reject different payloads, and use R4-D4 durable alarm/replay repair.
3. Completion: precommit failure changes nothing; postcommit failure returns original receipt/sequence/effect; successful release cannot become bad_request on lost reply.

### R6-DM4 — P1: held release during grace creates two current terms

Release checks only active (`coverage.ts:2351–2354`), then activates held/reset used (`2364–2371`) while existing grace survives. Admission/boundary can select/clear the older grace, leaving counters inconsistent with the new active term. [Full recipe](R6-do-mutations.md#r6-dm4--p1-releasing-held-coverage-during-grace-creates-two-current-terms).

**Fix steps:**
1. Reuse caught-up placement: live grace closes renewed and released coverage starts at prior ends_at; active coverage queues it; true lapse starts now. Preserve original-term reservations and settled usage.
2. Atomically emit ended→released→activated plus receipt via DM3; maintain one current term and matching hot pointer with term-local budgets.
3. Completion: old grace expiry cannot clear released coverage; late old usage remains on its old term. This differs from R4-D2's stranded complimentary queue.

### R6-O1 — P1: operator acceptance can lose the mutation or transfer runner

Local HP consumes challenge before release/manual/erase effects (`abo/src/ops/index.ts:750–771,1113–1145,1212–1258,1346–1355`); replay rejects used challenge. Begin calls platform before audit/work (`2988–3043`); crash or lost reply can leave transfer without its only ABO runner. [Full recipe](R6-lead-ops.md#o1--p1-accepted-operator-actions-can-lose-their-mutation-or-transfer-runner).

**Fix steps:**
1. Add ABO challenge-keyed accepted commands with exact bytes/actor/target/version/stage; atomically accept authorization/audit and resume identical retries. Apply local facts+next-work+stage in fenced batches; recheck full reversal atomically before payment release.
2. Persist begin intent before dispatch, recover same platform authorization, then batch transfer ID+work. Audit delivery and raw deletion become resumable stages. Before finishing any in-success shortcut, reconstruct/verify all per-term requests from original signed out package using R4-A2 receipt linkage.
3. Completion: every consumed action has discoverable completion/recovery; every accepted transfer has one runner, even after lost begin reply. R2-P1 target binding is prerequisite; R3-C5 and R4-PG3 remain their own canonical stores/flows.

## Moderate findings

**R6-BR3 — P2: voids are recorded as refunds.** `reversal.ts:477,493` hardcodes refund despite adapter void kind. Fix steps: (1) pass validated authoritative kind through SQL and canonical fact, (2) retain parent/state/cumulative identity and flag conflicting kind, (3) verify D1/export/history preserve kind; historic correction stays explicit. [Full evidence/recipe](R6-abo-reversal.md#br3--p2-provider-voids-are-permanently-recorded-as-refunds).

**R6-DM5 — P2: suspension event token violates closed contract.** `coverage.ts:1964` emits suspend/resume instead of suspension_changed. Fix steps: (1) emit suspension_changed with unchanged snapshot overlay, (2) R7 verifies consumers and R9 accepts historical aliases without rewriting facts, (3) both toggles preserve calendar/reservations and increasing sequence. No unverified consumer outage is asserted. [Full recipe](R6-do-mutations.md#r6-dm5--p2-suspension-events-use-tokens-outside-the-amended-closed-set).

**R6-O2 — P2: late callback recreates erased raw payer evidence.** Erasure selects/deletes current keys (`ops/index.ts:1287–1320,1348–1355`); later old-checkout callback unconditionally uploads raw body (`notify/intake.ts:364–374`). Fix steps: (1) persistent org erasure generation plus registry/claims for every raw key, (2) atomically claim generation, upload, finalize/recheck and delete stale generations via cleanup outbox, including orphan writes, (3) new contact permits new checkouts only; late old evidence retains hashes/normalized commercial facts. Completion covers callback before/during/after erasure and R2-success/D1-failure. [Full recipe](R6-lead-ops.md#o2--p2-erasure-does-not-fence-late-provider-body-writes).

## Failure-state/retry and consumer handoff

| Boundary | Current failure / required recovery |
| --- | --- |
| Callback→authoritative reversal | Unverified fullness/dedupe poison; BR1 hint→inquiry, BR2 continuing monitoring |
| Reversal fact→work | Orphan after failure; extend canonical R3-C5 batch to reversal/work and reversed-before-grant confirmation |
| Void before/during grant | Ledger absence race; PT1 terminal global claim and serialized local seal |
| Active void→held successors | DM3 atomic evidence; R5-A1/A2 own settled/reserved/historical accounting |
| Begin→fences→binding epoch | PT2 durable preparation, O1 durable ABO runner; unknown acknowledgements retry |
| Out/in local commit→D1 step | DM2 original evidence replay; DM1 exact conservation; no recomputed empty package |
| Transfer→delayed void | PT1 moving-route transient, destination generation CAS, reject stale source effect |
| Delete→held/retired→purge | PT3 authoritative freeze, pinned resumable command, no early completed status |
| Erase→late raw messages | O2 persistent generation fences and cleanup |

**R7 consumer invalidation obligations:** finish ordered event→projection→desktop consumption, including held/reversed/released/suspension/transfer. Once a newer binding epoch is authoritative, old installation/epoch events cannot overwrite it; within epoch use clinic_seq. Invalidate stale coverage/binding caches after accepted lifecycle changes; awaiting/held/deleted cannot appear active from an old snapshot. Consume suspension_changed and original-grant import events. BR1/BR3 affect reversal notices/history; erroneous stored facts are not fixed by UI filtering. Full response/frontend validation is unreviewed R7 scope.

**R8 obligations:** preserve exact op/target/reason through all forms and retry controls; inherit R2-P1/P2/P4. Retry parked reversal with original accepted bytes and identity; do not turn recovery into another value mutation. List-and-void containment inherits R4-PG4 verified credential attribution. Complete remaining method/UI/audit policy in R8; this review establishes only R6 relays and mutations.

**R9 obligations:** retain/rebuild global claims/routes/seals, accepted lifecycle commands, original receipts/packages, export/purge/erasure obligations and original-term pending settlements. Existing wipe/rebuild helper (coverage.ts:3298–3303,3768–3808 and supporting rebuild ranges) can lose local replay, and grant_void hydration ignores operator-versus-reversal source; R9 must finish its owned full reconstruction semantics, not assume R6 reviewed them. Reconcile orphan/guessed/provider-derived historical facts under maintainer/frontier ownership; fail closed for ambiguous lineage or value. Complete canonical R3-C5 orphan-work and R4-D4 shipment/alarm recovery. These are named downstream scope, not hidden unread R6 work.

All 18 escalation dispositions are in [coverage](R6-coverage.md#escalation-dispositions-18). Prior R1–R5 findings stay canonical/unfixed; they are not counted again. External provider cumulative semantics (BR1/R3-C4), historical route/value adjudication, and earlier R1/R2/R3 decisions remain explicit limits. Static source does not attest deployed keys, buckets, alarms, provider behavior or account settings.

Only review artifacts and R6 tracker changed. No application edits, fixes, commits, pushes, branches, tests/builds/lint, services, live research or usage/account queries. Architecture navigation incidentally displayed acceptance-walkthrough row snippets and vector references; they were not analyzed or used as evidence. No excluded implementation was opened. R0–R5 remain complete, R7–R10 not started, overall review in progress. Completion records diagnosis/coverage, not launch approval.
