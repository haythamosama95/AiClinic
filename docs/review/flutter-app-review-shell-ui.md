# App Feature Review — Shell UI & Layout

## Summary

The shell layer is a well-structured presentation frame: pure layout widgets (`AppShell`, nav components), a thin Riverpod orchestrator (`AuthenticatedShell`), and a static nav config. Token usage, responsive breakpoints, and directional layout are generally sound.

The main gaps are **integration correctness**, not widget polish:

1. **Navigation model drift** — sidebar shows all items regardless of permissions; several items have no routes; duplicate items (`home`/`dashboard`, `billing`/`invoices`) disagree on active-state resolution.
2. **Branch switcher fragility** — branch selection is in-memory only and is **wiped** on `reloadContext()` / token refresh (including app resume).
3. **Misnamed / over-broad shell** — `AuthenticatedShell` wraps login, bootstrap, and startup routes with full sidebar + top bar.
4. **Incomplete features** — queue badge warming runs but count is never bound to nav; command bar and notifications are non-functional placeholders.
5. **Zero widget/unit tests** for any of the reviewed shell files.

No **Critical** (crash/data-corruption) issues were found in these files alone, but branch reset on resume is a serious **clinical-scope** risk (HIGH).

---

## Files Reviewed

| File | Lines | Role |
|------|-------|------|
| `frontend/lib/app/shell/authenticated_shell.dart` | 84 | Riverpod orchestrator |
| `frontend/lib/app/shell/layout/app_shell.dart` | 58 | Layout frame |
| `frontend/lib/app/shell/navigation/app_top_bar.dart` | 153 | Top chrome |
| `frontend/lib/app/shell/navigation/app_sidebar.dart` | 318 | Sidebar + keyboard nav |
| `frontend/lib/app/shell/navigation/shell_nav_config.dart` | 138 | Nav tree + route mapping |
| `frontend/lib/app/shell/navigation/shell_nav_model.dart` | 40 | Data models |
| `frontend/lib/app/shell/navigation/app_command_bar_trigger.dart` | 73 | Search placeholder |
| `frontend/lib/app/shell/navigation/app_branch_switcher.dart` | 104 | Branch menu |
| `frontend/lib/app/shell/navigation/app_user_menu.dart` | 81 | Account menu |
| `frontend/lib/app/shell/providers/shell_sidebar_collapsed_provider.dart` | 32 | Collapse persistence |

---

## Findings

### Critical

*None in reviewed files.*

---

### High

#### H-1: Sidebar shows all nav items without permission gating

| | |
|---|---|
| **Severity** | High |
| **Files** | `authenticated_shell.dart`, `shell_nav_config.dart` |
| **Evidence** | `AuthenticatedShell` passes static `ShellNavConfig.groups` with no filtering (lines 52–54). No permission checks anywhere in shell nav. Router guards block direct URL access (`auth_route_guard.dart`), but sidebar always renders Patients, Billing, Staff, etc. |
| **Why** | Nav config is static; unlike `SettingsTabs.visibleFor(auth)` which filters by `AuthRouteGuard`, shell nav has no equivalent. |
| **Impact** | Users see destinations they cannot access; clicks redirect or show blocked content — confusing and undermines permission model UX. Keyboard nav (sidebar lines 60–88) can cycle through forbidden routes. |
| **Solution** | Add `ShellNavConfig.visibleGroupsFor(PermissionService)` (or `AuthSessionState`) mirroring `AuthRouteGuard` rules; filter `groups` and `footerItems` in `AuthenticatedShell`. |

---

#### H-2: Four sidebar items are dead — no route binding

| | |
|---|---|
| **Severity** | High |
| **Files** | `shell_nav_config.dart`, `authenticated_shell.dart` |
| **Evidence** | Items `encounters`, `workspace`, `reports` exist in `groups` (lines 37–38, 50) but are absent from `_routesByItemId`. `routeFor` returns `null`; `onNavigate` silently no-ops (authenticated_shell.dart lines 60–64). |
| **Why** | Placeholder nav entries added before routes existed. |
| **Impact** | Click and keyboard navigation appear broken with no feedback. |
| **Solution** | Remove until routes exist, or add routes + guards. Disable items visually and exclude from keyboard nav when `routeFor` is null. |

---

#### H-3: Branch selection resets on session context reload

| | |
|---|---|
| **Severity** | High |
| **Files** | `authenticated_shell.dart`, `branch_selection_notifier.dart`, `auth_session_provider.dart`, `session_context_loader.dart` |
| **Evidence** | `setActiveBranch` only mutates in-memory state (`auth_session_provider.dart` line 231). `refreshSessionContext` / token refresh replace context from `SessionContextLoader.load`, which sets `activeBranchId` to DB primary (session_context_loader.dart lines 52–63, 83). `app.dart` calls `reloadContext()` on app resume (line 53). |
| **Why** | Branch choice is not preserved across reload paths. |
| **Impact** | User switches branch, backgrounds app, resumes → silently reverts to primary branch. Feature providers (`patient_list_notifier`, `appointment_queue_provider`) key off `activeBranchId` — wrong-branch data risk without UI indication. |
| **Solution** | Preserve prior `activeBranchId` in `refreshSessionContext` / `_handleAuthState` when still in `branchIds`; or persist selection in `SharedPreferences` / server-side preference. |

---

#### H-4: `AuthenticatedShell` wraps unauthenticated routes

| | |
|---|---|
| **Severity** | High |
| **Files** | `authenticated_shell.dart`, `router.dart` |
| **Evidence** | `ShellRoute` builder always returns `AuthenticatedShell` (router.dart line 39), including `login`, `bootstrap`, `startupCheck`. Shell always renders `AppSidebar` + `AppTopBar` with fallback labels `'Staff'`, `'Organization'`, `'Branch'` (authenticated_shell.dart lines 45–58). |
| **Why** | Single shell route for all pages. |
| **Impact** | Login/setup pages show full clinic chrome; nav items route to guarded pages → redirect loop confusion. Misleading for a component named `AuthenticatedShell`. |
| **Solution** | Conditionally render chrome when `auth.isAuthenticated && !context.setupRequired`, or split `ShellRoute` / use a minimal auth layout for pre-auth routes. |

---

#### H-5: Nav/route model inconsistencies — duplicate items, wrong active states

| | |
|---|---|
| **Severity** | High |
| **Files** | `shell_nav_config.dart` |
| **Evidence** | (1) `home` and `dashboard` both map to `AppRoutes.home` (lines 10–11). (2) `billing` and `invoices` both map to `AppRoutes.billingInvoices` (lines 14–15). (3) On `/billing/invoices`, `itemIdForLocation` exact-match loop returns `'billing'` first (lines 90–93); `'invoices'` never active on list page. (4) Settings sub-routes (`/settings/staff`, etc.) have no prefix handler in `itemIdForLocation` — footer Settings never highlights. (5) Visit routes (`/visits/...`) have no nav item or location mapping. |
| **Why** | Dual mapping + exact-match-first logic + incomplete prefix rules. |
| **Impact** | Two nav items per destination; only one highlights; settings deep links show no active nav; visits are invisible in chrome. |
| **Solution** | One canonical item per route; add `isSettingsLocation` to `itemIdForLocation`; add visit mapping or remove visit chrome expectation; document canonical IDs. |

---

### Medium

#### M-1: Branch display uses raw UUIDs, not human names

| | |
|---|---|
| **Severity** | Medium |
| **Files** | `authenticated_shell.dart`, `app_branch_switcher.dart`, `app_sidebar.dart` |
| **Evidence** | `ShellBranch(id: id, name: id, ...)` (authenticated_shell.dart line 41). `AuthSessionContext` has `branchIds` only — no names (`auth_session.dart`). Sidebar header shows `session?.activeBranchId ?? 'Branch'`. |
| **Impact** | Unusable branch switcher UX on multi-branch clinics. |
| **Solution** | Load branch names in session context or a `branchesProvider`; map IDs to display names. |

---

#### M-2: Branch switcher hidden below 768px with no fallback

| | |
|---|---|
| **Severity** | Medium |
| **Files** | `app_top_bar.dart` |
| **Evidence** | `AppBranchSwitcher` gated by `width >= 768` (lines 77–84). Not exposed in `AppUserMenu`. |
| **Impact** | Narrow/desktop-resized windows cannot switch branch. |
| **Solution** | Add branch entry to user menu or sidebar header on small widths. |

---

#### M-3: Queue badge warm provider never wired to sidebar

| | |
|---|---|
| **Severity** | Medium |
| **Files** | `authenticated_shell.dart`, `appointment_queue_provider.dart`, `shell_nav_model.dart` |
| **Evidence** | `appointmentQueueShellWarmProvider` watched (authenticated_shell.dart lines 25–27). `ShellNavItem.count` supported in sidebar (app_sidebar.dart line 294) but never set. Nav config appointments item has no `count`. |
| **Impact** | Unnecessary provider subscription and network work with no UI benefit. |
| **Solution** | Pass `count: ref.watch(appointmentQueueCheckedInCountProvider)` into appointments `ShellNavItem`, or remove warm provider until badge is implemented. |

---

#### M-4: Sidebar collapse state flashes on startup

| | |
|---|---|
| **Severity** | Medium |
| **Files** | `shell_sidebar_collapsed_provider.dart` |
| **Evidence** | `build()` returns `false`, then `Future.microtask(_load)` async-updates (lines 9–19). |
| **Impact** | Visible 200ms expand-then-collapse animation on every cold start when user prefers collapsed. |
| **Solution** | Use `AsyncNotifier` / `FutureProvider` so first paint reads persisted value, or block shell until prefs load. |

---

#### M-5: `AppCommandBarTrigger` is non-functional but looks interactive

| | |
|---|---|
| **Severity** | Medium |
| **Files** | `app_command_bar_trigger.dart`, `app_top_bar.dart` |
| **Evidence** | `AppCommandBarTrigger()` constructed without `onPressed` (app_top_bar.dart line 68). Shows `⌘K` hint (app_command_bar_trigger.dart lines 53–61) but no `Shortcuts`/`Actions` binding. |
| **Impact** | Dead control; false affordance; accessibility gap (no `Semantics` button role with disabled reason). |
| **Solution** | Wire command palette or mark disabled with `onPressed: null` styling and `ExcludeSemantics` until implemented. |

---

#### M-6: Notifications button always disabled

| | |
|---|---|
| **Severity** | Medium |
| **Files** | `app_top_bar.dart`, `authenticated_shell.dart` |
| **Evidence** | `onNotificationsPressed` defaults to `null`; `AuthenticatedShell` never passes a handler. `AppIconButton` passes null `onPressed` → disabled `IconButton`. |
| **Impact** | Visible but inert control. |
| **Solution** | Hide until implemented, or pass handler. |

---

#### M-7: Duplicate theme toggle in top bar and user menu

| | |
|---|---|
| **Severity** | Medium |
| **Files** | `app_top_bar.dart`, `app_user_menu.dart` |
| **Evidence** | Theme button at `width >= 480` (app_top_bar.dart lines 121–127); `MenuItemButton` "Toggle theme" always in user menu (app_user_menu.dart lines 63–67). Same `onToggleTheme` callback. |
| **Impact** | Redundant controls; menu item always present even when top-bar button visible. |
| **Solution** | Keep one surface; hide menu item when top-bar button is shown. |

---

#### M-8: `AppShell` forces `SingleChildScrollView` on all feature content

| | |
|---|---|
| **Severity** | Medium |
| **Files** | `app_shell.dart` |
| **Evidence** | `Expanded` → `SingleChildScrollView(primary: true)` wraps `child` (lines 32–46). `fullWidth` never used (only caller is `authenticated_shell.dart` without `fullWidth: true`). |
| **Impact** | Feature pages with own scrollables (lists, tables) get nested scroll conflicts; `primary: true` competes with child scroll views. |
| **Solution** | Let features own scrolling; use `child` directly in `Expanded`, or pass `scrollable: false` flag. |

---

#### M-9: Sidebar keyboard nav lacks selected-state semantics

| | |
|---|---|
| **Severity** | Medium |
| **Files** | `app_sidebar.dart` |
| **Evidence** | `_SidebarNavItem` uses `InkWell` + visual `active` styling; no `Semantics(selected: active)` or `aria-current` equivalent. Icon-only mode relies on `AppTooltip` only. |
| **Impact** | Screen readers may not announce current page. |
| **Solution** | Wrap nav rows in `Semantics(button: true, selected: active, label: item.label)`. |

---

### Low

#### L-1: `footerItems()` allocates a new list every build

| | |
|---|---|
| **Severity** | Low |
| **Files** | `shell_nav_config.dart`, `authenticated_shell.dart` |
| **Evidence** | `footerItems()` called in `build` (authenticated_shell.dart line 54). |
| **Solution** | Cache as `static final` or memoize in provider. |

---

#### L-2: `AppUserMenu` hardcodes `appVersion = '1.0.0'`

| | |
|---|---|
| **Severity** | Low |
| **Files** | `app_user_menu.dart` |
| **Evidence** | Default parameter line 12; never overridden by `AuthenticatedShell`. |
| **Solution** | Inject from `package_info_plus` or build config. |

---

#### L-3: `ShellUser.email` never populated

| | |
|---|---|
| **Severity** | Low |
| **Files** | `authenticated_shell.dart`, `shell_nav_model.dart`, `app_user_menu.dart` |
| **Evidence** | `ShellUser` created with `name` and `role` only; email UI conditional never renders. |
| **Solution** | Populate from session when available. |

---

#### L-4: `FocusNode` map grows without pruning

| | |
|---|---|
| **Severity** | Low |
| **Files** | `app_sidebar.dart` |
| **Evidence** | `_focusNodes.putIfAbsent` (line 53); no removal when items disappear. |
| **Impact** | Negligible today (static nav); leak if nav becomes dynamic. |

---

#### L-5: Single-branch switcher still shows dropdown affordance

| | |
|---|---|
| **Severity** | Low |
| **Files** | `app_branch_switcher.dart` |
| **Evidence** | `branches.length == 1` still renders `MenuAnchor` with `expand_more`. |
| **Solution** | Render static label when `branches.length <= 1`. |

---

### Clean Architecture Violations

#### CA-1: Shell orchestrator imports feature presentation provider

| | |
|---|---|
| **Severity** | Clean Architecture Violation |
| **Files** | `authenticated_shell.dart` |
| **Evidence** | `import '.../appointment_queue_provider.dart'` and `ref.watch(appointmentQueueShellWarmProvider)` (lines 15, 25–27). |
| **Why** | App shell (composition root) depends on appointments feature presentation layer. |
| **Solution** | Expose badge count via app-layer provider or callback injection; keep feature warming inside appointments module. |

---

#### CA-2: `ShellNavConfig` couples nav presentation to routing and dev tooling

| | |
|---|---|
| **Severity** | Clean Architecture Violation |
| **Files** | `shell_nav_config.dart` |
| **Evidence** | Single class holds `ShellNavGroup` UI data, `AppRoutes` bindings, `ShellDevNav` delegation, and title resolution. |
| **Solution** | Split `ShellRouteRegistry` (routes ↔ IDs) from `ShellNavCatalog` (labels/icons) and permission-filtered views. |

---

### SOLID Violations

#### S-1: Single Responsibility — `AuthenticatedShell` does too much

| | |
|---|---|
| **Severity** | SOLID Violation |
| **Files** | `authenticated_shell.dart` |
| **Evidence** | Composes shell, maps session → view models, warms feature providers, handles theme/sign-out/branch/nav. |
| **Solution** | Extract `ShellViewModel` provider producing `ShellChromeState`; keep widget as pure layout glue. |

---

#### S-2: Open/Closed — adding nav items requires editing multiple switch blocks

| | |
|---|---|
| **Severity** | SOLID Violation |
| **Files** | `shell_nav_config.dart` |
| **Evidence** | `_routesByItemId`, `groups`, and `itemIdForLocation` prefix rules maintained separately (lines 9–121). |
| **Solution** | Single declarative nav entry type: `{ id, label, icon, route, prefixMatch, permission }`. |

---

#### S-3: Duplicated `MenuAnchor` toggle pattern

| | |
|---|---|
| **Severity** | SOLID / Duplication |
| **Files** | `app_branch_switcher.dart`, `app_user_menu.dart` |
| **Evidence** | Identical `controller.isOpen ? close() : open()` in both builders (branch lines 44–49, user lines 37–42). |
| **Solution** | Shared `AppMenuAnchorTrigger` widget. |

---

### Duplication

#### D-1: Duplicate nav entries for same destination

| | |
|---|---|
| **Files** | `shell_nav_config.dart` |
| **Evidence** | `home`/`dashboard` → `/home`; `billing`/`invoices` → `/billing/invoices`. |
| **Solution** | Remove duplicates or merge into one item with alias routing only. |

---

#### D-2: Duplicate route-resolution logic

| | |
|---|---|
| **Files** | `shell_nav_config.dart`, `shell_dev_nav.dart` |
| **Evidence** | Both implement `routeFor`, `itemIdForLocation`, `labelFor` with map iteration. |
| **Solution** | Shared `NavRouteRegistry` base or composition. |

---

### Performance

#### P-1: Broad `ref.watch(authSessionProvider)` rebuilds entire shell

| | |
|---|---|
| **Files** | `authenticated_shell.dart` |
| **Evidence** | Full auth state watched (line 33); also `branchSelectionProvider` (line 70) which itself watches auth. |
| **Solution** | Use `select` for `context`, `isAuthenticated`, `activeBranchId`, `branchIds` separately. |

---

#### P-2: Conditional side-effect watch in `build`

| | |
|---|---|
| **Files** | `authenticated_shell.dart` |
| **Evidence** | `if (ref.watch(permissionServiceProvider).canAccessAppointments()) { ref.watch(appointmentQueueShellWarmProvider); }` |
| **Why** | Works in Riverpod but is an anti-pattern; couples build to side effects. |
| **Solution** | `ref.listen` in a `ConsumerStatefulWidget` `initState`, or dedicated `Provider` that depends on permission + queue. |

---

### Test Gaps

#### T-1: No tests for any reviewed shell file

| | |
|---|---|
| **Severity** | Test Gaps |
| **Files** | All 10 reviewed files |
| **Evidence** | `grep` for `AppSidebar`, `AuthenticatedShell`, `ShellNavConfig`, `shell_sidebar` in `frontend/test` — no matches. |
| **Solution** | Add unit tests for `ShellNavConfig.itemIdForLocation` / `pageTitleForLocation`; widget tests for collapse persistence, branch switcher empty/single/multi, permission-filtered nav, keyboard nav skipping dead items. |

---

#### T-2: No test for sidebar collapse persistence round-trip

| | |
|---|---|
| **Files** | `shell_sidebar_collapsed_provider.dart` |
| **Solution** | Provider test with mock `SharedPreferences`. |

---

### Refactoring

#### R-1: Introduce `ShellChromeController` (Riverpod)

Centralize: filtered nav, branch list with names, badge counts, collapse state, auth-gated chrome visibility.

#### R-2: Align with `SettingsTabs.visibleFor` pattern

Permission-filtered nav is already established in settings — reuse `AuthRouteGuard` + `PermissionService` for shell nav parity.

#### R-3: Split auth layout from app chrome

`router.dart` should use two shell builders or a route-meta flag (`showAppChrome: false` for login/bootstrap).

---

## Brief Summary — Critical / High

| ID | Finding |
|----|---------|
| **H-1** | Sidebar not permission-gated — all items visible to every authenticated user |
| **H-2** | `encounters`, `workspace`, `reports` have no routes — silent no-op on click |
| **H-3** | Branch selection lost on `reloadContext()` / token refresh / app resume |
| **H-4** | Full shell chrome shown on login, bootstrap, and startup routes |
| **H-5** | Duplicate nav items + `itemIdForLocation` logic → wrong/missing active highlights (settings sub-routes, billing/invoices) |
