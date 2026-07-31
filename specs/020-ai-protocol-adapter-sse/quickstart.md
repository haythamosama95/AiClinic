# Quickstart: Protocol adapter and SSE framing (A6)

Slice **A6** owns the gateway's wire format: request parsing, the ingress body-size gate, the three
Submit-request headers, SSE event framing (`accepted`, heartbeat, terminal events), the
one-terminal-event invariant, and connection-scoped cancellation. The Worker `POST /v1/requests`
handler now delegates to the adapter instead of the A2 placeholder JSON response.

Full requirements: [`spec.md`](spec.md). File-level traceability: [`plan.md`](plan.md).

## 1. Architecture context

This slice implements delivery-plan row **A6** (*Protocol adapter and SSE framing*), which maps to
§4.3.1 and §5.5 of
[`../../docs/architecture/17-ai-platform.md`](../../docs/architecture/17-ai-platform.md) and row A6 of
[`../../docs/architecture/17b-ai-platform-delivery-plan.md`](../../docs/architecture/17b-ai-platform-delivery-plan.md).

- The **spec** freezes the Submit-request wire format (ingress body-size gate at stage 1, three
  correlation headers, SSE event vocabulary, one-terminal-event invariant, connection-scoped
  cancellation, and on-the-wire HTTP error emission via A2's taxonomy). It is the last Band A slice
  and the subject of review checkpoint **CP1**.
- The **plan** scopes one new source module (`adapter.ts`), a modified `worker.ts` fetch path, one
  integration test file (`adapter.test.ts`), and the frozen `contracts/sse-framing.md` artifact. No
  D1, R2, or Durable Object writes; no broker or provider.

## 2. What was implemented

- **Protocol adapter module** — `ai-platform/src/adapter.ts` parses `POST /v1/requests`, enforces the
  ingress body-size limit (`request_too_large` / HTTP 413 via A2), reads
  `x-idempotency-key`, `x-trace-id`, and `x-capability-version`, rejects adapter-local parse
  failures without a taxonomy-coded body (HTTP 422, not bare `400`), frames SSE events
  (`accepted`, heartbeat, `completed` / `failed` / `cancelled`), guarantees exactly one terminal
  event per stream, and handles connection-scoped cancellation.
- **Worker wiring** — `ai-platform/src/worker.ts` routes `POST /v1/requests` to
  `handleAdapterRequest`; the `/health` route and `GatewayObject` Durable Object class are unchanged.
- **Integration test suite** — `ai-platform/test/adapter.test.ts` drives the adapter through an
  in-process stub event source (no broker, no provider, no network), covering spec Test plan cases
  T1–T12.
- **Frozen framing contract** — `contracts/sse-framing.md` documents the header set, SSE vocabulary,
  one-terminal-event invariant, and cancellation rules for later slices' Consumes review.

## 3. Files to review

| Path | Role |
| --- | --- |
| `ai-platform/src/adapter.ts` | §4.3.1 protocol adapter — ingress gate, header parsing, SSE framing, terminal-event guard, cancellation |
| `ai-platform/src/worker.ts` | `POST /v1/requests` delegates to `handleAdapterRequest`; `/health` unchanged |
| `ai-platform/test/adapter.test.ts` | T-A6-T1..T12 integration suite (spec Test plan T1–T12) |

## 4. Run the automated suite

From the repository root:

```bash
cd ai-platform
npm install   # first time only
npx vitest run test/adapter.test.ts
```

Expected: **19 passing tests** for this slice only (twelve named spec scenarios T1–T12, plus
parameterized sub-cases for header rejection and duplicate-terminal guards).

To run a single describe block:

```bash
npx vitest run test/adapter.test.ts -t "T-A6-T6"
```

## 5. Inspect the changes

Read the frozen SSE framing contract:

```bash
cat specs/020-ai-protocol-adapter-sse/contracts/sse-framing.md
```

Inspect the ingress gate and parse-failure status (no bare `400`):

```bash
grep -n 'INGRESS_BODY_SIZE_LIMIT\|ingressTooLarge\|adapterParseFailure\|422' \
  ai-platform/src/adapter.ts
```

Inspect SSE event encoding and the one-terminal-event guard:

```bash
grep -n 'encodeSseEvent\|terminalEmitted\|accepted\|heartbeat\|cancelled' \
  ai-platform/src/adapter.ts
```

Inspect Worker routing to the adapter:

```bash
grep -n 'handleAdapterRequest\|/v1/requests\|/health' ai-platform/src/worker.ts
```

List the named test cases covered by this slice:

```bash
grep -n 'describe("T-A6' ai-platform/test/adapter.test.ts
```
