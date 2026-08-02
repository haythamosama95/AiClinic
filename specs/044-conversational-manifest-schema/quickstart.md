# Quickstart: Conversational manifest fields and context-request schema (H1)

H1 freezes conversational manifest extras, the shared `{key, arguments}` context-request schema,
`context_requested` as a fourth SSE terminal kind (not a taxonomy code), and `AwaitingContext` as a
terminal immutable request state — so H2/H3 bind to contracts rather than inventing them.

**Scope rule:** Document **this slice only**. List only files this slice added or modified, only
this slice's test files, and only commands that run this slice's tests.

## 1. Architecture context

- **Delivery plan** — Band H row H1 in
  [`../../docs/architecture/17b-ai-platform-delivery-plan.md`](../../docs/architecture/17b-ai-platform-delivery-plan.md)
  (Needs: A2, A4, A6).
- **Architecture** — Implements §5.1, §5.7, §6.7.4, §6.7.2, §5.5, §5.4, §6.3, A14 of
  [`../../docs/architecture/17-ai-platform.md`](../../docs/architecture/17-ai-platform.md)
  (see `spec.md` Slice Contract → Implements).
- **Spec** — [`spec.md`](./spec.md) freezes conversational Interaction fields + permitted key set,
  the shared context-request schema, fourth terminal kind, and terminal `AwaitingContext`.
- **Plan** — [`plan.md`](./plan.md) scoped extensions to `src/manifest/`, `src/context/context-request.ts`,
  `src/adapter.ts`, and `src/journal/`, plus contract + build + integration tests.

## 2. What was implemented

- **Conversational manifest load rules** — `ai-platform/src/manifest/index.ts` requires max history
  turns, max context rounds per turn, transcript size limit, and permitted key set when
  `interactionMode` is `conversational`; rejects conversational-only fields on `single_shot`;
  validates permitted keys via A5 `validateKey`.
- **Platform-owned context-request schema** — `ai-platform/src/context/context-request.ts` exports
  `validateContextRequest()` and `CONTEXT_REQUEST_SCHEMA_ID` for the shared list-of-`{key, arguments}`
  shape.
- **Fourth terminal kind** — `ai-platform/src/adapter.ts` adds `context_requested` to
  `TERMINAL_EVENT_KINDS`, gates emission on `interactionMode`, and exports mode-gated stub helpers
  for integration tests.
- **`AwaitingContext` terminal helpers** — `ai-platform/src/journal/index.ts` exports
  `isJournalTerminalState`, `isJournalTransitionAllowed`, and `canReachAwaitingContext`.
- **Contract + build + integration tests** — four test files covering manifest load/omit/reject,
  shared schema accept/reject, taxonomy absence, terminal immutability, and one-terminal invariant.
- **Frozen contracts** — `contracts/conversational-manifest.md`, `contracts/context-request-schema.md`,
  `contracts/context-requested-terminal.md`.

Link: [`spec.md`](./spec.md), [`plan.md`](./plan.md).

## 3. Files to review

| Path | Role |
| --- | --- |
| `ai-platform/src/manifest/index.ts` | Conversational Interaction + permitted key set load rules |
| `ai-platform/src/context/context-request.ts` | Shared `{key, arguments}` schema |
| `ai-platform/src/adapter.ts` | Fourth terminal kind + mode gate |
| `ai-platform/src/journal/index.ts` | `AwaitingContext` terminal / immutable helpers |
| `ai-platform/test/conversational-manifest.test.ts` | Manifest contract/build tests |
| `ai-platform/test/context-request.test.ts` | Shared schema + coverage tests |
| `ai-platform/test/awaiting-context.test.ts` | `AwaitingContext` terminal/immutable |
| `ai-platform/test/context-requested-terminal.test.ts` | Taxonomy absence + adapter integration |
| `specs/044-conversational-manifest-schema/contracts/*.md` | Frozen wire shapes for H2/H3 Consumes |

## 4. Run the automated suite

From the repository root:

```bash
cd ai-platform
npx vitest run \
  test/conversational-manifest.test.ts \
  test/context-request.test.ts \
  test/awaiting-context.test.ts \
  test/context-requested-terminal.test.ts
```

Expected: **28 passing tests** across the four H1 test files.

## 5. Inspect the changes

```bash
rg 'context_requested|permittedKeySet|AwaitingContext|validateContextRequest' \
  ai-platform/src/manifest ai-platform/src/context/context-request.ts \
  ai-platform/src/adapter.ts ai-platform/src/journal
cat specs/044-conversational-manifest-schema/contracts/conversational-manifest.md
cat specs/044-conversational-manifest-schema/contracts/context-request-schema.md
cat specs/044-conversational-manifest-schema/contracts/context-requested-terminal.md
```
