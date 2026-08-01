# Implementation Plan — Dev → Components → Navigation (Flutter Port)

Spec target: port the **Navigation** group of `web-reference/` into the Flutter `frontend/` App abstraction layer, surfaced in the Dev components page. Divided into **2 implementation phases** per the request (constraint 1 ≤ N ≤ 6 satisfied; no fallback to the default 3 needed).

## 0. Ambiguities & Design Decisions (resolve before coding)

> ⚠️ **Set-specific runtime regressions.** Five widgets in this group risk the regressions catalogued below. Apply the checklist items by number while implementing (consult `docs/ui/memory/ui-runtime-errors.md` only when explicitly instructed):
>
> - **AppMenu / AppContextMenu / AppBranchSwitcher / AppUserMenu** all host content inside `AppPopover` (or an `AppPopover`-equivalent overlay for the context menu). Apply **#2** (no `MediaQuery`/`AppMotion.transitionFor` in `initState` — use static `AppMotion.resolveDuration(AppMotionPreset.fadeScale)`), **#10** (controlled `open:` changes deferred via `addPostFrameCallback` in `didUpdateWidget`), **#12** (`_scheduleOverlayRefresh()` so search-box typing in BranchSwitcher keeps the overlay live), **#13** (guard `_overlayLinkActive` + `box.attached && box.hasSize` before measuring). Follow checklist item **#2** verbatim. Do **not** wrap disabled menu rows in `Tooltip` inside the popover child — show `disabledReason` inline (checklist item **#2** last sentence; memory entry **#11**); put the reason on `Semantics.label` for screen readers.
> - **AppCommandBar** is its own `OverlayEntry` dialog (not `AppPopover`), so it inherits the same `LayerLink`/`CompositedTransformFollower` risks as **#13** (skip the `CompositedTransformFollower` entirely — the panel is viewport-centered, not trigger-anchored, so no follower needed). Its input is a `TextField`-equivalent → it **must** have a `Material` ancestor (memory entry **#1** checklist item #1 — wrap with `appWrapMaterialInput` or `Material(color: transparent)`); do **not** read `MediaQuery` in `initState` (entry **#2**) and do **not** share a `FocusNode` between a `Shortcuts`/`Focus` ancestor and the inner `TextField` (entry **#4** — keep `focusNode` only on the `TextField`, attach `onKeyEvent` to that node).
> - **AppSidebar** uses `Focus` for ArrowUp/Down/Home/End roving. Do **not** put a `FocusNode` on both an ancestor `Focus` and a descendant `IconButton`/`InkWell` (entry **#4**). Use `FocusNode.onKeyEvent` on a single node per nav item, or a single `FocusScope` with `onKeyEvent`. The collapsed-rail `AppTooltip` is **not** inside a popover — entry **#11** does not apply; keep `side: right`.
> - **AppTabs** uses the same roving-tab `Focus` pattern as `AppSegmentedControl` (`app_segmented_control.dart`) which already follows entry **#4** correctly. Mirror its `_handleKeyEvent` on `FocusNode`s kept **only** on each tab button; no ancestor `Focus` sharing the node.
> - **AppPagination** formats the range summary (`start–end of total`) with `intl`. `NumberFormat` with an explicit locale needs the intl locale data initialized; the showcase flips between `en` and `ar`. Use `Intl.withLocale(locale, …)` or fall back to `NumberFormat.decimalPattern()` (no per-locale init needed); do not pull `Intl.defaultLocale` in `initState`. Memory entry **#3** covers the `DateFormat` analogue — NumberFormat is safe by default but verify under the AR preview.
> - **AppStepper** / **AppBreadcrumb** / **AppTopBar**: pure composition over `AppButton`/`AppIconButton`/`AppAvatar`, no overlays, no `TextField`, no date locale — low regression risk. Confirm `AppTopBar` lives under a `Material` ancestor (entry **#1**) since the design-system page composes custom shells.
> - All overlays: schedule open/close/refresh via `addPostFrameCallback` (entries **#10** / **#12** / **#13**) — never synchronously from `didUpdateWidget` or `build`.

1. **forui vs native Material.** Same finding as the Inputs & forms plan: `forui` is declared in `pubspec.yaml` but imported **nowhere**; every shipped App widget is **native Material** (`MenuAnchor`, `Overlay`/`OverlayEntry`, `AppPressable`, `IconButton`, `Slider` restyled, etc.). **Decision: native Material throughout. Treat `docs/ui/forui-wrappers.md` as superseded.** Build new `app_*.dart` widgets flat under `lib/core/ui/components/`, exported through `widgets.dart`.

2. **Dropdown overlays.** Web `Menu`/`BranchSwitcher`/`UserMenu` use Radix `DropdownMenu`. Existing `AppPopover` (`app_popover.dart`) already hosts arbitrary free-form content and is the established primitive for select/combobox/multi-select (it already encodes the memory fixes #2/#10/#12/#13). **Decision: reuse `AppPopover`** for the dropdown menu, BranchSwitcher, and UserMenu (rich items, sections, search box sit inside the popover body). Do **not** use `MenuAnchor` here — its `MenuItemButton`-only surface cannot host sections/search/labels, and nesting it inside `AppPopover` triggers entry **#11**.

3. **Context menu (right-click).** Web `ContextMenu` is a separate Radix right-click surface. Flutter has no built-in right-click widget. **Decision: introduce a thin `AppContextMenu`** built on `Listener` (desktop `onPointerDown` secondary / mobile `onLongPress` to show `kIsWeb`-agnostic overlay) + `AppPopover`'s overlay machinery (`OverlayEntry` + `CompositedTransformFollower` at the tap point with `LayerLink` placed at pointer location, fade-scale via `AppMotionPreset.fadeScale`). This is the **one new shared abstraction** in Navigation beyond per-widget wrappers; justified because no existing primitive hosts right-click and it is a distinct showcase demo. Share the `_AppMenuList` renderer with `AppMenu` (web `renderMenuEntries` / `ContextMenuItemContent`).

4. **`MenuEntry` model.** Web `Menu` takes a tagged union (`MenuItemDef | MenuSection | MenuSeparator`). **Decision: introduce `AppMenuEntry` data classes** (`AppMenuItem`, `AppMenuSection`, `AppMenuSeparator`) consumable by both `AppMenu` (dropdown) and `AppContextMenu`. Hosts `icon`, `shortcut` (`AppKbd`), `checked`, `destructive`, `disabled`/`disabledReason` (disabled-with-reason renders inline per memory entry **#11** — not a `Tooltip` inside the popover). A shared private `_AppMenuList` builder renders entries identically for both surfaces.

5. **Command bar (⌘K).** Web uses a `CommandBarProvider` context + global `createPortal` overlay + `useAiMode`. **Decision: mirror with a Riverpod `commandBarController`** (`NotifierProvider<CommandBarController, CommandBarState>`) exposing `open`/`openCommandBar`/`closeCommandBar`/`toggleCommandBar` + `registerTrigger(GlobalKey?)`, **plus** the `AppCommandBar` widget itself inserted into the root `Overlay` so it renders above everything when `open` is true. Binding ⌘K (and Ctrl-K) is done with a top-level `Shortcuts`/`Actions` (or a `KeyboardListener` at the showcase root) that calls `toggleCommandBar`. The panel is viewport-centered — it does **not** use `CompositedTransformFollower` (avoids entry **#13** follower-on-detached-leader issues). AI entry + `aiMode` reuse `AppSignal(variant: ai, size: hero, thinking: …)` + the `surfaceAi`/`textAi`/`actionAi`/`signalColorAi` semantic tokens. The inner input is a `TextField` and must sit under a `Material` ancestor (entry **#1**); its `FocusNode` carries `onKeyEvent` for arrow/enter/escape, with **no** ancestor `Focus` sharing the node (entry **#4**).

6. **App shell surface (`AppSidebar` / `AppTopBar`).** Web comps reference `AppShell`-style tokens (`--shell-topbar-height`, `--shell-nav-item-height`, expanded/collapsed width, collapse duration). These already exist as `AppShellTokens` (`app_shell_tokens.dart`) — `topBarHeight=56`, `navItemHeight=36`, `sidebarExpandedWidth=248`, `sidebarCollapsedWidth=56`, `collapseDuration=200ms`. **Decision: reuse `AppShellTokens` directly; do not redefine.** The sidebar showcase renders inside a fixed `h-96` (~384px) bordered box per web — mirror with `SizedBox(height: 384)` + border, inside which the `AppSidebar` is `Expanded`/`SizedBox` height-clamped so it has a finite height (avoids the unbounded-height class of entry **#8**).

7. **`AppSignal` active indicator.** Web `Tabs` (underline), `AppSidebar` (vertical bar), and `CommandBar` (hero above the input) all use the `Signal` primitive. `AppSignal` already exists with `variant: standard|ai`, `orientation`, `size: defaultSize|hero`, `thinking`. **Decision: reuse `AppSignal` everywhere**; the tab underline uses `orientation: Axis.horizontal`, sidebar uses `Axis.vertical`, command bar uses `size: AppSignalSize.hero` + `thinking` when `aiEntry && !aiResponse`.

8. **i18n / RTL.** Showcase samples bilingual EN/AR copy via `devPreviewProvider` (`locale`, `direction`). Widgets must stay direction-agnostic via `Directionality.of(context)`. Chevron separators (breadcrumb), arrows (pagination), connector lines (sidebar/stepper), and the command-bar layout all mirror in RTL — web uses `rtl:-scale-x-100` on chevrons; in Flutter, `Icons.chevron_right` auto-mirrors under `Directionality.rtl` via the `Icon`'s `matchTextDirection` (or `Transform.flip` on `TextDirection.rtl` for the Connector). `intl` (already a dep) supplies `NumberFormat` for the pagination range summary; per locale-context note above, prefer `NumberFormat.decimalPattern()` or wrap with `Intl.withLocale`. The command-bar ⌘K kbd hint uses `AppKbd`.

9. **Controlled/uncontrolled.** Mirror web's `value`/`onChange` (Tabs, Stepper `currentStep`, Pagination `page`/`pageSize`, BranchSwitcher `currentBranchId`, Sidebar `activeId`) as Flutter controlled props + `onChanged` callbacks. Demo `useState` → `ConsumerStatefulWidget` local state in the showcase (e.g. `_underline`/`_segmented`/`_vertical` tab indices, `_page`/`_pageSize` for pagination), matching `button_showcase_section.dart`.

10. **Error/invalid.** Navigation widgets do not carry `invalid` semantics in web; `disabled` + `destructive` (Menu) are the closest analogs. **Decision: do not add `error`/`invalid` to nav wrappers** — match web's surface exactly.

## 1. Existing App assets to reuse (do not recreate)

| Asset | Path | Used by |
|---|---|---|
| `AppButton` | `core/ui/components/app_button.dart` | Menu trigger, Stepper Back/Next, CommandBarTrigger button |
| `AppIconButton` | `core/ui/components/app_icon_button.dart` | Sidebar collapse toggle, TopBar notifications/theme, Pagination prev/next |
| `AppSegmentedControl` | `core/ui/components/app_segmented_control.dart` | Tabs `variant: segmented` (delegate, mirrors web `SegmentedControl`) |
| `AppPopover` | `core/ui/components/app_popover.dart` | Menu dropdown, BranchSwitcher, UserMenu (align/start/end, controlled `open`/`onOpenChange`) — already encodes memory fixes #2/#10/#12/#13 |
| `AppTooltip` | `core/ui/components/app_tooltip.dart` | Sidebar collapsed-rail item tooltips (`side: right`); **not** used for disabled-with-reason menu rows (memory #11) |
| `AppAvatar` | `core/ui/components/app_avatar.dart` | UserMenu trigger + CommandBar item avatars (`avatarName`) |
| `AppBadge` | `core/ui/components/app_badge.dart` | Sidebar item counts (neutral/soft/sm); already uses `UnconstrainedBox` (memory #21) |
| `AppKbd` | `core/ui/components/app_kbd.dart` | Menu shortcuts, TopBar ⌘K, CommandBar footer hints |
| `AppSignal` | `core/ui/components/app_signal.dart` | Tabs underline, Sidebar active bar, CommandBar hero (AI thinking) |
| `AppSearchInput` | `core/ui/components/app_search_input.dart` | BranchSwitcher search (>4 branches) + CommandBar input (or a styled `TextField` sharing the input-styles) |
| `AppSelect` | `core/ui/components/app_select.dart` | Pagination page-size select |
| `AppPressable` | `core/ui/components/app_pressable.dart` | custom triggers (sidebar nav buttons, topbar command trigger) |
| Theme: `context.appColors` (`AppSemanticColors`), `AppSpacing`, `AppRadius`, `AppTypography`, `AppMotion`/`AppMotionPreset` | `core/ui/theme/*`, `core/ui/motion/app_motion.dart` | every widget |
| `AppShellTokens` | `core/ui/theme/app_shell_tokens.dart` | AppSidebar widths/heights, AppTopBar height, collapse duration |
| `devPreviewProvider` | `features/design_system/presentation/providers/dev_preview_provider.dart` | locale/direction in showcases; UserMenu/TopBar language toggle writes here |
| Showcase primitives: `ShowcaseSection`, `ShowcaseDemoGrid`, `ShowcaseDemo`, `ShowcaseVariantMatrix`, `PlaceholderSection` | `components/showcase_primitives.dart` | every showcase section |
| Wiring: `component_registry.dart`, `component_section_builders.dart`, `components_content.dart` | `components/` | one-line registration per widget |
| `appWrapMaterialInput` / `appCenterInputField` helpers | `core/ui/components/app_input_styles.dart` | CommandBar input shell (memory #1, checklist #1, #5) |

## 2. New shared abstractions to introduce

| File (`lib/core/ui/components/` or `lib/core/ui/`) | Export name | Web analog | Purpose | Phase |
|---|---|---|---|---|
| `app_nav_models.dart` | `AppNavItem`, `AppNavGroup`, `AppBranch`, `AppUserMenuUser`, `kClinicNavGroups`, `kClinicNavFooter`, `kMockBranches`, `kMockUser`, `kMockOrg`, `kMockNotificationCount` | `nav-model.ts` | shared nav data models + showcase mock constants | P1 |
| `app_menu.dart` | `AppMenuEntry` (sealed), `AppMenuItem`, `AppMenuSection`, `AppMenuSeparator`, `AppMenu`, `AppContextMenu`, shared `_AppMenuList` renderer | `Menu.tsx` (`Menu` + `ContextMenu`) | dropdown menu (uses `AppPopover`) + right-click menu (uses `Listener`+overlay). Shared list renderer (icon/label/shortcut `AppKbd`/`Check` for checked/destructive/disabled-with-inline-reason per memory #11). | P1 |
| `app_breadcrumb.dart` | `AppBreadcrumb` (+ `AppBreadcrumbItem`) | `Breadcrumb.tsx` | hierarchical trail; last item non-link + `Semantics(current: true)`; middle-truncates when `items.length>3` (collapsed middle node with `…`). | P1 |
| `app_tabs.dart` | `AppTabs` (+ `AppTabItem`, `AppTabsVariant { underline, segmented, vertical }`) | `Tabs.tsx` | underline (Signal layout animation via `AnimatedPositioned`/shared `AppSignal`), vertical (stacked), segmented (delegates to `AppSegmentedControl`). Arrow/Home/End roving (mirror `app_segmented_control.dart`'s `_handleKeyEvent` on per-button `FocusNode`s — memory #4 compliant). | P1 |
| `app_stepper.dart` | `AppStepper` (+ `AppStep`, `AppStepperOrientation { horizontal, vertical }`, `AppStepState`) | `Stepper.tsx` | numbered indicators w/ Check on complete, ring on current (`borderFocus`), default on upcoming (`borderDefault`); connector line colored by state (vertical absolute line uses positive offsets per memory #19 pattern); Back/Next via `AppButton`. | P1 |
| `app_pagination.dart` | `AppPagination` | `Pagination.tsx` | `start–end of total` (`NumberFormat.decimalPattern()` / `Intl.withLocale`), page-size `AppSelect` (rows), prev/next `AppIconButton` (chevrons RTL-mirrored via `Icon.matchTextDirection`), `page / totalPages` label, disabled at bounds. | P1 |
| `app_sidebar.dart` | `AppSidebar` (consumes `AppNavGroup`/`AppNavItem`) | `AppSidebar.tsx` | aside using `AppShellTokens`; collapse toggle (`PanelLeftOpen/Close`-equivalent icons); nav groups (label + items); `_AppNavItemButton` with `AppSignal` vertical active indicator + `AppBadge` counts; collapsed-rail `AppTooltip` (`side: right`); arrow-key/Home/End roving via per-item `FocusNode.onKeyEvent` (memory #4 — no shared ancestor `Focus`). | P2 |
| `app_branch_switcher.dart` | `AppBranchSwitcher` (consumes `AppBranch`) | `BranchSwitcher.tsx` | `AppPopover` trigger button (Building icon + name + chevron); content: current-org label + `AppSearchInput` (when `branches.length>4`) + scrollable list w/ Check on selected + "No branches found" empty + transient "Switched to …" status pill auto-hide 2.5s. Overlays inherit memory fixes via `AppPopover`. | P2 |
| `app_user_menu.dart` | `AppUserMenu` (+ `AppUserMenuUser`) | `UserMenu.tsx` | `AppPopover` triggered by `AppAvatar` (sm, status online) hover opacity; label = name/role/email stack; items: Profile, Dark/Light theme toggle, Language (EN/AR swap via `devPreviewProvider`), Sign out (destructive); version footer caption. | P2 |
| `app_command_bar.dart` (core/ui) | `AppCommandBar` (+ `AppCommandItem`, `kDefaultCommandItems`) | `CommandBar.tsx` | `Overlay`-inserted centered dialog (backdrop button + max-w-xl panel — **no `CompositedTransformFollower`**, viewport-centered); input (`TextField` under `Material` per memory #1) with `AppSignal` hero (`ai` variant + `thinking`); grouped results list; arrow/enter/home/end/esc nav on the input's `FocusNode.onKeyEvent` (memory #4); footer kbd hints. | P2 |
| `command_bar_controller.dart` (features/design_system/presentation/providers/) | `commandBarProvider` (`NotifierProvider`) | `CommandBarProvider.tsx` | open state + `registerTrigger(GlobalKey?)` + ⌘K/Ctrl-K binding via a top-level `Shortcuts`/`Actions` inserted by the showcase (or app root). | P2 |
| `app_top_bar.dart` | `AppTopBar` | `AppTopBar.tsx` | header using `AppShellTokens.topBarHeight`; left = `pageContext` slot (breadcrumb); center = command-bar trigger button + `AppKbd` ⌘K (registers trigger with the controller); right = `toolbarSlot` + `AppBranchSwitcher` (md+) + notifications `AppIconButton` + count badge (>9→"9+") + theme toggle `AppIconButton` + `AppUserMenu`. | P2 |

**Barrel update:** append every new `app_*.dart` to `lib/core/ui/widgets/widgets.dart` under a `// Navigation` sub-comment; export `command_bar_controller.dart` from the feature providers barrel alongside `dev_preview_provider.dart` (or from `widgets.dart` if preferred).

## 3. Phasing (2 implementation phases)

> Rationale: **Phase 1** = self-contained wayfinding primitives that the later shell widgets compose (Breadcrumb→TopBar, Menu→UserMenu/BranchSwitcher popover patterns, Tabs/Stepper/Pagination standalone). No process-wide overlay state — only `AppPopover`-based dropdowns which already encode the runtime-error fixes. **Phase 2** = app-shell composition — Sidebar, BranchSwitcher, UserMenu, CommandBar (+Riverpod controller), and the composite TopBar that ties Breadcrumb/BranchSwitcher/UserMenu/CommandBar together. Each phase is independently shippable: after Phase 1 the 5 primitive sections flip to `ready`; after Phase 2 the remaining 5 flip.

### Phase 1 — Primitives & wayfinding

Widgets: **Breadcrumb, Tabs, Menu, Pagination, Stepper**

| Widget | Flutter widget(s) to create | File(s) | Reuse | Wrapper | Deps | Memory risks |
|---|---|---|---|---|---|---|
| Breadcrumb | `AppBreadcrumb` + `AppBreadcrumbItem { label, href?, onTap? }` | CREATE `components/app_breadcrumb.dart`; CREATE `components/app_nav_models.dart` (shared mocks used by P2); MOD `widgets.dart` | chevron `Icon` (`matchTextDirection` for RTL), `Flexible`+`TextOverflow.ellipsis`, `context.appColors`, tappable links via `InkWell`/`GestureDetector` | NEW | none | none |
| Tabs | `AppTabs` (+ `AppTabItem {id,label,disabled?}`, `AppTabsVariant`) | CREATE `components/app_tabs.dart`; MOD `widgets.dart` | `AppSegmentedControl` (segmented variant), `AppSignal` (underline), `AppMotion`/`AppMotionPreset.tab` (animated underline), Arrow/Home/End Focus roving (mirror `AppSegmentedControl._handleKeyEvent` on per-button `FocusNode`s, no shared ancestor `Focus`) | NEW | `AppSegmentedControl`, `AppSignal` | #4 (Focus node sharing) |
| Menu | `AppMenu` + `AppContextMenu` + `AppMenuEntry`-types + shared `_AppMenuList` renderer | CREATE `components/app_menu.dart`; MOD `widgets.dart` | `AppPopover` (dropdown, align; controlled `open`), `AppKbd` (shortcuts), Check icon, `AppButton` (trigger), `AppTooltip`**only outside popover**; destructive styling via `statusDangerFg`/`statusDangerSurface`; context menu = `Listener` (secondary tap / long-press) + `OverlayEntry` + `CompositedTransformFollower` at pointer `LayerLink`, fade-scale via `AppMotionPreset.fadeScale` | NEW | `AppPopover`, `AppKbd`, `AppButton` | #2, #10, #11 (no Tooltip in popover child → inline disabledReason), #13 (guard link active) |
| Pagination | `AppPagination` | CREATE `components/app_pagination.dart`; MOD `widgets.dart` | `AppIconButton` (prev/next, ghost/sm), `AppSelect` (page-size, sm), `Intl.NumberFormat.decimalPattern()` or `Intl.withLocale` (range summary + total), RTL chevron mirror | NEW | `AppIconButton`, `AppSelect`, intl | #3 (locale intl init — verify under AR preview; prefer default-pattern) |
| Stepper | `AppStepper` (+ `AppStep`, `AppStepperOrientation`, `AppStepState`) | CREATE `components/app_stepper.dart`; MOD `widgets.dart` | `AppButton` (Back secondary / Next primary), Check icon, `AppMotion` for connector color tween, `context.appColors` (actionPrimary / borderFocus ring / borderDefault), vertical/horizontal layout via `Flex`; vertical connector uses positive offsets (memory #19 pattern) | NEW | `AppButton` | #19 (vertical rail uses positive offsets + `IntrinsicHeight` if needed) |

Showcase sections (Phase 1), under `features/design_system/presentation/components/navigation/`:
`breadcrumb_showcase_section.dart`, `tabs_showcase_section.dart`, `menu_showcase_section.dart`, `pagination_showcase_section.dart`, `stepper_showcase_section.dart`.

### Phase 2 — App shell composition

Widgets: **App sidebar, Branch switcher, User menu, Command bar, App top bar**

| Widget | Flutter widget(s) | File(s) | Reuse | Wrapper | Deps | Memory risks |
|---|---|---|---|---|---|---|
| App sidebar | `AppSidebar` (consumes `AppNavGroup`/`AppNavItem` from `app_nav_models`) | CREATE `components/app_sidebar.dart`; MOD `widgets.dart` | `AppShellTokens`, `AppIconButton` (collapse toggle), `AppBadge` (counts, neutral/soft/sm), `AppTooltip` (collapsed rail, `side: right` — **not inside popover**), `AppSignal` (vertical active indicator), `AppMotion.nav` for width tween + signal layout, per-item `FocusNode.onKeyEvent` for ArrowUp/Down/Home/End roving (no shared ancestor `Focus`) | NEW | `AppNavModels`, `AppIconButton`, `AppBadge`, `AppTooltip`, `AppSignal` | #4 (Focus sharing), #1 (Material ancestor for the aside content) |
| Branch switcher | `AppBranchSwitcher` (consumes `AppBranch`) | CREATE `components/app_branch_switcher.dart`; MOD `widgets.dart` | `AppPopover` (align end, width 288), `AppSearchInput` (>4 branches), Check on selected, status pill (`role=status`) auto-hide 2.5s, `Icons.apartment` + `Icons.expand_more` | NEW | `AppPopover`, `AppSearchInput`, `AppNavModels` | inherit `AppPopover` fixes (#2/#10/#11/#12/#13) |
| User menu | `AppUserMenu` (+ `AppUserMenuUser`) | CREATE `components/app_user_menu.dart`; MOD `widgets.dart` | `AppPopover` (align end, width 224), `AppAvatar` (sm w/ status online trigger) hover opacity, `Icons.person_outline`/`Icons.dark_mode`/`Icons.light_mode`/`Icons.language`/`Icons.logout`, theme toggle → `ThemeMode` via `devPreviewProvider`/app theme, language toggle → `devPreviewProvider.setLocale`, destructive Sign out (`statusDangerFg`), version footer caption | NEW | `AppPopover`, `AppAvatar`, `AppNavModels` | inherit `AppPopover` fixes |
| Command bar | `AppCommandBar` (+ `AppCommandItem`, `kDefaultCommandItems`) and `commandBarController` | CREATE `core/ui/components/app_command_bar.dart`; CREATE `features/design_system/presentation/providers/command_bar_controller.dart`; MOD `widgets.dart` (+ feature barrel) | `Overlay`/`OverlayEntry` (backdrop + centered max-w-xl panel — **no `CompositedTransformFollower`**), `AppSignal` hero (`ai` variant + `thinking`), `AppAvatar`/icon slots per item, `AppKbd` (⌘K, ↑↓↵Esc), `TextField` under `Material` for input, `AppMotion.command`, `surfaceAi`/`textAi`/`actionAi`/`signalColorAi` tokens, ⌘K binding via `Shortcuts`/`Actions` at showcase root; `aiMode` flag on the controller (or reuse existing AI provider if present) | NEW | `AppSignal`, `AppAvatar`, `AppKbd`, `AppMotion`, semantic colors, `app_input_styles` (`appWrapMaterialInput`) | #1 (Material ancestor for `TextField`), #2 (no `MediaQuery` in `initState`), #4 (`FocusNode` only on `TextField`, no ancestor `Focus` sharing it), #13 (no follower — viewport-centered) |
| App top bar | `AppTopBar` | CREATE `components/app_top_bar.dart`; MOD `widgets.dart` | `AppShellTokens.topBarHeight`, `AppBreadcrumb` (pageContext slot, hidden < sm), `commandBarController` (openCommandBar + registerTrigger), `AppKbd` (⌘K hint), `AppBranchSwitcher` (md+), `AppIconButton` (notifications lg + count badge overlay >9→"9+"; theme toggle lg), `AppUserMenu`; `toolbarSlot` for showcase toggles | NEW | `AppBreadcrumb`, `AppBranchSwitcher`, `AppUserMenu`, `commandBarController`, `AppIconButton`, `AppKbd`, `AppNavModels` | #1 (Material ancestor for the header) |

Showcase sections (Phase 2): `sidebar_showcase_section.dart`, `branch_switcher_showcase_section.dart`, `user_menu_showcase_section.dart`, `command_bar_showcase_section.dart`, `top_bar_showcase_section.dart`.

## 4. Instantiation in the Dev page (mirrors web reference)

> **Binding source of truth:** each Flutter showcase section must reproduce **demo-for-demo** how the corresponding `web-reference/src/showcase/components/navigation/<Name>Showcase.tsx` instantiates the web widget:
> - the number, order, and titles of `ShowcaseDemo` cells;
> - the exact props passed (sizes, variants, `pageSizeOptions`, `orientation`, `entries`, `collapsed`, mock `branches`/`user`/`currentBranchId`, `appVersion`, etc.);
> - any `ShowcaseVariantMatrix` rows below the `ShowcaseDemoGrid`;
> - bilingual EN/AR copy following the existing `_copyEn`/`_copyAr` convention (see `actions/button_showcase_section.dart`).
>
> The Flutter `ShowcaseSection`/`ShowcaseDemoGrid`/`ShowcaseDemo`/`ShowcaseVariantMatrix` primitives are 1:1 in shape with the web ones, so the demo structure ports verbatim — only the control name and prop syntax change (e.g. `onChange` → `onChanged`, `className="w-48"` → `SizedBox(width: 192)`, `currentStep={n}` → `currentStep: n`, `entries={MENU_ENTRIES}` → `entries: kMenuEntries`).

Per widget (web is the binding source; copy EN/AR strings where the web demo uses labels — nav labels are mostly locale-neutral product names, but the command-bar placeholder, "Ask AI…", "No results", "Switched to …", pagination "Rows", Stepper Back/Next, and UserMenu items are bilingual):

- **Breadcrumb** — `ShowcaseDemoGrid(columns: 1)`: (1) "Default trail" — `[Home, Patients, Layla Hassan(current)]`; (2) "Long trail (middle truncates on narrow)" — `[Home, Billing, Invoices, INV-2026-00482(current)]` (4 items → collapse middle with `…`).
- **Tabs** — `ShowcaseDemoGrid(columns: 1)`: (1) "Underline (default)" `variant: underline`, `value/onChange` controlled (`overview`), items `[Overview, Visits, Billing, Documents(disabled: true)]`; (2) "Segmented" `variant: segmented` (filter out disabled), same state; (3) "Vertical" `variant: vertical`, `width: 192` (`w-48`).
- **Menu / Context menu** — `ShowcaseDemoGrid(columns: 2)`: (1) "Dropdown menu" — `AppMenu` with trigger = `AppButton(variant: secondary)` "Open menu / افتح القائمة", entries = section "Patient" (`Edit profile` w/ icon + shortcut `⌘E` via `AppKbd(['⌘','E'])`, `Copy MRN` w/ icon), separator, `Delete record` destructive w/ icon; (2) "Context menu" — `AppContextMenu` wrapping a dashed-border box "Right-click here / انقر بزر الفأرة الأيمن هنا" with the same entries.
- **Pagination** — single `ShowcaseDemo` "Default" `page + pageSize + total=2000`, `onPageChange`/`onPageSizeChange`, `pageSizeOptions=[25,50,100]` (web default), controlled state, `w-full`.
- **Stepper** — `ShowcaseDemoGrid(columns: 1)`: (1) "Horizontal" `orientation: horizontal`, 4 steps (`[patient, visit, billing, review]` w/ labels + descriptions), Back/Next disabled at bounds, `w-full`; (2) "Vertical" `orientation: vertical`, 3 steps, `maxW ~ 24rem` (`SizedBox(width: 384)`).
- **App sidebar** — `ShowcaseDemoGrid(columns: 2)`: (1) "Expanded" `collapsed: false`; (2) "Collapsed rail" `collapsed: true`. Both inside `SizedBox(height: 384)` + border, `items: kClinicNavGroups`, `footerItems: kClinicNavFooter`, `activeId: 'patients'` controlled, `org: kMockOrg`, `branch: kMockBranches[0].name`, `onToggleCollapsed: () {}`.
- **Branch switcher** — single `ShowcaseDemo` "Default" `branches: kMockBranches`, `currentBranchId: 'downtown'` controlled, `onBranchChange`. (3 branches so the search field is **not** shown per web's `branches.length > 4` gate — keep parity.)
- **User menu** — single `ShowcaseDemo` "Default" `user: kMockUser`, `appVersion: '0.1.0'`.
- **Command bar** — single `ShowcaseDemo` "Hero overlay": a trigger `AppButton(variant: secondary)` "Open command bar / افتح شريط الأوامر" calling `ref.read(commandBarProvider.notifier).openCommandBar()`; helper paragraph "Press `⌘K` anywhere in the showcase." with `AppKbd(keys: ['⌘','K'])`. The controller wires ⌘K/Ctrl-K at the showcase root and renders `AppCommandBar` into the root `Overlay` with `kDefaultCommandItems(onNavigate: ...)`.
- **App top bar** — single `ShowcaseDemo` "Default composition" `pageContext: AppBreadcrumb([Patients, Layla Hassan])`, `branches: kMockBranches`, `currentBranchId` controlled, `user: kMockUser`, `notificationCount: kMockNotificationCount(3)`; inside `w-full` bordered rounded box. The topbar registers its trigger `GlobalKey` with `commandBarController`.

## 5. Wiring steps (do after each phase's widgets land)

1. `component_registry.dart` — for each finished `id`, flip `status: ShowcaseSectionStatus.placeholder` → `ShowcaseSectionStatus.ready` (reuse exact `id` strings: `breadcrumb`, `tabs`, `menu`, `pagination`, `stepper` for P1; `app-sidebar`, `branch-switcher`, `user-menu`, `command-bar`, `app-topbar` for P2). Order already present (lines 330–390).
2. `component_section_builders.dart` — add an entry per ready id under a `// Navigation` comment:
   `'breadcrumb': () => const BreadcrumbShowcaseSection(),` … `'app-topbar': () => const AppTopBarShowcaseSection(),`.
3. Import the new section files at the top of `component_section_builders.dart`, grouped under `// Navigation` (mirrors existing Actions/Data display blocks).
4. Append new `app_*.dart` core files to `widgets.dart` barrel export list under a `// Navigation` sub-comment. Export `command_bar_controller.dart` (either from `widgets.dart` or from the feature providers barrel alongside `dev_preview_provider.dart`).
5. Mount `AppCommandBar` at the showcase root inside a `Shortcuts`/`Actions` (⌘K/Ctrl-K → `toggleCommandBar`) and within a root `Overlay` so the dialog renders above all sections at the P2 boundary.
6. Run `flutter analyze` (project uses `flutter_lints`) on changed files; fix lints. Do **not** commit unless asked.

## 6. Out-of-scope / defer

- The `forui`-based wrappers described in `docs/ui/forui-wrappers.md` are not built or reconciled.
- Real router/navigation wiring (GoRouter routes, deep-link breadcrumbs) — the showcase uses `onNavigate`/`onTap` no-ops and `href='#'`; production route integration is a later app-shell milestone.
- Theme/language toggle persistence — UserMenu/TopBar toggles write to `devPreviewProvider` (showcase-only); real app theme management is owned by the future App shell milestone.
- AI surfaced by `AppCommandBar`'s "Ask AI…" entry is mocked ("Thinking…" + canned response) exactly like web; the real AI provider integration belongs to the AI group milestone.
- Touch-rendered context menu (`onLongPress`) is wired for parity, but the showcase targets desktop right-click per the web demo ("Right-click here").
- Sidebar nested children / multi-level nav (web has none) — none added.
- Syncfusion/other calendar primitives — not needed for Navigation.

## 7. Source reference — web widget inventory

The 10 widgets in `web-reference/src/showcase/components/navigation/index.ts`:

| id | Title | Showcase file | Underlying UI component |
|---|---|---|---|
| `breadcrumb` | Breadcrumb | `BreadcrumbShowcase.tsx` | `components/navigation/Breadcrumb.tsx` |
| `tabs` | Tabs | `TabsShowcase.tsx` | `components/navigation/Tabs.tsx` (delegates to `components/actions/SegmentedControl`) |
| `menu` | Menu / Context menu | `MenuShowcase.tsx` | `components/navigation/Menu.tsx` (`Menu` + `ContextMenu`) → Radix `ContextMenu` + `components/ui/DropdownMenu` |
| `pagination` | Pagination | `PaginationShowcase.tsx` | `components/navigation/Pagination.tsx` → `IconButton`, `components/ui/select/Select` |
| `stepper` | Stepper | `StepperShowcase.tsx` | `components/navigation/Stepper.tsx` → `Button` |
| `app-sidebar` | App sidebar | `SidebarShowcase.tsx` | `components/navigation/AppSidebar.tsx` → `IconButton`, `Badge`, `Tooltip`, `Signal`, `nav-model` |
| `app-topbar` | App top bar | `TopBarShowcase.tsx` | `components/navigation/AppTopBar.tsx` → `Breadcrumb`, `BranchSwitcher`, `UserMenu`, `IconButton`, `Kbd`, `CommandBarProvider`, `ThemeProvider` |
| `command-bar` | Command bar | `CommandBarShowcase.tsx` | `components/navigation/CommandBar.tsx` + `providers/CommandBarProvider.tsx` → `Avatar`, `Kbd`, `Signal`, `AiModeProvider` |
| `branch-switcher` | Branch switcher | `BranchSwitcherShowcase.tsx` | `components/navigation/BranchSwitcher.tsx` → `SearchInput`, `components/ui/DropdownMenu`, `nav-model` |
| `user-menu` | User menu | `UserMenuShowcase.tsx` | `components/navigation/UserMenu.tsx` → `Avatar`, `components/ui/DropdownMenu`, `DirectionProvider`, `ThemeProvider` |

Shared web building blocks and their Flutter equivalents (introduced in §2):

- `components/ui/DropdownMenu` *(items/content/label/separator/trigger)* — **`AppPopover`** (existing) hosts the body; `AppMenu`/`_AppMenuList` render items/sections/separators/labels.
- `@radix-ui/react-context-menu` — **`AppContextMenu`** (new, `Listener` + overlay fade-scale).
- `components/kbd` — existing **`AppKbd`**.
- `components/tooltip/Tooltip` — existing **`AppTooltip`** (used for sidebar collapsed rail; **not** for disabled-with-reason menu rows inside popovers per memory #11).
- `components/avatar/Avatar` — existing **`AppAvatar`**.
- `components/badge/Badge` — existing **`AppBadge`**.
- `components/actions/SegmentedControl` — existing **`AppSegmentedControl`**.
- `components/actions/Button` / `IconButton` — existing **`AppButton`** / **`AppIconButton`**.
- `components/ui/select/Select` — existing **`AppSelect`**.
- `components/ui/search-input/SearchInput` — existing **`AppSearchInput`**.
- `primitives/Signal` — existing **`AppSignal`** (`standard`/`ai`, horizontal/vertical, default/hero, thinking).
- `providers/CommandBarProvider` — new **`commandBarController`** Riverpod notifier + ⌘K `Shortcuts`/`Actions` + `AppCommandBar` mounted at root `Overlay`.
- `lib/motion` (`motionPresets.tab`/`.nav`/`.command`/`.fade-scale`/`fade`) — **`AppMotion`**/`AppMotionPreset` (`core/ui/motion/app_motion.dart`).
- `lib/cn` — `context.appColors`/`AppSpacing`/`AppRadius`/`AppTypography` token composition (no `cn` analog needed).
- `useDirection` — `Directionality.of(context)` + `devPreviewProvider.direction`/`locale`.
- `useTheme` — `Theme.of(context).brightness` (light/dark) for Sun/Moon icons; showcase toggles `devPreviewProvider`.
- `lucide-react` icons → Material Icons equivalents: `ChevronRight` → `Icons.chevron_right` (RTL auto-mirror via `Icon.matchTextDirection`), `Check` → `Icons.check`, `Search` → `Icons.search`, `Bell` → `Icons.notifications_outlined`, `Moon`/`Sun` → `Icons.dark_mode`/`Icons.light_mode`, `Languages` → `Icons.language`, `LogOut` → `Icons.logout`, `User` → `Icons.person_outline`, `Building2` → `Icons.apartment`, `ChevronDown` → `Icons.expand_more`, `PanelLeftOpen`/`PanelLeftClose` → `Icons.view_sidebar_outlined`/`Icons.dock_to_right_outlined` (or closest Material glyphs), `Plus`/`FileText`/`UserPlus` (`Icons.add`/`Icons.description_outlined`/`Icons.person_add_outlined`), `Sparkles` → `Icons.auto_awesome_outlined`, `Edit`/`Copy`/`Trash2` (`Icons.edit_outlined`/`Icons.copy_outlined`/`Icons.delete_outline`).
- `nav-model.ts` mock constants — **`app_nav_models.dart`** (`kClinicNavGroups`/`kClinicNavFooter`/`kMockBranches`/`kMockUser`/`kMockOrg`/`kMockNotificationCount`).