# Quickstart: Soft-threshold degraded routing (F4)

F4 wires soft-threshold quota pressure into degraded routing: when period usage crosses the
entitlement soft threshold but budget remains, admission allows with `degraded: true`, the gateway
sets `routing_tier = degraded`, the D2 router selects the degraded target chain, and the client
receives `accepted { degraded_notice }`. Hard budget exhaustion returns `quota_exhausted` with A2's
`period_reset` (entitlement period end).

## 1. Architecture context

- **Delivery plan** — Band F row F4 in
  [`../../docs/architecture/ai-platform/03-ai-platform-delivery-plan.md`](../../docs/architecture/ai-platform/03-ai-platform-delivery-plan.md)
  (Needs: D2, B4).
- **Architecture** — Implements §4.3.3 (entitlement / quota soft-threshold branch), §8.8 (sequence),
  and §4.3.7 (provider router `routing_tier` signal) of
  [`../../docs/architecture/ai-platform/01-ai-platform.md`](../../docs/architecture/ai-platform/01-ai-platform.md).
- **Spec** — [`spec.md`](./spec.md) defines soft-threshold allow with `{ degraded: true }`, hard
  exhaustion non-lockout with `period_reset`, gateway-set `routing_tier`, and client-visible
  `degraded_notice`.
- **Plan** — [`plan.md`](./plan.md) scoped Quota DO + admission extensions, `src/soft-threshold/`
  signal module, journal `routing_tier` persistence, adapter `degraded_notice`, and seven
  integration tests with seeded DO counters.

## 2. What was implemented

- Quota DO soft-threshold branch (`degraded: true` when crossed; `period_end` on hard exhaustion);
  `soft_threshold` in `[0, 1]` with `0` = disabled; out-of-range coerced via `coerceSoftThreshold`;
  `isSoftThresholdCrossed` early-returns when `!(threshold > 0) || threshold > 1`.
- Stage-8 admission mapping (`degraded` on allow; `periodReset` on hard + concurrency→quota;
  empty `period_reset` omitted on the wire).
- `src/soft-threshold/` — `resolveRoutingTier(admission)` only; wire-boundary
  `CLIENT_ROUTING_INJECTION_KEYS` / empty `ADAPTER_ROUTING_BODY_FIELDS`.
- C3 journal `routingTier` + A6 optional `degraded_notice` on `accepted`.
- Frozen contracts under `contracts/*`. Harness composes the F4 path until a POST orchestrator
  exists; in-flight does not count toward soft threshold (§4.3.3).

## 3. Files to review

| Path | Role |
| --- | --- |
| `ai-platform/src/quota-do/index.ts` | Soft/hard threshold evaluation inside admission RPC |
| `ai-platform/src/admission/index.ts` | Maps DO `degraded` and `period_end` onto gateway outcomes |
| `ai-platform/src/soft-threshold/index.ts` | `routing_tier` / `degraded_notice` derivation |
| `ai-platform/src/journal/index.ts` | Persists `routing_tier` on `createRequestRow` |
| `ai-platform/src/adapter.ts` | `buildAcceptedSseEvent` with optional `degraded_notice` |
| `ai-platform/test/soft-threshold-routing.test.ts` | T1–T7 integration cases |
| `specs/042-soft-threshold-degraded-routing/contracts/soft-threshold-admission.md` | Frozen admission extension |
| `specs/042-soft-threshold-degraded-routing/contracts/degraded-routing-signal.md` | Frozen routing / notice signals |

## 4. Run the automated suite

From the repository root:

```bash
cd ai-platform
npx vitest run --config vitest.workers.config.ts test/soft-threshold-routing.test.ts
```

Expected: **12 passing describes** in `test/soft-threshold-routing.test.ts` (T1–T7 plus zero / zero-budget / token / cost / just-below boundary cases). T2 is gateway refuse + `period_reset` + no journal only (non-AI UX is E4).

## 5. Inspect the changes

```bash
cd ai-platform
rg 'degraded|routing_tier|period_end|period_reset' src/quota-do src/admission src/soft-threshold src/journal src/adapter.ts
cat test/soft-threshold-routing.test.ts
ls ../specs/042-soft-threshold-degraded-routing/contracts/
```
