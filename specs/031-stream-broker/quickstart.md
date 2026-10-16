# Quickstart: Stream broker, prose streaming, and cancellation (D4)

Slice D4 adds the **prose-only** stream broker: after D3's invocation loop produces normalized chunks, the gateway relays them over A6 SSE framing (`text_delta` in order), emits heartbeats during provider silence (`notifyActivity` resets silence), applies incremental cheap guards and a completion-time full guard set so `completed` carries the validated payload, and cancels by observing client disconnect — aborting the in-flight provider fetch, terminating as `cancelled`, and crediting live partial usage when present — with no per-request server-side state. Production wiring into the Worker pipeline (B4/C3 sinks, E4) is intentionally deferred. Structured modes live in D6's `src/stream/structured.ts`.

**Scope rule:** This quickstart documents **this slice only**. It lists only files D4 added or modified, only D4 test files, and only commands that run D4 tests.

## 1. Architecture context

- **Delivery plan row D4** ([`../../docs/architecture/ai-platform/03-ai-platform-delivery-plan.md`](../../docs/architecture/ai-platform/03-ai-platform-delivery-plan.md) §3.5): stream broker, prose streaming, and cancellation in band D.
- **Architecture sections implemented** ([`../../docs/architecture/ai-platform/01-ai-platform.md`](../../docs/architecture/ai-platform/01-ai-platform.md)):
  - §4.3.10 — stream broker: ordered chunk relay, heartbeat emission during provider silence, one-terminal-event guarantee, connection-scoped cancellation without per-request state
  - §6.4 — `prose` streaming path: incremental cheap guards (assembled length ceiling, stop-sequence, system-prompt-leak), full guard set on assembled text at completion, validated terminal payload (provisional chunks are not authoritative)
  - §5.5 — streaming protocol rules 3–6 as broker behaviour using A6 framing (heartbeats, one terminal event, cancel ≡ network drop, journal completeness on cancel)
  - §6.5 — cancellation semantics: disconnect aborts provider fetch, terminates as `cancelled`, credits partial usage
  - §9.7 — connection-scoped cancellation recommendation; no Session Durable Object or out-of-band cancel endpoint
- **Spec delivered** ([`spec.md`](spec.md)): frozen stream broker relay/heartbeat/one-terminal duties; `prose` incremental and completion-time guards with authoritative terminal payload; broker-owned connection-scoped cancellation; D3 adapter `createChunkSourceFromInvocationEvents`; nineteen original named tests (T-D4-01..T-D4-19) plus review-resolution T-D4-20..T-D4-27.
- **Plan scoped** ([`plan.md`](plan.md)): prose modules at `ai-platform/src/stream/index.ts` and `prose-guards.ts`; D6-owned `structured.ts` listed for path clarity only; frozen contract in `contracts/stream-broker.md`; injectable sinks; no D1 migrations.

## 2. What was implemented

- `ai-platform/src/stream/index.ts` — prose stream broker: ordered `text_delta` relay; silence heartbeats via injectable ticker + `notifyActivity`; incremental + completion guards; terminal-first settlement (journal on completed/failed/cancelled); live `getPartialUsage()` credit; sync cancel on disconnect with abortable iteration; source-error containment; `createChunkSourceFromInvocationEvents` D3 adapter. Not called from `worker.ts` yet (wiring deferred).
- `ai-platform/src/stream/prose-guards.ts` — assembled-length incremental guards; full set returns violation (non-throwing) including deferred `empty_output`.
- D6 (not this slice): `ai-platform/src/stream/structured.ts` — `createStructuredStreamBroker` for structured / structured_atomic modes.
- Frozen contract: [`contracts/stream-broker.md`](contracts/stream-broker.md).

See [`spec.md`](spec.md) for full requirements and [`plan.md`](plan.md) for file-level traceability.

## 3. Files to review

| Path | Role |
| --- | --- |
| `ai-platform/src/stream/index.ts` | Prose stream broker + D3 adapter |
| `ai-platform/src/stream/prose-guards.ts` | Incremental + full prose guards |
| `ai-platform/test/stream-broker.test.ts` | T-D4-01..T-D4-27 |
| `specs/031-stream-broker/contracts/stream-broker.md` | Frozen broker contract |

## 4. Prerequisites

From the repository root, first time only:

```bash
cd ai-platform
npm install
```

D4 tests are CPU-only — no Miniflare bindings or Cloudflare resources are required for this slice's integration suite.

## 5. Run the automated suite

From the repository root:

```bash
cd ai-platform
npx vitest run test/stream-broker.test.ts
```

Expected: all `stream-broker.test.ts` cases green (T-D4-01..T-D4-27).

## 6. Inspect the changes

Read the frozen contract:

```bash
cat specs/031-stream-broker/contracts/stream-broker.md
```

Inspect relay events, heartbeat emission, cancellation, and guard kinds:

```bash
grep -n 'text_delta\|heartbeat\|cancelled\|length_ceiling\|stop_sequence\|system_prompt_leak\|empty_output\|notifyActivity\|getPartialUsage' ai-platform/src/stream/
```

Run the focused test file:

```bash
cd ai-platform
npx vitest run test/stream-broker.test.ts
```
