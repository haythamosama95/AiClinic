# Implementation Plan: Diagnostic envelope — error taxonomy, request reference, trace propagation (A2)

**Branch**: `ai/016-a2-diagnostic-envelope` | **Date**: 2026-07-30 | **Spec**: `specs/016-ai-diagnostic-envelope/spec.md`

**Input**: Feature specification from `/specs/016-ai-diagnostic-envelope/spec.md`

## Summary

A2 gives the gateway a closed error taxonomy with a normative HTTP mapping, a short human-readable
request-reference generator, and a trace-id propagation contract — so that every later slice that
emits or handles an error, every support lookup, and every diagnostic query is constrained by
contracts that already exist and cannot drift (spec Summary; `## Slice Contract`).

A2 sits second in Band A (Delivery Plan §3.2), with `Needs: A1`. It carries no request path and no
user-facing behaviour; its `Done when` is provable by unit and contract tests, not by any
demonstration (DP-3). It runs inside the Worker skeleton and bindings A1 already provisioned.

## Technical Context

**Language/Version**: TypeScript on the Cloudflare Workers runtime, the same stack A1 established
(`ai-platform/` — `wrangler.toml`, `tsconfig.json`, `package.json`). No Dart, no SQL, no Flutter in
this slice.

**Primary Dependencies**: The existing A1 Worker (`ai-platform/src/worker.ts`) and its `Env`
interface (DB, R2, DO, BUILD_SHA, ENVIRONMENT), plus the WebCrypto `crypto.getRandomValues`
available in the Workers runtime for the CSPRNG the spec names (FR-011, FR-016). No new runtime
library is introduced; a ULID-format string and a Crockford-base32 reference are produced with
stdlib `crypto.getRandomValues` only (D-15 — one implementation needs no interface; the spec names
the format, not a package, and adding a dependency the spec does not name is out of scope).

**Storage**: No data is stored by this slice. A2's reference generator is stateless and in-memory
(spec Key Entities: "Not applicable"; FR-012 defers the D1 `request_reference` unique index and
stored-row retry to A6). The bindings A1 provisioned (DB, R2, DO) are untouched and unused here.

**Testing**: Vitest with `@cloudflare/vitest-pool-workers` (already in `ai-platform/package.json`),
exercising pure-unit and contract assertions against the taxonomy table, the error-body builder, the
reference generator, and the trace-id resolver. No `flutter test`, no SQL tests, no provider
fixtures, no live Worker fetch in this slice — the contracts are unit-testable in isolation
(§13.5 *Contract tests*).

**Target Platform**: Cloudflare Workers, the three environments A1 created (development, staging,
production). A2 adds no environment and no binding.

**Project Type**: An additive, non-primary serverless deployable — the AI Gateway Worker —Sibling
to the Flutter desktop app and the Supabase backend, already living in `ai-platform/` (Delivery Plan
§7.1). A2 adds contracts and generators to that Worker, not infrastructure.

**Performance Goals**: None at the request level. The only measurable is correctness of the taxonomy
mapping, the reference format/uniqueness over 20,000 draws (T21), and the trace contract. The
generator must not be a measurable latency contributor; a single `crypto.getRandomValues` call per
reference and per fallback trace id is the entire cost.

**Constraints**: §5.4 — the HTTP column is normative and the only translation the protocol adapter
(`§4.3.1`) may apply (FR-002); the taxonomy code in the body, not the status, is what clients branch
on (FR-003). §13.1 — structured logs always carry request reference, trace id, installation,
capability, prompt version, and never prompts, context, or credentials (FR-015, T27). §8.9 — the
reference is a support handle, not a key; uniqueness is enforced by A6's D1 index, not by this slice
(FR-012; Out of Scope). No per-request server-side state (§4.4, §9.7); the generator is stateless
(Out of Scope). No `499` on a live socket (FR-007). No error body for `context_requested` (FR-008).
No code maps to bare `400` (FR-005).

**Scale/Scope**: Eighteen taxonomy codes, one error-body shape, one reference generator, one
normalisation rule, one trace-id resolver, twenty-nine named tests (T1–T29), sixteen FRs. Well
under the ~25-task ceiling (Delivery Plan §6.3 stop condition 5); tasks will land at roughly one per
FR group, not one per test.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- [x] Feature scope still fits small-to-mid-size multi-branch clinics; hospital-scale or
      enterprise-only requirements are explicitly rejected or separately ratified — A2 gives every
      AI request failure a short reference a clinician can read aloud over the phone and keeps
      provider native errors out of the client; no enterprise-scale assumption is introduced (spec
      Constitution Alignment *Clinic Fit*).
- [x] Design keeps a simple operational model with no microservices, message queues,
      Kubernetes, or custom primary backend service — A2 adds TypeScript modules inside the
      existing single Worker; no new deployable, no queue, no orchestration (§14: one deployable
      Worker, synchronous, no queues).
- [x] Layer ownership is explicit: Flutter handles UI/orchestration, Supabase handles
      backend capabilities, PostgreSQL owns domain integrity, and AI stays isolated — A2 touches
      only `ai-platform/`; it touches neither `frontend/` nor `backend/` (spec Constitution
      Alignment *Layer Placement*).
- [x] Protected writes, validation, permissions, and transactional rules remain enforced
      through PostgreSQL constraints, triggers, RLS, or RPC functions — A2 writes nothing to any
      store and enforces no domain rules; it defines contracts and generators only.
- [x] Security remains authenticated, tenant-scoped, branch-scoped, permission-gated,
      auditable, and soft-delete-preserving — A2 holds no authN, no tenants, no audit rows; its
      security contribution is the no-prompt/context/credentials-in-logs rule (FR-015, T27) and the
      stateless, CSPRNG-derived reference (FR-011). It carries no PHI and writes nothing.
- [x] AI actions remain human-approved, have no direct database/backend access, and the
      feature still works in a degraded manual mode when AI is unavailable — A2 has no AI actions
      and no Supabase access; the gateway has no write path into Supabase at all (§14
      acknowledgement).

**§14 acknowledgement (gateway slices):** The Worker A2 extends is an additive, non-primary
deployable component. It holds **no domain logic, no business data, and no write path into
Supabase**, and it is **always optional** — if it vanishes, no business rule is lost (spec
Constitution note). A2 introduces only contracts and generators, so it stays squarely inside that
boundary.

## Project Structure

### Documentation (this feature)

```text
specs/016-ai-diagnostic-envelope/
├── spec.md               # /ai-platform-specify output (authoritative)
├── plan.md               # This file (/ai-platform-plan output)
└── quickstart.md         # What A2 implemented, files to review, and how to validate in CI
```

No `data-model.md` — A2 defines no D1 entities (spec Key Entities: "Not applicable").
No `contracts/` — A2 freezes the error-taxonomy, error-body, request-reference, and trace contracts
as prose + code in its `## Slice Contract`, Requirements, and `ai-platform/` source; it produces no
machine-readable contract artifact beyond the TypeScript types that encode them (the contract *is*
the typed module). No `research.md` — the research is `17-ai-platform.md` and redoing it is how
architecture drift starts (Delivery Plan §6.1).

### Source Code (repository root)

```text
ai-platform/                         # existing — created by A1
├── src/
│   ├── worker.ts                     # modified: wire diagnostic envelope into the fetch path's
│   │                                 #   error/log emission and the trace-id resolver (FR-004, FR-014–016)
│   ├── errors.ts                     # NEW: the §5.4 taxonomy table + error-body builder (FR-001–009)
│   ├── reference.ts                  # NEW: Crockford-base32 request-reference generator + normalisation (FR-010–013)
│   └── trace.ts                      # NEW: trace-id resolver — accept caller-supplied or generate ULID (FR-014–016)
└── test/
    ├── taxonomy.test.ts              # T1–T19, T24–T26, T29 (contract)
    ├── error-body.test.ts            # T20 (contract)
    ├── reference.test.ts             # T21, T28 (unit + contract)
    ├── trace.test.ts                 # T22, T23 (unit)
    └── log-redaction.test.ts         # T25, T27 (contract)
```

**Structure Decision**: The gateway lives in `ai-platform/` at the repository root as a sibling of
`frontend/` and `backend/` (Delivery Plan §7.1). A1 created this directory; A2 extends `src/` with
three contract modules and `test/` with five contract/unit files. No `frontend/` or `backend/` path
is touched. The diagnostic envelope is split into `errors.ts` / `reference.ts` / `trace.ts` rather
than one file because each freezes an independent contract a different later slice consumes
(A8 the error body and trace header, A6 the reference column, F3 the normalisation rule); keeping
them separate preserves the no-rework boundary (Delivery Plan §2.3).

## Consumes Binding

A2 has `Needs: A1` (Delivery Plan §3.2). It consumes the Worker skeleton and bindings A1 froze.

| Consumes entry | Binds to | Status |
| --- | --- | --- |
| A1 — Worker skeleton and environments (three isolated envs, bindings, health endpoint) | `ai-platform/wrangler.toml` (three envs, D1/R2/DO bindings each); `ai-platform/src/worker.ts` (`Env` interface, `GatewayObject` DO class, `fetch` handler, `/health` route); `ai-platform/package.json` (Vitest pool-workers, Workers types); `ai-platform/tsconfig.json` | Exists, created by A1 on `ai/master`. A2 imports the `Env` type and the `fetch` handler context; it **does not** alter env topology, bindings, or the health endpoint. |

No Consumes entry has a missing implementation (stop condition 2 not triggered).

## Components Touched

A2 touches **one** §4 component: **§4.3.1 Protocol adapter**.

`§4.3.1` owns "translation of the internal error taxonomy to HTTP status codes plus a stable error
body" and "header handling (idempotency key, client trace id, capability version pin)". A2 produces
the modules that behaviour calls: the taxonomy-to-HTTP translation (`errors.ts`), the error-body
builder (`errors.ts`), the request-reference generator (`reference.ts`), and the trace-id resolver
(`trace.ts`). The live wire-format parsing and SSE framing remain in A8; A2 only supplies the
contracts and generators A8 consumes, plus the diagnostic emission wired into the existing
`worker.ts` fetch path.

No other §4 component is modified. The journal writer (§4.3.11), telemetry emitter (§4.3.12), and
support lookup (§4.5) consume A2's contracts in later slices (C5/C6, F3) but are not touched here.
Stop condition 5 is not triggered.

## Files

| File | Created / Modified | Traces to |
| --- | --- | --- |
| `ai-platform/src/errors.ts` | Created | FR-001, FR-002, FR-003, FR-004, FR-005, FR-006, FR-007, FR-008, FR-009 (taxonomy table, HTTP mapping, error-body `{code,request_reference,trace_id,retry_safe}`, `retry_safe` boolean mapping, no-bare-400, `499`-never-on-socket, no-body-for-`context_requested`, unrecognised→`internal_error`) |
| `ai-platform/src/reference.ts` | Created | FR-010, FR-011, FR-012, FR-013 (Crockford-base32 8-symbol format, CSPRNG draw, support-handle-not-key, normalisation rule) |
| `ai-platform/src/trace.ts` | Created | FR-014, FR-015, FR-016 (accept caller-supplied trace id or generate ULID; propagate identical to caller-supplied; structured-log fields) |
| `ai-platform/src/worker.ts` | Modified | FR-004, FR-014, FR-015, FR-016 (wire the diagnostic envelope into the fetch path's trace-id resolution and error/log emission; no new route, no new binding) |
| `ai-platform/test/taxonomy.test.ts` | Created | T1–T19, T24, T26, T29 |
| `ai-platform/test/error-body.test.ts` | Created | T20 |
| `ai-platform/test/reference.test.ts` | Created | T21, T28 |
| `ai-platform/test/trace.test.ts` | Created | T22, T23 |
| `ai-platform/test/log-redaction.test.ts` | Created | T25, T27 |
| `specs/016-ai-diagnostic-envelope/quickstart.md` | Created | Slice completion guide — what was implemented, files to review, CI validation commands (Documentation) |

Every file traces to named FRs and named tests. No file is untraced. No file introduces a
requirement the spec does not name. `worker.ts` is modified, not created, and its modification is
limited to importing and calling the three new modules from the existing fetch path — no new route,
no new binding, no new env, no health-endpoint change (Consumes binding preserved, Delivery Plan
§2.3).

## Test Layout

The spec's Test plan names twenty-nine tests at the **Unit + contract** layer (Delivery Plan
§3.11.1 row A2). §13.5 names the matching row: **Contract tests** — "Manifests, context key shapes,
output schemas, and the **error taxonomy** are internally consistent and backward compatible
against the previous release … CI, on every change." The reference and trace tests are pure unit
tests of stateless generators, which §13.5 places under the same CI-on-every-change discipline; no
§13.5 row is violated (stop condition 3 not triggered).

| Named test | Layer (§13.5) | Path | Asserts (from spec Test plan) |
| --- | --- | --- | --- |
| T1–T18 | Contract tests (CI) | `ai-platform/test/taxonomy.test.ts` | one case per §5.4 code: HTTP status, retryability, quota-consumption flag, body code |
| T19 | Contract tests (CI) | `ai-platform/test/taxonomy.test.ts` | unrecognised code → `internal_error` (HTTP 500), never surfaced raw |
| T20 | Contract tests (CI) | `ai-platform/test/error-body.test.ts` | every error body is `{"code","request_reference","trace_id","retry_safe"}`, `retry_safe` boolean |
| T21 | Contract tests (CI) | `ai-platform/test/reference.test.ts` | 20,000 generated references match the regex, are uppercase, omit `I`/`L`/`O`/`U`, unique across the run |
| T22 | Unit (CI) | `ai-platform/test/trace.test.ts` | a supplied trace id appears on every log line for that request |
| T23 | Unit (CI) | `ai-platform/test/trace.test.ts` | an absent trace id is generated as a ULID (26-char Crockford-base32) and propagated identically |
| T24 | Contract tests (CI) | `ai-platform/test/taxonomy.test.ts` | no error body is built for `context_requested` |
| T25 | Contract tests (CI) | `ai-platform/test/log-redaction.test.ts` | a malformed body is rejected by adapter parsing and produces no taxonomy-coded body (no bare `400`) |
| T26 | Contract tests (CI) | `ai-platform/test/taxonomy.test.ts` | `rate_limited` carries `retry_after` not the period reset; `quota_exhausted` carries the period reset not `retry_after` |
| T27 | Contract tests (CI) | `ai-platform/test/log-redaction.test.ts` | no log line carries prompt text, context payload, or credentials, even for a request that contained them |
| T28 | Unit (CI) | `ai-platform/test/reference.test.ts` | a lowercase or `I`/`L`/`O`-confused input normalises to the stored reference form |
| T29 | Contract tests (CI) | `ai-platform/test/taxonomy.test.ts` | `retry_safe` is false for §5.4 "Retryable" values `No` and `—`, true for every other value |

All twenty-nine join CI permanently (Delivery Plan §3.10). A checkpoint requires every prior suite
green; A1's `env-deploys.test.ts` and `health.test.ts` remain green and untouched.

## Sequencing

Tests land alongside the implementation that satisfies them, never after (Delivery Plan §3.10). The
order is driven by what each module's tests need to exist:

1. **`src/errors.ts` — the taxonomy table and `retry_safe` mapping** (FR-001–009). The table is the
   single source the taxonomy tests introspect; write it first. T1–T18, T24, T26, T29 are written
   against it in `test/taxonomy.test.ts` in the same step (the table is the contract; the tests are
   the contract test).
2. **`src/errors.ts` — the error-body builder** (FR-004; Clarification Q1). Extends the table with
   a builder that emits `{"code","request_reference","trace_id","retry_safe"}`. T20 written
   alongside in `test/error-body.test.ts`.
3. **`src/reference.ts` — the Crockford-base32 generator + normalisation** (FR-010–013). CSPRNG
   draw via `crypto.getRandomValues`; the normalisation map (`I`/`L`→`1`, `O`→`0`, case-fold up).
   T21 (20,000-draw run) and T28 (normalisation) written alongside in `test/reference.test.ts`.
4. **`src/trace.ts` — the trace-id resolver** (FR-014–016; Clarification Q3). Accept the
   caller-supplied id; on absence generate a ULID-format string from `crypto.getRandomValues`;
   return a value propagated identically to a caller-supplied one. T22 and T23 written alongside
   in `test/trace.test.ts`.
5. **`src/worker.ts` modification — wire the envelope into the fetch path** (FR-004, FR-014,
   FR-015, FR-016). Resolve the trace id at the top of `fetch`, thread it into the error/log
   emission path, and ensure structured logs carry `request_reference`, `trace_id`, installation,
   capability, prompt version — and nothing else of payload. T25 (malformed body rejected before
   taxonomy) and T27 (no prompt/context/credentials in logs) written alongside in
   `test/log-redaction.test.ts`.
6. **Full CI run** — all five test files plus A1's two, green, before the slice is reviewable
   (Delivery Plan §3.10 — every prior suite green, not just the latest).
7. **`quickstart.md`** — last; documents what was implemented, the files to review, and how to
   reproduce the green suite for a human reviewer.

No implementation step precedes its test by more than the trivial "the module the test imports
must exist" coupling. No test is deferred to a later slice. The `worker.ts` change is last among
the source edits because it depends on all three contract modules existing; its tests (T25, T27)
exercise the wired path, not the modules in isolation.

## Complexity Tracking

No constitution violation to justify. All six Constitution Check boxes are ticked; the §14
acknowledgement is recorded above. This section is intentionally empty.

| Violation | Why Needed | Simpler Alternative Rejected Because |
| --- | --- | --- |
| *(none)* | — | — |