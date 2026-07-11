# Implementation Plan — Dev → Components → Data Display (Flutter Port)

Spec target: port the **Data display** group of `web-reference/` into the Flutter `frontend/` App abstraction layer, surfaced in the Dev components page. Divided into **5 implementation phases** (user requested 5).

## 0. Ambiguities & Design Decisions (resolve before coding)

> ⚠️ **Before writing any code, read `docs/ui/memory/ui-runtime-errors.md` end-to-end.** It captures the runtime crashes hit while porting the Inputs & forms group (red screens, focus-tree corruption, locale init failures). The Display port must not regress on the same pitfalls. Apply the memory's "Checklist for new input components" to every widget that touches a Material primitive, an overlay, a `Focus`/`FocusNode`, or `intl` date formatting. Specifically relevant to this plan:
> - **Tooltip extension (Phase 1)** uses an `OverlayEntry` + `AnimationController` like `AppPopover` → obey memory §2: do **not** call `AppMotion.transitionFor(context:…)` or read `MediaQuery` in `initState`; initialize the `AnimationController` with a context-free `AppMotion.resolveDuration(AppMotionPreset.fadeScale)` and defer reduced-motion checks to `build`/overlay builder. Also set `preferBelow: false` on the fast-path `Tooltip` to match web `side="top"` (memory §7).
> - **Calendar (Phase 5)** formats weekday labels with a non-default locale (`ar-EG`) via `Intl.DateFormat` → obey memory §3: rely on `ensureIntlDateFormattingInitialized()` (called at app startup in `main.dart`, helper in `frontend/lib/core/utils/intl_date_formatting.dart`) before any locale-specific `DateFormat` use; do not call `initializeDateFormatting` lazily inside the widget.
> - **Resizable panels (Phase 5)** attaches a `Focus`/`FocusNode` for keyboard arrows → obey memory §4: keep the `focusNode` on exactly one widget; do **not** share it between an ancestor `Focus` and a descendant focusable child. Prefer `FocusNode.onKeyEvent` on the single node rather than wrapping in a second `Focus`.
> - **DataTable (Phase 4)** embeds `AppCheckbox` (which uses Material ink) inside custom `Table` cells, and **CodeBlock (Phase 2)** uses `SelectableText`/`InkWell` for the copy button → obey memory §1: any Material primitive (`TextField`, `InkWell`, `Slider`, `DropdownButton`, `Checkbox`'s ink) needs a `Material` ancestor in its innermost shell; do **not** assume `ShowcaseDemo` or `MaterialApp` provides one. Wrap with `appWrapMaterialInput` (or an explicit `Material(type: MaterialType.transparency, …)`) when the visible chrome comes from a parent `DecoratedBox`/`AnimatedContainer`.
> - **Any `initState` that needs `Theme`/`MediaQuery`/`Directionality`** → defer to `didChangeDependencies` or pass context-free tokens (memory §2).

1. **forui vs native Material.** Same decision as the shipped Actions/Inputs groups: **native Material**, `forui-wrappers.md` is superseded. `forui` is imported nowhere; continue using Material primitives (`Tooltip`, `CircleAvatar`, `LinearProgressIndicator`/custom `CustomPainter`, `DataTable`-inspired `Table`, `SingleChildScrollView`, `Listener`/`GestureDetector` for drag).
2. **Core file layout.** Keep **flat** `core/ui/components/app_<name>.dart`. Showcase sections live under `features/design_system/presentation/components/display/<name>_showcase_section.dart` (mirrors existing `actions/` and `inputs/` subfolders).
3. **Extend existing stubs, don't fork.** `app_avatar.dart`, `app_badge.dart`, `app_chip.dart`, `app_kbd.dart`, `app_tooltip.dart` were created during the Inputs milestone as minimal stubs. The Display showcases require the **full web API** (variants, sizes, statuses, chords, placement). **Extend these files in place** rather than creating parallel widgets. `app_chip.dart` already matches the web `Chip` API (removable/selectable/selected/disabled) — only its showcase section is new.
4. **No new architectural patterns.** Unlike Inputs (which needed `AppPopover`), Display needs no new overlay infrastructure — `AppTooltip` extension uses Material `Tooltip` with `preferBelow`/`verticalOffset`/`Decoration` for placement + arrow, and the rich-content case wraps child in a `MouseRegion`+`OverlayEntry` only if Material `Tooltip` cannot host a widget content (Material's `Tooltip` is text-only via `message`/`richMessage`). **Decision: extend `AppTooltip` to use `OverlayEntry`-based custom tooltip** so it can render widget `content` (needed for the "With shortcut hint" demo with inline `AppKbd`). Justified: Material `Tooltip` is text-only; web `Tooltip` accepts ReactNode content.
5. **Charts = pure CustomPainter SVG-equivalent.** Web `AppChart`/`ChartSparkline` are hand-rolled SVG with no chart lib. **Decision: port as `CustomPaint` + `CustomPainter`** (line/bar/stacked-bar/donut/sparkline). No new chart dependency. A11y sr-only table → `Semantics`/`ExcludeSemantics` with a `Semantics(label:...)` summary.
6. **Calendar scope.** Web `Calendar` is a custom month/week/day grid (not Syncfusion). `pubspec` has `syncfusion_flutter_calendar` but it is heavyweight and doesn't match the demo. **Decision: build in-house `AppCalendar`** with a `CustomPainter`-free column layout (month grid via `GridView`, week/day via hour-row `Column`), reusing `AppMonthGrid` patterns from `app_month_grid.dart` where sensible (but `AppMonthGrid` is inputs-private; do not depend on it — Calendar has its own event-pill semantics).
7. **DataTable — native Material `DataTable`/`Table`?** Material `DataTable` is rigid (typed `DataRow`/`DataCell`, no zebra/loading/empty/sort-icons customization without heavy overriding). **Decision: build `AppDataTable` on the lower-level `Table` widget** (custom `TableRow`s) for full control over density, zebra, sticky header, selection checkboxes, sort header buttons, skeleton rows, empty/error row, footer. Reuses `AppCheckbox` (inputs) for selection.
8. **Cross-group shared deps built here.** DataTable's web demo composes `EmptyState`, `ErrorState`, `BulkActionBar` — whose own showcase sections belong to the **Feedback** and **Layout** groups (still placeholders). **Decision: build minimal `AppEmptyState`, `AppErrorState`, `AppBulkActionBar` now** (Phase 4) as shared abstractions, exactly like `AppKbd`/`AppChip` were built during Inputs. Their own Dev showcase sections remain deferred to their respective groups.
9. **i18n / RTL.** `devPreviewProvider` drives locale/direction. Widgets stay direction-agnostic via `Directionality.of(context)`. `AppMoneyDisplay` forces `Directionality.ltr` for the number (matches web `dir="ltr"`), AR currency label follows. `AppCalendar` weekday glyphs localized (`Intl.DateFormat` `ar-EG` → `ح ن ث ر خ ج س`). `AppResizablePanels` mirrors drag in RTL.
10. **Controlled/uncontrolled.** Display widgets are mostly presentational; the few interactive ones (`AppChip` selectable, `AppDataTable` selection/sort, `AppCalendar` view/date, `AppCodeBlock` copy, `AppResizablePanels` resize, `AppProgress` steps) mirror web's `value`/`defaultValue` + `onValueChange` as Flutter `controller`/`onChanged` with internal fallback state, consistent with existing `AppButton`/`AppChip`.
11. **Copy-to-clipboard.** Web `CodeBlock` uses `navigator.clipboard`. Flutter has no built-in clipboard in `material.dart`; **Decision: use `services.dart` `Clipboard.setData`** (already available via Flutter SDK). No new dep.

## 1. Existing App assets to reuse (do not recreate)

| Asset | Path | Used by |
|---|---|---|
| `AppAvatar` (extend) | `core/ui/components/app_avatar.dart` | Avatar, AvatarGroup, EntityCards, List, Calendar (event patient) |
| `AppBadge` (extend) | `core/ui/components/app_badge.dart` | Badge, EntityCards, DataTable status cell |
| `AppChip` (complete — section only) | `core/ui/components/app_chip.dart` | Chip |
| `AppKbd` (extend) | `core/ui/components/app_kbd.dart` | Kbd, Tooltip (shortcut hint), EmptyState (shortcutHint) |
| `AppTooltip` (extend) | `core/ui/components/app_tooltip.dart` | Tooltip, DataTable (column header sort hint) |
| `AppButton`, `AppIconButton`, `AppSegmentedControl` | `core/ui/components/app_*.dart` | Calendar, CodeBlock, EmptyState, ErrorState, BulkActionBar, EntityCards |
| `AppCheckbox` | `core/ui/components/app_checkbox.dart` | DataTable selectable rows + header |
| `AppPressable` | `core/ui/components/app_pressable.dart` | press/hover on Card interactive, ListItem, CodeBlock copy btn |
| Theme: `context.appColors`, `AppSpacing`, `AppRadius`, `AppTypography`, `AppMotion`, `AppElevation` | `core/ui/theme/*` | every widget |
| `devPreviewProvider` | `features/design_system/presentation/providers/dev_preview_provider.dart` | locale/direction in showcases |
| Showcase primitives: `ShowcaseSection`, `ShowcaseDemoGrid`, `ShowcaseDemo`, `ShowcaseVariantMatrix`, `PlaceholderSection` | `components/showcase_primitives.dart` | every showcase section |
| Section wiring: `component_registry.dart`, `component_section_builders.dart`, `components_content.dart` | `components/` | one-line registration per widget |
| `AppColorPrimitives` (teal/violet/red/neutral) | `core/ui/theme/app_color_primitives.dart` | deterministic avatar surfaces, chart palette |
| `intl` (`NumberFormat`/`DateFormat`) | pubspec | MoneyDisplay, Calendar AR glyphs |
| `Clipboard` (`package:flutter/services.dart`) | SDK | CodeBlock copy |

## 2. New shared abstractions to introduce (per phase)

| File (`lib/core/ui/components/`) | Export name | Web analog | Introduced in |
|---|---|---|---|
| `app_divider.dart` | `AppDivider` | `Divider` | Phase 1 |
| `app_avatar.dart` (extend) | `AppAvatar` (+ `AvatarSize`, `AvatarStatus` enums), `AppAvatarGroup` | `Avatar`/`AvatarGroup` | Phase 1 |
| `app_badge.dart` (extend) | `AppBadge` (+ `BadgeColor`, `BadgeVariant`, `BadgeSize` enums) | `Badge` | Phase 1 |
| `app_kbd.dart` (extend) | `AppKbd` (+ `keys`), `AppKbdKey` | `Kbd`/`KbdKey` | Phase 1 |
| `app_tooltip.dart` (extend) | `AppTooltip` (+ `content: Widget`, `side`, `align`, `showArrow`, `disabled`) | `Tooltip`/`TooltipProvider` | Phase 1 |
| `app_skeleton.dart` | `AppSkeleton` (+ `SkeletonVariant`) | `Skeleton` | Phase 2 |
| `app_progress.dart` | `AppProgress` (+ `ProgressVariant`) | `Progress` | Phase 2 |
| `app_money_display.dart` | `AppMoneyDisplay` | `MoneyDisplay` | Phase 2 |
| `app_code_block.dart` | `AppCodeBlock` | `CodeBlock` | Phase 2 |
| `app_description_list.dart` | `AppDescriptionList` (+ `DescriptionItem`) | `DescriptionList` | Phase 2 |
| `app_list.dart` | `AppList`, `AppListItem` | `List`/`ListItem` | Phase 2 |
| `app_card.dart` | `AppCard` (+ `CardVariant`, `CardPadding`), `AppMetricCard` (+ `MetricDelta`), `AppPatientCard`, `AppAppointmentCard`, `AppInvoiceCard`, `AppServiceCard` | `Card`/`MetricCard`/EntityCards | Phase 3 |
| `app_chart.dart` | `AppChart` (+ `ChartSeries`, `AppChartType`, `chartPalette`), `AppChartSparkline` | `AppChart`/`ChartSparkline` | Phase 3 |
| `app_timeline.dart` | `AppTimeline` (+ `TimelineEvent`) | `Timeline` | Phase 3 |
| `app_empty_state.dart` | `AppEmptyState` (+ `EmptyStateVariant`) | `EmptyState` | Phase 4 (shared — own showcase deferred to Feedback) |
| `app_error_state.dart` | `AppErrorState` | `ErrorState` | Phase 4 (shared — own showcase deferred to Feedback) |
| `app_bulk_action_bar.dart` | `AppBulkActionBar` | `BulkActionBar` | Phase 4 (shared — own showcase deferred to Layout) |
| `app_data_table.dart` | `AppDataTable` (+ `TableColumn`, `TableDensity`, `TableAlign`, `SortDirection`) | `DataTable` | Phase 4 |
| `app_calendar.dart` | `AppCalendar` (+ `CalendarEvent`, `CalendarView`) | `Calendar` | Phase 5 |
| `app_scroll_area.dart` | `AppScrollArea` | `ScrollArea` | Phase 5 |
| `app_resizable_panels.dart` | `AppResizablePanels` | `ResizablePanels` | Phase 5 |

**Barrel update:** append every new/extended `app_*.dart` to `lib/core/ui/widgets/widgets.dart` under a `// Data display` sub-comment (existing `// Components`/`// Inputs` blocks stay).

## 3. Phasing

> Rationale: **Phase 1** = the atomic primitives everything else composes (extend the 5 existing stubs + Divider). **Phase 2** = loading/shape/text display primitives (Skeleton, Progress, Money, CodeBlock, DescriptionList, List) — no cross-deps. **Phase 3** = cards + charts + timeline (Card first, Chart needed by MetricCard's sparkline, then EntityCards composing Card/Avatar/Badge/Money, then Timeline). **Phase 4** = the heavy DataTable + its 3 cross-group shared deps (EmptyState/ErrorState/BulkActionBar) built minimally. **Phase 5** = layout-ish display primitives (Calendar, ScrollArea, ResizablePanels). Each phase is independently shippable.

### Phase 1 — Atomic primitives (extend stubs + Divider)
Widgets: **Badge, Chip, Avatar, Tooltip, Kbd, Divider**

| Widget | Flutter widget(s) to create/extend | File(s) | Reuse | Wrapper | Deps |
|---|---|---|---|---|---|
| Badge | Extend `AppBadge` with `variant: BadgeVariant`, `color: BadgeColor`, `size: BadgeSize`, `label: String?`; render dot leading span when `dot` | MOD `components/app_badge.dart`; MOD `widgets.dart` | theme, `AppRadius`, `AppColorPrimitives` (teal/ai colors) | EXTEND existing | none |
| Chip | `AppChip` already matches web API — showcase section only | CREATE `components/display/chip_showcase_section.dart` | `AppChip` | none (already built) | `AppChip` |
| Avatar | Extend `AppAvatar` with `size: AvatarSize`, `status: AvatarStatus`, `showStatus: bool`, `src: String?`, deterministic initials color via `name.hashCode % 5`; NEW `AppAvatarGroup { max, size, children }` with `+N` overflow pill | MOD `components/app_avatar.dart`; MOD `widgets.dart` | theme, `AppColorPrimitives`, `CircleAvatar`/`Image.network` | EXTEND existing | none |
| Tooltip | Extend `AppTooltip` to `OverlayEntry`-based: `content: Widget`, `side: TooltipSide`, `align`, `showArrow`, `disabled`, delay 400ms, fade-scale via `AppMotion`; keep `message: String?` fast path | MOD `components/app_tooltip.dart` | `AppMotion`, `AppRadius`, `AppElevation`, `LayerLink`+`CompositedTransformFollower` | EXTEND existing | `AppKbd` (shortcut-hint demo) |
| Kbd | Extend `AppKbd` with `keys: List<String>` (chord, `+`-joined), NEW `AppKbdKey` standalone | MOD `components/app_kbd.dart`; MOD `widgets.dart` | theme, `AppTypography.mono` | EXTEND existing | none |
| Divider | NEW `AppDivider { orientation, label }` | CREATE `components/app_divider.dart`; MOD `widgets.dart` | theme (`borderSubtle`), `AppTypography.caption` | NEW | none |

Showcase sections (Phase 1), under `features/design_system/presentation/components/display/`:
`badge_showcase_section.dart`, `chip_showcase_section.dart`, `avatar_showcase_section.dart`, `tooltip_showcase_section.dart`, `kbd_showcase_section.dart`, `divider_showcase_section.dart`.

### Phase 2 — Loading, shape & text primitives
Widgets: **Skeleton, Progress, MoneyDisplay, CodeBlock, DescriptionList, List**

| Widget | Flutter widget(s) | File(s) | Reuse | Wrapper | Deps |
|---|---|---|---|---|---|
| Skeleton | `AppSkeleton { variant: SkeletonVariant, width, height }`; shimmer via `AnimatedBuilder`+`LinearGradient` sweep, static when `MediaQuery.disableAnimations` | CREATE `components/app_skeleton.dart`; MOD `widgets.dart` | theme (`surfaceMuted`), `AppMotion` | NEW | none |
| Progress | `AppProgress { variant: ProgressVariant, value, indeterminate, showLabel, size, steps, currentStep }`; bar=`LinearProgressIndicator` restyled + `FractionallySizedBox`; circular=`CustomPainter` arc; steps=row of `Flexible` segments | CREATE `components/app_progress.dart`; MOD `widgets.dart` | theme (`actionPrimary`, `surfaceMuted`), `AppMotion`, `AppTypography.caption` (tabular %) | NEW | none |
| Money display | `AppMoneyDisplay { amount, currency:'EGP', emphasis, negative? }`; `NumberFormat('#,##0.00', 'en_EG')`, `−` U+2212 prefix, `Directionality.ltr`, currency label `textTertiary` | CREATE `components/app_money_display.dart`; MOD `widgets.dart` | theme (`statusDangerFg`, `textPrimary`), `intl` | NEW | none |
| Code block | `AppCodeBlock { code, language }`; header bar (language label), `<pre>` via `SelectableText` mono, copy `AppButton variant=ghost` with Check/Copy icon + 2s "Copied" via `Clipboard.setData` | CREATE `components/app_code_block.dart`; MOD `widgets.dart` | `AppButton`, `AppPressable`, `AppTypography.mono`, `Clipboard` (services.dart) | NEW | `AppButton` |
| Description list | `AppDescriptionList { items: List<DescriptionItem>, columns: 1\|2 }`; `DescriptionItem { label, value: Widget, tabular }`; `GridView`/`Wrap`, `<dt>` caption / `<dd>` body | CREATE `components/app_description_list.dart`; MOD `widgets.dart` | theme, `AppTypography`, `AppSpacing` | NEW | none |
| List | `AppList { divided, children }` + `AppListItem { leading, primary, secondary, trailing, selected, onTap }`; `ListView`/`Column`, divided via `Divider`-height, interactive=`InkWell`/`AppPressable` | CREATE `components/app_list.dart`; MOD `widgets.dart` | theme, `AppTypography`, `AppPressable`, `AppDivider` (P1) | NEW | `AppDivider` |

Showcase sections (Phase 2): `skeleton_showcase_section.dart`, `progress_showcase_section.dart`, `money_display_showcase_section.dart`, `code_block_showcase_section.dart`, `description_list_showcase_section.dart`, `list_showcase_section.dart`.

### Phase 3 — Cards, charts, timeline
Widgets: **Card, Chart, MetricCard, EntityCards, Timeline**

| Widget | Flutter widget(s) | File(s) | Reuse | Wrapper | Deps |
|---|---|---|---|---|---|
| Card | `AppCard { variant: CardVariant, header, footer, padding, child }`; variants map to border/bg/elevation tokens; interactive=`InkWell` hover | CREATE `components/app_card.dart`; MOD `widgets.dart` | theme (`surfaceDefault/Raised/Hover/Ai`, `borderDefault/Subtle/Focus/Ai`), `AppElevation`, `AppRadius.lg` | NEW | none |
| Chart | `AppChart { type: AppChartType, series, labels, height, ariaLabel }` + `AppChartSparkline { data, color }`; pure `CustomPaint`/`CustomPainter` for line/bar/stacked-bar/donut/sparkline; `chartPalette` const list of `AppColorPrimitives`; `Semantics` summary | CREATE `components/app_chart.dart`; MOD `widgets.dart` | theme (`actionPrimary`, `statusInfoFg`, etc.), `AppColorPrimitives`, `AppRadius.lg` | NEW | none |
| Metric card | `AppMetricCard { label, value, delta: MetricDelta?, caption, sparkline: Widget? }` over `AppCard variant=raised`; delta icon TrendingUp/Down (`Icons.trending_up/down`) colored by `positive` | MOD `components/app_card.dart` (same file); MOD `widgets.dart` | `AppCard`, `AppTypography.display`, `AppChartSparkline`, `Icons` | NEW (in same file) | `AppCard`, `AppChartSparkline` |
| Entity cards | `AppPatientCard`, `AppAppointmentCard`, `AppInvoiceCard`, `AppServiceCard` — each composes `AppCard` + `AppAvatar`/`AppBadge`/`AppMoneyDisplay`/`AppIconButton`/`Icons` | MOD `components/app_card.dart`; MOD `widgets.dart` | `AppCard`, `AppAvatar`, `AppBadge`, `AppMoneyDisplay`, `AppIconButton`, `AppButton` | NEW (in same file) | `AppCard`, `AppAvatar`/`AppBadge`/`AppMoneyDisplay` (P1/P2) |
| Timeline | `AppTimeline { events: List<TimelineEvent> }`; grouped `ol`-equivalent `Column` with start border (`BorderDirectional.start`), dot via `DecoratedBox` positioned, `<time>` caption tabular | CREATE `components/app_timeline.dart`; MOD `widgets.dart` | theme (`borderSubtle`, `actionPrimary`, `surfaceDefault`), `AppTypography`, `AppSpacing` | NEW | none |

Showcase sections (Phase 3): `card_showcase_section.dart`, `chart_showcase_section.dart`, `metric_card_showcase_section.dart`, `entity_cards_showcase_section.dart`, `timeline_showcase_section.dart`.

### Phase 4 — Data table + cross-group shared deps
Widgets: **DataTable** (+ shared `EmptyState`, `ErrorState`, `BulkActionBar` built here)

| Widget | Flutter widget(s) | File(s) | Reuse | Wrapper | Deps |
|---|---|---|---|---|---|
| Empty state (shared) | `AppEmptyState { variant: EmptyStateVariant, title, description, action, secondaryAction, shortcutHint }`; centered col, icon in muted circle, optional `AppButton` + `AppKbd` hint | CREATE `components/app_empty_state.dart`; MOD `widgets.dart` | theme, `AppButton`, `AppKbd`, `Icons` (folder_open/search/lock/file) | NEW (shared — own showcase deferred to Feedback) | `AppButton`, `AppKbd` |
| Error state (shared) | `AppErrorState { title, message, onRetry, retryLabel }`; `role=alert`-equivalent `Semantics(alert)`, AlertTriangle icon in danger circle, retry `AppButton variant=secondary` + RefreshCw | CREATE `components/app_error_state.dart`; MOD `widgets.dart` | theme (`statusDangerFg/Surface`), `AppButton`, `Icons.warning`/`Icons.refresh` | NEW (shared — own showcase deferred to Feedback) | `AppButton` |
| Bulk action bar (shared) | `AppBulkActionBar { count, itemLabel, actions, onClear }`; returns `SizedBox.shrink()` when count==0; `role=region`; right side actions + Clear `AppButton variant=ghost` with X icon | CREATE `components/app_bulk_action_bar.dart`; MOD `widgets.dart` | theme (`surfaceRaised`, `AppElevation.elevation2`), `AppButton`, `Icons.close` | NEW (shared — own showcase deferred to Layout) | `AppButton` |
| Data table | `AppDataTable<T> { columns, data, density, zebra, stickyFirstColumn, selectable, selectedIds, onSelectionChange, getRowId, sortColumn, sortDirection, onSort, loading, loadingRows, emptyState, errorState, footer, onRowClick, rowActions }` over Material `Table` + `SingleChildScrollView` (horizontal); sticky thead via `Column`+vertical scroll; header sort buttons w/ ArrowUp/Down/UpDown icons; skeleton rows via `AppSkeleton`; selection via `AppCheckbox` | CREATE `components/app_data_table.dart`; MOD `widgets.dart` | theme, `AppCheckbox`, `AppSkeleton` (P2), `AppIconButton` (default row action), `AppEmptyState`/`AppErrorState`/`AppBulkActionBar` (built above), `Icons` | NEW | `AppCheckbox`, `AppSkeleton`, `AppEmptyState`/`AppErrorState`/`AppBulkActionBar` |

Showcase sections (Phase 4): `data_table_showcase_section.dart` (the only display section; the 3 shared widgets get no showcase section yet — deferred).

### Phase 5 — Calendar, scroll area, resizable panels
Widgets: **Calendar, ScrollArea, ResizablePanels**

| Widget | Flutter widget(s) | File(s) | Reuse | Wrapper | Deps |
|---|---|---|---|---|---|
| Calendar | `AppCalendar { events: List<CalendarEvent>, view: CalendarView, date, onViewChange, onDateChange }`; header (prev/next `AppIconButton`, title, `AppSegmentedControl` day/week/month, "Today" `AppButton variant=secondary`); month=`GridView` 7-col w/ weekday headers + event pills; week/day = hour-row `Column` w/ day columns + "now" indicator + event cards; conflict → `statusDangerSurface/Fg`; localized weekday glyphs via `Intl.DateFormat(weekdayLabels, locale)` | CREATE `components/app_calendar.dart`; MOD `widgets.dart` | theme, `AppIconButton`, `AppButton`, `AppSegmentedControl`, `intl` `DateFormat`, `Icons.chevron_left/right` | NEW | `AppIconButton`/`AppButton`/`AppSegmentedControl` |
| Scroll area | `AppScrollArea { maxHeight, fadeEdges, child }`; `SingleChildScrollView` w/ thin custom scrollbar; top/bottom gradient `IgnorePointer` overlays when `fadeEdges`; `Semantics(role:region, label)` | CREATE `components/app_scroll_area.dart`; MOD `widgets.dart` | theme (`surfaceDefault`), `AppRadius.lg` | NEW | none |
| Resizable panels | `AppResizablePanels { start, end, defaultStartPercent:35, minStartPercent:20, maxStartPercent:60 }`; `LayoutBuilder`+`Row`, start=`SizedBox(width: %)` w/ `SingleChildScrollView`, divider=`Listener`/`GestureDetector` drag (RTL-aware via `Directionality.of`) + `Focus`+`KeyboardListener` ArrowLeft/Right ±2%; `role=separator` `Semantics` | CREATE `components/app_resizable_panels.dart`; MOD `widgets.dart` | theme (`borderDefault`/`borderFocus`), `AppRadius.lg` | NEW | none |

Showcase sections (Phase 5): `calendar_showcase_section.dart`, `scroll_area_showcase_section.dart`, `resizable_panels_showcase_section.dart`.

## 4. Dev-page instantiation spec per widget (mirrors web reference)

> **Binding source of truth:** the per-demo arrangement, props, labels, copy, and variant matrices in each Flutter showcase section **must mirror exactly** how the corresponding showcase in `web-reference/src/showcase/components/display/<Name>Showcase.tsx` (or `DataDisplayShowcase.tsx` for the 13 grouped exports) instantiates the web widget. Composer 2.5 should open the referenced `.tsx` for each widget and reproduce, demo-for-demo:
> - the number, order, and titles of `ShowcaseDemo` cells;
> - the exact props passed to the control (variants, sizes, `defaultValue`s, statuses, icons, affixes, disabled flags, etc.);
> - any `ShowcaseVariantMatrix` rows below the `ShowcaseDemoGrid`;
> - the bilingual EN/AR copy following the existing `_copyEn`/`_copyAr` convention (see `actions/button_showcase_section.dart`).
>
> The Flutter `ShowcaseSection`/`ShowcaseDemoGrid`/`ShowcaseDemo`/`ShowcaseVariantMatrix` primitives are 1:1 in shape with the web ones, so the demo structure ports verbatim — only the control widget name and prop syntax change.

Per-widget demo spec (reproduce from the cited `.tsx`):

- **Badge** (`BadgeShowcase.tsx`) — `ShowcaseDemoGrid columns=2` of 4 demos: `Variant · solid/soft/outline/dot`, each containing a `ShowcaseVariantMatrix(title:"Status colors")` over 7 colors (neutral/success/warning/danger/info/teal/ai) labeling each pill with its color name; `Sizes` demo (sm/md, success); `Domain status mapping` demo (9 soft badges: Paid/Active/Confirmed/Pending/Draft/Overdue/Cancelled/In progress/AI suggested); `Dot with accessible label` demo (dot success "Active", dot danger "No-show" w/ visible text).
- **Chip** (`ChipShowcase.tsx`) — `ShowcaseDemoGrid` of 4: `Default` (Insurance, Walk-in); `Removable` (Branch A, Active — removable, stateful removal); `Selectable filters` (Today/This week/This month — stateful toggle, Today pre-selected); `Disabled` (plain "Inactive service" + selectable-selected "Locked").
- **Avatar** (`AvatarShowcase.tsx`) — `Sizes` demo (`ShowcaseVariantMatrix(title:"Initials")` over xs/sm/md/lg/xl, all "Sara Hassan"); `Status dot` demo (4 statuses online/offline/busy/away each labeled below); `ShowcaseDemoGrid` of 2: `Avatar group` (max=4, 5-member TEAM w/ +N overflow) and `Deterministic initials color` (4 members).
- **Tooltip** (`TooltipShowcase.tsx`) — wrap in `TooltipProvider`-equivalent (no-op in Flutter). `ShowcaseDemoGrid` of 3: `Default` (delay 400ms — bordered "Hover or focus me" button w/ Info icon, content "View patient history"); `With shortcut hint` (primary "Quick actions" button, content widget "Open Command Bar ⌘K" w/ inline `AppKbd`); `Placement` (4 buttons top/right/bottom/left, each with its own placement).
- **Kbd** (`KbdShowcase.tsx`) — `ShowcaseDemoGrid columns=3` of 3: `Single key` (`AppKbdKey` Enter/Esc/`/`); `Chord` (`AppKbd keys=[⌘,K]`); `Search hint` (inline "Press ⌘F to search" sentence).
- **Divider** (`DividerShowcase.tsx`) — `ShowcaseDemoGrid` of 3: `Horizontal` (text above/below w/ `AppDivider` between); `With label` ("Or continue with"); `Vertical` (Patients | Appointments in a row).
- **Skeleton** (`SkeletonShowcase.tsx`) — `ShowcaseDemoGrid` of 4: `Variants` (text max-w-xs, circular 40×40, rectangular 120×80); `List row layout` (circular 32 + two text lines); `Card layout` (rectangular 96 + text + 2/3 text); `Contrast with loaded avatar` (skeleton circular 32 + real `AppAvatar` md).
- **Progress** (`ProgressShowcase.tsx`) — `Bar · determinate` demo (value stateful via slider, `showLabel`, max-w-md); `ShowcaseDemoGrid` of 3: `Bar · indeterminate`, `Circular` (value 75 md + value 30 sm + indeterminate), `Steps` (5 steps current 2 + 4 steps current 4).
- **Money display** (`MoneyDisplayShowcase.tsx`) — single `ShowcaseDemo(label:"Variants")`: `MoneyDisplay(1250.5)`, `MoneyDisplay(1250.5, emphasis)`, `MoneyDisplay(-320, negative)`.
- **Code block** (`CodeBlockShowcase.tsx`) — single section, no demo grid: `CodeBlock(language:"json", code:'{\n  "patientId": "10482",\n  "mrn": "MRN-10482"\n}')`.
- **Description list** (`DescriptionListShowcase.tsx`) — single section: `DescriptionList(items:[{MRN,10482,tabular},{Date of birth,"Mar 14, 1988"},{Phone,"+20 100 234 5678",tabular},{Insurance,"AXA Egypt"}])`.
- **List** (`ListShowcase.tsx`) — single section: `List(aria-label:"Recent patients")` of 3 `ListItem`s (leading `AppAvatar sm`, primary name, secondary phone, trailing `AppMoneyDisplay(balance)`), over `MOCK_PATIENTS` (Layla Hassan / Omar Farouk / Nadia El-Sayed).
- **Card** (`CardShowcase` in `DataDisplayShowcase.tsx`) — `ShowcaseDemoGrid columns=2` of 4: `flat`/`raised`/`interactive`/`ai`, each `AppCard(variant, className:"w-full p-4")` with "Card title" + supporting text mentioning the variant.
- **Chart** (`ChartShowcase`) — `ShowcaseDemoGrid columns=2` of 4: `Line` (series Appointments [12,18,15,22,19], labels Mon–Fri); `Bar` (same series); `Stacked bar` (New [5,8,6,10,7] + Follow-up [7,10,9,12,12]); `Donut` (Services [40,30,20,10]).
- **Metric card** (`MetricCardShowcase`) — `ShowcaseDemoGrid columns=2` of 2: `Revenue today` (value "12,450.00", delta +8.2% up positive, caption "vs. yesterday", sparkline [4,6,5,8,7,9,12] action-primary); `Outstanding` (value "3,200.00", delta −2.1% down positive).
- **Entity cards** (`EntityCardsShowcase`) — `ShowcaseDemoGrid columns=2` of 4: `PatientCard` (Layla Hassan, mrn 10482, phone, tags [Insurance,VIP]); `AppointmentCard` (9:30 AM, Omar Farouk, Dr. Sara Mahmoud, confirmed, Downtown); `InvoiceCard` (INV-2026-0842, Nadia El-Sayed, 1850, pending, Jul 2 2026); `ServiceCard` (General consultation, 350, active, "Available at 3 of 4 branches").
- **Timeline** (`TimelineShowcase`) — single section, 3 grouped events: group "Jul 4, 2026" (10:30 "Visit completed" / 10:15 "Vitals recorded" BP 120/80 temp 37.1°C); group "Jul 2, 2026" (2:00 PM "Invoice paid" EGP 850.00 via card).
- **Data table** (`DataTableShowcase`) — top toolbar of 4 toggle buttons (default/loading/empty/error, stateful); conditional `AppBulkActionBar` when selection>0 (count, "patients selected", "Export" action, onClear); `AppDataTable` columns: Patient (sortable), Phone (align end), Balance (sortable, `AppMoneyDisplay` cell, negative when <0), Status (`AppBadge color=success variant=soft "Active"`); data=`MOCK_PATIENTS` when default else `[]`; density default, zebra, selectable; sort stateful (col + asc/desc toggle); loading demo shows skeleton rows; empty demo → `AppEmptyState variant=no-results`; error demo → `AppErrorState` w/ message + onRetry→setDemo('default'); footer "Total balance: `AppMoneyDisplay(1250, emphasis)`".
- **Calendar** (`CalendarShowcase`) — single section: `AppCalendar(events: MOCK_EVENTS)` (2 events on Jul 4 2026: Consultation 9:00–9:30 Layla Hassan/Dr. Ahmed; Follow-up 10:00–10:30 Omar Farouk/Dr. Sara, conflict=true). Default week view.
- **Scroll area** (`ScrollAreaShowcase`) — single section: `AppScrollArea(maxHeight:160, className:"rounded-lg border")` containing 12 "Scrollable row N" paragraphs.
- **Resizable panels** (`ResizablePanelsShowcase`) — single section: `AppResizablePanels(start: "Master list pane", end: "Detail pane — drag the divider or use arrow keys")`.

Bilingual copy: every label/placeholder/description string above has an AR counterpart via the `_copyEn`/`_copyAr` const-class pattern (mirroring `button_showcase_section.dart`/`search_input_showcase_section.dart`). Domain status words, weekday glyphs, and "Or continue with" must be translated. Calendar weekday labels come from `Intl.DateFormat(EEE, locale)` so no manual AR table is needed.

## 5. Wiring steps (do after each phase's widgets land)

1. `component_registry.dart` — for each finished display `id`, change `status: ShowcaseSectionStatus.placeholder` → `ShowcaseSectionStatus.ready` (keep order; ids already present at lines 203–328: badge, chip, avatar, tooltip, kbd, divider, skeleton, progress, data-table, card, metric-card, entity-cards, list, description-list, timeline, calendar, chart, money-display, code-block, scroll-area, resizable-panels).
2. `component_section_builders.dart` — add an entry per ready id in `componentSectionBuilders`, grouped under a `// Data display` comment (mirroring the existing `// Inputs & forms` block). Reuse the exact `'id'` strings from `component_registry.dart`. Example:
   ```
   // Data display
   'badge': () => const BadgeShowcaseSection(),
   'chip': () => const ChipShowcaseSection(),
   ...
   ```
3. Import the new section files at the top of `component_section_builders.dart` (group imports under a `// Data display` comment, after the Inputs block).
4. Append new/extended `app_*.dart` core files to `widgets.dart` barrel export list under a `// Data display` sub-comment (after the `// Inputs` block). Files extended in place (`app_avatar`, `app_badge`, `app_kbd`, `app_tooltip`) are already exported — no duplicate export needed; only newly-created files (`app_divider`, `app_skeleton`, `app_progress`, `app_money_display`, `app_code_block`, `app_description_list`, `app_list`, `app_card`, `app_chart`, `app_timeline`, `app_empty_state`, `app_error_state`, `app_bulk_action_bar`, `app_data_table`, `app_calendar`, `app_scroll_area`, `app_resizable_panels`) get new export lines.
5. Run `flutter analyze` (project uses `flutter_lints`) on changed files; fix lints. Do **not** commit unless asked.

## 6. Out-of-scope / defer

- The `forui`-based wrappers described in `docs/ui/forui-wrappers.md` are not built or reconciled here.
- **Dev showcase sections for `EmptyState`, `ErrorState`, `BulkActionBar` are deferred** to the Feedback & overlays and Layout & utility milestones respectively — only the shared `App*` widgets are built here (DataTable depends on them).
- Syncfusion calendar integration — not used; `AppCalendar` is a custom in-house grid.
- No new chart library — `AppChart` is pure `CustomPainter`.
- Density provider (`useDensity` web) — `AppDataTable` accepts an explicit `density` prop; no global DensityProvider ported in this milestone.
- `ChartSeries.color` per-series custom colors and `area` chart type are accepted by the API but `area` renders as `line` (matches web).
- Navigation/Feedback/AI/Layout group sections remain placeholders.

## 7. Source reference — web widget inventory

The 21 widgets in `web-reference/src/showcase/components/display/index.ts`:

| id | Title | Showcase file | Underlying UI component |
|---|---|---|---|
| `badge` | Badge / Status pill | `BadgeShowcase.tsx` | `components/badge/Badge.tsx` |
| `chip` | Chip / Tag | `ChipShowcase.tsx` | `components/chip/Chip.tsx` |
| `avatar` | Avatar / Group | `AvatarShowcase.tsx` | `components/avatar/{Avatar,AvatarGroup}.tsx` |
| `tooltip` | Tooltip | `TooltipShowcase.tsx` | `components/tooltip/Tooltip.tsx` (+ Radix) |
| `kbd` | Kbd | `KbdShowcase.tsx` | `components/kbd/Kbd.tsx` |
| `divider` | Divider | `DividerShowcase.tsx` | `components/divider/Divider.tsx` |
| `skeleton` | Skeleton | `SkeletonShowcase.tsx` | `components/skeleton/Skeleton.tsx` |
| `progress` | Progress | `ProgressShowcase.tsx` | `components/progress/Progress.tsx` |
| `data-table` | Table / Data grid | `DataDisplayShowcase.tsx` (`DataTableShowcase`) | `components/table/DataTable.tsx` |
| `card` | Card | `DataDisplayShowcase.tsx` (`CardShowcase`) | `components/card/Card.tsx` |
| `metric-card` | Metric card | `DataDisplayShowcase.tsx` (`MetricCardShowcase`) | `components/card/MetricCard.tsx` |
| `entity-cards` | Entity cards | `DataDisplayShowcase.tsx` (`EntityCardsShowcase`) | `components/card/{Patient,Appointment,Invoice,Service}Card.tsx` |
| `list` | List | `DataDisplayShowcase.tsx` (`ListShowcase`) | `components/list/List.tsx` |
| `description-list` | Description list | `DataDisplayShowcase.tsx` (`DescriptionListShowcase`) | `components/description-list/DescriptionList.tsx` |
| `timeline` | Timeline | `DataDisplayShowcase.tsx` (`TimelineShowcase`) | `components/timeline/Timeline.tsx` |
| `calendar` | Calendar | `DataDisplayShowcase.tsx` (`CalendarShowcase`) | `components/calendar/Calendar.tsx` |
| `chart` | Chart primitives | `DataDisplayShowcase.tsx` (`ChartShowcase`) | `components/chart/Chart.tsx` |
| `money-display` | Money display | `DataDisplayShowcase.tsx` (`MoneyDisplayShowcase`) | `components/money/MoneyDisplay.tsx` |
| `code-block` | Code block | `DataDisplayShowcase.tsx` (`CodeBlockShowcase`) | `components/code-block/CodeBlock.tsx` |
| `scroll-area` | Scroll area | `DataDisplayShowcase.tsx` (`ScrollAreaShowcase`) | `components/scroll-area/ScrollArea.tsx` |
| `resizable-panels` | Resizable panels | `DataDisplayShowcase.tsx` (`ResizablePanelsShowcase`) | `components/resizable/ResizablePanels.tsx` |

Shared web building blocks (port equivalents in §2):
- `components/ui/checkbox` → existing `app_checkbox.dart` (DataTable selection).
- `components/ui/popover` (Radix) → existing `app_popover.dart` (not needed by Display showcases — Tooltip uses its own overlay).
- `components/ui/spinner` (`Loader2`) → no dedicated `app_spinner.dart`; Progress circular indeterminate + `AppButton.loading` cover the cases Display needs.
- `components/ui/kbd`, `components/ui/tooltip`, `components/ui/chip` → map to `components/{kbd,tooltip,chip}` → existing `app_kbd`/`app_tooltip`/`app_chip` (extended in Phase 1).
- `components/ui/input-base` → existing `app_input_styles.dart` (inputs-only, not used by Display).
- `lib/cn` (Tailwind merge) → no Flutter equivalent; replaced by direct `BoxDecoration`/`TextStyle` composition.
- `lib/motion` (`motionPresets`, `resolveTransition`) → `app_motion.dart` (`AppMotion.instant`/`standardCurve`).
- `providers/DensityProvider` (`useDensity`) → `AppDataTable.density` prop (no global provider ported).
- `providers/DirectionProvider` (`useDirection`) → `Directionality.of(context)` + `devPreviewProvider.direction`.
- Radix primitives (`@radix-ui/react-tooltip`) → custom `OverlayEntry` in extended `app_tooltip.dart`.
- `lucide-react` icons → Flutter `Icons` equivalents (`Icons.add`/`close`/`chevron_left`/`chevron_right`/`trending_up`/`trending_down`/`content_copy`/`check`/`warning`/`refresh`/`folder_open`/`search`/`lock`/`info`/`calendar_today`/`more_horiz`/`phone`/`arrow_upward`/`arrow_downward`/`swap_vert`).

Cross-cutting web notes (inform the Flutter port):
- Single `BadgeColor`/`BadgeVariant`/`BadgeSize` system; `teal`↔action-primary tokens, `ai`↔action-ai tokens.
- `Avatar` deterministic color = `hashString(name) % 5` over 5 surfaces; status dot bottom-end w/ surface ring.
- `Progress` clamps `value` to 0–100; indeterminate omits `aria-valuenow`.
- `MoneyDisplay` forces `dir="ltr"`, `−` U+2212 (not ASCII hyphen), `toLocaleString('en-EG')`, currency label in `textTertiary`.
- `DataTable` selection checkbox is `indeterminate` when some-but-not-all selected; sort header cycles asc↔desc on same col, else asc.
- `Calendar` month grid shows up to 2 event pills/day; conflict pill = danger surface; week/day "now" indicator only on today's column at current hour.
- `ResizablePanels` RTL-aware: in RTL, drag x = `rect.right - clientX`; ArrowLeft/Right semantics invert.
- `Timeline` groups by `event.group`; renders group headers only when >1 distinct group.
- i18n/RTL: `MoneyDisplay`, `CodeBlock` (LTR code), `ResizablePanels` (drag mirror) are direction-sensitive; `Calendar` consumes locale for weekday glyphs.
