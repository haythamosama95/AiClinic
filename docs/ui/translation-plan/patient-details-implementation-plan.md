# Implementation Plan — Patient Details Page (Flutter Port)

Spec target: port the **Patient Details** production page of `web-reference/`
(`web-reference/src/pages/app/patients/PatientDetailPage.tsx`) — the screen opened when a
patient is tapped from the Patients list — into the Flutter `frontend/` patients feature,
under `frontend/lib/features/patients/presentation/`. The Patients **list** page is already
shipped and is explicitly **out of scope**.

> This is a **feature-page** port, not a design-system showcase group port. There is no
> `ShowcaseGroupId` entry for "patient details" and no Dev components-page registration to flip.
> The binding source of truth is the single web production file
> `PatientDetailPage.tsx` (515 lines) plus its colocated sub-components
> (`VisitCard`, `InvoiceCard`, `DocumentCard`, `RecordCardGrid`, `RecordCardShell`).
> Wiring is therefore **route + provider** wiring, not `component_registry.dart` wiring.

---

## 0. Ambiguities & Design Decisions (resolve before coding)

> ⚠️ **Set-specific runtime-regression watchlist (from the UI runtime-errors checklist):**
> 1. **Material ancestor.** The web `RecordCardShell` is a custom `motion.article` with a
>    teal-tinted linear-gradient `DecoratedBox` + `box-shadow`. Any Flutter card built from
>    `DecoratedBox`/`Container` gradients that hosts an `AppButton`/`AppAvatar`/`InkWell`
>    ripple **must** sit beneath a `Material(type: MaterialType.transparency)` (or wrap the
>    interactive child in `Material`) so the ripple/inkwell has a Material ancestor — otherwise
>    the ripple is clipped or asserts. Bear in mind for every record card.
> 2. **`intl` locale-specific `DateFormat`.** The web `formatDate` uses `en-GB` `day month year`.
>    The Flutter app already calls `ensureIntlDateFormattingInitialized()` at startup and ships
>    `package:intl`. Date-stamp month glyphs (`DateFormat.MMM`) and weekday glyphs
>    (`DateFormat.EEEE`) must use the active locale from `devPreviewProvider`/`Localizations` —
>    do **not** hard-code `Locale('en','GB')`. Reuse `PatientPresentationFormatting.date`
>    (`yMMMd`) for the DOB line; for the card date-stamp columns, build a small
>    `DateFormat('d')` / `DateFormat.MMM` / `DateFormat('y')` trio off the resolved locale.
> 3. **`MediaQuery`/inherited reads in `initState`.** `patients_page.dart` drives its enter
>    animation from `SingleTickerProviderStateMixin` and reads
>    `AppMotion.prefersReducedMotion(context)` in `initState`-adjacent build — keep that pattern
>    but read `MediaQuery`/`Directionality` only inside `build` for the detail page; the page's
>    `AnimationController` may be created in `initState` but must not call
>    `context.appColors`/`MediaQuery` there.
> 4. **`FocusNode` sharing.** Not applicable (no focus-receiving inputs on this page). Safe.

1. **forui vs native Material.** As with Actions/Inputs, the shipping convention is **native
   Material** under `core/ui/components/app_*.dart`; `forui` is imported nowhere. The patient
   detail page is **feature code**, so it imports `App*` widgets from the
   `core/ui/widgets/widgets.dart` barrel only — never Material internals directly. No new
   `core/ui/components/app_*.dart` files are introduced by this plan (all new widgets are
   feature-local under `presentation/widgets/`). **Decision: native Material via existing App
   abstractions; `forui-wrappers.md` is superseded.**

2. **Web fields that do not exist in the Flutter data layer are dropped.** Per the task brief,
   any web-reference field with no Flutter counterpart is ignored rather than fabricated.

   | Web field | Flutter `PatientDetail` counterpart | Decision |
   |---|---|---|
   | `mrn` | — | **ignored** |
| `status` (active/inactive/archived) | — | **ignored** (no status Badge) |
  | `email` | — | **ignored** (no Mail row) |
  | `address` | — | **ignored** (no MapPin row) |

   **Phase 4 adds** a **Billing** tab (the web's 3rd tab) bound to the Flutter
   `patientInvoicesProvider`, a **Patient edit** dialog (web has none — synthesized from the
   Flutter Add-patient dialog), and **EN/AR production localization** (web's `DirectionProvider`
   is the model; the Flutter port only mirrored the showcase half before). See §3 Phase 4.

   Flutter-own fields **not** on the web identity line — `maritalStatus`, `notes`, `branchName`,
   `createdAt`, `createdByDisplay` — are **optional enrichments**: the implementer MAY surface
   `branchName` as a secondary meta line under the contact row to avoid an empty header, but it
   is not part of the binding web layout and must not change the primary identity rhythm.

3. **Tab mapping.** The web has 3 tabs `Visits / Documents / Billing`. The Flutter patients
   feature exposes exactly three ready providers whose shape maps cleanly:
   `patientPastVisitsProvider` (`List<VisitListItem>`),
   `patientUpcomingAppointmentsProvider` (`List<AppointmentListItem>`),
   `patientVisitDocumentsProvider` (`List<PatientVisitDocument>`). There is **no billing/
   invoice** provider in the patients feature. **Decision:** drop the web `Billing` tab and split
   the web `Visits` tab into **Past visits** and **Upcoming**, yielding the 3 tabs
   **Past visits / Upcoming / Documents** — a 1:1 match to the three shipped providers. The
   existing `patientDetailHistoryTabProvider` enum (`past`/`upcoming`) only covers two of these;
   it is **superseded** for this page by a new local 3-value `PatientDetailSection` enum held in
   page-local state (the page is a `ConsumerStatefulWidget`, mirroring `patients_page.dart`).
   Leave `patientDetailHistoryTabProvider` in place (other future consumers may use it) — do not
   delete it.

4. **Invoice card / `MoneyDisplay`.** Entirely dropped — no billing data layer. Do not port
   `InvoiceCard`, `INVOICE_STATUS_BAND`, `invoiceDueMeta`, or `invoiceStatusColor`.

5. **Identity header card vs `AppPageHeader`.** The web identity section is a `Card variant=raised`
   containing avatar + title + badge + meta + contact rows **and** the tab strip inside the card
   (`<div className="border-t … px-6"><Tabs/></div>`). **Decision:** reproduce this faithfully —
   a raised `AppCard` hosts the identity block, with the `AppTabs` strip docked to the card's
   bottom edge across a `borderSubtle` divider (mirrors the web). `AppPageHeader` is used **only**
   in the not-found branch (web `PageHeader` with "Patient not found"). The shell already
   contributes a sidebar breadcrumb; the page additionally renders an `AppBreadcrumb`
   `Patients › <name>` above the identity card (web does this) for back-navigation affordance.

6. **Instant header from preview.** `pushPatientDetail` already attaches
   `PatientDetailRouteExtra(preview: PatientListItem?)` (list-row snapshot). **Decision:** render
   the identity header immediately from `preview` while `patientDetailProvider` is
   `AsyncLoading`, then swap to the full `PatientDetail` once it resolves (preview lacks
   `maritalStatus`/`notes`/`branchName`/audit, but those are optional). This matches the spec at
   `docs/specs/patient-detail-loading-plan.md` and avoids a flash of skeleton for the header.

7. **Responsive card grid.** Web `RecordCardGrid` uses `sm:grid-cols-2 xl:grid-cols-3`. Flutter:
   `LayoutBuilder` → 1 col below 640px, 2 cols 640–1280px, 3 cols ≥1280px via `SliverGrid`/
   `GridView.count` with `AppSpacing.space4` gutters. Stagger via `AppMotion` (reduced-motion
   aware) mirroring `patients_page.dart`'s enter pattern — but per-card, not per-grid, to match
   the web `staggerChildren(45)`.

8. **Record card shell.** Web `RecordCardShell` is a teal-tinted gradient `motion.article` with
   hover-lift + elevation transitions. **Decision:** create a single **feature-local** reusable
   `PatientRecordCard` shell (under `presentation/widgets/patient_record_card.dart`) that wraps
   `AppCard`-equivalent decoration (rounded `AppRadius.x2l`, `borderSubtle`, teal gradient via
   `context.appColors`, `AppElevation.level1`→`level2` on hover) and lifts on
   `AppPressable`/`MouseRegion` hover. It provides a single `child` slot. The two card variants
   (`PatientVisitCard`, `PatientDocumentCard`) compose it. The upcoming-appointment card reuses
   the visit card's date-stamp column with appointment data.

9. **i18n / RTL.** The page is in the production app (RTL-aware via `AppTheme`). Date-stamp
   columns and contact rows must respect `Directionality.of(context)`. Icons
   (`Phone`, `Building2`, `Download`) mirror in RTL automatically via `Icon` + `matchTextDirection`
   where used as leading glyphs. No AR copy is hardcoded in this plan; copy stays in EN and is
   localizable later via the existing `l10n` machinery (out of scope to wire now).

10. **Download wiring.** Web `DocumentCard` calls `downloadPatientDocument(document, visit)`.
    Flutter `VisitAttachmentItem` carries `canDownload: bool` but **no download-url/byte-stream
    accessor is confirmed in the patients/visits data layer**. **Decision:** render the
    "Download file" `AppButton` (secondary, sm) only when `attachment.canDownload` is true; the
    actual download invocation is **deferred** (§6) — gate the button `onPressed` behind a
    TODO/feature-flag that no-ops or calls an existing visit-attachment download path the
    implementer must locate (`visits` feature). Do not fabricate a download repository.

---

## 1. Existing App assets to reuse (do not recreate)

| Asset | Path | Used by |
|---|---|---|
| `AppPageHeader` | `core/ui/components/app_page_header.dart` | not-found branch header (`title`, `breadcrumb`) |
| `AppBreadcrumb` | `core/ui/components/app_breadcrumb.dart` | `Patients › <name>` above identity card |
| `AppCard` | `core/ui/components/app_card.dart` | raised identity card (reference decoration); record cards may extend |
| `AppAvatar` (`AvatarSize.lg`) | `core/ui/components/app_avatar.dart` | identity avatar (`size='xl'` web → `lg` Flutter; sizes are sm/md/lg) |
| `AppBadge` | `core/ui/components/app_badge.dart` | (optional) visit-status pill on visit cards |
| `AppTabs` | `core/ui/components/app_tabs.dart` | Past visits / Upcoming / Documents strip |
| `AppEmptyState` + `EmptyStateAction` | `core/ui/components/app_empty_state.dart` | not-found error + per-tab first-run empties |
| `AppErrorState` | `core/ui/components/app_error_state.dart` | `patientDetailProvider` error / permission StateError |
| `AppSkeletonizerZone` / `AppSkeleton` | `core/ui/components/app_skeletonizer_zone.dart`, `app_skeleton.dart` | skeletonized tab body while async loads |
| `AppButton` | `core/ui/components/app_button.dart` | "Download file" (secondary, sm); not-found "Back to patients" |
| `AppMotion`, `AppMotionPreset`, `AppMotion.prefersReducedMotion` | `core/ui/motion/app_motion.dart` | card-grid stagger + page enter |
| Theme: `context.appColors` (`AppSemanticColors`), `AppSpacing`, `AppRadius`, `AppTypography`, `AppElevation` | `core/ui/theme/*` | every widget |
| `widgets.dart` barrel | `core/ui/widgets/widgets.dart` | single import for all of the above |
| `PatientPresentationFormatting` (`date`, `dateOfBirthLabel`, `ageGenderLabel`, `orDash`, `displayId`) | `features/patients/presentation/utils/patient_presentation_formatting.dart` | DOB line, age/gender line, phone fallback; **only** age impl — do not reimplement |
| `patientDetailProvider` (`FutureProvider.autoDispose.family<PatientDetail,String>`) | `features/patients/presentation/providers/patient_detail_provider.dart` | identity + audit |
| `patientPastVisitsProvider` (`FutureProvider.autoDispose.family<List<VisitListItem>,String>`) | `features/patients/presentation/providers/patient_detail_history_provider.dart:55` | Past visits tab |
| `patientUpcomingAppointmentsProvider` (`…family<List<AppointmentListItem>,PatientDetailHistoryQuery>`) | `…/patient_detail_history_provider.dart:65` | Upcoming tab (needs active `branchId` from `authSessionProvider`/`patientDetailProvider`) |
| `patientVisitDocumentsProvider` (`…family<List<PatientVisitDocument>,String>`) | `…/patient_detail_history_provider.dart:87` | Documents tab |
| `PatientDetailRouteExtra` (`preview: PatientListItem?`, `sourceRect: Rect?`) | `features/patients/presentation/navigation/patient_detail_route_extra.dart` | instant header from list row |
| `context.nav.goPatients()` / `pushPatientDetail` | `app/navigation/app_navigator.dart` | "Back to patients" action; already used by list |
| `authSessionProvider` (`activeBranchId`) | `app/providers/auth_session_provider.dart` | `PatientDetailHistoryQuery.branchId` for upcoming |

#### Phase 4 — additional assets to reuse

| Asset | Path | Used by |
|---|---|---|
| `patientInvoicesProvider` (`FutureProvider.autoDispose.family<InvoiceListPageResult,String>`) | `features/billing/presentation/providers/invoice_detail_provider.dart:53` | Billing tab (by `patientId`) |
| `InvoiceListItem` (summary row: `id, invoiceNumber?, status, patientDisplayName?, subtotal/discountAmount/insuranceCoveredAmount/paidAmount/balance` (Money), `createdAt, issuedAt?`) | `features/billing/domain/invoice_list_item.dart:7` | invoice cards |
| `InvoiceStatus` enum (`draft, issued, partiallyPaid, paid, voided` + `label`, `isTerminal`, `isVoidable`) | `features/billing/domain/invoice_status.dart:1` | status `AppBadge` |
| `BillingFormatting` (`statusBadgeStyle(InvoiceStatus)` → variant+icon; currency/date formatters; `invoiceDisplayNumber`) | `features/billing/presentation/utils/billing_formatting.dart:1` | invoice card colors + money |
| `Money` (Decimal-backed; `wireValue`, `parse`, arithmetic) | `features/billing/domain/money.dart:6` | invoice `balance` rendering |
| `AuthRouteGuard.canAccessInvoiceList` | `core/auth/auth_route_guard.dart` | billing tab permission gate |
| `UpdatePatientInput` (`patientId, fullName, expectedUpdatedAt, phone?, dateOfBirth?, gender?, maritalStatus?, notes?, acknowledgeDuplicate`) | `features/patients/domain/update_patient_input.dart:5` | edit notifier |
| `updatePatientUseCaseProvider` / `UpdatePatient` | `domain/usecases/update_patient.dart` + `patient_use_case_providers.dart` | edit notifier submit |
| `checkDuplicatesUseCaseProvider` / `CheckDuplicates` (already has `excludePatientId`) | `domain/usecases/check_duplicates.dart` | edit duplicate detection (self-excluded) |
| `PatientRegistrationForm` + `PatientFormErrors` + `validateRegistration` | `models/patient_registration_form.dart` | edit form values (prefill from `PatientDetail`) |
| `AddPatientFormFields` (branch banner + identity preview + Patient details + Clinical notes sections) | `presentation/add_patient/add_patient_form_fields.dart` | **refactor for reuse** by `EditPatientFormFields` (prefill) |
| `PatientRegistrationNotifier` (the add flow template: validate → checkDuplicates → create → toast) | `presentation/providers/patient_registration_notifier.dart` | **template** for `PatientEditNotifier` |
| `DuplicatePatientDialog` | `presentation/add_patient/duplicate_patient_dialog.dart` | edit duplicate confirmation (reused as-is) |
| `patientMessageForRpc` (RPC failure → user message) | `features/patients/application/patient_rpc_messages.dart` | edit error mapping |
| `AppLocalizations` (generated, 31 keys, `localizationsDelegates`, `delegate`, `supportedLocales=[en]`) + `app_en.arb` | `frontend/lib/l10n/app_localizations.dart`, `frontend/lib/l10n/app_en.arb` | localization wiring |
| `l10n.yaml` (`arb-dir=lib/l10n`, template `app_en.arb`, gen-l10n on `generate: true`) | `frontend/l10n.yaml` | adding `app_ar.arb` |
| `ensureIntlDateFormattingInitialized()` (preloads `en_GB` + `ar_EG`) | `frontend/lib/core/utils/intl_date_formatting.dart:14` | Arabic date formatting once locale wired |
| `themeModeProvider` (persisted-via-SharedPreferences Riverpod notifier) | `app/providers/theme_provider.dart` | pattern for the new `localeProvider` |
| `flutter_localizations` + `intl` deps, `generate: true` | `pubspec.yaml:33-35,89` | localization deps (present) |
| Web `DirectionProvider` (persisted, locale↔direction coupled) | `web-reference/src/providers/DirectionProvider.tsx` | model for `localeProvider` coupling + persistence |

### Domain models in play

- `PatientDetail` (`features/patients/domain/patient_detail.dart:9`): `id, fullName, phone?, dateOfBirth?, gender?, maritalStatus?, notes?, branchId, branchName, createdAt, updatedAt, createdByDisplay?`.
- `PatientListItem` (preview, `domain/patient_list_item.dart`): `id, fullName, phone?, dateOfBirth?, gender?, lastVisitAt?, nextAppointmentAt?, registeringBranchId, registeringBranchName`.
- `VisitListItem` (`features/visits/domain/visit_list_item.dart:7`): `id, visitDate, doctorName, status (VisitStatus: inProgress|completed), branchName`.
- `AppointmentListItem` (`features/appointments/domain/appointment_list_item.dart:8`): `id, patientId, patientName, doctorId?, doctorName? (doctorDisplayName fallback 'Unassigned'), startTime, endTime, type, status, updatedAt?, checkedInAt?, inProgressAt?`.
- `PatientVisitDocument` (`domain/patient_visit_document.dart:6`): `visitId, visitDate, attachment: VisitAttachmentItem`.
- `VisitAttachmentItem` (`features/visits/domain/visit_attachment_item.dart:8`): `id, fileType (pdf|docx|jpeg|png → .label uppercase), label?, uploadedBy, uploadedByName?, sizeBytes, createdAt, canDownload, canDelete`.
- `VisitAttachmentFileType.label` already returns `PDF/DOCX/JPEG/PNG` — reuse it (no `documentExtension` helper needed).

---

## 2. New feature-local widgets to introduce (no new `core/ui` files)

All new files live under `frontend/lib/features/patients/presentation/widgets/` (feature-local).
No new `core/ui/components/app_*.dart` and **no** barrel (`widgets.dart`) edit is required, since
these are feature widgets consumed only by the detail page.

| File (`features/patients/presentation/widgets/`) | Export name | Web analog | Purpose | Phase |
|---|---|---|---|---|
| `patient_detail_section.dart` | `PatientDetailSection` enum (`pastVisits`, `upcoming`, `documents`) + labels | `TAB_ITEMS` (3 of them, renamed) | page-local tab state; replaces per-page `String` tab | 1 |
| `patient_record_card.dart` | `PatientRecordCard` | `RecordCardShell` | reusable raised/teal-gradient hover-lift `Material`-backed artboard slot hosting a single `child` + optional `leading` column | 2 |
| `patient_date_stamp.dart` | `PatientDateStamp` | `toDateStamp` left column | `day / MONTH / year` (+ optional weekday) stack; locale-aware via resolved `DateFormat`; reused by visit + document + linked-visit mini cards | 2 |
| `patient_visit_card.dart` | `PatientVisitCard` | `VisitCard` | `PatientRecordCard` with date-stamp left column + doctor initials circle + `doctorName`/"Attending physician" + branch pill; optional `status` `AppBadge` (frontend-only) | 2 |
| `patient_upcoming_appointment_card.dart` | `PatientUpcomingAppointmentCard` | (`VisitCard` analog) | reuses `PatientRecordCard` + `PatientDateStamp` with `AppointmentListItem`: `startTime` date-stamp, `doctorDisplayName`, appointment `type`/`status` `AppBadge`, time range (`startTime`–`endTime`) | 2 |
| `patient_record_grid.dart` | `PatientRecordGrid` | `RecordCardGrid` | responsive 1/2/3-col `SliverGrid`/`GridView.count` with `AppSpacing.space4` gutters + `AppMotion` stagger | 2 |
| `patient_document_card.dart` | `PatientDocumentCard` | `DocumentCard` | `PatientRecordCard` with file-type/size left column + `label`/"Patient file" overline + linked-visit mini-card (`visitDate` date-stamp only — no doctor/branch available on `PatientVisitDocument`) + gated "Download file" `AppButton` | 3 |

The page itself: **`features/patients/presentation/pages/patient_detail_page.dart`** → `PatientDetailPage`
(`ConsumerStatefulWidget` with `SingleTickerProviderStateMixin`, mirroring `patients_page.dart:22`).

### Phase 4 — additional feature-local + app-level widgets

| File | Export name | Web analog | Purpose | Phase |
|---|---|---|---|---|
| `features/patients/presentation/widgets/patient_invoice_card.dart` | `PatientInvoiceCard` | `InvoiceCard` (`PatientDetailPage.tsx:219-267`) | invoice record card bound to `InvoiceListItem` — status band + balance + issued line (no due-date per Flutter data rule) | 4 |
| `features/patients/presentation/providers/patient_edit_notifier.dart` | `PatientEditNotifier`, `PatientEditState`, `patientEditProvider` | (none on web — synthesized from Flutter `PatientRegistrationNotifier`) | family-by-`patientId` edit form state: preload → validate → `checkDuplicates` (self-excluded) → `updatePatient` → toast → invalidate detail | 4 |
| `features/patients/presentation/edit_patient/edit_patient_dialog.dart` | `EditPatientDialog` | (none on web — mirrors Flutter `AddPatientDialog`) | `AppDialog` hosting `EditPatientFormFields` + reused `DuplicatePatientDialog` | 4 |
| `features/patients/presentation/edit_patient/edit_patient_form_fields.dart` | `EditPatientFormFields` | (none — mirrors Flutter `AddPatientFormFields`) | prefill variant of the add fields; **preferred: refactor shared `AddPatientFormFields` to accept `initialValues`+`branchName`+`previewSubtitle` instead** | 4 |
| `frontend/lib/app/providers/locale_provider.dart` | `localeProvider`, `LocaleNotifier` | web `DirectionProvider` | persisted Riverpod `Locale` notifier (SharedPreferences), couples `ar`→RTL at `MaterialApp` builder | 4 |
| `frontend/lib/l10n/app_ar.arb` | (ARB catalog) | — | Arabic translation of all keys in `app_en.arb` + new patient-detail/edit keys | 4 |
| `frontend/lib/core/ui/l10n/app_localizations_x.dart` | `context.l10n` extension | — | `AppLocalizations.of(context)!` accessor for feature widgets | 4 |
| **MOD** `presentation/widgets/patient_detail_section.dart` | `PatientDetailSection.billing` (4th) | web `billing` tab | enables the billing tab | 4 |
| **MOD** `core/ui/...` — none (l10n wiring is in `app/app.dart`) | — | — | no new `core/ui/components/app_*.dart`; the `context.l10n` extension lives under `core/ui/l10n/` (a new subfolder) | 4 |

### Local tab-state decision
`PatientDetailSection` is plain `enum` + page `State` field (default `pastVisits`). No Riverpod
provider for the tab — keeps it scoped to the page instance (autoDispose detail providers already
rebuild on patientId change). Do **not** touch `patientDetailHistoryTabProvider`.

---

## 3. Phasing

> Rationale: **Phase 1** = the page shell — routing, identity header (instant-from-preview),
> not-found/error/loading, and the 3-tab scaffold rendering empty placeholders. Independently
> shippable: tapping a patient opens a real screen with the header and tab strip. **Phase 2** =
> the history timeline — record-card shell, date-stamp, responsive grid, Past-visits and
> Upcoming-appointment cards + their empty states. Independently shippable: two of three tabs
> populate. **Phase 3** = the Documents tab (document cards with linked-visit mini-card +
> download gating) + skeletonized-loading polish + motion, plus final router & analyze wiring.

### Phase 1 — Page shell, routing, identity header, tab scaffold

| Element | Widget(s) to create | File(s) | Reuse | Wrapper | Deps |
|---|---|---|---|---|---|
| Page | `PatientDetailPage` (`ConsumerStatefulWidget`, `SingleTickerProviderStateMixin`) — reads `patientId` + `PatientDetailRouteExtra.fromExtra(state.extra)` via constructor (router builder unpacks); watches `patientDetailProvider(patientId)` | CREATE `presentation/pages/patient_detail_page.dart` | `WidgetsApp`-injected `PatientDetail`/preview, `AppMotion`, theme | NEW | preview + provider |
| Tab state | `PatientDetailSection` enum + `State` field | CREATE `presentation/widgets/patient_detail_section.dart` | nothing | NEW (enum) | none |
| Identity card | `_PatientIdentityCard` (private in page file) — raised `AppCard`; `Row`: `AppAvatar(name, size: lg)` + `Column`: `<h1> fullName` (`AppTypography.h1(context)`) + sub-line `gender · label DOB (age yrs)` via `PatientPresentationFormatting.ageGenderLabel`/`dateOfBirthLabel` + `Phone` icon row (`phone` via `orDash`); optional `branchName` meta line (frontend-only optional) | inline in page file | `AppCard`, `AppAvatar`, `AppTypography`, `AppSemanticColors`, `PatientPresentationFormatting`, `Icon(Phone)` | NEW (private) | preview or `PatientDetail` |
| Tabs strip | `AppTabs` docked to card bottom across a `borderSubtle` `Divider`, items `Past visits / Upcoming / Documents` bound to `PatientDetailSection` | inline in page file | `AppTabs`, `AppSemanticColors.borderSubtle` | NEW (private) | `PatientDetailSection` |
| Breadcrumb | `AppBreadcrumb` `Patients → <name>` above the card; `onTap` Patients → `context.nav.goPatients()` | inline in page file | `AppBreadcrumb`, `context.nav` | NEW (private) | none |
| Not-found branch | `AppPageHeader(title:'Patient not found', breadcrumb: Patients → 'Not found')` + `AppEmptyState` error variant with `EmptyStateAction('Back to patients', → context.nav.goPatients())` | inline in page file | `AppPageHeader`, `AppEmptyState` | NEW (private) | `context.nav` |
| Error branch | `patientDetailProvider` in `AsyncError` (incl. permission `StateError`) → `AppErrorState` with retry → `ref.invalidate(patientDetailProvider(patientId))` | inline in page file | `AppErrorState` | NEW (private) | provider |
| Loading branch | header from `preview` (if present); tab body shows `AppSkeletonizerZone` blocks (mirrors web `PatientDetailSkeleton`) until provider resolves; if no preview, header itself is skeletonized | inline in page file | `AppSkeletonizerZone`, `AppSkeleton` | NEW (private) | preview |
| Tab body scaffold | `IndexedStack`/conditional switch over `PatientDetailSection` rendering Phase-2/3 grids; in Phase 1 each branch is a "Coming soon" `AppEmptyState` placeholder so the shell ships standalone | inline in page file | `AppEmptyState` | NEW (private) | `PatientDetailSection` |

**Wiring (Phase 1):**
1. Rebind the route at `frontend/lib/app/router.dart:85`:
   `GoRoute(path: '${AppRoutes.patients}/:patientId', builder: (context, state) => PatientDetailPage(patientId: state.pathParameters['patientId']!, extra: PatientDetailRouteExtra.fromExtra(state.extra)))`.
   Leave the `/patients/:patientId/edit` placeholder untouched (edit is out of scope).
2. Import `patient_detail_page.dart` + `patient_detail_route_extra.dart` + `PatientDetailSection` in `router.dart` as needed.
3. Confirm `context.nav.pushPatientDetail` already passes `extra` (it does — `app_navigator.dart:36`).
4. Run `flutter analyze` on the new/changed files.

### Phase 2 — History timeline cards (Past visits + Upcoming)

| Element | Widget(s) | File(s) | Reuse | Wrapper | Deps |
|---|---|---|---|---|---|
| Record-card shell | `PatientRecordCard` (`{child, leading?, className?}`) — `Material(type: transparency)` ancestor + teal-gradient `DecoratedBox` (`AppSemanticColors.surfaceDefault`→teal mix), `AppRadius.x2l`, `borderSubtle`, `AppElevation.level1`→`level2` via `MouseRegion`/`AppPressable` hover (`-translate-y-0.5` analog: subtle `Transform.translate` on hover), reduced-motion aware | CREATE `presentation/widgets/patient_record_card.dart` | `AppPressable`/`MouseRegion`, `context.appColors`, `AppRadius`, `AppElevation`, `AppMotion` | NEW | none |
| Date stamp | `PatientDateStamp({date, showWeekday: false})` — `Column`: `AppTypography.display(context)` day, `overline` short-month (uppercase, locale-aware `DateFormat.MMM`), `caption` year; optional `weekday` (`DateFormat.EEEE`) below for visit card | CREATE `presentation/widgets/patient_date_stamp.dart` | `AppTypography`, resolved `DateFormat` from `Localizations.localeOf` | NEW | none |
| Visit card | `PatientVisitCard({visit: VisitListItem})` — `PatientRecordCard(leading: PatientDateStamp(visit.visitDate, showWeekday: false)); body`: doctor initials circle (`40px`, mono caption) + `visit.doctorName` (`bodyStrong`) + "Attending physician" (`caption tertiary`); bottom: branch pill `Icon(Building2, size14)` + `visit.branchName` (truncate); optional `visit.status.label` `AppBadge` (frontend-only) | CREATE `presentation/widgets/patient_visit_card.dart` | `PatientRecordCard`, `PatientDateStamp`, `AppBadge` | NEW | `PatientRecordCard`, `PatientDateStamp` |
| Upcoming-appointment card | `PatientUpcomingAppointmentCard({appointment: AppointmentListItem})` — `PatientRecordCard(leading: PatientDateStamp(appointment.startTime)); body`: `appointment.doctorDisplayName` (`bodyStrong`) + time range (`DateFormat.jm` start–end, LTR-forced for numerics) + `appointment.status`/`type` `AppBadge`s; "Upcoming" semantics via date-stamp being future | CREATE `presentation/widgets/patient_upcoming_appointment_card.dart` | `PatientRecordCard`, `PatientDateStamp`, `AppBadge`, `Directionality.ltr` for time | NEW | `PatientRecordCard`, `PatientDateStamp` |
| Responsive grid | `PatientRecordGrid({children})` — `LayoutBuilder`: cols 1 (<640) / 2 (640–1280) / 3 (≥1280); `GridView.count`/`SliverList` `mainAxisSpacing/crossAxisSpacing = AppSpacing.space4`; stagger via `AppMotion` per-index (reduced-motion → no motion) | CREATE `presentation/widgets/patient_record_grid.dart` | `AppSpacing`, `AppMotion` | NEW | `AppMotion` |
| Past-visits tab body | watch `patientPastVisitsProvider(patientId)` → `AsyncValue` switch: loading → `AppSkeletonizerZone` of N `PatientVisitCard`-shaped skeletons; data → `PatientRecordGrid` of `PatientVisitCard` (sorted desc by `visitDate`, provider already sorts); empty → `AppEmptyState` first-run "No visits yet"/"This patient has no recorded visits." | inline in page file (Phase 2) | `PatientRecordGrid`, `PatientVisitCard`, `AppSkeletonizerZone`, `AppEmptyState` | NEW (private) | P2 widgets, provider |
| Upcoming tab body | build `PatientDetailHistoryQuery(patientId, branchId)` — `branchId` from `patientDetailProvider` resolved value, fallback `authSessionProvider` active branch. watch `patientUpcomingAppointmentsProvider(query)` → `AsyncValue` switch: loading→skeleton; data→`PatientRecordGrid` of `PatientUpcomingAppointmentCard` (sorted asc `startTime`, provider already sorts); empty→`AppEmptyState` "No upcoming appointments"/"This patient has no scheduled appointments." | inline in page file (Phase 2) | `PatientRecordGrid`, `PatientUpcomingAppointmentCard`, `AppSkeletonizerZone`, `AppEmptyState` | NEW (private) | P2 widgets, `PatientDetailHistoryQuery`, both providers |
| Doctor initials helper | `_practitionerInitials(String)` — strip leading `"Dr."`, first+last initial uppercase, fallback "?" | inline in `patient_visit_card.dart` | `dart` string ops | NEW (private fn) | none |

**Wiring (Phase 2):** no route change; just remove the Phase-1 "Coming soon" placeholders for
`pastVisits` and `upcoming` branches in the tab-body switch and render the two async bodies
above. Run `flutter analyze`.

### Phase 3 — Documents tab + skeleton/motion polish + final wiring

| Element | Widget(s) | File(s) | Reuse | Wrapper | Deps |
|---|---|---|---|---|---|
| Document card | `PatientDocumentCard({document: PatientVisitDocument})` — inner `attachment = document.attachment`; `PatientRecordCard(leading: _FileTypeColumn(<VisitAttachmentFileType.label>, `formatFileSize(attachment.sizeBytes)`)); body`: overline "Patient file" + `attachment.label ?? attachment.id` (`line-clamp-2` analog: `maxLines:2`); linked-visit mini-card = bordered `Container` with `PatientDateStamp(document.visitDate, compact)` + caption "Linked visit" (no doctor/branch on `PatientVisitDocument` → only date shown; do NOT show "Visit link unavailable" since we have the date); footer: `AppButton.secondary.sm` "Download file" `Icon(Download,15)` only when `attachment.canDownload`, `onPressed` gated (§6 download deferred) | CREATE `presentation/widgets/patient_document_card.dart` | `PatientRecordCard`, `PatientDateStamp`, `AppButton`, `Icon(Download)` | NEW | `PatientRecordCard`, `PatientDateStamp`, `AppButton` |
| File-size helper | `_formatFileSize(int bytes)` — B/KB/MB (web `formatFileSize` port: `<1KB`→`B`, `<1MB`→`KB` 1-decimal, else `MB` 1-decimal). Lives in `presentation/utils/patient_presentation_formatting.dart` (extend existing util class) or inline in document card file. | EXTEND `presentation/utils/patient_presentation_formatting.dart` (add `static String formatFileSize(int bytes)`) OR inline | `dart` math | NEW (private fn) | none |
| File-type column | `_FileTypeColumn({fileType: VisitAttachmentFileType, sizeBytes: int})` — `Column`: `fileType.label` mono bodyStrong + `_formatFileSize` caption tertiary (matches web `<span mono>` + `<caption>`) | inline in `patient_document_card.dart` | none | NEW (private) | `_formatFileSize` |
| Documents tab body | watch `patientVisitDocumentsProvider(patientId)` → `AsyncValue` switch: loading→skeleton; data→`PatientRecordGrid` of `PatientDocumentCard`; empty→`AppEmptyState` first-run "No documents"/"No documents have been uploaded for this patient yet." | inline in page file (Phase 3) | `PatientRecordGrid`, `PatientDocumentCard`, `AppSkeletonizerZone`, `AppEmptyState` | NEW (private) | P3 widget, provider |
| Skeleton polish | When `patientDetailProvider` is loading AND no `preview`: render `AppSkeletonizerZone` wrapping the whole identity card + tab strip (mirrors web `PatientDetailSkeleton` 3-block: header / tabs / body). Once preview or data present, identity renders; only the active tab body skeletonizes. | inline in page file | `AppSkeletonizerZone`, `AppSkeleton` | NEW (private) | `AppSkeletonizerZone` |
| Motion polish | Page-level enter animation via `AnimationController` + `CurvedAnimation` + `AppMotion.animatedPreset` mirroring `patients_page.dart:38-68` (reduced-motion aware); per-card stagger inside `PatientRecordGrid`. | inline in page file + `patient_record_grid.dart` | `AppMotion` | NEW (private) | `AppMotion` |

**Wiring (Phase 3):**
1. Replace the documents `Coming soon` placeholder with the documents async body.
2. Confirm the not-found branch still fires when `patientDetailProvider` resolves to `null`
   (`PatientDetail.fromRow` can return null on a missing row — `patientDetailProvider` should
   surface that; if it throws instead, map to `AppErrorState`). Verify provider behavior and
   branch accordingly. (If `getPatient` returns null rather than throwing, treat `AsyncData(null)`
   as the not-found branch.)
3. Run `flutter analyze` across all new/changed files; fix lints. Do **not** commit unless asked.

### Phase 4 — Billing tab, Patient edit page, EN/AR localization

> **Web-reference status for these three differs — read carefully:**
> - **Billing tab / invoice cards:** the web `PatientDetailPage.tsx` HAS a Billing tab + `InvoiceCard` + `invoiceDueMeta`. The *status enum diverges* (`draft/sent/paid/overdue/cancelled` on web vs `draft/issued/partiallyPaid/paid/voided` in the Flutter `InvoiceStatus`), and the money type is `int` on web vs `Money` (Decimal-backed) in Flutter. **The Flutter data layer is authoritative** — port the *card shape* from web, bind it to `InvoiceListItem` / `patientInvoicesProvider`.
> - **Patient edit page:** the web has **NO edit page/dialog/form** — the "Edit patient" context-menu item just navigates to the read-only detail page, and the showcase "Edit patient" button is a no-`onClick` mock. So there is **no web source to translate 1:1**. The Flutter edit page is **synthesized** by mirroring the shipped Flutter **Add-patient** dialog (`add_patient_form_fields.dart` + `patient_registration_notifier.dart`) — the only patient form the codebase has — and adapting it to update. The web `findPatientDuplicates(values, excludePatientId?)` signature (with its `excludePatientId`) is the forward-looking hint that edit reuses the add duplicate-detection flow with a self-exclusion.
> - **EN/AR localization:** the web has a `DirectionProvider` (persisted, locale↔direction coupled) that both showcases AND production widgets (`MoneyField`, `DatePicker`, `UserMenu`) consume. The Flutter port only replicated the *showcase* half (`devPreviewProvider` + `_copyEn`/`_copyAr`). Phase 4 wires the production half: install `AppLocalizations` in `MaterialApp.router`, add `app_ar.arb`, add a `localeProvider`, and route the patient-detail (and edit) copy through ARB keys. This is the only Phase-4 piece that touches `core/` and `app/` (not just `features/patients/`).

#### 4a. Billing tab + invoice cards

| Element | Widget(s) | File(s) | Reuse | Wrapper | Deps |
|---|---|---|---|---|---|
| Tab enum extension | add `billing` to `PatientDetailSection` (4th value) | MOD `presentation/widgets/patient_detail_section.dart` | existing enum | EXTEND | none |
| Invoice card | `PatientInvoiceCard({invoice: InvoiceListItem})` — port web `InvoiceCard` shape: `PatientRecordCard` with a status-colored top band (`BillingFormatting.statusBadgeStyle(invoice.status)` → `AppBadge` variant + accent) showing `invoiceNumber` (mono caption) + status `AppBadge`; body "Balance" overline + `invoice.balance` (render via `Money` → formatted with `BillingFormatting` currency) `AppTypography.display` tabular; bottom grid "Issued" (`invoice.issuedAt ?? invoice.createdAt` formatted) / "Payment" (due date label). Web `invoiceDueMeta` due-date arithmetic re-computed against `clock.now()`, returning `{label, urgent}`; `urgent` colors the label via the band's accent color. | CREATE `presentation/widgets/patient_invoice_card.dart` | `PatientRecordCard`, `AppBadge`, `BillingFormatting`, `Money`, `clock` (testable time), `AppTypography` | NEW | `PatientRecordCard`, `BillingFormatting` |
| Due-date helper | `_invoiceDueLabel({dueDate, status})` — port web `invoiceDueMeta` (`:94-116`): `paid`/`voided` → `"Due <date>"` non-urgent; `overdue` or past-due → `"<n> days overdue"` urgent; `0` → `"Due today"`; `≤7` → `"Due in n days"`/`"Due tomorrow"`; else `"Due <date>"`. Uses `clock.now()` and `PatientPresentationFormatting.date`. There is **no `dueDate` field** on `InvoiceListItem` — see caveat below. | inline in `patient_invoice_card.dart` (or extend `billing_formatting.dart`) | `clock`, `DateFormat` | NEW (private fn) | `PatientPresentationFormatting` |
| Billing tab body | watch `patientInvoicesProvider(patientId)` → `AsyncValue` switch: loading → skeleton grid; data (sorted desc by `issuedAt ?? createdAt`) → `PatientRecordGrid` of `PatientInvoiceCard`; empty → `AppEmptyState` first-run "No invoices"/"No billing records for this patient." (web :494-500); error/permission-denied (provider returns empty `InvoiceListPageResult` when `canAccessInvoiceList` false) → render a **permission** `AppEmptyState` or simply hide the tab; decision below. | inline in page file (Phase 4) | `PatientRecordGrid`, `PatientInvoiceCard`, `AppEmptyState`, `AppSkeletonizerZone` | NEW (private) | P4 widget, `patientInvoicesProvider` |
| File-size on card | (n/a — invoice card has no file column) | — | — | — | — |

**Caveat — `InvoiceListItem` has no `dueDate`.** The web `InvoiceCard` shows a "Payment"/due line based on `invoice.dueDate`. The Flutter `InvoiceListItem` (`invoice_list_item.dart:7-83`) exposes `createdAt`, `issuedAt` but **no `dueDate`** and **no `invoiceNumber` is guaranteed** (nullable). Per the brief's "ignore web fields not in frontend" rule:
- If `invoiceNumber` is null → render the invoice `id` shortened via `PatientPresentationFormatting.displayId`.
- **Drop the "Payment"/due-date line** when there is no `dueDate`. Replace the web bottom 2-col grid (Issued / Payment) with a single **Issued** line (`issuedAt ?? createdAt`). Do **not** fabricate a due date. Note this divergence in the card's doc comment. (If a `dueDate` is later added to the domain, the `_invoiceDueLabel` helper above is ready to bind.)
- Keep the status-colored top band + balance display (the binding visual identity of the web `InvoiceCard`).

**Invoice status color mapping** — prefer the Flutter `BillingFormatting.statusBadgeStyle(InvoiceStatus)` (already implemented, `billing_formatting.dart:70`), which returns an `InvoiceStatusBadgeStyle { variant, icon }` aligned to the **Flutter** enum (`draft/issued/partiallyPaid/paid/voided`). Do **not** port the web `INVOICE_STATUS_BAND` map (which is keyed on web statuses `sent`/`overdue`/`cancelled` that don't exist in Flutter).

**Permissions:** `patientInvoicesProvider` (`invoice_detail_provider.dart:53-62`) gates on `AuthRouteGuard.canAccessInvoiceList(auth)` and returns an empty page result on denial. Decision: when the returned `items` is empty AND the user lacks permission, render the billing tab as a locked `AppEmptyState` ("You don't have access to billing records.") rather than the first-run "No invoices" empty state (so a permitted-but-empty patient differs from a no-access user). Compute the permission flag by watching `authSessionProvider.select(AuthRouteGuard.canAccessInvoiceList)` in the page.

#### 4b. Patient edit page

Web has no edit. Synthesize by mirroring the **Flutter** Add-patient dialog (the authoritative form pattern), adapted for update.

| Element | Widget(s) | File(s) | Reuse | Wrapper | Deps |
|---|---|---|---|---|---|
| Edit notifier | `PatientEditNotifier extends StateNotifier<PatientEditState>` (mirrors `PatientRegistrationNotifier`) — family by `patientId`; `build` preloads from `patientDetailProvider(patientId)` once, building `PatientRegistrationForm.from<PatientDetail>` + storing `expectedUpdatedAt`; `updateField`/`_clearFieldError` identical to add; `submit()` validates → if `!acknowledgedDuplicate`, `checkDuplicatesUseCaseProvider(fullName, phone, dateOfBirth, excludePatientId: patientId)` (self-excluded via the existing `excludePatientId` param on `CheckDuplicates`) → on candidates open dialog → else `updatePatientUseCaseProvider(UpdatePatientInput(...))` with `expectedUpdatedAt` → on success toast + invalidate `patientDetailProvider(patientId)` and return. Handles `RpcFailure` (incl. stale-update `STALE_UPDATE`) via `patientMessageForRpc` (extend with `updatePatientMessageForRpc` if new codes appear). | CREATE `presentation/providers/patient_edit_notifier.dart` | `PatientRegistrationForm`, `PatientFormErrors`, `UpdatePatientInput`, `checkDuplicatesUseCaseProvider`, `updatePatientUseCaseProvider`, `patientDetailProvider`, `appToast`, `clock` | NEW | add notifier as template |
| Edit provider | `patientEditProvider = StateNotifierProvider.family<PatientEditNotifier, PatientEditState, String>` (non-autoDispose so the form survives the dialog; reset on `build`). Alternatively autoDispose + keyed by patientId. | inline in `patient_edit_notifier.dart` | Riverpod | NEW | `PatientEditNotifier` |
| Edit form fields | `EditPatientFormFields` — **reuse `AddPatientFormFields` wholesale** by parameterization rather than copy: refactor `AddPatientFormFields` to accept an optional `initialValues: PatientRegistrationForm?` (when null, `PatientRegistrationForm.empty`), a `branchName` for the banner (`activeBranchNameProvider` for add vs `patientDetail.branchName` for edit), and an `identityPreviewSubtitle` ("New record · MRN assigned on save" for add vs "Editing · <fullName>" for edit). If refactoring the shared widget is risky, create a parallel `EditPatientFormFields` under `presentation/edit_patient/` mirroring the add file but prefilling fields from `PatientDetail`. **Recommended: refactor shared** to keep the two forms from diverging. | MOD `presentation/add_patient/add_patient_form_fields.dart` (parameterize) OR CREATE `presentation/edit_patient/edit_patient_form_fields.dart` | `AppFormField`+`AppTextInput`/`AppDatePicker`/`AppSelect`/`AppPhoneInput`/`AppTextarea` (existing, already used by add) | EXTEND-or-NEW | add form fields |
| Edit dialog | `EditPatientDialog` — `AppDialog` (size lg) titled "Edit patient" (ARB-keyed), description "Update the patient's demographic and clinical information." (ARB); body = `EditPatientFormFields` prefilled from `patientDetailProvider`; footer Cancel (secondary) + "Save changes" (primary, `form=edit-form`, loading via `state.submitting`, `Icon(save)`); hosts `DuplicatePatientDialog` (reused unchanged — it already takes candidates + `onAcknowledge`/`onOpenExisting`). On success: close dialog, `ref.invalidate(patientDetailProvider(patientId))` so the detail page refreshes the identity card. | CREATE `presentation/edit_patient/edit_patient_dialog.dart` | `AppDialog`, `AppButton`, `DuplicatePatientDialog`, `patientEditProvider`, `appToast` | NEW | edit notifier, edit form fields, `DuplicatePatientDialog` |
| Edit entry point on detail page | Add an `AppButton.secondary` "Edit patient" (`Icon(edit)`, ARB-keyed) to the identity card's action row (top-right of `_PatientIdentityCard`, mirroring the showcase `RecordDetailPattern.tsx:55-57` "Edit patient" button) → opens `EditPatientDialog(patientId:)` via `showDialog`. (The web detail page does NOT have this button — it only exists in the showcase pattern. This is a deliberate frontend augmentation because there is no web detail edit affordance.) | inline in page file (Phase 4) | `AppButton`, `AppDialog`, `EditPatientDialog` | NEW (private) | `EditPatientDialog` |
| Stale-update guard | `UpdatePatientInput.expectedUpdatedAt` provides optimistic-concurrency — on `RpcFailure` with a stale code, surface a confirm dialog ("This record was modified by someone else. Reload and discard your edits?") then `ref.invalidate(patientDetailProvider)` to refresh. Inline or via a small `_StaleUpdateDialog`. | inline in `patient_edit_notifier.dart` / dialog | `AppDialog` | NEW (private) | `RpcResult`/`RpcFailure` |
| Edit route | The `/patients/:patientId/edit` route stays as `shellPlaceholderPage` — **edit is a dialog**, not a page (mirroring the add flow which is also a dialog, and the web's nonexistent edit route). Do **not** rebind it. `context.nav.pushPatientEdit` exists but is **unused** by this plan; left for a future page-based edit. | none — no router change | — | — | — |

**Field reconciliation (Flutter `PatientDetail` ↔ edit form):**
- `fullName` → `fullName` field (required, min 2).
- `phone?` → `phone` field (optional, 8-15 digits if present).
- `dateOfBirth?` → `dateOfBirth` field (optional, max today).
- `gender?` → `gender` select.
- `maritalStatus?` → `maritalStatus` select.
- `notes?` → `notes` textarea.
- `expectedUpdatedAt` → carried as the optimistic-concurrency token; **never** user-editable.
- `branchId`/`branchName`/`id`/`createdAt`/`createdByDisplay` → read-only, not in the edit form. The `update_patient` RPC derives branch from `expectedUpdatedAt` row; the patient stays at their registering branch.
- `acknowledgeDuplicate` → reused from the add duplicate flow; `checkDuplicatesUseCaseProvider`'s `excludePatientId` ensures the patient being edited is not flagged as a duplicate of itself.

**Duplicate flow reuse:** `DuplicatePatientDialog` (`add_patient/duplicate_patient_dialog.dart`) is already presenter-agnostic (takes `candidates`, `onAcknowledge`, `onOpenExisting`). The edit notifier reuses it; the "Create anyway" semantics become "Save anyway". `onOpenExisting` navigates to the candidate patient (rare in edit, but supported).

#### 4c. EN/AR localization

Bind the patient-detail + edit copy to the gen-l10n `AppLocalizations` system and wire Arabic.

| Element | What to do | File(s) | Reuse | Deps |
|---|---|---|---|---|
| Install delegates | add `localizationsDelegates: AppLocalizations.localizationsDelegates` and `supportedLocales: AppLocalizations.supportedLocales` to `MaterialApp.router` in `app.dart`; add a `locale:` argument driven by a new `localeProvider` (parallels `themeModeProvider`). | MOD `frontend/lib/app/app.dart` | `AppLocalizations.localizationsDelegates` (already generated) | `localeProvider` |
| Locale provider | `localeProvider = NotifierProvider<LocaleNotifier, Locale>` — defaults to `Locale('en')`, persists to `SharedPreferences` key `aiclinic.locale`, and **couples** `Locale('ar')`→`Directionality.rtl` at the `MaterialApp` level (set `builder` to wrap root in `Directionality` based on locale, matching the web `DirectionProvider` coupling). Companion `textDirectionProvider` derived from locale, OR set `MaterialApp`'s `builder` to inject `Directionality`. | CREATE `frontend/lib/app/providers/locale_provider.dart` | `SharedPreferences`, `themeModeProvider` (as the persistence pattern to copy) | none |
| Arabic ARB | Create `app_ar.arb` mirroring ALL 31 keys of `app_en.arb` (+ new patient-detail keys), Arabic strings. gen-l10n auto-emits `app_localizations_ar.dart`, extends `supportedLocales` to `[en, ar]`, and extends `isSupported`. | CREATE `frontend/lib/l10n/app_ar.arb` | `app_en.arb` as the key skeleton | `flutter gen-l10n` |
| New ARB keys (patient detail + edit) | Add keys to BOTH `app_en.arb` and `app_ar.arb`: `patientDetailBreadcrumb`, `patientNotFound`, `patientNotFoundDescription`, `backToPatients`, `pastVisits`, `upcoming`, `documents`, `billing`, `noVisitsYet`, `noVisitsYetDescription`, `noUpcomingAppointments`, `noUpcomingAppointmentsDescription`, `noDocuments`, `noDocumentsDescription`, `noInvoices`, `noInvoicesDescription`, `billingNoAccess`, `attendingPhysician`, `linkedVisit`, `patientFile`, `downloadFile`, `saveChanges`, `editingPatient`, `editPatientDescription`, `registeredAt`, `newRecordMrsAssignedOnSave`, `editingSuffix` (+ reuse existing `genderMale/Female/Other/PreferNotToSay/Unknown/NotSpecified`, `cancel`, `save`, `edit`, `retry`, `loading`, `discardChangesTitle/Message`, `keepEditing`, `discard`). Flat camelCase, feature-prefix where natural. | MOD `app_en.arb`, `app_ar.arb` | existing key-naming convention (flat, family-prefixed) | gen-l10n |
| l10n accessor | Add `extension AppLocalizationsX on BuildContext { AppLocalizations get l10n => AppLocalizations.of(this)!; }` in `core/ui/` (or `core/utils/`) so widgets do `context.l10n.patientNotFound`. Non-null because after the delegates are installed, `of(context)` resolves for supported locales. | CREATE `frontend/lib/core/ui/l10n/app_localizations_x.dart` (or `core/utils/`) | none | `AppLocalizations` |
| Replace literals in patient-detail page | Replace the hard-coded EN literals in `patient_detail_page.dart`, card widgets, empty states, dialog with `context.l10n.<key>`. The tab labels (`PatientDetailSection.label`) become a `labelOf(BuildContext, PatientDetailSection)` fn returning the ARB key, since enum values can't call `BuildContext`. | MOD `patient_detail_page.dart`, `patient_visit_card.dart`, `patient_document_card.dart`, `patient_upcoming_appointment_card.dart`, `patient_invoice_card.dart` (P4), `patient_detail_section.dart`, `edit_patient_dialog.dart` (P4) | `context.l10n` extension | ARB keys |
| Date/number locale | The card date-stamps and DOB line already resolve locale via `Localizations.localeOf`. With Arabic registered, `DateFormat` picks `ar_EG` symbols (already preloaded by `ensureIntlDateFormattingInitialized()`). Money/invoice balance formatting in `BillingFormatting` must pass the active locale (`NumberFormat.currency(locale: ...)`). | MOD `billing_formatting.dart` (currency locale) where it formats | `intl`, `Localizations.localeOf` | `app_ar.arb` |
| Showcase copy untouched | The `_copyEn`/`_copyAr` showcase convention is **not** migrated to ARB — it stays as-is (per the inputs-forms plan decision). Phase 4 only affects **production feature** copy (patients feature), not design-system showcase copy. | none | `devPreviewProvider` unchanged | — |

**ARB→web translation heuristic for new keys:** for each new key, the EN string is the literal already in the patient-detail page (taken from the web `PatientDetailPage.tsx` copy, e.g. "No visits yet", "Attending physician", "Download file"). The AR string is its Arabic translation, mirroring the style of the existing showcase `_copyAr` constants (e.g. "لا توجد زيارات بعد", "الطبيب المعالج", "تنزيل الملف"). The web-reference `PatientDetailPage.tsx` copy is the **source for the EN values**; the showcase `_copyAr` constants across `design_system/presentation/components/**` are the **style reference for the AR values** (the showcase files are the only Arabic strings already in the repo).

**Wiring (Phase 4):**
1. Add `patientInvoicesProvider` import to `patient_detail_page.dart`; wire the billing tab body.
2. Add `billing` to `PatientDetailSection` + the tab strip + `labelOf` ARB helper.
3. Create edit notifier/dialog/form wiring; add the "Edit patient" button to the identity card; on success invalidate `patientDetailProvider`.
4. Create `app_ar.arb`; add new keys to both ARBs; run `flutter gen-l10n`.
5. Wire `MaterialApp.router` (`app.dart`): `localizationsDelegates` + `supportedLocales` + `locale:` from `localeProvider` + `builder:` wrapping in `Directionality`.
6. Create the `context.l10n` extension and replace literals in the patients feature page/widgets/dialog.
7. Run `flutter analyze`; `flutter gen-l10n` (or `flutter pub get`) to regenerate. Do **not** commit unless asked.

---

## 4. Page composition spec (mirrors web reference)

> **Binding source of truth:** `web-reference/src/pages/app/patients/PatientDetailPage.tsx`
> (lines 358–504 for the main page; 51–356 for sub-components). Composer 2.5 should open that
> file and reproduce the structure demo-for-demo, substituting the Flutter `App*` widgets and
> the 3 frontend providers. There is **no** `*Showcase.tsx`; this is a production page, so the
> per-demo `ShowcaseDemo` matrix does not apply — the layout tree below is the spec.

**Layout tree to reproduce** (web :401–502, Flutter-adapted):

```
Scaffold(AppShell-provided content area, full-width) → Column/AppMotion.enterPreset:
└── PatientDetailPage                       // PatientDetailPage.tsx:358
    ├── AppBreadcrumb  [Patients → <fullName>]            // :403-408
    │     Patients → onTap: context.nav.goPatients()
    │
    ├── AppCard (raised, padding lg, overflow-hidden, no inner padding)  // :410-452
    │   ├── _PatientIdentityCard                                            // :411-440
    │   │   └── Row(align:start, gap:4):
    │   │       ├── AppAvatar(name: fullName, size: lg)                     // :413  (xl→lg)
    │   │       └── Column(gap:3):
    │   │           ├── Row(wrap, gap:3):
    │   │           │   ├── Text(fullName, AppTypography.h1)                // :416
    │   │           │   └── [DROPPED: status Badge — no status field]
    │   │           ├── Text("${ageGenderLabel} · DOB ${dateOfBirthLabel(dateOfBirth)}")  // :421-424
    │   │           │     gender via PatientPresentationFormatting; age appended by dateOfBirthLabel
    │   │           └── Row(wrap, gap:4, bodySm, textSecondary):
    │   │               ├── Icon(Phone,size14) + Text(phone ?? '—')         // :426-429  (Phone via orDash)
    │   │               ├── [DROPPED: Mail row — no email field]            // :430-433
    │   │               └── [DROPPED: MapPin row — no address field]        // :434-437
    │   │           └── (OPTIONAL frontend-only) Text(branchName, caption)  // not in web
    │   │
    │   └── Divider(borderSubtle) + AppTabs                                 // :443-450
    │         items: [Past visits, Upcoming, Documents]   // (web: Visits/Documents/Billing)
    │         bound to PatientDetailSection; aria-label "Patient sections"
    │
    └── switch (PatientDetailSection):
        ├── pastVisits  → PatientRecordGrid { PatientVisitCard(visit) each }   // :455-469
        │                 | AsyncValue(patientPastVisitsProvider(patientId))
        │                 | empty → AppEmptyState(info) "No visits yet"/"This patient has no recorded visits."
        ├── upcoming    → PatientRecordGrid { PatientUpcomingAppointmentCard(appt) }
        │                 | AsyncValue(patientUpcomingAppointmentsProvider(query))
        │                 | empty → AppEmptyState(info) "No upcoming appointments"/"…no scheduled appointments."
        └── documents   → PatientRecordGrid { PatientDocumentCard(doc) each }  // :471-485
                          | AsyncValue(patientVisitDocumentsProvider(patientId))
                          | empty → AppEmptyState(info) "No documents"/"…uploaded for this patient yet."

   // :487-501 Billing branch → DROPPED (no billing provider)
```

**Not-found branch** (web :374–396): `AppPageHeader(title: 'Patient not found', breadcrumb:
Patients → 'Not found')` + `AppEmptyState` (error variant) with `EmptyStateAction('Back to
patients', → context.nav.goPatients())`.

**Per-card faithful details** (mirror the web sub-components):

- `PatientVisitCard` ← `VisitCard` (:167–217): left date-stamp column (`w-5.25rem`, teal-tinted
  gradient, aria-hidden), `day` display-2rem + `MONTH` overline + `year` caption; body weekday
  overline + 40px doctor-initials circle (`border.Subtle`, mono caption) + `doctorName`
  bodyStrong + "Attending physician" caption; branch pill `Icon(Building2,14)` + `branchName`
  (`truncate`). Flutter: keep the same column rhythm with `AppSpacing`, `AppRadius`, and
  `PatientDateStamp`. Add optional `visit.status.label` pill (frontend-only).

- `PatientUpcomingAppointmentCard` (no direct web analog — synthesized from `VisitCard` shape):
  date-stamp from `appointment.startTime`; body = `doctorDisplayName` (bodyStrong) +
  time-range (`startTime`–`endTime`, LTR-forced) + `type`/`status` `AppBadge`s.

- `PatientDocumentCard` ← `DocumentCard` (:274–356): left column `fileType.label` (`PDF/DOCX/…`,
  mono) + `formatFileSize(sizeBytes)` caption over a muted→sunken gradient; body overline "Patient
  file" + `attachment.label ?? id` (`maxLines:2`, ellipsis); **Linked visit** mini-card: caption
  "Linked visit" + compact `PatientDateStamp(document.visitDate)` (only the date —
  `PatientVisitDocument` exposes no doctor/branch; do **not** show "Visit link unavailable" since
  the date is present). Footer "Download file" `AppButton.secondary.sm` full-width +
  `Icon(Download,15)`, only when `attachment.canDownload`.

Because there is no showcase, the bilingual EN/AR `_copyEn`/`_copyAr` convention from the
inputs-forms plan does not apply. Copy stays single-language EN in the page; localization is
deferred (§6).

---

## 5. Wiring steps (after all phases — or per phase as noted)

> Unlike the showcase-group plans, there is **no** `component_registry.dart` /
> `component_section_builders.dart` change — this is a feature page, not a Dev components entry.
> Wiring is routing + provider consumption only.

1. **Router (Phase 1):** `frontend/lib/app/router.dart:85` — replace
   `builder: shellPlaceholderPage` for the `:patientId` route with a builder returning
   `PatientDetailPage(patientId: state.pathParameters['patientId']!, extra:
   PatientDetailRouteExtra.fromExtra(state.extra))`. Add the necessary imports.
2. **Providers (Phases 1–3):** the four providers (`patientDetailProvider`,
   `patientPastVisitsProvider`, `patientUpcomingAppointmentsProvider`,
   `patientVisitDocumentsProvider`) already exist and are autoDispose family — consume them as
   described; no new providers required. For upcoming, assemble `PatientDetailHistoryQuery` with
   the resolved `branchId` (`patientDetail.value?.branchId ?? authSessionProvider activeBranch`).
3. **List-page link:** already wired — `patients_page.dart:256` calls
   `context.nav.pushPatientDetail(row.item.id, preview: row.item)`; the add-patient success
   callback (`patients_page.dart:341`) also navigates here. No change needed. Verify the
   context-menu "Open patient details"/"Edit patient" still route correctly.
4. **Edit route:** left as `shellPlaceholderPage` — edit is out of scope here.
5. **Analyze:** after each phase run `flutter analyze` on the touched files; fix all lints. **Do
   not commit** unless explicitly asked.

---

## 6. Out-of-scope / defer

> **Note:** the original three deferred items — **Billing tab**, **Patient edit page**, and
> **EN/AR production localization** — are now in **Phase 4 (§3)**. The remaining deferrals are
> listed below.

- **`getPatient` returning null** — verify whether `patientDetailProvider` throws or yields
  `AsyncData(null)`; branch the not-found UI accordingly. (Implementation detail, not a new
  design.)
- **Download invocation** — rendering the gated "Download file" button is in scope (Phase 3); the
  actual byte-stream/URL download call stays **deferred** even after Phase 4 (locate the existing
  visit-attachment download path in the `visits` feature or add one later). Button `onPressed`
  is a TODO/no-op for now.
- **Linked-visit doctor/branch on document cards** — `PatientVisitDocument` exposes only
  `visitDate`; enriching the documents RPC to include doctor/branch (or a separate
  `getVisitById`-style lookup) is deferred. Phase-3 card shows the linked-visit date only.
- **Invoice `dueDate` line** — dropped (no `dueDate` on `InvoiceListItem`). The web
  `invoiceDueMeta` helper is implemented but binds only if/when a `dueDate` field is added to the
  billing domain; the shipping card shows Issued only.
- **Invoice detail navigation** — tapping an invoice card does **not** open `/billing/invoices/:id`
  in this plan (that route is a stub `shellPlaceholderPage`). Tapping is a no-op or a
  `context.nav.pushBillingInvoiceDetail(id)` call left commented for when the invoice detail page
  ships (out of scope here). The `pushBillingInvoiceEdit` helper likewise unused.
- **Page-based edit** — edit is a **dialog** (mirroring add). The `/patients/:patientId/edit`
  route stays a `shellPlaceholderPage` and `context.nav.pushPatientEdit` stays unused; a future
  full-page edit (web has neither) can rebind it.
- **`status` Badge on identity** — dropped (no status field). If a status field is added later,
  reintroduce the web Badge using `AppBadge`.
- **`maritalStatus` / `notes` / `createdByDisplay`** — frontend-only optional enrichments; only
  surfaced if the implementer adds a secondary meta line. Not required by the binding web layout.
- **`PatientDetailHistoryTabProvider`** — left in place; superseded by page-local
  `PatientDetailSection` for the 4-tab layout (3 + billing). Not deleted.
- **Showcase `_copyEn`/`_copyAr` migration** — the design-system showcase bilingual convention
  is **not** migrated to ARB in Phase 4; it stays as-is. Phase 4 ARB wiring affects only
  production feature copy (patients detail/edit), not showcase copy.
- **No new `core/ui/components/app_*.dart`** — all feature widgets are under
  `presentation\widgets/`\, `presentation\edit_patient`\, or `presentation\providers/`. The
  `widgets.dart` barrel is not edited. The lone `core/`-level additions are the l10n extension
  (`core/ui/l10n/`) and the locale provider (`app/providers/`).

---

## 7. Source reference — web widget inventory

The Patient Details page lives in a single file with colocated sub-components (the show-registry
has no entry for it). Inventory of the bundles ported (and dropped):

| Export / sub-component | Title | Source | Binding reference | Flutter target |
|---|---|---|---|---|
| `PatientDetailPage` | Patient Details (page) | — (prod page) | `PatientDetailPage.tsx:358-504` | `PatientDetailPage` (page) |
| `Breadcrumb` | — | — | `@/components/navigation/Breadcrumb` | reuse `AppBreadcrumb` |
| `Card` (raised, lg) | — | — | `@/components/card/Card` | reuse `AppCard` (identity host) |
| `Tabs` | — | — | `@/components/navigation/Tabs` | reuse `AppTabs` |
| `EmptyState` | — | — | `@/components/empty-state/EmptyState` | reuse `AppEmptyState` |
| `PageHeader` | — | — | `@/components/layout/PageHeader` | reuse `AppPageHeader` (not-found only) |
| `Avatar` (xl) | — | — | `@/components/avatar/Avatar` | reuse `AppAvatar` (lg) |
| `Badge` | — | — | `@/components/badge` | reuse `AppBadge` (optional frontend-only) |
| `Skeleton` / `PatientDetailSkeleton` | — | — | `@/components/skeleton/Skeleton` | reuse `AppSkeletonizerZone`/`AppSkeleton` |
| `RecordCardShell` | Record-card shell | — | `PatientDetailPage.tsx:131-154` | NEW `PatientRecordCard` (feature-local) |
| `RecordCardGrid` | Responsive card grid | — | `PatientDetailPage.tsx:118-129` | NEW `PatientRecordGrid` (feature-local) |
| `ToDateStamp` (helper) | Date stamp | — | `PatientDetailPage.tsx:77-85` | NEW `PatientDateStamp` (feature-local) |
| `VisitCard` | Visit record card | — | `PatientDetailPage.tsx:167-217` | NEW `PatientVisitCard` (feature-local) |
| `DocumentCard` | Document record card | — | `PatientDetailPage.tsx:274-356` | NEW `PatientDocumentCard` (feature-local) |
| *— (synthesized from VisitCard)* | Upcoming appointment card | — | (none) | NEW `PatientUpcomingAppointmentCard` (feature-local) |
| `InvoiceCard` *(Phase 4)* | Invoice record card | — | `PatientDetailPage.tsx:219-267` | NEW `PatientInvoiceCard` (feature-local) bound to `InvoiceListItem` |
| `INVOICE_STATUS_BAND` | Invoice status band | — | `PatientDetailPage.tsx:51-75` | replaced by Flutter `BillingFormatting.statusBadgeStyle` |
| `invoiceStatusColor` | Invoice status color | — | `@/data/patients:271-276` | replaced by Flutter `InvoiceStatus` enum + `BillingFormatting` |
| `invoiceDueMeta` *(Phase 4)* | Invoice due-date logic | — | `PatientDetailPage.tsx:94-116` | NEW `_invoiceDueLabel` (DROPPED binding — no `dueDate` field; ready to bind if added) |
| `MoneyDisplay` | Money display | — | `@/components/money/MoneyDisplay` | replaced by `Money` (Decimal) + `BillingFormatting` currency |
| `formatFileSize` | File-size formatter | — | `@/data/patients:formatFileSize` | NEW `_formatFileSize` (extend `PatientPresentationFormatting`) |
| `practitionerInitials` | Doctor initials | — | `PatientDetailPage.tsx:87-92` | NEW `_practitionerInitials` (inline in `patient_visit_card.dart`) |
| `documentExtension` | File-extension extractor | — | `PatientDetailPage.tsx:269-272` | **DROPPED** — replaced by `VisitAttachmentFileType.label` |
| *(no web edit page)* | Patient edit | — | (none — web only navigates to detail) | NEW `EditPatientDialog`+`PatientEditNotifier` synthesized from **Flutter `AddPatientDialog`** |
| `findPatientDuplicates(values, excludePatientId?)` | Duplicate detection (edit-ready) | — | `@/data/patients` (web) | reuse Flutter `checkDuplicatesUseCaseProvider` (already has `excludePatientId`) |
| `DirectionProvider` | Locale/direction provider | — | `web-reference/src/providers/DirectionProvider.tsx` | NEW `localeProvider` (Riverpod, persisted, locale↔direction coupled) |
| `useDirection().locale` | Production locale consumer | — | `MoneyField`/`DatePicker`/`UserMenu.tsx` | NEW `context.l10n` + ARB wiring in `app.dart` |
| `COPY` (per-showcase EN/AR) | Showcase bilingual copy | — | each `*Showcase.tsx` | existing `_copyEn`/`_copyAr` (NOT migrated — see §6) |

### Shared web building blocks (Flutter equivalents)

- `cn` (Tailwind class merge) → `context.appColors`/`AppSpacing`/`AppRadius` token composition (no direct equiv; tokens compose via Dart).
- `motion`/`motionPresets`/`staggerChildren`/`resolveTransition` → `AppMotion`/`AppMotionPreset`/`AppMotion.animatedPreset` (reduced-motion aware).
- `lucide-react` icons (`Phone`, `Mail`, `MapPin`, `Building2`, `Download`) → Material `Icons`/`CupertinoIcons` equivalents (e.g. `Icons.phone_outlined`, `Icons.location_on_outlined`, `Icons.apartment`, `Icons.download_outlined`). Only `Phone` + `Building2` + `Download` are used (Mail/MapPin rows dropped).
- Web `formatDate` (en-GB `d MMM y`) → `PatientPresentationFormatting.date` (`yMMMd`) for the DOB line; card date-stamp columns use locale-resolved `DateFormat('d')`/`MMM`/`'y'` + `EEEE`.
- Web `getVisitsForPatient`/`getDocumentsForPatient`/`getInvoicesForPatient`/`getPatientById`/`getVisitById` (sync in-memory) → Flutter async `FutureProvider` family (`patientPastVisitsProvider`, `patientVisitDocumentsProvider`, `patientDetailProvider`, `patientUpcomingAppointmentsProvider`, **`patientInvoicesProvider`** Phase 4). `getVisitById` is **not** available in the docs feature — linked-visit only shows `visitDate`.
- Web `InvoiceStatus` enum (`draft/sent/paid/overdue/cancelled`) → Flutter `InvoiceStatus` (`draft/issued/partiallyPaid/paid/voided`) — **Flutter authoritative**; web statuses not fabricated.
- Web `PatientInvoice.total` (`int`) → Flutter `InvoiceListItem.balance` (`Money` Decimal) — balance renders via `Money`/`BillingFormatting`, not a raw int.