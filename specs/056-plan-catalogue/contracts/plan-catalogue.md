# Contract: Plan catalogue, assignment, override, and cache kind `plans` (G1)

**Frozen by:** Slice G1 — Plan catalogue and credit-denominated entitlement
**Implements:** §4.5, §7.3, §4.3.2, A15 of `docs/architecture/ai-platform/01-ai-platform.md`
**Status:** Frozen. Later slices may **extend** this contract; they may not **rewrite** it
(Delivery Plan §2.3).

**Source of truth in code:**
- D1: `ai-platform/migrations/20260911120000_plan_catalogue.sql`
- Control: `ai-platform/src/control/plan.ts` (CRUD); `ai-platform/src/control/entitle.ts`
  (`handleEntitle` assign-plan, `handleOverride`); `ai-platform/src/control/index.ts` (routes)
- Config cache kind: `ai-platform/src/config-cache/index.ts` (`"plans"`)

**Traces to:** spec FR-001–FR-018; Freezes in `spec.md` Slice Contract.

**Entity binding:** [`../data-model.md`](../data-model.md)

B2 `specs/022-control-plane-enrollment/contracts/control-plane.md` and A5
`specs/019-ai-context-keys-d1-config/contracts/config-cache.md` are **not** rewritten.

---

## 1. Overview

G1 freezes four cooperating surfaces:

1. The `plan` row shape and operator plan CRUD.
2. Plan-based entitlement assignment (extends I4 `POST /control/installations/{id}/entitle`).
3. Per-installation override as a distinct Entitlement-management mutation.
4. Config-cache kind `"plans"` with the A5 warm/cold I/O budget.

`credit_price` is frozen separately in [`credit-price.md`](./credit-price.md).

---

## 2. `plan` row shape

| Field | Meaning |
| --- | --- |
| `name` | Plan name (PK); matches `entitlement.plan` |
| `credit_budget` | Monthly credit budget |
| `request_quota` | Request-count guard |
| `max_cost_class` | Cost-class ceiling |
| `soft_threshold` | Soft-limit threshold |
| `allowed_capabilities` | Capability set (JSON array text) |
| `status` | Persisted TEXT; no closed enum in this slice |

---

## 3. HTTP surface (operator-authenticated)

All routes are `POST` only, dispatched through B2 `dispatchControlRequest`. Operator auth is
B2 `OperatorAuth` / `requireOperator`. Missing credentials → **`401` `{"error":"unauthorized"}`**
and **no** D1 write (no new diagnostic code; Consumes B2).

Malformed JSON → B2 `400 invalid_json`. Missing/invalid fields → B2 `400 invalid_payload`.

### 3.1 Plan CRUD

| Route | Handler | D1 writes | `control_audit.action` |
| --- | --- | --- | --- |
| `POST /control/plans/create` | `handlePlanCreate` | `plan`, `control_audit` | `plan_create` |
| `POST /control/plans/{name}/update` | `handlePlanUpdate` | `plan`, `control_audit` | `plan_update` |
| `POST /control/plans/{name}/delete` | `handlePlanDelete` | `control_audit` (row retained; full history) | `plan_delete` |

Create/update body carries the §2 fields (`name` on create; path `{name}` identifies update/delete).
`target` on `control_audit` is the plan `name`. `operator_id` is the resolved operator principal.

### 3.2 Assign plan (extends I4 entitle)

| Route | Handler | D1 writes | `control_audit.action` |
| --- | --- | --- | --- |
| `POST /control/installations/{installation_id}/entitle` | `handleEntitle` (extended) | `entitlement` economics + I4 grant writes + `control_audit` | `entitle` (I4 vocabulary, extended behaviour) |

Assignment **reads the catalogue**. It loads `plan` by the installation's `entitlement.plan`
(enroll already wrote that name) or by an optional body `plan` that is first written onto the
row. In **one** D1 batch it copies:

| From `plan` | Onto `entitlement` |
| --- | --- |
| `credit_budget` | `credit_budget` |
| `request_quota` | `request_quota` |
| `max_cost_class` | `max_cost_class` |
| `soft_threshold` | `soft_threshold` |
| `allowed_capabilities` | `allowed_capabilities` |

and sets `status = 'active'`. Token/cost budgets and period bounds are **not** catalogue fields;
I4's grant writes and those payload fields remain (G1 does not reimplement grant/revoke).

`target` is `installation_id`. This is the mutation the assignment tests distinguish from
override.

### 3.3 Per-installation override

| Route | Handler | D1 writes | `control_audit.action` |
| --- | --- | --- | --- |
| `POST /control/installations/{installation_id}/override` | `handleOverride` | `entitlement`, `control_audit` | `override` |

Body may set quota, budget (`credit_budget` and/or token/cost), period bounds, or soft
threshold — Entitlement management "set quota and budget" / "set period bounds and soft
threshold" (§4.5). It does **not** copy from `plan`.

`action` **must** differ from `entitle` so the override is recorded as such. `before_pointer` /
`after_pointer` carry the changed field snapshot (§7.3 `control_audit`; spec Edge Cases).
`target` is `installation_id`.

---

## 4. `control_audit` extension

B2 froze `enroll` / `rotate` / `suspend` / `resume` / `delete`. I4 extended with `entitle`.
G1 extends further (never rewrites those values):

| `action` | Mutation |
| --- | --- |
| `plan_create` | Create catalogue plan |
| `plan_update` | Update catalogue plan |
| `plan_delete` | Delete (retain row) catalogue plan |
| `entitle` | Assign plan (catalogue copy + I4 grants) |
| `override` | Explicit per-installation override |

Row shape is unchanged: `audit_id`, `operator_id`, `action`, `target`, `before_pointer`,
`after_pointer`, `recorded_at`.

---

## 5. Config-cache kind `"plans"`

Forward-only extension of A5 `ConfigEntityKind` (same pattern as `"token_contracts"`). A5's
frozen six-kind table is not edited.

```text
loadConfig(cache, reader, "plans", planName)
```

Production `createD1ConfigReader` maps `plans:{name}` to `SELECT * FROM plan WHERE name = ?`.

| Isolate | I/O |
| --- | --- |
| Cold (miss / expiry) | Exactly one `D1Reader.read` |
| Warm | Zero I/O |

A D1 miss is A5 `ConfigCacheMissError`; nothing is cached on miss. The cache owns nothing; D1
is the authority. TTL is A5's existing constant — not a new configuration surface.

Kind `"entitlements"` is unchanged as a kind. After the migration, loaded entitlement rows
include `credit_budget` (and `max_cost_class`). Same warm/cold budget.

`credit_price` is **not** a cached kind (FR-019).

---

## 6. Frozen admission snapshot name

The entitlement monthly credit-budget column's snapshot name is **`credit_budget`**. G2 binds
to that name when extending admission; G1 does not change B4 `EntitlementSnapshot`.

---

## 7. Consumers

| Slice | Binding |
| --- | --- |
| **G2** | Reads `credit_budget` from the entitlement row / snapshot name frozen here |
| **V4** | Drives the plan CRUD and assignment routes against a local stack |
| Later control slices | May extend `control_audit.action`; must not rewrite the values in §4 |
