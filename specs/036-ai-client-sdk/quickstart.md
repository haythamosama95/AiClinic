# Quickstart: AI Client SDK (E2)

E2 adds the Flutter **AI Client SDK** — a transport-only client under `frontend/lib/core/ai/` that
acquires and caches an AAT, submits capability requests with a stable idempotency key, consumes the
A6 SSE stream to a single terminal event (or typed drop), surfaces terminal state, cancels by
closing the stream with a local cancelled terminal, retains the last request reference, retries
transport failures within a bounded ceiling, and maps unknown taxonomy codes to `internal_error`.

## 1. Architecture context

- **Delivery plan row E2** ([§3.6](../../docs/architecture/ai-platform/03-ai-platform-delivery-plan.md)) implements
  **§4.1 AI Client SDK**, **§5.5 SSE consumption rules**, and **§5.4 taxonomy branching** from
  [`01-ai-platform.md`](../../docs/architecture/ai-platform/01-ai-platform.md).
- **Spec** (`spec.md`) froze the transport-only client seam: AAT cache/remint ceiling, stable
  idempotency key, consume-to-terminal SSE, cancel-by-close, last request-reference retention,
  no-auto-retry-after-terminal, and unknown→`internal_error`.
- **Plan** (`plan.md`) scoped four Dart library files under `frontend/lib/core/ai/` plus a Flutter
  unit/integration suite (T1–T28) driven by injectable in-memory fakes — no live Worker.

## 2. What was implemented

- **AI Client SDK** (`ai_client_sdk.dart`) — single-flight AAT cache/remint; stable
  idempotency key (per-invoke override); bounded transport retry → `TransportRetryExhausted`;
  rebroadcast SSE consume-to-terminal; local `CancelledTerminal` on cancel; `StreamDroppedTerminal`
  on silence/drop; last request reference; no auto-retry after terminal taxonomy outcomes except
  the single remint path.
- **Injectable ports** (`ports.dart`) — AAT mint, HTTPS submit, SSE connection close
  (single-subscription OK).
- **Taxonomy mirror** (`taxonomy.dart`) — §5.4 closed set; `classifyTaxonomyCode` →
  `internal_error`.
- **SSE event types** (`sse_events.dart`) — A6 kinds + terminals as received;
  `FailedEvent.fromWire`; no model-output reshape.
- **Test suite** — `ai_client_sdk_test.dart` (T1–T28) and `fakes.dart` in-memory spies.

See [`spec.md`](./spec.md) for requirements and [`plan.md`](./plan.md) for file-level traceability.

## 3. Files to review

| Path | Role |
| --- | --- |
| `frontend/lib/core/ai/ai_client_sdk.dart` | Transport SDK: cache, remint, submit, stream consume, cancel |
| `frontend/lib/core/ai/ports.dart` | Injectable mint / submit / SSE ports |
| `frontend/lib/core/ai/taxonomy.dart` | §5.4 code mirror and unknown→`internal_error` |
| `frontend/lib/core/ai/sse_events.dart` | A6 event kinds and terminal state types |
| `frontend/test/unit/core/ai/ai_client_sdk_test.dart` | Named tests T1–T28 |
| `frontend/test/unit/core/ai/fakes.dart` | In-memory mint/submit/SSE fakes and spies |

## 4. Prerequisites

- Flutter / Dart SDK as declared in `frontend/pubspec.yaml` (`sdk: ^3.11.5`).
- No live AI gateway Worker required — tests use injectable fakes.

## 5. Run the automated suite

From the repository root:

```bash
cd frontend
flutter test test/unit/core/ai/ai_client_sdk_test.dart
```

Expected: **28 passing tests** (T1–T28, including the parameterized T7–T23 no-retry family).

T28 additionally runs the E1 architecture guard as part of the suite:

```bash
cd frontend
dart run tool/architecture_guard/architecture_guard.dart
```

Expected: `architecture_guard: clean — no forbidden content detected.`

## 6. Inspect the changes

```bash
ls frontend/lib/core/ai/
ls frontend/test/unit/core/ai/
```

Open `ai_client_sdk.dart` for the remint/transport-retry loop and stream-to-terminal consumption.
Open `taxonomy.dart` for the closed code set. Skim `ai_client_sdk_test.dart` for the named T1–T28
cases. Confirm `frontend/lib/core/ai/` is covered by the E1 guard clean-tree scan roots (`lib/`).
