---

description: "Task list for Billing (V1-6) feature implementation"
---

# Tasks: Billing (V1-6)

**Input**: Design documents from `/specs/007-billing/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/billing-mutations.md, contracts/billing-queries.md, quickstart.md

**Tests**: INCLUDED. This feature is constitution-sensitive (Principle III backend authority, Principle IV defense-in-depth, audit, branch isolation) — backend SQL tests for RPC validation, RLS, and concurrency are mandatory; Flutter widget/integration tests cover acceptance scenarios.

**Organization**: Tasks are grouped by user story (US1..US8) per spec.md priorities.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: User story label (US1..US8)
- Exact file paths included

## Path Conventions

- Backend: `backend/supabase/migrations/`, `backend/tests/`
- Frontend: `frontend/lib/features/billing/`, `frontend/test/`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Scaffolding for the new billing feature module.

- [X] T001 Create directory skeleton `frontend/lib/features/billing/{data,domain,presentation/{pages,providers,widgets}}` and `frontend/test/{unit,widget,integration}/billing/`
- [X] T002 [P] Add billing-specific dependencies if not already present (verify `printing`/`pdf` Dart packages in `frontend/pubspec.yaml`); run `flutter pub get`
- [X] T003 [P] Create empty test harness file `backend/tests/run_billing_tests.sh` (executable; orchestrates the three SQL test suites)

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Schema, enums, base helpers, permission seed, RLS, and shared frontend wiring that EVERY user story depends on.

**⚠️ CRITICAL**: No user story work can begin until this phase is complete.

### Backend foundation

- [X] T004 Create migration `backend/supabase/migrations/20260605180000_billing.sql` with: enums (`invoice_status`, `payment_method`, `discount_kind`), tables (`invoices`, `invoice_items`, `payments`, `insurance_providers`, `organization_billing_settings`, `invoice_number_sequences`), all CHECK constraints, partial unique indexes, and standard audit columns per `specs/007-billing/data-model.md`
- [X] T005 In the same migration, add RLS policies: branch-scoped SELECT on `invoices`/`invoice_items`/`payments`; org-scoped SELECT on `insurance_providers`/`organization_billing_settings`; deny all direct INSERT/UPDATE/DELETE except via SECURITY DEFINER RPCs; explicit `REVOKE UPDATE, DELETE ON public.payments FROM PUBLIC, authenticated, anon`
- [X] T006 In the same migration, add trigger `AFTER INSERT ON organizations` to auto-provision an `organization_billing_settings` row with `allow_partial_payments=false`, plus a backfill statement for existing organizations
- [X] T007 [P] In the same migration, add PL/pgSQL helper functions in `auth_internal`: `assert_invoice_branch_scope`, `assert_invoice_in_draft`, `assert_one_active_invoice_per_visit`, `assert_discount_scope_exclusive`, `compute_invoice_subtotal`, `compute_invoice_balance`, `assign_invoice_number`
- [X] T008 [P] In the same migration, seed permission keys (`invoices.view`, `invoices.create`, `invoices.apply_discount`, `invoices.void`, `payments.record`, `payments.refund`, `insurance.manage`, `settings.billing.manage`) and role mappings per FR-021; mark `settings.billing.manage` as non-delegable in the role-permission management RPC (server-side reject if granted to receptionist/doctor/lab_staff)
- [X] T009 In the same migration, add trigger on `invoices` and `invoice_items` to enforce mutual exclusion of line vs invoice discount (`AFTER INSERT OR UPDATE`, raise if both scopes non-zero) per D3

### Frontend foundation

- [X] T010 [P] Extend `frontend/lib/features/auth/domain/permission_keys.dart` with the eight new billing permission keys
- [X] T011 [P] Extend `frontend/lib/core/auth/permission_service.dart` with `canViewInvoices`, `canCreateInvoices`, `canApplyDiscount`, `canVoidInvoice`, `canRecordPayment`, `canRefundPayment`, `canManageInsurance`, `canManageBillingSettings`
- [X] T012 [P] Add domain types under `frontend/lib/features/billing/domain/`: `invoice_status.dart`, `payment_method.dart`, `discount_kind.dart`, `discount_scope.dart`, `invoice_list_item.dart`, `invoice_detail.dart`, `invoice_item.dart`, `payment.dart`, `insurance_provider.dart`, `billing_settings.dart`
- [X] T013 [P] Add base repository skeletons under `frontend/lib/features/billing/data/`: `invoice_repository.dart`, `payment_repository.dart`, `insurance_provider_repository.dart`, `billing_settings_repository.dart` (RPC names and shapes per `contracts/billing-*.md`; backend-first reads per FR-030)
- [X] T014 Register routes in `frontend/lib/app/router.dart` and `frontend/lib/app/app_routes.dart`: `/billing/invoices`, `/billing/invoices/:id`, `/billing/insurance-providers`, `/settings/billing` (all permission-guarded; unauthorized → 403 view)

### Foundational backend tests

- [X] T015 [P] Create `backend/tests/billing_rls.sql` covering: cross-branch read denial on invoices/items/payments; cross-org read denial on insurance providers and billing settings; receptionist mutation denial on settings; doctor/lab_staff full denial on invoices

**Checkpoint**: Foundation ready - user story implementation can now begin in parallel.

---

## Phase 3: User Story 1 - Create an Invoice from a Completed Visit (Priority: P1) 🎯 MVP

**Goal**: A receptionist (or admin/owner) can turn a `completed` visit into a `draft` invoice, add items, and issue it, producing a branch-scoped invoice number.

**Independent Test**: Per spec Independent Test for US1 — complete a visit, create invoice, add items, issue, verify it appears in the list with status `issued` and correct linkage.

### Tests for User Story 1

- [X] T016 [P] [US1] In `backend/tests/billing_crud.sql`, add scenarios: create invoice from `completed` visit; rejection on `in_progress` visit; rejection on duplicate active invoice; rejection on missing `visit_id`; add/update/remove items in draft only; issue requires ≥1 item and `branches.code IS NOT NULL`; invoice number monotonicity per branch
- [X] T017 [P] [US1] In `frontend/test/integration/billing/`, add `create_and_issue_invoice_test.dart` covering acceptance scenarios 1, 2, 3, 4, 7, 8 of US1

### Implementation for User Story 1

- [X] T018 [P] [US1] Add RPCs in `backend/supabase/migrations/20260605180000_billing.sql` (or follow-up migration): `create_invoice_from_visit`, `discard_draft_invoice`, `add_invoice_item`, `update_invoice_item`, `remove_invoice_item`, `issue_invoice` (signatures and behavior per `contracts/billing-mutations.md`); each writes `audit_log` per FR-023
- [X] T019 [P] [US1] Add query RPCs `get_invoice_detail` and `list_invoices` per `contracts/billing-queries.md`
- [X] T020 [P] [US1] Implement `InvoiceRepository` methods in `frontend/lib/features/billing/data/invoice_repository.dart`: `createFromVisit`, `discardDraft`, `addItem`, `updateItem`, `removeItem`, `issue`, `getDetail`
- [X] T021 [US1] Implement `InvoiceEditorNotifier` in `frontend/lib/features/billing/presentation/providers/invoice_editor_notifier.dart` with optimistic-concurrency conflict handling (stale `updated_at` → refresh prompt)
- [X] T022 [US1] Implement `frontend/lib/features/billing/presentation/pages/invoice_editor_page.dart` with `invoice_items_editor.dart` widget; surface `branch_code_missing` error inline on issue
- [X] T023 [US1] Add **Create invoice** / **Open invoice** action in `frontend/lib/features/visits/presentation/widgets/visit_detail_actions.dart` against `completed` visits, deep-linking to the editor or detail page
- [X] T024 [US1] Implement `invoice_status_badge.dart` widget and a minimal `invoice_detail_page.dart` (header + items + balance) for navigation continuity after issue

**Checkpoint**: User Story 1 is fully functional — staff can produce issued invoices end-to-end.

---

## Phase 4: User Story 2 - Record Partial and Full Payments (Priority: P1)

**Goal**: Record payments (cash/card/bank_transfer/insurance_settlement) and refunds against issued invoices, honoring the `allow_partial_payments` org setting and preventing overpayment under concurrency.

**Independent Test**: Per spec — issue an invoice, record full and partial payments under both setting values, verify status transitions and overpayment rejection.

### Tests for User Story 2

- [X] T025 [P] [US2] In `backend/tests/billing_crud.sql`, add scenarios: full-balance payment marks `paid`; partial payment with setting ON moves to `partially_paid`; partial patient-tender payment with setting OFF is rejected (`partial_payments_disabled`); `insurance_settlement` partial is always allowed; overpayment rejected; refund moves status back; status transitions audited
- [X] T026 [P] [US2] Create `backend/tests/billing_concurrency.sql` simulating two near-simultaneous payments racing to zero balance — exactly one accepted, one rejected with `overpayment` (use `pg_background` or sequential txns with savepoints to emulate)
- [X] T027 [P] [US2] Add `frontend/test/integration/billing/record_payment_test.dart` covering acceptance scenarios 1, 1a, 2, 3, 6 (concurrent), and 7 (refund) of US2

### Implementation for User Story 2

- [X] T028 [P] [US2] Add `record_payment` and `record_refund` RPCs per `contracts/billing-mutations.md` (row-locked balance recompute; reads `organization_billing_settings.allow_partial_payments`; patient-tender vs insurance-settlement branching; audit with prior/new balance)
- [X] T029 [P] [US2] Implement `PaymentRepository.recordPayment` and `recordRefund` in `frontend/lib/features/billing/data/payment_repository.dart`
- [X] T030 [US2] Implement `payment_notifier.dart` provider and `payment_form.dart` widget (method, amount, reference, note); when `allow_partial_payments=false` and method ∈ {cash, card, bank_transfer}, pre-fill amount = balance and disable editing with explanatory tooltip (UI-level guard; server enforces too)
- [X] T031 [US2] Implement `refund_form.dart` widget (gated by `canRefundPayment`; mandatory reason)
- [X] T032 [US2] Extend `invoice_detail_page.dart` to render the payments list and embed `payment_form.dart`/`refund_form.dart`; backend-first refresh on focus

**Checkpoint**: Stories 1+2 together deliver the MVP billing loop (create → issue → collect → refund).

---

## Phase 5: User Story 8 - Configure "Allow Partial Payments" Setting (Priority: P2)

**Goal**: Owner/administrator can toggle the org-level partial-payments policy; the toggle is hidden/read-only for other roles.

**Independent Test**: Per spec US8 Independent Test — verify default off, admin can toggle, receptionist cannot, server rejects unauthorized mutations.

> Placed before US3..US7 because Story 2's enforcement reads this setting; toggling it is part of the validated payment flow.

### Tests for User Story 8

- [X] T033 [P] [US8] Extend `backend/tests/billing_crud.sql` (or new file `backend/tests/billing_settings.sql` orchestrated by `run_billing_tests.sh`): owner/admin can read+update; receptionist can read but UPDATE raises `permission_denied`; doctor/lab_staff read raises `permission_denied`; setting change is audited; default value is `false` for newly-created orgs (via trigger)
- [X] T034 [P] [US8] Add `frontend/test/widget/billing/billing_settings_section_test.dart` verifying admin sees an editable toggle, receptionist sees read-only, doctor/lab_staff don't see the section

### Implementation for User Story 8

- [X] T035 [P] [US8] Add `get_billing_settings` and `update_billing_settings` RPCs per `contracts/billing-mutations.md` and `contracts/billing-queries.md`; `update_billing_settings` checks both `settings.billing.manage` AND caller role ∈ {owner, administrator}
- [X] T036 [P] [US8] Implement `BillingSettingsRepository.get` and `update` in `frontend/lib/features/billing/data/billing_settings_repository.dart`
- [X] T037 [US8] Implement `billing_settings_notifier.dart` provider with backend-first refresh
- [X] T038 [US8] Implement `frontend/lib/features/organization_settings/presentation/widgets/billing_settings_section.dart` and mount inside the existing organization Settings page from V1-2; gate edit affordance with `canManageBillingSettings`

**Checkpoint**: The org-wide partial-payment policy is fully configurable; payment enforcement (US2) reflects toggle changes immediately on next payment attempt.

---

## Phase 6: User Story 3 - Apply a Discount to an Invoice (Priority: P2)

**Goal**: Apply line-level OR invoice-level discounts on draft invoices (mutually exclusive), permission-gated and audited.

**Independent Test**: Per spec US3 Independent Test — apply a line discount, attempt invoice discount and verify rejection; clear and apply invoice discount; verify receipts/totals.

### Tests for User Story 3

- [X] T039 [P] [US3] In `backend/tests/billing_crud.sql`, add scenarios: line discount valid/invalid bounds; invoice discount valid/invalid bounds; mutual exclusion raises `discount_scope_conflict` from both directions; trigger blocks any concurrent path that would yield both scopes non-zero; clearing a scope (NULL/NULL) re-enables the other
- [X] T040 [P] [US3] Add `frontend/test/integration/billing/discount_scopes_test.dart` covering US3 acceptance scenarios 1, 2, 2a, 3, 4, 5, 6

### Implementation for User Story 3

- [X] T041 [P] [US3] Add `apply_line_discount` and `apply_invoice_discount` RPCs per `contracts/billing-mutations.md` (pre-check exclusivity; audit with scope tag)
- [X] T042 [P] [US3] Implement `line_discount_field.dart` (per-item input) and `invoice_discount_panel.dart` widgets
- [X] T043 [US3] Implement `discount_scope_guard.dart` widget that disables the inactive scope's inputs when the other is non-zero and offers a "Clear other scope" affordance
- [X] T044 [US3] Wire discount widgets into `invoice_editor_page.dart`; ensure totals re-render from server response

**Checkpoint**: Discounts work with the mutual-exclusion constraint enforced top-to-bottom.

---

## Phase 7: User Story 4 - Record Insurance Coverage on an Invoice (Priority: P2)

**Goal**: Set insurance provider and covered amount on a draft invoice; manage the org-scoped insurance provider catalog.

**Independent Test**: Per spec US4 — select provider, enter covered amount, verify split on receipt and patient-due balance; deactivate provider and verify selectors.

### Tests for User Story 4

- [X] T045 [P] [US4] In `backend/tests/billing_crud.sql`, add: insurance set bounds (`0 ≤ amount ≤ subtotal - discount`); provider deactivation hides from selector but preserves history; cross-org provider access denied
- [X] T046 [P] [US4] Add `frontend/test/widget/billing/insurance_panel_test.dart` and `insurance_providers_page_test.dart`

### Implementation for User Story 4

- [X] T047 [P] [US4] Add `set_insurance_coverage`, `insurance_provider_upsert`, `insurance_provider_deactivate`, `list_insurance_providers` RPCs per contracts
- [X] T048 [P] [US4] Implement `InsuranceProviderRepository` methods
- [X] T049 [P] [US4] Implement `insurance_panel.dart` (provider selector + covered amount input + empty-state)
- [X] T050 [US4] Implement `frontend/lib/features/billing/presentation/pages/insurance_providers_page.dart` (list/create/edit/deactivate, gated by `canManageInsurance`)
- [X] T051 [US4] Wire `insurance_panel.dart` into `invoice_editor_page.dart`

**Checkpoint**: Insurance split is captured and displayed; provider catalog is manageable by authorized users.

---

## Phase 8: User Story 5 - List, Search, and View Invoices (Priority: P2)

**Goal**: Reception/billing/admin can find invoices via filters and pagination; detail loads backend-first.

**Independent Test**: Per spec US5 — create varied invoices, apply filters, verify results and pagination.

### Tests for User Story 5

- [X] T052 [P] [US5] Extend `backend/tests/billing_crud.sql` with `list_invoices` query scenarios: status filter, patient search, date range, branch intersection, pagination boundary
- [X] T053 [P] [US5] Add `frontend/test/integration/billing/invoice_list_test.dart` covering US5 acceptance scenarios 1–6

### Implementation for User Story 5

- [X] T054 [P] [US5] Implement `InvoiceRepository.listInvoices` and `listPatientInvoices`
- [X] T055 [P] [US5] Implement `invoice_list_notifier.dart` (debounced filter state, pagination)
- [X] T056 [US5] Implement `frontend/lib/features/billing/presentation/pages/invoice_list_page.dart` with filter bar (status, branch, patient, date range, invoice number) and pagination controls
- [X] T057 [US5] Add **Billing** tab to patient profile via `frontend/lib/features/patients/presentation/widgets/patient_billing_section.dart` consuming `listPatientInvoices`

**Checkpoint**: Invoice list and patient billing history surface are usable for daily reconciliation.

---

## Phase 9: User Story 6 - Void an Invoice (Priority: P3)

**Goal**: Admin/void-permitted users can void `issued`/`partially_paid` invoices with a reason; `paid` requires refund first; voided invoices reject mutations.

**Independent Test**: Per spec US6 — issue, void with reason, verify lock and that a new invoice can be created for the same visit.

### Tests for User Story 6

- [X] T058 [P] [US6] Extend `backend/tests/billing_crud.sql` with: void of `issued`/`partially_paid` succeeds; void of `paid` rejected (`invoice_not_voidable`); mutations on voided invoice all rejected; voided history remains visible; new invoice allowed after void
- [X] T059 [P] [US6] Add `frontend/test/integration/billing/void_invoice_test.dart` covering US6 acceptance scenarios 1–5

### Implementation for User Story 6

- [X] T060 [P] [US6] Add `void_invoice` RPC per `contracts/billing-mutations.md` (locks invoice, mandatory reason, audited)
- [X] T061 [P] [US6] Implement `void_invoice_dialog.dart` widget with reason field
- [X] T062 [US6] Wire void action into `invoice_detail_page.dart` (visible only when `canVoidInvoice` and status is voidable)

**Checkpoint**: Void path operational.

---

## Phase 10: User Story 7 - Print an Invoice Receipt (Priority: P3)

**Goal**: Render a printable receipt for any non-purged invoice state with appropriate watermarks; invoke OS print pipeline.

**Independent Test**: Per spec US7 — open print preview for draft/issued/partially_paid/paid/voided and verify watermarks/fields.

### Tests for User Story 7

- [X] T063 [P] [US7] Add `frontend/test/widget/billing/receipt_print_preview_test.dart` covering watermark rendering (draft/voided) and required field presence; smoke-test that the receipt renders within NFR-004 budget for ≤100 items
- [X] T064 [P] [US7] Add `frontend/test/integration/billing/print_receipt_test.dart` invoking the preview from `invoice_detail_page.dart`

### Implementation for User Story 7

- [X] T065 [P] [US7] Implement `receipt_print_preview.dart` widget producing a PDF via the `printing`/`pdf` packages, including line-discount columns when present, invoice-level discount row when present (never both, by US3 invariant), insurance line, payments list, balance
- [X] T066 [US7] Add print action to `invoice_detail_page.dart` (and a draft-preview affordance in `invoice_editor_page.dart`) using `Printing.layoutPdf` to invoke the OS-native dialog

**Checkpoint**: All eight user stories independently complete.

---

## Phase 11: Polish & Cross-Cutting Concerns

- [ ] T067 [P] Run `bash backend/tests/run_billing_tests.sh` and ensure all three SQL suites pass; capture output for the PR description
- [ ] T068 [P] Run `flutter test` against `frontend/test/{unit,widget,integration}/billing/` and ensure all green
- [ ] T069 [P] Documentation: append a short "Billing" section to any operator-facing notes in `docs/architecture/` if such conventions exist; reference `specs/operations/billing.spec.md` placeholder per FR-026
- [ ] T070 Performance pass: verify invoice list pagination remains snappy at 5,000 rows per branch (NFR-003) and receipt preview renders ≤2s for 100 items (NFR-004); add any missing indexes
- [ ] T071 Security pass: confirm `\dp public.payments` shows no UPDATE/DELETE grants; confirm `settings.billing.manage` cannot be granted to non-admin/owner via role-permission RPC
- [ ] T072 Walk through `specs/007-billing/quickstart.md` against a fresh local Supabase + Flutter build; record any deviations and file follow-up issues
- [ ] T073 Constitution compliance review: Principle I (no scope creep beyond V1-6), II (no new service tier), III (RPCs hold authority, RLS enforces isolation), IV (defense in depth + audit), V (AI absent, subscription-state-tolerant)

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: no dependencies
- **Foundational (Phase 2)**: depends on Setup; **BLOCKS all user stories**
- **User Stories** (Phases 3–10): all depend on Foundational; US2 also depends conceptually on US8's setting record existing (provided by Phase 2 trigger, so Phases 3+ can run in any order)
- **Polish (Phase 11)**: depends on all desired user stories

### User Story Dependencies

- **US1 (P1, MVP)**: depends only on Foundational
- **US2 (P1)**: depends on Foundational + US1 (needs an issued invoice to pay); Phase 5 (US8) provides the setting record but the row is already auto-created by the Phase 2 trigger, so US2 is functional without US8 toggling
- **US8 (P2)**: independent of other stories; placed early because it materially affects US2 behavior testing
- **US3 (P2)**: depends on US1 (needs a draft invoice and items)
- **US4 (P2)**: depends on US1 (needs a draft invoice)
- **US5 (P2)**: depends on US1 (needs invoices to list)
- **US6 (P3)**: depends on US1+US2 (needs issued/partially_paid invoices)
- **US7 (P3)**: depends on US1 minimum, ideally US2+US3+US4 for full receipt content

### Parallel Opportunities

- Phase 1 T002, T003 in parallel.
- Phase 2 T007, T008, T010, T011, T012, T013, T015 in parallel after T004–T006 land (all read from the migration but touch different files).
- Within each user story, [P]-marked tasks (typically: backend RPC + frontend repo + frontend widget scaffolding) run in parallel.
- Different developers can take US3 (discounts), US4 (insurance), US5 (list), US8 (settings) in parallel once US1 is complete.

---

## Parallel Example: User Story 1

```bash
# Backend + frontend can proceed simultaneously once Foundational is done:
Task: "Add RPCs create_invoice_from_visit, discard_draft_invoice, add/update/remove_invoice_item, issue_invoice in backend/supabase/migrations/20260605180000_billing.sql"
Task: "Add query RPCs get_invoice_detail and list_invoices"
Task: "Implement InvoiceRepository methods in frontend/lib/features/billing/data/invoice_repository.dart"

# Tests can be written in parallel:
Task: "Add backend SQL scenarios in backend/tests/billing_crud.sql"
Task: "Add Flutter integration test frontend/test/integration/billing/create_and_issue_invoice_test.dart"
```

---

## Implementation Strategy

### MVP First (US1 + US2)

1. Complete Phase 1 (Setup).
2. Complete Phase 2 (Foundational) — schema + RLS + permission seed + settings trigger + frontend wiring.
3. Complete Phase 3 (US1) — create/issue invoices end-to-end.
4. Complete Phase 4 (US2) — record payments and refunds.
5. **Validate**: a clinic can now create an invoice, collect payment, and process a refund. This is the minimum operationally viable billing slice.

### Incremental Delivery

1. MVP (US1+US2) → demo to staff.
2. Add Phase 5 (US8) → enables the partial-payment policy toggle; lets clinics that require full payment opt in.
3. Add Phase 6 (US3) → discounts.
4. Add Phase 7 (US4) → insurance split.
5. Add Phase 8 (US5) → list/search experience.
6. Add Phase 9 (US6) → void path.
7. Add Phase 10 (US7) → printed receipts (ideally before broad rollout).
8. Phase 11 polish.

### Parallel Team Strategy

After Foundational completes, three developers can split:
- Dev A: US1 → US2 (the payment loop)
- Dev B: US3 + US4 (financial accuracy: discounts + insurance)
- Dev C: US5 + US8 (operational surfaces: list + settings)
Then US6 and US7 either roll into Dev A or are taken by whoever finishes first.

---

## Notes

- All mutation RPCs MUST write audit log rows per FR-023 with prior/new key values; reviewer SHOULD spot-check audit payload shape during code review.
- All money fields are `numeric(14,2)`; never `float`/`double`.
- Payments table MUST NOT have UPDATE/DELETE grants — verify in T071.
- Backend-first fetch (FR-030) is mandatory for invoice list, invoice detail, payment screens, and billing settings UI.
- Stop at any checkpoint to validate the corresponding user story in isolation.
- Preserve layer boundaries: no domain authority in Flutter; no AI in V1-6.
