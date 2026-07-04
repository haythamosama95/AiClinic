# Phase 1 Data Model: Service Catalog (015)

**Date**: 2026-07-02 | **Feature**: `docs/specs/015-service-catalog/spec.md`

All money is `numeric(14, 2)`. All operational tables carry the shared audit + soft-delete columns and `apply_standard_audit_triggers`. Schema/type/RLS idioms match `backend/supabase/migrations/20260605180000_billing.sql`.

## Enums

```sql
-- Reuses text + CHECK, consistent with billing status enums.
CREATE TYPE public.service_global_status AS ENUM ('active', 'inactive');
CREATE TYPE public.service_branch_status AS ENUM ('active', 'inactive');
CREATE TYPE public.service_copy_mode AS ENUM ('replace', 'merge');
```

> Alternative if the codebase prefers text+CHECK over ENUM for these: use `text` with `CHECK (col IN ('active','inactive'))`. Match whichever the most recent migrations use; billing uses dedicated ENUM types (e.g. `public.invoice_status`), so ENUMs are the default here.

## Table: `public.services`

| Column | Type | Notes |
| --- | --- | --- |
| `id` | `uuid` PK | `DEFAULT gen_random_uuid()` |
| `organization_id` | `uuid NOT NULL` | FK → `public.organizations(id)`; tenancy scope |
| `name` | `text NOT NULL` | trimmed; `CHECK (char_length(name) BETWEEN 1 AND 200)` |
| `default_price` | `numeric(14,2) NOT NULL` | `CHECK (default_price >= 0)` |
| `global_status` | `public.service_global_status NOT NULL` | `DEFAULT 'active'` |
| `created_at` | `timestamptz NOT NULL` | `DEFAULT now()` |
| `created_by` | `uuid` | FK → `auth.users(id)` (audit trigger) |
| `updated_at` | `timestamptz` | audit trigger |
| `updated_by` | `uuid` | FK → `auth.users(id)` (audit trigger) |
| `is_deleted` | `boolean NOT NULL` | `DEFAULT false` |
| `deleted_at` | `timestamptz` | |
| `deleted_by` | `uuid` | FK → `auth.users(id)` |

**Indexes / constraints**

- Partial unique name per org (case-insensitive, trimmed):
  `CREATE UNIQUE INDEX services_org_name_unique ON public.services (organization_id, lower(btrim(name))) WHERE is_deleted = false;`
- `CREATE INDEX services_org_status_idx ON public.services (organization_id, global_status) WHERE is_deleted = false;`
- `SELECT public.apply_standard_audit_triggers('public.services'::regclass);`

## Table: `public.service_branches`

Per-branch configuration; a row exists **iff** the service is assigned to that branch.

| Column | Type | Notes |
| --- | --- | --- |
| `id` | `uuid` PK | `DEFAULT gen_random_uuid()` |
| `service_id` | `uuid NOT NULL` | FK → `public.services(id)` |
| `branch_id` | `uuid NOT NULL` | FK → `public.branches(id)` |
| `status` | `public.service_branch_status NOT NULL` | `DEFAULT 'active'` |
| `price_override` | `numeric(14,2)` | nullable; `CHECK (price_override IS NULL OR price_override >= 0)`; NULL ⇒ use default |
| `promotion_price` | `numeric(14,2)` | nullable; `>= 0` |
| `promotion_start_date` | `date` | nullable |
| `promotion_end_date` | `date` | nullable |
| audit + soft-delete columns | | same set as `services` |

**Constraints / indexes**

- Promotion all-or-nothing + ordering:
  `CHECK ( (promotion_price IS NULL AND promotion_start_date IS NULL AND promotion_end_date IS NULL) OR (promotion_price IS NOT NULL AND promotion_start_date IS NOT NULL AND promotion_end_date IS NOT NULL AND promotion_start_date <= promotion_end_date) )`
- One config row per (service, branch):
  `CREATE UNIQUE INDEX service_branches_service_branch_unique ON public.service_branches (service_id, branch_id) WHERE is_deleted = false;`
- `CREATE INDEX service_branches_branch_status_idx ON public.service_branches (branch_id, status) WHERE is_deleted = false;`
- `CREATE INDEX service_branches_service_idx ON public.service_branches (service_id) WHERE is_deleted = false;`
- `SELECT public.apply_standard_audit_triggers('public.service_branches'::regclass);`

> **Cross-field invariant** `promotion_price ≤ effective price` (override if set, else `services.default_price`) cannot be a table CHECK (references sibling table). It is enforced in RPCs `set_service_promotion`, `configure_service_branch`, and `update_service` (see contracts). Table CHECKs cover only intra-row validity.

## Extension: `public.invoice_items` (additive)

```sql
ALTER TABLE public.invoice_items
  ADD COLUMN service_id uuid REFERENCES public.services (id);
CREATE INDEX invoice_items_service_idx ON public.invoice_items (service_id) WHERE is_deleted = false;
```

- `service_id` is **nullable** to preserve historical free-text rows (created before this feature). New authoring MUST set it (enforced in `add_invoice_item_from_service`).
- The existing `description` column is repurposed as the **service name snapshot** for catalog-created items (still `NOT NULL`, ≤ 500 chars). Existing `unit_price`, `quantity`, `line_subtotal`, `line_total`, and line-discount columns are reused unchanged.
- No back-fill/migration of historical rows (FR-030). No change to billing SELECT/RLS.

## Relationships

```text
organizations 1───∞ services
services      1───∞ service_branches ∞───1 branches
services      1───∞ invoice_items (via nullable service_id snapshot link)
invoices      1───∞ invoice_items (existing)
```

## Validation Rules (enforced in DB / RPC)

| Rule | Where |
| --- | --- |
| Name required, trimmed, unique per org (case-insensitive, non-deleted) | `services` partial unique index + `create/update_service` RPC → `DUPLICATE_NAME` |
| `default_price`/`price_override`/`promotion_price` ≥ 0, scale 2 | column type + CHECKs |
| Promotion requires all three fields, `start ≤ end`, inclusive | `service_branches` CHECK + `set_service_promotion` |
| `promotion_price ≤ effective price` at all times | RPC guards (`set_service_promotion`, `configure_service_branch`, `update_service`) → `PROMO_EXCEEDS_PRICE` |
| One promotion per (service, branch) | inline columns (single window) |
| Branch config only for assigned branches | `configure_service_branch`/`set_service_promotion` require existing `service_branches` row → `BRANCH_NOT_ASSIGNED` |
| Eligibility = global active AND assigned AND branch-active | `resolve_effective_service_price` / selection RPCs |
| Invoice item requires eligible catalog service; quantity positive int; unit price server-resolved | `add_invoice_item_from_service` → `SERVICE_NOT_ELIGIBLE` |
| Service appears at most once per invoice (re-select increments) | `add_invoice_item_from_service` create-or-increment |
| Soft delete only; never hard delete referenced services | `soft_delete_service` |
| Optimistic concurrency on service/branch-config edits | `p_expected_updated_at` → `STALE_SERVICE` / `STALE_SERVICE_BRANCH` |

## State

- **Service.global_status**: `active` ⇄ `inactive` (via `set_service_global_status`). `inactive` ⇒ non-selectable at every branch regardless of branch status (FR-017).
- **ServiceBranch.status**: `active` ⇄ `inactive` (via `configure_service_branch`). Governs branch-level eligibility only.
- **Soft delete**: any row `is_deleted=false → true` (excluded from operational queries; historical invoice items still reference retained rows for display).
- **Promotion lifecycle**: derived from dates + current/add-to-invoice date (no stored state); automatically active within `[start, end]` inclusive and inert outside.

## Pricing resolution (authoritative)

For `(service, branch, on_date)` with the service assigned to the branch:

1. If a promotion is configured and `on_date BETWEEN promotion_start_date AND promotion_end_date` → `promotion_price` (rule `promo`).
2. Else if `price_override IS NOT NULL` → `price_override` (rule `override`).
3. Else → `services.default_price` (rule `default`).

Eligibility precondition (returned alongside price): `services.global_status='active'` AND a non-deleted `service_branches` row exists for the branch AND that row's `status='active'`. Ineligible results are excluded from selectors and rejected by `add_invoice_item_from_service`.
