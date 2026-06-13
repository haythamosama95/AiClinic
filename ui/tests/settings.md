# Settings hub & clinic administration UI tests

Comprehensive test coverage for branch `ui/006-settings` (built on `ui/005-first-setup`) — settings page hub, appearance/idle timeout, clinic setup (org/branch CRUD), staff management, role permissions matrix, tab transitions, and related backend migrations.

**Run frontend:**

```bash
cd frontend && flutter test \
  test/widget/settings/ \
  test/unit/settings/ \
  test/unit/setup/provisioning_notifier_test.dart \
  test/unit/auth/auth_session_idle_duration_test.dart \
  test/integration/settings/ \
  test/widget/setup/branch_form_fields_test.dart \
  test/widget/setup/organization_form_fields_test.dart
```

**Run backend (requires `DATABASE_URL`):**

```bash
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f backend/tests/org_branch_management_crud.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f backend/tests/org_branch_management_extended.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f backend/tests/org_branch_management_rls.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f backend/tests/create_staff_rpc.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f backend/tests/admin_reset_staff_password.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f backend/tests/delete_staff_member.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f backend/tests/admin_update_staff_username.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f backend/tests/role_permissions_matrix.sql
```

**Run boundary (live DB):**

```bash
cd frontend && flutter test test/boundary/settings/ --tags boundary
```

**Source files:**

| File                                                                         | Scope                                               |
| ---------------------------------------------------------------------------- | --------------------------------------------------- |
| `frontend/test/widget/settings/settings_page_test.dart`                      | Hub tabs, appearance, grid layout, shell navigation |
| `frontend/test/widget/settings/settings_section_card_test.dart`              | Edit/save/cancel header actions                     |
| `frontend/test/widget/settings/clinic_setup_settings_tab_test.dart`          | Org/branch read-only, add branch, lifecycle         |
| `frontend/test/widget/settings/branch_working_hours_sheet_test.dart`         | Working hours validation                            |
| `frontend/test/widget/settings/staff_list_page_test.dart`                    | Staff grid, search, filters, create modal           |
| `frontend/test/widget/settings/staff_detail_sheet_test.dart`                 | View/edit sheet, credentials, lifecycle             |
| `frontend/test/widget/settings/role_permissions_page_test.dart`              | Matrix visibility, RBAC denial                      |
| `frontend/test/widget/settings/role_permissions_matrix_test.dart`            | Matrix scroll sync, pinned headers                  |
| `frontend/test/unit/settings/branch_repository_test.dart`                    | Branch RPC payloads & error mapping                 |
| `frontend/test/unit/settings/staff_admin_repository_test.dart`               | Staff update/deactivate/delete RPC                  |
| `frontend/test/unit/settings/staff_list_query_test.dart`                     | Search/filter query logic                           |
| `frontend/test/unit/settings/permission_matrix_view_test.dart`               | Matrix grouping, dirty tracking                     |
| `frontend/test/unit/auth/auth_session_idle_duration_test.dart`               | Idle timeout persistence → service                  |
| `frontend/test/unit/settings/role_permissions_notifier_test.dart`            | Matrix toggle, discard, save RPC batching           |
| `frontend/test/unit/settings/idle_timeout_settings_notifier_test.dart`       | Custom minutes validation and persistence           |
| `frontend/test/unit/setup/provisioning_notifier_test.dart`                   | createStaffAccount RPC + branch guard               |
| `frontend/test/widget/settings/create_staff_modal_test.dart`                 | Form fields, branch snackbar, close                 |
| `frontend/test/widget/settings/idle_timeout_settings_card_test.dart`         | Preset display, custom mode from store              |
| `frontend/test/integration/settings/admin_settings_route_redirect_test.dart` | Route guards & deep links                           |
| `frontend/test/widget/setup/branch_form_fields_test.dart`                    | Shared branch form (setup + settings)               |
| `frontend/test/widget/setup/organization_form_fields_test.dart`              | Shared org form                                     |
| `backend/tests/org_branch_management_extended.sql`                           | delete_branch, staff create validation, audit       |
| `backend/tests/org_branch_management_crud.sql`                               | Branch CRUD, permission matrix, last-admin          |
| `backend/tests/create_staff_rpc.sql`                                         | Staff provisioning contract                         |
| `backend/tests/admin_reset_staff_password.sql`                               | Password reset RBAC                                 |
| `backend/tests/delete_staff_member.sql`                                      | delete_staff_member RPC guards                      |
| `backend/tests/admin_update_staff_username.sql`                              | Username change RPC                                 |
| `backend/tests/role_permissions_matrix.sql`                                  | Matrix toggle, billing delegation, doctor FORBIDDEN |

**Status legend:** ✅ implemented · 📋 planned / not automatable in CI

**Frontend automation:** 229 tests in settings suites (see run command above).

**Not automated (by design):** tab transition frame timing (220 ms), blur backdrop GPU fidelity, release-mode-only behaviors, multi-monitor viewport extremes, live GoTrue sign-in after staff create (`staff_sign_in_after_create.sh` is manual).

---

## Commit map

| Commit    | Summary                          | Primary test sections                           |
| --------- | -------------------------------- | ----------------------------------------------- |
| `0817839` | Settings hub + appearance        | SettingsPage, GeneralSettingsTab, shell nav     |
| `c9cddb5` | Clinic setup tab + working hours | ClinicSetupSettingsTab, BranchWorkingHoursSheet |
| `2651167` | Add branch button + modal        | CreateBranchModal, BranchRepository             |
| `cc8682d` | Branch deactivate/delete         | BranchSettingsSection, delete_branch RPC        |
| `e02cea2` | Staff roles permission matrix    | RolePermissionsPage, PermissionMatrixView       |
| `27326af` | Idle timeout settings card       | IdleTimeoutSettingsCard, idle service wiring    |
| `779805f` | Staff management page            | StaffListPage, filters, create modal            |
| `688f152` | Idle timeout forced on load      | auth_session_provider, idle duration unit       |
| `3fce5d0` | Staff detail right sheet         | StaffDetailSheet, admin_update_staff_username   |
| `8430d19` | Staff deactivate/delete/reset    | StaffDetailSheet lifecycle, delete_staff_member |
| `fefef85` | Tab transition animation         | SettingsPage AnimatedSwitcher                   |
| `e671a4d` | Staff page test fix              | settings_page_test regression                   |
| `e21f369` | Review fixes                     | delete_staff guards, password validation        |

---

## 0817839 — Settings initial design & appearance

### SettingsPage host

| Test Name                                           | Scenario                | Pass Criteria                                                | Fail Criteria       | Status |
| --------------------------------------------------- | ----------------------- | ------------------------------------------------------------ | ------------------- | ------ |
| `renders all settings tabs`                         | Open `/settings`        | General, Clinic Setup, Staff Management, Staff Roles visible | Missing tab         | ✅      |
| `default tab is General`                            | Fresh navigation        | General content visible; primary color on General            | Wrong default       | ✅      |
| `selecting tab switches content and primary color`  | Tap Clinic Setup        | Clinic tab primary; General muted                            | Stale highlight     | ✅      |
| `invalid initialTabId falls back to General`        | `initialTabId: 'bogus'` | General tab selected                                         | Crash or blank      | ✅      |
| `re-tapping active tab is no-op`                    | Tap General twice       | No transition flicker; state unchanged                       | Rebuild error       | ✅      |
| `settings route renders inside authenticated shell` | Shell + settings        | Header settings tooltip navigates back                       | Route outside shell | ✅      |

### GeneralSettingsTab — Appearance

| Test Name                                               | Scenario                | Pass Criteria                             | Fail Criteria    | Status |
| ------------------------------------------------------- | ----------------------- | ----------------------------------------- | ---------------- | ------ |
| `general tab shows appearance settings card`            | General tab             | Appearance + Idle sign-out cards          | Missing cards    | ✅      |
| `theme variant radio shows Astro Vista and Claude+`     | General tab             | Both palette options visible              | Missing variant  | ✅      |
| `color mode radio shows Light Dark System`              | General tab             | All ThemeMode options                     | Missing mode     | ✅      |
| `appearance card updates color mode selection`          | Tap Dark                | `themeModeProvider` → dark                | State unchanged  | ✅      |
| `theme variant selection updates provider`              | Tap Claude+             | `themeVariantProvider` updated            | Wrong variant    | ✅      |
| `settings cards use half page width in two-column grid` | 1000px width            | Each card ≈ (grid − gap) / 2              | Full-width cards | ✅      |
| `single card on narrow viewport stacks full width`      | 400px width             | Cards stack; no horizontal overflow       | Clipped content  | ✅      |
| `stupid usage: rapid theme toggling`                    | Tap Light/Dark 10× fast | No exception; final mode matches last tap | Crash or desync  | ✅      |

### SettingsTabBar

| Test Name                                            | Scenario     | Pass Criteria                        | Fail Criteria               | Status |
| ---------------------------------------------------- | ------------ | ------------------------------------ | --------------------------- | ------ |
| `tab bar horizontally scrollable when tabs overflow` | 240px width  | `maxScrollExtent > 0`                | Tabs clipped without scroll | ✅      |
| `tab icons render for each definition`               | All tabs     | tune, apartment, people, badge icons | Missing icons               | ✅      |
| `selected tab shows primary underline or color`      | Select Staff | Visual selected state                | Indistinguishable tabs      | ✅      |

### Shell integration

| Test Name                                           | Scenario          | Pass Criteria                 | Fail Criteria | Status |
| --------------------------------------------------- | ----------------- | ----------------------------- | ------------- | ------ |
| `settings header button navigates to settings page` | Tap header gear   | SettingsPage with General tab | Stays on home | ✅      |
| `settings page title shown in shell header`         | On settings route | "Settings" in header          | Wrong title   | ✅      |

---

## c9cddb5 — Branch settings aligned with setup phase

### ClinicSetupSettingsTab

| Test Name                                               | Scenario                    | Pass Criteria                              | Fail Criteria         | Status |
| ------------------------------------------------------- | --------------------------- | ------------------------------------------ | --------------------- | ------ |
| `shows organization and branch cards in read-only mode` | Loaded profile              | Org name, branch summary; no `*` labels    | Editable fields shown | ✅      |
| `organization card uses settings section layout`        | Render                      | `SettingsSectionCard` present              | Wrong container       | ✅      |
| `edit button reveals organization form fields`          | Tap Edit on org             | Name/currency/timezone fields; Save/Cancel | Stays read-only       | ✅      |
| `cancel edit restores original values`                  | Edit → change name → Cancel | Original name shown                        | Dirty value kept      | ✅      |
| `save organization calls update RPC`                    | Edit → valid change → Save  | RPC success; read-only mode                | Stuck in edit         | ✅      |
| `loading state shows spinner`                           | Slow provider               | Progress indicator                         | Blank screen          | ✅      |
| `error state shows retry`                               | Provider throws             | Error message + retry                      | Infinite spinner      | ✅      |

### Shared form fields (setup ↔ settings)

| Test Name                                                 | Scenario           | Pass Criteria                           | Fail Criteria      | Status |
| --------------------------------------------------------- | ------------------ | --------------------------------------- | ------------------ | ------ |
| `organization form create mode shows editable fields`     | Create mode        | Name, currency, timezone                | Missing fields     | ✅      |
| `organization form edit mode read-only until editing`     | Edit mode          | Read-only values; Modify reveals fields | Always editable    | ✅      |
| `branch form create mode shows working hours beside maps` | Wide create layout | Hours button + maps field same row      | Missing hours      | ✅      |
| `branch form requires working hours in setup wizard`      | Setup branch step  | Next disabled without hours             | Next enabled       | ✅      |
| `branch form edit mode two-column grid in settings`       | Settings edit      | Grid layout inside card                 | Single column only | ✅      |
| `branch working hours check mark when configured`         | Hours saved        | Check icon on hours button              | No indicator       | ✅      |

### BranchWorkingHoursSheet

| Test Name                                        | Scenario          | Pass Criteria                      | Fail Criteria        | Status |
| ------------------------------------------------ | ----------------- | ---------------------------------- | -------------------- | ------ |
| `error when close time before open time`         | Mon 17:00–09:00   | Alert: close must be after open    | Save enabled         | ✅      |
| `error when close equals open time`              | Mon 09:00–09:00   | Same error panel                   | Accepted             | ✅      |
| `valid hours hide error panel`                   | Mon 09:00–17:00   | No alert                           | False positive error | ✅      |
| `toggle day off clears times`                    | Disable Monday    | isWorkingDay false                 | Times still required | ✅      |
| `all days off rejected on save`                  | Zero working days | Validation error                   | Saved empty schedule | ✅      |
| `midnight-spanning hours rejected or documented` | 22:00–06:00       | Clear UX (reject or next-day rule) | Silent bad data      | ✅      |
| `stupid usage: spam toggle all days`             | Rapid day toggles | Stable UI; no exception            | Crash                | ✅      |

### Backend — bootstrap_finish_setup_working_schedule

| Test Name                                         | Scenario               | Pass Criteria                | Fail Criteria       | Status                             |
| ------------------------------------------------- | ---------------------- | ---------------------------- | ------------------- | ---------------------------------- |
| `finish_setup persists branch working_schedule`   | Bootstrap finish       | Schedule JSON on branch row  | NULL schedule       | ✅ (bootstrap_repository_test)      |
| `manage_create_branch requires working_schedule`  | Settings create branch | RPC accepts schedule payload | Missing param error | ✅ (org_branch_management_extended) |
| `update_branch persists working_schedule changes` | Settings hours save    | DB matches submitted JSON    | Stale schedule      | ✅ (org_branch_management_extended) |

---

## 2651167 — Add a new branch

| Test Name                                     | Scenario         | Pass Criteria                          | Fail Criteria      | Status                     |
| --------------------------------------------- | ---------------- | -------------------------------------- | ------------------ | -------------------------- |
| `add branch button visible on org card`       | Clinic setup tab | "Add branch" + add_business icon       | Button missing     | ✅                          |
| `add branch opens blurred create modal`       | Tap Add branch   | BackdropFilter; branch form fields     | Inline form only   | ✅                          |
| `create branch modal has Create branch CTA`   | Modal open       | Create branch button                   | Missing submit     | ✅                          |
| `create branch modal dismiss on scrim tap`    | Tap outside      | Modal closes; no branch created        | Stuck open         | ✅                          |
| `create branch validates required fields`     | Submit empty     | Inline errors; no RPC                  | RPC with bad data  | ✅                          |
| `create branch success refreshes branch list` | Valid submit     | New branch card appears                | Stale list         | ✅                          |
| `duplicate branch code surfaces server error` | Code collision   | User-facing duplicate message          | Generic error      | ✅ (branch_repository unit) |
| `stupid usage: double-tap Create branch`      | Rapid taps       | Single RPC; button disabled while busy | Duplicate branches | ✅                          |

### BranchRepository (unit)

| Test Name                                            | Scenario          | Pass Criteria                     | Fail Criteria | Status |
| ---------------------------------------------------- | ----------------- | --------------------------------- | ------------- | ------ |
| `createBranch sends manage_create_branch parameters` | Valid input       | Correct RPC name + trimmed fields | Wrong payload | ✅      |
| `empty branch name rejected locally`                 | `name: ''`        | INVALID_INPUT before RPC          | RPC called    | ✅      |
| `listBranches returns creation order`                | Multiple branches | Stable ordering                   | Random order  | ✅      |

---

## cc8682d — Branch deactivate & permanent delete

### BranchSettingsSection UI

| Test Name                                           | Scenario               | Pass Criteria                       | Fail Criteria       | Status                     |
| --------------------------------------------------- | ---------------------- | ----------------------------------- | ------------------- | -------------------------- |
| `active branch shows deactivate icon`               | Active branch card     | delete_outline + Deactivate tooltip | Delete on active    | ✅                          |
| `active branch shows active status icon`            | Active branch          | check_circle + Active tooltip       | Wrong icon          | ✅                          |
| `inactive branch shows activate + permanent delete` | Inactive branch        | play + delete_forever tooltips      | Deactivate shown    | ✅                          |
| `deactivate opens confirmation dialog`              | Tap deactivate         | "Deactivate branch?" dialog         | Immediate RPC       | ✅                          |
| `permanent delete opens confirmation dialog`        | Inactive → delete      | "Delete branch permanently?"        | Immediate delete    | ✅                          |
| `confirm deactivate calls set_branch_active false`  | Confirm dialog         | RPC `set_branch_active`             | No RPC              | ✅                          |
| `LAST_ACTIVE_BRANCH error shown in toast`           | Sole branch deactivate | User message                        | Silent fail         | ✅ (branch_repository unit) |
| `BRANCH_STILL_ACTIVE on delete active branch`       | Delete while active    | Error mapped                        | Success             | ✅ (branch_repository unit) |
| `edit branch saves trimmed fields`                  | Edit → Save            | update_branch RPC                   | Dirty state         | ✅                          |
| `working hours sheet from branch card`              | Tap hours in edit      | Right sheet opens                   | Missing entry point | ✅                          |

### Backend — delete_branch (`20260613130000`)

| Test Name                                           | Scenario          | Pass Criteria          | Fail Criteria       | Status |
| --------------------------------------------------- | ----------------- | ---------------------- | ------------------- | ------ |
| `delete active branch rejected BRANCH_STILL_ACTIVE` | Active branch     | Error code             | Soft-deleted active | ✅      |
| `delete inactive branch succeeds`                   | Inactive branch   | success true           | Failure             | ✅      |
| `delete marks is_deleted on branch row`             | After delete      | is_deleted true        | Row hard-deleted    | ✅      |
| `delete idempotent rejected BRANCH_ALREADY_DELETED` | Second delete     | Error code             | Double delete       | ✅      |
| `delete soft-deletes staff_branch_assignments`      | Has assignments   | Assignments is_deleted | Orphan assignments  | ✅      |
| `delete writes audit_log entry`                     | Successful delete | audit row              | No audit            | ✅      |
| `non-admin caller forbidden`                        | Doctor JWT        | FORBIDDEN              | Success             | ✅      |
| `cross-org branch id rejected BRANCH_NOT_FOUND`     | Other org UUID    | Error                  | Cross-org delete    | ✅      |

---

## e02cea2 — Staff roles permission matrix

### RolePermissionsPage

| Test Name                                     | Scenario       | Pass Criteria                                  | Fail Criteria       | Status |
| --------------------------------------------- | -------------- | ---------------------------------------------- | ------------------- | ------ |
| `administrator sees role columns`             | Admin session  | Administrator, Doctor, Receptionist, Lab staff | Owner column        | ✅      |
| `permissions grouped by category`             | Matrix loaded  | Settings, Patients section headers             | Flat unordered list | ✅      |
| `permission labels humanized`                 | Matrix         | "Manage Branches", "View"                      | Raw keys only       | ✅      |
| `doctor sees permission denied message`       | Doctor session | administrators-only copy                       | Matrix visible      | ✅      |
| `embedded mode fits settings staff-roles tab` | Tab content    | No duplicate app bar                           | Double scaffold     | ✅      |

### RolePermissionsMatrix widget

| Test Name                                           | Scenario              | Pass Criteria                            | Fail Criteria       | Status |
| --------------------------------------------------- | --------------------- | ---------------------------------------- | ------------------- | ------ |
| `checkbox reflects grant state`                     | Loaded matrix         | Checked = granted                        | Inverted            | ✅      |
| `toggle checkbox marks dirty state`                 | Uncheck patients.view | Unsaved indicator                        | Immediate RPC       | ✅      |
| `save submits only changed cells`                   | Toggle one cell       | `update_role_permission` once per change | Full matrix rewrite | ✅      |
| `discard resets working copy`                       | Toggle → Discard      | Restored saved state                     | Dirty persists      | ✅      |
| `billing.manage not delegable to non-administrator` | Doctor column billing | Checkbox disabled or RPC FORBIDDEN       | Doctor gets billing | ✅      |
| `horizontal scroll syncs header and body`           | Narrow width          | Header scroll matches body               | Misaligned columns  | ✅      |
| `pinned category headers stay visible`              | Vertical scroll       | Category labels sticky                   | Headers scroll away | ✅      |
| `stupid usage: toggle same cell rapidly`            | Spam click            | Stable final state                       | Exception           | ✅      |

### PermissionMatrixView (unit)

| Test Name                                | Scenario         | Pass Criteria                | Fail Criteria  | Status |
| ---------------------------------------- | ---------------- | ---------------------------- | -------------- | ------ |
| `displayRoles excludes owner`            | Static list      | 4 operational roles          | Owner present  | ✅      |
| `categoryGroups clusters by prefix`      | Mixed keys       | ai, patients, settings order | Wrong grouping | ✅      |
| `changesFrom detects dirty cells`        | withGrant toggle | Single change listed         | Missed diff    | ✅      |
| `missing role cell defaults not granted` | Partial rows     | false for absent role        | true default   | ✅      |

### Backend — role_permissions_full_matrix (`20260613140000`)

| Test Name                                          | Scenario       | Pass Criteria    | Fail Criteria | Status |
| -------------------------------------------------- | -------------- | ---------------- | ------------- | ------ |
| `update_role_permission nonexistent key rejected`  | Bad key        | Failure          | Silent no-op  | ✅      |
| `administrator can toggle receptionist permission` | Valid key      | Success + audit  | FORBIDDEN     | ✅      |
| `doctor cannot call update_role_permission`        | Doctor JWT     | FORBIDDEN        | Success       | ✅      |
| `matrix seed includes all V1 permission keys`      | Post migration | Complete catalog | Missing keys  | ✅      |

### Route guards

| Test Name                                                    | Scenario                | Pass Criteria         | Fail Criteria  | Status |
| ------------------------------------------------------------ | ----------------------- | --------------------- | -------------- | ------ |
| `doctor deep-link to permissions redirected to settings hub` | `/settings/permissions` | `/settings` + General | Matrix renders | ✅      |
| `administrator can open permissions via staff-roles tab`     | Admin                   | Matrix visible        | Denied         | ✅      |

---

## 27326af — Idle timeout settings

| Test Name                                   | Scenario                 | Pass Criteria         | Fail Criteria   | Status |
| ------------------------------------------- | ------------------------ | --------------------- | --------------- | ------ |
| `idle sign-out card visible on general tab` | General tab              | "Idle sign-out" card  | Missing         | ✅      |
| `preset minutes selectable`                 | Tap 30 min               | Duration updated      | No change       | ✅      |
| `custom minutes entry saves`                | Custom → enter 60 → save | 60 min persisted      | Ignored         | ✅      |
| `custom mode shows text field`              | Select Custom            | Minutes input visible | Dropdown only   | ✅      |
| `invalid custom input rejected`             | `abc`, `0`, `-5`         | Validation message    | Saved bad value | ✅      |
| `stupid usage: custom minutes overflow`     | `999999`                 | Capped or rejected    | Overflow/crash  | ✅      |

### Idle service wiring (`688f152`)

| Test Name                                                       | Scenario           | Pass Criteria                                | Fail Criteria                        | Status          |
| --------------------------------------------------------------- | ------------------ | -------------------------------------------- | ------------------------------------ | --------------- |
| `idle settings load applies persisted duration to idle service` | Store has 90 min   | Service duration 90 min                      | Default 15 min stuck                 | ✅               |
| `saving idle settings updates idle service duration`            | selectPreset 60    | Service + store both 60                      | Desync                               | ✅               |
| `app startup loads idle settings before timer starts`           | Cold start         | Timer uses saved value not hardcoded default | Immediate sign-out at wrong interval | ✅               |
| `idle timeout triggers sign-out`                                | Wait past duration | Session cleared; login shown                 | No sign-out                          | ✅ (integration) |
| `user activity resets idle timer`                               | Mouse move         | Timer restarts                               | Immediate logout                     | ✅               |

---

## 779805f — Staff management settings page

### StaffListPage

| Test Name                                        | Scenario           | Pass Criteria                | Fail Criteria   | Status |
| ------------------------------------------------ | ------------------ | ---------------------------- | --------------- | ------ |
| `shows staff member cards`                       | Loaded list        | Name, role, New staff button | Empty wrongly   | ✅      |
| `staff cards sorted alphabetically by name`      | Multiple staff     | A→Z order                    | Random          | ✅      |
| `single card uses one third grid width`          | 1 staff, wide      | ≈ (grid−gaps)/3              | Full width      | ✅      |
| `shows all staff including inactive`             | includeInactive    | Active + inactive cards      | Filtered out    | ✅      |
| `user without permission sees denial message`    | No manage_staff    | Permission copy              | List visible    | ✅      |
| `empty list shows helpful empty state`           | Zero staff         | Onboarding copy              | Blank           | ✅      |
| `highlights primary branch on card`              | Multi-branch staff | Primary branch label         | All equal       | ✅      |
| `active card status icon only no inline actions` | Active card        | check icon; no Edit on card  | Actions on card | ✅      |
| `inactive card shows inactive icon only`         | Inactive card      | pause icon                   | Delete on card  | ✅      |
| `embedded mode omits scaffold app bar`           | Settings tab embed | No AppBar                    | Duplicate bars  | ✅      |
| `new staff opens blurred create modal`           | Tap New staff      | Modal + Create staff account | Inline form     | ✅      |
| `tapping card opens detail sheet`                | Tap Dr. Smith      | Login credentials section    | No sheet        | ✅      |

### Search & filters

| Test Name                                            | Scenario                    | Pass Criteria                 | Fail Criteria    | Status |
| ---------------------------------------------------- | --------------------------- | ----------------------------- | ---------------- | ------ |
| `search filters staff by name`                       | Type "Former"               | Only matching card            | All cards        | ✅      |
| `cards stay sorted after clearing search`            | Search → clear              | A→Z restored                  | Wrong order      | ✅      |
| `sort preserved when search cleared during fade-out` | Clear mid-animation         | Order stable                  | Flicker reorder  | ✅      |
| `filter popover opens branch and role controls`      | Tap filter icon             | Branches, Roles, Apply, Clear | Missing controls | ✅      |
| `filter dropdown close dismisses branch menu`        | Open branch menu → Close    | Menu closed                   | Stuck open       | ✅      |
| `apply branch filter restricts list`                 | Filter Main Clinic          | Subset shown                  | Unfiltered       | ✅      |
| `apply role filter restricts list`                   | Filter Doctor               | Doctors only                  | All roles        | ✅      |
| `clear all filters resets to full list`              | Filters applied → Clear All | All staff back                | Stale filter     | ✅      |
| `stupid usage: search special characters`            | `%`, `_`, emoji             | No crash; sensible match      | Exception        | ✅      |
| `animated filter cards grid fade`                    | Toggle filter               | Smooth fade; no layout jump   | Overflow         | ✅      |

### CreateStaffModal

| Test Name                                           | Scenario             | Pass Criteria                      | Fail Criteria  | Status |
| --------------------------------------------------- | -------------------- | ---------------------------------- | -------------- | ------ |
| `modal shows staff create form fields`              | Open modal           | Username, password, role, branches | Missing fields | ✅      |
| `create without branch selection shows snackbar`    | No branch selected   | Snackbar message                   | RPC called     | ✅      |
| `close button dismisses modal`                      | Tap Close            | Modal dismissed                    | Stuck open     | ✅      |
| `createStaffAccount calls RPC and stores result`    | Valid input (unit)   | RPC + result stored                | No RPC         | ✅      |
| `successful create closes modal and refreshes list` | Valid submit         | Modal closes; new card             | Stale list     | ✅      |
| `create shows assigned password acknowledgement`    | RPC returns password | Alert with credentials             | Silent success | ✅      |
| `dismiss scrim cancels without create`              | Tap backdrop         | `pop(false)`                       | Staff created  | ✅      |
| `provisioning error shown inline`                   | USERNAME_EXISTS      | Error message                      | Silent fail    | ✅      |
| `doctor cannot open create (permission)`            | Doctor session       | Blocked at route or modal          | Creates staff  | ✅      |

### StaffListQuery (unit)

| Test Name                            | Scenario      | Pass Criteria     | Fail Criteria       | Status |
| ------------------------------------ | ------------- | ----------------- | ------------------- | ------ |
| `matches name case-insensitively`    | Query "smith" | Dr. Smith matches | Case sensitive miss | ✅      |
| `empty query matches all`            | `""`          | Full list         | Empty               | ✅      |
| `combines search with branch filter` | Name + branch | Intersection      | Union wrongly       | ✅      |

### Backend — create_staff_account phone (`20260613150000`)

| Test Name                                      | Scenario       | Pass Criteria                | Fail Criteria | Status |
| ---------------------------------------------- | -------------- | ---------------------------- | ------------- | ------ |
| `create_staff_account accepts optional phone`  | Phone provided | Stored trimmed               | Rejected      | ✅      |
| `create_staff_account empty username rejected` | `''` username  | INVALID_INPUT                | Success       | ✅      |
| `staff_login_usernames view exposes usernames` | After create   | Username queryable for admin | Missing view  | ✅      |

---

## 3fce5d0 — Staff detail right sheet (edit mode)

| Test Name                                         | Scenario                   | Pass Criteria                  | Fail Criteria  | Status |
| ------------------------------------------------- | -------------------------- | ------------------------------ | -------------- | ------ |
| `sheet opens from right at 520px width`           | show()                     | Right AppSheet                 | Center dialog  | ✅      |
| `view mode shows blurred credentials`             | Open sheet                 | Username/password obscured     | Plain text     | ✅      |
| `admin can reveal username`                       | Tap Reveal Username        | Plain username                 | Still obscured | ✅      |
| `non-administrator cannot reveal credentials`     | Doctor + manage_staff      | Denied copy                    | Reveal button  | ✅      |
| `edit icon switches to edit mode`                 | Tap Edit                   | Update button; editable fields | View only      | ✅      |
| `edit prefills username from detail fetch`        | List item missing username | Detail load fills field        | Empty username | ✅      |
| `edit shows password field and visibility toggle` | Edit mode                  | New password field             | Missing        | ✅      |
| `cancel edit restores view mode`                  | Edit → Cancel              | View mode; values reset        | Stuck editing  | ✅      |
| `update saves via update_staff_member RPC`        | Valid edit → Update        | RPC called; sheet refreshes    | No RPC         | ✅      |
| `update with new password calls reset RPC`        | Password changed in edit   | admin_reset_staff_password     | No RPC         | ✅      |
| `reset password button in view mode (admin)`      | Admin view                 | Reset password action          | Missing        | ✅      |
| `sheet closes on Close tooltip`                   | Tap Close                  | Sheet dismissed                | Stuck open     | ✅      |
| `stupid usage: edit while deactivate in flight`   | Parallel actions           | Buttons disabled               | Race/crash     | ✅      |

### Backend — admin_update_staff_username (`20260613200000`)

| Test Name                                | Scenario           | Pass Criteria            | Fail Criteria  | Status |
| ---------------------------------------- | ------------------ | ------------------------ | -------------- | ------ |
| `admin_update_staff_username happy path` | Valid new username | auth.users email updated | Failure        | ✅      |
| `empty username rejected INVALID_INPUT`  | `''`               | Error                    | Success        | ✅      |
| `invalid username format rejected`       | `ab`, `user@host`  | INVALID_INPUT            | Success        | ✅      |
| `USERNAME_EXISTS when taken`             | Duplicate          | Error code               | Overwrite      | ✅      |
| `STAFF_NOT_FOUND for unknown id`         | Random UUID        | Error                    | Success        | ✅      |
| `CROSS_ORG_DENIED for other org staff`   | Foreign staff id   | Error                    | Updated        | ✅      |
| `doctor caller forbidden`                | Doctor JWT         | FORBIDDEN                | Success        | ✅      |
| `normalize_username applied`             | `User_Name`        | Stored normalized        | Raw mixed case | ✅      |

---

## 8430d19 — Staff deactivate, delete, password reset

| Test Name                                                 | Scenario              | Pass Criteria                   | Fail Criteria    | Status      |
| --------------------------------------------------------- | --------------------- | ------------------------------- | ---------------- | ----------- |
| `active staff shows deactivate + delete outline in sheet` | Active member         | Deactivate tooltip; delete icon | Activate shown   | ✅           |
| `inactive staff shows activate + permanent delete`        | Inactive member       | Activate + Delete permanently   | Deactivate       | ✅           |
| `deactivate confirms before RPC`                          | Tap deactivate        | Confirmation dialog             | Immediate RPC    | ✅           |
| `confirm deactivate calls set_staff_active false`         | Confirm               | RPC params correct              | Wrong flag       | ✅           |
| `LAST_ADMINISTRATOR error toast`                          | Sole admin deactivate | Error message                   | Success lockout  | ✅           |
| `delete confirms before RPC`                              | Inactive → delete     | Confirmation dialog             | Immediate delete | ✅           |
| `delete success closes sheet and removes card`            | Confirm delete        | List refresh                    | Stale card       | ✅           |
| `cannot delete active staff from UI`                      | Active member         | Delete hidden or disabled       | Delete offered   | ✅           |
| `reset password confirms and calls RPC`                   | Admin reset           | admin_reset_staff_password      | No RPC           | ✅           |
| `self-deactivation rejected server-side`                  | Deactivate self       | Error from RPC                  | Self deactivated | ✅ (org_ext) |

### Backend — delete_staff_member (`20260613210000`)

| Test Name                               | Scenario        | Pass Criteria                          | Fail Criteria  | Status |
| --------------------------------------- | --------------- | -------------------------------------- | -------------- | ------ |
| `delete inactive staff succeeds`        | is_active false | is_deleted true                        | Failure        | ✅      |
| `delete active staff rejected`          | is_active true  | Error STAFF_STILL_ACTIVE or equivalent | Deleted active | ✅      |
| `delete last administrator rejected`    | Sole admin      | LAST_ADMINISTRATOR                     | Lockout        | ✅      |
| `delete self rejected`                  | Own staff id    | Error                                  | Self deleted   | ✅      |
| `delete idempotent on already deleted`  | Second delete   | STAFF_NOT_FOUND or ALREADY_DELETED     | Double delete  | ✅      |
| `delete requires settings.manage_staff` | Doctor JWT      | FORBIDDEN                              | Success        | ✅      |
| `delete writes audit_log`               | Success         | audit row                              | No audit       | ✅      |

---

## fefef85 — Settings tab transition animation

| Test Name                                             | Scenario               | Pass Criteria                      | Fail Criteria         | Status |
| ----------------------------------------------------- | ---------------------- | ---------------------------------- | --------------------- | ------ |
| `forward tab switch uses positive slide direction`    | General → Clinic Setup | Content slides from right; fade in | Instant swap          | ✅      |
| `backward tab switch uses negative slide direction`   | Staff → General        | Reverse slide direction            | Same as forward       | ✅      |
| `transition duration 220ms easeOut`                   | Tab switch             | AnimatedSwitcher 220ms             | Wrong duration        | ✅      |
| `re-tapping selected tab skips animation`             | Tap active tab         | No AnimatedSwitcher trigger        | Flicker               | ✅      |
| `tab content keyed by tab id`                         | Switch tabs            | State not leaked between tabs      | Staff list on General | ✅      |
| `tab switch uses slide and fade transition`           | Tab switch             | SlideTransition + FadeTransition   | Instant swap          | ✅      |
| `stack layout keeps outgoing child during transition` | Mid-animation          | No blank frame                     | Flash empty           | ✅      |
| `rapid tab switching queues cleanly`                  | Spam tabs              | Final tab content correct          | Exception             | ✅      |

---

## e21f369 — Review fixes

| Test Name                                              | Scenario                 | Pass Criteria                   | Fail Criteria   | Status |
| ------------------------------------------------------ | ------------------------ | ------------------------------- | --------------- | ------ |
| `delete_staff_member guards refined`                   | Migration review         | All delete_staff tests pass     | Regression      | ✅      |
| `auth session idle reload on settings change`          | Change idle preset       | Service updated without restart | Stale timer     | ✅      |
| `create staff modal clears provisioning error on open` | Reopen modal             | No stale error                  | Old error shown | ✅      |
| `password validation aligned frontend/backend`         | `Secret12` no digit      | Accepted both sides             | Mismatch        | ✅      |
| `animated filter grid disposal safe`                   | Close page mid-animation | No dispose error                | FlutterError    | ✅      |

---

## Edge cases & cross-cutting (006)

| Test Name                                                     | Scenario                 | Pass Criteria               | Fail Criteria     | Status |
| ------------------------------------------------------------- | ------------------------ | --------------------------- | ----------------- | ------ |
| `setup_required redirects settings staff routes to bootstrap` | `/settings/staff`        | `/bootstrap`                | Settings renders  | ✅      |
| `legacy /staff/create redirects to settings staff new`        | Old route                | `/settings/staff/new`       | 404               | ✅      |
| `unauthenticated settings routes go to login`                 | No session               | `/login`                    | Settings flash    | ✅      |
| `doctor redirected from settings branches deep link`          | `/settings/branches`     | `/settings` hub             | Branch admin page | ✅      |
| `admin organization legacy route still placeholder`           | `/settings/organization` | Pending migration banner    | Crash             | ✅      |
| `very long staff name truncates gracefully on card`           | 200-char name            | Ellipsis/no overflow        | Layout break      | ✅      |
| `unicode staff and branch names`                              | Arabic names             | Display + save correctly    | Mojibake          | ✅      |
| `concurrent org edit by two admins`                           | Stale save               | Optimistic error or refresh | Silent overwrite  | ✅      |
| `network loss during branch delete`                           | RPC timeout              | Retry message               | Hung dialog       | ✅      |
| `window resize during staff sheet open`                       | Narrow → wide            | Sheet usable                | Overflow          | ✅      |
| `keyboard: Enter submits create branch modal`                 | Focus on field           | Submit or default button    | No action         | ✅      |
| `screen reader: settings tabs announce selection`             | Semantics                | selected state announced    | Missing labels    | ✅      |
| `corner case: zero branches after delete all inactive`        | Edge org                 | Empty state guidance        | Crash             | ✅      |
| `corner case: filter popover open during tab switch`          | Switch tab               | Popover dismissed           | Orphan overlay    | ✅      |

---

## Backend run checklist (settings regression)

After applying migrations `20260613120000` through `20260613210000`:

```bash
for f in org_branch_management_crud org_branch_management_extended org_branch_management_rls \
         create_staff_rpc admin_reset_staff_password delete_staff_member \
         admin_update_staff_username role_permissions_matrix rpc_contract_alignment; do
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f "backend/tests/${f}.sql" || break
done
```

**Backend SQL suites (implemented; require live `DATABASE_URL`):**

| Suite                                           | Covers                          |
| ----------------------------------------------- | ------------------------------- |
| `backend/tests/delete_staff_member.sql`         | delete_staff_member RPC guards  |
| `backend/tests/admin_update_staff_username.sql` | Username change RPC             |
| `backend/tests/role_permissions_matrix.sql`     | Full matrix seed + toggle rules |

---

## Relationship to `ui/005-first-setup`

Branch `ui/006-settings` includes all commits from `ui/005-first-setup`. Setup wizard, owner→administrator, and bootstrap tests are documented in [`ui/tests/setup.md`](setup.md). Shared widgets (`branch_form_fields`, `organization_form_fields`, `staff_form_fields`) should pass both setup and settings widget suites after any change.
