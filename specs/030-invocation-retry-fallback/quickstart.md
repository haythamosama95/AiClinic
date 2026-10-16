# Quickstart: Invocation with bounded retry and fallback (D3)

Slice D3 adds the platform-internal attempt loop: given D2's ordered candidate chain, the gateway walks targets through the provider port with bounded jittered retries, attempt-level selection reasons, per-invoke journal feeds, exhausted-chain `provider_unavailable`, and regenerating/no-splice on fallback after partial streaming — all CPU-only with an in-memory sink.

**Scope rule:** This quickstart documents **this slice only**. It lists only files D3 added or modified, only D3 test files, and only commands that run D3 tests.

## 1. Architecture context

- **Delivery plan row D3** ([`../../docs/architecture/ai-platform/03-ai-platform-delivery-plan.md`](../../docs/architecture/ai-platform/03-ai-platform-delivery-plan.md) §3.5): invocation with bounded retry and fallback in band D.
- **Architecture sections implemented** ([`../../docs/architecture/ai-platform/01-ai-platform.md`](../../docs/architecture/ai-platform/01-ai-platform.md)):
  - §4.3.7 — provider router and policy engine (attempt loop walks `routing_decision.chain[]`; per-target `max_attempts` and `timeout_ms`; attempt-level `selection_reason`)
  - §8.6 — inference pipeline (retry/fallback sequence, exhausted-chain `provider_unavailable`, regenerating/no-splice rule)
  - §6.6 — provider attempts (bounded jittered retries only for adapter-classified retryable failures; one journaled attempt per invoke; same request identity across internal retries)
- **Spec delivered** ([`spec.md`](spec.md)): frozen platform-internal attempt loop, fallback walk with `primary` / `fallback_after_retryable_error` / `fallback_after_timeout` selection reasons, exhausted-chain `provider_unavailable`, no-splice regenerating rule, per-attempt journal feed, and thirteen named integration tests (T-D3-01..T-D3-13).
- **Plan scoped** ([`plan.md`](plan.md)): one implementation module at `ai-platform/src/invocation/index.ts`; one integration test file; frozen contract in `contracts/invocation-attempt-loop.md`; consumes D2 `provider/` and `router/` unchanged; no D1 migrations, no `wrangler.toml` changes, no I/O.

## 2. What was implemented

- `ai-platform/src/invocation/index.ts` — platform-internal attempt loop: walks `routing_decision.chain[]` through a port resolver; bounds per-target invokes by `max_attempts`; retries only adapter-classified retryable failures with jittered backoff; records attempt-level `selection_reason`; feeds one attempt record per invoke to an in-memory sink; fails with `provider_unavailable` when the chain is exhausted; emits `regenerating` and discards partial text on fallback after streaming.
- Frozen contract: [`contracts/invocation-attempt-loop.md`](contracts/invocation-attempt-loop.md) — attempt loop rules, selection reasons, exhausted-chain outcome, regenerating/no-splice rule, and per-attempt journal feed shape.

See [`spec.md`](spec.md) for full requirements and [`plan.md`](plan.md) for file-level traceability.

## 3. Files to review

| Path | Role |
| --- | --- |
| `ai-platform/src/invocation/index.ts` | Attempt loop entry point, selection reasons, sink feed, regenerating |
| `ai-platform/test/invocation.test.ts` | T-D3-01..T-D3-13 (13 integration tests) |
| `specs/030-invocation-retry-fallback/contracts/invocation-attempt-loop.md` | Frozen attempt loop, selection reasons, regenerating, journal feed |

## 4. Prerequisites

From the repository root, first time only:

```bash
cd ai-platform
npm install
```

D3 tests are CPU-only — no Miniflare bindings or Cloudflare resources are required for this slice's integration suite.

## 5. Run the automated suite

From the repository root:

```bash
cd ai-platform
npx vitest run test/invocation.test.ts
```

Expected: **13 passing tests** for this slice only (`invocation.test.ts` — T-D3-01..T-D3-13).

To run a subset of this slice's tests:

```bash
npx vitest run test/invocation.test.ts
```

## 6. Inspect the changes

Read the frozen contract:

```bash
cat specs/030-invocation-retry-fallback/contracts/invocation-attempt-loop.md
```

Inspect selection reasons, regenerating, and exhausted-chain handling:

```bash
grep -n 'selection_reason\|regenerating\|provider_unavailable' ai-platform/src/invocation/index.ts
```

Run the focused test file:

```bash
cd ai-platform
npx vitest run test/invocation.test.ts
```
