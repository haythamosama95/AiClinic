# R6 actual coverage and escalation closure

Target `db9244fddfddc1905335fb8c7105328c15a0cc5e`; completed 2026-10-17 Africa/Cairo. **Complete with findings**,0 P0/10 P1/3 P2. [Canonical report](R6-reversals-transfer-deletion.md) · [machine coverage](R6-coverage.json) · [checkpoint](R6-checkpoint.md).

## Exact primary ownership and actual reads

| Context | Explicit model/effort | Assigned and read | Exact evidence |
| --- | --- | --- | --- |
| Lead/synthesis `/root/abo_r6_review` | GPT-6.1 Sol/high |36 tuples/995 lines: ABO R6 ops + three migrations | [Ops report](R6-lead-ops.md), [ranges](R6-lead-ops-coverage.json) |
| `abo_reversal` | GPT-6.1 Sol/medium |94 tuples/1,757 lines: reversal1004+sweep753 | [Report](R6-abo-reversal.md), [ranges](R6-abo-reversal-coverage.json) |
| `do_mutations` | GPT-6.1 Sol/medium |49 tuples/1,493 lines: coverage1222+index271 | [Report](R6-do-mutations.md), [ranges](R6-do-mutations-coverage.json) |
| `platform_transfer` | GPT-6.1 Sol/medium |51 tuples/1,799 lines: transfer750+vendor1049 | [Report](R6-platform-transfer.md), [ranges](R6-platform-transfer-coverage.json) |
| Total | Explicit high/medium only |**230/230 tuples,6,044/6,044 lines** | Manifest tuple multiset equals actual owner-read multiset; no missing or duplicate primary tuple |

Each initial manifest `(path,revision,start,end,symbol)` has exactly one primary owner and one completed read record. The manifest is inventory; navigation is never credited as reading. Bounded supporting expansion includes provider normalization and actual intake/runner/budget callers, credential/replay/receipt helpers, DO schemas/storage/dispatch/admission/credit, retention and narrowly required rebuild seams. Exact ranges are retained in slice JSONs and aggregated with original reviewer. Lead re-read targeted snippets solely to verify findings across interfaces; those are explicitly supporting verification, not another primary owner/read claim. No required R6 unread scope remains.

Reference material: AGENTS.md, complete review plan, R0 packet index/system map, R6 packet/manifest/escalations; current architecture03 reversal/work/platform records/term+reversal lifecycle/coverage rules/identifiers/retention,04 relevant value-changing methods/receipt validation,05 actions/failure recovery; canonical R1–R5 reports' handoffs and relevant known-root summaries. Architecture references are not documentation-quality review. Metadata confirms HEAD/master T,B/H and workflow/artifact-only T/H differences; only review docs are untracked.

## Escalation dispositions (18)

| ID | Producer→consumer disposition |
| --- | --- |
|067:5|Inclusive grant-list/credential fields feed list-and-void relay and platform query; R6 listGrantsForVoid window propagation verified. General listGrants remains inherited R4; verified credential attribution/containment root R4-PG4 remains canonical.|
|067:6|Grant and `.void.ndjson` objects remain distinct; DO void outbox carries reason/source/evidence/receipt. Tombstone D1/R2 gap PT1 and DO command durability DM3; R9 reconstructs these durable obligations.|
|067:7|R6 end/held/release/void/transfer snapshots and sequence producers read. DM2 requires missing per-import grant_applied event; DM5 fixes suspend/resume token. Full feed/projection/client consumption explicitly R7.|
|067:8|Compact signed receipts tied to local clinic_seq read at mutation/consumer sites. DM2/DM3 preserve exact original event/receipt identity; PT1 preserves tombstone replay/export. ABO signature-only semantic matching inherits R4-A2, extended with nil-tombstone predicates.|
|067:11|Public grant minimum/paid exception inherited R2/R4 with079:6; internal out/in requires existing HP-authorized transfer row. Read transfer authorization→internal per-element receipts/lineage; DM2 retains canonical per-term package/evidence, without inventing a new unauthenticated grant entry.|
|067:12|Reference re-transcription, no new source rule; actual amended receipt/event/approval rules dispositioned under067:5–11. Excluded clarification workflow not reviewed.|
|070:1|Adjustment contributions/active-target path read; atomicity/lifecycle/history across epochs inherit R4-D1/D3/D5. Suspension overlay is intentionally calendar-preserving; token defect DM5. Remaining ceiling configuration policy stays R8.|
|071:1|Required boolean partial/refusal-with-no-write, inclusive required listing window and operator challenge evidence traced. Partial/full authority BR1, exact route/tombstone PT1 and command durability DM3. No partial request is treated as permission to reduce value automatically.|
|071:2|Same amended rules, no second design decision. Matching reversal replay compares grant/reason/evidence and partialfalse and returns original applied receipt. PT1/DM3 make it recoverable after crash; historical spec re-transcription itself excluded from source review.|
|071:3|Nil IDs/seq0/empty terms and no coverage event for before-grant tombstone are implemented intentionally. PT1 identifies why missing asynchronous ledger is insufficient proof of before-grant state.|
|072:1|Begin/delete successful ok detail, early-in awaiting_transfer_out and package/source-grace arithmetic traced. DM1 conservation, DM2 original local step replay, PT2 destination preparation, PT3 deletion completion violate intended guarantees. Receivers must accept new local already_applied after repair.|
|079:2|Reversal facts/held snapshot supply notices/history; bounded billing-read producer121–138 read by ABO reviewer. BR1/BR3 incorrect inputs propagate. Full response shape/pagination/frontend remain R7, with inherited R4 receipt linkage.|
|079:3|Same five-code notice closure carried as producer obligation: reversal_recorded and terms_held conditions traced. Reference re-transcription adds no new workflow; R7 owns complete consumer behavior.|
|079:6|Paid operation-object approval exception remains canonical R2/R4. Machine-signed reversal bodies are separate from grant approval; transfer authorization retains HP. No testkit/vector implementation read.|
|080:2|Fails BR1: original parent/cumulative authority and fullness not reliably established, despite nominal parent/state/cumulative key. Partial20/100 may void100; authoritative correction/unknown-defer recipe and provider owner stop point explicit.|
|080:3|Canonical R3-C7 owns atomic cap2/priority/concurrency. BR2 independently prevents eligible recurring work after partial evidence and skips other live-funded payments; corrected populations must still use the one cap and leave overflow due.|
|082:1|ABO verifyHpRequest reloads active credential list and refuses absent credential_not_active (`ops/index.ts:722–737`), distinct from platform own revoked-code checks. R2-P1 target-binding root inherited; O1 separately makes accepted actions resumable.|
|083:1|ABO per-package index and DO SHA256 index0…k−1 agree, order byposition and origin preserved. DM2 prevents retry package changes; O1 reconstructs local grant_request rows even on early remote-in-success before work completion.|

## Deduplication, decision limits and forward scope

No new count for R1 identity/expiry/role, R2 target/override/bootstrap/browser/version, R3 discovery/multiple success/marker batching/budget, R4 global grant identity/grant atomicity/transport/outcome/alarm/lifecycle/credential/ceiling, or R5 original-term reservation/late settlement/fallback roots. Exact additional consumers appear in slice handoffs. R6-DM3 is separately implemented void/release command atomicity; DM4 is held-release placement rather than complimentary placement. O1 is ABO acceptance/runner handoff rather than R4-PG3 platform complimentary acceptance.

BR1 is fully diagnosed; safe unknown-defer containment is ready. Its provider terminal cumulative/missing-field decoder decision remains with provider integration owner plus frontier reviewer under R3-C4. Historical inconsistent routes/value/facts require maintainer+frontier/R9 evidence adjudication and fail-closed mutation until mapping is known. Existing earlier-phase decisions persist. These are explicit remedy/data limits, not missing R6 reads.

R7 obligations: invalidate old binding/epoch state, consume ordered final snapshots and correct closed event tokens/notices. R8: exact forms/arguments/retry identity and inherited passkey roots; full remaining console audit/policy unreviewed. R9: retain/rebuild commands/routes/seals/original receipt+package/export/purge/erasure obligations and original-term settlements; complete source-kind-sensitive grant_void hydration, canonical C5/D4 recovery and historical reconciliation. These phases were not executed.

No application edits, patches, tests/builds/lint, services, live provider research, commits/pushes/branch changes or usage/account queries. Architecture navigation incidentally surfaced acceptance-walkthrough row snippets and vector references; not analyzed or used as correctness evidence. No excluded implementation bodies were opened. Source review cannot attest deployed keys/alarms/R2 locks/account settings. Overall review remains in progress; R0–R5 preserved and R7–R10 not started.
