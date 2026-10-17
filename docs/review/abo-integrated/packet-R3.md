# R3 review packet

Target: `db9244fddfddc1905335fb8c7105328c15a0cc5e`. Prepared 2026-10-16 Africa/Cairo.

### R3 — Administrator checkout through confirmed payment

**Question:** Can a legitimate checkout become exactly the intended confirmed payment, without browser returns, callbacks, retries or overlapping workers creating unsupported value?

**Primary source:** ABO offers/contact/checkouts, provider port/registry and Paymob client/adapter, notification intake, confirmation and lease sections of `work/runner.ts`, inquiry-budget code; corresponding checkout/evidence/payment/work schema; Flutter offers/contact/checkout flow and the associated `abo_client.dart` operations. Include return routes and worker scheduling that connect these modules.

**Read:** 03 §§2.1–2.6, 2.9, 2.11, 5.1–5.2, 5.6; 04 §§2.2–2.3, 5; 02 TB-1 and billing boundaries; 05 relevant scheduled work/failure modes. Provenance: P4.1–P4.3, P4.5, P6.3. Escalations: 076–078, 080 inquiry budget, 091, and any later provider/source fixes.

**Trace together:** displayed offer/contact → immutable checkout snapshot and idempotency key → intention request → callback evidence → authoritative inquiry → confirmed payment and queued grant. Include same-key/different-payload retries, multiple provider successes, amount/currency/account correlation, forged/duplicate/late notifications, missing callback, lease expiry and process failure between durable writes. Verify redirects are UX signals only and do not authorize confirmation. Follow provider budget consumption across every caller.

**Handoff:** exact payment/grant eligibility boundary to R4; reversal identities and provider normalization to R6; durable-evidence obligations to R9.


## Manifest and preparation dependencies

The authoritative bounded source regions are the rows owned by this phase in [region ownership](regions.md); candidate disposition/provenance is in [candidate inventory](candidates.md). Read directly relevant unchanged callees listed there and expand the coverage log when tracing discovers another dependency. Escalations are the entries whose phase list includes this phase in [escalation inventory](escalations.md), including cross-unit amendments and excluded-effect dispositions.

Read [system map](system-map.md), repository AGENTS.md and the complete review plan before source. Initial open seams are the trace questions above; predecessor reports supply additional named handoffs. A packet is navigation only and does not claim its owned source reviewed. Use fresh GPT-6.1 Sol context(s), load bounded source sections, and checkpoint rather than infer unread coverage. Only the coordinator changes the overall tracker.

Phase-specific escalation IDs (10): 076:1, 077:1, 077:2, 078:1, 079:2, 080:1, 080:2, 080:3, 081:1, 091:1. Exact records: [escalations-R3.json](escalations-R3.json).

## Bounded reading and context plan

Read this phase’s [exact source manifest](manifest-R3.md) ([JSON](manifest-R3.json)), including unchanged dependencies only as the owned invariant requires. [SQL declaration navigation](regions-sql-definitions.md) lists earlier and later overrides; resolve signatures, grants, DROP/ALTER and actual final definitions in migration order. [Provenance](provenance.md) includes all delivery units and later fixes.

Assigned line inventory: primary source: 6,276. These are navigation totals, not reviewed-line claims. Load source by bounded functions; do not paste the entire manifest/source into initial context.

One fresh same-phase context is the initial sizing choice; use named same-phase continuation contexts if directly relevant supporting code exceeds the target. Save exact read/unread regions, not a whole-file completion guess.
