# Quickstart: Protocol adapter and SSE framing (A6)

Slice **A6** owns the gateway's wire format: request parsing, the UTF-8 byte-accurate ingress
body-size gate, the three Submit-request headers, SSE event framing (`accepted`, heartbeat, terminal
events), the one-terminal-event invariant, and connection-scoped cancellation (mark `terminalEmitted`
only — never enqueue `cancelled` on a dead socket). The Worker `POST /v1/requests` handler delegates
to the adapter and fails fast (HTTP 503) until D4 injects an `eventSource`.

Full requirements: [`spec.md`](spec.md). File-level traceability: [`plan.md`](plan.md).

## 1. Architecture context

This slice implements delivery-plan row **A6** (*Protocol adapter and SSE framing*), which maps to
§4.3.1 and §5.5 of
[`../../docs/architecture/ai-platform/01-ai-platform.md`](../../docs/architecture/ai-platform/01-ai-platform.md) and row A6 of
[`../../docs/architecture/ai-platform/03-ai-platform-delivery-plan.md`](../../docs/architecture/ai-platform/03-ai-platform-delivery-plan.md).

- The **spec** freezes the Submit-request wire format (ingress body-size gate at stage 1, three
  correlation headers, SSE event vocabulary, one-terminal-event invariant, connection-scoped
  cancellation, and on-the-wire HTTP error emission via A2's taxonomy). It is the last Band A slice
  and the subject of review checkpoint **CP1**.
- The **plan** scopes one new source module (`adapter.ts`), a modified `worker.ts` fetch path, one
  integration test file (`adapter.test.ts`) plus `test/helpers/adapter-stub.ts`, and the frozen
  `contracts/sse-framing.md` artifact. No D1, R2, or Durable Object writes; no broker or provider.

## 2. What was implemented

- **Protocol adapter module** — `ai-platform/src/adapter.ts` parses `POST /v1/requests`, enforces the
  UTF-8 byte-accurate ingress body-size limit (`Content-Length` pre-check; stream-read abort; never
  buffer past the cap; `request_too_large` / HTTP 413 with empty `request_reference` and
  `trace_id`), reads `x-idempotency-key`, `x-trace-id` (any non-empty client string via A2
  `resolveTraceId`; ULID only when absent), and `x-capability-version`, rejects adapter-local parse
  failures with bare HTTP 422 (malformed body / empty-whitespace headers; no taxonomy body), frames
  SSE events (`accepted`, heartbeat, `completed` / `failed` / `cancelled`), guarantees exactly one
  terminal event per stream, and on cancel/abort marks `terminalEmitted` only (never enqueues
  `cancelled` on a dead socket). Requires injected `eventSource`; missing → HTTP 503. No stubs in
  `src/`.
- **Worker wiring** — `ai-platform/src/worker.ts` routes `POST /v1/requests` to
  `handleAdapterRequest`; live route fails fast until D4. The `/health` route and `GatewayObject`
  Durable Object class are unchanged.
- **Integration test suite** — `ai-platform/test/adapter.test.ts` +
  `ai-platform/test/helpers/adapter-stub.ts` drive the adapter through an in-process stub (no broker,
  no provider, no network), covering spec Test plan cases T1–T13 (**33 tests**): real
  `reader.cancel()`, already-aborted, signal abort, Content-Length, multi-byte UTF-8, malformed body,
  empty/whitespace headers, non-ULID trace, 503 without `eventSource`, connection-scoped terminal
  flag.
- **Frozen framing contract** — `contracts/sse-framing.md` documents the header set, SSE vocabulary,
  one-terminal-event invariant, cancellation rules, body gate, bare 422, and event-source requirement
  for later slices' Consumes review.

## 3. Files to review

| Path | Role |
| --- | --- |
| `ai-platform/src/adapter.ts` | §4.3.1 protocol adapter — ingress gate, header parsing, SSE framing, terminal-event guard, cancellation |
| `ai-platform/src/worker.ts` | `POST /v1/requests` delegates to `handleAdapterRequest`; fails fast until D4; `/health` unchanged |
| `ai-platform/test/adapter.test.ts` | T-A6-T1..T13 integration suite (33 tests) |
| `ai-platform/test/helpers/adapter-stub.ts` | Test-harness stub event source (not shipped in `src/`) |

## 4. Run the automated suite

From the repository root:

```bash
cd ai-platform
npm install   # first time only
npx vitest run test/adapter.test.ts
```

Expected: **33 passing tests** for this slice only (named spec scenarios T1–T13, including
parameterized sub-cases for header/body rejection, disconnect paths, and duplicate-terminal guards).

To run a single describe block:

```bash
npx vitest run test/adapter.test.ts -t "T-A6-T6"
```

## 5. Inspect the changes

Read the frozen SSE framing contract:

```bash
cat specs/020-ai-protocol-adapter-sse/contracts/sse-framing.md
```

Inspect the ingress gate, bare 422, and required eventSource:

```bash
grep -n 'INGRESS_BODY_SIZE_LIMIT\|readBodyWithinLimit\|ingressTooLarge\|adapterParseFailure\|eventSourceRequired\|422\|503' \
  ai-platform/src/adapter.ts
```

Inspect SSE event encoding, cancel-without-enqueue, and the one-terminal-event guard:

```bash
grep -n 'encodeSseEvent\|terminalEmitted\|markCancelledWithoutEnqueue\|accepted\|heartbeat\|cancelled' \
  ai-platform/src/adapter.ts
```

Inspect Worker routing to the adapter:

```bash
grep -n 'handleAdapterRequest\|/v1/requests\|/health' ai-platform/src/worker.ts
```

Confirm stubs are test-only:

```bash
grep -n 'StubEventSource\|createModeGated\|attemptDuplicateTerminal' \
  ai-platform/src/adapter.ts ai-platform/test/helpers/adapter-stub.ts
```

List the named test cases covered by this slice:

```bash
grep -n 'describe("T-A6' ai-platform/test/adapter.test.ts
```
