# R1 review packet

Target: `db9244fddfddc1905335fb8c7105328c15a0cc5e`. Prepared 2026-10-16 Africa/Cairo.

### R1 — Tenant identity, token issuance and clinic authorization

**Question:** Does the current authenticated membership determine the same clinic and authority from SQL issuance through vendor authentication, including stale sessions and key changes?

**Primary source:** backend membership/tenant-scoping migrations and later staff-membership/session-RLS fix; issuer-key-custody and canonical billing/feed JWT migrations; platform `identity/` and identity/binding/key-registry sections of `vendor/entrypoint.ts`; ABO `clinic-api/auth.ts`; Dart token-minting ports and `billing_token_client.dart`. Include the actual final SQL definitions and their grants, RLS, definer ownership and search paths, following migration order and overrides.

**Read:** 02 §§2–3, 6–7; 03 §4 and identity rows in §3.2; 04 §§2.1, 3.1, 4.1–4.2. Provenance: P1, P3.2, P4.1, P5.1, P6.1 and later fixes. Escalations: 066, 076, 087, plus token-related amendments routed from other units.

**Trace together:** active-org selection → live-membership recheck → role/scope/audience claims → signing key → platform/ABO verifier → tenant binding. Include role removal, org switching, missing/legacy claims, key rotation/revocation, token lifetime and issuance limits. Review inherited tenant-scoped tables/RPCs touched by P1 as one authority surface, not merely the new billing functions. Check that no vendor service gets a Supabase credential or clinic write path.

**Handoff:** identity/authority table and exact consumers to R2, R3, R5 and R7; unresolved authorization questions remain explicitly open.


## Manifest and preparation dependencies

The authoritative bounded source regions are the rows owned by this phase in [region ownership](regions.md); candidate disposition/provenance is in [candidate inventory](candidates.md). Read directly relevant unchanged callees listed there and expand the coverage log when tracing discovers another dependency. Escalations are the entries whose phase list includes this phase in [escalation inventory](escalations.md), including cross-unit amendments and excluded-effect dispositions.

Read [system map](system-map.md), repository AGENTS.md and the complete review plan before source. Initial open seams are the trace questions above; predecessor reports supply additional named handoffs. A packet is navigation only and does not claim its owned source reviewed. Use fresh GPT-6.1 Sol context(s), load bounded source sections, and checkpoint rather than infer unread coverage. Only the coordinator changes the overall tracker.

Phase-specific escalation IDs (14): 066:1, 066:2, 066:3, 066:4, 066:5, 066:6, 066:7, 066:8, 066:9, 076:1, 077:1, 087:1, 087:2, 088:1. Exact records: [escalations-R1.json](escalations-R1.json).

## Bounded reading and context plan

Read this phase’s [exact source manifest](manifest-R1.md) ([JSON](manifest-R1.json)), including unchanged dependencies only as the owned invariant requires. [SQL declaration navigation](regions-sql-definitions.md) lists earlier and later overrides; resolve signatures, grants, DROP/ALTER and actual final definitions in migration order. [Provenance](provenance.md) includes all delivery units and later fixes.

Assigned line inventory: primary source: 7,167. These are navigation totals, not reviewed-line claims. Load source by bounded functions; do not paste the entire manifest/source into initial context.

Use two fresh same-phase contexts: **R1-SQL** owns all backend R1 migrations/final overrides and inherited tenant-scoped dependencies (~5,256 assigned lines); **R1-consumers** owns remaining R1 platform/ABO identity, registry and Dart regions (~1,911 assigned lines), plus supporting caller/receiver verification. SQL context supplies exact claims/role/current-org authority to consumers; coordinator reconciles producer/receiver traces and findings. These are one coherent R1 review, not independent delivery reviews.
