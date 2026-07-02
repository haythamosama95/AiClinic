# Quickstart: Service Catalog (015)

**Date**: 2026-07-02 | **Feature**: `specs/015-service-catalog/spec.md`

Developer walkthrough to build, apply, and verify the Service Catalog feature. Assumes the local Supabase stack from `backend/local/` and the Flutter desktop app.

## Prerequisites

- `002-auth-rbac`, `003-org-branch-management`, `004-patient-management`, `006-visit-medical-records`, `007-billing` applied.
- Local Supabase running (see `backend/local/docker-compose*`).
- Flutter toolchain configured for Windows desktop.

## 1. Backend: apply migrations

Add the four migrations under `backend/supabase/migrations/` (timestamps MUST sort after the newest existing migration, currently `20260711210000_*` → use `20260712NNNNNN_*`):

1. `20260712090000_service_catalog.sql` — enums, `services`, `service_branches`, constraints, partial unique indexes, `apply_standard_audit_triggers`, RLS policies (+ `auth_internal.staff_has_services_read_access()`), and the `services.view`/`services.manage` permission seed (`INSERT ... ON CONFLICT DO UPDATE`).
2. `20260712090500_service_catalog_rpcs.sql` — service management + branch configuration + promotion + copy + new-branch setup RPCs.
3. `20260712091000_service_catalog_pricing_rpcs.sql` — `resolve_effective_service_price`, `search_eligible_services`, `list_services`, `get_service`.
4. `20260712091500_service_catalog_billing_integration.sql` — `invoice_items` ALTER + `add_invoice_item_from_service`.

Apply via the project's standard migration flow (same as billing). Verify with `\df public.*service*` and `\d public.services`.

## 2. Backend: run tests

```bash
# individual
bash backend/tests/run_service_catalog_tests.sh
# or all
bash backend/tests/run_all_backend_tests.sh
```

Test files: `service_catalog_crud.sql`, `service_catalog_rls.sql`, `service_catalog_pricing.sql`, `service_catalog_concurrency.sql` (JWT simulation + temp result tables, per `billing_crud.sql`).

Covers: CRUD + assignment + copy + soft-delete; cross-org/cross-branch denial + DML denial; pricing priority + inclusive dates + `promotion_price ≤ effective` invariant + add-to-invoice snapshot + create-or-increment; optimistic-concurrency stale rejection.

## 3. Frontend: analyze & test

```bash
cd frontend
dart analyze lib/features/service_catalog
flutter test test/unit/service_catalog test/widget/service_catalog
```

## 4. Manual verification (maps to acceptance scenarios)

1. **US1** — As `administrator`, open Catalog → Create service "Consultation", default 200, assign to two of three branches, save. Confirm it lists and is selectable only at the two branches. Try a duplicate name → rejected; try negative price → rejected.
2. **US2** — Open a `draft` invoice at an assigned branch → in the item editor, the free-text field is gone; use the **service selector**, add "Consultation" → unit price = resolved effective price, quantity 1, snapshot stored. Re-select it → quantity increments (no duplicate line). Edit quantity → total updates; unit price is read-only. Later change the catalog price → the issued invoice line is unchanged.
3. **US3** — Set Branch B override 150, Branch C inactive. Confirm Branch B resolves 150, Branch A (no override) resolves 200, Branch C not selectable. Try configuring an unassigned branch → rejected.
4. **US4** — Set Branch C promo 100 for 01-Jan..31-Jan (override 120). Invoice on 15-Jan and 31-Jan → 100; on 01-Feb → 120. Promo > effective → rejected; missing a date / start>end → rejected. Then lower Branch C override below 100 → rejected until promo adjusted/cleared.
5. **US5** — Rename service, raise default price, mark globally inactive → new invoices can't select it; previously issued lines unchanged. Reactivate → selectable again.
6. **US6** — Create several services; search by name fragment; filter by status `inactive`; filter by a branch → correct paginated results. A user without `services.view`/`services.manage` cannot open the management screen but a `receptionist` can still select services on invoices.
7. **US7** — Configure Branch A fully; copy to empty Branch D with **merge** → D matches A; change a value in D, copy again with **replace** (confirm dialog) → D matches A; cancel at confirm → no change.
8. **New branch (FR-031)** — Create a new branch → service setup prompt offers select-from-catalog / copy-entire / copy-then-modify; until completed the branch has no assigned services.

## 5. Permissions & degraded behavior checks

- `owner`/`administrator` have `services.view` + `services.manage`; `receptionist`/`doctor`/`lab_staff` do not (receptionist selects via `invoices.create`).
- Direct table DML from a client is denied by RLS (mutations only via RPC).
- Cross-organization service access denied.
- AI unavailability does not affect any flow (no AI dependency). Offline mutation attempts surface clear errors without false success.

## Key references

- Backend patterns: `backend/supabase/migrations/20260605180000_billing.sql`, `..._billing_us1_rpcs.sql`, `20260516100100_auth_rbac_audit_triggers.sql`.
- Frontend patterns: `frontend/lib/core/rpc/app_rpc_invoker.dart`, `frontend/lib/features/billing/{domain,data,presentation}`, `frontend/lib/core/ui/widgets/widgets.dart`, `frontend/lib/core/auth/permission_service.dart`, `frontend/lib/features/visits/presentation/widgets/catalog_autocomplete_field.dart`.
- Contracts: `specs/015-service-catalog/contracts/*.md`; data model: `specs/015-service-catalog/data-model.md`.
