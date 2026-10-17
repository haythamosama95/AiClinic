# R6 review packet

Target: `db9244fddfddc1905335fb8c7105328c15a0cc5e`. Prepared 2026-10-16 Africa/Cairo.

### R6 — Reversals, operator value changes, transfer and deletion

**Question:** Can coverage be reduced, moved or removed safely despite delayed grants, stale bindings, duplicate evidence and interrupted multi-store operations?

**Primary source:** ABO `work/reversal.ts`, sweep recovery paths, reversal/provider normalization, transfer work and related console relays; platform void/tombstone/held-term/release/adjustment/suspension/deletion methods, `coverage/transfer.ts` and corresponding DO sections; grant-void/transfer/binding schema and receipts. Include operator-action construction for these operations, not just platform receivers.

**Read:** 03 §§2.7–2.9, 3.1–3.3, 5.5, 6.1–6.4, 7–8; 04 relevant value-changing methods in §1.3, validation/receipts; 05 §3.2 and corresponding failure modes. Provenance: P3.6–P3.8, P4.5, P4.7–P4.8. Escalations: 070–072, 080, 082–083.

**Trace together:** full/partial refund or chargeback → reversal identity → void/tombstone → held/reserved coverage; and asserted transfer → source freeze/export → destination import → binding-epoch changes → status/feed. Include reversal-before-grant, repeated/pending reversals, stale async messages after transfer/deletion, origin-grant lineage, source/destination retries, and suspension/resume interaction with running requests. Check conservation of value across terms/clinics and immutable audit lineage. Include contact erasure and retained commercial facts where deletion connects to them.

**Handoff:** reversal/transfer failure-state map and consumer invalidation obligations to R7/R8/R9.


## Manifest and preparation dependencies

The authoritative bounded source regions are the rows owned by this phase in [region ownership](regions.md); candidate disposition/provenance is in [candidate inventory](candidates.md). Read directly relevant unchanged callees listed there and expand the coverage log when tracing discovers another dependency. Escalations are the entries whose phase list includes this phase in [escalation inventory](escalations.md), including cross-unit amendments and excluded-effect dispositions.

Read [system map](system-map.md), repository AGENTS.md and the complete review plan before source. Initial open seams are the trace questions above; predecessor reports supply additional named handoffs. A packet is navigation only and does not claim its owned source reviewed. Use fresh GPT-6.1 Sol context(s), load bounded source sections, and checkpoint rather than infer unread coverage. Only the coordinator changes the overall tracker.

Phase-specific escalation IDs (18): 067:5, 067:6, 067:7, 067:8, 067:11, 067:12, 070:1, 071:1, 071:2, 071:3, 072:1, 079:2, 079:3, 079:6, 080:2, 080:3, 082:1, 083:1. Exact records: [escalations-R6.json](escalations-R6.json).

## Bounded reading and context plan

Read this phase’s [exact source manifest](manifest-R6.md) ([JSON](manifest-R6.json)), including unchanged dependencies only as the owned invariant requires. [SQL declaration navigation](regions-sql-definitions.md) lists earlier and later overrides; resolve signatures, grants, DROP/ALTER and actual final definitions in migration order. [Provenance](provenance.md) includes all delivery units and later fixes.

Assigned line inventory: primary source: 6,044. These are navigation totals, not reviewed-line claims. Load source by bounded functions; do not paste the entire manifest/source into initial context.

One fresh same-phase context is the initial sizing choice; use named same-phase continuation contexts if directly relevant supporting code exceeds the target. Save exact read/unread regions, not a whole-file completion guess.
