# R6 DO mutations bounded source review

Target `db9244fddfddc1905335fb8c7105328c15a0cc5e`; 2026-10-17 Africa/Cairo. Reviewer `/root/abo_r6_review/do_mutations`, explicitly GPT-6.1 Sol/medium. **Complete with findings for this assignment**: 4 P1, 1 P2. All 49 assigned primary tuples, 1,493 lines (coverage.ts 1,222; index.ts 271), read exactly by their initial bounded slices; no unread primary tuples. [Exact read record](R6-do-mutations-coverage.json) lists supporting expansions. Lead retains aggregate status and canonical numbering.

Source-only review: no app edits, tests/test design/testkit/fixtures/vectors/harness/campaign/viewer analysis, builds, lint, services, live research or commits. No excluded implementation was accidentally displayed. References are requirements, not runtime evidence. Other owners' primary source is not credited here; caller facts below explicitly identify their communicated interface evidence.

## Mutation, lineage, epoch and retry maps

Adjustment only targets a stored active term; it adds allowance/days and optionally replaces plan snapshot, then finalizes the grant. Its stale lifecycle decision and value-before-receipt write remain canonical R4-D1/D3. Its org ceiling history across transfers remains R4-D5; no duplicate count.

Reversal finds current/original grant identity (`findTermForGrant`, coverage.ts:634–637), derives effect from actual term state rather than trusting the supplied reason, ends active/grace and holds every queued successor, removes queued/held own term, or records a no-effect void of ended/exhausted value. Replay compares reversal ID with grant/reason/evidence and returns original receipt; Worker passes its real concurrency block (worker.ts:1892–1901). Partial validation/tombstones are platform owner scope. Manual void ends its term and activates oldest queued successor when the target was active; HP release re-appends held value and can activate it. Both retain live reservation JSON. They omit `used_final` on closure, and late credit can disappear/subtract: canonical R5-A2 must cover these consumers with settled-only closing. Global reserved leaking into successors remains R5-A1.

Suspension toggles only hot.suspended; it leaves terms/calendars and live reservations intact. New admission refuses suspension (index.ts:1345–1350), whereas credit can settle existing reservations (1588–1619). Resume does not add time. Its event-token drift is DM5.

Transfer package order follows loadTerms ORDER BY position (coverage.ts:231–235). IDs are SHA-256 of `grant:transfer:<id>:<zero-based decimal index>` (3090–3093); origin_grant_id survives import (3178,3242). Active export computes remaining allowance; grace exports remaining grace plus original budget/base/used. Source ends all movable terms and stops future grants with transferred_out; destination clears awaiting_transfer only after its import. No live reservations are exported or drained by these DO methods. DM1/DM2 must therefore depend on the platform owner's freeze/drain fence, retaining original request IDs and term attribution through R5 recovery. Never discard outstanding work merely to complete transfer.

| Interrupted/replayed state | Actual source result |
| --- | --- |
| Reversal ends current, interruption before signed receipt/replay | Retry sees ended and signs a different no-effect receipt; original transition lacks matching durable evidence (DM3) |
| Release changes held→active/queued, interruption before replay | Retry cannot find held; operation becomes bad_request despite effect (DM3) |
| Manual void ends target, interruption before replay | Retry rejects ended target without original receipt (DM3) |
| Source transfer mutation succeeds, reply/D1 step missing | Same ID exports empty package because all source terms ended (DM2) |
| Destination import succeeds, reply/D1 step missing | New random term precedes duplicate deterministic grant PK; retry leaves orphan and throws (DM2) |
| Active allowance 100, settled used 40 transfers | Export remaining60/full100; import allowance100/used0 restores40 (DM1) |
| Release while another term is grace | Two current terms; later grace boundary clears hot pointer of new active term (DM4) |
| New/late mutation reaches historical DO | ensureHotRow returns on any existing row without checking epoch (206–210); reversal/release/transfer methods add no epoch fencing |

Epoch/routing handoff: openAwaitingTransfer unconditionally writes supplied epoch/awaiting flag (2866–2872); other ensureHotRow consumers do not validate an existing epoch. Reversal can match an old transferred source term and produce applied/no-effect if the receiver routes to that historical installation. Platform owner owns live binding/lineage routing, held_for_transfer access and stale-call fencing. These are not additional DO-local findings. Transfer/admission state and deletion must be fenced by that shared remedy, rather than merely checking a D1 mirror.

Wipe removes hot/term/grant/outbox (3298–3303), with no independent durable replay record left. The supporting rebuild caller wipes/hydrates, clears reservation JSON and reconstructs from ledger/void rows (3876–3937). Assigned applyGrantVoidRowToDo treats every source as reversal and holds queued successors (3768–3806); the caller's row type omits source. R9 must retain command receipts, transfer packages, original-term pending settlements and operator/reversal distinction when reconstructing. No complete R9 rebuild correctness claim is made here.

## R6-DM1 — P1: active transfer restores already consumed allowance

High confidence, source defect, implementation-ready with the platform freeze/drain prerequisite. Export subtracts hot.used (`buildTransferPackageTerm`, coverage.ts:2913–2927), but includes original plan_allowance. Import preferentially stores that full value (3166–3169) and resets active hotUsed to zero (3188–3191). A supported HP transfer after consuming40 of100 therefore recreates100 credits instead of60. Dates and origin lineage remain, so ordinary admission can spend the recreated credits. This is independent of global grant replay and of predecessor reservation accounting.

**Fix steps**
1. In coverage.ts `buildTransferPackageTerm`/`transferInRPC`, preserve original allowance plus settled usage: when active `plan_allowance` exists, import `allowance=plan_allowance`, `hot.used=plan_allowance−pkg.allowance`. Validate finite integer, nonnegative remaining and usage, and remaining≤full. An older package without plan_allowance imports remaining allowance with used0. An invalid package fails closed without writes.
2. Preserve grace's original allowance, grace_base_used, hot_used, grace cap and original ends_at/grace_ends_at. Validate that recomputing remaining grace matches the exported remaining allowance. Preserve active calendar dates; do not restart its duration. Queued/held terms retain full allowance, duration and position unchanged.
3. Before final export, platform coordination must freeze all admission paths and resolve existing reservations/fallback intents against their original term IDs using R5-A2/A3; until zero unresolved work, return retryable pending and retain source terms. Do not subtract provisional reservations and silently drop later settlements. Then use DM2's immutable transaction/replay record.
4. Completion: 100−40 remains60 at destination and throughout repeated transfers; grace retains exact remaining budget/dates; queued/held value is unchanged; consumed/released late source requests cannot alter destination value after immutable export.

## R6-DM2 — P1: transfer steps lack durable DO replay and can lose or duplicate moved terms

High confidence, source defect, implementation-ready with the coordinator's transfer fence. transferOut ends terms/clears active at2991–3004, awaits hashing/signing at3016–3030 and never stores package/receipt. A retry exports no terms. transferIn generates a random term and inserts it at3159–3186 before its deterministic grant insert3227–3237, with no replay lookup and no encompassing transaction. A duplicate returns neither original receipt nor original terms; the term table has no grant uniqueness (index.ts:1940–1960), while grant_id is a grant primary key (1961–1973).

Platform reviewer interface evidence: `coverage/transfer.ts` executeOut checks D1 transfer_step330–339, calls DO350–361, and only later stores package/step385–401; executeIn similarly calls DO454–465 before step485–491. Lost reply or failed D1 write genuinely reaches these repeat calls. These ranges are sibling-owned evidence, not direct read coverage here. Escalation072:1 explicitly requires original-receipt already_applied.

**Fix steps**
1. Add a durable DO transfer-step table (schema in quota-do/index.ts) keyed by `(transfer_id,step)`, binding org/source/destination/epoch plus canonical package hash and storing original package, term IDs, receipt and applied_at. Preserve records through retention/export/rebuild. Initialize receiver schema before callers use it.
2. In transferOutRPC/transferInRPC, resolve identical replay first and return exact original result; changed binding/package identity conflicts without effect. Prepare complete step plan and signatures before writes under the existing concurrency block. Use synchronous SQLite transaction to atomically commit all term/grant/hot/outbox changes and step record. Use deterministic/import-unique term identity or one-term-per-transfer-grant constraint as a second integrity guard, after surfacing existing orphan history.
3. Store each canonical package element as the imported grant envelope matching its envelope_sha256 and retain its accepted transfer authorization linkage. Include per-import grant_applied events consistent with each receipt's ledger_seq; current loop increments sequence/signs grant receipts (3201–3225) without inserting that named coverage event. Commit all generated events and the final transfer event in order with the same transaction. Apply canonical R4-D4 durable alarm recovery on first apply and replay.
4. Update coverage/transfer.ts executeOut/executeIn and decoders to accept `applied` or `already_applied`, persist the original returned package/receipt into D1 once, and never replace it with an empty recomputation. Apply the platform owner's freeze/drain/current-binding fence before committing a new step; identical old-step replay returns evidence without resurrecting a deleted destination.
5. Completion: lost reply, failure before D1 step persistence, and interruption within import return the same package/term IDs/receipt; no empty package overwrites value, no orphan/duplicate terms or unsigned transitions remain. Disagreeing historical evidence is blocked for maintainer reconciliation, not auto-credited.

## R6-DM3 — P1: reversal, release and manual void commit effects before replayable evidence

High confidence, distinct R6 command-transition root. All three mutate terms/hot/events before asynchronous signing, then store replay/outbox later: reversal2165–2228→2233–2259; release2364–2397→2400–2412; manual void2458–2517→2519–2540. blockConcurrencyWhile serializes callers but does not roll back earlier SQLite statements after a signing failure/process interruption. A lost release/void receipt can turn the next same-action retry into bad_request; reversal retry instead sees ended state and signs a no-effect receipt, disconnecting applied commercial evidence from the actual transition. These paths need their own atomic command records; R4-D1 remains canonical for grant application.

**Fix steps**
1. Refactor voidForReversalRPC, releaseHeldRPC and voidGrantRPC into prepare/sign/atomic-commit. Prepare the chosen term/hot changes, ordered event snapshots/sequences, command identity and immutable receipt without executing SQL. Include R5-A2 settled-only used_final and preserve outstanding reservations.
2. Sign before value writes; then use one synchronous SQLite transaction to recheck replay identity and commit every term/hot/event/grant_void-outbox change plus the exact signed replay entry. Persist reversal binding including envelope_sha256 and partial=false; HP replay binds canonical operation arguments and assertion/evidence identity. Distinct payload replay conflicts.
3. Prearm durable wake-up before commit and repair actual alarm presence on replay per R4-D4. Retain permanent command receipts separately from expiring admission answers; include them in R9 export/rebuild so retention cannot convert a completed action into a fresh mutation.
4. Completion: failure before commit leaves original coverage and no command evidence; failure after commit returns the exact original receipt and sequences on retry. A successful release cannot become bad_request solely because its reply was lost; reversal cannot rewrite end_current as none.

## R6-DM4 — P1: releasing held coverage during grace creates two current terms

High confidence, source defect, policy resolved with lead using03§6.1. releaseHeldRPC checks only `state==='active'` at2351–2354. A valid scenario is: refund A holds queued B; a new paid C runs into grace; HP releases B. The code activates B and resets hot.used2371 without ending C's grace. Admission selects the earlier C (index.ts:995–997), and C's eventual boundary clears active_term_id and grace_base_used (coverage.ts:895–905) while B remains active. Usage/counters refer to different current terms and paid service can be denied or mischarged. This is independent of R4's complimentary-during-grace defect.

**Fix steps**
1. Make releaseHeldRPC use shared current placement planning with lifecycle catch-up at now. During live grace, end C as renewed, freeze its settled-only used_final (R5-A2), then activate released B anchored at C.ends_at with B's original duration. Lead chose the existing03§6.1 grace-renewal rule to avoid an inert queue and two current terms.
2. With active coverage, append B queued as today; with genuinely no current coverage/unheld predecessor, activate B at now. Preserve original grant/term lineage, allowance and live original-term reservations; apply R5-A1 term-local budgets. Clear grace_base_used when switching current term.
3. Commit ended→released→activated events plus receipt/replay through DM3's transaction. Completion: exactly one current active/grace row and matching hot.active_term_id; old grace boundary cannot clear B; outstanding C settlement remains on C; active/no-coverage release preserves queue order and duration.

## R6-DM5 — P2: suspension events use tokens outside the amended closed set

High confidence, bounded contract drift. suspendResumeRPC emits request.kind (`suspend`/`resume`, coverage.ts:1964), while067:7 and03§6.7 require `suspension_changed`. The source demonstrably stores an unsupported token. No downstream rejection/outage is asserted without R7 review.

**Fix steps**
1. Emit kind `suspension_changed` for both operations; retain operation in alert/audit metadata and the snapshot's suspended flag as the state distinction.
2. R7 must verify feed/backend/ABO/desktop readers accept that closed token and always consume snapshot suspension. R9 must read historical suspend/resume aliases during recovery without rewriting immutable historical events.
3. Completion: both toggles generate increasing-sequence suspension_changed events with correct full snapshots, unchanged calendars and retained running reservations; repeated unchanged toggle adds no duplicate transition.

## Escalations and handoffs

| IDs | Bounded disposition |
| --- | --- |
| 067:5,071:1 list window | Receiver/listGrants is platform owner. Mutation side retains paid/original ID lookup; no list-filter correctness claim here. |
| 067:6,071:1/2 void object | DO outbox carries separate void reason/source/evidence/receipt; shipment writes `<grant>.void.ndjson` (2754–2780), distinct grant object. DM3 protects durable command evidence; platform owner covers tombstone nil receipt and partial validation. |
| 067:7/8 | Reversal/manual void sequences identify grant_voided receipts; DM2 missing per-grant event corrected, DM5 suspension token drift. Receipt signers use compact JWS/receiptSigningBytes. Downstream receipt/feed interpretation remains R7/R9. |
| 067:11,079:6 | Shared approvals validation is canonical R2/R4 and platform ownership, not repeated through an unauthenticated DO helper. Transfer authorization evidence flows from the HP receiver. |
| 067:12,071:2 | Reference re-transcription adds no second source rule; original amended source obligations traced as above. |
| 070:1 | Adjustment positive contributions checked; org-history/atomicity/lifecycle findings inherit R4-D5/D1/D3. No duplicate. |
| 071:3 | Nil tombstone before grant is platform-owned. DO has no serialized tombstone read in applyGrantRPC1575–1654; interface sent to platform reviewer for global fencing finding. |
| 072:1 | DM1/DM2 conservation/step-replay failures; platform owner closes begin/delete idempotency, binding fences and deleted-identity behavior. |
| 083:1 | Package ordered by position; zero-based deterministic per-element grant IDs and preserved origin verified. DM2 closes retry failure despite deterministic grant IDs; ABO producer rows owned by lead. |

All assigned tuples closed. R7 must finish consumer invalidation/projection rules; R9 must preserve command/transfer evidence and reconcile ambiguous historical rows without guessing. Static source cannot attest deployed alarms, keys, R2 retention or operational service state.
