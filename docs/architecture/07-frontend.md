# Frontend

- Purpose: Define the Flutter desktop architecture, feature layout, state management, and UX shell conventions.
- Read this when: implementing Flutter modules, app shell behavior, routing, Riverpod state, or Supabase configuration in the client.
- Canonical for: project structure, presentation/domain/data boundaries, Riverpod patterns, and desktop UX/navigation rules.
- Usually paired with: `docs/architecture/04-backend.md`, `docs/architecture/09-security-rbac.md`, and the feature spec being built.
- Not covered here: deployment internals, deep database design, or roadmap sequencing.

---

## Flutter Frontend Architecture

### Project Structure (Feature-First Clean Architecture)

Each feature uses a layered layout with `data/`, `domain/`, and `presentation/` directories. The domain layer contains abstract repository interfaces (in `domain/repositories/`) and single-responsibility use cases (in `domain/usecases/`). Concrete repository implementations live in `data/` and are named with an `Impl` suffix. Presentation-layer notifiers depend on use cases, not repositories directly.

```
frontend/lib/
├── main.dart
├── app/
│   ├── app.dart                        # MaterialApp, ProviderScope
│   ├── router.dart                     # GoRouter with auth/startup redirects
│   ├── app_routes.dart                 # Route path constants
│   └── session_activity_scope.dart     # Wraps app for idle-timeout tracking
│
├── core/
│   ├── auth/
│   │   ├── auth_route_guard.dart       # GoRouter redirect logic
│   │   ├── idle_timeout_service.dart   # Inactivity auto-sign-out
│   │   ├── permission_service.dart     # Permission checks from session context
│   │   └── permission_denied_handler.dart
│   ├── config/
│   │   ├── deployment_profile.dart     # Strongly-typed profile (mode, URLs, device role)
│   │   ├── supabase_config.dart        # SupabaseConfig + SupabaseBootstrap + JWT decode
│   │   └── supabase_config_env_io.dart # Platform-specific env detection
│   ├── errors/
│   │   ├── failures.dart               # Failure classes
│   │   └── exceptions.dart             # Exception classes
│   ├── logging/
│   │   └── app_log.dart                # Structured logging
│   ├── rpc/
│   │   └── rpc_result.dart             # Typed wrapper for rpc_result composite
│   ├── widgets/                        # Shared UI widgets (buttons, cards, dialogs, form fields, etc.)
│   └── ...
│
├── features/
│   ├── startup/                        # App startup: health probes, profile loading, connectivity
│   │   ├── presentation/
│   │   │   ├── pages/                  # startup_check_page, startup_entry_page, setup_guidance_page
│   │   │   ├── providers/              # startup_notifier
│   │   │   └── widgets/               # failure_banner, degraded_state_notice
│   │
│   ├── auth/
│   │   ├── data/
│   │   │   ├── auth_repository.dart        # AuthRepositoryImpl (Supabase auth wrapper)
│   │   │   ├── bootstrap_repository.dart   # BootstrapRepositoryImpl
│   │   │   ├── provisioning_repository.dart # ProvisioningRepositoryImpl
│   │   │   └── permission_repository.dart  # PermissionRepositoryImpl
│   │   ├── domain/
│   │   │   ├── auth_session.dart           # StaffRole enum, StaffProfile, AuthSessionContext
│   │   │   ├── staff_username.dart         # Username normalization and validation
│   │   │   ├── branch_summary.dart         # Branch DTO for session context
│   │   │   ├── permission_keys.dart        # Permission key constants
│   │   │   ├── bootstrap_organization_input.dart
│   │   │   ├── bootstrap_branch_input.dart
│   │   │   ├── create_staff_account_input.dart
│   │   │   ├── create_staff_account_result.dart
│   │   │   ├── admin_reset_staff_password_result.dart
│   │   │   ├── repositories/              # Abstract interfaces
│   │   │   │   ├── auth_repository.dart
│   │   │   │   ├── bootstrap_repository.dart
│   │   │   │   ├── permission_repository.dart
│   │   │   │   └── provisioning_repository.dart
│   │   │   └── usecases/                  # Single-operation use case classes
│   │   │       ├── sign_in.dart
│   │   │       ├── sign_out.dart
│   │   │       ├── refresh_session.dart
│   │   │       ├── clear_persisted_session.dart
│   │   │       ├── create_organization.dart
│   │   │       ├── create_bootstrap_branch.dart
│   │   │       ├── reset_installation.dart
│   │   │       ├── load_granted_permissions.dart
│   │   │       ├── list_org_staff_members.dart
│   │   │       ├── list_branches_by_ids.dart
│   │   │       ├── create_staff_account.dart
│   │   │       ├── reset_staff_password.dart
│   │   │       └── auth_use_case_providers.dart
│   │   └── presentation/
│   │       ├── pages/                  # login_page, clinic_bootstrap_page, staff_create_page, etc.
│   │       └── widgets/               # permission_demo_panel, no_branch_blocked_panel
│   │
│   ├── patients/
│   │   ├── data/
│   │   │   ├── patient_repository.dart     # PatientRepositoryImpl + patientRepositoryProvider
│   │   │   ├── patient_rpc_failure.dart    # Typed RPC error mapping
│   │   │   └── patient_dev_seed_service.dart # Dev-only bulk patient seeding
│   │   ├── domain/
│   │   │   ├── patient_list_item.dart      # List DTO
│   │   │   ├── patient_detail.dart         # Full detail DTO
│   │   │   ├── patient_gender.dart         # Gender enum (male, female)
│   │   │   ├── patient_marital_status.dart # Marital status enum
│   │   │   ├── patient_list_scope.dart     # branch vs organization scope
│   │   │   ├── patient_search_page.dart    # Paginated search result
│   │   │   ├── create_patient_input.dart   # Input DTO for creation
│   │   │   ├── update_patient_input.dart   # Input DTO for update
│   │   │   ├── duplicate_candidate.dart    # Duplicate match DTO
│   │   │   ├── patient_search_query.dart   # Search query value object
│   │   │   ├── repositories/              # Abstract interface
│   │   │   │   └── patient_repository.dart
│   │   │   └── usecases/                  # Single-operation use case classes
│   │   │       ├── search_patients.dart
│   │   │       ├── get_patient.dart
│   │   │       ├── check_duplicates.dart
│   │   │       ├── create_patient.dart
│   │   │       ├── update_patient.dart
│   │   │       ├── archive_patient.dart
│   │   │       └── patient_use_case_providers.dart
│   │   └── presentation/
│   │       ├── pages/                      # patient_list, registration, edit, detail
│   │       └── widgets/                    # patient_search_field, archive_dialog
│   │
│   ├── settings/                           # Organization, branch, staff, permissions, idle timeout
│   │   ├── data/
│   │   │   ├── organization_repository.dart    # OrganizationRepositoryImpl
│   │   │   ├── branch_repository.dart          # BranchRepositoryImpl
│   │   │   ├── staff_admin_repository.dart     # StaffAdminRepositoryImpl
│   │   │   ├── role_permissions_repository.dart # RolePermissionsRepositoryImpl
│   │   │   ├── settings_rpc_repository.dart
│   │   │   └── idle_timeout_preferences_store.dart
│   │   ├── domain/
│   │   │   ├── organization_profile.dart
│   │   │   ├── branch_list_item.dart
│   │   │   ├── branch_list_filter.dart
│   │   │   ├── create_branch_input.dart
│   │   │   ├── update_branch_input.dart
│   │   │   ├── update_organization_input.dart
│   │   │   ├── staff_list_item.dart
│   │   │   ├── staff_list_filter.dart
│   │   │   ├── staff_member_detail.dart
│   │   │   ├── update_staff_member_input.dart
│   │   │   ├── permission_matrix_row.dart
│   │   │   ├── permission_matrix_view.dart
│   │   │   ├── idle_timeout_config.dart
│   │   │   ├── repositories/              # Abstract interfaces
│   │   │   │   ├── branch_repository.dart
│   │   │   │   ├── organization_repository.dart
│   │   │   │   ├── role_permissions_repository.dart
│   │   │   │   └── staff_admin_repository.dart
│   │   │   └── usecases/                  # Single-operation use case classes
│   │   │       ├── list_branches.dart
│   │   │       ├── create_branch.dart
│   │   │       ├── update_branch.dart
│   │   │       ├── set_branch_active.dart
│   │   │       ├── fetch_organization_profile.dart
│   │   │       ├── update_organization.dart
│   │   │       ├── fetch_permission_matrix.dart
│   │   │       ├── update_role_permission.dart
│   │   │       ├── list_staff.dart
│   │   │       ├── fetch_staff_member.dart
│   │   │       ├── organization_has_owner.dart
│   │   │       ├── update_staff_member.dart
│   │   │       ├── set_staff_active.dart
│   │   │       └── settings_use_case_providers.dart
│   │   └── presentation/
│   │       ├── pages/                      # settings_page, org, branches, staff, roles, idle timeout
│   │       ├── providers/                  # staff_list_notifier, role_permissions_notifier
│   │       └── widgets/                    # shell_status_bar
│   │
│   └── foundation_demo/                    # Dev-only: widget catalog/theme demonstration
│       └── presentation/pages/
│
└── shared/
    └── providers/
        ├── auth_session_provider.dart      # Global auth session state
        ├── startup_session_provider.dart    # Startup lifecycle state
        ├── connectivity_provider.dart       # Network/Supabase health monitoring
        └── theme_provider.dart             # Theme state
```

### Layer Responsibilities (Per Feature)

| Layer            | Directory       | Contains                                                                                                   | Depends On                                                    |
| ---------------- | --------------- | ---------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------- |
| **Presentation** | `presentation/` | Pages (screens), Widgets, Riverpod Providers/Notifiers                                                    | Domain use cases (via providers)                              |
| **Domain**       | `domain/`       | Value objects, enums, DTOs, abstract repository interfaces (`repositories/`), use cases (`usecases/`)      | Nothing (innermost layer)                                     |
| **Data**         | `data/`         | Concrete repository implementations (`*Impl`), RPC call logic, error mapping                               | Domain interfaces, Supabase SDK                               |

Implementation note: The project uses **full clean architecture** with abstract repository interfaces in `domain/repositories/` and single-responsibility use case classes in `domain/usecases/`. Each use case has a single public `call()` method. Concrete repository classes (suffixed `Impl`) live in `data/` and implement the domain interface. Presentation-layer notifiers inject use cases via Riverpod providers, not repositories directly. The `auth_session_provider.dart` in `shared/providers/` is an exception — it uses repositories directly as infrastructure-level code.

### State Management with Riverpod

#### Provider Types by Use Case

| Riverpod Concept        | Use Case                                     | Example                                                  |
| ----------------------- | -------------------------------------------- | -------------------------------------------------------- |
| `Provider`              | Repository instances, use case instances     | `patientRepositoryProvider`, `searchPatientsUseCaseProvider` |
| `FutureProvider`        | One-shot async data fetching                 | `patientByIdProvider(id)`                                |
| `StreamProvider`        | Realtime data (Supabase subscriptions)       | `appointmentQueueProvider(branchId)`                     |
| `AsyncNotifierProvider` | Mutable async state with actions             | `appointmentListNotifierProvider` (load, create, cancel) |
| `NotifierProvider`      | Synchronous mutable state                    | `selectedBranchProvider`, `themeProvider`                |

#### State Architecture Pattern

```
UI Widget
    │ reads/watches
    ▼
Riverpod Provider (AsyncNotifier)
    │ ref.read(useCaseProvider)
    ▼
Use Case (domain/usecases/)
    │ calls repository interface
    ▼
Repository Interface (domain/repositories/)
    │ implemented by
    ▼
RepositoryImpl (data/)
    │ calls
    ▼
Supabase SDK (data source)
```

#### Branch Context

A global `activeBranchProvider` holds the currently selected branch. All branch-scoped data providers depend on this. When the user switches branches, all dependent providers automatically refresh.

```dart
// Simplified example
final activeBranchProvider = NotifierProvider<ActiveBranchNotifier, Branch>(...);

final appointmentListProvider = AsyncNotifierProvider<AppointmentListNotifier, List<Appointment>>(() {
  // Watches activeBranchProvider internally
  // Re-fetches when branch changes
});
```

### Supabase Configuration and Startup

Configuration is resolved from a `deployment-profile.json` file bundled alongside the app (or loaded from a platform-specific location):

```dart
class DeploymentProfile {
  final DeploymentMode deploymentMode;  // currently only `local`
  final Uri supabaseUrl;                // e.g., "http://192.168.1.100:54321"
  final String supabaseAnonKey;
  final Uri? aiServiceUrl;              // e.g., "http://192.168.1.100:8090"
  final SourceDeviceRole? sourceDeviceRole;  // server-node or client-node
}

class SupabaseConfig {
  final Uri url;
  final String anonKey;
  final Uri? aiServiceUrl;

  factory SupabaseConfig.fromDeploymentProfile(DeploymentProfile profile) { ... }
}
```

The startup sequence is managed by a `StartupNotifier`:
1. Load deployment profile from JSON file.
2. Probe Supabase health endpoints (`/auth/v1/health`, `/rest/v1/`).
3. Initialize `SupabaseBootstrap.ensureInitialized(config)` with `EmptyLocalStorage` (no session persistence).
4. Transition to login page.

Health probes run before Supabase SDK initialization to provide clear error messages when the backend is unreachable.

### Session Lifecycle

- **No cross-restart persistence**: `EmptyLocalStorage` ensures reopening the app never restores a prior session. Staff must sign in on every app launch (shared workstation security model).
- **Idle timeout**: A configurable idle timer (default 15 minutes) signs out the user automatically. Configurable per-device via settings UI (1–120 minutes).
- **Session context**: After sign-in, the app decodes JWT custom claims to build an `AuthSessionContext` containing `StaffProfile`, `organizationId`, `branchIds`, `activeBranchId`, and cached `permissions`.

### Desktop-First UX Principles

| Principle                  | Implementation                                                                                                                        |
| -------------------------- | ------------------------------------------------------------------------------------------------------------------------------------- |
| **Keyboard efficiency**    | Tab-order optimization, keyboard shortcuts for common actions (Ctrl+N for new patient, Ctrl+B for book appointment), focus management |
| **Dense layouts**          | Master-detail panels, split views, data tables with inline actions. No excessive whitespace.                                          |
| **Operational speed**      | Prefetched dropdown data, debounced search, optimistic UI updates, minimal navigation depth                                           |
| **Receptionist workflows** | Appointment queue as a persistent sidebar, quick patient search with recent patients, one-click check-in                              |
| **Modern design**          | Material 3 theming, consistent spacing, professional typography, subtle animations                                                    |
| **Window management**      | Responsive to window resizing, minimum window size constraints, state persisted across sessions                                       |

### Navigation Architecture

A shell layout with persistent sidebar navigation:

```
┌────────┬─────────────────────────────────────────┐
│        │                                         │
│  SIDE  │          CONTENT AREA                   │
│  BAR   │                                         │
│        │  ┌─────────────────┬─────────────────┐  │
│ [Home] │  │  Master List    │  Detail Panel   │  │
│ [Appt] │  │                 │                 │  │
│ [Ptnt] │  │                 │                 │  │
│ [Bill] │  │                 │                 │  │
│ [Shift]│  │                 │                 │  │
│ [AI]   │  │                 │                 │  │
│ [...]  │  └─────────────────┴─────────────────┘  │
│        │                                         │
│        ├─────────────────────────────────────────┤
│ [Gear] │  Status Bar: Branch | User | Connection │
└────────┴─────────────────────────────────────────┘
```

Navigation is router-based (GoRouter). Deep links are supported for future web deployment.

---
