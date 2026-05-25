# Frontend Clean Architecture Migration Plan

**Purpose**: Migrate from simplified feature-first architecture to full Flutter clean architecture with abstract repository interfaces, use cases, and proper layer separation.

**Target folder structure per feature**:

```
features/{name}/
  domain/
    {existing entity/model files — stay in place}
    repositories/          # NEW: abstract interfaces
    usecases/              # NEW: one class per operation
  data/
    repositories/          # MOVED: concrete implementations (renamed *Impl)
    {other data-layer files stay in place}
  presentation/
    providers/             # UPDATED: inject use cases instead of repos
    pages/
    widgets/
```

**Naming conventions**:
- Abstract interface: `AuthRepository` (in `domain/repositories/auth_repository.dart`)
- Concrete class: `AuthRepositoryImpl` (in `data/repositories/auth_repository_impl.dart`)
- Use case: `SignIn` (in `domain/usecases/sign_in.dart`)
- Riverpod provider for interface: `authRepositoryProvider` returns `AuthRepository` (the interface)
- Riverpod provider for use case: `signInUseCaseProvider`

**Rules for the implementing model**:
1. Do ONE phase at a time. Run `dart analyze` after each phase to catch import errors.
2. Never break existing behavior — this is a structural refactor only.
3. Every use case class has a single public `call()` method.
4. Every abstract repository method signature must EXACTLY match the current concrete method.
5. Keep barrel exports updated as files move.
6. The `SettingsRpcInvoker` mixin stays in `data/` — it is an implementation detail.
7. Input/output types that are currently co-located with repositories move to `domain/`.
8. The Riverpod provider for each repository moves to the concrete impl file and returns the abstract type.

---

## Phase 1: Extract Input/Output Types from Repository Files to Domain

**Goal**: Move all DTO/input/output classes from `data/*.dart` files into `domain/` so they become domain-layer concepts that both the use case layer and data layer can reference without circular imports.

### Task 1.1 — Patients: extract types from `patient_repository.dart`

**Create** `features/patients/domain/patient_search_page.dart`:
```dart
import 'package:ai_clinic/features/patients/domain/patient_list_item.dart';

/// Paginated patient list/search result from `search_patients`.
class PatientSearchPage {
  // Copy the ENTIRE PatientSearchPage class (constructor, fields, factory, _readInt)
  // from patient_repository.dart lines 15–55, exactly as-is.
}
```

**Create** `features/patients/domain/create_patient_input.dart`:
```dart
import 'package:ai_clinic/features/patients/domain/patient_gender.dart';
import 'package:ai_clinic/features/patients/domain/patient_marital_status.dart';

/// Input for patient creation.
class CreatePatientInput {
  // Copy the ENTIRE CreatePatientInput class from patient_repository.dart lines 58–78, exactly as-is.
}
```

**Create** `features/patients/domain/update_patient_input.dart`:
```dart
import 'package:ai_clinic/features/patients/domain/patient_gender.dart';
import 'package:ai_clinic/features/patients/domain/patient_marital_status.dart';

/// Input for patient update.
class UpdatePatientInput {
  // Copy the ENTIRE UpdatePatientInput class from patient_repository.dart lines 81–103, exactly as-is.
}
```

**Modify** `features/patients/data/patient_repository.dart`:
- Remove `PatientSearchPage`, `CreatePatientInput`, `UpdatePatientInput` class definitions.
- Add imports:
  ```dart
  import 'package:ai_clinic/features/patients/domain/patient_search_page.dart';
  import 'package:ai_clinic/features/patients/domain/create_patient_input.dart';
  import 'package:ai_clinic/features/patients/domain/update_patient_input.dart';
  ```

**Fix imports** in all files that reference these types via `patient_repository.dart`:
- `patient_dev_seed_service.dart` — add import for `create_patient_input.dart`
- `patient_rpc_failure.dart` — may need `patient_search_page.dart` if it references `PatientSearchPage`
- `patient_data_layer.dart` — add re-exports if needed
- Any test files importing from `patient_repository.dart` that use these types

### Task 1.2 — Auth bootstrap: extract types from `bootstrap_repository.dart`

**Create** `features/auth/domain/bootstrap_organization_input.dart`:
```dart
class BootstrapOrganizationInput {
  // Copy entire class from bootstrap_repository.dart lines 9–23.
}
```

**Create** `features/auth/domain/bootstrap_branch_input.dart`:
```dart
class BootstrapBranchInput {
  // Copy entire class from bootstrap_repository.dart lines 26–42.
}
```

**Modify** `features/auth/data/bootstrap_repository.dart`:
- Remove both classes, add imports for the new domain files.
- Keep `bootstrapRpcFailureFromPostgrest` function in this file (it's a data-layer concern).

### Task 1.3 — Auth provisioning: extract types from `provisioning_repository.dart`

**Create** `features/auth/domain/create_staff_account_input.dart`:
```dart
import 'package:ai_clinic/features/auth/domain/auth_session.dart';

class CreateStaffAccountInput {
  // Copy from provisioning_repository.dart lines 13–29.
}
```

**Create** `features/auth/domain/create_staff_account_result.dart`:
```dart
class CreateStaffAccountResult {
  // Copy from provisioning_repository.dart lines 32–38.
}
```

**Create** `features/auth/domain/admin_reset_staff_password_result.dart`:
```dart
class AdminResetStaffPasswordResult {
  // Copy from provisioning_repository.dart lines 41–46.
}
```

**Modify** `features/auth/data/provisioning_repository.dart`:
- Remove the three classes, add imports for the new domain files.
- Keep `provisioningRpcFailureFromPostgrest` in this file.

### Task 1.4 — Settings branches: extract types from `branch_repository.dart`

**Create** `features/settings/domain/branch_list_filter.dart`:
```dart
enum BranchListFilter { active, inactive, all }
```

**Create** `features/settings/domain/create_branch_input.dart`:
```dart
class CreateBranchInput {
  // Copy from branch_repository.dart lines 13–21.
}
```

**Create** `features/settings/domain/update_branch_input.dart`:
```dart
class UpdateBranchInput {
  // Copy from branch_repository.dart lines 24–40.
}
```

**Modify** `features/settings/data/branch_repository.dart`:
- Remove the three types, add imports for the new domain files.

**Fix imports**: `patient_dev_seed_service.dart` imports `CreateBranchInput` from `branch_repository.dart` — update to new domain path.

### Task 1.5 — Settings organization: extract types from `organization_repository.dart`

**Create** `features/settings/domain/update_organization_input.dart`:
```dart
class UpdateOrganizationInput {
  // Copy from organization_repository.dart lines 10–24.
}
```

**Modify** `features/settings/data/organization_repository.dart`:
- Remove the class, add import for the new domain file.

### Task 1.6 — Settings staff: extract types from `staff_admin_repository.dart`

**Create** `features/settings/domain/staff_list_filter.dart`:
```dart
enum StaffListFilter { active, inactive, all }
```

**Create** `features/settings/domain/update_staff_member_input.dart`:
```dart
import 'package:ai_clinic/features/auth/domain/auth_session.dart';

class UpdateStaffMemberInput {
  // Copy from staff_admin_repository.dart lines 15–33.
}
```

**Modify** `features/settings/data/staff_admin_repository.dart`:
- Remove the two types, add imports for the new domain files.

**Fix imports**: `patient_dev_seed_service.dart` imports `UpdateStaffMemberInput` from `staff_admin_repository.dart` — update.

### Task 1.7 — Verify Phase 1

Run: `dart analyze` from `frontend/`.
All existing tests must still pass: `flutter test --no-pub`.
Fix any broken imports before proceeding.

---

## Phase 2: Create Abstract Repository Interfaces in `domain/repositories/`

**Goal**: Define one abstract class per repository. Method signatures must EXACTLY match the current concrete class. These interfaces live in the domain layer and know nothing about Supabase.

### Task 2.1 — Auth: `domain/repositories/auth_repository.dart`

**Create** `features/auth/domain/repositories/auth_repository.dart`:
```dart
import 'package:supabase_flutter/supabase_flutter.dart';

/// Abstract auth operations for staff sign-in lifecycle.
abstract class AuthRepository {
  Stream<AuthState> get authStateChanges;
  Session? get currentSession;
  User? get currentUser;
  Future<void> signIn({required String username, required String password});
  Future<void> signOut();
  Future<void> clearPersistedSessionOnColdStart();
  Future<void> refreshSession();
}
```

> **Note**: This interface imports Supabase types (`AuthState`, `Session`, `User`) because the domain currently uses them.
> This is a pragmatic compromise — refactoring these away would require changing the auth state machine throughout the app, which is out of scope for this structural migration.

### Task 2.2 — Auth: `domain/repositories/bootstrap_repository.dart`

**Create** `features/auth/domain/repositories/bootstrap_repository.dart`:
```dart
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/auth/domain/bootstrap_organization_input.dart';
import 'package:ai_clinic/features/auth/domain/bootstrap_branch_input.dart';

abstract class BootstrapRepository {
  Future<String> createOrganization(BootstrapOrganizationInput input);
  Future<String> createBranch(BootstrapBranchInput input);
  Future<RpcResult> resetInstallationForDevelopment();
}
```

### Task 2.3 — Auth: `domain/repositories/permission_repository.dart`

**Create** `features/auth/domain/repositories/permission_repository.dart`:
```dart
import 'package:ai_clinic/features/auth/domain/auth_session.dart';

abstract class PermissionRepository {
  Future<Set<String>> loadGrantedPermissions(StaffRole role);
}
```

### Task 2.4 — Auth: `domain/repositories/provisioning_repository.dart`

**Create** `features/auth/domain/repositories/provisioning_repository.dart`:
```dart
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/auth/domain/branch_summary.dart';
import 'package:ai_clinic/features/auth/domain/staff_member_summary.dart';
import 'package:ai_clinic/features/auth/domain/create_staff_account_input.dart';
import 'package:ai_clinic/features/auth/domain/create_staff_account_result.dart';
import 'package:ai_clinic/features/auth/domain/admin_reset_staff_password_result.dart';

abstract class ProvisioningRepository {
  Future<List<StaffMemberSummary>> listOrgStaffMembers();
  Future<List<BranchSummary>> listBranchesByIds(List<String> branchIds);
  Future<CreateStaffAccountResult> createStaffAccount(CreateStaffAccountInput input);
  Future<AdminResetStaffPasswordResult> resetStaffPassword({
    required String staffMemberId,
    required String newPassword,
  });
}
```

### Task 2.5 — Patients: `domain/repositories/patient_repository.dart`

**Create** `features/patients/domain/repositories/patient_repository.dart`:
```dart
import 'package:ai_clinic/features/patients/domain/create_patient_input.dart';
import 'package:ai_clinic/features/patients/domain/duplicate_candidate.dart';
import 'package:ai_clinic/features/patients/domain/patient_detail.dart';
import 'package:ai_clinic/features/patients/domain/patient_list_scope.dart';
import 'package:ai_clinic/features/patients/domain/patient_search_page.dart';
import 'package:ai_clinic/features/patients/domain/update_patient_input.dart';

abstract class PatientRepository {
  Future<PatientSearchPage> searchPatients({
    String? query,
    required PatientListScope scope,
    String? branchId,
    int limit = 25,
    int offset = 0,
  });

  Future<PatientDetail> getPatient(String patientId);

  Future<List<DuplicateCandidate>> checkDuplicates({
    String? fullName,
    String? phone,
    DateTime? dateOfBirth,
    String? excludePatientId,
  });

  Future<String> createPatient(CreatePatientInput input);

  Future<DateTime> updatePatient(UpdatePatientInput input);

  Future<void> archivePatient(String patientId);
}
```

> **Note**: Keep the static `parseDuplicateCandidates` method on the concrete implementation since it's a parsing utility, not a domain contract. The `PatientRpcFailure` extension that references it will import from the impl.

### Task 2.6 — Settings: `domain/repositories/branch_repository.dart`

**Create** `features/settings/domain/repositories/branch_repository.dart`:
```dart
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/settings/domain/branch_list_filter.dart';
import 'package:ai_clinic/features/settings/domain/branch_list_item.dart';
import 'package:ai_clinic/features/settings/domain/create_branch_input.dart';
import 'package:ai_clinic/features/settings/domain/update_branch_input.dart';

abstract class BranchRepository {
  Future<List<BranchListItem>> listBranches({
    required String organizationId,
    BranchListFilter filter = BranchListFilter.all,
  });
  Future<String> createBranch(CreateBranchInput input);
  Future<String> updateBranch(UpdateBranchInput input);
  Future<RpcResult> setBranchActive({required String branchId, required bool isActive});
}
```

### Task 2.7 — Settings: `domain/repositories/organization_repository.dart`

**Create** `features/settings/domain/repositories/organization_repository.dart`:
```dart
import 'package:ai_clinic/features/settings/domain/organization_profile.dart';
import 'package:ai_clinic/features/settings/domain/update_organization_input.dart';

abstract class OrganizationRepository {
  Future<OrganizationProfile?> fetchProfile({required String organizationId});
  Future<String> updateOrganization(UpdateOrganizationInput input);
}
```

### Task 2.8 — Settings: `domain/repositories/role_permissions_repository.dart`

**Create** `features/settings/domain/repositories/role_permissions_repository.dart`:
```dart
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/settings/domain/permission_matrix_row.dart';

abstract class RolePermissionsRepository {
  Future<List<PermissionMatrixRow>> fetchMatrix();
  Future<void> updateRolePermission({
    required StaffRole role,
    required String permissionKey,
    required bool isGranted,
  });
}
```

### Task 2.9 — Settings: `domain/repositories/staff_admin_repository.dart`

**Create** `features/settings/domain/repositories/staff_admin_repository.dart`:
```dart
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/settings/domain/staff_list_filter.dart';
import 'package:ai_clinic/features/settings/domain/staff_list_item.dart';
import 'package:ai_clinic/features/settings/domain/staff_member_detail.dart';
import 'package:ai_clinic/features/settings/domain/update_staff_member_input.dart';

abstract class StaffAdminRepository {
  Future<List<StaffListItem>> listStaff({StaffListFilter filter = StaffListFilter.all});
  Future<StaffMemberDetail?> fetchStaffMember(String staffMemberId);
  Future<bool> organizationHasOwner();
  Future<String> updateStaffMember(UpdateStaffMemberInput input);
  Future<RpcResult> setStaffActive({required String staffMemberId, required bool isActive});
}
```

### Task 2.10 — Verify Phase 2

Run `dart analyze`. All new files should have no errors. Existing code should still compile because the abstract classes are not yet referenced.

---

## Phase 3: Make Concrete Repositories Implement Interfaces

**Goal**: Rename concrete classes to `*Impl`, make them implement the abstract interfaces, and update the Riverpod provider return types to the abstract interface.

### Task 3.1 — Auth: `AuthRepository` → `AuthRepositoryImpl`

**Modify** `features/auth/data/auth_repository.dart`:
1. Add import: `import 'package:ai_clinic/features/auth/domain/repositories/auth_repository.dart' as domain;`
2. Rename class: `class AuthRepository` → `class AuthRepositoryImpl implements domain.AuthRepository`
3. Add `@override` to every public method/getter.
4. Update provider:
   ```dart
   final authRepositoryProvider = Provider<domain.AuthRepository>((ref) {
     return AuthRepositoryImpl(ref.watch(supabaseClientProvider));
   });
   ```

**Alternative import approach** (to avoid `as domain`): Since the abstract and concrete classes will have different names, you can import the abstract directly:
```dart
import 'package:ai_clinic/features/auth/domain/repositories/auth_repository.dart';
// AuthRepository is the abstract interface (from domain)
// AuthRepositoryImpl is the concrete class (in this file)
```

Wait — this causes a name conflict. The file is `auth_repository.dart` and the abstract is also `AuthRepository`. **Solution**: The abstract class keeps the simple name `AuthRepository`. The concrete class becomes `AuthRepositoryImpl`. There is no name conflict because they are in different files.

**IMPORTANT**: When importing the abstract interface into the concrete file, the concrete file's class is `AuthRepositoryImpl`, so there is no collision. Import the abstract directly:
```dart
import 'package:ai_clinic/features/auth/domain/repositories/auth_repository.dart';

class AuthRepositoryImpl implements AuthRepository {
  ...
}
```

The provider's return type becomes `AuthRepository` (the abstract interface, imported from domain):
```dart
final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepositoryImpl(ref.watch(supabaseClientProvider));
});
```

### Task 3.2 — Auth: `BootstrapRepository` → `BootstrapRepositoryImpl`

**Modify** `features/auth/data/bootstrap_repository.dart`:
1. Import `features/auth/domain/repositories/bootstrap_repository.dart`
2. Rename: `class BootstrapRepository` → `class BootstrapRepositoryImpl implements BootstrapRepository`
3. Add `@override` to `createOrganization`, `createBranch`, `resetInstallationForDevelopment`.
4. `_invoke` stays private — not part of interface.
5. Update provider return type to `BootstrapRepository` (abstract).

### Task 3.3 — Auth: `PermissionRepository` → `PermissionRepositoryImpl`

**Modify** `features/auth/data/permission_repository.dart`:
1. Import the abstract.
2. Rename class, add `implements PermissionRepository`.
3. `@override` on `loadGrantedPermissions`.
4. Keep `parseGrantedPermissionKeys` as a static on the impl (not in the interface).
5. Update provider return type.

### Task 3.4 — Auth: `ProvisioningRepository` → `ProvisioningRepositoryImpl`

**Modify** `features/auth/data/provisioning_repository.dart`:
1. Import the abstract.
2. Rename class, add `implements ProvisioningRepository`.
3. `@override` on all four public methods.
4. `_invoke` and `provisioningRpcFailureFromPostgrest` stay as-is.
5. Update provider return type.

### Task 3.5 — Patients: `PatientRepository` → `PatientRepositoryImpl`

**Modify** `features/patients/data/patient_repository.dart`:
1. Import the abstract from domain/repositories/.
2. Rename class, add `implements PatientRepository`.
3. `@override` on all six public methods.
4. Keep `_invoke` private and `parseDuplicateCandidates` as static on impl.
5. Update provider return type.

### Task 3.6 — Settings: `BranchRepository` → `BranchRepositoryImpl`

**Modify** `features/settings/data/branch_repository.dart`:
1. Import the abstract.
2. Rename class: `class BranchRepositoryImpl with SettingsRpcInvoker implements BranchRepository`
   (mixin `with SettingsRpcInvoker` stays — it's an implementation detail).
3. `@override` on all public methods.
4. Update provider return type.

### Task 3.7 — Settings: `OrganizationRepository` → `OrganizationRepositoryImpl`

Same pattern as 3.6.

### Task 3.8 — Settings: `RolePermissionsRepository` → `RolePermissionsRepositoryImpl`

Same pattern.

### Task 3.9 — Settings: `StaffAdminRepository` → `StaffAdminRepositoryImpl`

Same pattern.

### Task 3.10 — Fix all imports referencing old class names

After renaming, search the entire `lib/` and `test/` for every reference to the old concrete class name. Most imports will still work because:
- Providers are unchanged in name (`authRepositoryProvider` etc.)
- Consumer code uses the provider, not the class directly.

**Files likely needing updates** (they reference the concrete class by name):
- `patient_dev_seed_service.dart` — constructs `PatientDevSeedService` with repo types. Update parameter types to abstract interfaces.
- `auth_session_provider.dart` — uses `ref.read(authRepositoryProvider)` which is fine since provider returns abstract type.
- Test files that create concrete instances directly — update to `AuthRepositoryImpl`, etc.
- `patient_rpc_failure.dart` — references `PatientRepository.parseDuplicateCandidates`. Update import to point to `PatientRepositoryImpl`.

### Task 3.11 — Update `PatientDevSeedService` parameter types

**Modify** `features/patients/data/patient_dev_seed_service.dart`:
- Change constructor parameter types from concrete to abstract:
  ```dart
  PatientDevSeedService({
    required PatientRepository patients,      // abstract (from domain/repositories/)
    required BranchRepository branches,        // abstract (from domain/repositories/)
    required StaffAdminRepository staffAdmin,   // abstract (from domain/repositories/)
  })
  ```
- Update field types similarly.
- Update imports to point to domain/repositories/ files.

### Task 3.12 — Update barrel export

**Modify** `features/patients/data/patient_data_layer.dart`:
```dart
export 'package:ai_clinic/features/patients/data/patient_repository.dart';
export 'package:ai_clinic/features/patients/domain/repositories/patient_repository.dart';
export 'package:ai_clinic/features/patients/domain/patient_search_page.dart';
export 'package:ai_clinic/features/patients/domain/create_patient_input.dart';
export 'package:ai_clinic/features/patients/domain/update_patient_input.dart';
```

### Task 3.13 — Verify Phase 3

Run `dart analyze`. Run `flutter test --no-pub`. Fix all errors.

---

## Phase 4: Create Use Cases in `domain/usecases/`

**Goal**: One class per operation. Each has a constructor that takes the abstract repository, and a single `call()` method that delegates to it.

**Base pattern for every use case**:
```dart
class SomeUseCase {
  const SomeUseCase(this._repository);
  final SomeRepository _repository;

  Future<ReturnType> call(ParamType param) {
    return _repository.someMethod(param);
  }
}
```

### Task 4.1 — Auth use cases

**Create** `features/auth/domain/usecases/sign_in.dart`:
```dart
import 'package:ai_clinic/features/auth/domain/repositories/auth_repository.dart';

class SignIn {
  const SignIn(this._repository);
  final AuthRepository _repository;

  Future<void> call({required String username, required String password}) {
    return _repository.signIn(username: username, password: password);
  }
}
```

**Create** `features/auth/domain/usecases/sign_out.dart`:
```dart
import 'package:ai_clinic/features/auth/domain/repositories/auth_repository.dart';

class SignOut {
  const SignOut(this._repository);
  final AuthRepository _repository;

  Future<void> call() => _repository.signOut();
}
```

**Create** `features/auth/domain/usecases/refresh_session.dart`:
```dart
import 'package:ai_clinic/features/auth/domain/repositories/auth_repository.dart';

class RefreshSession {
  const RefreshSession(this._repository);
  final AuthRepository _repository;

  Future<void> call() => _repository.refreshSession();
}
```

**Create** `features/auth/domain/usecases/clear_persisted_session.dart`:
```dart
import 'package:ai_clinic/features/auth/domain/repositories/auth_repository.dart';

class ClearPersistedSession {
  const ClearPersistedSession(this._repository);
  final AuthRepository _repository;

  Future<void> call() => _repository.clearPersistedSessionOnColdStart();
}
```

**Create** `features/auth/domain/usecases/create_organization.dart`:
```dart
import 'package:ai_clinic/features/auth/domain/repositories/bootstrap_repository.dart';
import 'package:ai_clinic/features/auth/domain/bootstrap_organization_input.dart';

class CreateOrganization {
  const CreateOrganization(this._repository);
  final BootstrapRepository _repository;

  Future<String> call(BootstrapOrganizationInput input) {
    return _repository.createOrganization(input);
  }
}
```

**Create** `features/auth/domain/usecases/create_bootstrap_branch.dart`:
```dart
import 'package:ai_clinic/features/auth/domain/repositories/bootstrap_repository.dart';
import 'package:ai_clinic/features/auth/domain/bootstrap_branch_input.dart';

class CreateBootstrapBranch {
  const CreateBootstrapBranch(this._repository);
  final BootstrapRepository _repository;

  Future<String> call(BootstrapBranchInput input) {
    return _repository.createBranch(input);
  }
}
```

**Create** `features/auth/domain/usecases/reset_installation.dart`:
```dart
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/auth/domain/repositories/bootstrap_repository.dart';

class ResetInstallation {
  const ResetInstallation(this._repository);
  final BootstrapRepository _repository;

  Future<RpcResult> call() => _repository.resetInstallationForDevelopment();
}
```

**Create** `features/auth/domain/usecases/load_granted_permissions.dart`:
```dart
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/auth/domain/repositories/permission_repository.dart';

class LoadGrantedPermissions {
  const LoadGrantedPermissions(this._repository);
  final PermissionRepository _repository;

  Future<Set<String>> call(StaffRole role) {
    return _repository.loadGrantedPermissions(role);
  }
}
```

**Create** `features/auth/domain/usecases/list_org_staff_members.dart`:
```dart
import 'package:ai_clinic/features/auth/domain/repositories/provisioning_repository.dart';
import 'package:ai_clinic/features/auth/domain/staff_member_summary.dart';

class ListOrgStaffMembers {
  const ListOrgStaffMembers(this._repository);
  final ProvisioningRepository _repository;

  Future<List<StaffMemberSummary>> call() => _repository.listOrgStaffMembers();
}
```

**Create** `features/auth/domain/usecases/list_branches_by_ids.dart`:
```dart
import 'package:ai_clinic/features/auth/domain/repositories/provisioning_repository.dart';
import 'package:ai_clinic/features/auth/domain/branch_summary.dart';

class ListBranchesByIds {
  const ListBranchesByIds(this._repository);
  final ProvisioningRepository _repository;

  Future<List<BranchSummary>> call(List<String> branchIds) {
    return _repository.listBranchesByIds(branchIds);
  }
}
```

**Create** `features/auth/domain/usecases/create_staff_account.dart`:
```dart
import 'package:ai_clinic/features/auth/domain/repositories/provisioning_repository.dart';
import 'package:ai_clinic/features/auth/domain/create_staff_account_input.dart';
import 'package:ai_clinic/features/auth/domain/create_staff_account_result.dart';

class CreateStaffAccount {
  const CreateStaffAccount(this._repository);
  final ProvisioningRepository _repository;

  Future<CreateStaffAccountResult> call(CreateStaffAccountInput input) {
    return _repository.createStaffAccount(input);
  }
}
```

**Create** `features/auth/domain/usecases/reset_staff_password.dart`:
```dart
import 'package:ai_clinic/features/auth/domain/repositories/provisioning_repository.dart';
import 'package:ai_clinic/features/auth/domain/admin_reset_staff_password_result.dart';

class ResetStaffPassword {
  const ResetStaffPassword(this._repository);
  final ProvisioningRepository _repository;

  Future<AdminResetStaffPasswordResult> call({
    required String staffMemberId,
    required String newPassword,
  }) {
    return _repository.resetStaffPassword(
      staffMemberId: staffMemberId,
      newPassword: newPassword,
    );
  }
}
```

### Task 4.2 — Patient use cases

**Create** `features/patients/domain/usecases/search_patients.dart`:
```dart
import 'package:ai_clinic/features/patients/domain/patient_list_scope.dart';
import 'package:ai_clinic/features/patients/domain/patient_search_page.dart';
import 'package:ai_clinic/features/patients/domain/repositories/patient_repository.dart';

class SearchPatients {
  const SearchPatients(this._repository);
  final PatientRepository _repository;

  Future<PatientSearchPage> call({
    String? query,
    required PatientListScope scope,
    String? branchId,
    int limit = 25,
    int offset = 0,
  }) {
    return _repository.searchPatients(
      query: query,
      scope: scope,
      branchId: branchId,
      limit: limit,
      offset: offset,
    );
  }
}
```

**Create** `features/patients/domain/usecases/get_patient.dart`:
```dart
import 'package:ai_clinic/features/patients/domain/patient_detail.dart';
import 'package:ai_clinic/features/patients/domain/repositories/patient_repository.dart';

class GetPatient {
  const GetPatient(this._repository);
  final PatientRepository _repository;

  Future<PatientDetail> call(String patientId) {
    return _repository.getPatient(patientId);
  }
}
```

**Create** `features/patients/domain/usecases/check_duplicates.dart`:
```dart
import 'package:ai_clinic/features/patients/domain/duplicate_candidate.dart';
import 'package:ai_clinic/features/patients/domain/repositories/patient_repository.dart';

class CheckDuplicates {
  const CheckDuplicates(this._repository);
  final PatientRepository _repository;

  Future<List<DuplicateCandidate>> call({
    String? fullName,
    String? phone,
    DateTime? dateOfBirth,
    String? excludePatientId,
  }) {
    return _repository.checkDuplicates(
      fullName: fullName,
      phone: phone,
      dateOfBirth: dateOfBirth,
      excludePatientId: excludePatientId,
    );
  }
}
```

**Create** `features/patients/domain/usecases/create_patient.dart`:
```dart
import 'package:ai_clinic/features/patients/domain/create_patient_input.dart';
import 'package:ai_clinic/features/patients/domain/repositories/patient_repository.dart';

class CreatePatient {
  const CreatePatient(this._repository);
  final PatientRepository _repository;

  Future<String> call(CreatePatientInput input) {
    return _repository.createPatient(input);
  }
}
```

**Create** `features/patients/domain/usecases/update_patient.dart`:
```dart
import 'package:ai_clinic/features/patients/domain/update_patient_input.dart';
import 'package:ai_clinic/features/patients/domain/repositories/patient_repository.dart';

class UpdatePatient {
  const UpdatePatient(this._repository);
  final PatientRepository _repository;

  Future<DateTime> call(UpdatePatientInput input) {
    return _repository.updatePatient(input);
  }
}
```

**Create** `features/patients/domain/usecases/archive_patient.dart`:
```dart
import 'package:ai_clinic/features/patients/domain/repositories/patient_repository.dart';

class ArchivePatient {
  const ArchivePatient(this._repository);
  final PatientRepository _repository;

  Future<void> call(String patientId) {
    return _repository.archivePatient(patientId);
  }
}
```

### Task 4.3 — Settings use cases

**Create** `features/settings/domain/usecases/list_branches.dart`:
```dart
import 'package:ai_clinic/features/settings/domain/branch_list_filter.dart';
import 'package:ai_clinic/features/settings/domain/branch_list_item.dart';
import 'package:ai_clinic/features/settings/domain/repositories/branch_repository.dart';

class ListBranches {
  const ListBranches(this._repository);
  final BranchRepository _repository;

  Future<List<BranchListItem>> call({
    required String organizationId,
    BranchListFilter filter = BranchListFilter.all,
  }) {
    return _repository.listBranches(organizationId: organizationId, filter: filter);
  }
}
```

**Create** `features/settings/domain/usecases/create_branch.dart`:
```dart
import 'package:ai_clinic/features/settings/domain/create_branch_input.dart';
import 'package:ai_clinic/features/settings/domain/repositories/branch_repository.dart';

class CreateBranch {
  const CreateBranch(this._repository);
  final BranchRepository _repository;

  Future<String> call(CreateBranchInput input) {
    return _repository.createBranch(input);
  }
}
```

**Create** `features/settings/domain/usecases/update_branch.dart`:
```dart
import 'package:ai_clinic/features/settings/domain/update_branch_input.dart';
import 'package:ai_clinic/features/settings/domain/repositories/branch_repository.dart';

class UpdateBranch {
  const UpdateBranch(this._repository);
  final BranchRepository _repository;

  Future<String> call(UpdateBranchInput input) {
    return _repository.updateBranch(input);
  }
}
```

**Create** `features/settings/domain/usecases/set_branch_active.dart`:
```dart
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/settings/domain/repositories/branch_repository.dart';

class SetBranchActive {
  const SetBranchActive(this._repository);
  final BranchRepository _repository;

  Future<RpcResult> call({required String branchId, required bool isActive}) {
    return _repository.setBranchActive(branchId: branchId, isActive: isActive);
  }
}
```

**Create** `features/settings/domain/usecases/fetch_organization_profile.dart`:
```dart
import 'package:ai_clinic/features/settings/domain/organization_profile.dart';
import 'package:ai_clinic/features/settings/domain/repositories/organization_repository.dart';

class FetchOrganizationProfile {
  const FetchOrganizationProfile(this._repository);
  final OrganizationRepository _repository;

  Future<OrganizationProfile?> call({required String organizationId}) {
    return _repository.fetchProfile(organizationId: organizationId);
  }
}
```

**Create** `features/settings/domain/usecases/update_organization.dart`:
```dart
import 'package:ai_clinic/features/settings/domain/update_organization_input.dart';
import 'package:ai_clinic/features/settings/domain/repositories/organization_repository.dart';

class UpdateOrganization {
  const UpdateOrganization(this._repository);
  final OrganizationRepository _repository;

  Future<String> call(UpdateOrganizationInput input) {
    return _repository.updateOrganization(input);
  }
}
```

**Create** `features/settings/domain/usecases/fetch_permission_matrix.dart`:
```dart
import 'package:ai_clinic/features/settings/domain/permission_matrix_row.dart';
import 'package:ai_clinic/features/settings/domain/repositories/role_permissions_repository.dart';

class FetchPermissionMatrix {
  const FetchPermissionMatrix(this._repository);
  final RolePermissionsRepository _repository;

  Future<List<PermissionMatrixRow>> call() => _repository.fetchMatrix();
}
```

**Create** `features/settings/domain/usecases/update_role_permission.dart`:
```dart
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/settings/domain/repositories/role_permissions_repository.dart';

class UpdateRolePermission {
  const UpdateRolePermission(this._repository);
  final RolePermissionsRepository _repository;

  Future<void> call({
    required StaffRole role,
    required String permissionKey,
    required bool isGranted,
  }) {
    return _repository.updateRolePermission(
      role: role,
      permissionKey: permissionKey,
      isGranted: isGranted,
    );
  }
}
```

**Create** `features/settings/domain/usecases/list_staff.dart`:
```dart
import 'package:ai_clinic/features/settings/domain/staff_list_filter.dart';
import 'package:ai_clinic/features/settings/domain/staff_list_item.dart';
import 'package:ai_clinic/features/settings/domain/repositories/staff_admin_repository.dart';

class ListStaff {
  const ListStaff(this._repository);
  final StaffAdminRepository _repository;

  Future<List<StaffListItem>> call({StaffListFilter filter = StaffListFilter.all}) {
    return _repository.listStaff(filter: filter);
  }
}
```

**Create** `features/settings/domain/usecases/fetch_staff_member.dart`:
```dart
import 'package:ai_clinic/features/settings/domain/staff_member_detail.dart';
import 'package:ai_clinic/features/settings/domain/repositories/staff_admin_repository.dart';

class FetchStaffMember {
  const FetchStaffMember(this._repository);
  final StaffAdminRepository _repository;

  Future<StaffMemberDetail?> call(String staffMemberId) {
    return _repository.fetchStaffMember(staffMemberId);
  }
}
```

**Create** `features/settings/domain/usecases/organization_has_owner.dart`:
```dart
import 'package:ai_clinic/features/settings/domain/repositories/staff_admin_repository.dart';

class OrganizationHasOwner {
  const OrganizationHasOwner(this._repository);
  final StaffAdminRepository _repository;

  Future<bool> call() => _repository.organizationHasOwner();
}
```

**Create** `features/settings/domain/usecases/update_staff_member.dart`:
```dart
import 'package:ai_clinic/features/settings/domain/update_staff_member_input.dart';
import 'package:ai_clinic/features/settings/domain/repositories/staff_admin_repository.dart';

class UpdateStaffMember {
  const UpdateStaffMember(this._repository);
  final StaffAdminRepository _repository;

  Future<String> call(UpdateStaffMemberInput input) {
    return _repository.updateStaffMember(input);
  }
}
```

**Create** `features/settings/domain/usecases/set_staff_active.dart`:
```dart
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/settings/domain/repositories/staff_admin_repository.dart';

class SetStaffActive {
  const SetStaffActive(this._repository);
  final StaffAdminRepository _repository;

  Future<RpcResult> call({required String staffMemberId, required bool isActive}) {
    return _repository.setStaffActive(staffMemberId: staffMemberId, isActive: isActive);
  }
}
```

### Task 4.4 — Verify Phase 4

Run `dart analyze`. All new use case files should compile. Existing code still works because use cases are not yet wired in.

---

## Phase 5: Create Use Case Providers and Wire into Notifiers

**Goal**: Create Riverpod providers for each use case, then update notifiers/providers to inject use cases instead of repositories.

### Task 5.1 — Create use case provider files

**Create** `features/auth/domain/usecases/auth_use_case_providers.dart`:
```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/features/auth/data/auth_repository.dart';
import 'package:ai_clinic/features/auth/data/bootstrap_repository.dart';
import 'package:ai_clinic/features/auth/data/permission_repository.dart';
import 'package:ai_clinic/features/auth/data/provisioning_repository.dart';
import 'package:ai_clinic/features/auth/domain/usecases/sign_in.dart';
import 'package:ai_clinic/features/auth/domain/usecases/sign_out.dart';
import 'package:ai_clinic/features/auth/domain/usecases/refresh_session.dart';
import 'package:ai_clinic/features/auth/domain/usecases/clear_persisted_session.dart';
import 'package:ai_clinic/features/auth/domain/usecases/create_organization.dart';
import 'package:ai_clinic/features/auth/domain/usecases/create_bootstrap_branch.dart';
import 'package:ai_clinic/features/auth/domain/usecases/reset_installation.dart';
import 'package:ai_clinic/features/auth/domain/usecases/load_granted_permissions.dart';
import 'package:ai_clinic/features/auth/domain/usecases/list_org_staff_members.dart';
import 'package:ai_clinic/features/auth/domain/usecases/list_branches_by_ids.dart';
import 'package:ai_clinic/features/auth/domain/usecases/create_staff_account.dart';
import 'package:ai_clinic/features/auth/domain/usecases/reset_staff_password.dart';

final signInUseCaseProvider = Provider((ref) => SignIn(ref.watch(authRepositoryProvider)));
final signOutUseCaseProvider = Provider((ref) => SignOut(ref.watch(authRepositoryProvider)));
final refreshSessionUseCaseProvider = Provider((ref) => RefreshSession(ref.watch(authRepositoryProvider)));
final clearPersistedSessionUseCaseProvider = Provider((ref) => ClearPersistedSession(ref.watch(authRepositoryProvider)));
final createOrganizationUseCaseProvider = Provider((ref) => CreateOrganization(ref.watch(bootstrapRepositoryProvider)));
final createBootstrapBranchUseCaseProvider = Provider((ref) => CreateBootstrapBranch(ref.watch(bootstrapRepositoryProvider)));
final resetInstallationUseCaseProvider = Provider((ref) => ResetInstallation(ref.watch(bootstrapRepositoryProvider)));
final loadGrantedPermissionsUseCaseProvider = Provider((ref) => LoadGrantedPermissions(ref.watch(permissionRepositoryProvider)));
final listOrgStaffMembersUseCaseProvider = Provider((ref) => ListOrgStaffMembers(ref.watch(provisioningRepositoryProvider)));
final listBranchesByIdsUseCaseProvider = Provider((ref) => ListBranchesByIds(ref.watch(provisioningRepositoryProvider)));
final createStaffAccountUseCaseProvider = Provider((ref) => CreateStaffAccount(ref.watch(provisioningRepositoryProvider)));
final resetStaffPasswordUseCaseProvider = Provider((ref) => ResetStaffPassword(ref.watch(provisioningRepositoryProvider)));
```

**Create** `features/patients/domain/usecases/patient_use_case_providers.dart`:
```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/features/patients/data/patient_repository.dart';
import 'package:ai_clinic/features/patients/domain/usecases/search_patients.dart';
import 'package:ai_clinic/features/patients/domain/usecases/get_patient.dart';
import 'package:ai_clinic/features/patients/domain/usecases/check_duplicates.dart';
import 'package:ai_clinic/features/patients/domain/usecases/create_patient.dart';
import 'package:ai_clinic/features/patients/domain/usecases/update_patient.dart';
import 'package:ai_clinic/features/patients/domain/usecases/archive_patient.dart';

final searchPatientsUseCaseProvider = Provider((ref) => SearchPatients(ref.watch(patientRepositoryProvider)));
final getPatientUseCaseProvider = Provider((ref) => GetPatient(ref.watch(patientRepositoryProvider)));
final checkDuplicatesUseCaseProvider = Provider((ref) => CheckDuplicates(ref.watch(patientRepositoryProvider)));
final createPatientUseCaseProvider = Provider((ref) => CreatePatient(ref.watch(patientRepositoryProvider)));
final updatePatientUseCaseProvider = Provider((ref) => UpdatePatient(ref.watch(patientRepositoryProvider)));
final archivePatientUseCaseProvider = Provider((ref) => ArchivePatient(ref.watch(patientRepositoryProvider)));
```

**Create** `features/settings/domain/usecases/settings_use_case_providers.dart`:
```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/features/settings/data/branch_repository.dart';
import 'package:ai_clinic/features/settings/data/organization_repository.dart';
import 'package:ai_clinic/features/settings/data/role_permissions_repository.dart';
import 'package:ai_clinic/features/settings/data/staff_admin_repository.dart';
import 'package:ai_clinic/features/settings/domain/usecases/list_branches.dart';
import 'package:ai_clinic/features/settings/domain/usecases/create_branch.dart';
import 'package:ai_clinic/features/settings/domain/usecases/update_branch.dart';
import 'package:ai_clinic/features/settings/domain/usecases/set_branch_active.dart';
import 'package:ai_clinic/features/settings/domain/usecases/fetch_organization_profile.dart';
import 'package:ai_clinic/features/settings/domain/usecases/update_organization.dart';
import 'package:ai_clinic/features/settings/domain/usecases/fetch_permission_matrix.dart';
import 'package:ai_clinic/features/settings/domain/usecases/update_role_permission.dart';
import 'package:ai_clinic/features/settings/domain/usecases/list_staff.dart';
import 'package:ai_clinic/features/settings/domain/usecases/fetch_staff_member.dart';
import 'package:ai_clinic/features/settings/domain/usecases/organization_has_owner.dart';
import 'package:ai_clinic/features/settings/domain/usecases/update_staff_member.dart';
import 'package:ai_clinic/features/settings/domain/usecases/set_staff_active.dart';

final listBranchesUseCaseProvider = Provider((ref) => ListBranches(ref.watch(branchRepositoryProvider)));
final createBranchUseCaseProvider = Provider((ref) => CreateBranch(ref.watch(branchRepositoryProvider)));
final updateBranchUseCaseProvider = Provider((ref) => UpdateBranch(ref.watch(branchRepositoryProvider)));
final setBranchActiveUseCaseProvider = Provider((ref) => SetBranchActive(ref.watch(branchRepositoryProvider)));
final fetchOrganizationProfileUseCaseProvider = Provider((ref) => FetchOrganizationProfile(ref.watch(organizationRepositoryProvider)));
final updateOrganizationUseCaseProvider = Provider((ref) => UpdateOrganization(ref.watch(organizationRepositoryProvider)));
final fetchPermissionMatrixUseCaseProvider = Provider((ref) => FetchPermissionMatrix(ref.watch(rolePermissionsRepositoryProvider)));
final updateRolePermissionUseCaseProvider = Provider((ref) => UpdateRolePermission(ref.watch(rolePermissionsRepositoryProvider)));
final listStaffUseCaseProvider = Provider((ref) => ListStaff(ref.watch(staffAdminRepositoryProvider)));
final fetchStaffMemberUseCaseProvider = Provider((ref) => FetchStaffMember(ref.watch(staffAdminRepositoryProvider)));
final organizationHasOwnerUseCaseProvider = Provider((ref) => OrganizationHasOwner(ref.watch(staffAdminRepositoryProvider)));
final updateStaffMemberUseCaseProvider = Provider((ref) => UpdateStaffMember(ref.watch(staffAdminRepositoryProvider)));
final setStaffActiveUseCaseProvider = Provider((ref) => SetStaffActive(ref.watch(staffAdminRepositoryProvider)));
```

### Task 5.2 — Update notifiers to use use cases

**For every notifier that currently does `ref.read(fooRepositoryProvider).someMethod(...)`**:
1. Replace with `ref.read(someMethodUseCaseProvider).call(...)` or `ref.read(someMethodUseCaseProvider)(...)`.
2. Update imports.

**Example transformation** in a notifier:

Before:
```dart
final result = await ref.read(patientRepositoryProvider).searchPatients(
  query: query,
  scope: scope,
  branchId: branchId,
);
```

After:
```dart
final result = await ref.read(searchPatientsUseCaseProvider)(
  query: query,
  scope: scope,
  branchId: branchId,
);
```

**Files to update** (search for `ref.read(*RepositoryProvider)` and `ref.watch(*RepositoryProvider)` in all presentation/ files):

Auth notifiers:
- `auth_notifier.dart` — uses `authRepositoryProvider` → use `signInUseCaseProvider`
- `bootstrap_notifier.dart` — uses `bootstrapRepositoryProvider` → use bootstrap use cases
- `provisioning_notifier.dart` — uses `provisioningRepositoryProvider` → use provisioning use cases
- Any other auth presentation providers

Patient notifiers:
- `patient_list_notifier.dart` — uses `patientRepositoryProvider.searchPatients` → use `searchPatientsUseCaseProvider`
- `patient_detail_provider.dart` — uses `patientRepositoryProvider.getPatient` → use `getPatientUseCaseProvider`
- Any registration/edit providers

Settings notifiers:
- `branch_list_notifier.dart` or similar — use branch use cases
- `organization_settings_notifier.dart` — use org use cases
- `role_permissions_notifier.dart` — use permission use cases
- `staff_list_notifier.dart` — use staff use cases

**EXCEPTION**: `auth_session_provider.dart` in `shared/providers/` is complex and uses `authRepositoryProvider` extensively for the auth state machine. It also uses `permissionRepositoryProvider` and direct `supabaseClientProvider` for JWT decoding. **Leave this file using repositories directly** — it is infrastructure-level code, not a feature notifier. Attempting to route it through use cases would add complexity without benefit.

### Task 5.3 — Verify Phase 5

Run `dart analyze`. Run `flutter test --no-pub`. Fix all errors.

---

## Phase 6: Update Tests

**Goal**: Fix all test files that reference old concrete class names or old import paths.

### Task 6.1 — Find all affected test files

Search `frontend/test/` for:
- `AuthRepository(` → change to `AuthRepositoryImpl(`
- `BootstrapRepository(` → change to `BootstrapRepositoryImpl(`
- `PermissionRepository(` → change to `PermissionRepositoryImpl(`
- `ProvisioningRepository(` → change to `ProvisioningRepositoryImpl(`
- `PatientRepository(` → change to `PatientRepositoryImpl(`
- `BranchRepository(` → change to `BranchRepositoryImpl(`
- `OrganizationRepository(` → change to `OrganizationRepositoryImpl(`
- `RolePermissionsRepository(` → change to `RolePermissionsRepositoryImpl(`
- `StaffAdminRepository(` → change to `StaffAdminRepositoryImpl(`
- Any import of `CreatePatientInput`, `UpdatePatientInput`, `PatientSearchPage`, etc. from old paths

### Task 6.2 — Update test imports

For each test file found in 6.1:
1. Update the import path for the concrete class (now in same file but renamed).
2. Update any type references from `AuthRepository` to `AuthRepositoryImpl` when creating instances directly.
3. For provider overrides in tests, the provider type is now the abstract interface — mock classes should implement the abstract interface, not extend the concrete impl.

### Task 6.3 — Run full test suite

```bash
cd frontend
flutter test --no-pub
```

Fix any remaining failures.

---

## Phase 7: Final Cleanup

### Task 7.1 — Remove dead barrel exports

Check `patient_data_layer.dart` and any other barrel files for stale re-exports.

### Task 7.2 — Update `ARCHITECTURE.md`

If it describes the frontend structure, update the folder layout description to reflect the new domain/repositories/ and domain/usecases/ folders.

### Task 7.3 — Final verification

```bash
cd frontend
dart analyze
flutter test --no-pub
```

Zero errors, zero test failures.

---

## Summary of New Files Created

### Auth feature (14 new files)
```
features/auth/domain/
  bootstrap_organization_input.dart
  bootstrap_branch_input.dart
  create_staff_account_input.dart
  create_staff_account_result.dart
  admin_reset_staff_password_result.dart
  repositories/
    auth_repository.dart
    bootstrap_repository.dart
    permission_repository.dart
    provisioning_repository.dart
  usecases/
    sign_in.dart
    sign_out.dart
    refresh_session.dart
    clear_persisted_session.dart
    create_organization.dart
    create_bootstrap_branch.dart
    reset_installation.dart
    load_granted_permissions.dart
    list_org_staff_members.dart
    list_branches_by_ids.dart
    create_staff_account.dart
    reset_staff_password.dart
    auth_use_case_providers.dart
```

### Patients feature (9 new files)
```
features/patients/domain/
  patient_search_page.dart
  create_patient_input.dart
  update_patient_input.dart
  repositories/
    patient_repository.dart
  usecases/
    search_patients.dart
    get_patient.dart
    check_duplicates.dart
    create_patient.dart
    update_patient.dart
    archive_patient.dart
    patient_use_case_providers.dart
```

### Settings feature (16 new files)
```
features/settings/domain/
  branch_list_filter.dart
  create_branch_input.dart
  update_branch_input.dart
  update_organization_input.dart
  staff_list_filter.dart
  update_staff_member_input.dart
  repositories/
    branch_repository.dart
    organization_repository.dart
    role_permissions_repository.dart
    staff_admin_repository.dart
  usecases/
    list_branches.dart
    create_branch.dart
    update_branch.dart
    set_branch_active.dart
    fetch_organization_profile.dart
    update_organization.dart
    fetch_permission_matrix.dart
    update_role_permission.dart
    list_staff.dart
    fetch_staff_member.dart
    organization_has_owner.dart
    update_staff_member.dart
    set_staff_active.dart
    settings_use_case_providers.dart
```

**Total**: ~39 new files, ~9 modified repository files, ~10+ modified notifier/provider files, ~20+ modified test files.

---

## Execution Order for Cheap Model

1. Phase 1 (Tasks 1.1–1.7): Extract types → verify
2. Phase 2 (Tasks 2.1–2.10): Create interfaces → verify
3. Phase 3 (Tasks 3.1–3.13): Rename impls → verify
4. Phase 4 (Tasks 4.1–4.4): Create use cases → verify
5. Phase 5 (Tasks 5.1–5.3): Wire providers → verify
6. Phase 6 (Tasks 6.1–6.3): Fix tests → verify
7. Phase 7 (Tasks 7.1–7.3): Cleanup → final verify

**CRITICAL**: After EACH phase, run `dart analyze` and fix errors before moving to the next phase. Do NOT proceed to the next phase with outstanding errors.
