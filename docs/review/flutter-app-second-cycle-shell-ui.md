# Flutter App — Second Cycle Shell UI Review

**Review date:** 2026-07-05 (second pass)  
**Scope:** `frontend/lib/app/shell/` (+ `ui_pending_placeholder_page.dart`, `session_activity_scope.dart` for integration context; `frontend/test/` shell-related tests)  
**Method:** Re-read methodology (`docs/review/prompt.md`), first-cycle findings (H5–H8, H15, M15–M18, S3–S4, D3–D5, D11, P3–P6, T4), direct code verification of every scoped file  
**Verdict:** Shell **presentation widgets are unchanged and polished**; **all first-cycle integration defects remain open**. One minor improvement (`pageTitleForLocation` for settings sub-routes) does not fix active-state or permission parity. **Zero shell widget/unit tests** were added.


---

## Executive Summary

The shell layer is structurally sound (layout tokens, responsive top bar, collapse animation, keyboard nav scaffold) but **integration correctness did not advance** since the first review:

| Theme | Second-cycle status |
|-------|---------------------|
| Permission-filtered nav | **STILL OPEN** — static `ShellNavConfig.groups` passed unfiltered |
| Dead nav items | **STILL OPEN** — `encounters`, `workspace`, `reports` have no routes |
| Auth-route chrome | **STILL OPEN** — `ShellRoute` always builds `AuthenticatedShell` |
| Branch switcher UX | **STILL OPEN** — raw UUIDs for branch names; hidden &lt;768px |
| Nav active-state bugs | **PARTIALLY ADDRESSED** — settings *titles* work; settings *footer highlight*, billing/home duplicates, visits still broken |
| Shell rebuild performance | **STILL OPEN** — broad `authSessionProvider` watch; conditional warm in `build` |
| Provider warming on wrong routes | **STILL OPEN** — gated by permission but not by route/auth chrome |
| Collapse persistence flash | **STILL OPEN** — sync default `false` then async prefs load |

**New findings:** 0 Critical, 1 High (org UUID in sidebar header), 5 Medium (keyboard nav gaps, billing active split, branch switcher mismatch).

**Recommended action:** Fix branch persistence (H4, cross-cutting) and permission-filtered nav (H5) before feature UI wiring. Add `ShellNavConfig` unit tests immediately — they would catch H6/H8 regressions cheaply.

---

## Files Re-verified

| File | Lines | Role |
|------|-------|------|
| `frontend/lib/app/shell/authenticated_shell.dart` | 84 | Riverpod orchestrator |
| `frontend/lib/app/shell/layout/app_shell.dart` | 58 | Layout frame |
| `frontend/lib/app/shell/navigation/app_sidebar.dart` | 318 | Sidebar + keyboard nav |
| `frontend/lib/app/shell/navigation/app_top_bar.dart` | 153 | Top chrome |
| `frontend/lib/app/shell/navigation/shell_nav_config.dart` | 138 | Nav tree + route mapping |
| `frontend/lib/app/shell/navigation/shell_nav_model.dart` | 40 | Data models |
| `frontend/lib/app/shell/navigation/app_branch_switcher.dart` | 104 | Branch menu |
| `frontend/lib/app/shell/navigation/app_user_menu.dart` | 81 | Account menu |
| `frontend/lib/app/shell/navigation/app_command_bar_trigger.dart` | 73 | Search placeholder |
| `frontend/lib/app/shell/providers/shell_sidebar_collapsed_provider.dart` | 32 | Collapse persistence |
| `frontend/lib/app/presentation/ui_pending_placeholder_page.dart` | 37 | Route placeholder (shell child) |
| `frontend/lib/app/session_activity_scope.dart` | 41 | Idle activity (app root; not shell chrome) |
| `frontend/lib/app/router.dart` (integration) | — | `ShellRoute` → `AuthenticatedShell` |
| `frontend/test/unit/shell/shell_dev_security_test.dart` | 115 | Dev security only; no shell UI tests |

---

## First-Cycle Triage

| ID | Severity | Finding | Status | Evidence |
|----|----------|---------|--------|----------|
| **H5** | High | Sidebar shows all nav items without permission gating | **STILL OPEN** | `AuthenticatedShell` passes `ShellNavConfig.groups` unchanged (lines 52–54). No `visibleGroupsFor` equivalent unlike `SettingsTabs.visibleFor` (`settings_tab.dart:44–46`). |
| **H6** | High | Dead sidebar items — no route binding | **STILL OPEN** | `encounters`, `workspace`, `reports` in `groups` (`shell_nav_config.dart:37–38,50`) absent from `_routesByItemId` (lines 9–21). `onNavigate` no-ops when `routeFor` returns null (`authenticated_shell.dart:60–64`). |
| **H7** | High | `AuthenticatedShell` wraps unauthenticated routes | **STILL OPEN** | `router.dart:38–39` — `ShellRoute` builder always returns `AuthenticatedShell`, including `login`, `bootstrap`, `startupCheck` (lines 41–54). No conditional chrome. |
| **H8** | High | Nav/route inconsistencies — duplicates, wrong active states | **PARTIALLY FIXED** | **Still open:** `home`/`dashboard` duplicate (`shell_nav_config.dart:10–11,27–28`); `billing`/`invoices` duplicate (14–15,45–46); exact-match loop returns `'billing'` before `'invoices'` (89–93); no visit mapping; settings footer never active on sub-routes. **Fixed (title only):** `isSettingsLocation` + `pageTitleForLocation` returns `'Settings'` for `/settings/*` (69–79) — footer `activeId` still null on sub-routes. |
| **H15** | High | Branch switcher displays raw branch UUIDs | **STILL OPEN** | `ShellBranch(id: id, name: id, ...)` (`authenticated_shell.dart:39–41`). `AuthSessionContext` has `branchIds` only, no names (`auth_session.dart:74–75`). Sidebar header also shows raw `activeBranchId` (line 58). |
| **H4** | High | Branch selection lost on reload (shell impact) | **STILL OPEN** | `SessionContextLoader.load` always sets `activeBranchId: primaryBranchId` (line 83). `tokenRefreshed` replaces full context (`auth_session_provider.dart:138–142`). `refreshSessionContext` same (292–294). `app.dart:53` calls `reloadContext()` on resume. |
| **M8** | Medium | Branch switcher hidden &lt;768px, no fallback | **STILL OPEN** | `app_top_bar.dart:77–84` gates `AppBranchSwitcher`; not in `AppUserMenu`. |
| **M9** | Medium | Queue warm provider never wired to badge | **STILL OPEN** | `appointmentQueueShellWarmProvider` watched (`authenticated_shell.dart:25–27`); `ShellNavItem.count` never set; appointments item has no count (`shell_nav_config.dart:36`). |
| **M10** | Medium | Sidebar collapse flashes on startup | **STILL OPEN** | `build()` returns `false`, `Future.microtask(_load)` async-updates (`shell_sidebar_collapsed_provider.dart:9–19`). |
| **M11** | Medium | Command bar non-functional but interactive | **STILL OPEN** | `AppCommandBarTrigger()` without `onPressed` (`app_top_bar.dart:68`); shows `⌘K` hint (`app_command_bar_trigger.dart:53–61`). |
| **M12** | Medium | Notifications button always disabled | **STILL OPEN** | `onNotificationsPressed` never passed from shell (`authenticated_shell.dart` omits it; `app_top_bar.dart:94` gets null). |
| **M13** | Medium | Duplicate theme toggle | **STILL OPEN** | Top bar at `width >= 480` (`app_top_bar.dart:121–127`); user menu always has "Toggle theme" (`app_user_menu.dart:63–67`). |
| **M14** | Medium | `AppShell` forces `SingleChildScrollView` | **STILL OPEN** | `app_shell.dart:35–46` wraps all children; `fullWidth` unused. |
| **M15** | Medium | Sidebar keyboard nav lacks selected semantics | **STILL OPEN** | `_SidebarNavItem` has visual `active` styling only; no `Semantics(selected: active)` (`app_sidebar.dart:254–312`). |
| **M16** | Medium | Connectivity startup-only | **STILL OPEN** *(out of shell files)* | Unchanged in `connectivity_provider.dart` / `startup_session_provider.dart`. |
| **M17** | Medium | Raw `error.toString()` in session failure UI | **STILL OPEN** *(out of shell files)* | `auth_session_provider.dart:165` still uses `error.toString()`. |
| **M18** | Medium | `clearBranch()` desyncs from auth session | **STILL OPEN** | `clearBranch` sets `state = null` only (`branch_selection_notifier.dart:26–28`); shell masks with `branchSelectionProvider ?? session?.activeBranchId` (`authenticated_shell.dart:70`); zero call sites. |
| **S3** | Medium (SOLID) | `AuthenticatedShell` SRP violation | **STILL OPEN** | Single widget: session mapping, warm provider, theme, branch, nav (`authenticated_shell.dart:24–81`). |
| **S4** | Medium (SOLID) | Open/Closed — nav edits need multiple blocks | **STILL OPEN** | `_routesByItemId`, `groups`, `itemIdForLocation` prefix rules maintained separately (`shell_nav_config.dart`). |
| **D3** | Duplication | Duplicate nav entries per destination | **STILL OPEN** | `home`/`dashboard` → `/home`; `billing`/`invoices` → `/billing/invoices`. |
| **D4** | Duplication | Duplicate route-resolution with dev nav | **STILL OPEN** | `ShellNavConfig.routeFor` delegates to `ShellDevNav.routeFor` (line 67); parallel `itemIdForLocation` / `labelFor` implementations. |
| **D5** | Duplication | Parallel navigation APIs | **STILL OPEN** | Shell uses `context.go(route)` (`authenticated_shell.dart:63`); `AppNavigator` unused (no imports). |
| **D11** | Duplication | Duplicate theme toggle surfaces | **STILL OPEN** | Same as M13. |
| **P3** | Performance | Broad `ref.watch(authSessionProvider)` | **STILL OPEN** | Full auth watched line 33; `permissionServiceProvider` also watches full auth (`auth_session_provider.dart:318–319`). |
| **P4** | Performance | Conditional side-effect watch in `build` | **STILL OPEN** | `if (canAccessAppointments()) { ref.watch(appointmentQueueShellWarmProvider); }` (`authenticated_shell.dart:25–27`). |
| **P5** | Performance | Router refresh on any `SetupUiState` change | **STILL OPEN** *(router.dart)* | `router.dart:26–28` unchanged. |
| **P6** | Performance | Queue warm on all shell routes | **STILL OPEN** | Warm runs whenever shell builds + appointment permission; H7 means login/bootstrap still inside shell tree (warm skipped when unauthenticated/null context). |
| **T4** | Test gap | No shell widget / nav config tests | **STILL OPEN** | `grep` in `frontend/test` for `ShellNavConfig`, `AuthenticatedShell`, `AppSidebar` — **no matches**. Only `shell_dev_security_test.dart` covers dev nav security. |

---

## Critical Issues (Second Cycle)

*No new Critical issues in shell-scoped code. First-cycle shell review had no Critical findings; branch-reset risk remains rated **High** (H4) per consolidated review.*

---

## High Priority Issues (Second Cycle)

### H2-S-01: Sidebar org header displays raw `organizationId` UUID

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **Files** | `authenticated_shell.dart`, `app_sidebar.dart` |
| **Evidence** | `org: session?.organizationId ?? 'Organization'` (`authenticated_shell.dart:57`). Rendered in `_SidebarHeader` as org label (`app_sidebar.dart:199`). `AuthSessionContext` stores `organizationId` only — no org display name (`auth_session.dart:73`). `SessionContextLoader` loads `timezone` from `organizations` but not `name` (`session_context_loader.dart:69`). |
| **Why** | Same gap as H15 (branch names): session context lacks human-readable org metadata. |
| **Impact** | Multi-tenant staff see UUID in primary chrome; indistinguishable orgs in sidebar header. |
| **Solution** | Load `organizations.name` in `SessionContextLoader` (or branch directory provider); map to display string in shell. |
| **Cycle 1** | **NEW** (companion to H15) |

*First-cycle High issues H5–H8, H15, H4 remain **STILL OPEN** — see triage table.*

---

## Medium Priority Issues (Second Cycle)

### M2-S-01: Keyboard navigation disabled when no nav item matches current route

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **Files** | `app_sidebar.dart`, `shell_nav_config.dart` |
| **Evidence** | `_handleNavKey` returns `ignored` when `ids.indexOf(widget.activeId ?? '') < 0` (`app_sidebar.dart:65–67`). `itemIdForLocation` returns `null` for `/settings/staff`, `/visits/:id/*`, etc. (no prefix rules). |
| **Why** | Keyboard nav requires a known `activeId`; many legitimate routes have no nav mapping (H8). |
| **Impact** | Arrow/Home/End keys do nothing on settings sub-pages, visit routes, and other deep links. |
| **Solution** | Add settings/visits prefix rules to `itemIdForLocation`; or allow keyboard nav from last-focused item when `activeId` is null. |
| **Cycle 1** | **NEW** |

### M2-S-02: Keyboard nav cycles through dead items with silent no-op

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **Files** | `app_sidebar.dart`, `shell_nav_config.dart`, `authenticated_shell.dart` |
| **Evidence** | `ids` list built from all `groups` + `footerItems` (`app_sidebar.dart:60–63`) including `encounters`, `workspace`, `reports`. `onNavigate` no-ops when `routeFor` is null (`authenticated_shell.dart:61–64`). |
| **Why** | Dead items not excluded from keyboard list (H6). |
| **Impact** | Arrow-down appears to change focus/route but nothing happens for 3 items per cycle. |
| **Solution** | Filter `ids` to items where `routeFor(id) != null`; or disable dead items visually and skip in keyboard list. |
| **Cycle 1** | **NEW** (extends H6) |

### M2-S-03: Billing nav active-state inconsistent between list and detail routes

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **Files** | `shell_nav_config.dart` |
| **Evidence** | Exact path `/billing/invoices`: loop at lines 90–93 returns `'billing'` first (map insertion order). Prefix rule at 105–106 returns `'invoices'` for `startsWith(AppRoutes.billingInvoices)`. |
| **Why** | Dual items + exact-before-prefix resolution order. |
| **Impact** | Invoice list highlights "Billing"; invoice detail highlights "Invoices" — confusing paired nav items. |
| **Solution** | Remove duplicate; single canonical `billing` item with one ID. |
| **Cycle 1** | **NEW** (refinement of H8/D3) |

### M2-S-04: Branch switcher display can misrepresent selection when `currentBranchId` is stale

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **Files** | `app_branch_switcher.dart`, `authenticated_shell.dart` |
| **Evidence** | `current = branches.firstWhere(..., orElse: () => branches.first)` (line 29) — label shows first branch when ID not found. Checkmarks use `branch.id == currentBranchId` (line 96). After context reload (H4), `currentBranchId` may not match displayed name. |
| **Why** | Defensive `orElse` without syncing displayed vs selected state. |
| **Impact** | Switcher label may show Branch A while session/context still holds Branch B UUID (or no checkmark). |
| **Solution** | When ID not in list, show explicit "Unknown branch" + force pick; preserve selection across reloads (H4). |
| **Cycle 1** | **NEW** |

### M2-S-05: Settings footer never highlights on sub-routes despite title fix

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **Files** | `shell_nav_config.dart`, `authenticated_shell.dart` |
| **Evidence** | `pageTitleForLocation` uses `isSettingsLocation` (69–79). `itemIdForLocation` has **no** settings prefix — `/settings/staff` → `null` → footer `active: false` (`authenticated_shell.dart:30,55`). |
| **Why** | Partial H8 fix applied only to title path. |
| **Impact** | Settings deep links show correct top-bar title but Settings footer item never appears selected. |
| **Solution** | `if (isSettingsLocation(location)) return 'settings';` in `itemIdForLocation`. |
| **Cycle 1** | **NEW** (partial H8 regression) |

*First-cycle Medium issues M8–M15, M18 and architectural items remain **STILL OPEN** — see triage.*

---

## Test Coverage Gaps

| ID | Gap | Severity | Evidence | Recommended Test |
|----|-----|----------|----------|------------------|
| **T4** | No shell widget / nav config tests | High | Zero test files reference `ShellNavConfig`, `AuthenticatedShell`, `AppSidebar`, `shell_sidebar_collapsed_provider` | Unit: `itemIdForLocation` matrix (home, billing list/detail, settings sub-routes, visits); widget: collapse round-trip, branch switcher empty/single/multi |
| **T4-S-01** | No test for permission-filtered nav (when implemented) | High | H5 still open; no test scaffold | Given mock `PermissionService`, assert filtered `groups` |
| **T4-S-02** | No test for dead-item keyboard skip | Medium | M2-S-02 | Assert `ids` list excludes items without routes |
| **T12** | No sidebar collapse persistence test | Medium | M10 | Provider test with mock `SharedPreferences` |
| **T4-S-03** | No test for settings footer active on sub-routes | Medium | M2-S-05 | `expect(ShellNavConfig.itemIdForLocation('/settings/staff'), 'settings')` |

**Existing positive coverage:** `frontend/test/unit/shell/shell_dev_security_test.dart` — dev nav gating, redirect suppression (not shell UI).

---

## Recommended Fix Order

### Phase 1 — Clinical scope & permission parity (blockers)

1. **H4 — Preserve `activeBranchId` across `tokenRefreshed` / `refreshSessionContext` / resume** (provider layer; shell is impact surface).
2. **H5 — `ShellNavConfig.visibleGroupsFor(auth)`** mirroring `AuthRouteGuard` + `SettingsTabs.visibleFor`.
3. **H6 — Remove or disable dead items** (`encounters`, `workspace`, `reports`); exclude from keyboard list (M2-S-02).

### Phase 2 — Nav model correctness

4. **H8 / D3 / M2-S-03 / M2-S-05 — Dedupe `home`/`dashboard`, `billing`/`invoices`; add settings + visits prefix rules to `itemIdForLocation`.**
5. **H15 + H2-S-01 — Load branch and org display names** into session context or directory providers.

### Phase 3 — Chrome boundaries & UX polish

6. **H7 / P6 — Split auth layout from app chrome** (login/bootstrap outside full shell).
7. **M8 — Mobile branch switcher fallback** in user menu or sidebar.
8. **M9 — Wire queue count or remove warm provider.**
9. **M10 — AsyncNotifier for collapse** to eliminate flash.
10. **M11–M13 — Hide or wire placeholders** (command bar, notifications, duplicate theme).

### Phase 4 — Performance & architecture

11. **P3 / P4 — `select` on auth fields; move queue warm to `ref.listen` or composed provider.**
12. **S3 — Extract `ShellChromeState` provider** (filtered nav, names, badge, chrome visibility).
13. **T4 — Add `shell_nav_config_test.dart`** before further nav edits.

---

## Finding Count Summary

| Category | Cycle 1 (shell) | Cycle 2 |
|----------|-----------------|---------|
| Critical | 0 | 0 |
| High | 5 (+ H4 cross-cutting) | 5 STILL OPEN + **1 NEW** (H2-S-01) |
| Medium (shell-focused) | 11 | 11 STILL OPEN + **5 NEW** (M2-S-01–05) |
| Test gaps | T4 open | T4 open + 3 sub-gaps |

**Bottom line:** The shell is **presentation-ready but integration-incomplete**. No first-cycle High/Medium shell issue was fixed in code. The highest-impact work remains **branch persistence (H4)**, **permission-filtered nav (H5)**, and **nav model cleanup (H8)** — with **tests (T4)** to lock behavior before feature pages land.

---

*Second-cycle review: direct verification of all files under `frontend/lib/app/shell/` and shell-related tests. Cross-references: `docs/review/flutter-app-feature-review.md`, `docs/review/flutter-app-review-shell-ui.md`.*
