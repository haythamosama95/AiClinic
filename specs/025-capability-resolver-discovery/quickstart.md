# Quickstart: Capability registry, resolver stage, and discovery endpoint (C1)

C1 adds the pipeline's stage-5 capability resolver and the §5.5 discovery surface to the AI
gateway: a registry-backed lookup that turns `capability id + requested version` into exactly one
immutable manifest, and a discovery read that returns the active, granted manifests for an
installation and plan.

**Scope rule:** A quickstart documents **this slice only**. List only files this slice added or
modified, only this slice's test files, and only commands that run this slice's tests. Do **not**
include prior-slice files in the review table, combined test counts from earlier slices, prior-slice
regression commands, or diffs "against the <prior slice> baseline". Full-suite regression (this slice
plus every prior slice) belongs in the Verification task, not in `quickstart.md`.

**Numbering rule:** Number sections sequentially (`## 1.`, `## 2.`, …). Section **1** is always
**Architecture context**. When omitting Prerequisites or Manual validation, renumber the remaining
sections — do not leave gaps (e.g. 1, 2, 4, 5).

## 1. Architecture context

C1 implements the **C1** row in
[`../../docs/architecture/ai-platform/03-ai-platform-delivery-plan.md`](../../docs/architecture/ai-platform/03-ai-platform-delivery-plan.md)
§3.4, covering architecture sections **§4.3.4** (capability resolver), **§5.1** (manifest
immutability), **§6.1 stage 5** (pipeline stage-5 resolve), **§5.5** (discovery surface), and
**§5.2** (client context-key discovery).

- **What the spec delivered** ([`spec.md`](./spec.md)): a registry lookup that resolves
  `capability id + requested version` to one immutable manifest honouring the client's pin;
  three distinct resolver error codes (`capability_unknown`, `capability_retired`,
  `capability_disabled`); a discovery response returning active, granted manifests for an
  installation and plan, cacheable and revalidated by etag; and immutability of the resolved
  manifest handed to later stages.
- **What the plan scoped** ([`plan.md`](./plan.md)): one module `ai-platform/src/capability/`
  exporting `resolve()`, `discover()`, `buildDiscoveryResponse()`, and `computeDiscoveryEtag()`;
  one test file with ten named test suites (`T-C1-01` … `T-C1-10`); one frozen contract artifact;
  no `worker.ts` wiring (functions tested directly, mirroring B3's precedent); reads only from
  bundled manifests and the A5 config-cache surface (kill switches, entitlements, grants).

## 2. What was implemented

- **`CapabilityRegistry`** — a `Map<string, Manifest>` keyed by `${capabilityId}@${version}`,
  built from bundled manifests via A4's `load()` and frozen at the registry boundary.
- **`resolve()`** — stage-5 lookup: exact version pin, lifecycle checks (`retired` rejected,
  `deprecated` served), kill-switch enforcement via config cache; returns `{ok, manifest}` or
  `{ok: false, code}`.
- **`discover()`** — returns active, granted manifests filtered by entitlement plan tier,
  `allowed_capabilities`, and grant rows; produces a sorted manifest list plus etag.
- **`buildDiscoveryResponse()`** — HTTP helper returning `200` with manifest JSON or `304`
  when `If-None-Match` matches the etag.
- **`computeDiscoveryEtag()`** — stable hash over the granted+active manifest set, reusing A4's
  `hashManifest`.

See [`spec.md`](./spec.md) for full requirements and [`plan.md`](./plan.md) for file-level
traceability.

## 3. Files to review

| Path | Role |
| --- | --- |
| `ai-platform/src/capability/index.ts` | Registry, `resolve()`, `discover()`, `buildDiscoveryResponse()`, `computeDiscoveryEtag()` |
| `ai-platform/test/capability.test.ts` | Ten named test suites `T-C1-01` … `T-C1-10` (11 test cases total) |
| `specs/025-capability-resolver-discovery/contracts/capability-registry.md` | Frozen `ResolveResult`, `DiscoveryResult`, registry key format, immutability guarantee |

## 4. Prerequisites

From the repository root:

```bash
cd ai-platform
npm install   # first time only
```

The three integration cases (`T-C1-04`, `T-C1-07`, `T-C1-10`) read kill-switch, entitlement, and
grant rows against the real Miniflare D1 binding. Run them with
`--config vitest.workers.config.ts` (B3's workers-pool harness: `d1Databases: ["DB"]`, seeded
from the A5 migration).

## 5. Run the automated suite

From `ai-platform/`:

```bash
npx vitest run test/capability.test.ts
```

> **Note:** `test/capability.test.ts` is excluded from the default Node pool per the T001 harness
> (`vitest.config.ts` `exclude`). All 11 test cases run via the workers config below.

```bash
npx vitest run --config vitest.workers.config.ts test/capability.test.ts
```

Expected: **11 passing tests** in `test/capability.test.ts` for this slice only. Do **not** run
`npm test` for the full platform suite.

| Test id | Describe name |
| --- | --- |
| T-C1-01 | `resolver_exact_pin_resolves` |
| T-C1-02 | `resolver_unknown_capability` |
| T-C1-03 | `resolver_retired_rejected` |
| T-C1-04 | `resolver_killed_capability_disabled` |
| T-C1-05 | `resolver_deprecated_serves` |
| T-C1-06 | `resolver_manifest_immutable` |
| T-C1-07 | `discovery_only_granted_active` |
| T-C1-08 | `discovery_etag_not_modified` |
| T-C1-09 | `discovery_etag_changes` |
| T-C1-10 | `discovery_entitlement_gated_absent` |

## 6. Inspect the changes

Grep for the three resolver error codes in the capability module:

```bash
cd ai-platform
grep -n 'capability_unknown\|capability_retired\|capability_disabled' src/capability/index.ts
```

Read the frozen contract artifact:

```bash
cat ../specs/025-capability-resolver-discovery/contracts/capability-registry.md
```

Confirm the `ResolveResult` discriminated union, `DiscoveryResult` shape, `${capabilityId}@${version}`
registry key format, and the resolved-manifest immutability guarantee match what `resolve()` and
`discover()` export.
