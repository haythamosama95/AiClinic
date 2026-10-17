# R7 review packet

Target: `db9244fddfddc1905335fb8c7105328c15a0cc5e`. Prepared 2026-10-16 Africa/Cairo.

### R7 — Coverage feed, backend projection and desktop-visible state

**Question:** Does authoritative platform state reach the correct user's desktop with correct ordering, freshness, notices and role restrictions, without blocking clinical work?

**Primary source:** platform feed/coverage-read methods and event/mirror producers; backend coverage-feed-puller/status and read-time-notice migrations, including later overrides; ABO coverage view, billing reads and corresponding work updates; Flutter availability/status providers, host/degraded/AI pages, subscription/payment/notices, app routing/settings entry points and relevant RPC/HTTP/SSE adapters. Review the relevant `abo_client.dart` read/parse behavior and `.arb` inputs.

**Read:** 03 §4, §5.7 and event ordering/epochs; 04 §§1.7, 2.2, 3, 4.1–4.2; 05 FM-06/FM-10/FM-11 and §5.4. Provenance: P3.9, P4.2/P4.4–P4.5, P5.2a/P5.2b, P6.1–P6.4. Escalations: 073, 079, 088, 088b, 089, 091–092.

**Trace together:** grant/usage/reversal/transfer event → paginated feed → cursor/epoch/version checks → SQL projection → read-time status → role-specific desktop action and presentation. Include out-of-order/repeated pages, cursor recovery, stale responses, grace/lapse at read time, refreshing after denials, cached credentials and org/role changes. Check staff cannot obtain administrator commercial details, missing/unknown states fail safely, and subscriptions/checkout/payment history remain consistent with authoritative state. AI denial must preserve ordinary clinical workflows.

**Handoff:** producer-to-display field mapping, stale/error semantics and unresolved contract seams to R9/R10.


## Manifest and preparation dependencies

The authoritative bounded source regions are the rows owned by this phase in [region ownership](regions.md); candidate disposition/provenance is in [candidate inventory](candidates.md). Read directly relevant unchanged callees listed there and expand the coverage log when tracing discovers another dependency. Escalations are the entries whose phase list includes this phase in [escalation inventory](escalations.md), including cross-unit amendments and excluded-effect dispositions.

Read [system map](system-map.md), repository AGENTS.md and the complete review plan before source. Initial open seams are the trace questions above; predecessor reports supply additional named handoffs. A packet is navigation only and does not claim its owned source reviewed. Use fresh GPT-6.1 Sol context(s), load bounded source sections, and checkpoint rather than infer unread coverage. Only the coordinator changes the overall tracker.

Phase-specific escalation IDs (27): 066:3, 067:4, 067:7, 067:8, 067:9, 067:10, 067:12, 071:3, 072:1, 073:1, 073:2, 079:2, 079:3, 079:5, 088:1, 088:2, 088:3, 088:4, 088:5, 088:6, 088:7, 088b:1, 089:1, 091:1, 092:1, 095:1, 095:2. Exact records: [escalations-R7.json](escalations-R7.json).

## Bounded reading and context plan

Read this phase’s [exact source manifest](manifest-R7.md) ([JSON](manifest-R7.json)), including unchanged dependencies only as the owned invariant requires. [SQL declaration navigation](regions-sql-definitions.md) lists earlier and later overrides; resolve signatures, grants, DROP/ALTER and actual final definitions in migration order. [Provenance](provenance.md) includes all delivery units and later fixes.

Assigned line inventory: primary source: 7,969. These are navigation totals, not reviewed-line claims. Load source by bounded functions; do not paste the entire manifest/source into initial context.

One fresh same-phase context is the initial sizing choice; use named same-phase continuation contexts if directly relevant supporting code exceeds the target. Save exact read/unread regions, not a whole-file completion guess.
