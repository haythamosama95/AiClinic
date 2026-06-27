# Senior QA Review — `ui/010-queue`

**Base branch:** `ui/master`
**Head:** `ui/010-queue` (`da5eb34`)
**Scope:** 96 files, +9,922 / −288 lines across queue dashboard, `AppNotchedCard` widget, appointment status/backend migrations, shell chrome, and automated tests.

This document analyzes every commit and functional change between `ui/master` and `ui/010-queue`, identifies regression and risk areas, and defines a production-oriented test suite. Findings assume the implementation may contain defects.

---

## Executive summary

This branch delivers a full **clinic queue dashboard** at `/appointments/queue`: today's appointments in a timeline column, doctors on shift, checked-in waiting patients, KPI stat cards with day-over-day trends, inline status management via a journey dialog, doctor-picker flow when starting visits, and navigation cross-links (checked-in/doctor rows scroll to the matching schedule card). It introduces the reusable **`AppNotchedCard`** layout widget (also used on dashboard showcase cards), three **Supabase migrations** (list `updated_at`, one-in-progress-per-doctor enforcement, `checked_in_at` / `in_progress_at` timestamps), and a **shell nav badge** for checked-in count. Shell chrome changes (header profile, content panel bleed, settings nav focus) ship in the same diff via merge from `ui/master`.

**Release confidence blockers to verify manually:**

| Area | Risk |
| ---- | ---- |
| Backend migrations | `one_in_progress_per_doctor`, `appointment_wait_timestamps`, and `list_appointments_updated_at` must be applied before queue stats and Start actions behave correctly |
| Status changes from queue dialog | Confirm → Check in → Start (with doctor picker) → No-show/Cancel; RPC errors must surface via toast, queue must stay consistent |
| One in-progress per doctor | Server rejects second `in_progress` for same doctor; UI must offer alternate doctor when preferred is busy |
| Doctor picker on every Start | Staff must confirm doctor even when preferred doctor is free — verify UX acceptance |
| Realtime vs optimistic patch | `patchAppointmentStatus` updates local cache; realtime refresh may race; degraded connection is not shown in UI |
| Layout at breakpoints | Wide (≥1100px) vs narrow column stack; viewport-fill vs page scroll (`bodyScrollable`); resize must not nest scroll areas incorrectly |
| Widget test gap | No `appointment_queue_page_test.dart` despite docs reference — page-level behavior is manual-only |
| Shell regressions | Header profile, settings nav deselect, content panel inset removal affect all authenticated routes |

---

## Commit-by-commit change analysis

### `5aea90d` — Initial implementation for the queue UI

| Category | Detail |
| -------- | ------ |
| **New feature** | `AppointmentQueuePage`, `AppointmentQueueDisplay`, `AppointmentQueueController`, four column widgets, stats banner |
| **Routing** | Queue route wired to real page |
| **Design** | `design-system/aiclinic/pages/queue.md`, `MASTER.md` updates |

**Affected systems:** App router, appointments feature module, design system.

**Regression areas:** Any placeholder at `/appointments/queue`.

**Risks:** Initial partition logic may not match final shift-doctor rules; no backend timestamp columns yet.

---

### `0723c9f` — Modifying dev option for filling appointments with correct statuses

| Category | Detail |
| -------- | ------ |
| **Dev tooling** | `dev_clinic_seed_schedule.dart` seeds appointments across lifecycle statuses for queue testing |
| **Tests** | `dev_clinic_seed_schedule_test.dart` extended |

**Regression areas:** Dev "fill dummy clinic" action; seed data used in manual QA.

**Risks:** Seed statuses must align with RPC transition rules or queue demo is misleading.

---

### `7b3177f` — Limiting in progress appointments to one per doctor

| Category | Detail |
| -------- | ------ |
| **Database** | `20260621120000_list_appointments_updated_at.sql`, `20260621140000_one_in_progress_per_doctor.sql` |
| **Backend** | `doctor_has_in_progress_appointment`, `update_appointment_status` blocks `DOCTOR_ALREADY_IN_PROGRESS` |
| **Frontend** | `doctorInProgressBlockReason`, schedule column refactor, waiting column removed temporarily |
| **Tests** | `appointment_management_crud.sql`, display/transition/realtime unit tests |

**Affected systems:** All appointment status RPCs, visit create advance path, queue Start button enablement.

**Regression areas:** Calendar/detail status actions; concurrent in-progress visits.

**Risks:** Unassigned `doctor_id IS NULL` shares one in-progress slot per branch (per migration comment).

---

### `bfad2d0` — adding shifts in the dummy clinic data

| Category | Detail |
| -------- | ------ |
| **Dev tooling** | Shifts seeded with dummy clinic; `shift_repository` list helpers |
| **Tests** | `shift_repository_test.dart`, seed schedule tests |

**Regression areas:** Shift list RPC used by queue shift lookup.

---

### `493bcb2` — Refining doctor name in the appointments cards in queue page

| Category | Detail |
| -------- | ------ |
| **New domain** | `AppointmentQueueShiftDoctorLookup`, shift provider |
| **UI** | Doctor column shows shift-aware names, patient-choice labeling |

**Risks:** Doctor resolution by normalized name may mismatch if staff rename or duplicate names exist.

---

### `054a315` — Adding buttons to advance state of each appointment

| Category | Detail |
| -------- | ------ |
| **UI** | `appointment_queue_row_advance_button.dart` (later replaced by status journey dialog) |

---

### `edee1e4` — Adding speckit docs

| Category | Detail |
| -------- | ------ |
| **Docs** | `specs/010-app-notched-card/*`, `docs/ui/notch_card_design.md`, feature.json cursor rules |

---

### `726aa04` — Implementing phases 1 and 2

| Category | Detail |
| -------- | ------ |
| **New widget** | `notched_card_path.dart` geometry + unit tests |
| **Spec** | Notched card tasks marked complete for path phase |

---

### `f79582d` — Improving the appointments card in the queue page

| Category | Detail |
| -------- | ------ |
| **UI** | Major `appointment_queue_schedule_column` redesign; `AppointmentQueueStartDoctor`, doctor picker dialog |
| **Shared** | `tilted_background_icon_stack.dart`, `appointment_scale_down_text.dart` |
| **Status** | Detail status actions integrate queue sibling appointments + shift lookup |

**Risks:** Start flow assigns doctor via `updateAppointment` then `updateAppointmentStatus` — partial failure leaves inconsistent doctor assignment.

---

### `040b6f0` — Implementing phase 3

| Category | Detail |
| -------- | ------ |
| **New widget** | `app_notched_card.dart` initial implementation |
| **UI** | Dashboard showcase cards for notched card demo |

---

### `fd4eba4` — Adding check in count to the navbar indicator

| Category | Detail |
| -------- | ------ |
| **UI** | `appointmentQueueCheckedInCountProvider`, shell nav badge on Queue item |
| **Config** | `ShellNavConfig.queueNavItemId`, success badge tone |

**Risks:** Badge counts checked-in partition only; does not include confirmed/scheduled.

---

### `53a7ba5` — Fixing issue where stall state affected the queue page

| Category | Detail |
| -------- | ------ |
| **Bug fix** | Queue page refresh on route focus without stale stall blocking |

---

### `2a2f2e0` — Prompting busy preferred doctor to whoever is available

| Category | Detail |
| -------- | ------ |
| **Logic** | `blockReasonForStart` allows Start when preferred busy but free alternatives exist |
| **UX** | Doctor picker messaging for busy preferred doctor |

---

### `8c16835` — Removing title and subtitle from the queue page

| Category | Detail |
| -------- | ------ |
| **UI** | Page relies on shell header title; removes redundant in-page heading |

---

### `3165ce4` — Adapting notch height to the actions provided

| Category | Detail |
| -------- | ------ |
| **UI** | `AppNotchedCard` dynamic notch sizing based on action count/width |

---

### `dd48059` — Adding new design for the statistics cards

| Category | Detail |
| -------- | ------ |
| **New widget** | `app_metric_stat_card.dart` |
| **UI** | Stats banner uses metric cards with trend indicators |

---

### `5f4686f` / `64c5fc5` — Improving actions sizing / hover effect

| Category | Detail |
| -------- | ------ |
| **UI** | Notched card action bar polish |

---

### `eee8249` — Adding more statistics

| Category | Detail |
| -------- | ------ |
| **Feature** | Avg wait, avg visit duration, day-over-day comparison via previous working day fetch |

**Risks:** Comparison fetch fails silently (`_fetchComparisonItems` returns null); trends hidden not errored.

---

### `1294763` — Implementing phases 5 and 6

| Category | Detail |
| -------- | ------ |
| **Widget** | `AppNotchedCard` phases 5–6 per spec tasks |
| **Tests** | Extended `app_notched_card_test.dart` |

---

### `b5973f5` — Adding no show button to appointments

| Category | Detail |
| -------- | ------ |
| **UI** | No-show action in status journey / detail status actions |

---

### `f56267a` — Making appointment status switching buttons always visible

| Category | Detail |
| -------- | ------ |
| **UI** | Status actions always rendered (disabled with tooltips when blocked) |

---

### `3125242` — Fixing coderabbit review comments + slider issue in theme showcase

| Category | Detail |
| -------- | ------ |
| **Bug fix** | Theme showcase slider; minor review fixes |

---

### `4bf78e6` — Fixing screen flash during appointment status change

| Category | Detail |
| -------- | ------ |
| **Bug fix** | `patchAppointmentStatus` avoids full list reload flash on successful RPC |
| **State** | Optimistic local patch for status + timestamps |

**Risks:** Patched `checkedInAt`/`inProgressAt` use client `DateTime.now()` — may drift from server if RPC fails silently on second tab.

---

### `5ab6401` — Removing showcasing cards from the dashboard

| Category | Detail |
| -------- | ------ |
| **UI** | Dashboard cleanup after notched card integration elsewhere |

---

### `e13d95e` — Reducing width for time section in appointments cards

| Category | Detail |
| -------- | ------ |
| **UI** | Schedule row layout: 72px time column |

---

### `0d0b25b` — Making status shown in a pop out dialog to transition

| Category | Detail |
| -------- | ------ |
| **New widget** | `appointment_status_journey_dialog.dart`, `appointment_queue_row_status_button.dart` |
| **UX** | Play button opens status timeline dialog instead of inline advance |

---

### `d3b5153` — Making content page span to right and bottom + removing search from app header

| Category | Detail |
| -------- | ------ |
| **Shell** | `shell_content_panel.dart` inset changes; header search removed |

**Regression areas:** All shell-wrapped pages layout bleed.

---

### `82b1b0f` — Fixing settings nav focus issue

| Category | Detail |
| -------- | ------ |
| **Bug fix** | `ShellNavConfig.isSettingsLocation` — settings routes don't highlight nav items |

---

### `bde4907` — Making account info displayed in the header bar

| Category | Detail |
| -------- | ------ |
| **Shell** | `shell_header_profile.dart` — profile in header |

---

### `29b14aa` / `6a77571` — Doctors in shift cards + design

| Category | Detail |
| -------- | ------ |
| **UI** | `AppointmentQueueSessionColumn` with `AppNotchedCard`, doctor rows, in-progress patient display |

---

### `94f35dd` — Designing the check in card below doctors in shift

| Category | Detail |
| -------- | ------ |
| **UI** | `AppointmentQueueWaitingColumn` restored as separate notched card |

---

### `5df86f3` / `6127302` / `c0379ce` — Merge commits

| Category | Detail |
| -------- | ------ |
| **Merge** | Integrates `ui/master` shell/notched-card work into queue branch |

---

### `e0f6183` / `b6c396e` / `4f4ecf5` — Notched card integration

| Category | Detail |
| -------- | ------ |
| **UI** | Schedule, session, and waiting columns use `AppNotchedCard`; header icons; `AppBadge` tweaks |

---

### `5450491` — Modifying statistics cards

| Category | Detail |
| -------- | ------ |
| **Logic** | Stats computation updates for completed/no-show/trend display |

---

### `3d1b664` — Fixing resizing issue (minimum height)

| Category | Detail |
| -------- | ------ |
| **Bug fix** | `LayoutBuilder` viewport-fill logic, min panel heights, `Expanded` vs scroll |

---

### `f27ae68` — Doctor card scroll to patient in appointments

| Category | Detail |
| -------- | ------ |
| **UX** | Tapping doctor with in-progress patient scrolls schedule to that appointment + flash highlight |

---

### `5176980` — User must select doctor even when preferred is selected

| Category | Detail |
| -------- | ------ |
| **UX** | `requiresDoctorPicker` always prompts on Start when any free option exists |
| **Tests** | `appointment_queue_start_doctor_test`, picker dialog tests updated |

**Risks:** Extra click on every Start — intentional but may slow front desk.

---

### `da5eb34` — Making all widgets in queue page not scrollable during width resize

| Category | Detail |
| -------- | ------ |
| **Bug fix** | `bodyScrollable: fillsViewport` on all three columns — defers scroll to page when viewport too short |

---

## Cross-cutting findings

### Missing test coverage

- No `appointment_queue_page_test.dart` (referenced in `docs/tests/test-coverage-frontend.md` but file absent)
- No widget tests for `AppointmentQueueScheduleColumn`, `AppointmentQueueSessionColumn`, `AppointmentQueueWaitingColumn`
- No widget tests for `AppointmentStatusJourneyDialog` end-to-end status change
- Realtime `degraded` connection state subscribed but ignored (`onConnectionChanged: (_) {}`) — no UI test possible
- No E2E test for checked-in tap → scroll → flash → status change flow
- Backend migration tests exist in `appointment_management_crud.sql` but no dedicated SQL test file for `DOCTOR_ALREADY_IN_PROGRESS` concurrent scenario

### Potential bugs

| ID | Severity | Area | Description | Related change |
| -- | -------- | ---- | ----------- | -------------- |
| BUG-001 | High | Optimistic patch | `patchAppointmentStatus` sets `checkedInAt`/`inProgressAt` with client clock; may disagree with server timestamps until refresh | `4bf78e6` |
| BUG-002 | High | Realtime | Degraded realtime connection never surfaced; queue may show stale data without user awareness | `fd4eba4` / provider |
| BUG-003 | Medium | Scroll | `_estimatedRowHeight = 92` scroll fallback may miss target row before `ensureVisible` | `f27ae68` |
| BUG-004 | Medium | Doctor assign | Start flow: `updateAppointment` then `updateAppointmentStatus` — if second RPC fails, doctor assigned but status unchanged | `f79582d` |
| BUG-005 | Medium | Shift lookup | Doctor matched by normalized full name on shifts; duplicate names or typos assign wrong doctor | `493bcb2` |
| BUG-006 | Medium | Stats trends | Previous working day comparison fails silently; trends omitted without error indicator | `eee8249` |
| BUG-007 | Low | Nav badge | Badge driven by queue provider; count is 0 until user visits queue or provider warms — may lag on first load | `fd4eba4` |
| BUG-008 | Low | Focus index | `indexClosestToNow` uses slot times, not status — in-progress appointment outside slot window may not be focused | `5aea90d` |
| BUG-009 | Low | Null doctor slot | Multiple unassigned in-progress appointments blocked as one shared slot server-side — UI messaging may be unclear | `7b3177f` |

### Potential performance issues

- Queue refresh on every route revisit (`didChangeDependencies` + `refresh()`)
- Comparison day fetch adds second `listAppointments` RPC on every refresh
- Shift lookup provider fetches shifts + branch staff + org staff list on each rebuild scope
- Large appointment lists: timeline `ListView` with per-row gradients and `TiltedBackgroundIconStack` — profile with 50+ rows

### Potential security concerns

- Status changes respect `appointments.create` / `appointments.cancel` permissions (inherited from detail actions)
- Queue page gates on `canAccessAppointments()` — verify role matrix for reception vs doctor
- Doctor picker allows selecting any non-busy shift doctor — server must validate doctor-branch assignment on `updateAppointment`

### Risky implementation decisions

- Doctor picker shown on every Start when alternatives exist (explicit product choice in `5176980`)
- Realtime apply falls back to full `refresh()` when payload insufficient — may cause list jump during active scrolling
- `requiresDoctorPicker` returns false when `blockReasonForStart != null` — user sees disabled Start with tooltip instead of picker
- Page-level `SingleChildScrollView` when viewport short — nested scroll hand-off via `bodyScrollable` is subtle

### Manual testing required before release

- Full status lifecycle from queue journey dialog on real Supabase (all RPC error codes)
- Two receptionists changing same appointment status concurrently
- Preferred doctor busy → pick alternate → verify doctor_id persisted
- Migrations applied on staging: timestamps in list response, one-in-progress enforcement
- Nav badge updates when checking in from calendar vs queue
- Wide/narrow/tablet widths; window resize during interaction
- Shell: settings route, header profile, content bleed on dashboard + queue + calendar

---

## Test suite

### Functional tests

#### FUNC-001 — Queue page loads today's appointments

| Field | Value |
| ----- | ----- |
| **Area/Module** | Queue / data load |
| **Related commit** | `5aea90d` — Initial queue UI |
| **Priority** | Critical |
| **Type** | Functional |
| **Preconditions** | Authenticated user with `appointments.read`, active branch selected, appointments exist today |

**Steps:**

1. Navigate to Appointments → Queue.
2. Wait for loading skeleton to clear.

**Expected result:** Appointments for today appear in schedule column sorted by start time; stats banner shows counts.

---

#### FUNC-002 — Permission denied without appointment access

| Field | Value |
| ----- | ----- |
| **Area/Module** | Queue / RBAC |
| **Related commit** | `5aea90d` |
| **Priority** | Critical |
| **Type** | Functional |
| **Preconditions** | User lacks appointment permissions |

**Steps:**

1. Navigate to `/appointments/queue`.

**Expected result:** "Queue access required" message; no appointment data fetched.

---

#### FUNC-003 — Missing active branch guidance

| Field | Value |
| ----- | ----- |
| **Area/Module** | Queue / branch scope |
| **Related commit** | `5aea90d` |
| **Priority** | High |
| **Type** | Functional |
| **Preconditions** | Authenticated without `activeBranchId` |

**Steps:**

1. Open queue page.

**Expected result:** Error message to select active branch; Retry button present.

---

#### FUNC-004 — Confirm appointment from journey dialog

| Field | Value |
| ----- | ----- |
| **Area/Module** | Status transitions |
| **Related commit** | `0d0b25b`, `f56267a` |
| **Priority** | Critical |
| **Type** | Functional |
| **Preconditions** | Scheduled appointment today; `appointments.create` permission |

**Steps:**

1. Tap play/status button on scheduled row.
2. In dialog, tap Confirm.

**Expected result:** Status → confirmed; toast success; row badge updates without full-page flash; calendar invalidates.

---

#### FUNC-005 — Check in appointment

| Field | Value |
| ----- | ----- |
| **Area/Module** | Status transitions |
| **Related commit** | `0d0b25b` |
| **Priority** | Critical |
| **Type** | Functional |
| **Preconditions** | Confirmed appointment today |

**Steps:**

1. Open journey dialog; tap Check in.

**Expected result:** Status → checked_in; patient appears in Checked in column; nav badge count increments.

---

#### FUNC-006 — Start appointment with doctor picker

| Field | Value |
| ----- | ----- |
| **Area/Module** | Start flow |
| **Related commit** | `5176980`, `f79582d` |
| **Priority** | Critical |
| **Type** | Functional |
| **Preconditions** | Checked-in appointment; multiple doctors on shift |

**Steps:**

1. Tap Start in journey dialog.
2. Confirm doctor in picker dialog.

**Expected result:** Doctor assigned; status → in_progress; session column shows doctor busy with patient.

---

#### FUNC-007 — Start blocked when all doctors busy

| Field | Value |
| ----- | ----- |
| **Area/Module** | One in-progress rule |
| **Related commit** | `7b3177f` |
| **Priority** | Critical |
| **Type** | Functional |
| **Preconditions** | Each on-shift doctor has an in-progress appointment |

**Steps:**

1. Attempt Start on another checked-in patient.

**Expected result:** Start disabled with tooltip explaining all doctors busy; RPC not called.

---

#### FUNC-008 — Start with busy preferred doctor, free alternate

| Field | Value |
| ----- | ----- |
| **Area/Module** | Doctor picker |
| **Related commit** | `2a2f2e0`, `5176980` |
| **Priority** | High |
| **Type** | Functional |
| **Preconditions** | Checked-in with preferred doctor A; A in progress; doctor B free on shift |

**Steps:**

1. Tap Start; select doctor B in picker.

**Expected result:** Appointment assigned to B; in_progress; preferred doctor constraint satisfied.

---

#### FUNC-009 — Mark no-show

| Field | Value |
| ----- | ----- |
| **Area/Module** | Status transitions |
| **Related commit** | `b5973f5` |
| **Priority** | High |
| **Type** | Functional |
| **Preconditions** | Confirmed or checked-in appointment today; `appointments.cancel` |

**Steps:**

1. Open journey dialog; tap No-show.

**Expected result:** Status → no_show; stats no-show count increments.

---

#### FUNC-010 — Cancel appointment with reason

| Field | Value |
| ----- | ----- |
| **Area/Module** | Status transitions |
| **Related commit** | `0d0b25b` |
| **Priority** | High |
| **Type** | Functional |
| **Preconditions** | Scheduled appointment |

**Steps:**

1. Cancel from journey dialog with reason.

**Expected result:** Status → cancelled; row dimmed in schedule.

---

#### FUNC-011 — Book appointment from queue schedule header

| Field | Value |
| ----- | ----- |
| **Area/Module** | Booking |
| **Related commit** | `f79582d` |
| **Priority** | High |
| **Type** | Functional |
| **Preconditions** | `appointments.create`; branch working hours configured |

**Steps:**

1. Tap Book Appointment in schedule notched card header.
2. Complete booking sheet.

**Expected result:** New appointment appears after refresh; slot snapped to current time.

---

### Frontend tests

#### FE-001 — Wide layout three-column grid

| Field | Value |
| ----- | ----- |
| **Area/Module** | Layout |
| **Related commit** | `3d1b664`, `da5eb34` |
| **Priority** | High |
| **Type** | Frontend |
| **Preconditions** | Viewport width ≥ 1100px, height sufficient |

**Steps:**

1. Open queue with sample data at 1280×900.

**Expected result:** Schedule (left), Doctors + Checked in (right stack); no page-level scroll; columns scroll internally.

---

#### FE-002 — Narrow layout stacked columns

| Field | Value |
| ----- | ----- |
| **Area/Module** | Layout |
| **Related commit** | `3d1b664` |
| **Priority** | High |
| **Type** | Frontend |
| **Preconditions** | Viewport width < 1100px |

**Steps:**

1. Open queue at 800px width.

**Expected result:** Schedule, Doctors, Checked in stacked vertically.

---

#### FE-003 — Short viewport page scroll

| Field | Value |
| ----- | ----- |
| **Area/Module** | Layout |
| **Related commit** | `da5eb34` |
| **Priority** | Medium |
| **Type** | Frontend |
| **Preconditions** | Short window height (< min body height) |

**Steps:**

1. Resize height to ~500px with full queue data.

**Expected result:** Outer `SingleChildScrollView` scrolls; column lists use `shrinkWrap` + `NeverScrollableScrollPhysics`.

---

#### FE-004 — Stats banner compact vs wide

| Field | Value |
| ----- | ----- |
| **Area/Module** | Stats UI |
| **Related commit** | `dd48059` |
| **Priority** | Medium |
| **Type** | Frontend |
| **Preconditions** | Queue loaded |

**Steps:**

1. View at width ≥ 720px, then < 720px.

**Expected result:** Row of five cards vs 2-column wrap; trend arrows visible when comparison data exists.

---

#### FE-005 — Schedule timeline focus bubble

| Field | Value |
| ----- | ----- |
| **Area/Module** | Schedule column |
| **Related commit** | `5aea90d`, `f79582d` |
| **Priority** | Medium |
| **Type** | Frontend |
| **Preconditions** | Multiple appointments spanning current time |

**Steps:**

1. Observe timeline gutter at current time.

**Expected result:** Closest/current slot has teal focus bubble; past segments use active line color.

---

#### FE-006 — Checked-in patient tap scrolls schedule

| Field | Value |
| ----- | ----- |
| **Area/Module** | Navigation |
| **Related commit** | `6ffb641`, `f27ae68` |
| **Priority** | High |
| **Type** | Frontend |
| **Preconditions** | Checked-in patient not visible in schedule viewport |

**Steps:**

1. Tap patient row in Checked in column.

**Expected result:** Schedule scrolls to appointment; row flashes ~1.4s highlight.

---

#### FE-007 — Doctor row tap when in progress

| Field | Value |
| ----- | ----- |
| **Area/Module** | Session column |
| **Related commit** | `6ffb641` |
| **Priority** | High |
| **Type** | Frontend |
| **Preconditions** | Doctor with in-progress patient |

**Steps:**

1. Tap doctor row.

**Expected result:** Scrolls to patient's schedule card (same as FE-006). Doctor without patient is not tappable.

---

#### FE-008 — Nav badge checked-in count

| Field | Value |
| ----- | ----- |
| **Area/Module** | Shell nav |
| **Related commit** | `fd4eba4` |
| **Priority** | High |
| **Type** | Frontend |
| **Preconditions** | N checked-in appointments |

**Steps:**

1. Observe Queue nav item badge on any shell page.

**Expected result:** Badge shows N; success tone; updates after check-in without requiring queue revisit (after provider refresh).

---

#### FE-009 — AppNotchedCard action bar sizing

| Field | Value |
| ----- | ----- |
| **Area/Module** | Shared widget |
| **Related commit** | `3165ce4`, `5f4686f` |
| **Priority** | Medium |
| **Type** | Frontend |
| **Preconditions** | Schedule card with Book + date badge + calendar icon |

**Steps:**

1. Inspect notch width and action clipping at various widths.

**Expected result:** Actions fit notch; no overflow; hover states on desktop.

---

#### FE-010 — Status journey dialog loading preview

| Field | Value |
| ----- | ----- |
| **Area/Module** | Status dialog |
| **Related commit** | `0d0b25b` |
| **Priority** | Medium |
| **Type** | Frontend |
| **Preconditions** | Slow network to detail RPC |

**Steps:**

1. Open journey dialog.

**Expected result:** Preview timeline from list item while loading; transitions to full detail without dialog close.

---

### Backend tests

#### BE-001 — list_appointments returns updated_at

| Field | Value |
| ----- | ----- |
| **Area/Module** | RPC |
| **Related commit** | `7b3177f` |
| **Priority** | High |
| **Type** | Backend |
| **Preconditions** | Migration `20260621120000` applied |

**Steps:**

1. Call `list_appointments` for today.

**Expected result:** Each item includes `updated_at` ISO timestamp.

---

#### BE-002 — list_appointments returns wait timestamps

| Field | Value |
| ----- | ----- |
| **Area/Module** | RPC |
| **Related commit** | `20260627120000` |
| **Priority** | Critical |
| **Type** | Backend |
| **Preconditions** | Migration `20260627120000` applied; checked-in appointment exists |

**Steps:**

1. Call `list_appointments`.

**Expected result:** `checked_in_at` and `in_progress_at` present when set.

---

#### BE-003 — Second in_progress for same doctor rejected

| Field | Value |
| ----- | ----- |
| **Area/Module** | Status RPC |
| **Related commit** | `7b3177f` |
| **Priority** | Critical |
| **Type** | Backend |
| **Preconditions** | Doctor D has appointment A in_progress; appointment B checked_in with doctor D |

**Steps:**

1. `update_appointment_status(B, 'in_progress')`.

**Expected result:** `DOCTOR_ALREADY_IN_PROGRESS` error; status unchanged.

---

#### BE-004 — checked_in sets checked_in_at

| Field | Value |
| ----- | ----- |
| **Area/Module** | Timestamps |
| **Related commit** | `20260627120000` |
| **Priority** | High |
| **Type** | Backend |
| **Preconditions** | Confirmed appointment |

**Steps:**

1. Transition to checked_in.

**Expected result:** `checked_in_at` NOT NULL; `in_progress_at` NULL.

---

#### BE-005 — in_progress sets in_progress_at

| Field | Value |
| ----- | ----- |
| **Area/Module** | Timestamps |
| **Related commit** | `20260627120000` |
| **Priority** | High |
| **Type** | Backend |
| **Preconditions** | Checked-in appointment with doctor |

**Steps:**

1. Transition to in_progress.

**Expected result:** Both timestamps set.

---

#### BE-006 — Future day check-in rejected

| Field | Value |
| ----- | ----- |
| **Area/Module** | Day rules |
| **Related commit** | `7b3177f` |
| **Priority** | High |
| **Type** | Backend |
| **Preconditions** | Appointment scheduled future date |

**Steps:**

1. Attempt check-in.

**Expected result:** `INVALID_TRANSITION`.

---

### Integration tests

#### INT-001 — Realtime insert updates queue

| Field | Value |
| ----- | ----- |
| **Area/Module** | Realtime |
| **Related commit** | `5aea90d` |
| **Priority** | High |
| **Type** | Integration |
| **Preconditions** | Queue page open; realtime connected |

**Steps:**

1. Create appointment via second client/session.

**Expected result:** Queue list updates without manual refresh.

---

#### INT-002 — Realtime status change patches row

| Field | Value |
| ----- | ----- |
| **Area/Module** | Realtime |
| **Related commit** | `4bf78e6` |
| **Priority** | High |
| **Type** | Integration |
| **Preconditions** | Queue open |

**Steps:**

1. Check in appointment from calendar detail in second tab.

**Expected result:** Queue row and checked-in column update; minimal scroll jump.

---

#### INT-003 — Start assigns doctor then advances status

| Field | Value |
| ----- | ----- |
| **Area/Module** | Start flow |
| **Related commit** | `f79582d` |
| **Priority** | Critical |
| **Type** | Integration |
| **Preconditions** | Unassigned checked-in appointment |

**Steps:**

1. Start with doctor picker selection.

**Expected result:** DB `doctor_id` set; status in_progress; visit can be created.

---

#### INT-004 — Stats comparison previous working day

| Field | Value |
| ----- | ----- |
| **Area/Module** | Stats |
| **Related commit** | `eee8249` |
| **Priority** | Medium |
| **Type** | Integration |
| **Preconditions** | Branch open Mon–Fri; appointments on previous working day |

**Steps:**

1. Load queue on Tuesday after Monday data.

**Expected result:** Trend percent on stat cards reflects Monday vs Tuesday delta.

---

#### INT-005 — Shift doctors match today's shifts

| Field | Value |
| ----- | ----- |
| **Area/Module** | Shifts |
| **Related commit** | `493bcb2`, `bfad2d0` |
| **Priority** | High |
| **Type** | Integration |
| **Preconditions** | Shifts assigned for today |

**Steps:**

1. Compare Doctors column to shifts admin view.

**Expected result:** Same doctors listed; in-progress status accurate.

---

### Edge & corner cases

#### EDGE-001 — Empty queue today

| Field | Value |
| ----- | ----- |
| **Area/Module** | Empty states |
| **Related commit** | `5aea90d` |
| **Priority** | Medium |
| **Type** | Edge |
| **Preconditions** | No appointments today |

**Steps:**

1. Open queue.

**Expected result:** Schedule empty state; Doctors may show shift staff; Checked in empty; stats show zeros.

---

#### EDGE-002 — Wait tier warning at 15 minutes

| Field | Value |
| ----- | ----- |
| **Area/Module** | Wait display |
| **Related commit** | `5aea90d` |
| **Priority** | Medium |
| **Type** | Edge |
| **Preconditions** | Checked-in 16 minutes ago |

**Steps:**

1. Observe checked-in row styling.

**Expected result:** Warning tier styling at ≥15m; critical at ≥30m.

---

#### EDGE-003 — Appointment without preferred doctor on shift

| Field | Value |
| ----- | ----- |
| **Area/Module** | Doctor display |
| **Related commit** | `493bcb2` |
| **Priority** | Medium |
| **Type** | Edge |
| **Preconditions** | Appointment with doctor not on today's shift |

**Steps:**

1. View schedule doctor column.

**Expected result:** Shows assigned name or "No preferred doctor" / shift fallback per `queueDoctorPresentation`.

---

#### EDGE-004 — Timezone boundary near midnight

| Field | Value |
| ----- | ----- |
| **Area/Module** | Today range |
| **Related commit** | `5aea90d` |
| **Priority** | High |
| **Type** | Edge |
| **Preconditions** | Org timezone UTC+3; test at 23:30 local |

**Steps:**

1. Load queue; verify appointment just after midnight local excluded/included correctly.

**Expected result:** `appointmentTodayRangeInTimezone` bounds match org calendar day.

---

#### EDGE-005 — Completed row shows time range

| Field | Value |
| ----- | ----- |
| **Area/Module** | Schedule display |
| **Related commit** | `e13d95e` |
| **Priority** | Low |
| **Type** | Edge |
| **Preconditions** | Completed appointment |

**Steps:**

1. View schedule row time column.

**Expected result:** Shows `start - end` range; row dimmed.

---

#### EDGE-006 — RPC failure shows retry on load

| Field | Value |
| ----- | ----- |
| **Area/Module** | Error handling |
| **Related commit** | `5aea90d` |
| **Priority** | High |
| **Type** | Edge |
| **Preconditions** | Network failure or RPC error |

**Steps:**

1. Open queue with list_appointments failing.

**Expected result:** Error text + Retry button; existing items preserved if any.

---

### Regression tests

#### REG-001 — Calendar still loads after queue provider shared

| Field | Value |
| ----- | ----- |
| **Area/Module** | Calendar |
| **Related commit** | `f79582d` |
| **Priority** | High |
| **Type** | Regression |
| **Preconditions** | Calendar route accessible |

**Steps:**

1. Open calendar; book and change status.

**Expected result:** Calendar unaffected; sibling appointments fallback when queue empty.

---

#### REG-002 — Shell settings nav not highlighted

| Field | Value |
| ----- | ----- |
| **Area/Module** | Shell |
| **Related commit** | `82b1b0f` |
| **Priority** | Medium |
| **Type** | Regression |
| **Preconditions** | Authenticated shell |

**Steps:**

1. Navigate to Settings.

**Expected result:** No appointments/dashboard nav item selected.

---

#### REG-003 — Dashboard without showcase cards

| Field | Value |
| ----- | ----- |
| **Area/Module** | Dashboard |
| **Related commit** | `5ab6401` |
| **Priority** | Low |
| **Type** | Regression |
| **Preconditions** | Home route |

**Steps:**

1. Open dashboard.

**Expected result:** No notched card demo clutter; normal dashboard content.

---

#### REG-004 — Theme showcase slider

| Field | Value |
| ----- | ----- |
| **Area/Module** | Theme showcase |
| **Related commit** | `3125242` |
| **Priority** | Low |
| **Type** | Regression |
| **Preconditions** | Dev theme route |

**Steps:**

1. Adjust slider control.

**Expected result:** No assertion/overflow errors.

---

#### REG-005 — Detail status actions from appointment detail page

| Field | Value |
| ----- | ----- |
| **Area/Module** | Appointment detail |
| **Related commit** | `f79582d` |
| **Priority** | High |
| **Type** | Regression |
| **Preconditions** | Appointment detail open |

**Steps:**

1. Advance status using detail page actions (not queue).

**Expected result:** Same rules: doctor picker, one-in-progress block, day rules.

---

### User abuse tests

#### ABUSE-001 — Double tap Start in journey dialog

| Field | Value |
| ----- | ----- |
| **Area/Module** | Status actions |
| **Related commit** | `f56267a` |
| **Priority** | High |
| **Type** | User abuse |
| **Preconditions** | Checked-in appointment ready to start |

**Steps:**

1. Rapidly double-tap Start.

**Expected result:** Single RPC; busy state blocks second action; no duplicate in_progress.

---

#### ABUSE-002 — Rapid open/close journey dialog

| Field | Value |
| ----- | ----- |
| **Area/Module** | Dialog |
| **Related commit** | `0d0b25b` |
| **Priority** | Medium |
| **Type** | User abuse |
| **Preconditions** | Queue with appointments |

**Steps:**

1. Open and close dialog quickly on multiple rows.

**Expected result:** No exception; detail provider cancels cleanly.

---

#### ABUSE-003 — Navigate away during status RPC

| Field | Value |
| ----- | ----- |
| **Area/Module** | Navigation |
| **Related commit** | `4bf78e6` |
| **Priority** | High |
| **Type** | User abuse |
| **Preconditions** | Slow network |

**Steps:**

1. Tap Confirm; immediately navigate to Calendar.

**Expected result:** RPC completes or fails safely; no crash; queue refreshes on return.

---

#### ABUSE-004 — Resize window during scroll animation

| Field | Value |
| ----- | ----- |
| **Area/Module** | Layout |
| **Related commit** | `da5eb34` |
| **Priority** | Medium |
| **Type** | User abuse |
| **Preconditions** | Queue with scroll target animation active |

**Steps:**

1. Tap checked-in patient; drag window width across 1100px breakpoint during flash.

**Expected result:** No nested scroll trap; layout settles without exception.

---

#### ABUSE-005 — Dismiss doctor picker

| Field | Value |
| ----- | ----- |
| **Area/Module** | Doctor picker |
| **Related commit** | `5176980` |
| **Priority** | Medium |
| **Type** | User abuse |
| **Preconditions** | Start requires picker (`barrierDismissible: false`) |

**Steps:**

1. Attempt back gesture / escape without selecting doctor.

**Expected result:** Status unchanged; no partial doctor assign.

---

#### ABUSE-006 — Spam Retry on load error

| Field | Value |
| ----- | ----- |
| **Area/Module** | Error UI |
| **Related commit** | `5aea90d` |
| **Priority** | Low |
| **Type** | User abuse |
| **Preconditions** | Persistent RPC failure |

**Steps:**

1. Tap Retry repeatedly.

**Expected result:** Concurrent refresh guarded; no duplicate subscriptions.

---

## Verification commands

Apply migrations (local Supabase):

```bash
cd backend && supabase db reset   # or migration up through 20260627120000
```

Backend SQL tests (includes timestamp and status transitions):

```bash
cd backend && psql "$DATABASE_URL" -f tests/appointment_management_crud.sql
```

Queue unit tests:

```bash
cd frontend && flutter test \
  test/unit/appointments/appointment_queue_display_test.dart \
  test/unit/appointments/appointment_queue_provider_test.dart \
  test/unit/appointments/appointment_queue_shift_doctors_test.dart \
  test/unit/appointments/appointment_queue_start_doctor_test.dart \
  test/unit/appointments/appointment_queue_realtime_apply_test.dart \
  test/unit/appointments/appointment_status_transitions_test.dart \
  test/widget/appointments/queue_shift_doctor_picker_dialog_test.dart
```

Notched card tests:

```bash
cd frontend && flutter test \
  test/widget/core/ui/app_notched_card_test.dart \
  test/unit/core/ui/notched_card_path_test.dart
```

Shell nav badge:

```bash
cd frontend && flutter test test/widget/shell/shell_nav_single_item_test.dart
```

Full appointments unit suite (regression):

```bash
cd frontend && flutter test test/unit/appointments/ --concurrency 1
```

---

## Coverage matrix

| Change area | Automated coverage | Manual only | Gap |
| ----------- | ------------------ | ----------- | --- |
| Queue display/partition/stats | Yes (`appointment_queue_display_test`) | Trend comparison with real branch schedule | Silent comparison failure |
| Queue provider fetch/refresh | Partial (`appointment_queue_provider_test`) | Route-focus refresh, comparison RPC | No degraded realtime state |
| One-in-progress logic | Yes (unit + SQL) | Concurrent two-tab Start | — |
| Doctor picker dialog | Yes (widget) | Full Start integration | — |
| Shift doctor lookup | Yes (unit) | Real shift data alignment | Name normalization edge cases |
| AppNotchedCard | Yes (widget + path unit) | Visual parity vs reference PNG | Golden tests deferred |
| Queue page layout | No | FE-001–003, ABUSE-004 | **No page widget tests** |
| Status journey dialog | No | FUNC-004–010 | **No dialog widget tests** |
| Schedule/session/waiting columns | No | FE-005–007 | **No column widget tests** |
| Realtime live updates | Partial (apply unit) | INT-001–002 | Degraded UI not implemented |
| Backend migrations | Partial (`appointment_management_crud.sql`) | BE-003 concurrent | Dedicated concurrency SQL |
| Shell header/profile/settings | Partial (shell widget tests) | d3b5153 layout bleed | Cross-page visual |
| Nav badge count | Partial (shell_nav test) | FE-008 live update | Provider warm-up lag |
