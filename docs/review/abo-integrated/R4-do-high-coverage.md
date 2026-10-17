# R4 DO high coverage

Target `db9244fddfddc1905335fb8c7105328c15a0cc5e`; baseline `c6cf2c3809a38e2a348f373e926cf2585cfcf291`; history `d2e7666f59d8ea7b37a5e05fae89f34d96ba1a3f`. Reviewer GPT-6.1 Sol, explicitly high. No unpinned credit.

**All 54 assigned manifest regions (1498 inventory lines) freshly read.** No unread primary regions or source-reading blocker. Result: complete with findings (4 P1, 1 P2); no remaining work in this bounded context. Complete outside-assignment R4 synthesis belongs to coordinator.

## Actual source reads

- `ai-platform/src/quota-do/coverage.ts`: 1–460, 462–542, 600–1574, 1575–1930, 2007–2110, 2570–2908, 3120–3400, 3506–3545, 4185–4315.
- `ai-platform/src/quota-do/index.ts`: 400–455, 800–1210, 1211–1565, 1900–2005.
- `ai-platform/src/worker.ts`: 1690–1795, 1840–1905, 1995–2090.
- `ai-platform/src/vendor/entrypoint.ts`: 3410–3470, 3585–3704, 4540–4610.
- `ai-platform/src/coverage-read/index.ts`: 1–145.
- `ai-platform/migrations/20261003140000_plan_version_paid_grant_coverage.sql`: 1–90.
- `ai-platform/src/coverage/calendar.ts`: 1–71.

Owned manifest symbols and exact boundaries are recorded individually in [JSON](R4-do-high-coverage.json). Supporting reads are bounded to R4 placement/value/receipt/shipment invariants; they do not complete later-phase ownership. The initial truncated 95–230 gap was explicitly reread and closed.

## Escalation dispositions

- **067:2**: Service-key authorization is upstream; receiver consumes authorized request; coordinator/platform owns register/list/paid verification closure.
- **067:3**: DO stores immutable planSnapshot supplied by published-plan receiver; actual term consumer read. Upstream publish/retire and replay validation owned by platform reviewer.
- **067:4**: loadTerms position order; queued filter and recent descending max12/live-hot usage source verified; R7 owns actual external consumer freshness.
- **067:5**: Shipment produces exact grant ledger fields; listGrants consumer/filter owned by platform/coordinator, no full R8/R9 claim.
- **067:6**: Grant ledger D1 then distinct R2 .ndjson object before deleting outbox verified; void suffix seen supporting shipment only. Full rebuild R9.
- **067:7**: Paid event ordering term_ended,term_activated,grant_applied verified; immediate snapshots reflect intermediate transition states; post-grant wording ambiguity forwarded to coordinator/R7 without new finding.
- **067:8**: signReceipt canonical signing bytes and grantApplied clinic_seq linkage/source columns verified; caller cryptographic/business acceptance owned by coordinator.
- **067:9**: DO stores request.planSnapshot; index admission consumes capabilities/cost/concurrency and snapshot consumers read JSON; producer mapping at entrypoint3410 and3662 checked supporting.
- **067:11**: DO assumes upstream validated approvals; no separate DO human check. All-kind minimum producer/receiver closure owned by platform/coordinator.
- **067:12**: Reference-only transcription workflow; current amended requirements used, no excluded code inspected.
- **068:1**: calendar complete; UTC clamp/day/staging-unit behavior and direct grant/boundary callers verified. No harness analysis.
- **069:1**: Reference-only clock/test effect excluded. Runtime environment clock/scale dispatch incidentally read in worker; deployment isolation R9.
- **070:1**: Local per-grant and open-lower/closed-upper 90-day sums verified; adjustment contribution support read; D5 org-history defect, R2 canonical override-binding defect retained; complete control method R8.
- **073:1**: Queued and max12 recent producer shape verified; usage chooses hot for active ID else used_final. External API/desktop full flow R7.
- **079:1**: Paid DO receives immutable envelope and hashes it, sign receipt retains hash; operation approval producer/receiver coordinator/platform ownership.
- **079:2**: Coverage snapshot producer read; ABO subscription/payment notices and fallback consumer coordinator/R7 ownership, not credited here.
- **079:4**: DO signs applied receipt and stores replay copy; ABO verification/parking coordinator ownership; D1/D4 expose durability gaps.
- **079:6**: Paid operation approval validator upstream platform/coordinator ownership; no fabricated DO assertion validation.
- **083:1**: Supporting transferIn index0..length-1 creates deterministic transferGrantId and one imported term/grant per package element; full transfer correctness R6.
- **085:1**: DO receipt stored verbatim in outbox then D1/R2; reconciliation exact comparison owned by R9/coordinator; no reconciliation audit claimed.

## Reference and verification scope

Read repository AGENTS, constitution, complete integrated plan, R4 packet/manifest/system map, canonical R1/R2/R3 handoffs and all 20 R4 escalation resolutions. Used amended lifecycle/contract sections, relevant operations failure modes and bounded 067/069/070 spec requirement references. No test implementation was inspected/analyzed. Worker source includes runtime test-clock/fault gate declarations; only production reachability/environment behavior was relevant.

HEAD equals T, B/H objects exist, and git diff against T for primary/selected supporting source was empty. No tracked application source edits, tests/build/lint/service operations, commits or checkout.
