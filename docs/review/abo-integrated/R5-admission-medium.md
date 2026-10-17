# R5 admission medium source review

Target `db9244fddfddc1905335fb8c7105328c15a0cc5e`; baseline `c6cf2c3809a38e2a348f373e926cf2585cfcf291`; history `d2e7666f59d8ea7b37a5e05fae89f34d96ba1a3f`. GPT-6.1 Sol, explicitly **medium**. Result: complete with findings. All 225 assigned regions / 5,153 primary lines read; exact completed union and supporting reads are in [coverage JSON](R5-admission-medium-coverage.json). No primary regions remain. Static source only; no tests/build/lint/services, excluded implementations, source changes or tracker changes. HEAD matches target; assigned production paths have no working-tree diff.

## Findings

### ADM1 — P1: concurrent fallback admissions exceed the outage allowance cap

`ai-platform/src/admission/index.ts:504–529` reads pending weight and inserts in separate awaited D1 statements. With cap `5*w_max`, six simultaneous distinct keys of weight `w_max` can all read pending=0, pass `pending+w<=cap`, and each insert a fresh row. Their guards then journal and invoke providers (`pipeline/index.ts:493–519,581–598,642–671`; `worker.ts:1507–1539`). D1 serialization of individual statements does not serialize the read/insertion pair. Ordinary configured per-clinic and per-actor rate limits permit this small burst. Admission does not enforce a DO concurrency limit in fallback. The intended five-weight outage overshoot bound therefore is not an invariant. This is independent of the accounting reviewer's drain defects.

Fix steps (implementation-ready):
1. In `tryMirrorFallbackAdmission`, replace `pendingFallbackWeight` plus unconditional insertion with one `INSERT OR IGNORE … SELECT … WHERE (SELECT COALESCE(SUM(weight),0) FROM fallback_admission WHERE installation_id=? AND state='pending') + ? <= ?`. Keep the sum and insert inside that single D1 statement, with installation and `5*publishedQuotaWeightMax()` bound explicitly.
2. Inspect `meta.changes`; if zero, distinguish an existing identity row from cap refusal. Return `coverage_unknown` for a genuinely new over-cap request. Keep existing request identity stable; do not turn an ignored insert into a second fresh admission.
3. Coordinate terminalization with the accounting reviewer's drain fix: only pending rows count, and durable settlement must move the same row out of pending exactly once. No new table is needed for this atomic cap repair.
4. Completion criteria: simultaneous distinct-key admissions cannot make the sum of newly pending weights exceed the cap; exactly-at-cap succeeds, above-cap fails, and same-key retries do not add weight.

### ADM2 — P2: fallback raises an economy plan's provider cost ceiling to standard

The authoritative term stores `max_cost_class`, but the mirror term projection (`quota-do/coverage.ts:288–312`) and parser (`2558–2583`) omit it. Fallback returns only a legacy dummy entitlement (`admission/index.ts:209–224,539–565`); `runGuard` deliberately omits `termAdmission` (`pipeline/index.ts:556–566`). Production routing consequently supplies `standard` for its entitlement ceiling (`worker.ts:1110–1113`). Router `resolveEffectiveCostClass` (`router/index.ts:308–345`) uses that ceiling, and target filtering admits standard targets under a standard ceiling (`557–579`). An economy-plan request during an outage can therefore invoke a standard-cost target when the matched degraded routing rule permits one. Degraded routing tier does not itself enforce an economy cost ceiling. Exposure is outage-bounded absent ADM1, so severity is P2.

Fix steps (implementation-ready; conservative choice):
1. In the Worker invocation context, derive an explicit routing ceiling: use `guard.termAdmission.snapshot.max_cost_class` for normal term admission; use `economy` for a fallback guard identified by its `entitlementSnapshot`. Fail closed for an admission with neither representation.
2. Pass this derived ceiling consistently to the router's entitlement ceiling and manifest-cost input. Do not infer a plan from the dummy `standard` legacy entitlement.
3. Keep the existing degraded routing tier. This deliberately restricts all fallback requests to the cheapest class, avoiding a new public coverage/feed schema or mirror backfill; standard-plan fallback may have a smaller available chain.
4. Completion criteria: an economy term with a degraded rule containing standard targets excludes those targets during DO outage; normal term routing retains its admitted snapshot ceiling; missing fallback plan metadata cannot increase spend authority. Coordinate with the accounting reviewer's replacement of the fallback guard shape.

### ADM3 — P2: mirror fallback bypasses the mandatory one-use JTI check

`runAdmission` sends `principal.jti` only to the unavailable DO (`admission/index.ts:667–684`). After transport failure, `tryMirrorFallbackAdmission` neither checks nor persists it (`458–565`). `fallback_admission` has installation/key and request-ID uniqueness but no JTI (`migrations/20261006160000_fallback_admission_feed.sql:3–16`); journal insertion also contains no JTI (`journal/index.ts:245–273`). A still-valid signed AI token can be replayed with distinct idempotency keys while the DO is unavailable; each gets a fresh UUID, journal row and provider invocation until the outage cap. This violates 03 §6.2's installation-scoped replay requirement. It is bounded by the intended fallback allowance, independently of ADM1; it is not a claim that duplicate request IDs produce duplicate provider calls.

Fix steps (**not implementation-ready: architecture decision required**):
1. Safe containment in `runAdmission`: return retryable `coverage_unknown` when DO transport cannot authorize the JTI, until the architecture owner chooses the replay rule for outages. This disables the affected fallback path temporarily.
2. Architecture owner must choose either a common durable JTI claim consulted before **all** normal and fallback admissions, with revised hot-only/denied-write budget; or an explicit amended contract allowing bounded token replay during an outage. Merely adding a JTI column to new fallback rows cannot detect a token already consumed by the hidden DO before the outage.
3. After that decision, implement the common claim's atomic installation/JTI uniqueness and horizon (if selected) consistently in normal admission, idempotent replay, fallback and cleanup; preserve actor/branch/capability/fingerprint binding. Do not let the implementation agent silently weaken the invariant.
4. Completion criteria: either repeated prior-normal and prior-fallback JTIs are rejected during outage before provider work, or the deliberately bounded exception and its revised acceptance contract are explicitly approved. Stop after containment if the decision is unresolved.

## Trace conclusions and handoffs

Normal ingress verifies the issuer token, checks fresh mirror suspension/kill switches, resolves capability membership/role/scope, validates context and computes a canonical request fingerprint (`pipeline:392–470`). It sends actor/branch/capability/fingerprint and any matching journal answer/conflict into the DO (`admission:636–684`). A durable journal answer alone is not replayed when the DO is unavailable (`746–750`). DO version negotiation precedes coverage-table creation (`worker:1732–1751`), accepts N/N-1 and echoes the accepted request version; an explicit contract rejection maps to `coverage_unknown` without fallback (`admission:731–732`).

A timed-out DO call is not canceled; its generated UUID is reused in the fallback row (`admission:568–599,666–684,756–765`). The accounting reviewer owns whether late reservation/credit and drain share an exactly-once receipt. That reviewer also owns the concrete missing fallback term handoff: fallback guards omit `termAdmission`, while Worker `1269–1272` returns after provider work without normal terminal settlement. This report does not duplicate that finding.

The fallback same-key ignored-insert path returns fresh `grace_admitted` without binding checks (`530–549`). The journal's plain PK insert rejects a second insert of that same UUID, so source does **not** support a blanket duplicate-provider claim for same-key retries. A changed-payload race can instead win the first journal insert under the older fallback identity; tie any future schema repair to ADM3's chosen identity authority. No separate speculative finding is counted.

Legacy entitlement/plan cache kinds return miss (`config-cache:261–264`); `evaluateEntitlement`, `loadMatchingGrant`, and `settleHappyPath` have no production callers in `src`. The registry is installed at Worker boot with the published manifest (`worker:194–204`). TEST_CLOCK faults require the environment flag before any table read (`worker:1769–1771`, `clock.ts:8–11`); production config does not set it or DURATION_SCALE. Private DO clock/scale overrides are not exposed through the public request-to-guard body mapping. Actual deployment settings remain outside static review; R9 owns deployment verification.

## Escalations

- **066:6** checked final mirror capability readers and missing legacy table readers; tier helper is absent from the live guard.
- **066:8**, **066:10** are excluded harness/assertion effects. No excluded implementation inspected; accounting reviewer checks real settlement/payload behavior.
- **067:1**, **095:1** checked Worker version production, before-write negotiation, echo and coverage-unknown refusal mapping.
- **067:7** own feed handler preserves stored event kind, sequence and snapshot; DO event production is accounting reviewer's responsibility; projection consumer is R7.
- **067:9** checked string-array membership through term mirror, resolver, discovery and fallback. ADM2 records the related lost cost ceiling.
- **068:1** calendar/placement source belongs to accounting reviewer; own Worker propagation preserves staging scale only when configured.
- **089:1** own admission produces the three named coverage denial codes. R7 must verify Flutter refresh-on-denial consumer; no frontend completion claimed.

Exact supporting source ranges, all nine dispositions and exact completed region indices are saved in the coverage JSON. Remaining decision: ADM3 architecture choice; remaining cross-phase consumer work belongs to R7/R9 as above. Inherited R1 token-validity exposure and R4 D1 grant-transaction/due-boundary/wakeup/global-grant identity roots remain canonical and are not new findings here.
