# Quickstart: <slice title> (<slice id>)

<Two or three sentences: what this slice adds to the AI gateway. Do not catalogue prior slices —
context belongs in `spec.md` / `plan.md`, not here.>

**Scope rule:** A quickstart documents **this slice only**. List only files this slice added or
modified, only this slice's test files, and only commands that run this slice's tests. Do **not**
include prior-slice files in the review table, combined test counts from earlier slices, prior-slice
regression commands, or diffs "against the <prior slice> baseline". Full-suite regression (this slice
plus every prior slice) belongs in the Verification task, not in `quickstart.md`.

**Numbering rule:** Number sections sequentially (`## 1.`, `## 2.`, …). When omitting Prerequisites
or Manual validation, renumber the remaining sections — do not leave gaps (e.g. 1, 2, 4, 5).

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

<Omit this section when `npx vitest run` against this slice's test files is sufficient. Otherwise
list Node version, `wrangler` auth, Cloudflare resources, etc. Do not point at prior slices' test
files or quickstarts here.>

## 4. Run the automated suite

From the repository root:

```bash
cd ai-platform
npm install   # first time only
npx vitest run test/<file>.test.ts
```

Expected: **<N> passing tests** for this slice only (<list this slice's test files>). Do not cite
prior-slice test counts or run `npm test` for the full platform suite unless this is the bootstrap
slice (A1) with no predecessors.

To run a subset of this slice's tests:

```bash
npx vitest run test/<file>.test.ts
```

## 5. Inspect the changes

<Concrete commands or paths so a reviewer can see what this slice landed: open specific modules,
grep for a contract field, run a focused test file, read a frozen type, etc. Scope to this slice's
files only.>

## 6. Manual validation

<Omit this section when CI is the only verification path. Otherwise: deploy steps, `curl` examples,
dashboard checks, log inspection — only what this slice actually exposes beyond the test suite.>
