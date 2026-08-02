# Quickstart: Conversational manifest fields and context-request schema (H1)

> **Fill status:** Skeleton produced by `/ai-platform-plan`. Complete sections 2–5 during the
> Documentation task after implementation and verification
> (`.specify/templates/ai-platform-quickstart-template.md`). Slice-only scope — no prior-slice
> files, combined counts, or full-suite `npm test`.

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
- **Plan** — [`plan.md`](./plan.md) scopes extensions to `src/manifest/`, `src/context/context-request.ts`,
  `src/adapter.ts`, and `src/journal/`, plus contract + build + integration tests.

## 2. What was implemented

<!-- Fill after verification: deliverables matching plan Files / Sequencing. -->

- _(pending implementation)_ Conversational load rules on the A4 manifest loader.
- _(pending implementation)_ Platform-owned context-request schema module.
- _(pending implementation)_ `context_requested` terminal kind gated on `interactionMode`.
- _(pending implementation)_ `AwaitingContext` terminal immutability helpers.
- Frozen contracts under `contracts/`.
- Link: [`spec.md`](./spec.md), [`plan.md`](./plan.md).

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
npm install   # first time only
npx vitest run \
  test/conversational-manifest.test.ts \
  test/context-request.test.ts \
  test/awaiting-context.test.ts \
  test/context-requested-terminal.test.ts
```

Expected: all H1 named tests passing for this slice only. Do not cite prior-slice counts or run
`npm test` for the full platform suite here.

## 5. Inspect the changes

<!-- Fill after verification: concrete greps / focused commands for this slice's files. -->

- Open the modules in §3.
- Grep for `context_requested`, `permittedKeySet`, `AwaitingContext`, `validateContextRequest`.
- Read the three files under `contracts/`.

## 6. Manual validation

Omitted — CI / `vitest` is the only verification path for this contract slice.
