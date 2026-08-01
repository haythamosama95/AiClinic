# Implementation Plan — Encounters (Visit Documentation) Page (Flutter Port)

Spec target: port the **Encounters** production page of `web-reference/` — the
`web-reference/src/features/visits/` feature folder, whose route entry is
`encounters` in `web-reference/src/pages/app/routes.tsx:119` rendering
`VisitPage.tsx` — into the Flutter `frontend/` visits feature, under
`frontend/lib/features/visits/presentation/`.

> This is a **feature-page** port, not a design-system showcase group port. There is no
> `ShowcaseGroupId` entry for "encounters" and no Dev components-page registration to flip.
> The binding source of truth is the web `features/visits/` folder
> (`VisitPage.tsx` + `useVisitForm.ts` + `VisitPatientBanner.tsx`/`VisitStepRail.tsx`
> + `sections/{Intake,Findings,Treatment}Section.tsx`
> + `components/{MedicalBackground,VitalSigns,Investigations,TreatmentPlan}Editor.tsx`
> + `components/*FormDialog.tsx` / `*EntryCard.tsx` / `EntryCardField.tsx`
> + `VisitSummary.tsx` / `VisitSummaryChronicle.tsx` / `VisitCompleted.tsx`
> + `mock-data.ts` / `types.ts`) plus the shared `web-reference/src/components/timeline/Timeline.tsx`
> and `web-reference/src/pages/app/settings/components/AnimatedPanels.tsx` (`StepPanel`).
> Wiring is therefore **route + provider** wiring, not `component_registry.dart` wiring.
>
> The Flutter visits feature already ships **everything but the UI**: domain
> (`features/visits/domain/*`), data (`features/visits/data/*`), application
> (`features/visits/application/*`), and presentation providers
> (`features/visits/presentation/providers/*`). The presentation `pages/` and
> `widgets/` folders are empty. This plan wires those providers to a new UI that
> reproduces the web reference's layout **and its exact animations/transitions/motions**.

---

## 0. Ambiguities & Design Decisions (resolve before coding)

> ⚠️ **Set-specific runtime-regression watchlist (from the UI runtime-errors checklist):**
> 1. **Material ancestor.** The web `EntryCardField`/`*EntryCard` shells and the `VisitCompleted`
>    seal are custom `motion.article`/`DecoratedBox` containers with colored borders, gradients,
>    and `box-shadow`. Any Flutter card built from `DecoratedBox`/`Container` gradients/borders
>    that hosts an `AppIconButton`/`InkWell` ripple **must** sit beneath a
>    `Material(type: MaterialType.transparency)` (or wrap the interactive child in `Material`)
>    so the ripple/inkwell has a Material ancestor — otherwise the ripple is clipped or asserts.
>    Bear in mind for every entry card and the completed-seal card.
> 2. **`intl` locale-specific `DateFormat`.** The web `VisitCompleted`/`VisitSummaryChronicle`
>    format `finalizedAt` with `toLocaleString('en-GB', { weekday, day, month, year, hour, minute })`.
>    The Flutter app already calls `ensureIntlDateFormattingInitialized()` at startup and ships
>    `package:intl`. The completed/chronicle timestamp must use a locale-aware
>    `DateFormat.yMMEd('en_GB').add_jms()` (or the active locale from `Localizations`/future
>    `localeProvider`) — do **not** hard-code `Locale('en','GB')`.
> 3. **`MediaQuery`/inherited reads in `initState`.** `VisitDocumentPage` drives phase transitions
>    and staggered enter animations. Read `AppMotion.prefersReducedMotion(context)`,
>    `Directionality.of(context)`, and `context.appColors` **only inside `build`**; the page's
>    `AnimationController`/`Ticker` may be created in `initState` but must not call
>    `context.appColors`/`MediaQuery` there. (Reference: `appointment_detail_page.dart`.)
> 4. **`FocusNode` sharing.** Each `*FormDialog` contains an `AppTextInput`/`AppTextarea` inside an
>    `AppDialog`. Do **not** share a single `FocusNode` between an ancestor `Focus` and a descendant
>    `TextField`; create a fresh `FocusNode` per dialog instance in `initState` and dispose it in
>    `dispose`. The `AppCombobox`/`AppSelect` popovers manage their own focus internally — do not
>    wrap them in an extra `Focus` widget.
> 5. **Overlay popover + `initState` reads.** The three form dialogs embed `AppCombobox` (medication
>    search) and `AppSelect` (vital type/frequency/duration). `AppCombobox` triggers async
>    `searchMedications`/`searchInvestigations` — those repo calls must happen on open/user-typed,
>    not in `initState`. Trigger them from the combobox `onSearch` callback only.

1. **forui vs native Material.** As with Actions/Inputs/Patient-details, the shipping convention is
   **native Material** under `core/ui/components/app_*.dart`; `forui` is imported nowhere. The
   visits page is **feature code**, so it imports `App*` widgets from the
   `core/ui/widgets/widgets.dart` barrel only — never Material internals directly. No new
   `core/ui/components/app_*.dart` files are introduced by this plan (all new widgets are
   feature-local under `presentation/widgets/` and `presentation/pages/`).
   **Decision: native Material via existing App abstractions; `forui-wrappers.md` is superseded.**

2. **Web `patientId`-keyed mock vs Flutter `visitId`-keyed real visit.** The web `VisitPage` is
   keyed by `patientId` and drives a local `useVisitForm` mock state machine over
   `MOCK_PATIENTS`. The Flutter feature is keyed by **`visitId`** (a real persisted visit) and
   already has the full state machine in providers. Mapping:

   | Web (`useVisitForm` / `types.ts`) | Flutter counterpart | Notes |
   |---|---|---|
   | `phase: 'intake'` | `EncounterPhase.subjective` (`encounter_phase.dart:5`) | label "Intake" |
   | `phase: 'findings'` | `EncounterPhase.objective` | label "Findings & Diagnosis" |
   | `phase: 'treatment'` | `EncounterPhase.plan` | label "Treatment" |
   | `phase: 'summary'` | `EncounterPhase.review` | label "Summary" |
   | `phase: 'completed'` | `visit.status == VisitStatus.completed` after `completeVisit` | not an `EncounterPhase` |
   | `direction` | derived from `EncounterActivePhaseNotifier.setPhase` (forward/back) | local page state |
   | `form.complaint`/`history` | `state.complaint`/`history` (`visit_documentation_notifier.dart`) | `updateComplaint`/`updateHistory` |
   | `form.examination`/`diagnosis` | `state.examination`/`diagnosis` | `updateExamination`/`updateDiagnosis` |
   | `form.treatmentNotes` | `state.plan` | `updatePlan` |
   | `form.chronicConditions`/`allergies`/`currentMedications` (Combobox multi over fixed catalogs) | `patientSafetyProvider(patientId)` + `encounterDraft.patientSafety` stage APIs | see §0.4 below |
   | `form.vitalSigns` (dialog entries) | `effectiveVisit.vitalSigns` + `stage{Create,Update,Archive}VitalSign` | `state.predefinedVitalSigns` catalog |
   | `form.investigationsNeeded` | `effectiveVisit.investigations` + `stage{Create,Update,Archive}Investigation` | `searchInvestigations` combobox |
   | `form.treatmentPlan` | `effectiveVisit.treatmentPlans` + `stage{Create,Update,Archive}TreatmentPlan` | `searchMedications` combobox |
   | `form.documents` (FileDropzone) | `effectiveVisit.attachments` + `pendingAttachments` + `stageAttachment`/`stageDeleteAttachment` | `AppFileDropzone` |
   | `finalizeVisit()` | `VisitDocumentationNotifier.completeVisit()` | returns `CompleteVisitResult` |
   | "Save draft" button | `notifier.save()` (or `saveAll()` before review) | `saveStatus` |
   | `goNext`/`goBack`/`goToPhase` | `encounterActivePhaseProvider(visitId).setPhase(next/prev)` | `EncounterPhase.next`/`previous` |
   | `summaryView='chronicle'` | `visitDetailViewProvider(visitId)` → `VisitDetailPage` at `/visits/:id/detail` | web chronicle maps to Flutter read-only detail |
   | `patient` (mock) | `patientSafetyProvider` patient + `visitDetailViewProvider` visit patient banner | no `Patient` model import needed; use `VisitDetail` fields |

   `EncounterPhase.context` ("Background") is a Flutter-only phase **not** in `stepperPhases`
   (`encounter_phase.dart:14`); it is surfaced as the Medical Background editor block inside the
   subjective phase (mirrors web `MedicalBackgroundEditor` inside `IntakeSection`), not as a
   separate stepper step. **Decision: render Medical Background as a sub-block of the Intake
   (subjective) section, exactly like the web.**

3. **Medical background editing model.** The web `MedicalBackgroundEditor` is three `MultiSelect`s
   over fixed catalogs (`CHRONIC_CONDITION_OPTIONS`, `ALLERGY_OPTIONS`, `MEDICATION_OPTIONS`
   in `mock-data.ts`). The Flutter data layer has **no fixed catalogs** for chronic conditions or
   allergies; only medications have an org catalog (`visitRepositoryProvider.searchMedications`),
   and patient-safety rows are free-form (`PatientAllergy.substance`/`reaction`,
   `PatientMedication.name`/`medicationId`/`note`, `PatientChronicCondition.name`/`note`).
   The stage APIs (`stageCreateAllergy(substance, reaction)`,
   `stageCreateMedication(name, medicationId, note)`, `stageCreateCondition(name, note)`,
   + update/archive) are add/edit/remove, not toggle-multi-select.
   **Decision: port `MedicalBackgroundEditor` as a feature-local "Patient safety editors"
   component** — three sub-editors (allergies, current medications, chronic conditions) each
   following the **same entry-card + add/edit dialog pattern** as the web `VitalSignsEditor` /
   `InvestigationsEditor` / `TreatmentPlanEditor` (which the web itself uses for visit-scoped
   data). This reuses the established `*EntryCard` + `*FormDialog` rhythm and the
   `stageCreate/Update/Archive*` APIs verbatim. The medications sub-editor uses `AppCombobox` over
   `searchMedications` to pick `medicationId` + auto-fill `name`; allergies & conditions use a
   plain `AppTextInput` for the free-form substance/name. This is the documented deviation from
   the web's `MultiSelect` and is justified by the Flutter data layer's free-form model.

4. **Frequency / duration option sets.** The web `FREQUENCY_OPTIONS` (`mock-data.ts:73`) and
   `DURATION_OPTIONS` (`mock-data.ts:85`) are fixed `SelectOption[]` lists. Flutter
   `TreatmentPlanItem.frequency`/`duration` are free `String?`. **Decision: define two
   feature-local const lists** `kFrequencyOptions` and `kDurationOptions` in
   `presentation/widgets/visit_catalog_options.dart` (copying the web's `value`→`label` maps
   verbatim) and render them as `AppSelect`s in the treatment-plan dialog, storing the `value`
   string into `TreatmentPlanItem.frequency`/`duration`. This reproduces the web UX exactly and
   keeps stored values constrained.

5. **Vital sign catalog.** The web `VITAL_SIGN_CATALOG` is a fixed 8-item list
   (`{id,label,unit,placeholder}`). Flutter loads the **org** predefined catalog via
   `VisitDocumentationState.predefinedVitalSigns` (already in state, populated from
   `listPredefinedVitalSigns()`). **Decision: use `state.predefinedVitalSigns`** as the vital-sign
   type picker in `VitalSignFormDialog` (`AppSelect` over `CatalogItem.id`/`name`/`defaultUnit`),
   not a hard-coded catalog. Each `CatalogItem` carries `id`, `name`, optional `defaultUnit` —
   map web `{id,label,unit,placeholder}` → `{CatalogItem.id, .name, .defaultUnit,
   placeholder=defUnit}`. The dialog stores `predefinedVitalSignId` + `name` + `value` + `unit`.

6. **Page header title/description.** The web `PageHeader` title/description is ternary on
   `isCompleted`/`isSummary`/`isChronicle` (`VisitPage.tsx:51-65`). **Decision: reproduce the exact
   ternary** in `VisitDocumentPage` (document / review / completed states) using `AppPageHeader`
   (`core/ui/components/app_page_header.dart`). The "Save draft" `Button variant=secondary
   leadingIcon=Save size=sm` appears only in the document state (not summary/completed) — reproduce
   verbatim, wiring `onPressed` to `notifier.save()`. The `finalizedAt` description text uses the
   locale-aware formatter from §0 watchlist #2.

7. **AnimatePresence ↔ AnimatedSwitcher.** The web wraps the three view branches
   (completed / summary / form) in `<AnimatePresence mode="wait">` with `motion.div key=…`
   `initial={{opacity:0}} animate={{opacity:1}} exit={{opacity:0}}` + `resolveTransition({duration:'base',ease:'out'})`
   (`VisitPage.tsx:90-191`). **Decision: use `AnimatedSwitcher` with `duration: AppMotion.base`
   (`220ms`) + `AppMotionEasing.out` + an `Opacity`-only transition builder** for the top-level
   view swap. **Inner phase swap** (intake→findings→treatment) uses the existing
   `AppStepPanel` (`core/ui/components/app_step_panel.dart`) which itself wraps
   `ShellPageTransition` (web `StepPanel`/`AnimatedPanels.tsx`: `slide-inline` wait-mode with
   `direction`-aware x offset + opacity + `AnimatedSize` height tween). **Reuse `AppStepPanel`
   as-is** — it is the exact port of the web `StepPanel`. Direction-aware x offset: pass the
   derived `direction` (forward=+1, back=−1) so the slide mirrors the web `custom={direction}`.

8. **Per-section stagger.** Each web section wraps its blocks in
   `staggerChildren(40)` + `motionPresets['slide-up']`. **Decision: reproduce with a small
   feature-local `VisitStagger` helper** (`presentation/widgets/visit_stagger.dart`) that runs an
   `AnimationController` (created in `initState`, `TickerProviderMixin`) with a
   `CurvedAnimation` per child at `Interval(0, 1, curve: AppMotionEasing.out)` and an incremental
   start offset of `AppMotion.staggerStep(context, stepMs: 40)` between children; each child wraps
   in `Opacity` + `Transform.translate(Offset(0, 8))` lerped from hidden→visible
   (== `motionPresets['slide-up']`). Respect `AppMotion.prefersReducedMotion` (collapse to instant
   / no offset). This mirrors `patients_page.dart`'s existing enter pattern and the web
   `slide-up` preset exactly.

9. **Entry card motion (`fade-scale` + `layout`).** Each web `*EntryCard` is a `motion.article
   layout={!getReducedMotion()} variants={motionPresets['fade-scale'].variants}
   initial="hidden" animate="visible" exit="exit"` inside an `AnimatePresence mode="popLayout"`.
   **Decision:** wrap each entry card list in an `AnimatedList`-equivalent: use
   `AnimatedSwitcher` (or a feature-local `VisitEntryList` wrapping `SingleChildScrollView` +
   per-item `AnimatedSize` + `Opacity`/`Transform.scale` enter/exit) keyed by entry `id`.
   The card itself renders the `fade-scale` enter via the `VisitStagger` helper or a one-shot
   `AnimationController` on mount. Reuse the `fade-scale` preset values (`AppMotionPreset.fadeScale`:
   opacity 0→1, scale 0.98→1, `AppMotionDuration.quick` 160ms, `out` curve). Reduced-motion → no
   animation. This matches the web `popLayout` reflow + `fade-scale` enter/exit closely enough for
   the spec; a full FLIP `layout` animation is out of scope (§6).

10. **Routes.** Flutter already defines `/visits/:visitId/document` and
    `/visits/:visitId/detail` (`app/routes.dart:117-121`, `app/app_routes.dart:96-107`) — both
    currently `shellPlaceholderPage`. The top `/encounters` route (`app/routes.dart:86`) is also a
    placeholder and **out of scope** (no visits list in this plan). **Decision: replace the two
    visit-segment placeholders with the new pages** — document → `VisitDocumentPage`, detail →
    `VisitDetailPage`. Keep `/encounters` as a placeholder (list deferred, §6). The web
    `/encounters/:patientId/chronicle` route maps to Flutter `/visits/:visitId/detail`
    (read-only chronicle view).

11. **Guided vs expert workspace mode.** `workspaceModeProvider` (`workspace_mode_provider.dart`)
    already ships `WorkspaceMode.guided` (web's single-phase stepper) **and** `expert`
    (Flutter-only single-page accordion with all sections stacked). The web reference only models
    guided. **Decision:** Phase 1-3 build the **guided** experience (matches web exactly, including
    all motions). **Phase 4 adds the expert accordion** as a Flutter-only enhancement, reusing the
    same section widgets and the `slide-up` stagger across stacked sections, plus
    `expertModeScrollTargetProvider` for "Edit" navigation from the summary that scrolls to the
    target section. The `AppSegmentedControl` (web has none — this is Flutter-only) toggles
    guided/expert in the patient banner footer, mirroring the `workspaceModeProvider.toggleMode`.

12. **Patient banner + step rail.** The web `VisitPatientBanner` uses a mock `Patient` (avatar +
    name + age); the step rail is 3 hardcoded steps (`VisitStepRail.tsx:7-15`). Flutter has no
    `Patient` model import in the visits feature; the banner derives identity from `VisitDetail`
    (`doctorName`, `visitDate`, `visitType`, patient implicit) + `patientSafetyProvider` last
    vitals. **Decision: render the banner from `visitDetailViewProvider`/`visitDocumentationProvider`
    `VisitDetail` fields** — avatar initials from `patientId` (or patient name if a lightweight
    patient lookup exists; otherwise show `visit.id` short form + `doctorName` + `visitDate`).
    The step rail renders `EncounterPhase.stepperPhases` (`subjective`/`objective`/`plan`) using
    `EncounterPhase.label`/`EncounterPhase.icon`, with state derived from
    `encounterPhaseBadgesProvider` (empty/hasContent/error) → web `stepState` (upcoming/current/
    complete). The animated connector fill (`motion.span width: 0%→100%`) becomes a
    `Tween<double>` on an `AnimatedContainer`/`Align` width, `AppMotionDuration.quick`/`out`.
    Completed-step icon = `Icons.check_rounded`; clickable when not upcoming and not review
    (matches web `clickable` predicate `VisitStepRail.tsx:48`).

13. **i18n / RTL.** The page is production code, RTL-aware via `AppTheme`. All layout uses
    `Directionality.of(context)`; leading/trailing icons mirror automatically through the
    `App*` widgets. Motion `slide-inline` x-offset mirrors via `AppMotion.hidden(slideInline,
    direction: Directionality.of(context))` (already implemented in `app_motion.dart:152`). No
    AR copy is hardcoded in this plan; EN copy mirrors the web verbatim and is localizable later
    via the existing `l10n` machinery (out of scope to wire now — tracked in §6).

14. **Controlled/uncontrolled.** Text fields bind to `visitDocumentationProvider` via
    `onChanged` → `updateComplaint`/etc. (controlled by provider state). Dialog form fields use
    local `TextEditingController`s seeded on open (`useEffect([open,…])` → Flutter
    `didUpdateWidget`/`initState` sync), matching the web dialog reset-on-open pattern.

15. **Error/invalid placement.** Validation errors in the form dialogs render via `AppFormField`
    `error:` (matches web `FormField error=`). Save/complete errors surface via
    `state.saveStatus`/`state.errorMessage` as a dismissible banner above the footer, using
    `context.appColors.statusError*` (matches web `status-warning` review band + error text).

---

## 1. Existing App assets to reuse (do not recreate)

| Asset | Path | Used by |
|---|---|---|
| `AppPageHeader` | `core/ui/components/app_page_header.dart` | page title/description/actions in document & detail pages |
| `AppCard` (`CardVariant.raised`, `CardPadding.lg/md/sm`) | `core/ui/components/app_card.dart` | raised `Card` wrapping the `StepPanel` + summary/completed cards (matches web `Card variant="raised" padding="lg"`) |
| `AppButton` (`variant=primary/secondary/ghost`, `size=sm/md`, `leadingIcon`/`trailingIcon`) | `core/ui/components/app_button.dart` | Back / Continue / Review / Save draft / Finalize / Edit / New visit / Print |
| `AppIconButton` (`size=sm`) | `core/ui/components/app_icon_button.dart` | entry-card edit/remove actions (Pencil/Trash) |
| `AppFormField` (`label`, `required`, `hint`, `helper`, `error`) | `core/ui/components/app_form_field.dart` | every text/select/combobox/dropzone field |
| `AppTextarea` (`autoGrow`, `rows`, `showCounter`) | `core/ui/components/app_textarea.dart` | complaint/history/examination/diagnosis/treatment-notes |
| `AppTextInput` | `core/ui/components/app_text_input.dart` | vital-sign value, treatment-plan dosage, allergy substance, medication name, condition name, investigation note |
| `AppSelect` + `AppSelectOption` (`{value,label,disabled,disabledReason}`) | `core/ui/components/app_select.dart` | vital-sign type, frequency, duration |
| `AppCombobox` + `AppComboboxItem` (`{id,label,meta,disabled,…}`) | `core/ui/components/app_combobox.dart` | medication search (treatment plan + current medications), investigation search |
| `AppFileDropzone` + `AppFileItem` | `core/ui/components/app_file_dropzone.dart` | attachments dropzone |
| `AppDialog` (`open`, `onOpenChange`, `size=sm/md`, `title`, `footer`) | `core/ui/components/app_dialog.dart` | all `*FormDialog`s |
| `AppStepPanel` (`stepKey`, direction-aware `slide-inline`) | `core/ui/components/app_step_panel.dart` | inner phase swap (exact port of web `StepPanel`) |
| `AppTimeline` (`events: [{id,timestamp,title,description,group}]`) | `core/ui/components/app_timeline.dart` | chronicle view (web `Timeline.tsx`) in `VisitDetailPage` |
| `AppEmptyState` + `EmptyStateAction` | `core/ui/components/app_empty_state.dart` | empty entry-card lists ("No vital signs recorded yet." etc.), permission-denied, not-found |
| `AppErrorState` | `core/ui/components/app_error_state.dart` | `visitDocumentationProvider`/`visitDetailViewProvider` error branch |
| `AppSkeletonizerZone` / `AppSkeleton` | `core/ui/components/app_skeletonizer_zone.dart`, `app_skeleton.dart` | async-loading skeletons |
| `AppAvatar` | `core/ui/components/app_avatar.dart` | patient banner avatar |
| `AppBadge` / `AppChip` | `core/ui/components/app_badge.dart`, `app_chip.dart` | phase completion badges, attachment type chip |
| `AppDescriptionList` | `core/ui/components/app_description_list.dart` | summary ledger `<dl>` rows (web `LedgerSection`) |
| `AppSegmentedControl` | `core/ui/components/app_segmented_control.dart` | guided/expert mode toggle (Flutter-only) |
| `AppMotion`, `AppMotionPreset`, `AppMotionDuration`, `AppMotionEasing`, `AppMotion.prefersReducedMotion`, `AppMotion.staggerStep`, `AppMotion.hidden`, `AppMotion.lerpPreset`, `AppMotion.animatedPreset` | `core/ui/motion/app_motion.dart` | all transitions/staggers (fade, fadeScale, slideUp, slideInline, rowEnter) |
| Theme: `context.appColors` (`AppSemanticColors`), `AppSpacing`, `AppRadius`, `AppTypography`, `AppElevation` | `core/ui/theme/*` | every widget |
| `widgets.dart` barrel | `core/ui/widgets/widgets.dart` | single import for all of the above |
| `ShellPageTransition` | `app/shell/layout/shell_page_transition.dart` (via `AppStepPanel`) | directional slide-inline (already wrapped by `AppStepPanel`) |

### Existing visits feature providers/state to wire (the "existing implementation")

| Provider / model | Path | Used by |
|---|---|---|
| `visitDocumentationProvider(visitId)` (`AsyncNotifierProvider.autoDispose.family<VisitDocumentationNotifier, VisitDocumentationState, String>`) | `presentation/providers/visit_documentation_notifier.dart` | main page state: complaint/history/examination/diagnosis/plan, encounterDraft, saveStatus; actions `updateComplaint`/`updateHistory`/`updateExamination`/`updateDiagnosis`/`updatePlan`, `save`, `saveAll`, `completeVisit`, `prepareEncounterReview`, `enterEditMode`/`enterWorkspaceEditMode`, `reloadVisit`/`reloadAfterStale` |
| `VisitDocumentationState` (`effectiveVisit`, `persistedVisit`, `encounterDraft`, `predefinedVitalSigns`, `saveStatus`, `noteEditMode`, `workspaceEditMode`, `errorMessage`, `canEditWorkspace`, `hasUnsavedDraft`, `needsPersistBeforeSubmit`) | same file | all section bindings |
| `stage{Create,Update,Archive}VitalSign` / `stage{Create,Update,Archive}Investigation` / `stage{Create,Update,Archive}TreatmentPlan` / `stageAttachment`/`stageDeleteAttachment` / `stage{Create,Update,Archive}Allergy`/`Medication`/`Condition` / `stageInvestigationResult` | same file | editor add/edit/remove actions |
| `encounterActivePhaseProvider(visitId)` (`EncounterActivePhaseNotifier`, `setPhase`) | `presentation/providers/encounter_step_provider.dart` | stepper active phase; `review` triggers `prepareEncounterReview` |
| `encounterPhaseBadgesProvider(visitId)` (`PhaseBadges = Map<EncounterPhase, PhaseCompletionBadge>`) | same file | step-rail complete/current/upcoming state |
| `expertModeScrollTargetProvider(visitId)` (`ExpertModeScrollTargetNotifier`, `request`/`clear`) | `presentation/providers/expert_mode_scroll_provider.dart` | summary "Edit" → scroll to section in expert mode |
| `patientSafetyProvider(patientId)` (`PatientSafetyContext` with allergies/currentMedications/chronicConditions/lastVitals) | `presentation/providers/patient_safety_provider.dart` | medical background editors + banner last vitals |
| `workspaceModeProvider` (`WorkspaceMode.guided`/`expert`, `setMode`/`toggleMode`) | `presentation/providers/workspace_mode_provider.dart` | guided/expert toggle |
| `visitDetailViewProvider(visitId)` (`VisitDetailViewState`: visit, canEditDocumentation, hasBranchAccess, canUploadAttachments) | `presentation/providers/visit_detail_provider.dart` | `VisitDetailPage` (chronicle) |
| `visitDetailProvider(visitId)` (deprecated alias) | same file | legacy fallback (avoid) |
| Domain: `EncounterPhase` (`stepperPhases`, `label`, `icon`, `next`/`previous`, `stepperIndex`), `PhaseCompletionBadge` | `domain/encounter_phase.dart` | step rail + navigation |
| `VisitDetail`, `VisitVitalSign`, `VisitInvestigation`, `TreatmentPlanItem`, `VisitAttachmentItem`, `PatientAllergy`, `PatientMedication`, `PatientChronicCondition`, `PatientSafetyContext`, `VisitEncounterDraft`, `CatalogItem`, `VisitStatus`, `VisitSubmitReadiness`/`evaluateVisitSubmitReadiness`, `visitHasPersistableDocumentation` | `domain/*` | all section models |
| `visitRepositoryProvider` (`searchMedications`, `searchInvestigations`, `listPredefinedVitalSigns`, attachment download/delete, patient safety CRUD) + `visitAttachmentServiceProvider` | `data/visit_repository.dart`, `data/visit_attachment_service.dart` | combobox async sources, attachment upload |
| `visitMessageForRpc` | `application/visit_rpc_messages.dart` | RPC error → user message |
| `context.nav.goVisitDocument`/`goVisitDetail`/`pushVisitDocument`/`pushVisitDetail` | `app/navigation/app_navigator.dart:64-68` | navigation |
| `AppRoutes.visitDocument(visitId)` / `visitDetail(visitId)` | `app/app_routes.dart:100-107` | route paths |
| `authSessionProvider` (`activeBranchId`, permissions) | `app/providers/auth_session_provider.dart` | branch gating |
| `permissionServiceProvider` (`canEditVisitSoap`, `canUploadVisitAttachments`) | (via `AuthRouteGuard` + `_canEditVisit`) | edit gating |

### Domain models in play

- `EncounterPhase` (`features/visits/domain/encounter_phase.dart:4`): `context, subjective, objective, plan, review`; `stepperPhases = [subjective, objective, plan]`; `label`/`icon`/`next`/`previous`.
- `VisitDetail` (`features/visits/domain/visit_detail.dart:13`): `id, branchId, appointmentId, patientId, doctorId, doctorName, visitDate, status, visitType?, …, vitalSigns, investigations, treatmentPlans, attachments, pendingInvestigations`.
- `VisitVitalSign` (`domain/visit_vital_sign.dart`): `id, name, value, unit?, predefinedVitalSignId?`.
- `VisitInvestigation` (`domain/visit_investigation.dart`): `id, name, note?, investigationId?, result?, resultRecordedAt?, orderedVisitId?, orderedVisitDate?`.
- `TreatmentPlanItem` (`domain/treatment_plan_item.dart`): `id, visitId, patientId, medicationName, medicationId?, dosage?, frequency?, duration?, notes?`.
- `VisitAttachmentItem` (`domain/visit_attachment_item.dart`): `id, fileType, label?, uploadedBy, uploadedByName?, sizeBytes, createdAt, canDownload, canDelete`.
- `PatientAllergy`/`PatientMedication`/`PatientChronicCondition` (`domain/patient_safety.dart`): `id, substance/name, reaction?/note?`.
- `PatientSafetyContext` (`domain/patient_safety.dart`): `allergies, currentMedications, chronicConditions, lastVitals`.
- `VisitEncounterDraft` + `PatientSafetyDraft` (`domain/visit_encounter_draft.dart`): overlay staging + `applyTo`.
- `CatalogItem` (`domain/catalog_item.dart`): `id, name, defaultUnit?`.
- `VisitStatus` (`domain/visit_status.dart`): `inProgress, completed`; `isTerminal`, `canTransitionTo`.
- `VisitSubmitReadiness`/`evaluateVisitSubmitReadiness`/`visitHasPersistableDocumentation` (`domain/visit_submit_readiness.dart`): submit validation (used by summary "Finalize" gating).

---

## 2. New feature-local widgets to introduce (no new `core/ui` files)

All new files live under `frontend/lib/features/visits/presentation/` (`widgets/`, `pages/`).
No new `core/ui/components/app_*.dart` and **no** barrel (`widgets.dart`) edit is required — these
are feature widgets consumed only by the visits pages.

| File (`features/visits/presentation/widgets/`) | Export name | Web analog | Purpose | Phase |
|---|---|---|---|---|
| `visit_patient_banner.dart` | `VisitPatientBanner` | `VisitPatientBanner.tsx` | raised `AppCard` with avatar + patient name + age/visit meta + embedded `VisitStepRail`; optional guided/expert `AppSegmentedControl` footer | 1 |
| `visit_step_rail.dart` | `VisitStepRail` | `VisitStepRail.tsx` | 3-step `<ol>` with circular nodes (complete=current=upcoming), animated connector fill, check/icon glyphs, clickable-back predicate | 1 |
| `visit_stagger.dart` | `VisitStagger` (+ `VisitStaggeredItem`) | `staggerChildren(40)` + `motionPresets['slide-up']` | feature-local stagger helper: `AnimationController` + per-child `Interval` offset `AppMotion.staggerStep(context,40ms)`, opacity+y(8) lerp, reduced-motion aware | 1 |
| `visit_view_fade.dart` | `VisitViewFade` | `AnimatePresence mode="wait"` (top-level opacity swap) | `AnimatedSwitcher` with `Opacity`-only transition, `AppMotion.base`/`out`, keyed by view (form/summary/completed) | 1 |
| `visit_entry_card.dart` | `VisitEntryCard`, `VisitEntryCardField`, `VisitEntryCardFieldsRow` | `EntryCardField.tsx` + `*EntryCard.tsx` shell | reusable rounded `Material` card with left-accent border + `fade-scale` enter + fields row + trailing edit/remove `AppIconButton`s; shared by vital/investigation/treatment/safety cards | 2 |
| `visit_entry_list.dart` | `VisitEntryList<T>` | `AnimatePresence mode="popLayout"` | per-item `fade-scale` enter/exit + `AnimatedSize` reflow list keyed by entry `id`; reduced-motion aware | 2 |
| `visit_text_section.dart` | `VisitTextSection` | `IntakeSection`/`FindingsSection`/`TreatmentSection` text blocks | `AppFormField` + `AppTextarea` bound to `updateComplaint`/`History`/`Examination`/`Diagnosis`/`Plan` + `slide-up` stagger | 1 (shared) |
| `medical_background_editor.dart` | `MedicalBackgroundEditor` | `MedicalBackgroundEditor.tsx` | raised-bordered block hosting three `PatientSafetyEditor`s (allergies/medications/conditions) | 2 |
| `patient_safety_editor.dart` | `PatientSafetyEditor` (+ `PatientSafetyKind` enum) | (synthesized from `VitalSignsEditor` pattern) | entry-card list + empty state + "Add …" `AppButton` + add/edit dialog; generic over kind (allergy/medication/condition) | 2 |
| `allergy_form_dialog.dart` | `AllergyFormDialog` | (synthesized) | `AppDialog` with substance `AppTextInput` + reaction/severity `AppSelect`; bind `stageCreate/UpdateAllergy` | 2 |
| `medication_form_dialog.dart` | `MedicationFormDialog` | (synthesized) | `AppDialog` with medication-name `AppCombobox` over `searchMedications` (auto-fill name) + note `AppTextInput`; bind `stageCreate/UpdateMedication` | 2 |
| `condition_form_dialog.dart` | `ConditionFormDialog` | (synthesized) | `AppDialog` with name `AppTextInput` + note `AppTextInput`; bind `stageCreate/UpdateCondition` | 2 |
| `vital_signs_editor.dart` | `VitalSignsEditor` | `VitalSignsEditor.tsx` | entry-card wrap (chips) + empty state + add `AppButton`; bind `stage{Create,Update,Archive}VitalSign` | 2 |
| `vital_sign_form_dialog.dart` | `VitalSignFormDialog` | `VitalSignFormDialog.tsx` | `AppDialog` (size sm) with vital-type `AppSelect` (over `state.predefinedVitalSigns`) + value `AppTextInput` with catalog placeholder/unit; validation | 2 |
| `vital_sign_entry_card.dart` | `VitalSignEntryCard` | `VitalSignEntryCard.tsx` | `VisitEntryCard` variant: uppercase label + big tabular value + unit + edit/remove | 2 |
| `investigations_editor.dart` | `InvestigationsEditor` | `InvestigationsEditor.tsx` | entry-card list + empty state + add `AppButton`; bind `stage{Create,Update,Archive}Investigation` | 3 |
| `investigation_form_dialog.dart` | `InvestigationFormDialog` | `InvestigationFormDialog.tsx` | `AppDialog` (md) with investigation `AppCombobox` over `searchInvestigations` + note `AppTextarea` | 3 |
| `investigation_entry_card.dart` | `InvestigationEntryCard` | `InvestigationEntryCard.tsx` | `VisitEntryCard`: Investigation/Type/Note fields | 3 |
| `treatment_plan_editor.dart` | `TreatmentPlanEditor` | `TreatmentPlanEditor.tsx` | entry-card list + empty state + add `AppButton`; bind `stage{Create,Update,Archive}TreatmentPlan` | 3 |
| `treatment_plan_form_dialog.dart` | `TreatmentPlanFormDialog` | `TreatmentPlanFormDialog.tsx` | `AppDialog` (md) with medication `AppCombobox` over `searchMedications` + dosage `AppTextInput` + frequency `AppSelect` + duration `AppSelect`; validation | 3 |
| `treatment_plan_entry_card.dart` | `TreatmentPlanEntryCard` | `TreatmentPlanEntryCard.tsx` | `VisitEntryCard`: Medication/Dosage/Frequency/Duration fields | 3 |
| `visit_attachments_editor.dart` | `VisitAttachmentsEditor` | (web `FileDropzone` inside `TreatmentSection`) | `AppFileDropzone` bound to `pendingAttachments` + `effectiveVisit.attachments` + `stageAttachment`/`stageDeleteAttachment`; "PDF, JPG, PNG — max 10 MB" helper | 3 |
| `visit_catalog_options.dart` | `kFrequencyOptions`, `kDurationOptions`, `kAttachmentKinds` (const) | `FREQUENCY_OPTIONS`/`DURATION_OPTIONS` (`mock-data.ts:73,85`) | fixed `AppSelectOption` lists copied verbatim from web | 3 |
| `intake_section.dart` | `IntakeSection` | `IntakeSection.tsx` | header + complaint + history + `MedicalBackgroundEditor`; `slide-up` stagger | 2 (header/text in 1) |
| `findings_section.dart` | `FindingsSection` | `FindingsSection.tsx` | header + examination + `VitalSignsEditor` + diagnosis; `slide-up` stagger | 2 |
| `treatment_section.dart` | `TreatmentSection` | `TreatmentSection.tsx` | header + treatment notes + `InvestigationsEditor` + `TreatmentPlanEditor` + `VisitAttachmentsEditor`; `slide-up` stagger | 3 |
| `visit_summary.dart` | `VisitSummary` | `VisitSummary.tsx` | warning band + 3 `LedgerSection`s (Intake/Findings/Treatment) + Edit/Finalize footer; `fade-scale` + `staggerChildren(60)` + per-section `slide-up` delays | 4 |
| `visit_summary_ledger.dart` | `VisitSummaryLedger`, `LedgerEntry`, `LedgerInlineList`, `LedgerText` | `VisitSummary.tsx` `LedgerSection`/`LedgerEntry`/`LedgerInlineList`/`LedgerText` | `<dl>` grid via `AppDescriptionList` + per-section motion + empty `—`/`None recorded` fallbacks | 4 |
| `visit_completed.dart` | `VisitCompleted` | `VisitCompleted.tsx` | success seal card: radial-gradient bg + animated seal (`scale 0.6→1`, `rotate -20→0`, `deliberate`/`out`, delays) + title + finalized timestamp + 3 "Recorded phase" cards (`staggerChildren(50)` `slide-up`) + actions (View patient/Print/Start new visit) | 4 |
| `visit_recorded_phase_card.dart` | `VisitRecordedPhaseCard` | `RecordedPhase` (`VisitCompleted.tsx:30`) | success-border mini-card with icon circle + "Recorded" check | 4 |
| `expert_visit_accordion.dart` | `ExpertVisitAccordion` | (Flutter-only) | stacked all sections in one scroller with `slide-up` stagger + `expertModeScrollTargetProvider` scroll-to; used when `workspaceModeProvider == expert` | 4 |

The pages themselves:

| File (`features/visits/presentation/pages/`) | Export name | Web analog | Purpose | Phase |
|---|---|---|---|---|
| `visit_document_page.dart` | `VisitDocumentPage` (`ConsumerStatefulWidget` + `SingleTickerProviderStateMixin`) | `VisitPage.tsx` | the main encounter workspace: `AppPageHeader` + `VisitPatientBanner` + `AnimatedSwitcher` view swap (form/summary/completed) + `AppStepPanel` (guided) or `ExpertVisitAccordion` (expert) + Back/Continue footer; wires `visitDocumentationProvider` + `encounterActivePhaseProvider` + `encounterPhaseBadgesProvider` + `workspaceModeProvider` | 1 (shell), 2/3 (sections), 4 (summary/completed/expert) |
| `visit_detail_page.dart` | `VisitDetailPage` (`ConsumerWidget`) | `VisitSummaryChronicle.tsx` (web chronicle) + read-only completed | read-only chronicle: `AppTimeline` over the visit's sections + header (patient + MRN-less meta + finalized timestamp) + actions (Card view / Edit / Print / New visit); wires `visitDetailViewProvider` | 4 |

---

## 3. Phasing

> Rationale — **4 phases**, each a logical, independently-shippable cluster:
> - **Phase 1** = page shell, routing, patient banner + step rail, intake text fields — the
>   navigable skeleton with the first phase's content, fully animated.
> - **Phase 2** = medical background (patient safety) editors + findings section (vital signs) —
>   the two dialog-driven editors that establish the `*Editor`/`*EntryCard`/`*FormDialog` pattern.
> - **Phase 3** = treatment section (investigations + treatment plan + attachments) — completes
>   the three documentation phases and the "Save draft" / "Continue → Review" wiring.
> - **Phase 4** = summary review, completed success screen, chronicle detail page, expert
>   workspace mode, and final route/motion polish.
> Each phase ships behind the same `VisitDocumentPage`; later phases plug new section widgets into
> the phase switch built in Phase 1.

### Phase 1 — Page shell, routing, patient banner + step rail, intake text fields

Widgets: **VisitDocumentPage, VisitPatientBanner, VisitStepRail, VisitStagger, VisitViewFade,
VisitTextSection, IntakeSection (text portion only)**

| Widget | Flutter widget(s) to create | File(s) | Reuse | Wrapper | Deps |
|---|---|---|---|---|---|
| Page shell | `VisitDocumentPage` (`ConsumerStatefulWidget` + `SingleTickerProviderStateMixin`) | CREATE `pages/visit_document_page.dart` | `AppPageHeader`, `AppCard`, `AppButton`, `AppMotion`, `widgets.dart`; providers `visitDocumentationProvider(visitId)`, `encounterActivePhaseProvider(visitId)`, `encounterPhaseBadgesProvider(visitId)`, `workspaceModeProvider`, `authSessionProvider` | NEW (page) | none |
| Patient banner | `VisitPatientBanner` | CREATE `widgets/visit_patient_banner.dart` | `AppCard` (raised), `AppAvatar`, `AppSegmentedControl` (guided/expert footer), `VisitStepRail`, `context.appColors`, `AppSpacing` | NEW | `VisitStepRail` |
| Step rail | `VisitStepRail` | CREATE `widgets/visit_step_rail.dart` | `AppMotion` (connector fill `Tween` `quick`/`out`), `EncounterPhase.label`/`icon`/`stepperIndex`, `encounterPhaseBadgesProvider` (empty/hasContent/error → upcoming/current/complete), `Icons.check_rounded` for complete | NEW | none |
| Stagger helper | `VisitStagger` + `VisitStaggeredItem` | CREATE `widgets/visit_stagger.dart` | `AppMotion.staggerStep`, `AppMotionEasing.out`, `AppMotion.prefersReducedMotion`, `AnimationController`/`CurvedAnimation`/`Interval` | NEW | none |
| View fade | `VisitViewFade` | CREATE `widgets/visit_view_fade.dart` | `AnimatedSwitcher` + `Opacity`, `AppMotion.base`/`AppMotionEasing.out` | NEW | none |
| Text section | `VisitTextSection` | CREATE `widgets/visit_text_section.dart` | `AppFormField`, `AppTextarea` (`autoGrow`, `rows`), `VisitStagger` | NEW | `VisitStagger` |
| Intake section | `IntakeSection` (text portion: header + complaint + history; medical background block is a placeholder `SizedBox` filled in Phase 2) | CREATE `widgets/intake_section.dart` | `VisitTextSection`, `VisitStagger`, `AppTypography` | NEW | `VisitTextSection`, `VisitStagger` |

**Route wiring (Phase 1):**
- `app/router.dart:117-119` — replace `shellPlaceholderPage` for
  `'${AppRoutes.visits}/:visitId/${AppRoutes.visitDocumentSegment}'` with
  `(context, state) => VisitDocumentPage(visitId: state.pathParameters['visitId']!)`.
- Leave `'${AppRoutes.visits}/:visitId/${AppRoutes.visitDetailSegment}'` placeholder for Phase 4.

**Motion detail (Phase 1):**
- Top-level view swap: `VisitViewFade` wraps the form/summary/completed branch in
  `AnimatedSwitcher` (`switchInCurve`/`switchOutCurve` = `AppMotionEasing.out`,
  `duration = AppMotion.base` 220ms), `TransitionBuilder` = `Opacity(opacity: animation.value)`
  (matches web `initial/animate/exit opacity 0/1/0`). Keyed by
  `state.visit.status == completed ? 'completed' : activePhase == review ? 'summary' : 'form'`.
- Inner phase swap: `AppStepPanel(stepKey: activePhase.name)` wraps the active section
  (`IntakeSection`/`FindingsSection`/`TreatmentSection`). `AppStepPanel` already implements the
  web `StepPanel` `slide-inline` wait-mode + `AnimatedSize` height tween. Pass `direction`
  (forward=+1 → x: +12→0 LTR / −12→0 RTL; back=−1 → mirror) by deriving from the previous vs new
  `EncounterPhase.stepperIndex`.
- Each section's blocks stagger via `VisitStagger` with `stepMs: 40` (`slide-up`: opacity 0→1,
  y 8→0, `AppMotion.base`/`out`).
- Step-rail connector fill: per connector `Tween<double>(begin: 0, end: completeFlag ? 1 : 0)`
  driven by `AnimatedBuilder` over a 160ms `quick`/`out` `AnimationController`
  (matches web `motion.span width 0%→100% quick/out`). Reduced-motion → instant.

**State bindings (Phase 1):**
- `visitDocumentationProvider(visitId)` async-when: loading → `AppSkeletonizerZone`, error →
  `AppErrorState` + retry (`reloadVisit`), data → page body.
- Active phase: `encounterActivePhaseProvider(visitId)`; `setPhase(next/prev/review)` on
  Continue/Back/goToPhase. `review` auto-calls `prepareEncounterReview` (already in notifier).
- Banner: `visitDetailViewProvider(visitId)` for `VisitDetail` (doctorName, visitDate, visitType),
  `patientSafetyProvider(patientId)` for last vitals line.
- "Save draft" `AppButton` (secondary, sm, `Icons.save_outlined` leading) → `notifier.save()`;
  disabled while `saveStatus == saving`; show a transient "Saved" state on `saved`.

**Phase 1 acceptance:** navigating to `/visits/<id>/document` renders the header, patient banner
with a working 3-step rail (clickable-back when complete), the Intake section with complaint +
history text areas, animated phase swap, and Back/Continue footer. Guided/expert toggle present
(expert branch is a "coming in Phase 4" `AppEmptyState` for now).

### Phase 2 — Medical background editors + findings section (vital signs)

Widgets: **MedicalBackgroundEditor, PatientSafetyEditor, AllergyFormDialog,
MedicationFormDialog, ConditionFormDialog, VitalSignsEditor, VitalSignFormDialog,
VitalSignEntryCard, VisitEntryCard, VisitEntryList, FindingsSection, IntakeSection (full)**

| Widget | Flutter widget(s) | File(s) | Reuse | Wrapper | Deps |
|---|---|---|---|---|---|
| Entry card shell | `VisitEntryCard`, `VisitEntryCardField`, `VisitEntryCardFieldsRow` | CREATE `widgets/visit_entry_card.dart` | `Material(type: transparency)` + `DecoratedBox` (rounded `AppRadius.xl`, `borderSubtle`, left-accent `border.actionPrimary@50%`), `AppIconButton` (edit Pencil/remove Trash, sm), `AppMotionPreset.fadeScale` one-shot enter | NEW | none |
| Entry list | `VisitEntryList<T>` | CREATE `widgets/visit_entry_list.dart` | per-item `AnimatedSwitcher`/`AnimatedSize` + `Opacity`/`Transform.scale` `fade-scale` enter/exit keyed by `id`; reduced-motion aware | NEW | `AppMotion` |
| Medical background | `MedicalBackgroundEditor` | CREATE `widgets/medical_background_editor.dart` | bordered block (`AppRadius.xl`, `borderSubtle`, `surfaceDefault`), 3-col `Wrap`/`Column` hosting three `PatientSafetyEditor`s | NEW | `PatientSafetyEditor` |
| Safety editor | `PatientSafetyEditor` (+ `PatientSafetyKind {allergy,medication,condition}`) | CREATE `widgets/patient_safety_editor.dart` | `VisitEntryList`, `AppEmptyState` ("No allergies recorded yet."), `AppButton` (secondary, sm, Plus) → opens dialog; generic per-kind labels/icons; bind `patientSafetyProvider(patientId)` + `stage{Create,Update,Archive}Allergy/Medication/Condition` from `visitDocumentationProvider` | NEW | `VisitEntryList`, dialogs, `patientSafetyProvider` |
| Allergy dialog | `AllergyFormDialog` | CREATE `widgets/allergy_form_dialog.dart` | `AppDialog` (sm): substance `AppTextInput` (required) + reaction `AppSelect` (`AllergySeverityOptions.items`); `stageCreate/UpdateAllergy`; reset on open; dispose `FocusNode` | NEW | `AppDialog`, `AppFormField`, `AppTextInput`, `AppSelect` |
| Medication dialog | `MedicationFormDialog` | CREATE `widgets/medication_form_dialog.dart` | `AppDialog` (sm): name `AppCombobox` over `searchMedications` (auto-fill `medicationName` from selected `label`); note `AppTextInput`; `stageCreate/UpdateMedication` | NEW | `AppDialog`, `AppCombobox` (`searchMedications`), `AppTextInput` |
| Condition dialog | `ConditionFormDialog` | CREATE `widgets/condition_form_dialog.dart` | `AppDialog` (sm): name `AppTextInput` (required) + note `AppTextInput`; `stageCreate/UpdateCondition` | NEW | `AppDialog`, `AppTextInput` |
| Vital signs editor | `VitalSignsEditor` | CREATE `widgets/vital_signs_editor.dart` | bordered block + `VisitEntryList` (wrap, chip-style) + empty state (`Icons.monitor_heart_outlined`) + "Add vital sign"/"Add another vital sign" `AppButton`; `canAddMore = usedIds.size < predefinedVitalSigns.length`; bind `effectiveVisit.vitalSigns` + `stage{Create,Update,Archive}VitalSign` | NEW | `VisitEntryList`, `VitalSignFormDialog`, `VitalSignEntryCard` |
| Vital sign dialog | `VitalSignFormDialog` | CREATE `widgets/vital_sign_form_dialog.dart` | `AppDialog` (sm): type `AppSelect` over `state.predefinedVitalSigns` (`CatalogItem`→`{value:id,label:name,disabled: usedIds}`) + value `AppTextInput` (placeholder from `defaultUnit`); validation (type required, value required); `stageCreate/UpdateVitalSign` | NEW | `AppDialog`, `AppSelect`, `AppTextInput` |
| Vital sign card | `VitalSignEntryCard` | CREATE `widgets/vital_sign_entry_card.dart` | `VisitEntryCard` variant: uppercase `label` + tabular `value` + `unit` suffix; edit/remove `AppIconButton` | NEW | `VisitEntryCard` |
| Findings section | `FindingsSection` | CREATE `widgets/findings_section.dart` | header + examination `VisitTextSection` + `AppFormField`("Vital signs", helperText) wrapping `VitalSignsEditor` + diagnosis `VisitTextSection`; `slide-up` stagger (40ms) | NEW | `VisitTextSection`, `VitalSignsEditor`, `VisitStagger` |
| Intake (full) | `IntakeSection` | MOD `widgets/intake_section.dart` | replace Phase-1 placeholder with `MedicalBackgroundEditor` bound to `patientSafetyProvider` + `encounterDraft.patientSafety`; `slide-up` stagger | (extend) | `MedicalBackgroundEditor` |

**State bindings (Phase 2):**
- Patient safety editors read `patientSafetyProvider(current.visit.patientId)` for the *base* list
  and `state.encounterDraft.patientSafety` for the *staged overlay*; display
  `state.effectivePatientSafety(base)` (merge). Add/edit/remove call
  `stageCreate/Update/ArchiveAllergy/Medication/Condition` → overlay updates → list re-renders.
- Vital signs read `state.effectiveVisit.vitalSigns` (merge of persisted + pending +
  updates − archived). Add/edit/remove call `stageCreate/Update/ArchiveVitalSign`.
- "Add" disabled when `canAddMore == false` (all catalog items used), mirroring web
  `disabled={!canAddMore}`.

**Motion detail (Phase 2):**
- Entry cards enter via `fade-scale` one-shot (`AppMotionPreset.fadeScale`: opacity 0→1, scale
  0.98→1, 160ms `out`); exit via reverse. `VisitEntryList` animates reflow with `AnimatedSize`
  (`AppMotion.base`/`out`). Reduced-motion → instant, no scale.
- Each `PatientSafetyEditor` and the `VitalSignsEditor` block enter via the parent section's
  `slide-up` stagger (40ms).

**Phase 2 acceptance:** Intake shows the medical-background block with three add/edit/remove editors
and a live updated chip/card list. Findings shows examination + vital-sign editor (add via dialog,
edit/remove via card icons) + diagnosis. All entries persist into `encounterDraft` on save.

### Phase 3 — Treatment section (investigations + treatment plan + attachments)

Widgets: **VisitCatalogOptions, InvestigationsEditor, InvestigationFormDialog,
InvestigationEntryCard, TreatmentPlanEditor, TreatmentPlanFormDialog,
TreatmentPlanEntryCard, VisitAttachmentsEditor, TreatmentSection**

| Widget | Flutter widget(s) | File(s) | Reuse | Wrapper | Deps |
|---|---|---|---|---|---|
| Catalog consts | `kFrequencyOptions`, `kDurationOptions` (`AppSelectOption[]` copied verbatim from `mock-data.ts:73,85`) | CREATE `widgets/visit_catalog_options.dart` | `AppSelectOption` | NEW | none |
| Investigations editor | `InvestigationsEditor` | CREATE `widgets/investigations_editor.dart` | bordered block + `VisitEntryList` (vertical) + empty state (`Icons.flask_conical`/`Icons.science_outlined`) + add buttons; `canAddMore` over `searchInvestigations`-independent uniqueness by `investigationId`; bind `effectiveVisit.investigations` + `stage{Create,Update,Archive}Investigation` | NEW | `VisitEntryList`, `InvestigationFormDialog`, `InvestigationEntryCard` |
| Investigation dialog | `InvestigationFormDialog` | CREATE `widgets/investigation_form_dialog.dart` | `AppDialog` (md): investigation `AppCombobox` over `searchInvestigations` (async, disabled already-added) + note `AppTextarea` (3 rows, autoGrow); validation (investigation required); `stageCreate/UpdateInvestigation` | NEW | `AppDialog`, `AppCombobox` (`searchInvestigations`), `AppTextarea` |
| Investigation card | `InvestigationEntryCard` | CREATE `widgets/investigation_entry_card.dart` | `VisitEntryCard` + `VisitEntryCardFieldsRow`: Investigation (`name`) / Type (`meta`/`—`) / Note (`note`/`—`, flex 1.5) | NEW | `VisitEntryCard` |
| Treatment plan editor | `TreatmentPlanEditor` | CREATE `widgets/treatment_plan_editor.dart` | bordered block + `VisitEntryList` + empty state (`Icons.medical_services_outlined`/pill) + add button; bind `effectiveVisit.treatmentPlans` + `stage{Create,Update,Archive}TreatmentPlan` | NEW | `VisitEntryList`, `TreatmentPlanFormDialog`, `TreatmentPlanEntryCard` |
| Treatment plan dialog | `TreatmentPlanFormDialog` | CREATE `widgets/treatment_plan_form_dialog.dart` | `AppDialog` (md): medication `AppCombobox` over `searchMedications` (auto-fill `medicationName` from `label`) + dosage `AppTextInput` + frequency `AppSelect` (`kFrequencyOptions`) + duration `AppSelect` (`kDurationOptions`, full-width row); validation (all required); `stageCreate/UpdateTreatmentPlan` | NEW | `AppDialog`, `AppCombobox` (`searchMedications`), `AppTextInput`, `AppSelect` |
| Treatment plan card | `TreatmentPlanEntryCard` | CREATE `widgets/treatment_plan_entry_card.dart` | `VisitEntryCard`: Medication (`medicationName` · `medicationMeta`) / Dosage / Frequency (`kFrequencyOptions` label lookup) / Duration (`kDurationOptions` label lookup) | NEW | `VisitEntryCard`, `visit_catalog_options.dart` |
| Attachments editor | `VisitAttachmentsEditor` | CREATE `widgets/visit_attachments_editor.dart` | `AppFileDropzone` (id "documents") bound to `pendingAttachments` display list + `effectiveVisit.attachments`; `stageAttachment(pick,label,uploadedBy,uploadedByName)` on drop; `stageDeleteAttachment(id)` on remove; helper "PDF, JPG, or PNG — max 10 MB"; `canUploadAttachments` from `visitDetailViewProvider` | NEW | `AppFileDropzone`, `visitAttachmentServiceProvider` |
| Treatment section | `TreatmentSection` | CREATE `widgets/treatment_section.dart` | header + treatment-notes `VisitTextSection` + investigations `AppFormField` + treatment-plan `AppFormField` + attachments `AppFormField`; `slide-up` stagger (40ms) | NEW | `VisitTextSection`, `InvestigationsEditor`, `TreatmentPlanEditor`, `VisitAttachmentsEditor`, `VisitStagger` |

**State bindings (Phase 3):**
- Investigations: `effectiveVisit.investigations` (merge persisted + pending; archived removed);
  add/edit → `stageCreate/UpdateInvestigation`; remove → `stageArchiveInvestigation`.
  Prior-visit pending investigations (`effectiveVisit.pendingInvestigations`) render with their
  `orderedVisitDate` as a secondary meta (web has no analog — Flutter-only enrichment, optional).
- Treatment plan: `effectiveVisit.treatmentPlans`; `stageCreate/Update/ArchiveTreatmentPlan`.
  Frequency/duration stored as `value` strings; card label lookup via `kFrequencyOptions`/
  `kDurationOptions` maps (fallback to raw value, matches web `getFrequencyLabel`).
- Attachments: `effectiveVisit.attachments` + `pendingAttachments` (display via
  `PendingVisitAttachment.toDisplayItem()`); `stageAttachment` requires `uploadedBy` (staff id
  from `authSessionProvider`) + `uploadedByName`; `stageDeleteAttachment` for both pending and
  persisted. `canUploadAttachments` gates the dropzone (permission + branch access).

**Motion detail (Phase 3):**
- Same `fade-scale` entry-card + `VisitEntryList` reflow as Phase 2.
- Section blocks stagger via `VisitStagger` (40ms `slide-up`).

**Phase 3 acceptance:** Treatment phase shows treatment notes + investigations editor (async combobox
search + note) + treatment-plan editor (medication combobox + dosage/frequency/duration selects) +
attachments dropzone. "Continue" advances to `EncounterPhase.review` (Summary — placeholder until
Phase 4). "Save draft" persists clinical note + flushes `encounterDraft` via `saveAll()`.

### Phase 4 — Summary review, completed success screen, chronicle detail, expert mode, polish

Widgets: **VisitSummary, VisitSummaryLedger, VisitCompleted, VisitRecordedPhaseCard,
ExpertVisitAccordion, VisitDetailPage**

| Widget | Flutter widget(s) | File(s) | Reuse | Wrapper | Deps |
|---|---|---|---|---|---|
| Summary ledger | `VisitSummaryLedger`, `LedgerEntry`, `LedgerInlineList`, `LedgerText` | CREATE `widgets/visit_summary_ledger.dart` | `AppDescriptionList` (or custom `Table`/grid for the responsive 3-col desktop / 2-col mobile layout), `AppTypography`, `context.appColors` (textTertiary for `—`), `AppMotion` per-section `slide-up` with delays (0.05/0.10/0.15s via `VisitStagger` cumulative offset) | NEW | `AppMotion`, `VisitStagger` |
| Summary | `VisitSummary` | CREATE `widgets/visit_summary.dart` | `AppCard` (raised, sm) + warning band (`statusWarning*` — "Pending review" overline + helper) + 3 `LedgerSection`s (Intake/Findings/Treatment) + footer (Edit visit secondary ArrowLeft / Finalize visit primary CheckCircle); `fade-scale` outer + `staggerChildren(60)`; "Finalize" gated by `evaluateVisitSubmitReadiness` (`hasMinimumDocumentation`) — disabled if false with helper tooltip | NEW | `VisitSummaryLedger`, `AppButton`, `AppCard`, `AppMotion` |
| Completed success | `VisitCompleted` + `VisitRecordedPhaseCard` | CREATE `widgets/visit_completed.dart`, `widgets/visit_recorded_phase_card.dart` | `AppCard` (raised, lg, centered) + radial-gradient `DecoratedBox` (`statusSuccessSurface`) + animated seal (`AnimationController` deliberate 480ms/out: `scale 0.6→1` delay 50ms, inner check `scale 0→1 rotate -20→0` delay 200ms) + title + locale-aware `DateFormat` timestamp + 3 `VisitRecordedPhaseCard` (`staggerChildren(50)` `slide-up` from delay 150ms) + actions (View patient record secondary UserRound, Print secondary Printer, Start new visit primary ArrowRight); centered `max-w-xl` via `ConstrainedBox(maxWidth: 576)` | NEW | `AppCard`, `AppButton`, `AppMotion`, `DateFormat` |
| Expert accordion | `ExpertVisitAccordion` | CREATE `widgets/expert_visit_accordion.dart` | stacked `IntakeSection` + `FindingsSection` + `TreatmentSection` in one `SingleChildScrollView`, each prefixed by an `AppSectionHeader` with the phase `icon`/`label`; `slide-up` stagger per section (40ms); listens to `expertModeScrollTargetProvider(visitId)` → `ScrollController.animateTo` to the target section's `GlobalKey` then `clear()` | NEW | section widgets, `expertModeScrollTargetProvider` |
| Chronicle detail | `VisitDetailPage` | CREATE `pages/visit_detail_page.dart` | `AppPageHeader` ("Encounter chronicle" / patient name) + meta line (MRN-less: `doctorName` · locale `DateFormat` visitDate) + actions (Card view ghost LayoutGrid → `goVisitDocument`, Edit visit secondary RotateCcw → `goVisitDocument` w/ edit, Print secondary Printer, New visit primary ArrowLeft → reset&navigate) + `AppCard` (raised, lg) wrapping `AppTimeline` with 3 events (Intake/Findings/Treatment) built from `visitDetailViewProvider(visitId).visit`; `fade-scale` outer; wires `visitDetailViewProvider` (loading skeleton, error `AppErrorState`, permission-denied `AppEmptyState`) | NEW | `AppTimeline`, `AppPageHeader`, `AppCard`, `visitDetailViewProvider` |

**Route wiring (Phase 4):**
- `app/router.dart:121` — replace `shellPlaceholderPage` for `'${AppRoutes.visits}/:visitId/${AppRoutes.visitDetailSegment}'` with `(context, state) => VisitDetailPage(visitId: state.pathParameters['visitId']!)`.
- `VisitDocumentPage` view swap now resolves `summary` → `VisitSummary` and `completed` → `VisitCompleted` (Phase 1's `VisitViewFade` keys light up).
- Guided/expert: `VisitDocumentPage` reads `workspaceModeProvider`; `guided` → `AppStepPanel` (Phases 1-3), `expert` → `ExpertVisitAccordion`. Toggle via `VisitPatientBanner` footer `AppSegmentedControl` → `workspaceModeProvider.toggleMode`.

**State bindings (Phase 4):**
- Summary: reads `state.effectiveVisit` + `state` (complaint/history/examination/diagnosis/plan) +
  `patientSafetyProvider` (allergies/medications/conditions) for the ledger rows. "Edit visit"
  → `encounterActivePhaseProvider(visitId).setPhase(EncounterPhase.plan)` (back to last form phase,
  matching web `goBack` from summary). "Finalize visit" → `notifier.completeVisit()`; on success,
  `state.visit.status == completed` flips the view to `VisitCompleted`. On `RpcFailure`, surface
  `visitMessageForRpc(error)` + `state.errorMessage` in a dismissible error banner and keep the
  summary view (do not advance).
- Completed: reads `state.visit` (post-complete) + `finalizedAt` (from `visit.updatedAt` or
  `documentation.updatedAt`). "Start new visit" → `notifier.reloadVisit()` + reset phase to
  `subjective` + navigate (or stay, per web `resetVisit` + `onNavigate(encounterRoute)`).
  "View patient record" → `context.nav.pushPatientDetail(patientId)` (if permitted).
  "Print" → platform print (deferred stub, §6).
- Chronicle: `visitDetailViewProvider(visitId)` → `VisitDetailViewState`; build timeline events
  from `visit.documentation` + `visit.vitalSigns` + `visit.investigations` + `visit.treatmentPlans`
  + `visit.attachments`. Same empty fallbacks (`—`/`None recorded`) as the summary ledger.

**Motion detail (Phase 4):**
- Summary: outer `fade-scale` (`AppMotionPreset.fadeScale` quick/out) + per-`LedgerSection`
  `slide-up` with cumulative delays 0.05/0.10/0.15s (via `VisitStagger` with explicit delay-ms).
- Completed: outer `fade-scale` + `staggerChildren(70)`; seal `AnimationController` `deliberate`
  (480ms)/`out` with `scale 0.6→1` at 50ms delay, inner check `scale 0→1 rotate −20deg→0` at 200ms;
  `VisitRecordedPhaseCard`s `slide-up` `staggerChildren(50)` from 150ms base + per-index 60ms.
  All reduced-motion aware (instant).
- Chronicle: outer `fade-scale` + `AppTimeline` (no per-item motion beyond timeline's own).
- Expert accordion: per-section `slide-up` stagger (40ms) on first build.

**Phase 4 acceptance:** Continue from Treatment lands on Summary (ledger with all sections + warning
band + Finalize). Finalize → Completed seal success with 3 recorded-phase cards + actions. Navigating
to `/visits/<id>/detail` shows the chronicle timeline. Toggling guided→expert stacks all sections
with scroll-to from summary "Edit".

---

## 4. Page composition spec (mirrors web reference)

> **Binding source of truth:** the web `web-reference/src/features/visits/VisitPage.tsx` and its
> colocated sub-files. Composer 2.5 must reproduce the web demo-… well, **page-for-page**:
> the header ternary, the `AnimatePresence` view branches, the `StepPanel` directional phase swap,
> the per-section `staggerChildren(40)` `slide-up`, the entry-card `fade-scale` + `popLayout`
> reflow, the summary `staggerChildren(60)` ledger with per-section delays, and the completed
> seal `staggerChildren(70)` + deliberate-scale choreography. The Flutter `App*` primitives
> (`AppStepPanel`, `AppCard`, `AppDialog`, `AppTimeline`, `AppMotion`) are 1:1 in shape with the
> web ones, so only the widget names + prop syntax change.
>
> Dev-page instantiation does **not** apply (this is a feature page, not a Dev showcase). Instead,
> the **route instantiation** is:
> - `/visits/:visitId/document` → `VisitDocumentPage(visitId: …)` (the web `VisitPage` form/summary/
>   completed branches).
> - `/visits/:visitId/detail` → `VisitDetailPage(visitId: …)` (the web `VisitPage summaryView='chronicle'`
>   branch).
> - The web `summaryView='card'` branch is the `EncounterPhase.review` view inside `VisitDocumentPage`
>   (the `VisitSummary` widget).

### VisitDocumentPage composition (mirrors `VisitPage.tsx:67-194`)

```
AppPageHeader(title: pageTitle ternary, description: pageDescription ternary,
  actions: (!isSummary && !isCompleted) ? AppButton.secondary.sm(Save icon, "Save draft", save) : null)

VisitViewFade(  // AnimatedSwitcher opacity 220ms/out, keyed by view
  key: completed ? 'completed' : review ? 'summary' : 'form',
  child:
    isCompleted ? VisitCompleted(patient, finalizedAt, onStartNewVisit, onViewPatient)
    : isReview   ? VisitSummary(effectiveVisit, onEdit: goBackToPlan, onFinalize: completeVisit)
    : Column(
        VisitPatientBanner(visit, activePhase, badges, onPhaseSelect: setPhase, mode, onToggleMode),
        AppCard.raised.lg(  // raised card with grid-bg DecoratedBox overlay (web VisitPage:146-158)
          AppStepPanel(stepKey: activePhase.name, child:
            switch (activePhase) {
              subjective => IntakeSection(state, onUpdate),
              objective  => FindingsSection(state, onUpdate),
              plan       => TreatmentSection(state, onUpdate),
            }
          ),
          footer: Row(  // border-top, pt-6, mt-10
            AppButton.secondary(ArrowLeft, "Back", goToPrevious, disabled: !canGoBack),
            AppButton.primary("Continue" | "Review visit", ArrowRight, goToNext),
          ),
        ),
      ),
)
```

- `pageTitle`/`pageDescription` ternary reproduces `VisitPage.tsx:51-65` exactly:
  - completed → "Visit completed" / `"Encounter for <patient> has been finalized"`
  - review → "Review visit" / `"Check documentation for <patient> before finalizing"`
  - form → "Document visit" / `"Record clinical information for <patient>"`
- `.mt-6 .space-y-6` → `Column(spacing: AppSpacing.space6)` with top `SizedBox(height: AppSpacing.space6)`.
- Card grid-bg overlay: `DecoratedBox` with two-axis `linear-gradient` `borderSubtle` 20px grid +
  `radial-gradient` mask (`VisitPage.tsx:149-157`) — render via a `CustomPaint` or layered
  `LinearGradient`/`RadialGradient` `DecoratedBox` behind the `AppCard` content, `opacity 0.25`.
  Reduced-motion does not affect (static).
- `direction` for `AppStepPanel`: track `previousPhase` in `setState`; compare
  `EncounterPhase.stepperIndex` → forward (+1) or back (−1).

### IntakeSection composition (mirrors `IntakeSection.tsx`)

```
VisitStagger(stepMs: 40, children: [
  VisitStaggeredItem( Header: h2 "Patient intake" + subtitle ),
  VisitStaggeredItem( AppFormField("complaint", "Chief complaint", required, hint) →
    AppTextarea(rows:3, autoGrow, placeholder "e.g. Persistent cough…") ),
  VisitStaggeredItem( AppFormField("history", "History of present illness", hint) →
    AppTextarea(rows:4, autoGrow, placeholder "Describe the timeline…") ),
  VisitStaggeredItem( MedicalBackgroundEditor(allergies, medications, conditions, …) ),
])
```

`onChange` for each text area → `notifier.updateComplaint(value)` / `updateHistory(value)` /
`updateExamination(value)` / `updateDiagnosis(value)` / `updatePlan(value)`.

### FindingsSection composition (mirrors `FindingsSection.tsx`)

```
VisitStagger(stepMs: 40, children: [
  VisitStaggeredItem( Header: "Findings & diagnosis" + subtitle ),
  VisitStaggeredItem( AppFormField("examination", "Physical examination", hint) → AppTextarea(rows:4) ),
  VisitStaggeredItem( AppFormField("vital-signs", "Vital signs", helperText) → VitalSignsEditor ),
  VisitStaggeredItem( AppFormField("diagnosis", "Diagnosis", required, hint) → AppTextarea(rows:3) ),
])
```

### TreatmentSection composition (mirrors `TreatmentSection.tsx`)

```
VisitStagger(stepMs: 40, children: [
  VisitStaggeredItem( Header: "Treatment" + subtitle ),
  VisitStaggeredItem( AppFormField("treatment-notes", "Treatment notes", hint) → AppTextarea(rows:3) ),
  VisitStaggeredItem( AppFormField("investigations", "Investigations needed", helperText) → InvestigationsEditor ),
  VisitStaggeredItem( AppFormField("treatment-plan", "Treatment plan", helperText) → TreatmentPlanEditor ),
  VisitStaggeredItem( AppFormField("documents", "Attachments", helperText) → VisitAttachmentsEditor ),
])
```

### VisitSummary composition (mirrors `VisitSummary.tsx:263-302`)

```
VisitStagger(stepMs: 60, children: [
  VisitStaggeredItem( AppCard.raised.sm(
    warning band (statusWarningSurface/Fg/Border): overline "Pending review" + helper,
    VisitSummaryLedger("Intake", intakeRows, delay 0.05),
    VisitSummaryLedger("Findings & diagnosis", findingsRows, delay 0.10),
    VisitSummaryLedger("Treatment", treatmentRows, delay 0.15, isLast),
    footer Row: AppButton.secondary(ArrowLeft, "Edit visit", onEdit) | AppButton.primary(CheckCircle, "Finalize visit", onFinalize),
  ) ),
])
```

Ledger rows reproduce `VisitSummary.tsx:157-261`:
- Intake: Complaint / History (`LedgerText`) / Chronic conditions / Allergies / Current medications (`LedgerInlineList`, "None recorded" empty).
- Findings: Examination (`LedgerText`) / Vital signs (list `label · value unit`, "None recorded") / Diagnosis.
- Treatment: Treatment notes / Investigations (list "Investigation — note", "None ordered") / Treatment plan (list "Medication — dosage · freq · dur", "None prescribed") / Attachments (list FileText icon + name, "No attachments").

### VisitCompleted composition (mirrors `VisitCompleted.tsx`)

```
Centered ConstrainedBox(maxWidth: 576):
  VisitStagger(stepMs: 70, children: [
    VisitStaggeredItem( AppCard.raised.lg(centered, radial-gradient bg):
      Column(centered, children: [
        AnimatedSeal(scale 0.6→1 50ms delay deliberate/out; inner check scale 0→1 rotate -20→0 200ms delay),
        Text h1 "Visit completed",
        Text body "Documentation for <name> is on record…",
        Time(locale DateFormat timestamp),
        VisitStagger(stepMs: 50, base: 150ms, children: [
          VisitRecordedPhaseCard(Intake, ClipboardList),
          VisitRecordedPhaseCard(Findings, Activity),
          VisitRecordedPhaseCard(Treatment, Pill),
        ]),
        Row( AppButton.secondary(UserRound, "View patient record") | secondary(Printer, "Print summary") | primary(ArrowRight, "Start new visit") ),
      ])
    )
  ])
```

### VisitDetailPage (chronicle) composition (mirrors `VisitSummaryChronicle.tsx`)

```
Column(spacing: AppSpacing.space6):
  Row(spaceBetween: [
    Column( overline "Encounter chronicle", h2 patientName, body "doctorName · locale timestamp" ),
    Row( AppButton.ghost(LayoutGrid, "Card view", onBack→goVisitDocument) | secondary(RotateCcw, "Edit visit", onEdit) | secondary(Printer, "Print") | primary(ArrowLeft, "New visit", onNewVisit) ),
  ]),
  AppCard.raised.lg(maxWidth ~768):
    ChronicleSection("Continuous record"): AppTimeline(events: [intake, findings, treatment]),
```

Timeline events reproduce `VisitSummaryChronicle.tsx:116-203` (timestamp, title, group
"Encounter record", description with `ProseField` + `InlineList` blocks). `AppTimeline` already
accepts `group`/`timestamp`/`description` (`web-reference/src/components/timeline/Timeline.tsx`).

### ExpertVisitAccordion composition (Flutter-only)

```
SingleChildScrollView(controller, children: [
  VisitStagger(stepMs: 40, children: [
    VisitStaggeredItem( AppSectionHeader(subjective.icon, subjective.label) + IntakeSection ),
    VisitStaggeredItem( AppSectionHeader(objective.icon, objective.label) + FindingsSection ),
    VisitStaggeredItem( AppSectionHeader(plan.icon, plan.label) + TreatmentSection ),
  ]),
])
listener(expertModeScrollTargetProvider) → ScrollController.animateTo(sectionKey) → clear()
```

---

## 5. Wiring steps (after each phase — or per phase as noted)

> This is a **feature-page** port. There is **no** `component_registry.dart` /
> `component_section_builders.dart` showcase registration to flip — those belong to the Dev
> components page only. Wiring is **route + provider** wiring.

### After Phase 1
1. `app/router.dart:117-119` — replace the `shellPlaceholderPage` builder for
   `'${AppRoutes.visits}/:visitId/${AppRoutes.visitDocumentSegment}'` with
   `(context, state) => VisitDocumentPage(visitId: state.pathParameters['visitId']!)`.
   Add the `import` for `VisitDocumentPage` at the top of `router.dart` under a `// Visits (V1-5)` comment.
2. Verify `app/navigation/app_navigator.dart:65-66` (`goVisitDocument`/`pushVisitDocument`) already
   target this route — no change needed.
3. Run `flutter analyze` on changed files (`router.dart`, new `pages/visit_document_page.dart`,
   new `widgets/*`); fix lints. Do **not** commit unless asked.

### After Phase 2
1. No route changes. Confirm `IntakeSection` and `FindingsSection` plug into the
   `VisitDocumentPage` phase switch (built in Phase 1) without further page edits beyond swapping
   the placeholder widgets.
2. Run `flutter analyze`; fix lints.

### After Phase 3
1. No route changes. Confirm `TreatmentSection` plugs into the phase switch and the
   "Continue" → `EncounterPhase.review` transition surfaces the Phase-1 placeholder for the
   summary (to be replaced in Phase 4).
2. Run `flutter analyze`; fix lints.

### After Phase 4
1. `app/router.dart:121` — replace the `shellPlaceholderPage` builder for
   `'${AppRoutes.visits}/:visitId/${AppRoutes.visitDetailSegment}'` with
   `(context, state) => VisitDetailPage(visitId: state.pathParameters['visitId']!)`.
   Add the `import` under the same `// Visits (V1-5)` comment.
2. Verify `app/navigation/app_navigator.dart:67-68` (`goVisitDetail`/`pushVisitDetail`) target
   this route — no change needed.
3. Confirm `VisitDocumentPage` view swap resolves `summary` → `VisitSummary` and `completed` →
   `VisitCompleted`, and the guided/expert `AppSegmentedControl` toggles `workspaceModeProvider`.
4. Run `flutter analyze` on all changed visits-presentation files + `router.dart`; fix lints.
5. Do **not** commit unless asked.

---

## 6. Out-of-scope / defer

- **Visits list at `/encounters`** (`app/routes.dart:86` placeholder) — no visits list page in this
  plan; the top encounters route stays `shellPlaceholderPage`. A future plan will port the web
  encounters list (out of `web-reference` scope here — `VisitPage` is keyed by patient, not a list).
- **Web `summaryView='chronicle'` strict parity** — the web chronicle is a *patient*-keyed
  continuous record across all visits; the Flutter chronicle (`VisitDetailPage`) is a single-visit
  read-only timeline. Cross-visit continuous-chronicle aggregation is deferred (no provider).
- **`window.print()`** on "Print summary"/"Print" actions — Flutter uses platform printing
  (`printing`/`share_plus`) not yet wired. Render the buttons; gate `onPressed` behind a deferred
  stub that no-ops or calls a future `visitPdfProvider`. Do not fabricate a PDF repo.
- **Full FLIP `layout` animation** for entry-card reflow (web `motion.article layout`) — approximated
  with `AnimatedSize` + `fade-scale` enter/exit. A true shared-element FLIP is out of scope.
- **Rich-text (Quill) editor drafts** — `VisitDocumentationState.richTextDrafts` + `rich_text_draft_utils`
  exist but wiring a Quill editor is out of scope; Phase 1-3 bind plain `AppTextarea` to the plain-text
  fields (`complaint`/`history`/etc.). The `registerClinicalNoteFlush` hook is honored by
  `prepareEncounterReview` on the summary transition, so plain-text binding is sufficient.
- **EN/AR production localization** — this plan mirrors web EN copy verbatim and is RTL-aware via
  `Directionality.of(context)`; wiring `app_ar.arb` + `localeProvider` (modeled on
  `web-reference/src/providers/DirectionProvider.tsx`) is tracked separately (see
  `patient-details-implementation-plan.md` Phase 4) and is **not** done here.
- **`mrn` display** — `VisitDetail` has no MRN; the chronicle header omits the MRN line (web shows
  `MRN {patient.mrn}`). Do not fabricate.
- **Cross-widget `popLayout` perf** — large entry lists (many vital signs/investigations) use
  `AnimatedSwitcher` per item; if perf becomes an issue, a future plan can switch to
  `SliverAnimatedList`. Not now.
- **No new `core/ui/components/app_*.dart`** — all new widgets are feature-local under
  `features/visits/presentation/`. The barrel `widgets.dart` is **not** edited.

---

## 7. Source reference — web widget inventory

The web `web-reference/src/features/visits/` folder exports the following widgets/states. The
Flutter port reproduces each (no showcase `index.ts`, since this is a feature folder, not a
showcase group):

| Export name | Title / role | Source file | Underlying UI component(s) |
|---|---|---|---|
| `VisitPage` | Encounters page orchestrator | `features/visits/VisitPage.tsx` | `PageHeader`, `Card`, `Button`, `AnimatePresence` + `motion.div`, `StepPanel` |
| `useVisitForm` | Encounter state machine | `features/visits/useVisitForm.ts` | (hook) — ↔ `encounterActivePhaseProvider` + `visitDocumentationProvider` |
| `VISIT_PHASES` / `VisitPhase` | Phase enum + labels | `useVisitForm.ts:10` + `types.ts:4` | ↔ `EncounterPhase` |
| `VisitPatientBanner` | Patient context + step rail host | `features/visits/VisitPatientBanner.tsx` | `Card`, `Avatar`, `VisitStepRail` |
| `VisitStepRail` | 3-step progress | `features/visits/VisitStepRail.tsx` | `motion`, lucide `Check`/`ClipboardList`/`Microscope`/`Stethoscope` |
| `IntakeSection` | Intake phase | `features/visits/sections/IntakeSection.tsx` | `FormField`, `Textarea`, `MedicalBackgroundEditor`, `motion` stagger |
| `FindingsSection` | Findings phase | `features/visits/sections/FindingsSection.tsx` | `FormField`, `Textarea`, `VitalSignsEditor`, `motion` stagger |
| `TreatmentSection` | Treatment phase | `features/visits/sections/TreatmentSection.tsx` | `FormField`, `Textarea`, `FileDropzone`, `InvestigationsEditor`, `TreatmentPlanEditor`, `motion` stagger |
| `MedicalBackgroundEditor` | Chronic/allergy/med multi-selects | `features/visits/components/MedicalBackgroundEditor.tsx` | `FormField`, `MultiSelect` ×3 |
| `VitalSignsEditor` | Vital signs list + dialog | `features/visits/components/VitalSignsEditor.tsx` | `Button`, `AnimatePresence`/`motion`, `VitalSignEntryCard`, `VitalSignFormDialog` |
| `VitalSignFormDialog` | Vital sign add/edit | `features/visits/components/VitalSignFormDialog.tsx` | `Dialog`, `FormField`, `Select`, `TextInput` |
| `VitalSignEntryCard` | Vital sign chip card | `features/visits/components/VitalSignEntryCard.tsx` | `motion.article layout`, `IconButton` |
| `InvestigationsEditor` | Investigations list + dialog | `features/visits/components/InvestigationsEditor.tsx` | `Button`, `AnimatePresence`/`motion`, `InvestigationEntryCard`, `InvestigationFormDialog` |
| `InvestigationFormDialog` | Investigation add/edit | `features/visits/components/InvestigationFormDialog.tsx` | `Dialog`, `FormField`, `Combobox`, `Textarea` |
| `InvestigationEntryCard` | Investigation row card | `features/visits/components/InvestigationEntryCard.tsx` | `motion.article layout`, `IconButton`, `EntryCardField` |
| `TreatmentPlanEditor` | Prescriptions list + dialog | `features/visits/components/TreatmentPlanEditor.tsx` | `Button`, `AnimatePresence`/`motion`, `TreatmentPlanEntryCard`, `TreatmentPlanFormDialog` |
| `TreatmentPlanFormDialog` | Prescription add/edit | `features/visits/components/TreatmentPlanFormDialog.tsx` | `Dialog`, `FormField`, `Combobox`, `Select` ×2, `TextInput` |
| `TreatmentPlanEntryCard` | Prescription row card | `features/visits/components/TreatmentPlanEntryCard.tsx` | `motion.article layout`, `IconButton`, `EntryCardField` |
| `EntryCardField` / `EntryCardFieldsRow` | Shared card field layout | `features/visits/components/EntryCardField.tsx` | `cn` |
| `VisitSummary` | Review ledger | `features/visits/VisitSummary.tsx` | `Card`, `Button`, `motion` stagger, `LedgerSection`/`LedgerEntry`/`LedgerInlineList`/`LedgerText` |
| `VisitSummaryChronicle` | Chronicle timeline view | `features/visits/VisitSummaryChronicle.tsx` | `Card`, `Button`, `Timeline`, `motion`, `ProseField`/`InlineList` |
| `VisitCompleted` | Success screen | `features/visits/VisitCompleted.tsx` | `Card`, `Button`, `motion` (seal + stagger), `RecordedPhase`, lucide icons |
| `Timeline` | Timeline primitive | `components/timeline/Timeline.tsx` | ↔ `AppTimeline` |
| `StepPanel` | Animated step panel | `pages/app/settings/components/AnimatedPanels.tsx` | `AnimatePresence`/`motion` `slide-inline` ↔ `AppStepPanel` |
| `mock-data.ts` | Catalogs + label lookups | `features/visits/mock-data.ts` | ↔ `kFrequencyOptions`/`kDurationOptions` (verbatim), `searchMedications`/`searchInvestigations`/`listPredefinedVitalSigns` (org), label-lookup fns inlined in cards |
| `types.ts` | `VisitFormData`/`VisitPhase`/entries | `features/visits/types.ts` | ↔ Flutter domain models |

### Shared web building blocks (port equivalents)

- `motion/react` (`AnimatePresence`, `motion.div`, `motion.article layout`, `motion.span`) →
  `AnimatedSwitcher` + `AppStepPanel` + `VisitEntryList` + `AnimatedContainer`/`Tween`, all driven by
  `AppMotion` (`core/ui/motion/app_motion.dart`) durations/curves/presets. Reduced-motion via
  `AppMotion.prefersReducedMotion`.
- `lib/motion.ts` (`motionPresets`, `resolveTransition`, `staggerChildren`) →
  `AppMotion` (`AppMotionPreset.fade`/`fadeScale`/`slideUp`/`slideInline`/`rowEnter`,
  `AppMotion.transitionFor`, `AppMotion.staggerStep`) + feature-local `VisitStagger`.
- `cn` → `AppSpacing`/`AppRadius`/`context.appColors` token composition (no `cn` helper needed).
- `useDirection` → `Directionality.of(context)` (RTL) — already respected by `App*` widgets and
  `AppMotion.hidden(slideInline, direction:)`.
- `Popover` (Radix) → `AppPopover` (already shipped under `core/ui/components/app_popover.dart`),
  used internally by `AppSelect`/`AppCombobox`.
- `Spinner` (lucide Loader2) → `CircularProgressIndicator` inside `AppCombobox` async search.
- `Chip`/`Kbd` → `AppChip`/`AppKbd` (shipped) — used by `AppMultiSelect` (not needed here; medical
  background uses feature-local entry cards instead, see §0.3).
- lucide-react icons → Material `Icons.*` round-outlined equivalents
  (`save_outlined`, `arrow_back_rounded`, `arrow_forward_rounded`, `check_rounded`,
  `check_circle_outline_rounded`, `edit_outlined`/pencil, `delete_outline_rounded`/trash,
  `monitor_heart_outlined` (Activity), `science_outlined` (FlaskConical), `medical_services_outlined`
  (Pill/Stethoscope), `description_outlined` (FileText), `layout_grid_outlined` (LayoutGrid),
  `print_outlined` (Printer), `restore_rounded` (RotateCcw), `person_outline_rounded` (UserRound)).
- `formatDate`/`toLocaleString('en-GB', …)` → locale-aware `DateFormat` (see §0 watchlist #2).