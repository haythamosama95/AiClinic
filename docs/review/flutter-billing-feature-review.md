# Flutter Billing Feature — Code Review

**Date:** 2026-07-05  
**Scope:** All 24 files under `frontend/lib/features/billing/`, routing/auth integration, 7 unit tests under `frontend/test/unit/billing/`, `auth_route_guard_billing_test.dart`, `billing_rpc_test_client.dart`  
**Maturity:** Logic-layer only — billing routes exist but all screens are `uiPendingPlaceholder`

---

## Executive Summary

The billing feature delivers a coherent V1-6 backend integration: domain value objects and entities, four RPC repositories, Riverpod notifiers/providers, and route-guard wiring. It aligns with **service_catalog** (concrete repos, notifiers own orchestration) more than **patients** (repository interfaces + use cases).

The implementation is structurally sound for a pre-UI vertical slice, but several issues undermine correctness, security boundaries, and maintainability before screens land:

1. **Not production-ready for UI wiring** — [presentation review](3a03caeb-ec66-4c26-abfb-2788b9260a15) rates the layer repository wiring with Riverpod types; Phase 1 auth/concurrency fixes are blocking.
2. **4 critical issues** — unguarded detail fetch; silent parse data loss; concurrent editor mutations; edit route gated by `invoices.view` only (not `invoices.create`).
3. **Data-layer parsing hazards** — [data review](8d866d32-7b9d-4056-b47a-841bfa515586): `result.data?.toString()` can return garbage IDs; `StateError` vs `RpcFailure` inconsistency bypasses `billingMessageForRpc`; wrong `migrationHint` on three repos.
4. **Domain coercion bugs** — [domain review](5afcb7d5-9997-4517-bbca-3627e5001b41): `Money.tryParse('')` → zero defeats `fromRow` null guards; missing quantity defaults to `'0'`; discount-scope rules live in presentation not domain.
5. **Convention drift vs patients** — no repository interfaces or use-case layer; presentation imports `data/` directly.
6. **Cross-feature coupling** — `service_catalog` → billing `Money` + `BillingFormatting`; billing editor → `service_catalog` data.
7. **Test mismatch** — `BillingRpcTestClient` (~680 lines) barely exercised; **zero notifier tests**.

Remediation should prioritize: remove dangerous ID fallbacks, fix `Money.tryParse` semantics, auth-gate detail/edit/settings mutations, serialize editor mutations, wire `billingMessageForRpc`, and expand repo/notifier tests before UI ships.

---

## Feature Overview

### Purpose

Organization-scoped clinic billing (V1-6): draft invoices from visits, line items (catalog-integrated), discounts (line vs invoice scope), insurance coverage, issue/void lifecycle, payments/refunds, insurance provider catalog, and org billing settings (partial payments policy).

### Layer inventory

| Layer | Files | Role |
|-------|-------|------|
| `domain/` | 12 | `Money`, enums, entities with wire parsing (`fromRow` / `fromRpcData`) |
| `data/` | 4 | Concrete RPC repositories + Riverpod providers |
| `application/` | 1 | `billingMessageForRpc` only |
| `presentation/` | 7 | Notifiers/providers, `InvoiceListFilters`, `BillingFormatting` |

**Missing:** `presentation/screens/`, `presentation/widgets/`, use cases, repository interfaces.

### Data flow

```
Presentation (notifiers/providers)
    → Data (concrete repositories)
        → Supabase RPCs
    ↔ service_catalog (editor adds items via catalog repo)
```

---

## 1. Critical Issues

### C-01 — `invoiceDetailViewProvider` fetches data without auth gate

| Field | Detail |
|-------|--------|
| **Severity** | Critical |
| **Files** | `presentation/providers/invoice_detail_provider.dart` |
| **Evidence** | Provider calls `getDetail(invoiceId: id)` unconditionally; `AuthRouteGuard.canAccessInvoiceDetail` is never checked. Compare with `invoiceListProvider` and `patientInvoicesProvider`, which return empty when unauthorized. |
| **Why** | A user without billing list permission can still trigger an RPC if they obtain an invoice ID (deep link, patient context leak, dev tools). |
| **Impact** | Unauthorized invoice data exposure; inconsistent with route guard intent. |
| **Solution** | Guard fetch: if `!AuthRouteGuard.canAccessInvoiceDetail(auth)`, throw `ForbiddenException` or return a sealed error state. Mirror `patientInvoicesProvider` pattern. |

---

### C-02 — Silent dropping of malformed line items and payments

| Field | Detail |
|-------|--------|
| **Severity** | Critical |
| **Files** | `domain/invoice_detail.dart` (`_parseItems`, `_parsePayments`), `domain/invoice_item.dart`, `domain/payment.dart` |
| **Evidence** | `fromRow` returns `null` on invalid rows; parent parsers use `.whereType<InvoiceItem>()` / `.whereType<Payment>()`, silently omitting bad rows. Invoice envelope still succeeds with partial data. |
| **Why** | Server contract drift or corrupt payloads produce invoices that appear valid but omit payments or line items. |
| **Impact** | User records payment, UI shows old balance; financial totals disagree with backend; debugging is extremely hard. |
| **Solution** | Fail the entire envelope if any child row fails parse, or collect parse warnings and surface `ParseWarning` on `InvoiceDetail`. Add parsing tests with intentionally bad child rows. |

---

### C-03 — Concurrent `_mutate` calls corrupt editor state

| Field | Detail |
|-------|--------|
| **Severity** | Critical |
| **Files** | `presentation/providers/invoice_editor_notifier.dart` |
| **Evidence** | `_mutate` sets `isMutating: true` with no mutex, generation token, or re-entry guard. On failure it restores the pre-mutation snapshot while another mutation may still be in flight. |
| **Why** | Double-tap or overlapping actions (quantity + remove) use the same `expectedUpdatedAt`; failure of one restores `isMutating: false` during an active RPC. |
| **Impact** | Misleading loading state, spurious `STALE_INVOICE` errors, possible duplicate catalog adds. |
| **Solution** | Serialize mutations (queue/lock); track generation; ignore calls while `isMutating`. |

---

### C-04 — Edit route gated by `invoices.view` only

| Field | Detail |
|-------|--------|
| **Severity** | Critical (security/UX) |
| **Files** | `core/auth/auth_route_guard.dart`, `presentation/providers/invoice_editor_notifier.dart` |
| **Evidence** | `/billing/invoices/:id/edit` uses `canAccessInvoiceDetail` → `canViewInvoices()`. Editor `build()` has no `canCreateInvoices()` gate. Spec FR-031 requires `invoices.create` for mutations. |
| **Why** | View-only users can reach the editor; backend `FORBIDDEN` is the only guard. |
| **Impact** | Least-privilege routing violated; confusing error UX once UI ships. |
| **Solution** | Add `canAccessInvoiceEdit` requiring `canCreateInvoices()`; gate `invoiceEditorProvider.build()`. |

---

## 2. High Priority Issues

### H-01 — Presentation depends directly on data layer (no use-case / interface boundary)

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **Files** | All 6 `presentation/providers/*.dart` |
| **Evidence** | e.g. `invoice_list_notifier.dart` imports `invoice_repository.dart`; patients use `domain/usecases/*` instead. |
| **Why** | Violates dependency rule: UI orchestration is coupled to Supabase RPC implementation. |
| **Impact** | Notifiers cannot be tested against fakes without `overrideWithValue`; diverges from patients/settings/auth conventions. |
| **Solution** | Add `domain/repositories/invoice_repository.dart` (etc.) + thin use cases; bind `*RepositoryImpl` in data layer. |

---

### H-02 — No repository abstractions (convention drift from patients)

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **Files** | `data/invoice_repository.dart`, `payment_repository.dart`, `billing_settings_repository.dart`, `insurance_provider_repository.dart` |
| **Evidence** | Billing repos are concrete classes; patients define `PatientRepository` interface + `PatientRepositoryImpl`. |
| **Impact** | Harder to mock; inconsistent project patterns. |
| **Solution** | Mirror patients: interfaces in `domain/repositories/`, `implements` in data. |

---

### H-03 — Cross-feature: billing editor → service_catalog data

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **Files** | `presentation/providers/invoice_editor_notifier.dart` |
| **Evidence** | Imports `service_catalog/data/service_catalog_repository.dart`; `addItemFromService` calls `_catalogRepo.addInvoiceItemFromService(...)`. |
| **Why** | Feature presentation reaches into another feature's data layer. |
| **Impact** | Circular coupling risk; billing cannot be understood in isolation. |
| **Solution** | Application-layer `AddCatalogServiceToInvoice` use case with narrow ports (`InvoiceWriter`, `CatalogItemAdder`). |

---

### H-04 — Cross-feature: service_catalog → billing presentation

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **Files** | `service_catalog/presentation/utils/service_price_preview.dart` → `billing/presentation/utils/billing_formatting.dart` |
| **Evidence** | `ServicePricePreview.formatUnitPrice` delegates to `BillingFormatting.formatMoney`. |
| **Why** | Inverted dependency: catalog depends on billing **presentation** utilities. |
| **Impact** | Feature DAG violation; refactoring billing UI utils breaks catalog. |
| **Solution** | Extract `Money` + currency formatting to `core/` or `shared/`; both features depend on shared kernel only. |

---

### H-05 — `billingMessageForRpc` is dead code in production

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **Files** | `application/billing_rpc_messages.dart` |
| **Evidence** | `billingMessageForRpc` referenced only in `billing_rpc_messages_test.dart`, not in any `lib/` file. Notifiers rethrow `RpcFailure` raw or use generic `InvoiceStaleException`. |
| **Why** | Error translation layer built but not wired. |
| **Impact** | When UI arrives, risk of raw RPC messages or duplicated error strings. |
| **Solution** | Notifiers catch `RpcFailure` and surface `billingMessageForRpc(failure)` via state error fields. |

---

### H-06 — Rich test fake, thin test suite

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **Files** | `test/support/billing_rpc_test_client.dart` vs 6 billing unit tests |
| **Evidence** | Fake implements `record_payment`, `record_refund`, `void_invoice`, discount scope conflict, partial payments — none covered by repo tests. |
| **Impact** | Payment/refund/void/discount regressions undetected on client. |
| **Solution** | Add `payment_repository_test.dart`; expand `invoice_repository_test.dart` for `getDetail`, `voidInvoice`, stale paths. |

---

### H-07 — Zero notifier tests (vs service_catalog precedent)

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **Files** | All billing notifiers/providers |
| **Evidence** | `service_catalog_list_notifier_test.dart`, `service_editor_notifier_test.dart` exist; no billing equivalents. |
| **Why** | Auth gating, filter→RPC mapping, `_mutate` stale flow, settings rollback untested. |
| **Impact** | Highest-risk client logic ships without tests. |
| **Solution** | Port service_catalog pattern: `ProviderContainer` + `authSessionProvider.overrideWith` + repo fake. Priority: `InvoiceEditorNotifier`, `InvoiceListNotifier`, `BillingSettingsNotifier`. |

---

### H-08 — `activeInsuranceProvidersProvider` lacks auth check

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **Files** | `presentation/providers/insurance_providers_notifier.dart` |
| **Evidence** | `activeInsuranceProvidersProvider` calls `listProviders(onlyActive: true)` with no `AuthRouteGuard` check; `insuranceProvidersProvider` is gated. |
| **Why** | Editor insurance selector may fetch provider catalog for users lacking `insurance.manage` or billing access. |
| **Impact** | Unnecessary RPC; potential data exposure depending on backend RLS. |
| **Solution** | Gate with `canAccessInvoiceList` or `canApplyDiscount`; or derive active list from gated `insuranceProvidersProvider`. |

---

### H-09 — `result.data?.toString()` fallback returns garbage IDs

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **Files** | `data/invoice_repository.dart`, `data/payment_repository.dart`, `data/insurance_provider_repository.dart` |
| **Evidence** | `result.data?['invoice_id']?.toString() ?? result.data?.toString()` — on `{}` or wrong-key map, `toString()` yields `{foo: bar}` which passes non-empty guard. |
| **Impact** | Invalid IDs propagated to navigation/mutations; failures surface as cryptic UUID errors. |
| **Solution** | Remove `?? result.data?.toString()` fallback; require explicit key; throw `RpcFailure(UNEXPECTED_RESPONSE)`. |

---

### H-10 — Inconsistent malformed-success handling (`StateError` vs `RpcFailure`)

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **Files** | `data/invoice_repository.dart`, `payment_repository.dart`, `insurance_provider_repository.dart` vs `billing_settings_repository.dart` |
| **Evidence** | `getDetail` throws `StateError` on bad shape; `BillingSettingsRepository.get()` throws `RpcFailure(UNEXPECTED_RESPONSE)`. |
| **Impact** | `billingMessageForRpc` never maps shape failures when wired later. |
| **Solution** | Standardize all malformed-success paths on `RpcFailure(UNEXPECTED_RESPONSE)`. |

---

### H-11 — Wrong `migrationHint` on payment, settings, and insurance repos

| Field | Detail |
|-------|--------|
| **Severity** | High (operability) |
| **Files** | `data/payment_repository.dart`, `billing_settings_repository.dart`, `insurance_provider_repository.dart` |
| **Evidence** | All point to `20260605180000_billing.sql` (triggers only); RPCs live in `*_us2_payment_rpcs.sql`, `*_us4_insurance_rpcs.sql`, etc. |
| **Impact** | `RPC_NOT_APPLIED` errors cite wrong migration file during incidents. |
| **Solution** | Point each repo at the migration defining its RPCs (invoice repo already correct). |

---

### H-12 — `Money.tryParse('')` returns zero, defeating `fromRow` null guards

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **Files** | `domain/money.dart`, all monetary `fromRow` parsers |
| **Evidence** | `parse('')` returns `zero`; `tryParse` only returns `null` for `null` input. Empty wire string `"balance": ""` passes validation as `$0.00`. Tests encode this behavior. |
| **Impact** | Corrupt RPC rows produce plausible zero-balance invoices instead of parse failure. |
| **Solution** | `tryParse` → `null` for null/empty/invalid; add explicit `parseOrZero` only where semantically valid. |

---

### H-13 — `InvoiceItem.fromRow` defaults missing quantity to `'0'`

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **Files** | `domain/invoice_item.dart` |
| **Evidence** | `quantity: row['quantity']?.toString() ?? '0'` — DB constraint is `quantity > 0`. |
| **Impact** | Invalid line items enter domain model. |
| **Solution** | Reject null, empty, or non-positive quantity. |

---

### H-14 — Settings mutations lack `canManageBillingSettings` gate

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **Files** | `presentation/providers/billing_settings_notifier.dart` |
| **Evidence** | `build()` uses `canAccessBillingSettings` (view OR record); `updateAllowPartialPayments` has no `canManageBillingSettings()` check. |
| **Impact** | Users with `payments.record` only can trigger update RPC; raw errors after loading flash. |
| **Solution** | Early return in `updateAllowPartialPayments`; expose `canManage` on view state. |

---

### H-15 — `reload()` methods bypass auth guards in `build()`

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **Files** | `billing_settings_notifier.dart`, `insurance_providers_notifier.dart` |
| **Evidence** | `reload()` calls repository directly without re-checking `AuthRouteGuard`. |
| **Impact** | After permission revocation, manual reload still hits backend. |
| **Solution** | Shared `_guardedLoad()` used by `build()` and `reload()`. |

---

### H-16 — `billingMessageForRpc` discards admin-useful `RPC_NOT_APPLIED` detail

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **Files** | `application/billing_rpc_messages.dart`, `core/rpc/app_rpc_invoker.dart` |
| **Evidence** | `AppRpcInvoker` embeds migration filename in `failure.message` for missing RPCs; `billingMessageForRpc` maps `RPC_NOT_APPLIED` to generic copy, discarding the hint. |
| **Impact** | Even after wiring error mapping, admins lose deployment diagnostics needed to fix missing migrations. |
| **Solution** | Pass through `failure.message` for `RPC_NOT_APPLIED` / `RPC_NOT_CONFIGURED` when non-empty (same pattern as `INVALID_INPUT`). |

---

## 3. Medium Priority Issues

### M-01 — Wire-format parsing lives in domain entities

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **Files** | `domain/invoice_detail.dart`, `invoice_list_item.dart`, `invoice_item.dart`, `payment.dart`, `billing_settings.dart`, `insurance_provider.dart` |
| **Evidence** | `InvoiceDetail.fromRpcData`, `InvoiceListItem.fromRow` know RPC JSON field names (`branch_id`, `partially_paid`). |
| **Why** | Domain entities know infrastructure wire shape. |
| **Impact** | Domain changes when API shape changes. |
| **Solution** | Data-layer mappers returning domain types; keep domain free of `Map<String,dynamic>`. |

---

### M-02 — `InvoiceListPageResult` leaked into presentation API

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **Files** | `data/invoice_repository.dart`, `presentation/providers/invoice_detail_provider.dart` |
| **Evidence** | `patientInvoicesProvider` returns `InvoiceListPageResult` defined in data layer. |
| **Solution** | Move pagination envelope to domain or define `PatientInvoiceHistory` in domain/application. |

---

### M-03 — `Money` depends on Flutter foundation

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **Files** | `domain/money.dart`, all domain entities using `@immutable` from `package:flutter/foundation.dart` |
| **Evidence** | `import 'package:flutter/foundation.dart'` in domain layer. |
| **Why** | Domain is not framework-agnostic; blocks pure Dart unit tests without Flutter binding in some setups. |
| **Impact** | `Money` used across `service_catalog` domain — Flutter coupling spreads. |
| **Solution** | Use `meta` package `@immutable` or plain Dart; move `Money` to `core/money/`. |

---

### M-04 — `Money.parse('')` returns zero silently

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **Files** | `domain/money.dart` |
| **Evidence** | `if (trimmed.isEmpty) { return zero; }` in `parse()`. |
| **Why** | Empty user input becomes valid zero amount; differs from repo `_assertPositiveDecimal` which rejects empty. |
| **Impact** | Client-side validation inconsistency; accidental zero amounts if UI uses `Money.parse` on empty fields. |
| **Solution** | `parse` should throw on empty; keep `fromWire` lenient for nullable server fields. |

---

### M-05 — `double.tryParse` validation vs `Money`/`Decimal` domain type

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **Files** | `data/invoice_repository.dart`, `data/payment_repository.dart` |
| **Evidence** | Repos validate money as `double`; domain uses `Decimal` with scale-2 wire format. Comma separators rejected by `Money` but not checked in repos. |
| **Solution** | Validate via `Money.parse` / `Money.tryParse` in application or shared validation. |

---

### M-06 — Copy-pasted RPC input assertions across repositories

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **Files** | `invoice_repository.dart`, `payment_repository.dart`, `insurance_provider_repository.dart` |
| **Evidence** | Identical `_assertNonEmpty`, overlapping `_assertPositiveDecimal` / `_assertNonNegativeDecimal`. |
| **Solution** | Shared `core/rpc/input_assertions.dart` or `Money`-based validation helper. |

---

### M-07 — `InvoiceRepository` god object (SRP / ISP)

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **Files** | `data/invoice_repository.dart` (~300 lines, 15+ public methods) |
| **Evidence** | Single class: create, items CRUD, discounts, insurance, void, list, detail, `findForVisit`. |
| **Solution** | Split by aggregate concern or use-case facades. |

---

### M-08 — Duplicate insurance provider fetch paths

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **Files** | `presentation/providers/insurance_providers_notifier.dart` |
| **Evidence** | `insuranceProvidersProvider` (auth-gated, `onlyActive: false`) vs `activeInsuranceProvidersProvider` (no auth, `onlyActive: true`, separate RPC). |
| **Solution** | Single provider with param; client-side filter for active. |

---

### M-09 — Double round-trip on every editor mutation

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **Files** | `presentation/providers/invoice_editor_notifier.dart` |
| **Evidence** | `_mutate` always `await _repo.getDetail(invoiceId: _invoiceId)` after each RPC. |
| **Impact** | 2× latency per editor action. |
| **Solution** | Return updated envelope from RPC where backend supports it; debounce quantity edits. |

---

### M-10 — No list filter debounce (comment claims otherwise)

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **Files** | `presentation/providers/invoice_list_notifier.dart` line 29 |
| **Evidence** | Comment: "Paginated invoice list with debounced filters"; `applyFilters` has no debounce/timer. |
| **Impact** | UI will fire RPC per keystroke on patient search. |
| **Solution** | 300ms debounce in notifier (match spec NFR-002) or fix comment. |

---

### M-11 — Orphan repository APIs (no tests, no callers)

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **Files** | `data/invoice_repository.dart` — `createFromVisit`, `voidInvoice` |
| **Evidence** | Not referenced outside data layer; visits feature has no billing integration. |
| **Solution** | Add visit integration notifier + tests, or document as backend-only until visits wires it. |

---

### M-12 — Domain RPC parsing largely untested

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **Files** | `invoice_detail.dart`, `invoice_list_item.dart`, `invoice_item.dart` |
| **Evidence** | Patients have extensive `fromRpcData` tests; billing has none for main aggregates. |
| **Solution** | `billing_domain_parsing_test.dart` with golden JSON fixtures. |

---

### M-13 — `InvoiceListItem.displayTotal` ignores insurance

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **Files** | `domain/invoice_list_item.dart` |
| **Evidence** | `displayTotal => (subtotal - discountAmount).wireValue` — does not subtract `insuranceCoveredAmount`. |
| **Why** | List row "total" may disagree with patient-facing balance semantics. |
| **Impact** | Misleading list display if used for amount column without separate balance field. |
| **Solution** | Document semantics or add `displayBalance` / align with server `balance` field for display. |

---

### M-14 — `findForVisit` uses list RPC with client-side filter

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **Files** | `data/invoice_repository.dart` |
| **Evidence** | `findForVisit` calls `listInvoices` with `visit_id` filter and `limit: 1` instead of a dedicated RPC. |
| **Why** | Depends on `visit_id` filter support in `list_invoices`; returns first match only. |
| **Solution** | Confirm backend filter contract; consider dedicated `find_invoice_for_visit` RPC. |

---

## 4. Low Priority Issues

### L-01 — `PaymentNotifier` adds no value (pass-through)

| Field | Detail |
|-------|--------|
| **Severity** | Low |
| **Files** | `presentation/providers/payment_notifier.dart` |
| **Evidence** | 32-line class forwards to `PaymentRepository`; no state, stale handling, or `allowPartialPayments` integration. |
| **Solution** | Merge into invoice detail orchestrator or proper `AsyncNotifier` with balance/settings awareness. |

---

### L-02 — Presentation strings on domain enums

| Field | Detail |
|-------|--------|
| **Severity** | Low |
| **Files** | `domain/invoice_status.dart`, `payment_method.dart`, `discount_kind.dart`, `discount_scope.dart` |
| **Evidence** | `.label` getters return English UI copy. |
| **Solution** | Move labels to `billing_formatting.dart` or l10n ARB keys. |

---

### L-03 — Auth-gating boilerplate repeated in every notifier

| Field | Detail |
|-------|--------|
| **Severity** | Low |
| **Files** | `invoice_list_notifier.dart`, `billing_settings_notifier.dart`, `insurance_providers_notifier.dart` |
| **Evidence** | Same `AuthRouteGuard.canAccess*` → empty/default early return pattern. |
| **Solution** | Optional mixin `requiresBillingAccess(ref, loader)` — low priority. |

---

### L-04 — Legacy free-text item APIs coexist with catalog path

| Field | Detail |
|-------|--------|
| **Severity** | Low |
| **Files** | `invoice_editor_notifier.dart` (`addItem`, `updateItem`), `invoice_repository.dart` (`addItem`) |
| **Evidence** | Spec 015 retires free-text authoring; `addItemFromService` is intended path. |
| **Solution** | Deprecate free-text methods from editor when UI ships. |

---

### L-05 — `estimatedTotal` is heuristic, not server total

| Field | Detail |
|-------|--------|
| **Severity** | Low |
| **Files** | `presentation/providers/invoice_list_notifier.dart` |
| **Evidence** | `estimatedTotal = offset + items.length + (hasMore ? 1 : 0)`. |
| **Solution** | Add `total_count` to RPC contract or rename to `loadedCountHint`. |

---

### L-06 — Hard-coded `USD` fallback in domain

| Field | Detail |
|-------|--------|
| **Severity** | Low |
| **Files** | `domain/invoice_detail.dart` line 126 |
| **Evidence** | `currency: invoice['currency']?.toString() ?? 'USD'`. |
| **Impact** | Aligns with backend hard-coded USD noted in backend review; multi-currency future needs coordinated change. |

---

### L-07 — `invoiceDisplayNumber` truncates UUID without validation

| Field | Detail |
|-------|--------|
| **Severity** | Low |
| **Files** | `presentation/utils/billing_formatting.dart` |
| **Evidence** | `'Draft · ${invoiceId.substring(0, 8)}'` — throws if `invoiceId.length < 8`. |
| **Solution** | Use safe prefix: `invoiceId.length >= 8 ? invoiceId.substring(0, 8) : invoiceId`. |

---

## 5. Clean Architecture Violations

| ID | Violation | Severity | Files |
|----|-----------|----------|-------|
| CA-01 | Presentation → Data direct imports (no interfaces/use cases) | High | All `presentation/providers/*.dart` |
| CA-02 | Wire parsing (`fromRow`/`fromRpcData`) in domain | Medium | All domain entities with parsers |
| CA-03 | Data type (`InvoiceListPageResult`) in presentation contract | Medium | `invoice_detail_provider.dart` |
| CA-04 | Cross-feature presentation→data (`invoice_editor` → `service_catalog`) | High | `invoice_editor_notifier.dart` |
| CA-05 | Cross-feature inverted dep (catalog → billing presentation) | High | `service_price_preview.dart` |
| CA-06 | Application layer unused (`billingMessageForRpc`) | High | `billing_rpc_messages.dart` |
| CA-07 | Domain depends on Flutter (`foundation.dart`) | Medium | `money.dart`, entity files |
| CA-08 | `InvoiceListFilters` in presentation but maps to RPC wire | Low | `invoice_list_filters.dart` — acceptable as presentation DTO if domain filter model added later |

**Dependency direction today:**

```
presentation → data → (Supabase)
presentation → service_catalog/data  [violation]
service_catalog/presentation → billing/presentation  [violation]
service_catalog/domain → billing/domain  [acceptable if Money is shared kernel]
```

---

## 6. SOLID Violations

| ID | Principle | Violation | Severity |
|----|-----------|-----------|----------|
| SOLID-01 | SRP | `InvoiceRepository` handles CRUD, discounts, insurance, void, list, detail | Medium |
| SOLID-02 | SRP | `PaymentNotifier` pass-through with no behavior | Low |
| SOLID-03 | OCP | No repository interface — cannot swap implementations without changing consumers | Medium |
| SOLID-04 | DIP | Notifiers depend on concrete `InvoiceRepository`, not abstraction | High |
| SOLID-05 | ISP | `InvoiceRepository` forces consumers to depend on full surface | Medium |
| SOLID-06 | SRP | `BillingFormatting` mixes money format, dates, status badges | Low |

---

## 7. Code Duplication & Redundancy

| ID | Duplication | Location | Recommendation |
|----|-------------|----------|----------------|
| DUP-01 | `_assertNonEmpty`, `_assertPositiveDecimal`, `_assertNonNegativeDecimal` | `invoice_repository.dart`, `payment_repository.dart`, `insurance_provider_repository.dart` | Extract to `core/rpc/input_assertions.dart` |
| DUP-02 | `double.tryParse` vs `Money.parse` validation | Repos vs domain | Consolidate on `Money` |
| DUP-03 | Auth-gating early-return pattern | All notifiers | Optional shared mixin |
| DUP-04 | Editor `_mutate` + reload pattern | `invoice_editor_notifier.dart`, `service_editor_notifier.dart` | Shared optimistic-concurrency mixin |
| DUP-05 | Two insurance provider providers | `insurance_providers_notifier.dart` | Single provider with filter param |
| DUP-06 | Free-text + catalog item add paths | `invoice_editor_notifier.dart` | Remove free-text when UI ships |

---

## 8. Performance Issues

| ID | Issue | Severity | Files |
|----|-------|----------|-------|
| PERF-01 | Double RPC per editor mutation (mutate + getDetail) | Medium | `invoice_editor_notifier.dart` |
| PERF-02 | No filter debounce on invoice list | Medium | `invoice_list_notifier.dart` |
| PERF-03 | Redundant insurance provider RPC (two providers) | Low | `insurance_providers_notifier.dart` |
| PERF-04 | `invoiceListProvider` rebuilds on any `activeBranchId` change via `ref.watch` | Low | `invoice_list_notifier.dart` — may over-fetch; consider debounce or explicit reload |

---

## 9. Test Coverage Gaps

| Component | Test file | Status |
|-----------|-----------|--------|
| `Money` | `money_test.dart` | Good |
| Enums, `Payment.fromRow` | `billing_domain_test.dart` | Partial |
| `billingMessageForRpc` | `billing_rpc_messages_test.dart` | Good |
| `InvoiceRepository` | `invoice_repository_test.dart` | Minimal (4 tests) |
| `BillingSettingsRepository` | `billing_settings_repository_test.dart` | 1 test |
| `InsuranceProviderRepository` | `insurance_provider_repository_test.dart` | 1 test |
| **`PaymentRepository`** | — | **None** |
| **`InvoiceDetail.fromRpcData`** | — | **None** |
| **`InvoiceListItem.fromRow`** | — | **None** |
| **`InvoiceItem.fromRow`** | — | **None** |
| **`InvoiceListFilters.toRpcFilters`** | — | **None** |
| **`BillingFormatting`** | — | **None** |
| **All notifiers/providers** | — | **None** |
| **`InvoiceEditorState.activeDiscountScope`** | — | **None** |
| **`InvoiceStaleException` handling** | — | **None** |
| Auth route guard billing | `auth_route_guard_billing_test.dart` | Good |
| Widget / integration tests | — | **None** |
| `BillingRpcTestClient` simulations | support file | **Underutilized** |

**Priority tests to add:**
1. `InvoiceEditorNotifier` — `STALE_INVOICE` → `InvoiceStaleException`, `activeDiscountScope`, concurrent `_mutate`
2. `invoiceDetailViewProvider` — auth gate behavior
3. `payment_repository_test.dart` — overpayment, partial payments disabled
4. `billing_domain_parsing_test.dart` — malformed child rows fail loudly

---

## 10. Recommended Refactoring

### Tier 1 — Before billing UI lands

| # | Refactor | Rationale |
|---|----------|-----------|
| R1 | Remove `result.data?.toString()` ID fallbacks; standardize `RpcFailure(UNEXPECTED_RESPONSE)` | Prevents garbage IDs; enables error mapping |
| R2 | Fix `Money.tryParse` empty-string semantics; reject quantity `'0'` | Closes domain coercion bugs |
| R3 | Auth: gate detail fetch, edit route (`invoices.create`), settings mutations, `reload()` paths | Close permission gaps |
| R4 | Serialize `InvoiceEditorNotifier` mutations | Prevent concurrent `_mutate` races |
| R5 | Wire `billingMessageForRpc` into notifiers; preserve admin detail for `RPC_NOT_APPLIED` | Application layer earns its place |
| R6 | Fix `migrationHint` on payment/settings/insurance repos | Correct incident diagnostics |
| R7 | Expand tests: `payment_repository_test.dart`, notifier tests, domain parsing tests | Close highest-risk gaps |
| R8 | Extract shared kernel: `core/money/` + `core/formatting/` | Breaks billing↔catalog presentation cycle |
| R9 | Add repository interfaces + `AddServiceToInvoice` use case | Restores convention; removes cross-feature data import |

### Tier 2 — During UI implementation

| # | Refactor | Rationale |
|---|----------|-----------|
| R8 | Invoice detail orchestrator (detail + payments + void + settings) | Replace `PaymentNotifier` pass-through |
| R9 | Visit→invoice flow (`createFromVisit` + `findForVisit`) in visits feature | Complete P1 billing journey |
| R10 | Move wire parsers to data mappers | Clean domain layer |
| R11 | List filter debounce (300ms) | Match NFR |
| R12 | Billing screens/widgets under `presentation/` | Currently 0 of 24 files are UI |

### Tier 3 — Hardening

| # | Refactor | Rationale |
|---|----------|-----------|
| R13 | Shared `RpcInputAssertions` or `Money`-based validation | Remove triple duplication |
| R14 | Split `InvoiceRepository` or introduce use cases per user story | SRP |
| R15 | Fail-loud parsing for invoice envelope children | Prevent silent financial data loss |
| R16 | Optimistic concurrency mixin shared with service_catalog | Consistent stale UX |

---

## Convention Comparison

| Aspect | Patients | Service Catalog | Billing |
|--------|----------|-----------------|---------|
| Repository interface | Yes | No | No |
| Use cases | Yes | No | No |
| Application validation | Partial | Yes | No (only RPC messages) |
| Presentation→Data import | No | Yes | Yes |
| Notifier tests | Yes | Yes | **No** |
| UI screens | Yes | Partial/placeholder | **Placeholder only** |
| Cross-feature deps | Minimal | Billing `Money` + formatting | Service catalog data |

**Conclusion:** Billing matches service_catalog's pragmatic style but **lags on tests**, has **worse cross-feature coupling**, and has **permission gaps** on detail fetch. Patients remains the gold standard for layering in this codebase.

---

## File Reference

| Path | Role |
|------|------|
| `frontend/lib/features/billing/` | Feature root (24 files) |
| `frontend/test/unit/billing/` | Unit tests (6 files) |
| `frontend/test/unit/core/auth_route_guard_billing_test.dart` | Route guard tests |
| `frontend/test/support/billing_rpc_test_client.dart` | RPC test fake |
| `frontend/lib/app/router.dart` | Billing routes (placeholders) |
| `frontend/lib/core/auth/auth_route_guard.dart` | Billing permission guards |

---

## Review Sources

Parallel layer reviews merged into this document:

| Review | Focus |
|--------|-------|
| [Architecture & tests](6e140519-9900-4d1a-b1dd-22d636780fd1) | Cross-cutting boundaries, test gaps, convention comparison |
| [Domain layer](5afcb7d5-9997-4517-bbca-3627e5001b41) | `Money`, `fromRow` parsers, business invariants |
| [Data layer](8d866d32-7b9d-4056-b47a-841bfa515586) | RPC wrappers, ID parsing, migration hints, validation |
| [Presentation layer](3a03caeb-ec66-4c26-abfb-2788b9260a15) | Notifiers, auth gaps, concurrency, missing orchestration |

**Severity rollup (deduplicated):** 4 Critical · ~20 High · ~22 Medium · ~14 Low

---

# Second Cycle Review — 2026-07-05

**Reviewers:** Five parallel layer reviews ([domain pass 1](44248b30-0ceb-4108-a89e-88b7a52db5a8), [domain pass 2](12b26f6c-6553-485d-8c6f-38c66531b8ad), [data](8a5b6df0-4832-4ab5-b9dd-e02495cc6e19), [presentation](6a06c594-f3e0-4e24-8470-b64823591f58), [integration](07299824-ddc9-4e0a-bdc0-22fbb720fe73), [integration pass 2](94d90c50-35dc-4f12-8c87-3a7f32ea5e01))  
**Outcome:** **No first-cycle critical or high issue has been fixed.** Cycle 2 confirms all four criticals remain open and surfaces **7 new high** and **17 new medium** findings across auth gaps, parse coercion, data-loss paths, and integration wiring.

---

## Second Cycle Executive Summary

The billing feature is unchanged since cycle 1. All 24 logic-layer files were re-reviewed with cross-file validation. The implementation remains structurally sound for a pre-UI vertical slice, but **is not production-ready for screen wiring**.

### Verdict by layer

| Layer | Cycle-1 status | Cycle-2 outcome |
|-------|----------------|-----------------|
| **Domain** | Coercion bugs, silent child-row drop | **Still open** — `C-02`, `H-12`, `H-13` unfixed; `Money.fromWire` adds silent-zero path |
| **Data** | ID fallbacks, error-type drift, wrong hints | **Still open** — all 9 cycle-1 data findings confirmed; **3 new high** (silent empty lists, row drop, partial envelope) |
| **Presentation** | Auth gaps, concurrent mutations | **Still open** — `C-01`, `C-03`, `C-04` unfixed; **3 new high** (`PaymentNotifier` auth, per-mutation guards, insurance writes) |
| **Integration** | Cross-feature coupling, test gaps | **Still open** — patient/visit/settings nav unwired; auth test encodes edit-route bug as passing behavior |

### Phase 1 blockers (before UI)

1. **C-01** — Gate `invoiceDetailViewProvider` before fetch
2. **C-03** — Serialize `InvoiceEditorNotifier._mutate`
3. **C-04** — Add `canAccessInvoiceEdit` (`invoices.create`) for edit route + editor
4. **NC-H-01 / INT-H03** — Auth-gate `PaymentNotifier`
5. **H-14 / INT-H06** — Gate `updateAllowPartialPayments` with `canManageBillingSettings`
6. **H-15 / INT-H07** — Guard all `reload()` paths
7. **C-02 / H-D4** — Fail-loud parsing for invoice envelope children
8. **H-09** — Remove `result.data?.toString()` ID fallbacks

---

## Second Cycle — Consolidated Findings

### Critical (4 confirmed, 0 fixed)

| ID | Status | Summary |
|----|--------|---------|
| **C-01** | Still open | `invoiceDetailViewProvider` fetches before auth check |
| **C-02** | Still open | `_parseItems` / `_parsePayments` silently drop malformed child rows |
| **C-03** | Still open | Concurrent `_mutate` restores stale snapshot; no serialization |
| **C-04** | Still open | Edit route uses `canViewInvoices()` only; editor ungated |

### High — confirmed open + new (cycle 2)

| ID | Status | Summary |
|----|--------|---------|
| **H-01** | Still open | Presentation imports data layer directly |
| **H-02** | Still open | No repository interfaces |
| **H-03 / INT-H01** | Still open | Editor → `service_catalog` data; billing RPC in wrong feature |
| **H-04 / INT-H02** | Still open | Catalog → billing presentation utils |
| **H-05 / INT-M08** | Still open | `billingMessageForRpc` unused in `lib/` |
| **H-06** | Still open | `PaymentRepository` untested; rich fake unused |
| **H-07 / INT-H09** | Still open | Zero notifier tests |
| **H-08 / INT-H05** | Still open | `activeInsuranceProvidersProvider` ungated |
| **H-09** | Still open | `result.data?.toString()` garbage ID fallbacks (7 sites) |
| **H-10** | Still open | `StateError` vs `RpcFailure` inconsistency |
| **H-11** | Still open | Wrong `migrationHint` on 3 repos |
| **H-12** | Still open | `Money.tryParse('')` → zero; tests encode bug |
| **H-13** | Still open | `InvoiceItem` quantity defaults to `'0'` |
| **C2-H-01** | **New** | Empty payment amount wire → phantom `$0.00` payment (H-12 cascade) |
| **N-H-01** | **New** | `InvoiceItem.quantity` accepts non-numeric/negative strings (extends H-13) |
| **D2-H-01** | **New** | Negative money accepted on invoice aggregates (no `>= 0` invariant checks) |
| **H-14 / INT-H06** | Still open | Settings mutations lack `canManageBillingSettings` |
| **H-15 / INT-H07** | Still open | `reload()` bypasses auth (settings, insurance, editor) |
| **H-16** | Still open | `RPC_NOT_APPLIED` admin detail discarded |
| **H-D2** | **New** | Malformed list RPC → silent `[]` |
| **H-D3** | **New** | List/provider `.whereType` drops invalid rows |
| **H-D4** | **New** | `getDetail` succeeds with partial child parse |
| **NC-H-01 / INT-H03** | **New** | `PaymentNotifier` has zero auth gating |
| **NC-H-02** | **New** | Editor mutations lack per-action permission checks |
| **NC-H-03 / INT-H04** | **New** | Insurance `upsert`/`deactivate` skip auth |
| **N-H-02** | **New** | `add_invoice_item_from_service` RPC owned by `ServiceCatalogRepository`, not billing |

### Medium — notable new (cycle 2)

| ID | Summary |
|----|---------|
| **NC-M-01** | Editor loads non-draft invoices without status guard |
| **NC-M-02** | `InvoiceListNotifier` stale cache on permission revocation |
| **NC-M-03** | `updateItemQuantity` throws unhandled `StateError` on missing item |
| **NC-M-04** | `billing_settings` concurrent update race |
| **NC-M-05** | `InvoiceEditorNotifier` doesn't watch auth session |
| **INT-M01** | Invoice list ignores `activeBranchId` (sends all `branchIds`) |
| **INT-M02** | `patientInvoicesProvider` defined but unwired to patients |
| **INT-M03** | Visit→invoice flow (`createFromVisit`) has no callers |
| **INT-M04** | Settings billing route exists but no settings tab |
| **INT-M05** | Sidebar shows billing nav without permission filter |
| **M-D1** | Quantity/unitPrice not trimmed before RPC |
| **M-D2** | Repo write validation vs domain read quantity mismatch |
| **M-12** | Domain RPC parsing largely untested (`InvoiceDetail`, list/item `fromRow`) |
| **M-13** | `InvoiceListItem.displayTotal` ignores `insuranceCoveredAmount` |
| **C2-M-02** | FR-010 discount-scope rules not in domain (`DiscountScope` label-only) |
| **C2-M-03** | Discount kind/value pairing not validated in domain parsers |
| **C2-M-04** | `Money.fromWire` unused coercion footgun |
| **NC-M-06** | `invoiceDisplayNumber` throws on IDs shorter than 8 chars |
| **NC-M-07** | Discount scope conflict not guarded before editor mutations |
| **N-M-02** | No `invalidateBillingSurfaceProviders` on sign-out / auth lifecycle |
| **N-M-01** | `Money.parse` accepts excess precision despite scale-≤2 contract |
| **N-M-03** | Boolean fields reject integer `1` (`allowPartialPayments`, `isActive`) |
| **N-M-04** | `InvoiceDetail` does not validate voided status vs `voidedAt`/`voidReason` |

---

## Second Cycle — Domain & Application

#### Status of First-Cycle Domain Findings

| ID | Status | Notes |
|----|--------|-------|
| **C-02** | **Still open** | `_parseItems` / `_parsePayments` use `.whereType` after `fromRow` returns null — bad rows silently omitted |
| **H-12** | **Still open** | `Money.parse('')` returns `zero`; `tryParse('')` follows same path. Test at `money_test.dart` L21 encodes this |
| **H-13** | **Still open** | `invoice_item.dart` L48: `quantity: row['quantity']?.toString() ?? '0'` |
| **H-16** | **Still open** | `billing_rpc_messages.dart` L24–25: `RPC_NOT_APPLIED` → generic copy, discards `failure.message` migration hint |
| **M-01** | **Still open** | All entities retain `fromRow` / `fromRpcData` with RPC field names |
| **M-03** | **Still open** | Domain imports `package:flutter/foundation.dart` for `@immutable` |
| **M-04** | **Still open** | Same root cause as H-12 |
| **M-07 / C2-M-02** | **Still open** | `DiscountScope` mutual-exclusion logic lives in `invoice_editor_notifier.dart`, not domain |
| **M-12** | **Still open** | No tests for `InvoiceDetail.fromRpcData`, `InvoiceListItem.fromRow`, `InvoiceItem.fromRow` |
| **M-13** | **Still open** | `displayTotal` = subtotal − discount only; ignores insurance coverage |

#### New or Confirmed Critical Issues

**DOM-C01 (confirmed — C-02)** — Silent child-row dropping in invoice envelope

| Field | Detail |
|-------|--------|
| **Severity** | Critical |
| **Files** | `domain/invoice_detail.dart` (L148–169), `domain/invoice_item.dart`, `domain/payment.dart` |
| **Evidence** | `_parseItems`: `.whereType<InvoiceItem>()` after `fromRow` null. `_parsePayments`: same pattern. Envelope monetary fields validated; children are not count-checked. |
| **Impact** | Invoice appears valid with wrong balance when payments/items omitted. Confirmed at data boundary (H-D4). |
| **Solution** | Fail envelope when `raw.length != parsed.length`; add tests with intentionally bad child rows. |

#### New or Confirmed High Priority Issues

**DOM-H01 (confirmed — H-12)** — `Money.tryParse('')` returns zero

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **Files** | `domain/money.dart` (L14–18, L29–37), `money_test.dart` (L21) |
| **Evidence** | `parse('')` returns `zero` before `tryParse` null-check path. Empty wire `"balance": ""` passes `fromRpcData` null guards as `$0.00`. |
| **Solution** | `tryParse` → `null` for null/empty; restrict `parseOrZero` / `fromWire` to explicit call sites. |

**DOM-H02 (confirmed — H-13)** — Missing quantity defaults to `'0'`

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **Files** | `domain/invoice_item.dart` (L48) |
| **Evidence** | `quantity: row['quantity']?.toString() ?? '0'` — DB constraint is `quantity > 0`; repo write rejects `<= 0`. |
| **Solution** | Reject null, empty, or non-positive quantity in `fromRow`. |

**C2-H-01 (new)** — Zero-amount payments accepted via empty wire string

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **Files** | `domain/payment.dart`, `domain/money.dart` |
| **Evidence** | `Payment.fromRow` requires `amount != null` from `Money.tryParse`, but `""` yields `Money.zero`. Backend: `payments_amount_non_zero CHECK (amount <> 0)`. |
| **Impact** | Phantom `$0.00` payments in history; balance reconciliation unreliable. |
| **Solution** | Fix H-12; reject `amount.isZero` in `Payment.fromRow`. |

**DOM-H04 (confirmed — H-16)** — `billingMessageForRpc` discards admin diagnostics

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **Files** | `application/billing_rpc_messages.dart` (L24–25) |
| **Evidence** | `RPC_NOT_APPLIED` mapped to generic string; `INVALID_INPUT` correctly passes `failure.message`. |
| **Solution** | Pass through `failure.message` for `RPC_NOT_APPLIED` / `RPC_NOT_CONFIGURED` when non-empty. |

#### New or Confirmed Medium Priority Issues

**DOM-M01 (new)** — Non-list `items`/`payments` coerced to empty arrays

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **Files** | `domain/invoice_detail.dart` (L149–151, L161–163) |
| **Evidence** | `if (raw is! List) { return const []; }` — wrong-type payload yields zero children, not parse failure. |
| **Solution** | Return null from `fromRpcData` when `items`/`payments` key present but wrong type. |

**M-12 (confirmed)** — Domain RPC parsing largely untested

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **Files** | `billing_domain_test.dart` — enums + 2 `Payment.fromRow` cases only |
| **Evidence** | No tests for `InvoiceDetail.fromRpcData`, `InvoiceListItem.fromRow`, `InvoiceItem.fromRow`, or malformed-child behavior. |
| **Solution** | Add `billing_domain_parsing_test.dart` with golden JSON fixtures. |

**M-13 (confirmed)** — `displayTotal` ignores insurance coverage

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **Files** | `domain/invoice_list_item.dart` (L36–37) |
| **Evidence** | `displayTotal => (subtotal - discountAmount).wireValue` — entity also carries `insuranceCoveredAmount` and `balance`. |
| **Solution** | Document semantics or add `displayBalance` aligned with server `balance`. |

**C2-M-03 (new)** — Discount kind/value pairing not validated

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **Files** | `domain/invoice_detail.dart`, `domain/invoice_item.dart` |
| **Evidence** | Parsers accept independent `discountKind` / `discountValue` fields. Backend: `(discount_kind IS NULL) = (discount_value IS NULL)`. |
| **Solution** | Reject rows where `(kind == null) != (value == null)`. |

**C2-M-04 (new)** — `Money.fromWire` unused coercion footgun

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **Files** | `domain/money.dart` (L40) |
| **Evidence** | `fromWire` → `tryParse(raw) ?? zero`; zero usages in `frontend/lib/`. |
| **Solution** | Remove or restrict; do not adopt for required monetary fields during UI work. |

**N-M-01 (new, domain pass 2)** — Scale ≤ 2 not enforced on inbound parse

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **Files** | `domain/money.dart` |
| **Evidence** | Doc claims scale ≤ 2; `Decimal.tryParse` accepts `"10.123"`. `wireValue` rounds on output only. |
| **Solution** | Reject or normalize excess precision at parse time; align with NFR-007 and repo validators. |

**N-M-03 (new, domain pass 2)** — Boolean wire coercion rejects numeric truthy values

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **Files** | `domain/billing_settings.dart`, `domain/insurance_provider.dart` |
| **Evidence** | `allowPartial == true \|\| allowPartial.toString() == 'true'` — integer `1` evaluates false. |
| **Solution** | Normalize Postgres boolean wire shapes (`true`/`false`/`1`/`0`). |

**N-M-04 (new, domain pass 2)** — Void status invariants not cross-validated

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **Files** | `domain/invoice_detail.dart` |
| **Evidence** | `status`, `voidedAt`, `voidReason` parsed independently; `voided` with null `voided_at` succeeds. |
| **Solution** | Enforce DB pairing rules in `fromRpcData`. |

---

## Second Cycle — Data Layer

*(Full detail from [data layer review](8a5b6df0-4832-4ab5-b9dd-e02495cc6e19))*

All 9 first-cycle data findings **still open**. Key new findings:

- **H-D2** — `_parseListRows` / `listProviders` return `[]` when array key missing or wrong type
- **H-D3** — `.whereType` drops invalid list rows without error
- **H-D4** — `getDetail` returns partially parsed `InvoiceDetail`
- **M-D1** — `quantity`/`unitPrice` validated with trim but sent untrimmed to RPC
- **M-D3** — `getDetail`, `issue`, `createFromVisit`, `voidInvoice` lack repo tests despite fake support

---

## Second Cycle — Presentation Layer

*(Full detail from [presentation review](6a06c594-f3e0-4e24-8470-b64823591f58))*

All 3 presentation criticals **still open**. Key new findings:

- **NC-H-01** — `PaymentNotifier` forwards `recordPayment`/`recordRefund` with no auth
- **NC-H-02** — Editor mutation methods lack per-action permission checks
- **NC-H-03** — Insurance `upsert`/`deactivate` skip auth re-check
- **NC-M-01** — Editor loads non-draft invoices (doc says draft-only)
- **NC-M-02** — List notifier doesn't watch permissions; stale cache on revocation
- **NC-M-03** — `firstWhere` on missing itemId throws `StateError`
- **NC-M-04** — Settings toggle concurrent update race
- **NC-M-05** — Editor doesn't watch `authSessionProvider`

---

## Second Cycle — Integration & Cross-Cutting

*(Detail from [integration review (pass 1)](07299824-ddc9-4e0a-bdc0-22fbb720fe73) and [integration review (pass 2)](94d90c50-35dc-4f12-8c87-3a7f32ea5e01))*

All 13 first-cycle integration findings **still open**. Routing/guard wiring verified OK (5 routes, redirect chain, static-path tests). Key gaps:

- **INT-M01** — Invoice list passes all `branchIds`, not `activeBranchId` (patients scopes correctly)
- **INT-M02** — `patientInvoicesProvider` has zero consumers; patient history has no billing section
- **INT-M03** — `createFromVisit` / `findForVisit` orphaned; visits feature has no billing imports
- **INT-M04 / N-M-04** — `/settings/billing` route registered but absent from `SettingsTabs`; view vs manage permission conflated
- **INT-M05 / N-M-03** — Sidebar renders billing/invoices without permission filtering; duplicate nav items
- **N-H-02** — `add_invoice_item_from_service` lives in `ServiceCatalogRepository`, splitting invoice mutation ownership
- **N-M-01 / NC-M-02** — Global non-`autoDispose` providers retain stale data after permission refresh
- **N-M-02** — No billing surface invalidation on sign-out (appointments has `invalidateAppointmentSurfaceProviders`; billing has no equivalent)

#### Test coverage gaps (cycle 2)

| ID | Severity | Gap |
|----|----------|-----|
| **TC-C01** | Critical | No test that detail provider denies before fetch |
| **TC-C02** | Critical | `auth_route_guard_billing_test.dart` allows view-only to edit URL (bug as passing test) |
| **TC-H01** | High | Zero notifier tests |
| **TC-H02** | High | No `payment_repository_test.dart` |
| **TC-H03** | High | No payment/insurance mutation auth tests |
| **TC-M01** | Medium | No branch-scoping test for invoice list |
| **TC-M02** | Medium | No billing router integration tests |

---

## Second Cycle — Recommended Priority

### Must fix before any billing UI ships

| Priority | Items |
|----------|-------|
| **P0 Security** | C-01, C-04, NC-H-01, H-14, H-08, NC-H-03 |
| **P0 Correctness** | C-02, C-03, H-09, H-12, H-D2, H-D3, H-D4 |
| **P0 Tests** | TC-C01, TC-C02, editor/list notifier tests |

### Fix during UI implementation

| Priority | Items |
|----------|-------|
| **P1 UX** | H-05, H-16, NC-M-01, INT-M04, INT-M05 |
| **P1 Integration** | INT-M02, INT-M03, N-H-02, H-03 |
| **P2 Hardening** | H-10, H-11, M-06, INT-M01, N-M-02 |

---

## Second Cycle Review Sources

| Review | Agent | Focus |
|--------|-------|-------|
| Domain & application | [44248b30-0ceb-4108-a89e-88b7a52db5a8](44248b30-0ceb-4108-a89e-88b7a52db5a8), [12b26f6c-6553-485d-8c6f-38c66531b8ad](12b26f6c-6553-485d-8c6f-38c66531b8ad) | `Money`, parsers, `billing_rpc_messages`, invariants |
| Data layer | [8a5b6df0-4832-4ab5-b9dd-e02495cc6e19](8a5b6df0-4832-4ab5-b9dd-e02495cc6e19) | RPC repos, ID parsing, silent data loss |
| Presentation | [6a06c594-f3e0-4e24-8470-b64823591f58](6a06c594-f3e0-4e24-8470-b64823591f58) | Notifiers, auth, concurrency |
| Integration | [07299824-ddc9-4e0a-bdc0-22fbb720fe73](07299824-ddc9-4e0a-bdc0-22fbb720fe73), [94d90c50-35dc-4f12-8c87-3a7f32ea5e01](94d90c50-35dc-4f12-8c87-3a7f32ea5e01) | Routing, cross-feature, tests, auth lifecycle |

**Second-cycle severity rollup (deduplicated):** 4 Critical (0 fixed) · ~26 High (+6 new) · ~35 Medium (+13 new)
