# Quickstart: Canonical inference representation (A3)

Slice **A3** freezes the four §5.3 canonical inference elements (request, stream chunk,
result, error) as typed code inside the Cloudflare Worker, plus a provider-shape guard
and an owned JSON codec — so every later inference-path slice speaks only this
provider-neutral representation upstream of the adapters.

Full requirements: [`spec.md`](spec.md). File-level traceability: [`plan.md`](plan.md).

## 1. Architecture context

This slice implements delivery-plan row **A3** (*Canonical inference representation*), which maps to
[§5.3 and §9.10](../../docs/architecture/ai-platform/01-ai-platform.md) of
[`../../docs/architecture/ai-platform/01-ai-platform.md`](../../docs/architecture/ai-platform/01-ai-platform.md) and row A3 of
[`../../docs/architecture/ai-platform/03-ai-platform-delivery-plan.md`](../../docs/architecture/ai-platform/03-ai-platform-delivery-plan.md).
The **spec** freezes the four provider-neutral canonical elements (request, stream chunk, result,
error), the closed chunk-kind set, and a guard that rejects provider-shaped field names upstream of
adapters. The **plan** scopes `contracts/canonical.ts`, seven contract tests (T-A3-01..07), and a
`contracts/canonical-shapes.md` artifact — types and tests only, no Worker behaviour changes.

## 2. What was implemented

- **`ai-platform/src/contracts/canonical.ts`** — field-name manifest (`CANONICAL_FIELD_MANIFEST`)
  for all four §5.3 elements; TypeScript types derived from the manifest
  (`CanonicalRequest`, `CanonicalStreamChunk`, `CanonicalResult`, `CanonicalError`);
  closed chunk-kind union (`text_delta`, `partial_structured`, `usage`, `provider_note`);
  terminal-flag invariant helper (`assertExactlyOneTerminal`); provider-shape guard
  (`assertNoProviderShapedFieldNames`); thin owned JSON codec
  (`encodeCanonical*` / `decodeCanonical*` pairs driven by the manifest).
- **`ai-platform/test/canonical.test.ts`** — seven named contract cases (T-A3-01..07):
  round-trip for each canonical element, provider-shaped field rejection, exhaustive
  chunk kinds, and exactly-one-terminal invariant.
- **`specs/017-ai-canonical-inference/contracts/canonical-shapes.md`** — frozen wire-shape
  reference for later slices' Consumes review.

## 3. Files to review

| Path | Role |
| --- | --- |
| `ai-platform/src/contracts/canonical.ts` | Manifest, types, chunk-kind union, guard, codec |
| `ai-platform/test/canonical.test.ts` | T-A3-01..07 contract suite |
| `specs/017-ai-canonical-inference/contracts/canonical-shapes.md` | Frozen §5.3 wire shapes |

## 4. Run the automated suite

From the repository root:

```bash
cd ai-platform
npm install   # first time only
npx vitest run test/canonical.test.ts
```

Expect **16 passing tests** in `canonical.test.ts` — the seven named A3 contract cases
(T-A3-01..07) plus supporting assertions for the manifest guard, chunk-kind set, and
terminal-flag invariant.

## 5. Inspect the changes

Read the frozen wire shapes:

```bash
cat specs/017-ai-canonical-inference/contracts/canonical-shapes.md
```

Inspect the manifest and closed chunk-kind set in code:

```bash
grep -n 'CANONICAL_FIELD_MANIFEST\|CANONICAL_CHUNK_KINDS' \
  ai-platform/src/contracts/canonical.ts
```

View the contract module:

```bash
cat ai-platform/src/contracts/canonical.ts
```
