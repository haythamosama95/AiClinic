# Phase 0 Research: Service Catalog (015)

**Date**: 2026-07-02 | **Feature**: `docs/specs/015-service-catalog/spec.md`

All Technical Context unknowns are resolved against existing repository conventions (billing V1-6 / `007-billing` and visits catalog `013`/`014`). No `NEEDS CLARIFICATION` remains. Each decision below records the choice, rationale, and rejected alternatives.

## R1 — Schema & money/soft-delete/audit conventions

- **Decision**: New tables `public.services` and `public.service_branches` use `numeric(14,2)` for all money, `is_deleted boolean DEFAULT false` + `deleted_at timestamptz` + `deleted_by uuid`, standard `created_at/created_by/updated_at/updated_by`, and `SELECT public.apply_standard_audit_triggers('public.<table>'::regclass)` for `set_updated_at()`/`set_audit_user()`. Uniqueness via partial unique indexes `WHERE is_deleted = false`.
- **Rationale**: Exactly matches `invoices`/`invoice_items`/`insurance_providers` and the visits `medications`/`investigations` catalogs; keeps operational queries filtering `is_deleted = false` and lets audit/user stamping be automatic.
- **Alternatives rejected**: `money` type or floats (precision drift, violates NFR-005/`007-billing` NFR-007); hard delete (violates constitution + FR-020); manual audit column setting in every RPC (duplicated, error-prone).

## R2 — RPC architecture (auth_internal + public wrappers)

- **Decision**: All mutations and the price-resolution read live in `auth_internal.*` `SECURITY DEFINER` functions returning `public.rpc_result`, exposed via thin `public.*` `SECURITY INVOKER` SQL wrappers with `GRANT EXECUTE ... TO authenticated`. Permission via `auth_internal.assert_permission('services.manage'|'services.view')`; org/branch scope via `public.jwt_organization_id()` / `public.jwt_branch_ids()`; success/error via `public.rpc_success(jsonb)` / `public.rpc_error(code, msg)`; audit via inserts into `public.audit_log`.
- **Rationale**: Identical to `add_invoice_item` / `record_payment`; the client calls public RPC names through the `AppRpcInvoker` mixin and gets the uniform `RpcResult`/`RpcFailure` handling (PGRST202 → `RPC_NOT_APPLIED` with `migrationHint`, 42501 → `RPC_NOT_CONFIGURED`).
- **Alternatives rejected**: Direct table DML from client (blocked by RLS, violates backend authority); Edge Functions (unnecessary; cloud-only, out of the local-first path); bespoke return shapes (breaks the shared envelope).

## R3 — Optimistic concurrency

- **Decision**: Service and branch-configuration mutations accept `p_expected_updated_at timestamptz`; the RPC locks the row `FOR UPDATE`, compares `updated_at`, and raises `STALE_SERVICE` / `STALE_SERVICE_BRANCH` on mismatch. The client maps these to a refresh prompt (mirrors billing `STALE_INVOICE` → `InvoiceStaleException`).
- **Rationale**: Matches FR-027 and billing's `lock_draft_invoice` concurrency idiom.
- **Alternatives rejected**: Last-write-wins (silent data loss); table-level advisory locks (heavier, unnecessary).

## R4 — Server-authoritative price resolution & eligibility (single source)

- **Decision**: One internal function `auth_internal.resolve_effective_service_price(service_id, branch_id, on_date)` returns `{ unit_price, applied_rule (promo|override|default), eligible (bool), reason }`. It is reused by (a) the read RPC `resolve_effective_service_price` (price preview, FR-026) and (b) `add_invoice_item_from_service` (snapshot). Eligibility = `global_status = active` AND assigned to branch AND `service_branches.status = active`.
- **Rationale**: Guarantees the client never computes pricing (NFR-008) and that preview equals the snapshotted price. Single implementation avoids drift.
- **Alternatives rejected**: Client-side resolution (source-of-truth violation); duplicating logic in two RPCs (drift risk).

## R5 — Promotion model & invariant enforcement

- **Decision**: The single optional promotion lives inline on `service_branches` (`promotion_price`, `promotion_start_date`, `promotion_end_date`), enforced by a table CHECK that either all three are NULL or all set with `start ≤ end` and `promotion_price ≥ 0`. The `promotion_price ≤ effective price` invariant (FR-008) is enforced inside the RPCs that can break it: set-promotion, configure-override, and update-service (default price). Inclusive window comparison uses `on_date BETWEEN start AND end`.
- **Rationale**: One-promotion-per-branch (FR-009) is naturally expressed by inline columns; a CHECK cannot see the sibling default price, so the cross-field invariant is guarded in RPCs (the only write path).
- **Alternatives rejected**: Separate `service_promotions` table (over-models a single-window requirement, adds joins); trigger-based invariant (harder to return a friendly `rpc_error`; RPC guard is clearer and testable).

## R6 — Assignment semantics ("all branches" + future branches)

- **Decision**: A `service_branches` row exists iff the service is assigned to that branch. "All branches" expands to explicit rows for branches existing at save time (no dynamic flag). New branches are not auto-assigned; the new-branch service setup step (FR-031) uses the copy-configuration RPC to populate them.
- **Rationale**: Matches the clarified spec decision; keeps assignment explicit/auditable and the eligibility query simple (row presence + status).
- **Alternatives rejected**: Dynamic "all branches" flag with implicit rows (complicates eligibility, override storage, and audit; rejected in clarification).

## R7 — Billing invoice_items integration (additive + editor swap)

- **Decision**: `ALTER TABLE public.invoice_items ADD COLUMN service_id uuid REFERENCES public.services(id)` (nullable to preserve historical rows) plus snapshot columns aligned to existing ones (`description` repurposed as the `service_name` snapshot; existing `unit_price`/`quantity`/`line_total` reused). New authoring uses `add_invoice_item_from_service(p_invoice_id, p_expected_updated_at, p_service_id)`: it asserts `invoices.create`, locks the draft invoice (`lock_draft_invoice`), validates eligibility for the invoice branch, resolves + snapshots price, and **create-or-increments** (a re-selected service increments quantity, FR-015). The legacy free-text `add_invoice_item` is removed from the editor path (kept only for historical data integrity; no new free-text authoring).
- **Rationale**: Additive column change keeps all billing SELECT/RLS and historical rows working; reuses `lock_draft_invoice`, `refresh_invoice_subtotal`, and draft-only mutation rules; snapshot immutability (FR-013/FR-016) is inherent because the resolved price is written once at add time.
- **Alternatives rejected**: New parallel item table (fragments billing reads/receipts); back-filling historical free-text to services (rejected in clarification, fragile name-matching); making `service_id` NOT NULL (would break existing rows).

## R8 — Permissions & seeding

- **Decision**: Two new keys `services.view` (browse management surface) and `services.manage` (all mutations), seeded to `owner`/`administrator` only via `INSERT ... ON CONFLICT (role, permission_key) DO UPDATE SET is_granted = EXCLUDED.is_granted, is_deleted = false`. Service **selection** in the invoice editor requires only the existing `invoices.create`. Mirror keys in `frontend/lib/features/auth/domain/permission_keys.dart` and add `PermissionService.canViewServices()` / `canManageServices()`.
- **Rationale**: Matches the billing seed idiom and the client permission mirror; `receptionist` keeps selection via `invoices.create` (FR-022/FR-023).
- **Alternatives rejected**: Overloading `invoices.*` keys (conflates catalog governance with invoicing); a new role (spec forbids new roles).

## R9 — RLS

- **Decision**: `services` SELECT: `is_deleted = false AND organization_id = public.jwt_organization_id()` AND a read-access helper (view via `services.view`/`services.manage`, or selection via `invoices.create`). `service_branches` SELECT: `is_deleted = false` AND parent service in caller's org AND `branch_id = ANY(public.jwt_branch_ids())`. All INSERT/UPDATE/DELETE policies `WITH CHECK (false)` / `USING (false)` — writes via RPC only. Add an `auth_internal.staff_has_services_read_access()` helper analogous to `staff_has_invoices_view_access()`.
- **Rationale**: Mirrors billing RLS exactly (branch scope for per-branch data, org scope for org-level data, DML blocked).
- **Alternatives rejected**: Permissive DML policies (violates backend authority); org-only scoping for `service_branches` (would leak other branches' pricing).

## R10 — Frontend architecture, state, and reuse

- **Decision**: New module `frontend/lib/features/service_catalog` with `flutter_riverpod` (`AsyncNotifierProvider(.autoDispose/.family)`), `go_router` routes registered in `app_routes.dart`/`router.dart` guarded by a `services.*` route redirect (extend `AuthRouteGuard`), `core/ui/widgets/widgets.dart` components, the billing `Money` value object + a small `service_catalog` price-preview formatter (or reuse `billing_formatting.formatMoney`), and repository via `AppRpcInvoker`. The invoice service selector reuses the `CatalogAutocompleteField` interaction (debounced type-ahead) but **without** free-text/`SaveToCatalogDialog` (selection-only).
- **Rationale**: Consistency with billing/visits; maximizes reuse and keeps the module replaceable (NFR-006/007).
- **Alternatives rejected**: `hooks_riverpod` (billing uses `flutter_riverpod`); bespoke widgets instead of `core/ui` (inconsistent UX); embedding catalog logic inside billing (breaks modularity).

## R11 — Currency display

- **Decision**: Reuse `Money` (`decimal`, scale 2) and `billing_formatting.formatMoney(amount, currency)`; the invoice's `currency` field drives the symbol in the selector/preview, consistent with billing.
- **Rationale**: Single currency per org (out-of-scope multi-currency); avoids a second formatter.
- **Alternatives rejected**: A new currency formatter (duplication).

## R12 — Testing strategy

- **Decision**: Backend SQL tests (`service_catalog_crud.sql`, `_rls.sql`, `_pricing.sql`, `_concurrency.sql`) with `run_service_catalog_tests.sh` wired into `run_all_backend_tests.sh`, using JWT simulation and temp result tables like `billing_crud.sql`. Frontend `frontend/test/unit/service_catalog/` (domain, `effective_price`, eligibility, rpc messages, filters) and `frontend/test/widget/service_catalog/` (branch matrix, promotion validation, selector, copy dialog).
- **Rationale**: Matches the established harness; covers eligibility (SC-001), price resolution + inclusive dates + invariant (SC-002/SC-005), history stability (SC-003), permissions (SC-004), copy (SC-006), isolation (SC-007), concurrency.
- **Alternatives rejected**: Only frontend tests (would not verify DB-authoritative rules); ad-hoc manual verification only (not repeatable).

## Migration ordering note

Existing migrations run through `20260711210000_*`. New migration filenames MUST sort lexically after that; this plan uses `20260712NNNNNN_*` prefixes. Final exact timestamps are assigned at implementation time but must remain `> 20260711210000`.
