# Quickstart: Provider port, fake adapter, and routing policy (D2)

Slice D2 adds the typed provider port, exhaustive failure classification, a deterministic fake adapter for pipeline suites, and a policy-as-data router that builds an ordered candidate chain with a recorded selection reason — all CPU-only, with no live providers or per-request server-side state.

**Scope rule:** This quickstart documents **this slice only**. It lists only files D2 added or modified, only D2 test files, and only commands that run D2 tests.

## 1. Architecture context

- **Delivery plan row D2** ([`../../docs/architecture/ai-platform/03-ai-platform-delivery-plan.md`](../../docs/architecture/ai-platform/03-ai-platform-delivery-plan.md) §3.5): provider port, fake adapter, and routing policy in band D.
- **Architecture sections implemented** ([`../../docs/architecture/ai-platform/01-ai-platform.md`](../../docs/architecture/ai-platform/01-ai-platform.md)):
  - §4.3.8 — provider adapters and egress (port boundary, classification, fake)
  - §4.3.7 — provider router and policy engine (policy-as-data → candidate chain + selection reason)
  - §7.3 — `routing_policy` entity shape (interpreted, not migrated)
  - §13.5 — provider adapter / pipeline tests with fake provider
- **Spec delivered** ([`spec.md`](spec.md)): frozen provider port, exhaustive retryable/terminal classification over A2 taxonomy, deterministic fake with scripted outcomes, routing-policy-as-data with stateless chain selection and `routing_decision` recording.
- **Plan scoped** ([`plan.md`](plan.md)): four implementation modules under `ai-platform/src/provider/` and `ai-platform/src/router/`; two unit test files; frozen contracts in `contracts/`; no D1 migrations, no `wrangler.toml` changes.

## 2. What was implemented

- `ai-platform/src/provider/port.ts` — typed `ProviderPort` boundary (canonical in; result / classified error out); no retry or fallback API on the export surface.
- `ai-platform/src/provider/classify.ts` — exhaustive `TaxonomyCode` → `retryable` | `terminal` mapping via A2 `isRetrySafe`.
- `ai-platform/src/provider/fake.ts` — `FakeAdapter` with ordered scripted-outcome queue behind `ProviderPort`.
- `ai-platform/src/router/index.ts` — `selectCandidateChain` reads versioned policy from config cache, filters targets, records `routing_decision`, bounds `max_parallel_attempts` to 1–6.
- Frozen contracts: [`contracts/provider-port.md`](contracts/provider-port.md), [`contracts/routing-decision.md`](contracts/routing-decision.md).

See [`spec.md`](spec.md) for full requirements and [`plan.md`](plan.md) for file-level traceability.

## 3. Files to review

| Path | Role |
| --- | --- |
| `ai-platform/src/provider/port.ts` | `ProviderPort`, `ScriptedOutcome`, `ProviderInvokeResult` types |
| `ai-platform/src/provider/classify.ts` | `classifyFailure`, retryability helper |
| `ai-platform/src/provider/fake.ts` | Deterministic fake adapter |
| `ai-platform/src/router/index.ts` | Policy-as-data router and `routing_decision` |
| `ai-platform/test/provider-port.test.ts` | T-D2-01..06, T-D2-18, T-D2-21 (24 tests) |
| `ai-platform/test/router.test.ts` | T-D2-07..17, T-D2-19, T-D2-20 (13 tests) |
| `specs/029-provider-port-routing/contracts/provider-port.md` | Frozen port, classification, fake contract |
| `specs/029-provider-port-routing/contracts/routing-decision.md` | Frozen policy interpretation and selection reason |

## 4. Prerequisites

From the repository root, first time only:

```bash
cd ai-platform
npm install
```

D2 tests are CPU-only — no Miniflare bindings or Cloudflare resources are required for this slice's unit suite.

## 5. Run the automated suite

From the repository root:

```bash
cd ai-platform
npx vitest run test/provider-port.test.ts test/router.test.ts
```

Expected: **37 passing tests** for this slice only (`provider-port.test.ts` — 24; `router.test.ts` — 13).

To run a subset:

```bash
npx vitest run test/provider-port.test.ts
npx vitest run test/router.test.ts
```

## 6. Inspect the changes

Read the frozen contracts:

```bash
cat specs/029-provider-port-routing/contracts/provider-port.md
cat specs/029-provider-port-routing/contracts/routing-decision.md
```

Inspect router selection-reason fields:

```bash
grep -n 'routing_decision\|max_parallel_attempts' ai-platform/src/router/index.ts
```

Run a focused test file:

```bash
cd ai-platform
npx vitest run test/router.test.ts
```
