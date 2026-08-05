# F4 — Soft-threshold Degraded Routing: Static Review

**Slice**: F4 — Soft-threshold degraded routing (`specs/042-soft-threshold-degraded-routing/`)
**Canonical architecture sections**: §4.3.3, §8.8, §4.3.7 of `docs/architecture/17-ai-platform.md`
**Review type**: Static review only (no build, no test execution, no file modifications)
**Date**: 2026-08-05

## 1. Executive Summary

F4 is a small, well-scoped slice and the core wiring is faithful to the architecture: the
soft-threshold branch rides the existing single Quota DO admission round trip (§4.3.3, §8.8),
hard exhaustion returns `quota_exhausted` carrying the entitlement `period_end` mapped onto
A2's `period_reset`, the gateway-internal `routing_tier` is derived only from the admission
answer and matched against `rules[].match.tiers` by the D2 router (§4.3.7), and the client
receives only the `degraded_notice` boolean on the accepted event. All seven named tests
(T1–T7) exist in `ai-platform/test/soft-threshold-routing.test.ts` and are registered in
`ai-platform/vitest.workers.config.ts`.

One significant defect was found: a `soft_threshold` of `0` (an enroll-legitimate value the
frozen contract explicitly says must never degrade) causes **every** request to be flagged
`degraded: true`, silently downgrading all routing for the installation — and no test covers
that case. Coverage gaps remain for the token/cost threshold dimensions and the
just-below-boundary region required by the §3.10 coverage rule. The client-injection test
(T4) exercises an artificial helper parameter rather than the real wire boundary, and the
production request path does not yet compose the F4 helpers (composition exists only in the
test harness, which the plan sanctions but which leaves "Done when" unproven end-to-end).

## 2. Critical Issues

- **High — Zero soft threshold degrades all traffic (§4.3.3, §8.8).**
  `isSoftThresholdCrossed` (`ai-platform/src/quota-do/index.ts:239-269`) guards each
  dimension's budget (`> 0`) but never guards the threshold itself. With
  `entitlement.soft_threshold = 0`, any positive-budget dimension yields
  `used / budget >= 0` → `true` even when `used = 0`, so the first request of a fresh period
  is admitted with `degraded: true` (`ai-platform/src/quota-do/index.ts:354-365`) and routed
  to the degraded tier. The frozen contract
  (`specs/042-soft-threshold-degraded-routing/contracts/soft-threshold-admission.md` §2)
  explicitly states "enroll's zero-budget / zero-threshold case never degrades", and FR-010
  requires below-threshold traffic to be unaffected. The D1 schema allows the value
  (`soft_threshold REAL NOT NULL`, `ai-platform/migrations/20260731120000_platform_schema.sql:34`)
  with no range constraint, and `mapEntitlementSnapshot` passes it through unvalidated
  (`ai-platform/src/admission/index.ts:128`). Fix: return `false` early when
  `!(threshold > 0)`, and validate the range at entitlement write time.

## 3. Bugs

- **Medium — Unvalidated `soft_threshold` range produces silent misbehavior at both ends
  (§4.3.3).** Beyond the zero case above, a threshold `> 1` silently disables degradation
  forever, and a threshold of exactly `1` can never fire because `isQuotaExhausted`
  (`ai-platform/src/quota-do/index.ts:228-237`) trips first on the same `>=` comparison.
  Neither is rejected anywhere (`ai-platform/src/admission/index.ts:115-130`). The contract
  defines the threshold as "a fraction of period budget", implying `(0, 1]`.
- **Low — `period_reset: ""` emitted on the concurrency-mapped exhaustion branch (§8.8).**
  `concurrency_exhausted` is mapped to `quota_exhausted` without a `periodReset`
  (`ai-platform/src/admission/index.ts:241-249`), and `supplementaryFieldsForCode` then
  emits `period_reset: ""` (`ai-platform/src/errors.ts:182-184`) — an empty, non-actionable
  "admin path" value, contrary to the spirit of FR-003/FR-004. This mapping is B4-frozen, so
  it is flagged as an inherited edge rather than an F4 rewrite target.
- **Low — In-flight requests do not count toward the soft threshold (§4.3.3).** Counters
  increment only on credit (`ai-platform/src/quota-do/index.ts:396-400`), so a burst of
  concurrent admissions just below the threshold all route `standard` even when their
  combined usage crosses it. §4.3.3 explicitly rejects pre-flight reservations, so this is
  architecturally sanctioned; noted only so the behavior is a conscious acceptance, not an
  oversight.

## 4. Architectural Deviations

- **Low — F4 signals are not composed in any production request path (§8.8, §4.3.7).**
  `resolveRoutingTier` / `degradedNoticeFromAdmission`
  (`ai-platform/src/soft-threshold/index.ts:15-35`) are referenced only by the test file;
  `worker.ts:108` calls `handleAdapterRequest(request)` with no options, so
  `options.degradedNotice` (`ai-platform/src/adapter.ts:53,363-367`) is never supplied in
  production, and no orchestrator feeds `routingTier` into `selectCandidateChain` or
  `createRequestRow`. The plan defers full-pipeline composition to a later slice and the
  tests compose the stages manually, so this is plan-consistent — but the delivery-plan
  "Done when" is currently proven only in the test harness, not on a real request path.
- **None found** for the core contracts: single DO round trip (§4.3.3, §8.8) is preserved
  (`callAdmissionDo` performs exactly one `stub.fetch`, `ai-platform/src/admission/index.ts:183-209`);
  the soft/hard branch order matches §8.8 (hard exhaustion checked at
  `ai-platform/src/quota-do/index.ts:320-327`, soft threshold evaluated only on the admit
  path); `routing_tier` is gateway-set and never read from the client (§4.3.7); the accepted
  event omits `degraded_notice` below threshold rather than sending `false`
  (`ai-platform/src/adapter.ts:69-71`), matching the frozen contract.
- **Documentation note (not a deviation):** the §8.8 diagram shows the hard-exhaustion reply
  carrying `{period reset, consumed, limit}`; the implementation carries only `period_end`.
  The frozen contract (soft-threshold-admission.md §3.2) explicitly declares `consumed` /
  `limit` narrative-only, so architecture-vs-implementation is reconciled in the contract —
  no action needed beyond awareness that the diagram is the looser artifact.

## 5. Missing or Weak Tests

- **High — No test for the zero-threshold / zero-budget boundary (§3.10 named boundaries;
  contract §2).** The contract explicitly names "enroll's zero-budget / zero-threshold case
  never degrades", yet no test seeds `soft_threshold = 0` or a zero-budget dimension. This
  gap is exactly why the Critical-issue bug shipped. Required by §3.10 (every named
  boundary).
- **Medium — Token and cost threshold dimensions are untested (§3.10 every branch).**
  `isSoftThresholdCrossed` has three dimension branches
  (`ai-platform/src/quota-do/index.ts:245-268`); all tests cross via the request-count
  dimension only (`SOFT_CROSS_REQUESTS_USED = 80` vs `REQUEST_QUOTA = 100`,
  `ai-platform/test/soft-threshold-routing.test.ts:44-47`). No test crosses on
  `tokensUsed / token_budget` or `costUsed / cost_budget`, and none verifies that a
  zero-budget dimension never contributes.
- **Medium — T4 tests an artificial seam, not the wire boundary (§4.3.7; §3.10
  prohibition).** `soft_threshold_tier_not_accepted_from_client`
  (`ai-platform/test/soft-threshold-routing.test.ts:790-817`) passes a `clientInjection`
  object into `resolveRoutingTier`, whose second parameter is deliberately unused
  (`ai-platform/src/soft-threshold/index.ts:30-34`). The test proves the helper ignores its
  own argument; it does not prove the real request path (HTTP body/headers through
  `handleAdapterRequest`) cannot inject a tier. The prohibition is honored in practice only
  because no production code reads such fields — which the test does not demonstrate.
- **Low — No just-below-boundary case (§3.10 boundaries).** T1 tests the exact boundary
  (80/100 = 0.8 ≥ 0.8) and T3 tests far below (10/100); nothing tests 79/100 to pin the
  `>=` semantics from below.
- **Low — T2's "admin path / no hard-lock" assertion is necessarily thin (§8.8; FR-004).**
  `hard_exhaustion_quota_exhausted_admin_path_no_lock`
  (`ai-platform/test/soft-threshold-routing.test.ts:738-763`) asserts `quota_exhausted` +
  `period_reset` and that no `ai_request` row is journaled (the §6.4 prohibition). "Non-AI
  workflows remain fully usable" is untestable at the gateway layer and is reasonably
  deferred to E4 — acceptable, but the test name overpromises relative to what it proves.

## 6. Recommended Improvements

- **High** — Guard the threshold in `isSoftThresholdCrossed`
  (`ai-platform/src/quota-do/index.ts:243`): `if (!(threshold > 0)) return false;`, and add
  a range check (`0 < soft_threshold <= 1`) wherever entitlements are written (enroll /
  control plane), matching the contract's "fraction of period budget".
- **High** — Add tests: `soft_threshold = 0` never degrades; zero-budget dimension never
  contributes; token-dimension and cost-dimension crossings each select the degraded chain.
- **Medium** — Remove the dead `_clientInjection` parameter and `ClientRoutingInjection`
  type from `ai-platform/src/soft-threshold/index.ts:8-13,30-34` (technical debt: it
  simulates a security boundary that does not exist in code), and re-express T4 as a
  wire-level test once a POST orchestrator exists, or as an assertion that the adapter's
  request parsing surfaces no tier fields.
- **Medium** — When the full pipeline orchestrator lands, wire
  `resolveRoutingTier` / `degradedNoticeFromAdmission` / `RequestRowInput.routingTier` into
  it and add one end-to-end POST test so "Done when" is proven on the real path, not only
  in a hand-composed harness.
- **Low** — Add a 79/100 just-below-boundary case to pin the `>=` comparison.
- **Low** — Avoid emitting `period_reset: ""` on the concurrency-mapped `quota_exhausted`
  branch (`ai-platform/src/errors.ts:183`); either populate it from the entitlement snapshot
  (available in `runAdmission`) or omit the field when there is no value.
