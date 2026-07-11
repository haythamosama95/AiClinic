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

- **Billing tab / `InvoiceCard` / `MoneyDisplay` / due-meta logic** — dropped; no billing data
  layer in the patients feature. (Billing exists as its own `/billing` feature module.)
- **Patient edit page** (`/patients/:id/edit`) — remains a `shellPlaceholderPage`; separate task.
- **`getPatient` returning null** — verify whether `patientDetailProvider` throws or yields
  `AsyncData(null)`; branch the not-found UI accordingly. (Implementation detail, not a new
  design.)
- **Download invocation** — rendering the gated "Download file" button is in scope; the actual
  byte-stream/URL download call is **deferred** (locate the existing visit-attachment download
  path in the `visits` feature or add one later). Button `onPressed` is a TODO/no-op for now.
- **Linked-visit doctor/branch on document cards** — `PatientVisitDocument` exposes only
  `visitDate`; enriching the documents RPC to include doctor/branch (or a separate
  `getVisitById`-style lookup) is deferred. Phase-3 card shows the linked-visit date only.
- **Localization (EN/AR) of copy** — single-language EN for now; AR + `l10n` wiring is deferred.
- **`status` Badge on identity** — dropped (no status field). If a status field is added later,
  reintroduce the web Badge using `AppBadge`.
- **`maritalStatus` / `notes` / `createdByDisplay`** — frontend-only optional enrichments; only
  surfaced if the implementer adds a secondary meta line. Not required by the binding web layout.
- **`PatientDetailHistoryTabProvider`** — left in place; superseded by page-local
  `PatientDetailSection` for the 3-tab layout. Not deleted.
- **No new `core/ui` abstractions** — all new widgets are feature-local under
  `presentation/widgets/`; the `widgets.dart` barrel is not edited.

---

## 7. Source reference — web widget inventory

The Patient Details page lives in a single file with colocated sub-components (the show-registry
has no entry for it). Inventory of the bundles ported (and dropped):

| Export / sub-component | Title | Showcase file | Underlying UI component | Flutter target |
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
| `InvoiceCard` | Invoice record card | — | `PatientDetailPage.tsx:219-267` | **DROPPED** (no billing provider) |
| `INVOICE_STATUS_BAND` / `invoiceStatusColor` / `invoiceDueMeta` | Invoice styling + due logic | — | `PatientDetailPage.tsx:51-116` | **DROPPED** |
| `MoneyDisplay` | Money display | — | `@/components/money/MoneyDisplay` | **DROPPED** (billing) |
| `formatFileSize` | File-size formatter | — | `@/data/patients:formatFileSize` | NEW `_formatFileSize` (extend `PatientPresentationFormatting`) |
| `practitionerInitials` | Doctor initials | — | `PatientDetailPage.tsx:87-92` | NEW `_practitionerInitials` (inline in `patient_visit_card.dart`) |
| `documentExtension` | File-extension extractor | — | `PatientDetailPage.tsx:269-272` | **DROPPED** — replaced by `VisitAttachmentFileType.label` |

### Shared web building blocks (Flutter equivalents)

- `cn` (Tailwind class merge) → `context.appColors`/`AppSpacing`/`AppRadius` token composition (no direct equiv; tokens compose via Dart).
- `motion`/`motionPresets`/`staggerChildren`/`resolveTransition` → `AppMotion`/`AppMotionPreset`/`AppMotion.animatedPreset` (reduced-motion aware).
- `lucide-react` icons (`Phone`, `Mail`, `MapPin`, `Building2`, `Download`) → Material `Icons`/`CupertinoIcons` equivalents (e.g. `Icons.phone_outlined`, `Icons.location_on_outlined`, `Icons.apartment`, `Icons.download_outlined`). Only `Phone` + `Building2` + `Download` are used (Mail/MapPin rows dropped).
- Web `formatDate` (en-GB `d MMM y`) → `PatientPresentationFormatting.date` (`yMMMd`) for the DOB line; card date-stamp columns use locale-resolved `DateFormat('d')`/`MMM`/`'y'` + `EEEE`.
- Web `getVisitsForPatient`/`getDocumentsForPatient`/`getInvoicesForPatient`/`getPatientById`/`getVisitById` (sync in-memory) → Flutter async `FutureProvider` family (`patientPastVisitsProvider`, `patientVisitDocumentsProvider`, `patientDetailProvider`, `patientUpcomingAppointmentsProvider`). `getVisitById` is **not** available in the docs feature — linked-visit only shows `visitDate`.