# Quickstart: Stream broker, prose streaming, and cancellation (D4)

Slice D4 adds the stream broker: after D3's invocation loop produces normalized chunks, the gateway relays them over A6 SSE framing for `prose` (`text_delta` in order), emits heartbeats during provider silence, applies incremental cheap guards and a completion-time full guard set so `completed` carries the validated payload, and cancels by observing client disconnect — aborting the in-flight provider fetch, terminating as `cancelled`, and crediting partial usage — with no per-request server-side state.

**Scope rule:** This quickstart documents **this slice only**. It lists only files D4 added or modified, only D4 test files, and only commands that run D4 tests.

## 1. Architecture context

- **Delivery plan row D4** ([`../../docs/architecture/17b-ai-platform-delivery-plan.md`](../../docs/architecture/17b-ai-platform-delivery-plan.md) §3.5): stream broker, prose streaming, and cancellation in band D.
- **Architecture sections implemented** ([`../../docs/architecture/17-ai-platform.md`](../../docs/architecture/17-ai-platform.md)):
  - §4.3.10 — stream broker: ordered chunk relay, heartbeat emission during provider silence, one-terminal-event guarantee, connection-scoped cancellation without per-request state
  - §6.4 — `prose` streaming path: incremental cheap guards (length ceiling, stop-sequence, system-prompt-leak), full guard set on assembled text at completion, validated terminal payload (provisional chunks are not authoritative)
  - §5.5 — streaming protocol rules 3–6 as broker behaviour using A6 framing (heartbeats, one terminal event, cancel ≡ network drop, journal completeness on cancel)
  - §6.5 — cancellation semantics: disconnect aborts provider fetch, terminates as `cancelled`, credits partial usage
  - §9.7 — connection-scoped cancellation recommendation; no Session Durable Object or out-of-band cancel endpoint
- **Spec delivered** ([`spec.md`](spec.md)): frozen stream broker relay/heartbeat/one-terminal duties; `prose` incremental and completion-time guards with authoritative terminal payload; broker-owned connection-scoped cancellation (abort signal → `cancelled` → partial-usage credit → journal-terminal outcome); explicit non-support of out-of-band cancel, Session DO, and stream resume; and nineteen named integration (spy) tests (T-D4-01..T-D4-19).
- **Plan scoped** ([`plan.md`](plan.md)): two implementation modules at `ai-platform/src/stream/index.ts` and `ai-platform/src/stream/prose-guards.ts`; one integration test file; frozen contract in `contracts/stream-broker.md`; consumes A6 `adapter.ts` and D3 `invocation/` unchanged; injectable heartbeat ticker, AbortSignal, and credit/journal sinks in tests; no D1 migrations, no `wrangler.toml` changes, no I/O.

## 2. What was implemented

- `ai-platform/src/stream/index.ts` — stream broker: relays normalized chunks in order as A6 `text_delta` events; emits `heartbeat` during provider silence via an injectable ticker; applies `prose-guards` incrementally and at completion; on success emits exactly one `completed` with the validated payload; on guard abort emits exactly one `failed`; on client disconnect aborts the in-flight provider fetch through a broker-owned `AbortSignal`, emits exactly one `cancelled`, credits partial usage via the credit sink, and records a complete terminal outcome via the journal-terminal sink; creates no per-request server-side state, Session DO, separate cancel endpoint, or D1 row per chunk; relays D3 `regenerating` when present without owning retry/fallback.
- `ai-platform/src/stream/prose-guards.ts` — `prose` incremental cheap guards (length ceiling, stop-sequence, system-prompt-leak) and completion-time full guard set on assembled text; violations abort with `validation_failed` taxonomy.
- Frozen contract: [`contracts/stream-broker.md`](contracts/stream-broker.md) — broker relay/heartbeat/one-terminal duties, prose guard path, connection-scoped cancel, and prohibitions (no OOB cancel, Session DO, or D1-per-chunk).

See [`spec.md`](spec.md) for full requirements and [`plan.md`](plan.md) for file-level traceability.

## 3. Files to review

| Path | Role |
| --- | --- |
| `ai-platform/src/stream/index.ts` | Stream broker: chunk relay, heartbeat ticker, cancel wiring, terminal emit |
| `ai-platform/src/stream/prose-guards.ts` | Incremental cheap guards + full guard set on assembled text |
| `ai-platform/test/stream-broker.test.ts` | T-D4-01..T-D4-19 (19 named integration tests; 20 `it` cases — T-D4-15 has two) |
| `specs/031-stream-broker/contracts/stream-broker.md` | Frozen broker relay, prose guards, heartbeat, cancel path, prohibitions |

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

Expected: **20 passing tests** for this slice only (`stream-broker.test.ts` — T-D4-01..T-D4-19).

To run a subset of this slice's tests:

```bash
npx vitest run test/stream-broker.test.ts
```

## 6. Inspect the changes

Read the frozen contract:

```bash
cat specs/031-stream-broker/contracts/stream-broker.md
```

Inspect relay events, heartbeat emission, cancellation, and guard kinds:

```bash
grep -n 'text_delta\|heartbeat\|cancelled\|length_ceiling\|stop_sequence\|system_prompt_leak' ai-platform/src/stream/
```

Run the focused test file:

```bash
cd ai-platform
npx vitest run test/stream-broker.test.ts
```
