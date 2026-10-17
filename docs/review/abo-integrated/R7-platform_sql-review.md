# R7 platform/SQL bounded review

Target `db9244fddfddc1905335fb8c7105328c15a0cc5e`; reviewer GPT-6.1 Sol, explicitly medium. **Complete with findings: 0 P0, 0 P1, 4 P2.** All 44 assigned tuples / 1,815 primary lines read at T, with exact supporting ranges in [coverage](R7-platform_sql-coverage.json). Source-only conclusions; no runtime reproduction, tests, builds, services, research, fixes or source changes. Control records are workspace artifacts absent at T; application/reference source reads used `git show T:path`.

## Established traces

DO outbox shipment inserts events idempotently by event_id, then updates the installation mirror, then deletes the outbox entry. Its callers serialize shipment under the DO lock; no independently concurrent mirror writer was established, so the mirror SELECT/REPLACE pattern alone is not reported as a demonstrated race. Mirror snapshots retain their version and capabilities; reversed snapshots map to lapsed for fallback, with terminal states unavailable. Feed pages order by feed_seq and continue at the last row. Both vendor and HTTP feeds return the stored full snapshots; shipment is eventual, not a live snapshot computation.

The backend singleton feed-state row is locked for the pull cycle. Matching response header/body version, echoed cursor, ascending feed sequence and response age are checked before projection. Projection upserts use strictly greater `(binding_epoch, clinic_seq)`, so equal/repeated events and late old-epoch events cannot roll back a newer row; a re-created identity's higher epoch beats a restarted clinic sequence. Failure keeps the cursor. Cursor reset to zero replays immutable events into the same guarded projection. The versionless flattened projection matches escalation 088:6. The puller does not explicitly validate nested snapshot versions; strict decoder work remains canonical R2-C3, not a new count here.

Migration-order search at T establishes no later redefinitions of the owned pull/refresh/status signatures. Pull and refresh remain in `20261007230000_coverage_feed_puller_status.sql`; the effective shared status/public status/billing bodies are in `20261008010000_read_time_status_notices.sql`. Projection tables enable deny-all RLS and revoke clinic roles; internal functions revoke PUBLIC/anon/authenticated/service_role. Public status and billing grant authenticated; refresh also grants anon but its body checks valid session and administrator role before a write/pull. Membership lifecycle defects remain R1-SQL-02/03/04, not recounted.

The final SQL reader correctly evaluates suspended first; active expiry falls through queued/grace/lapse; stored grace lapses at grace_ends_at. days_left uses ends_at and floors whole days; reason and member notices match the amended rules. `as_of=now()` exists even without a row. Billing reuses the same status and adds flat commercial details only after membership administrator authorization. Member status contains no prices/payment references. Freshness is global last successful pull, not last clinic event, as specified.

Queued lists preserve ascending positions because loadTerms orders position; recent lists filter active/grace/ended, reverse position and cap at 12, with live hot.used only for the current term. Subscription references use the shared deterministic helper/SQL hash recipe. Grant receipt sequence/event roots remain R4/R6; pure pre-grant tombstones intentionally publish no event.

## Findings

### R7-PS1 — P2: deletion with retained coverage never publishes unavailable status

**High confidence; implementation-ready after R6-PT3's reliable deletion command.** T `ai-platform/src/quota-do/coverage.ts:3106–3114` only sets `hot.transfer_pending=1`; `buildCoverageSnapshot:381–459` ignores that flag when selecting state/reason. The normal deletion producer `ai-platform/src/coverage/transfer.ts:663–676` calls this path after marking the binding held. There is no new clinic_seq/event/alarm there. An active paid clinic deleted with time left therefore continues to read active in the live snapshot, while the backend's previously active row stays available until an unrelated term event; even that event still derives active while its term remains active. AI enforcement can deny transfer_pending independently, so this is misleading status rather than restored authority/value. It violates 03 §§5.4/5.7 and cannot be repaired merely by epoch ordering. R6-PT3 owns deletion unknown-ack/retry/purge ordering; this finding owns the missing projection transition.

**Fix steps**
1. Extend SetTransferPendingRequest and its callers in transfer.ts/worker dispatch with installationId, orgId, accepted snapshot version, nowIso and durationScale, retaining the pinned deletion generation from R6-PT3.
2. In buildCoverageSnapshot give `transfer_pending=1` precedence over active/grace term selection (after a completed transferred-out marker): return state/reason `transfer_pending`, retain term/queue/held metadata and existing suspended flag. Do not change calendar or allowance.
3. In the serialized setTransferPendingRPC, only the first 0→1 transition increments clinic_seq and enqueues a full snapshot with the closed `transfer` event kind. Schedule shipment using the existing coverage alarm path; retry with the same flag/generation must recover shipment without a duplicate transition.
4. Completion: held deletion becomes unavailable in live coverage and the backend after feed consumption; repeated deletion produces no duplicate transition; old-epoch events cannot overwrite the new identity; suspension remains an overlay. Preserve R6-PT3's durable retry behavior.

### R7-PS2 — P2: empty and terminal coverage snapshots report incorrect state/reason

**High confidence; implementation-ready.** T `coverage.ts:2064` overwrites an empty DO snapshot as active with term=null; an initialized empty hot row instead falls through `430–438` to lapsed. Neither returns the required none state for no grant ever applied (03 §5.7). Terminal exhausted (`431–432`) and transferred (`397–398`) also retain reason none instead of their named reasons (04 §1.7). New administrators/live subscription consumers can see an active or lapsed subscription without any term; terminal diagnostics lose the causal reason. This affects display/contract fidelity, not admission authority.

**Fix steps**
1. Make buildCoverageSnapshot return state/reason `none` when no term has ever been applied, preserving a suspended overlay and PS1 transfer precedence. For history with terminal terms retain current last-position selection.
2. Set reason `exhausted` on exhausted snapshots and `transferred` on completed transferred snapshots. Keep expired/grace_exhausted/reversed mappings unchanged.
3. Remove readCoverageRPC's special `snapshot.state='active'`; use the common empty-hot snapshot with none and empty lists. Do not create hot/term rows during a read.
4. Completion: fresh no-hot and initialized empty DOs agree on none; exhausted and transferred reasons survive feed flattening; active/grace SQL reasons stay null; repeated reads remain free of writes.

### R7-PS3 — P2: concurrent refreshes bypass the tenant throttle

**High confidence; implementation-ready.** T `backend/supabase/migrations/20261007230000_coverage_feed_puller_status.sql:496–519` reads requested_at before an unconditional upsert. Two requests can both observe no row or an old timestamp, both update and both invoke the global pull. The later feed-state lock does not repeat the tenant throttle check. This violates 088:1's 10-second acceptance condition and can multiply pulls/waiting work from one administrator; impact is bounded to refresh/resource behavior.

**Fix steps**
1. Add a forward migration overriding auth_internal.request_ai_status_refresh(integer), retaining its session/role/version/error behavior.
2. Replace SELECT-then-write with one conditional INSERT ON CONFLICT DO UPDATE, predicate `status_refresh.requested_at <= now()-interval '10 seconds'`, RETURNING requested_at. Exactly one concurrent transaction may claim the window.
3. When RETURNING yields no row, return RATE_LIMITED with accepted p_contract_version and perform no pull/write; on success call pull_coverage_feed and return the claimed timestamp. Preserve transaction rollback on pull failure.
4. Completion: concurrent same-org calls accept one; a different org has its own window; equality at ten seconds accepts; non-administrators leave status_refresh and feed_state unchanged.

### R7-PS4 — P2: suspension blocks the administrator's live diagnostic read

**High confidence; implementation-ready.** T `ai-platform/src/coverage-read/index.ts:93–103` verifies without allowSuspended; `identity/index.ts:517–548` rejects a suspended installation before returning the principal. The administrator-only read is therefore denied instead of returning the suspended snapshot. `control/installation-lifecycle.ts:26–32` updates installation without invalidating the isolate cache, so an isolate that cached suspended status can keep denying this read after resume until its configured TTL expires (default 30 seconds). This is a diagnostic/read availability defect; backend status remains available and admission must remain suspended.

**Fix steps**
1. Pass allowSuspended:true only from handleCoverageReadRequest's verification context, as already supported by IssuerTokenVerifier. Retain full signature, expiry, live binding, tenant and administrator-role checks.
2. Keep the DO snapshot's suspended flag authoritative for the returned coverage; do not extend this exemption to admission or mutation routes. Handle deleted/held state through PS1 and existing binding rules.
3. Completion: valid administrators can read live coverage before/during/after suspension even with a cached suspended installation; staff still get no commercial payload, retired/deleted-unheld identities remain denied, and AI admission stays suspended.

## Prior roots, boundary seam and escalation dispositions

R2-C2/C3 remain canonical for missing response version metadata, HTTP-200 DO refusals cast as coverage success, and sender decoding. R1-C1 owns feed token expiration. R4-D1 owns intermediate rather than final post-grant snapshots; R4-D4 owns lost shipment/alarm recovery. R5 owns usage/band/exhaustion event production. R6-DM5 owns suspend/resume tokens outside the closed vocabulary: backend ignores kind and applies snapshot, and ABO's validator only requires kind string (lead source confirmation), so no demonstrated projection outage follows from that token mismatch. R9 must retain historical aliases in rebuild handling.

R4 read-boundary handoff is closed with a limit: readCoverageRPC returns persisted states without applying due boundaries; this is a read-only endpoint by 04 §4.2. A delayed alarm can therefore leave live active/grace labels behind their dates, while final SQL status still evaluates dates correctly. Do not insert writes into the read path as an incidental repair; R4-D3/D4 own lifecycle/alarm repair. readCoverageRPC also does not pass durationScale into coverage_through, so queued durations use unscaled months/days in staging; production unscaled behavior is unaffected. This staging-only source limit is recorded for integration, not counted as a production failure.

| Escalation | Bounded disposition |
| --- | --- |
| 066:3 | HTTP verification failures map unauthenticated/401; cap/AL-20 producer remains R1-C2. Desktop mapping is lead scope. |
| 067:4,073:1 | Companion list fields/order/cap and live-vs-final usage traced; snapshot defects PS1/PS2 and canonical R2 decoder limits apply. |
| 067:7 | Shipment/feed/SQL consume full snapshots in sequence. R4-D1 final-state issue and R6-DM5 kind issue retained. |
| 067:8,071:3 | findGrantAppliedSnapshotForGrant filters grant_applied and increasing clinic_seq; pure tombstone has no event by design. Receipt signing/reversal roots remain R4/R6. |
| 067:9 | String-array capabilities copied into snapshots and mirror term view; immutable plan origin remains R4/R5. |
| 067:10 | Vendor readCoverageEvents rejects missing/noninteger/outside 1..200, no receipt; HTTP separately defaults invalid limits to 200. |
| 067:12 | Clarification-process amendment only; no additional runtime effect. |
| 072:1 | Final transfer event epoch ordering traced; PS1 exposes held-delete publication gap, R6 remains canonical transfer/package/retry owner. |
| 073:2 | Deterministic subscription reference helper and billing SQL recipe traced. |
| 088:1 | Role and timestamp payload rules preserved; throttle concurrency defect PS3. |
| 088:2–6 | Notice fields, dates, reason, billing flat fields and versionless projection match final SQL; upstream snapshot reason defect PS2 retained. |
| 088:7 | Delivery split reference only; both final migrations reviewed together. |
| 088b:1 | Shared read-time now() as_of present with/without projection, reused by billing. |
| 095:1 | Negotiated previous-version success must echo sender; R2-C3 owns missing decoder/refusal handling. No claim that N→N+1 itself fails. |
| 095:2 | Test-only RPC variant effect excluded; published final RPC gates still accept (0,1), before role/status work. |

Source inspection does not establish deployed definer ownership/default global ACLs, cron liveness, actual keys/environment, cache TTL overrides or recovery execution. No extra unread primary regions or unclosed bounded source seams remain. Lead owns desktop/ABO consumer synthesis and R9 owns full rebuild semantics.
