# Frontend Code Review — AiClinic (Flutter/Dart)

**Date**: 2026-05-24  
**Scope**: All 154 Dart source files under `frontend/lib/`  
**Stack**: Flutter 3.38+, Dart 3.11+, Riverpod 3.x, GoRouter 17.x, Supabase Flutter 2.x

---

## Table of Contents

1. [Critical Bugs](#1-critical-bugs)
2. [Non-Critical Bugs & Code Smells](#2-non-critical-bugs--code-smells)
3. [Architectural Issues](#3-architectural-issues)
4. [Future Extension Risks](#4-future-extension-risks)
5. [Security Concerns](#5-security-concerns)
6. [UI/UX Issues](#6-uiux-issues)
7. [Testing & Maintainability](#7-testing--maintainability)
8. [Positive Observations](#8-positive-observations)

---

## 1. Critical Bugs

### 1.1 Web deployment profile path string interpolation is broken

**File**: `lib/core/config/deployment_profile_store_web.dart:9`

```dart
String resolveDeploymentProfilePath() => 'web/$DeploymentProfileStore.fileName';
```

The `$` interpolation captures only `DeploymentProfileStore` (the class name) and treats `.fileName` as a literal suffix. The result is the string `"web/DeploymentProfileStore.fileName"` rather than `"web/deployment-profile.json"`.

**Fix**: Use braces: `'web/${DeploymentProfileStore.fileName}'`.

---

### 1.2 `SnackbarService.showFailure` hides the actual error message from the user

**File**: `lib/core/widgets/snackbar_service.dart:33-48`

```dart
static void showFailure(BuildContext context, AppFailure failure) {
  final semanticsLabel = '${failure.title}: ${failure.message}';
  // ...
  SnackBar(
    content: Semantics(label: semanticsLabel, child: Text(failure.title)),
    // ...
  );
}
```

Only `failure.title` (e.g., "Configuration required") is shown visually. The detailed `failure.message` (the actual explanation) is buried in the `Semantics` label, which is only accessible to screen readers. Users see a generic title with no actionable information.

**Fix**: Show both title and message, e.g., `Text('${failure.title}: ${failure.message}')` or use a two-line layout.

---

### 1.3 `PatientEditPage` runs side effects inside `build()`

**File**: `lib/features/patients/presentation/pages/patient_edit_page.dart:271-273`

```dart
data: (detail) {
  _populateFromDetail(detail);  // Side effect: sets controller text, mutates state
  return _buildForm(context, detail: detail, patientId: id);
},
```

`_populateFromDetail` sets `TextEditingController.text` and mutates instance fields during the `build` method. Although a guard (`_loadedPatientId == detail.id`) prevents repeated execution, this is a Flutter anti-pattern. If Riverpod rebuilds the widget with the same data, the guard works, but the approach is fragile if the data shape changes (e.g., adding an `updatedAt` version check).

**Fix**: Move population logic into a `ref.listen` callback or a `didChangeDependencies`-style hook so it runs outside the build phase.

---

### 1.4 Optimistic lock fallback silently bypasses concurrency protection

**File**: `lib/features/patients/presentation/pages/patient_edit_page.dart:86`

```dart
expectedUpdatedAt: _expectedUpdatedAt ?? DateTime.now().toUtc(),
```

If `_expectedUpdatedAt` is null, `_buildInput` falls back to `DateTime.now().toUtc()`. The `_submit` method has a null-guard that returns early, so this path is theoretically unreachable. However, `_buildInput` is a public-scope method that could be called from other contexts (tests, future refactors) and would silently bypass the `updated_at` optimistic lock. This defeats the stale-update protection that the spec explicitly requires.

**Fix**: Make `_expectedUpdatedAt` non-nullable by requiring it as a parameter, or throw `StateError` instead of falling back to `DateTime.now()`.

---

## 2. Non-Critical Bugs & Code Smells

### 2.1 `copyWith` methods cannot clear nullable fields back to `null`

**Files**: `patient_detail.dart`, `patient_list_item.dart`, `auth_session.dart`, `organization_profile.dart`, `branch_list_item.dart`, `staff_list_item.dart`

All domain model `copyWith` implementations use the standard `??` pattern:

```dart
PatientDetail copyWith({String? phone, ...}) {
  return PatientDetail(
    phone: phone ?? this.phone,  // Cannot clear phone to null
    ...
  );
}
```

Once a nullable field is set, it can never be cleared through `copyWith`. The `StartupSessionState.copyWith` already uses a correct sentinel-based pattern (`_noChange`) — but this pattern is not applied to any other model.

**Impact**: Medium. Will surface as bugs when features require clearing optional patient fields (e.g., removing a phone number or notes).

---

### 2.2 Redundant branches in `_contextFailureReason`

**File**: `lib/shared/providers/auth_session_provider.dart:186-201`

```dart
static String _contextFailureReason(Object error) {
  final message = error.toString().toLowerCase();
  if (message.contains('missing staff claims')) {
    if (message.contains('staff_role') || message.contains('staff claims')) {
      return 'missing_staff_claims';  // Always true: parent already matched 'staff claims'
    }
    return 'missing_staff_claims';
  }
  // ...
}
```

The inner `if` condition always evaluates to `true` because the outer `if` already matched `'missing staff claims'`, which contains `'staff claims'`. Both branches return the same string, making the entire nested conditional dead code.

---

### 2.3 `StaffListItem.fromRow` parses `branch_names` that never exist in the row

**File**: `lib/features/settings/domain/staff_list_item.dart:44`

```dart
branchNames: _parseBranchNames(row['branch_names']),
```

The `listStaff()` query in `StaffAdminRepository` selects only `id, full_name, role, phone, is_active` — no `branch_names` column. Branch names are loaded separately via `_loadBranchNamesByStaffId` and set via `copyWith`. The parsing in `fromRow` always returns an empty list through the normal code path.

---

### 2.4 Inconsistent `PermissionService` instantiation

Multiple instantiation patterns coexist despite the clean architecture migration establishing use case providers as the standard injection mechanism:

| Pattern | Location |
|---------|----------|
| `ref.watch(permissionServiceProvider)` | `permission_demo_panel.dart` |
| `PermissionService(auth.context)` | `patient_list_page.dart`, `patient_detail_page.dart` |
| `PermissionService(auth)` | `auth_shell_page.dart:59` |

The provider-based approach (`permissionServiceProvider`) automatically updates when the auth session changes. The direct instantiation approach creates a new service per build and doesn't subscribe to changes, meaning stale permission checks are possible if the auth state changes between builds.

---

### 2.5 `AppSearchableDropdownField` fires selection on pointer-down rather than tap

**File**: `lib/core/widgets/app_searchable_dropdown_field.dart:188`

```dart
Listener(
  behavior: HitTestBehavior.opaque,
  onPointerDown: (_) => onSelect(option),
  child: ListTile(...),
);
```

The selection triggers on `onPointerDown` to work around a focus-loss-before-tap race condition. However, this means a long press or accidental touch-down (without lift/release) will trigger selection, which is unexpected UX for desktop users.

---

### 2.6 Duplicate date formatting code across 4+ files

Date formatting (`YYYY-MM-DD`) is manually implemented in:
- `patient_detail_page.dart` (`_formatDate`, `_formatDateTime`)
- `patient_registration_page.dart` (inline string interpolation)
- `patient_edit_page.dart` (inline string interpolation)
- `duplicate_candidates_dialog.dart` (inline string interpolation)

Each copy uses the same `padLeft(2, '0')` pattern but none share a utility function.

---

## 3. Architectural Issues

### 3.1 Duplicated RPC invocation layer

`PatientRepositoryImpl._invoke` and `SettingsRpcInvoker.invokeSettingsRpc` implement nearly identical logic:

1. Log the call
2. Invoke `_client.rpc()`
3. Parse via `RpcResult.fromDynamic`
4. Throw `RpcFailure` if `!result.success`
5. Catch `PostgrestException` with `PGRST202` code
6. Map to `RPC_NOT_APPLIED` error

The patient repository duplicates this rather than reusing the `SettingsRpcInvoker` mixin. As more feature modules are added (appointments, billing, AI), each will need the same boilerplate.

**Recommendation**: Extract a single `AppRpcInvoker` mixin or base class in `core/rpc/` that all repositories use.

---

### 3.2 Flat route structure will not scale

**File**: `lib/app/router.dart`

All 25+ routes are defined at the same flat level in `GoRouter.routes`. There is no `ShellRoute` for the authenticated layout. Every page independently manages its own AppBar, back navigation, and scaffold. This causes:

- Duplicated AppBar/scaffold code across every page
- No shared authenticated chrome (sidebar, bottom nav, breadcrumbs)
- The `AuthShellPage` is a page, not a shell—navigating to patients/settings leaves the shell entirely

**Recommendation**: Wrap authenticated routes in a `ShellRoute` with a shared scaffold (navigation rail/drawer + app bar). This would eliminate per-page scaffold duplication and prepare for feature modules like appointments, billing, AI.

---

### 3.3 Cross-feature dependencies in the feature layer (partially improved)

Feature modules still import from each other, though the clean architecture migration improved this by having cross-feature code reference abstract interfaces rather than concrete implementations:

| Source Feature | Imports From |
|---|---|
| `features/patients/data/patient_dev_seed_service.dart` | `features/settings/domain/repositories/branch_repository.dart`, `features/settings/domain/repositories/staff_admin_repository.dart` (abstract interfaces) |
| `features/auth/presentation/pages/auth_shell_page.dart` | `features/patients/presentation/widgets/`, `features/settings/presentation/widgets/` |

While the migration to abstract interfaces reduces coupling at the data layer, presentation-level cross-feature imports still exist and create a dependency graph between features.

**Recommendation**: Shared entities (branch list items, staff profiles) should live in `shared/domain/` or `core/domain/`. Presentation-level cross-feature imports should be replaced by navigation to routes (no direct widget imports) and shared providers in `shared/providers/`.

---

### 3.4 State management inconsistency

Two different patterns are used for managing async operations:

| Pattern | Used By | Loading/Error Tracking |
|---|---|---|
| `AsyncNotifier<T>` | `PatientListNotifier` | Automatic via `AsyncValue` |
| `Notifier<UiState>` with manual `isSubmitting`/`errorMessage` | `BootstrapNotifier`, `ProvisioningNotifier`, `BranchFormNotifier`, etc. | Manual boolean + string fields |

The `AsyncNotifier` pattern gives loading, error, and data states for free, while the manual pattern requires `copyWith` calls with `clearError`, `isSubmitting` toggles, and `clearLastCreated` flags. This inconsistency increases cognitive load and the chance of forgetting to reset state.

**Note**: The clean architecture migration introduced use case providers, so notifiers now inject use cases (e.g., `ref.read(searchPatientsUseCaseProvider)(...)`) instead of direct repository access. This is a structural improvement but does not resolve the state management pattern inconsistency itself.

**Recommendation**: Standardize on `AsyncNotifier` for data-fetching notifiers and reserve `Notifier` for purely synchronous UI state.

---

### 3.5 ~~No repository interface abstraction~~ — RESOLVED

**Status**: Resolved by the clean architecture migration.

All repositories now follow a proper interface/implementation split:

- **Abstract interfaces** in `domain/repositories/` (e.g., `PatientRepository` in `features/patients/domain/repositories/patient_repository.dart`)
- **Concrete implementations** renamed to `*Impl` in `data/` (e.g., `PatientRepositoryImpl` in `features/patients/data/patient_repository.dart`)
- **Use cases** in `domain/usecases/` (one class per operation with a single `call()` method)
- **Providers** return the abstract type:

```dart
final patientRepositoryProvider = Provider<PatientRepository>((ref) {
  return PatientRepositoryImpl(ref.watch(supabaseClientProvider));
});
```

Tests can now mock the abstract interface without overriding the concrete implementation. Use case providers allow fine-grained dependency injection at the operation level.

---

### 3.6 Navigation not abstracted from UI

Direct GoRouter calls (`context.go()`, `context.push()`, `context.pop()`) are scattered across 15+ files. This means:
- Every page is tightly coupled to GoRouter
- Navigation cannot be unit-tested without a full widget harness
- Route changes require updating every call site

---

## 4. Future Extension Risks

### 4.1 `DeploymentMode` is hardcoded to `local` only

**File**: `lib/core/config/deployment_profile.dart`

```dart
enum DeploymentMode { local }
```

The `fromMap` constructor explicitly rejects anything except `local`:

```dart
if (deploymentModeValue != DeploymentMode.local.wireValue) {
  throw InvalidDeploymentProfileException(
    'Only clinic-local deployment is supported in V1-0.',
  );
}
```

Adding cloud/hosted deployment will require:
- New enum values
- Refactoring the rejection logic
- New health check flows (cloud endpoints have different availability characteristics)
- Different auth strategies (magic links, SSO)

---

### 4.2 No offline/cache layer

The app makes direct Supabase calls for every operation. For a desktop app on a clinic LAN:
- If the LAN cable is unplugged, the entire app becomes unusable
- There is no local patient cache for lookup during network outages
- No optimistic UI updates for mutations

This is acknowledged in the V1-0 scope but will become critical as the app is deployed to real clinics.

---

### 4.3 `PatientGender` enum is limited to male/female

**File**: `lib/features/patients/domain/patient_gender.dart`

Only `male` and `female` values exist. Many healthcare systems require additional options (other, non-binary, prefer not to say, unknown). Adding values will require:
- DB enum migration
- RPC changes
- All form dropdowns updated
- Existing data migration

---

### 4.4 `AppDataTable` uses `List<List<String>>` for row data

**File**: `lib/core/widgets/app_data_table.dart`

```dart
final List<List<String>> rows;
```

This is type-unsafe. A mismatched column count between `columns` and a row's `List<String>` will either show blank cells (gracefully handled) or be silently wrong. As more tables are added (appointments, billing), the risk of column/data mismatch grows.

**Recommendation**: Use a typed row model with column definitions that include value extractors, e.g., `AppDataColumn<T>(label: 'Name', extract: (T item) => item.fullName)`.

---

### 4.5 No internationalization (i18n)

All user-facing strings are hardcoded in English across 100+ files. There are no `AppLocalizations`, no `.arb` files, and no `Intl` integration. Adding multi-language support later would require touching virtually every widget.

---

### 4.6 Hard-coded permission keys as raw strings

Permission checks use raw string literals throughout the codebase:

```dart
auth.context!.permissions.contains('settings.manage_branches');
```

While `PermissionKeys` constants exist, they're not used consistently. A typo in a raw string (e.g., `'settings.mange_branches'`) would silently fail the permission check without any compile-time error.

---

### 4.7 Single-provider architecture for global session state

`AuthSessionNotifier` is a single global `Notifier` that manages:
- Supabase initialization
- Auth state streaming
- Session context loading (DB queries)
- Idle timeout wiring
- Branch selection
- Sign-out flows

This is a god-class risk. As features grow, more responsibilities will be added (multi-factor auth, session pinning, audit logging). It's already 350+ lines.

---

### 4.8 No pagination abstraction

`PatientListNotifier` implements pagination manually with `offset`, `limit`, `hasMore`, and `loadMore()`. The branch and staff lists in settings use simple full-load approaches. When those lists grow (e.g., 100+ branches, 500+ staff), they'll need pagination too, and the pattern will be duplicated again.

---

## 5. Security Concerns

### 5.1 Committed Supabase anon key and local URL

**File**: `web/deployment-profile.json`

```json
{
  "supabase_anon_key": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
}
```

While this is a local dev key and the `deployment-profile.json` is intentionally committed for local development, this file pattern means that a production deployment profile could accidentally be committed if `.gitignore` isn't updated.

**Recommendation**: Add `deployment-profile.json` to `.gitignore` at the repo root (not just `web/`) and document that `web/deployment-profile.json` is a template only.

---

### 5.2 Dev-only buttons guarded only by `kDebugMode`

**Files**: `dev_fill_dummy_clinic_button.dart`, `dev_reset_clinic_button.dart`, `dev_quick_admin_sign_in_button.dart`, `dev_seed_patients_button.dart`

These buttons are conditionally rendered based on `kDebugMode`:

```dart
if (!kDebugMode) {
  return const SizedBox.shrink();
}
```

This is correct for production builds (tree-shaken out), but profile builds (`flutter run --profile`) still include them. If a profile build is accidentally used in a clinic, dev controls like "Reset clinic" and "Sign in as admin" would be available.

---

### 5.3 Hard-coded dev admin credentials

**File**: `lib/features/auth/presentation/widgets/dev_quick_admin_sign_in_button.dart:13-14`

```dart
const kDevAdminUsername = 'admin';
const kDevAdminPassword = 'admin';
```

These are the seeded bootstrap admin credentials. While guarded by `kDebugMode`, they remain in the source code and could be discovered by anyone with repo access.

---

### 5.4 JWT parsing does not validate signature or expiry

**File**: `lib/core/config/supabase_config.dart:147-162`

`decodeAccessTokenClaims` splits the JWT and base64-decodes the payload without verifying the signature or checking `exp`. This is used for extracting staff claims (role, branch IDs, etc.) to build the session context.

While Supabase handles actual auth validation server-side, the client trusts the decoded claims for UI permission decisions. A modified JWT (man-in-the-middle on the clinic LAN) could grant UI-level access to restricted features, though the actual RPC calls would still fail server-side.

---

### 5.5 `AppLog` redaction patterns may not catch all sensitive data

**File**: `lib/core/logging/app_log.dart`

The log redaction handles passwords, Bearer tokens, JWTs, and emails. However:
- Patient names, phone numbers, and dates of birth (PHI) are not redacted
- The log param patterns in repositories include patient IDs and field names in plain text
- `AppLog.fine` messages include things like `'patients.rpc.invoke fn=create_patient params=p_full_name,p_phone,...'`

While the actual values aren't logged (only param keys), any future logging that includes values would leak PHI.

---

## 6. UI/UX Issues

### 6.1 No loading skeleton / shimmer for list pages

Patient, staff, and branch lists show a bare `CircularProgressIndicator` while loading. For a desktop app, a skeleton/shimmer layout would feel more responsive and indicate the shape of incoming data.

---

### 6.2 Error messages display raw exceptions to users

**Files**: `patient_edit_page.dart:181`, `patient_registration_page.dart:163`

```dart
_formError = error.toString();
```

Unhandled exceptions show their raw `toString()` to the user (e.g., `"StateError: ..."` or PostgreSQL error messages). This is unhelpful for clinic staff and may leak implementation details.

---

### 6.3 `PermissionDemoPanel` is always visible on the home page

**File**: `lib/features/auth/presentation/pages/auth_shell_page.dart:115`

The permission demo panel is unconditionally shown on the authenticated home page. This is development scaffolding that should be behind `kDebugMode` or removed before release.

---

### 6.4 No confirmation before navigating away from unsaved forms

Patient registration and edit pages have no "discard changes?" dialog. A user who accidentally taps the back button after filling out a form loses all input without warning.

---

### 6.5 Date picker UX on desktop

**Files**: `patient_registration_page.dart`, `patient_edit_page.dart`

The date of birth picker uses Flutter's `showDatePicker` with a default `initialDate` of 30 years ago. On desktop, this calendar-style picker is cumbersome for entering dates decades in the past (elderly patients). A text-input date field with format validation would be more efficient.

---

### 6.6 Patient search debounce is only 300ms

**File**: `lib/features/patients/presentation/widgets/patient_search_field.dart:33`

```dart
_debounce = Timer(const Duration(milliseconds: 300), () { ... });
```

At 300ms, the search fires an RPC call for every brief typing pause. On a slow LAN, this could queue multiple in-flight requests. A 500-800ms debounce is more appropriate for RPC-backed search, especially with minimum character requirements.

---

## 7. Testing & Maintainability

### 7.1 `SupabaseBootstrap` uses static mutable state

**File**: `lib/core/config/supabase_config.dart`

```dart
static bool _initialized = false;
static Future<void>? _pendingInitialization;
static bool _testReady = false;
```

These statics make `SupabaseBootstrap` a global singleton with mutable state. Tests must remember to call `debugResetForTests()` between test cases, and forgetting to do so causes test pollution.

---

### 7.2 `AuthSessionNotifier` at 350+ lines

**File**: `lib/shared/providers/auth_session_provider.dart`

This single notifier manages:
- Supabase SDK initialization
- Auth state streaming
- Session context loading (DB queries)
- Idle timeout wiring
- Branch selection
- Sign-in and sign-out flows
- Session refresh
- Context failure classification

This is complex to test and extend. Breaking it into smaller focused notifiers (e.g., `AuthLifecycleNotifier`, `SessionContextLoader`, `BranchSelectionNotifier`) would improve testability.

---

### 7.3 No test helpers for common widget test patterns

Each widget test presumably builds its own `ProviderScope` with overrides. Common patterns (authenticated user, specific permissions, specific patient list state) should be extracted into shared test utilities. The `testing/` directory has `auth_test_support.dart` and `startup_test_support.dart`, but there's no equivalent for patients or settings.

---

### 7.4 Debug-only code mixed with production code

Dev buttons (`DevFillDummyClinicButton`, `DevResetClinicButton`, `DevQuickAdminSignInButton`, `DevSeedPatientsButton`) are imported and instantiated in production widgets (e.g., `AuthShellPage`). While they render as `SizedBox.shrink()` in release, the import graph and constructor calls still exist.

**Recommendation**: Use conditional imports or move dev widgets to a `testing/` or `dev/` directory that's only imported in debug entry points.

---

## 8. Positive Observations

### 8.1 Strong clean architecture with proper layer separation

The codebase follows a full Flutter clean architecture pattern across all features (`auth`, `patients`, `settings`):

- **Abstract repository interfaces** in `domain/repositories/` define contracts that the data layer implements
- **Use cases** in `domain/usecases/` encapsulate single operations with `call()` methods
- **Concrete implementations** (`*Impl`) in `data/` implement the interfaces with Supabase RPC calls
- **Providers** return abstract types, enabling clean dependency injection and testability
- **Input/output DTOs** extracted to `domain/` layer, keeping the data layer free of domain type ownership

Domain models are immutable (`@immutable`), have proper `==`/`hashCode` overrides, and include factory parsers with null safety. The dependency rule (presentation → use cases → repository interfaces ← repository implementations) is consistently enforced.

### 8.2 Comprehensive error mapping for RPCs

Both `bootstrapMessageForRpc`, `provisioningMessageForRpc`, and `patientMessageForRpc` provide user-friendly messages for every known RPC error code. This shows thoughtful attention to the user experience during failures.

### 8.3 Security-conscious logging

`AppLog` with redaction patterns for passwords, tokens, JWTs, and emails demonstrates a security-first mindset appropriate for a healthcare application.

### 8.4 Robust deployment profile validation

The `DeploymentProfile.fromMap` validation is thorough — checking for required fields, validating URI schemes, rejecting unsupported modes, and providing clear error messages at each step.

### 8.5 Well-implemented optimistic locking

The patient edit flow with `expected_updated_at` and the stale-update banner is a solid implementation of optimistic concurrency control that provides a good user experience when conflicts occur.

### 8.6 Good test coverage structure

The test directory mirrors the source structure with 109 test files covering unit, widget, and integration levels. The test support files (`fake_postgrest_rpc.dart`, `patient_rpc_test_client.dart`, etc.) show investment in testability infrastructure.

### 8.7 Thoughtful idle timeout system

The `IdleTimeoutService` correctly tracks only user-initiated activity (keyboard/pointer) and ignores background token refresh, preventing background auth events from artificially extending sessions.

### 8.8 Platform-conditional imports

The `deployment_profile_store.dart` → `_io.dart` / `_web.dart` pattern and `supabase_config_env` conditional imports cleanly handle platform differences without `dart:io` availability issues on web.

---

---

# Second Review Cycle — New Findings

**Date**: 2026-05-24
**Scope**: Deep review of all 154 Dart files, focusing on areas the first cycle treated at a higher level: widget lifecycle, subscription management, timezone handling, hash contracts, state recovery, and layout correctness.

---

## 9. Critical Bugs (Cycle 2)

### 9.1 `Expanded` inside `DataColumn.label` — invalid widget parentage

**File**: `lib/core/widgets/app_data_table.dart:56`

```dart
DataColumn(
  numeric: column.numeric,
  label: Expanded(child: Text(column.label, style: Theme.of(context).textTheme.labelLarge)),
),
```

`Expanded` must be a direct child of a `Row`, `Column`, or `Flex` widget. `DataColumn.label` is placed inside a `Table`/`TableCell` layout, not a flex parent. This triggers **"Incorrect use of ParentDataWidget"** in debug mode and can cause runtime layout failures in release builds. Every page that renders `AppDataTable` is affected (patients list, staff list, branch list).

---

### 9.2 `ref.listenManual` subscription never closed — memory leak

**Files**: `lib/features/auth/presentation/pages/staff_create_page.dart:37-41`, `lib/features/settings/presentation/pages/staff_form_page.dart:42-49`

Both pages call `ref.listenManual()` in `initState()` but neither stores the returned `ProviderSubscription` nor calls `.close()` in `dispose()`:

```dart
// staff_create_page.dart:37
ref.listenManual(
  authSessionProvider.select((s) => s.context?.branchIds ?? const <String>[]),
  (previous, next) => _onAssignableBranchIdsChanged(next),
  fireImmediately: true,
);

// staff_form_page.dart:42
ref.listenManual(staffManagementBranchesProvider, (previous, next) {
  next.whenData((branches) { ... setState(...) ... });
});
```

The listener outlives the widget. If the provider emits after the widget is disposed, the callback fires against a defunct `State` object, causing `setState` on a disposed widget (crashes in debug, undefined behavior in release) and leaking memory.

---

### 9.3 Repeated `addPostFrameCallback` redirect stacking during build

**File**: `lib/features/auth/presentation/pages/clinic_bootstrap_page.dart:111-118`

```dart
if (session.isAuthenticated && auth != null && !auth.setupRequired) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!mounted) return;
    context.go(AppRoutes.home);
  });
  return const Scaffold(body: Center(child: CircularProgressIndicator()));
}
```

This runs inside `build()`. Every rebuild while the condition is true schedules **another** post-frame `context.go(AppRoutes.home)`. Multiple redundant navigation calls stack up, which can cause assertion failures, double-push artifacts, or flickering during the settle phase.

---

## 10. Non-Critical Bugs & Code Smells (Cycle 2)

### 10.1 `searchPatients` silently omits `branchId` for `thisBranch` scope

**File**: `lib/features/patients/data/patient_repository.dart` (`PatientRepositoryImpl`)

```dart
if (scope == PatientListScope.thisBranch && branchId != null) 'p_branch_id': branchId,
```

When scope is `thisBranch` but `branchId` is null, `p_branch_id` is silently omitted from the RPC params. The SQL may fall back to a default or return unexpected results. The notifier has a guard (`throw StateError` for empty branch), but the abstract `PatientRepository.searchPatients` interface is callable from other contexts (e.g., use cases, tests) without that guard.

---

### 10.2 `updatePatient` return timestamp timezone inconsistency

**File**: `lib/features/patients/data/patient_repository.dart` (`PatientRepositoryImpl`)

```dart
final updatedAt = result.data?['updated_at']?.toString();
final parsed = DateTime.tryParse(updatedAt);
return parsed;
```

The `expectedUpdatedAt` is sent as `input.expectedUpdatedAt.toUtc().toIso8601String()` (explicit UTC), but the returned `updated_at` is parsed with `DateTime.tryParse`, which may produce a local-zone `DateTime` for offset-less strings (e.g. `"2026-05-24 10:30:00"`). This creates a timezone mismatch between the sent and received timestamps, breaking subsequent optimistic concurrency comparisons.

---

### 10.3 `parsePatientDate` date truncation not UTC-normalized

**File**: `lib/features/patients/domain/patient_row_parsing.dart:7`

```dart
if (value is DateTime) {
  return DateTime(value.year, value.month, value.day);
}
```

`DateTime(year, month, day)` creates a local-timezone midnight. If the input is a UTC midnight `DateTime` (e.g. `2026-05-24T00:00:00Z`), the local calendar date can shift (e.g. to May 23 in UTC-3 zones). PostgreSQL `date` columns are timezone-agnostic, so this creates a data display mismatch for clinics in negative UTC offsets.

---

### 10.4 `OrganizationProfile.hashCode` violates `==`/`hashCode` contract

**File**: `lib/features/settings/domain/organization_profile.dart:126-138`

```dart
// == uses order-insensitive comparison:
mapEquals(settingsJson, other.settingsJson)

// hashCode uses iteration-order-dependent hashing:
settingsJson == null ? null : Object.hashAll(settingsJson!.entries),
```

`mapEquals` is order-insensitive, but `Object.hashAll(entries)` produces different hashes for maps with the same key-value pairs in different iteration order. Two `OrganizationProfile` instances that compare equal can produce different hash codes, breaking `Set`, `Map`, and any hash-based collection usage.

---

### 10.5 `PermissionRepository` missing `is_deleted: false` filter

**File**: `lib/features/auth/data/permission_repository.dart:14-18`

```dart
final rows = await _client
    .from('roles_permissions')
    .select('permission_key')
    .eq('role', role.wireValue)
    .eq('is_granted', true);
```

Unlike `RolePermissionsRepository.fetchMatrix`, this query does not filter `is_deleted == false`. If RLS does not fully enforce soft-delete filtering, revoked (soft-deleted) permission grants could still be loaded into the session context, granting UI access that should be denied.

---

### 10.6 `_ensureSupabaseReadyTask` cached forever — failed init never retried

**File**: `lib/shared/providers/auth_session_provider.dart:83-84`

```dart
Future<void> _ensureSupabaseReady(StartupSessionState startup) {
  return _ensureSupabaseReadyTask ??= _runEnsureSupabaseReady(startup);
}
```

The completed `Future` is cached for the notifier's lifetime and never cleared. If `_runEnsureSupabaseReady` throws (transient network error, misconfigured profile), subsequent calls return the same failed future and **never re-attempt initialization**. The user is stranded until they restart the app.

---

### 10.7 `activeBranchId` defaults to first JWT claim token, not DB primary

**File**: `lib/shared/providers/auth_session_provider.dart:248-265`

```dart
final branchIdsRaw = claims['branch_ids']?.toString() ?? '';
final branchIds = branchIdsRaw.split(',').map((value) => value.trim()).where((value) => value.isNotEmpty).toList();
final primaryBranchId = branchIds.isEmpty ? null : branchIds.first;
// ...
activeBranchId: primaryBranchId,
```

`branchIds.first` picks the first token from the comma-separated JWT claim, which may not be the actual DB primary branch from `staff_branch_assignments`. If claim order doesn't match the primary, the patient "this branch" scope targets the wrong branch until the user manually switches.

---

### 10.8 `loadMore` failure drops entire loaded list

**File**: `lib/features/patients/presentation/providers/patient_list_notifier.dart:127-128`

```dart
} catch (error, stack) {
  state = AsyncError(error, stack);
}
```

When `loadMore` fails, the state becomes `AsyncError`, which replaces the `AsyncData` containing all previously loaded rows. The list page renders the error widget, and the user loses all visible data. They must do a full reload to recover.

---

### 10.9 "Archived" detection by substring matching on error text

**File**: `lib/features/patients/presentation/pages/patient_detail_page.dart:160`

```dart
final isArchived = message.contains('archived');
```

The error page branches its entire UI (button labels, retry logic) on whether the error string contains the word "archived". Any unrelated error that happens to include "archived" triggers the wrong code path. Conversely, a wording change in the RPC error message breaks the detection.

---

### 10.10 `ref.listen` → `setState` without `mounted` guard

**Files**: `staff_password_reset_page.dart`, `idle_timeout_settings_page.dart`, `organization_settings_page.dart`, `branch_list_page.dart`

Multiple `ref.listen` callbacks call `setState` or `showDialog` without checking `context.mounted` first. If the provider emits after the widget is disposed (async completion), this calls `setState` on a defunct state object.

Example from `idle_timeout_settings_page.dart:35-40`:

```dart
ref.listen<AsyncValue<IdleTimeoutSettingsState>>(idleTimeoutSettingsProvider, (previous, next) {
  final value = next.value;
  if (value?.saveMessage != null) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value!.saveMessage!)));
  }
});
```

---

### 10.11 Snackbar listeners fire without comparing to `previous` state

**Files**: `lib/features/settings/presentation/pages/idle_timeout_settings_page.dart:35-40`, `lib/features/settings/presentation/pages/organization_settings_page.dart:67-72`

Unlike `role_permissions_page.dart` which correctly compares `previous` and `next`, these listeners only check the current `next` state for `saveMessage != null`. Any provider rebuild that preserves the same `saveMessage` re-shows the snackbar without a new save action.

---

### 10.12 `Flexible` inside tight `Column` in duplicate candidates dialog

**File**: `lib/features/patients/presentation/widgets/duplicate_candidates_dialog.dart:33`

```dart
Column(
  mainAxisSize: MainAxisSize.min,
  children: [
    const Text(...),
    Flexible(
      child: ListView.separated(shrinkWrap: true, ...),
    ),
  ],
)
```

`Flexible` in a `Column` with `mainAxisSize: MainAxisSize.min` receives unbounded max height in the main axis. `Flexible` expects a bounded flex constraint from its parent. With many duplicate candidates, this can assert at runtime or produce inconsistent layout.

---

### 10.13 Forced non-null path parameters in router

**File**: `lib/app/router.dart:80`

```dart
builder: (context, state) => StaffSettingsPasswordResetPage(staffId: state.pathParameters['staffId']!),
```

The force-unwrap `!` throws a `TypeError` if the parameter is missing or the route is matched incorrectly (e.g. a deep link with a malformed URL). Other routes (patient detail, patient edit, branch edit) safely pass nullable `pathParameters['id']` — this one is inconsistent.

---

### 10.14 `PatientSearchField` debounce fires after `enabled` becomes false

**File**: `lib/features/patients/presentation/widgets/patient_search_field.dart:31-36`

```dart
_debounce = Timer(const Duration(milliseconds: 300), () {
  if (!mounted) return;
  widget.onSearch(_controller.text);
});
```

The timer callback checks `mounted` but not `widget.enabled`. When the search field is disabled (e.g. no active branch selected), an in-flight debounce timer still fires `onSearch`, triggering a reload against the invalid state.

---

## 11. Low-Severity Issues (Cycle 2)

### 11.1 Dead `AppColors.info` token

**File**: `lib/app/theme/app_colors.dart`

`AppColors.info` is defined but never referenced anywhere in the codebase. Dead code.

---

### 11.2 `debugRecords` grows unbounded in long debug sessions

**File**: `lib/core/logging/app_log.dart`

In `kDebugMode`, `debugRecords` accumulates log records without any size bound. A long-running debug session (common during desktop development) steadily consumes memory.

---

### 11.3 `idle_timeout_preferences_store_io.dart` uses `Directory.current` for settings file

**File**: `lib/features/settings/data/idle_timeout_preferences_store_io.dart:57-59`

```dart
File _settingsFile() {
  return File('${Directory.current.path}${Platform.pathSeparator}${IdleTimeoutPreferencesStore.fileName}');
}
```

Settings are written relative to the process working directory, which varies depending on how the app is launched (IDE, installer, shortcut). Settings can be lost or written to unexpected locations.

---

### 11.4 `permission_matrix_view.dart` getter mutates internal lists

**File**: `lib/features/settings/domain/permission_matrix_view.dart:53`

```dart
PermissionCategoryGroup(category: category, permissionKeys: byCategory[category]!..sort()),
```

The `categoryGroups` getter uses `..sort()` which mutates the lists held in `byCategory`. While single-threaded, this is a surprising side effect inside a getter.

---

### 11.5 `staff_member_summary.roleLabel` returns wire value

**File**: `lib/features/auth/domain/staff_member_summary.dart:24-25`

```dart
String get roleLabel => role.wireValue;
```

Named `roleLabel` but returns the snake_case wire value (e.g. `lab_staff`), not a human-readable display label like other role-label patterns in the codebase.

---

### 11.6 Patient list page has no retry button on load error

**File**: `lib/features/patients/presentation/pages/patient_list_page.dart:82`

```dart
error: (error, _) => Center(child: Text('Failed to load patients: $error')),
```

Unlike the detail page (which has a retry button), the list page shows only a raw error string with no retry action and no friendly message.

---

### 11.7 Accessibility: icon-only actions missing `tooltip` / `Semantics`

Several `IconButton` instances across patient and settings pages use only a `Key` but no `tooltip` or `Semantics` label. Screen readers receive no description for these interactive elements. Examples include back-navigation buttons in various pages and action icons in list rows.

---

### 11.8 `patient_pages.dart` barrel omits registration page

**File**: `lib/features/patients/presentation/pages/patient_pages.dart`

The barrel file exports `patient_detail_page.dart`, `patient_edit_page.dart`, and `patient_list_page.dart` — but not `patient_registration_page.dart`. The router imports it directly, so the app works, but the barrel is incomplete for consumers.

---

### 11.9 Concurrent `reload()` race in `PatientListNotifier`

**File**: `lib/features/patients/presentation/providers/patient_list_notifier.dart:64-76`

`ref.listen` on scope changes and branch changes both call `reload()` without cancellation or serialization. Rapid scope/branch toggles can overlap async RPC completions and briefly show stale results from an earlier reload.

---

## Updated Summary

| Category | Critical | Medium | Low |
|---|---|---|---|
| Bugs (Cycle 1) | 4 | 3 | 3 |
| Bugs (Cycle 2) | 3 | 14 | 9 |
| Architecture | — | 5 (1 resolved) | 2 |
| Future Extension | — | 5 | 3 |
| Security | — | 3 | 2 |
| UI/UX | — | 2 | 4 |
| Testing | — | 2 | 2 |
| **Combined Totals** | **7** | **34** | **25** |

> **Note**: Issue 3.5 (No repository interface abstraction) has been resolved by the clean architecture migration, which introduced abstract interfaces in `domain/repositories/`, use cases in `domain/usecases/`, and renamed concrete implementations to `*Impl`.

**Top 5 new priorities** (in recommended order):
1. Fix `Expanded` inside `DataColumn.label` — affects all table views (9.1)
2. Close `ref.listenManual` subscriptions in `dispose()` (9.2)
3. Guard `addPostFrameCallback` redirect with a one-shot flag (9.3)
4. Fix `OrganizationProfile.hashCode` contract violation (10.4)
5. Retain loaded rows on `loadMore` failure instead of replacing with error (10.8)
