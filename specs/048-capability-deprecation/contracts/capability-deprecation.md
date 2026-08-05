# Contract: Capability deprecation and the overlap window (J1)

**Frozen by:** Slice J1 — Capability deprecation and the overlap window
**Implements:** §5.7, §12.4, A12 of `docs/architecture/17-ai-platform.md`; Open Decision 9
**Status:** Frozen. Later slices **may extend, never rewrite** the overlay column set, the
effective-lifecycle rule, the deprecate / retire control surface and `control_audit.action`
values added here, the discovery announcement of deprecated + successor, or the OD-9 overlap
default (delivery plan §2.3).

**Source of truth in code:** `ai-platform/src/control/index.ts` (deprecate / retire);
`ai-platform/src/capability/index.ts` (effective lifecycle, discovery announcement);
`ai-platform/migrations/20260802100000_capability_grant_lifecycle.sql`.

**Traces to:** FR-001 … FR-010; spec Freezes. Consumes C1
(`specs/025-capability-resolver-discovery/contracts/capability-registry.md`) and B2
(`specs/022-control-plane-enrollment/contracts/control-plane.md`) without rewriting them.

---

## 1. Overview

J1 freezes the runtime compatibility path for capability versions:

1. Deprecate and retire persist as a **`global`-scope `capability_grant` lifecycle overlay** —
   never by editing or republishing a manifest (§5.1; §7.3; §12.4).
2. Discovery **announces** deprecation with a **successor** before retirement is enforced (§5.7).
3. A deprecated pin remains **servable** for the configured overlap window (A12; OD-9).
4. After retirement, the same pin returns **`capability_retired`** (C1 taxonomy code, unchanged).
5. Each mutate path writes **`control_audit`** with the operator identity (B2 Freezes applied).

---

## 2. Lifecycle overlay on `capability_grant`

### 2.1 Additive columns

A5's `capability_grant` table gains four nullable columns via forward-only migration (no new
table):

| Column | Type | Nullable | Meaning |
| --- | --- | --- | --- |
| `lifecycle_state` | TEXT | Yes | Overlay state: `active`, `deprecated`, or `retired`. Absent → manifest published value stands. |
| `successor_id` | TEXT | Yes | Successor capability id (with version identity as published by the operator). |
| `deprecated_at` | TEXT | Yes | ISO-8601 instant when deprecation started the overlap window. |
| `retire_after` | TEXT | Yes | ISO-8601 instant at or after which retirement may be enforced. |

Existing A5 columns (`grant_id`, `scope`, `capability_id`, `capability_version`, `granted_at`,
`revoked_at`, `changed_at`, `changed_by`) are unchanged.

### 2.2 Scope and append-only writes

| Mutation | `scope` value | Durability |
| --- | --- | --- |
| Deprecate | `global` | Insert a new `capability_grant` row (append-only history) with overlay fields set; `changed_by` = operator id. |
| Retire | `global` | Insert a new row transitioning overlay `lifecycle_state` to `retired`. |

Lifecycle-overlay rows are **not** live grants. Writers stamp `revoked_at = changed_at` (and
`granted_at = changed_at` because A5's `granted_at` is `NOT NULL`) so any future reader that filters
`revoked_at IS NULL` without scoping excludes overlay history. Overlay readers key
`scope = 'global'` + id/version and do not require `revoked_at IS NULL`.

Plan- or installation-scoped grant / gate rows are out of this contract (Entitlement management /
other slices). Lifecycle is a property of the capability version, not of one tenant (§7.3).

### 2.3 Effective lifecycle rule

```
effective = overlay present ? overlay : published Manifest.Identity
```

| Reader | Uses |
| --- | --- |
| `resolve()` | Effective state: `retired` → `{ ok: false, code: "capability_retired" }`; `deprecated` → serve (not a rejection); `active` → serve when not kill-switched. |
| `discover()` | Includes a granted version when effective state is `active` **or** `deprecated`; for `deprecated`, the discovery view carries effective `lifecycleState` and `successorId`. Effective `retired` is excluded. |

Published manifest bytes and their content hash **never** change for a lifecycle transition
(FR-009; §5.1). Discovery may return a **derived** Identity view with overlay applied; the
registry entry remains the A4-frozen published manifest.

### 2.4 Config-cache read path

Overlay rows are read through A5's existing `"grants"` `ConfigEntityKind` (no new kind):

| Kind | Key | D1 source |
| --- | --- | --- |
| `grants` | `global/{capabilityId}/{version}` | Current (latest `changed_at`) `capability_grant` row with `scope = 'global'` for that id + version |

Cold isolates reconstruct lifecycle from D1 via `loadConfig` exactly as for grants and kill
switches (§6.1 stage 5; FR-010).

**Production-reader dependency (handoff):** FR-010's config-cache path requires a production
`D1Reader` that handles kind `grants`, including the `global/{capabilityId}/{version}` key form.
Today's `createD1ConfigReader` only covers `installations` / `keys` / `token_contracts` and returns
`"miss"` for `grants`. Slice tests supply a grants-aware reader. The slice that wires the request
pipeline MUST NOT ship the miss-everything reader for capability resolve/discover — extend or
compose a reader that loads global overlays before enforcing retirement in production.

---

## 3. Overlap window default (Open Decision 9)

| Constant | Value | Notes |
| --- | --- | --- |
| Configured overlap window | Two client release cycles, **minimum 90 days** | Recommended default of §15 OD-9 / A12; named constant in Worker code — not a configuration surface (R-20). |

On deprecate, `deprecated_at` is the mutation instant and `retire_after` is
`deprecated_at + overlap window`. The request path does **not** auto-retire when the clock
passes `retire_after`; retirement is the operator `retire` mutation (§7.3).

---

## 4. Control-plane surface (extends B2)

Authenticated by B2's `OperatorAuth` (operator identity, not clinic identity). Rejections use
B2's non-taxonomy JSON `{ "error": "<reason>" }` pattern — no new §5.4 codes.

### 4.1 Routes

| Route | Handler | D1 writes |
| --- | --- | --- |
| `POST /control/capabilities/{capability_id}/versions/{version}/deprecate` | `handleDeprecate` | `capability_grant` (global overlay), `control_audit` |
| `POST /control/capabilities/{capability_id}/versions/{version}/retire` | `handleRetire` | `capability_grant` (global overlay), `control_audit` |

### 4.2 Deprecate request body

| Field | Required | Purpose |
| --- | --- | --- |
| `successor_id` | yes | Successor capability identity announced through discovery |

Deprecate **requires** (before any D1 write):

1. `{capability_id}@{version}` exists in the in-memory capability registry (`404 capability_not_found`).
2. Non-empty `successor_id` (`400 missing_successor_id`).
3. `successor_id` is a known registry identity — either `capabilityId@version` or a `capabilityId`
   that has at least one registered version (`400 unknown_successor`).

Deprecate **state guard** (one-directional lifecycle — §5.7 / §12.4):

| Latest global overlay | Behaviour |
| --- | --- |
| `retired` | `409 already_retired` — no write (retirement is terminal; deprecate must not resurrect). |
| `deprecated` with the **same** `successor_id` | Idempotent `200` — no new overlay row; do not reset `deprecated_at` / `retire_after`. |
| `deprecated` with a **different** `successor_id` | `409 already_deprecated` — no write. |
| Absent / non-deprecated | Insert overlay as below. |

### 4.3 Retire request body

Empty JSON object `{}`. Retire **requires**:

1. `{capability_id}@{version}` exists in the registry (`404 capability_not_found`).
2. A prior global overlay with `lifecycle_state = deprecated` and a non-empty `successor_id`
   (announcement before enforcement — FR-002; §5.7) — else `400 not_deprecated`.
3. Current time `>= retire_after` compared as **epoch milliseconds** via `Date.parse` (window
   elapsed — FR-005; FR-007). Unparseable `retire_after` → `400 overlap_window_active`.

### 4.4 Extended `control_audit.action` vocabulary

B2 froze `enroll` / `rotate` / `suspend` / `resume` / `delete`. J1 **extends** (does not rewrite)
with:

| `action` | Mutation | `target` | `after_pointer` (extension) |
| --- | --- | --- | --- |
| `deprecate` | Mark capability version deprecated with successor | `{capability_id}@{version}` | Successor id announced on the overlay |
| `retire` | Retire capability version after the overlap window | `{capability_id}@{version}` | Successor id carried from the deprecate overlay |

`target` keeps the B2-compatible `{id}@{version}` shape. `after_pointer` records the successor so
`control_audit` alone answers “deprecated / retired in favour of what” (§7.3). Every row carries
`operator_id` from the resolved operator principal (FR-008).

---

## 5. Discovery announcement

When an installation is entitled to a capability version whose **effective** lifecycle is
`deprecated`, `discover()` includes that version in `manifests` with:

| Field (effective Identity) | Value |
| --- | --- |
| `lifecycleState` | `deprecated` |
| `successorId` | Overlay (or published) successor id |

Retirement is not enforced until after this announcement path has been used (§5.7; Freezes).
Etag computation continues to hash the discovery set (including effective Identity), so a
deprecation announcement invalidates client caches.

---

## 6. Resolve after retirement

After a successful retire mutation, `resolve(principal, capabilityId, version, …)` for that pin
returns:

```typescript
{ ok: false, code: "capability_retired" }
```

No other taxonomy code is introduced. Opaque failure is forbidden (FR-005; §12.4). A
guard rejection at resolve produces no `ai_request` journal row (C1 / C3 invariant).

---

## 7. Explicit non-goals

- Editing or republishing a capability manifest for lifecycle change.
- Auto-retirement by a request-path clock.
- New `ConfigEntityKind` or new D1 entity.
- Rewriting C1's three resolver codes or B2's five installation-lifecycle actions.
- Flutter update UX beyond returning `capability_retired`.
- J2 / J3 / J4 behaviour.
