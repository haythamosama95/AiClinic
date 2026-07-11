# Implementation Plan — Clinic Management page (web-reference → Flutter feature port)

Spec target: port the **Clinic Management** page from `web-reference/src/features/clinic-management/` into a **new** Flutter feature at `frontend/lib/features/clinic-management/`, and **migrate the clinic-management functionality currently living in `frontend/lib/features/settings/`** (organization, branches, staff, role-permissions) into that new feature. The remaining app-level settings (idle timeout) stays in `features/settings/`.

This is a **feature page** port (not a Dev showcase component group). The §4 "Demo-for-demo" guideline is adapted: the web `ClinicManagementPage.tsx` + its 4 tab components are the **binding source of truth** for layout, copy, props, and ordering; the Flutter page reproduces them 1:1 in shape using the shipped App abstraction layer.

## 0. Ambiguities & Design Decisions (resolve before coding)

> ⚠️ **Composer 2.5: read `docs/ui/memory/ui-runtime-errors.md` first.** This plan drives form-heavy tabs (Organization/Branches/Staff) and a permission-matrix grid. The regressions below WILL recur if not handled. Reference the memory's "Checklist for new input components" (items 1–9), "Checklist for new display components" (items 1–9), and "Checklist for new feedback/overlay components" (items 1–4) by item number.

Group-specific regressions to avoid (carry over from the memory):

- **Material primitive inside a custom shell.** Every `AppFormField` + `AppTextInput`/`AppCombobox`/`AppSelect`/`AppMultiSelect`/`AppPasswordInput` pair embeds a `TextField`. The clinic-management forms already ship these wrappers (they use `appWrapMaterialInput` / `appCenterInputField` internally), but the new **`WorkingHoursEditor`** rows and **permission-matrix toggle buttons** must not be placed inside a bare `DecoratedBox`/`AnimatedContainer` without a `Material` ancestor when they use `InkWell` (memory #1, #23, checklist-display #6). Use `Material(color: Colors.transparent)` shells around any `InkWell` toggle (matrix `GrantToggle`, branch-card overflow menu trigger, list rows).
- **`AppPopover`-based controls (Select/Combobox/MultiSelect/TimePicker).** The Organization currency/timezone `AppCombobox`, Staff role `AppSelect`, branch-assignment `AppMultiSelect`, and Working-hours `AppTimePicker` are all controlled popover consumers. The page mounts the Organization form, the Branch form dialog, and the Staff form dialog inside `AppDialog` (also a controlled overlay). Memory #10, #11, #12, #13, #27: controlled `open:` overlays must defer `_open/_close` to `addPostFrameCallback` in `didUpdateWidget`; never put `Tooltip`/`MenuAnchor` inside a popover child; schedule `markNeedsBuild` via `_scheduleOverlayRefresh()` only after the frame and skip while closing / leader detached; toast/dialog controllers must be driven from **route** context not `MaterialApp.builder`. The shipped App overlay widgets already encode these fixes — **do not regress them by wrapping their internals in another `Focus`/`Overlay`/`Tooltip`** in feature code.
- **`AppTimePicker` locale formatting.** Working-hours `TimePicker` is web `use24Hour`. The Flutter `AppTimePicker` needs intl date formatting initialized; `ensureIntlDateFormattingInitialized()` runs at app startup (memory #3). Verify it is called in `main.dart`; if not, add it before the first TimePicker renders.
- **Focus tree.** Do not wrap any `AppTextInput`/`AppCombobox` in an ancestor `Focus` that shares the field's `FocusNode` (memory #4). The shipped App inputs manage their own `FocusNode` — leave them alone.
- **List/card layout in scroll context.** The Branches tab is a `Wrap`/grid of branch cards and the Staff tab is a list. They render inside `AppShell`'s content slot which can be a `SingleChildScrollView` (memory #28, #30): page `Column`s must use `mainAxisSize: MainAxisSize.min`; branch cards use `MouseRegion` + `AnimatedContainer` hover (memory #18, checklist-display #6) **not** `InkWell` for the decorative hover swap (the overflow `IconButton`/menu trigger still needs a `Material` ancestor). Do not use `CrossAxisAlignment.stretch` on a `Row` inside the scroll body (memory #8, #15).
- **Street-address/branch-card `a href target=_blank` "View on maps".** `url_launcher` is **not** in `pubspec.yaml` → **unsupported** web affordance. Per the user's instruction, **ignore it** (omit the "View on maps" external link); the maps URL is retained on the domain model for a future milestone. Do not add a dep for it.

Decisions:

1. **native Material App abstraction (no forui).** `forui` is declared in pubspec but imported nowhere — the shipping convention is native Material wrapped behind `App*` widgets exported from `core/ui/widgets/widgets.dart`. The clinic-management feature imports **only** `package:ai_clinic/core/ui/widgets/widgets.dart` (and feature/domain files). Never `import package:flutter/material.dart` widgets like `TextField`/`DropdownButton`/`showDialog` directly in feature surfaces — go through `AppTextInput`, `AppSelect`, `AppDialog`, etc.
2. **Feature folder layout** mirrors existing features (`patients/`, `billing/`): `domain/` (entities + `repositories/` interfaces + `usecases/`), `data/` (repo impls), `application/` (rpc messages), `presentation/` (`pages/`, `components/`, `providers/`, `models/`). No `core/ui/components/` additions are needed — every web widget already has an App equivalent.
3. **Migration, not duplication.** Clinic-management domain/data/application/providers currently in `features/settings/` are **moved** (preserving git history via `git mv`) into `features/clinic-management/`. The `features/settings/` feature keeps **only** idle-timeout (`domain/idle_timeout_config.dart`, `data/idle_timeout_preferences_store*.dart`, `application/idle_timeout_settings_notifier.dart`).
4. **New route `/clinic-management`, single tabbed page.** The web is ONE page with 4 tabs (Organization / Branches / Staff / Roles), not 4 routes. The existing Flutter `/settings/organization`, `/settings/branches`, `/settings/staff`, `/settings/permissions` routes (all currently `shellPlaceholderPage`) are **retired in favor of** `/clinic-management`. To avoid breaking deep links / guards, the four `/settings/*` admin routes are kept as **permanent redirects** to `/clinic-management` (guard logic already branches on them). The old `SettingsTabs` catalog (`general / clinicSetup / staff / staffRoles`) is trimmed in `features/settings/` to just `general`.
5. **i18n / RTL.** Page mirrors web copy in EN; AR literals follow the existing `_copyEn`/`_copyAr` convention from the Actions showcase sections where the web has user-facing copy. Money/phone digits rendered LTR via `Directionality.ltr` on the relevant `AppTextInput` (matches web `inputMode=numeric` + money/phone inputs). `AppTimePicker` uses 24h regardless of locale (web `use24Hour`).
6. **Controlled/uncontrolled.** Forms use the App widgets' idiomatic `controller`/`onChanged` (or `value`/`onValueChange`) with internal fallback state — exactly the pattern the inputs-forms plan §0.7 codifies. The Organization/Staff "create vs edit" `mode` flag (web) is preserved as a dialog `mode` enum.
7. **Mock state vs. real RPC.** The web `useClinicManagementState` is a pure `useState` mock with `INITIAL_*` seed data. The Flutter feature **already** has real RPC-backed providers (`clinicSetupOrganizationProvider`, `clinicSetupBranchesProvider`, `staffListProvider`, `rolePermissionsProvider`) + use cases against Supabase RPC. **Reuse the real providers/use-cases** (after relocation); do not port the web's in-memory mock. The web mock data informs only the empty-state copy and seed/dummy fill (shell dev already seeds via `dev_clinic_seed_service` against the real repos).
8. **Icon mapping (lucide → Material Icons).** Web uses `lucide-react`. Map to `IconData` from `Icons`, approximating where no exact glyph exists: Building2→`apartment`, MapPin→`location_on`, Shield→`shield`, Users→`group`, UserRound→`person`, Pencil→`edit`, Plus→`add`, X→`close`, Save→`save`, Check→`check`, Phone→`phone`, Power→`power_settings_new`, MoreHorizontal→`more_horiz`, Trash2→`delete_outline`, ExternalLink→`open_in_new` (unused, see §0.2), SearchX→`search_off`, SlidersHorizontal→`tune`, ArrowUpDown→`sort`, CalendarClock→`event_available`. No new icon dep added.

> **Phase count note.** User requested **4 phases**; this plan uses 4. No clamping needed (4 ∈ [1,6]).

## 1. Existing App assets to reuse (do not recreate)

| Asset | Path | Used by |
|---|---|---|
| `AppPageHeader` | `core/ui/components/app_page_header.dart` | `ClinicManagementPage` header ("Clinic Management" + description) — web `PageHeader` analog |
| `AppTabs` + tab item model | `core/ui/components/app_tabs.dart` | 4-tab section switch (Organization/Branches/Staff/Roles) — web `Tabs` analog |
| `AppButton`, `AppIconButton` | `core/ui/components/app_button.dart`, `app_icon_button.dart` | "Add branch", "Edit organization", "Save changes", list-row overflow triggers |
| `AppBadge` | `core/ui/components/app_badge.dart` | branch status pill (Active/Inactive success/warning), staff role chip (teal/ai/info/neutral) |
| `AppAvatar` | `core/ui/components/app_avatar.dart` | staff list row avatar (`name`, size md) |
| `AppChip` | `core/ui/components/app_chip.dart` | active-filter chips in `ListControlBar` (removable) |
| `AppFormField` | `core/ui/components/app_form_field.dart` | every labeled form field (label + required `*` + hint tooltip + helper/error) |
| `AppTextInput`, `AppTextarea` | `core/ui/components/app_text_input.dart` | name/code/address/phone/username/logo-URL/maps-URL fields |
| `AppCombobox` | `core/ui/components/app_combobox.dart` | Organization currency-code + timezone (type-to-search) |
| `AppSelect` | `core/ui/components/app_select.dart` | Staff role select, Staff primary-branch select, Staff-filter role/branch selects |
| `AppMultiSelect` | `core/ui/components/app_multi_select.dart` | Staff branch assignments (multi-token) |
| `AppPasswordInput` | `core/ui/components/app_password_input.dart` | staff create/edit username password |
| `AppSwitch` | `core/ui/components/app_switch.dart` | `WorkingHoursEditor` per-day isWorkingDay toggle |
| `AppTimePicker` | `core/ui/components/app_time_picker.dart` | `WorkingHoursEditor` open/close times (24h) |
| `AppDialog` (+ `AppDialog` confirm) | `core/ui/components/app_dialog.dart` | `BranchFormDialog`, `StaffFormDialog`, working-hours sub-dialog, `ConfirmationDialog` (delete branch/staff) |
| `AppMenu` / `MenuAnchor` (`app_menu.dart`) | `core/ui/components/app_menu.dart` | branch-card overflow menu (Edit / Activate-Deactivate / Delete), staff-row overflow (Edit / Delete), `ListControlBar` sort dropdown |
| `AppSearchInput` | `core/ui/components/app_search_input.dart` | `ListControlBar` search field (showShortcutHint off) |
| `AppPopover` | `core/ui/components/app_popover.dart` | `ListControlBar` Filter popover host |
| `AppEmptyState`, `AppErrorState` | `core/ui/components/app_empty_state.dart`, `app_error_state.dart` | branch/staff empty + no-results + permission-denied states |
| `AppTooltip` | `core/ui/components/app_tooltip.dart` | `RolePermissionsMatrix` column-header role summary tooltip (`preferBelow: false`) |
| Theme: `context.appColors`, `AppSpacing`, `AppRadius`, `AppTypography`, `AppMotion` | `core/ui/theme/*` | every component |
| `AppRoutes` + `ShellNavConfig` + `AuthenticatedShell` + `shellPlaceholderPage` | `app/app_routes.dart`, `app/shell/navigation/*`, `app/presentation/shell_page_builder.dart` | route + page wiring (§6) |
| `AuthRouteGuard` (canAccessOrganizationSettings / canAccessBranchManagement / canAccessStaffManagement / canAccessPermissionMatrix) | `core/auth/auth_route_guard.dart` | page/tab access gating; reused as-is (guards stay in core; only the route strings they switch on change) |
| Real RPC providers/use-cases (relocated) | (post Phase 1) `features/clinic-management/...` | data source instead of web mock |

## 2. New shared abstractions to introduce

None in `core/ui/components/` — every web UI widget maps to a shipped App widget (§1). The only **new** code is feature-local (presentation components + form-field validators + list-control helpers), all under `features/clinic-management/presentation/`. These are NOT promoted to `core/ui/` (they are clinic-management specific):

| File (`features/clinic-management/presentation/`) | Export name | Web analog | Purpose | Phase |
|---|---|---|---|---|
| `constants/clinic_constants.dart` | `kCurrencyCodes`, `kTimezones`, `kWeekdays`, `kStaffRoles`, `kRoleLabels`, `kUsernameHint`, `kPasswordHint` | `constants.ts` | static option catalogs for forms (combobox/select) + weekday iteration | P2 |
| `utils/working_schedule.dart` | `WorkingSchedule`, `defaultWorkingSchedule()`, `emptyWorkingSchedule()`, `hasConfiguredWorkingHours()`, `formatWorkingHoursSummary()`, `weekdayLabel()` | `working-schedule.ts` (relocated logic; the existing `branch_working_schedule.dart` domain entity becomes the model this utility formats) | per-day model + form helpers + summary string for branch cards | P3 |
| `utils/permission_matrix.dart` | `PermissionKey`, `RoleGrantsMap`, `createDefaultRoleGrants()`, `cloneRoleGrants()`, `roleGrantsEqual()`, `canTogglePermissionGrant()`, `permissionCategoryGroups()`, `permissionLabel()`, `categoryLabel()` | `permission-matrix.ts` (note: existing Flutter `PermissionMatrixView` already encodes grant-set diffing; this provides the **category grouping + labels** for the UI grid) | roles-tab grid grouping/labeling + toggle guard (`settings.billing.manage` admin-only) | P4 |
| `utils/role_theme.dart` | `kRoleBadgeColors`, `kRoleAccents`, `kRoleSummaries` | `role-theme.ts` | badge color + header accent gradient + tooltip summary per role | P4 |
| `models/clinic_management_tab.dart` | `ClinicManagementTab` enum, `clinicManagementTabs` | `ClinicManagementPage` `TAB_ITEMS` | tab catalog (id,label,icon) for `AppTabs` + access filtering (hide tabs the session can't access) | P2 |
| `models/branch_form_values.dart`, `models/staff_form_values.dart`, `models/organization_form_values.dart` | `BranchFormValues`, `StaffFormValues`, `OrganizationFormValues` + `validateBranch()/validateStaff()/validateOrganization()` + `*ToFormValues()`/`empty*()` | `forms/*FormFields.tsx` | mutable form drafts + validators (web ports) | P2/P3/P4 |
| `components/list_control_bar.dart` | `ListControlBar` | `components/ListControlBar.tsx` | search + sort dropdown + filter popover + active-filter chip strip (reused by Branches & Staff) | P3 |
| `components/filter_menu_panel.dart` | `FilterMenuPanel` | `components/FilterMenuPanel.tsx` | single-section radio listbox (branches status) | P3 |
| `components/clinic_hero.dart` | `ClinicHero` | `components/ClinicHero.tsx` | identity banner (org name + initials avatar + 3 stat tiles); gradient simplified per §0.2 | P2 |
| `components/organization_tab.dart`, `forms/organization_form_fields.dart` | `OrganizationTab`, `OrganizationFormFields` | `components/OrganizationTab.tsx`, `forms/OrganizationFormFields.tsx` | read/edit toggle + form | P2 |
| `components/working_hours_editor.dart` | `WorkingHoursEditor` | `forms/WorkingHoursEditor.tsx` | per-day switch + open/close `AppTimePicker` | P3 |
| `components/branches_tab.dart`, `components/branch_form_dialog.dart`, `utils/branch_list_controls.dart` | `BranchesTab`, `BranchFormDialog`, `filterAndSortBranches()`, `BranchListControls` | `components/BranchesTab.tsx`, `BranchFormDialog.tsx`, `utils/branch-list-controls.ts` | branch cards + CRUD dialog + filter/sort | P3 |
| `components/staff_tab.dart`, `components/staff_form_dialog.dart`, `components/staff_filter_panel.dart`, `utils/staff_list_controls.dart` | `StaffTab`, `StaffFormDialog`, `StaffFilterPanel`, `filterAndSortStaff()`, `StaffListControls` | `components/StaffTab.tsx`, `StaffFormDialog.tsx`, `StaffFilterPanel.tsx`, `utils/staff-list-controls.ts` | staff list + CRUD dialog + role/branch filter | P4 |
| `components/roles_tab.dart`, `components/role_permissions_matrix.dart` | `RolesTab`, `RolePermissionsMatrix` | `components/RolesTab.tsx`, `RolePermissionsMatrix.tsx` | draft grant grid + save/discard | P4 |
| `pages/clinic_management_page.dart` | `ClinicManagementPage` | `ClinicManagementPage.tsx` | shell: `AppPageHeader` + `AppTabs` + active-tab body; owns the relocated state hook (delegates to real providers) | P2 |
| `providers/clinic_management_notifier.dart` | `clinicManagementProvider` (AsyncNotifier) | `useClinicManagementState` | orchestrates organization/branches/staff mutations across real use-cases (replaces the web mock); roles matrix keeps its own notifier (relocated `rolePermissionsProvider`) | P2 |

## 3. Phasing

> **Rationale.** The migration must be a **no-behavior-change refactor first** so the app still compiles and the shell chrome / seed data / cross-feature imports keep working — that is **Phase 1** (domain/data relocation + route placeholder). Then the 4 web tabs are built out as one page: **Phase 2** = page shell + Organization tab (foundation providers + hero + first form), **Phase 3** = Branches tab + the two shared list-control components that Staff also reuses (introduces `ListControlBar`/`FilterMenuPanel` now), **Phase 4** = Staff tab + Roles tab (heaviest — multi-select, matrix grid, save/discard). Each phase is independently shippable.

### Phase 1 — Feature scaffold + domain/data relocation (no UI)

Goal: introduce `features/clinic-management/`, **move** all clinic-management concerns out of `features/settings/` via `git mv`, update every external import consumer, register the `/clinic-management` route as a (still-placeholder) route, and trim the settings route set. App must compile and behave identically before/after.

| Concern | Files to MOVE (settings → clinic-management) | New path |
|---|---|---|
| Organization domain | `domain/organization_profile.dart`, `domain/update_organization_input.dart`, `domain/repositories/organization_repository.dart` | `features/clinic-management/domain/...` |
| Branch domain | `domain/branch_list_item.dart`, `domain/branch_list_filter.dart`, `domain/branch_working_schedule.dart`, `domain/create_branch_input.dart`, `domain/update_branch_input.dart`, `domain/repositories/branch_repository.dart` | `features/clinic-management/domain/...` |
| Staff domain | `domain/staff_list_item.dart`, `domain/staff_list_filter.dart`, `domain/staff_list_query.dart`, `domain/staff_member_detail.dart`, `domain/update_staff_member_input.dart`, `domain/repositories/staff_admin_repository.dart` | `features/clinic-management/domain/...` |
| Role-permissions domain | `domain/permission_matrix_row.dart`, `domain/permission_matrix_view.dart`, `domain/repositories/role_permissions_repository.dart` | `features/clinic-management/domain/...` |
| Use cases | `domain/usecases/*` (fetch_organization_profile, update_organization, list_branches, create_branch, update_branch, delete_branch, set_branch_active, list_staff, fetch_staff_member, update_staff_member, set_staff_active, delete_staff_member, fetch_permission_matrix, update_role_permission, update_role_permissions) | `features/clinic-management/domain/usecases/*.dart` (rename `settings_use_case_providers.dart` → `clinic_management_use_case_providers.dart`) |
| Data | `data/organization_repository.dart`, `data/branch_repository.dart`, `data/staff_admin_repository.dart`, `data/role_permissions_repository.dart`, `data/settings_rpc_repository.dart` (the `SettingsRpcInvoker` mixin) | `features/clinic-management/data/...` (rename `settings_rpc_repository.dart` → `clinic_management_rpc_repository.dart`; keep `SettingsRpcInvoker` class name OR rename to `ClinicManagementRpcInvoker` — see decision below) |
| Application | `application/settings_rpc_messages.dart` | `features/clinic-management/application/clinic_management_rpc_messages.dart` (functions `organizationMessageForRpc`/`branchMessageForRpc`/`permissionMessageForRpc` move; if `staffMessageForRpc` exists it moves too) |
| Presentation providers | `presentation/providers/clinic_setup_providers.dart`, `presentation/providers/staff_list_notifier.dart`, `presentation/providers/role_permissions_notifier.dart` | `features/clinic-management/presentation/providers/...` |

**Rename decision (§0.7 confirmation):** `SettingsRpcInvoker` → `ClinicManagementRpcInvoker`, log domain stays `'settings'` to match the DB migration hint, OR change to `'clinic_management'` and update `AppLog` filters. **Recommend keeping the migration hint string `'20260522100000_org_branch_management.sql'` verbatim** (DB contract) and renaming only the Dart class + log domain to `clinic_management` for clarity. The `rpcLogDomain` is cosmetic; either is fine — note the choice in the PR.

Settings feature **kept** pieces:
- `domain/idle_timeout_config.dart` — stays.
- `data/idle_timeout_preferences_store.dart`, `data/idle_timeout_preferences_store_io.dart`, `data/idle_timeout_preferences_store_web.dart` — stay.
- `application/idle_timeout_settings_notifier.dart` — stays.
- `presentation/models/settings_tab.dart` — **trimmed**: remove `clinicSetup`, `staff`, `staffRoles` definitions; keep only `general`. `visibleFor(...)` collapses to `=> [general]`.
- The settings feature folder shrinks to `domain/` + `data/` + `application/` for idle timeout **only**; `domain/repositories/`, `domain/usecases/`, `presentation/providers/` become empty — delete the empty directories.

External import consumers to update (blast radius — verified by grep `features/settings`):

| File | Current import | New import |
|---|---|---|
| `features/patients/data/patient_dev_seed_service.dart` | `settings/domain/branch_list_filter.dart`, `branch_list_item.dart`, `branch_working_schedule.dart`, `create_branch_input.dart`, `repositories/branch_repository.dart`, `repositories/staff_admin_repository.dart`, `update_staff_member_input.dart` | `clinic-management/domain/...` |
| `features/appointments/domain/appointment_settings.dart`, `appointment_branch_working_hours.dart`, `appointment_reschedule_validation.dart`, `appointment_calendar_display.dart`, `appointment_working_hours.dart` | `settings/domain/branch_working_schedule.dart` | `clinic-management/domain/branch_working_schedule.dart` |
| `features/appointments/domain/appointment_queue_shift_doctors.dart` | `settings/domain/staff_list_item.dart` | `clinic-management/domain/staff_list_item.dart` |
| `features/appointments/data/doctor_dev_seed_service.dart`, `presentation/providers/appointment_queue_shift_provider.dart`, `appointment_queue_provider.dart`, `appointment_calendar_provider.dart` | (transitive — fix to the relocated symbols above) | `clinic-management/...` |
| `features/setup/domain/setup_step_readiness.dart`, `bootstrap_branch_input.dart`, `setup/presentation/providers/setup_notifier.dart` | `settings/domain/branch_working_schedule.dart` | `clinic-management/domain/branch_working_schedule.dart` |
| `app/providers/repository_providers.dart` | re-exports `settings/data/branch_repository.dart` (`branchRepositoryProvider`), `settings/data/staff_admin_repository.dart` (`staffAdminRepositoryProvider`) | re-export from `clinic-management/data/...` |
| `app/providers/auth_session_provider.dart` | `settings/data/idle_timeout_preferences_store.dart` | **stays** (idle-timeout stays in settings) |
| `app/shell/providers/shell_chrome_provider.dart` | `settings/presentation/providers/clinic_setup_providers.dart` | `clinic-management/presentation/providers/clinic_setup_providers.dart` |
| `app/shell/dev/dev_clinic_seed_service.dart`, `dev_clinic_seed_spec.dart`, `dev_clinic_seed_notifier.dart` | `settings/domain/create_branch_input.dart`, `repositories/branch_repository.dart`, `repositories/staff_admin_repository.dart`, `update_staff_member_input.dart` | `clinic-management/domain/...` |

Routing scaffolding (Phase 1):

- `app/app_routes.dart`: add `static const clinicManagement = '/clinic-management';` and a `clinicManagementPaths` list. Keep the existing `/settings/organization|branches|branches/new|staff|staff/new|staff/:id|staff/:id/reset-password|permissions` route constants for the redirect step (§6) — they are repurposed from "placeholder page" to "redirect to `/clinic-management`".
- `app/router.dart`: add `GoRoute(path: AppRoutes.clinicManagement, builder: clinicManagementPlaceholderPage)` (still a placeholder in Phase 1; Phase 2 swaps in the real page).
- `app/shell/navigation/shell_nav_config.dart`: add `'clinic-management': AppRoutes.clinicManagement` to `_routesByItemId`; add `itemIdForLocation` prefix match `if (location == AppRoutes.clinicManagement) return 'clinic-management';`. Add the nav item `'clinic-management'` (`label: 'Clinic Management', icon: Icons.apartment_outlined`) to `kClinicNavGroups` (operations group, near `staff`/`shifts`) and `ShellRouteMeta` title/description.

Wiring steps for Phase 1 are in §6 (P1). After Phase 1: app compiles, route `/clinic-management` exists (placeholder), all settings/clinic-management domain relocated, idle-timeout untouched.

### Phase 2 — Page shell + Organization tab

Build the page skeleton + hero + the Organization tab (read mode + edit form), and the relocated state orchestrator.

| Web component | Flutter widget(s) to create | File(s) under `features/clinic-management/` | Reuse (App assets, relocated providers) | Deps |
|---|---|---|---|---|
| `ClinicManagementPage` shell | `ClinicManagementPage` (ConsumerStatefulWidget) | CREATE `presentation/pages/clinic_management_page.dart`; MOD `app/router.dart` (swap placeholder builder) | `AppPageHeader` (title "Clinic Management", description "Organization identity, locations, team accounts, and access roles."), `AppTabs`, `clinicManagementProvider`, `authSessionProvider`, `AuthRouteGuard` (filter tabs by access) | P1 providers |
| Tab catalog | `ClinicManagementTab` enum + `clinicManagementTabs` | CREATE `presentation/models/clinic_management_tab.dart` | `Icons.apartment`/`location_on`/`group`/`shield` | — |
| Orchestrator | `clinicManagementProvider` (`AsyncNotifier` exposing `organization`, `branches`, `staff` + mutation methods `updateOrganization/addBranch/updateBranch/removeBranch/toggleBranchActive/addStaff/updateStaff/removeStaff` mirroring `useClinicManagementState`'s return shape but delegating to real use-cases) | CREATE `presentation/providers/clinic_management_notifier.dart` | relocated `fetchOrganizationProfileUseCase`, `listBranchesUseCase`, `createBranch/updateBranch/deleteBranch/setBranchActive`, `listStaff/.../deleteStaffMember` use cases; `authSessionProvider` for `organizationId` | P1 use cases |
| `ClinicHero` | `ClinicHero` | CREATE `presentation/components/clinic_hero.dart` | `AppAvatar` (initials fallback), `AppTypography.display`, `context.appColors`, `Container(decoration: BoxDecoration(gradient: LinearGradient(...)))`; **simplify**: drop the two `radial-gradient blur-2xl` blobs and the `backdrop-filter` on stat tiles (unsupported cosmetic — §0.2); keep the diagonal teal→violet `LinearGradient` on the banner and the 3 stat `Icon+label+value` tiles | `organization` from notifier |
| `OrganizationTab` | `OrganizationTab` (read/edit toggle) | CREATE `presentation/components/organization_tab.dart` | `AppButton` (Edit/Save/Cancel), `ClinicHero`, `OrganizationFormFields` | `OrganizationFormFields`, `clinicManagementProvider.updateOrganization` |
| `OrganizationFormFields` | `OrganizationFormFields` + `validateOrganization()` | CREATE `presentation/forms/organization_form_fields.dart`; CREATE `constants/clinic_constants.dart` | `AppFormField`, `AppTextInput` (name, logo URL — `type: url`), `AppCombobox` (currency, timezone — type-to-search with 20/20 entries), 2-col responsive `Wrap`/`LayoutBuilder` grid | `kCurrencyCodes`, `kTimezones` |

Dev-page instantiation spec (web binding of truth — `OrganizationTab.tsx` + `OrganizationFormFields.tsx`): 4 fields in a `sm:grid-cols-2` grid — Organization name (required, placeholder "Enter your clinic name"), Logo URL (placeholder "https://example.com/logo.png"), Currency code (required, Combobox placeholder "Type to search (e.g. EGP)"), Timezone (required, Combobox placeholder "Type to search (e.g. Africa/Cairo)"). Edit mode shows Cancel (X icon, secondary sm) + Save changes (Save icon, primary sm); read mode shows "Edit organization" (Pencil icon, secondary sm). Validation: name non-empty, currency ∈ list, timezone ∈ list (messages: "Organization name is required" / "Select a currency code from the list" / "Select a timezone from the list"). Copy EN/AR via `_copyEn`/`_copyAr` for the two add-branch/empty states.

### Phase 3 — Branches tab + shared list controls

Introduce the two shared list-control components (reused by Staff in P4), the working-hours editor, and the Branches tab.

| Web component | Flutter widget(s) to create | File(s) | Reuse | Deps |
|---|---|---|---|---|
| `ListControlBar` | `ListControlBar` (SearchInput + Filter popover + Sort dropdown + active-filter chip strip + Clear all) | CREATE `presentation/components/list_control_bar.dart` | `AppSearchInput` (`showShortcutHint:false`), `AppPopover` (Filter host), `AppMenu`/`MenuAnchor` (Sort), `AppButton` (secondary, SlidersHorizontal→`tune` leading), `AppChip` (removable), `Wrap` for the chip strip; filter-active badge counter; fade strip via `AnimatedSize`/`Visibility` (NOT a bottom-height `AnimatedContainer` in scroll — §0) | `AppPopover`, `AppChip` |
| `FilterMenuPanel` | `FilterMenuPanel` (single-section radio listbox) | CREATE `presentation/components/filter_menu_panel.dart` | `Material(transparent)` + `InkWell` rows (memory #23), `Check`→`Icons.check` selected leading, `AppTypography.overline`(caption) section label | — |
| `BranchFormFields` | `BranchFormFields` + `validateBranch()` + `branchToFormValues()` | CREATE `presentation/forms/branch_form_fields.dart`; CREATE `models/branch_form_values.dart`; CREATE `utils/working_schedule.dart` (relocated helpers) | `AppFormField`, `AppTextInput` (name, code, address, phone [`inputMode:numeric` digit-strip + `Directionality.ltr`], maps URL — `type:url`), `AppButton` (secondary "Set working hours" leading `event_available`), `AppDialog` (working-hours dialog), `WorkingHoursEditor`; 2-col grid; address/working-hours span 2 | `WorkingHoursEditor`, `kWeekdays` |
| `WorkingHoursEditor` | `WorkingHoursEditor` | CREATE `presentation/components/working_hours_editor.dart` | `AppSwitch` (per-day isWorkingDay), `AppTimePicker` (`use24Hour`, "Open"/"Close"), `AppTypography.bodySm`; wrapped `Material` shell per §0 | `AppSwitch`, `AppTimePicker` |
| `BranchFormDialog` | `BranchFormDialog` (create/edit) | CREATE `presentation/components/branch_form_dialog.dart` | `AppDialog` (`size: lg`, title "Add branch"/"Edit branch", description per mode), footer Cancel + "Create branch"/"Save changes"; `useEffect`→`initState`/`didUpdateWidget` reset draft+errors on open | `BranchFormFields`, `validateBranch` (requireHours = mode==create) |
| `BranchesTab` | `BranchesTab` | CREATE `presentation/components/branches_tab.dart`; CREATE `utils/branch_list_controls.dart` (`filterAndSortBranches`, `BranchListControls`, `BranchStatusFilter`, `BRANCH_SORT_OPTIONS`, `DEFAULT_BRANCH_CONTROLS`) | `AppButton` ("Add branch" `add`), `ListControlBar`, `FilterMenuPanel` (status: All/Active only/Inactive only), `AppBadge` (status pill success/warning soft sm, code pill neutral soft sm), `AppMenu` overflow (Edit `edit` / Activate-Deactivate `power_settings_new` / Delete `delete_outline` destructive), `AppEmptyState` (no-branches `location_on` / no-results `search_off`), `ConfirmationDialog` (`AppDialog` confirm: "Delete branch?"), `Card` via `DecoratedBox`+top gradient strip + `MouseRegion` hover (memory #18); 2-col grid (`LayoutBuilder` breakpoint) | `ListControlBar`, `FilterMenuPanel`, `BranchFormDialog` |
| `ClinicManagementPage` wiring | mount `BranchesTab` under the 'branches' tab | MOD `presentation/pages/clinic_management_page.dart` | `branches` from `clinicManagementProvider`, mutation methods | P2 page |

Dev-page instantiation spec (web `BranchesTab.tsx`): header "Branches" + "Every location your clinic operates. Staff and services are assigned per branch." + "Add branch" button; `ListControlBar` with search placeholder "Search by name, code, address, or phone…", sort options Name A–Z / Name Z–A / Code A–Z / Active first, filter="Status" (3 options). Empty state "No branches yet" + "Add your first location…". No-results "No branches match" + "Clear filters". Branch cards: top teal→violet gradient strip (1px), name + code `AppBadge` + status `AppBadge`, address, phone (`phone` icon, tabular), working-hours summary (`location_on` icon). Overflow menu 3 items. Delete confirmation "Delete branch?" → "Delete branch". Form dialog fields (6) + working hours sub-dialog (7 rows, Switch + 2 TimePickers each).

### Phase 4 — Staff tab + Roles tab

Staff list + staff CRUD (multi-select branches, role select, password, primary branch), and the role-permissions matrix grid with save/discard.

| Web component | Flutter widget(s) to create | File(s) | Reuse | Deps |
|---|---|---|---|---|
| `StaffFormFields` | `StaffFormFields` + `validateStaff(mode)` + `staffToFormValues()` + `emptyStaffFormValues()` | CREATE `presentation/forms/staff_form_fields.dart`; CREATE `models/staff_form_values.dart` | `AppFormField`, `AppTextInput` (fullName, phone [edit mode optional], username [hint], phone-number field with `Directionality.ltr` + digit strip), `AppPasswordInput` (create "Initial password" hint; edit "New password" leave-blank hint), `AppSelect` (role — placeholder "Select a role"; primary branch — only when `branchIds.length>1`), `AppMultiSelect` (branch assignments — active branches only, "No active branches…" fallback text when empty); "Login credentials" inset card (edit mode) | `kStaffRoles`, `kRoleLabels`, `kUsernameHint`, `kPasswordHint` |
| `StaffFilterPanel` | `StaffFilterPanel` (role Select + branch Select + Clear) | CREATE `presentation/components/staff_filter_panel.dart` | `AppFormField`, `AppSelect`; "Filters" overline caption; "Clear filters" `AppButton(secondary,sm,full width)` | `AppSelect` |
| `StaffFormDialog` | `StaffFormDialog` (create/edit) | CREATE `presentation/components/staff_form_dialog.dart` | `AppDialog` (size: lg, "Add staff member"/"Edit staff member"), footer Cancel + "Create account"/"Save changes" | `StaffFormFields`, `validateStaff` |
| `StaffTab` | `StaffTab` | CREATE `presentation/components/staff_tab.dart`; CREATE `utils/staff_list_controls.dart` (`filterAndSortStaff`, `StaffListControls`, `StaffRoleFilter`, `STAFF_SORT_OPTIONS`, `DEFAULT_STAFF_CONTROLS`) | `AppButton` ("Add staff member" `add`), `ListControlBar` (search "Search by name, username, phone, or role…", sort Name A–Z/Name Z–A/Role A–Z/Branch A–Z), `StaffFilterPanel` (role + branch), `AppAvatar` (name, md), `AppBadge` (role color from `kRoleBadgeColors`), `AppMenu` overflow (Edit / Delete destructive), `AppEmptyState` (no-staff `person` / no-results `search_off`), `ConfirmationDialog` ("Delete staff account?"), list rows in a bordered card with `divide`-style separators; `branchNames(member.branchIds, branches)` helper (>2 → "… +N") | `ListControlBar`, `StaffFilterPanel`, `StaffFormDialog`, `kRoleBadgeColors` |
| `RolePermissionsMatrix` | `RolePermissionsMatrix` (+ `GrantIndicator`, `GrantToggle`, `MatrixColumnHeaders`, `CategoryCard`) | CREATE `presentation/components/role_permissions_matrix.dart`; CREATE `utils/permission_matrix.dart`; CREATE `utils/role_theme.dart` | `AppTooltip` (column header role summary, `preferBelow:false` — memory #7, #11 NO tooltip inside popover child; this tooltip is NOT inside a popover so it's fine), `Material(transparent)`+`InkWell` `GrantToggle` (memory #23, #1), `Icons.check`/`Icons.close` indicator box (granted=filled action-primary; ungranted=border-default muted), dirty-cell tint via `BoxDecoration(color: action-primary@12%)` on the toggle; horizontal scroll body per card + sticky header (mirror web `overflow-x-auto`; `SingleChildScrollView(horizontal)` with `SizedBox(width:minWidth)` — memory #15) | `kRoleAccents`, `kRoleSummaries`, `permissionCategoryGroups()`, `canTogglePermissionGrant()` |
| `RolesTab` | `RolesTab` | CREATE `presentation/components/roles_tab.dart`; reuse relocated `rolePermissionsProvider` (already encodes draft/saved/dirty/save/discard/permissionDenied) | `AppButton` (Discard `close` secondary sm [only when hasChanges] + Save changes `save` primary sm [disabled when !hasChanges]), `RolePermissionsMatrix`, `AppEmptyState` (permission-denied), `AppErrorState`, removed `AppLoadingOverlay`/`AppSkeleton` loading | `RolePermissionsMatrix`, `rolePermissionsProvider` |
| `ClinicManagementPage` wiring | mount `StaffTab` under 'staff' and `RolesTab` under 'roles' | MOD `presentation/pages/clinic_management_page.dart` | `staff` + `branches` from `clinicManagementProvider`; `rolePermissionsProvider` for Roles | P3 |

Dev-page instantiation spec (web `StaffTab.tsx`/`RolesTab.tsx`): Staff header "People who sign in to AiClinic. Each account has a role and branch assignments." + "Add staff member"; list rows show `AppAvatar` + fullName + role `AppBadge`(teal/ai/info/neutral) + "@username · {branchNames}" + phone (sm: hidden) + overflow (Edit/Delete) → `ConfirmationDialog` "Delete staff account?" → "Delete account". `StaffFormDialog` create-mode fields: Full name, Phone number (required), Username (hint,"Staff username"), Initial password (hint, "••••••••"), Role select, Branch assignments MultiSelect (required, "Select branches" placeholder, active branches only, empty-state text), Primary branch Select (shown when `branchIds.length>1`). Edit-mode shows the "Login credentials" inset (Username + New password "Leave blank to keep the current password"). Roles tab: header "Built-in roles and their access grants…" + Save changes/Discard; matrix = 4 columns (administrator/doctor/receptionist/lab_staff) × N permission rows grouped by category card (category label = permission prefix capitalized, "ai"→"AI"), each cell a toggle; column header shows role label + gradient accent strip (1px) + tooltip summary from `kRoleSummaries`; `settings.billing.manage` is only grantable to administrator (guard in `canTogglePermissionGrant`).

## 4. Dev-page instantiation spec per widget (mirrors web reference)

> **Binding source of truth:** the layout, copy, props, ordering, and states in each Flutter presentation component **must mirror exactly** the corresponding file in `web-reference/src/features/clinic-management/` (`ClinicManagementPage.tsx`, `components/*Tab.tsx`, `components/*FormDialog.tsx`, `forms/*FormFields.tsx`, `forms/WorkingHoursEditor.tsx`, `components/ListControlBar.tsx`, `components/FilterMenuPanel.tsx`, `components/StaffFilterPanel.tsx`, `components/RolePermissionsMatrix.tsx`, `components/ClinicHero.tsx`, plus `constants.ts` / `working-schedule.ts` / `permission-matrix.ts` / `role-theme.ts` / `utils/*-list-controls.ts` / `types.ts`). Composer 2.5 should open the referenced `.tsx` for each component and reproduce demo-for-demo:
> - the exact tab order: Organization → Branches → Staff → Roles (web `TAB_ITEMS`);
> - the exact field set, order, labels, placeholders, required flags, helper/hint text, and validators per form (port the `validate*` functions verbatim, adjusting regex to Dart `RegExp`);
> - the exact list-bar/empty-state/confirmation copy;
> - the icon→Material mapping in §0.8.
>
> **Unsupported web affordances to OMIT** (per the user's "ignore unmatched fields" instruction):
> - `ClinicHero` radial-blur decorative blobs + `backdrop-filter` on stat tiles (§0.2) → keep only the diagonal `LinearGradient`.
> - Branch card "View on maps" `<a target=_blank>` external link (no `url_launcher` dep) → omit the link text + `open_in_new` icon; keep `mapsUrl` on the model.
> - `motion/react` `layout` shared-element transitions on list items → replace with simple `AppMotion` fade-in on mount (unsupported — §0.2).
> - Web `motion/react` enter `{ initial:{opacity:0,y:6}, animate:{opacity:1,y:0} }` per tab → approximate with `AppMotion` fade-slide via `AnimatedSwitcher` on the active tab body.
> - `crypto.randomUUID()` (web `newId(prefix)`) → Dart `UniqueKey()` or a lightweight UUID generator; IDs are server-generated for real persists anyway (the notifier sends creates without client IDs — match the existing real use-case contracts).

The Flutter page uses **native App widgets** with their idiomatic prop names (e.g. web `defaultValue="x"` → `AppTextInput(initialValue:'x')` or a `TextEditingController`; web `invalid` → `AppTextInput(invalid:true)`; web `disabled` → `disabled:true`; web `onValueChange` → `onChanged`/`onSelected`). The `ShowcaseDemoGrid`/`ShowcaseDemo` primitives are NOT used (this is a feature page, not a Dev showcase); the page is mounted directly in `AppShell` via `GoRoute`.

## 5. Wiring steps (do after each phase lands)

### Phase 1 wiring
1. `git mv` each domain/data/application/provider file from `features/settings/` to `features/clinic-management/` (preserve history). Rename per §3.
2. Update every external import consumer listed in the Phase-1 blast-radius table (patients, appointments, setup, app/providers, app/shell). Run `flutter analyze` after each feature folder is repointed to catch stragglers.
3. Trim `features/settings/presentation/models/settings_tab.dart` to `general` only; delete the now-empty `settings/domain/repositories/`, `settings/domain/usecases/`, `settings/presentation/providers/` directories.
4. `app/app_routes.dart`: add `clinicManagement` + `clinicManagementPaths`; in `adminSettingsPaths` keep the four admin constants (used for redirects).
5. `app/router.dart`: replace the four `/settings/{organization|branches|staff|permissions}` + `/settings/branches/new` + `/settings/staff/new` + `/settings/branches/:id/edit` + `/settings/staff/:id` + `/settings/staff/:id/reset-password` `GoRoute(builder: shellPlaceholderPage)` entries with `redirect: (_) => AppRoutes.clinicManagement` (one-line redirects). Keep `/settings` (general/idle-timeout) page. Add `GoRoute(path: AppRoutes.clinicManagement, builder: shellPlaceholderPage)` (Phase 1 placeholder; P2 swaps builder).
6. `app/shell/navigation/shell_nav_config.dart`: add the `'clinic-management'` nav item to `kClinicNavGroups` (Operations group) + `_routesByItemId` + `itemIdForLocation`; add `ShellRouteMeta` title "Clinic Management" / description "Organization identity, locations, team accounts, and access roles.".
7. `core/auth/auth_route_guard.dart`: `isAdminSettingsRoute` covers the four `/settings/*` admin paths — keep those (they now redirect, so the guard runs before redirect); add `isClinicManagementRoute(location)` == `location == AppRoutes.clinicManagement` and fold it into `requiresAuthentication`. Add `clinicManagementRouteRedirect({location, auth})` mirroring the existing `adminSettingsRedirect` (organization→`canAccessOrganizationSettings`, branches→`canAccessBranchManagement`, staff→`canAccessStaffManagement`, permissions→`canAccessPermissionMatrix`), returning `AppRoutes.home` on denial. Call it from the router `redirect`. (Non-admins landing on `/clinic-management` with no accessible sub-area redirect home.)
8. Run `flutter analyze` (project uses `flutter_lints`) — fix all import path breakages. Do **not** commit unless asked.

### Phase 2 wiring
1. Swap the `clinicManagement` `GoRoute` builder from `shellPlaceholderPage` to `ClinicManagementPage()` (import `features/clinic-management/presentation/pages/clinic_management_page.dart`).
2. Tabs honor access: build `clinicManagementTabsFor(auth)` filtering out Organization when `!canAccessOrganizationSettings&&!canAccessBranchManagement`, Branches when `!canAccessBranchManagement`, Staff when `!canAccessStaffManagement`, Roles when `!canAccessPermissionMatrix`. If the filtered list is empty, show `AppEmptyState`/`AppErrorState` (permission-denied). Default tab = first visible.
3. Wire `OrganizationTab` to `clinicManagementProvider.updateOrganization`.
4. `flutter analyze`.

### Phase 3 wiring
1. Mount `BranchesTab` under the 'branches' tab; wire `clinicManagementProvider.addBranch/updateBranch/removeBranch/toggleBranchActive` (these call the real `createBranch/updateBranch/deleteBranch/setBranchActive` use cases, then invalidate `clinicSetupBranchesProvider`).
2. Confirm `ensureIntlDateFormattingInitialized()` is called in `main.dart` before any `AppTimePicker` mounts (memory #3) — if missing, add it.
3. `flutter analyze`; manually open Working hours dialog and exercise open/close Times.

### Phase 4 wiring
1. Mount `StaffTab` (wire `addStaff/updateStaff/removeStaff`) and `RolesTab` (reuse `rolePermissionsProvider.saveChanges/discardChanges/setLocalGrant`).
2. `flutter analyze`; manually exercise Staff create/edit (multi-select branches, role select, primary branch appears when >1), and Roles matrix toggle + Save + Discard + permission-denied state.

## 6. Out-of-scope / defer

- **`url_launcher` / "View on maps" external links** — deferred until a future milestone adds the dep. The `mapsUrl` field stays on the model and in the branch form.
- **`ClinicHero` blur/backdrop-filter cosmetics** — simplified to a `LinearGradient` banner; the radial blobs are not ported.
- **`motion/react` shared-layout animations** on list items — not ported (no equivalent without heavy custom work); replaced with simple fade-in.
- **Server-persisted IDs.** Web `newId(prefix)` client-side UUIDs are not reproduced; real creates rely on server-generated IDs (the existing use-case contracts already do this).
- **Promoting `ListControlBar`/`FilterMenuPanel`/`RolePermissionsMatrix` to `core/ui/components/`.** Kept feature-local for now; promote only if a second consumer appears (e.g. patients/services lists).
- **Retiring the `/settings/{organization,branches,staff,permissions}` constants entirely.** Kept as redirects to avoid breaking deep links / guards. A later cleanup milestone can remove them once all in-app navigation targets `/clinic-management`.
- **Settings page general/idle-timeout UI** is unchanged (still placeholder-routed).
- **No new `core/ui/components/` files.**

## 7. Source reference — web widget inventory

The Clinic Management page surfaces these tabs/sections/components under `web-reference/src/features/clinic-management/`:

| id | Title | Web file | Underlying web building blocks | Flutter analog |
|---|---|---|---|---|
| `clinic-management` | Clinic Management (page) | `ClinicManagementPage.tsx` | `PageHeader` (`@/components/layout/PageHeader`), `Tabs` (`@/components/navigation/Tabs`) | `AppPageHeader` + `AppTabs` |
| `organization` | Organization (tab) | `components/OrganizationTab.tsx` | `Button`, `ClinicHero`, `OrganizationFormFields` | `AppButton`, `ClinicHero`, `OrganizationFormFields` |
| `organization-form` | (form fields) | `forms/OrganizationFormFields.tsx` | `FormField`, `TextInput`, `Combobox` | `AppFormField`, `AppTextInput`, `AppCombobox` |
| `clinic-hero` | Clinic identity banner | `components/ClinicHero.tsx` | `motion`, `Building2/MapPin/Shield/Users`, gradient panes | `AppAvatar` + `LinearGradient` `Container` (cosmetics trimmed) |
| `branches` | Branches (tab) | `components/BranchesTab.tsx` | `Button`, `IconButton`, `Badge`, `ConfirmationDialog`, `DropdownMenu`, `BranchFormDialog`, `FilterMenuPanel`, `ListControlBar`, working-schedule summary | `AppButton`, `AppIconButton`, `AppBadge`, `AppDialog`, `AppMenu`, `BranchFormDialog`, `FilterMenuPanel`, `ListControlBar` |
| `branch-form` | (branch form) | `forms/BranchFormFields.tsx`, `components/BranchFormDialog.tsx` | `FormField`, `TextInput`, `Button`, `Dialog`, `WorkingHoursEditor` | `AppFormField`, `AppTextInput`, `AppButton`, `AppDialog`, `WorkingHoursEditor` |
| `working-hours-editor` | (working hours) | `forms/WorkingHoursEditor.tsx` | `Switch`, `TimePicker` | `AppSwitch`, `AppTimePicker` |
| `list-control-bar` | (shared list control) | `components/ListControlBar.tsx` | `SearchInput`, `Popover`, `DropdownMenu`, `Chip`, `Button` | `AppSearchInput`, `AppPopover`, `AppMenu`, `AppChip`, `AppButton` |
| `filter-menu-panel` | (branch status filter) | `components/FilterMenuPanel.tsx` | (plain buttons) | `Material`+`InkWell` listbox |
| `staff` | Staff (tab) | `components/StaffTab.tsx` | `Button`, `IconButton`, `Avatar`, `Badge`, `ConfirmationDialog`, `DropdownMenu`, `StaffFormDialog`, `StaffFilterPanel`, `ListControlBar` | `AppButton`, `AppIconButton`, `AppAvatar`, `AppBadge`, `AppDialog`, `AppMenu`, `StaffFormDialog`, `StaffFilterPanel`, `ListControlBar` |
| `staff-form` | (staff form) | `forms/StaffFormFields.tsx`, `components/StaffFormDialog.tsx` | `FormField`, `TextInput`, `PasswordInput`, `Select`, `MultiSelect` | `AppFormField`, `AppTextInput`, `AppPasswordInput`, `AppSelect`, `AppMultiSelect` |
| `staff-filter-panel` | (staff role+branch filter) | `components/StaffFilterPanel.tsx` | `FormField`, `Select`, `Button` | `AppFormField`, `AppSelect`, `AppButton` |
| `roles` | Roles & permissions (tab) | `components/RolesTab.tsx` | `Button`, `RolePermissionsMatrix`, `permission-matrix.ts` (grants/dirty/clone/equals/canToggle), `role-theme.ts` | `AppButton`, `RolePermissionsMatrix`, relocated `rolePermissionsProvider`, `utils/permission_matrix.dart`, `utils/role_theme.dart` |
| `role-permissions-matrix` | (grant grid) | `components/RolePermissionsMatrix.tsx` | `Tooltip`, `STAFF_ROLES`, `ROLE_ACCENTS`, `ROLE_SUMMARIES` | `AppTooltip`, `kStaffRoles`, `kRoleAccents`, `kRoleSummaries`, `Material`+`InkWell` toggles |

Shared web building blocks (and where they live / Flutter equivalents):

- `tabs/Tabs.tsx` (`@/components/navigation/Tabs`) → `AppTabs`.
- `PageHeader` (`@/components/layout/PageHeader`) → `AppPageHeader`.
- `Button` (`@/components/actions/Button`) → `AppButton`; `IconButton` → `AppIconButton`.
- `Badge` (`@/components/badge`) → `AppBadge`; `Avatar` → `AppAvatar`; `Chip` → `AppChip`.
- `Dialog` + `ConfirmationDialog` (`@/components/dialog/Dialog`) → `AppDialog` (+ confirm variant).
- `FormField` (`@/components/ui/form-field/FormField`) → `AppFormField`.
- `TextInput`/`PasswordInput`/`Select`/`Combobox`/`MultiSelect`/`SearchInput`/`Switch`/`TimePicker` (`@/components/ui/...`) → `AppTextInput`/`AppPasswordInput`/`AppSelect`/`AppCombobox`/`AppMultiSelect`/`AppSearchInput`/`AppSwitch`/`AppTimePicker`.
- `DropdownMenu*` (`@/components/ui/DropdownMenu`) → `AppMenu`/`MenuAnchor` (`app_menu.dart`).
- `Popover` (`@/components/ui/popover/Popover`) → `AppPopover`.
- `Tooltip` (`@/components/tooltip/Tooltip`) → `AppTooltip`.
- `motion/react`, `getReducedMotion`, `motionPresets`, `resolveTransition` → `AppMotion` (`core/ui/motion/app_motion.dart`) + `AnimatedSwitcher`/`AnimatedSize`.
- `cn` (`@/lib/cn`) → direct `BoxDecoration`/`TextStyle` composition; no `cn` analog needed.
- `lucide-react` icons → Material `Icons.*` per §0.8.
- `useClinicManagementState` (web mock) → **replaced** by real `clinicManagementProvider` (AsyncNotifier) backed by relocated Supabase-RPC use-cases (NOT ported verbatim — see §0.7).
- `mock-data.ts` (`INITIAL_ORGANIZATION/BRANCHES/STAFF`) → not ported; shell dev seed (`app/shell/dev/dev_clinic_seed_service.dart`) seeds the real repos (its imports get repointed in Phase 1).
- `crypto.randomUUID()` → omitted (server-generated IDs).