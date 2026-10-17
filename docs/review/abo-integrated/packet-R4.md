# R4 review packet

Target: `db9244fddfddc1905335fb8c7105328c15a0cc5e`. Prepared 2026-10-16 Africa/Cairo.

### R4 — Confirmed money to durable coverage and term lifecycle

**Question:** Does each eligible payment or authorized grant produce the intended coverage once, with consistent terms, receipts and renewal behavior across ABO and the platform?

**Primary source:** ABO `work/grant.ts`, grant-related runner paths, grant request/outcome/attempt schema; platform paid/complimentary grant validation/application and plan-version snapshot sections of the entrypoint; DO grant placement, term activation/renewal/grace and calendar logic; D1/R2 grant ledger/event/mirror writes; shared grant-envelope and receipt consumer sites. R2's package review is supporting context, not a substitute for checking how values are used.

**Read:** 03 §§2.8, 3.1–3.3, 5.3–5.4, 5.7, 6.1, 6.3–6.4, 6.7–6.8, 7; 04 §§1.3–1.4, 1.6–1.7; 05 grant failure modes. Provenance: P3.3, P3.5–P3.6, P4.4 and P4.8. Escalations: 067, 068, 069, 070, 079; 083 lineage rules where relevant.

**Trace together:** confirmed payment → deterministic grant/envelope/approvals → platform validation → ledger/DO effects → signed matching receipt → ABO outcome/projection. Include lost replies, transient failure after a partial durable effect, duplicate/conflicting grants, unsupported/retired plans, queued successors, exhaustion vs expiry, end-of-month arithmetic and grace. Evaluate all relevant stores' ordering together, not a happy-path review of one method.

**Handoff:** state-transition and idempotency table, receipt-to-state linkage, and crash windows to R5/R6/R7/R9.


## Manifest and preparation dependencies

The authoritative bounded source regions are the rows owned by this phase in [region ownership](regions.md); candidate disposition/provenance is in [candidate inventory](candidates.md). Read directly relevant unchanged callees listed there and expand the coverage log when tracing discovers another dependency. Escalations are the entries whose phase list includes this phase in [escalation inventory](escalations.md), including cross-unit amendments and excluded-effect dispositions.

Read [system map](system-map.md), repository AGENTS.md and the complete review plan before source. Initial open seams are the trace questions above; predecessor reports supply additional named handoffs. A packet is navigation only and does not claim its owned source reviewed. Use fresh GPT-6.1 Sol context(s), load bounded source sections, and checkpoint rather than infer unread coverage. Only the coordinator changes the overall tracker.

Phase-specific escalation IDs (20): 067:2, 067:3, 067:4, 067:5, 067:6, 067:7, 067:8, 067:9, 067:11, 067:12, 068:1, 069:1, 070:1, 073:1, 079:1, 079:2, 079:4, 079:6, 083:1, 085:1. Exact records: [escalations-R4.json](escalations-R4.json).

## Bounded reading and context plan

Read this phase’s [exact source manifest](manifest-R4.md) ([JSON](manifest-R4.json)), including unchanged dependencies only as the owned invariant requires. [SQL declaration navigation](regions-sql-definitions.md) lists earlier and later overrides; resolve signatures, grants, DROP/ALTER and actual final definitions in migration order. [Provenance](provenance.md) includes all delivery units and later fixes.

Assigned line inventory: primary source: 4,011. These are navigation totals, not reviewed-line claims. Load source by bounded functions; do not paste the entire manifest/source into initial context.

One fresh same-phase context is the initial sizing choice; use named same-phase continuation contexts if directly relevant supporting code exceeds the target. Save exact read/unread regions, not a whole-file completion guess.
