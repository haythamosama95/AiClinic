# R2 review packet

Target: `db9244fddfddc1905335fb8c7105328c15a0cc5e`. Prepared 2026-10-16 Africa/Cairo.

### R2 — Shared wire contracts, service perimeter and human approval

**Question:** Do callers and receivers agree on authenticated bytes, accepted versions and the authority needed for each kind of operation?

**Primary source:** production `packages/vendor-contracts/src/` exports, canonicalization, identifiers, JWS, claims, messages, receipts, WebAuthn and Access verification; vendor entrypoint dispatch/authentication/assertion/replay sections; ABO host/version middleware and console Access/passkey/operation-binding sections; relevant worker/DO version dispatch. Read consumer use at the actual verification sites, not just package implementations.

**Read:** 02 §§1.3–1.4, 2–4, 6; 04 §§1.1–1.6, 2.3, 7. Provenance: P2, P3.1–P3.3, P4.1, P4.6–P4.7, P7.2–P7.3. Escalations: 066–067, 076, 079, 081–082, 094–095.

**Trace together:** public request/service-binding call → correct version rejection order → Access identity or machine credential → operation hash and bound arguments → passkey verification → replay recording → authorized dispatch. Check ceremony freshness, actor/credential binding, delayed activation/bootstrap, exact mutation authorization, and cross-host/route bypass. Check package behavior against SQL/Dart producers and receivers without reviewing vectors or testkit. Separate receipt cryptographic validity from its business-state effect, which R4/R6 review.

**Handoff:** channel/version matrix, M/H/HP method-authority map, and proof obligations for all value-moving consumers in R4/R6/R8. R8 still owns each method's specific policy and mutation.


## Manifest and preparation dependencies

The authoritative bounded source regions are the rows owned by this phase in [region ownership](regions.md); candidate disposition/provenance is in [candidate inventory](candidates.md). Read directly relevant unchanged callees listed there and expand the coverage log when tracing discovers another dependency. Escalations are the entries whose phase list includes this phase in [escalation inventory](escalations.md), including cross-unit amendments and excluded-effect dispositions.

Read [system map](system-map.md), repository AGENTS.md and the complete review plan before source. Initial open seams are the trace questions above; predecessor reports supply additional named handoffs. A packet is navigation only and does not claim its owned source reviewed. Use fresh GPT-6.1 Sol context(s), load bounded source sections, and checkpoint rather than infer unread coverage. Only the coordinator changes the overall tracker.

Phase-specific escalation IDs (33): 066:1, 066:4, 066:5, 066:7, 066:9, 067:1, 067:2, 067:8, 067:10, 067:11, 067:12, 071:1, 071:2, 071:3, 072:1, 075:2, 076:1, 077:1, 078:1, 079:1, 079:4, 079:6, 081:1, 081:2, 081:3, 082:1, 086:2, 087:1, 088:1, 088:6, 094:1, 095:1, 095:2. Exact records: [escalations-R2.json](escalations-R2.json).

## Bounded reading and context plan

Read this phase’s [exact source manifest](manifest-R2.md) ([JSON](manifest-R2.json)), including unchanged dependencies only as the owned invariant requires. [SQL declaration navigation](regions-sql-definitions.md) lists earlier and later overrides; resolve signatures, grants, DROP/ALTER and actual final definitions in migration order. [Provenance](provenance.md) includes all delivery units and later fixes.

Assigned line inventory: primary source: 3,885. These are navigation totals, not reviewed-line claims. Load source by bounded functions; do not paste the entire manifest/source into initial context.

One fresh same-phase context is the initial sizing choice; use named same-phase continuation contexts if directly relevant supporting code exceeds the target. Save exact read/unread regions, not a whole-file completion guess.
