# R8 review packet

Target: `db9244fddfddc1905335fb8c7105328c15a0cc5e`. Prepared 2026-10-16 Africa/Cairo.

### R8 — Operator control plane, configuration and privileged workflows

**Question:** Do the final console and platform methods enforce the same operator intent, policy and audit guarantees throughout configuration and support operations?

**Primary source:** remaining ABO `ops/index.ts` sections; platform remaining vendor entrypoint method implementations; retained `control/*` handlers for routing, cohort, capability lifecycle, kill switches and token contracts; support/installation-lifecycle routes and audit writes; registry/bootstrap/plan-version/ceiling configuration policies and removed bootstrap script. R2 owns common cryptographic/perimeter machinery; R4/R6 own coverage mutations; this phase owns method-specific validation, dispatch and cross-action interactions.

**Read:** 02 §§3.3, 4, 6; 03 relevant registry/configuration/audit rows; 04 §1.3 and changed/removed control paths; 05 §§3.1–3.2. Provenance: P3.1–P3.3, P3.6, P3.10, P4.6–P4.9, P7.1. Escalations: 066–067, 070, 074, 081–083, 093.

**Trace together:** operator lookup/form → displayed target and operation args → policy/class checks → final service-binding method → durable audit/result. Include issuer/service/operator-key lifecycle, bootstrap and second credential, ceiling and plan changes, support data visibility, kill-switch propagation, and routing/capability configuration. Check absence of legacy `/control/*` entry routes and bearer-token backdoors in production code; retained internal `control/` filenames alone are not a defect. Review cross-action consistency and every remaining public method, not merely the console happy path.

**Handoff:** complete method coverage, configuration lifecycle/audit map and outstanding security seams to R9/R10.


## Manifest and preparation dependencies

The authoritative bounded source regions are the rows owned by this phase in [region ownership](regions.md); candidate disposition/provenance is in [candidate inventory](candidates.md). Read directly relevant unchanged callees listed there and expand the coverage log when tracing discovers another dependency. Escalations are the entries whose phase list includes this phase in [escalation inventory](escalations.md), including cross-unit amendments and excluded-effect dispositions.

Read [system map](system-map.md), repository AGENTS.md and the complete review plan before source. Initial open seams are the trace questions above; predecessor reports supply additional named handoffs. A packet is navigation only and does not claim its owned source reviewed. Use fresh GPT-6.1 Sol context(s), load bounded source sections, and checkpoint rather than infer unread coverage. Only the coordinator changes the overall tracker.

Phase-specific escalation IDs (24): 066:1, 066:4, 066:5, 066:6, 066:7, 066:8, 066:9, 067:2, 067:3, 067:5, 067:9, 067:12, 070:1, 071:1, 074:1, 074:2, 081:1, 081:2, 081:3, 082:1, 086:2, 087:1, 087:2, 093:1. Exact records: [escalations-R8.json](escalations-R8.json).

## Bounded reading and context plan

Read this phase’s [exact source manifest](manifest-R8.md) ([JSON](manifest-R8.json)), including unchanged dependencies only as the owned invariant requires. [SQL declaration navigation](regions-sql-definitions.md) lists earlier and later overrides; resolve signatures, grants, DROP/ALTER and actual final definitions in migration order. [Provenance](provenance.md) includes all delivery units and later fixes.

Assigned line inventory: primary source: 4,469, deleted: 1,951. These are navigation totals, not reviewed-line claims. Load source by bounded functions; do not paste the entire manifest/source into initial context.

One fresh same-phase context is the initial sizing choice; use named same-phase continuation contexts if directly relevant supporting code exceeds the target. Save exact read/unread regions, not a whole-file completion guess.
