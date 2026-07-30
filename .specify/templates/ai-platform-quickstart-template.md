# Quickstart: <slice title> (<slice id>)

<Two or three sentences: what this slice adds to the AI gateway and where it sits in the delivery
sequence.>

## 1. What was implemented

- <Deliverable 1 — module, contract, endpoint, migration, etc.>
- <Deliverable 2>
- <Link to `spec.md` for full requirements and `plan.md` for file-level traceability.>

## 2. Files to review

| Path | Role |
| --- | --- |
| `ai-platform/src/<file>.ts` | <What this file does> |
| `ai-platform/test/<file>.test.ts` | <Which named tests live here> |

## 3. Prerequisites

<Omit this section when `npm test` from `ai-platform/` is sufficient. Otherwise list Node version,
`wrangler` auth, Cloudflare resources, prior-slice setup, etc. Point at an earlier slice's
`quickstart.md` when this slice builds on it.>

## 4. Run the automated suite

From the repository root:

```bash
cd ai-platform
npm install   # first time only
npm test
```

Expected: <N> passing tests for this slice, plus <M> from prior slices (<list test files or slice
ids>). A regression in a prior slice's suite is a hard fail.

To run only this slice's tests:

```bash
npx vitest run test/<file>.test.ts
```

## 5. Inspect the changes

<Concrete commands or paths so a reviewer can see what landed without reading the whole diff: open
specific modules, grep for a contract field, run a focused test file, read a frozen type, etc.>

## 6. Manual validation

<Omit this section when CI is the only verification path. Otherwise: deploy steps, `curl` examples,
dashboard checks, log inspection — only what this slice actually exposes beyond the test suite.>
