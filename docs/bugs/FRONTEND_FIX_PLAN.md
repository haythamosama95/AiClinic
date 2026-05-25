# Frontend Fix Plan — AiClinic (Flutter/Dart)

**Date**: 2026-05-24
**Based on**: `frontend/FRONTEND_CODE_REVIEW.md`
**Scope**: All 35 issues across 7 categories

---

## Table of Contents

1. [Critical Bugs (Priority: Immediate)](#1-critical-bugs)
2. [Non-Critical Bugs & Code Smells (Priority: High)](#2-non-critical-bugs--code-smells)
3. [Architectural Issues (Priority: Medium-High)](#3-architectural-issues)
4. [Future Extension Risks (Priority: Medium)](#4-future-extension-risks)
5. [Security Concerns (Priority: Medium-High)](#5-security-concerns)
6. [UI/UX Issues (Priority: Medium)](#6-uiux-issues)
7. [Testing & Maintainability (Priority: Low-Medium)](#7-testing--maintainability)

---

## 1. Critical Bugs

### 1.1 Fix web deployment profile path string interpolation

**File**: `lib/core/config/deployment_profile_store_web.dart:9`

**Problem**: `$DeploymentProfileStore` interpolates the class type name, not the static field. The path resolves to `"web/DeploymentProfileStore.fileName"` instead of `"web/deployment-profile.json"`.

**Fix**:

```dart
// BEFORE
String resolveDeploymentProfilePath() => 'web/$DeploymentProfileStore.fileName';

// AFTER
String resolveDeploymentProfilePath() => 'web/${DeploymentProfileStore.fileName}';
```

**Verification**: Add a unit test asserting the return value equals `'web/deployment-profile.json'`. Run the web target and confirm the deployment profile loads correctly.

**Risk**: None — this is a one-character fix that corrects broken behavior.

---

### 1.2 Fix `SnackbarService.showFailure` to display the error message

**File**: `lib/core/widgets/snackbar_service.dart:33-48`

**Problem**: Only `failure.title` is shown visually. The detailed `failure.message` is only in the `Semantics` label (screen readers only). Users see a generic title with no actionable context.

**Fix**: Use a two-line layout that shows both title and message.

```dart
// BEFORE
content: Semantics(
  label: semanticsLabel,
  child: Text(failure.title),
),

// AFTER
content: Semantics(
  label: semanticsLabel,
  child: Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        failure.title,
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
      if (failure.message.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            failure.message,
            style: const TextStyle(fontSize: 13),
          ),
        ),
    ],
  ),
),
```

**Verification**: Trigger a known failure (e.g. configuration required) and confirm both title and message appear in the snackbar. Verify the snackbar auto-sizing works for long messages. Check that the semantics label still reads correctly for screen readers.

**Risk**: Low — snackbar height increases slightly when a message is present. Test on both desktop and web to ensure layout doesn't overflow.

---

### 1.3 Move `_populateFromDetail` out of `build()` in `PatientEditPage`

**File**: `lib/features/patients/presentation/pages/patient_edit_page.dart:271-273`

**Problem**: `_populateFromDetail(detail)` sets `TextEditingController.text` and mutates instance fields during the `build` method. This is a Flutter anti-pattern — even though a guard (`_loadedPatientId == detail.id`) prevents re-execution, the approach is fragile if data shape changes.

**Fix**: Use `ref.listen` to populate controllers outside the build phase.

```dart
// STEP 1: Remove _populateFromDetail call from build()
// In the build method's data: branch, only return the form:
//   data: (detail) => _buildForm(context, detail: detail, patientId: id),

// STEP 2: Add ref.listen in initState or a separate init method
@override
void initState() {
  super.initState();
  // Listen for patient detail changes and populate form outside build
  WidgetsBinding.instance.addPostFrameCallback((_) {
    ref.listen(
      patientDetailProvider(widget.patientId),
      (previous, next) {
        next.whenData((detail) {
          if (_loadedPatientId != detail.id) {
            _populateFromDetail(detail);
          }
        });
      },
      fireImmediately: true,
    );
  });
}
```

**Alternative (simpler)**: If using Riverpod hooks (`HookConsumerWidget`), use `ref.listen` directly in `build` with the listener callback — this is the idiomatic Riverpod approach and does not count as a build-phase side effect since `ref.listen` callbacks run asynchronously.

```dart
@override
Widget build(BuildContext context) {
  ref.listen(patientDetailProvider(id), (prev, next) {
    next.whenData((detail) {
      if (_loadedPatientId != detail.id) {
        _populateFromDetail(detail);
      }
    });
  });

  final detailAsync = ref.watch(patientDetailProvider(id));
  return detailAsync.when(
    data: (detail) => _buildForm(context, detail: detail, patientId: id),
    loading: () => const Center(child: CircularProgressIndicator()),
    error: (e, st) => Center(child: Text('Error: $e')),
  );
}
```

**Verification**: Edit a patient, verify all fields populate correctly. Trigger a Riverpod rebuild (e.g. resize window) and confirm controllers don't re-populate or lose user edits.

**Risk**: Low — the `ref.listen` approach is the standard Riverpod pattern. Ensure `fireImmediately: true` covers the initial data load.

---

### 1.4 Remove optimistic lock fallback to `DateTime.now()`

**File**: `lib/features/patients/presentation/pages/patient_edit_page.dart:86`

**Problem**: `_buildInput` falls back to `DateTime.now().toUtc()` when `_expectedUpdatedAt` is null, which would silently bypass the stale-update protection. Although `_submit` has a null guard, `_buildInput` is callable from other contexts.

**Fix**: Replace the fallback with a `StateError` throw.

```dart
// BEFORE
expectedUpdatedAt: _expectedUpdatedAt ?? DateTime.now().toUtc(),

// AFTER
expectedUpdatedAt: _expectedUpdatedAt ?? (throw StateError(
  'Cannot build patient update input: _expectedUpdatedAt is null. '
  'Ensure patient detail is loaded before calling _buildInput.',
)),
```

**Alternative (stronger)**: Make `_expectedUpdatedAt` a required parameter of `_buildInput` instead of reading instance state:

```dart
PatientUpdateInput _buildInput({required DateTime expectedUpdatedAt}) {
  return PatientUpdateInput(
    // ... fields ...
    expectedUpdatedAt: expectedUpdatedAt,
  );
}

// In _submit:
if (_expectedUpdatedAt == null) {
  setState(() => _formError = 'Patient data not loaded');
  return;
}
final input = _buildInput(expectedUpdatedAt: _expectedUpdatedAt!);
```

**Verification**: Write a unit test that calls `_buildInput` (or its equivalent) when `_expectedUpdatedAt` is null and assert it throws `StateError`. Verify the normal edit → save flow still works.

**Risk**: None — this makes an implicit invariant explicit.

---

## 2. Non-Critical Bugs & Code Smells

### 2.1 Implement sentinel-based `copyWith` for nullable domain fields

**Files**: `patient_detail.dart`, `patient_list_item.dart`, `auth_session.dart`, `organization_profile.dart`, `branch_list_item.dart`, `staff_list_item.dart`

**Problem**: The `??` pattern in `copyWith` makes it impossible to clear a nullable field back to `null`.

**Fix**: Use the sentinel pattern already established in `StartupSessionState.copyWith`. Create a shared sentinel and apply it to all domain models.

**Step 1**: Create a shared sentinel in `lib/core/utils/copy_with_sentinel.dart`:

```dart
/// Sentinel value used in copyWith methods to distinguish
/// "not provided" from "explicitly set to null".
const Object _noChange = Object();

/// Returns true if the value was explicitly provided (even if null).
bool isProvided(Object? value) => !identical(value, _noChange);
```

**Step 2**: Update each domain model. Example for `PatientDetail`:

```dart
PatientDetail copyWith({
  String? fullName,
  Object? phone = _noChange,      // nullable field — use Object?
  Object? notes = _noChange,       // nullable field
  PatientGender? gender,
  // ... non-nullable fields use normal T? ...
}) {
  return PatientDetail(
    fullName: fullName ?? this.fullName,
    phone: identical(phone, _noChange) ? this.phone : phone as String?,
    notes: identical(notes, _noChange) ? this.notes : notes as String?,
    gender: gender ?? this.gender,
    // ...
  );
}
```

**Step 3**: Update all call sites that currently pass `null` intentionally (search for `.copyWith(` across all affected files). Most call sites pass non-null values and won't need changes — only sites that intend to clear a field need updating.

**Verification**: Write unit tests that assert:
- `model.copyWith()` returns an identical copy (no change)
- `model.copyWith(phone: null)` returns a copy with `phone == null`
- `model.copyWith(phone: '123')` returns a copy with the new phone

**Risk**: Medium — requires updating all affected models and their call sites. Do this in a dedicated PR with thorough test coverage.

---

### 2.2 Simplify `_contextFailureReason` redundant branches

**File**: `lib/shared/providers/auth_session_provider.dart:186-201`

**Problem**: The inner `if` condition always evaluates to `true` because the outer `if` already matched `'missing staff claims'`, which contains `'staff claims'`. Both branches return the same string.

**Fix**: Remove the dead inner conditional.

```dart
// BEFORE
static String _contextFailureReason(Object error) {
  final message = error.toString().toLowerCase();
  if (message.contains('missing staff claims')) {
    if (message.contains('staff_role') || message.contains('staff claims')) {
      return 'missing_staff_claims';
    }
    return 'missing_staff_claims';
  }
  // ...
}

// AFTER
static String _contextFailureReason(Object error) {
  final message = error.toString().toLowerCase();
  if (message.contains('missing staff claims')) {
    return 'missing_staff_claims';
  }
  // ...
}
```

**Verification**: Existing tests for auth session failure classification should pass unchanged. If no tests exist, add one that passes an error containing `'missing staff claims'` and asserts the return value.

**Risk**: None — pure dead code removal.

---

### 2.3 Remove dead `branch_names` parsing from `StaffListItem.fromRow`

**File**: `lib/features/settings/domain/staff_list_item.dart:44`

**Problem**: `fromRow` parses `row['branch_names']` which never exists in the query result. Branch names are loaded separately via `_loadBranchNamesByStaffId` and set via `copyWith`.

**Fix**: Remove the parsing and default to empty list.

```dart
// BEFORE
branchNames: _parseBranchNames(row['branch_names']),

// AFTER
branchNames: const [],
```

Keep `_parseBranchNames` as a private utility only if it's used elsewhere (check with a search). If not used, remove it entirely to avoid dead code.

**Verification**: Verify staff list still loads correctly with branch names populated via the separate `_loadBranchNamesByStaffId` path.

**Risk**: None — the parsed value was always `[]` through the normal code path.

---

### 2.4 Standardize `PermissionService` instantiation via provider

**Files**: `patient_list_page.dart`, `patient_detail_page.dart`, `auth_shell_page.dart`

**Problem**: Three different instantiation patterns coexist. Direct instantiation creates stale permission checks.

**Fix**: Standardize all permission checks to use the provider.

**Step 1**: Ensure `permissionServiceProvider` (already declared in `auth_session_provider.dart`) is the single source:

```dart
final permissionServiceProvider = Provider<PermissionService>((ref) {
  final auth = ref.watch(authSessionProvider);
  return PermissionService(auth.context);
});
```

**Step 2**: Replace all direct instantiations:

```dart
// BEFORE (in patient_list_page.dart, patient_detail_page.dart)
final permissions = PermissionService(auth.context);

// AFTER
final permissions = ref.watch(permissionServiceProvider);

// BEFORE (in auth_shell_page.dart)
final permissions = PermissionService(auth);

// AFTER
final permissions = ref.watch(permissionServiceProvider);
```

**Step 3**: Verify that `PermissionService` constructor accepts `AuthSessionContext?` consistently. If `auth_shell_page.dart` passes an `AuthSessionState` instead of `AuthSessionContext`, fix the constructor or the call site.

**Verification**: Navigate between pages while signed in. Sign out and back in — verify permission checks update reactively. Confirm no stale permission states.

**Risk**: Low — straightforward provider consolidation. Test permission-gated UI elements after the change.

---

### 2.5 Fix `AppSearchableDropdownField` to use tap instead of pointer-down

**File**: `lib/core/widgets/app_searchable_dropdown_field.dart:188`

**Problem**: `onPointerDown` fires on press-down, not tap release. Long presses and accidental touches trigger selection.

**Fix**: Replace `Listener` + `onPointerDown` with `GestureDetector` + `onTap`, and address the focus-loss race condition properly.

```dart
// BEFORE
Listener(
  behavior: HitTestBehavior.opaque,
  onPointerDown: (_) => onSelect(option),
  child: ListTile(...),
);

// AFTER
GestureDetector(
  behavior: HitTestBehavior.opaque,
  onTap: () => onSelect(option),
  child: ListTile(...),
);
```

**Addressing the race condition**: The original `onPointerDown` was used because focus loss (closing the overlay) fires before `onTap`. Fix this by deferring focus loss:

```dart
// In the overlay builder or focus change handler, defer the close:
void _handleFocusChange() {
  if (!_focusNode.hasFocus) {
    // Defer overlay close to allow tap to fire first
    Future.delayed(const Duration(milliseconds: 100), () {
      if (!_focusNode.hasFocus && mounted) {
        _closeOverlay();
      }
    });
  }
}
```

Lines ~65-72 of the file already have a `WidgetsBinding.instance.addPostFrameCallback` deferral for focus loss. Verify it's working correctly with `onTap` instead of `onPointerDown`. If the overlay closes before `onTap` fires, increase the deferral or use `onTapDown` with a short delay before confirming selection.

**Verification**: Test on desktop: click an option (should select), long-press and drag away (should NOT select), click and hold without release (should NOT select). Test with keyboard navigation if applicable.

**Risk**: Medium — the original `onPointerDown` was a deliberate workaround. Test thoroughly on all target platforms.

---

### 2.6 Extract shared date formatting utility

**Files**: `patient_detail_page.dart`, `patient_registration_page.dart`, `patient_edit_page.dart`, `duplicate_candidates_dialog.dart`

**Problem**: Identical `padLeft(2, '0')` date formatting duplicated in 4+ files.

**Fix**: Create a shared utility.

**Step 1**: Create `lib/core/utils/date_format_utils.dart`:

```dart
/// Formats a DateTime as 'YYYY-MM-DD'.
String formatDate(DateTime date) {
  final y = date.year.toString();
  final m = date.month.toString().padLeft(2, '0');
  final d = date.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}

/// Formats a DateTime as 'YYYY-MM-DD HH:mm' in local time.
String formatDateTime(DateTime dateTime) {
  final local = dateTime.toLocal();
  final date = formatDate(local);
  final h = local.hour.toString().padLeft(2, '0');
  final min = local.minute.toString().padLeft(2, '0');
  return '$date $h:$min';
}
```

**Step 2**: Replace all inline formatting across the 4 files:

```dart
// BEFORE (in patient_detail_page.dart)
String _formatDate(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

// AFTER
import 'package:ai_clinic/core/utils/date_format_utils.dart';
// Use formatDate(d) directly
```

**Step 3**: Remove the local `_formatDate` and `_formatDateTime` methods from `patient_detail_page.dart`.

**Verification**: Verify all date displays render the same format as before. Add unit tests for the utility functions covering edge cases (single-digit months, year boundaries).

**Risk**: None — pure refactor with no behavior change.

---

## 3. Architectural Issues

### 3.1 Unify RPC invocation into a shared mixin

**Files**: `lib/features/patients/data/patient_repository.dart` (`PatientRepositoryImpl._invoke`), `lib/features/settings/data/settings_rpc_repository.dart` (`SettingsRpcInvoker`)

**Problem**: Two nearly identical RPC invocation implementations with the same log → call → parse → error-map pattern.

**Fix**: Extract a shared `AppRpcInvoker` mixin in `core/`.

**Step 1**: Create `lib/core/rpc/app_rpc_invoker.dart`:

```dart
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ai_clinic/core/logging/app_log.dart';
// ... other imports

mixin AppRpcInvoker {
  SupabaseClient get rpcClient;

  /// The migration file hint shown when the RPC function is not found.
  String get migrationHint;

  /// The log domain prefix (e.g., 'patients', 'settings').
  String get rpcLogDomain;

  Future<Map<String, dynamic>> invokeRpc(
    String functionName, {
    Map<String, dynamic>? params,
  }) async {
    final paramKeys = params?.keys.join(',') ?? 'none';
    AppLog.fine('$rpcLogDomain.rpc.invoke fn=$functionName params=$paramKeys');

    try {
      final response = params != null
          ? await rpcClient.rpc(functionName, params: params)
          : await rpcClient.rpc(functionName);

      final result = RpcResult.fromDynamic(response);
      if (!result.success) {
        AppLog.warning('$rpcLogDomain.rpc.failed fn=$functionName code=${result.errorCode}');
        throw RpcFailure(
          functionName: functionName,
          errorCode: result.errorCode ?? 'UNKNOWN',
          message: result.message ?? 'RPC call failed',
        );
      }
      return result.data;
    } on PostgrestException catch (e) {
      if (e.code == 'PGRST202' ||
          (e.message?.contains('Could not find the function') ?? false)) {
        throw RpcFailure(
          functionName: functionName,
          errorCode: 'RPC_NOT_APPLIED',
          message: 'Function $functionName not found. '
              'Apply migration: $migrationHint',
        );
      }
      rethrow;
    }
  }
}
```

**Step 2**: Refactor `PatientRepositoryImpl` to use the mixin:

```dart
class PatientRepositoryImpl with AppRpcInvoker implements PatientRepository {
  PatientRepositoryImpl(this._client);
  final SupabaseClient _client;

  @override
  SupabaseClient get rpcClient => _client;

  @override
  String get migrationHint => '20260523140000_patient_management.sql';

  @override
  String get rpcLogDomain => 'patients';

  // Remove _invoke method, replace all _invoke() calls with invokeRpc()
}
```

**Step 3**: Refactor `SettingsRpcInvoker` mixin to extend or delegate to `AppRpcInvoker`:

```dart
mixin SettingsRpcInvoker on AppRpcInvoker {
  @override
  String get migrationHint => '20260522100000_org_branch_management.sql';

  @override
  String get rpcLogDomain => 'settings';
}
```

Or simply remove `SettingsRpcInvoker` and have settings repository implementations (e.g., `BranchRepositoryImpl`, `StaffAdminRepositoryImpl`) use `AppRpcInvoker` directly.

**Step 4**: Update all `*Impl` repository classes that currently duplicate RPC logic.

**Verification**: Run all existing RPC-related tests. Verify that error messages still include the correct migration hint for each domain. Test the `PGRST202` error path.

**Risk**: Medium — touching multiple repository files. Run full test suite after refactoring.

---

### 3.2 Introduce `ShellRoute` for authenticated layout

**File**: `lib/app/router.dart`

**Problem**: All routes are flat. No shared scaffold, duplicated AppBar/navigation across every page, no shared chrome for the authenticated state.

**Fix**: Wrap authenticated routes in a `ShellRoute` with a shared scaffold.

**Step 1**: Create `lib/app/shell/authenticated_shell.dart`:

```dart
class AuthenticatedShell extends ConsumerWidget {
  const AuthenticatedShell({required this.child, super.key});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: _buildAppBar(context, ref),
      body: Row(
        children: [
          _buildNavigationRail(context, ref),
          const VerticalDivider(width: 1),
          Expanded(child: child),
        ],
      ),
    );
  }

  NavigationRail _buildNavigationRail(BuildContext context, WidgetRef ref) {
    final permissions = ref.watch(permissionServiceProvider);
    final currentPath = GoRouterState.of(context).uri.path;

    return NavigationRail(
      selectedIndex: _indexForPath(currentPath),
      onDestinationSelected: (index) => _navigateTo(context, index),
      destinations: [
        const NavigationRailDestination(
          icon: Icon(Icons.home),
          label: Text('Home'),
        ),
        if (permissions.canViewPatients())
          const NavigationRailDestination(
            icon: Icon(Icons.people),
            label: Text('Patients'),
          ),
        // ... settings, etc.
      ],
    );
  }
}
```

**Step 2**: Restructure `router.dart` to use `ShellRoute`:

```dart
GoRouter(
  routes: [
    // Unauthenticated routes (sign-in, bootstrap, etc.)
    GoRoute(path: '/sign-in', builder: ...),
    GoRoute(path: '/bootstrap', builder: ...),

    // Authenticated shell
    ShellRoute(
      builder: (context, state, child) => AuthenticatedShell(child: child),
      routes: [
        GoRoute(path: '/', builder: (_, __) => const HomePage()),
        GoRoute(path: '/patients', builder: (_, __) => const PatientListPage()),
        GoRoute(path: '/patients/:id', builder: ...),
        GoRoute(path: '/patients/:id/edit', builder: ...),
        GoRoute(path: '/patients/register', builder: ...),
        GoRoute(path: '/settings', builder: ...),
        // ... all authenticated routes
      ],
    ),
  ],
);
```

**Step 3**: Remove per-page `Scaffold` and `AppBar` from each authenticated page. Pages should return only their body content.

**Step 4**: Move dev buttons (fill clinic, reset, seed) from `AuthShellPage` into the shell's AppBar actions (behind `kDebugMode`).

**Verification**: Navigate between all pages and verify the shell persists. Verify back navigation works correctly with `ShellRoute`. Test that unauthenticated routes don't show the shell. Verify deep linking still works.

**Risk**: High — this is a significant structural change. Do in a dedicated branch. Test all navigation flows, including redirect logic.

---

### 3.3 Eliminate remaining cross-feature imports

**Files**: `patient_dev_seed_service.dart` → settings (via abstract interfaces), `auth_shell_page.dart` → patients/settings (presentation-level)

**Problem**: Feature modules still import from each other. The clean architecture migration improved data-layer coupling (cross-feature references now use abstract interfaces from `domain/repositories/` instead of concrete implementations), but presentation-level cross-feature imports remain.

**Fix**: Move shared entities to `shared/domain/` and eliminate presentation-level cross-feature imports.

**Step 1**: Move shared domain models that are used across features:

```
lib/shared/domain/
├── branch_list_item.dart    # Used by patients + settings
├── staff_list_item.dart     # Used by patients + settings (for seed)
└── staff_role.dart          # Used by auth + settings
```

**Step 2**: Replace direct cross-feature provider/repository imports with shared providers:

```dart
// BEFORE (in patient_dev_seed_service.dart)
import 'package:ai_clinic/features/settings/domain/repositories/branch_repository.dart';

// AFTER — access via shared provider, no direct import of settings feature
final branches = await ref.read(branchListProvider.future);
```

**Step 3**: Create shared providers in `lib/shared/providers/` for any data needed across features:

```dart
// lib/shared/providers/branch_providers.dart
final branchListProvider = FutureProvider<List<BranchListItem>>((ref) {
  return ref.watch(branchRepositoryProvider).listBranches();
});
```

**Step 4**: For `AuthShellPage`, extract navigation targets into route constants. The shell should navigate to routes, not import feature widgets:

```dart
// BEFORE
import 'package:ai_clinic/features/patients/presentation/widgets/dev_seed_patients_button.dart';

// AFTER — no feature import needed; dev buttons are part of the shell or dev overlay
```

**Verification**: Verify no `features/X` imports `features/Y` directly. Run `dart analyze` to confirm no circular dependency warnings.

**Risk**: Medium — requires moving files and updating imports across the codebase. Do incrementally.

---

### 3.4 Standardize state management pattern

**Problem**: Mix of `AsyncNotifier<T>` and `Notifier<UiState>` with manual `isSubmitting`/`errorMessage` fields. The clean architecture migration introduced use case providers (notifiers now call `ref.read(useCaseProvider)(...)` instead of direct repository methods), but this structural improvement doesn't resolve the state management pattern inconsistency.

**Fix**: Establish conventions and migrate manual notifiers.

**Step 1**: Document the convention in a project rule:

- **Data-fetching / CRUD operations**: Use `AsyncNotifier<T>` — gets loading/error/data states for free.
- **Synchronous UI state** (e.g. form visibility toggles, theme): Use `Notifier<T>`.
- **Mutation operations** (create/update/delete): Use `AsyncNotifier<void>` or a dedicated `MutationNotifier` pattern.

**Step 2**: Migrate `BootstrapNotifier`, `ProvisioningNotifier`, `BranchFormNotifier` to `AsyncNotifier`:

```dart
// BEFORE
class BranchFormNotifier extends Notifier<BranchFormState> {
  @override
  BranchFormState build() => const BranchFormState();

  Future<void> submit() async {
    state = state.copyWith(isSubmitting: true, clearError: true);
    try {
      await ref.read(createBranchUseCaseProvider)(...);
      state = state.copyWith(isSubmitting: false, lastCreated: branch);
    } catch (e) {
      state = state.copyWith(isSubmitting: false, errorMessage: e.toString());
    }
  }
}

// AFTER
class BranchFormNotifier extends AsyncNotifier<BranchFormResult?> {
  @override
  FutureOr<BranchFormResult?> build() => null;

  Future<void> submit(BranchFormInput input) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      return await ref.read(createBranchUseCaseProvider)(input);
    });
  }
}
```

**Step 3**: Update corresponding UI code to use `asyncValue.when(loading:, error:, data:)` instead of manual `state.isSubmitting` / `state.errorMessage` checks.

**Verification**: Each migrated notifier should pass its existing tests. Verify loading/error/success states render correctly in the UI.

**Risk**: Medium — each notifier migration requires updating both the notifier and its consuming widgets. Do one at a time.

---

### 3.5 ~~Introduce repository interface abstractions~~ — COMPLETED

**Status**: Resolved by the clean architecture migration.

The following changes have been implemented:

- **Abstract interfaces** created in `domain/repositories/` for every feature (e.g., `PatientRepository` in `features/patients/domain/repositories/patient_repository.dart`)
- **Concrete implementations** renamed to `*Impl` (e.g., `PatientRepositoryImpl` in `features/patients/data/patient_repository.dart`)
- **Use cases** added in `domain/usecases/` — one class per operation with a `call()` method
- **Use case providers** created (e.g., `searchPatientsUseCaseProvider`, `createPatientUseCaseProvider`)
- **Repository providers** now return the abstract type:
  ```dart
  final patientRepositoryProvider = Provider<PatientRepository>((ref) {
    return PatientRepositoryImpl(ref.watch(supabaseClientProvider));
  });
  ```
- **Input/output DTOs** extracted from data layer to `domain/` (e.g., `CreatePatientInput`, `PatientSearchPage`, `UpdatePatientInput`)
- **Notifiers** updated to inject use cases instead of direct repository access

**No further action required.**

---

### 3.6 Abstract navigation from UI

**Problem**: Direct `context.go()` / `context.push()` calls scattered across 15+ files.

**Fix**: Create a navigation service that centralizes route definitions and navigation calls.

**Step 1**: Create `lib/app/navigation/app_navigator.dart`:

```dart
class AppNavigator {
  AppNavigator(this._context);
  final BuildContext _context;

  void goHome() => _context.go('/');
  void goPatientList() => _context.go('/patients');
  void goPatientDetail(String id) => _context.go('/patients/$id');
  void goPatientEdit(String id) => _context.go('/patients/$id/edit');
  void goPatientRegister() => _context.go('/patients/register');
  void goSettings() => _context.go('/settings');
  void goSignIn() => _context.go('/sign-in');
  void pop() => _context.pop();
}
```

**Step 2**: Optionally, expose via a Riverpod provider or an extension on `BuildContext`:

```dart
extension NavigatorExt on BuildContext {
  AppNavigator get nav => AppNavigator(this);
}

// Usage:
context.nav.goPatientDetail(patient.id);
```

**Step 3**: Replace all direct `context.go('/patients/$id')` calls with `context.nav.goPatientDetail(id)`.

**Step 4**: Route paths should be defined as constants in `app_routes.dart` (already partially exists):

```dart
class AppRoutes {
  static const home = '/';
  static const patients = '/patients';
  static String patientDetail(String id) => '/patients/$id';
  static String patientEdit(String id) => '/patients/$id/edit';
  static const patientRegister = '/patients/register';
  static const settings = '/settings';
  static const signIn = '/sign-in';
}
```

**Verification**: Navigation should behave identically. Route changes now only require updating `AppRoutes` and `AppNavigator`, not every call site.

**Risk**: Low — pure refactor. Search for all `context.go(` and `context.push(` to ensure complete migration.

---

## 4. Future Extension Risks

### 4.1 Prepare `DeploymentMode` for future modes

**File**: `lib/core/config/deployment_profile.dart`

**Problem**: Only `local` mode exists, and the constructor explicitly rejects anything else.

**Fix**: Add the enum values now but keep the validation rejection for V1. This documents intent without changing behavior.

```dart
enum DeploymentMode {
  local,
  // Reserved for future releases:
  // cloud,
  // hybrid,
}

// In fromMap — keep the existing rejection but reference the enum:
if (deploymentModeValue != DeploymentMode.local.wireValue) {
  throw InvalidDeploymentProfileException(
    'Only "${DeploymentMode.local.wireValue}" deployment is supported. '
    'Received: "$deploymentModeValue".',
  );
}
```

**Verification**: Existing tests pass. No behavior change.

**Risk**: None — documentation-only change.

---

### 4.2 Document offline/cache strategy for future implementation

**Problem**: No offline support; entire app unusable when LAN is down.

**Fix** (deferred — document now, implement later):

**Step 1**: Create `specs/future/offline-cache-strategy.md` documenting the approach:

- Use `drift` (SQLite) as a local cache for patient data
- Implement a sync queue for mutations made offline
- Show stale-data indicator when cache is being used
- Cache invalidation strategy on reconnection

**Step 2**: For now, add user-friendly error handling when network is unavailable:

```dart
// In PatientRepositoryImpl, wrap RPC calls:
try {
  return await invokeRpc('search_patients', params: params);
} on SocketException {
  throw AppFailure(
    title: 'Network unavailable',
    message: 'Cannot reach the clinic server. Check your LAN connection.',
    isRecoverable: true,
  );
}
```

**Verification**: Disconnect from LAN and verify the app shows a friendly error instead of a raw exception.

**Risk**: Low for error handling improvement. Full offline support is a separate major feature.

---

### 4.3 Extend `PatientGender` enum

**File**: `lib/features/patients/domain/patient_gender.dart`

**Problem**: Only `male` and `female` values; healthcare systems often require more options.

**Fix**: Add additional values. This requires a coordinated backend + frontend change.

**Step 1**: Backend migration to alter the `patient_gender` enum:

```sql
ALTER TYPE patient_gender ADD VALUE IF NOT EXISTS 'other';
ALTER TYPE patient_gender ADD VALUE IF NOT EXISTS 'prefer_not_to_say';
ALTER TYPE patient_gender ADD VALUE IF NOT EXISTS 'unknown';
```

**Step 2**: Update the Dart enum:

```dart
enum PatientGender {
  male('male', 'Male'),
  female('female', 'Female'),
  other('other', 'Other'),
  preferNotToSay('prefer_not_to_say', 'Prefer not to say'),
  unknown('unknown', 'Unknown');

  const PatientGender(this.wireValue, this.label);
  final String wireValue;
  final String label;

  static PatientGender? tryParse(String? value) {
    if (value == null) return null;
    return PatientGender.values.cast<PatientGender?>().firstWhere(
      (g) => g!.wireValue == value,
      orElse: () => null,
    );
  }
}
```

**Step 3**: Update all form dropdowns that show gender options to include the new values.

**Verification**: Register a patient with each gender option. Verify the value round-trips through the RPC correctly.

**Risk**: Medium — requires coordinated DB migration. Plan as part of a future feature release.

---

### 4.4 Replace `List<List<String>>` with typed row model in `AppDataTable`

**File**: `lib/core/widgets/app_data_table.dart`

**Problem**: Type-unsafe row representation. Column/data mismatch is silent.

**Fix**: Introduce a generic typed data table.

```dart
class AppDataColumn<T> {
  const AppDataColumn({
    required this.label,
    required this.extract,
    this.numeric = false,
  });
  final String label;
  final String Function(T item) extract;
  final bool numeric;
}

class AppTypedDataTable<T> extends StatelessWidget {
  const AppTypedDataTable({
    required this.columns,
    required this.rows,
    this.onRowTap,
    super.key,
  });

  final List<AppDataColumn<T>> columns;
  final List<T> rows;
  final void Function(T item)? onRowTap;

  @override
  Widget build(BuildContext context) {
    return DataTable(
      columns: columns.map((c) => DataColumn(
        label: Text(c.label),
        numeric: c.numeric,
      )).toList(),
      rows: rows.map((item) => DataRow(
        cells: columns.map((c) => DataCell(
          Text(c.extract(item)),
          onTap: onRowTap != null ? () => onRowTap!(item) : null,
        )).toList(),
      )).toList(),
    );
  }
}
```

**Usage** at call sites:

```dart
AppTypedDataTable<PatientListItem>(
  columns: [
    AppDataColumn(label: 'Name', extract: (p) => p.fullName),
    AppDataColumn(label: 'Phone', extract: (p) => p.phone ?? ''),
    AppDataColumn(label: 'DOB', extract: (p) => formatDate(p.dateOfBirth)),
  ],
  rows: patients,
  onRowTap: (p) => context.nav.goPatientDetail(p.id),
)
```

Keep the old `AppDataTable` temporarily and deprecate it. Migrate each table to the typed version incrementally.

**Verification**: All existing tables render identically. Compile-time errors catch any column/data mismatches.

**Risk**: Low — additive change. Old widget can coexist during migration.

---

### 4.5 Prepare for internationalization (i18n)

**Problem**: All strings hardcoded in English across 100+ files.

**Fix** (phased approach):

**Phase 1 — Set up infrastructure** (do now):

```yaml
# pubspec.yaml
dependencies:
  flutter_localizations:
    sdk: flutter
  intl: any

flutter:
  generate: true
```

Create `l10n.yaml`:
```yaml
arb-dir: lib/l10n
template-arb-file: app_en.arb
output-localization-file: app_localizations.dart
```

Create `lib/l10n/app_en.arb` with initial strings:
```json
{
  "@@locale": "en",
  "appTitle": "AiClinic",
  "patients": "Patients",
  "settings": "Settings",
  "signOut": "Sign out"
}
```

**Phase 2 — Migrate strings** (incremental, per-feature):
- Start with shared/core strings (nav labels, button labels, common actions)
- Then migrate feature-by-feature: auth → patients → settings

**Phase 3 — Add additional locales** (when needed):
- Create `app_ar.arb`, `app_tr.arb`, etc.

**Verification**: App renders identically in English after migration. `flutter gen-l10n` generates without errors.

**Risk**: Low for infrastructure setup. String migration is high-effort but low-risk (no behavior change).

---

### 4.6 Enforce `PermissionKeys` constants everywhere

**Problem**: Raw string literals for permission checks alongside `PermissionKeys` constants. Typos fail silently.

**Fix**:

**Step 1**: Add a lint rule or project convention enforcing `PermissionKeys` usage. Add a comment at the top of `permission_keys.dart`:

```dart
/// All permission checks MUST use constants from this class.
/// Direct string literals for permission keys are prohibited.
abstract final class PermissionKeys {
  // ...
}
```

**Step 2**: Search for all raw permission string usage and replace:

```dart
// BEFORE
auth.context!.permissions.contains('settings.manage_branches');

// AFTER
auth.context!.permissions.contains(PermissionKeys.manageBranches);
```

**Step 3**: Consider making `PermissionService` the only entry point for permission checks, so raw `permissions.contains()` calls are never needed:

```dart
// Instead of checking the set directly:
if (permissions.canManageBranches()) { ... }
```

**Verification**: Search the codebase for string literals matching `'.*\\..*'` in permission-checking contexts. All should use `PermissionKeys` constants.

**Risk**: None — pure refactor to compile-time safety.

---

### 4.7 Break up `AuthSessionNotifier` god class

**File**: `lib/shared/providers/auth_session_provider.dart` (350+ lines)

**Problem**: Single notifier manages Supabase init, auth streaming, session context, idle timeout, branch selection, and sign-out. Note: This file deliberately uses repositories directly rather than use cases (as per the clean architecture migration exception — it is infrastructure-level code).

**Fix**: Decompose into focused notifiers.

```
lib/shared/providers/
├── auth_lifecycle_notifier.dart     # Supabase init, auth state stream, sign-in/sign-out
├── session_context_loader.dart      # JWT decode, staff_members query, permission load
├── branch_selection_notifier.dart   # Active branch selection, persistence
├── idle_timeout_notifier.dart       # Idle timeout wiring, countdown
└── auth_session_provider.dart       # Thin facade that composes the above
```

**Step 1**: Extract `SessionContextLoader`:

```dart
class SessionContextLoader {
  SessionContextLoader(this._client);
  final SupabaseClient _client;

  Future<AuthSessionContext> loadContext(String userId, Map<String, dynamic> claims) async {
    // JWT decode, staff query, permission load
    // Moved from AuthSessionNotifier._loadSessionContext
  }
}
```

**Step 2**: Extract `BranchSelectionNotifier`:

```dart
class BranchSelectionNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void selectBranch(String branchId) { state = branchId; }
  void clearBranch() { state = null; }
}
```

**Step 3**: `AuthSessionNotifier` becomes a thin coordinator:

```dart
class AuthSessionNotifier extends Notifier<AuthSessionState> {
  @override
  AuthSessionState build() {
    // Wire auth stream from lifecycle
    // Delegate context loading to SessionContextLoader
    // Delegate branch selection to BranchSelectionNotifier
  }
}
```

**Verification**: All auth-related tests pass. Sign-in, sign-out, branch selection, idle timeout, and session refresh work correctly.

**Risk**: High — this is a significant refactor of core infrastructure. Do incrementally, extracting one concern at a time.

---

### 4.8 Create pagination abstraction

**Problem**: Manual pagination in `PatientListNotifier`; other lists will need it too.

**Fix**: Create a reusable pagination mixin or base class.

```dart
// lib/core/data/paginated_list_notifier.dart

abstract class PaginatedListNotifier<T> extends AsyncNotifier<PaginatedList<T>> {
  int get pageSize => 20;

  Future<PaginatedPage<T>> fetchPage(int offset, int limit);

  @override
  Future<PaginatedList<T>> build() async {
    final page = await fetchPage(0, pageSize);
    return PaginatedList(
      items: page.items,
      hasMore: page.items.length >= pageSize,
      offset: page.items.length,
    );
  }

  Future<void> loadMore() async {
    final current = state.valueOrNull;
    if (current == null || !current.hasMore) return;

    state = AsyncData(current.copyWith(isLoadingMore: true));
    final page = await fetchPage(current.offset, pageSize);
    state = AsyncData(PaginatedList(
      items: [...current.items, ...page.items],
      hasMore: page.items.length >= pageSize,
      offset: current.offset + page.items.length,
    ));
  }
}

class PaginatedList<T> {
  const PaginatedList({
    required this.items,
    required this.hasMore,
    required this.offset,
    this.isLoadingMore = false,
  });
  final List<T> items;
  final bool hasMore;
  final int offset;
  final bool isLoadingMore;
}
```

**Usage**:

```dart
class PatientListNotifier extends PaginatedListNotifier<PatientListItem> {
  @override
  Future<PaginatedPage<PatientListItem>> fetchPage(int offset, int limit) {
    return ref.read(searchPatientsUseCaseProvider)(
      query: _currentQuery,
      scope: _currentScope,
      branchId: _activeBranchId,
      limit: limit,
      offset: offset,
    );
  }
}
```

**Verification**: Patient list pagination works identically. New lists (staff, branches) can adopt the abstraction when they need pagination.

**Risk**: Low — additive abstraction. Existing `PatientListNotifier` can be migrated as proof of concept.

---

## 5. Security Concerns

### 5.1 Protect deployment profile from accidental commit

**File**: `web/deployment-profile.json`

**Problem**: Local dev key is committed. Production profiles could be accidentally committed too.

**Fix**:

**Step 1**: Add to root `.gitignore`:

```gitignore
# Deployment profiles (templates only — never commit real credentials)
**/deployment-profile.json
!web/deployment-profile.example.json
```

**Step 2**: Rename the existing file to `deployment-profile.example.json`:

```bash
git mv web/deployment-profile.json web/deployment-profile.example.json
```

**Step 3**: Update `deployment_profile_store_web.dart` and any loading logic to look for `deployment-profile.json` (the non-example version), and document in the README that developers should copy the example file.

**Step 4**: Add a startup check that warns if the profile is missing and points to the example file.

**Verification**: `git status` should not show `deployment-profile.json` as tracked. New clones should have clear instructions for setting up the profile.

**Risk**: Low — requires updating developer setup docs.

---

### 5.2 Tighten dev button guards beyond `kDebugMode`

**Files**: `dev_fill_dummy_clinic_button.dart`, `dev_reset_clinic_button.dart`, `dev_quick_admin_sign_in_button.dart`, `dev_seed_patients_button.dart`

**Problem**: Profile builds still include dev buttons.

**Fix**: Add a secondary guard using a compile-time flag or environment variable.

```dart
// Option A: Compile-time constant
const bool kEnableDevTools = bool.fromEnvironment('ENABLE_DEV_TOOLS');

// In widgets:
if (!kDebugMode && !kEnableDevTools) {
  return const SizedBox.shrink();
}

// Production/profile builds without the flag will never show dev tools.
// Dev builds explicitly opt in: flutter run --dart-define=ENABLE_DEV_TOOLS=true
```

**Alternative (Option B)**: Use conditional imports so dev widgets are never in the release import graph:

```dart
// lib/features/auth/presentation/widgets/dev_tools.dart
export 'dev_tools_stub.dart'
  if (dart.library.developer) 'dev_tools_impl.dart';
```

**Verification**: Run `flutter build windows --profile` and verify dev buttons are not visible.

**Risk**: Low — additive guard.

---

### 5.3 Remove hard-coded dev credentials from source

**File**: `lib/features/auth/presentation/widgets/dev_quick_admin_sign_in_button.dart:13-14`

**Problem**: `admin` / `admin` credentials in source code.

**Fix**: Move to environment/compile-time configuration.

```dart
// BEFORE
const kDevAdminUsername = 'admin';
const kDevAdminPassword = 'admin';

// AFTER
const kDevAdminUsername = String.fromEnvironment(
  'DEV_ADMIN_USER',
  defaultValue: '',
);
const kDevAdminPassword = String.fromEnvironment(
  'DEV_ADMIN_PASS',
  defaultValue: '',
);

// Usage: flutter run --dart-define=DEV_ADMIN_USER=admin --dart-define=DEV_ADMIN_PASS=admin
```

Update the widget to show a disabled state when credentials are not configured.

**Verification**: Dev sign-in works when `--dart-define` flags are passed. Without flags, the button is disabled or hidden.

**Risk**: Low — only affects developer workflow. Document in README.

---

### 5.4 Add JWT expiry validation for client-side claims

**File**: `lib/core/config/supabase_config.dart:147-162`

**Problem**: JWT payload is decoded without checking `exp`, so expired tokens could display stale permissions in the UI.

**Fix**: Add expiry check after decoding.

```dart
static Map<String, dynamic> decodeAccessTokenClaims(String token) {
  try {
    final parts = token.split('.');
    if (parts.length != 3) return {};

    final payload = parts[1];
    final normalized = base64Url.normalize(payload);
    final decoded = utf8.decode(base64Url.decode(normalized));
    final claims = jsonDecode(decoded) as Map<String, dynamic>;

    // Validate expiry
    final exp = claims['exp'] as int?;
    if (exp != null) {
      final expiryDate = DateTime.fromMillisecondsSinceEpoch(exp * 1000);
      if (expiryDate.isBefore(DateTime.now())) {
        AppLog.warning('supabase.jwt.expired exp=$expiryDate');
        return {}; // or throw, depending on desired behavior
      }
    }

    return claims;
  } catch (e) {
    AppLog.warning('supabase.jwt.decode_failed error=$e');
    return {};
  }
}
```

**Note**: Signature validation is intentionally not added client-side — the server handles that. This fix only prevents using obviously expired claims for UI decisions.

**Verification**: Create a test with an expired JWT token and verify `decodeAccessTokenClaims` returns empty map. Test with a valid token and verify claims are returned.

**Risk**: Low — adding a simple timestamp check. Ensure the Supabase SDK's own token refresh cycle handles expiry before this code path is hit.

---

### 5.5 Expand `AppLog` redaction for PHI

**File**: `lib/core/logging/app_log.dart`

**Problem**: Patient names, phone numbers, and dates of birth are not redacted.

**Fix**: Add PHI-aware redaction patterns.

```dart
static final _redactionPatterns = [
  // Existing patterns...
  MapEntry(RegExp(r'password[=:]\s*\S+', caseSensitive: false), 'password=***'),
  MapEntry(RegExp(r'Bearer\s+\S+'), 'Bearer ***'),
  MapEntry(RegExp(r'eyJ[A-Za-z0-9_-]+\.eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+'), '***JWT***'),
  MapEntry(RegExp(r'[\w.+-]+@[\w-]+\.[\w.]+'), '***@***.***'),

  // PHI patterns
  MapEntry(RegExp(r'p_full_name[=:]\s*\S+'), 'p_full_name=***'),
  MapEntry(RegExp(r'p_phone[=:]\s*[\d+\-\s]+'), 'p_phone=***'),
  MapEntry(RegExp(r'p_date_of_birth[=:]\s*\d{4}-\d{2}-\d{2}'), 'p_date_of_birth=***'),
  MapEntry(RegExp(r'p_national_id[=:]\s*\S+'), 'p_national_id=***'),
];
```

**Alternative (broader approach)**: Instead of pattern-matching field names, ensure that repository logging only logs parameter keys, never values. Add a lint comment or code review checklist item.

**Verification**: Add unit tests that pass strings containing patient data through `_format` and verify redaction. Review all `AppLog` call sites in repositories to confirm no values are logged.

**Risk**: Low — additive patterns. False positive redaction is acceptable (over-redacting is safer than under-redacting for PHI).

---

## 6. UI/UX Issues

### 6.1 Add loading skeletons for list pages

**Problem**: Bare `CircularProgressIndicator` during loading.

**Fix**: Create a reusable skeleton widget and use it in list pages.

**Step 1**: Add `shimmer` package or create a simple skeleton:

```yaml
# pubspec.yaml
dependencies:
  shimmer: ^3.0.0
```

**Step 2**: Create `lib/core/widgets/skeleton_list.dart`:

```dart
class SkeletonList extends StatelessWidget {
  const SkeletonList({this.itemCount = 8, super.key});
  final int itemCount;

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: Colors.grey[300]!,
      highlightColor: Colors.grey[100]!,
      child: ListView.builder(
        itemCount: itemCount,
        itemBuilder: (_, __) => const _SkeletonRow(),
      ),
    );
  }
}

class _SkeletonRow extends StatelessWidget {
  const _SkeletonRow();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Container(width: 40, height: 40, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(width: double.infinity, height: 14, color: Colors.white),
                const SizedBox(height: 6),
                Container(width: 150, height: 12, color: Colors.white),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
```

**Step 3**: Replace `CircularProgressIndicator` in list pages:

```dart
// BEFORE
loading: () => const Center(child: CircularProgressIndicator()),

// AFTER
loading: () => const SkeletonList(),
```

**Verification**: Navigate to patient/staff/branch lists and verify skeleton appears during loading. Verify it transitions smoothly to actual data.

**Risk**: None — cosmetic improvement.

---

### 6.2 Map raw exceptions to user-friendly messages

**Files**: `patient_edit_page.dart:181`, `patient_registration_page.dart:163`

**Problem**: `error.toString()` shown directly to users.

**Fix**: Create an error mapping utility and use it in all form pages.

**Step 1**: Create `lib/core/utils/user_error_mapper.dart`:

```dart
class UserErrorMapper {
  /// Maps a caught error to a user-friendly message.
  static String mapToUserMessage(Object error) {
    if (error is RpcFailure) {
      return _mapRpcFailure(error);
    }
    if (error is SocketException) {
      return 'Unable to connect to the server. Please check your network connection.';
    }
    if (error is TimeoutException) {
      return 'The operation timed out. Please try again.';
    }
    if (error is FormatException) {
      return 'Invalid data format. Please check your input and try again.';
    }

    // Generic fallback — never show raw exception
    AppLog.warning('unhandled_error type=${error.runtimeType} error=$error');
    return 'An unexpected error occurred. Please try again or contact support.';
  }

  static String _mapRpcFailure(RpcFailure failure) {
    // Use existing message maps (patientMessageForRpc, etc.)
    return failure.message;
  }
}
```

**Step 2**: Replace raw `error.toString()` in form pages:

```dart
// BEFORE
_formError = error.toString();

// AFTER
_formError = UserErrorMapper.mapToUserMessage(error);
```

**Verification**: Trigger various error conditions (network down, validation failure, stale update) and verify user-friendly messages appear. Verify the raw exception is still logged for debugging.

**Risk**: None — improves UX without changing logic.

---

### 6.3 Gate `PermissionDemoPanel` behind `kDebugMode`

**File**: `lib/features/auth/presentation/pages/auth_shell_page.dart:115`

**Problem**: Demo panel always visible on home page.

**Fix**:

```dart
// BEFORE
const PermissionDemoPanel(),

// AFTER
if (kDebugMode) const PermissionDemoPanel(),
```

**Verification**: Run in release mode and confirm the panel is gone. Run in debug mode and confirm it still appears.

**Risk**: None — one-line change.

---

### 6.4 Add unsaved changes confirmation dialog

**Problem**: No "discard changes?" dialog when navigating away from forms.

**Fix**: Use Flutter's `WillPopScope` (or `PopScope` in newer Flutter) to intercept back navigation.

**Step 1**: Create a reusable mixin or wrapper:

```dart
// lib/core/widgets/unsaved_changes_guard.dart

class UnsavedChangesGuard extends StatelessWidget {
  const UnsavedChangesGuard({
    required this.hasUnsavedChanges,
    required this.child,
    super.key,
  });

  final bool hasUnsavedChanges;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !hasUnsavedChanges,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final shouldDiscard = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Discard changes?'),
            content: const Text(
              'You have unsaved changes. Are you sure you want to leave?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Keep editing'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Discard'),
              ),
            ],
          ),
        );
        if (shouldDiscard == true && context.mounted) {
          Navigator.pop(context);
        }
      },
      child: child,
    );
  }
}
```

**Step 2**: Wrap form pages with the guard:

```dart
// In patient_registration_page.dart and patient_edit_page.dart
@override
Widget build(BuildContext context) {
  return UnsavedChangesGuard(
    hasUnsavedChanges: _hasChanges(),
    child: Scaffold(
      // ... existing form
    ),
  );
}

bool _hasChanges() {
  return _fullNameController.text.isNotEmpty ||
         _phoneController.text.isNotEmpty ||
         _selectedDob != null;
  // Compare against initial values for edit page
}
```

**Verification**: Fill out a form partially, press back — confirm dialog appears. Press "Keep editing" — stay on form. Press "Discard" — navigate away. Submit form — no dialog on success navigation.

**Risk**: Low — ensure `PopScope` works correctly with GoRouter's navigation model.

---

### 6.5 Improve date of birth picker for desktop

**Problem**: Calendar picker is cumbersome for entering dates decades in the past.

**Fix**: Use a text input field with format validation, with the calendar picker as an optional secondary input.

```dart
// Create a DateOfBirthField widget
class DateOfBirthField extends StatelessWidget {
  const DateOfBirthField({
    required this.controller,
    required this.onDateSelected,
    this.selectedDate,
    super.key,
  });

  final TextEditingController controller;
  final ValueChanged<DateTime?> onDateSelected;
  final DateTime? selectedDate;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: 'Date of Birth',
        hintText: 'YYYY-MM-DD',
        suffixIcon: IconButton(
          icon: const Icon(Icons.calendar_today),
          onPressed: () => _showCalendar(context),
        ),
      ),
      keyboardType: TextInputType.datetime,
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[\d-]')),
        LengthLimitingTextInputFormatter(10),
      ],
      validator: _validateDate,
      onChanged: (value) {
        final parsed = DateTime.tryParse(value);
        if (parsed != null) onDateSelected(parsed);
      },
    );
  }

  String? _validateDate(String? value) {
    if (value == null || value.isEmpty) return 'Date of birth is required';
    final parsed = DateTime.tryParse(value);
    if (parsed == null) return 'Enter date as YYYY-MM-DD';
    if (parsed.isAfter(DateTime.now())) return 'Date cannot be in the future';
    return null;
  }

  Future<void> _showCalendar(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: selectedDate ?? DateTime.now().subtract(const Duration(days: 365 * 30)),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
      initialDatePickerMode: DatePickerMode.year, // Start in year selection
    );
    if (picked != null) {
      controller.text = formatDate(picked);
      onDateSelected(picked);
    }
  }
}
```

**Key improvement**: `initialDatePickerMode: DatePickerMode.year` opens the calendar in year-selection mode first, making it much faster to navigate to distant years.

**Verification**: Enter DOB by typing `1945-03-15` — verify it's accepted. Use the calendar icon — verify year picker opens first. Verify validation rejects invalid formats and future dates.

**Risk**: Low — existing validation logic preserved.

---

### 6.6 Increase search debounce to 500ms

**File**: `lib/features/patients/presentation/widgets/patient_search_field.dart:33`

**Problem**: 300ms debounce fires too frequently on slow LAN connections.

**Fix**:

```dart
// BEFORE
_debounce = Timer(const Duration(milliseconds: 300), () { ... });

// AFTER
_debounce = Timer(const Duration(milliseconds: 500), () { ... });
```

Also fix the inconsistency where `onChanged` uses raw `_controller.text` but `onSubmitted` uses trimmed text:

```dart
// In the debounce callback:
_debounce = Timer(const Duration(milliseconds: 500), () {
  onSearch(_controller.text.trim()); // trim consistently
});
```

**Verification**: Type in the search field and verify requests don't fire on every keystroke. Verify that pressing Enter still triggers immediate search. Test on a slow connection to confirm reduced request volume.

**Risk**: None — minor timing adjustment.

---

## 7. Testing & Maintainability

### 7.1 Encapsulate `SupabaseBootstrap` static state

**File**: `lib/core/config/supabase_config.dart`

**Problem**: Static mutable state causes test pollution.

**Fix**: Wrap initialization in a provider or injectable service.

**Step 1**: Create `lib/core/config/supabase_initializer.dart`:

```dart
class SupabaseInitializer {
  bool _initialized = false;
  Future<void>? _pendingInitialization;

  Future<void> initialize(DeploymentProfile profile) async {
    if (_initialized) return;
    if (_pendingInitialization != null) {
      await _pendingInitialization;
      return;
    }
    _pendingInitialization = _doInitialize(profile);
    await _pendingInitialization;
    _initialized = true;
  }

  Future<void> _doInitialize(DeploymentProfile profile) async {
    await Supabase.initialize(
      url: profile.supabaseUrl.toString(),
      anonKey: profile.supabaseAnonKey,
    );
  }

  void reset() {
    _initialized = false;
    _pendingInitialization = null;
  }
}
```

**Step 2**: Expose via Riverpod provider:

```dart
final supabaseInitializerProvider = Provider<SupabaseInitializer>((ref) {
  return SupabaseInitializer();
});
```

**Step 3**: In tests, override the provider instead of calling `debugResetForTests()`:

```dart
final container = ProviderContainer(
  overrides: [
    supabaseInitializerProvider.overrideWithValue(FakeSupabaseInitializer()),
  ],
);
```

**Verification**: All existing tests pass without calling `debugResetForTests()`. Tests can run in parallel without polluting each other's state.

**Risk**: Medium — requires updating all test files that interact with Supabase initialization.

---

### 7.2 Decompose `AuthSessionNotifier`

See [4.7 — Break up `AuthSessionNotifier` god class](#47-break-up-authsessionnotifier-god-class) for the detailed plan.

This is the same fix addressed in the Future Extension Risks section. The decomposition improves both testability and extensibility.

---

### 7.3 Create shared test helpers for patients and settings

**Problem**: No test utilities for patient or settings widget tests.

**Fix**: Create test support files mirroring the existing auth test support.

**Step 1**: Create `test/testing/patient_test_support.dart`:

```dart
/// Creates a ProviderContainer with a fake patient repository.
/// FakePatientRepository implements the abstract PatientRepository interface.
ProviderContainer createPatientTestContainer({
  List<PatientListItem> patients = const [],
  PatientDetail? patientDetail,
}) {
  return ProviderContainer(
    overrides: [
      patientRepositoryProvider.overrideWithValue(
        FakePatientRepository(
          patients: patients,
          detail: patientDetail,
        ),
      ),
      authSessionProvider.overrideWith(() => FakeAuthSessionNotifier()),
    ],
  );
}

/// Standard test patient for consistent test data.
PatientListItem get testPatient => PatientListItem(
  id: 'test-patient-id',
  fullName: 'Test Patient',
  phone: '+1234567890',
  dateOfBirth: DateTime(1990, 1, 15),
  gender: PatientGender.male,
  branchId: 'test-branch-id',
  branchName: 'Test Branch',
  isArchived: false,
);
```

**Step 2**: Create `test/testing/settings_test_support.dart` with similar helpers for branch and staff testing.

**Step 3**: Create `test/testing/widget_test_utils.dart` for common widget test wrappers:

```dart
Widget wrapWithProviders(Widget child, {List<Override> overrides = const []}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp.router(
      routerConfig: testRouter,
      child: child,
    ),
  );
}
```

**Verification**: Refactor one existing widget test to use the new helpers and verify it passes.

**Risk**: None — additive test infrastructure.

---

### 7.4 Isolate debug-only code from production imports

**Problem**: Dev widgets are imported in production code paths.

**Fix**: Use conditional imports to keep dev code out of the release import graph.

**Step 1**: Create a `dev_tools` barrel with conditional export:

```dart
// lib/features/auth/presentation/widgets/dev_tools.dart
export 'dev_tools_release.dart'
  if (dart.library.developer) 'dev_tools_debug.dart';

// lib/features/auth/presentation/widgets/dev_tools_release.dart
class DevFillDummyClinicButton extends SizedBox { const DevFillDummyClinicButton({super.key}); }
class DevResetClinicButton extends SizedBox { const DevResetClinicButton({super.key}); }
class DevQuickAdminSignInButton extends SizedBox { const DevQuickAdminSignInButton({super.key}); }
class DevSeedPatientsButton extends SizedBox { const DevSeedPatientsButton({super.key}); }

// lib/features/auth/presentation/widgets/dev_tools_debug.dart
export 'dev_fill_dummy_clinic_button.dart';
export 'dev_reset_clinic_button.dart';
export 'dev_quick_admin_sign_in_button.dart';
export 'dev_seed_patients_button.dart';
```

**Step 2**: Update `AuthShellPage` to import from the conditional barrel:

```dart
import 'package:ai_clinic/features/auth/presentation/widgets/dev_tools.dart';
```

**Alternative (simpler)**: If conditional imports are too complex, just move all dev widgets behind `kDebugMode` checks at both the import and render level, and document the convention. The tree-shaker will handle dead code elimination in release builds.

**Verification**: Build in release mode and verify dev widgets are tree-shaken out (check binary size or use `--analyze-size`).

**Risk**: Low — the conditional import approach is standard Dart.

---

## Implementation Priority & Ordering

### Phase 1 — Immediate (Critical bugs, 1-2 days)

| # | Issue | Effort | Risk |
|---|-------|--------|------|
| 1.1 | Web deployment profile path | 5 min | None |
| 1.2 | Snackbar error message display | 30 min | Low |
| 1.3 | PatientEditPage build() side effects | 1 hr | Low |
| 1.4 | Optimistic lock fallback | 15 min | None |
| 2.2 | Dead code in _contextFailureReason | 5 min | None |
| 2.3 | Dead branch_names parsing | 10 min | None |
| 6.3 | Gate PermissionDemoPanel | 5 min | None |
| 6.6 | Search debounce increase | 5 min | None |

### Phase 2 — High Priority (1 week)

| # | Issue | Effort | Risk |
|---|-------|--------|------|
| 2.4 | Standardize PermissionService provider | 2 hr | Low |
| 2.5 | Fix searchable dropdown pointer-down | 2 hr | Medium |
| 2.6 | Extract date formatting utility | 1 hr | None |
| 3.1 | Unify RPC invocation mixin | 4 hr | Medium |
| 4.6 | Enforce PermissionKeys constants | 2 hr | None |
| 5.1 | Protect deployment profile | 1 hr | Low |
| 6.2 | User-friendly error messages | 2 hr | None |

### Phase 3 — Medium Priority (2-3 weeks)

| # | Issue | Effort | Risk |
|---|-------|--------|------|
| 2.1 | Sentinel-based copyWith | 1 day | Medium |
| 3.4 | Standardize state management | 2 days | Medium |
| ~~3.5~~ | ~~Repository interface abstractions~~ | ~~1 day~~ | ~~COMPLETED~~ |
| 3.6 | Abstract navigation | 1 day | Low |
| 4.4 | Typed data table | 1 day | Low |
| 4.8 | Pagination abstraction | 1 day | Low |
| 5.2 | Tighten dev button guards | 2 hr | Low |
| 5.3 | Remove hard-coded dev credentials | 1 hr | Low |
| 5.4 | JWT expiry validation | 1 hr | Low |
| 5.5 | PHI log redaction | 2 hr | Low |
| 6.1 | Loading skeletons | 4 hr | None |
| 6.4 | Unsaved changes dialog | 4 hr | Low |
| 6.5 | Date picker improvement | 3 hr | Low |

### Phase 4 — Long-term (future sprints)

| # | Issue | Effort | Risk |
|---|-------|--------|------|
| 3.2 | ShellRoute for authenticated layout | 3 days | High |
| 3.3 | Eliminate cross-feature imports | 2 days | Medium |
| 4.1 | DeploymentMode future modes | 30 min | None |
| 4.2 | Offline/cache strategy | 2+ weeks | High |
| 4.3 | Extend PatientGender enum | 1 day | Medium |
| 4.5 | Internationalization setup | 1 week+ | Low |
| 4.7 / 7.2 | AuthSessionNotifier decomposition | 3 days | High |
| 7.1 | SupabaseBootstrap static state | 1 day | Medium |
| 7.3 | Shared test helpers | 1 day | None |
| 7.4 | Isolate debug code imports | 4 hr | Low |

---

## Summary

| Phase | Issues | Total Effort | Goal |
|-------|--------|-------------|------|
| Phase 1 | 8 | 1-2 days | Fix all critical bugs and trivial fixes |
| Phase 2 | 7 | ~1 week | Consolidate patterns and fix high-priority smells |
| Phase 3 | 12 (was 13; 3.5 completed) | 2-3 weeks | Architectural improvements and security hardening |
| Phase 4 | 10 | 4+ weeks | Long-term scalability and infrastructure |

> **Note**: Issue 3.5 (Repository interface abstractions) was completed as part of the clean architecture migration, which introduced abstract interfaces in `domain/repositories/`, use cases in `domain/usecases/`, and renamed concrete implementations to `*Impl`. See `CLEAN_ARCHITECTURE_MIGRATION_PLAN.md` for details.

Each fix includes the exact file(s), before/after code, verification steps, and risk assessment. Fixes within each phase can generally be done in parallel by different developers, with the exception of dependencies noted in the descriptions (e.g., 3.1 before 3.2, 3.2 before 3.3).

---

---

# Second Review Cycle — Fix Plan

**Date**: 2026-05-24
**Based on**: `frontend/FRONTEND_CODE_REVIEW.md` — Sections 9–11 (Cycle 2 findings)

---

## 9. Critical Bugs (Cycle 2)

### 9.1 Remove `Expanded` from `DataColumn.label` in `AppDataTable`

**File**: `lib/core/widgets/app_data_table.dart:56`

**Problem**: `Expanded` requires a `Flex` parent (`Row`/`Column`). `DataColumn.label` is placed inside a `Table`/`TableCell`, not a flex context. Triggers "Incorrect use of ParentDataWidget" in debug and layout failures in release.

**Fix**:

```dart
// BEFORE
DataColumn(
  numeric: column.numeric,
  label: Expanded(child: Text(column.label, style: Theme.of(context).textTheme.labelLarge)),
),

// AFTER
DataColumn(
  numeric: column.numeric,
  label: Text(column.label, style: Theme.of(context).textTheme.labelLarge),
),
```

If column text needs to clip/wrap, use `Flexible` inside a `Row` label or set `overflow: TextOverflow.ellipsis` on the `Text` widget.

**Verification**: Run the app in debug mode and navigate to any table view (patients, staff, branches). Confirm no "Incorrect use of ParentDataWidget" assertion. Verify column headers render correctly.

**Risk**: None — removing an invalid parent widget.

---

### 9.2 Store and close `ref.listenManual` subscriptions in `dispose()`

**Files**: `lib/features/auth/presentation/pages/staff_create_page.dart:37-41`, `lib/features/settings/presentation/pages/staff_form_page.dart:42-49`

**Problem**: `listenManual()` returns a `ProviderSubscription` that must be closed in `dispose()`. Neither page stores or closes it, causing memory leaks and stale `setState` calls.

**Fix** (same pattern for both files):

```dart
// STEP 1: Add a field to hold the subscription
ProviderSubscription<List<String>>? _branchIdsSubscription;

// STEP 2: Store it in initState
@override
void initState() {
  super.initState();
  _branchIdsSubscription = ref.listenManual(
    authSessionProvider.select((s) => s.context?.branchIds ?? const <String>[]),
    (previous, next) => _onAssignableBranchIdsChanged(next),
    fireImmediately: true,
  );
}

// STEP 3: Close in dispose
@override
void dispose() {
  _branchIdsSubscription?.close();
  _usernameController.dispose();
  _fullNameController.dispose();
  _passwordController.dispose();
  super.dispose();
}
```

For `staff_form_page.dart`, the pattern is the same but the provider is `staffManagementBranchesProvider`:

```dart
ProviderSubscription<AsyncValue<List<BranchSummary>>>? _branchesSubscription;

@override
void initState() {
  super.initState();
  _branchesSubscription = ref.listenManual(staffManagementBranchesProvider, (previous, next) {
    next.whenData((branches) {
      if (!mounted) return;
      setState(() => _syncBranchSelection(branches.map((b) => b.id).toList()));
    });
  });
}

@override
void dispose() {
  _branchesSubscription?.close();
  // ... existing dispose logic
  super.dispose();
}
```

**Verification**: Open staff create page, navigate away, confirm no "setState called after dispose" assertion in debug console. Repeat for staff form page.

**Risk**: None — standard Riverpod lifecycle fix.

---

### 9.3 Guard bootstrap redirect with a one-shot flag

**File**: `lib/features/auth/presentation/pages/clinic_bootstrap_page.dart:111-118`

**Problem**: Every rebuild schedules another `context.go(AppRoutes.home)` via `addPostFrameCallback`, stacking redundant navigation calls.

**Fix**:

```dart
// STEP 1: Add a flag field
bool _redirectScheduled = false;

// STEP 2: Guard the redirect
if (session.isAuthenticated && auth != null && !auth.setupRequired) {
  if (!_redirectScheduled) {
    _redirectScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.go(AppRoutes.home);
    });
  }
  return const Scaffold(body: Center(child: CircularProgressIndicator()));
}
```

**Alternative**: Move the redirect to `ref.listen` (outside build) so it fires at most once per state change:

```dart
@override
Widget build(BuildContext context) {
  ref.listen<AuthSessionState>(authSessionProvider, (prev, next) {
    final ctx = next.context;
    if (next.isAuthenticated && ctx != null && !ctx.setupRequired) {
      context.go(AppRoutes.home);
    }
  });
  // ... rest of build without the redirect block
}
```

**Verification**: Complete bootstrap setup → confirm single navigation to home (no flicker or double-push). Watch debug console for "route pushed while navigating" warnings.

**Risk**: Low — the `ref.listen` approach is the standard Riverpod pattern for navigation side effects.

---

## 10. Non-Critical Bugs & Code Smells (Cycle 2)

### 10.1 Validate `branchId` is non-null when scope is `thisBranch`

**File**: `lib/features/patients/data/patient_repository.dart` (`PatientRepositoryImpl`)

**Problem**: `p_branch_id` is silently omitted when scope is `thisBranch` and `branchId` is null.

**Fix**: Add an explicit assertion:

```dart
// BEFORE
if (scope == PatientListScope.thisBranch && branchId != null) 'p_branch_id': branchId,

// AFTER — add a pre-flight check
Future<PatientSearchPage> searchPatients({
  String? query,
  required PatientListScope scope,
  String? branchId,
  int limit = 25,
  int offset = 0,
}) async {
  if (scope == PatientListScope.thisBranch && (branchId == null || branchId.trim().isEmpty)) {
    throw ArgumentError('branchId is required when scope is thisBranch');
  }

  final params = <String, dynamic>{
    'p_scope': scope.rpcScopeValue,
    'p_limit': limit,
    'p_offset': offset,
    if (query != null && query.trim().isNotEmpty) 'p_query': query.trim(),
    if (branchId != null && branchId.trim().isNotEmpty) 'p_branch_id': branchId,
  };
  // ...
}
```

**Verification**: Write a unit test calling `searchPatients(scope: thisBranch, branchId: null)` and assert it throws `ArgumentError`. Verify normal branch-scoped searches still work.

**Risk**: None — makes an implicit requirement explicit.

---

### 10.2 Normalize `updatePatient` return timestamp to UTC

**File**: `lib/features/patients/data/patient_repository.dart` (`PatientRepositoryImpl`)

**Problem**: `DateTime.tryParse` may produce local-zone for offset-less strings, creating timezone mismatch with the UTC `expectedUpdatedAt`.

**Fix**:

```dart
// BEFORE
final parsed = DateTime.tryParse(updatedAt);
if (parsed == null) {
  throw StateError('Patient updated_at could not be parsed: $updatedAt');
}
return parsed;

// AFTER
final parsed = DateTime.tryParse(updatedAt);
if (parsed == null) {
  throw StateError('Patient updated_at could not be parsed: $updatedAt');
}
return parsed.toUtc();
```

**Verification**: Update a patient and verify the returned `DateTime` is UTC. Verify subsequent edit→save cycles don't get stale-update conflicts due to timezone mismatch.

**Risk**: None — ensures consistent UTC representation throughout the optimistic locking chain.

---

### 10.3 UTC-normalize `parsePatientDate` for date-only values

**File**: `lib/features/patients/domain/patient_row_parsing.dart:2-18`

**Problem**: `DateTime(year, month, day)` creates local-zone midnight. UTC midnight input can shift the calendar date in negative UTC zones.

**Fix**:

```dart
// BEFORE
DateTime? parsePatientDate(Object? value) {
  if (value == null) return null;
  if (value is DateTime) {
    return DateTime(value.year, value.month, value.day);
  }
  final text = value.toString().trim();
  if (text.isEmpty) return null;
  final parsed = DateTime.tryParse(text);
  if (parsed == null) return null;
  return DateTime(parsed.year, parsed.month, parsed.day);
}

// AFTER — use UTC constructors for date-only values
DateTime? parsePatientDate(Object? value) {
  if (value == null) return null;
  if (value is DateTime) {
    return DateTime.utc(value.year, value.month, value.day);
  }
  final text = value.toString().trim();
  if (text.isEmpty) return null;
  final parsed = DateTime.tryParse(text);
  if (parsed == null) return null;
  return DateTime.utc(parsed.year, parsed.month, parsed.day);
}
```

**Verification**: Write a unit test with `DateTime.utc(2026, 5, 24, 0, 0)` and verify the returned date is `2026-05-24` regardless of local timezone. Verify patient detail page displays correct DOB.

**Risk**: Low — all date-only display code uses `value.year`/`value.month`/`value.day` which is the same for UTC datetimes. Search for any code that depends on the `DateTime` being local.

---

### 10.4 Fix `OrganizationProfile.hashCode` for `settingsJson`

**File**: `lib/features/settings/domain/organization_profile.dart:132-141`

**Problem**: `==` uses order-insensitive `mapEquals`, but `hashCode` uses order-dependent `Object.hashAll(entries)`.

**Fix**: Use a canonical, order-independent hash for the map:

```dart
// BEFORE
settingsJson == null ? null : Object.hashAll(settingsJson!.entries),

// AFTER
settingsJson == null ? null : Object.hashAllUnordered(
  settingsJson!.entries.map((e) => Object.hash(e.key, e.value)),
),
```

**Alternative**: Sort the entries before hashing:

```dart
settingsJson == null
    ? null
    : Object.hashAll(
        (settingsJson!.entries.toList()..sort((a, b) => a.key.compareTo(b.key)))
            .map((e) => Object.hash(e.key, e.value)),
      ),
```

**Verification**: Write a unit test with two `OrganizationProfile` instances whose `settingsJson` maps have the same entries in different insertion order. Assert `a == b` and `a.hashCode == b.hashCode`.

**Risk**: None — corrects a contract violation.

---

### 10.5 Add `is_deleted` filter to `PermissionRepositoryImpl`

**File**: `lib/features/auth/data/permission_repository.dart` (`PermissionRepositoryImpl`)

**Problem**: Missing `is_deleted: false` filter on permission query.

**Fix**:

```dart
// BEFORE
final rows = await _client
    .from('roles_permissions')
    .select('permission_key')
    .eq('role', role.wireValue)
    .eq('is_granted', true);

// AFTER
final rows = await _client
    .from('roles_permissions')
    .select('permission_key')
    .eq('role', role.wireValue)
    .eq('is_granted', true)
    .eq('is_deleted', false);
```

**Verification**: Soft-delete a permission row in the DB, then sign in with that role. Verify the permission is NOT loaded into the session context.

**Risk**: Low — additive filter. If the `is_deleted` column doesn't exist (schema mismatch), PostgREST will return an error that's visible at sign-in.

---

### 10.6 Clear `_ensureSupabaseReadyTask` on failure

**File**: `lib/shared/providers/auth_session_provider.dart:83-118`

**Problem**: Failed initialization future is cached forever, preventing retry.

**Fix**:

```dart
// BEFORE
Future<void> _ensureSupabaseReady(StartupSessionState startup) {
  return _ensureSupabaseReadyTask ??= _runEnsureSupabaseReady(startup);
}

// AFTER
Future<void> _ensureSupabaseReady(StartupSessionState startup) {
  return _ensureSupabaseReadyTask ??= _runEnsureSupabaseReady(startup).catchError((error) {
    _ensureSupabaseReadyTask = null;
    throw error;
  });
}
```

**Alternative (cleaner)**: Use a try/finally in `_runEnsureSupabaseReady`:

```dart
Future<void> _runEnsureSupabaseReady(StartupSessionState startup) async {
  try {
    // ... existing init logic ...
  } catch (error) {
    _ensureSupabaseReadyTask = null; // allow retry
    AppLog.warning('auth.session.bootstrap_failed reason=${error.runtimeType}');
    state = AuthSessionState(status: AuthSessionStatus.unauthenticated, failureMessage: error.toString());
  }
}
```

**Verification**: Simulate init failure (misconfigured profile URL), then fix the config. Verify the app retries initialization without requiring a restart.

**Risk**: Low — only affects the error recovery path. Success path is unchanged.

---

### 10.7 Load primary branch from DB instead of JWT claim order

**File**: `lib/shared/providers/auth_session_provider.dart:248-265`

**Problem**: `activeBranchId` defaults to `branchIds.first` from JWT, not the DB primary.

**Fix**: Query the primary branch from `staff_branch_assignments`:

```dart
// In _loadSessionContext, after loading branchIds from JWT:

String? primaryBranchId;
if (branchIds.isNotEmpty) {
  final primaryRow = await client
      .from('staff_branch_assignments')
      .select('branch_id')
      .eq('staff_member_id', staffMemberId)
      .eq('is_primary', true)
      .maybeSingle();
  primaryBranchId = primaryRow?['branch_id']?.toString();
  if (primaryBranchId == null || !branchIds.contains(primaryBranchId)) {
    primaryBranchId = branchIds.first;
  }
}
```

**Alternative (lower cost)**: If adding a DB query is too expensive for the session load path, document the limitation and ensure the JWT claim emits primary branch first in the DB function that builds the claim.

**Verification**: Create a staff member with 3 branch assignments, set the second one as primary. Sign in and verify the "this branch" scope targets the primary (second) branch, not the first.

**Risk**: Medium — adds a DB query to the session load path. Consider caching or batching with the existing `staff_members` query.

---

### 10.8 Retain loaded rows on `loadMore` failure

**File**: `lib/features/patients/presentation/providers/patient_list_notifier.dart:115-129`

**Problem**: `loadMore` error replaces the entire list state with `AsyncError`.

**Fix**: Keep the existing data and add an error indicator:

```dart
// STEP 1: Add a loadMoreError field to PatientListUiState
class PatientListUiState {
  const PatientListUiState({
    // ... existing fields ...
    this.loadMoreError,
  });

  final String? loadMoreError;

  // update copyWith accordingly
}

// STEP 2: In loadMore catch, retain the loaded data
} catch (error, stack) {
  state = AsyncData(current.copyWith(
    isLoadingMore: false,
    loadMoreError: error.toString(),
  ));
}
```

**Step 3**: In the patient list page, show the error at the bottom of the list with a "Retry" button instead of replacing the whole view.

**Verification**: Load a patient list, then simulate a network error on loadMore. Verify existing rows remain visible and an error/retry appears at the bottom.

**Risk**: Low — additive state field. UI needs a minor update to render the error.

---

### 10.9 Use typed error codes instead of substring matching for archived state

**File**: `lib/features/patients/presentation/pages/patient_detail_page.dart:152-181`

**Problem**: `message.contains('archived')` is brittle.

**Fix**: Check the error type rather than its string content:

```dart
// STEP 1: Define a typed exception for archived patients (in domain/)
class PatientArchivedException implements Exception {
  const PatientArchivedException(this.message);
  final String message;
  @override
  String toString() => message;
}

// STEP 2: In PatientRepositoryImpl.getPatient, throw the typed exception
final detail = PatientDetail.fromRow(result.data ?? {});
if (detail == null) {
  throw StateError('Patient profile was returned in an unexpected shape.');
}
if (detail.isArchived == true) {
  throw const PatientArchivedException('This patient has been archived.');
}

// STEP 3: In _PatientDetailError, check the type
class _PatientDetailError extends StatelessWidget {
  // ...
  @override
  Widget build(BuildContext context) {
    final isArchived = _isArchivedError;
    // ...
  }

  bool get _isArchivedError {
    // Check if the original error was PatientArchivedException
    // This depends on how the error propagates through AsyncValue
    return message.contains('PatientArchivedException') || message.contains('archived');
  }
}
```

**Alternative (simpler)**: Add a `PatientDetailError` sealed class that the provider maps RPC errors into:

```dart
sealed class PatientDetailError {
  const PatientDetailError();
}
class PatientArchivedError extends PatientDetailError { ... }
class PatientNotFoundError extends PatientDetailError { ... }
class PatientLoadError extends PatientDetailError { ... }
```

**Verification**: Archive a patient, navigate to their detail page. Verify the archived UI appears. Trigger a different error and verify it shows the generic error + retry UI.

**Risk**: Low — requires updating the error propagation path from provider to UI.

---

### 10.10 Add `context.mounted` guards to `ref.listen` callbacks

**Files**: `staff_password_reset_page.dart`, `idle_timeout_settings_page.dart`, `organization_settings_page.dart`, `branch_list_page.dart`

**Problem**: `setState` / `showDialog` called without checking `context.mounted`.

**Fix** (apply to all affected files):

```dart
// BEFORE
ref.listen<AsyncValue<IdleTimeoutSettingsState>>(idleTimeoutSettingsProvider, (previous, next) {
  final value = next.value;
  if (value?.saveMessage != null) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value!.saveMessage!)));
  }
});

// AFTER
ref.listen<AsyncValue<IdleTimeoutSettingsState>>(idleTimeoutSettingsProvider, (previous, next) {
  if (!context.mounted) return;
  final value = next.value;
  if (value?.saveMessage != null) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value!.saveMessage!)));
  }
});
```

Apply the same `if (!context.mounted) return;` guard to:
- `organization_settings_page.dart` snackbar listener
- `branch_list_page.dart` dialog listener
- `staff_password_reset_page.dart` setState listener

**Verification**: Navigate away from each page while an async operation is in flight. Confirm no "setState called after dispose" assertions in the debug console.

**Risk**: None — additive guard.

---

### 10.11 Compare `previous` in snackbar listeners to prevent duplicates

**Files**: `idle_timeout_settings_page.dart:35-40`, `organization_settings_page.dart:67-72`

**Problem**: Snackbar re-shows if the provider re-emits the same state.

**Fix**: Compare the save message from `previous` and `next`:

```dart
// BEFORE
ref.listen<AsyncValue<IdleTimeoutSettingsState>>(idleTimeoutSettingsProvider, (previous, next) {
  final value = next.value;
  if (value?.saveMessage != null) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value!.saveMessage!)));
  }
});

// AFTER
ref.listen<AsyncValue<IdleTimeoutSettingsState>>(idleTimeoutSettingsProvider, (previous, next) {
  if (!context.mounted) return;
  final prevMessage = previous?.value?.saveMessage;
  final nextMessage = next.value?.saveMessage;
  if (nextMessage != null && nextMessage != prevMessage) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(nextMessage)));
  }
});
```

Apply the same pattern to `organization_settings_page.dart`.

**Verification**: Save settings, verify snackbar appears once. Trigger a rebuild (resize window) and verify it doesn't re-appear.

**Risk**: None — additive comparison.

---

### 10.12 Replace `Flexible` with `ConstrainedBox` in duplicate candidates dialog

**File**: `lib/features/patients/presentation/widgets/duplicate_candidates_dialog.dart:33`

**Problem**: `Flexible` inside tight `Column` gets unbounded max height.

**Fix**:

```dart
// BEFORE
Flexible(
  child: ListView.separated(
    shrinkWrap: true,
    itemCount: candidates.length,
    separatorBuilder: (_, _) => const Divider(height: 1),
    itemBuilder: (context, index) => _CandidateTile(candidate: candidates[index]),
  ),
),

// AFTER
ConstrainedBox(
  constraints: const BoxConstraints(maxHeight: 300),
  child: ListView.separated(
    shrinkWrap: true,
    itemCount: candidates.length,
    separatorBuilder: (_, _) => const Divider(height: 1),
    itemBuilder: (context, index) => _CandidateTile(candidate: candidates[index]),
  ),
),
```

**Verification**: Trigger duplicate detection with 1, 5, and 20 candidates. Verify the dialog scrolls correctly and doesn't overflow or assert.

**Risk**: None — constrains the maximum height to a reasonable value.

---

### 10.13 Defensively handle nullable path parameters in router

**File**: `lib/app/router.dart:80`

**Problem**: `state.pathParameters['staffId']!` throws if the parameter is missing.

**Fix**:

```dart
// BEFORE
builder: (context, state) => StaffSettingsPasswordResetPage(staffId: state.pathParameters['staffId']!),

// AFTER
builder: (context, state) => StaffSettingsPasswordResetPage(staffId: state.pathParameters['staffId']),
```

Update `StaffSettingsPasswordResetPage` to accept `String?` and show an error state if null:

```dart
class StaffSettingsPasswordResetPage extends ConsumerWidget {
  const StaffSettingsPasswordResetPage({this.staffId, super.key});
  final String? staffId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (staffId == null || staffId!.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Reset password')),
        body: const Center(child: Text('Invalid staff member ID.')),
      );
    }
    // ... existing implementation
  }
}
```

**Verification**: Navigate to `/settings/staff//reset-password` (empty staffId) and verify a graceful error page instead of a crash.

**Risk**: None — defensive error handling.

---

### 10.14 Check `widget.enabled` in search debounce callback

**File**: `lib/features/patients/presentation/widgets/patient_search_field.dart:31-36`

**Problem**: Debounce timer fires `onSearch` even when `enabled` is false.

**Fix**:

```dart
// BEFORE
_debounce = Timer(const Duration(milliseconds: 300), () {
  if (!mounted) return;
  widget.onSearch(_controller.text);
});

// AFTER
_debounce = Timer(const Duration(milliseconds: 300), () {
  if (!mounted || !widget.enabled) return;
  widget.onSearch(_controller.text);
});
```

**Verification**: Set scope to "this branch" with no branch selected (field disabled). Type in the search field before disabling. Verify no RPC call fires after disable.

**Risk**: None — additive guard.

---

## 11. Low-Severity Fixes (Cycle 2)

### 11.1 Remove dead `AppColors.info`

**File**: `lib/app/theme/app_colors.dart`

Remove the unused `info` color constant.

**Risk**: None.

---

### 11.2 Cap `debugRecords` size

**File**: `lib/core/logging/app_log.dart`

```dart
static const _maxDebugRecords = 5000;

// In the log method:
if (kDebugMode) {
  debugRecords.add(record);
  if (debugRecords.length > _maxDebugRecords) {
    debugRecords.removeRange(0, debugRecords.length - _maxDebugRecords);
  }
}
```

**Risk**: None.

---

### 11.3 Use stable app directory for idle timeout settings (IO)

**File**: `lib/features/settings/data/idle_timeout_preferences_store_io.dart`

Replace `Directory.current` with `getApplicationSupportDirectory()` from `path_provider`:

```dart
Future<File> _settingsFile() async {
  final dir = await getApplicationSupportDirectory();
  return File('${dir.path}${Platform.pathSeparator}${IdleTimeoutPreferencesStore.fileName}');
}
```

**Risk**: Low — requires `path_provider` package (already commonly used in Flutter projects). Store methods become async.

---

### 11.4 Avoid mutation in `permission_matrix_view.dart` getter

**File**: `lib/features/settings/domain/permission_matrix_view.dart:53`

```dart
// BEFORE
permissionKeys: byCategory[category]!..sort(),

// AFTER
permissionKeys: (byCategory[category]!.toList()..sort()),
```

**Risk**: None.

---

### 11.5 Display-friendly `roleLabel` in `StaffMemberSummary`

**File**: `lib/features/auth/domain/staff_member_summary.dart`

```dart
// BEFORE
String get roleLabel => role.wireValue;

// AFTER
String get roleLabel => switch (role) {
  StaffRole.owner => 'Owner',
  StaffRole.administrator => 'Administrator',
  StaffRole.doctor => 'Doctor',
  StaffRole.receptionist => 'Receptionist',
  StaffRole.labStaff => 'Lab staff',
};
```

**Risk**: None — cosmetic fix.

---

### 11.6 Add retry action to patient list error state

**File**: `lib/features/patients/presentation/pages/patient_list_page.dart:82`

```dart
// BEFORE
error: (error, _) => Center(child: Text('Failed to load patients: $error')),

// AFTER
error: (error, _) => Center(
  child: Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text('Failed to load patients.', style: Theme.of(context).textTheme.bodyLarge),
      const SizedBox(height: 16),
      FilledButton(
        onPressed: () => ref.invalidate(patientListProvider),
        child: const Text('Retry'),
      ),
    ],
  ),
),
```

**Risk**: None.

---

### 11.7 Add tooltips to icon-only buttons

Search for `IconButton` across patient and settings pages. Add `tooltip` property where missing:

```dart
IconButton(
  icon: const Icon(Icons.arrow_back),
  tooltip: 'Go back',
  onPressed: () => _leavePatientDetail(context),
),
```

**Risk**: None.

---

### 11.8 Add registration page to barrel export

**File**: `lib/features/patients/presentation/pages/patient_pages.dart`

```dart
export 'patient_detail_page.dart';
export 'patient_edit_page.dart';
export 'patient_list_page.dart';
export 'patient_registration_page.dart'; // ADD
```

**Risk**: None.

---

### 11.9 Cancel stale reloads in `PatientListNotifier`

**File**: `lib/features/patients/presentation/providers/patient_list_notifier.dart`

Add a monotonic counter to ignore stale completions:

```dart
int _reloadGeneration = 0;

Future<void> reload({String? searchQuery}) async {
  _reloadGeneration++;
  final myGeneration = _reloadGeneration;
  // ...
  state = await AsyncValue.guard(() async {
    final result = await _fetchPage(offset: 0);
    if (_reloadGeneration != myGeneration) {
      throw StateError('stale');
    }
    return result;
  });
}
```

**Risk**: Low — standard stale-cancellation pattern.

---

## Updated Implementation Priority

### Phase 1+ — Immediate additions (Cycle 2 critical + trivial, 1 day)

| # | Issue | Effort | Risk |
|---|-------|--------|------|
| 9.1 | Remove `Expanded` from `DataColumn.label` | 5 min | None |
| 9.2 | Close `listenManual` subscriptions | 30 min | None |
| 9.3 | One-shot redirect flag in bootstrap page | 15 min | Low |
| 10.10 | Add `context.mounted` guards | 30 min | None |
| 10.11 | Compare `previous` in snackbar listeners | 15 min | None |
| 10.12 | Fix `Flexible` in duplicate dialog | 5 min | None |
| 10.13 | Defensive path parameter handling | 15 min | None |
| 10.14 | Check `enabled` in search debounce | 5 min | None |
| 11.1 | Remove dead `AppColors.info` | 2 min | None |
| 11.4 | Fix getter mutation in permission matrix | 5 min | None |

### Phase 2+ — High priority additions (Cycle 2 medium, 2-3 days)

| # | Issue | Effort | Risk |
|---|-------|--------|------|
| 10.1 | Validate branchId for thisBranch scope | 30 min | None |
| 10.2 | Normalize updatePatient timestamp to UTC | 15 min | None |
| 10.3 | UTC-normalize parsePatientDate | 30 min | Low |
| 10.4 | Fix OrganizationProfile hashCode | 30 min | None |
| 10.5 | Add is_deleted filter to PermissionRepositoryImpl | 15 min | Low |
| 10.6 | Clear cached init task on failure | 15 min | Low |
| 10.8 | Retain rows on loadMore failure | 2 hr | Low |
| 10.9 | Typed error codes for archived state | 2 hr | Low |
| 11.5 | Display-friendly roleLabel | 10 min | None |
| 11.6 | Add retry to patient list error | 15 min | None |
| 11.7 | Add tooltips to icon-only buttons | 30 min | None |
| 11.8 | Add registration to barrel export | 2 min | None |

### Phase 3+ — Medium priority additions (Cycle 2, 1 week)

| # | Issue | Effort | Risk |
|---|-------|--------|------|
| 10.7 | Load primary branch from DB | 2 hr | Medium |
| 11.2 | Cap debugRecords size | 15 min | None |
| 11.3 | Stable app directory for settings file | 1 hr | Low |
| 11.9 | Cancel stale reloads | 1 hr | Low |

---

## Combined Summary (Cycle 1 + Cycle 2)

| Phase | Issues (C1) | Issues (C2) | Total | Effort |
|-------|-------------|-------------|-------|--------|
| Phase 1 | 8 | 10 | 18 | 2-3 days |
| Phase 2 | 7 | 12 | 19 | ~2 weeks |
| Phase 3 | 12 (1 completed) | 4 | 16 | 3-4 weeks |
| Phase 4 | 10 | — | 10 | 4+ weeks |
| **Total** | **37 open + 1 completed** | **26** | **63 open** | — |

> **Architecture migration note**: The clean architecture migration resolved issue 3.5 (repository interface abstractions) and partially addressed 3.3 (cross-feature dependencies now reference abstract interfaces instead of concrete classes). Concrete repository classes have been renamed to `*Impl` (e.g., `PatientRepositoryImpl`), and notifiers now inject use cases instead of direct repository access.
