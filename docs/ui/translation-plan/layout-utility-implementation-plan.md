# Implementation Plan — Dev → Components → Layout & Utility (Flutter Port)

Spec target: port the **Layout & utility** group of `web-reference/` into the Flutter `frontend/` App abstraction layer, surfaced in the Dev components page. Split into **two phases** (per user request — default would be three; two kept since the group has fewer primitives and several widgets already ship as App widgets).

> Phase count note: user requested `divide them into two phases only`. Two phases were honored as requested; each phase remains a meaningful, independently-shippable cluster.

## 0. Ambiguities & Design Decisions (resolve before coding)

⚠️ **Composer 2.5: read `docs/ui/memory/ui-runtime-errors.md` end-to-end before touching any widget in this group.** The regressions below are the ones most likely to recur in this group — guard against them explicitly.

1. **forui vs native Material.** The shipping Actions / Inputs / Display App widgets use **native Material** under `core/ui/components/app_*.dart`. `forui` is imported nowhere. `docs/ui/forui-wrappers.md` is **superseded**.
   **Decision: keep native Material.** No forui.

2. **Already-shipped App widgets reused, not recreated.** Three of the seven layout web components already have an App widget:
   - `BulkActionBar` → `frontend/lib/core/ui/components/app_bulk_action_bar.dart`
   - `ScrollArea` → `frontend/lib/core/ui/components/app_scroll_area.dart`
   - `ResizablePanels` → `frontend/lib/core/ui/components/app_resizable_panels.dart`
   These widgets are feature-complete and already exported in `widgets.dart`. **Do not recreate them.** Only the *showcase section* files under `components/layout/` need to be authored (each bound to its own layout-group `id`, distinct from the display-group id).

3. **New App widgets to create (flat, under `core/ui/components/`):**
   - `app_page_header.dart` → `AppPageHeader` (web `PageHeader`)
   - `app_section_header.dart` → `AppSectionHeader` (web `SectionHeader`)
   - `app_toolbar.dart` → `AppToolbar` (web `Toolbar`)
   - `app_app_shell.dart` → `AppAppShell` (web `AppShell`). Named `AppAppShell` to avoid collision with the production `app/shell/layout/app_shell.dart` (which is the app's own shell frame, not the design-system primitive).

4. **Core file layout.** Flat `app_<name>.dart` per widget (mirrors Actions/Inputs/Display). Showcase sections under `features/design_system/presentation/components/layout/` (new subfolder, mirrors `components/inputs/`, `components/display/`).

5. **No new shared infrastructure.** All seven widgets compose existing App primitives (`AppButton`, `AppBreadcrumb`, `AppTabs`, `AppSidebar`, `AppSkeleton`, `AppSearchInput`, `AppChip`, `AppBulkActionBar`, `AppScrollArea`, `AppResizablePanels`). No popover, chip, calendar, dialog, etc. is needed — already shipped. The only new wrappers are the four listed in §3 above.

6. **i18n / RTL.** Showcase samples bilingual EN/AR copy via `devPreviewProvider`. Widgets are pure slot-composition widgets (no inputs, no locales) and stay direction-agnostic via `Directionality.of(context)`. The `AppAppShell` showcase needs a mock nav-model (branches, org, user, nav groups) — reuse the same shape as web `nav-model.ts`; author a small `layout/nav_model_mock.dart` constant in the showcase folder (display-only data, no production coupling).

7. **Controlled / uncontrolled.** The `AppAppShell` showcase holds the `activeId`, `collapsed`, `branchId`, and `tab` state in the showcase widget itself (`StatefulWidget` / `ConsumerStatefulWidget`), exactly like the web `AppShellShowcase` uses `useState`. No `controller` plumbing on the App widgets themselves — they are pure composition (slots).

8. **AppAppShell ↔ production `AppShell` in `app/shell/layout/app_shell.dart`.** They differ: the production shell uses `SizedBox.expand` + `SingleChildScrollView` and serves the real app frame; the design-system `AppAppShell` mirrors the web `AppShell` (sidebar | topBar / main-overflow with `max-w-6xl` content gutter / optional commandBar slot, `contentClassName` / `fullWidth` flags). Do **not** refactor the production shell — create a separate primitive.

9. **TopBar dependency in the AppShell demo.** Web `AppShellShowcase` embeds `AppTopBar`, which is a **Navigation** group widget not yet shipped as an App widget (`app_topbar.dart` does not exist). Decision: author a minimal **showcase-local** top-bar mock inside `app_shell_showcase_section.dart` (a `Column`/`Row` of breadcrumb + branch switcher + user avatar reused from existing App widgets `AppBreadcrumb`, `AppBranchSwitcher`, `AppAvatar`) so the AppShell demo can render without waiting on the full Navigation milestone. Mark the `app-topbar` dependency as out-of-scope (§7). This keeps Phase 2 shippable independently.

10. **Runtime-error regressions to avoid in this group (from `ui-runtime-errors.md`):**
   - **#8 `BoxConstraints forces an infinite height` / #19 timeline Stack** — the design-system page is `SingleChildScrollView` → `Column` (unbounded max height). `AppAppShell` is a `Row` with `crossAxisAlignment: stretch` that **must** receive bounded height. The web demo wraps it in `h-[32rem]` (a fixed 32rem height box). **Flutter port MUST wrap the live shell demo in an explicit `SizedBox(height: 512)`** (32rem ≈ 512px) before `AppAppShell`. Do **not** let `AppAppShell` size itself from its parent `Column` — it will collapse or assert.
   - **#15 `RenderFlex` unbounded width + `Expanded`** — `AppAppShell`'s `main` uses `Expanded(flex:1)` inside a `Row`. The outer `SizedBox(height: 512)` gives bounded height; the `Row`'s cross axis is bounded by that height. The `Row`'s main axis (width) is bounded by the parent demo card width. Safe — but only because of the explicit height wrapper. Verify in `flutter run`.
   - **#18 `InkWell` hover invisible on decorated surfaces** — none of the four new wrappers use `InkWell`; they are slot-only. The `AppBulkActionBar` (existing) uses `DecoratedBox` + `Wrap` and is fine. Do not introduce `InkWell` on `AppAppShell`/`AppToolbar`/`AppPageHeader`/`AppSectionHeader`.
   - **#21 pill stretches full width** — not relevant (no chips/badges authored here), but the `Wrap` end-slot in `AppToolbar` and `AppBulkActionBar` must keep `mainAxisSize: MainAxisSize.min` on inner action rows. Existing `AppBulkActionBar` already does. `AppToolbar` must follow the same pattern: outer `Wrap(alignment: spaceBetween)` with inner `Wrap(mainAxisSize: min)` for `start` and `end` slots, so the bar hugs the available width without forcing stretch.
   - **Checklist items 1–9 (Inputs/Display)** — none of the four new wrappers embed `TextField`/`Slider`/`DropdownButton`/`AppPopover`/`Tooltip`/date-formatting/`Focus`+`TextField`/focus ring. The only `Material`-ancestor risk is if a demoed child (e.g. `AppButton`, `AppSearchInput`) is placed inside a fully transparent `DecoratedBox` shell — these widgets already bring their own `Material`/`InkWell` and are safe; the new wrappers must NOT wrap children in an opaque `DecoratedBox` that paints above `Material`. Use `Material(color: Colors.transparent, child: …)` if a tinted surface is required (it is not for these four — they are layout-only).

## 1. Existing App assets to reuse (do not recreate)

| Asset | Path | Used by |
|---|---|---|
| `AppBulkActionBar` | `core/ui/components/app_bulk_action_bar.dart` | bulk-action-bar showcase (direct reuse) |
| `AppScrollArea` | `core/ui/components/app_scroll_area.dart` | layout-scroll-area showcase (direct reuse, different `id` from display's `scroll-area`) |
| `AppResizablePanels` | `core/ui/components/app_resizable_panels.dart` | layout-resizable showcase (direct reuse, different `id` from display's `resizable-panels`) |
| `AppButton` | `core/ui/components/app_button.dart` | page-header, section-header, toolbar, bulk-action-bar, app-shell demos |
| `AppBreadcrumb` | `core/ui/components/app_breadcrumb.dart` | page-header + app-shell demos |
| `AppTabs` | `core/ui/components/app_tabs.dart` | page-header + app-shell demos |
| `AppSidebar` | `core/ui/components/app_sidebar.dart` | app-shell demo |
| `AppBranchSwitcher` | `core/ui/components/app_branch_switcher.dart` | app-shell demo (top-bar mock) |
| `AppAvatar` | `core/ui/components/app_avatar.dart` | app-shell demo (top-bar mock) |
| `AppSkeleton` | `core/ui/components/app_skeleton.dart` | app-shell demo placeholder content |
| `AppSearchInput` | `core/ui/components/app_search_input.dart` | toolbar demo |
| `AppChip` | `core/ui/components/app_chip.dart` | toolbar demo |
| `AppTooltip` | `core/ui/components/app_tooltip.dart` | (available; not strictly required here) |
| Theme: `context.appColors`(`AppSemanticColors`), `AppSpacing`,`AppRadius`,`AppTypography`,`AppElevation` | `core/ui/theme/*` | every widget |
| `devPreviewProvider` | `features/design_system/presentation/providers/dev_preview_provider.dart` | EN/AR copy + `Directionality`awareness |
| Showcase primitives: `ShowcaseSection`,`ShowcaseDemoGrid`,`ShowcaseDemo`,`ShowcaseVariantMatrix`,`PlaceholderSection` | `components/showcase_primitives.dart` | every showcase section |
| Wiring: `component_registry.dart`,`component_section_builders.dart`,`components_content.dart` | `components/` | one-line registration per widget |

## 2. New shared abstractions to introduce (prefix per phase)

| File (`lib/core/ui/components/`) | Export name | Web analog | Purpose | Phase |
|---|---|---|---|---|
| `app_page_header.dart` | `AppPageHeader` | `PageHeader` | header slot composition: breadcrumb + (title + description) | actions slot | tabs slot. | 1 |
| `app_section_header.dart` | `AppSectionHeader` | `SectionHeader` | sub-section header: `text-overline` title + description | actions. | 1 |
| `app_toolbar.dart` | `AppToolbar` | `Toolbar` | horizontal toolbar slots `start` / `center` / `end`, optional `sticky`. | 1 |
| `app_app_shell.dart` | `AppAppShell` | `AppShell` | sidebar | topBar | main(scroll, `max-w-6xl` gutter) | optional commandBar slots; `fullWidth` + `contentClassName`-equivalent. | 2 |

Plus a **showcase-only local** (NOT exported via `widgets.dart`):
| File (`features/design_system/presentation/components/layout/`) | Export name | Purpose | Phase |
|---|---|---|---|
| `nav_model_mock.dart` | `mockOrg`,`mockBranches`,`mockUser`,`mockNotificationCount`,`clinicNavGroups`,`clinicNavFooter` | static demo data mirroring web `nav-model.ts` for the AppShell demo only. | 2 |

**Barrel update:** append `app_page_header.dart`, `app_section_header.dart`, `app_toolbar.dart`, `app_app_shell.dart` to `widgets.dart` under a `// Layout & utility` sub-comment. Do **not** re-export `nav_model_mock.dart` — it stays in the showcase folder.

## 3. Phasing

> Rationale: **Phase 1** = the four header/toolbar primitives that have no cross-group navigation dependency (PageHeader + SectionHeader + Toolbar + BulkActionBar — the BulkActionBar App widget already ships; only its section is new). **Phase 2** = the AppShell composition + the layout-group ScrollArea and ResizablePanels demos. AppShell depends on navigation primitives, so it is deferred to Phase 2 alongside the two pure demos to keep Phase 1 shippable on its own. Each phase is independently shippable (registry + builders flip per completed widget).

### Phase 1 — Headers + toolbar + bulk action bar

Widgets: **PageHeader, SectionHeader, Toolbar, BulkActionBar**

| Widget | Flutter widget(s) to create | File(s) | Reuse | Wrapper | Deps |
|---|---|---|---|---|---|
| Page header | `AppPageHeader` | CREATE `components/app_page_header.dart`; MOD `widgets.dart` | `AppTypography`(h1),`AppSpacing`,`Theme.appColors`; accepts `title`,`description?`,`breadcrumb?`,`actions?`,`tabs?` Widget slots | NEW wrapper | none |
| Section header | `AppSectionHeader` | CREATE `components/app_section_header.dart`; MOD `widgets.dart` | `AppTypography.caption`(overline equiv),`AppSpacing`; accepts `title`,`description?`,`actions?` | NEW wrapper | none |
| Toolbar | `AppToolbar` | CREATE `components/app_toolbar.dart`; MOD `widgets.dart` | `AppRadius`,`AppSpacing`,`colors.borderDefault`,`colors.surfaceDefault`; accepts `start?`,`center?`,`end?`,`sticky=false`; `Semantics(container,label:'toolbar')` | NEW wrapper | none |
| Bulk action bar | (existing `AppBulkActionBar`) | reuse `core/ui/components/app_bulk_action_bar.dart` | existing | EXISTING — extend showcase only | none |

Showcase sections (Phase 1), under `features/design_system/presentation/components/layout/`:
`page_header_showcase_section.dart` (`PageHeaderShowcaseSection`), `section_header_showcase_section.dart` (`SectionHeaderShowcaseSection`), `toolbar_showcase_section.dart` (`ToolbarShowcaseSection`), `bulk_action_bar_showcase_section.dart` (`BulkActionBarShowcaseSection`).

### Phase 2 — AppShell + scroll-area + resizable panels

Widgets: **AppShell, ScrollArea (layout), ResizablePanels (layout)**

| Widget | Flutter widget(s) to create | File(s) | Reuse | Wrapper | Deps |
|---|---|---|---|---|---|
| App shell | `AppAppShell` | CREATE `components/app_app_shell.dart`; MOD `widgets.dart` | `colors.surfaceCanvas`,`AppSpacing`; slots `sidebar`,`topBar`,`child`,`commandBar?`,`fullWidth=false`; main uses `SingleChildScrollView` + `ConstrainedBox(maxWidth: fullWidth?double.infinity:1152)` | NEW wrapper | (demo) `AppSidebar`,`AppBreadcrumb`,`AppTabs`,`AppBranchSwitcher`,`AppAvatar`,`AppSkeleton`,`AppButton` |
| Scroll area (layout) | (existing `AppScrollArea`) | reuse `core/ui/components/app_scroll_area.dart` | existing | EXISTING — showcase only | none |
| Resizable panels (layout) | (existing `AppResizablePanels`) | reuse `core/ui/components/app_resizable_panels.dart` | existing | EXISTING — showcase only | none |

Showcase sections (Phase 2), under `features/design_system/presentation/components/layout/`:
`app_shell_showcase_section.dart` (`AppShellShowcaseSection`), `scroll_area_showcase_section.dart` (`LayoutScrollAreaShowcaseSection` — distinct class name from the display `ScrollAreaShowcaseSection`), `resizable_panels_showcase_section.dart` (`ResizablePanelsLayoutShowcaseSection` — distinct from display `ResizablePanelsShowcaseSection`), `nav_model_mock.dart` (constants only).

## 4. Dev-page instantiation spec per widget (mirrors web reference)

> **Binding source of truth:** the per-demo arrangement, slot content, props, labels, copy, and state in each Flutter showcase section **must mirror exactly** how the corresponding showcase in `web-reference/src/showcase/components/layout/<Name>Showcase.tsx` instantiates the web widget. Composer 2.5 must open the referenced `.tsx` and reproduce, demo-for-demo:
> - the number, order, and titles of `ShowcaseDemo` cells (where the web uses `ShowcaseDemo`);
> - the exact slot content (which App widgets fill `breadcrumb`/`actions`/`tabs`/`start`/`end`/`sidebar`/`topBar`);
> - any `ShowcaseVariantMatrix` rows (the web layout showcases do **not** use any variant matrices — every layout section is a single loose demo, not a `ShowcaseDemoGrid`);
> - the bilingual EN/AR copy where the web demo uses titles/descriptions/placeholders/helper text (AR translations follow the existing `_copyEn`/`_copyAr` pattern in `button_showcase_section.dart`).
>
> The Flutter showcase primitives (`ShowcaseSection` / `ShowcaseDemoGrid` / `ShowcaseDemo` / `ShowcaseVariantMatrix`) are 1:1 in shape with the web ones, so the demo structure ports verbatim — only the widget name and slot-prop syntax change.

Per widget (reproduce exactly):

- **Page header** — 1 `ShowcaseDemo` titled "Full composition" with `propsHint="title + breadcrumb + actions + tabs", inside a `w-full rounded-lg border bg-surface-default p-6` wrapper (use `DecoratedBox(border radius lg)` + `Padding(all: 24)`):
  - `breadcrumb` = `AppBreadcrumb` items: `Billing`,`Invoices`,`INV-2026-00482` (last item not navigable)
  - `title` = "Invoice details" (AR: "تفاصيل الفاتورة")
  - `description` = "Review line items, payments, and patient responsibility." (AR: "راجع البنود والمدفوعات ومسؤولية المريض.")
  - `actions` = `Row` of two `AppButton`: secondary "Download PDF" (AR: "تنزيل PDF"), primary "Record payment" (AR: "تسجيل دفعة")
  - `tabs` = `AppTabs` items `overview/payments/history` with controlled `tab` state via `StatefulWidget` (useState mirror)

- **Section header** — single loose demo (no `ShowcaseDemoGrid`) under `ShowcaseSection`:
  - `title` = "Branch configuration" (AR: "إعدادات الفرع")
  - `description` = "Manage services and pricing per branch." (AR: "أدر الخدمات والتسعير لكل فرع.")
  - `actions` = `AppButton(size: AppButtonSize.sm)` "Add service" (AR: "إضافة خدمة")

- **Toolbar / filter bar** — single loose demo:
  - `start` = `Wrap(spacing: 8)` of: `AppSearchInput(placeholder: "Search patients…" / AR: "ابحث عن مرضى…", width: 224)`; `AppChip(selectable:true, selected:true)` "Active" (AR: "نشط"); `AppChip(removable:true, onRemove: noop)` "Downtown" (AR: "وسط البلد")
  - `end` = `AppButton(variant: AppButtonVariant.secondary, size: AppButtonSize.sm, leadingIcon: Icon(Icons.search, size:14))` "Filters" (AR: "تصفية")

- **Bulk action bar** — single loose demo:
  - `count` = 3, `itemLabel` = "invoices selected" (AR: "فواتير محددة")
  - `actions` = `Row`: `AppButton(size:sm, variant:secondary)` "Export" (AR: "تصدير"); `AppButton(size:sm, variant:danger)` "Void" (AR: "إلغاء")
  - `onClear` = noop lambda (matches web `() => undefined`)

- **App shell** — 1 `ShowcaseDemo` titled "Live shell demo" with `propsHint="⌘K · collapse · toggles"`, **wrapped in `SizedBox(height: 512)` + `ClipRRect(radius: 12)` + `DecoratedBox(border, shadow-elevation-2)`** (matches web `h-[32rem] overflow-hidden rounded-xl border shadow` — see §0.10 runtime-error guard #8):
  - state (in `ConsumerStatefulWidget`): `activeId='patients'`, `collapsed=false`, `branchId=mockBranches[0].id`, `tab='overview'`
  - `sidebar` = `AppSidebar(items: clinicNavGroups, footerItems: clinicNavFooter, activeId: activeId, onNavigate: setActiveId, collapsed: collapsed, onToggleCollapsed: toggle, org: mockOrg, branch: branch.name)`
  - `topBar` = local `_LiveTopBarMock` (breadcrumb `Patients / Directory` + `AppBranchSwitcher(branches: mockBranches, currentBranchId: branchId, onBranchChange: setBranchId)` + `AppAvatar` user + a notification badge with `mockNotificationCount`) — see §0.9; no `AppTopBar` App widget yet
  - `child` = `AppPageHeader(title:"Patients" / AR:"المرضى", description:"Manage patient records, demographics, and care history." / AR:"أدارة سجلات المرضى والبيانات الديموغرافية وتاريخ الرعاية.", actions: `AppButton(variant: primary)` "New patient" / AR:"مريض جديد", tabs: `AppTabs` overview/active/archived)` + a `Column` of `AppSkeleton` placeholders (grid 3×h24, h48, h32) mirroring web
  - `commandBar` slot left null (matches web `AppShellShowcase`, which does not pass `commandBar` — only `AppShellWithCommand` does)

- **Scroll area (layout)** — single loose demo:
  - `AppScrollArea(maxHeight: 120)` (web uses 120; display's `scroll-area` demo uses 160 — keep the **120** value to match this group's source of truth)
  - content = `Column(spacing: 8, padding: 16)` of 8 `Text` "Layout scroll item N" (AR: "عنصر تمرير التخطيط N"), `AppTypography.bodySm` + `colors.textSecondary`

- **Resizable panels (layout)** — single loose demo:
  - `AppResizablePanels(start: …, end: …)`
  - `start` = `Padding(all:16)` `Text` "Patient list" (AR: "قائمة المرضى"), `AppTypography.bodySm`
  - `end` = `Padding(all:16)` `Text` "Patient detail" (AR: "تفاصيل المريض"), `AppTypography.bodySm`

## 5. Wiring steps (do after each phase's widgets land)

1. `component_registry.dart` — for each finished `id`, flip `status: ShowcaseSectionStatus.placeholder` → `ShowcaseSectionStatus.ready` (reuse the exact `'id'` strings: `app-shell`,`page-header`,`section-header`,`toolbar`,`bulk-action-bar`,`layout-scroll-area`,`layout-resizable` — already in the file at lines 466–507).
2. `component_section_builders.dart` — add an entry per ready id in `componentSectionBuilders` under a new `// Layout & utility` comment block (mirror the existing `// Data display` block at lines 75–96):
   ```dart
   'page-header': () => const PageHeaderShowcaseSection(),
   'section-header': () => const SectionHeaderShowcaseSection(),
   'toolbar': () => const ToolbarShowcaseSection(),
   'bulk-action-bar': () => const BulkActionBarShowcaseSection(),
   // (Phase 2)
   'app-shell': () => const AppShellShowcaseSection(),
   'layout-scroll-area': () => const LayoutScrollAreaShowcaseSection(),
   'layout-resizable': () => const ResizablePanelsLayoutShowcaseSection(),
   ```
3. Import the new section files at the top of `component_section_builders.dart` grouped under a `// Layout & utility` comment (mirror `// Data display` lines 23–44).
4. Append the new `app_*.dart` core files to the `widgets.dart` barrel under a `// Layout & utility` sub-comment, **after** the existing `// Data display` block (lines 36–53). Do not re-add `app_bulk_action_bar.dart` / `app_scroll_area.dart` / `app_resizable_panels.dart` — already exported there.
5. Run `flutter analyze` (project uses `flutter_lints`) on changed files; fix lints. Do **not** commit unless asked.

## 6. Out-of-scope / defer

- **`AppTopBar` App widget** — not authored here; Phase 2 AppShell demo uses a showcase-local `_LiveTopBarMock`. The real `AppTopBar` belongs to the Navigation milestone.
- **`CommandBar` / `AppShellWithCommand`** — web exports `AppShellWithCommand` (convenience shell with built-in CommandBar). The design-system `AppShellShowcase` does **not** use it (no `commandBar` prop passed), so the Flutter port does not need `AppAppShellWithCommand` for this plan. Defer until the Navigation milestone ships CommandBar.
- **`forui`-based wrappers** in `docs/ui/forui-wrappers.md` — superseded; not built.
- **Refactoring the production `app/shell/layout/app_shell.dart`** — untouched; `AppAppShell` is a separate primitive.
- **`layout-scroll-area` vs display `scroll-area`** and **`layout-resizable` vs display `resizable-panels`** — they share the same App widget but render different demos under different section ids. The display-group sections (`scroll-area_showcase_section.dart`, `resizable_panels_showcase_section.dart`) remain as-is; this plan only adds the two layout-group section files. No deduplication of the App widget is needed.

## 7. Source reference — web widget inventory

The 7 widgets in `web-reference/src/showcase/components/layout/index.ts`:

| id | Title | Showcase file | Underlying UI component |
|---|---|---|---|
| `app-shell` | App shell | `AppShellShowcase.tsx` | `components/layout/AppShell.tsx` |
| `page-header` | Page header | `PageHeaderShowcase.tsx` | `components/layout/PageHeader.tsx` |
| `section-header` | Section header | `LayoutUtilityShowcase.tsx` (`SectionHeaderShowcase`) | `components/layout/SectionHeader.tsx` |
| `toolbar` | Toolbar / filter bar | `LayoutUtilityShowcase.tsx` (`ToolbarShowcase`) | `components/layout/Toolbar.tsx` |
| `bulk-action-bar` | Bulk action bar | `LayoutUtilityShowcase.tsx` (`BulkActionBarShowcase`) | `components/layout/BulkActionBar.tsx` |
| `layout-scroll-area` | Scroll area | `LayoutUtilityShowcase.tsx` (`ScrollAreaLayoutShowcase`) | `components/scroll-area` (Radix `ScrollArea`) |
| `layout-resizable` | Resizable panels | `LayoutUtilityShowcase.tsx` (`ResizablePanelsLayoutShowcase`) | `components/resizable` (Radix `Resizable`) |

Shared web building blocks and their Flutter equivalents (all already shipped — no new primitives needed by this plan):
- `cn` / `motionPresets` — N/A in Flutter (no conditional className; motion tokens via `AppMotion` if needed, but these four wrappers are static).
- Radix `ScrollArea` → existing `AppScrollArea` (`core/ui/components/app_scroll_area.dart`, with `Scrollbar`+`ScrollController` per `ui-runtime-errors.md` #16).
- Radix `Resizable` → existing `AppResizablePanels` (`core/ui/components/app_resizable_panels.dart`).
- `lucide-react` icons (`Search`,`X`) → Material `Icons` equivalents (`Icons.search`,`Icons.close`) — already used by `AppButton` / `AppBulkActionBar`.
- `Skeleton` → existing `AppSkeleton` (`core/ui/components/app_skeleton.dart`).
- `Breadcrumb`,`Tabs`,`AppSidebar` → existing `AppBreadcrumb`,`AppTabs`,`AppSidebar`.
- `Button` → existing `AppButton`.
- `Chip`,`SearchInput` (used by the Toolbar demo) → existing `AppChip`,`AppSearchInput`.

Cross-cutting web notes (inform the Flutter port):
- All four new wrappers are **composition-only** (slot props, no internal state, no controllers, no overlays). Lowest runtime-risk category.
- The only stateful showcase is `AppShellShowcase` (4 `useState` hooks) → mirror with a `ConsumerStatefulWidget` reading `devPreviewProvider` for locale/direction.
- `BulkActionBar`/`Toolbar` use `flex-wrap` → Flutter `Wrap` (already the pattern in `app_bulk_action_bar.dart`); `mainAxisSize: MainAxisSize.min` on inner action rows to honor `ui-runtime-errors.md` #21.
- `AppShell` web uses `h-full min-h-0` + `mx-auto max-w-6xl px-6 py-6` content gutter → Flutter `Expanded` + `SingleChildScrollView` + `ConstrainedBox(maxWidth: fullWidth ? double.infinity : 1152)` + `Padding(all: 24)`. Container height bounded by the demo's `SizedBox(height: 512)` (see §0.10 #8).
- i18n/RTL: layout wrappers are direction-agnostic; only the showcase copy is bilingual. `Directionality.of(context)` drives inset mirroring in `AppToolbar`'s `ms-auto` end slot → use `Directionality`-aware `EdgeInsetsDirectional` / `Wrap` `alignment`.