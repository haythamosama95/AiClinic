---
description: "Task list for Service Catalog (015) implementation"
---

# Tasks: Service Catalog (015)

**Input**: Design documents from `specs/015-service-catalog/`

**Prerequisites**: plan.md (required), spec.md (user stories), research.md, data-model.md, contracts/ (service-management, branch-configuration, pricing-and-eligibility, billing-integration), quickstart.md

**Tests**: INCLUDED. The plan's Testing section mandates SQL suites (`service_catalog_crud.sql`, `service_catalog_rls.sql`, `service_catalog_pricing.sql`, `service_catalog_concurrency.sql`) plus Flutter unit/widget tests, and the constitution requires proving RLS, RPC validation, and auditability.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing. Priorities from spec.md: **US1, US2 = P1**; **US3, US4, US5, US6 = P2**; **US7 (+ FR-031 new-branch setup) = P3**.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependency on incomplete tasks)
- **[Story]**: US1–US7 for story-phase tasks (Setup/Foundational/Polish carry no story label)
- All paths are repo-root-relative

## Path Conventions

- **Flutter desktop app**: `frontend/lib/features/service_catalog/`, `frontend/test/`
- **Supabase backend**: `backend/supabase/migrations/`, `backend/tests/`
- Migration timestamps MUST sort after the newest existing migration (`20260711210000_*`) → use `20260712NNNNNN_*`

**Migration files (shared across stories; edited sequentially, never in parallel)**:

- `20260712090000_service_catalog.sql` — schema + RLS + audit + permission seed (Foundational)
- `20260712090500_service_catalog_rpcs.sql` — service mgmt + branch config + promotion + copy + new-branch setup RPCs (US1, US3, US4, US5, US7)
- `20260712091000_service_catalog_pricing_rpcs.sql` — resolve/search/list/get read RPCs (US1, US2, US6)
- `20260712091500_service_catalog_billing_integration.sql` — `invoice_items` ALTER + `add_invoice_item_from_service` (US2)

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Architecture-safe module scaffolding and empty artifact files

- [ ] T001 Create the feature module tree `frontend/lib/features/service_catalog/{domain,data,application,presentation/{models,providers,pages,widgets}}/` and test dirs `frontend/test/unit/service_catalog/` and `frontend/test/widget/service_catalog/`
- [ ] T002 [P] Create the four empty migration files with correct sort-after prefixes in `backend/supabase/migrations/`: `20260712090000_service_catalog.sql`, `20260712090500_service_catalog_rpcs.sql`, `20260712091000_service_catalog_pricing_rpcs.sql`, `20260712091500_service_catalog_billing_integration.sql`
- [ ] T003 [P] Create backend test runner `backend/tests/run_service_catalog_tests.sh` (mirroring the billing harness) and register it in `backend/tests/run_all_backend_tests.sh`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Schema, security, permissions, and shared client primitives every story depends on

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [ ] T004 Author base schema in `backend/supabase/migrations/20260712090000_service_catalog.sql`: enums (`service_global_status`, `service_branch_status`, `service_copy_mode`), tables `public.services` and `public.service_branches` with all columns, CHECK constraints (name length, `default_price>=0`, override/promotion `>=0`, promotion all-or-nothing + `start<=end`), partial unique indexes (`services_org_name_unique`, `service_branches_service_branch_unique`), secondary indexes, and `apply_standard_audit_triggers` on both tables per `specs/015-service-catalog/data-model.md`
- [ ] T005 Add RLS to both tables in `backend/supabase/migrations/20260712090000_service_catalog.sql`: authenticated-only, org isolation via `jwt_organization_id()`, branch scoping for `service_branches`, read helper `auth_internal.staff_has_services_read_access()` allowing `invoices.create` selection reads, exclusion of soft-deleted rows, and denial of direct INSERT/UPDATE/DELETE (mutations only via RPC)
- [ ] T006 Seed permission keys `services.view` and `services.manage` to `owner` and `administrator` in `backend/supabase/migrations/20260712090000_service_catalog.sql` using the billing `INSERT ... ON CONFLICT (role, permission_key) DO UPDATE` idiom
- [ ] T007 [P] Add `servicesView` (`services.view`) and `servicesManage` (`services.manage`) constants to `frontend/lib/features/auth/domain/permission_keys.dart`
- [ ] T008 [P] Expose the new keys through `frontend/lib/core/auth/permission_service.dart` (helpers/`canManageServices`/`canViewServices` as appropriate to that file's pattern)
- [ ] T009 [P] Create shared domain primitives `frontend/lib/features/service_catalog/domain/service.dart` (Service model: id, name, `defaultPrice: Money`, `globalStatus`, timestamps) and `frontend/lib/features/service_catalog/domain/global_status.dart` (enum active/inactive), no framework/SDK imports
- [ ] T010 [P] Create repository skeleton `frontend/lib/features/service_catalog/data/service_catalog_repository.dart` using the `AppRpcInvoker` mixin and returning `RpcResult`/`RpcFailure` (methods added per story)
- [ ] T011 [P] Create `frontend/lib/features/service_catalog/application/service_catalog_rpc_messages.dart` mapping RPC error codes (`STALE_SERVICE`, `STALE_SERVICE_BRANCH`, `DUPLICATE_NAME`, `INVALID_PRICE`, `BRANCH_NOT_IN_ORG`, `BRANCH_NOT_ASSIGNED`, `PROMO_EXCEEDS_PRICE`, `PROMO_INCOMPLETE`, `PROMO_DATE_RANGE`, `INVALID_COPY_TARGET`, `SERVICE_NOT_ELIGIBLE`, `NOT_FOUND`, `FORBIDDEN`) to user-facing messages

**Checkpoint**: Schema live, RLS + permissions enforced, client primitives available — user stories can begin

---

## Phase 3: User Story 1 - Create a Service and Assign Branches (Priority: P1) 🎯 MVP

**Goal**: Owners/administrators create an org-scoped service (name, default price, global status) and assign it to all/selected branches, forming the governed catalog root.

**Independent Test**: Create "Consultation" (default 200) assigned to two of three branches; verify `service_branches` rows exist for exactly those two branches, a duplicate name is rejected, and a negative price is rejected.

### Implementation for User Story 1

- [ ] T012 [US1] Implement `create_service` (`auth_internal` + `public` wrapper) in `backend/supabase/migrations/20260712090500_service_catalog_rpcs.sql`: assert `services.manage`, trim/validate unique name (`DUPLICATE_NAME`), `default_price>=0` (`INVALID_PRICE`), insert service, expand assignment (all-branches or validated `p_branch_ids` → `BRANCH_NOT_IN_ORG`) into `service_branches`, audit `service.create` + `service.branch.assign` (contract: service-management.md)
- [ ] T013 [US1] Implement `set_service_branch_assignment` in `backend/supabase/migrations/20260712090500_service_catalog_rpcs.sql`: assign (upsert/reactivate soft-deleted rows) or unassign (soft-delete rows), audit `service.branch.assign`/`unassign`
- [ ] T014 [US1] Implement `get_service` read RPC in `backend/supabase/migrations/20260712091000_service_catalog_pricing_rpcs.sql`: assert `services.view`/`services.manage`, return service + its non-deleted `service_branches` rows scoped to `jwt_branch_ids()` (editor backend-first load, FR-028)
- [ ] T015 [US1] Add `createService`, `setBranchAssignment`, and `getService` methods to `frontend/lib/features/service_catalog/data/service_catalog_repository.dart`
- [ ] T016 [US1] Create `frontend/lib/features/service_catalog/presentation/providers/service_editor_notifier.dart` (AsyncNotifier) handling create + branch-assignment submission and error mapping
- [ ] T017 [US1] Create `frontend/lib/features/service_catalog/presentation/widgets/service_form.dart`: name, default price (Money), global status, and branch-assignment (all/selected) with inline validation
- [ ] T018 [US1] Create `frontend/lib/features/service_catalog/presentation/pages/service_editor_page.dart` composing `service_form` with loading/saving/error/permission-denied states via `core/ui`
- [ ] T019 [US1] Register the service editor route with a `services.manage` guard in `frontend/lib/app/app_routes.dart` and `frontend/lib/app/router.dart` (reuse `core/auth/auth_route_guard.dart`)

### Tests for User Story 1

- [ ] T020 [P] [US1] Add create + branch-assignment CRUD cases (duplicate-name, negative-price, all/selected expansion, org scope) to `backend/tests/service_catalog_crud.sql`
- [ ] T021 [P] [US1] Add RLS cases (cross-org SELECT denial, direct INSERT/UPDATE/DELETE denial) to `backend/tests/service_catalog_rls.sql`
- [ ] T022 [P] [US1] Add Dart unit tests for Service model parsing, `service_editor_notifier` create flow, and `service_form` validation in `frontend/test/unit/service_catalog/`

**Checkpoint**: US1 delivers a governed, org-scoped, branch-assigned catalog — independently testable

---

## Phase 4: User Story 2 - Select a Catalog Service on an Invoice with Correct Pricing (Priority: P1)

**Goal**: Billing staff select eligible services (no free-text) and the server resolves + snapshots the effective unit price (promo → override → default) at add time.

**Independent Test**: On a draft invoice at Branch B, add "Consultation" via the selector → unit price equals resolved effective price, snapshot stored, re-selecting increments quantity; later changing the catalog price leaves the invoice line unchanged.

### Implementation for User Story 2

- [ ] T023 [US2] Implement internal helper `auth_internal.resolve_effective_service_price(service, branch, on_date)` returning `{eligible, unit_price, applied_rule, reason}` and the public `resolve_effective_service_price` read RPC in `backend/supabase/migrations/20260712091000_service_catalog_pricing_rpcs.sql` (priority promo→override→default; eligibility = global-active AND assigned AND branch-active)
- [ ] T024 [US2] Implement `search_eligible_services` read RPC in `backend/supabase/migrations/20260712091000_service_catalog_pricing_rpcs.sql`: assert `invoices.create`/`services.view`/`services.manage` for the branch, return eligible services matching `ILIKE '%query%'` with resolved price + `on_promotion` flag (clamped limit)
- [ ] T025 [US2] Add the additive `invoice_items` ALTER (`service_id uuid` FK + `invoice_items_service_idx`) in `backend/supabase/migrations/20260712091500_service_catalog_billing_integration.sql` (nullable to preserve historical rows; `description` repurposed as name snapshot)
- [ ] T026 [US2] Implement `add_invoice_item_from_service` in `backend/supabase/migrations/20260712091500_service_catalog_billing_integration.sql`: assert `invoices.create`, `lock_draft_invoice` (`STALE_INVOICE`), resolve price for invoice branch + `current_date`, reject ineligible (`SERVICE_NOT_ELIGIBLE` + reason), create-or-increment with snapshot (`description`/`unit_price`/`quantity`/totals), `refresh_invoice_subtotal`, audit `invoice.item.add_from_service`
- [ ] T027 [P] [US2] Create domain `frontend/lib/features/service_catalog/domain/effective_price.dart` (resolved price + applied rule) and `frontend/lib/features/service_catalog/domain/service_eligibility.dart` (pure eligibility descriptor with reason)
- [ ] T028 [US2] Add `resolveEffectivePrice`, `searchEligibleServices`, and `addInvoiceItemFromService` methods to `frontend/lib/features/service_catalog/data/service_catalog_repository.dart`
- [ ] T029 [US2] Create `frontend/lib/features/service_catalog/presentation/providers/service_selector_notifier.dart` (debounced eligible-services search for the invoice editor, backend-first)
- [ ] T030 [US2] Create `frontend/lib/features/service_catalog/presentation/widgets/invoice_service_selector.dart` (type-ahead, eligibility-aware results, price + "on promotion" badge, keyboard-navigable) reusing the `catalog_autocomplete_field` interaction pattern
- [ ] T031 [US2] Create `frontend/lib/features/service_catalog/presentation/widgets/service_price_preview.dart` with a pure, testable price-preview formatter reused across widgets (NFR-008)
- [ ] T032 [US2] Modify `frontend/lib/features/billing/presentation/widgets/invoice_items_editor.dart` to remove the free-text description input (FR-012), embed `InvoiceServiceSelector`, call `add_invoice_item_from_service` on selection, and keep quantity editable with read-only snapshot unit price (FR-014)

### Tests for User Story 2

- [ ] T033 [P] [US2] Add pricing cases (priority resolution, add-to-invoice snapshot immutability, create-or-increment, ineligible rejection) to `backend/tests/service_catalog_pricing.sql`
- [ ] T034 [P] [US2] Add widget test for `invoice_service_selector` and unit tests for the price-preview formatter + `service_eligibility` descriptor in `frontend/test/widget/service_catalog/` and `frontend/test/unit/service_catalog/`

**Checkpoint**: US1+US2 = MVP — governed catalog with correctly-priced, snapshot-stable invoice selection

---

## Phase 5: User Story 3 - Configure Branch Price Override and Activation (Priority: P2)

**Goal**: Per assigned branch, activate/deactivate a service and set/clear a non-negative price override, with default-price fallback.

**Independent Test**: For "Consultation" (default 200), set Branch B override 150 and Branch C inactive; verify B resolves 150, A (no override) resolves 200, C is not selectable; configuring an unassigned branch is rejected.

### Implementation for User Story 3

- [ ] T035 [US3] Implement `configure_service_branch` in `backend/supabase/migrations/20260712090500_service_catalog_rpcs.sql`: require assigned row (`BRANCH_NOT_ASSIGNED`), concurrency (`STALE_SERVICE_BRANCH`), validate override `>=0` (`INVALID_PRICE`), invariant guard (`PROMO_EXCEEDS_PRICE`), set status/override, audit `service.branch.configure`
- [ ] T036 [P] [US3] Create domain `frontend/lib/features/service_catalog/domain/service_branch_config.dart` (per-branch status, nullable override, optional promotion)
- [ ] T037 [US3] Add `configureServiceBranch` method to `frontend/lib/features/service_catalog/data/service_catalog_repository.dart`
- [ ] T038 [US3] Create `frontend/lib/features/service_catalog/presentation/widgets/branch_configuration_matrix.dart` (per-branch rows: assigned/active toggle + override input, empty = default) reusing `core/ui`
- [ ] T039 [US3] Extend `frontend/lib/features/service_catalog/presentation/providers/service_editor_notifier.dart` and `service_editor_page.dart` to load (`get_service`) and mutate branch config via the matrix with optimistic concurrency

### Tests for User Story 3

- [ ] T040 [P] [US3] Add override-resolution + default-fallback + unassigned-branch-rejection cases to `backend/tests/service_catalog_pricing.sql`, and a `STALE_SERVICE_BRANCH` stale-write case to `backend/tests/service_catalog_concurrency.sql`
- [ ] T041 [P] [US3] Add widget test for `branch_configuration_matrix` (toggles, override empty=default, validation) in `frontend/test/widget/service_catalog/`

**Checkpoint**: Branch-level activation + override work on top of US1

---

## Phase 6: User Story 4 - Configure Promotional Pricing per Branch (Priority: P2)

**Goal**: A single time-boxed promotion per (service, branch) with inclusive dates that auto-applies within the window and reverts afterward, enforcing `promotion_price ≤ effective price`.

**Independent Test**: Branch C promo 100 for 01-Jan..31-Jan over override 120 → invoices on 15-Jan and 31-Jan resolve 100, 01-Feb resolves 120; promo > effective, missing a date, or start>end are rejected.

### Implementation for User Story 4

- [ ] T042 [US4] Implement `set_service_promotion` (set/replace/clear) in `backend/supabase/migrations/20260712090500_service_catalog_rpcs.sql`: require assigned row, concurrency, validate all-three-present (`PROMO_INCOMPLETE`), `start<=end` (`PROMO_DATE_RANGE`), `>=0` (`INVALID_PRICE`), `promotion_price<=effective` (`PROMO_EXCEEDS_PRICE`), overwrite single window, audit `service.promotion.set`/`clear`
- [ ] T043 [P] [US4] Create domain `frontend/lib/features/service_catalog/domain/service_promotion.dart` value object (price + inclusive start/end) with pure `isActiveOn(date)`
- [ ] T044 [US4] Add `setServicePromotion` method to `frontend/lib/features/service_catalog/data/service_catalog_repository.dart`
- [ ] T045 [US4] Create `frontend/lib/features/service_catalog/presentation/widgets/promotion_editor.dart` (price + inclusive start/end + client-side validation + expired indicator) and wire it into `branch_configuration_matrix.dart`

### Tests for User Story 4

- [ ] T046 [P] [US4] Add promotion cases (inclusive boundaries, promo-over-effective rejection at save and on later default/override lowering, incomplete/invalid dates, single-window replace) to `backend/tests/service_catalog_pricing.sql`
- [ ] T047 [P] [US4] Add unit test for `service_promotion.isActiveOn` and widget test for `promotion_editor` validation in `frontend/test/`

**Checkpoint**: Promotions layered on branch config (US3)

---

## Phase 7: User Story 5 - Edit a Service and Change Global Status (Priority: P2)

**Goal**: Edit name/default price/assignments/config/global status and soft-delete, affecting only future invoices while preserving historical snapshots.

**Independent Test**: Rename "Consultation"→"General Consultation", raise default to 220, mark globally inactive → new invoices can't select it and previously issued lines keep their old snapshot; soft-deleting a referenced service hides it but retains history.

### Implementation for User Story 5

- [ ] T048 [US5] Implement `update_service` in `backend/supabase/migrations/20260712090500_service_catalog_rpcs.sql`: lock row, org scope (`NOT_FOUND`), concurrency (`STALE_SERVICE`), name uniqueness (`DUPLICATE_NAME`), price validity (`INVALID_PRICE`), default-price-lowering invariant guard (`PROMO_EXCEEDS_PRICE`), audit `service.update`
- [ ] T049 [US5] Implement `set_service_global_status` in `backend/supabase/migrations/20260712090500_service_catalog_rpcs.sql`: concurrency, set status, audit `service.status`
- [ ] T050 [US5] Implement `soft_delete_service` in `backend/supabase/migrations/20260712090500_service_catalog_rpcs.sql`: concurrency, soft-delete service + child `service_branches`, never hard delete, audit `service.delete`
- [ ] T051 [US5] Add `updateService`, `setGlobalStatus`, and `softDeleteService` methods to `frontend/lib/features/service_catalog/data/service_catalog_repository.dart`
- [ ] T052 [US5] Extend `service_editor_notifier.dart`/`service_editor_page.dart` for edit + global-status toggle + soft-delete with a destructive-action confirmation dialog and stale-conflict refresh prompt

### Tests for User Story 5

- [ ] T053 [P] [US5] Add edit-history-stability + soft-delete-of-referenced-service cases to `backend/tests/service_catalog_crud.sql`
- [ ] T054 [P] [US5] Add a `STALE_SERVICE` stale-write case to `backend/tests/service_catalog_concurrency.sql`
- [ ] T055 [P] [US5] Add Dart unit test for the edit/global-status/soft-delete notifier flows in `frontend/test/unit/service_catalog/`

**Checkpoint**: Full catalog maintenance lifecycle with history immutability

---

## Phase 8: User Story 6 - Browse, Search, and Filter the Catalog (Priority: P2)

**Goal**: Paginated management surface with name/status/branch filters and at-a-glance branch/pricing summary.

**Independent Test**: With mixed services, search by name fragment, filter by status `inactive`, filter by branch → correct paginated results; a user lacking `services.view`/`services.manage` is blocked from the management screen.

### Implementation for User Story 6

- [ ] T056 [US6] Implement `list_services` read RPC in `backend/supabase/migrations/20260712091000_service_catalog_pricing_rpcs.sql`: assert `services.view`/`services.manage`, org scope, exclude soft-deleted, optional name/status/branch filters (branch adds `branch_summary`), `total` + paginated `items` ordered by name
- [ ] T057 [P] [US6] Create presentation model `frontend/lib/features/service_catalog/presentation/models/service_list_filters.dart` (name/status/branch filters + pagination)
- [ ] T058 [US6] Create `frontend/lib/features/service_catalog/presentation/providers/service_catalog_list_notifier.dart` (backend-first list/search/filter with pagination)
- [ ] T059 [US6] Create `frontend/lib/features/service_catalog/presentation/pages/service_catalog_list_page.dart` (results/empty/loading/error/permission-denied + pagination) and register its route with a `services.view` guard in `frontend/lib/app/app_routes.dart` + `router.dart`
- [ ] T060 [P] [US6] Add unit tests for `service_list_filters` and `service_catalog_list_notifier` in `frontend/test/unit/service_catalog/`
- [ ] T061 [P] [US6] Add widget test for `service_catalog_list_page` states (loading/empty/results/filter/permission-denied) in `frontend/test/widget/service_catalog/`

**Checkpoint**: Manageable, searchable catalog at scale (NFR-003)

---

## Phase 9: User Story 7 - Copy Branch Configuration + New-Branch Setup (Priority: P3)

**Goal**: Copy assignment/activation/override/promotion between branches (`merge`/`replace` with confirmation) and onboard new branches via select / copy-all / copy-then-modify (FR-031).

**Independent Test**: Fully configure Branch A, copy to empty Branch D with `merge` → D matches A; change a value in D, copy again with `replace` (confirm) → D matches A; cancel at confirm → no change. Creating a new branch offers the setup step and leaves it empty until completed.

### Implementation for User Story 7

- [ ] T062 [US7] Implement `copy_service_branch_configuration` in `backend/supabase/migrations/20260712090500_service_catalog_rpcs.sql`: both branches in org/`jwt_branch_ids()`, source≠target (`INVALID_COPY_TARGET`), `merge` (create missing only) vs `replace` (overwrite; server idempotent), re-validate invariant, audit `service.branch.copy` with `{source, target, mode, affected_service_ids}`
- [ ] T063 [US7] Implement `setup_new_branch_services` (FR-031) in `backend/supabase/migrations/20260712090500_service_catalog_rpcs.sql`: `select` assigns listed services; `copy_all`/`copy_modify` delegate to `copy_service_branch_configuration`; audit `service.branch.setup`
- [ ] T064 [US7] Add `copyConfiguration` and `setupNewBranchServices` methods to `frontend/lib/features/service_catalog/data/service_catalog_repository.dart`
- [ ] T065 [US7] Create `frontend/lib/features/service_catalog/presentation/widgets/copy_configuration_dialog.dart` (source/target pickers + mode + explicit replace-confirmation, no changes on cancel)
- [ ] T066 [US7] Create `frontend/lib/features/service_catalog/presentation/widgets/new_branch_service_setup.dart` (select / copy-entire / copy-then-modify) and hook it into the branch-creation flow from `003-org-branch-management`

### Tests for User Story 7

- [ ] T067 [P] [US7] Add copy cases (`merge` leaves existing untouched, `replace` overwrites, audit payload with affected services) to `backend/tests/service_catalog_crud.sql`
- [ ] T068 [P] [US7] Add widget test for `copy_configuration_dialog` (replace confirmation + cancel makes no change) in `frontend/test/widget/service_catalog/`

**Checkpoint**: All seven stories independently functional

---

## Phase 10: Polish & Cross-Cutting Concerns

**Purpose**: Quality, verification, and constitution compliance across stories

- [ ] T069 [P] Run `dart analyze lib/features/service_catalog` (from `frontend/`) and resolve all findings
- [ ] T070 Run `bash backend/tests/run_service_catalog_tests.sh` and `flutter test test/unit/service_catalog test/widget/service_catalog`; fix failures
- [ ] T071 [P] Add unit tests for the new `services.view`/`services.manage` checks in `frontend/test/unit/` covering `permission_service.dart`
- [ ] T072 [P] Verify responsive collapse for narrow desktop windows and keyboard navigation/empty-loading-error-permission states across catalog list, editor, matrix, and selector (NFR-009)
- [ ] T073 Execute the `specs/015-service-catalog/quickstart.md` manual verification walkthrough (US1–US7 + new-branch FR-031)
- [ ] T074 [P] Cross-link the delivered feature in `docs/service_catalog_feature.md` and confirm `specs/015-service-catalog/` artifacts are consistent
- [ ] T075 Final constitution compliance review (backend authority, RLS defense-in-depth, audit coverage, no AI dependency, additive billing change)

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: no dependencies
- **Foundational (Phase 2)**: depends on Setup — **BLOCKS all user stories**
- **User Stories (Phases 3–9)**: all depend on Foundational; then proceed in priority order (P1 → P2 → P3) or in parallel where staffed
- **Polish (Phase 10)**: depends on all targeted stories

### User Story Dependencies

- **US1 (P1)**: after Foundational — no story dependencies (MVP anchor)
- **US2 (P1)**: after Foundational — reuses US1's catalog data and `get_service`; independently testable via seeded services
- **US3 (P2)**: after Foundational — builds on US1 assignments (branch config requires an assigned row)
- **US4 (P2)**: after US3 — promotions require branch config rows and the effective-price invariant
- **US5 (P2)**: after Foundational — edit/status/soft-delete of US1 services; independently testable
- **US6 (P2)**: after Foundational — browse of existing services; independently testable
- **US7 (P3)**: after US3/US4 — copies assignment/override/promotion between branches

### Shared-file ordering (not parallelizable within the same file)

- `20260712090500_service_catalog_rpcs.sql`: T012→T013 (US1) → T035 (US3) → T042 (US4) → T048→T049→T050 (US5) → T062→T063 (US7)
- `20260712091000_service_catalog_pricing_rpcs.sql`: T014 (US1) → T023→T024 (US2) → T056 (US6)
- `service_catalog_repository.dart`: T010 → T015 → T028 → T037 → T044 → T051 → T064
- `service_editor_notifier.dart`/`service_editor_page.dart`: T016/T018 → T039 → T052
- `branch_configuration_matrix.dart`: T038 → T045
- `service_catalog_crud.sql`: T020 → T053 → T067
- `service_catalog_concurrency.sql`: T040 → T054
- `service_catalog_pricing.sql`: T033 → T040 → T046

### Within Each User Story

- Backend RPC/schema before repository methods; repository before notifiers; notifiers before pages/widgets; core before integration
- `[P]` tests operate on distinct files and can run alongside implementation

---

## Parallel Example: User Story 1

```bash
# After the US1 backend RPCs (T012–T014) and repository (T015) land,
# these operate on distinct files and can run in parallel:
Task: "T020 create+assign CRUD cases in backend/tests/service_catalog_crud.sql"
Task: "T021 RLS denial cases in backend/tests/service_catalog_rls.sql"
Task: "T022 Dart unit tests in frontend/test/unit/service_catalog/"
```

## Parallel Example: Foundational

```bash
# Distinct files, no interdependencies:
Task: "T007 PermissionKeys additions in frontend/lib/features/auth/domain/permission_keys.dart"
Task: "T009 domain models service.dart + global_status.dart"
Task: "T010 repository skeleton service_catalog_repository.dart"
Task: "T011 rpc error-message mapping service_catalog_rpc_messages.dart"
```

---

## Implementation Strategy

### MVP First (User Stories 1 + 2)

1. Complete Phase 1 (Setup) and Phase 2 (Foundational)
2. Complete US1 (create/assign) → validate independently
3. Complete US2 (invoice selection + pricing + billing integration) → **STOP and VALIDATE**: a governed catalog with correctly-priced, snapshot-stable invoice selection is the MVP
4. Deploy/demo

### Incremental Delivery

1. Setup + Foundational → foundation ready
2. US1 → US2 → MVP demo (P1)
3. US3 → US4 → US5 → US6 (P2) — each independently testable and demoable
4. US7 + new-branch setup (P3) — convenience/scale accelerator
5. Polish

### Parallel Team Strategy

Once Foundational completes: US1 and US2 (P1) first (US2 leans on US1 data). Then a developer each can take US5 and US6 in parallel, while US3→US4 (and later US7) proceed on the branch-config track, respecting the shared-file ordering above.

---

## Notes

- `[P]` = different files, no dependency on incomplete tasks
- `[Story]` labels map tasks to spec.md user stories for traceability
- All catalog mutations go through `auth_internal` `SECURITY DEFINER` RPCs with `public` wrappers; RLS blocks direct DML (backend authority)
- Pricing/eligibility is server-authoritative and reused by preview + add-to-invoice (no duplicated client pricing logic)
- Money is `numeric(14,2)` in the DB and `Money` on the client; snapshots are immutable at add time
- Soft delete only; historical invoice items retain their snapshots
- Migration timestamps use the `20260712NNNNNN_*` prefix so they sort after `20260711210000_*`
