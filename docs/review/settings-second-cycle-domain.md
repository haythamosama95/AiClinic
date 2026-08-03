# Settings Feature — Second-Cycle Domain Layer Review

**Scope:** `frontend/lib/features/settings/domain/` (entities, inputs, filters, repository interfaces, use cases, `settings_use_case_providers.dart`), related domain tests under `frontend/test/**/settings/**`, and cross-feature imports from `appointments`, `setup`, and `shifts` into settings domain.

**Review date:** 2026-07-05  
**Prior review:** [flutter-settings-feature-code-review.md](./flutter-settings-feature-code-review.md)  
**Method:** Read every file in scope; re-verify first-cycle domain findings; challenge assumptions with code evidence.

---

## Executive Summary

The settings **domain model layer is structurally readable** (immutable entities, clear repository interfaces, framework-free use-case classes), but it **does not function as a true domain layer** in Clean Architecture terms:

1. **Composition root lives inside domain** — `settings_use_case_providers.dart` imports Riverpod and all four data-layer repository providers (H1, still unfixed).
2. **Business rules are absent from use cases** — all 15 use cases are one-line delegations; validation lives exclusively in data repositories (H6, still unfixed).
3. **Settings domain is an undeclared shared kernel** — 20+ non-settings files import settings domain types or DI wiring, with no published contract boundary (H3, still unfixed; shifts claim was overstated).

No **Critical** domain-layer defects were found (first-cycle Critical items are presentation/data/SQL). Domain issues are architectural and consistency gaps that will compound as settings UI ships and more features consume these types.

| Severity | Count | New this cycle | Re-verified from cycle 1 |
|----------|-------|----------------|--------------------------|
| **Critical** | 0 | 0 | 0 |
| **High** | 4 | 0 | 4 |
| **Medium** | 12 | 5 | 7 |

### Top 3 Findings

1. **H1 — Domain imports data layer + Riverpod** (`settings_use_case_providers.dart`): DIP inversion unchanged; domain cannot be tested or reused without Supabase-backed impls.
2. **H3 — Undeclared shared kernel**: `BranchWorkingSchedule` and `StaffListItem` are imported by 6 appointments domain files, 3 setup files, 3 appointment providers, plus patients/app dev-seed — any schema or field change is a cross-feature breaking change.
3. **H6 — Anemic use cases with validation trapped in data layer**: e.g. `CreateBranch`/`UpdateStaffMember` delegate with zero invariant checks; `hasConfiguredWorkingHours` enforced in setup wizard but not in settings branch mutations (M19).

---

## First-Cycle Domain Findings — Re-Verification Status

| ID | Finding (domain scope) | Status |
|----|------------------------|--------|
| H1 | Domain use-case providers import data layer | **CONFIRMED STILL PRESENT** |
| H3 | Settings domain as undeclared shared kernel | **CONFIRMED STILL PRESENT** (shifts: **INVALID/NUANCED** — no direct `settings/domain` imports found; coupling is indirect via appointments/staff types) |
| H6 | Business validation in data repos, not domain/use cases | **CONFIRMED STILL PRESENT** |
| H9 | `RpcResult` leaks into domain repository interfaces | **CONFIRMED STILL PRESENT** (also propagates through 4 mutation use cases) |
| M1 | `fromRow` DB mapping in domain entities | **CONFIRMED STILL PRESENT** |
| M3 | Repository scoping inconsistency (`listBranches` requires orgId; `listStaff` does not) | **CONFIRMED STILL PRESENT** (visible at domain interface level) |
| M5 | Cross-feature imports of `settings_use_case_providers.dart` | **CONFIRMED STILL PRESENT** (3 appointment providers) |
| M7 | `StaffListQuery` is dead code | **CONFIRMED STILL PRESENT** (only referenced by its own unit test) |
| M17 | `_parseIsActive` / truthy parsing drift in `BranchWorkingDayHours.fromJson` | **CONFIRMED STILL PRESENT** (no test covers `'t'`/`'1'` forms) |
| M18 | `BranchListItem.normalizeCode` unused on write path | **CONFIRMED STILL PRESENT** |
| M19 | `hasConfiguredWorkingHours` not enforced in branch CRUD use cases | **CONFIRMED STILL PRESENT** |
| M20 | No cross-field validation: `primaryBranchId` ∈ `branchIds` | **CONFIRMED STILL PRESENT** |
| M21 | `FetchPermissionMatrix` returns raw rows; view assembly in presentation | **CONFIRMED STILL PRESENT** |
| M22 | Inconsistent local-validation exception types | **CONFIRMED STILL PRESENT** (singular permission update throws `StateError` in data layer; domain interface exposes no contract for validation failures) |
| H2 | settings ↔ app idle-timeout cycle | **INVALID/NUANCED for domain scope** — cycle is app/application/data; `IdleTimeoutConfig` in domain is appropriate |
| H7 | `updateBranch` silently clears `code` | **INVALID/NUANCED for domain scope** — input/repo/SQL contract issue; `UpdateBranchInput` itself is fine but offers no guard |

---

## Critical Issues

*None in domain scope.*

First-cycle Critical items (C1 notifier race, C2 save revert, C3 batch RPC atomicity) live in presentation, data, or SQL — outside this review's domain boundary.

---

## High Priority Issues

### H1. Domain layer imports data layer and Riverpod (DIP inversion)

**First-cycle status:** CONFIRMED STILL PRESENT

- **Severity:** High
- **Files involved:**
  - `frontend/lib/features/settings/domain/usecases/settings_use_case_providers.dart`
  - `frontend/lib/features/settings/data/{branch,organization,role_permissions,staff_admin}_repository.dart` (imported targets)

- **Evidence:**

```1:6:frontend/lib/features/settings/domain/usecases/settings_use_case_providers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/features/settings/data/branch_repository.dart';
import 'package:ai_clinic/features/settings/data/organization_repository.dart';
import 'package:ai_clinic/features/settings/data/role_permissions_repository.dart';
import 'package:ai_clinic/features/settings/data/staff_admin_repository.dart';
```

```23:27:frontend/lib/features/settings/domain/usecases/settings_use_case_providers.dart
final listBranchesUseCaseProvider = Provider((ref) => ListBranches(ref.watch(branchRepositoryProvider)));
final createBranchUseCaseProvider = Provider((ref) => CreateBranch(ref.watch(branchRepositoryProvider)));
final updateBranchUseCaseProvider = Provider((ref) => UpdateBranch(ref.watch(branchRepositoryProvider)));
final setBranchActiveUseCaseProvider = Provider((ref) => SetBranchActive(ref.watch(branchRepositoryProvider)));
final deleteBranchUseCaseProvider = Provider((ref) => DeleteBranch(ref.watch(branchRepositoryProvider)));
```

- **Why it is a problem:** Clean Architecture requires dependencies to point inward. A file under `domain/` that imports `data/` and `flutter_riverpod` makes the domain layer depend on infrastructure and a DI framework. Any feature importing `settings_use_case_providers.dart` (appointments) transitively depends on settings data implementations.
- **Potential impact:** Domain use cases cannot be unit-tested without Riverpod + Supabase repo providers; refactoring settings data breaks cross-feature consumers; violates NFR-007 layering intent from the service-catalog spec pattern.
- **Recommended solution:** Move `settings_use_case_providers.dart` to `application/` (or a dedicated `di/` module outside domain). Domain retains entities, repository interfaces, and pure use-case classes only.

---

### H3. Settings domain acting as undeclared shared kernel

**First-cycle status:** CONFIRMED STILL PRESENT (shifts direct import: INVALID/NUANCED)

- **Severity:** High
- **Files involved (consumers, non-exhaustive):**
  - **Appointments domain (6):** `appointment_working_hours.dart`, `appointment_settings.dart`, `appointment_reschedule_validation.dart`, `appointment_branch_working_hours.dart`, `appointment_calendar_display.dart`, `appointment_queue_shift_doctors.dart`
  - **Appointments presentation (3):** `appointment_calendar_provider.dart`, `appointment_queue_provider.dart`, `appointment_queue_shift_provider.dart`
  - **Setup (3):** `bootstrap_branch_input.dart`, `setup_step_readiness.dart`, `setup_notifier.dart`
  - **Patients (1):** `patient_dev_seed_service.dart`
  - **App dev seed (1):** `dev_clinic_seed_service.dart`
  - **Settings domain exports:** `branch_working_schedule.dart`, `staff_list_item.dart`, `staff_list_filter.dart`, `branch_list_item.dart`, `branch_list_filter.dart`, repository interfaces, mutation inputs

- **Evidence (appointments domain example):**

```1:1:frontend/lib/features/appointments/domain/appointment_working_hours.dart
import 'package:ai_clinic/features/settings/domain/branch_working_schedule.dart';
```

```12:16:frontend/lib/features/appointments/presentation/providers/appointment_calendar_provider.dart
import 'package:ai_clinic/features/settings/domain/branch_list_filter.dart';
import 'package:ai_clinic/features/settings/domain/branch_list_item.dart';
import 'package:ai_clinic/features/settings/domain/staff_list_filter.dart';
import 'package:ai_clinic/features/settings/domain/staff_list_item.dart';
import 'package:ai_clinic/features/settings/domain/usecases/settings_use_case_providers.dart';
```

```3:3:frontend/lib/features/setup/domain/setup_step_readiness.dart
import 'package:ai_clinic/features/settings/domain/branch_working_schedule.dart';
```

- **Why it is a problem:** Scheduling primitives (`BranchWorkingSchedule`) and staff list types (`StaffListItem`, filters) are owned by settings but consumed as if they were platform-wide. There is no published "settings read API" — features deep-import internal domain paths and DI wiring.
- **Potential impact:** Renaming a field, changing `fromRow` parsing, or moving validation breaks appointments, setup, and dev-seed tooling silently. Ownership of breaking changes is unclear.
- **Recommended solution:** Promote shared types (`BranchWorkingSchedule`, `StaffRole`-adjacent staff types) to `core/` or `shared/domain/`. Expose cross-feature reads through a narrow published provider surface (e.g. `app/providers/repository_providers.dart` barrel), not `domain/usecases/settings_use_case_providers.dart`.

---

### H6. Anemic use cases; business validation lives in data layer

**First-cycle status:** CONFIRMED STILL PRESENT

- **Severity:** High
- **Files involved:**
  - All 15 use cases under `frontend/lib/features/settings/domain/usecases/*.dart` (except providers file)
  - `frontend/lib/features/settings/data/{branch,organization,staff_admin,role_permissions}_repository.dart`

- **Evidence (use case — pure pass-through):**

```4:10:frontend/lib/features/settings/domain/usecases/create_branch.dart
class CreateBranch {
  const CreateBranch(this._repository);
  final BranchRepository _repository;

  Future<String> call(CreateBranchInput input) {
    return _repository.createBranch(input);
  }
}
```

```4:10:frontend/lib/features/settings/domain/usecases/update_staff_member.dart
class UpdateStaffMember {
  const UpdateStaffMember(this._repository);
  final StaffAdminRepository _repository;

  Future<String> call(UpdateStaffMemberInput input) {
    return _repository.updateStaffMember(input);
  }
}
```

- **Evidence (validation only in data layer):**

```54:60:frontend/lib/features/settings/data/branch_repository.dart
  Future<String> createBranch(CreateBranchInput input) async {
    final name = input.name.trim();
    if (name.isEmpty) {
      throw RpcFailure(
        const RpcResult(success: false, errorCode: 'INVALID_INPUT', errorMessage: 'Branch name is required.'),
      );
    }
```

```167:182:frontend/lib/features/settings/data/staff_admin_repository.dart
  Future<String> updateStaffMember(UpdateStaffMemberInput input) async {
    final fullName = input.fullName.trim();
    if (fullName.isEmpty) {
      throw RpcFailure(
        const RpcResult(success: false, errorCode: 'INVALID_INPUT', errorMessage: 'Full name is required.'),
      );
    }
    if (input.branchIds.isEmpty) {
      throw RpcFailure(
        const RpcResult(
          success: false,
          errorCode: 'INVALID_INPUT',
          errorMessage: 'At least one branch assignment is required.',
        ),
      );
    }
```

- **Why it is a problem:** Domain invariants (required fields, schedule validity, branch assignment rules) are coupled to Supabase repository implementations. Alternate repository implementations (fakes, offline cache, migration adapters) would skip validation. Use cases provide no single place to enforce rules before I/O.
- **Potential impact:** Rules cannot be tested at domain layer; error semantics tied to `RpcFailure` infrastructure type; setup wizard and settings CRUD enforce different rules for the same entities (see M-NEW-2, M19).
- **Recommended solution:** Add validation methods on input types (`CreateBranchInput.validate()`, etc.) or enforce in use-case `call()` before delegating. Keep repositories as pure I/O adapters.

---

### H9. `RpcResult` infrastructure type leaks through domain repository interfaces and use cases

**First-cycle status:** CONFIRMED STILL PRESENT

- **Severity:** High
- **Files involved:**
  - `frontend/lib/features/settings/domain/repositories/branch_repository.dart`
  - `frontend/lib/features/settings/domain/repositories/staff_admin_repository.dart`
  - `frontend/lib/features/settings/domain/usecases/{set_branch_active,delete_branch,set_staff_active,delete_staff_member}.dart`

- **Evidence (repository interface):**

```15:16:frontend/lib/features/settings/domain/repositories/branch_repository.dart
  Future<RpcResult> setBranchActive({required String branchId, required bool isActive});
  Future<RpcResult> deleteBranch({required String branchId});
```

```12:13:frontend/lib/features/settings/domain/repositories/staff_admin_repository.dart
  Future<RpcResult> setStaffActive({required String staffMemberId, required bool isActive});
  Future<RpcResult> deleteStaffMember({required String staffMemberId});
```

- **Evidence (use case propagates infra type):**

```8:12:frontend/lib/features/settings/domain/usecases/set_branch_active.dart
  Future<RpcResult> call({required String branchId, required bool isActive}) {
    return _repository.setBranchActive(
      branchId: branchId,
      isActive: isActive,
    );
  }
```

- **Why it is a problem:** `RpcResult`/`RpcFailure` are transport-layer concerns from `core/rpc/`. Domain should express success/failure with domain-meaningful types (`void`, sealed failure classes). Callers receive a result envelope whose `.success` field is never checked at the domain boundary — failures are thrown as `RpcFailure` instead.
- **Potential impact:** Domain layer is coupled to RPC wire format; mutation use cases expose ambiguous contracts (return value vs thrown exception).
- **Recommended solution:** Repository interfaces return `Future<void>`; map `RpcFailure` to a domain `SettingsMutationFailure` at the data boundary. Use cases mirror the simplified contract.

---

## Medium Priority Issues

### M1. DB-row mapping (`fromRow`) lives in domain entities

**First-cycle status:** CONFIRMED STILL PRESENT

- **Severity:** Medium
- **Files involved:** `organization_profile.dart`, `branch_list_item.dart`, `staff_list_item.dart`, `staff_member_detail.dart`, `permission_matrix_row.dart` (via `BranchWorkingSchedule.fromJson` in `branch_list_item.dart`)

- **Evidence:**

```28:49:frontend/lib/features/settings/domain/branch_list_item.dart
  static BranchListItem? fromRow(Map<String, dynamic> row) {
    final id = row['id']?.toString();
    final name = row['name']?.toString().trim();
    if (id == null || id.isEmpty || name == null || name.isEmpty) {
      return null;
    }
    // ...
    return BranchListItem(
      id: id,
      name: name,
      isActive: _parseIsActive(row['is_active']),
      code: optionalString(row['code']),
      // ...
      workingSchedule: BranchWorkingSchedule.fromJson(row['working_schedule']),
    );
  }
```

- **Why it is a problem:** Snake_case column names and Supabase JSON shapes are persistence concerns. Domain entities should be persistence-ignorant value objects constructed from already-mapped data.
- **Potential impact:** Schema/column renames require domain edits; encourages other layers to call `fromRow` directly (data repos do).
- **Recommended solution:** Introduce data-layer DTOs/mappers (`BranchListItemDto.fromRow` → `toDomain()`). Keep domain entities constructor-only.

---

### M3. Repository scoping inconsistency at domain interface level

**First-cycle status:** CONFIRMED STILL PRESENT

- **Severity:** Medium
- **Files involved:**
  - `frontend/lib/features/settings/domain/repositories/branch_repository.dart`
  - `frontend/lib/features/settings/domain/repositories/staff_admin_repository.dart`
  - Corresponding use cases `list_branches.dart`, `list_staff.dart`

- **Evidence:**

```9:12:frontend/lib/features/settings/domain/repositories/branch_repository.dart
  Future<List<BranchListItem>> listBranches({
    required String organizationId,
    BranchListFilter filter = BranchListFilter.all,
  });
```

```9:9:frontend/lib/features/settings/domain/repositories/staff_admin_repository.dart
  Future<List<StaffListItem>> listStaff({StaffListFilter filter = StaffListFilter.all});
```

- **Why it is a problem:** Sibling repositories express tenancy differently — branches require explicit `organizationId`; staff relies implicitly on RLS/session. Domain interfaces should encode the same scoping contract.
- **Potential impact:** Callers of `ListStaff` cannot validate org scope client-side; latent risk if RLS coverage diverges between tables.
- **Recommended solution:** Add `organizationId` (or a shared `TenantScope`) to `StaffAdminRepository.listStaff` and `ListStaff.call`, matching `ListBranches`.

---

### M5. Cross-feature reach into settings internal DI wiring

**First-cycle status:** CONFIRMED STILL PRESENT

- **Severity:** Medium
- **Files involved:**
  - `frontend/lib/features/appointments/presentation/providers/appointment_calendar_provider.dart`
  - `frontend/lib/features/appointments/presentation/providers/appointment_queue_provider.dart`
  - `frontend/lib/features/appointments/presentation/providers/appointment_queue_shift_provider.dart`
  - `frontend/lib/features/settings/domain/usecases/settings_use_case_providers.dart`

- **Evidence:**

```16:16:frontend/lib/features/appointments/presentation/providers/appointment_calendar_provider.dart
import 'package:ai_clinic/features/settings/domain/usecases/settings_use_case_providers.dart';
```

- **Why it is a problem:** Appointments depends on settings' internal composition root, which (via H1) transitively binds to settings data providers. This is not a published cross-feature contract.
- **Potential impact:** Moving or renaming providers breaks appointments; couples feature lifecycles.
- **Recommended solution:** Re-export required read providers from `app/providers/repository_providers.dart` or a dedicated `settings_public_providers.dart` in application layer.

---

### M7. `StaffListQuery` is dead domain code

**First-cycle status:** CONFIRMED STILL PRESENT

- **Severity:** Medium
- **Files involved:** `frontend/lib/features/settings/domain/staff_list_query.dart`, `frontend/test/unit/settings/staff_list_query_test.dart`

- **Evidence:** Grep shows `StaffListQuery` is referenced only in its definition file and its dedicated test — no notifier, provider, or presentation import.

- **Why it is a problem:** Domain exposes client-side search/filter logic that nothing consumes. Maintainers may assume list UI uses it; it does not (`StaffListNotifier` always fetches `StaffListFilter.all`).
- **Potential impact:** Wasted maintenance surface; misleading API for future settings UI work.
- **Recommended solution:** Wire into staff list notifier/UI, or remove until needed.

---

### M17. Truthy parsing inconsistency — `BranchWorkingDayHours.fromJson` vs entity `fromRow` helpers

**First-cycle status:** CONFIRMED STILL PRESENT

- **Severity:** Medium
- **Files involved:** `frontend/lib/features/settings/domain/branch_working_schedule.dart`, `branch_list_item.dart`, `staff_list_item.dart`, `staff_member_detail.dart`, `permission_matrix_row.dart`

- **Evidence (strict parsing in schedule JSON path):**

```60:63:frontend/lib/features/settings/domain/branch_working_schedule.dart
    final workingRaw = json['is_working_day'];
    final isWorkingDay = workingRaw is bool
        ? workingRaw
        : (workingRaw?.toString().toLowerCase() == 'true' || workingRaw == 1);
```

- **Evidence (permissive parsing elsewhere):**

```52:57:frontend/lib/features/settings/domain/branch_list_item.dart
  static bool _parseIsActive(Object? value) {
    if (value is bool) {
      return value;
    }
    final text = value?.toString().trim().toLowerCase();
    return text == 'true' || text == 't' || text == '1';
  }
```

- **Why it is a problem:** PostgreSQL/Supabase may emit `'t'`/`'f'` for booleans in JSON contexts. Working-day flags inside `working_schedule` JSON silently parse as `false` when other entity fields accept `'t'`/`'1'`.
- **Potential impact:** Branch working hours appear closed when wire format differs; appointment scheduling logic consuming `BranchWorkingSchedule` gets wrong hours.
- **Recommended solution:** Extract shared `WireParse.truthy()` in `core/utils/`; use everywhere including `BranchWorkingDayHours.fromJson`. Add tests for `'t'` and `'1'` string forms.

---

### M18. `BranchListItem.normalizeCode` documented but unused on mutation path

**First-cycle status:** CONFIRMED STILL PRESENT

- **Severity:** Medium
- **Files involved:** `frontend/lib/features/settings/domain/branch_list_item.dart`, `frontend/lib/features/settings/data/branch_repository.dart`

- **Evidence:**

```60:67:frontend/lib/features/settings/domain/branch_list_item.dart
  /// Branch code normalized for uniqueness checks (lowercase, trimmed).
  static String? normalizeCode(String? input) {
    final trimmed = input?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return trimmed.toLowerCase();
  }
```

```62:68:frontend/lib/features/settings/data/branch_repository.dart
    final result = await invokeSettingsRpc('manage_create_branch', {
      'p_name': name,
      'p_working_schedule': input.workingSchedule.toJson(),
      if (input.code != null) 'p_code': input.code!.trim(),
```

- **Why it is a problem:** Domain documents normalization for uniqueness checks, but create/update repos send raw trimmed code — no use case or input validation calls `normalizeCode`.
- **Potential impact:** Client-side duplicate detection (once UI exists) will disagree with server normalization rules.
- **Recommended solution:** Apply `normalizeCode` in `CreateBranchInput`/`UpdateBranchInput` validation or use-case `call()` before RPC; or remove if server-only.

---

### M19. `hasConfiguredWorkingHours` enforced in setup but not settings branch CRUD

**First-cycle status:** CONFIRMED STILL PRESENT

- **Severity:** Medium
- **Files involved:**
  - `frontend/lib/features/settings/domain/branch_working_schedule.dart`
  - `frontend/lib/features/settings/domain/usecases/{create_branch,update_branch}.dart`
  - `frontend/lib/features/setup/domain/setup_step_readiness.dart`

- **Evidence (invariant exists on entity):**

```123:124:frontend/lib/features/settings/domain/branch_working_schedule.dart
  /// True when at least one day is open with valid HH:mm open/close times.
  bool get hasConfiguredWorkingHours => days.any(isValidWorkingDay);
```

- **Evidence (setup enforces; settings use cases do not):**

```57:59:frontend/lib/features/setup/domain/setup_step_readiness.dart
  if (!workingSchedule.hasConfiguredWorkingHours) {
    return false;
  }
```

```8:10:frontend/lib/features/settings/domain/usecases/create_branch.dart
  Future<String> call(CreateBranchInput input) {
    return _repository.createBranch(input);
  }
```

- **Why it is a problem:** The same `BranchWorkingSchedule` type gates setup wizard progression but can be submitted through `CreateBranch`/`UpdateBranch` with an empty or all-closed schedule (use case passes through; repo only checks name).
- **Potential impact:** Settings branch management will hit server-side rejection with worse UX than setup once UI ships; inconsistent product behavior.
- **Recommended solution:** Validate `input.workingSchedule.hasConfiguredWorkingHours` in `CreateBranch.call()` and `UpdateBranch.call()` before repository delegation.

---

### M20. No cross-field validation: `primaryBranchId` vs `branchIds`

**First-cycle status:** CONFIRMED STILL PRESENT

- **Severity:** Medium
- **Files involved:** `frontend/lib/features/settings/domain/update_staff_member_input.dart`, `frontend/lib/features/settings/domain/usecases/update_staff_member.dart`, `frontend/lib/features/settings/data/staff_admin_repository.dart`

- **Evidence (input allows inconsistent combinations; no validator):**

```4:22:frontend/lib/features/settings/domain/update_staff_member_input.dart
class UpdateStaffMemberInput {
  const UpdateStaffMemberInput({
    required this.staffMemberId,
    required this.fullName,
    required this.role,
    required this.branchIds,
    this.phone,
    this.primaryBranchId,
    this.isActive,
  });
  // ...
  final List<String> branchIds;
  final String? primaryBranchId;
}
```

```8:10:frontend/lib/features/settings/domain/usecases/update_staff_member.dart
  Future<String> call(UpdateStaffMemberInput input) {
    return _repository.updateStaffMember(input);
  }
```

- **Why it is a problem:** Nothing verifies that a non-null `primaryBranchId` is contained in `branchIds`. Invalid combinations reach the RPC.
- **Potential impact:** Server error with opaque message; or silent primary-branch misassignment depending on SQL behavior.
- **Recommended solution:** Add `UpdateStaffMemberInput.validate()` asserting `primaryBranchId == null || branchIds.contains(primaryBranchId)`; call from use case before repo.

---

### M21. `FetchPermissionMatrix` returns raw rows; view assembly duplicated in presentation

**First-cycle status:** CONFIRMED STILL PRESENT

- **Severity:** Medium
- **Files involved:** `frontend/lib/features/settings/domain/usecases/fetch_permission_matrix.dart`, `frontend/lib/features/settings/domain/permission_matrix_view.dart`, `frontend/lib/features/settings/presentation/providers/role_permissions_notifier.dart`

- **Evidence:**

```4:9:frontend/lib/features/settings/domain/usecases/fetch_permission_matrix.dart
class FetchPermissionMatrix {
  const FetchPermissionMatrix(this._repository);
  final RolePermissionsRepository _repository;

  Future<List<PermissionMatrixRow>> call() => _repository.fetchMatrix();
}
```

- **Why it is a problem:** `PermissionMatrixView.fromRows` is domain view logic, but the use case stops at raw rows — presentation must know to assemble the view (duplicated 3× per first-cycle review).
- **Potential impact:** Future consumers may handle rows inconsistently; domain view type underused.
- **Recommended solution:** Change `FetchPermissionMatrix.call()` to return `PermissionMatrixView` directly.

---

### M-NEW-1. Settings domain tightly coupled to auth feature via `StaffRole`

**First-cycle status:** NEW (related to H3; not explicitly called out)

- **Severity:** Medium
- **Files involved (8 domain files import auth):**
  - `staff_list_item.dart`, `staff_member_detail.dart`, `staff_list_query.dart`, `update_staff_member_input.dart`
  - `permission_matrix_row.dart`, `permission_matrix_view.dart`
  - `repositories/role_permissions_repository.dart`
  - `usecases/update_role_permission.dart`

- **Evidence:**

```1:2:frontend/lib/features/settings/domain/staff_list_item.dart
import 'package:ai_clinic/core/utils/copy_with_sentinel.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
```

```1:2:frontend/lib/features/settings/domain/repositories/role_permissions_repository.dart
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/settings/domain/permission_matrix_row.dart';
```

- **Why it is a problem:** Settings domain depends on another feature's domain module for the `StaffRole` enum. This is feature-to-feature coupling at the innermost layer — worse than presentation importing settings.
- **Potential impact:** Auth refactors (role additions, wire value changes) force settings domain edits; settings domain tests must import auth types.
- **Recommended solution:** Move `StaffRole` to `core/auth/` or `shared/domain/` as a platform type both features depend on downward.

---

### M-NEW-2. Branch field validation rules exist in setup but absent from settings domain inputs/use cases

**First-cycle status:** NEW

- **Severity:** Medium
- **Files involved:**
  - `frontend/lib/features/settings/domain/create_branch_input.dart`, `update_branch_input.dart`
  - `frontend/lib/features/settings/domain/usecases/{create_branch,update_branch}.dart`
  - `frontend/lib/features/setup/domain/branch_field_validation.dart`, `setup_step_readiness.dart`

- **Evidence (setup validates phone, maps URL, required code):**

```30:41:frontend/lib/features/setup/domain/setup_step_readiness.dart
  if (code.trim().isEmpty) {
    return false;
  }
  if (address.trim().isEmpty) {
    return false;
  }
  if (!BranchFieldValidation.isValidPhone(phone)) {
    return false;
  }
  if (!BranchFieldValidation.isValidMapsUrl(mapsUrl)) {
    return false;
  }
```

- **Evidence (settings inputs — all optional except name/schedule; no validation helpers):**

```4:19:frontend/lib/features/settings/domain/create_branch_input.dart
class CreateBranchInput {
  const CreateBranchInput({
    required this.name,
    required this.workingSchedule,
    this.code,
    this.address,
    this.phone,
    this.mapsUrl,
  });
```

- **Why it is a problem:** Setup wizard and steady-state settings branch CRUD share domain schedule types but enforce different field rules. Settings repos only validate non-empty `name`.
- **Potential impact:** Settings UI can submit branches that setup would block; inconsistent data quality; duplicated validation logic stays in setup-only module.
- **Recommended solution:** Move `BranchFieldValidation` to shared domain (or settings domain); add input validation on `CreateBranchInput`/`UpdateBranchInput`; enforce in use cases.

---

### M-NEW-3. Batch permission update lacks empty-key validation present on singular path

**First-cycle status:** NEW

- **Severity:** Medium
- **Files involved:**
  - `frontend/lib/features/settings/domain/usecases/update_role_permissions.dart`
  - `frontend/lib/features/settings/data/role_permissions_repository.dart`

- **Evidence (singular validates; batch does not):**

```45:48:frontend/lib/features/settings/data/role_permissions_repository.dart
    final key = permissionKey.trim();
    if (key.isEmpty) {
      throw StateError('Permission key is required.');
    }
```

```58:68:frontend/lib/features/settings/data/role_permissions_repository.dart
  Future<void> updateRolePermissions(Iterable<PermissionMatrixChange> changes) async {
    final payload = [
      for (final change in changes)
        {'role': change.role.wireValue, 'permission_key': change.permissionKey.trim(), 'is_granted': change.isGranted},
    ];
    // ... no per-key empty check ...
    await invokeSettingsRpc('update_role_permissions', {'p_changes': payload});
  }
```

- **Why it is a problem:** Domain use case `UpdateRolePermissions` passes changes through with no validation. Empty keys after trim can reach RPC in batch saves (production path via notifier) but would fail on singular path with `StateError`.
- **Potential impact:** Inconsistent error types (M22); possible server-side rejection mid-batch (related to C3 atomicity, outside domain).
- **Recommended solution:** Validate all changes in `UpdateRolePermissions.call()` or a domain value type; reject empty keys before repository call with consistent domain exception.

---

### M-NEW-4. Domain entities import Flutter framework (`foundation.dart`)

**First-cycle status:** NEW

- **Severity:** Medium
- **Files involved:** `branch_working_schedule.dart`, `branch_list_item.dart`, `staff_list_item.dart`, `staff_member_detail.dart`, `organization_profile.dart`, `permission_matrix_row.dart`, `permission_matrix_view.dart`; plus `settings_use_case_providers.dart` imports `flutter_riverpod`

- **Evidence:**

```1:1:frontend/lib/features/settings/domain/branch_working_schedule.dart
import 'package:flutter/foundation.dart';
```

- **Why it is a problem:** NFR-007 (service-catalog spec pattern used project-wide) expects domain models with no framework/SDK imports. `@immutable` and `listEquals`/`mapEquals` tie pure domain to Flutter.
- **Potential impact:** Domain cannot be reused in non-Flutter contexts; test/analysis coupling to Flutter SDK for entity-only tests.
- **Recommended solution:** Use `meta` `@immutable` or plain Dart classes; replace `listEquals`/`mapEquals` with collection package or manual equality (already hand-rolled in several places).

---

### M-NEW-5. Zero unit tests for domain use cases; validation only tested at repository layer

**First-cycle status:** NEW (first cycle listed as test gap; confirmed no use-case tests exist)

- **Severity:** Medium
- **Files involved:** All files under `frontend/lib/features/settings/domain/usecases/`; tests under `frontend/test/unit/settings/` (entity/repo/notifier only)

- **Evidence:** Grep for `usecases|UseCase` under `frontend/test/**/settings/**` returns no matches. Validation tests like empty branch name exist only in `branch_repository_test.dart` and boundary tests against `BranchRepositoryImpl`.

- **Why it is a problem:** Once validation moves to domain (H6 recommendation), there is no test harness. Currently confirms validation is not considered domain responsibility.
- **Potential impact:** Regressions in business rules go undetected until integration/boundary tests; use-case refactors untested.
- **Recommended solution:** Add `frontend/test/unit/settings/usecases/` with fake repositories testing validation orchestration in use-case `call()` methods.

---

## Cross-Feature Import Inventory (into settings domain)

| Source feature | Files importing settings domain | Primary symbols |
|----------------|--------------------------------|-----------------|
| **appointments** | 9 (6 domain + 3 presentation) | `BranchWorkingSchedule`, `StaffListItem`, filters, `settings_use_case_providers` |
| **setup** | 3 | `BranchWorkingSchedule` |
| **patients** | 1 | Repository interfaces, `CreateBranchInput`, `UpdateStaffMemberInput` |
| **app (dev seed)** | 1 | Repository interfaces, mutation inputs |
| **shifts** | 0 direct | **First-cycle "via shifts" claim not supported** — no direct imports |

---

## Domain Test Coverage Notes

**Existing positive coverage (entities/domain logic):**
- `branch_working_schedule_test.dart` — schedule invariants (partial; no `fromJson` truthy forms)
- `branch_list_item_test.dart` — `fromRow`, `normalizeCode`, equality
- `staff_list_item_test.dart`, `staff_member_detail_test.dart`, `organization_profile_test.dart`
- `permission_matrix_view_test.dart`, `permission_matrix_row_test.dart`
- `staff_list_query_test.dart` — tests dead code in isolation

**Gaps confirmed:**
- No use-case tests (M-NEW-5)
- No test for M17 `'t'`/`'1'` in `BranchWorkingDayHours.fromJson`
- No test for M20 `primaryBranchId`/`branchIds` consistency
- No test that M19 `hasConfiguredWorkingHours` is enforced on branch mutations (because it is not enforced)

---

## Recommended Refactoring Priority (Domain Layer)

1. **Move `settings_use_case_providers.dart` out of domain** (H1) — unblocks clean dependency direction.
2. **Promote shared types** (`BranchWorkingSchedule`, staff list types, `StaffRole`) to neutral module (H3, M-NEW-1).
3. **Add validation to inputs/use cases** — branch schedule (M19), staff primary branch (M20), branch fields (M-NEW-2), permission batch keys (M-NEW-3); remove from data repos gradually (H6).
4. **Clean domain boundaries** — `RpcResult` out of interfaces (H9); `fromRow` to data mappers (M1); return `PermissionMatrixView` from fetch use case (M21).
5. **Consolidate parsing** (M17) and **add use-case test suite** (M-NEW-5).

---

*Second-cycle domain review complete. All 35 domain-layer source files read. Cross-feature imports verified via ripgrep across `frontend/lib/features`.*
