# Quickstart: Prompt registry and composer (D1)

D1 makes pipeline stage 10 (prompt composition) real: it deploys prompt artifacts as immutable,
hash-pinned assets bundled with the Worker and assembles the canonical provider-bound request from
those artifacts plus the resolved capability manifest and the filtered context payload. The registry
resolves manifest pins at build time with no runtime I/O; the composer derives the output-format
instruction from the output schema and renders context as delimited typed data (R-10).

**Scope rule:** A quickstart documents **this slice only**. List only files this slice added or
modified, only this slice's test files, and only commands that run this slice's tests. Do **not**
include prior-slice files in the review table, combined test counts from earlier slices, prior-slice
regression commands, or diffs "against the <prior slice> baseline". Full-suite regression (this slice
plus every prior slice) belongs in the Verification task, not in `quickstart.md`.

**Numbering rule:** Number sections sequentially (`## 1.`, `## 2.`, …). Section **1** is always
**Architecture context**. When omitting Prerequisites or Manual validation, renumber the remaining
sections — do not leave gaps (e.g. 1, 2, 4, 5).

## 1. Architecture context

D1 implements the **D1** row in
[`../../docs/architecture/17b-ai-platform-delivery-plan.md`](../../docs/architecture/17b-ai-platform-delivery-plan.md)
§3.5 (Band D — inference path), covering architecture sections **§4.3.6** (prompt composer and prompt
registry), **§5.7** (prompt artifact immutability and version pinning), **§9.5** (no prompt text in
D1), and **§5.3** (canonical inference representation — no provider-shaped fields upstream of
adapters).

- **What the spec delivered** ([`spec.md`](./spec.md)): a build-time prompt registry and a stage-10
  composer that assembles the canonical request; 12 named tests (`T-D1-01` … `T-D1-12`); no prompt
  text in any D1 table; context rendered as delimited typed data with R-10 neutralization so embedded
  instructions cannot act as commands.
- **What the plan scoped** ([`plan.md`](./plan.md)): `ai-platform/src/prompt/registry.ts` and
  `ai-platform/src/prompt/composer.ts`; fixture prompt artifacts under
  `ai-platform/prompts/clinic.visit_summary/`; `wrangler.toml` `[rules]` for `"Text"` module imports
  of `prompts/**`; frozen contract at
  `specs/028-prompt-registry-composer/contracts/composer-output.md`.

## 2. What was implemented

- **`registry.ts`** (`src/prompt/registry.ts`) — `resolveArtifact`, `resolvePromptVersion`,
  `verifyBuildPins`, and `verifyAllRegistryPins`: build-time `import.meta.glob` index over
  `prompts/**/*.md` (`?raw`) and `prompts/*/registry.json`; test overlay seam for pin tests; no
  runtime I/O.
- **`composer.ts`** (`src/prompt/composer.ts`) — `composeRequest` at stage 10: assembles the
  canonical request; derives the output-format instruction from the output schema; renders context as
  delimited typed data (`<key name="…" shape="…">` blocks with `</` neutralization); forwards output
  constraints from the manifest; surfaces the resolved prompt version for the journal row; emits
  `internal_error` on composition failure.
- **Fixture prompt artifact tree** under `prompts/clinic.visit_summary/` — `system.md`,
  `rules-visit-summary.md`, `template-visit-summary.md`, and `registry.json` (ref → content-hash
  index).
- **`wrangler.toml` `[rules]`** — `"Text"` module imports for `prompts/**` so artifacts bundle with
  the Worker.

See [`spec.md`](./spec.md) for full requirements and [`plan.md`](./plan.md) for file-level
traceability.

## 3. Files to review

| Path | Role |
| --- | --- |
| `ai-platform/src/prompt/registry.ts` | Build-time glob index + pin verification |
| `ai-platform/src/prompt/composer.ts` | Stage 10 `composeRequest` |
| `ai-platform/test/prompt-registry.test.ts` | T-D1-01 through T-D1-05 |
| `ai-platform/test/prompt-registry-gate.test.ts` | CI pin / published-manifest / disk-bytes gate |
| `ai-platform/test/prompt-journal-seam.test.ts` | `resolvePromptVersion` ≡ C3 journal bind |
| `ai-platform/test/prompt-composer.test.ts` | T-D1-06 through T-D1-12 |
| `ai-platform/prompts/clinic.visit_summary/` | Four artifact files + `registry.json` |
| `ai-platform/wrangler.toml` | `[rules]` Text imports for `prompts/**` |
| `specs/028-prompt-registry-composer/contracts/composer-output.md` | Frozen composer output contract |

## 4. Prerequisites

From the repository root:

```bash
cd ai-platform
npm install   # first time only
```

This slice's tests are CPU-only. No Miniflare D1 or R2 bindings are required.

## 5. Run the automated suite

From `ai-platform/`:

```bash
npx vitest run test/prompt-registry.test.ts test/prompt-composer.test.ts
```

Expected: **13 passing tests** for this slice only (6 in `prompt-registry.test.ts`, 7 in
`prompt-composer.test.ts`). Do **not** run `npm test` for the full platform suite.

To run a single test file:

```bash
npx vitest run test/prompt-composer.test.ts
```

## 6. Inspect the changes

Grep the delimited-typed-data tag pattern in the composer:

```bash
cd ai-platform
grep -n '<key name=' src/prompt/composer.ts
```

Read the frozen composer output contract:

```bash
cat ../specs/028-prompt-registry-composer/contracts/composer-output.md
```

Run a focused test file:

```bash
npx vitest run test/prompt-registry.test.ts
```

Open the build-time pin index for pinned hashes:

```bash
cat prompts/clinic.visit_summary/registry.json
```

List the named test suites:

```bash
grep -n '^describe(' test/prompt-registry.test.ts test/prompt-composer.test.ts
```
