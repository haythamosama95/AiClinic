# Implementation Plan: Guard stages: identity, rate limiting, entitlement and kill switches (B3)

**Branch**: `ai/023-b3-guard-stages` | **Date**: 2026-07-31 | **Spec**: [`spec.md`](./spec.md)

**Input**: Feature specification from `specs/023-guard-stages/spec.md`

**Note**: This template is filled in by the `/ai-platform-plan` command. See `.specify/templates/plan-template.md` for the execution workflow.

## Summary

B3 implements the guard's identity, entitlement, and rate-limit stages (§6.1 stages 2–4): it verifies the AAT through the token verifier port (WebCrypto `Ed25519`, `alg: EdDSA`), produces an immutable request principal, evaluates AI-enablement / plan tier / capability grant / all four kill-switch scopes from the config cache with zero D1 reads on a warm isolate, enforces the three composite rate-limit keys, and counts every guard rejection in bucketed `platform_counter` rows — never as `ai_request` rows. It sits after A5/B1/B2 (its `Needs`: it reads keys, entitlements, and lifecycle state the earlier slices froze) and before B4 (the admission stage's single Quota DO round trip runs only after these stages have produced an immutable principal and a cheap rejection).

## Technical Context

**Language/Version**: TypeScript (Cloudflare Workers; `target: ES2022`, `module: ES2022`, strict, `@cloudflare/workers-types`).

**Primary Dependencies**: Cloudflare Workers runtime (WebCrypto `Ed25519` `importKey`/`verify` — a first-class Workers algorithm, §4.2.1); the platform's existing `ai-platform/src/config-cache/` (A5), `ai-platform/src/errors.ts` (A2), `ai-platform/src/adapter.ts` (A6); the Workers Rate Limiting binding (§4.3.3); Miniflare D1 via `@cloudflare/vitest-pool-workers` for integration tests (matching B2's harness).

**Storage**: Reads only — `installation`, `installation_key`, `entitlement`, `capability_grant`, kill-switch state, and `platform_counter` rows in the platform D1 (`ai-platform/migrations/20260731120000_platform_schema.sql`, frozen by A5). B3 defines no D1 entities and runs no migrations. Writes are limited to bucketed `platform_counter` rows whose table shape is frozen by A5 (§4.3.12; §7.5).

**Testing**: `npx vitest run` for unit/spy suites (via `vitest.config.ts`); `vitest.workers.config.ts` for integration suites needing the real Miniflare D1 binding (B2's harness). Spy seams: A5's `D1Reader`/`ReaderSpy` for no-D1-read assertions; a fake `TokenVerifier` for the swap test.

**Target Platform**: Cloudflare Workers (the AI gateway Worker in `ai-platform/`).

**Project Type**: Cloudflare Worker guard stage — additive, non-primary component (§14 acknowledgement).

**Performance Goals**: Guard stages 2–4 complete in low tens of milliseconds with no D1 read on a warm isolate (§6.1); rejections are nearly free (§4.3.12; §7.5).

**Constraints**: One D1 read on a cold isolate only (A5 invariant, not re-proven by B3); zero D1 reads on a warm isolate for entitlement/kill-switch; no per-request server-side state (§4.4, §9.7); no second Quota DO round trip (B3 does not contact the DO at all — replay/idempotency are B4); guard rejections never journaled as `ai_request` rows (§7.5; §6.1 stage 9).

**Scale/Scope**: Clinic-scale — tens of installations, a few kilobytes of cached config (§4.3.2; §14).

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- [x] Feature scope still fits small-to-mid-size multi-branch clinics; hospital-scale or
      enterprise-only requirements are explicitly rejected or separately ratified — the guard
      protects a clinic-scale installation tenant boundary; no enterprise machinery (§4.3.2; §14).
- [x] Design keeps a simple operational model with no microservices, message queues,
      Kubernetes, or custom primary backend service — one Worker, in-isolate config cache, no
      per-request state, no queues (§4.4; §4.3.12; §14).
- [x] Layer ownership is explicit: Flutter handles UI/orchestration, Supabase handles
      backend capabilities, PostgreSQL owns domain integrity, and AI stays isolated — B3 touches
      `ai-platform/` only; the Worker holds no domain logic and no business data and has no write
      path into Supabase (§14 acknowledgement: the gateway is an additive, non-primary component,
      always optional).
- [x] Protected writes, validation, permissions, and transactional rules remain enforced
      through PostgreSQL constraints, triggers, RLS, or RPC functions — B3 reads the platform's own
      D1 (config + counters); it never writes the clinic database; the clinic-side signing and
      keystore are B1 (in `backend/supabase/`), unchanged (§4.2.1; §14 "III").
- [x] Security remains authenticated, tenant-scoped, branch-scoped, permission-gated,
      auditable, and soft-delete-preserving — every request is authenticated by an Ed25519 AAT
      verified against an enrolled public key, audience-scoped, installation-scoped; the principal is
      immutable to later stages (§4.3.2; §4.2.1; §5.6; §14 "IV").
- [x] AI actions remain human-approved, have no direct database/backend access, and the
      feature still works in a degraded manual mode when AI is unavailable — the guard is strictly
      additive; a rejection or an unreachable platform degrades to "AI unavailable" and never blocks
      clinical work (§14 "V"; A11). Hard-locking never occurs (§8.8 is F4/B4, not B3).

## Project Structure

### Documentation (this feature)

```text
specs/023-guard-stages/
├── plan.md              # This file
├── spec.md              # /ai-platform-specify output (authoritative)
├── contracts/
│   ├── token-verifier.md   # Frozen: TokenVerifier port + Principal + VerifyResult wire shape
│   └── request-principal.md # Frozen: immutable RequestPrincipal field set
└── quickstart.md       # Written during the implement-phase Documentation task (sections below)
```

`data-model.md` is **not** produced — B3 defines no D1 entities (spec `### Key Entities`: "Not applicable"). It writes only bucketed `platform_counter` rows whose shape is already frozen by A5's migration and the §4.3.12/§7.5 contract.

`research.md` is **not** produced — the research is `docs/architecture/17-ai-platform.md`; redoing it is how architecture drift starts.

`contracts/` is produced because two **Freezes** entries have wire shapes a later slice's **Consumes** must bind to (the `TokenVerifier` port and the immutable `RequestPrincipal`). The plan names them; the implement phase writes the two files above. J4 (token-contract rotation) and B4 (admission) will consume the verifier port; every downstream pipeline stage consumes the principal.

`quickstart.md` (written during the implement-phase Documentation task, per `.specify/templates/ai-platform-quickstart-template.md`) will contain:
- **§1 Architecture context** — B3 row of the delivery plan (§3.3) and the §4.3.2/§4.3.3/§4.3.4/§6.1-stages-2–4 sections; what the spec delivered; what the plan scoped.
- **§2 What was implemented** — the three sibling modules, the verifier port, the principal, the counter flush.
- **§3 Files to review** — this slice's `ai-platform/src/identity/`, `src/entitlement/`, `src/rate-limit/` files and their test files.
- **§5 Run the automated suite** — `npx vitest run test/identity.test.ts test/entitlement.test.ts test/rate-limit.test.ts` (slice-only; no full-suite `npm test`).
- **§6 Inspect the changes** — grep for the verifier port, read the frozen contract files.
- Manual validation omitted — CI is the only verification path (B3 exposes no user-facing behaviour beyond the test suite).

### Source Code (repository root)

```text
ai-platform/
├── src/
│   ├── identity/           # NEW (FR-001..FR-005, FR-013, FR-014)
│   │   └── index.ts        # TokenVerifier port, VerifyResult, Principal, enrolled-key verify
│   ├── entitlement/        # NEW (FR-008..FR-010, FR-013)
│   │   └── index.ts        # entitlement + four kill-switch scopes from config cache
│   ├── rate-limit/         # NEW (FR-006, FR-007, FR-011, FR-012, FR-013)
│   │   └── index.ts        # three composite keys, rate_limited + retry_after, counter flush
│   ├── errors.ts           # UNCHANGED (consumed from A2)
│   ├── config-cache/       # UNCHANGED (consumed from A5)
│   ├── adapter.ts          # UNCHANGED (consumed from A6)
│   ├── control/            # UNCHANGED (consumed from B2)
│   └── worker.ts           # UNCHANGED (B3 wires no new route; guard invoked by later pipeline glue)
├── test/
│   ├── identity.test.ts        # NEW
│   ├── entitlement.test.ts     # NEW
│   └── rate-limit.test.ts      # NEW
├── migrations/             # UNCHANGED (no new migration; platform_counter table frozen by A5)
├── vitest.config.ts        # MODIFIED — include identity/entitlement/rate-limit test files
└── vitest.workers.config.ts # MODIFIED — add integration cases needing the real D1 binding
```

`worker.ts` is unchanged because B3 freezes the guard contracts in code but does not wire them into the request pipeline — that wiring is a later slice (the pipeline orchestrator that calls identity → entitlement → rate-limit before the admission stage B4 owns). B3's tests exercise the three modules directly via their exported functions, mirroring how A5's `config-cache.test.ts` tests `loadConfig` without a Worker fetch.

**Structure Decision**: Sibling-per-concern modules under `ai-platform/src/`, matching the established pattern (A4 `src/manifest/`, A5 `src/config-cache/` + `src/context/`, B2 `src/control/`). From Clarification Q1 — keeps the three §4.3 components whose tests run at different layers (pure-unit identity vs D1-touching entitlement) in separately importable modules, instead of one bundled `src/guard/` that would force a test-file split across unrelated layers.

## Consumes Binding

| Consumes entry | Existing module / file / type it binds to |
| --- | --- |
| **A2** — §5.4 error taxonomy + error body | `ai-platform/src/errors.ts` — `TaxonomyCode`, `TaxonomyEntry`, `getTaxonomyEntry`, `buildErrorBody`, `supplementaryFieldsForCode` (for `rate_limited` `retry_after`). B3 emits codes; HTTP translation stays the adapter's (A6). |
| **A5** — platform D1 schema + config cache | `ai-platform/migrations/20260731120000_platform_schema.sql` (frozen `platform_counter`, `installation`, `installation_key`, `entitlement`, `capability_grant`); `ai-platform/src/config-cache/index.ts` — `ConfigCache`, `loadConfig`, `D1Reader`, `ConfigCacheMissError`, `CACHE_TTL_MS`, `ConfigEntityKind` (`"installations"`, `"keys"`, `"entitlements"`, `"grants"`, `"kill_switches"`). B3 reads through `loadConfig`; no identity-local reader (Clarification Q2). |
| **A6** — protocol adapter surface | `ai-platform/src/adapter.ts` — `AdapterStreamContext` (carries `idempotencyKey`, `traceId`, `capabilityVersion` headers). B3 receives the parsed request context from the adapter and emits taxonomy codes; it does not touch the SSE stream or HTTP translation. |
| **B1** — AAT token contract + installation keystore | `backend/supabase/migrations/20260801120000_ai_keystore_schema.sql` + `20260801120100_ai_installation_keypair_routines.sql` + `20260801120200_ai_token_issuer_rpc.sql`; frozen wire shape in `specs/021-installation-keystore-aat-issuer/contracts/aat-token.md` — `alg: EdDSA` JWS, `iss`+`kid` key selection, the §5.6 claim set, JWK `{"kty":"OKP","crv":"Ed25519","x":…}` public-key shape. B3 verifies this contract with WebCrypto `Ed25519`; it defines neither claims nor signing. |
| **B2** — installation lifecycle state | `ai-platform/src/control/index.ts` — `installation.status` enum (`active`/`suspended`/`deleted`), `entitlement.status` (`pending`/`active`/`suspended`); frozen contract in `specs/022-control-plane-enrollment/contracts/control-plane.md`. B3 reads `installation.status` for the `installation_suspended` rejection and `entitlement.status`/economics for `forbidden_capability`; it does not write lifecycle state. |

No consumed entry lacks an implementation. None is modified (delivery plan §2.3).

## Components Touched

| §4 component | Touched? | Reason |
| --- | --- | --- |
| §4.3.2 Identity and tenant resolution | **Created** | B3's primary component — the verifier port, the enrolled-key strategy, the immutable principal. |
| §4.3.3 Entitlement, quota, and rate control | **Created (partial)** | B3 creates the entitlement/kill-switch evaluation and the rate-limiting portion of this component. The Quota DO, concurrency, and credit-after-call in the same §4.3.3 row belong to B4 (out of scope — spec `Out of Scope`). |
| §4.3.4 Capability resolver | **Created (partial)** | B3 evaluates only the kill-switch and entitlement-gate aspects of §4.3.4 that are read from the config cache. The manifest-lookup portion (`capability id + version → immutable manifest`, `capability_unknown`/`capability_retired`) is C1 (out of scope). |
| §4.3.12 Telemetry emitter | **Created (partial)** | B3 owns the in-isolate rejection tally + bucketed `platform_counter` flush. The structured-log/spans portion of §4.3.12 is not built here. |
| §4.3.1 Protocol adapter, §4.3.5–§4.3.11, §4.4, §4.5 | **Not touched** | Consumed unchanged or out of scope. |

**Reason for more than one §4 component**: B3 is a merged-band-B slice (delivery plan §2.6) whose `Canonical` cell explicitly lists §4.3.2, §4.3.3, §4.3.4, and §4.3.12 together, and whose `Done when` cell fuses identity, rate limiting, and entitlement/kill-switch into a single guard. The delivery plan merged what were originally separate rows into one Spec Kit feature because the three stages cannot be tested apart (the immutable principal from identity is the input to entitlement; the principal + capability id form the rate-limit composite keys). This is the explicit, cited reason the merged-slice rule (§2.6) exists.

## Files

| File | FR(s) | Status |
| --- | --- | --- |
| `ai-platform/src/identity/index.ts` | FR-001, FR-002, FR-003, FR-004, FR-005, FR-013, FR-014 | NEW — `TokenVerifier` port, `VerifyContext`, `VerifyResult` discriminated union, `Principal` type, `EnrolledKeyVerifier` (WebCrypto `Ed25519` `importKey`+`verify`, `alg` pinned to `EdDSA`), audience/expiry/skew checks, suspended-installation rejection via `loadConfig("installations")`, immutable principal construction. |
| `ai-platform/src/entitlement/index.ts` | FR-008, FR-009, FR-010, FR-013 | NEW — `evaluateEntitlement(principal, ctx, cache, reader)` returning `{ok}` or `{code:"forbidden_capability"|"capability_disabled"}`, and the four kill-switch scopes (global/capability/installation/provider) read from `loadConfig("kill_switches")`/`loadConfig("grants")`/`loadConfig("entitlements")`. No D1 read on a warm isolate. |
| `ai-platform/src/rate-limit/index.ts` | FR-006, FR-007, FR-011, FR-012, FR-013 | NEW — three composite keys (`installation`, `installation+actor`, `installation+capability`) against the Workers Rate Limiting binding, `rate_limited` + `retry_after` (via `supplementaryFieldsForCode`), in-isolate rejection tally that flushes bucketed `platform_counter` rows (no `ai_request` row). |
| `ai-platform/test/identity.test.ts` | (tests for FR-001..FR-005, FR-013, FR-014) | NEW |
| `ai-platform/test/entitlement.test.ts` | (tests for FR-008..FR-010, FR-013) | NEW |
| `ai-platform/test/rate-limit.test.ts` | (tests for FR-006, FR-007, FR-011, FR-012, FR-013) | NEW |
| `ai-platform/vitest.config.ts` | — | MODIFIED — `include` adds `test/identity.test.ts`, `test/entitlement.test.ts`, `test/rate-limit.test.ts`. |
| `ai-platform/vitest.workers.config.ts` | — | MODIFIED — `include` adds the integration cases from the three test files that need the real Miniflare D1 binding (B2's harness: `d1Databases: ["DB"]`). Unit/spy cases stay in `vitest.config.ts`. |
| `specs/023-guard-stages/contracts/token-verifier.md` | (freezes the port from FR-001..FR-004) | NEW — frozen `TokenVerifier` port wire shape (Clarification Q3), so B4/J4 consume a contract, not prose. |
| `specs/023-guard-stages/contracts/request-principal.md` | (freezes the principal from FR-004) | NEW — frozen immutable `RequestPrincipal` field set, so every downstream pipeline stage consumes a typed artifact. |
| `specs/023-guard-stages/quickstart.md` | — | NEW — written during the implement-phase Documentation task (sections named in Project Structure → Documentation). |

Every file traces to an `FR-###`. No file is created for an unstated requirement. `worker.ts`, `errors.ts`, `config-cache/`, `adapter.ts`, `control/`, and the migration are unchanged (consumed).

## Test Layout

The spec's Test plan names 24 tests at layers "Unit", "Unit (spy)", "Integration", and "Integration (spy)" (§3.11.2 row B3). Layers are the ones in §13.5. Files mirror the source-module split (Clarification Q1).

| Test name | Spec layer | File | Config |
| --- | --- | --- | --- |
| `identity_valid_token_accepted` | Unit | `test/identity.test.ts` | `vitest.config.ts` |
| `identity_rejects_non_eddsa_alg` | Unit | `test/identity.test.ts` | `vitest.config.ts` |
| `identity_rejects_bad_signature` | Unit | `test/identity.test.ts` | `vitest.config.ts` |
| `identity_rejects_wrong_audience` | Unit | `test/identity.test.ts` | `vitest.config.ts` |
| `identity_rejects_expired_token` | Unit | `test/identity.test.ts` | `vitest.config.ts` |
| `identity_accepts_notyetvalid_inside_skew` | Unit | `test/identity.test.ts` | `vitest.config.ts` |
| `identity_rejects_outside_skew` | Unit | `test/identity.test.ts` | `vitest.config.ts` |
| `identity_rejects_unknown_issuer` | Unit | `test/identity.test.ts` | `vitest.config.ts` |
| `verifier_swap_changes_no_outcome` | Unit | `test/identity.test.ts` | `vitest.config.ts` |
| `principal_immutable_to_later_stage` | Unit (spy) | `test/identity.test.ts` | `vitest.config.ts` |
| `identity_rejects_suspended_installation` | Integration | `test/identity.test.ts` | `vitest.workers.config.ts` |
| `rate_limit_installation_key_trips` | Integration (spy) | `test/rate-limit.test.ts` | `vitest.workers.config.ts` |
| `rate_limit_installation_actor_key_trips` | Integration (spy) | `test/rate-limit.test.ts` | `vitest.workers.config.ts` |
| `rate_limit_installation_capability_key_trips` | Integration (spy) | `test/rate-limit.test.ts` | `vitest.workers.config.ts` |
| `rate_limit_rejection_no_ai_request_row` | Integration (spy) | `test/rate-limit.test.ts` | `vitest.workers.config.ts` |
| `rate_limit_counters_flush_bucketed` | Integration (spy) | `test/rate-limit.test.ts` | `vitest.workers.config.ts` |
| `entitlement_ai_disabled_installation_rejected` | Integration | `test/entitlement.test.ts` | `vitest.workers.config.ts` |
| `entitlement_plan_tier_too_low_rejected` | Integration | `test/entitlement.test.ts` | `vitest.workers.config.ts` |
| `entitlement_capability_not_granted_rejected` | Integration | `test/entitlement.test.ts` | `vitest.workers.config.ts` |
| `kill_switch_global_rejected` | Integration | `test/entitlement.test.ts` | `vitest.workers.config.ts` |
| `kill_switch_capability_rejected` | Integration | `test/entitlement.test.ts` | `vitest.workers.config.ts` |
| `kill_switch_installation_rejected` | Integration | `test/entitlement.test.ts` | `vitest.workers.config.ts` |
| `kill_switch_provider_rejected` | Integration | `test/entitlement.test.ts` | `vitest.workers.config.ts` |
| `entitlement_warm_isolate_no_d1_read` | Integration (spy) | `test/entitlement.test.ts` | `vitest.workers.config.ts` |

**Harness split (Clarification Q4):** integration cases that assert against a real schema — `identity_rejects_suspended_installation`, every `entitlement_*` case, every `kill_switch_*` case, and the three `rate_limit_*_key_trips` + `rate_limit_rejection_no_ai_request_row` + `rate_limit_counters_flush_bucketed` cases — run under `vitest.workers.config.ts` against the real Miniflare `DB` binding B2 already wired (`d1Databases: ["DB"]`), seeded with the A5 migration. Pure-unit cases (`identity_valid_token_accepted` and the seven other identity rejections, `verifier_swap_changes_no_outcome`) run under `vitest.config.ts` with no D1 binding. Spy assertions on the D1 read count (`entitlement_warm_isolate_no_d1_read`, `principal_immutable_to_later_stage`) reuse A5's `ReaderSpy` shape (`config-cache.test.ts`) against the injected `D1Reader`, in either config where the case has no other D1 dependency.

Every named test places in a §13.5 layer (Unit / Unit (spy) / Integration / Integration (spy)) — stop condition 3 not triggered.

## Sequencing

Tests land first or alongside their implementation, never after (delivery plan §2.2; the test file plus the diff is the review artifact). Within this slice:

1. **Identity (FR-001..FR-005, FR-013, FR-014)** — pure-unit first: the nine `identity_*` cases (`vitest.config.ts`) drive the `TokenVerifier` port and the `EnrolledKeyVerifier` against fixture tokens minted by a test helper that mirrors the B1 `EdDSA` JWS shape (no Postgres needed — WebCrypto `Ed25519` `generateKey` produces test keypairs). Then `identity_rejects_suspended_installation` (integration) wires `loadConfig("installations")` against the real D1.
2. **Entitlement (FR-008..FR-010, FR-013)** — `entitlement_warm_isolate_no_d1_read` lands first as a spy on `D1Reader`, pinning the zero-read invariant before any integration case is added; then the seven `entitlement_*`/`kill_switch_*` integration cases against the real D1, seeded with `installation`/`entitlement`/`capability_grant`/`kill_switches` rows from the A5 migration.
3. **Rate limit (FR-006, FR-007, FR-011, FR-012, FR-013)** — the three composite-key trips and `rate_limit_rejection_no_ai_request_row` first (they fix the no-`ai_request`-row invariant against a real `ai_request` table), then `rate_limit_counters_flush_bucketed` (asserts the `platform_counter` flush is bucketed, not one-row-per-event).
4. **Contracts** — `contracts/token-verifier.md` and `contracts/request-principal.md` are written alongside the `identity/` module (they freeze what its tests pin), so B4/J4 can bind during their own plan phase.
5. **Documentation** — `quickstart.md` last, during the implement-phase Documentation task, after the slice's tests pass.

The cold-isolate "exactly one D1 read on miss" invariant (Acceptance Scenario 24) is not re-proven by B3 — A5's `T-A5-17` already pins it; B3's `entitlement_warm_isolate_no_d1_read` proves only the warm-isolate half (the spec's `FR-010`).

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified**

None. No constitution violation. Every checkbox is ticked without justification; the §14 gateway acknowledgement is recorded in Constitution Check, not here.