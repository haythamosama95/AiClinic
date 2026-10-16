# Implementation Plan: Worker skeleton and environments (A1)

**Branch**: `ai/017-a1-worker-skeleton` | **Date**: 2026-07-30 | **Spec**: `specs/015-ai-worker-skeleton/spec.md`

**Input**: Feature specification from `/specs/015-ai-worker-skeleton/spec.md`

## Summary

A1 provisions a bare Cloudflare Worker skeleton deployed as three isolated environments —
development, staging, production — each wired to its own D1, R2, and Durable Object bindings, so
that every later slice builds against bindings that are already separated. It carries no request
path and no behaviour beyond a health endpoint that reports build and environment identity.

A1 sits at the head of Band A (Delivery Plan §3.2), with `Needs: —`: it precedes every slice
that touches a binding (A6 D1 schema, A7 config cache, B6 Quota DO). Its `Done when` is provable
by four infra/config tests, not by any user-facing demonstration (DP-3).

## Technical Context

**Language/Version**: TypeScript (Cloudflare Workers runtime; `wrangler` config and Worker
source). No Dart, no SQL, no Flutter in this slice.

**Primary Dependencies**: Cloudflare Workers Paid subscription, `wrangler` (Workers CLI), and the
three Cloudflare bindings the spec names — D1, R2, Durable Objects — plus the Workers secret
store. No runtime libraries are introduced; a Worker skeleton needs no framework (D-15).

**Storage**: No data is stored by this slice. A1 provisions one D1 database binding, one R2
bucket binding, and one Durable Object namespace binding *per environment* (§13.4 *Environments*,
FR-001). No tables, no objects, no migrations are created (Key Entities: none).

**Testing**: Vitest with `@cloudflare/vitest-pool-workers` (the Workers test layer in §13.5
*Contract tests* / infra-config layer), exercising the health endpoint and the binding
definitions via `unstable_dev` / `wrangler` environment introspection. No `flutter test`, no SQL
tests, no provider fixtures.

**Target Platform**: Cloudflare Workers, three named environments (development, staging,
production). The D1 region pin (§13.4 *D1 region*) is asserted in A6/A7; A1 only ensures each
environment has its own D1 binding.

**Project Type**: A new additive, non-primary serverless deployable — the AI Gateway Worker —
sibling to the Flutter desktop app and the Supabase backend, living in `ai-platform/` at the repo
root (Delivery Plan §7.1).

**Performance Goals**: None. A1 has no request path and no latency budget. The only observable
is correctness of environment separation and the health endpoint.

**Constraints**: §1.4 capability budget — Workers Paid plan only (Free plan not viable, FR-004);
§13.4 *Environments* — no shared state, no shared installations (FR-002); §13.4 *Secrets* —
provider keys and signing material in the secret store only, never in config files, never
journaled, never logged (FR-003); startup must fail loud on a missing required infrastructure
binding (FR-006). No §4 component is touched (A1 is infra, not a gateway component).

**Scale/Scope**: Three environments, one health endpoint, four named tests (T1–T4), six FRs.
Well under the ~25-task ceiling (Delivery Plan §6.3 stop condition 5).

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- [x] Feature scope still fits small-to-mid-size multi-branch clinics; hospital-scale or
      enterprise-only requirements are explicitly rejected or separately ratified — A1 keeps the
      platform on the single low-cost Workers Paid subscription (§1.4.1) with the recurring R2
      free allowance; no enterprise-scale infrastructure is introduced.
- [x] Design keeps a simple operational model with no microservices, message queues,
      Kubernetes, or custom primary backend service — one Worker skeleton, three environments,
      no queues, no orchestration (§14: one deployable Worker, synchronous, no queues).
- [x] Layer ownership is explicit: Flutter handles UI/orchestration, Supabase handles
      backend capabilities, PostgreSQL owns domain integrity, and AI stays isolated — A1 touches
      only `ai-platform/`; it touches neither `frontend/` nor `backend/`.
- [x] Protected writes, validation, permissions, and transactional rules remain enforced
      through PostgreSQL constraints, triggers, RLS, or RPC functions — A1 writes nothing to any
      store and enforces no domain rules; it provisions empty bindings only.
- [x] Security remains authenticated, tenant-scoped, branch-scoped, permission-gated,
      auditable, and soft-delete-preserving — A1 holds no authN, no tenants, no audit rows;
      its security contribution is environment separation (§13.4 "no shared state, no shared
      installations") and the §13.4 *Secrets* contract it freezes for later slices.
- [x] AI actions remain human-approved, have no direct database/backend access, and the
      feature still works in a degraded manual mode when AI is unavailable — A1 has no AI
      actions and no Supabase access; the gateway has no write path into Supabase at all (§14
      acknowledgement).

**§14 acknowledgement (gateway slices):** The Worker provisioned here is an additive,
non-primary deployable component. It holds **no domain logic, no business data, and no write path
into Supabase**, and it is **always optional** — if it vanishes, no business rule is lost. A1
introduces only empty environments, bindings, and a health endpoint, so it stays squarely inside
that boundary. The constitution amendment registering this new deployable (Delivery Plan §7, §14
acknowledgement) is made before or as part of this slice so A1 is not itself architectural drift
(spec Assumptions).

## Project Structure

### Documentation (this feature)

```text
specs/015-ai-worker-skeleton/
├── spec.md               # /speckit-specify output (authoritative)
├── plan.md               # This file (/speckit-plan output)
└── quickstart.md         # How a human runs the three-environment deploy and the health check
```

No `data-model.md` — A1 defines no D1 entities (spec Key Entities: "Not applicable").
No `contracts/` — A1 freezes the environment-topology and health-endpoint *contract surfaces* as
prose in its `## Slice Contract` and Requirements; it produces no machine-readable contract
artifact (the first such artifacts are A2/A3). No `research.md` — the research is
`01-ai-platform.md` and redoing it is how architecture drift starts (Delivery Plan §6.1).

### Source Code (repository root)

```text
ai-platform/                         # NEW — sibling of frontend/ and backend/ (Delivery Plan §7.1)
├── wrangler.toml                    # Three named envs: dev, staging, production; D1/R2/DO bindings each
├── package.json                     # wrangler, vitest, @cloudflare/vitest-pool-workers
├── tsconfig.json
├── src/
│   └── worker.ts                    # The skeleton: binds D1/R2/DO, serves the health endpoint
├── test/
│   ├── env-deploys.test.ts          # T1, T3, T4 (infra/config, via wrangler env introspection)
│   └── health.test.ts               # T2 (infra/config, via unstable_dev)
└── README.md                        # One-paragraph orientation to the gateway directory
```

**Structure Decision**: The gateway lives in `ai-platform/` at the repository root as a sibling
of `frontend/` and `backend/`, not inside `backend/`, because it is a separate deployable with a
separate store and no write path into Supabase (Delivery Plan §7.1, §3.4 of the architecture).
A1 creates this directory for the first time. No `frontend/` or `backend/` path is touched.

## Consumes Binding

A1 has `Needs: —` (Delivery Plan §3.2). It consumes no frozen contract from any earlier slice.

| Consumes entry | Binds to | Status |
| --- | --- | --- |
| *(none)* | — | No earlier-slice contract is consumed; there is no existing implementation to bind to. |

## Components Touched

A1 modifies **no** §4 component of `01-ai-platform.md`. §4 enumerates the Worker's *behavioural*
components (protocol adapter, identity stage, journal writer, etc.); A1 is infra/config that
provisions the deployable those components will later live in, and it introduces none of their
behaviour. This is the explicit reason a single-component-touch rule is not violated: there is no
§4 component to touch. (Stop condition 5 is not triggered.)

## Files

| File | Created / Modified | Traces to |
| --- | --- | --- |
| `ai-platform/wrangler.toml` | Created | FR-001 (three envs, each own D1/R2/DO), FR-002 (no shared binding), FR-004 (Paid plan target), FR-006 (missing binding fails startup) |
| `ai-platform/package.json` | Created | FR-005 (health endpoint build pipeline), Test plan (Vitest pool-workers) |
| `ai-platform/tsconfig.json` | Created | FR-005 (TypeScript Worker source) |
| `ai-platform/src/worker.ts` | Created | FR-005 (health endpoint returns git SHA + wrangler env name), FR-006 (binding presence check at startup) |
| `ai-platform/test/env-deploys.test.ts` | Created | T1, T3, T4 (FR-001, FR-002, FR-006) |
| `ai-platform/test/health.test.ts` | Created | T2 (FR-005) |
| `ai-platform/README.md` | Created | Structure Decision (orient future readers to the gateway directory) |
| `specs/015-ai-worker-skeleton/quickstart.md` | Created | FR-001, FR-005 (human runs the three-env deploy + health check) |

Every file traces to a named FR or a named test. No file is untraced. No file introduces a
requirement the spec does not name.

## Test Layout

The spec's Test plan names four tests, all at the **Infra / config** layer (Delivery Plan
§3.11.1 row A1). §13.5 does not name an "infra/config" row explicitly; the closest layer is
*Contract tests* run in CI on every change, exercised here against the Worker's binding
configuration and health endpoint via `@cloudflare/vitest-pool-workers`.

| Named test | Layer (§13.5) | Path | Asserts (from spec Test plan) |
| --- | --- | --- | --- |
| T1 `env_each_environment_deploys` | Contract tests (CI) | `ai-platform/test/env-deploys.test.ts` | dev, staging, production each deploy, each with own D1, R2, DO namespace |
| T2 `health_returns_build_and_environment_identity` | Contract tests (CI) | `ai-platform/test/health.test.ts` | health endpoint returns build identity (git commit SHA) + environment identity (wrangler env name) |
| T3 `env_no_binding_shared_between_environments` | Contract tests (CI) | `ai-platform/test/env-deploys.test.ts` | no D1/R2/DO binding shared by any two envs; fails on violation |
| T4 `env_missing_required_binding_fails_at_startup` | Contract tests (CI) | `ai-platform/test/env-deploys.test.ts` | missing D1/R2/DO binding fails at startup, not at first use |

All four join CI permanently (Delivery Plan §3.10). The missing-secret branch is **not** a test
here — it is deferred to the slice that first introduces a secret binding (spec Clarifications
Session 2026-07-30, FR-006).

## Sequencing

Tests land alongside the implementation that satisfies them, never after. The order is driven by
what each test needs to exist:

1. **`wrangler.toml` with three environments and their D1/R2/DO bindings** → satisfies the
   structure T1 and T3 assert against. Write the binding definitions before any test can compare
   them.
2. **`src/worker.ts` startup binding-presence check** → satisfies what T4 exercises (a missing
   D1/R2/DO binding throws at startup, in the Worker's top-level scope so it fails before the
   fetch handler runs). This is the only failure branch A1 can reach (FR-006).
3. **`src/worker.ts` health endpoint** → satisfies what T2 asserts (returns git commit SHA +
   wrangler env name). The git SHA is injected as a build-time variable bound in `wrangler.toml`
   per environment; the env name is read from the runtime environment.
4. **`test/env-deploys.test.ts` (T1, T3, T4)** — written alongside steps 1–2; these three tests
   introspect the `wrangler.toml` environment definitions and exercise the startup check via
   `unstable_dev`.
5. **`test/health.test.ts` (T2)** — written alongside step 3; calls the health endpoint through
   `unstable_dev` for each environment and asserts the two identity tokens.
6. **`quickstart.md` + `README.md`** — last; they document the now-passing deploy and health
   check for the human reviewer.

No implementation step precedes its test by more than the trivial "the file the test imports must
exist" coupling. No test is deferred to a later slice.

## Complexity Tracking

No constitution violation to justify. All six Constitution Check boxes are ticked; the §14
acknowledgement is recorded above. This section is intentionally empty.

| Violation | Why Needed | Simpler Alternative Rejected Because |
| --- | --- | --- |
| *(none)* | — | — |