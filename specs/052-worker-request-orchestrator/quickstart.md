# Quickstart: Worker request orchestrator (I1)

This slice wires production `POST /v1/requests` through the adapter pre-accept gate and a
post-accept event source that composes the existing pipeline, stream broker, and settlement path.

**Scope rule:** This document covers slice I1 only.

## 1. Architecture context

- Delivery plan row **I1** in [`../../docs/architecture/ai-platform/03-ai-platform-delivery-plan.md`](../../docs/architecture/ai-platform/03-ai-platform-delivery-plan.md) — live Worker orchestration on `POST /v1/requests`.
- Architecture refs: [`../../docs/architecture/ai-platform/01-ai-platform.md`](../../docs/architecture/ai-platform/01-ai-platform.md) §6.1 (stages 1–16), §4.3.1, §4.3.10, §5.5, §6.4.
- **Spec:** FR-001–FR-019 — production `preAccept` + `eventSource`, guard-reject taxonomy HTTP, happy-path SSE with exactly one terminal, I/O budgets, idempotency replay.
- **Plan:** A6 §8 extension in `adapter.ts`; production injectors in `worker.ts`; 23 Workers-integration spy tests via `SELF.fetch`.

## 2. What was implemented

- **`adapter.ts` (A6 §8):** Optional `preAccept` gate defers SSE + `accepted` until `{ ok: true }`; failures return taxonomy HTTP without opening a stream.
- **`worker.ts`:** Production `preAccept` (`runGuard` through stage 9) and `eventSource` (routing → invocation → D4 broker → settle) on live `POST /v1/requests`; `ExecutionContext.waitUntil` drains background settlement.
- **Tests:** `test/worker-request-orchestrator.test.ts` — 23 named cases (T1–T23) against production `worker.ts`.

See `spec.md` for requirements and `plan.md` for file-level traceability.

## 3. Files to review

| Path | Role |
| --- | --- |
| `ai-platform/src/adapter.ts` | A6 §8 `preAccept` gate and deferred `accepted` |
| `ai-platform/src/worker.ts` | Production `preAccept` + `eventSource` injectors |
| `ai-platform/test/worker-request-orchestrator.test.ts` | I1 Workers-integration suite (T1–T23) |
| `ai-platform/vitest.workers.config.ts` | Workers-pool include for I1 file |
| `ai-platform/vitest.config.ts` | Node-pool exclude pairing |
| `ai-platform/test/worker-entry.test.ts` | Worker entry seam updated for production wiring |

## 4. Prerequisites

```bash
cd ai-platform && npm install   # first time only
```

Tests use `@cloudflare/vitest-pool-workers` with Miniflare D1/R2/DO bindings (`SELF.fetch` against production `worker.ts`).

## 5. Run the automated suite

```bash
cd ai-platform
npx vitest run --config vitest.workers.config.ts test/worker-request-orchestrator.test.ts
```

Expected: **23 passing tests** for this slice only.

## 6. Inspect the changes

```bash
cd ai-platform
rg "preAccept|eventSource|createProductionPreAccept" src/worker.ts src/adapter.ts
npx vitest run --config vitest.workers.config.ts test/worker-request-orchestrator.test.ts
```

Open `src/worker.ts` for `handleLivePostRequest`, `createProductionPreAccept`, and `createProductionEventSource`. Open `src/adapter.ts` for the §8 gate in `handleAdapterRequest`.
