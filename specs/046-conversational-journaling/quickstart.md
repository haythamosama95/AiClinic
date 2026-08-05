# Quickstart: Conversational journaling and client chat surface (H3)

H3 populates the A5-reserved `conversation_id` and `turn_ordinal` columns on each conversational
leg's `ai_request` row, exposes a one-query conversation read helper, and lands the Flutter
Conversation store plus negotiation loop that resupplies the transcript, resolves
`context_requested` through the existing Context Resolver, and keeps cancellation scoped to one leg.

**Scope rule:** This quickstart documents **slice H3 only** — files, tests, and commands for this
slice; full-suite regression is the Verification task (T023), not repeated here.

## 1. Architecture context

- **Delivery plan row:** [H3 in §3.8](../../docs/architecture/17b-ai-platform-delivery-plan.md) —
  Conversational journaling and client chat surface (band H).
- **Architecture sections implemented:** §7.3 (journal grouping columns + ordered query), §6.7.1
  (independent legs, no conversation entity), §6.7.2 (`context_requested` credit and client
  append), §8.10 (client transcript / Resolver / RLS boundaries), §4.1 (Conversation store and
  SDK invoke surface), §6.7.4 (per-leg idempotency and cancel).
- **Spec delivered:** FR-001–FR-018 — journal column population, ordered conversation query,
  independent admit/credit per leg, client transcript hold/resupply/discard, Resolver-driven
  `context_requested` loop, new idempotency key per leg, connection-scoped cancel.
- **Plan scoped:** `listConversationLegs` in `journal/index.ts`; `runGuard` wire-through;
  workers-pool integration tests;
  optional `CapabilityInvokeInput` fields and `context_requested` client terminal; `conversation_store.dart`
  and `conversation_loop.dart`; frozen `contracts/conversational-journaling.md`.

## 2. What was implemented

- Journal writer populates client-supplied `conversation_id` / `turn_ordinal` on conversational legs
  (rejects missing grouping with `context_invalid`) and adds
  `listConversationLegs(conversationId, installationId)`
  (`WHERE conversation_id = ? AND installation_id = ? ORDER BY turn_ordinal`).
- Pipeline `runGuard` stage 6/9 wires `conversation_id` / `turn_ordinal` / `transcript` from the
  submit body into `validateContext` and `createRequestRow` (not test-only composition).
- A5 follow-up index `idx_ai_request_conversation` on `(conversation_id, turn_ordinal)`.
- Workers-pool integration tests prove independent admit/credit, `AwaitingContext` credit, no
  conversation table, I/O budget upper bounds, `runGuard` column write, and `single_shot` null columns.
- Flutter Conversation store (local transcript hold / resupply / discard; no interpretation).
  Leg 1 submits `intent = typed message` with an empty transcript; transcript turn ordinals are
  strictly less than the leg's `turn_ordinal` (§6.7.1). User turns are committed only on success
  (no dangling unanswered user turn on cancel/fail).
- Flutter negotiation loop: on `context_requested`, resolve full `{key, arguments}` via
  `resolveRequests`, append request + resolved payload, and **automatically submit the
  continuation leg** (new idempotency key, resupplied transcript, no fabricated user turn) until
  `completed` or a failure/cancel terminal. `ContextResolveFailure` fails the leg visibly (no empty
  `context_resolved`); RLS-empty is success with an empty payload and may continue.
- E2 SDK optional invoke fields (`conversationId`, `turnOrdinal`, `transcript`) and
  `ContextRequestedEvent` / `ContextRequestedTerminal`.
- Frozen contract: [`contracts/conversational-journaling.md`](./contracts/conversational-journaling.md).

See [`spec.md`](./spec.md) for requirements and [`plan.md`](./plan.md) for file-level traceability.

## 3. Files to review

| Path | Role |
| --- | --- |
| `ai-platform/src/journal/index.ts` | `listConversationLegs`; conversational column write via `createRequestRow` |
| `ai-platform/src/pipeline/index.ts` | `runGuard` stage 6/9 conversational wire fields |
| `ai-platform/migrations/20260805180000_h3_conversation_index.sql` | Conversation index |
| `ai-platform/test/conversational-journaling.test.ts` | Pipeline integration (spy) named tests |
| `ai-platform/vitest.workers.config.ts` | Workers-pool include for journaling file |
| `ai-platform/vitest.config.ts` | Unit-pool exclude for workers-pool file |
| `frontend/lib/core/ai/ports.dart` | Optional `conversationId` / `turnOrdinal` / `transcript` on invoke input |
| `frontend/lib/core/ai/sse_events.dart` | `ContextRequestedEvent` / `ContextRequestedTerminal` |
| `frontend/lib/core/ai/ai_client_sdk.dart` | Surfaces `context_requested` terminal |
| `frontend/lib/core/ai/conversation_store.dart` | Local transcript hold / resupply / discard |
| `frontend/lib/core/ai/conversation_loop.dart` | Chat negotiation loop |
| `frontend/test/unit/core/ai/fakes.dart` | Conversational submit / SSE / Resolver fakes |
| `frontend/test/unit/core/ai/conversation_store_test.dart` | Store named tests + §3.10 coverage |
| `frontend/test/unit/core/ai/conversation_loop_test.dart` | Loop / cancel / append / RLS tests |
| `specs/046-conversational-journaling/contracts/conversational-journaling.md` | Frozen journaling contract |

## 4. Run the automated suite

From the repository root:

```bash
cd ai-platform
npx vitest run test/conversational-journaling.test.ts --config vitest.workers.config.ts
```

```bash
cd frontend
flutter test test/unit/core/ai/conversation_store_test.dart test/unit/core/ai/conversation_loop_test.dart
```

Expected: Vitest journaling cases green (including `runGuard` wiring and index assertion) and Flutter store/loop cases green.

## 5. Inspect the changes

1. Read the frozen contract: `specs/046-conversational-journaling/contracts/conversational-journaling.md`.
2. Open `ai-platform/src/journal/index.ts` — locate `listConversationLegs` and conversational
   `createRequestRow` column binding (reject-missing + tenant scope).
3. Open `ai-platform/src/pipeline/index.ts` — `runGuard` extracts wire fields for stages 6 and 9.
4. Open `frontend/lib/core/ai/conversation_store.dart` and `conversation_loop.dart` — transcript
   lifecycle and Resolver wiring.
5. Open `frontend/lib/core/ai/ports.dart` / `sse_events.dart` — optional invoke fields and fourth
   terminal kind.
6. Re-run the focused test commands in §4 to confirm green.