# Implementation Plan — Invoices **Details** page (web-reference → Flutter port)

Spec target: port the **Invoice Details** page at
`web-reference/src/pages/app/invoices/InvoiceDetailPage.tsx` into the Flutter
`frontend/` billing feature, surfaced as the existing
`/billing/invoices/:id` route. An existing UI implementation already lives at
`frontend/lib/features/billing/presentation/pages/invoice_detail_page.dart`
(V1-6 — a single raised card with line-items + perforation + totals panel, a
loose payment-ledger column, and inline `_showPaymentForm` / `_showRefundForm`
expansion blocks in the page body). **Replace** that body wholesale with the
new web-reference design the user opened an invoice for from the list:

- breadcrumb → hero card (perforated edge, invoice number + status badge,
  billed-to link, balance due emphasis, 4-up meta grid) → voided notice →
  two `LinkCard`s (Patient + Visit) → line-items card with totals → payments
  card with totals → footer caption.
- The existing inline-expand PaymentForm/RefundForm blocks and the header
  `Edit draft`/`Void` buttons are **relocated** into App-header actions and a
  trailing `AppMenu` overflow on the hero card (the web reference is read-only
  on the detail page; the billing actions the existing Flutter page surfaced
  inline are preserved so the workflow is not degraded).

Split into **2 phases**.

This is a **feature-page port** (like
`invoices-page-implementation-plan.md` and
`patient-details-implementation-plan.md`), **not** a Dev components-showcase
group — so there is **no** `component_registry.dart` /
`component_section_builders.dart` wiring. The only App-layer additions along
the way are composite shipping-feature widgets under
`frontend/lib/features/billing/presentation/widgets/invoice_detail/` plus a
couple of small private widget classes; nothing new is exported from
`widgets.dart` for this port.

## 0. Ambiguities & Design Decisions (resolve before coding)

> ⚠️ **Set-specific runtime regressions.** The redesigned detail page embeds
> `AppCard(raised)` shells over `DecoratedBox`, a `LinkCard` with an inner
> `Material`-tappable "View patient" affordance, the existing
> `InvoicePerforationDivider`, `AppMoneyDisplay` (forces `Directionality.ltr`),
> `IconButton`-trigger row actions inside `MenuAnchor`, an optional `AppMenu`
> overflow on the hero card, `AppEmptyState(error)` for the not-found branch,
> and a `Motion` enter `FadeTransition`. Before coding, confirm the
> regressions to avoid (consult `docs/ui/memory/ui-runtime-errors.md` only
> when explicitly instructed):
>
> - **#1 / #5** — the "Billed to" patient link button, the Patient `LinkCard`
>   chevron `IconButton`, and the Visit `LinkCard` chevron `IconButton` all
>   sit inside `Card`/`DecoratedBox` shells. Wrap each tappable in
>   `Material(color: Colors.transparent, child: InkWell(...))` (already the
>   idiom shipped in `app_card.dart`'s `_InteractiveCard` and
>   `app_breadcrumb.dart`'s segment) so `InkWell` hit-testing and ripple have
>   a Material ancestor.
> - **#4 / #11** — the hero-card `AppMenu` overflow menu (Edit draft / Void /
>   Print) is a `MenuAnchor`. Use a single `FocusNode` on the trigger
>   `AppIconButton`, dispose it in `dispose`. Do **not** place the menu inside
>   a `Tooltip`.
> - **#3 / #8** — the page body sits in `AppShell` → `SingleChildScrollView` →
>   `Column`. Use `CrossAxisAlignment.start` and guard the hero `Row`s with
>   `Wrap` / `Flexible` so the title/badge row reflows under narrow viewports
>   (web wraps via `flex-wrap`) and the meta grid switches from 2-up to 4-up at
>   the `sm` breakpoint (mirror via `LayoutBuilder` + a `Wrap` of
>   `MetaItem`s, not a fixed `Row`).
> - **#30** — during the billing route transition the outgoing page can be
>   mounted under unbounded height for one frame. Keep the body column
>   `mainAxisSize: MainAxisSize.min` and do not stack two
>   `SliverFillViewport`s; the existing `SingleChildScrollView` already
>   avoids this (verify).
> - **Intl / DateFormat** — `BillingFormatting.formatDate` /
>   `formatDateTime` use `intl` `DateFormat`; `AppMoneyDisplay` uses
>   `NumberFormat` for `en_EG`. `ensureIntlDateFormattingInitialized()` is
>   already wired from `main.dart:12` — no change.
> - **Cross-widget row danger styling** — the voided notice's danger-surface
>   card and the refund row's `colors.statusDangerFg` amount reuse the same
>   semantic tokens as the existing `_PaymentLedgerRow`. No new token.
>
> Memory "Checklist for new input components" items 1, 4, 5, 6, 7 apply to the
> hero `AppMenu` overflow (Material+MenuAnchor hosted). Items 1 of the
> shell/placeholder checklist (#28/#30) apply to the page column +
> transition.

Other decisions:

1. **forui vs native Material** — native Material only;
   `forui-wrappers.md` is superseded. All controls reuse the shipped `App*`
   widgets; no `forui` import.
2. **File layout** — feature-page tree under
   `frontend/lib/features/billing/presentation/`:
   - `pages/invoice_detail_page.dart` — **MODIFY** the existing
     `/billing/invoices/:id` route widget: replace the body (still uses
     `invoiceDetailViewProvider`, still routes via `AppNavigator`).
   - `widgets/invoice_detail/invoice_hero_card.dart` — **CREATE** — the
     raised perforated hero card (invoice number + status badge + billed-to
     link + MRN + balance due emphasis + 4-up meta grid).
   - `widgets/invoice_detail/invoice_voided_notice.dart` — **CREATE** — the
     flat danger-surface notice shown only when `status == voided`.
   - `widgets/invoice_detail/invoice_link_card.dart` — **CREATE** — the
     reusable `LinkCard` (eyebrow + icon + title + subtitle + optional badge
     + trailing chevron `IconButton`); used for Patient & Visit.
   - `widgets/invoice_detail/invoice_section_title.dart` — **CREATE** — the
     shared "Line items" / "Payments" heading (rounded icon-chip + title)
     consumed by the two raised cards' header strips.
   - `widgets/invoice_detail/invoice_line_items_card.dart` — **CREATE** — the
     raised card hosting the section title header + line-items table + totals
     panel (reuses the existing `InvoicePerforationDivider`).
   - `widgets/invoice_detail/invoice_payments_card.dart` — **CREATE** — the
     raised card hosting the section title header + payments ledger table
     (or `AppEmptyState(firstRun)` when empty) + totals panel.
   - `widgets/invoice_detail/invoice_meta_grid.dart` — **CREATE** — the
     branch/created/issued/insurance "MetaItem" 2-up→4-up grid; only the
     reusable layout primitive + a small `MetaItem` widget (private).
   - `widgets/invoice_detail/invoice_totals_panel.dart` — **CREATE** — the
     dashed-top totals `<dl>` panel shared in shape by the line-items card
     and the payments card (Subtotal / Discount / Insurance / Amount due OR
     Amount due / Net paid / Balance due-with-voided-label).
   - `widgets/invoice_detail/invoice_detail_footer.dart` — **CREATE** — the
     "Last updated…" caption card.
   - `widgets/invoice_detail/invoice_detail_actions.dart` — **CREATE** —
     composes the permission-aware action affordances: header `Edit draft`
     + a trailing `AppMenu` (`MenuAnchor`) overflow on the hero card with
     `Record payment` / `Record refund` / `Void` entries (gated by
     `view.canRecordPayment`/`canRefund`/`canVoid`) + `View patient` /
     `View visit` shortcuts that match the web `LinkCard` arrows. Hosting
     the existing `PaymentForm`/`RefundForm`/`VoidInvoiceDialog` widgets
     unchanged.
   - **No App-layer additions** under `core/ui/components/` are required for
     this port — every web component (`Avatar`, `Badge`, `Card`,
     `EmptyState`, `PageHeader`, `MoneyDisplay`, `Breadcrumb`, `IconButton`,
     motion presets) has a shipped Flutter equivalent (see §1).
3. **Replace vs redesign** (per the user instruction):
   - **Replace** (web reference wins):
     - Drop the existing `AppPageHeader` + `_LineItemsTable` +
       `_TotalsPanel` + `_PaymentLedgerRow` body. The web reference's
       breadcrumb-and-card layout restructures the page from "header → table
       → ledger column → form spurts" to "breadcrumb → hero → meta → links →
       items card → payments card → footer".
     - Drop the existing top-`Row` "balance warning inline" text (the hero
       card already shows the balance prominently with success-green when
       ≤ 0).
   - **Redesign** (billing-specific additions the web reference does not
     cover):
     - **Action affordances** — the web detail page is purely read-only.
       The existing Flutter page surface exposed `Edit draft`, `Void`,
       `Record payment`, `Record refund` inline. Drop the inline form
       spurts; consolidate the actions into the hero card's trailing area:
       an `AppMenu` overflow (`MenuAnchor`) keeps Edit / Void / Record
       payment / Record refund contextually. When a user picks `Record
       payment` / `Record refund`, surface the existing `PaymentForm` /
       `RefundForm` inside an `AppDialog` (sheet on mobile) instead of the
       inline expansion blocks. `Void` continues to use the existing
       `VoidInvoiceDialog`. This preserves the workflow end-to-end while
       matching the read-only web detail visual exactly.
     - **Voided balance labelling** — web labels the totals balance row
       "Balance at void"` when `status == voided` and otherwise
       "Balance due"`; replicate the label switch and the danger-surface
       `InvoiceVoidedNotice` block.
     - **Net paid emphasis** — web paints the totals `Balance due` figure
       green when `balance <= 0 && status != voided`; voided balances stay
       neutral. Use `colors.statusSuccessFg` for the success case,
       `colors.textPrimary` for voided.
     - **Visit LinkCard fallback** — when `InvoiceDetail.visitId` is missing
       or the visit can't be resolved to date+doctor+branch, render the web's
       "source visit no longer available" flat-Card fallback. Phase 1 always
       renders the fallback until Phase 2 ships visit enrichment.
4. **i18n / RTL** — EN-only copy for this port (matches the
   `invoices-page-implementation-plan.md` §0.10 and the broader milestone.
   AR strings land with the future l10n milestone (§6). Widgets stay
   direction-agnostic via `Directionality.of(context)`; `AppMoneyDisplay`
   already forces `Directionality.ltr` for the numeric span (mirrors web
   `tabular-nums` + `dir="ltr"`). The Patient/Visit `LinkCard` chevron
   mirrors under RTL; replicate via `Transform.flip(flipX: isRtl)` on the
   `Icons.arrow_forward` glyph (matches web `rtl:-scale-x-100`).
5. **Permissions** — actions stay gated exactly as the existing page does:
   - `canEdit   = invoice.status.isDraft && view.canCreate`
   - `canPay    = view.canRecordPayment && !invoice.status.isDraft && !invoice.status.isTerminal`
   - `canVoid   = view.canVoid && invoice.status.isVoidable`
   - `canRefund  = view.canRefund && invoice.payments.any((p) => !p.isRefund)`
6. **Navigation** — `onNavigate('invoices')` → `context.nav.pop()` (or
   `pushBillingInvoices` if the stack is empty); `onNavigate('patients/:id')`
   → `context.nav.pushPatientDetail(patientId)`; visit navigation uses
   `context.nav.pushVisitDocument(visitId)` (or `pushVisitDetail` when a
   dedicated host exists; the web falls back to the patient record).
7. **Approval loop for ethics/sensitive content** — n/a (no
   clinical/medication surface on this page).
8. **No `widgets.dart` barrel change** for this port — every file lives
   inside the billing feature presentation tree, not the App abstraction
   core.

## 1. Existing App assets to reuse (do not recreate)

| Asset | Path | Used by |
|---|---|---|
| `AppBreadcrumb` (`items: List<AppBreadcrumbItem>` — each `{label, onTap?}`) | `core/ui/components/app_breadcrumb.dart` | breadcrumb ("Invoices"/[invoice number]) above the hero card |
| `AppCard` (`variant: CardVariant.raised/flat`, `padding`, `header`, `footer`) | `core/ui/components/app_card.dart` | hero card (raised), line-items / payments cards (raised), link cards + footer + voided notice (flat) |
| `AppPageHeader` | `core/ui/components/app_page_header.dart` | the not-found branch only (web reuses `PageHeader` only for the error state) |
| `AppAvatar` (`name`, `size: .lg/.sm`) | `core/ui/components/app_avatar.dart` | hero card avatar + (optional) patient column tile avatar |
| `AppBadge` (`variant: .soft`, `color`, `size`) | `core/ui/components/app_badge.dart` | hero status badge (via `InvoiceStatusBadge`), Visit `Completed` soft success badge |
| `AppMoneyDisplay` (`amount`, `currency`, `emphasis`, `negative`) | `core/ui/components/app_money_display.dart` | every money span (line-items table cells, totals rows, payments ledger, balance emphasis) |
| `AppEmptyState` (`variant: firstRun/error`, `title`, `description`, `action`) | `core/ui/components/app_empty_state.dart` | not-found error branch + payments-card "No payments yet" first-run branch |
| `AppButton` (`variant`, `leadingIcon`, `onPressed`) | `core/ui/components/app_button.dart` | "Record payment"/"Record refund"/"Edit draft"/"Void"/"View patient" actions (hosted inside `AppMenu` overflow on hero card) |
| `AppIconButton` (`variant: secondary`, `size: lg`, `icon`, `label`) | `core/ui/components/app_icon_button.dart` | the `LinkCard` trailing chevron, the `AppMenu` overflow trigger |
| `AppMenu` / `AppMenuEntry` (`MenuItemButton` mapping) | `core/ui/components/app_menu.dart` | the hero-card trailing overflow menu (Edit / Void / Record payment / Record refund / View patient / View visit) |
| `AppDialog` / `showAppDialog` | `core/ui/components/app_dialog.dart` | hosting `PaymentForm` / `RefundForm` when an action is selected from the overflow menu (replaces the inline expansion blocks) |
| `AppDivider` | `core/ui/components/app_divider.dart` | meta-grid divider line, payments ledger row separators (replaces the existing `Divider`) |
| `InvoicePerforationDivider` | `features/billing/presentation/widgets/invoice_perforation_divider.dart` | the dashed tear-line between the line-items table and the totals panel inside the line-items card |
| `InvoiceStatusBadge` (`status`, `size`) | `features/billing/presentation/widgets/invoice_status_badge.dart` | hero card status and any other status affordance |
| `VoidInvoiceDialog`, `PaymentForm`, `RefundForm` | `features/billing/presentation/widgets/...` | the existing void/payment/refund flows, opened from the hero-card overflow menu |
| `BillingFormatting` (`formatDate`, `formatDateTime`, `formatMoney`, `invoiceDisplayNumber`, `paymentMethodIcon`) | `features/billing/presentation/utils/billing_formatting.dart` | every date / money / icon rendering on the page |
| `InvoiceDetail`, `InvoiceDetailViewState`, `InvoiceItem`, `Payment`, `Money`, `InvoiceStatus`, `DiscountKind`, `PaymentMethod` | `features/billing/domain/*` | data |
| `invoiceDetailViewProvider` (`family<InvoiceDetailViewState, String>`) | `features/billing/presentation/providers/invoice_detail_provider.dart` | data loading + permission flags + reload on action success |
| `paymentNotifierProvider` | `features/billing/presentation/providers/payment_notifier.dart` | record payment / refund / void mutations |
| `App Navigator` (`pushBillingInvoiceEdit`, `pushPatientDetail`, `pushVisitDocument`, `pop`) | `app/navigation/app_navigator.dart` | navigation from breadcrumb / LinkCards / overflow menu |
| Theme: `context.appColors` (`AppSemanticColors`), `AppSpacing`, `AppRadius`, `AppTypography`, `AppElevation` | `core/ui/theme/*` | every region |
| `AppMotion`, `FadeTransition`, `AppMotionPreset.fade` / `row-enter`, `staggerChildren` | `core/ui/motion/app_motion.dart` | the hero `motion.div` slide-up enter + the link-cards staggered `row-enter` (mirror web `motionPresets['slide-up']` + `staggerChildren(60)`) |

## 2. New shared abstractions to introduce

| File (`features/billing/presentation/widgets/invoice_detail/`) | Export name | Web analog | Purpose | Phase |
|---|---|---|---|---|
| `invoice_hero_card.dart` | `InvoiceHeroCard` | `InvoiceDetailPage` hero `<Card variant="raised">` block | raised, perforated-edge card: avatar + invoice number (`AppTypography.mono`) + `InvoiceStatusBadge` + "Billed to" tappable name → patient route + `· MRN`; trailing "Balance due"/"Balance at void" + `AppMoneyDisplay(emphasis)` figure (green when `balance ≤ 0 && !voided`); 4-up meta grid (`InvoiceMetaGrid`) below a `border-t` divider | 1 |
| `invoice_meta_grid.dart` + private `MetaItem` | `InvoiceMetaGrid` + `_MetaItem` | `InvoiceDetailPage` meta items `Branch`/`Created`/`Issued`/`Insurance` | responsive `LayoutBuilder` 2-up→4-up grid of overline-label + body-sm-value tiles | 1 |
| `invoice_voided_notice.dart` | `InvoiceVoidedNotice` | `VoidedNotice` | flat `Card` with `bg-statusDangerSurface`/`border-statusDangerBorder`; icon-chip "!" + "This invoice was voided" + reason + "voidedAt · voidedByName" caption | 1 |
| `invoice_link_card.dart` | `InvoiceLinkCard` | `LinkCard` | flat `Card`: icon-chip + eyebrow + optional badge + title + subtitle + trailing chevron `AppIconButton(secondary, size:lg)` → `onAction`; mirrors web RTL `-scale-x-100` on the chevron via `Transform.flip(flipX: isRtl)` | 1 |
| `invoice_section_title.dart` | `InvoiceSectionTitle` | `InvoiceSectionTitle` | rounded icon-chip (`bg-surface-selected`) + title; consumed by both raised cards' header strips | 1 |
| `invoice_totals_panel.dart` | `InvoiceTotalsPanel` | both `<dl>` totals blocks | dashed-top "data list" panel: rows of `(label, value, optional danger/success color, emphasis flag)`; the two web `<dl>`s (line-items card: Subtotal/Discount/Insurance/Amount due; payments card: Amount due/Net paid/(Balance at void)|Balance due) share this primitive, switched by an enum/flag | 1 |
| `invoice_line_items_card.dart` | `InvoiceLineItemsCard` | line-items `<Card variant="raised">` | header (`InvoiceSectionTitle` icon `Icons.receipt_long` "Line items") + table (Service/Unit/Qty/[Discount]/Amount with `hasLineDiscounts` gate, the discount column rendered using `DiscountKind.labelFor(item.lineDiscountKind, item.lineDiscountValue)`) + `InvoicePerforationDivider` + `InvoiceTotalsPanel` (line-items variant) | 1 |
| `invoice_payments_card.dart` | `InvoicePaymentsCard` | payments `<Card variant="raised">` | header (`InvoiceSectionTitle` icon `Icons.account_balance_wallet` "Payments") + `PaymentLedgerRow` table (Payment/Recorded/By/Amount) OR `AppEmptyState(firstRun)` when empty + `InvoiceTotalsPanel` (payments variant) | 1 |
| `invoice_detail_footer.dart` | `InvoiceDetailFooter` | the trailing `<Card variant="flat">` | "Last updated … · Every invoice is tied to exactly one completed visit — the balance above is recomputed from the line items, discounts, insurance coverage, and payment ledger shown here." |
| `invoice_detail_actions.dart` | `InvoiceDetailActions` | n/a (billing-specific) | composes the permission-aware action affordances the existing page exposed (Edit draft / Void / Record payment / Record refund) into a trailing `AppMenu` overflow shown inside the hero card's header row; opens `PaymentForm`/`RefundForm` inside `showAppDialog`; `Void` opens the existing `VoidInvoiceDialog`. Phase 2. | 2 |

> **Note** — `PerforatedEdge` (the thin top-edge inside the hero card) is a
> 1.5px-tall decorative strip. Reuse `InvoicePerforationDivider`'s dot
> pattern as a private top edge rather than introducing a new App widget.
> Either (a) add an `edge: PerforationEdge.top` enum to
> `InvoicePerforationDivider`, or (b) extract a small
> `_PerforatedEdge` painter reused by both — pick (b) to avoid touching the
> existing widget's API surface.

**No barrel update needed.** These widgets live inside the billing feature
and are imported only by `invoice_detail_page.dart`.

## 3. Phasing

> Rationale: **Phase 1** = the read-only visual redesign (the web page as
> written) — every region of `InvoiceDetailPage.tsx` is recreated in Flutter
> and the action affordances the existing page had are temporarily dropped
> (Edit/Void/Record payment/Record refund). The page is fully visible /
> navigable / void-displaying debit-noted; only the action affordances are
> gone. **Phase 2** = re-introducing the workflow actions via the hero-card
> overflow menu + dialog-hosted forms (Edit draft stays a header button per
> design polish) + visit enrichment for the Visit LinkCard. Each phase is
> independently shippable: Phase 1 lands the redesign the user opened from
> the list; Phase 2 restores full workflow parity without breaking the new
> layout.

### Phase 1 — Read-only visual redesign

Widgets / regions ported (top → bottom in the web): **Breadcrumb · Hero
card · Voided notice · Patient LinkCard · Visit LinkCard (fallback) ·
Line-items card · Payments card · Footer**.

| Region | Flutter widget(s) to create/modify | File(s) | Reuse | Wrapper | Deps |
|---|---|---|---|---|---|
| Breadcrumb | modify page body to render `AppBreadcrumb(items: [AppBreadcrumbItem(label:'Invoices', onTap: pop-to-list-or-push), AppBreadcrumbItem(label: invoiceDisplayNumber)])` above the hero card | MOD `pages/invoice_detail_page.dart` | `AppBreadcrumb`, `BillingFormatting.invoiceDisplayNumber` | n/a | none |
| Hero card | `InvoiceHeroCard(invoice, patientName, mrn?, branchName?, insuranceProviderName?, balance, currency)` | CREATE `widgets/invoice_detail/invoice_hero_card.dart` | `AppCard(raised, padding:lg)`, `InvoicePerforationDivider`-derived `_PerforatedEdge` private painter, `AppAvatar(name, size:lg)`, `AppTypography.mono` invoice number, `InvoiceStatusBadge(size:md)`, `Material`-tappable "Billed to" name, `AppMoneyDisplay(emphasis)` balance, `InvoiceMetaGrid` (below the `border-t` divider) | NEW | `InvoiceMetaGrid` |
| Meta grid | `InvoiceMetaGrid(items: List<{label, valueWidget, icon?}>)` with private `_MetaItem` | CREATE `widgets/invoice_detail/invoice_meta_grid.dart` | `LayoutBuilder` 2-up→4-up `Wrap`, `AppTypography.overline` label + `bodySm` value, `Icon(Icons apartment/credit_card/shield,date)` glyphs | NEW | none |
| Voided notice | `InvoiceVoidedNotice(invoice)` rendered only when `status == voided` | CREATE `widgets/invoice_detail/invoice_voided_notice.dart` | `AppCard(flat)`, `AppTypography.bodyStrong` + danger-fg strings, `AppTypography.caption` for the audit trail (`voidedAt · voidedByName`), `BillingFormatting.formatDateTime` | NEW | `BillingFormatting` |
| Patient LinkCard | `InvoiceLinkCard(eyebrow:'Patient', icon: Icons.person, title: patientName ?? 'Unknown', subtitle: '$mrn · $phone', actionLabel:'View patient profile', onAction: pushPatientDetail)` | CREATE `widgets/invoice_detail/invoice_link_card.dart` | `AppCard(flat, padding:lg)`, `AppIconButton(secondary, size:lg, icon: arrow_forward)` mirrored in RTL | NEW (primitive) | none |
| Visit LinkCard | Phase 1 fallback only — render the web "source visit no longer available" flat card (icon-chip `Icons.event_busy` + body-sm copy). Real visit rendering lands in Phase 2. | inline in `pages/invoice_detail_page.dart` (uses `AppCard(flat)` + an icon chip; mirrors the existing `_InvoiceMetaGrid` icon-chip pattern) | `AppCard(flat)`, `AppTypography.bodySm` | inline | none |
| Line-items card | `InvoiceLineItemsCard(items, currency, totals: InvoiceTotalsModel)` | CREATE `widgets/invoice_detail/invoice_line_items_card.dart` | `AppCard(raised)` with `header: InvoiceSectionTitle(icon: Icons.receipt_long, title:'Line items')`; an internal `_LineItemsTable` (private, plain `Column`/`Row` + `AppDivider` rows — no `AppDataTable`, the web uses a native `<table>`); `InvoicePerforationDivider` below the table; `InvoiceTotalsPanel` (line-items variant: Subtotal / Invoice discount w/ `Tag` icon + discountKind label / Insurance covered w/ `ShieldCheck` icon + provider name / Amount due emphasis) | NEW | `InvoiceSectionTitle`, `InvoicePerforationDivider`, `InvoiceTotalsPanel`, `AppMoneyDisplay`, `DiscountKind.labelFor` (or local helper on `BillingFormatting` — see §0.4) |
| Payments card | `InvoicePaymentsCard(payments, currency, totals, status)` | CREATE `widgets/invoice_detail/invoice_payments_card.dart` | `AppCard(raised)` with `header: InvoiceSectionTitle(icon: Icons.account_balance_wallet, title:'Payments')`; internal `_PaymentLedgerRow` (private — icon-chip + method label + reference + note + recorded date + recordedByName + signed amount via `AppMoneyDisplay`); `AppEmptyState(firstRun, title:'No payments yet', description: status == draft ? 'Issue this invoice before recording a payment.' : 'Payments recorded against this invoice will appear here.')` when `payments.isEmpty`; `InvoiceTotalsPanel` (payments variant: Amount due / Net paid / (Balance at void when voided else Balance due), emphasis + green when `balance ≤ 0 && !voided`) | NEW | `InvoiceSectionTitle`, `InvoiceTotalsPanel`, `AppEmptyState`, `AppMoneyDisplay`, `BillingFormatting.paymentMethodIcon` |
| Totals panel (shared primitive) | `InvoiceTotalsPanel(model)` where `model` carries the typed `{label, valueMoney, currency, danger/success?, emphasized?}` rows + a `{lineItems, payments}` variant selector | CREATE `widgets/invoice_detail/invoice_totals_panel.dart` | dashed-top `Border(top: BorderSide(..., dashPattern:[6,4]))` via `CustomPaint` OR a `Row` of dashed `Container`s; emulate web `bg-surfaceSunken/20`; each row uses `Row(label, value)`, alignment `spaceBetween`, max-width 384 on the trailing edge via `ConstrainedBox(maxWidth: 384)` + `Alignment.centerRight` | NEW | `AppMoneyDisplay` |
| Section title primitive | `InvoiceSectionTitle(icon, title)` | CREATE `widgets/invoice_detail/invoice_section_title.dart` | rounded `bg-surface-selected` icon-chip (`size:40`) + `AppTypography.bodyStrong` title | NEW | none |
| Footer | `InvoiceDetailFooter(updatedAt)` | CREATE `widgets/invoice_detail/invoice_detail_footer.dart` | `AppCard(flat, padding:md)` + `Icon(Icons.event_available_outlined)` + `AppTypography.caption` "Last updated …" | NEW | `BillingFormatting.formatDateTime` |
| Page body rewrite | `invoice_detail_page.dart` `_InvoiceDetailBody`: replace the existing body with `Column(crossAxisAlignment: start, children: [ breadcrumb, SizedBox(space4), InvoiceHeroCard(...), if(voided) InvoiceVoidedNotice(...), SizedBox(space4), two-up Wrap(Invoices LinkCards) , SizedBox(space4), InvoiceLineItemsCard(...), SizedBox(space4), InvoicePaymentsCard(...), SizedBox(space4), InvoiceDetailFooter(...)])` inside the existing `SingleChildScrollView`. Keep `invoiceDetailViewProvider`, the not-found `AppEmptyState(error)` branch, the `FadeTransition` enter (use `AppMotionPreset.slideUp` to mirror web `motionPresets['slide-up']`). Strip the now-dead `_LineItemsTable`, `_HeaderCell`, `_TotalsPanel`, `_TotalRow`, `_PaymentLedgerRow` classes. | MOD `pages/invoice_detail_page.dart` | all of the above | extend existing | none |

#### Phase 1 — Dev-page instantiation spec (mirrors web reference)

> **Binding source of truth:**
> `web-reference/src/pages/app/invoices/InvoiceDetailPage.tsx` is the binding
> source to reproduce demo-for-demo. The Flutter invoice detail page is a
> feature page (no Dev showcase section), so the "instantiate in the Dev
> page" step is replaced by **region-for-region recreation of the web page
> in the `/billing/invoices/:id` route**. Composer 2.5 should open the
> referenced `.tsx` and reproduce, region-for-region, the structure, copy,
> props, and copy switches.

Region-by-region (top → bottom):

1. **Breadcrumb** — `AppBreadcrumb(items: [AppBreadcrumbItem(label:'Invoices', onTap: () => nav.pop-to-list-or-pushBillingInvoices), AppBreadcrumbItem(label: BillingFormatting.invoiceDisplayNumber(invoice.invoiceNumber, invoice.id))])`. Web: `Breadcrumb items=[{label:'Invoices', onClick: onNavigate('invoices')}, {label: invoice.invoiceNumber ?? 'Draft invoice'}]` at `InvoiceDetailPage.tsx:282–287`. RTL chevron mirror behavior already shipped in `AppBreadcrumb`.
2. **Hero card** — `InvoiceHeroCard(...)` reproducing web `InvoiceDetailPage.tsx:289–365`:
   - `Card(variant: raised, padding: lg)` with a left/right/top rounded-`x2l` radius and a clip; `overflow: hidden`; the private `_PerforatedEdge` painted as a 1.5px dashed strip across the top edge (web `PerforatedEdge`).
   - Top row `Wrap(spacing: space4, runSpacing: space4, children: [ Row([Avatar(name, size:lg), SizedBox(space4), Column([Row([Text(invoiceDisplayNumber, style: bodyMono h1 with letterSpacing 0.02em + tabularFigures), InvoiceStatusBadge(status, size:md), ]), SizedBox(space1_5), Text('Billed to ', body) + tappableText(patientName ?? '—', color: textLink, underline on hover, onTap: pushPatientDetail) + Text(' · $mrn', error if no Mrn a '—', caption tertiary + tabularFigures)]), ]), Spacer/end-aligned balance block: Column([Text(invoice.status == voided ? 'Balance at void' : 'Balance due', overline tertiary), AppMoneyDisplay(amount: balance.asDouble, currency: invoice.currency, emphasis: true, negative: balance.isNegative) wrapped in DefaultTextStyle(display + tabularFigures, color: (balance ≤ 0 && !voided) ? statusSuccessFg : textPrimary)]), ])`.
   - `border-t borderSubtle` divider.
   - `InvoiceMetaGrid(items: [ ('Branch', icon: Icons.apartment_outlined, value: branchName ?? '—'), ('Created', value: BillingFormatting.formatDate(invoice.createdAt — note: the InvoiceDetail domain exposes `updatedAt` only; web uses `invoice.createdAt`. Add `createdAt` to the domain in Phase 1 too — see §0.4 / §6 disclaimer), ('Issued', value: issuedAt == null ? 'Not yet issued' : BillingFormatting.formatDate(issuedAt)), ('Insurance', icon: Icons.shield_outlined, value: insuranceProviderName ?? 'None on file'), ])`.
3. **Voided notice** — render only when `invoice.status == voided`. `InvoiceVoidedNotice(invoice)` reproducing web `InvoiceDetailPage.tsx:205–227`:
   - `Card(flat)` with `bg-statusDangerSurface` `border-statusDangerBorder` `rounded-x2l`.
   - BodyRow: 36px circle "!" icon-chip (`bg-surfaceDefault`, `color: statusDangerFg`) + Column([Text('This invoice was voided', bodyStrong, color: statusDangerFg), Text(invoice.voidReason ?? '', bodySm, textPrimary), Text('${BillingFormatting.formatDateTime(voidedAt ?? …)}${voidedByName != null ? ' · $voidedByName' : ''}', caption, textTertiary)]).
   - The current `InvoiceDetail` domain exposes `voidReason` and `voidedAt` but **not** `voidedByName`. Render `'${formatDateTime(voidedAt ?? updatedAt)}'` and omit the `by` clause until Phase 2 extends the envelope (§6).
4. **Patient LinkCard** — `InvoiceLinkCard(eyebrow:'Patient', icon: Icons.person_outline, title: patientName ?? 'Unknown patient', subtitle: '$mrn · $phone', actionLabel:'View patient profile', onAction: () => nav.pushPatientDetail(patientId))` reproducing web `InvoiceDetailPage.tsx:376–384`. The chevron icon mirrors under RTL via `Transform.flip(flipX: isRtl)` on `Icons.arrow_forward` (mirrors web `rtl:-scale-x-100`).
   - The current `InvoiceDetail` envelope exposes `patientDisplayName` only; `patientMrn`/`patientPhone` are not on the envelope. Phase 1 ships with the MRN shown as `'—'` until Phase 2 extends the envelope (visit/patient enrichment in Phase 2). The Patient tile is still rendered with the name from `patientDisplayName`; both subtitle fields degrade gracefully to `'—'`.
5. **Visit LinkCard fallback** — render the web visit-unavailable fallback (`InvoiceDetailPage.tsx:402–412`) every time in Phase 1: `Card(flat, padding:lg)` with Row([icon-chip(`bg-surfaceMuted`, `Icons.event_busy_outlined`), Text('The source visit for this invoice is no longer available.', bodySm textSecondary)]). Phase 2 swaps this for the real `InvoiceLinkCard(visit)` when a visit can be resolved.
6. **Line-items card** — `InvoiceLineItemsCard(items, currency, totals)` reproducing web `InvoiceDetailPage.tsx:416–504`:
   - `Card(raised)` with `header: InvoiceSectionTitle(icon: Icons.receipt_long_outlined, title: 'Line items')`; `!p-0` (set inside `Card(padding: md)` + a content `Padding(space5)` so the header strips align — or extend `AppCard`'s existing `header` flow). Use `overflow: hidden` + a rounded-`x2l` clip.
   - `_LineItemsTable`: header row `[Text('Service'), hidden-on-sm `Text('Unit', end), Text('Qty', center/16-fixed width), if(hasLineDiscounts) hidden-on-sm `Text('Discount', end), Text('Amount', end)]`; each body row `[Text(description), hidden `AppMoneyDisplay(unitPrice)`, Text(quantity, center), if(hasLineDiscounts) hidden `Text(item.lineDiscountAmount > 0 ? DiscountKind.labelFor(lineDiscountKind, lineDiscountValue) : '—', color: statusSuccessFg)`, `AppMoneyDisplay(lineTotal)]`.
     - Implement "hidden-on-sm" via a `LayoutBuilder`: `if (constraints.maxWidth >= 600)` for `Unit`/`Discount`; mirror web's `sm:hidden` breakpoint behaviour.
     - `hasLineDiscounts = items.any((i) => i.lineDiscountAmount.asDouble > 0)`.
   - `InvoicePerforationDivider` between the table and the totals block (existing widget reused as-is).
   - `InvoiceTotalsPanel(model: TotalsModel.lineItems(subtotal, discountKind, discountValue, discountAmount, insuranceProviderName, insuranceCoveredAmount, currency, amountDue))`:
     - Subtotal row (`AppMoneyDisplay(subtotal)`).
     - if `discountAmount > 0`: row label `Row([Icon(Icons.local_offer_outlined, size:13), Text('Invoice discount${discountKind != null ? ' (' + DiscountKind.labelFor(...) + ')' : ''}')], color: statusSuccessFg)`, value `AppMoneyDisplay(discountAmount, negative: true)`.
     - if `insuranceCoveredAmount > 0`: row label `Row([Icon(Icons.shield_outlined, size:13), Text('Insurance covered${providerName != null ? ' (' + providerName + ')' : ''}')], color: statusSuccessFg)`, value `AppMoneyDisplay(insuranceCoveredAmount, negative: true)`.
     - `border-t` row: `Text('Amount due', bodyStrong)` + `AppMoneyDisplay(amountDue, emphasis: true)` (display size h2 + tabularFigures).
7. **Payments card** — `InvoicePaymentsCard(payments, currency, totals, status)` reproducing web `InvoiceDetailPage.tsx:506–580`:
   - `Card(raised)` with `header: InvoiceSectionTitle(icon: Icons.account_balance_wallet_outlined, title: 'Payments')`.
   - if `payments.isNotEmpty`: `_PaymentLedgerTable` with header row `[Text('Payment') , hidden-on-sm `Text('Recorded', end) , hidden-on-md `Text('By', end) , Text('Amount', end)]`; each row `_PaymentLedgerRow`:
     - leading 28×28 icon-chip (`pad: 6.5`, `bg: surfaceMuted`, `color: iconMuted`, `Icon(BillingFormatting.paymentMethodIcon(payment.method), size:14)`),
     - Column([Text('${paymentMethodLabel(payment.method)}${payment.isRefund ? ' · Refund (danger caption span)' : ''}', body, textPrimary), if(reference != null) `Text(reference, mono caption tertiary)`, if(note != null) `Text(note, caption secondary)`]);
     - hidden `Text(formatDateTime(recordedAt), end bodySm secondary)`;
     - hidden `Text(recordedByDisplayName ?? '—', end secondary)`;
     - `AppMoneyDisplay(payment.amount, currency, negative: payment.isRefund)` wrapped in DefaultTextStyle(color: payment.isRefund ? statusDangerFg : statusSuccessFg).
   - else: `AppEmptyState(firstRun, title: 'No payments yet', description: invoice.status == InvoiceStatus.draft ? 'Issue this invoice before recording a payment.' : 'Payments recorded against this invoice will appear here.')`.
   - `InvoiceTotalsPanel(model: TotalsModel.payments(amountDue, netPaid, balance, currency, isVoided: status == voided))`:
     - Amount due row (`AppMoneyDisplay(amountDue, emphasis: true)`).
     - if `payments.isNotEmpty`: Net paid row (`AppMoneyDisplay(netPaid)`).
     - `border-t` row: label `status == voided ? 'Balance at void' : 'Balance due'`, bodyStrong; value `AppMoneyDisplay(balance, emphasis); color = (balance ≤ 0 && !voided) ? statusSuccessFg : textPrimary.
8. **Footer** — `InvoiceDetailFooter(updatedAt)` reproducing web `InvoiceDetailPage.tsx:582–591`:
   - `Card(flat, padding: md)` with `border-subtle`.
   - Row(crossAxisAlignment: start, children: [`Icon(Icons.event_available_outlined, size:16, color: iconMuted)`, SizedBox(space3), Text('Last updated ${BillingFormatting.formatDateTime(updatedAt)}. Every invoice is tied to exactly one completed visit — the balance above is recomputed from the line items, discounts, insurance coverage, and payment ledger shown here.', caption secondary, maxLines: null)]).
9. **Not-found branch** — when `invoice == null` (provider throws `StateError` or returns no data), `AppPageHeader(title:'Invoice not found', breadcrumb: AppBreadcrumb(items:[AppBreadcrumbItem(label:'Invoices', onTap: pop-to-list), AppBreadcrumbItem(label:'Not found')]))` + `AppEmptyState(error, title:'Invoice not found', description:'The invoice you requested does not exist or has been removed.', action: EmptyStateAction(label:'Back to invoices', onPressed: pop-to-list))`. Reproduces web `InvoiceDetailPage.tsx:245–266`.

### Phase 2 — Action integration + visit/patient enrichment

Widgets / regions ported: **Hero-card actions overflow · Dialog-hosted Payment/Refund forms · Edit/Void header affordance · Patient MRN/Phone enrichment · Visit LinkCard real rendering**.

| Widget / change | Flutter widget(s) to create/modify | File(s) | Reuse | Wrapper | Deps |
|---|---|---|---|---|---|
| Hero-card overflow actions | `InvoiceDetailActions(invoice, view, onEdit, onVoid, onRecordPayment, onRecordRefund, onViewPatient, onViewVisit)` — a trailing `AppIconButton(icon: Icons.more_vert, variant: secondary, size: lg)` inside the hero card's header row wrapped in a `MenuAnchor` whose `menuChildren` are `MenuItemButton`s built from permission-gated `AppMenuEntry`s (Edit draft when `canEdit`; Void when `canVoid` (destructive); Record payment when `canPay`; Record refund when `canRefund`; separator; View patient profile; View visit). | CREATE `widgets/invoice_detail/invoice_detail_actions.dart`; MOD `invoice_hero_card.dart` to accept an optional `actions` slot placed in the header Row end side | `AppMenu`/`AppMenuEntry`/`MenuItemButton`, `AppIconButton`, `AppNavigator` (`pushBillingInvoiceEdit`, `pushPatientDetail`, `pushVisitDocument`), `VoidInvoiceDialog`, `paymentNotifierProvider` | NEW | none |
| Dialog-hosted Payment/Refund forms | `_showRecordPaymentDialog(BuildContext, invoice)` / `_showRecordRefundDialog(...)` open the existing `PaymentForm`/`RefundForm` inside `showAppDialog(...)` (large dialog, `title: 'Record payment' / 'Record refund'`, `child: PaymentForm(...)` etc.); on the form's `onRecorded` callback, `Navigator.pop(dialogContext)` + `ref.invalidate(invoiceDetailViewProvider)` + `ref.invalidate(invoiceListProvider)`. Replaces the inline `_showPaymentForm`/`_showRefundForm` expansions removed in Phase 1. | inline in `invoice_detail_page.dart` (private methods on `_InvoiceDetailBodyState`) | `AppDialog`/`showAppDialog`, `PaymentForm`, `RefundForm`, `paymentNotifierProvider` | extend existing | Phase 1 |
| Edit draft header button | mirror a minimal header affordance above the hero card: when `canEdit`, render an `AppButton(variant: secondary, leadingIcon: Icons.edit_outlined, child: Text('Edit draft'), onPressed: nav.pushBillingInvoiceEdit)`. (Web has none; billing-specific. Optional; can be folded into the overflow menu instead — recommend the overflow route and skipping a top-bar banner to keep the read-only look closer to web.) | optional; inline in `invoice_detail_page.dart` | `AppButton` | inline | Phase 1 |
| Visit LinkCard real rendering | replace the Phase 1 fallback with `InvoiceLinkCard(eyebrow:'Visit', icon: Icons.medical_services_outlined, title: BillingFormatting.formatDate(visit.date) or 'Visit ' + short-id, subtitle: '${visit.doctor} · ${visit.branch}', badge: AppBadge(variant: soft, color: success, size: sm, label:'Completed'), actionLabel: 'View visit in patient record', onAction: () => nav.pushVisitDocument(invoice.visitId))` | MOD `pages/invoice_detail_page.dart` (render method switch on `view.visit`) | `InvoiceLinkCard` (from Phase 1), `BillingFormatting.formatDate`, `AppBadge` | extend | Phase 1's `InvoiceLinkCard` |
| `InvoiceDetail` envelope: `createdAt`, `voidedByName`, patient enrichment | extend `InvoiceDetail` with `createdAt: DateTime`, `voidedByName: String?`, `patientMrn: String?`, `patientPhone: String?`, `visitSummary: VisitSummary?` (where `VisitSummary { date: DateTime, doctor: String, branch: String }`) + forward-parse from the `get_invoice_detail` envelope in `fromRpcData` | MOD `features/billing/domain/invoice_detail.dart`; MOD `features/billing/data/invoice_repository.dart` to pass the extra fields if the RPC envelope does not currently return them (else document defer in §6 and degrade gracefully) | existing parsing | extend existing | backend envelope verification |
| Hero meta-grid `createdAt` | switch `MetaItem label 'Created'` to `BillingFormatting.formatDate(invoice.createdAt)` (the field added above) | inline in `invoice_meta_grid.dart` / `invoice_hero_card.dart` | `BillingFormatting.formatDate` | extend | envelope extension |
| Polish: motion variants | wrap Patient & Visit LinkCards in a `TweenSequenceBuilder`/`AnimatedSwitcher` that applies the web's `staggerChildren(60)` + `motionPresets['row-enter'].variants` (approximated via `AppMotionPreset.fade` + `AppMotionPreset.slideUp` + 60ms stagger delays) — or, if reduced-motion is on (`AppMotion.prefersReducedMotion(context)`), render fully visible instantly. Already partly approximated by the existing page enter; reuse `AppMotion.animatedPreset` style helper if present, else build with two `AnimatedOpacity`/`SlideTransition` instances | inline in `invoice_detail_page.dart` | `AppMotion` | extend | Phase 1 |
| Analyzer sweep | `flutter analyze` over all touched files | run | — | — | — |

#### Phase 2 — Dev-page instantiation spec (mirrors web reference)

Phase 2 only re-arranges Phase-1 regions; no new web regions to mirror. The
action affordances are billing-specific and intentionally place the web's
read-only detail page inside the hero-card overflow (mirroring the shipped
billing convention that actions live behind a trailing `…` `MenuAnchor`).

Concretely:

1. The hero card's header row, originally `Row([avatar+title-block, Spacer, balance-block])`, becomes `Row([avatar+title-block, Spacer, balance-block, IconButton(overflow)])`.
2. The overflow `MenuAnchor` hosts the four permission-gated entries + a separator + the two navigation entries (View patient / View visit). The Patient LinkCard's chevron button stays as the primary navigation affordance for patient profile; the overflow's "View patient profile" entry is the same destination (covers keyboard users who land on the overflow first).
3. `Record payment` / `Record refund` open the existing `PaymentForm` / `RefundForm` widgets inside `showAppDialog` — not inline expansions. This keeps the read-only web layout intact while preserving the billing workflow.
4. `Void` opens the existing `VoidInvoiceDialog`; on confirm, the page calls `ref.invalidate(invoiceDetailViewProvider)` + `ref.invalidate(invoiceListProvider)`.

## 4. Wiring steps (do after each phase's widgets land)

> **Status: complete** (2026-07-21). This is a feature-page port — there is
> **no** `component_registry.dart` / `component_section_builders.dart`
> Dev-showcase wiring to update. The wiring is purely the billing-feature page
> + provider integration.

### Phase 1 — done

1. Created the nine widgets under
   `frontend/lib/features/billing/presentation/widgets/invoice_detail/`
   (`invoice_hero_card.dart`, `invoice_meta_grid.dart`,
   `invoice_voided_notice.dart`, `invoice_link_card.dart`,
   `invoice_section_title.dart`, `invoice_totals_panel.dart`,
   `invoice_line_items_card.dart`, `invoice_payments_card.dart`,
   `invoice_detail_footer.dart`).
2. Modified
   `frontend/lib/features/billing/presentation/pages/invoice_detail_page.dart`
   to render the new region sequence (breadcrumb → hero → voided notice →
   two LinkCards → line-items card → payments card → footer) and removed the
   dead inline `_showPaymentForm`/`_showRefundForm` state + page-level
   `_LineItemsTable`/`_HeaderCell`/`_TotalsPanel`/`_TotalRow`/
   `_PaymentLedgerRow` private classes (table/ledger primitives now live
   inside the card widgets). `invoiceDetailViewProvider` watching is unchanged.
3. Not-found branch verified — `_InvoiceNotFoundView` renders
   `AppPageHeader` + `AppEmptyState(error)` matching web
   `InvoiceDetailPage.tsx:245–266`; `NOT_FOUND` RPC maps to this branch.
4. Routing verified — `AppNavigator.pushBillingInvoiceDetail` from
   `invoice_list_page.dart`, `invoice_table.dart`,
   `invoice_row_context_menu.dart`, `patient_invoice_card.dart`, and
   `router.dart` (`/billing/invoices/:id`) all resolve to
   `InvoiceDetailPage` unchanged.
5. `flutter analyze` over touched files — clean.

### Phase 2 — done

1. Created
   `frontend/lib/features/billing/presentation/widgets/invoice_detail/invoice_detail_actions.dart`
   (`MenuAnchor` overflow with permission-gated entries + single `FocusNode`).
2. Modified `invoice_hero_card.dart` — optional `actions` slot in the header
   row (wide + narrow breakpoints).
3. Modified `pages/invoice_detail_page.dart` — overflow callbacks wire
   `PaymentForm`/`RefundForm` inside `AppDialog.show`; `Void` via
   `VoidInvoiceDialog`; patient/visit nav via `AppNavigator`; staggered
   LinkCard enter via `_StaggeredLinkCard` + `AppMotionPreset.rowEnter`.
4. Modified `features/billing/domain/invoice_detail.dart` — `createdAt`,
   `voidedByName`, `patientMrn`/`patientPhone`, `VisitSummary` +
   `fromRpcData` parsing with graceful degradation.
5. Visit-unavailable fallback verified — `_VisitUnavailableCard` renders when
   `visitSummary` is null or incomplete; no build failure when the backend
   omits the `visit` block.
6. Patient LinkCard degrades `'—'` for missing MRN/phone; fills when the
   envelope returns them.
7. `flutter analyze` over touched files — clean. `test/unit/billing/` — all
   pass (including new `InvoiceDetail.fromRpcData` enrichment tests).

## 5. Out-of-scope / defer

> **Status: verified** (2026-07-21). Each item below is intentionally
> excluded from this port; the shipping Flutter page honours the deferral.

- **AR strings / l10n** — EN-only copy hard-coded throughout (matches
  `invoices-page-implementation-plan.md` §6). AR lands with the future l10n
  milestone. Widgets stay direction-agnostic; `InvoiceLinkCard` mirrors the
  chevron under RTL via `Transform.flip(flipX: isRtl)`.
- **Backend envelope extensions** — **verified absent** in
  `auth_internal.get_invoice_detail` (latest migration
  `20260605300000_fix_billing_review_items_13_17.sql`): the RPC emits
  `invoice` (no `created_at`, no `voided_by`), `patient` (id +
  `display_name` only — no `mrn`/`phone`), and no `visit` block. Flutter
  ships `InvoiceDetail.fromRpcData` parsers for all enrichment fields and
  degrades: `createdAt` falls back to `updatedAt`; voided notice omits the
  `· voidedByName` clause; Patient LinkCard shows `'—'` for MRN/phone; Visit
  LinkCard shows the unavailable fallback. Defer comment added in
  `invoice_repository.dart:getDetail`. Backend additions belong to a backend
  epic, not this plan.
- **"Print invoice" / "Export PDF" / "Share" actions** — not on the web detail
  page; not surfaced in `InvoiceDetailActions`. Deferred to a future
  detail-page revision (mirrors `invoices-page-implementation-plan.md` §6).
- **Reconcile line-item / per-line discount editing** — read-only detail
  surface; editing lands with `/billing/invoices/:id/edit`, not here.
- **End-of-day reconciliation banner** — not surfaced.
- **Insurance claim status widget** — only the "Insurance covered (+ provider
  name)" totals row is shown; no claim-tracking surface.

## 6. Web widget / region inventory (Invoice Detail page)

The ported source of truth:
`web-reference/src/pages/app/invoices/InvoiceDetailPage.tsx` (594 lines). It
composes:

| export name / region | Web source file | Underlying Flutter widget (Phase 1) |
|---|---|---|
| `Breadcrumb` (region) | `components/navigation/Breadcrumb.tsx` | reuse `AppBreadcrumb` |
| `PerforatedEdge` (private) | inline in `InvoiceDetailPage.tsx:54–65` | private `_PerforatedEdge` painter derived from `InvoicePerforationDivider` |
| `MetaItem` (private, repeated 4×) | inline `:67–74` | private `_MetaItem` inside `InvoiceMetaGrid` |
| `InvoiceSectionTitle` (private, repeated 2×) | inline `:76–91` | `InvoiceSectionTitle` |
| `LinkCard` (private, used 2× for Patient + Visit) | inline `:93–135` | `InvoiceLinkCard` |
| `paymentMethodIcon` (private util) | inline `:137–150` | reuse `BillingFormatting.paymentMethodIcon` |
| `PaymentLedgerRow` (private, repeated N×) | inline `:152–203` | private `_PaymentLedgerRow` inside `InvoicePaymentsCard` |
| `VoidedNotice` (private) | inline `:205–227` | `InvoiceVoidedNotice` |
| `InvoiceDetailPage` (main, exported) | inline `:229–594` | MODIFY `invoice_detail_page.dart` + the 9 created widgets above |
| Inline `<Card variant="raised">` line-items block | inline `:416–504` | `InvoiceLineItemsCard` |
| Inline `<Card variant="raised">` payments block | inline `:506–580` | `InvoicePaymentsCard` |
| Inline trailing `<Card variant="flat">` footer | inline `:582–591` | `InvoiceDetailFooter` |
| `motion` (`motion.div` + `staggerChildren` + `motionPresets['slide-up'/'row-enter']`) | `lib/motion.ts` | `core/ui/motion/app_motion.dart` |
| `cn` className merge | `lib/cn.ts` | n/a (Material `ThemeData` + explicit `BoxDecoration`) |
| `EmptyState` (error + first-run variants) | `components/empty-state/EmptyState.tsx` | `AppEmptyState` (variants error / firstRun) |
| `PageHeader` (not-found branch only) | `components/layout/PageHeader.tsx` | `AppPageHeader` |
| `Avatar`, `Badge`, `Card`, `MoneyDisplay`, `IconButton`, `Breadcrumb` | `components/avatar`, `components/badge`, `components/card/Card`, `components/money/MoneyDisplay`, `components/actions/IconButton`, `components/navigation/Breadcrumb` | `AppAvatar`, `AppBadge` (via `InvoiceStatusBadge`), `AppCard`, `AppMoneyDisplay`, `AppIconButton`, `AppBreadcrumb` |
| `lucide-react` (`AlertTriangle`, `ArrowRight`, `Banknote`, `Building2`, `CalendarCheck`, `CalendarPlus`, `CreditCard`, `Landmark`, `ReceiptText`, `ShieldCheck`, `Stethoscope`, `Tag`, `UserRound`, `Wallet`) | inline icon imports | Material `Icons.*` (`warning_amber_outlined`, `arrow_forward`, `payments_outlined`, `apartment_outlined`, `event_available_outlined`, `event_busy_outlined`, `credit_card_outlined`, `account_balance_outlined`, `receipt_long_outlined`, `shield_outlined`, `medical_services_outlined`, `local_offer_outlined`, `person_outline`, `account_balance_wallet_outlined` — most already routed via `BillingFormatting.paymentMethodIcon`) |

Cross-cutting web → Flutter notes:

- The web page is **read-only** for the invoice detail surface; all action
  affordances (`Edit`, `Void`, `Record payment`, `Refund`) live **elsewhere**
  in the web app (the visit billing flow / invoice ledger row context menu),
  which is exactly why Phase 2 re-introduces the existing Flutter workflow
  affordances behind a hero-card overflow instead of inline card spurts.
- The web page consumes `getInvoiceById` / `getPatientById` /
  `getVisitForInvoice` / `getBranchById` / `getInsuranceProviderById` from
  `@/data/invoices` (synchronous, in-memory). The Flutter port consumes
  `invoiceDetailViewProvider`, which already returns the
  `InvoiceDetail` envelope with patient/branch/insurance-provider summaries
  embedded (V1-6 backend-first). The visit summary is **not** currently
  embedded — Phase 2 ships either an envelope extension or a separate
  `visitSummaryProvider(family)` lookup; until then the visit LinkCard
  renders the web fallback.
- The web page reads `invoice.createdAt`; the `InvoiceDetail` domain exposes
  `updatedAt` only. Phase 2 extends the domain with `createdAt`. Until then
  the "Created" meta item renders `'—'` (degraded gracefully, mirroring web's
  fallback `'—'` for missing values).
- The web "Billed to" patient name link + the Patient LinkCard's chevron both
  navigate to `patients/${patient.id}`; the Flutter port routes both through
  `context.nav.pushPatientDetail(invoice.patientId)`.
- The web footer is the last region before closing; the Flutter port keeps
  the same order — no end-of-body action banner.
- Motion: web animates the hero `motion.div initial {opacity:0, y:6}
  → animate {opacity:1, y:0}` (220ms) and staggers the two LinkCards via
  `staggerChildren(60)`. The Flutter body's existing `FadeTransition`
  `enterController` (220ms) approximates the hero enter; Phase 2 adds the
  staggered enter for the two LinkCards via `AppMotion.animatedPreset` or a
  pair of `AnimatedSwitcher`s with staggered delays; reduced-motion short-
  circuits both.