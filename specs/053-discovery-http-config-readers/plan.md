# Implementation Plan: Discovery HTTP route and production config-cache readers (I2)

**Branch**: `ai/053-i2-discovery-http-config-readers` | **Date**: 2026-08-07 | **Spec**: [`spec.md`](./spec.md)

**Input**: Feature specification from `specs/053-discovery-http-config-readers/spec.md`

**Note**: This template is filled in by the `/ai-platform-plan` command. See `.specify/templates/plan-template.md` for the execution workflow.

## Summary

I2 mounts C1's `discover()` on the live §5.5 wire — `GET /v1/capabilities` with Bearer AAT
(same verifier as submit), `If-None-Match` / `ETag` revalidation, and
`Cache-Control: private, must-revalidate` — and completes the production D1 config-cache reader so
every request-path kind (installations, keys, entitlements, grants / lifecycle overlay, kill
switches, active routing policy, `token_contract`) is served from D1 on a miss under A5's single
cold-isolate read pattern. It sits in Band I after A5 and C1 (`Needs: A5, C1`); live client invoke
(I3) cannot proceed until discovery is reachable over HTTP (`03-ai-platform-delivery-plan.md`
§3.10).

## Technical Context

**Language/Version**: TypeScript 5.9 in the Cloudflare Worker (`ai-platform/`), `target: ES2022`,
strict, `@cloudflare/workers-types` — matching A5/C1/B3.

**Primary Dependencies**: existing `ai-platform/src/capability/` (C1 — `discover`,
`buildDiscoveryResponse`, `DiscoveryResult`); `ai-platform/src/config-cache/` (A5 —
`ConfigCache`, `loadConfig`, `D1Reader`, `ConfigCacheMissError`, `createD1ConfigReader`,
`ConfigEntityKind`); `ai-platform/src/identity/` (B3 — `EnrolledKeyVerifier`, `Principal`,
`VerifyResult`); `ai-platform/src/errors.ts` (A2 — `unauthenticated`, `liveHttpStatusForCode`,
`buildErrorBody`). No new runtime dependency; no HTTP-framework or caching library (R-20).

**Storage**: Platform D1 — additive `kill_switch` table (Clarification Q1; entity shape already named
in §7.3) so `createD1ConfigReader` can SELECT present kill-switch rows; schema snapshot update.
All other request-path kinds already have tables and SELECT branches. No R2 on the discovery path;
no Quota DO; no Supabase write.

**Testing**: Workers integration (delivery plan §3.12.9 row I2; §13.5 Pipeline / Workers
integration via Miniflare):
- `npx vitest run --config vitest.workers.config.ts test/discovery-http.test.ts` — T1–T5 (HTTP
  wire).
- `npx vitest run --config vitest.workers.config.ts test/config-readers.test.ts` — T6–T14 (direct
  Miniflare D1 + `createD1ConfigReader` / `loadConfig` per kind; T13 spy/wrapper on `D1Reader.read`).
  Both files registered in `vitest.workers.config.ts` `include` and `vitest.config.ts` `exclude`
  (B2/C1/J4 precedent). Slice-only; suite joins CI permanently (§3.10).

**Target Platform**: the `ai-platform/` Cloudflare Worker at the repository root (delivery plan
§7.1). Discovery is a live Worker fetch route; config-reader cases exercise the production reader
against Miniflare D1 without requiring every kind to be consulted by discovery HTTP.

**Project Type**: Additive, non-primary AI gateway composition (§14 acknowledgement) — no domain
logic, no business data, no write path into Supabase. Band I freezes no new contract; I2 exposes
and completes already-frozen surfaces.

**Performance Goals**: Cold-isolate config miss still pays exactly one same-region D1 read pattern
(A5 Freezes; FR-008 / T13). Discovery introduces no Quota DO round trip, no R2 object, no journal
row on auth failure, and no per-request server-side state (§4.4, §7.5, §9.7, §13.6; delivery plan
§6.4).

**Constraints**:
- `GET /v1/capabilities` never requires a capability id; entitlements + grants alone determine the
  set (FR-004; Done when).
- Auth uses Bearer AAT and the same enrolled-key verifier as submit (FR-002); missing/invalid →
  taxonomy `unauthenticated` (FR-005).
- Conditional revalidation: `If-None-Match` vs prior `ETag`; every response carries
  `Cache-Control: private, must-revalidate` (FR-003) — delegated to C1's `buildDiscoveryResponse`.
- Live route invokes C1 `discover()`; does not re-implement registry filtering (FR-006).
- Production reader covers every request-path kind including kill switches and `token_contract`
  (FR-007); miss is typed `ConfigCacheMissError`, never a silent empty admit (FR-009).
- Only volatile policy is D1 data; prompts/manifests/schemas remain deployed artifacts (FR-010).
- Do not modify Consumes contracts (A5 cache mechanics; C1 `discover`/`resolve` library) — delivery
  plan §2.3.
- Shared cache/reader in the discovery handler; verify then `discover()` (Clarification Q2).

**Scale/Scope**: Two §4 components composed (§4.3.4 discovery surface over HTTP; §4.3.2 production
config-cache readers) — see **Components Touched** for the written reason. One discovery handler
module, one worker route, one additive D1 migration + schema snapshot, `createD1ConfigReader`
kill_switches SELECT completion, two Workers test files, one contract artifact, one named
quickstart. Roughly 14–18 tasks (under the ~25 ceiling of delivery plan §6.3 / plan stop
condition 5).

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- [x] Feature scope still fits small-to-mid-size multi-branch clinics; hospital-scale or
      enterprise-only requirements are explicitly rejected or separately ratified — the entire
      config set remains a few kilobytes so a warm isolate answers from memory and a cold one pays
      one same-region D1 read; no distributed cache (constitution I; §4.3.2; §9.15).
- [x] Design keeps a simple operational model with no microservices, message queues,
      Kubernetes, or custom primary backend service — one HTTP route, one additive D1 table, and
      production SELECTs through the existing `D1Reader` seam; no new service.
- [x] Layer ownership is explicit: Flutter handles UI/orchestration, Supabase handles
      backend capabilities, PostgreSQL owns domain integrity, and AI stays isolated — I2 lives
      wholly in `ai-platform/` and touches neither `frontend/` nor `backend/`.
- [ ] (intentionally unchecked — see note) Protected writes, validation, permissions, and transactional rules remain enforced
      through PostgreSQL constraints, triggers, RLS, or RPC functions — N/A: I2 defines no clinic
      domain data, no Supabase writes, no RLS, no RPC. This row concerns the Supabase/PostgreSQL
      layer. Per the §14 acknowledgement, the Worker is an additive, non-primary component with
      **no domain logic, no business data, and no write path into Supabase**.
- [x] Security remains authenticated, tenant-scoped, branch-scoped, permission-gated,
      auditable, and soft-delete-preserving — discovery is installation-scoped via the same AAT
      verifier as submit; granted manifests are filtered by entitlements/grants; unauthenticated
      fails closed with taxonomy `unauthenticated`; no soft-delete concept on this surface.
- [x] AI actions remain human-approved, have no direct database/backend access, and the
      feature still works in a degraded manual mode when AI is unavailable — discovery is a read
      of granted manifests; gateway unavailability never blocks clinical work (§14 "V").

The one unchecked box is the Supabase/PostgreSQL row that is structurally inapplicable to a
gateway composition slice. It is not a constitution violation; it is recorded here rather than
silently dropped, per the §14 acknowledgement.

## Project Structure

### Documentation (this feature)

```text
specs/053-discovery-http-config-readers/
├── plan.md              # This file
├── spec.md              # /ai-platform-specify + /ai-platform-clarify output (authoritative)
├── contracts/
│   └── discovery-http.md  # Frozen: GET /v1/capabilities wire (auth, ETag, Cache-Control, body)
└── quickstart.md        # Written during the implement-phase Documentation task (sections below)
```

`data-model.md` is **not** produced — spec `### Key Entities` is "Not applicable" (no new D1 entity
or contract type; A5 froze the logical model; §7.3 already names `kill_switch`). The additive
`kill_switch` migration (Clarification Q1) realises an already-architecture-defined entity so the
production reader can SELECT a present row; it is not a new logical-model Freezes entry.

`research.md` is **never** produced on this platform — the research is
`docs/architecture/ai-platform/01-ai-platform.md`.

`contracts/` is produced because the **Freezes** live capability-discovery HTTP wire has a shape
later **Consumes** (I3) must bind to — not prose.

`quickstart.md` (written during the implement-phase Documentation task, per
`.specify/templates/ai-platform-quickstart-template.md`) will contain:
- **§1 Architecture context** — I2 row of the delivery plan (§3.10) and §5.5 / §4.3.4 / §4.3.2 /
  §13.4; what the spec delivered; what the plan scoped.
- **§2 What was implemented** — `GET /v1/capabilities` handler; `createD1ConfigReader` kill_switches
  SELECT; `kill_switch` migration + schema snapshot.
- **§3 Files to review** — this slice's `src/discovery/`, `src/config-cache/` (reader branch),
  `src/worker.ts` route, migration, and the two test files.
- **§5 Run the automated suite** — `npx vitest run --config vitest.workers.config.ts
  test/discovery-http.test.ts test/config-readers.test.ts` (slice-only; 14 named tests).
- **§6 Inspect the changes** — curl/grep for `/v1/capabilities`, read
  `contracts/discovery-http.md`, confirm kill_switches SELECT in `createD1ConfigReader`.
- **§7 Manual validation** — optional `curl` against a local Worker for `GET /v1/capabilities`
  with Bearer AAT and `If-None-Match` (this slice exposes live HTTP beyond CI).

### Source Code (repository root)

```text
ai-platform/
├── migrations/
│   └── <YYYYMMDDHHMMSS>_kill_switch.sql   # NEW — additive kill_switch table (§7.3; Clarification Q1)
├── schema.snap.sql                        # MODIFIED — include kill_switch DDL
├── src/
│   ├── discovery/                         # NEW — HTTP handler (Clarification Q2)
│   │   └── index.ts                       # verify Bearer AAT → discover() → buildDiscoveryResponse
│   ├── config-cache/
│   │   └── index.ts                       # MODIFIED — kill_switches SELECT in createD1ConfigReader
│   ├── capability/                        # UNCHANGED (consumed from C1)
│   ├── identity/                          # UNCHANGED (consumed — EnrolledKeyVerifier)
│   ├── errors.ts                          # UNCHANGED (consumed — unauthenticated taxonomy)
│   └── worker.ts                          # MODIFIED — route GET /v1/capabilities
├── test/
│   ├── discovery-http.test.ts             # NEW — T1–T5 Workers integration
│   └── config-readers.test.ts             # NEW — T6–T14 Workers integration
├── vitest.workers.config.ts               # MODIFIED — include the two new test files
└── vitest.config.ts                       # MODIFIED — exclude the two new test files
```

**Structure Decision**: A dedicated `src/discovery/` handler keeps C1's `capability/` module
untouched (Consumes / delivery plan §2.3) and mirrors the journal pattern of a thin HTTP auth +
surface function (`authenticateGetRequest` precedent) without rewriting §4.3.1's submit adapter.
Shared `ConfigCache` + `createD1ConfigReader` are constructed once per request in that handler,
then passed to `EnrolledKeyVerifier.verify` and `discover()` (Clarification Q2). Production reader
completion stays in `config-cache/index.ts` where `createD1ConfigReader` already lives — only the
stub `kill_switches` branch changes from always-miss to a D1 SELECT; cache mechanics
(`ConfigCache`, `loadConfig`, TTL, single-flight) are not altered.

## Consumes Binding

| Consumes entry | Existing module / file / type it binds to | How I2 binds to it |
| --- | --- | --- |
| **A5** — config-cache contract: in-isolate map, short TTL, D1 on miss, owns nothing; D1 logical model; cold-isolate single same-region D1 read (§4.3.2, §13.4) | `ai-platform/src/config-cache/index.ts` — `ConfigCache`, `loadConfig`, `D1Reader`, `ConfigCacheMissError`, `ConfigEntityKind`, `createD1ConfigReader`, `CACHE_TTL_MS`. Frozen artifact: `specs/019-ai-context-keys-d1-config/contracts/config-cache.md`. | I2 uses the frozen cache surface unchanged. It completes the production `createD1ConfigReader` `kill_switches` branch (currently a stub miss) with a SELECT against the additive `kill_switch` table, and proves every request-path kind through that reader (T6–T14). Cache mechanics (TTL, warm/cold I/O budget, typed miss) are not redefined. |
| **C1** — `discover()` / `resolve()` library exports, discovery response shape, etag revalidation at the library boundary, entitlement-gated absence (§4.3.4, §5.5) | `ai-platform/src/capability/index.ts` — `discover`, `buildDiscoveryResponse`, `DiscoveryResult`, `computeDiscoveryEtag`. Frozen artifact: `specs/025-capability-resolver-discovery/contracts/capability-registry.md`. | I2's discovery handler calls `discover(principal, cache, reader)` then `buildDiscoveryResponse(request, manifests, etag)`. It does not re-implement filtering, etag hashing, or `If-None-Match` matching. `resolve()` is not exercised by this slice's HTTP surface. |

No consumed entry lacks an implementation. Neither consumed **contract** is rewritten (delivery plan
§2.3). Extending `createD1ConfigReader`'s kill_switches SELECT is I2's **Freezes** work (production
readers), not a change to A5's cache-mechanics contract.

## Components Touched

| §4 component | What I2 changes | Behaviour added? |
| --- | --- | --- |
| §4.3.4 Capability resolver | **Composition only** — mounts C1's existing `discover()` / `buildDiscoveryResponse` on the live §5.5 HTTP route via a new discovery handler and a `worker.ts` route. Does not change resolver/discovery library behaviour. | Yes — live HTTP reachability for discovery (the library half was C1). |
| §4.3.2 Identity and tenant resolution | **Production config-cache readers only** — completes `createD1ConfigReader` for every request-path kind the guard/resolver consult (including kill switches via the additive `kill_switch` table). Does not change AAT verification, principal construction, or identity stage ordering. | Yes — durable kill-switch rows become readable through the production reader; other kinds already SELECT and are proven by T6–T14. |

**Written reason for touching two §4 components:** Delivery plan §3.10 row **I2** deliberately
co-locates both concerns in one slice — "exposes C1's `discover()` over HTTP **and** ensures the
production config-cache D1 reader covers every entity kind" — with Canonical
`§5.5, §4.3.4, §4.3.2, §13.4` and a single Done-when cell that requires authenticated discovery HTTP
**and** production readers for all request-path kinds under A5's cold-isolate read pattern. Band I
adds no new §4 component (DP-8 / §3.10); I2 composes the two already-frozen surfaces that Done when
binds together. The discovery handler shares one cache/reader with verify + `discover()` on the
same request (Clarification Q2), so splitting the reader completion into a second slice would leave
the live route without a complete production reader for kinds the guard path already names.

§4.3.1 Protocol adapter is **not** touched — submit remains `handleAdapterRequest`; discovery is a
sibling §5.5 surface mounted beside it in `worker.ts`, not inside the adapter.

## Files

| File | Created / Modified | Traces to |
| --- | --- | --- |
| `ai-platform/src/discovery/index.ts` | Created | FR-001, FR-002, FR-003, FR-004, FR-005, FR-006 — handler: parse Bearer AAT → shared `ConfigCache` + `createD1ConfigReader` → `EnrolledKeyVerifier.verify` → `discover()` → `buildDiscoveryResponse`; unauthenticated → taxonomy `unauthenticated` body (no discovery body). |
| `ai-platform/src/worker.ts` | Modified | FR-001 — route `GET /v1/capabilities` to the discovery handler. |
| `ai-platform/src/config-cache/index.ts` | Modified | FR-007, FR-008, FR-009, FR-010 — replace kill_switches stub miss with SELECT against `kill_switch` (§7.3 keys `global` / `{scope}:{target}`); leave `ConfigCache` / `loadConfig` / other kind SELECTs unchanged. |
| `ai-platform/migrations/<YYYYMMDDHHMMSS>_kill_switch.sql` | Created | FR-007 — additive `kill_switch` table per §7.3 (Clarification Q1; not promoted to a Key Entity requirement). |
| `ai-platform/schema.snap.sql` | Modified | FR-007 — snapshot includes `kill_switch` DDL after migration (Clarification Q1). |
| `ai-platform/test/discovery-http.test.ts` | Created | SC-001, SC-002, SC-003 — T1–T5 Workers integration against live Worker fetch. |
| `ai-platform/test/config-readers.test.ts` | Created | SC-004, SC-005 — T6–T14 Workers integration (direct Miniflare D1 + reader; T13 spy). |
| `ai-platform/vitest.workers.config.ts` | Modified | — `include` adds the two new test files. |
| `ai-platform/vitest.config.ts` | Modified | — `exclude` adds the two new test files (workers-only). |
| `specs/053-discovery-http-config-readers/contracts/discovery-http.md` | Created | Freezes live discovery HTTP wire (FR-001..FR-006) so I3 binds to an artifact. |
| `specs/053-discovery-http-config-readers/quickstart.md` | Created (implement phase) | — template-mandated review surface; sections named above. |

Every code/contract file traces to an `FR-###` (or Freezes). No file is created for an unstated
requirement. Consumed modules (`capability/`, `identity/`, `errors.ts`) are unchanged aside from
imports by the new handler.

## Test Layout

The spec's `### Test plan` names fourteen Workers integration tests (delivery plan §3.12.9 I2;
§13.5 Workers / pipeline integration via Miniflare). Per Clarification Q3 they split into two
files. Per Clarification Q4, T6–T12 and T14 use direct Miniflare D1 + `createD1ConfigReader` /
`loadConfig` (discovery HTTP does not consult every kind). Per Clarification Q5, T13 spies /
wraps `D1Reader.read` around `createD1ConfigReader`.

| Spec Test plan name | Test id | File | §13.5 layer | Asserts (FR / SC) |
| --- | --- | --- | --- | --- |
| `discovery_http_granted_active_manifests` | T1 | `test/discovery-http.test.ts` | Workers integration | FR-001, FR-004, FR-006 / SC-001 — enrolled installation + valid AAT → only granted effective-`active`/`deprecated` manifests; no capability id required. |
| `discovery_http_etag_not_modified` | T2 | `test/discovery-http.test.ts` | Workers integration | FR-003 / SC-002 — matching `If-None-Match` → 304; `Cache-Control: private, must-revalidate`. |
| `discovery_http_changed_manifest_changes_etag` | T3 | `test/discovery-http.test.ts` | Workers integration | FR-003 / SC-002 — changed granted set → different `ETag`. |
| `discovery_http_ineligible_plan_capability_absent` | T4 | `test/discovery-http.test.ts` | Workers integration | FR-004 / SC-001 — entitlement-gated capability absent for ineligible plan (not an error code). |
| `discovery_http_unauthenticated` | T5 | `test/discovery-http.test.ts` | Workers integration | FR-002, FR-005 / SC-003 — missing/invalid AAT → taxonomy `unauthenticated`; no manifest body. |
| `config_reader_presence_installation` | T6 | `test/config-readers.test.ts` | Workers integration | FR-007 / SC-004 — present installation row via production reader. |
| `config_reader_presence_keys` | T7 | `test/config-readers.test.ts` | Workers integration | FR-007 / SC-004 — present keys row via production reader. |
| `config_reader_presence_entitlements` | T8 | `test/config-readers.test.ts` | Workers integration | FR-007 / SC-004 — present entitlement via production reader. |
| `config_reader_presence_grants_lifecycle_overlay` | T9 | `test/config-readers.test.ts` | Workers integration | FR-007 / SC-004 — present grants / lifecycle overlay via production reader. |
| `config_reader_presence_kill_switches` | T10 | `test/config-readers.test.ts` | Workers integration | FR-007 / SC-004 — present kill_switch row via production reader. |
| `config_reader_presence_active_routing_policy` | T11 | `test/config-readers.test.ts` | Workers integration | FR-007 / SC-004 — present active routing policy via production reader. |
| `config_reader_presence_token_contract` | T12 | `test/config-readers.test.ts` | Workers integration | FR-007 / SC-004 — present `token_contract` accepted-`ver` via production reader. |
| `config_reader_cold_isolate_single_d1_read_pattern` | T13 | `test/config-readers.test.ts` | Workers integration | FR-008 / SC-005 — spy on `D1Reader.read` around `createD1ConfigReader`: cold load performs A5's single read pattern. |
| `config_reader_miss_typed_failure_not_silent_admit` | T14 | `test/config-readers.test.ts` | Workers integration | FR-009 / SC-005 — miss → `ConfigCacheMissError`, not empty grant admit. |

Every named test places in a §13.5 layer — stop condition 3 not triggered.

## Sequencing

Tests land first or alongside their implementation, never after (delivery plan §2.2).

1. **Migration + snapshot (FR-007; Clarification Q1)** — additive `kill_switch` migration and
   `schema.snap.sql` update so the production reader has a table to SELECT.
2. **Production reader kill_switches SELECT (FR-007, FR-009)** — replace the stub in
   `createD1ConfigReader`; land **T10**, **T6–T9**, **T11–T12**, **T14** alongside (direct D1 +
   `loadConfig`).
3. **Cold-isolate spy (FR-008)** — **T13** with spy/wrapper on `D1Reader.read` around
   `createD1ConfigReader` (Clarification Q5).
4. **Discovery handler + worker route (FR-001..FR-006; Clarification Q2)** — shared cache/reader,
   verify then `discover()` then `buildDiscoveryResponse`; land **T1–T5** alongside against Worker
   fetch.
5. **Contract** — `contracts/discovery-http.md` written alongside the handler (Freezes the live
   wire for I3).
6. **Documentation** — `quickstart.md` last, during the implement-phase Documentation task, after
   the slice's tests pass.

Steps 2–4 interleave tests with implementation; no test is written after its code. Documentation
artifacts (step 6) fill after the suite is green — the plan names them here.

## Complexity Tracking

> Not filled — no Constitution Check violation requires justification. The one unchecked
> Constitution box is recorded above as structurally inapplicable to a gateway composition slice
> (per the §14 acknowledgement), not as a violation.
