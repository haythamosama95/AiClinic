# Quickstart: Soft-threshold degraded routing (F4)

F4 wires soft-threshold quota pressure into degraded routing: when period usage crosses the
entitlement soft threshold but budget remains, admission allows with `degraded: true`, the gateway
sets `routing_tier = degraded`, the D2 router selects the degraded target chain, and the client
receives `accepted { degraded_notice }`. Hard budget exhaustion returns `quota_exhausted` with A2's
`period_reset` (entitlement period end).

## 1. Architecture context

- **Delivery plan** — Band F row F4 in
  [`../../docs/architecture/17b-ai-platform-delivery-plan.md`](../../docs/architecture/17b-ai-platform-delivery-plan.md)
  (Needs: D2, B4).
- **Architecture** — Implements §4.3.3 (entitlement / quota soft-threshold branch), §8.8 (sequence),
  and §4.3.7 (provider router `routing_tier` signal) of
  [`../../docs/architecture/17-ai-platform.md`](../../docs/architecture/17-ai-platform.md).
- **Spec** — [`spec.md`](./spec.md) defines soft-threshold allow with `{ degraded: true }`, hard
  exhaustion non-lockout with `period_reset`, gateway-set `routing_tier`, and client-visible
  `degraded_notice`.
- **Plan** — [`plan.md`](./plan.md) scoped Quota DO + admission extensions, `src/soft-threshold/`
  signal module, journal `routing_tier` persistence, adapter `degraded_notice`, and seven
  integration tests with seeded DO counters.

## 2. What was implemented

- Quota DO soft-threshold branch on the existing admission RPC (`degraded: true` when crossed with
  budget remaining; `period_end` on hard exhaustion).
- Stage-8 admission mapping (`degraded` on allow; `periodReset` on `quota_exhausted`).
- `src/soft-threshold/` — pure helpers deriving `routing_tier` and `degraded_notice` from
  admission (client tier injection ignored).
- C3 journal writer extension — `RequestRowInput.routingTier` → `ai_request.routing_tier`.
- A6 adapter extension — optional `degraded_notice` on `accepted` SSE data via
  `buildAcceptedSseEvent`.
- Frozen contracts under `contracts/soft-threshold-admission.md` and
  `contracts/degraded-routing-signal.md`.

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

Expected: **7 passing tests** in `test/soft-threshold-routing.test.ts` (T1–T7).

## 5. Inspect the changes

```bash
cd ai-platform
rg 'degraded|routing_tier|period_end|period_reset' src/quota-do src/admission src/soft-threshold src/journal src/adapter.ts
cat test/soft-threshold-routing.test.ts
ls ../specs/042-soft-threshold-degraded-routing/contracts/
```
