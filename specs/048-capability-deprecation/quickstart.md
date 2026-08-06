# Quickstart: Capability deprecation and the overlap window (J1)

J1 adds operator deprecate / retire mutations that persist a global-scope `capability_grant`
lifecycle overlay, discovery announcement of deprecated versions with a successor, overlap-window
serving for deprecated pins, and `capability_retired` after retirement — without editing published
manifest bytes.

**Scope rule:** A quickstart documents **this slice only**. List only files this slice added or
modified, only this slice's test files, and only commands that run this slice's tests. Do **not**
include prior-slice files in the review table, combined test counts from earlier slices, prior-slice
regression commands, or diffs "against the <prior slice> baseline". Full-suite regression (this slice
plus every prior slice) belongs in the Verification task, not in `quickstart.md`.

**Numbering rule:** Number sections sequentially (`## 1.`, `## 2.`, …). Section **1** is always
**Architecture context**. When omitting Prerequisites or Manual validation, renumber the remaining
sections — do not leave gaps (e.g. 1, 2, 4, 5).

## 1. Architecture context

J1 implements the **J1** row in
[`../../docs/architecture/ai-platform/03-ai-platform-delivery-plan.md`](../../docs/architecture/ai-platform/03-ai-platform-delivery-plan.md)
§3.9, covering architecture sections **§5.7** (deprecation announcement), **§12.4** (retire a
capability), and **A12** (overlap window for deprecated versions).

- **What the spec delivered** ([`spec.md`](./spec.md)): operator deprecate / retire mutations
  journaled on `control_audit`; discovery announces deprecation with a successor before retirement is
  enforced; a deprecated pin keeps serving inside the configured overlap window; after retirement the
  same pin returns `capability_retired`; lifecycle overlay persisted on `capability_grant` at global
  scope without manifest edits.
- **What the plan scoped** ([`plan.md`](./plan.md)): one additive migration on `capability_grant`;
  extensions to `src/capability/` (effective lifecycle overlay reads, resolve / discover behaviour)
  and `src/control/` (deprecate / retire handlers and routes); one workers-pool integration test file
  with five named cases (`T-J1-01` … `T-J1-05`); frozen contract
  `contracts/capability-deprecation.md`.

## 2. What was implemented

- **Additive migration** — nullable `lifecycle_state`, `successor_id`, `deprecated_at`, and
  `retire_after` columns on `capability_grant` (global-scope overlay rows).
- **Control-plane deprecate / retire** — `POST /control/capabilities/{id}/versions/{version}/deprecate`
  and `/retire`; append-only global overlay rows; `control_audit` actions `deprecate` / `retire`.
- **Resolve / discovery overlay reads** — `effectiveLifecycle()` via `loadConfig("grants",
  "global/{id}/{version}")`; resolve rejects only effective `retired`; discovery includes
  overlay-announced `deprecated` with successor.
- **Deprecate state guard + registry checks** — one-directional lifecycle; target/successor must
  exist in the capability registry; overlay rows stamp `revoked_at`; window compare uses epoch ms;
  deprecate audit records successor in `after_pointer`.
- **OD-9 overlap constant** — `OVERLAP_WINDOW_MS` (90 days minimum; not a configuration surface).
- **Frozen contract** — [`contracts/capability-deprecation.md`](./contracts/capability-deprecation.md).
  **Handoff:** production `D1Reader` must handle `grants` / `global/…` before the request pipeline
  enforces overlays (see contract §2.4).

See [`spec.md`](./spec.md) for full requirements and [`plan.md`](./plan.md) for file-level
traceability.

## 3. Files to review

| Path | Role |
| --- | --- |
| `ai-platform/migrations/20260802100000_capability_grant_lifecycle.sql` | Additive overlay columns on `capability_grant` |
| `ai-platform/src/capability/index.ts` | `effectiveLifecycle()`, overlay reads, resolve / discover extensions |
| `ai-platform/src/control/index.ts` | `handleDeprecate`, `handleRetire`, route dispatch |
| `ai-platform/src/worker.ts` | Control boundary includes capability lifecycle routes via `isControlRoute` |
| `ai-platform/test/capability-deprecation.test.ts` | Five named test suites `T-J1-01` … `T-J1-05` |
| `specs/048-capability-deprecation/contracts/capability-deprecation.md` | Frozen overlay shape, routes, overlap default, discovery announcement |

## 4. Prerequisites

From the repository root:

```bash
cd ai-platform
npm install   # first time only
```

Tests run in the Miniflare D1 workers pool (`vitest.workers.config.ts`); A5 plus J1 migrations are
applied in `beforeAll`.

## 5. Run the automated suite

From `ai-platform/`:

```bash
npx vitest run --config vitest.workers.config.ts test/capability-deprecation.test.ts
```

Expected: **20 passing tests** in `test/capability-deprecation.test.ts` for this slice only. Do
**not** run `npm test` for the full platform suite.

| Test id | Describe name |
| --- | --- |
| T-J1-01 | `discovery_marks_deprecated_with_successor` |
| T-J1-02 | `deprecated_serves_inside_overlap_window` |
| T-J1-03 | `retired_pin_returns_capability_retired` |
| T-J1-04 | `retire_journaled_with_operator_identity` |
| T-J1-05 | `lifecycle_survives_cold_isolate_manifest_unchanged` |
| T-J1-06 … T-J1-20 | Review-resolution branches (state guard, registry, auth, retire gates, discovery/etag/window/overlay-absent) |

## 6. Inspect the changes

Grep overlay columns and control actions:

```bash
cd ai-platform
grep -n 'lifecycle_state\|successor_id\|deprecated_at\|retire_after' \
  migrations/20260802100000_capability_grant_lifecycle.sql src/capability/index.ts src/control/index.ts
grep -n "'deprecate'\|'retire'" src/control/index.ts
```

Read the frozen contract:

```bash
cat ../specs/048-capability-deprecation/contracts/capability-deprecation.md
```

After a deprecate mutation, confirm published manifest bytes in the registry are unchanged — overlay
rows carry lifecycle state; manifests are not republished.
