# Frontend

- Purpose: Define the Flutter desktop architecture, feature layout, state management, and UX shell conventions.
- Read this when: implementing Flutter modules, app shell behavior, routing, Riverpod state, or Supabase configuration in the client.
- Canonical for: project structure, presentation/domain/data boundaries, Riverpod patterns, and desktop UX/navigation rules.
- Usually paired with: `docs/architecture/04-backend.md`, `docs/architecture/09-security-rbac.md`, and the feature spec being built.
- Not covered here: deployment internals, deep database design, or roadmap sequencing.

---

## Flutter Frontend Architecture

### Project Structure (Feature-First Clean Architecture)

```
frontend/lib/
├── main.dart
├── app/
│   ├── app.dart                    # MaterialApp, routing setup
│   ├── router.dart                 # GoRouter or auto_route configuration
│   └── theme/                      # Theme definitions, colors, typography
│
├── core/
│   ├── config/
│   │   └── supabase_config.dart    # Supabase URL/key resolution (local vs cloud)
│   ├── constants/                  # App-wide constants
│   ├── errors/
│   │   ├── failures.dart           # Failure classes
│   │   └── exceptions.dart         # Exception classes
│   ├── network/
│   │   └── ai_service_client.dart  # HTTP client for AI service
│   ├── utils/                      # Date formatters, validators, helpers
│   └── widgets/                    # Shared UI widgets (buttons, cards, dialogs)
│
├── features/
│   ├── auth/
│   │   ├── data/
│   │   │   ├── datasources/
│   │   │   │   └── auth_remote_datasource.dart
│   │   │   └── repositories/
│   │   │       └── auth_repository_impl.dart
│   │   ├── domain/
│   │   │   ├── entities/
│   │   │   │   └── staff_user.dart
│   │   │   ├── repositories/
│   │   │   │   └── auth_repository.dart
│   │   │   └── usecases/
│   │   │       ├── sign_in.dart
│   │   │       └── sign_out.dart
│   │   └── presentation/
│   │       ├── providers/
│   │       │   └── auth_provider.dart
│   │       ├── pages/
│   │       │   └── login_page.dart
│   │       └── widgets/
│   │           └── login_form.dart
│   │
│   ├── patients/
│   │   ├── data/
│   │   ├── domain/
│   │   └── presentation/
│   │
│   ├── appointments/
│   │   ├── data/
│   │   ├── domain/
│   │   └── presentation/
│   │
│   ├── visits/                     # Visits, SOAP notes, treatment plans
│   │   ├── data/
│   │   ├── domain/
│   │   └── presentation/
│   │
│   ├── billing/                    # Invoices, payments, insurance
│   │   ├── data/
│   │   ├── domain/
│   │   └── presentation/
│   │
│   ├── shifts/
│   │   ├── data/
│   │   ├── domain/
│   │   └── presentation/
│   │
│   ├── ai_chat/                    # AI interaction UI
│   │   ├── data/
│   │   ├── domain/
│   │   └── presentation/
│   │
│   ├── analytics/                  # Dashboards, reports
│   │   ├── data/
│   │   ├── domain/
│   │   └── presentation/
│   │
│   └── settings/                   # Organization, branch, staff management
│       ├── data/
│       ├── domain/
│       └── presentation/
│
└── shared/
    ├── models/                     # Shared DTOs (organization, branch, etc.)
    ├── providers/                  # Shared Riverpod providers
    └── services/                   # Cross-feature services
```

### Layer Responsibilities (Per Feature)

| Layer            | Directory       | Contains                                                                                                   | Depends On                                                    |
| ---------------- | --------------- | ---------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------- |
| **Presentation** | `presentation/` | Pages (screens), Widgets, Riverpod Providers (state notifiers, async notifiers)                            | Domain layer (use cases, entities)                            |
| **Domain**       | `domain/`       | Entities (pure Dart classes), Repository interfaces (abstract classes), Use cases (single-purpose classes) | Nothing (innermost layer)                                     |
| **Data**         | `data/`         | Repository implementations, Data sources (Supabase calls), DTOs (JSON serialization models)                | Domain layer (implements repository interfaces), Supabase SDK |

Dependency rule: dependencies point inward. Presentation depends on Domain. Data depends on Domain. Domain depends on nothing external.

### State Management with Riverpod

#### Provider Types by Use Case

| Riverpod Concept        | Use Case                                     | Example                                                  |
| ----------------------- | -------------------------------------------- | -------------------------------------------------------- |
| `Provider`              | Static/computed values, repository instances | `authRepositoryProvider`                                 |
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
    │ calls
    ▼
Use Case
    │ calls
    ▼
Repository (interface, injected)
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

### Supabase Configuration

A `SupabaseConfig` determines the connection target at app startup:

```dart
class SupabaseConfig {
  final String url;        // e.g., "http://192.168.1.100:54321" or "https://xyz.supabase.co"
  final String anonKey;    // Supabase anon/public key

  // Resolved from local config file or environment
  factory SupabaseConfig.fromLocalSettings() { ... }
}
```

The config is stored in a local settings file on each device. On first launch, the user (or a setup wizard) specifies whether this is a local or cloud deployment and enters the appropriate URL.

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
