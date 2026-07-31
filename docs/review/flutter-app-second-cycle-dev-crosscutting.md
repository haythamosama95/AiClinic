# Flutter App Second-Cycle Review — Dev Tooling & Cross-Cutting

**Review date:** 2026-07-05 (second cycle)  
**Scope:** `frontend/lib/app/shell/dev/`, `shell_dev_integration.dart`, dev seed ↔ router integration, `pubspec.yaml` dev assets, app-layer feature imports, `frontend/test/**/shell_dev*` and seed tests  
**Methodology:** `/home/haytham/Desktop/AiClinic/docs/review/prompt.md`  
**First-cycle sources:** `flutter-app-feature-review.md` (C1, C2, H12–H14, H18, M23–M25, D10, T9–T11), `flutter-app-review-dev-crosscutting.md`

---

## Executive Summary

Second-cycle verification re-read all 10 files under `frontend/lib/app/shell/dev/`, router integration hooks, `pubspec.yaml`, cross-cutting app imports, and 5 related test files. **None of the first-cycle Critical/High/Medium dev findings have been fixed.** The ~600-line seed engine remains unreachable from the UI; `DevClinicSeedService.run()` still has no client-side `kDebugMode` guard; ~797 KB of dev JSON assets still ship in all build modes; reset-database metadata is still dead; redirect suppression still bypasses the full auth stack during seed; the overlay still hides progress text.

**7 new findings** were identified: router redirect churn on every progress tick, a public unguarded service provider, violated documented integration boundary, a dead parallel setup dev UI stub, misleading security tests, post-seed setup-state divergence, and app-layer imports of feature presentation providers.

**Verdict:** Dev tooling is still **engine-only, not productized**. Cross-cutting CA boundaries remain porous (8 feature data imports in dev notifier, presentation imports in app shell, unused `repository_providers.dart`).

| Category | First-cycle (dev scope) | Fixed | Still open | Downgraded | New |
|----------|-------------------------|-------|------------|------------|-----|
| Critical | 2 | 0 | 2 | 0 | 0 |
| High | 6 | 0 | 6 | 0 | 3 |
| Medium | 4 (+D10) | 0 | 5 | 0 | 4 |
| Test gaps | 3 | 0 | 3 | 0 | 2 |

---

## First-Cycle Triage

### Critical

#### C1 — Dev seed and reset actions have no UI entry point → **STILL OPEN**

**Evidence (re-verified):**

- `ShellDevFillDummyClinic.handleNavSelection` / `confirmAndRun` exist but have **zero call sites** outside their definition file:

```28:34:frontend/lib/app/shell/dev/shell_dev_fill_dummy_clinic.dart
  static Future<void> handleNavSelection(BuildContext context, WidgetRef ref) async {
    if (!isEnabled) {
      return;
    }

    await confirmAndRun(context, ref);
  }
```

- Sidebar footer exposes only a single `dev` item routing to design system — not `ShellDevNav.footerItemIds`:

```55:60:frontend/lib/app/shell/navigation/shell_nav_config.dart
  static List<ShellNavItem> footerItems() {
    final items = <ShellNavItem>[const ShellNavItem(id: 'settings', label: 'Settings', icon: Icons.settings_outlined)];

    if (ShellDevNav.isEnabled) {
      items.add(const ShellNavItem(id: 'dev', label: 'Dev', icon: Icons.science_outlined));
    }
```

- `AuthenticatedShell.onNavigate` only calls `context.go(route)` — no dev-action dispatch:

```60:65:frontend/lib/app/shell/authenticated_shell.dart
        onNavigate: (itemId) {
          final route = ShellNavConfig.routeFor(itemId);
          if (route != null) {
            context.go(route);
          }
        },
```

- Parallel dead path: `SetupDevWidgets.panel` accepts `onFillDummy` / `onResetInstallation` but always returns `SizedBox.shrink()` and has **no consumers** in the codebase.

**Impact unchanged:** ~1,200 LOC seed engine unreachable in running app.

---

#### C2 — `DevClinicSeedService.run()` lacks client-side debug guard → **STILL OPEN**

**Evidence:**

- Notifier guards `kDebugMode`:

```61:64:frontend/lib/app/shell/dev/dev_clinic_seed_notifier.dart
  Future<bool> fillDummyClinic() async {
    if (!kDebugMode) {
      return false;
    }
```

- Service `run()` has **no** `kDebugMode` check — only bootstrap-admin:

```75:82:frontend/lib/app/shell/dev/dev_clinic_seed_service.dart
  Future<void> run({
    required AuthSessionContext auth,
    required Future<void> Function() refreshSession,
    DevClinicSeedProgress? onProgress,
  }) async {
    if (!auth.staffProfile.isBootstrapAdmin) {
      throw StateError('Only the bootstrap administrator can fill dummy clinic data.');
    }
```

- `devClinicSeedServiceProvider` is a public `Provider` — any future/test code can call `run()` directly, bypassing the notifier guard.

**Impact unchanged:** Profile builds or direct service invocation can trigger destructive wipe against dev/staging backends.

---

### High

#### H12 — Dev assets bundled in production (~796 KB) → **STILL OPEN**

**Evidence:**

```94:98:frontend/pubspec.yaml
  assets:
    - assets/images/patient_avatar_female.png
    - assets/images/patient_avatar_male.png
    - assets/dev/egyptian_medication_names.json
    - assets/dev/egyptian_investigation_names.json
```

File sizes confirmed: `egyptian_medication_names.json` = **792,712 bytes**; `egyptian_investigation_names.json` = **3,828 bytes** (~797 KB total). Assets are unconditional — no flavor or `kDebugMode` gating.

---

#### H13 — `resetDatabaseId` declared but completely unwired → **STILL OPEN**

**Evidence:**

```12:27:frontend/lib/app/shell/dev/shell_dev_nav.dart
  static const resetDatabaseId = 'reset-database';
  ...
  static List<String> get footerItemIds => [
    themeShowcaseId,
    if (ShellDevFillDummyClinic.isEnabled) ShellDevFillDummyClinic.itemId,
    resetDatabaseId,
  ];
```

- No `routeFor` entry for `reset-database`
- No handler anywhere in `lib/`
- `setupNotifier.resetInstallationForDevelopment()` exists but is never called from shell/dev code
- `labelFor` advertises `'Reset Database'` — misleading API surface

---

#### H14 — Auth redirect suppression during seed masks session problems → **STILL OPEN**

**Evidence:**

```47:53:frontend/lib/app/shell/dev/shell_dev_integration.dart
bool shellDevSuppressAuthRedirect(Ref ref, AuthSessionState auth) {
  if (!kDebugMode || !auth.isAuthenticated) {
    return false;
  }

  return ref.read(devClinicSeedProvider).inProgress;
}
```

```199:201:frontend/lib/app/router.dart
    if (shellDevSuppressAuthRedirect(ref, auth)) {
      return null;
    }
```

When `inProgress`, **all** redirect logic (startup FSM, permission guards, bootstrap redirects) is skipped. Partial mitigation: sign-out sets `auth.isAuthenticated == false`, which stops suppression — but stale `authenticated` context during JWT expiry or failed `refreshSession` mid-seed is not handled.

**Not downgraded** — risk remains for multi-minute seeds.

---

#### H17 — No automated test for `DevClinicSeedService` orchestration → **STILL OPEN** (tracked under T9)

No test file references `DevClinicSeedService` or `dev_clinic_seed_service.dart` in `frontend/test/`.

---

#### H18 — Seed progress message not shown to user → **STILL OPEN**

**Evidence:**

- Notifier updates `progressMessage` on every phase (`dev_clinic_seed_notifier.dart:87`)
- Overlay renders only a spinner — never reads `seed.progressMessage` or `seed.errorMessage`:

```14:27:frontend/lib/app/shell/dev/dev_clinic_seed_overlay.dart
  final seed = ref.watch(devClinicSeedProvider);
  if (!seed.inProgress) {
    return child;
  }

  return Stack(
    fit: StackFit.expand,
    children: [
      AbsorbPointer(absorbing: true, child: child),
      const ColoredBox(
        color: Color(0xB3000000),
        child: Center(child: CircularProgressIndicator()),
      ),
    ],
  );
```

---

### Medium

#### M23 / D10 — Duplicate Egyptian asset loader implementations → **STILL OPEN**

Both `dev_egyptian_medications_asset.dart` and `dev_egyptian_investigations_asset.dart` contain identical `loadNames()` and `batchesFor()` implementations differing only in `assetPath` and default `batchSize` (1000 vs 500). No shared abstraction exists.

---

#### M24 — Design system route registered in all build modes → **STILL OPEN**

```60:60:frontend/lib/app/router.dart
      GoRoute(path: AppRoutes.foundationDemo, builder: (context, state) => const DesignSystemPage()),
```

Always registered. Redirect gating (`ShellDevNav.allowsOpenAccess` → `kDebugMode`) blocks release access, but route surface and `DesignSystemPage` import remain in release builds.

---

#### M25 — Seed operation has no cancellation → **STILL OPEN**

`DevClinicSeedService.run()` is one uninterruptible async sequence from wipe through 384+ sequential RPCs. Overlay uses `AbsorbPointer` with no cancel control. No cancel token between phases.

---

#### M22 — Dev seed app-layer coupling to 8 features → **STILL OPEN**

`dev_clinic_seed_notifier.dart` imports 8 feature **data** repositories directly (lines 8–15), bypassing the documented `repository_providers.dart` barrel. Additionally imports 2 feature **presentation** modules (see H2-D-03).

---

### Test Gaps (T9–T11)

| ID | Finding | Status | Evidence |
|----|---------|--------|----------|
| **T9** | No `DevClinicSeedService` orchestration test | **STILL OPEN** | `grep DevClinicSeedService frontend/test` → 0 matches |
| **T10** | No test asserting dev UI renders dev actions | **STILL OPEN** | No widget test for `AuthenticatedShell` / `DesignSystemPage` dev panel; `shell_dev_security_test.dart` only checks metadata |
| **T11** | No service-layer debug guard test | **STILL OPEN** | No test asserting `run()` rejects outside debug |

**Existing positive coverage:** `shell_dev_security_test.dart`, `dev_clinic_seed_spec_test.dart`, `dev_clinic_seed_schedule_test.dart`, `dev_egyptian_*_asset_test.dart`.

---

## New Critical Issues

*None identified beyond still-open C1 and C2.*

---

## New High Priority Issues

### H2-D-01 — Router redirect re-evaluates on every seed progress tick

| Field | Detail |
|-------|--------|
| **Severity** | High (performance / stability) |
| **Files** | `shell_dev_integration.dart`, `router.dart`, `dev_clinic_seed_notifier.dart` |
| **Evidence** | `shellDevListenForRouterRefresh` listens to **all** `DevClinicSeedState` changes: `ref.listen<DevClinicSeedState>(devClinicSeedProvider, (_, _) => onChanged())` (`shell_dev_integration.dart:43`). Notifier updates `progressMessage` dozens of times during seed (`dev_clinic_seed_notifier.dart:86-88`; service reports every 10th patient, every 25th appointment, etc.). Each update increments `refreshSignal` (`router.dart:30`), re-running the full ~130-line redirect closure. |
| **Why** | Progress reporting and router refresh share the same listenable. |
| **Impact** | Hundreds of redirect re-evaluations during a multi-minute seed; unnecessary rebuilds; fragile if redirect gains side effects (M1). |
| **Solution** | Listen only to `inProgress` changes (`ref.listen(devClinicSeedProvider.select((s) => s.inProgress), ...)`), or remove router refresh dependency on progress entirely. |

---

### H2-D-02 — Public `devClinicSeedServiceProvider` exposes unguarded destructive API

| Field | Detail |
|-------|--------|
| **Severity** | High (defense-in-depth; amplifies C2) |
| **Files** | `dev_clinic_seed_notifier.dart`, `dev_clinic_seed_service.dart` |
| **Evidence** | `final devClinicSeedServiceProvider = Provider<DevClinicSeedService>(...)` is top-level public (`dev_clinic_seed_notifier.dart:42-53`). Service `run()` immediately calls `_bootstrap.resetInstallationForDevelopment()` (`dev_clinic_seed_service.dart:89-90`) with no `kDebugMode` guard. Only consumer today is the notifier, but the provider is injectable from any Riverpod scope. |
| **Why** | Provider visibility + missing service guard = bypass path for C2. |
| **Impact** | Integration tests, future features, or profile builds can invoke wipe without notifier's `kDebugMode` gate. |
| **Solution** | Add `kDebugMode` guard in `run()`; mark provider `@visibleForTesting` or move behind notifier-only accessor; add T11 test. |

---

### H2-D-03 — App-layer dev notifier imports feature presentation providers

| Field | Detail |
|-------|--------|
| **Severity** | High (CA boundary) |
| **Files** | `dev_clinic_seed_notifier.dart` |
| **Evidence** | Direct imports of presentation-layer modules: `appointment_surface_invalidation.dart` (line 16), `setup_notifier.dart` (line 17). Post-seed calls `ref.read(setupNotifierProvider.notifier).markSetupComplete()` and `invalidateAppointmentSurfaceProviders(ref)`. |
| **Why** | App composition root should orchestrate via domain ports, not feature presentation notifiers. |
| **Impact** | Dev seed coupled to setup wizard UI state and appointment presentation cache; feature presentation refactors break app shell. |
| **Solution** | Extract `DevSeedCompletionPort` in app or `features/setup/application/`; invalidate via domain events or narrow app-layer facade. |

---

## New Medium Priority Issues

### M2-D-01 — Documented dev integration boundary is violated

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **Files** | `shell_dev_integration.dart`, `router.dart`, `shell_nav_config.dart` |
| **Evidence** | `shell_dev_integration.dart:11` states: *"Production code should import only this file from `lib/app/shell/dev/`."* Yet `router.dart` imports both `shell_dev_integration.dart` **and** `shell_dev_nav.dart` (lines 13-14); `shell_nav_config.dart` imports `shell_dev_nav.dart` directly (line 4). |
| **Why** | Integration facade documented but not enforced. |
| **Impact** | Production removal checklist incomplete; dev symbols leak into router and nav config. |
| **Solution** | Re-export `ShellDevNav` APIs through `shell_dev_integration.dart`; update router/nav to import only the facade. |

---

### M2-D-02 — `SetupDevWidgets.panel` is a dead parallel dev UI stub

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **Files** | `features/setup/presentation/dev/setup_dev_widgets.dart` |
| **Evidence** | `panel(...)` requires `onFillDummy` and `onResetInstallation` callbacks but always returns `SizedBox.shrink()` even in debug (lines 14-15). Zero call sites in codebase. |
| **Why** | Second dev UI entry point started but never completed — parallel to C1. |
| **Impact** | Developers may wire bootstrap wizard to this API expecting functional panel; duplicates dev surface area. |
| **Solution** | Implement panel or delete file; if kept, wire to `ShellDevFillDummyClinic` and `resetInstallationForDevelopment()`. |

---

### M2-D-03 — Security test DV-S-002 gives false confidence on UI wiring

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **Files** | `shell_dev_security_test.dart` |
| **Evidence** | Test `'DV-S-002: Fill Dummy Clinic nav item visible in debug builds'` asserts `ShellDevNav.footerItemIds` contains `fill-dummy-clinic` (lines 35-36) — metadata only. Does not render `AuthenticatedShell`, tap nav, or verify `handleNavSelection` is reachable. Would pass while C1 remains broken. |
| **Why** | Test validates data structure, not product wiring. |
| **Impact** | CI green while primary dev workflow unreachable (would have caught C1). |
| **Solution** | Widget test: pump shell in debug → navigate to dev options → tap fill → assert dialog; or rename test to clarify it checks metadata only. |

---

### M2-D-04 — Post-seed `markSetupComplete()` diverges from JWT `setupRequired`

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **Files** | `dev_clinic_seed_notifier.dart`, `setup_notifier.dart` |
| **Evidence** | After service completes, notifier calls `ref.read(setupNotifierProvider.notifier).markSetupComplete()` (`dev_clinic_seed_notifier.dart:91`). `markSetupComplete()` only sets local `SetupWizardStep.complete` (`setup_notifier.dart:180-182`) — does not read `auth.context.setupRequired`. Service calls `refreshSession` internally but setup notifier is independent. |
| **Why** | Two sources of setup-complete truth (local wizard vs JWT). |
| **Impact** | Brief window where wizard shows complete but router may still redirect to `/bootstrap` if JWT lags; race on cold start after seed. |
| **Solution** | Derive bootstrap allowance from `auth.context.setupRequired`; call `markSetupComplete` only after verified `refreshSessionContext` shows `!setupRequired`. |

---

### M2-D-05 — `repository_providers.dart` is completely unused dead code

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **Files** | `providers/repository_providers.dart`, `dev_clinic_seed_notifier.dart` |
| **Evidence** | File documents: *"Features that need access to repositories from other features should import from here"* and exports 3 providers. `grep repository_providers frontend/` → **zero imports**. Dev seed imports 8 repos directly from `features/*/data/`. |
| **Why** | Barrel started but never adopted. |
| **Impact** | Misleading documented DI path; scattered cross-feature import graph. |
| **Solution** | Expand barrel and migrate dev seed imports, or delete file and update docs. |

---

## Cross-Cutting: App-Layer Feature Import Map

| File | Feature imports | Layer | CA concern |
|------|-----------------|-------|------------|
| `dev_clinic_seed_notifier.dart` | 8× `features/*/data/*_repository.dart` | Data | Bypasses `repository_providers.dart` |
| `dev_clinic_seed_notifier.dart` | `setup_notifier`, `appointment_surface_invalidation` | **Presentation** | H2-D-03 |
| `dev_clinic_seed_service.dart` | Domain repos + 2 data impl imports | Mixed | Acceptable for orchestrator; belongs in feature layer long-term |
| `auth_session_provider.dart` | `auth_repository`, `permission_repository`, `idle_timeout_preferences_store` | Data | CA3 (unchanged) |
| `authenticated_shell.dart` | `appointment_queue_provider` | Presentation | CA5 (unchanged) |
| `router.dart` | `design_system_page`, `setup_notifier` | Presentation | Composition-root pattern |
| `app_navigator.dart` | Feature domain + presentation route extras | Mixed | CA4 (unchanged) |
| `session_context_loader.dart` | Domain only | OK | — |

---

## Test Gaps (Second Cycle)

| ID | Gap | Severity | Status |
|----|-----|----------|--------|
| T9 | `DevClinicSeedService` orchestration (call order, error propagation, bootstrap-admin guard) | High | **STILL OPEN** |
| T10 | Widget test: dev actions visible and invocable from shell/design system | Medium | **STILL OPEN** |
| T11 | `run()` throws/rejects outside `kDebugMode` | Medium | **STILL OPEN** |
| **T2-D-01** | Router refresh count during seed — assert `inProgress`-only listen | Medium | **NEW** |
| **T2-D-02** | `reset-database` in `footerItemIds` has no executability test (only fill-dummy checked) | Medium | **NEW** |

---

## Recommended Fix Order

### Phase 1 — Unblock dev workflow (P0)

1. **Wire dev UI (C1, H13)** — Add `DevOptionsSection` to `DesignSystemPage` or shell footer submenu rendering `ShellDevNav.footerItemIds`; dispatch `fill-dummy-clinic` → `ShellDevFillDummyClinic.handleNavSelection`; dispatch `reset-database` → confirm → `setupNotifier.resetInstallationForDevelopment()`.
2. **Harden service (C2, H2-D-02)** — `if (!kDebugMode) throw StateError(...)` at top of `run()`; add T11.
3. **Fix overlay UX (H18)** — Display `seed.progressMessage` and failure `errorMessage`.

### Phase 2 — Stability during seed (P1)

4. **Narrow redirect suppression (H14)** — Suppress only bootstrap/setup redirects, not auth-failure paths; abort seed on sign-out.
5. **Fix router refresh churn (H2-D-01)** — Listen to `inProgress` only.
6. **Sync setup state (M2-D-04)** — Verify JWT before `markSetupComplete()`.

### Phase 3 — Build hygiene & architecture (P2)

7. **Conditional dev assets (H12)** — Debug flavor or lazy load; remove from release `pubspec.yaml`.
8. **Service orchestration tests (T9)** — Fake repos; verify wipe → org → branches → patients → appointments order.
9. **Widget wiring test (T10, M2-D-03)** — Replace metadata-only DV-S-002 with real UI test.
10. **CA cleanup** — Enforce `shell_dev_integration.dart` single import (M2-D-01); adopt or delete `repository_providers.dart` (M2-D-05); extract `DevSeedPort` (M22/H2-D-03).
11. **Extract shared asset loader (M23/D10)**; add seed cancellation (M25).
12. **Delete or implement `SetupDevWidgets` (M2-D-02)**.

---

## Files Reviewed (Complete List)

| Path | Lines reviewed |
|------|----------------|
| `frontend/lib/app/shell/dev/shell_dev_integration.dart` | Full |
| `frontend/lib/app/shell/dev/shell_dev_nav.dart` | Full |
| `frontend/lib/app/shell/dev/shell_dev_fill_dummy_clinic.dart` | Full |
| `frontend/lib/app/shell/dev/dev_clinic_seed_notifier.dart` | Full |
| `frontend/lib/app/shell/dev/dev_clinic_seed_service.dart` | Full |
| `frontend/lib/app/shell/dev/dev_clinic_seed_overlay.dart` | Full |
| `frontend/lib/app/shell/dev/dev_clinic_seed_spec.dart` | Partial (header + structure) |
| `frontend/lib/app/shell/dev/dev_clinic_seed_schedule.dart` | Partial (offsets + structure) |
| `frontend/lib/app/shell/dev/dev_egyptian_medications_asset.dart` | Full |
| `frontend/lib/app/shell/dev/dev_egyptian_investigations_asset.dart` | Full |
| `frontend/lib/app/shell/navigation/shell_nav_config.dart` | Dev-related sections |
| `frontend/lib/app/shell/authenticated_shell.dart` | Full |
| `frontend/lib/app/router.dart` | Dev hooks + foundationDemo route |
| `frontend/lib/app/providers/repository_providers.dart` | Full |
| `frontend/pubspec.yaml` | Assets section |
| `frontend/lib/features/setup/presentation/dev/setup_dev_widgets.dart` | Full |
| `frontend/test/unit/shell/shell_dev_security_test.dart` | Full |
| `frontend/test/unit/shell/dev_clinic_seed_spec_test.dart` | Confirmed exists |
| `frontend/test/unit/shell/dev_clinic_seed_schedule_test.dart` | Confirmed exists |
| `frontend/test/unit/shell/dev_egyptian_medications_asset_test.dart` | Full |
| `frontend/test/unit/shell/dev_egyptian_investigations_asset_test.dart` | Confirmed exists |

---

*Second-cycle dev & cross-cutting review — 2026-07-05.*
