# R5 review packet

Target: `db9244fddfddc1905335fb8c7105328c15a0cc5e`. Prepared 2026-10-16 Africa/Cairo.

### R5 — Live AI admission, allowance accounting and fallback

**Question:** Does every admitted request charge the right term at most once while preserving coverage, concurrency and overshoot bounds through failures?

**Primary source:** platform `quota-do/index.ts` and admission/reservation/settlement/alarm parts of `quota-do/coverage.ts`; `admission/`, `credit/`, changed `pipeline/`, entitlement/capability/discovery readers and cache behavior; request idempotency/fingerprint handling and its migration; changed worker request, stream handoff, settlement and fallback-drain paths; relevant journal/usage/rollup changes. Include changed manifest/vocabulary/routing/threshold dependencies.

**Read:** 03 §§3.1–3.2, 5.4, 5.7, 6.2–6.7; 04 §§4.2, 6.1; 05 fallback/settlement failure modes. Provenance: P3.2–P3.5, P3.9–P3.11 and later request-fingerprint fixes. Escalations: relevant 066–069, 073, 075, 095.

**Trace together:** issuer principal → fresh coverage check → reserve → actual provider/stream outcome → settlement/journal → release/retry, and DO-unreachable → mirror/fallback admission → later drain. Include request-ID reuse with changed payload, replay, cancellation, late completion, term changes while work is active, concurrent requests, and duplicate settlement. Check removal of old period/tier paths and that denied or replayed calls do not create unintended writes. Read only ABO-affected invocation/stream/provider context; do not reopen the entire old AI engine.

**Handoff:** accounting invariants, fallback bounds and remaining recovery questions to R6/R7/R9.


## Manifest and preparation dependencies

The authoritative bounded source regions are the rows owned by this phase in [region ownership](regions.md); candidate disposition/provenance is in [candidate inventory](candidates.md). Read directly relevant unchanged callees listed there and expand the coverage log when tracing discovers another dependency. Escalations are the entries whose phase list includes this phase in [escalation inventory](escalations.md), including cross-unit amendments and excluded-effect dispositions.

Read [system map](system-map.md), repository AGENTS.md and the complete review plan before source. Initial open seams are the trace questions above; predecessor reports supply additional named handoffs. A packet is navigation only and does not claim its owned source reviewed. Use fresh GPT-6.1 Sol context(s), load bounded source sections, and checkpoint rather than infer unread coverage. Only the coordinator changes the overall tracker.

Phase-specific escalation IDs (9): 066:6, 066:8, 066:10, 067:1, 067:7, 067:9, 068:1, 089:1, 095:1. Exact records: [escalations-R5.json](escalations-R5.json).

## Bounded reading and context plan

Read this phase’s [exact source manifest](manifest-R5.md) ([JSON](manifest-R5.json)), including unchanged dependencies only as the owned invariant requires. [SQL declaration navigation](regions-sql-definitions.md) lists earlier and later overrides; resolve signatures, grants, DROP/ALTER and actual final definitions in migration order. [Provenance](provenance.md) includes all delivery units and later fixes.

Assigned line inventory: primary source: 10,234, deleted: 303. These are navigation totals, not reviewed-line claims. Load source by bounded functions; do not paste the entire manifest/source into initial context.

Use two fresh same-phase contexts: admission/identity/request/fingerprint/worker flow; and DO reservation/settlement/fallback/accounting/old-period replacement. Partition manifest paths and worker/DO symbols before review, target about 5,000 primary lines each, then reconcile one R5 report. No source region may be counted twice or dropped.
