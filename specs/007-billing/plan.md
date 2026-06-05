# Implementation Plan: Billing (V1-6)

**Branch**: `specs/007-billing` | **Date**: 2026-06-05 | **Spec**: `specs/007-billing/spec.md`

**Input**: Feature specification from `/specs/007-billing/spec.md`

## Summary

Deliver V1-6 billing: invoice issuance from `completed` visits with line items, mutually-exclusive line-level or invoice-level discounts (permission-gated), informational insurance coverage split, branch-scoped invoice numbering using existing `branches.code`, append-only payments (cash/card/bank_transfer/insurance_settlement), refund support, void workflow, soft-deletable drafts, and a printable receipt view. Adds an organization-level **billing settings** record with `allow_partial_payments` (default `false`) — mutable only by `owner`/`administrator` via a new `settings.billing.manage` permission key — that the payment RPC consults to reject partial patient-tender payments (insurance settlements and refunds exempt). All mutations route through `auth_internal` PL/pgSQL RPCs with branch RLS, defense-in-depth permission gating, and audit log entries. Builds on V1-1 auth, V1-2 org/branch/settings, V1-3 patients, V1-4 appointments, V1-5 visits. No AI. No claim lifecycle, dunning, analytics, or multi-currency (deferred to V3-1/V3-2).

## Technical Context

**Language/Version**: Dart/Flutter stable (Windows desktop); PostgreSQL 15+ via Supabase local stack; PL/pgSQL in `auth_internal` + public RPC wrappers

**Primary Dependencies**: Supabase Flutter SDK (RPC), Riverpod, GoRouter, `printing`/`pdf` (or platform `Printing.layoutPdf`) for OS-native receipt printing; V1-2 `AuthSessionNotifier`, `PermissionRepository`, organization settings page; V1-3 patient profile (new billing tab); V1-5 visit detail (create-invoice action)

**Storage**: New `public.invoices`, `invoice_items`, `payments`, `insurance_providers`, `organization_billing_settings`; enums `invoice_status`, `payment_method`, `discount_kind`; per-branch `invoice_number_sequences` table (or `bigserial` keyed sequence helper); new permission keys `invoices.view`, `invoices.create`, `invoices.apply_discount`, `invoices.void`, `payments.record`, `payments.refund`, `insurance.manage`, `settings.billing.manage`

**Testing**: `backend/tests/billing_crud.sql`, `billing_rls.sql`, `billing_concurrency.sql`, `run_billing_tests.sh`; Flutter unit/widget/integration under `frontend/test/**/billing/**`

**Target Platform**: Windows desktop on clinic LAN against local Supabase (V1-0 profile); OS native print pipeline for receipts

**Project Type**: Desktop client + Supabase PostgreSQL (migrations, RLS, RPC); no custom API server; no AI

**Performance Goals**: Create-invoice-from-visit to editor in 15s P95 (SC-001); payment recording feels instantaneous (NFR-002); invoice list pagination up to 5,000/branch (NFR-003); receipt print preview ≤ 2s for ≤100 line items (NFR-004)

**Constraints**: Branch-scoped RLS on `invoices`/`invoice_items`/`payments`; org-scoped RLS on `insurance_providers`/`organization_billing_settings`; mutations via RPC only; payments append-only (no UPDATE/DELETE grants); server-side transactional balance check prevents overpayment; optimistic concurrency on draft item edits via invoice `updated_at`; exact decimal scale 2 with banker's rounding for percentage discounts; invoice number sequence per branch with stable `INV-<branch_code>-` prefix; partial-payment policy enforced inside payment RPC for patient-tender methods only

**Scale/Scope**: 1 migration; ~15 RPCs (create/discard invoice, add/update/remove item, apply line discount, apply invoice discount, set insurance, issue, record payment, void, get invoice detail, list invoices, insurance provider CRUD, get/update billing settings); 1 storage-free domain (no attachments); ~10 Flutter pages/widgets across `features/billing` + extensions to patient profile, visit detail, and organization settings page; 2 contract docs

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

### Pre-Research Gate

- [x] Scope fits small-to-mid-size multi-branch outpatient clinics; explicitly excludes claim lifecycle, dunning, analytics dashboards, multi-currency, line-level taxes, prescription printing, shift management, and AI billing (FR-027)
- [x] No microservices, queues, Kubernetes, or custom primary backend service; same Flutter + Supabase + PostgreSQL stack as V1-0..V1-5
- [x] Flutter UI/orchestration; Supabase RPC; PostgreSQL owns mutations, validation, audit, RLS, balance computation, invoice number sequencing, and the partial-payments policy gate
- [x] Protected writes routed through `auth_internal` PL/pgSQL functions; payments append-only enforced by GRANTs and table policies; mutual exclusion of discount scopes enforced in RPC + CHECK constraints
- [x] Defense in depth: UI permission checks, RPC validation, RLS isolation, table-level grants
- [x] No AI dependency; billing flows are fully manual in V1; AI absence does not block any acceptance scenario (FR-029, AI Hooks)
- [x] Subscription state does not block invoice creation or payment recording (edge case enumerated; principle V preserved)

### Post-Design Re-Check

- [x] One-active-invoice-per-visit enforced by `UNIQUE (visit_id) WHERE status <> 'voided' AND is_deleted = false` partial index
- [x] Mutual exclusion of line vs invoice discount enforced by per-RPC pre-check **and** trigger that re-evaluates after writes to `invoice_items.line_discount_amount` and `invoices.discount_amount`
- [x] Branch isolation enforced via `branch_id` in JWT `branch_ids` per existing V1-2/V1-3/V1-4/V1-5 pattern; insurance providers and billing settings use org-scoped RLS
- [x] Overpayment prevented by transactional balance recompute inside `record_payment` RPC with `FOR UPDATE` on the invoice row
- [x] `allow_partial_payments=false` enforced server-side in `record_payment` for patient-tender methods (`cash`/`card`/`bank_transfer`); insurance settlements and refunds exempt
- [x] Invoice numbering monotonic per branch via per-branch sequence row in `invoice_number_sequences` updated under row lock during issue
- [x] All sensitive operations audited (`audit_log` writes with prior/new key values) and `settings.billing.manage` is non-delegable to non-admin roles in role-permission seed
- [x] Soft delete preserved on `invoices`/`invoice_items`; payments are append-only with no UPDATE/DELETE path (REVOKEd at GRANT level); no hard deletes anywhere

## Project Structure

### Documentation (this feature)

```text
specs/007-billing/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   ├── billing-mutations.md
│   └── billing-queries.md
└── tasks.md              # /speckit-tasks (not created by /speckit-plan)
```

### Source Code (repository root)

```text
backend/
├── supabase/migrations/
│   └── 20260605180000_billing.sql
└── tests/
    ├── billing_crud.sql
    ├── billing_rls.sql
    ├── billing_concurrency.sql
    └── run_billing_tests.sh

frontend/lib/
├── app/
│   ├── router.dart
│   └── app_routes.dart                              # + /billing/*, + /settings/billing
├── core/auth/
│   └── permission_service.dart                      # canViewInvoices, canCreateInvoices,
│                                                    # canApplyDiscount, canVoidInvoice,
│                                                    # canRecordPayment, canRefundPayment,
│                                                    # canManageInsurance, canManageBillingSettings
├── features/
│   ├── auth/domain/permission_keys.dart             # + invoicesView, invoicesCreate,
│   │                                                # invoicesApplyDiscount, invoicesVoid,
│   │                                                # paymentsRecord, paymentsRefund,
│   │                                                # insuranceManage, settingsBillingManage
│   ├── visits/presentation/widgets/
│   │   └── visit_detail_actions.dart                # + Create invoice / Open invoice
│   ├── patients/presentation/widgets/
│   │   └── patient_billing_section.dart             # new billing tab on patient profile
│   ├── organization_settings/presentation/widgets/
│   │   └── billing_settings_section.dart            # toggle Allow partial payments
│   └── billing/
│       ├── data/
│       │   ├── invoice_repository.dart
│       │   ├── payment_repository.dart
│       │   ├── insurance_provider_repository.dart
│       │   └── billing_settings_repository.dart
│       ├── domain/
│       │   ├── invoice_list_item.dart
│       │   ├── invoice_detail.dart
│       │   ├── invoice_item.dart
│       │   ├── invoice_status.dart
│       │   ├── payment.dart
│       │   ├── payment_method.dart
│       │   ├── discount_kind.dart
│       │   ├── discount_scope.dart                  # line | invoice
│       │   ├── insurance_provider.dart
│       │   └── billing_settings.dart
│       └── presentation/
│           ├── pages/
│           │   ├── invoice_list_page.dart
│           │   ├── invoice_editor_page.dart         # draft: items, discount, insurance, issue
│           │   ├── invoice_detail_page.dart         # issued/paid/voided + payment panel
│           │   └── insurance_providers_page.dart
│           ├── providers/
│           │   ├── invoice_editor_notifier.dart
│           │   ├── invoice_list_notifier.dart
│           │   ├── payment_notifier.dart
│           │   └── billing_settings_notifier.dart
│           └── widgets/
│               ├── invoice_items_editor.dart
│               ├── line_discount_field.dart
│               ├── invoice_discount_panel.dart
│               ├── discount_scope_guard.dart        # enforces mutual-exclusion UX
│               ├── insurance_panel.dart
│               ├── payment_form.dart                # method, amount, reference, note
│               ├── refund_form.dart
│               ├── void_invoice_dialog.dart
│               ├── invoice_status_badge.dart
│               └── receipt_print_preview.dart       # PDF/HTML render + OS print

frontend/test/
├── unit/billing/
├── widget/billing/
└── integration/billing/billing_acceptance_test.dart
```

**Structure Decision**: Billing domain lives under `frontend/lib/features/billing` with thin extension points in `features/visits` (Create/Open invoice action), `features/patients` (billing tab replacing placeholder if any), and `features/organization_settings` (Billing subsection with the partial-payments toggle). All authoritative logic remains in PostgreSQL RPCs and policies per Principle III.

## Implementation Phases (high level)

### Phase A — Backend: schema, sequences, RPCs

1. Migration: enums (`invoice_status`, `payment_method`, `discount_kind`), tables (`invoices`, `invoice_items`, `payments`, `insurance_providers`, `organization_billing_settings`, `invoice_number_sequences`), indexes, partial unique on `(visit_id) WHERE status<>'voided' AND is_deleted=false`, CHECK constraints (scale-2 decimals, percentage bounds, mutual-exclusion safeguards), branch/org RLS (SELECT only; deny direct INSERT/UPDATE/DELETE on `invoices`/`invoice_items`; REVOKE all UPDATE/DELETE on `payments`)
2. Auto-provision trigger: on `organizations` INSERT create `organization_billing_settings` with `allow_partial_payments=false`
3. Seed new permission keys; map to roles per FR-021 (owner/administrator: all eight; receptionist: view+create+record; doctor/lab_staff: none); flag `settings.billing.manage` as non-delegable in role-permission management
4. Helpers: `assert_invoice_branch_scope`, `assert_invoice_in_draft`, `assert_one_active_invoice_per_visit`, `assert_discount_scope_exclusive`, `compute_invoice_subtotal`, `compute_invoice_balance`, `assign_invoice_number(branch_id)` (row-locked sequence read)
5. RPCs per `data-model.md` and `contracts/billing-mutations.md`
6. Audit log entries per FR-023 (`audit_log` writes with prior/new key values)
7. GRANTs: `EXECUTE` on RPCs to `authenticated`; `SELECT` on tables via RLS; explicitly no UPDATE/DELETE on `payments`

### Phase B — Backend verification

1. `billing_crud.sql` — create from completed visit, item mutations in draft, line discount and invoice discount (with mutual exclusion), insurance set, issue (number assignment & monotonicity), record payment full/partial under both setting values, refund, void, discard draft
2. `billing_rls.sql` — cross-branch/org denial for invoices/items/payments/insurance/settings; receptionist cannot mutate settings; doctor/lab_staff cannot view/create invoices
3. `billing_concurrency.sql` — two-station concurrent payments racing toward zero balance (exactly one accepted, one rejected); concurrent draft item edits with stale `updated_at` rejected
4. `run_billing_tests.sh`

### Phase C — Flutter billing module

1. Extend `PermissionKeys` + `PermissionService` with the eight new keys
2. Repositories: `InvoiceRepository`, `PaymentRepository`, `InsuranceProviderRepository`, `BillingSettingsRepository` (backend-first reads per FR-030)
3. Routes/guards under `/billing` (`/billing/invoices`, `/billing/invoices/:id`, `/billing/insurance-providers`) and `/settings/billing`
4. Invoice editor page: items editor with optimistic-concurrency conflict UX, line-discount input per item, invoice-discount panel, insurance panel, issue button with branch-code-missing error surface; `DiscountScopeGuard` disables the inactive scope when the other is non-zero and offers a "clear other scope" affordance
5. Invoice detail page: status badge, payments list, payment form (method/amount/ref/note) with disabled "less than full balance" state when `allow_partial_payments=false` and method is patient-tender, refund form gated by permission, void dialog with reason
6. Receipt print preview using OS print pipeline; watermarks for `draft` and `voided`
7. Invoice list page with filters (status, branch, patient, date range, invoice number) and pagination

### Phase D — Integration into existing surfaces

1. `features/visits`: add **Create invoice** / **Open invoice** action on `completed` visit detail; deep-link to invoice editor or detail
2. `features/patients`: add billing tab to patient profile showing the patient's invoice history with status badges and balance
3. `features/organization_settings`: add **Billing** subsection hosting the `allow_partial_payments` toggle; visible to all roles with `invoices.view`, mutable only with `settings.billing.manage`; non-admin/non-owner roles see read-only state

### Phase E — Tests & docs

1. Unit/widget/integration coverage per Test Cases 1–22 plus 7a/7b (settings + partial-payment behavior)
2. `quickstart.md` operator verification walkthrough (issue → partial-disabled rejection → enable → partial accepted → full → paid → refund → void path)

## Complexity Tracking

No constitution violations requiring justification. All authoritative logic is in PostgreSQL; no new service tier introduced.

## Phase 0 & Phase 1 Artifacts

| Artifact                                          | Status               |
| ------------------------------------------------- | -------------------- |
| `research.md`                                     | Complete             |
| `data-model.md`                                   | Complete             |
| `contracts/billing-mutations.md`                  | Complete             |
| `contracts/billing-queries.md`                    | Complete             |
| `quickstart.md`                                   | Complete             |
| Agent context (`.cursor/rules/specify-rules.mdc`) | Updated to this plan |

**Next command**: `/speckit-tasks` to generate `tasks.md`.
