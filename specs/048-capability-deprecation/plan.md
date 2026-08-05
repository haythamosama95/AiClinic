# Implementation Plan: Capability deprecation and the overlap window (J1)

**Branch**: `ai/048-j1-capability-deprecation` | **Date**: 2026-08-02 | **Spec**: [`spec.md`](./spec.md)

**Input**: Feature specification from `specs/048-capability-deprecation/spec.md`

**Note**: This template is filled in by the `/ai-platform-plan` command. See `.specify/templates/plan-template.md` for the execution workflow.

## Summary

J1 adds the deferred compatibility behaviour for capability versions: operator deprecate / retire
mutations persist a `global`-scope `capability_grant` lifecycle overlay (never editing a published
manifest), discovery announces deprecation with a successor before retirement is enforced, a
deprecated pin keeps serving for the configured overlap window (OD-9 / A12), and after retirement
the same pin returns `capability_retired` with the retire mutation journaled on `control_audit`. It
sits in band J after C1 and B2 (`Needs: C1, B2`); build when a client version exists that a capability
change could break (delivery plan §3.9 row J1; DP-5).

## Technical Context

**Language/Version**: TypeScript 5.9 in the Cloudflare Worker (`ai-platform/`), `target: ES2022`,
strict, `@cloudflare/workers-types` — matching C1/B2.

**Primary Dependencies**: existing `ai-platform/src/capability/` (C1 — `resolve`, `discover`,
registry, `ResolveResult` / `DiscoveryResult`), `ai-platform/src/control/` (B2 — `OperatorAuth`,
`writeAudit` pattern, `dispatchControlRequest`), `ai-platform/src/config-cache/` (A5 —
`ConfigCache`, `loadConfig`, `D1Reader`, kind `"grants"`), `ai-platform/src/manifest/` (A4 —
immutable `Manifest`, `hashManifest`). No new runtime dependency; no schema-validation or
HTTP-framework library (R-20).

**Storage**: Platform D1 only. J1 writes lifecycle overlay fields onto existing `capability_grant`
rows at `scope = 'global'` and writes `control_audit` rows for deprecate / retire (B2 Freezes). One
**forward-only additive migration** adds nullable overlay columns
(`lifecycle_state`, `successor_id`, `deprecated_at`, `retire_after`) to `capability_grant` because
A5's shipped schema predates the §5.1 / §7.3 lifecycle-overlay amendment (delivery plan §3.9 band J
note; §13.4). No new table. Manifests remain bundled content-immutable (A4/C1). No R2, Quota DO, or
Supabase write.

**Testing**: `npx vitest run --config vitest.workers.config.ts test/capability-deprecation.test.ts`
— Integration / Pipeline layer (delivery plan §3.11.8 row J1; §13.5 Pipeline tests). Real Miniflare
D1 (`d1Databases: ["DB"]`), A5 migration plus J1 additive migration applied in setup, C1 registry
fixtures, B2-style fake `OperatorAuth`. Slice-only; suite joins CI permanently (§3.10). The file is
registered in **both** harness configs — added to `vitest.workers.config.ts` `include` and to
`vitest.config.ts` `exclude` — so the default Node pool's `test/**/*.test.ts` glob does not load a
Miniflare-D1 test and `npx vitest run` (§3.10) stays green (C1/C3/B2/H3 precedent).

**Target Platform**: the `ai-platform/` Cloudflare Worker at the repository root (sibling of
`frontend/` and `backend/`). Control-plane mutate path plus stage-5 resolve / discovery reads; no
Flutter or Supabase domain path.

**Project Type**: Additive, non-primary AI gateway component (§14 acknowledgement) — no domain
logic, no business data, no write path into Supabase, always optional.

**Performance Goals**: Off the Quota DO / R2 budgets (deprecate / retire are operator-rare control
mutations). Request-path resolve / discovery read the overlay through the existing config cache
alongside grants and kill switches (§6.1 stage 5; FR-010) — no second D1 round trip on a warm
isolate, no per-request server-side state (§4.4, §9.7). Guard rejection as `capability_retired`
produces no `ai_request` row (C1 / C3 invariant; consumed, not re-built).

**Constraints**:
- Manifest content and content hash never change for a lifecycle transition (FR-009; §5.1).
- Effective lifecycle = published Identity value, overridden by global-scope overlay when present
  (§5.1; §7.3).
- `deprecated` remains servable for the overlap window; only `retired` rejects with
  `capability_retired` (C1 Freezes taxonomy; FR-001, FR-004, FR-005).
- Overlap window length is the OD-9 default: two client release cycles, minimum 90 days — a named
  constant, not a configuration surface (FR-007; R-20).
- Retirement is an operator mutation after announcement and after `retire_after`; the request path
  does not auto-trip retirement on a clock (§7.3).
- Deprecate is one-directional: reject after retire; idempotent same-successor duplicate; never
  silently restart `deprecated_at` / `retire_after`. Target version and successor must exist in the
  registry before any overlay write.
- Production request-path enforcement of overlays requires a `D1Reader` that handles `grants`
  including `global/{id}/{version}` (contract §2.4 handoff) — not introduced by rewriting
  `createD1ConfigReader` in this slice.
- No rewrite of C1 registry lookup semantics, the three resolver codes, or B2 enroll / rotate /
  suspend / resume / delete / `control_audit` shape (delivery plan §2.3).
- No mechanism from §9.14; no Flutter update UX beyond returning `capability_retired` (spec Out of
  Scope).

**Scale/Scope**: Two §4 components (§4.3.4 Capability resolver and §4.5 Control plane) — see
**Components Touched** for the written reason. One additive migration, extensions to
`src/capability/` and `src/control/`, one new integration test file, one contract artifact, one
named quickstart. Roughly 12–16 tasks (under the ~25 ceiling of delivery plan §6.3 / plan stop
condition 5).

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- [x] Feature scope still fits small-to-mid-size multi-branch clinics; hospital-scale or
      enterprise-only requirements are explicitly rejected or separately ratified — overlap window
      keeps clinic-schedule desktop clients working without enterprise rollout machinery
      (constitution I; A12; spec Clinic Fit).
- [x] Design keeps a simple operational model with no microservices, message queues,
      Kubernetes, or custom primary backend service — additive columns on an existing D1 table,
      two control mutations, and overlay reads through the existing config cache; no new service.
- [x] Layer ownership is explicit: Flutter handles UI/orchestration, Supabase handles
      backend capabilities, PostgreSQL owns domain integrity, and AI stays isolated — J1 lives
      wholly in `ai-platform/`; no Flutter surface; no Supabase write.
- [ ] (intentionally unchecked — see note) Protected writes, validation, permissions, and
      transactional rules remain enforced through PostgreSQL constraints, triggers, RLS, or RPC
      functions — N/A: J1 writes the platform's **own** D1 (`capability_grant` overlay,
      `control_audit`), not clinic Supabase. Integrity is the additive migration's columns plus
      B2's operator-authenticated audit rule. This row concerns the Supabase/PostgreSQL layer.
- [x] Security remains authenticated, tenant-scoped, branch-scoped, permission-gated,
      auditable, and soft-delete-preserving — deprecate / retire are operator-authenticated (B2
      `OperatorAuth`, not clinic identity); every mutation writes `control_audit` with the
      operator identity (FR-008); request-path retirement uses the existing taxonomy code; no
      hard-delete of clinic data.
- [x] AI actions remain human-approved, have no direct database/backend access, and the
      feature still works in a degraded manual mode when AI is unavailable — after retirement,
      pinned requests degrade to `capability_retired` (prompt-for-update) rather than opaque
      failure; gateway unavailability never blocks clinical work (constitution V; A11; §14).

**§14 acknowledgement (gateway slice):** The Worker is an additive, non-primary component with no
domain logic, no business data, and no write path into Supabase. J1 only extends platform D1
lifecycle overlay + control audit and stage-5 / discovery reads of that overlay.

The one unchecked box is the Supabase/PostgreSQL-enforcement row that is structurally inapplicable
to a gateway D1 control / resolve slice. It is not a constitution violation; it is recorded here
rather than silently dropped.

## Project Structure

### Documentation (this feature)

```text
specs/048-capability-deprecation/
├── plan.md              # This file
├── spec.md              # /ai-platform-specify (+ clarify) output (authoritative)
├── contracts/
│   └── capability-deprecation.md  # Freezes: overlay fields, deprecate/retire surface,
│                                  # discovery successor announcement, overlap default
└── quickstart.md        # Written during the implement-phase Documentation task (sections below)
```

`data-model.md` is **not** produced — J1 defines **no new D1 entity** (spec Key Entities). It adds
overlay columns to A5's `capability_grant` by forward-only migration; those column shapes and the
effective-lifecycle rule are frozen in `contracts/capability-deprecation.md` so later slices bind to
an artifact without rewriting A5's `specs/019-…/data-model.md` (delivery plan §2.3).

`research.md` is **never** produced on this platform — the research is
`docs/architecture/17-ai-platform.md`.

`contracts/` **is** produced — Freezes entries have wire / table shapes (overlay columns, deprecate /
retire control routes and `control_audit.action` extensions, discovery announcement of deprecated +
successor, overlap-window constant) that later slices' **Consumes** must bind to.

`quickstart.md` (written during the implement-phase Documentation task, per
`.specify/templates/ai-platform-quickstart-template.md`) will contain:
- **§1 Architecture context** — J1 row of the delivery plan (§3.9) and Implements (§5.7, §12.4,
  A12); what the spec delivered; what the plan scoped.
- **§2 What was implemented** — additive `capability_grant` overlay migration; control-plane
  deprecate / retire; resolve / discovery overlay reads; OD-9 overlap constant.
- **§3 Files to review** — this slice's migration, `src/capability/index.ts` diff,
  `src/control/index.ts` diff, `test/capability-deprecation.test.ts`,
  `contracts/capability-deprecation.md`.
- **§4 Prerequisites** — Miniflare D1 workers pool (`vitest.workers.config.ts`); one-time
  `npm install` in `ai-platform/`.
- **§5 Run the automated suite** —
  `npx vitest run --config vitest.workers.config.ts test/capability-deprecation.test.ts`
  (slice-only).
- **§6 Inspect the changes** — grep overlay columns / `deprecate`/`retire` actions; read the
  frozen contract; confirm manifests unchanged after a lifecycle mutation.
- No **§7 Manual validation** — CI is the only verification path beyond the suite.

### Source Code (repository root)

```text
ai-platform/
├── migrations/
│   ├── 20260731120000_platform_schema.sql          # A5 — unchanged (consumed)
│   └── 20260802100000_capability_grant_lifecycle.sql  # NEW — additive overlay columns (FR-009)
├── schema.snap.sql                                 # MODIFIED — reflect additive columns
├── src/
│   ├── capability/
│   │   └── index.ts                                # MODIFIED — effective lifecycle via grants
│   │                                               #   overlay; discovery announces deprecated
│   │                                               #   + successor (FR-001..007, FR-010)
│   ├── control/
│   │   └── index.ts                                # MODIFIED — deprecate / retire handlers +
│   │                                               #   audit + dispatch (FR-008, FR-009)
│   ├── config-cache/                               # UNCHANGED — reuse kind "grants"
│   ├── manifest/                                   # UNCHANGED — content immutability
│   └── worker.ts                                   # MODIFIED — /control capability routes
├── test/
│   └── capability-deprecation.test.ts              # T-J1-01 .. T-J1-20 (Pipeline + review branches)
├── vitest.workers.config.ts                        # MODIFIED — include the new test file
└── vitest.config.ts                                # MODIFIED — exclude the new test file from
                                                    #   the default Node pool (paired with the
                                                    #   workers-pool include; C1/C3/B2/H3 pattern)
```

**Structure Decision**: Extend C1's `src/capability/` and B2's `src/control/` in place (same
`index.ts` pattern as prior slices). Lifecycle overlay rows are read through the existing
`"grants"` config-cache kind with a `global/{capabilityId}/{version}` key — no new
`ConfigEntityKind` and no rewrite of A5's config-cache contract. One new workers-pool test file
mirrors B2/C1 integration style. Manifests stay in the bundled registry; only D1 overlay + audit
rows are written.

## Consumes Binding

| Consumes entry | Existing module / file / type it binds to | How J1 binds to it |
| --- | --- | --- |
| **C1** — capability-registry lookup (id + version → immutable manifest honouring the pin); three resolver codes (`capability_unknown`, `capability_retired`, `capability_disabled`); `deprecated` is not a rejection; discovery surface | `ai-platform/src/capability/index.ts` — `resolve`, `discover`, `CapabilityRegistry`, `ResolveResult`, `DiscoveryResult`. Frozen artifact: `specs/025-capability-resolver-discovery/contracts/capability-registry.md`. | J1 **extends** resolve / discover to apply the global-scope lifecycle overlay via `loadConfig(..., "grants", …)` (FR-010). It does **not** change registry key format, the three taxonomy codes, kill-switch rejection, or manifest immutability of registry entries. Discovery filtering is extended (may extend, never rewrite) so effective-`deprecated` versions appear with successor; C1's contract file is not edited. |
| **B2** — operator-authenticated control-plane surface; every mutation journaled as `control_audit` with operator identity | `ai-platform/src/control/index.ts` — `OperatorAuth`, `OperatorPrincipal`, `dispatchControlRequest`, audit insert pattern; `ai-platform/src/worker.ts` `/control` dispatch. Frozen artifact: `specs/022-control-plane-enrollment/contracts/control-plane.md`. | J1 **extends** the control plane with deprecate / retire Capability-availability mutations (§4.5; §12.4) that reuse `OperatorAuth` and write `control_audit` with new `action` values `deprecate` / `retire` (B2 explicitly allows later slices to extend the action vocabulary). It does **not** redefine enroll / rotate / suspend / resume / delete or the `control_audit` row shape. B2's contract file is not edited. |

No consumed entry lacks an implementation. None of the frozen Consumes contracts is rewritten
(delivery plan §2.3).

## Components Touched

| §4 component | What J1 changes | Behaviour added? |
| --- | --- | --- |
| §4.3.4 Capability resolver | **Extended** — effective lifecycle from global-scope `capability_grant` overlay via config cache; discovery announces deprecated + successor; deprecated pin still serves inside the window; retired pin returns `capability_retired`. | Yes — C1 deferred overlap window and successor announcement to J1. |
| §4.5 Control plane | **Extended** — Capability availability deprecate / retire mutations at global scope; `control_audit` with operator identity; sets overlay fields including `deprecated_at` / `retire_after`. | Yes — §12.4 Retire a capability is enacted here. |

**Written reason for touching two §4 components:** J1's Done when and §12.4 "Retire a capability"
require both halves of one recipe: (1) control-plane Capability-availability mutations that persist
the lifecycle overlay and `control_audit`, and (2) capability resolve / discovery that read that
overlay and announce / enforce it. Delivery plan §3.9 Needs are exactly `C1, B2`; the band J note
places the durable write on `capability_grant` via the control plane while C1 deferred window /
successor behaviour. Neither component alone satisfies the slice. Stop condition 5 is satisfied by
this reason; task count stays ~12–16.

No other §4 component is touched (journal / Quota DO / R2 / Flutter / providers unchanged).

## Files

| File | Created / Modified | Traces to |
| --- | --- | --- |
| `ai-platform/migrations/20260802100000_capability_grant_lifecycle.sql` | Created | FR-009 — `ALTER TABLE capability_grant ADD` nullable `lifecycle_state`, `successor_id`, `deprecated_at`, `retire_after`. |
| `ai-platform/schema.snap.sql` | Modified | FR-009 — snapshot matches post-migration `capability_grant` shape. |
| `ai-platform/src/capability/index.ts` | Modified | FR-001, FR-002, FR-003, FR-004, FR-005, FR-006, FR-007, FR-010 — `effectiveLifecycle(manifest, overlay)`; resolve rejects only effective `retired`; serves effective `deprecated`; discovery includes granted effective-`active` **and** effective-`deprecated` (with successor) and excludes effective `retired`; overlay loaded through `loadConfig("grants", "global/{id}/{version}")`; registry / published manifest bytes untouched; registry lookup helpers for control validation. |
| `ai-platform/src/control/capability-lifecycle.ts` | Modified | FR-008, FR-009 — deprecate state guard; registry/successor validation; epoch-ms window compare; overlay `revoked_at`; audit `after_pointer` successor. |
| `ai-platform/src/control/index.ts` | Modified | FR-008, FR-009 — `handleDeprecate` / `handleRetire`; append-only global-scope `capability_grant` overlay row; `control_audit` actions `deprecate` / `retire`; refuse retire without prior announced deprecation (successor set) or before `retire_after` (FR-002, FR-005, FR-007); `dispatchControlRequest` routes. |
| `ai-platform/src/worker.ts` | Modified | FR-008 — dispatch new `/control/capabilities/...` paths to control handlers (same `/control` boundary B2 froze). |
| `ai-platform/test/capability-deprecation.test.ts` | Created | SC-001..SC-005 — named tests T-J1-01 .. T-J1-05 plus review-resolution branches T-J1-06 .. T-J1-20. |
| `ai-platform/vitest.workers.config.ts` | Modified | — `include` adds `test/capability-deprecation.test.ts`. |
| `ai-platform/vitest.config.ts` | Modified | — `exclude` adds `test/capability-deprecation.test.ts` so the default Node pool does not load a Miniflare-D1 test picked up by `include: ["test/**/*.test.ts"]`; required for §3.10 `npx vitest run` to stay green. Every prior D1 workers-pool slice (C1, C3, B2, H3) pairs the workers-config `include` with this `exclude`. |
| `specs/048-capability-deprecation/contracts/capability-deprecation.md` | Created | Freezes overlay column shape, effective-lifecycle rule, deprecate/retire HTTP + audit vocabulary, discovery announcement, OD-9 overlap constant (FR-001..FR-010 Freezes). |
| `specs/048-capability-deprecation/quickstart.md` | Created (implement phase) | — template-mandated review surface; sections named above. Not traced to an FR. |

Every code/contract file traces to an `FR-###`. Consumed modules' frozen contracts
(`capability-registry.md`, `control-plane.md`, `config-cache.md`, A5 `data-model.md`) are **not**
modified. No untraced file.

## Test Layout

The spec's Test plan names five tests at §13.5 **Pipeline tests** (delivery plan §3.11.8 J1 layer
**Integration** → stage ordering / guard rejection at capability resolve). All five live in
`ai-platform/test/capability-deprecation.test.ts` under `vitest.workers.config.ts` (real D1 +
control mutations + resolve/discover).

| Spec Test plan name | Test id | §13.5 layer | Config | Asserts (FR / SC) |
| --- | --- | --- | --- | --- |
| Discovery marks a deprecated version with its successor | T-J1-01 | Pipeline tests | `vitest.workers.config.ts` | FR-002, FR-003 / SC-001 — after `deprecate` with successor, `discover()` for an entitled installation includes that version with effective `deprecated` and the successor id. |
| A deprecated version still serves inside the overlap window | T-J1-02 | Pipeline tests | `vitest.workers.config.ts` | FR-001, FR-004, FR-006, FR-007 / SC-002 — pin to the deprecated version inside the window (`now < retire_after`, state `deprecated`) → `resolve()` `{ ok: true, manifest }`. |
| After retirement the same pinned request returns `capability_retired` | T-J1-03 | Pipeline tests | `vitest.workers.config.ts` | FR-005 / SC-003 — after `retire`, same pin → `{ ok: false, code: "capability_retired" }` (not opaque). |
| Retirement is journaled with the operator identity (`control_audit`) | T-J1-04 | Pipeline tests | `vitest.workers.config.ts` | FR-008 / SC-004 — retire writes `control_audit` with that operator id and action `retire`. |
| Lifecycle transition survives a cold isolate; manifest unchanged | T-J1-05 | Pipeline tests | `vitest.workers.config.ts` | FR-009, FR-010 / SC-005 — after deprecate (or retire), a fresh `ConfigCache` (cold isolate) reconstructs lifecycle via `loadConfig("grants", …)` for discovery and resolve; published manifest content / `hashManifest` unchanged. |

Coverage from §3.10: the only error code this slice's retirement path emits is `capability_retired`
(T-J1-03); unknown / disabled remain C1's. Branches: announce-before-enforce (T-J1-01 before
T-J1-03), deprecate-vs-retire (T-J1-02 vs T-J1-03), cold-isolate reconstruction (T-J1-05), audit
identity (T-J1-04). Inherited prohibitions (no per-request state; no guard-rejection `ai_request`
row) are consumed from C1/C3 and not re-asserted here.

Every named test places in a §13.5 layer — stop condition 3 not triggered.

## Sequencing

Tests land first or alongside implementation, never after (delivery plan §2.2):

1. **Migration (FR-009)** — additive SQL + `schema.snap.sql` update so D1 accepts overlay columns.
2. **Overlay read helper + resolve/discover (FR-001..007, FR-010)** — T-J1-02 / T-J1-03 unit of
   behaviour against seeded global grant rows (before or with control handlers); then T-J1-01
   discovery announcement; then T-J1-05 cold-cache reconstruction.
3. **Control-plane deprecate / retire (FR-008, FR-009)** — handlers + routes; T-J1-01 and T-J1-04
   driven through the mutation path; retire gates (prior successor announcement; `retire_after`).
4. **Contract** — `contracts/capability-deprecation.md` written alongside the module surface.
5. **Documentation** — `quickstart.md` last, during the implement-phase Documentation task, after
   the slice's tests pass.

## Complexity Tracking

> Not filled — no Constitution Check violation requires justification. The one unchecked
> Constitution box is recorded above as structurally inapplicable to a gateway D1 slice (per the
> §14 acknowledgement), not as a violation.
