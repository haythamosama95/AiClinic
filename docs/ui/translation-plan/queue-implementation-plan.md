# Implementation Plan — Queue feature (web-reference `features/queue` → Flutter `frontend/lib/features/queue`)

Spec target: port the **Queue page** (`web-reference/src/features/queue/QueuePage.tsx` + its `components/`, `types.ts`, `utils.ts`) into a **new** Flutter feature directory `frontend/lib/features/queue`. The non-UI queue layers that already live under `frontend/lib/features/appointments` (realtime, display, shift/start-doctor domain, queue providers, start-doctor dialog) are **extracted out of appointments** into the new `queue` feature first; then the UI is built on top. Split into **5 phases**: 2 extraction phases + 3 UI phases.

> Phase-count note: user requested 5 phases for this work. No clamping was needed.

---

## 0. Ambiguities & Design Decisions (resolve before coding)

> ⚠️ **Set-specific runtime regressions to avoid** (the memory "Checklist for new input components" applies to the toolbar's search field and the status-filter popover):
> - The QueueToolbar search field reuses the shipped `AppSearchInput` — do not introduce a second `FocusNode`/`Focus` ancestor around it (item: duplicate `FocusNode` on `Focus` + `TextField`).
> - The status-filter `AppPopover` hosts a multi-select listbox; do **not** read `MediaQuery`/inherited sizes inside `initState` of the popover body — measure in `build`/`didChangeDependencies`.
> - The QueueStats carousel KPI cards use `intl` only via `AppTypography` + tick timer; no locale-specific `DateFormat` is required in the cells, but the `AppointmentQueueDisplay.formatDurationLabel` path must not be called before the material app is mounted (Material ancestor missing). Wrap any standalone demo cell in `Material`.
> - `FlowPulse` uses an infinitely repeating animation — guard with `MediaQuery.disableAnimations` / `TickerMode` and dispose the `AnimationController`; do not construct it in `initState` of an overlay.
> - `ConfirmDialog`/`UndoToast` use `showDialog`/`OverlayEntry` (or `AppToastHost`); ensure they have a `Material` ancestor (the shell page hosts one — fine) and do not holdBuildContexts across async gaps (capture `appointmentId` before `await`).

1. **forui vs native Material.** As with the shipped Actions group and the Inputs & forms plan, `forui` is imported nowhere. **Decision: native Material only.** `docs/ui/forui-wrappers.md` is superseded. Queue UI widgets sit behind the existing App abstraction layer (reuse `AppDataTable`/`AppTabs`/`AppDialog`/`AppToast`/`AppPopover`/`AppSearchInput`/`AppBadge`/`AppSegmentedControl`/`AppCard`/`AppPageHeader`/`AppToolbar`); feature code imports App widgets only, never Material internals directly beyond `core/ui`.

2. **Feature architecture / layering.** `frontend/lib/features/<feature>` uses `domain/`, `data/`, `application/`, `presentation/{pages,widgets,providers,models,navigation}`. The new `features/queue` feature mirrors this. **Dependency direction: `queue` depends on `appointments`** (a queue is a live view over the appointment aggregate) — never the reverse. This is the single hardest decision and drives the extraction boundary below.

3. **What "extract queue layers out of appointments" actually means.** The appointments feature currently co-locates two kinds of queue code:
   - **Queue-only** (named `appointment_queue_*`): realtime subscription + apply, queue display stats/partition/wait-tier, shift-doctor lookup, start-doctor selection, queue provider (warm + checked-in badge), start-doctor dialog. These move to `features/queue`.
   - **Shared appointment-lifecycle** (used by the calendar, booking, and the *detail* page too): `appointment_status_transitions.dart`, `appointment_status_day_rules.dart`, `appointment_status_timeline.dart`, `appointment_status_timeline_widget.dart`, `appointment_status_motion.dart`, plus the status enum, `AppointmentListItem`, `AppointmentRepository`. These **stay in `appointments`**.
   - To avoid an illegal `appointments → queue` import, the shared lifecycle helpers that today import `appointment_queue_shift_doctors` / `appointment_queue_start_doctor` (i.e. `appointment_status_transitions.forwardStatusTargetFor`) are **decoupled**: the in-progress guard becomes an injected callback / parameter (`bool Function(AppointmentListItem, Iterable<AppointmentListItem>) isInProgressBlocked`), and `appointment_status_timeline_widget` receives its doctor presentation as a parameter rather than importing the shift lookup. After that, `features/queue` depends on `appointments`, never the reverse.
   - **Extraction boundary (MOVE to `features/queue`):**
     | Current path | New path |
     |---|---|
     | `appointments/domain/appointment_queue_display.dart` | `queue/domain/queue_display.dart` |
     | `appointments/domain/appointment_queue_shift_doctors.dart` | `queue/domain/queue_shift_doctors.dart` |
     | `appointments/domain/appointment_queue_start_doctor.dart` | `queue/domain/queue_start_doctor.dart` |
     | `appointments/data/appointment_queue_realtime.dart` | `queue/data/queue_realtime.dart` |
     | `appointments/data/appointment_queue_realtime_apply.dart` | `queue/data/queue_realtime_apply.dart` |
     | `appointments/presentation/providers/appointment_queue_provider.dart` | `queue/presentation/providers/queue_provider.dart` |
     | `appointments/presentation/providers/appointment_queue_shift_provider.dart` | `queue/presentation/providers/queue_shift_provider.dart` |
     | `appointments/presentation/widgets/appointment_start_doctor_dialog.dart` | `queue/presentation/widgets/queue_start_doctor_dialog.dart` |
   - Symbol names keep their `AppointmentQueue…` / `Queue…` identifiers; only paths + import prefixes change. The `appointment_queue_*` *provider ids* (`appointmentQueueProvider`, `appointmentQueueCheckedInCountProvider`, `appointmentQueueShellWarmProvider`, `appointmentQueueShiftDoctorLookupProvider`) keep their names so the shell, detail, and surface-invalidation consumers update only their import lines.

4. **Status model mismatch (web vs backend).** The web `types.ts` `AppointmentStatus` has `arrived` and `walk_in`, and a live `Doctor` entity with `status: 'available' | 'with_patient' | 'on_break'`. The real backend `AppointmentStatus` (PostgreSQL enum V1-4) has `scheduled, confirmed, checkedIn, inProgress, completed, cancelled, noShow` (no `arrived`/`walk_in`), and there is **no persisted Doctor.status** — doctor availability is derived from shifts + in-progress assignment via the (extracted) `QueueShiftDoctor`/`inProgressAppointmentForDoctor` logic.
   **Decision: the Flutter QueuePage is *demo-faithful but data-backed*** — it renders the same regions/affordances as the web page but maps onto the real domain, not the mock `INITIAL_APPOINTMENTS`/`INITIAL_DOCTORS`:
   - Web "Waiting" (status `arrived`) ⟶ no backend `arrived`; the queue instead surfaces the **checked-in waiting room** (real `AppointmentQueuePartition.waiting` ≡ `checkedIn`). KPI cards: keep all 10 web cards but remap `waiting` ⟶ checked-in count, drop the `arrivedAt`-over-`scheduledTime` semantics that don't exist; "Queue length" ⟶ `currentQueueLength = waiting + checkedIn` collapses to the checked-in count.
   - Web `AppointmentRowActions` "Start Consultation" with an inline doctor picker ⟶ reuse the **extracted `QueueStartDoctorDialog`** + `AppointmentQueueStartDoctor.shiftOptionsFor` (real busy/available check), not a free `doctors[]` list.
   - Web `DoctorsPanel` `Doctor.status` (`available/with_patient/on_break`) ⟶ derive two states from the shift lookup: `available` (idle, no in-progress) vs `with_patient` (the in-progress appointment assigned to that doctor). `on_break` has no backend equivalent ⟶ omitted (or shown as `unavailable`/dimmed using shift absence).
   - Web `StatusBadge` `arrived` state ⟶ folded into the `confirmed`/`checkedIn` badge tone already produced by `AppointmentQueueDisplay.scheduleBadgeTone`. The Flutter `StatusBadge` widget therefore maps over `AppointmentStatus` only.
   - Web `ExceptionChips` (`copayDue/formsIncomplete/selfCheckInPending/insuranceIssue`) ⟶ **out of scope** (no such field on `AppointmentListItem`); see §6.

5. **Undo vs real revert.** The web `UndoToast` keeps a local 5-second snapshot of the whole list and reverts client-side. The backend supports a *real* one-step revert (`previousStatusTargetFor` + the cancel/undo RPC already wired by `AppointmentDetailStatusActions`). **Decision: the Flutter "Undo" maps to a real revert RPC** surfaced via `AppToast` (`AppToastHost`) with a 5-second auto-dismiss and a hard button: tapping Undo calls the revert RPC + `appointmentQueueProvider` patch. The 5-second window mirrors the web affordance; the action is data-backed, not a local list swap.

6. **ConfirmDialog**: cancel / no-show require confirmation (web `ConfirmDialog` `danger`). Backend gates these via `canCancelAppointment` / `canMarkNoShowAppointment` (+ day rules). **Reuse `appointment_cancel_dialog.dart`** (already exists in appointments) when its copy/shape fits; otherwise a thin `QueueConfirmDialog` built on `AppDialog`. Prefer reusing the existing cancel dialog and passing the queue-specific copy ("Mark no show?" / "Cancel appointment?").

7. **i18n / RTL.** The queue page is an authenticated clinic page (not a dev showcase), so it does **not** use `devPreviewProvider`'s bilingual EN/AR toggle. Copy is production English (matches existing appointment pages). Layout must be `Directionality`-agnostic (use `start`/`end` margins, `AppSpacing`) so a future Arabic locale flips correctly. `formatDuration`/`formatTime` reuse `AppointmentQueueDisplay.formatDurationLabel` and the existing `intl`-based time formatting — no new locale initialization needed.

8. **Controlled/uncontrolled.** Search/filter/sort are page-local controller state held on the page (`StatefulWidget`) and threaded into pure display helpers — mirrors the web `useState` in `QueuePage`. No new global providers for filter state; the queue *data* provider (`appointmentQueueProvider`) stays the single source of truth for items.

9. **Realtime.** The extracted `AppointmentQueueRealtimeClient` (Supabase) already patches the cached list on update/delete and full-refreshes on insert. No new realtime work; the page just `watch`es `appointmentQueueProvider`. The `now` 30-second tick from the web is replaced by the page reading `DateTime.now()` in a `Timer.periodic` (or `app_motion`/`AppSignal`) for wait-tier refresh; existing wait computation is already `now`-parametrised.

10. **No new shared abstraction under `core/ui`** is required for the queue — every web building block has an existing App widget (table, tabs, dialog, toast, popover, search, segmented control, badge, card, toolbar, page header). The only "new" presentation pieces are feature-local widgets under `features/queue/presentation/widgets/`. This respects the hard constraint that feature code never imports Material internals beyond `core/ui`.

---

## 1. Existing App assets to reuse (do not recreate)

| Asset | Path | Used by |
|---|---|---|
| `AppDataTable` | `core/ui/components/app_data_table.dart` | Appointments triage table (`AppointmentsTable`) |
| `AppTabs` | `core/ui/components/app_tabs.dart` | Flow-control panel `Waiting`/`Doctors` tabs |
| `AppSegmentedControl` | `core/ui/components/app_segmented_control.dart` | Checked-in sort toggle (`longest_wait`/`next_in_order`) |
| `AppPopover` | `core/ui/components/app_popover.dart` | `QueueToolbar` status-filter popover |
| `AppSearchInput` | `core/ui/components/app_search_input.dart` | `QueueToolbar` patient search |
| `AppButton` / `AppIconButton` | `core/ui/components/app_button.dart`, `app_icon_button.dart` | KPI carousel scroll chevrons, "Clear filters", confirm/dialog buttons |
| `AppBadge` | `core/ui/components/app_badge.dart` | `StatusBadge` (semantic tone already in `AppBadgeTone`) |
| `AppChip` | `core/ui/components/app_chip.dart` | `ExceptionChips` (if/when domain lands) |
| `AppCard` | `core/ui/components/app_card.dart` | KPI cards, flow-control panel, checked-in/doctor list items |
| `AppToolbar` / `AppPageHeader` / `AppSectionHeader` | `core/ui/components/app_toolbar.dart`, `app_page_header.dart`, `app_section_header.dart` | page header + "Today's appointments" heading + count |
| `AppDialog` (or existing `AppointmentCancelDialog`) | `core/ui/components/app_dialog.dart`, `appointments/presentation/widgets/appointment_cancel_dialog.dart` | `ConfirmDialog` |
| `AppToast` / `AppToastHost` + `AppToastController` | `core/ui/components/app_toast.dart` | `UndoToast` |
| `AppEmptyState` / `AppErrorState` / `AppLoadingOverlay` | `core/ui/components/app_empty_state.dart`, `app_error_state.dart`, `app_loading_overlay.dart` | empty / error / loading states |
| `AppProgress` | `core/ui/components/app_progress.dart` | `FlowPulse` bar fill, KPI trend spinner fallback |
| Theme: `context.appColors` (`AppSemanticColors`), `AppSpacing`, `AppRadius`, `AppTypography`, `AppMotion` | `core/ui/theme/*` | every widget |
| `AppRoutes.appointmentsQueue` + `app_navigator.goAppointmentsQueue` | `app/app_routes.dart`, `app/navigation/app_navigator.dart` | route wiring |
| `AppointmentSection.queue` tab | `appointments/presentation/models/appointment_section.dart` + `AppointmentSectionNav` | breadcrumb/tab consistency |
| Lifecycle RPC + helpers (kept in appointments) | `appointments/application/appointment_rpc_messages.dart`, `appointments/presentation/widgets/appointment_detail_status_actions.dart`, `appointments/domain/appointment_status_transitions.dart` | row actions, confirm, undo revert |

---

## 2. Extraction scaffolding introduced in Phase 1 / 2 (no new `core/ui` files)

| File (`lib/features/queue/`) | Export / symbol | Analog | Purpose |
|---|---|---|---|
| `domain/queue_display.dart` | `AppointmentQueueDisplay`, `AppointmentQueueStats`, `AppointmentQueuePartition`, `AppointmentQueueWaitTier`, `AppBadgeTone` | web `utils.computeQueueStats` + `QueueStats` types | moved from `appointments/domain/appointment_queue_display.dart` |
| `domain/queue_shift_doctors.dart` | `QueueShiftDoctor`, `QueueAppointmentDoctorPresentation`, `AppointmentQueueShiftDoctorLookup` | web `Doctor` + `getDoctorLagMinutes` | moved from `appointments/domain/appointment_queue_shift_doctors.dart` |
| `domain/queue_start_doctor.dart` | `QueueStartDoctorOption`, `AppointmentQueueStartDoctor` | web `AppointmentRowActions` doctor picker | moved from `appointments/domain/appointment_queue_start_doctor.dart` |
| `data/queue_realtime.dart` | `AppointmentQueueRealtimeClient`, `SupabaseAppointmentQueueRealtimeClient`, `appointmentQueueRealtimeClientProvider`, `AppointmentQueueRealtimeConnection` | web `mock` realtime (no analog) | moved from `appointments/data/appointment_queue_realtime.dart` |
| `data/queue_realtime_apply.dart` | `applyAppointmentQueueRealtimeChange`, `AppointmentQueueRealtimeChange` | — | moved from `appointments/data/appointment_queue_realtime_apply.dart` |
| `presentation/providers/queue_provider.dart` | `appointmentQueueProvider`, `AppointmentQueueController`, `AppointmentQueueState`, `appointmentQueueCheckedInCountProvider`, `appointmentQueueShellWarmProvider` | web `QueuePage` state | moved from `appointments/presentation/providers/appointment_queue_provider.dart` |
| `presentation/providers/queue_shift_provider.dart` | `appointmentQueueShiftDoctorLookupProvider`, `resolveQueueShiftDoctors` | web `DoctorsPanel`/`Doctors` | moved from `appointments/presentation/providers/appointment_queue_shift_provider.dart` |
| `presentation/widgets/queue_start_doctor_dialog.dart` | `QueueStartDoctorDialog` (ex-`AppointmentStartDoctorDialog`) | web `AppointmentRowActions` inline doctor picker | moved from `appointments/presentation/widgets/appointment_start_doctor_dialog.dart` |
| `presentation/widgets/queue_status_badge.dart` (NEW) | `QueueStatusBadge` | web `StatusBadge` | maps `AppointmentStatus` → `AppBadge` tone/label |
| `presentation/widgets/queue_kpi_carousel.dart` (NEW) | `QueueKpiCarousel` | web `QueueStats` | horizontal KPI cards + scroll chevrons |
| `presentation/widgets/queue_toolbar.dart` (NEW) | `QueueToolbar` | web `QueueToolbar` | search + status-filter popover |
| `presentation/widgets/queue_alert_banner.dart` (NEW) | `QueueAlertBanner` | web `QueueAlertBanner` | `getQueueHealthIssues`-driven warning strip |
| `presentation/widgets/queue_appointments_table.dart` (NEW) | `QueueAppointmentsTable` | web `AppointmentsTable` | `AppDataTable` wrapper + triage sort |
| `presentation/widgets/queue_row_actions.dart` (NEW) | `QueueRowActions` | web `AppointmentRowActions` | `AppPopover` menu + doctor picker (delegates to extracted start dialog) |
| `presentation/widgets/queue_secretary_utils.dart` (NEW) | pure helpers `queueWaitMinutes`, `queueIsOverdue`, `queueSortForTriage`, `queueFilterByStatus`, `queueCheckedInPatients` | web `utils.ts` | Flutter utils backed by `AppointmentQueueDisplay` + `AppointmentListItem` (no `arrived`) |
| `presentation/widgets/queue_flow_control_panel.dart` (NEW) | `QueueFlowControlPanel` | web `FlowControlPanel` | `AppTabs` + two panels |
| `presentation/widgets/queue_checked_in_panel.dart` (NEW) | `QueueCheckedInPanel` | web `CheckedInPanel` | wait-tier list + segmented sort |
| `presentation/widgets/queue_doctors_panel.dart` (NEW) | `QueueDoctorsPanel` | web `DoctorsPanel` | shift doctors list (available/with_patient) |
| `presentation/widgets/queue_flow_pulse.dart` (NEW) | `QueueFlowPulse` | web `FlowPulse` | animated severity meter |
| `presentation/widgets/queue_confirm_dialog.dart` (NEW) | `QueueConfirmDialog` | web `ConfirmDialog` | `AppDialog` danger confirm (or reuse `AppointmentCancelDialog`) |
| `presentation/widgets/queue_undo_toast.dart` (NEW) | `QueueUndoToast` controller | web `UndoToast` | `AppToast` undo + revert RPC |
| `presentation/pages/queue_page.dart` (NEW) | `QueuePage` | web `QueuePage` | page assembly + page-local search/filter/sort state |

No changes to `widgets.dart` barrel (nothing new under `core/ui`).

---

## 3. Phasing

> Rationale: per the user's instruction, **extract the queue layers first, then add the UI**. **Phase 1** moves the `domain` + `data` layers and decouples the shared lifecycle so `appointments` no longer imports them. **Phase 2** moves the `presentation/providers` + the shared `start-doctor dialog` widget and rewires the shell/route/surface-invalidation consumers; the route still builds a placeholder so nothing user-visible changes. **Phase 3–5** add the UI in three independently-shippable vertical slices: top region (stats + toolbar + alert + empty), main column (triage table + row actions + status badge), and side rail + confirm/undo + page assembly + route builder flip.

### Phase 1 — Extract queue domain + data layers out of `appointments`

| Task | Action | Files | Reuse / update | Deps |
|---|---|---|---|---|
| Move queue display domain | MOVE `appointments/domain/appointment_queue_display.dart` → `queue/domain/queue_display.dart` | `queue/domain/queue_display.dart`; update imports of `appointment_list_item` (still in appointments), `appointment_queue_shift_doctors`/`appointment_queue_start_doctor` (now `queue/domain/…`) | updates `queue_provider` import only | — |
| Move shift-doctors domain | MOVE → `queue/domain/queue_shift_doctors.dart` | new path | update consumers: `queue_start_doctor`, `queue_display`, `queue_shift_provider`, `appointment_status_transitions` (decouple, see row below), `appointment_status_timeline_widget` (param-inject), `appointment_detail_shift_provider`, `appointment_detail_status_actions`, `appointment_detail_page` | queue_display |
| Move start-doctor domain | MOVE → `queue/domain/queue_start_doctor.dart` | new path | update `appointment_status_transitions` (decouple), `appointment_start_doctor_dialog` (Phase 2), `appointment_detail_status_actions` | queue_shift_doctors |
| Decouple `appointment_status_transitions` (keep in appointments) | MOD `appointments/domain/appointment_status_transitions.dart`: replace direct `AppointmentQueueStartDoctor`/`AppointmentQueueShiftDoctorLookup` deps with an injected `inProgressBlocked` predicate + optional `availableShiftOptions` callback | `appointments/domain/appointment_status_transitions.dart`; call sites in `appointment_reschedule_validation.dart`, `appointment_calendar_tile_context_menu.dart`, `appointment_detail_status_actions.dart` pass the predicate from the (later) queue layer | removes `appointments → queue` import | after moves |
| Decouple `appointment_status_timeline_widget` (keep in appointments) | MOD `appointments/presentation/widgets/appointment_status_timeline_widget.dart`: take `doctorPresentation` (`QueueAppointmentDoctorPresentation?`) as a constructor param instead of importing `AppointmentQueueShiftDoctorLookup` | new param on the widget; `appointment_detail_page` passes the already-resolved presentation | removes `appointments → queue` import | after shift-doctors move |
| Move queue realtime data | MOVE `appointment_queue_realtime_apply.dart` → `queue/data/queue_realtime_apply.dart`; MOVE `appointment_queue_realtime.dart` → `queue/data/queue_realtime.dart` | new paths; `queue_realtime.dart` imports `queue_realtime_apply.dart` + `core/config/supabase_config.dart` | `queue_provider` (Phase 2) imports updated | display moved |

Wiring after Phase 1: `flutter analyze` on changed files; route still builds placeholder. Verify `appointments` has zero `import …features/queue/` lines (the extraction must not invert the dependency). **Do not commit unless asked.**

### Phase 2 — Extract queue presentation/providers + shared start-doctor dialog; rewire shell & route

| Task | Action | Files | Reuse / update | Deps |
|---|---|---|---|---|
| Move queue provider | MOVE `appointment_queue_provider.dart` → `queue/presentation/providers/queue_provider.dart` | new path; imports now point at `queue/data/queue_realtime*`, `queue/domain/queue_display`, `appointments/data/appointment_repository`, `appointments/domain/…` (allowed: queue→appointments) | consumers: `app/shell/authenticated_shell.dart` (`appointmentQueueShellWarmProvider`), `appointments/presentation/providers/appointment_surface_invalidation.dart` | Phase 1 |
| Move shift provider | MOVE `appointment_queue_shift_provider.dart` → `queue/presentation/providers/queue_shift_provider.dart` | new path; imports `queue/domain/queue_shift_doctors`, `shifts/…`, `clinic-management/…`, `appointments/domain/appointment_org_calendar` | consumers: `appointments/presentation/providers/appointment_detail_shift_provider.dart`, `appointment_surface_invalidation.dart` | queue_shift_doctors moved |
| Move start-doctor dialog | MOVE `appointments/presentation/widgets/appointment_start_doctor_dialog.dart` → `queue/presentation/widgets/queue_start_doctor_dialog.dart` (rename widget class `QueueStartDoctorDialog`) | new path; imports `queue/domain/queue_start_doctor` | consumer: `appointment_detail_status_actions.dart` imports from `features/queue` (allowed: it invokes the queue action of starting a consultation) — keep class API identical so only the import changes | queue_start_doctor moved |
| Route placeholder→scaffold | MOD `app/router.dart` line 112: keep `shellPlaceholderPage` for now (real builder lands in Phase 5); add `import 'features/queue/presentation/pages/queue_page.dart'` only when Phase 5 flips it | `app/router.dart` | — | Phase 1 |
| Surface-invalidation wiring | MOD `appointments/presentation/providers/appointment_surface_invalidation.dart`: update `appointmentQueueProvider` / `appointmentQueueShiftDoctorLookupProvider` import prefixes to `features/queue/…` | that file | verify no `appointments → queue` cycle beyond the provider id lift | queue providers moved |

Wiring after Phase 2: `flutter analyze`; launch the app — queue route shows placeholder, shell badge still counts checked-ins (`appointmentQueueCheckedInCountProvider` lives in `queue` now). **Do not commit unless asked.**

### Phase 3 — Queue UI: top region (stats header + toolbar + alert banner + empty/loading)

| Widget | Flutter widget(s) to create | Files | Reuse | Wrapper | Deps |
|---|---|---|---|---|---|
| KPI carousel | `QueueKpiCarousel(stats: AppointmentQueueStats, trends: …)` | CREATE `queue/presentation/widgets/queue_kpi_carousel.dart` | `AppCard` per KPI, `AppIconButton` chevrons, `AppScrollArea` (horizontal), `context.appColors`, `AppTypography` (mono numerals via `queue-mono`→`AppTypography` token), `TickerMode` | NEW feature widget | Phase 2 (stats model) |
| Toolbar | `QueueToolbar(search, onSearchChange, statusFilters, onToggleStatus, onClearFilters)` | CREATE `queue/presentation/widgets/queue_toolbar.dart` | `AppSearchInput` (patient search), `AppPopover` + a checkbox-style listbox (`AppCheckbox`-in-`PopupMenu` or `AppPopover` body) mirroring web status listbox, `AppButton` "Status · N" + "Clear filters" | NEW feature widget | none |
| Alert banner | `QueueAlertBanner(issues: List<String>, onDismiss)` | CREATE `queue/presentation/widgets/queue_alert_banner.dart` | `AppCard` warning surface, `Icons.warning_amber`, `context.appColors.warning` | NEW feature widget | `queue_secretary_utils.queueHealthIssues` |
| Empty / loading / error | reuse `AppEmptyState`/`AppLoadingOverlay`/`AppErrorState` directly in the page | no new file | — | reuse | Phase 2 |

> Dev-page instantiation: the web `QueueStats` renders 10 KPI cards (`total, waiting(wk→checkedIn), checked_in, in_progress, completed, queue_length, avg_wait, avg_consult, cancelled, no_show`) with `getKpiTrends()` mock trends. Flutter mirrors all 10 cards; trend labels are backed by `AppointmentQueueStatTrend.percentChange` (real comparison) — flat/neutral when `comparisonItems == null`. Cards: responsive min-width via `LayoutBuilder` breakpoints matching web (`50% / 33% / 25% / 20% / 16.6%`); left/right scroll chevrons gated on `ScrollController` reachability (mirror `canScrollLeft/Right`); `role="region" aria-label="Queue statistics"` ⟶ `Semantics(label: …)`. The toolbar mirrors: search `placeholder='Search patients…'`, `aria-label`; status popover lists the 7 backend statuses in `STATUS_LABELS` order (excluding `arrived`, since backend has none), checklist + "Clear filters" with `activeCount > 0` badge. The web `QueueStats.tsx` / `QueueToolbar.tsx` are the binding source of truth for arrangement, copy, and disabled behavior; control syntax differs (Flutter widgets vs JSX).

Wiring after Phase 3: `flutter analyze`; route still placeholder if a dev preview is wanted, a `QueuePage` skeleton rendering only the top region can be flipped onto the route for smoke-testing (optional). **Do not commit unless asked.**

### Phase 4 — Queue UI: main column (appointments triage table + row actions + status badge)

| Widget | Flutter widget(s) to create | Files | Reuse | Wrapper | Deps |
|---|---|---|---|---|---|
| Status badge | `QueueStatusBadge(status: AppointmentStatus, {size})` | CREATE `queue/presentation/widgets/queue_status_badge.dart` | `AppBadge` with `AppBadgeTone` from `AppointmentQueueDisplay.scheduleBadgeTone`, lucide-style `Icons` per status (Calendar/Clock/Stethoscope/CheckCircle/XCircle/UserX) | NEW feature widget | queue_display |
| Row actions | `QueueRowActions(appointment, siblingAppointments, shiftLookup, onTransition)` | CREATE `queue/presentation/widgets/queue_row_actions.dart` | `AppPopover` menu (`role=menu`), items from real `forwardStatusTargetFor` + `canCancelAppointment`/`canMarkNoShowAppointment`; "Start" → `QueueStartDoctorDialog`; danger items red via `AppBadge`/`context.appColors.destructive` | NEW feature widget; EXTENDS extracted `queue_start_doctor_dialog` | Phase 2 (start dialog), appointments lifecycle RPC |
| Appointments table | `QueueAppointmentsTable(appointments, siblingAppointments, shiftLookup, now, onTransition)` | CREATE `queue/presentation/widgets/queue_appointments_table.dart` | `AppDataTable` with columns Patient (name + MRN via `patientMrn` field — see `docs/specs/016-patient-mrn-field/plan.md`), Time (`intl` time + overdue badge), Status (`QueueStatusBadge`), Preferred doctor (`queueDoctorLabel`), Type (`AppointmentType` label), Wait (`AppointmentQueueDisplay.waitPresentation` + tier color), Actions (`QueueRowActions`); triage sort via `queueSortForTriage`; overdue row red-left-border à la web | NEW feature widget | queue_status_badge, queue_row_actions, queue_display |
| Secretary utils | pure helpers | CREATE `queue/presentation/widgets/queue_secretary_utils.dart` | `AppointmentQueueDisplay`, `AppointmentListItem` | — | queue_display |

> Dev-page instantiation: web `AppointmentsTable` columns are Patient / Time / Status / Preferred doctor / Type / Wait / Actions in that order; the empty state is a dashed-border `AppEmptyState` ("No appointments match your filters" + "Try adjusting search or status filters"). Overdue scheduled rows get a 4px danger left border + danger-surface tint and an "Nm overdue" sub-line under the time cell — Flutter reproduces via an `AppDataTable` row decoration. MRN cell uses `item.patientMrn ?? '—'` and a mono style. Wait tier colors (>30 danger, >20 warning, else primary) come from `AppointmentQueueDisplay.waitTierFor`. The web `AppointmentsTable.tsx` / `AppointmentRowActions.tsx` / `StatusBadge.tsx` are the binding source of truth; `arrived`-row semantics are mapped onto the `confirmed`/`checkedIn` rows that real data produces.

Wiring after Phase 4: `flutter analyze`; row transition calls delegate to the existing appointment status RPC (`appointmentRepository` + `appointmentMessageForRpc`) and `appointmentQueueProvider.patchAppointmentStatus`. **Do not commit unless asked.**

### Phase 5 — Queue UI: side rail (flow control) + confirm/undo + page assembly + route flip

| Widget | Flutter widget(s) to create | Files | Reuse | Wrapper | Deps |
|---|---|---|---|---|---|
| Flow pulse | `QueueFlowPulse(severity, patientCount)` | CREATE `queue/presentation/widgets/queue_flow_pulse.dart` | `AppProgress`-style bar, `AnimationController` (repeat) gated by `TickerMode.of(context)` + `MediaQuery.disableAnimations`, `context.appColors` severity color | NEW feature widget | none |
| Checked-in panel | `QueueCheckedInPanel(patients, now, {embedded})` | CREATE `queue/presentation/widgets/queue_checked_in_panel.dart` | `AppSegmentedControl` (`longest_wait`/`next_in_order`), `QueueFlowPulse`, list of `AppCard`-style rows with wait-tier tint, `AlertCircle` icon for warning/critical | NEW feature widget | queue_flow_pulse, queue_secretary_utils |
| Doctors panel | `QueueDoctorsPanel(doctors, appointments, now, {embedded})` | CREATE `queue/presentation/widgets/queue_doctors_panel.dart` | shift doctors from `AppointmentQueueShiftDoctorLookup`; per-doctor `available`/`with_patient` derived via `inProgressAppointmentForDoctor`; `patientsSeenToday`/idle from shift data (or omitted when absent, per §0.4); progress bar `AppProgress`; lag pill when `getDoctorLagMinutes` analog ≥ 15 | NEW feature widget | queue_shift_doctors, queue_secretary_utils |
| Flow control panel | `QueueFlowControlPanel(appointments, now)` | CREATE `queue/presentation/widgets/queue_flow_control_panel.dart` | `AppTabs` (underline, equalWidth) `Waiting (n)` / `Doctors (n)`; `AnimatedSwitcher`/`AppMotion` collapse between panels | NEW feature widget | queue_checked_in_panel, queue_doctors_panel |
| Confirm dialog | `QueueConfirmDialog(open, kind: cancel/noShow, patientName, onConfirm, onCancel)` | CREATE `queue/presentation/widgets/queue_confirm_dialog.dart` | `AppDialog` danger variant (or reuse `AppointmentCancelDialog` when copy fits: "Cancel appointment?" / "Mark no show?") | NEW feature widget | appointments `canCancelAppointment`/`canMarkNoShowAppointment` |
| Undo toast | `QueueUndoToastController` + binding | CREATE `queue/presentation/widgets/queue_undo_toast.dart` | `AppToastController` / `AppToastHost`; 5s auto-dismiss; Undo → revert RPC (`previousStatusTargetFor`) + `appointmentQueueProvider` refresh; "Undo" button with `Undo2`→`Icons.undo` | NEW feature widget | appointments `canRevertAppointmentStatus`, RPC |
| Page | `QueuePage` | CREATE `queue/presentation/pages/queue_page.dart` | `AppPageHeader` (`Queue` / "Today's patient flow — scan exceptions, move patients forward"); `ConsumerStatefulWidget` holding page-local `search` / `statusFilters` / `sort`; `ref.watch(appointmentQueueProvider)` + `ref.watch(appointmentQueueShiftDoctorLookupProvider)`; 30s `now` `Timer.periodic`; responsive grid `lg:[1fr_340px] xl:[1fr_380px]` via `LayoutBuilder` + `Row`/`Column`; mounts `QueueKpiCarousel`, `QueueToolbar`, `QueueAlertBanner`, `QueueAppointmentsTable`, `QueueFlowControlPanel`, `QueueConfirmDialog`, `QueueUndoToast` | NEW page widget | all Phase 3–5 widgets |

> Dev-page instantiation: web `FlowControlPanel` has 2 tabs (`Waiting`/`Doctors`) with counts; `CheckedInPanel` has a segmented `Longest wait`/`Next in order` sort + `FlowPulse` severity meter (0.2/0.45/0.7/0.95 by max-wait bands) + list rows with wait-tier tint and an index chip `#n`; `DoctorsPanel` lists doctors with status badge (available/with_patient/on_break), current patient, "seen today", idle minutes, lag pill `+N min behind`, and a 12%-per-seen progress bar. `ConfirmDialog` is a centred modal (title, message, "Go back" secondary + danger primary). `UndoToast` is bottom-centred, polite aria-live, `Undo2` button. **The Flutter `features/queue` reproduces each region demo-for-demo from the corresponding `web-reference/src/features/queue/components/*.tsx`**, with the two documented adaptations (status/doctor mapping per §0.4, undo = real revert per §0.5). Where a web prop has no backend equivalent (`embedded`, `on_break`, `exception` chips), it is dropped/derived as noted.

Wiring after Phase 5: flip `app/router.dart` line 112 to `builder: (context, state) => const QueuePage()`; add `QueuePage` import; ensure `AppointmentSection.queue` tab in `AppointmentSectionNav` resolves to it; `flutter analyze` the whole feature. **Do not commit unless asked.**

---

## 4. Dev-page instantiation spec per widget

Because the Queue page is a **feature page** (not a design-system showcase section), there is no `components/<group>/index.ts` registry entry to flip and no `ShowcaseDemo`/`ShowcaseVariantMatrix` grid. Instead the binding source of truth is the **web `QueuePage.tsx` + `components/*.tsx`** themselves, reproduced demo-for-demo inside the single `QueuePage`. Specifically:

- **Page layout & state** ≡ `QueuePage.tsx` lines 30–205: header → `QueueStats` → `QueueToolbar` → responsive grid (`QueueAppointmentsTable` | `QueueFlowControlPanel`) → `ConfirmDialog` → `UndoToast`. Page-local state: `search`, `statusFilters: Set<AppointmentStatus>`, sort (in `QueueCheckedInPanel`), `pendingConfirm`, `undo`/toast, 30s `now` tick. The `useMemo` pipelines translate to pure helpers in `queue_secretary_utils.dart` (filter → search → triage sort; `getCheckedInPatients`).
- **KPI cards** ≡ `QueueStats.tsx` `cards[]` (10 cards, exact order + label + valueClassName tone remapped to backend) and trend surface/tone classes → `context.appColors` semantic surfaces.
- **Toolbar** ≡ `QueueToolbar.tsx`: `AppSearchInput` + `AppPopover`-hosted status listbox (7 backend statuses, check glyph, `activeCount` badge, "Clear filters").
- **Appointments table** ≡ `AppointmentsTable.tsx`: 7 columns in order; overdue row styling; MRN mono sub-line; wait tier color; `QueueRowActions` menu.
- **Row actions** ≡ `AppointmentRowActions.tsx`: "Actions ▾" `AppPopover`; transitions from `forwardStatusTargetFor`/cancel/no-show; "Start Consultation" → `QueueStartDoctorDialog` doctor picker (available doctors only, busy dot).
- **Flow control** ≡ `FlowControlPanel.tsx`: `AppTabs` underline equal-width `Waiting (n)` / `Doctors (n)`; animated collapse.
- **Checked-in panel** ≡ `CheckedInPanel.tsx`: segmented sort + `QueueFlowPulse` + tier-tinted list rows + index chip + `AlertCircle` long/critical wait tag.
- **Doctors panel** ≡ `DoctorsPanel.tsx`: doctor status badge (2 backend states), current patient, seen-today, idle, lag pill, progress bar.
- **Confirm dialog** ≡ `ConfirmDialog.tsx`: title/message/`danger`/`Go back`/confirmLabel.
- **Undo toast** ≡ `UndoToast.tsx`: bottom-centred polite status with `Undo` action (semantics `aria-live="polite"` ⟶ `MergeSemantics`/`Semantics(liveRegion: true)`).

Flutter showcase primitives (`ShowcaseSection`/`ShowcaseDemoGrid`/`ShowcaseDemo`/`ShowcaseVariantMatrix`) are **not** used here — those apply to design-system component ports, not feature pages.

---

## 5. Wiring steps (do after each phase)

After **Phase 1** & **Phase 2** (extraction):
- Update every consumer import prefix from `features/appointments/{domain,data,presentation/providers,presentation/widgets}/appointment_queue_*` and `appointment_start_doctor_dialog` to the new `features/queue/…` paths (see the table in §0.3 for the exact consumer list).
- MOD `appointments/domain/appointment_status_transitions.dart` and `appointments/presentation/widgets/appointment_status_timeline_widget.dart` to drop their `queue` imports (dependency-inject the in-progress guard / doctor presentation).
- `flutter analyze` on `frontend/`; run the app and confirm the shell still shows the checked-in badge and the appointments calendar/detail pages build.
- No `component_registry.dart` / `component_section_builders.dart` changes (not a design-system component).
- Do NOT commit unless asked.

After **Phase 3 / 4 / 5** (UI):
- No barrel (`widgets.dart`) changes (no new `core/ui` files).
- After Phase 5: MOD `app/router.dart` `appointmentsQueue` route `builder` → `QueuePage`; add the `features/queue/presentation/pages/queue_page.dart` import.
- Verify `AppointmentSectionNav` `queue` tab navigates to the live page and the breadcrumb (`shell_nav_config.dart` `appointments` item) renders "Queue".
- `flutter analyze` the `features/queue/` + touched `app/` + `features/appointments/` files; golden smoke-test the page with a seeded branch (`dev_clinic_seed_*`).
- Do NOT commit unless asked.

---

## 6. Out-of-scope / defer

- **Exception chips** (`copayDue`/`formsIncomplete`/`selfCheckInPending`/`insuranceIssue`): no such field on `AppointmentListItem`; deferred until a billing/forms domain field lands (separate spec).
- **`arrived` status & self-check-in flow**: backend `AppointmentStatus` has no `arrived`; the web's arrived-vs-checked-in split is collapsed onto `confirmed`/`checkedIn`. A future "patient self check-in" spec may reintroduce it.
- **`on_break` doctor status** & `idleSince`/`patientsSeenToday` persistence: backend derives availability from shifts only; lag/idle shown only where the shift lookup exposes the data; full `DoctorsPanel` parity deferred with the shifts feature.
- **KPI trend comparison when `comparisonItems` not loaded**: trend surfaces render flat/neutral (matches `AppointmentQueueStatTrend.percentChange == null`).
- **Board view** (`web-reference/src/features/queue/board/` is empty): not ported.
- **Pattern page** `showcase/patterns/CalendarQueuePattern.tsx`: not ported (dev showcase, separate concern).
- **Mock-data port**: `mock-data.ts` is **not** ported; the Flutter page binds to real `appointmentQueueProvider` (seeded in dev by `dev_clinic_seed_*`).

---

## 7. Source reference — web widget inventory

| Export (web) | Title | Showcase file | Underlying UI component |
|---|---|---|---|
| `QueuePage` | Queue page | `web-reference/src/features/queue/QueuePage.tsx` | composition of the components below |
| `QueueStats` | KPI carousel | `…/components/QueueStats.tsx` | `IconButton`, lucide `TrendingUp/Down/Minus/ChevronLeft/Right`, `formatDuration` |
| `QueueToolbar` | Search + status filter | `…/components/QueueToolbar.tsx` | `Button`, `Popover`, lucide `Search/SlidersHorizontal/Check` |
| `AppointmentsTable` | Triage table | `…/components/AppointmentsTable.tsx` | `StatusBadge`, `AppointmentRowActions` |
| `AppointmentRowActions` | Row transition menu | `…/components/AppointmentRowActions.tsx` | lucide `ChevronDown`, `STATUS_TRANSITIONS` |
| `StatusBadge` | Status pill | `…/components/StatusBadge.tsx` | lucide status icons, `STATUS_LABELS` |
| `ExceptionChips` | Exception chips | `…/components/ExceptionChips.tsx` | lucide `CreditCard/ClipboardList/Smartphone/AlertCircle` *(deferred — no backend field)* |
| `QueueAlertBanner` | Alert strip | `…/components/QueueAlertBanner.tsx` | lucide `AlertTriangle`, `buildAlertSummary`/`getQueueHealthIssues` |
| `FlowControlPanel` | Side rail | `…/components/FlowControlPanel.tsx` | `Tabs`, `motion` collapse |
| `CheckedInPanel` | Waiting list | `…/components/CheckedInPanel.tsx` | `SegmentedControl`, `FlowPulse`, lucide `AlertCircle` |
| `DoctorsPanel` | Doctors list | `…/components/DoctorsPanel.tsx` | lucide `Coffee/Stethoscope/UserCheck`, `getDoctorLagMinutes`/`getIdleMinutes` |
| `FlowPulse` | Severity meter | `…/components/FlowPulse.tsx` | `motion`, `useReducedMotion` |
| `ConfirmDialog` | Danger confirm modal | `…/components/ConfirmDialog.tsx` | (raw) |
| `UndoToast` | Undo snackbar | `…/components/UndoToast.tsx` | `motion`/`AnimatePresence`, lucide `Undo2` |
| `types.ts` | `Appointment`/`Doctor`/`QueueStats`/`StatusTransition`/`STATUS_TRANSITIONS`/`STATUS_LABELS` | `…/types.ts` | — |
| `utils.ts` | `computeQueueStats`/`getWaitMinutes`/`isOverdue`/`sortAppointmentsForTriage`/`filterByStatusChip`/`getCheckedInPatients`/`getKpiTrends`/`getQueueHealthIssues`/`getDoctorLagMinutes`/`getIdleMinutes`/`formatDuration`/`formatTime` | `…/utils.ts` | — |

**Shared web building blocks → Flutter equivalents:** `cn` ⟶ `context.appColors` conditional theming; `motion`/`motionPresets`/`useReducedMotion` ⟶ `core/ui/motion/app_motion.dart` + `TickerMode`/`MediaQuery.disableAnimations`; lucide-react icons ⟶ Material `Icons`; Radix `Popover`/`Tabs`/listbox ⟶ `AppPopover`/`AppTabs`/`MenuAnchor`; `IconButton` ⟶ `AppIconButton`; `Button` ⟶ `AppButton`; `SegmentedControl` ⟶ `AppSegmentedControl`; `Tabs` ⟶ `AppTabs`. No `chip`/`kbd`/`tooltip` web primitives surface here beyond icon usage.