# Implementation Plan — Invoices page (web-reference → Flutter port)

Spec target: port the **Invoices** page at `web-reference/src/pages/app/invoices/InvoicesPage.tsx` into the Flutter `frontend/` billing feature, surfaced as the existing `/billing/invoices` route (V1-6 US5). An existing UI implementation already lives at `frontend/lib/features/billing/presentation/pages/invoice_list_page.dart` (search input + status-chip row + custom card-list). **Replace** the parts the new web reference designs (page header, `ListControlBar`, `FilterMenuPanel`, `DataTable` + column set, `Pagination`, empty states) with App-abstraction ports, and **redesign** the parts the billing feature addresses that the web reference does not cover for this page (auth-scoped branch filtering, extended `InvoiceListItem` with `patientId`/`patientMrn`/`branchId`, server-side sort/filter/pagination, row context menu with invoice-specific actions, AR strings pass-through). Split into **3 phases**.

This is a feature-page port (like `patients-page-implementation-plan.md`), **not** a Dev components-showcase group — so there is **no** `component_registry.dart` / `component_section_builders.dart` work for the page itself. The two new App-abstraction layers introduced along the way (`AppListControlBar`, `AppFilterMenuPanel`) are added to `widgets.dart` only; registry placeholders for `list-control-bar` / `filter-menu-panel` do **not** currently exist, so no Dev-showcase wiring is required (see §6).

## 0. Ambiguities & Design Decisions (resolve before coding)

> ⚠️ **Set-specific runtime regressions.** The invoices page embeds `AppSearchInput` (debounced), `AppPopover`-backed `FilterMenuPanel` and `Sort` dropdown (`AppMenu`/`MenuAnchor`), `AppDataTable` (Syncfusion grid) with a `MenuAnchor`-driven row-context-menu, optional `AppSelect` for page-size, debounced RPC search/filter, and a motion enter `FadeTransition`. Before coding, confirm the regressions to avoid (consult `docs/ui/memory/ui-runtime-errors.md` only when explicitly instructed):
> - **#1 / #5 / #23** — the `FilterMenuPanel` popover content and the `Sort` `MenuAnchor` live inside `AppPopover` shells over a `DecoratedBox` bar. Wrap actionable list options in `Material(color: transparent)` (or drive hover with `MouseRegion` + `AnimatedContainer`) so the inner `InkWell`/`TextButton` hit affordance and the `MenuAnchor` have a Material ancestor. Do **not** nest a bare `TextField` in either shell (none is required here).
> - **#2 / #10 / #12 / #13** — the page rebuilds on every search keystroke + filter popover change. `AppPopover`/`AppMenu` already guard rebuild-during-open (detach/refresh guards). Route search/sort/filter updates through `invoiceListNotifier.applyFilters` (debounced via `AppSearchInput`) and let the overlay settle — do **not** synchronously mutate overlay state from `didUpdateWidget`.
> - **#3** — `AppMoneyDisplay` formats with explicit `en_EG` locale; date formatting via `BillingFormatting.formatDate` uses `intl` `DateFormat`. `ensureIntlDateFormattingInitialized()` must run at app startup (already wired — verify still called from `main.dart`).
> - **#4 / #11** — the row-context-menu trigger is a tertiary-tap/keyboard-action on the row itself; use a single `FocusNode` on the `MenuAnchor`/`Actions` cell, dispose in `dispose`. Do **not** place a `Tooltip` or `MenuAnchor` inside the `FilterMenuPanel` popover children.
> - **#8 / #30** — the page body sits in `AppShell` → scroll view → `Column`. Use `CrossAxisAlignment.start` (not `stretch`) and guard the `Column` with `mainAxisSize: min` + `LayoutBuilder` so the outgoing page does not crash during route transition when the shell passes unbounded height (memory #30 — `fillViewport`/`effectiveFillViewport`).
> - **Async DataTable + NullMoney columns** — `AppMoneyDisplay` requires `double`. `InvoiceListItem.subtotal`/`paidAmount`/`balance` are `Money`. Use `money.wireValue as double` (or expose a `Money.toDouble`) and pass `negative: amount < 0` explicitly to avoid relying on the `negative ?? amount < 0` fallback when the bare `Money` is a non-double source.
>
> Memory "Checklist for new input components" items 1, 4, 5, 6, 7, 8 apply to the `FilterMenuPanel`/`Sort` menu (popover-hosted, driven inside a `DecoratedBox` bar). Items 1, 4 of the shell/placeholder checklist (#28/#30) apply to the page column + transition.

Other decisions:

1. **forui vs native Material** — native Material only; `forui-wrappers.md` is superseded. All controls reuse the shipped `App*` widgets; no `forui` import.
2. **File layout** — feature-page tree under `frontend/lib/features/billing/presentation/`:
   - `pages/invoice_list_page.dart` — **MODIFY** the existing `/billing/invoices` route widget: replaces the custom card-list + status-chip row with the new `AppListControlBar` + `AppFilterMenuPanel` + `AppDataTable` + `AppPagination` layout.
   - `widgets/invoice_list_controls.dart` — **CREATE** — wraps `AppListControlBar` (search + sort dropdown + filter popover button + active-filter chip strip); the page owns the `InvoiceListControls` state and passes patches to `invoiceListNotifier.applyFilters`. Billing-specific: hides the **Branch** filter popover section when the auth session exposes only one branch (`branchIds.length <= 1`).
   - `widgets/invoice_row_context_menu.dart` — **CREATE** — `MenuAnchor`-based row actions menu (Open invoice / View patient / void invoice when `status.isVoidable`). Mirrors `patient_row_context_menu.dart` (`AppMenuEntry` → `MenuItemButton` mapping).
   - `widgets/invoice_table.dart` — **CREATE** — the `AppDataTable<InvoiceListItem>` wrapper with the six web columns (Invoice, Patient, Status, Subtotal, Total payments, Remaining), row click → `AppNavigator.pushBillingInvoiceDetail`, row context-menu via `rowActions` returning an `InvoiceRowContextMenu` trigger.
   - `models/invoice_list_controls.dart` — **CREATE** — page-local control state model (search, `status: InvoiceStatus?` (single-select, mirroring web), `branch: String?`, `sort: InvoiceSortKey`), mapping to the backbone `InvoiceListFilters` via `toBackendFilters()` (status single → `statuses: [status]`; branch → `branchId`; sort → backend sort field). Defaults: `{ search: '', status: null, branch: null, sort: .dateDesc }`.
   - `models/invoice_sort_key.dart` — **CREATE** — enum of the 6 web sort keys (`dateDesc/Asc, balanceDesc/Asc, amountDesc/Asc`) with a `backend rpcSort` mapping (the existing `InvoiceListFilters` does **not** yet expose a sort field; this phase adds it, see §3 phase 2).
   - `providers/branch_id_options_provider.dart` — **CREATE optional, MVP skip** — when the auth session exposes multiple branches and you want labels (`Branch A`) instead of `branchId`s in the active-filter chip, resolve `listBranchesUseCaseProvider` to a `{branchId → name}` map. Defer until the branch-switcher hook can be verified (§6).
   - **App–layer additions** under `frontend/lib/core/ui/components/` (Phase 1):
     - `app_list_control_bar.dart` — `AppListControlBar` (web `ListControlBar`).
     - `app_filter_menu_panel.dart` — `AppFilterMenuPanel` (web `FilterMenuPanel`).
3. **Replace vs redesign** (per the user instruction):
   - **Replace** (web reference wins): drop the existing custom `_InvoiceLedgerList` (card list with left status stripe) and the existing `_StatusFilterRow` (multi-status toggle chips). Rebuild with `AppListControlBar` (search + sort dropdown + filter popover) + the six-column `AppDataTable` + `AppPagination`.
   - **Redesign** (billing-specific additions the web reference does not cover):
     - **Branch section gating** — the web `FilterMenuPanel` always renders the Branch section from `MOCK_BRANCHES`. Billing derives branches from `authSessionProvider.context.branchIds`; the section is rendered only when `branchIds.length > 1`. When hidden, do **not** show the "Branch" active-filter chip either.
     - **Voided balance emphasis** — web paints the Remaining cell green when `balance <= 0`. For `voided` invoices the remaining is structurally `0` but should **not** read as "paid-green". Add `InvoiceStatus.voided` check to the green rule: `green iff balance <= 0 && status != voided`; for voided, render the amount in `colors.textTertiary`.
     - **Row context menu extension** — web lists only `Open invoice` and `View patient`. Billing additionally surfaces **Void invoice** (when `status.isVoidable`) directly on the row, to short-circuit the detail page. The action opens the existing `VoidInvoiceDialog` (`widgets/void_invoice_dialog.dart`) in a confirm flow, then `paymentNotifier.voidInvoice(...)` / `invoiceDetailProvider.invalidate(...)`, and `invoiceListNotifier.reload()` on success.
     - **Empty state copy** — first-run uses the web text "Invoices appear here once a completed visit is billed."; no-results matches web text. Both already matched by `AppEmptyStateVariant.firstRun`/`noResults`.
     - **Net payments styling** — web colours `paidAmount <= 0` as `textTertiary`, else `textSecondary`. We replicate directly.
4. **Polling granularity** — `AppListControlBar.sortOptions`, `FilterMenuPanel.sections`, and the active-filter chip list are derived from `models/invoice_list_controls.dart` `InvoiceListControls`; the page state owns the canonical copy and the controls bar is a pure function of it + callbacks (no internal controls-bar state).
5. **Sort wiring** — `InvoiceListFilters` does not yet have a `sort` field. Add `InvoiceSortField` (server-side: `created_at`, `balance`, `subtotal`) + `sortDirection` to the filters and to `toRpcFilters()` outputs (`sort_field`, `sort_direction`). The RPC `list_invoices` is expected to honour them (verify via `invoice_repository.dart`; if backend support is missing, document as deferred in §6 and fall back to client-side sort over the loaded page — but ship the UI fully).
6. **Search debounce** — `AppSearchInput` already debounces `onValueChange` (300 ms default, configurable `debounceMs: 250`). Wire `onValueChange → applyFilters(controls.copyWith(search: …, page: 1))`. Do not roll a second debounce layer.
7. **Single-select status** — the web reference uses single-select (`all | draft | issued | partially_paid | paid | voided`) in the `FilterMenuPanel`, while the existing billing widget used a multi-status toggle row. Switch to **single-select** to match the new design. Backend filter maps `status` → `statuses: [status.wireValue]` (the existing backend `list_invoices` already accepts a `statuses` array), so no backend change is needed.
8. **Pagination** — web slices in-memory; billing paginates server-side via `invoiceListProvider` (`limit`/`offset`/`hasMore`). `AppPagination` binds to `InvoiceListUiState.estimatedTotal` + `filters.page`/`pageSize`; changing page/pageSize → `applyFilters`. Default `pageSize = 10` (web), expose `pageSizeOptions: [10, 25, 50]`.
9. **Active-filter chips** — three removable chips aligned to web: `status` (labelled via `InvoiceStatus.label`), `branch` (labelled via branch-name lookup; falls back to `branchId`), `search` (labelled `"Search: <q>"`). The Clear-all action calls `applyFilters(InvoiceListControls.initial.toBackendFilters())`.
10. **AR / i18n** — EN-only copy for this port (matches patients-page / settings-page plans). All strings hard-coded EN via the existing convention; AR strings land with the future l10n milestone (§6). Widgets stay direction-agnostic via `Directionality.of(context)`; `AppMoneyDisplay` already forces `Directionality.ltr` for the numeric span, mirroring web `dir="ltr"` on amount cells.
11. **Motion** — keep the existing `FadeTransition(opacity: _enterAnimation)` 220 ms page enter (web uses `motion.div` initial `{opacity:0, y:6}` → `animate {opacity:1, y:0}`; the existing controller already matches within Material's `CurvedAnimation(outCurve)`). Drop the `y` translate delta (the Slate shell renders within a fixed viewport, and a vertical translate at root causes a 1-frame overflow with `mainAxisSize.min` column under unbounded height; matches memory #30 guidance).
12. **Existing page kept binary-compatible** — the existing `invoice_list_page.dart` already exposes `InvoiceListPage` and is referenced by the billing router. Modify it in place; do not change the route name or constructor.

## 1. Existing App assets to reuse (do not recreate)

| Asset | Path | Used by |
|---|---|---|
| `AppPageHeader` (`title`, `description`, `actions`) | `core/ui/components/app_page_header.dart` | page header ("Invoices" + "Every invoice for this branch — status, payments collected, and what's still owed.") |
| `AppSearchInput` (`controller`/`value`, `onValueChange`/listener, `placeholder`, `debounceMs`) | `core/ui/components/app_search_input.dart` | controls-bar search (debounced → notifier) |
| `AppButton` (`secondary`, `ghost`, `leadingIcon`, `size`) | `core/ui/components/app_button.dart` | Sort/Filter buttons in `AppListControlBar`; "Clear filters" affordance in the bar footer |
| `AppMenu`/`AppContextMenu`/`AppMenuEntry` | `core/ui/components/app_menu.dart` | row context menu (Open / View patient / Void invoice) + Sort dropdown |
| `AppPopover` (`trigger`, `content`, `align: .end`) | `core/ui/components/app_popover.dart` | Filter popover wrapping `AppFilterMenuPanel` |
| `AppChip` (`removable`, `onRemove`, `child`) | `core/ui/components/app_chip.dart` | active-filter chips |
| `AppDataTable<T>` (`columns`, `data`, `getRowId`, `onRowClick`, `rowActions`, `loading`, `loadingRows`, `emptyState`, `errorState`, `footer`, `animateRows`, `ariaLabel`) | `core/ui/components/app_data_table.dart` | the invoices ledger table |
| `AppPagination` (`page`, `pageSize`, `total`, `onPageChange`, `onPageSizeChange`, `pageSizeOptions`) | `core/ui/components/app_pagination.dart` | list pagination (server-backed `estimatedTotal`) |
| `AppEmptyState` (`variant: firstRun`/`noResults`/`error`, `title`, `description`, `action`) | `core/ui/components/app_empty_state.dart` | "No invoices yet" + "No invoices match" + error retry |
| `AppAvatar` (`name`, `size: .sm`) | `core/ui/components/app_avatar.dart` | the Patient cell leading avatar (initials fallback) |
| `AppBadge` (`variant: .soft`, `color`, `size: .sm`) | `core/ui/components/app_badge.dart` | the Status cell (via existing `InvoiceStatusBadge`) |
| `AppMoneyDisplay` (`amount`, `currency`, `emphasis`, `negative`) | `core/ui/components/app_money_display.dart` | Subtotal / Total payments / Remaining columns |
| `AppIconButton` (`ghost`, `sm`, `icon`, `label`) | `core/ui/components/app_icon_button.dart` | context-menu trigger if it surfaces as a "more" slot; prev/next page (already used by `AppPagination`) |
| Theme: `context.appColors`, `AppSpacing`, `AppRadius`, `AppTypography`, `AppElevation` | `core/ui/theme/*` | every region |
| `AppMotion`, `FadeTransition`, `AppMotionPreset.fade` | `core/ui/motion/app_motion.dart` | page enter |
| `invoiceListProvider`/`InvoiceListUiState`/`InvoiceListNotifier` | `features/billing/presentation/providers/invoice_list_notifier.dart` | list load/filter/paginate (server-side) |
| `InvoiceListFilters` | `features/billing/presentation/models/invoice_list_filters.dart` | backbone filter state (extend with `sortField`/`sortDirection`) |
| `InvoiceListItem`, `InvoiceStatus`, `Money` | `features/billing/domain/*` | row data (extend `InvoiceListItem` with `patientId`/`patientMrn`/`branchId`) |
| `BillingFormatting.formatDate`/`formatMoney`/`invoiceDisplayNumber` | `features/billing/presentation/utils/billing_formatting.dart` | table cell formatting |
| `InvoiceStatusBadge`, `VoidInvoiceDialog`, `paymentNotifier`/`invoiceDetailProvider` | `features/billing/presentation/widgets/...`, `.../providers/...` | status badge cell, void action |
| `authSessionProvider` (`context.branchIds`, `context.activeBranchId`) | `app/providers/auth_session_provider.dart` | branch-filter gating + provider dependency |
| `App Navigator` (`pushBillingInvoiceDetail`, `pushPatientDetail`) | `app/navigation/app_navigator.dart` | row click + context-menu navigation |
| `devPreviewProvider`, `commandBarController`, `commandBarRegistry` | `features/design_system/presentation/providers/...`, `.../components/...` | optional Quick-bar "Invoices" entry already exists — no change |

## 2. New shared abstractions to introduce

| File (`lib/core/ui/components/`) | Export name | Web analog | Purpose | Phase |
|---|---|---|---|---|
| `app_list_control_bar.dart` | `AppListControlBar` + `AppSortOption`, `AppActiveFilter` | `web-reference/src/components/layout/ListControlBar.tsx` | rounded, branded-gradient bar hosting `AppSearchInput` (flex-1) + a 🟦 Filter `AppPopover` button (with a numeric active-count badge) + a Sort `AppMenu`/`MenuAnchor` trigger, plus an animated `activeFilters` chip strip footer (`VerticalDirection` collapsed-row on `activeFilters.isNotEmpty`); `onClearFilters` and `onClearAll` callbacks; reduced-motion gated. | 1 |
| `app_filter_menu_panel.dart` | `AppFilterMenuPanel` + `AppFilterMenuOption`, `AppFilterMenuSection` | `web-reference/src/components/layout/FilterMenuPanel.tsx` | vertical listbox of `sections: List<AppFilterMenuSection>`; `option.value == section.value` selects (Check icon + `surfaceSelected` bg + medium weight); thin `Divider` between sections; overline label per section; used inside the `AppPopover` content slot of the bar. | 1 |

**Barrel update:** append both files to `lib/core/ui/widgets/widgets.dart` under the existing `// Layout & utility` sub-comment (mirrors `app_page_header.dart` / `app_section_header.dart` / `app_toolbar.dart` placement).

No other App-layer additions are required: `AppDataTable` is extended (not replaced) in Phase 2 to accept per-row context-menu entries via the existing `rowActions` slot returning an `InvoiceRowContextMenu` `MenuAnchor`-wrapped trigger (pattern already shipped in `features/patients/presentation/widgets/patient_row_context_menu.dart` — no API change to `AppDataTable` itself).

## 3. Phasing

> Rationale: **Phase 1** = the two reusable App-aspect wrappers (`AppListControlBar`, `AppFilterMenuPanel`) — no billing domain change, no page wiring (it only lands when Phase 2's domain model + notifier changes ship). **Phase 2** = the billing-feature data layer extensions (extended `InvoiceListItem`, single-select `status`, new `sort` field, branch gating) + the new `InvoiceListControls` page model + the rewritten `invoice_list_page.dart` body with the controls bar + filtered dataTable + pagination — the visible redesign. **Phase 3** = the row context menu, Void action, toast-on-success, polish (animated chip strip + reduced-motion + tabular figures), and end-to-end analyzer pass. Each phase is independently shippable; Phase 2 is the user-visible release, Phase 3 the completion pass.

### Phase 1 — Shared `AppListControlBar` + `AppFilterMenuPanel`

| Widget | Flutter widget(s) to create | File(s) | Reuse | Wrapper | Deps |
|---|---|---|---|---|---|
| List control bar | `AppListControlBar` + `AppSortOption`, `AppActiveFilter` | CREATE `core/ui/components/app_list_control_bar.dart`; MOD `widgets.dart` (barrel) | `AppSearchInput`, `AppButton` (Filter + Clear-filter), `AppPopover` (Filter content slot), `AppMenu`/`AppMenuEntry`/`AppMenuItem` (Sort dropdown trigger + list), `AppChip` (removable, in active-filter strip), `AppBadge`-style count circle, `context.appColors`, `AppSpacing`, `AppRadius`, `AppTypography`, `AppElevation`, `AppMotion` (`prefersReducedMotion`, `animatedPreset`) | NEW | `AppSearchInput`, `AppPopover`, `AppMenu`, `AppChip`, `AppButton` |
| Filter menu panel | `AppFilterMenuPanel` + `AppFilterMenuSection`, `AppFilterMenuOption` | CREATE `core/ui/components/app_filter_menu_panel.dart`; MOD `widgets.dart` (barrel) | `AppMenu`'s row affordance look (`InkWell`/`TextButton` ripple over a `Material(color: transparent)` cell), `Icon(Icons.check, size:14)` for selected option, `AppDivider` between sections, `AppTypography.overline` for section label, theme tokens | NEW | none |

Behaviour to mirror verbatim from web `ListControlBar.tsx`:
- Bar uses a `BoxDecoration` with `border border-borderSubtle`, rounded `AppRadius.x2l`, gradient background using `colors.surfaceDefault` → a teal tint (web `linear-gradient(180deg, surface-default, color-mix(teal-50 35%, surface-default))`; port via a `LinearGradient` with `colors.surfaceDefault` + a faint `colors.accentTealTint` if exposed, else a flat `colors.surfaceMuted`), `elevation: AppElevation.level1` (`boxShadow: shadows1`).
- Inner padding `AppSpacing.space4` (sm) / `space5` (md+) ``; controls in `Row` with `SearchInput`Expanded(flex-1) + a `shrink-0` `Wrap` of Filter + Sort `AppButton`s.
- Filter `AppButton` shows `SlidersHorizontal`-equivalent `Icon(Icons.tune, size: 15)` `leadingIcon`, label "Filter", and a 20×20 active-count badge when `filterActiveCount > 0` (`colors.actionPrimary` bg / `colors.actionPrimaryFg` text, 10px bold).
- Sort `AppButton` shows `ArrowUpDown`-equivalent `Icon(Icons.swap_vert, size: 15)` `leadingIcon`, label "Sort"; a tiny `colors.actionPrimary` 6×6 dot appears top-end when `sortValue != defaultSortValue`.
- Sort `AppMenu` lists `sortOptions` with a `Check` icon on the selected one and a `Clear sorting` separator entry when sortable.
- Active-filter strip animates open/close height on `activeFilters.isNotEmpty` (`AnimatedSize` + `AnimatedSwitcher` + `FadeTransition`); reduced-motion gate (`AppMotion.prefersReducedMotion(context)`) collapses the animation.
- "Clear all" is a ghost `TextButton` aligned to the trailing edge of the strip; appears only if `hasActiveFilters && onClearAll != null`.

### Phase 2 — Billing domain/data + redesigned `InvoiceListPage` body

| Widget / change | Flutter widget(s) to create/modify | File(s) | Reuse | Wrapper | Deps |
|---|---|---|---|---|---|
| Extended `InvoiceListItem` | add `patientId: String?`, `patientMrn: String?`, `branchId: String?` to existing model + `fromRow` mapping | MOD `features/billing/domain/invoice_list_item.dart` | `fromRow` parsing | extend existing | none |
| Sort on `InvoiceListFilters` | add `sortField: InvoiceSortField?`, `sortDirection: SortDirection` (reuse existing `SortDirection` enum already imported in app_data_table.dart or define a small enum) | MOD `features/billing/presentation/models/invoice_list_filters.dart` + CREATE `models/invoice_sort_key.dart` (UI-side enum of 6 keys mapping to `(InvoiceSortField, SortDirection)`) | none | extend existing | backend `list_invoices` must honour `sort_field`/`sort_direction` (verify in `invoice_repository.dart`); if absent, document defer + apply client-side sort over the loaded page (see §6) |
| Notifier wires new controls | optional single public `applyControls(InvoiceListControls)` that maps controls → filters; or keep `applyFilters(InvoiceListFilters)` and let the page map controls | MOD `features/billing/presentation/providers/invoice_list_notifier.dart` | existing | extend | none |
| `InvoiceListControls` UI model | `InvoiceListControls` (`search`, `status: InvoiceStatus?`, `branch: String?`, `sort: InvoiceSortKey`) + `default`, `toBackendFilters({required bool multiBranch})` (drops `branch` when `!multiBranch`), `activeFilters` derivation | CREATE `features/billing/presentation/models/invoice_list_controls.dart` | `InvoiceListFilters`, `InvoiceStatus`, `InvoiceSortKey` | NEW | `InvoiceListFilters`, `InvoiceSortKey` |
| Branch filter gating | provider that exposes the list of selectable branches `{branchId, name}` from `listBranchesUseCaseProvider` filtered by `authSessionProvider.context.branchIds`; or expose `branchIds.length > 1` boolean + read names lazily on demand | REUSE `listBranchesUseCaseProvider` (verify present); otherwise derive labels from `authSessionProvider.context.branchIds` with `branchId` only | `authSessionProvider`, `listBranchesUseCaseProvider` (existing) | none | existing providers |
| Controls bar widget | `InvoiceListControlsBar` (renders `AppListControlBar` with bound `sortOptions: InvoiceSortKey.options`, `statusOptions: [All, ...InvoiceStatus.values]`, `branchOptions: [All, ...branches]`; hides `branch` section when single-branch) | CREATE `features/billing/presentation/widgets/invoice_list_controls.dart` | `AppListControlBar`, `AppFilterMenuPanel` | NEW (composition only) | Phase 1 |
| Table wrapper | `InvoiceLedgerTable` (`AppDataTable<InvoiceListItem>`, six columns Invoice/Patient/Status/Subtotal/Total payments/Remaining, row click → detail, `rowActions` slot left empty in Phase 2; populated in Phase 3 with the row-context menu `MenuAnchor` trigger) | CREATE `features/billing/presentation/widgets/invoice_table.dart` + the six column-accessor builders | `AppDataTable`, `AppAvatar`, `AppBadge` (via `InvoiceStatusBadge`), `AppMoneyDisplay`, `BillingFormatting`, `appColors` | NEW | Phase 1 |
| Rewritten page body | `InvoiceListPage` (existing): replace the search `AppSearchInput` + `_StatusFilterRow` + `_InvoiceLedgerList` with `InvoiceListControlsBar` + `InvoiceLedgerTable` (+ `AppEmptyState` first-run / no-results / error and `AppPagination`). Keep the existing `FadeTransition` page enter. | MOD `features/billing/presentation/pages/invoice_list_page.dart` | `AppPageHeader`, `AppListControlBar` (via `InvoiceListControlsBar`), `AppDataTable` (via `InvoiceLedgerTable`), `AppPagination`, `AppEmptyState`, `invoiceListProvider`, `authSessionProvider` | extend existing | Phase 1 + Phase 2 model changes |

Column set to reproduce exactly (web `columns` const, `InvoicesPage.tsx:37–101`):

| # | `TableColumn.id` | `TableColumn.header` | `TableColumn.align` | Cell composition (port mapping) |
|---|---|---|---|---|
| 1 | `number` | "Invoice" | start | `Column(crossAxisAlignment.start)` with mono Invoice number (`BillingFormatting.invoiceDisplayNumber(item.invoiceNumber, item.id)`, `AppTypography.mono`, letterSpacing `0.04em`, `tabularFigures`) on line 1, `BillingFormatting.formatDate(item.issuedAt ?? item.createdAt)` `textCaption` `textText3` on line 2. |
| 2 | `patient` | "Patient" | start | `Row` with leading `AppAvatar(name: patientDisplayName ?? '', size: .sm)` + `Column`: bold patient name (`AppTypography.bodyStrong`) + caption MRN (`item.patientMrn ?? '—'`). |
| 3 | `status` | "Status" | start | `InvoiceStatusBadge(status: status, size: .sm)` (web uses `Badge color={invoiceStatusColor(status)} variant="soft"`; the existing badge already maps billing statuses → soft badge colours and adds an icon — a billing-side augmentation; keep it as the redesign naïve was web-only with no icon). |
| 4 | `subtotal` | "Subtotal" | end | `AppMoneyDisplay(amount: subtotal.wireValue, currency: item.currency)`. |
| 5 | `payments` | "Total payments" | end | `AppMoneyDisplay(amount: paidAmount.wireValue, currency: item.currency, negative: false)` wrapped in `DefaultTextStyle.override(color: paidAmount <= 0 ? colors.textTertiary : colors.textSecondary)`. |
| 6 | `remaining` | "Remaining" | end | `AppMoneyDisplay(amount: balance.wireValue, currency: item.currency, emphasis: balance > 0 && status != voided, negative: balance < 0)`; for `status == voided` override color to `colors.textTertiary` (billing extension per §0.3 web design decision). |

Row click: `onRowClick: (item) => AppNavigator.of(context).pushBillingInvoiceDetail(item.id)`.
`ariaLabel: 'Invoices'`. `animateRows: true` (matches web).

### Phase 3 — Row context menu, Void action, polish

| Widget / change | Flutter widget(s) | File(s) | Reuse | Wrapper | Deps |
|---|---|---|---|---|---|
| Row context menu | `InvoiceRowContextMenu` (`MenuAnchor` with `menuChildren` built from `AppMenuEntry` → `MenuItemButton` mapping, mirroring `patient_row_context_menu.dart`); `rowActions` cell of `AppDataTable` returns this trigger `AppIconButton` (`Icons.more_horiz`, ghost, sm, label "Row actions") | CREATE `features/billing/presentation/widgets/invoice_row_context_menu.dart`; MOD `invoice_table.dart` to return the trigger from `rowActions` | `AppMenu`, `AppMenuEntry`, `MenuItemButton`, `AppIconButton`, `AppNavigator` (`pushBillingInvoiceDetail`, `pushPatientDetail`), `VoidInvoiceDialog`, `paymentNotifier` | NEW | Phase 2 |
| Row context menu entries (per web rowContextMenu + billing extension) | `Open invoice` (`Icons.open_in_new`, → `pushBillingInvoiceDetail(item.id)`); `View patient` (`Icons.person_outline`, → `pushPatientDetail(item.patientId ?? '')`, disabled when `patientId == null`); `AppMenuSeparator`; `Void invoice` (destructive, `Icons.delete_outline`, enabled iff `item.status.isVoidable`, opens `VoidInvoiceDialog` → on confirm calls `ref.read(paymentNotifierProvider.notifier).voidInvoice(...)` then `ref.invalidate(invoiceListProvider)`) | inline in `invoice_row_context_menu.dart` | `AppMenuEntry` subclasses | extend | existing `VoidInvoiceDialog` |
| Toast on Void success | `appToast(context, AppToastInput(variant: success, message: 'Invoice voided.'))` | inline in `invoice_row_context_menu.dart` | `AppToast` | reuse | existing `AppToastHost` |
| Polish: animated active-filter strip | verify `AnimatedSize` + `FadeTransition` on the chip strip pauses when reduced-motion is on (`AppMotion.prefersReducedMotion(context)`) | inline in `app_list_control_bar.dart` | `AppMotion` | extend | Phase 1 |
| Polish: tabular figures + letterSpacing on subtotal/payment/remaining cells | wrap each money cell's `DefaultTextStyle` with `fontFeatures: [FontFeature.tabularFigures()]` (already true for `AppMoneyDisplay` only if ancestor is not larger; pin via `DefaultTextStyle.override(fontFeatures: ...)` and `DefaultTextStyle.merge(styleFactor: (_) => bodySm)` to land at `bodySm` size in the row) | inline in `invoice_table.dart` | `AppTypography` | extend | none |
| Analyzer sweep | `flutter analyze` over the touched files | run | — | — | — |

## 4. Page instantiation spec (mirrors web reference)

> **Binding source of truth:** the visible structure, copy, prop values, and ordering of the rebuilt `InvoiceListPage` must mirror exactly `web-reference/src/pages/app/invoices/InvoicesPage.tsx`. Composer 2.5 should open that `.tsx` and reproduce region-for-region; the Flutter control name and prop syntax change (e.g. `value`/`onChange` → Riverpod notifiers, `rowContextMenu={rowContextMenu}` → `rowActions: (row) => InvoiceRowContextMenu(row: row, ...)` via `MenuAnchor`, `<DataTable aria-label="Invoices" animateRows>` → `AppDataTable(ariaLabel:'Invoices', animateRows:true)`). The billing-specific deviations called out in §0.3 are the only intentional departures from the web reference.

Region-by-region (top → bottom):

1. **Page header** — `AppPageHeader(title: 'Invoices', description: "Every invoice for this branch — status, payments collected, and what's still owed.")`. (Matches web `<PageHeader title=… description=…/>` at `InvoicesPage.tsx:188–191`.) No header actions (web has none).
2. **List controls bar** (only when `hasInvoices`, i.e. backend returned ≥1 across all-time; the patient page distinguishes "first-run" via `state.isEmpty && !filters.hasActiveFilters`). Render `InvoiceListControlsBar` bound to the page `InvoiceListControls`:
   - `searchPlaceholder: 'Search by invoice number, patient, or MRN…'`
   - `searchAriaLabel: 'Search invoices'`
   - `sortValue: controls.sort.value`, `defaultSortValue: InvoiceSortKey.dateDesc.value`, `sortOptions: InvoiceSortKey.options` (6 entries with EN labels: `'Created (newest)'`/`'Created (oldest)'`/`'Remaining (highest)'`/`'Remaining (lowest)'`/`'Subtotal (highest)'`/`'Subtotal (lowest)'`)
   - `sortAriaLabel: 'Sort invoices'`
   - `filterMenu:` `AppFilterMenuPanel(sections: [ statusSection, branchSection ])` where:
     - `statusSection` id `'status'`, label `'Status'`, value `controls.status?.value ?? 'all'`, options `[{value:'all',label:'All statuses'}, ...InvoiceStatus.values.map((s) => (value: s.wireValue, label: s.label))]`, `onChange: (v) => apply controls.status = (v == 'all' ? null : InvoiceStatus.tryParse(v))`.
     - `branchSection` id `'branch'`, label `'Branch'`, value `controls.branch ?? 'all'`, options `[{value:'all',label:'All branches'}, ...branches.map((b) => (value: b.id, label: b.name))]`, `onChange: (v) => apply controls.branch = (v == 'all' ? null : v)`. **Gated:** hide the branch section entirely when `branchIds.length <= 1` (billing extension).
   - `filterActiveCount: (controls.status != null ? 1 : 0) + (controls.branch != null ? 1 : 0)`
   - `onClearFilters:` resets `status`+`branch` to null, page to 1
   - `activeFilters: [{id:'status',label:status.label,onRemove:...}, {id:'branch',label:branchName,onRemove:...}, {id:'search',label:'Search: <q>',onRemove:...}]` (drop `status` if null, drop `branch` if null/single-branch, drop `search` if empty)
   - `onClearAll:` resets to `InvoiceListControls.defaultControls` when `isFiltered`
3. **Empty — first-run** — `AppEmptyState(variant: firstRun, title:'No invoices yet', description:'Invoices appear here once a completed visit is billed.')` when `state.isEmpty && !controls.isFiltered` (matches web `<EmptyState variant="first-run" …>`, `InvoicesPage.tsx:244–248`).
4. **Empty — no results** — web renders an inline card (`<div className="rounded-2xl …">`); port via `AppEmptyState(variant: noResults, title:'No invoices match', description:'Try a different search term or clear your filters.', action: EmptyStateAction(label:'Clear filters', onPressed: clearAll))` wrapped in a `SizedBox` with `DecoratedBox(bg: surfaceDefault, border: borderSubtle, radius: x2l, padding: 6×14)`. Apply the same border/shadow tokens. (Billing: the existing `AppEmptyState.error` path is reused when the RPC errored; the first-run/no-results paths are the only two visual shells.)
5. **Data table** — `InvoiceLedgerTable(items: paged)` with the six-column set from §3 Phase 2; `AppListControlBar`'s sort/filter/state lives on the page; the page slices `paged = filtered.slice(...)` server-side (the notifier already sends `limit`/`offset`). `onRowClick: (row) => AppNavigator.pushBillingInvoiceDetail(row.id)`.
6. **Pagination** — `AppPagination(page: filters.page, pageSize: filters.pageSize, total: state.estimatedTotal, onPageChange: (p) => applyFilters(...), onPageSizeChange: (s) => applyFilters(...), pageSizeOptions: [10, 25, 50])`. Shown only when `!state.isEmpty` (matches web `hasResults`).
7. **Row context menu** (Phase 3) — `rowActions: (row) => InvoiceRowContextMenu(row: row, onOpen: ..., onViewPatient: ..., onVoid: ...)`. Each context-menu item is an `AppMenuEntry`; mapping mirrors `patient_row_context_menu.dart`. The trigger is an `AppIconButton(icon: Icons.more_horiz, variant: ghost, size: sm, label: 'Row actions')` inside `MenuAnchor`.

Bilingual copy note: EN-only for this port (matches `patients-page-implementation-plan.md` §0.11). The `_copyEn`/`_copyAr` convention is not required because the Invoices page has no Dev components-showcase section. AR translations land with the future l10n milestone (§6).

## 5. Wiring steps

After each phase:

- **Phase 1** — Append `app_list_control_bar.dart` + `app_filter_menu_panel.dart` to `widgets.dart` under the existing `// Layout & utility` block. Run `flutter analyze` on the two new files. No UI consumer yet.
- **Phase 2** —
  - Modify `frontend/lib/features/billing/domain/invoice_list_item.dart` (`patientId`/`patientMrn`/`branchId` additions + `fromRow` parsing).
  - Modify `frontend/lib/features/billing/presentation/models/invoice_list_filters.dart` (sort field + sort direction + `toRpcFilters` outputs).
  - Create `frontend/lib/features/billing/presentation/models/invoice_list_controls.dart` + `models/invoice_sort_key.dart`.
  - Create `frontend/lib/features/billing/presentation/widgets/invoice_list_controls.dart` + `widgets/invoice_table.dart`.
  - Modify `frontend/lib/features/billing/presentation/pages/invoice_list_page.dart` to use the new layout; remove the dead `_StatusFilterRow`/`_InvoiceLedgerList`/`_InvoiceLedgerRow` classes.
  - Verify `frontend/lib/features/billing/data/invoice_repository.dart` forward `sort_field`/`sort_direction` to the RPC (if backend supports them); else document defer in §6.
  - Run `flutter analyze` on the touched files; fix lints. Do **not** commit unless asked.
  - **No** `component_registry.dart` / `component_section_builders.dart` change (page port, not a Dev section).
- **Phase 3** — Create `widgets/invoice_row_context_menu.dart`; modify `widgets/invoice_table.dart` `rowActions`; add toast hook; run `flutter analyze`; visually QA the bar's active-filter strip animation + the table's row-context-menu (mouse + keyboard). Do **not** commit unless asked.

## 6. Out-of-scope / defer

- **AR strings / l10n** — EN-only this port; AR via future l10n milestone.
- **Backend sort support verification** — if `list_invoices` does not honour `sort_field`/`sort_direction`, ship the UI control and apply a **client-side sort over the loaded page** as a stopgap, with a TODO referencing this section. Re-extend to server-side when the backend lands the params.
- **Branch-name lookup provider** — if `listBranchesUseCaseProvider` is unavailable or returns names asynchronously, the active-branch chip can fall back to `branchId` raw; the section label still resolves names lazily. A `branch_id_options_provider.dart` is deferred to keep this port self-contained.
- **Bulk select / bulk action bar** — web `InvoicesPage` ships **no** row selection, but `AppDataTable` supports it; the future billing milestone may add bulk "Reconcile"/"Export". Not in scope here.
- **Export CSV / PDF / Print** — `web-reference` does not surface these on the list page; deferred to the invoice **detail** page revision.
- **Scheduled invoice reminders** — not addressed by either reference; deferred.
- **Reconcile action** — the "Reconcile" line-item action lands with the detail page redesign, not the list page.
- Schedule redesign of `visit_billing/*` widgets (the modal stepper) — separate spec, not in this plan.

## 7. Source reference — web widget inventory (Invoices page)

The page composes the following exported widgets (one `.tsx` source = one Canvas-demo enumerated below; binding source of truth = `web-reference/src/pages/app/invoices/InvoicesPage.tsx` except where noted):

| id (export name) | Title | Showcase / source file | Underlying UI component |
|---|---|---|---|
| `PageHeader` | Page header | `components/layout/PageHeader.tsx` (consumed at `InvoicesPage.tsx:188`) | shipped `AppPageHeader` — reuse, no port |
| `ListControlBar` | List control bar | `components/layout/ListControlBar.tsx` (consumed at `InvoicesPage.tsx:194`) | **NEW** `AppListControlBar` (Phase 1) |
| `FilterMenuPanel` | Filter menu panel | `components/layout/FilterMenuPanel.tsx` (consumed at `InvoicesPage.tsx:213`) | **NEW** `AppFilterMenuPanel` (Phase 1) |
| `DataTable` | Table / Data grid | `components/table/DataTable.tsx` (consumed at `InvoicesPage.tsx:261`) | shipped `AppDataTable` — reuse + `rowActions` extension (Phase 3) |
| `Pagination` | Pagination | `components/navigation/Pagination.tsx` (consumed at `InvoicesPage.tsx:280`) | shipped `AppPagination` — reuse |
| `EmptyState` | Empty state | `components/empty-state/EmptyState.tsx` (consumed at `InvoicesPage.tsx:244`, `:270`) | shipped `AppEmptyState` — reuse |
| `Avatar` | Avatar | `components/avatar/Avatar.tsx` (consumed in Patient column accessor `InvoicesPage.tsx:55`) | shipped `AppAvatar` — reuse |
| `Badge` | Badge | `components/badge/` (consumed in Status column accessor `InvoicesPage.tsx:67`) | shipped `AppBadge` (via `InvoiceStatusBadge`) — reuse |
| `MoneyDisplay` | Money display | `components/money/MoneyDisplay.tsx` (consumed in Subtotal/Payments/Remaining columns `InvoicesPage.tsx:76,82,93`) | shipped `AppMoneyDisplay` — reuse |
| `Chip` | Chip | `components/chip/Chip.tsx` (consumed by `ListControlBar` active-filter strip) | shipped `AppChip` — reuse |
| `Button` | Button | `components/actions/Button.tsx` (consumed by `ListControlBar` Filter + Sort + Clear) | shipped `AppButton` — reuse |
| `MenuEntry`/`Menu` (context menu) | Row context menu | `components/navigation/Menu.ts` (`MenuEntry` type), `InvoicesPage.tsx:166` `rowContextMenu` factory | shipped `AppMenu`/`AppMenuEntry` (via `patient_row_context_menu.dart` pattern) — reuse, *extended* for Void action |

Shared web building blocks and their Flutter equivalents (cross-reference §2):

| Web file | Flutter equivalent |
|---|---|
| `lib/cn.ts` (className merge) | n/a (Material ThemeData + `Theme.of(context)`) |
| `lib/motion.ts` (`motionPresets`, `getReducedMotion`) | `core/ui/motion/app_motion.dart` (`AppMotion.prefersReducedMotion`, `AppMotionPreset.fade`) |
| `components/ui/search-input/SearchInput.tsx` | `core/ui/components/app_search_input.dart` |
| `components/ui/popover/Popover.tsx` (Radix popover) | `core/ui/components/app_popover.dart` (`AppPopover`) |
| `components/ui/DropdownMenu.tsx` (Radix dropdown) | `core/ui/components/app_menu.dart` (`AppMenu`/`AppContextMenu`) + `MenuAnchor`/`MenuItemButton` (Material) |
| `components/avatar/Avatar.tsx` | `core/ui/components/app_avatar.dart` |
| `components/badge/index.ts` | `core/ui/components/app_badge.dart` |
| `components/empty-state/EmptyState.tsx` | `core/ui/components/app_empty_state.dart` |
| `components/money/MoneyDisplay.tsx` | `core/ui/components/app_money_display.dart` |
| `components/navigation/Pagination.tsx` | `core/ui/components/app_pagination.dart` |
| `components/table/DataTable.tsx` (`TableColumn<T>`) | `core/ui/components/app_data_table.dart` (`TableColumn<T>`, `AppDataTable<T>`) |
| `data/invoices.ts` (`InvoiceListRow`, `MOCK_INVOICE_LIST_ROWS`) | `features/billing/domain/invoice_list_item.dart` (`InvoiceListItem`) + `features/billing/data/invoice_repository.dart` (`list_invoices` RPC) |
| `pages/app/invoices/invoice-list-controls.ts` (`InvoiceListControls`, `filterAndSortInvoices`, status/sort/branch option lists) | `features/billing/presentation/models/invoice_list_controls.dart` + `models/invoice_list_filters.dart` + `utils/billing_formatting.dart` |
| `lucide-react` icons (`ExternalLink`, `UserRound`, `SearchX`, `SlidersHorizontal`, `ArrowUpDown`, `Check`, `ChevronRight`) | Material `Icons` (`Icons.open_in_new`, `Icons.person_outline`, `Icons.search_off`, `Icons.tune`, `Icons.swap_vert`, `Icons.check`, `Icons.chevron_right`) |

Cross-cutting web → Flutter notes:

- **Server-side vs in-memory** — web slices/sorts/filters in-memory over `MOCK_INVOICE_LIST_ROWS`. Flutter delegates to the RPC (`list_invoices`) with debounced `AppSearchInput` (250–300 ms), single-select status (`statuses: [status]`), optional `branch_id` (gated single-branch), and `sort_field`/`sort_direction` params (server honoured; stopgap client-side sort per §6). `AppPagination` binds to `InvoiceListUiState.estimatedTotal`.
- **Active-filter chip strip** — web derives `activeFilters` from `controls` + label resolves via `INVOICE_BRANCH_FILTER_OPTIONS.find(...)`. Flutter mirrors this derivation in `InvoiceListControls.activeFilters({bool multiBranch, String Function(String) branchName})`.
- **Row context menu** — web passes `rowContextMenu = (row) => MenuEntry[]` directly to `<DataTable>`. Flutter passes `rowActions: (row) => InvoiceRowContextMenu(row: row, …)` (a `MenuAnchor`-wrapped `AppIconButton` "more"), following the shipped `patient_row_context_menu.dart` pattern; billing extends the entry list with `Void invoice` (destructive, gated on `status.isVoidable`).
- **i18n/RTL** — `AppMoneyDisplay` forces `Directionality.ltr` (matches web money cells); the rest of the page lays out via `Directionality.of(context)`. `AppPagination` mirrors RTL icon swap.