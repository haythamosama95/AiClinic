# Breadcrumb Investigation Findings

**Date:** 2026-07-31  
**Scope:** AiClinic Flutter frontend (`/frontend`)  
**Task:** Investigation only — no solution design or implementation.

---

## Executive Summary

Breadcrumbs are **statically hardcoded per page** based on each feature’s assumed “canonical” entry path (e.g. visits always show `Calendar → Appointment → …`). They do **not** read GoRouter navigation history, route `extra`, or any shared navigation-state provider.

Cross-feature navigation (e.g. **Invoices → Visit**, **Patients → Visit**) therefore shows breadcrumbs as if the user arrived from Appointments/Calendar, even when the actual stack contains a different origin.

There is also a **dual breadcrumb architecture**: the authenticated shell top bar derives a single-segment breadcrumb from the current URL (`ShellNavConfig.breadcrumbForLocation`), while several detail pages render a separate, longer trail inside page content via `AppPageHeader` / standalone `AppBreadcrumb`. These layers are not coordinated and visit routes are not mapped in shell config at all.

---

## Root Cause Analysis

### Primary cause: page-local, assumption-based breadcrumb definitions

Detail pages construct `AppBreadcrumb` inline with fixed labels and `onTap` handlers tied to a single feature entry point:

| Page | Hardcoded trail | Assumed origin |
|------|-----------------|----------------|
| `VisitDocumentPage` | `Calendar → {appointment} → {title}` | Appointments calendar |
| `AppointmentDetailPage` | `Calendar → {title}` | Appointments calendar |
| `PatientDetailPage` | `Patients → {name}` | Patients list |
| `InvoiceDetailPage` | `Invoices → {number}` | Invoices list |

None of these consult:

- GoRouter’s navigation stack (`context.canPop()`, matched location chain)
- Route `extra` payloads (only `preview` / `sourceRect` exist today)
- A breadcrumb or navigation-history provider

### Secondary cause: shell top bar uses URL → sidebar-item mapping only

`AuthenticatedShell` passes `ShellNavConfig.breadcrumbForLocation(location)` to `AppTopBar.pageContext`. That function:

1. Maps the current path to a **sidebar nav item id** via `itemIdForLocation`.
2. Returns a **single-segment** breadcrumb for most routes (or two segments for Design System `dev` routes).
3. Does **not** map `/visits/...` routes — `itemIdForLocation` has no visit branch, so visit pages get `null` top-bar breadcrumbs.

This is route-segment-based wayfinding, not history-based wayfinding.

### Tertiary cause: `go` vs `push` inconsistency without breadcrumb compensation

`AppNavigator` mixes navigation modes:

| Method | Behavior | Breadcrumb impact |
|--------|----------|-------------------|
| `pushVisitDocument` | `context.push` — preserves stack | Stack knows origin; breadcrumbs do not |
| `goVisitDocument` | `context.go` — replaces stack | Stack loses origin; breadcrumbs still show Calendar path |
| `goVisitDetail` | `context.go` | Same |

Cross-feature entry points use different modes:

- Invoice → Visit: `pushVisitDocument` (`invoice_detail_page.dart:244`)
- Patient history → Visit: `goVisitDocument` / `goVisitDetail` (`visit_navigation.dart:33–39`)
- Appointment → Visit: `pushVisitDocument` (`appointment_detail_open_visit_button.dart:92,136`)

Even when `push` preserves history, breadcrumbs ignore it. When `go` replaces history, `_goBack` on visit pages falls back to `goAppointmentsCalendar()` (`visit_document_page.dart:62–67`), compounding the wrong-origin assumption.

### No navigation-history infrastructure exists

Grep across `frontend/lib` found:

- No breadcrumb provider/notifier
- No navigation stack snapshot for UI
- Route extras (`PatientDetailRouteExtra`, `AppointmentDetailRouteExtra`) carry list-preview data only — no `sourceRoute`, `breadcrumbTrail`, or `referrer`

`shellChromeProvider` resolves org/branch/user for chrome only — not breadcrumbs.

---

## Routing Solution

**Package:** `go_router` (declared in `pubspec.yaml`, configured in `lib/app/router.dart`).

**Structure:**

- Root `GoRouter` with auth redirects and `refreshListenable`
- `ShellRoute` wrapping authenticated routes with `AuthenticatedShell` (sidebar + top bar + content)
- Feature routes as child `GoRoute`s (patients, appointments, visits, billing, etc.)
- Central navigation API: `AppNavigator` + `context.nav` extension (`lib/app/navigation/app_navigator.dart`)

**Relevant visit/billing routes:**

```
/visits/:visitId/document     → VisitDocumentPage
/visits/:visitId/detail       → VisitDetailPage
/billing/invoices             → InvoiceListPage
/billing/invoices/:invoiceId  → InvoiceDetailPage
/billing/visits/:visitId      → VisitBillingPage
/appointments/:appointmentId  → AppointmentDetailPage
/patients/:patientId          → PatientDetailPage
```

---

## Breadcrumb Data Model / API

### `AppBreadcrumbItem` (`lib/core/ui/components/app_breadcrumb.dart`)

```dart
class AppBreadcrumbItem {
  const AppBreadcrumbItem({required this.label, this.href, this.onTap});
  final String label;
  final String? href;      // showcase/deep-link placeholder; rarely used in production
  final VoidCallback? onTap;
}
```

### `AppBreadcrumb`

- `items: List<AppBreadcrumbItem>`
- Renders chevron-separated trail with RTL mirroring, compact middle truncation when `items.length > 3` and width `< 640px`
- Last item: non-interactive, `Semantics` “Current page”
- Earlier items: `InkWell` when `onTap` or `href` set (requires `Material` ancestor — fixed per `docs/ui/memory/ui-runtime-errors.md`)

### `AppPageHeader`

- Optional `breadcrumb` widget slot above title/description/actions/tabs
- No breadcrumb logic — consumers pass a pre-built `AppBreadcrumb`

### Shell-level API

```dart
// shell_nav_config.dart
static AppBreadcrumb? breadcrumbForLocation(
  String location, {
  Uri? uri,
  void Function(String route)? onNavigate,
});
```

Returns `null` when `itemIdForLocation` is null; otherwise mostly `[AppBreadcrumbItem(label: pageLabel)]`.

### Web reference parity note

The web mock app (`web-reference/src/App.tsx`) also derives top-bar breadcrumbs from **hash route segments**, not navigation history. Page-level breadcrumbs in web invoice/patient detail are similarly static (`Invoices → number`, `Patients → name`). The Flutter visit workspace breadcrumbs (`Calendar → appointment`) appear to mirror an appointments-first clinical workflow that is not generalized for cross-feature entry. Web does not currently ship a visit documentation page with breadcrumbs to compare against.

---

## Architecture: Two Breadcrumb Surfaces

```
┌─────────────────────────────────────────────────────────────┐
│ AppTopBar.pageContext                                       │
│ Source: ShellNavConfig.breadcrumbForLocation(current path) │
│ Typically: single segment ("Invoices", "Patients", …)       │
│ Visit routes: null (no itemId mapping)                      │
│ Hidden when viewport width < 640px                          │
└─────────────────────────────────────────────────────────────┘
┌─────────────────────────────────────────────────────────────┐
│ Page content (AppPageHeader / standalone AppBreadcrumb)     │
│ Source: hardcoded per feature page                          │
│ Multi-segment trails on detail/workspace pages              │
└─────────────────────────────────────────────────────────────┘
```

On wide screens, patient and invoice detail pages can show **both** a single-segment top-bar crumb and a two-segment in-page crumb — redundant and inconsistent with the web reference, where the top bar shows two segments for patient/invoice detail (`App.tsx:78–97`).

---

## Key Files

| File | Role |
|------|------|
| `lib/core/ui/components/app_breadcrumb.dart` | Breadcrumb widget + item model |
| `lib/core/ui/components/app_page_header.dart` | Page header breadcrumb slot |
| `lib/core/ui/components/app_top_bar.dart` | Shell top bar `pageContext` slot |
| `lib/app/shell/authenticated_shell.dart` | Wires shell breadcrumb from current route |
| `lib/app/shell/navigation/shell_nav_config.dart` | `itemIdForLocation`, `breadcrumbForLocation`, layout flags |
| `lib/app/navigation/app_navigator.dart` | Centralized `go`/`push` navigation |
| `lib/app/router.dart` | GoRouter route table |
| `lib/app/app_routes.dart` | Route path constants |
| `lib/features/visits/presentation/pages/visit_document_page.dart` | **Primary bug surface** — Calendar-based crumbs |
| `lib/features/appointments/presentation/pages/appointment_detail_page.dart` | Calendar-based crumbs |
| `lib/features/patients/presentation/pages/patient_detail_page.dart` | Patients-based crumbs |
| `lib/features/billing/presentation/pages/invoice_detail_page.dart` | Invoices-based crumbs |
| `lib/features/visits/presentation/navigation/visit_navigation.dart` | Patient/appointment → visit navigation |
| `lib/features/patients/presentation/navigation/patient_detail_route_extra.dart` | Route extra (preview only) |
| `lib/features/appointments/presentation/navigation/appointment_detail_route_extra.dart` | Route extra (preview only) |

---

## Code Snippets (with paths and line numbers)

### Shell derives top-bar breadcrumb from URL only

```34:43:frontend/lib/app/shell/authenticated_shell.dart
    final routerState = GoRouterState.of(context);
    // Use the actual URI path so pushed routes (e.g. visit billing) get correct shell layout.
    final location = routerState.uri.path;
    final uri = routerState.uri;
    final activeId = ShellNavConfig.itemIdForLocation(location) ?? '';
    final pageContext = ShellNavConfig.breadcrumbForLocation(
      location,
      uri: uri,
      onNavigate: (route) => context.go(route),
    );
```

### `breadcrumbForLocation` — single segment for most routes

```176:201:frontend/lib/app/shell/navigation/shell_nav_config.dart
  static AppBreadcrumb? breadcrumbForLocation(String location, {Uri? uri, void Function(String route)? onNavigate}) {
    final itemId = itemIdForLocation(location);
    if (itemId == null) {
      return null;
    }
    // ... dev section: two segments ...
    final pageLabel = pageTitleForLocation(location) ?? labelFor(itemId);
    if (pageLabel == null) {
      return null;
    }
    return AppBreadcrumb(items: [AppBreadcrumbItem(label: pageLabel)]);
  }
```

### Visit routes not mapped in `itemIdForLocation`

`itemIdForLocation` handles `patients`, `appointments`, `billing`, `invoices`, etc., but **no branch for** `AppRoutes.visits` (`/visits/...`). Visit pages therefore return `null` from `breadcrumbForLocation`.

### Visit document — hardcoded Calendar → Appointment trail

```262:267:frontend/lib/features/visits/presentation/pages/visit_document_page.dart
        final breadcrumb = AppBreadcrumb(
          items: [
            AppBreadcrumbItem(label: 'Calendar', onTap: () => context.nav.goAppointmentsCalendar()),
            AppBreadcrumbItem(label: appointmentLabel, onTap: () => context.nav.pushAppointmentDetail(appointmentId)),
            AppBreadcrumbItem(label: title),
          ],
        );
```

Same pattern in error/not-found states (`visit_document_page.dart:527–531`, `582–585`).

### Visit back navigation fallback to calendar

```62:67:frontend/lib/features/visits/presentation/pages/visit_document_page.dart
  static void _goBack(BuildContext context) {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
      return;
    }
    context.nav.goAppointmentsCalendar();
  }
```

### Cross-feature: Invoice → Visit (push, but visit crumbs ignore origin)

```244:244:frontend/lib/features/billing/presentation/pages/invoice_detail_page.dart
      onAction: () => context.nav.pushVisitDocument(invoice.visitId),
```

### Invoice detail — static Invoices trail (correct when entered from billing)

```309:313:frontend/lib/features/billing/presentation/pages/invoice_detail_page.dart
        AppBreadcrumb(
          items: [
            AppBreadcrumbItem(label: 'Invoices', onTap: widget.onPopToInvoicesList),
            AppBreadcrumbItem(label: displayNumber),
          ],
        ),
```

### Appointment detail — always Calendar parent

```777:784:frontend/lib/features/appointments/presentation/pages/appointment_detail_page.dart
              breadcrumb: AppBreadcrumb(
                items: [
                  AppBreadcrumbItem(
                    label: 'Calendar',
                    onTap: () => context.nav.goAppointmentsCalendar(),
                  ),
                  AppBreadcrumbItem(label: title),
                ],
              ),
```

### Patient detail — static Patients trail

```171:180:frontend/lib/features/patients/presentation/pages/patient_detail_page.dart
  Widget _buildBreadcrumb(BuildContext context, String patientName) {
    final l10n = context.l10n;
    return AppBreadcrumb(
      items: [
        AppBreadcrumbItem(
          label: l10n.patients,
          onTap: () => context.nav.goPatients(),
        ),
        AppBreadcrumbItem(label: patientName),
      ],
    );
  }
```

### Route extras — no breadcrumb/source metadata

```5:10:frontend/lib/features/patients/presentation/navigation/patient_detail_route_extra.dart
class PatientDetailRouteExtra {
  const PatientDetailRouteExtra({this.preview, this.sourceRect});
  final PatientListItem? preview;
  final Rect? sourceRect;
```

---

## All Pages / Screens Using Breadcrumbs

### Production feature pages

| Page | File | Breadcrumb location | Trail |
|------|------|---------------------|-------|
| Visit documentation | `visit_document_page.dart` | In-page (`AppPageHeader` + inline) | `Calendar → {appointment label} → {title}` |
| Visit documentation (loading/error/not-found) | same | In-page | `Calendar → …` (degraded variants) |
| Appointment detail | `appointment_detail_page.dart` | In-page (`AppPageHeader`) | `Calendar → {title}` |
| Patient detail | `patient_detail_page.dart` | In-page (above identity card) | `Patients → {name}` |
| Patient not found | `patient_detail_page.dart` | In-page (`AppPageHeader`) | `Patients → Not found` |
| Invoice detail | `invoice_detail_page.dart` | In-page (standalone `AppBreadcrumb`) | `Invoices → {number}` |
| Invoice not found | `invoice_detail_page.dart` | In-page (`AppPageHeader`) | `Invoices → Not found` |

### Production pages without in-page breadcrumbs (shell may show single segment)

| Page | File | Notes |
|------|------|-------|
| Invoice list | `invoice_list_page.dart` | `AppPageHeader` only, no breadcrumb |
| Invoice editor | `invoice_editor_page.dart` | `AppPageHeader` only |
| Invoice review | `invoice_review_page.dart` | `AppPageHeader` only |
| Visit billing | `visit_billing_page.dart` | `AppPageHeader` only; shell maps to `invoices` |
| Visit detail (chronicle) | `visit_detail_page.dart` | No breadcrumb widget |
| Home, calendar, queue, patients list, clinic management, etc. | various | Shell top bar single segment when mapped |

### Shell top bar (all authenticated routes with mapped `itemId`)

Any route where `ShellNavConfig.itemIdForLocation` returns non-null gets a top-bar breadcrumb (usually one label). Special case: `/foundation-demo?section=…` → `Dev → {section}`.

### Design system / showcase (non-production)

- `breadcrumb_showcase_section.dart`
- `page_header_showcase_section.dart`
- `app_shell_showcase_section.dart`
- `top_bar_showcase_section.dart`
- `component_registry.dart` (breadcrumb entry)

### Placeholder scaffold

- `lib/app/presentation/placeholder_page.dart` — accepts optional `breadcrumb` prop

---

## Examples of Broken Navigation Paths

### 1. Invoices → Visit (reported scenario)

**Steps:**

1. `/billing/invoices` → tap row → `pushBillingInvoiceDetail`
2. `/billing/invoices/:id` — breadcrumb: `Invoices → INV-…` ✓
3. Tap “View visit in patient record” → `pushVisitDocument`
4. `/visits/:visitId/document` — breadcrumb: `Calendar → Jane Doe · May 31, 2026 → Visit documentation` ✗

**Expected (history-aware):** `Invoices → INV-… → Visit documentation` (or similar)

**Top bar:** empty on visit route (unmapped)

### 2. Patients → Visit

**Steps:**

1. `/patients/:id` — breadcrumb: `Patients → {name}` ✓
2. Open visit from patient history → `goVisitDocument` (replaces route)
3. `/visits/:visitId/document` — breadcrumb: `Calendar → …` ✗

**Expected:** `Patients → {name} → Visit documentation`

### 3. Queue → Appointment detail

**Steps:**

1. `/appointments/queue` — shell top bar: “Queue”
2. Row click → `pushAppointmentDetail`
3. `/appointments/:id` — breadcrumb: `Calendar → {title}` ✗

**Expected:** `Queue → {title}` (or `Appointments → …`)

### 4. Visit billing round-trip

**Steps:**

1. Visit documentation → billing phase or `pushVisitBilling` → `/billing/visits/:visitId`
2. No in-page breadcrumb; shell shows `Invoices` only
3. “Back to review” → `goVisitDocument` — returns to Calendar-based visit crumbs ✗

### 5. Deep link / direct URL to visit

**Steps:**

1. Open `/visits/:id/document` directly (no stack)
2. Breadcrumb shows Calendar path; back falls through to `goAppointmentsCalendar()` ✗

### 6. Appointment → Visit (works only by coincidence)

**Steps:**

1. Calendar → appointment detail → Open visit
2. `Calendar → appointment → visit` — **appears correct** because visit page assumes calendar origin

This is the only cross-page flow where hardcoded crumbs match user path.

---

## Cross-Feature Navigation Entry Points (for fix scoping)

| Source | Target | Navigation call | File |
|--------|--------|-----------------|------|
| Invoice detail | Visit document | `pushVisitDocument` | `invoice_detail_page.dart:244` |
| Invoice detail | Patient detail | `pushPatientDetail` | `invoice_detail_page.dart:299,321` |
| Patient invoice card | Invoice detail | `pushBillingInvoiceDetail` | `patient_invoice_card.dart:59` |
| Patient history | Visit | `goVisitDocument` / `goVisitDetail` | `visit_navigation.dart:27–41` |
| Appointment detail | Visit | `pushVisitDocument` | `appointment_detail_open_visit_button.dart` |
| Appointment detail | Patient | `pushPatientDetail` | `appointment_detail_page.dart:759` |
| Queue table | Appointment detail | `pushAppointmentDetail` | `queue_appointments_table.dart:173` |
| Calendar | Appointment detail | `pushAppointmentDetail` | `appointment_calendar_page.dart:1926` |
| Visit summary | Visit billing | `pushVisitBilling` | `visit_summary_section.dart:102` |
| Visit billing | Visit document | `goVisitDocument` | `visit_billing_page.dart:36` |
| Visit submitted dialog | Appointment detail | `pushAppointmentDetail` | `visit_submitted_dialog.dart:146` |

---

## Navigation State Patterns Today

| Pattern | Used for | Breadcrumb relevance |
|---------|----------|----------------------|
| `context.go(route)` | Sidebar nav, replacing hub routes | Replaces stack; no trail preserved |
| `context.push(route, extra: …)` | Detail overlays from lists | Stack preserved; breadcrumbs ignore stack |
| `context.pop()` / `canPop()` | Back from pushed routes | Invoice detail `_popToInvoicesList`; visit `_goBack` |
| `PatientDetailRouteExtra` / `AppointmentDetailRouteExtra` | List preview + hero animation | No source route |
| `ShellNavConfig.itemIdForLocation` | Sidebar active state + shell breadcrumb | URL prefix heuristics, not history |
| `ShellNavConfig.isFullWidthLocation` | Layout | Visit workspace treated as full-width |

---

## Constraints and Conventions to Respect

### Design system

- Use existing `AppBreadcrumb` / `AppBreadcrumbItem` — web parity component (`core/ui/components/app_breadcrumb.dart`)
- Breadcrumbs belong in `AppTopBar.pageContext` (shell) and/or `AppPageHeader.breadcrumb` (page) per `docs/ui/design-system/05-patterns.md` and `04-components.md`
- RTL: chevrons auto-mirror; use `Directionality.of(context)` — do not hardcode LTR separators
- Compact truncation: middle segments collapse when `items.length > 3` and width `< 640px`
- `InkWell` requires `Material` ancestor (documented runtime fix)
- Top bar hides `pageContext` when width `< 640px` (`app_top_bar.dart:100–102`) — in-page breadcrumbs remain important on mobile

### Navigation conventions

- Prefer `AppNavigator` / `context.nav` over raw `context.go`/`push` (`app_navigator.dart` header comment)
- `AuthenticatedShell` uses `routerState.uri.path` (not only `matchedLocation`) for pushed routes — any fix should remain compatible
- Full-width visit workspace: `ShellNavConfig._isVisitWorkspaceLocation` — layout must not regress

### Localization

- Patient breadcrumbs use `context.l10n.patients` — other pages use hardcoded English (`'Calendar'`, `'Invoices'`, `'Visit documentation'`)
- Mixed i18n is a pre-existing inconsistency

### Web reference

- Static per-feature crumbs in web invoice/patient pages
- Top bar uses segment-based two-level crumbs for patients/invoices detail
- Navigation implementation plan (`docs/ui/translation-plan/navigation-implementation-plan.md:148`) explicitly deferred “Real router/navigation wiring (GoRouter routes, deep-link breadcrumbs)” — production shell wiring exists but is still URL-based, not history-based

### Out of scope for this investigation

- Whether breadcrumbs should live only in top bar vs page header (architectural decision for design subagent)
- Whether `go` vs `push` should change for visit entry (behavioral decision)

---

## Test Infrastructure

### Widget tests asserting breadcrumb behavior

| Test file | Coverage |
|-----------|----------|
| `test/widget/visits/visit_document_page_test.dart` | Calendar crumb tap → calendar stub; appointment crumb tap → appointment stub; expects `_appointmentBreadcrumbLabel` |
| `test/widget/billing/invoice_detail_page_test.dart` | Invoices crumb → pop/push back to list; visit link → visit document stub |
| `test/widget/appointments/appointment_detail_page_test.dart` | Calendar crumb → calendar route |
| `test/widget/patients/patient_detail_page_test.dart` | Patients crumb → `goPatients` via router log |

### Test harnesses with GoRouter stubs

- `test/widget/visits/visit_widget_test_harness.dart` — `createVisitsTestRouter`, stub routes for calendar/appointment/visit
- `test/widget/billing/billing_widget_test_harness.dart` — `createBillingTestRouter`
- `test/widget/patients/patients_widget_test_harness.dart` — `createPatientsTestRouter`
- `test/widget/appointments/detail_widget_test_harness.dart` — `buildDetailTestRouter`

### Unit tests for route extras

- `test/unit/patients/patient_detail_route_extra_test.dart`
- `test/unit/appointments/appointment_detail_route_extra_test.dart`

### Gap

No tests cover cross-feature breadcrumb correctness (e.g. invoice → visit should show Invoices parent). Existing visit tests **encode the Calendar-based assumption** as expected behavior.

---

## Summary for Design Subagent

1. **Fix target:** Dynamic breadcrumbs reflecting actual navigation history (or explicit navigation context), not per-page canonical paths.
2. **Highest-impact file:** `visit_document_page.dart` — always assumes Calendar/Appointment origin.
3. **System gap:** No shared breadcrumb state; route extras don't carry referrer; shell config doesn't map visit routes.
4. **Dual rendering:** Top bar (URL → nav item) vs page content (hardcoded) — decide single source of truth.
5. **Tests will need updating:** Visit/appointment tests currently assert Calendar navigation from breadcrumbs.
6. **Related back-navigation bug:** Visit `_goBack` fallback to calendar when stack empty — same root assumption.

---

## Investigation Checklist

- [x] Find all breadcrumb-related code
- [x] Understand how routes/pages define breadcrumbs
- [x] Find cross-feature navigation examples
- [x] Identify routing solution (go_router)
- [x] List pages using breadcrumbs
- [x] Note navigation state patterns
- [x] Document test infrastructure
