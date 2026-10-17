# R9 review packet

Target: `db9244fddfddc1905335fb8c7105328c15a0cc5e`. Prepared 2026-10-16 Africa/Cairo.

### R9 — Durable records, recovery, reconciliation and executable operations

**Question:** Can the system detect divergence and recover durable truth without issuing duplicate value, losing audit evidence or exposing production-only bypasses?

**Primary source:** ABO record append/export, rebuild and rebuild script, reconciliation/payout import/finding resolution, alert/lock/digest/watch/housekeeping modules; platform alert, retention, rebuild entrypoint/DO sections and related rollup/support changes; worker cron wiring; all remaining runtime D1 migration constraints/triggers and final schema consistency; operational `launch-check.mjs`, `audit-watcher.mjs`, `heartbeat-monitor.mjs`; worker/backend runtime config and executable source-boundary/residue guards. Consult runbooks only to establish what these programs claim to do.

**Read:** 02 §§1.4, 4–6; 03 §§1, 2.1, 2.10, 3, 8; 05 §§1–7 and non-code launch conditions as limits. Provenance: P3.1/P3.8/P3.11, P4.1/P4.10–P4.11, P7.1, P8.1/P8.3. Escalations: 075–076, 081, 085–086, 093; 097 as reference-only workflow context.

**Trace together:** immutable fact → D1/R2 ordering → export/lock → projection/rebuild → resumed work/re-inquiry → reconciliation and alert. Include failure after each durable side effect, replay with existing IDs, gap handling, tampered/missing/mismatched receipts, payout correlation, alert failure/deduplication, retention and missed cron execution. Check deployment bindings, inaccessible test overrides/clocks, environment separation, public exposure, and whether operational programs check live authoritative state or merely trust supplied snapshots. Record source limits explicitly; static review cannot attest actual production account settings, key ceremonies or external monitor uptime.

**Handoff:** durability/recovery matrix, all remaining source-region coverage, and unresolved operational-source assumptions to R10.


## Manifest and preparation dependencies

The authoritative bounded source regions are the rows owned by this phase in [region ownership](regions.md); candidate disposition/provenance is in [candidate inventory](candidates.md). Read directly relevant unchanged callees listed there and expand the coverage log when tracing discovers another dependency. Escalations are the entries whose phase list includes this phase in [escalation inventory](escalations.md), including cross-unit amendments and excluded-effect dispositions.

Read [system map](system-map.md), repository AGENTS.md and the complete review plan before source. Initial open seams are the trace questions above; predecessor reports supply additional named handoffs. A packet is navigation only and does not claim its owned source reviewed. Use fresh GPT-6.1 Sol context(s), load bounded source sections, and checkpoint rather than infer unread coverage. Only the coordinator changes the overall tracker.

Phase-specific escalation IDs (37): 066:2, 066:3, 066:4, 066:10, 067:5, 067:6, 067:8, 067:10, 067:12, 068:1, 071:1, 071:2, 071:3, 072:1, 075:1, 075:2, 076:1, 076:2, 077:1, 077:2, 078:1, 079:2, 079:4, 080:1, 080:2, 080:3, 081:1, 081:2, 083:1, 085:1, 086:1, 086:2, 088:1, 088:6, 088:7, 093:1, 097:1. Exact records: [escalations-R9.json](escalations-R9.json).

## Bounded reading and context plan

Read this phase’s [exact source manifest](manifest-R9.md) ([JSON](manifest-R9.json)), including unchanged dependencies only as the owned invariant requires. [SQL declaration navigation](regions-sql-definitions.md) lists earlier and later overrides; resolve signatures, grants, DROP/ALTER and actual final definitions in migration order. [Provenance](provenance.md) includes all delivery units and later fixes.

Assigned line inventory: supporting runtime artifact: 13,800, primary source: 7,781. These are navigation totals, not reviewed-line claims. Load source by bounded functions; do not paste the entire manifest/source into initial context.

Use successive fresh same-phase contexts for (a) platform DO/D1/R2 rebuild/retention and recovery, (b) ABO records/reconciliation/alert/housekeeping/operations, and (c) deployment/dependency/export/runtime guards. Supporting runtime lines are mostly generated lock metadata; context (c) must navigate package resolution/export/runtime-relevant entries in bounded sections and account for every assigned artifact, without treating lock metadata as application logic. Reserve separate context if needed rather than exceed the supporting-code target or omit regions.
