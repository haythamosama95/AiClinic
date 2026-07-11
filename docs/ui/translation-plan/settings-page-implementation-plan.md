# Implementation Plan — Settings page (web-reference → Flutter port)

Spec target: port the **Settings** page at `web-reference/src/pages/app/settings/` into the Flutter `frontend/` feature layer. Scope per request: the **left navigation rail** + the **Setup section** (the setup wizard) are the only fully-implemented regions; the other settings screens (General, Branches, Staff, Services, Notifications) ship as **empty placeholder screens**, but the **cross-screen transition** between every settings tab must work. Split into **2 phases**.

This is a feature-page port (like `login-page-implementation-plan.md`), not a Dev components-showcase group — so there is **no** `component_registry.dart` / `component_section_builders.dart` work. Wiring is in `app/router.dart` + a new feature page tree under `features/settings/presentation/`.

## 0. Ambiguities & Design Decisions (resolve before coding)

> ⚠️ **Set-specific runtime regressions.** This plan touches Material inputs (`TextField`-backed `AppTextInput`/`AppPhoneInput`/`AppPasswordInput`/`AppMoneyField`), `AppSelect`/`AppMultiSelect`/`AppCombobox` popovers, `AppTimePicker` popovers, `AppIconButton`/`InkWell` nav buttons, and an `AnimatedSwitcher`-style panel transition inside a scroll view. The items below are the regressions Composer 2.5 must not reintroduce (consult `docs/ui/memory/ui-runtime-errors.md` only when explicitly instructed).

Set-specific regression watchlist (cite by memory entry number):

- **#1 / #5** — every step form embeds `TextField`-backed inputs inside `AppCard` (`DecoratedBox`) shells and `AnimatedContainer` transitions. `AppTextInput` et al. already wrap with `appWrapMaterialInput` / `appCenterInputField`; do **not** re-shell them in another custom `DecoratedBox` without a `Material` ancestor, and never put a bare `TextField` inside the `StepPanel`/`ScreenPanel` `AnimatedSwitcher` directly.
- **#2 / #10 / #12 / #13** — `AppSelect`/`AppMultiSelect`/`AppCombobox`/`AppTimePicker` open `AppPopover` overlays. The Setup wizard rebuilds on every keystroke (debounced search in combobox, branch add/remove). The popover refresh/detach guards from entries #10/#12/#13 are already in `app_popover.dart`; do not bypass them by mutating overlay state synchronously from `didUpdateWidget` of the wizard.
- **#3** — `AppTimePicker` formats with explicit locale for AR; `ensureIntlDateFormattingInitialized()` must run at app startup (already wired — verify it is still called from `main.dart`).
- **#4** — the wizard step forms use `FocusScope`/`onSubmit` for Enter-to-next. Keep `focusNode` on the `TextField` only; never share a node between an ancestor `Focus` and the field (BranchStep/StaffStep have many fields — use `FocusNode` per field, dispose in `dispose`).
- **#8 / #30** — the Settings page body sits in `AppShell` → `SingleChildScrollView` → `Column`. The left nav + main `Row` must use `CrossAxisAlignment.start` (not `stretch`), and `Expanded`/`mainAxisSize` rules from entry #30 apply: when the shell passes unbounded height during route transition, the page `Column` must use `mainAxisSize: min` + `LayoutBuilder` guard so the outgoing Settings page does not crash while animating away (memory #30 — `fillViewport`/`effectiveFillViewport`).
- **#23** — the left nav buttons and the collapsed-branch expand buttons are `InkWell`/`AppPressable` descendants of `AppCard`/`ShowcaseDemo`-style `DecoratedBox`. Wrap each actionable `InkWell` in `Material(color:.transparent)` (or drive hover with `MouseRegion`+`AnimatedContainer` per #18/#25).
- **#25** — the left settings nav rail item hover must use `Material`+`InkWell(hoverColor:)` (or `MouseRegion` text-color swap), **not** `AnimatedContainer`+`setState` background flash, to match the existing `AppSidebar`/vertical-tabs convention.
- **#11** — do not put `Tooltip`/`MenuAnchor` inside `AppSelect`/`AppMultiSelect` popover children; disabled reasons show inline.

Memory "Checklist for new input components" items 1, 4, 5, 6, 7, 8 apply to every step form field. Items 1, 4 of the shell/placeholder checklist (#28/#30) apply to the page column + transition.

Other decisions:

1. **forui vs native Material** — native Material only; `forui-wrappers.md` is superseded (same as the inputs-forms plan). All controls reuse the shipped `App*` widgets.
2. **File layout** — feature-page tree under `frontend/lib/features/settings/presentation/`:
   - `pages/settings_page.dart` — the route widget (header + nav rail + `ScreenPanel`).
   - `widgets/settings_nav_rail.dart` — the left nav.
   - `widgets/settings_screen_panel.dart` — `AnimatedSwitcher` fade-scale wrapper (web `ScreenPanel`).
   - `screens/` — one file per settings screen: `general_screen.dart`, `setup_screen.dart`, `branches_screen.dart`, `staff_screen.dart`, `services_screen.dart`, `notifications_screen.dart`. Phase 1 ships all six as screens; only `setup_screen.dart` is fully built (Phase 2), the rest are `EmptySettingsScreen` placeholders sharing one helper.
   - `setup/` — the wizard: `setup_wizard.dart`, `setup_step_rail.dart`, `setup_step_panel.dart` (slide-inline `AnimatedSwitcher`), `setup_complete_screen.dart`, `steps/organization_step.dart`, `steps/branch_step.dart`, `steps/staff_step.dart`, `steps/services_step.dart`, `setup_validation.dart`, `widgets/working_hours_editor.dart`, `widgets/maps_location_input.dart`, `widgets/entity_list.dart`, `widgets/collapsed_branch_card.dart`.
   - `providers/clinic_setup_draft_notifier.dart` — page-local Riverpod notifier mirroring web `SetupContext` (draft + `step` + `completed` + `resetSetup`), persisted via `SharedPreferences` (web uses `localStorage`). This is **separate from** `features/setup/presentation/providers/setup_notifier.dart`, which drives the bootstrap RPC installation flow on `/bootstrap` and is out of scope here (see §7). Do not couple them.
3. **Transition technology** — web `AnimatedPanels.tsx` uses `motion`/`AnimatePresence` with `motionPresets['fade-scale']` (screen→screen) and `motionPresets['slide-inline']` (step→step). Flutter already has `AppMotion` (`AppMotionPreset.fade`/`.modal`/`.slideInline`, `animatedPreset`, `resolveDuration`, `prefersReducedMotion`). Build the two panel wrappers as **feature-private** `AnimatedSwitcher`s keyed on `screenKey`/`stepKey`, driven by `AppMotion.animatedPreset`. Do **not** promote to a shared `AppScreenPanel` in `core/ui` yet — premature (only the Settings page uses it); if a second page needs it later, lift then.
4. **Routing** — the Settings page is one shell route (`AppRoutes.settings = '/settings'`) with the active screen as a **path segment**: `/settings`, `/settings/setup`, `/settings/branches`, `/settings/staff`, `/settings/services`, `/settings/notifications`, `/settings/general`. Add these as child `GoRoute`s under the existing shell `GoRoute(path: AppRoutes.settings, …)` in `app/router.dart` (currently a single placeholder route). The `SettingsPage` widget reads `state.pathParameters`/`state.uri.pathSegments` to resolve the active screen (web resolves from `screen` prop). Add the new sub-route constants to `app/app_routes.dart`.
5. **State persistence** — `SharedPreferences` (`shared_preferences` is already a dep — verify in pubspec; if absent, add it). Keys mirror web: `aiclinic:setup-draft`, `aiclinic:setup-complete`. JSON-encode the draft with `dart:convert`.
6. **i18n / RTL** — the nav rail and step headers use `Directionality.of(context)`; the rail flips to a horizontal scroll strip below `lg` (web `lg:flex-row` → Flutter `LayoutBuilder` breakpoint ≥ 1024 px). Copy is **EN-only** for this port (matches the shipped settings/auth features); AR is deferred (§7). `AppPhoneInput`/`AppMoneyField` already force `Directionality.ltr` for the numeric field.
7. **Controlled/uncontrolled** — step form fields use `onChanged` callbacks that patch the draft notifier (controlled), mirroring web's `value`/`onChange`. No internal fallback state needed (the notifier is the single source of truth).
8. **Validation** — port `validation.ts` verbatim into `setup_validation.dart` as pure functions returning `Map<String,String>` keyed identically (`name`, `branch-<i>-name`, `staff-<i>-password`, `_form`, …). The wizard calls `validateStep(step, draft)` on Continue; branch expand/add also calls `validateSingleBranch` (web `BranchStep.validateAndConfirm`).

## 1. Existing App assets to reuse (do not recreate)

| Asset | Path | Used by |
|---|---|---|
| `AppPageHeader` (`title`, `description`) | `core/ui/components/app_page_header.dart` | Settings page header ("Settings" + "Configure your clinic, team, and operational defaults.") |
| `AppButton` (`primary`/`secondary`/`ghost`, `leadingIcon`/`trailingIcon`, `disabled`, `size`) | `core/ui/components/app_button.dart` | wizard Back/Continue, "Add another branch/staff/service", "Run setup again" |
| `AppIconButton` (`ghost`, `sm`/`md`, `icon`, `label`) | `core/ui/components/app_icon_button.dart` | remove branch/service/staff, collapsed-branch expand chevron |
| `AppCard` (`variant: flat/raised/interactive`, `padding: lg`) | `core/ui/components/app_card.dart` | setup complete banner, branch/staff/service forms, notifications placeholder |
| `AppBadge` (`color: success`, `variant: soft`) | `core/ui/components/app_badge.dart` | "Done" badge on the setup-complete banner |
| `AppEmptyState` (`variant: firstRun`, `title`, `description`) | `core/ui/components/app_empty_state.dart` | empty Branches/Staff/Services screens + notifications/future placeholder |
| `AppDescriptionList` | `core/ui/components/app_description_list.dart` | General screen (org name / timezone / currency) |
| `AppProgress` (`variant: bar`, `value`, `showLabel`) | `core/ui/components/app_progress.dart` | wizard header progress bar (`(step+1)/4 * 100`) |
| `AppStepper` (`orientation: vertical`, `steps`, `currentStep`, `onStepChange: null`) | `core/ui/components/app_stepper.dart` | wizard `VerticalStepRail` (rail only; Back/Continue are separate `AppButton`s) |
| `AppFormField` (`label`, `requiredMark`, `error`, `helperText`, `hint`) | `core/ui/components/app_form_field.dart` | every step field |
| `AppTextInput` (`placeholder`, `onChanged`, `invalid`, `id`, uppercase for code) | `core/ui/components/app_text_input.dart` | org/branch/staff/service names, branch code, staff username |
| `AppSelect` (`value`, `onValueChange`, `options`, `invalid`) | `core/ui/components/app_select.dart` | timezone, currency, staff role |
| `AppPhoneInput` | `core/ui/components/app_phone_input.dart` | branch mobile, staff mobile |
| `AppPasswordInput` | `core/ui/components/app_password_input.dart` | staff password |
| `AppMoneyField` (`currency`, `value`, `onValueChange`, `invalid`) | `core/ui/components/app_money_field.dart` | service price |
| `AppMultiSelect` (`value`, `onValueChange`, `options`, `placeholder`, `disabled`) | `core/ui/components/app_multi_select.dart` | staff branch assignments |
| `AppCheckbox` (`checked`, `onChanged`) | `core/ui/components/app_checkbox.dart` | working-days enabled toggle |
| `AppTimePicker` (`size: sm`, `value`, `onValueChange`, `use24Hour`) | `core/ui/components/app_time_picker.dart` | working-hours open/close times |
| `AppMotion` (`AppMotionPreset.fade`/`.slideInline`, `animatedPreset`, `resolveDuration`, `prefersReducedMotion`) | `core/ui/motion/app_motion.dart` | `ScreenPanel` fade-scale, `StepPanel` slide-inline, enter animations |
| Theme: `context.appColors`, `AppSpacing`, `AppRadius`, `AppTypography`, `AppElevation` | `core/ui/theme/*` | every region |
| `AppRoutes.*` + `context.go`/`context.goNamed` (go_router) | `app/app_routes.dart`, `package:go_router` | nav rail navigation between settings screens |
| `AppShell` (shell route builder) | `app/shell/*` | hosts the Settings page; respects `fillViewport`/`effectiveFillViewport` during route transition (memory #30) |
| `shared_preferences` | pubspec | `ClinicSetupDraftNotifier` persistence (verify dep; add if missing) |

## 2. New shared abstractions to introduce

This port introduces **no new `core/ui/components/app_*.dart` primitives** — every control already ships. All new widgets are feature-private under `features/settings/presentation/`. (The skill's default "introduce app_* wrappers" step is intentionally empty here; existing primitives host all content.)

Feature-private composite widgets (each ported 1:1 from its web analog; created in the phase noted):

| File (`frontend/lib/features/settings/presentation/`) | Export name | Web analog | Purpose | Phase |
|---|---|---|---|---|
| `widgets/settings_nav_rail.dart` | `SettingsNavRail` | `SettingsPage.tsx` `<nav>` + `settingsNavItemClass` | vertical icon+label list, horizontal scroll strip below `lg`, active = `surfaceSelected`+icon `teal-600`, aria-current=page | 1 |
| `widgets/settings_screen_panel.dart` | `SettingsScreenPanel` | `components/AnimatedPanels.tsx` `ScreenPanel` | `AnimatedSwitcher` keyed on `screenKey`, `AppMotionPreset.fade`-equivalent fade-scale (opacity 0→1, scale 0.98→1) | 1 |
| `screens/_empty_screen.dart` | `EmptySettingsScreen` | `SummaryListScreen` empty branch / `NotificationsScreen` placeholder | shared icon+title+description+`AppCard`/`AppEmptyState` body for the 5 non-setup screens (they stay empty per scope) | 1 |
| `providers/clinic_setup_draft_notifier.dart` | `clinicSetupDraftProvider` (`ClinicSetupDraftNotifier`) | `SetupContext.tsx` `SetupProvider`/`useSetup`/`isSetupComplete` | Riverpod `StateNotifier` holding `SetupDraft` + `step` + `completed`; persists to `SharedPreferences`; exposes `updateOrganization`/`setBranches`/`setStaff`/`setServices`/`setStep`/`completeSetup`/`resetSetup` | 1 (skeleton) / 2 (full) |
| `setup/setup_wizard.dart` | `SetupWizard` | `setup/SetupWizard.tsx` | header (Sparkles eyebrow + "Step N of 4" + `AppProgress`) + body grid (rail aside + `SetupStepPanel` + content) + Back/Continue footer; blueprint-grid backdrop | 2 |
| `setup/setup_step_rail.dart` | `SetupStepRail` | `SetupWizard.tsx` `VerticalStepRail` | thin wrapper over `AppStepper(orientation: vertical)` rendering the 4 steps with complete/current/upcoming states and animated connector | 2 |
| `setup/setup_step_panel.dart` | `SetupStepPanel` | `AnimatedPanels.tsx` `StepPanel` | `AnimatedSwitcher` keyed on `stepKey`, slide-inline (x: ±24, opacity) driven by `direction` | 2 |
| `setup/setup_complete_screen.dart` | `SetupCompleteScreen` | `SetupWizard.tsx` `SetupComplete` | centered CheckCircle2 + "Clinic is ready" + summary `<dl>` + "Run setup again" `AppButton` | 2 |
| `setup/setup_validation.dart` | `validateOrganization`/`validateBranches`/`validateSingleBranch`/`validateStaff`/`validateServices`/`hasErrors` | `setup/validation.ts` | pure functions returning `Map<String,String>` | 2 |
| `setup/steps/organization_step.dart` | `OrganizationStep` | `steps/OrganizationStep.tsx` | org header + 3 `AppFormField`s (name TextInput, timezone Select, currency Select) | 2 |
| `setup/steps/branch_step.dart` | `BranchStep` | `steps/BranchStep.tsx` | collapsed/expanded branch cards, add/remove, `WorkingHoursEditor`, `MapsLocationInput`, local+merged error map, `validateAndConfirm` | 2 |
| `setup/steps/staff_step.dart` | `StaffStep` | `steps/StaffStep.tsx` | `EntityList` of staff cards: name/mobile/username/password/role/branches | 2 |
| `setup/steps/services_step.dart` | `ServicesStep` | `steps/ServicesStep.tsx` | `AppCard` table-like grid of name TextInput + `AppMoneyField` + remove `AppIconButton`, "Add another service" | 2 |
| `setup/widgets/working_hours_editor.dart` | `WorkingHoursEditor` | `components/WorkingHoursEditor.tsx` `WorkingHoursEditor` | 7-day list w/ `AppCheckbox` + open/close `AppTimePicker(24h)` + per-day time error + "N days open" header | 2 |
| `setup/widgets/maps_location_input.dart` | `MapsLocationInput` | `WorkingHoursEditor.tsx` `MapsLocationInput` | `AppFormField` wrapping a `MapPin`-prefixed URL `TextField` (reuse `AppTextInput` with a leading icon if supported, else a small custom shell — must wrap in `Material` per memory #1) | 2 |
| `setup/widgets/entity_list.dart` | `EntityList<T extends {id}>` | `components/EntityList.tsx` | generic card-per-item list with remove `AppIconButton` (hidden at `minItems`) + add `AppButton(secondary)` | 2 |
| `setup/widgets/collapsed_branch_card.dart` | `CollapsedBranchCard` | `BranchStep.tsx` `CollapsedBranchCard` | pressable row (expand) + remove `AppIconButton`; `Material`+`InkWell` per memory #23 | 2 |

**Barrel update:** none to `widgets.dart` (no new core primitives).

## 3. Phasing

> Rationale: **Phase 1** = the Settings page shell that a user can navigate end-to-end — header, left nav rail, cross-screen fade-scale transition, all six screens routed (Setup is a placeholder pointing at Phase 2; the other five are empty placeholders), and the draft notifier skeleton. **Phase 2** = the Setup wizard itself — rail, step panel transition, 4 step forms, validation, completion screen — wired into the `SetupScreen` from Phase 1. Each phase is independently shippable: after Phase 1 the nav works and every tab lands on its (empty/placeholder) screen; after Phase 2 the Setup tab is fully functional.

### Phase 1 — Settings page shell + nav transitions

Widgets: **SettingsPage, SettingsNavRail, SettingsScreenPanel, EmptySettingsScreen (×5), SetupScreen (placeholder), ClinicSetupDraftNotifier (skeleton)**

| Widget | Flutter widget(s) to create | File(s) | Reuse | Wrapper | Deps |
|---|---|---|---|---|---|
| Settings page | `SettingsPage` (`ConsumerWidget`): resolves active screen from route path; `AppPageHeader(title:'Settings', description:'Configure your clinic, team, and operational defaults.')`; body `LayoutBuilder` → `Row(crossAxisAlignment: start, children: [SettingsNavRail(active:), Expanded(child: SettingsScreenPanel(screenKey:, child: <active screen>))])`, collapses to `Column` below `lg`; `mainAxisSize: min` + scroll guard per memory #28/#30 | CREATE `pages/settings_page.dart` | `AppPageHeader`, `AppSpacing`, `LayoutBuilder`, `AppShell` (via router) | NEW (feature page) | nav rail, screen panel, screens, notifier |
| Nav rail | `SettingsNavRail({required String active, required ValueChanged<String> onNavigate})`: list of 6 `SettingsScreenMeta` mirroring `SETTINGS_SCREENS` (`general/setup/branches/staff/services/notifications`) each with `iconData` (mirroring `SETTINGS_NAV_ICONS`: Building2→`Icons.business`, WandSparkles→`Icons.auto_fix_high`, MapPinned→`Icons.location_on`, Users→`Icons.group`, Stethoscope→`Icons.medical_services`, Bell→`Icons.notifications`), label, id; active item `surfaceSelected`+icon `actionPrimary`, else `textSecondary`+hover `surfaceHover`; `Material`+`InkWell` per memory #23/#25; below `lg` → horizontal `SingleChildScrollView` strip | CREATE `widgets/settings_nav_rail.dart` | `AppSpacing`, `AppRadius`, `AppTypography`, `context.appColors`, `Material`/`InkWell`, `SingleChildScrollView` | NEW | none |
| Screen panel | `SettingsScreenPanel({required String screenKey, required Widget child})`: `AnimatedSwitcher(duration: resolveDuration(AppMotionPreset.fade), switchInCurve/switchOutCurve from animatedPreset, transitionBuilder: (child,anim)=> FadeScaleTransition(..., child))` keyed on `screenKey`; matches web `ScreenPanel` (opacity 0→1, scale 0.98→1) | CREATE `widgets/settings_screen_panel.dart` | `AppMotion`, `AnimatedSwitcher` | NEW | `AppMotion` |
| Empty screen (×5) | `EmptySettingsScreen({required IconData icon, required String title, required String description, String? emptyTitle, String? emptyDescription})`: header row (icon tile + h2 + p) + body (`AppCard(flat, lg)` centered "…will be configurable in a future release." for Notifications; for Branches/Staff/Services an `AppEmptyState(firstRun)` with the web empty copy). Branches/Staff/Services could also read the draft notifier and show the populated `SummaryListScreen`-style list — **but scope says keep them empty**, so they all render the placeholder | CREATE `screens/_empty_screen.dart`; CREATE per-screen files `general_screen.dart`, `branches_screen.dart`, `staff_screen.dart`, `services_screen.dart`, `notifications_screen.dart` (each constructs `EmptySettingsScreen` with the web copy) | `AppCard`, `AppEmptyState`, `AppTypography`, `context.appColors` | NEW (shared helper) | none |
| Setup screen (placeholder) | `SetupScreen` rendering `EmptySettingsScreen(icon: auto_fix_high, title:'Setup', description:'Walk through the essentials … running — organization, branches, staff, and services.')` for Phase 1; Phase 2 replaces its body with `<SetupWizard/>`-equivalent + the setup-complete banner | CREATE `screens/setup_screen.dart` | `EmptySettingsScreen` (P1), `SetupWizard` (P2) | NEW | notifier (P2) |
| Draft notifier (skeleton) | `ClinicSetupDraftNotifier extends StateNotifier<ClinicSetupDraftState>` with `loadDraft()`/`persistDraft()` against `SharedPreferences` (no-op-safe if pref absent), `createDefaultSetup()` ported from `data/settings.ts`. Phase 1 ships the state shape + load/persist only; mutators are added/tested in Phase 2 | CREATE `providers/clinic_setup_draft_notifier.dart` | `StateNotifier`, `shared_preferences`, `dart:convert` | NEW (feature provider) | `shared_preferences` |

Routing + constants changes (Phase 1):

- `app/app_routes.dart` — add `static const settingsSetup = '/settings/setup';`, `settingsGeneral = '/settings/general';`, `settingsNotifications = '/settings/notifications';` (Branches/Staff/Services routes already exist). Add a `settingsScreenSegments` list + a `settingsScreenFromPath(String path)` resolver mirroring web `resolveScreen`.
- `app/router.dart` — replace the single `GoRoute(path: AppRoutes.settings, builder: shellPlaceholderPage)` with a parent `GoRoute(path: AppRoutes.settings, builder: (context,state) => const SettingsPage(), routes: [ GoRoute(path: 'general', …), GoRoute(path: 'setup', …), GoRoute(path: 'branches', …), GoRoute(path: 'staff', …), GoRoute(path: 'services', …), GoRoute(path: 'notifications', …) ])`. The parent builder renders `SettingsPage` which reads the matched child path to resolve the active screen. Import `pages/settings_page.dart`.

### Phase 2 — Setup section (wizard + steps + validation + completion)

Widgets: **SetupWizard, SetupStepRail, SetupStepPanel, SetupCompleteScreen, OrganizationStep, BranchStep (+ CollapsedBranchCard), StaffStep (+ EntityList), ServicesStep, WorkingHoursEditor, MapsLocationInput, SetupValidation, ClinicSetupDraftNotifier (mutators + complete/reset), SetupScreen (final wiring)**

| Widget | Flutter widget(s) to create | File(s) | Reuse | Wrapper | Deps |
|---|---|---|---|---|---|
| Setup wizard | `SetupWizard` (`ConsumerWidget`): reads `clinicSetupDraftProvider`; if `completed` → `SetupCompleteScreen`; else blueprint-grid backdrop `DecoratedBox` (`24px` grid `CustomPaint`/`BoxDecoration` with radial mask) + header (Sparkles→`Icon(Icons.auto_fix_high, size:14, actionPrimary)` eyebrow "Clinic setup", `bodySm` "Step N of 4", `AppProgress(variant: bar, value: (step+1)/4*100, showLabel: true, maxWidth: ~320)`) + body `LayoutBuilder` grid (rail aside ≥ 13rem on `sm+`, else hidden) + `SetupStepPanel(stepKey: '$step', direction:)` + footer (Back `AppButton(secondary, leadingIcon: arrow_back, disabled: step==0)` / Continue `AppButton(primary, trailingIcon: arrow_forward unless last)` label "Continue"/"Finish setup") | CREATE `setup/setup_wizard.dart` | `AppProgress`, `AppButton`, `AppSpacing`, `AppRadius`, `AppElevation`, `AppTypography`, `context.appColors`, `AppMotion` | NEW | step rail, step panel, steps, validation, notifier |
| Step rail | `SetupStepRail({required int currentStep})`: `AppStepper(orientation: vertical, steps: [AppStep(id:'organization',label:'Organization',description:'Name & region'), …branch/staff/services], currentStep:, onStepChange: null)` — the web `VerticalStepRail` connector animation is already in `AppStepper`'s vertical list | CREATE `setup/setup_step_rail.dart` | `AppStepper` | extend (use) | `AppStepper` |
| Step panel | `SetupStepPanel({required String stepKey, required int direction, required Widget child})`: `AnimatedSwitcher` keyed on `stepKey`, slide-inline tween (x: direction≥0?24:-24, opacity 0→1 in; x: direction≥0?-24:24 exit) via `AppMotion.animatedPreset(AppMotionPreset.slideInline)` | CREATE `setup/setup_step_panel.dart` | `AppMotion`, `AnimatedSwitcher`, `Transform`+`Opacity` | NEW | `AppMotion` |
| Complete screen | `SetupCompleteScreen`: centered `AppMotionPreset.modal` enter; `CheckCircle2`→`Icon(Icons.check_circle, size:32, actionPrimary)` in `teal-50` circle; `h1` "Clinic is ready"; `body` summary "<org name> is configured with N branch(es), N staff member(s), and N service(s)."; `<dl>` grid of Timezone/Currency rows (`surfaceMuted` rounded); `AppButton(secondary)` "Run setup again" → `notifier.resetSetup()` | CREATE `setup/setup_complete_screen.dart` | `AppButton`, `AppMotionPreset.modal`, `AppTypography`, `context.appColors`, `AppRadius` | NEW | notifier |
| Validation | pure functions `validateOrganization(OrganizationDraft)→Map<String,String>`, `validateBranches`, `validateSingleBranch(branch,index)`, `validateStaff(staff,branchCount)`, `validateServices`, `hasErrors` — port `validation.ts` verbatim (keys: `name`, `branch-<i>-name`, `branch-<i>-hours`, `branch-<i>-<day>-time`, `staff-<i>-password`, `service-<i>-price`, `_form`, …) | CREATE `setup/setup_validation.dart` | none | NEW | none |
| Organization step | `OrganizationStep({required Map<String,String> errors})`: header tile (`teal-50`/`teal-600` `Icons.business`) + h2 "Your organization" + p; 3 `AppFormField`s (name `AppTextInput(placeholder:'e.g. Nile Dental Group')`, timezone `AppSelect(options: TIMEZONE_OPTIONS)`, currency `AppSelect(options: CURRENCY_OPTIONS, helperText:'Used for invoices, services, and financial reports.')`), all `required` + `invalid`/`error` from `errors` | CREATE `setup/steps/organization_step.dart` | `AppFormField`, `AppTextInput`, `AppSelect`, `context.appColors` | extend | notifier, validation |
| Branch step | `BranchStep({required Map<String,String> parentErrors})`: header (`violet-50`/`violet-600` `Icons.location_on`) + h2 "Branches"; `AnimatePresence`-equivalent → `Column` of `CollapsedBranchCard` for confirmed non-active branches + the active `BranchForm` inside an `AnimatedSwitcher`/`TweenAnimationBuilder`; "Add another branch" `AppButton(secondary, leadingIcon: add)`; manages `activeBranchId`, `confirmedIds`, `localErrors`, merged errors; `validateAndConfirm` on add/expand; `updateBranch`/`removeBranch` patch the notifier | CREATE `setup/steps/branch_step.dart`; CREATE `setup/widgets/collapsed_branch_card.dart` | `AppCard`, `AppFormField`, `AppTextInput` (uppercase code), `AppPhoneInput`, `MapsLocationInput`, `WorkingHoursEditor`, `AppIconButton`, `AppButton`, `AppMotion` | NEW | working hours editor, maps input, notifier, validation |
| Branch form (inline in `branch_step.dart`) | `BranchForm`: `AppCard(flat, lg)` "Branch N"; grid of name + uppercase code; mobile `AppPhoneInput`; `MapsLocationInput`; hours error `<p>`; `WorkingHoursEditor` | same file | as above | NEW (private) | working hours editor, maps input |
| Collapsed branch card | `CollapsedBranchCard`: `Material`+`InkWell` pressable row (MapPin tile, name/"Branch N", secondary `code · mobile · N open days`, trailing `Icons.chevron_right`) + remove `AppIconButton(ghost, md)` when `canRemove`; `AnimatedSwitcher` enter/exit (y:-8, opacity) | CREATE `setup/widgets/collapsed_branch_card.dart` | `AppIconButton`, `AppMotion`, `Material`/`InkWell` (memory #23) | NEW | none |
| Working hours editor | `WorkingHoursEditor({required List<WorkingDay> value, required ValueChanged<List<WorkingDay>> onChange, Map<String,String>? errors})`: header row "Working days & hours" + "N days open" (tabular); `AppCard`-like bordered list of 7 rows (`DAYS_OF_WEEK`), each row: `AppCheckbox(enabled)` + label (muted when disabled) + when enabled: two `AppTimePicker(size: sm, use24Hour: true, width: ~112)` with "to" between; when disabled: "Closed"; per-day time error `<p>` | CREATE `setup/widgets/working_hours_editor.dart` | `AppCheckbox`, `AppTimePicker`, `AppTypography`, `context.appColors`, `AppRadius` | NEW | `AppTimePicker`, `AppCheckbox` |
| Maps location input | `MapsLocationInput({required String id, required String value, required ValueChanged<String> onChange, bool invalid})`: `AppFormField(label:'Google Maps location', requiredMark: true, hint:'Paste a Google Maps link …', helperText:'Patients use this to find your branch on the map.')` wrapping a `MapPin`-prefixed URL field. Prefer `AppTextInput` with a leading icon slot if available; otherwise a small `Material`+`TextField(decoration with prefixIcon: Icons.location_on)` per memory #1 | CREATE `setup/widgets/maps_location_input.dart` | `AppFormField`, `AppTextInput` or `TextField`+`Material` | NEW | `AppFormField` |
| Staff step | `StaffStep({required Map<String,String> errors})`: header (`teal-50`/`teal-700` `Icons.group`) + h2 "Staff"; `_form` error `<p>`; `EntityList<StaffDraft>` with each card: grid name+mobile, grid username+password, grid role(`AppSelect(STAFF_ROLE_OPTIONS)`)+branches(`AppMultiSelect(branchOptions, disabled: branchOptions empty, placeholder:'Select branches')`); add "Add another staff member" | CREATE `setup/steps/staff_step.dart`; CREATE `setup/widgets/entity_list.dart` | `AppFormField`, `AppTextInput`, `AppPhoneInput`, `AppPasswordInput`, `AppSelect`, `AppMultiSelect`, `EntityList`, `AppIconButton`, `AppButton` | NEW | entity list, notifier, validation |
| Entity list | `EntityList<T extends HasId>({required List<T> items, required VoidCallback onAdd, required ValueChanged<String> onRemove, required String addLabel, int minItems=1, required IndexedWidgetBuilder renderItem, ItemLabeler? getItemLabel})`: `Column` of `AppCard(flat, lg)` (header label + remove `AppIconButton(ghost, sm)` when `items.length>minItems`) + add `AppButton(secondary, leadingIcon: add)` | CREATE `setup/widgets/entity_list.dart` | `AppCard`, `AppIconButton`, `AppButton` | NEW | none |
| Services step | `ServicesStep`: header (`violet` `Icons.medical_services`) + h2 "Service catalog"; `_form` error; `AppCard(flat, lg)` with hidden header row (name/price/actions) on `sm+`; `Column` of `<li>`-rows: name `AppFormField`+`AppTextInput(placeholder:'e.g. Dental cleaning')`, price `AppFormField`+`AppMoneyField(currency: draft.organization.currency)` with sr-only labels on `sm+`, remove `AppIconButton(ghost, sm)` when >1 else spacer; "Add another service" `AppButton(ghost, leadingIcon: add)` | CREATE `setup/steps/services_step.dart` | `AppCard`, `AppFormField`, `AppTextInput`, `AppMoneyField`, `AppIconButton`, `AppButton` | NEW | notifier, validation |
| Draft notifier (mutators) | add `setStep`, `updateOrganization(patch)`, `setBranches`, `setStaff`, `setServices`, `completeSetup()` (set `completed` + persist `aiclinic:setup-complete`), `resetSetup()` (re-default + clear complete flag). Expose `isSetupComplete` as a selector. | MOD `providers/clinic_setup_draft_notifier.dart` | `StateNotifier`, `shared_preferences` | extend | — |
| Setup screen (final) | replace Phase-1 placeholder body with: header (h2 "Setup" + p) + setup-complete banner (`AppCard(raised, lg)` teal-bordered with `Icons.auto_fix_high` tile + "Setup complete" + "Done" `AppBadge(success, soft)`) when `isSetupComplete` + `SetupWizard` | MOD `screens/setup_screen.dart` | `AppCard`, `AppBadge`, `SetupWizard`, notifier | extend | wizard, notifier |

Domain value objects (port from `web-reference/src/data/settings.ts`): `OrganizationDraft`, `BranchDraft`, `StaffDraft`, `ServiceDraft`, `WorkingDay`, `SetupDraft`, `SettingsScreenMeta`, and constants `TIMEZONE_OPTIONS`, `CURRENCY_OPTIONS`, `STAFF_ROLE_OPTIONS`, `DAYS_OF_WEEK`, `SETTINGS_SCREENS`, and factories `createDefaultWorkingDays`, `createEmptyBranch`, `createEmptyStaff`, `createEmptyService`, `createDefaultSetup`. Put these under `features/settings/presentation/setup/setup_draft_models.dart` (or extend the existing `models/` dir; keep them distinct from the bootstrap domain to avoid coupling — see §7). IDs: web uses `crypto.randomUUID()`; Flutter uses `DateTime.now().microsecondsSincePeriod`-based or the `uuid` package if already a dep — verify pubspec; else a monotonic counter.

## 4. Page instantiation spec (mirrors web reference)

> **Binding source of truth:** `web-reference/src/pages/app/settings/SettingsPage.tsx`, `screens/SettingsScreens.tsx`, `setup/SetupWizard.tsx`, and `setup/steps/*.tsx` are the binding sources to reproduce **screen-for-screen** and **step-for-step**. The Flutter port renders the same regions, in the same order, with the same copy, the same iconography, and the same motion presets. Composer 2.5 must open each referenced `.tsx` and reproduce its layout/props verbatim; only the widget names and prop syntax change (e.g. `onValueChange` → `onChanged`/`onValueChange`, `invalid` stays `invalid`, `disabled` stays `disabled`).

### Settings page (`SettingsPage.tsx`)

- `AppPageHeader(title: 'Settings', description: 'Configure your clinic, team, and operational defaults.')`.
- Body `LayoutBuilder`: ≥ 1024 px (`lg`) → `Row(crossAxisAlignment: start, children: [SizedBox(width: 224, child: SettingsNavRail(...)), Expanded(child: main)])`; < 1024 → `Column(children: [SettingsNavRail (horizontal strip), main])`. Gap `AppSpacing.space8`/`space12` (web `gap-8`/`gap-12`).
- `main = SettingsScreenPanel(screenKey: <active id>, child: <active screen widget>)`.
- Trailing `Semantics(liveRegion: true, label: 'Viewing <label> settings')` equivalent (web `sr-only` `aria-live`).

### Nav rail (`SettingsPage.tsx` `<nav>` + `settingsNavItemClass`)

- 6 buttons in order: General, Setup, Branches, Staff, Services, Notifications (web `SETTINGS_SCREENS` order; note web renders General first, Setup second — preserve).
- Each button: icon (18, strokeWidth 1.5) + label; active → `surfaceSelected` background, `textPrimary`, medium weight, icon `actionPrimary`; else `textSecondary`, hover `surfaceHover`+`textPrimary`, icon `iconMuted`. `aria-current: page` when active → `Semantics(selected: active)`.
- On tap → `onNavigate('settings/<id>')` → `context.go(AppRoutes.settings + '/<id>')` (or named route).

### Setup screen header (`SettingsScreens.tsx` `SetupScreen`)

- `h2` font-display "Setup" + `body` "Walk through the essentials to get your clinic running — organization, branches, staff, and services."
- Setup-complete banner (when `isSetupComplete`): `AppCard(variant: raised, padding: lg)` `teal-200` border + `teal-50@30%` fill; `Row` between left (tile `teal-100`/`teal-700` `Icons.auto_fix_high` 18 + "Setup complete" `bodyStrong` + "Your clinic configuration is in place. Re-run the wizard to change defaults." `bodySm secondary`) and right (`AppBadge(color: success, variant: soft, label: 'Done')`).
- `SetupWizard()`.

### Setup wizard (`SetupWizard.tsx`)

- If `completed` → `SetupCompleteScreen`.
- Container: `AppRadius.x2l` `borderSubtle` `surfaceDefault` `shadow-elevation-1`; non-interactive blueprint grid backdrop (24px grid lines `borderSubtle` @ 35% opacity, radial mask ellipse 80%×60%@50%,0%). Composer: implement with a `CustomPaint`/`BoxDecoration` layer + `ShaderMask`/radial gradient mask; `IgnorePointer`.
- Header: eyebrow row `Icons.auto_fix_high(14)` + "Clinic setup" (`caption`, medium, uppercase tracking-wider, `actionPrimary`); `bodySm secondary` "Step {step+1} of 4"; `AppProgress(variant: bar, value: (step+1)/4*100, showLabel: true)` `maxWidth: 320`.
- Body `LayoutBuilder`: ≥ 600 px (`sm`) → `Row(children: [SizedBox(width: ~208, child: SetupStepRail), Expanded(child: body)])`; < 600 → rail hidden, just body. Gap `AppSpacing.space8`/`space12`.
- Body = `SetupStepPanel(stepKey: '$step', direction: direction)` wrapping the active step (`OrganizationStep`/`BranchStep`/`StaffStep`/`ServicesStep`), all receiving `errors`.
- Footer: `Row` between Back (`AppButton(secondary, leadingIcon: Icons.arrow_back, disabled: step==0, label: 'Back')`) and Continue (`AppButton(primary, trailingIcon: isLast? null : Icons.arrow_forward, label: isLast? 'Finish setup' : 'Continue')`), `border-t` top divider + `AppSpacing.space6`.
- Handlers: `goNext` → `validateStep(step, draft)`; if `hasErrors` set `errors` and return; else clear errors, if last → `completeSetup()`, else `direction=1; setStep(step+1)`. `goBack` → clear errors, `direction=-1; setStep(step-1)`.

### Step rail (`SetupWizard.tsx` `VerticalStepRail`)

- 4 steps: `{id:'organization', label:'Organization', description:'Name & region'}`, `{id:'branch', label:'Branch', description:'Locations & hours'}`, `{id:'staff', label:'Staff', description:'Team & access'}`, `{id:'services', label:'Services', description:'Catalog & pricing'}`.
- Use `AppStepper(orientation: vertical, steps: …, currentStep: step, onStepChange: null)`. State per item: `index<current` → complete (filled `actionPrimary` circle + Check), `index==current` → current (ring focus), else upcoming (muted). Connector animates fill for completed predecessors.

### Step panel + complete screen

- `SetupStepPanel` slide-inline as in §3 (x: ±24, opacity), `resolveDuration(AppMotionPreset.slideInline)`.
- `SetupCompleteScreen`: `AppMotionPreset.modal` enter (opacity + scale .96→1, CheckCircle scale 0→1 with 0.1s delay); copy verbatim: "Clinic is ready", "<org name> is configured with N branch(es), N staff member(s), and N service(s).", `<dl>` Timezone/Currency rows, "Run setup again".

### Step forms (mirror each `.tsx` exactly)

- **OrganizationStep** — tile (`teal-50`/`teal-600` `Icons.business` 22) + h2 "Your organization" + p "Set the legal name and regional defaults for your clinic. These apply across every branch." `maxWidth: 576`. Three `AppFormField`s (all `required`): name `AppTextInput(value, onChanged→updateOrganization({name}), placeholder:'e.g. Nile Dental Group', invalid: errors['name']!=null, error: errors['name'])`; timezone `AppSelect(value: organization.timezone, onValueChange→updateOrganization({timezone}), options: TIMEZONE_OPTIONS, invalid, error)`; currency `AppSelect(value: organization.currency, onValueChange→updateOrganization({currency}), options: CURRENCY_OPTIONS, invalid, error, helperText:'Used for invoices, services, and financial reports.')`.
- **BranchStep** — tile (`violet-50`/`violet-600` `Icons.location_on` 22) + h2 "Branches" + p "Add every location where patients are seen. Each branch needs a unique code for scheduling and billing." `_form` error `<p role=alert>`. List: confirmed collapsed branches (sorted by draft order) → `CollapsedBranchCard`; active branch → `AnimatedSwitcher` to `BranchForm`. "Add another branch" `AppButton(secondary, leadingIcon: add)`. `BranchForm` (inside `AppCard(flat, lg)`): header "Branch N"; grid name `AppTextInput(placeholder:'e.g. Zamalek')` + code `AppTextInput(placeholder:'e.g. ZML', uppercase)`; mobile `AppPhoneInput`; `MapsLocationInput`; hours error `<p>`; `WorkingHoursEditor`. Errors keyed `branch-<i>-name/-code/-mobile/-map/-hours/-<day>-time`.
- **StaffStep** — tile (`teal-50`/`teal-700` `Icons.group` 22) + h2 "Staff" + p "Create accounts for your team. Each person needs a role and at least one branch assignment." `_form` error. `EntityList<StaffDraft>` addLabel "Add another staff member", getItemLabel `(s)=> s.name || 'New staff member'`. Each card: grid name `AppTextInput(placeholder:'e.g. Dr. Sara Hassan')` + mobile `AppPhoneInput`; grid username `AppTextInput(placeholder:'e.g. sara.hassan')` + password `AppPasswordInput`; grid role `AppSelect(STAFF_ROLE_OPTIONS)` + branches `AppMultiSelect(options: branchOptions, placeholder:'Select branches', disabled: branchOptions.length==0)`. Errors keyed `staff-<i>-name/-mobile/-username/-password/-role/-branches`.
- **ServicesStep** — tile (`violet` `Icons.medical_services` 22) + h2 "Service catalog" + p "Define the procedures and treatments you bill for. You can add more services and branch-specific pricing later." `_form` error. `AppCard(flat, lg)` with `sm+` hidden header row (name/price/actions). Per service `<li>`-row: `AppFormField`+`AppTextInput(placeholder:'e.g. Dental cleaning')` (sr-only label on `sm+`), `AppFormField`+`AppMoneyField(currency: draft.organization.currency)` (sr-only label on `sm+`), remove `AppIconButton(ghost, sm, Icons.delete)` when >1 else spacer. "Add another service" `AppButton(ghost, leadingIcon: add)`. Errors keyed `service-<i>-name/-price`.

### Working hours editor + maps input (mirror `WorkingHoursEditor.tsx`)

- `WorkingHoursEditor`: header "Working days & hours" + "N day(s) open" (tabular); bordered list over `DAYS_OF_WEEK` (mon…sun). Each row: `AppCheckbox(checked: day.enabled, onChanged→updateDay enabled)` + label (medium when enabled, muted when disabled, min width 7rem). When enabled: `AppTimePicker(size:sm, use24Hour, value: day.openTime, aria-label '<day> opening time')` + "to" + closing `AppTimePicker`; when disabled: "Closed" (end-aligned). Per-day time error `<p role=alert>` (`<dayId>-time`).
- `MapsLocationInput`: `AppFormField(label:'Google Maps location', requiredMark: true, hint:'Paste a Google Maps link or search for your clinic address', helperText:'Patients use this to find your branch on the map.')` wrapping a `MapPin`-prefixed URL field, placeholder "https://maps.google.com/… or street address", `invalid` → danger border.

### Empty screens (×5, keep empty per scope)

- `EmptySettingsScreen` header: 40px `surfaceMuted`/`iconDefault` icon tile + h2 + p. Body varies: General → `AppCard(flat, lg)` with `AppDescriptionList` (org name / timezone label / currency label) + caption "Edit these in the Setup wizard or update them here when editing is enabled." (this is a **read-only** mirror of web `GeneralScreen`; it reads the draft notifier, no editing). Branches/Staff/Services → `AppEmptyState(firstRun)` with the web empty title/description (e.g. "No branches yet" / "Complete the Setup wizard to add your first branch."). Notifications → `AppCard(flat, lg, centered)` "Notification preferences will be configurable in a future release."
  - **Note:** the scope says "other settings pages are empty." General's read-only description list is technically populated from the draft, but it has no editing UI (matches web `GeneralScreen`, which is also non-editable). If the reviewer prefers all five to be the literal "future release" placeholder, drop General to the same `EmptySettingsScreen` body as Notifications — flagged in §7.

## 5. Wiring steps

### After Phase 1

1. **`app/app_routes.dart`** — add `settingsSetup`/`settingsGeneral`/`settingsNotifications` constants + `settingsScreenFromPath` resolver + `settingsScreenSegments` list.
2. **`app/router.dart`** — replace the single `GoRoute(path: AppRoutes.settings, builder: shellPlaceholderPage)` with a parent route (builder → `SettingsPage()`) whose `routes:` are the 6 child `GoRoute(path: '<segment>')` (Branches/Staff/Services reuse existing constants as child segments — adjust the existing standalone `/settings/branches` etc. routes to be children of the new parent, or keep them as siblings that also resolve to the same `SettingsPage`; pick the simpler nested form and update `AppRoutes.allSettingsAdminPaths` accordingly). Import `features/settings/presentation/pages/settings_page.dart`.
3. **`widgets.dart`** — no change (no new core primitives).
4. **`pubspec.yaml`** — verify `shared_preferences` is present; add it if missing.
5. **`flutter analyze`** on the new/changed files; fix lints. **Do not commit unless asked.**
6. **Smoke test:** navigate `/settings` → lands on General (default); tap each nav item → URL updates to `/settings/<id>`, screen swaps with fade-scale, active item highlighted; below `lg` the rail is a horizontal scroll strip; reduced-motion disables the fade-scale.

### After Phase 2

1. **`pages/settings_page.dart`** — no change (Setup screen already routed in Phase 1).
2. **`screens/setup_screen.dart`** — swap the Phase-1 placeholder body for the final header + setup-complete banner + `SetupWizard`.
3. **`widgets.dart`** — no change.
4. **`flutter analyze`** on the new setup files; fix lints. **Do not commit unless asked.**
5. **Smoke test:** open `/settings/setup` → wizard renders with step 1; fill org → Continue (validates) → step 2; add/remove branches, toggle working days, set open/close times; step 3 add staff with role + branches; step 4 add services with prices; Finish setup → `SetupCompleteScreen`; "Run setup again" resets to step 1 with blank draft (persisted across restart via SharedPreferences). Invalid fields show error text + danger border; Back/Continue slide-inline transition direction follows nav; reduced-motion disables slide.

## 6. Out-of-scope / defer

- **Editing on General/Branches/Staff/Services screens** — scope explicitly keeps them empty; the read-only General description list is the only populated one (see §4 note). Editing UI for those tabs is a later milestone.
- **`features/setup/.../setup_notifier.dart` (bootstrap RPC flow)** — that notifier drives the `/bootstrap` installation wizard against the backend (create organization/branch/staff via RPC, provisioning rules, `finishBootstrapSetup`). It is **not** the in-page Settings Setup wizard. Coupling the in-page wizard to it is out of scope; the in-page wizard uses a separate page-local draft notifier + `SharedPreferences` to mirror the web `SetupContext` exactly. A future milestone may reconcile them (persist the in-page draft to the backend).
- **AR localization** — EN-only copy for this port (matches shipped auth/settings features). Add AR strings when the settings l10n story lands.
- **Promoting `SettingsScreenPanel`/`SetupStepPanel` to `core/ui`** — kept feature-private; lift to a shared `AppScreenPanel` only when a second page needs the same primitive.
- **Blueprint-grid backdrop fidelity** — a pragmatic `CustomPaint`/`BoxDecoration` approximation of the 24px grid + radial mask is acceptable; pixel-perfect mask matching web's `maskImage: radial-gradient(ellipse 80% 60% at 50% 0%, black 20%, transparent 70%)` is not required.
- **working-schedule ↔ existing `branch_working_schedule.dart` domain** — the in-page `WorkingDay` draft model is intentionally separate from the bootstrap `BranchWorkingSchedule` domain to avoid coupling (see above). Reconciling them is a later milestone.
- **`uuid` dependency** — if no `uuid` package is present, generate draft entity IDs from a monotonic counter / `DateTime.now().microsecondsSinceEpoch`; do not add a dep just for showcase IDs.

## 7. Source reference — web inventory

The Settings page is a composite screen tree (not a registry group); the inventory is per-screen / per-region.

| id / export | title | web source file | underlying UI components |
|---|---|---|---|
| `SettingsPage` | Settings (page shell) | `pages/app/settings/SettingsPage.tsx` | `PageHeader`, `ScreenPanel`, `settingsNavItemClass`, `SETTINGS_SCREENS`, `SETTINGS_NAV_ICONS` |
| `SettingsNavRail` | Settings nav (left) | `SettingsPage.tsx` `<nav>` + `settingsNavItemClass` | `cn`, lucide icons (`Building2`, `WandSparkles`, `MapPinned`, `Users`, `Stethoscope`, `Bell`) |
| `SettingsScreenPanel` | cross-screen transition | `components/AnimatedPanels.tsx` `ScreenPanel` | `motion`/`AnimatePresence`, `motionPresets['fade-scale']`, `resolveTransition` |
| `GeneralScreen` | General | `screens/SettingsScreens.tsx` `GeneralScreen` | `Card`, `DescriptionList`, `useSetup`, `TIMEZONE_OPTIONS`, `CURRENCY_OPTIONS` |
| `SetupScreen` | Setup | `SettingsScreens.tsx` `SetupScreen` | `Card`, `Badge`, `isSetupComplete`, `SetupWizard`, `WandSparkles` |
| `BranchesScreen` | Branches (empty) | `SettingsScreens.tsx` `BranchesScreen` → `SummaryListScreen` | `EmptyState`, `motion` item stagger |
| `StaffScreen` | Staff (empty) | `SettingsScreens.tsx` `StaffScreen` → `SummaryListScreen` | `EmptyState` |
| `ServicesScreen` | Services (empty) | `SettingsScreens.tsx` `ServicesScreen` → `SummaryListScreen` | `EmptyState`, `Intl.NumberFormat` currency |
| `NotificationsScreen` | Notifications (empty) | `SettingsScreens.tsx` `NotificationsScreen` | `Card`, `Bell` |
| `SetupContext` | draft state | `SetupContext.tsx` (`SetupProvider`/`useSetup`/`isSetupComplete`) | `createDefaultSetup`, `localStorage` (`aiclinic:setup-draft`, `aiclinic:setup-complete`) |
| `SetupWizard` | wizard shell | `setup/SetupWizard.tsx` | `Button`, `Progress`, `StepPanel`, `VerticalStepRail`, `resolveTransition`, `validation.ts` |
| `VerticalStepRail` | step rail | `SetupWizard.tsx` `VerticalStepRail` | `motion`, `CheckCircle2`, `Step` type (`components/navigation/Stepper`) |
| `StepPanel` | step transition | `components/AnimatedPanels.tsx` `StepPanel` | `motion`/`AnimatePresence`, `motionPresets['slide-inline']` |
| `SetupComplete` | completion screen | `SetupWizard.tsx` `SetupComplete` | `motion`, `CheckCircle2`, `Button`, draft summary `<dl>` |
| `OrganizationStep` | step 1 | `setup/steps/OrganizationStep.tsx` | `FormField`, `TextInput`, `Select`, `Building2`, `CURRENCY_OPTIONS`/`TIMEZONE_OPTIONS` |
| `BranchStep` | step 2 | `setup/steps/BranchStep.tsx` | `Button`, `IconButton`, `Card`, `FormField`, `TextInput`, `PhoneInput`, `MapsLocationInput`, `WorkingHoursEditor`, `createEmptyBranch`, `validateSingleBranch`, `motion` |
| `CollapsedBranchCard` | collapsed branch | `BranchStep.tsx` | `motion`, `IconButton`, `MapPin`, `ChevronRight` |
| `WorkingHoursEditor` | working days/hours | `components/WorkingHoursEditor.tsx` | `Checkbox`, `TimePicker`, `FormField`, `DAYS_OF_WEEK`, `cn` |
| `MapsLocationInput` | maps link field | `WorkingHoursEditor.tsx` | `FormField`,`MapPin`, native `<input type=url>` |
| `StaffStep` | step 3 | `setup/steps/StaffStep.tsx` | `EntityList`, `FormField`, `TextInput`, `PhoneInput`, `PasswordInput`, `Select`, `MultiSelect`, `STAFF_ROLE_OPTIONS`, `createEmptyStaff` |
| `EntityList` | generic entity list | `components/EntityList.tsx` | `Button`, `IconButton`, `Card`, `cn` |
| `ServicesStep` | step 4 | `setup/steps/ServicesStep.tsx` | `Button`, `IconButton`, `Card`, `FormField`, `MoneyField`, `TextInput`, `createEmptyService` |
| `validation.ts` | step validation | `setup/validation.ts` | pure functions (`validateOrganization`/`Branches`/`Staff`/`Services`/`hasErrors`) |
| `data/settings.ts` | models + constants | `data/settings.ts` | `TIMEZONE_OPTIONS`, `CURRENCY_OPTIONS`, `STAFF_ROLE_OPTIONS`, `DAYS_OF_WEEK`, draft types, `createDefaultSetup` etc. |

Shared web building blocks and their Flutter equivalents (proposed in §1/§2):

- `cn` → Dart `TextStyle`/`BoxDecoration` merge + `context.appColors`.
- `motion`/`motionPresets`/`resolveTransition` → `AppMotion`/`AppMotionPreset.fade`/`.modal`/`.slideInline` (`core/ui/motion/app_motion.dart`).
- lucide-react icons → Material `Icons.*` (mapping above).
- `Radix`/popover primitives → shipped `AppSelect`/`AppMultiSelect`/`AppCombobox`/`AppTimePicker` (already `AppPopover`-based).
- `localStorage` → `SharedPreferences`.