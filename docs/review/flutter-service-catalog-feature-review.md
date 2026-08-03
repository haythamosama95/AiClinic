# Flutter Service Catalog Feature — Code Review

**Date:** 2026-07-05  
**Scope:** All 21 files under `frontend/lib/features/service_catalog/`, billing integration touchpoints, routing/auth/DI, 8 unit tests under `frontend/test/unit/service_catalog/`  
**Maturity:** Logic-layer only — routes are `uiPendingPlaceholder`; no pages, widgets, or billing editor UI

---

## Executive Summary

The service catalog feature delivers a solid **backend + domain + data + notifier** foundation for org-scoped catalog management and invoice service selection. It aligns with the billing feature pattern (concrete repos, notifiers own orchestration) rather than the patients pattern (repository interfaces + use cases).

The implementation is **not shippable**. The largest gaps are missing UI, incomplete billing integration, and documentation drift (`tasks.md` marks UI tasks complete when files do not exist). Several notifier bugs would block correct UX even after UI is wired.

**Cross-layer verdict (~60% complete):**

| Layer | Verdict |
|-------|---------|
| Domain | Strong parsers/value objects; weak invariants; dead validation code |
| Application | Validators and RPC messages exist but are **unintegrated** |
| Data | All 14 RPCs align with contracts; fragile parsing; no repository interface/tests |
| Presentation | Notifiers scaffolded; **critical stale-reload bug**; no pages/widgets |
| Cross-cutting | Route guards wired; billing coupling partial; snapshot contract unenforced |

**Top ship-blockers (prioritized):**

1. **No UI** — entire `presentation/pages/` and `presentation/widgets/` absent; router uses placeholders ([cross-cutting review](e34d6186-8ff9-4b68-ad36-9537ca444eab))
2. **Stale-conflict reload bug** — `reloadDetail()` is immediately overwritten by pre-mutation state ([presentation review](88939897-55e4-4fd9-b3eb-8a16a3a8555b))
3. **Free-text invoice path not retired** — `addItem`/`updateItem` remain; `InvoiceItem` lacks `serviceId` ([cross-cutting review](e34d6186-8ff9-4b68-ad36-9537ca444eab))
4. **Snapshot unit price mutable** — `update_invoice_item` allows price/description changes on catalog rows ([cross-cutting review](e34d6186-8ff9-4b68-ad36-9537ca444eab))
5. **Eligible services silently dropped** — `searchEligibleServices` lacks `Map<dynamic,dynamic>` coercion ([data review](93c1bcc1-f608-47a4-8a3d-aaf59e97017e))
6. **Dead application code** — `PromotionValidation`, `serviceCatalogMessageForRpc` never imported ([domain review](fcf94306-3e79-473b-958f-147e13567a76))

---

## Feature Overview

### Purpose

Organization-scoped service catalog (015) with per-branch configuration (assignment, activation, price override, single time-boxed promotion). Invoice items are selected from the catalog; server resolves effective price and snapshots it at add-to-invoice time.

### Layer inventory

| Layer | Files | Role |
|-------|-------|------|
| `domain/` | 11 | Entities, value objects, wire parsers (`fromRow` / `fromRpcData`) |
| `data/` | 1 | Concrete `ServiceCatalogRepository` (14 RPC methods) + result DTOs |
| `application/` | 3 | Form/promotion validation, RPC error messages |
| `presentation/` | 6 | 3 notifiers, 2 models, 1 price-preview formatter |

**Missing from plan:** `presentation/pages/*`, `presentation/widgets/*`, `test/widget/service_catalog/*`, repository interface, use cases.

### Data flow

```
Presentation (notifiers) → Data (ServiceCatalogRepository) → Supabase RPCs
Billing (invoice_editor_notifier) → ServiceCatalogRepository.addInvoiceItemFromService
```

---

## 1. Critical Issues

### C-01 — Stale-conflict reload immediately undone

| Field | Detail |
|-------|--------|
| **Severity** | Critical |
| **Files** | `presentation/providers/service_editor_notifier.dart` |
| **Evidence** | On `STALE_SERVICE` / `STALE_SERVICE_BRANCH`, handler calls `await reloadDetail()` then overwrites with pre-mutation `current`: `state = AsyncData(current.copyWith(isSaving: false))`. Same pattern in 5 mutation methods. |
| **Why** | Optimistic concurrency UX is broken; fresh server data is fetched then discarded. |
| **Impact** | User retries fail with repeated stale errors; `updatedAt` tokens stay wrong. |
| **Solution** | After successful reload, return without overwriting, or set state from reloaded value. |

### C-02 — Create flow partial failure rolls back to empty create state

| Field | Detail |
|-------|--------|
| **Severity** | Critical |
| **Files** | `presentation/providers/service_editor_notifier.dart` (`createService`) |
| **Evidence** | `catch` restores `current` captured before create. If `create_service` succeeds but branch config or `get_service` fails, UI resets to create mode while service exists server-side. |
| **Impact** | Duplicate creates, orphaned services, lost pending branch config. |
| **Solution** | After `serviceId` known, set state to loaded detail (best-effort `getService`); never roll back to pre-create state. |

### C-03 — Out-of-order list loads can show stale results

| Field | Detail |
|-------|--------|
| **Severity** | Critical |
| **Files** | `presentation/providers/service_catalog_list_notifier.dart` |
| **Evidence** | No request generation token or cancellation in `applyFilters` / `reload`. |
| **Impact** | Wrong list after rapid filter/pagination changes. |
| **Solution** | Monotonic `_loadGeneration`; discard stale results. |

### C-04 — Entire presentation UI layer missing

| Field | Detail |
|-------|--------|
| **Severity** | Critical |
| **Files** | `app/router.dart`, `docs/specs/015-service-catalog/plan.md` |
| **Evidence** | Routes use `uiPendingPlaceholder`. Zero files under `presentation/pages/`, `presentation/widgets/`, `billing/presentation/widgets/invoice_items_editor.dart`. |
| **Impact** | US1–US7 undeliverable; notifiers have no production consumers. |
| **Solution** | Implement planned pages/widgets; replace router placeholders. |

### C-05 — `tasks.md` overstates completion

| Field | Detail |
|-------|--------|
| **Severity** | Critical (process) |
| **Files** | `docs/specs/015-service-catalog/tasks.md` |
| **Evidence** | T017–T018, T030–T032, T034, T038–T039, T041, T045, T047, T059 marked `[X]` but UI files and widget tests absent. |
| **Impact** | False release confidence; QA planning misses largest remaining work. |
| **Solution** | Reconcile tasks with repo reality. |

### C-06 — Free-text invoice item path not retired

| Field | Detail |
|-------|--------|
| **Severity** | Critical |
| **Files** | `billing/presentation/providers/invoice_editor_notifier.dart`, `billing/data/invoice_repository.dart` |
| **Evidence** | `addItem({description, quantity, unitPrice})` still calls `add_invoice_item`. Spec FR-012 requires free-text authoring removed. |
| **Impact** | Future UI can bypass catalog governance. |
| **Solution** | Remove or guard legacy path; route all authoring through `addItemFromService`. |

### C-07 — Snapshot unit price mutable after catalog add

| Field | Detail |
|-------|--------|
| **Severity** | Critical |
| **Files** | `backend/.../billing_us1_rpcs.sql` (`update_invoice_item`), `invoice_editor_notifier.dart`, `billing/domain/invoice_item.dart` |
| **Evidence** | `update_invoice_item` updates `unit_price` with no `service_id` check. `InvoiceItem` has no `serviceId` field. |
| **Impact** | Violates FR-013/FR-014 snapshot immutability. |
| **Solution** | Backend: reject price/description changes when `service_id IS NOT NULL`. Client: parse `serviceId`; quantity-only updates for catalog lines. |

---

## 2. High Priority Issues

### H-01 — `searchEligibleServices` drops rows when map type differs

| Field | Detail |
|-------|--------|
| **Files** | `data/service_catalog_repository.dart` (lines 307–315) |
| **Evidence** | Only handles `Map<String, dynamic>`; `listServices` also handles `Map<dynamic, dynamic>`. |
| **Impact** | Invoice selector shows empty results despite successful RPC. |
| **Solution** | Mirror dual-map handling from `listServices`. |

### H-02 — `configure_service_branch` null override clears existing override

| Field | Detail |
|-------|--------|
| **Files** | `data/service_catalog_repository.dart`, contract `branch-configuration.md` |
| **Evidence** | `p_price_override: priceOverride?.trim()` — null clears per contract. Status-only callers can silently wipe overrides. |
| **Solution** | Explicit `PriceOverrideIntent` (keep/clear/set); pass current override unless clearing. |

### H-03 — Malformed RPC responses throw `StateError`, not `RpcFailure`

| Field | Detail |
|-------|--------|
| **Files** | `data/service_catalog_repository.dart`, `application/service_catalog_rpc_messages.dart` |
| **Evidence** | `UNEXPECTED_RESPONSE` defined but never thrown; UI catching `RpcFailure` misses shape errors. |
| **Solution** | Standardize on `RpcFailure(UNEXPECTED_RESPONSE)`. |

### H-04 — `SERVICE_NOT_ELIGIBLE` has no user-facing message path in billing

| Field | Detail |
|-------|--------|
| **Files** | `invoice_editor_notifier.dart`, `billing_rpc_messages.dart` |
| **Evidence** | `_mutate` only special-cases `STALE_INVOICE`. `serviceCatalogMessageForRpc` handles `SERVICE_NOT_ELIGIBLE` but is unused. |
| **Solution** | Route catalog failures through appropriate message mapper. |

### H-05 — `ServiceEligibility` can be `eligible: true` with `price: null`

| Field | Detail |
|-------|--------|
| **Files** | `domain/service_eligibility.dart` |
| **Evidence** | `EffectivePrice.fromRpcData` can return null on malformed eligible payload. |
| **Impact** | Null deref in selector/preview consumers. |
| **Solution** | Treat parse failure as ineligible or enforce invariant in factory. |

### H-06 — `PromotionValidation` and `serviceCatalogMessageForRpc` are dead code

| Field | Detail |
|-------|--------|
| **Files** | `application/promotion_validation.dart`, `application/service_catalog_rpc_messages.dart` |
| **Evidence** | Zero call sites in `frontend/lib`. FR-008 client validation never runs. |
| **Solution** | Wire into notifiers/UI or remove until needed. |

### H-06b — `PromotionValidation.validatePrice` allows negative amounts

| Field | Detail |
|-------|--------|
| **Files** | `application/promotion_validation.dart` (lines 5–14) vs `service_form_validation.dart` (lines 28–29) |
| **Evidence** | Promotion validator checks parse success only; unlike `validateDefaultPrice`, no `isNegative` guard. |
| **Impact** | Invalid promotion prices pass client validation and fail only at RPC. |
| **Solution** | Align with default-price rules; reject negatives and comma separators. |

### H-07 — `updateService` multi-step mutation without rollback semantics

| Field | Detail |
|-------|--------|
| **Files** | `presentation/providers/service_editor_notifier.dart` |
| **Evidence** | Sequential update → assign → unassign → getService; generic catch restores full pre-call snapshot. |
| **Solution** | Application use case with partial-failure semantics; reload on any post-first-RPC failure. |

### H-08 — Route guards untested; editor mutations skip permission re-check

| Field | Detail |
|-------|--------|
| **Files** | `core/auth/auth_route_guard.dart`, `service_editor_notifier.dart` |
| **Evidence** | No `auth_route_guard_service_catalog_test.dart`. `canAccessServiceEditor` only in `build()`. |
| **Solution** | Add route guard tests; re-check permissions on each mutation. |

### H-09 — Zero widget tests; repository untested

| Field | Detail |
|-------|--------|
| **Files** | `frontend/test/widget/service_catalog/` (absent), no `service_catalog_repository_test.dart` |
| **Evidence** | 8 unit tests cover partial domain/notifier happy paths only. |
| **Solution** | Add repo tests with `FakePostgrestRpc`; widget tests per plan. |

### H-11 — `owner` role missing from service catalog permission seed

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **Files** | `backend/supabase/migrations/20260712090000_service_catalog.sql`, `permission_keys.dart` |
| **Evidence** | Plan seeds `owner`/`administrator`; migration seeds only `administrator`. Billing migration grants `owner` invoice permissions — owner is a first-class DB role. |
| **Impact** | Clinic owners cannot view or manage the catalog via RPC or route guards. |
| **Solution** | Add `('owner', 'services.view', true)` and `('owner', 'services.manage', true)` with `ON CONFLICT DO UPDATE`. |

### H-10 — Billing ↔ catalog coupling partial

| Field | Detail |
|-------|--------|
| **Files** | `invoice_editor_notifier.dart`, `service_selector_notifier.dart` |
| **Evidence** | `addItemFromService` exists; `serviceSelectorProvider` has no consumers. No `InvoiceServiceSelector` widget. |
| **Solution** | Build selector widget; wire billing editor. |

---

## 3. Medium Priority Issues

| ID | Issue | Files |
|----|-------|-------|
| M-01 | Silent row dropping in list/search parsers | Repository + domain `fromRow` |
| M-02 | Branch `status` is unvalidated raw `String` (vs `GlobalStatus` enum) | `service_branch_row.dart`, `service_branch_config.dart` |
| M-03 | List notifier lacks auth session watch | `service_catalog_list_notifier.dart` |
| M-04 | No search debounce on list notifier | `service_catalog_list_notifier.dart` |
| M-05 | Permission denied shows empty list, not error state | `service_catalog_list_notifier.dart` |
| M-06 | No domain repository interface | vs `PatientRepository` pattern |
| M-07 | Result DTOs live in data file | `service_catalog_repository.dart` |
| M-08 | `addInvoiceItemFromService` in catalog repo (SRP) | Should be in `InvoiceRepository` |
| M-09 | `ServiceBranchConfig`, `ServiceFormDraftSnapshot` unused | Orphan scaffolding |
| M-10 | Decimal scale ≤ 2 not enforced client-side | Validators claim it but `Money.tryParse` accepts 3+ decimals |
| M-11 | Shell nav exposes Services to all roles | `shell_nav_config.dart` |
| M-12 | Three repo methods unwired (`resolveEffectivePrice`, `copyConfiguration`, `setupNewBranchServices`) | Data layer only |
| M-13 | `ServicePromotion` allows `start > end`; no promo ≤ effective in domain | `service_promotion.dart` |
| M-14 | Timezone inconsistency in `isActiveOn` vs `_wireDate` | `service_promotion.dart` |
| M-15 | `serviceCatalogListProvider` global, not `autoDispose` | Stale cache risk |
| M-16 | `setBranchAssignment` returns one ID list, drops `service_id` and the other list from contract response | `service_catalog_repository.dart` |
| M-17 | `createService` does not guard `assignAllBranches: false` + empty `branchIds` at repository boundary | Extra server round-trip |
| M-19 | `Service` domain model omits `organizationId` (FR-001/FR-021) | Tenant scope not assertable client-side |
| M-20 | `ServiceFormValidation` wired only in tests, not production code | Same class of gap as dead `PromotionValidation` |
| M-21 | `ServicePromotion.isActiveOn` is a second pricing source of truth vs server (FR-026/NFR-008) | Use server `on_promotion` / resolve RPC for authoritative state |

---

## 4. Low Priority Issues

| ID | Issue |
|----|-------|
| L-01 | `ServiceListFilters.toRpcParams()` duplicates repository param assembly |
| L-02 | Wire status strings (`'active'`/`'inactive'`) leak into notifiers |
| L-03 | `ServicePricePreview` hardcodes `currency = 'USD'` |
| L-04 | `migrationHint` points only to pricing migration |
| L-05 | Router duplicates path string instead of using `AppRoutes` |
| L-06 | Redirect target inconsistency: billing → home, catalog → settings |
| L-07 | Dead wire getters on `ServicePromotion` |
| L-08 | `Service.fromRow` does not trim name at domain level |

---

## 5. Clean Architecture Violations

| Violation | Detail |
|-----------|--------|
| No repository interface | Presentation depends directly on concrete `ServiceCatalogRepository` |
| No use-case layer | Notifiers call repository directly; orchestration (assignment diffing, pending configs) in presentation |
| Wire parsing in domain | `fromRow`/`fromRpcData` couples domain to Supabase JSON shapes (project pattern, but blurs boundary) |
| Flutter in domain | 6/11 domain files import `flutter/foundation.dart` for `@immutable` |
| Billing → catalog data | `invoice_editor_notifier` imports catalog data layer, not a narrow port |
| Application layer unused | Validators and RPC messages not consumed by presentation |
| Result types in data | 8 result classes co-located with repository |

---

## 6. SOLID Violations

| Principle | Assessment |
|-----------|------------|
| **SRP** | `ServiceEditorNotifier` ~350 lines: load, create, update, delete, branch config, promotions. `ServiceCatalogRepository` owns catalog CRUD + invoice item creation. |
| **OCP** | Stale-handling duplicated 5× with same bug; hard to extend safely. |
| **ISP** | Billing depends on full repository for one method (`addInvoiceItemFromService`). |
| **DIP** | No abstraction between notifiers and repository; cannot swap implementations. |

---

## 7. Code Duplication & Redundancy

1. **Stale `RpcFailure` handlers** — identical block in 5 editor methods
2. **Save pattern** — `current` capture → `isSaving: true` → try/repo → catch revert (~7×)
3. **Date formatting** — triplicated across `ServicePromotion`, repository, `PromotionValidation`
4. **Price validation** — triplicated in form, promotion validators
5. **Dual branch models** — `ServiceBranchRow` vs unused `ServiceBranchConfig`
6. **`onPromotion` vs `appliedRule`** — redundant fields in `EligibleService`
7. **List notifier shape** — mirrors invoice/patient notifiers without auth watch hooks

**Recommendation:** Extract `_withSaving` / `_onStaleConflict` helpers or application-layer mutation coordinator. Consolidate price/date validators. Pick one branch config model.

---

## 8. Performance Issues

| Item | Severity |
|------|----------|
| N+1 RPCs in `_applyPendingBranchConfigurations` (configure + getService per branch) | Medium |
| `updateService` sequence: up to 4 RPCs | Medium |
| List search without debounce (once UI exists) | Medium |
| Selector: uncancelled in-flight searches | Low |
| Global list provider retains state across sessions | Low |

No N+1 within repository itself — each method is a single RPC.

---

## 9. Test Coverage Gaps

| Area | Present | Missing |
|------|---------|---------|
| Domain parsers | `Service`, `ServicePromotion.isActiveOn`, partial `ServiceEligibility` | 7 of 11 types; malformed payloads; silent drop cases |
| Application | `ServiceFormValidation` | `PromotionValidation`, `serviceCatalogMessageForRpc` |
| Repository | — | All 14 RPC wrappers, param mapping, map coercion |
| Notifiers | List/editor happy paths | Selector, stale conflicts, races, partial create failure, permission-denied mutations |
| Route guards | — | `serviceCatalogRouteRedirect`, editor vs list permissions |
| Billing integration | — | `addItemFromService`, snapshot behavior, `SERVICE_NOT_ELIGIBLE` |
| Widget | — | Entire `test/widget/service_catalog/` per plan |
| Backend SQL | CRUD, RLS, pricing, concurrency | `update_invoice_item` guard on `service_id` rows |

---

## 10. Recommended Refactoring (Prioritized)

### Phase 1 — Ship-blockers (before any UI merge)

1. Fix stale-conflict handler — stop overwriting post-`reloadDetail` state
2. Fix create partial-failure — persist detail after successful create
3. Add load generation to list notifier
4. Fix `searchEligibleServices` map coercion
5. Implement pages, widgets, billing `invoice_items_editor`
6. Retire free-text client API on invoice editor
7. Enforce snapshot immutability (backend + `InvoiceItem.serviceId`)

### Phase 2 — Architecture & UX hardening

8. Introduce `abstract class ServiceCatalogRepository` in domain
9. Wire `PromotionValidation` + `serviceCatalogMessageForRpc` into notifiers
10. Add `PriceOverrideIntent` to prevent accidental override clearing
11. Move `addInvoiceItemFromService` to `InvoiceRepository`
12. Extract application use cases for multi-RPC orchestration
13. Strengthen domain invariants (`ServiceEligibility`, `ServicePromotion`, `BranchStatus` enum)

### Phase 3 — Quality & consistency

14. Add repository + route guard + widget + integration tests
15. Permission-gate shell nav and editor mutations
16. Reconcile `tasks.md` with file inventory
17. Consolidate validators and stale-handling helpers
18. Add auth session watch to list notifier; consider `autoDispose`

---

## Review Sources

| Layer | Agent |
|-------|-------|
| Domain + Application | [domain review](fcf94306-3e79-473b-958f-147e13567a76), [domain review (pass 2)](a34092dc-1a40-4f5f-b8ba-7a86f5a1b436), [domain review (pass 3)](5b476d67-a723-4715-a50e-cc61f613dec5) |
| Data | [data repository review](93c1bcc1-f608-47a4-8a3d-aaf59e97017e), [data review (pass 2)](01e1c91f-bd95-4b33-983d-68c59daf0a4a) |
| Presentation | [presentation notifiers review](88939897-55e4-4fd9-b3eb-8a16a3a8555b) |
| Cross-cutting (billing, routing, DI, tests) | [integration review](e34d6186-8ff9-4b68-ad36-9537ca444eab), [integration review (pass 2)](3ba0897c-4472-429a-8486-924e8b8d41e6) |

---

## File Inventory

### `frontend/lib/features/service_catalog/` (21 files)

**Application (3):** `promotion_validation.dart`, `service_catalog_rpc_messages.dart`, `service_form_validation.dart`

**Data (1):** `service_catalog_repository.dart`

**Domain (11):** `effective_price.dart`, `eligible_service.dart`, `global_status.dart`, `pending_branch_configuration.dart`, `service.dart`, `service_branch_config.dart`, `service_branch_row.dart`, `service_detail.dart`, `service_eligibility.dart`, `service_list_item.dart`, `service_promotion.dart`

**Presentation (6):** `service_form_draft_snapshot.dart`, `service_list_filters.dart`, `service_catalog_list_notifier.dart`, `service_editor_notifier.dart`, `service_selector_notifier.dart`, `service_price_preview.dart`

### Tests (8 unit, 0 widget)

`permission_service_services_test.dart`, `pricing_preview_test.dart`, `service_catalog_list_notifier_test.dart`, `service_editor_notifier_test.dart`, `service_form_validation_test.dart`, `service_list_filters_test.dart`, `service_promotion_test.dart`, `service_test.dart`

### Cross-feature touchpoints

`invoice_editor_notifier.dart`, `auth_route_guard.dart`, `permission_service.dart`, `permission_keys.dart`, `app_routes.dart`, `router.dart`, `shell_nav_config.dart`

---

# Cycle 2 Review — 2026-07-05

**Method:** Four parallel skeptical re-reviews ([domain + application](93ef54b0-def2-46b1-bb19-b5aa4be99086), [data](bc9ba2b3-9cb2-4c46-a0e7-045f03d778de), [presentation](f7e17295-df75-4e5e-a7c1-31715bc4187a), [cross-cutting](c439b187-4eb4-429e-a069-432cac2eafc9)). Every Cycle 1 finding re-verified against current code.

**Cycle 2 verdict:** **No Cycle 1 issues were fixed.** The feature remains a logic-layer scaffold (~58% cross-cutting shippability). Backend catalog RPCs are solid; client integration, notifier concurrency, snapshot governance, and all UI are not production-ready.

| Layer | Cycle 2 readiness | Key blocker |
|-------|-------------------|-------------|
| Domain + Application | Scaffolding only | Validators/RPC messages 100% unwired; weak invariants |
| Data | ~70% | Map coercion gap, override clearing, zero repo tests |
| Presentation | ~40% | Stale-reload, create rollback, list races; no UI |
| Cross-cutting | ~58% | Free-text invoice path, snapshot update gap, tasks.md drift |

---

## Cycle 2 — Critical Issues

### D2-C01 — Stale-conflict reload immediately undone
| Field | Detail |
|-------|--------|
| **Status** | CONFIRMED (C-01) |
| **Files** | `presentation/providers/service_editor_notifier.dart` |
| **Evidence** | Five mutation methods call `await reloadDetail()` on `STALE_SERVICE` / `STALE_SERVICE_BRANCH`, then overwrite with pre-mutation `current.copyWith(isSaving: false)`. |
| **Impact** | Fresh `updatedAt` tokens discarded; repeated stale errors on retry. |
| **Solution** | After successful reload, return without overwriting; or assign state from reloaded value. |

### D2-C02 — Create flow partial failure rolls back to empty create state
| Field | Detail |
|-------|--------|
| **Status** | CONFIRMED (C-02) |
| **Files** | `presentation/providers/service_editor_notifier.dart` (`createService`, `_applyPendingBranchConfigurations`) |
| **Evidence** | `catch` restores `current` captured before create. Post-`create_service` failures (branch config, `getService`) reset UI to create mode while service may exist server-side with partial branch config. |
| **Impact** | Orphaned services, duplicate creates, lost pending branch config. |
| **Solution** | After `serviceId` known, never roll back to pre-create state; persist loaded or partial-success detail. |

### D2-C03 — Out-of-order list loads can show stale results
| Field | Detail |
|-------|--------|
| **Status** | CONFIRMED (C-03) |
| **Files** | `presentation/providers/service_catalog_list_notifier.dart` |
| **Evidence** | `applyFilters` / `reload` have no load-generation token or cancellation. |
| **Impact** | Wrong list after rapid filter/pagination changes; `_filters` and `state` can disagree. |
| **Solution** | Monotonic `_loadGeneration`; discard stale results. |

### D2-C04 — Entire presentation UI layer missing
| Field | Detail |
|-------|--------|
| **Status** | CONFIRMED (C-04) |
| **Files** | `presentation/` (6 logic files only), `app/router.dart`, billing widgets |
| **Evidence** | Zero files under `presentation/pages/`, `presentation/widgets/`, `billing/presentation/widgets/`. Router uses `uiPendingPlaceholder`. `serviceSelectorProvider` has zero consumers. |
| **Impact** | US1–US7 undeliverable; notifiers have no production consumers. |
| **Solution** | Implement planned pages/widgets; replace router placeholders; wire billing selector. |

### D2-C05 — `tasks.md` falsely marks UI/integration work complete
| Field | Detail |
|-------|--------|
| **Status** | CONFIRMED (C-05) |
| **Files** | `docs/specs/015-service-catalog/tasks.md` |
| **Evidence** | T017–T018, T030–T032, T034, T038–T039, T041, T045, T047, T059 marked `[X]` but UI files and widget tests absent. T006 still references `owner` role seeding — `owner` removed in `20260611150000_remove_owner_role.sql`. |
| **Impact** | False release confidence; ~15 tasks marked done but not implemented. |
| **Solution** | Reconcile every `[X]` against file inventory; update spec from `owner` → `administrator`. |

### D2-C06 — Free-text invoice authoring path still live
| Field | Detail |
|-------|--------|
| **Status** | CONFIRMED (C-06) |
| **Files** | `billing/presentation/providers/invoice_editor_notifier.dart`, `billing/data/invoice_repository.dart` |
| **Evidence** | `addItem` / `updateItem` still call `add_invoice_item` / `update_invoice_item` with free-text fields. `addItemFromService` exists alongside them. |
| **Impact** | FR-012 violated; future billing UI can bypass catalog governance. |
| **Solution** | Remove or guard legacy path; route all authoring through `addItemFromService`. |

### D2-C07 — Snapshot immutability unenforced end-to-end
| Field | Detail |
|-------|--------|
| **Status** | CONFIRMED (C-07, expanded) |
| **Files** | `backend/.../billing_us1_rpcs.sql`, `billing/domain/invoice_item.dart`, `invoice_editor_notifier.dart` |
| **Evidence** | `update_invoice_item` updates `unit_price`/`description` with no `service_id` check. `get_invoice_detail` omits `service_id`. `InvoiceItem` has no `serviceId`; `updateItem` accepts mutable price/description. |
| **Impact** | FR-013/FR-014 violated; catalog-linked lines can be altered post-add. |
| **Solution** | Backend: reject price/description changes when `service_id IS NOT NULL`; include `service_id` in detail payload. Client: parse `serviceId`; quantity-only updates for catalog lines. |

---

## Cycle 2 — High Priority Issues

| ID | Issue | Files | Status |
|----|-------|-------|--------|
| D2-H01 | `searchEligibleServices` drops `Map<dynamic,dynamic>` rows | `service_catalog_repository.dart` | CONFIRMED (H-01) |
| D2-H02 | `configureServiceBranch` null override clears existing override | Repository + backend RPC | CONFIRMED (H-02) |
| D2-H03 | Malformed RPC responses throw `StateError`, not `RpcFailure` | `service_catalog_repository.dart` | CONFIRMED (H-03) |
| D2-H04 | Application validators + `serviceCatalogMessageForRpc` entirely unwired | `application/*`, all notifiers | CONFIRMED (H-06, M-20) |
| D2-H05 | `PromotionValidation.validatePrice` accepts negatives | `promotion_validation.dart` | CONFIRMED (H-06b) |
| D2-H06 | `ServiceEligibility` allows `eligible: true` with `price: null` | `service_eligibility.dart` | CONFIRMED (H-05) |
| D2-H07 | `updateService` multi-step mutation without partial-failure semantics | `service_editor_notifier.dart` | CONFIRMED (H-07) |
| D2-H08 | Editor mutations skip permission re-check | `service_editor_notifier.dart` | CONFIRMED (H-08) |
| D2-H09 | `serviceSelectorProvider` has no consumers; no selector tests | `service_selector_notifier.dart` | CONFIRMED (H-10, H-09) |
| D2-H10 | `SERVICE_NOT_ELIGIBLE` has no billing error path | `invoice_editor_notifier.dart` | CONFIRMED (H-04) |
| D2-H11 | Billing depends on catalog data layer directly | `invoice_editor_notifier.dart` | CONFIRMED (M-08) |
| D2-H12 | Service catalog route guards untested | `auth_route_guard.dart` | CONFIRMED (H-08) |
| D2-H13 | Zero repository + billing integration tests | `frontend/test/` | CONFIRMED (H-09) |
| D2-H14 | Pending branch config during create can partially apply then roll back UI | `service_editor_notifier.dart` | NEW |
| D2-H15 | Spec/tasks still reference `owner` role (superseded as runtime bug) | `spec.md`, `tasks.md` | SUPERSEDED (H-11) |

---

## Cycle 2 — Medium Priority Issues

| ID | Issue | Files | Status |
|----|-------|-------|--------|
| D2-M01 | Silent row dropping in list/detail/search parsers | Domain parsers + repository | CONFIRMED (M-01) |
| D2-M02 | Branch `status` is unvalidated raw `String` | `service_branch_row.dart` | CONFIRMED (M-02) |
| D2-M03 | `Service` omits `organizationId` (FR-001/FR-021) | `service.dart` | CONFIRMED (M-19) |
| D2-M04 | Decimal scale ≤ 2 not enforced client-side | Validators + `Money` | CONFIRMED (M-10) |
| D2-M05 | `ServicePromotion.tryParse` allows inverted dates / negatives | `service_promotion.dart` | CONFIRMED (M-13) |
| D2-M06 | Timezone inconsistency in `isActiveOn` vs `_wireDate` | `service_promotion.dart` | CONFIRMED (M-14) |
| D2-M07 | `isActiveOn` is second pricing source of truth vs server | `service_promotion.dart` | CONFIRMED (M-21) |
| D2-M08 | `ServiceBranchConfig` / `ServiceFormDraftSnapshot` orphaned | Domain + presentation models | CONFIRMED (M-09) |
| D2-M09 | No domain repository interface (DIP) | Domain (missing) | CONFIRMED (M-06) |
| D2-M10 | List notifier lacks auth session watch | `service_catalog_list_notifier.dart` | CONFIRMED (M-03) |
| D2-M11 | Permission denied shows empty list, not error | `service_catalog_list_notifier.dart` | CONFIRMED (M-05) |
| D2-M12 | No search debounce on list notifier | `service_catalog_list_notifier.dart` | CONFIRMED (M-04) |
| D2-M13 | `serviceCatalogListProvider` global, not `autoDispose` | `service_catalog_list_notifier.dart` | CONFIRMED (M-15) |
| D2-M14 | Shell nav exposes Services to all roles | `shell_nav_config.dart` | CONFIRMED (M-11) |
| D2-M15 | `setBranchAssignment` lacks stale-conflict handling | `service_editor_notifier.dart` | NEW |
| D2-M16 | `updateService` branch sub-RPCs don't handle `STALE_SERVICE_BRANCH` | `service_editor_notifier.dart` | NEW |
| D2-M17 | Selector debounce-only guard allows brief stale results | `service_selector_notifier.dart` | NEW |
| D2-M18 | `searchEligibleServices` treats malformed `items` as empty success | `service_catalog_repository.dart` | NEW |
| D2-M19 | `setBranchAssignment` discards contract response fields | `service_catalog_repository.dart` | CONFIRMED (M-16) |
| D2-M20 | Whitespace-only price strings sent as `""` to numeric RPC params | `service_catalog_repository.dart` | NEW |
| D2-M21 | Three repo methods unwired (`resolveEffectivePrice`, `copyConfiguration`, `setupNewBranchServices`) | `service_catalog_repository.dart` | CONFIRMED (M-12) |
| D2-M22 | Domain parsers don't enforce non-negative money (FR-006) | Domain factories | NEW |
| D2-M23 | `validateAgainstEffective` silently passes on parse failure | `promotion_validation.dart` | NEW |
| D2-M24 | `onPromotion` vs `appliedRule` inconsistency accepted | `eligible_service.dart`, `service_list_item.dart` | NEW |
| D2-M25 | Router edit path hardcoded; bypasses `AppRoutes` | `router.dart` | NEW |
| D2-M26 | Inconsistent permission-denied redirect targets (billing vs catalog) | `auth_route_guard.dart` | NEW |
| D2-M27 | Invoice edit route gated on `invoices.view`, not `invoices.create` | `auth_route_guard.dart` | NEW |
| D2-M28 | Backend tests omit `update_invoice_item` snapshot guard | `backend/tests/` | NEW |

---

## Cycle 2 — Conclusions

**Fixed since Cycle 1:** None across all layers.

**New findings (Cycle 2 only):** 10 items — partial branch-config rollback (D2-H14), stale handling gaps in `setBranchAssignment`/`updateService` (D2-M15/16), selector race window (D2-M17), malformed `items` as empty success (D2-M18), whitespace price strings (D2-M20), domain negative-money gap (D2-M22), `validateAgainstEffective` parse-fail bypass (D2-M23), `onPromotion`/`appliedRule` inconsistency (D2-M24), routing/auth gaps (D2-M25–27), backend snapshot test gap (D2-M28).

**Ship-blockers (unchanged priority):**
1. Fix notifier concurrency bugs (D2-C01–C03)
2. Implement UI + billing integration (D2-C04)
3. Retire free-text invoice path (D2-C06)
4. Enforce snapshot immutability backend + client (D2-C07)
5. Fix `searchEligibleServices` map coercion (D2-H01)
6. Reconcile `tasks.md` (D2-C05)

**Architecture debt (unchanged):** Application layer dead code, no repository interface, billing→catalog data coupling, `StateError` vs `RpcFailure` inconsistency, duplicated stale/save patterns in editor notifier.

---

## Cycle 2 Review Sources

| Layer | Agent |
|-------|-------|
| Domain + Application | [Cycle 2 domain review](93ef54b0-def2-46b1-bb19-b5aa4be99086) |
| Data | [Cycle 2 data review](bc9ba2b3-9cb2-4c46-a0e7-045f03d778de) |
| Presentation | [Cycle 2 presentation review](f7e17295-df75-4e5e-a7c1-31715bc4187a) |
| Cross-cutting | [Cycle 2 integration review](c439b187-4eb4-429e-a069-432cac2eafc9) |
