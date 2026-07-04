# Implementation Plan: Service Catalog (015)

**Branch**: `015-service-catalog` | **Date**: 2026-07-02 | **Spec**: `specs/015-service-catalog/spec.md`

**Input**: Feature specification from `specs/015-service-catalog/spec.md`

## Summary

Introduce an administrator-governed, **organization-scoped Service Catalog** with **per-branch configuration** (assignment, activation, price override, single time-boxed promotion) and wire it into billing so invoice items are **selected from the catalog** instead of typed free-text. The server resolves the **effective unit price** (promotion → override → default) at add-to-invoice time and **snapshots** it onto the invoice item so history is immutable.

The design reuses existing platform patterns end to end: two new PostgreSQL tables (`services`, `service_branches`) with `numeric(14,2)` money, `is_deleted`/`deleted_at`/`deleted_by` soft delete, `apply_standard_audit_triggers`, and partial unique indexes; all mutations through `auth_internal.*` `SECURITY DEFINER` RPCs with thin `public.*` wrappers returning `public.rpc_result`, gated by `auth_internal.assert_permission`, scoped via `jwt_organization_id()`/`jwt_branch_ids()`, audited to `audit_log`, and protected by optimistic concurrency (`p_expected_updated_at`); RLS that permits scoped SELECT and blocks direct DML. Two new permission keys (`services.view`, `services.manage`) are seeded to `owner`/`administrator` and mirrored in the Flutter `PermissionKeys`/`PermissionService`.

The billing integration is **additive + one breaking editor change**: `invoice_items` gains a nullable `service_id` FK plus snapshot columns; a new `add_invoice_item_from_service` RPC replaces free-text `add_invoice_item` on the editor path (the old free-text RPC is retired for new authoring, historical rows untouched). The Flutter client adds a modular clean-architecture feature `frontend/lib/features/service_catalog` (`domain`/`data`/`application`/`presentation`) reusing `flutter_riverpod`, `go_router`, `core/ui`, the `Money` value object, and the `CatalogAutocompleteField` interaction pattern for the invoice service selector.

Delivery is priority-sequenced: **P1** = catalog CRUD + branch assignment + billing selection with price resolution (US1–US2); **P2** = branch override/activation, promotions, edit/global-status, catalog browse (US3–US6); **P3** = copy-between-branches + new-branch service setup (US7 + FR-031).

## Technical Context

**Language/Version**: Dart/Flutter stable (Windows desktop); PostgreSQL 15+ via Supabase; PL/pgSQL in `auth_internal` schema with `public` RPC wrappers

**Primary Dependencies**: Supabase Flutter SDK (RPC), `flutter_riverpod`, `go_router`, `decimal` (via existing `Money` value object); existing platform primitives — `core/rpc/app_rpc_invoker.dart` (`AppRpcInvoker` mixin, `RpcResult`/`RpcFailure`), `core/auth/permission_service.dart` + `features/auth/domain/permission_keys.dart`, `core/auth/auth_route_guard.dart`, `core/ui/widgets/widgets.dart` design system, billing `Money` (`features/billing/domain/money.dart`) and `billing_formatting.dart`; reuse of `features/visits/.../catalog_autocomplete_field.dart` interaction pattern

**Storage**: Supabase PostgreSQL. New tables `public.services`, `public.service_branches`. Additive ALTER on `public.invoice_items` (+`service_id` FK, +snapshot columns). Money as `numeric(14,2)`. Soft delete via `is_deleted`/`deleted_at`/`deleted_by` with partial unique indexes (`WHERE is_deleted = false`). No table dropped; no Storage bucket change; no AI.

**Testing**: New SQL tests under `backend/tests/` (`service_catalog_crud.sql`, `service_catalog_rls.sql`, `service_catalog_pricing.sql`, `service_catalog_concurrency.sql`) with a `run_service_catalog_tests.sh` runner added to `run_all_backend_tests.sh`, following the billing test harness (JWT simulation via `set_config('request.jwt.claims', ...)`, temp result tables, `RAISE EXCEPTION` on failure). Flutter unit/widget tests under `frontend/test/unit/service_catalog/` and `frontend/test/widget/service_catalog/` (domain parsing, price-preview formatter, eligibility descriptor, notifier flows, selector widget). `dart analyze` on the new feature.

**Target Platform**: Windows desktop on clinic LAN against local Supabase (V1-0 deployment profile); responsive collapse for narrow windows.

**Project Type**: Desktop client + Supabase PostgreSQL (additive migrations, RLS, RPC). No custom API server. No AI.

**Performance Goals**: Service selector search returns within the existing 300ms debounce under normal LAN (NFR-002, SC-009 < 15s add-to-invoice); catalog list navigable with pagination up to 2,000 services (NFR-003); price resolution is a single server round-trip reused by both preview and add-to-invoice (FR-026).

**Constraints**: Organization-scoped services, branch-scoped configuration; mutations via RPC only (RLS blocks direct DML); optimistic concurrency on service and `service_branches` edits (`STALE_SERVICE` / `STALE_SERVICE_BRANCH`); price/eligibility resolution is server-authoritative and reused (client never the source of truth); monetary exact-decimal scale 2; invariant `promotion_price ≤ effective price` enforced on every price-affecting write; snapshot-at-add immutability for invoice items; soft delete only; backend-first fetch for list/editor/selector; no AI dependency; online-only mutation semantics (no offline drafts); new migration timestamps MUST sort after the latest existing migration (currently `20260711210000_*`), so use `20260712NNNNNN_*` prefixes.

**Scale/Scope**: 2 new tables + 1 additive `invoice_items` ALTER; ~11 RPC families (create/update service, set assignment, configure branch status/override, set/clear promotion, change global status, soft-delete, copy config, resolve effective price, add-item-from-service, list/search); 2 new permission keys; ~12–16 new Flutter files across 4 layers (models ×3, repository, notifiers ×2–3, catalog list/editor pages, branch-config matrix + promotion editor + copy dialog + new-branch setup widgets, invoice service selector) plus modification of the billing invoice editor to swap free-text entry for the selector; 4 backend SQL test files + runner; frontend unit/widget tests.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

### Pre-Research Gate

- [x] **Clinic fit**: An org-governed service list with per-branch pricing and simple single-window promotions targets small-to-mid multi-branch clinics; taxonomies, bundles, tax engines, cost/margin, inventory, multi-currency, and analytics are explicitly out of scope (spec Business Context + FR-029).
- [x] **Simple operational model**: No microservices, queues, Kubernetes, or custom primary backend service; delivery is Flutter presentation + additive Postgres migrations, RPCs, and RLS only.
- [x] **Layer ownership explicit**: Flutter owns catalog UI, invoice selector, price-preview display, permission-aware controls, orchestration; Supabase exposes RPC + RLS-scoped reads; PostgreSQL owns schema, constraints, eligibility/price resolution, one-promotion-per-branch, snapshotting, soft delete, audit; AI not involved.
- [x] **Backend authority**: All catalog mutations and add-to-invoice pricing run through `auth_internal` `SECURITY DEFINER` RPCs with `public` wrappers; validation, uniqueness, non-negative price, promotion invariant, and price resolution live in the database; RLS blocks direct DML.
- [x] **Security**: Authenticated, tenant-scoped (`jwt_organization_id()`), branch-scoped (`jwt_branch_ids()`), permission-gated (`services.view`/`services.manage`, plus `invoices.create` for selection); `audit_log` entries for all sensitive changes; soft delete preserves history.
- [x] **AI isolation & degradation**: No AI dependency; every catalog and invoicing workflow is fully manual (Principle V); degrades to clear errors when offline; subscription-degraded mode never deletes data and at worst limits mutations while existing services remain selectable.

### Post-Design Re-Check

- [x] `invoice_items` change is additive (nullable `service_id` + snapshot columns); historical rows keep values; existing billing SELECT/RLS unchanged; only the editor authoring path swaps free-text RPC for `add_invoice_item_from_service`.
- [x] Optimistic concurrency reused analogously to billing (`p_expected_updated_at`) with new `STALE_SERVICE`/`STALE_SERVICE_BRANCH` codes.
- [x] Price resolution and eligibility are single server-authoritative functions reused by preview and add-to-invoice — no duplicated client pricing logic (NFR-008).
- [x] No new custom backend service; no AI write paths; no hard deletes; catalog management gated by new `services.manage` (owner/administrator only), selection gated by existing `invoices.create`.
- [x] New permission key `services.manage` seeding mirrors the billing seed idiom (`ON CONFLICT (role, permission_key) DO UPDATE`) and the client `PermissionKeys`/`PermissionService`.

No constitution violations — **Complexity Tracking is omitted**.

## Project Structure

### Documentation (this feature)

```text
specs/015-service-catalog/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/           # Phase 1 output
│   ├── service-management.md      # create/update/assign/status/soft-delete RPCs
│   ├── branch-configuration.md    # status/override/promotion + copy + new-branch setup RPCs
│   ├── pricing-and-eligibility.md # resolve_effective_service_price + search/list RPCs
│   └── billing-integration.md     # invoice_items ALTER + add_invoice_item_from_service
├── checklists/
│   └── requirements.md  # from /speckit-specify
└── tasks.md             # /speckit-tasks (NOT created by /speckit-plan)
```

### Source Code (repository root)

```text
backend/
├── supabase/migrations/                                  # timestamps MUST sort after 20260711210000
│   ├── 20260712090000_service_catalog.sql                # tables, constraints, indexes, RLS, audit triggers, permission seed
│   ├── 20260712090500_service_catalog_rpcs.sql           # service + branch-config + promotion + copy RPCs (auth_internal + public)
│   ├── 20260712091000_service_catalog_pricing_rpcs.sql   # resolve_effective_service_price + search/list RPCs
│   └── 20260712091500_service_catalog_billing_integration.sql  # invoice_items ALTER + add_invoice_item_from_service + retire free-text editor path
└── tests/
    ├── service_catalog_crud.sql          # new: service + branch-config CRUD, copy, soft-delete
    ├── service_catalog_rls.sql           # new: cross-org / cross-branch denial, DML denial
    ├── service_catalog_pricing.sql       # new: resolution priority, inclusive dates, invariant, add-to-invoice snapshot
    ├── service_catalog_concurrency.sql   # new: optimistic concurrency stale rejection
    └── run_service_catalog_tests.sh      # new runner; also referenced from run_all_backend_tests.sh

frontend/lib/features/service_catalog/
├── domain/
│   ├── service.dart                      # Service model (id, name, defaultPrice: Money, globalStatus, timestamps)
│   ├── service_branch_config.dart        # per-branch config (status, priceOverride?, promotion?)
│   ├── service_promotion.dart            # value object (price + inclusive start/end) + isActiveOn(date)
│   ├── global_status.dart                # enum active/inactive
│   ├── effective_price.dart              # resolved price + applied rule (promo/override/default)
│   └── service_eligibility.dart          # pure eligibility descriptor (reason when ineligible)
├── data/
│   └── service_catalog_repository.dart   # with AppRpcInvoker; all public RPC calls
├── application/
│   └── service_catalog_rpc_messages.dart # RPC error code → user message (STALE_*, DUPLICATE_NAME, PROMO_EXCEEDS_PRICE, ...)
└── presentation/
    ├── models/service_list_filters.dart  # name/status/branch filters + pagination
    ├── providers/
    │   ├── service_catalog_list_notifier.dart     # list/search/filter (AsyncNotifier)
    │   ├── service_editor_notifier.dart           # create/edit + branch matrix mutations (optimistic concurrency)
    │   └── service_selector_notifier.dart         # eligible-services search for invoice editor
    ├── pages/
    │   ├── service_catalog_list_page.dart
    │   └── service_editor_page.dart               # form + branch configuration matrix
    ├── widgets/
    │   ├── service_form.dart                      # name/default price/global status + assignment
    │   ├── branch_configuration_matrix.dart       # per-branch status/override/promotion rows
    │   ├── promotion_editor.dart                  # price + inclusive start/end + validation
    │   ├── copy_configuration_dialog.dart         # source/target + mode + replace confirmation
    │   ├── new_branch_service_setup.dart          # select / copy-entire / copy-then-modify
    │   ├── service_price_preview.dart             # calls resolve RPC for branch/date
    │   └── invoice_service_selector.dart          # type-ahead eligible-services picker for billing editor
    └── (routes registered in frontend/lib/app/app_routes.dart + router.dart with services.* guard)

frontend/lib/features/billing/presentation/
└── widgets/invoice_items_editor.dart     # MODIFIED: replace free-text description entry with InvoiceServiceSelector; quantity editable, unit price read-only snapshot

frontend/test/
├── unit/service_catalog/    # domain parsing, effective_price/eligibility, rpc_messages, filters, notifier logic
└── widget/service_catalog/  # branch matrix, promotion editor validation, invoice service selector, copy dialog
```

**Structure Decision**: A new self-contained feature module `frontend/lib/features/service_catalog` follows the established clean-architecture layering (`domain`/`data`/`application`/`presentation`) used by billing/visits, exposing only its repository + providers (notably `InvoiceServiceSelector` and the eligible-services search) to billing — the single, well-defined cross-feature coupling (NFR-006/007). Backend work is additive: two new tables plus an additive `invoice_items` ALTER, mirroring the billing migration clustering (base schema + per-concern RPC migrations). Billing's SELECT paths, RLS, and historical rows are untouched; only the invoice editor's item-authoring path changes from free-text to catalog selection.

## Phase 0 — Research

See `research.md`. All Technical Context items are resolved against existing repo conventions (no remaining NEEDS CLARIFICATION). Key decisions: reuse `numeric(14,2)` + soft-delete + audit-trigger schema idioms; `auth_internal`→`public` RPC pattern with `rpc_result` envelope; server-authoritative price resolution reused by preview and add-to-invoice; additive `invoice_items` extension with a new `add_invoice_item_from_service` RPC retiring the free-text editor path; reuse `Money`, `PermissionService`, `AppRpcInvoker`, `core/ui`, and the `CatalogAutocompleteField` interaction for the selector.

## Phase 1 — Design & Contracts

Outputs generated: `data-model.md` (tables, columns, constraints, indexes, state, invoice_items extension), `contracts/*.md` (RPC signatures, params, envelopes, error codes, RLS), and `quickstart.md` (setup, migration apply, test run, manual verification walkthrough). Agent context updated by pointing the `specify-rules.mdc` SPECKIT block at this plan.

## Phase 2 — Task Planning Approach (preview only; tasks.md created by /speckit-tasks)

Tasks will be derived from the contracts and data model, priority-sequenced by user story:

- **P1**: migration `20260712090000` (tables + RLS + audit + permission seed) → service management RPCs (create/update/assign/status/soft-delete) → pricing/eligibility resolve RPC + search/list → `invoice_items` ALTER + `add_invoice_item_from_service` → frontend domain models + repository + list/editor + `InvoiceServiceSelector` swap in billing editor → SQL CRUD/RLS/pricing tests + Dart unit tests for US1–US2.
- **P2**: branch status/override + promotion RPCs (with invariant guards) → branch-configuration matrix + promotion editor → edit/global-status flows → catalog browse filters → concurrency tests + widget tests for US3–US6.
- **P3**: copy-configuration RPC (replace/merge, idempotent) + copy dialog → new-branch service setup step (FR-031, reuses copy) → audit + tests for US7.

Each story remains independently testable; P1 alone yields a usable MVP (governed catalog + correctly-priced invoice selection).
