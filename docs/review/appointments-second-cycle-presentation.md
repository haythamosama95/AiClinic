# Appointments Feature — Second Cycle Presentation Layer Review

**Scope:** `frontend/lib/features/appointments/presentation/` (providers + navigation), integration points (`authenticated_shell.dart`, `setup_notifier.dart`, `patient_detail_history_provider.dart`), and presentation-related tests under `frontend/test/**/appointments/**`  
**Review date:** 2026-07-05  
**Prior review:** `appointments-feature-code-review.md` (first cycle)  
**Focus:** Riverpod lifecycle, async races, CA boundaries, realtime vs refresh consistency, cross-provider invalidation, error/loading edge cases

---

## Executive Summary

The presentation layer is **structurally sound for a provider-only scaffold** — session-scope listening via `AppointmentFetchScope`, realtime unsubscribe on dispose, optimistic `patchAppointmentStatus`, and calendar filter state machine are reasonable foundations. However, **none of the first-cycle critical async correctness issues have been addressed**. Both queue and calendar `refresh()` remain unguarded against overlapping in-flight work. Realtime incremental patches can be overwritten by stale full refreshes, and branch switches can briefly or persistently show the wrong branch's queue.

Clean Architecture violations persist: all appointment providers and the patient-history integration call `appointmentRepositoryProvider` directly; the shift lookup provider also calls `shiftRepositoryProvider` from the data layer. Cross-surface invalidation omits detail, patient-upcoming, and calendar filter dropdown providers.

| Severity | Count |
|----------|-------|
| Critical | 4 |
| High | 8 |
| Medium | 7 |

**First-cycle §1.2 (stale data races): CONFIRMED STILL PRESENT** — no `_fetchGeneration`, mutex, or single-flight guard exists in either provider.

---

## Critical Issues

### C-1. Unserialized concurrent `refresh()` — first-cycle §1.2 still present

| Field | Detail |
|-------|--------|
| **Severity** | Critical |
| **Files** | `appointment_queue_provider.dart`, `appointment_calendar_provider.dart` |
| **Evidence** | Neither controller tracks in-flight generation. `refresh()` unconditionally assigns `state` when the awaited RPC completes. Triggers overlap from: `Future.microtask` on build, `ref.listen` on `authSessionProvider` (`unawaited(refresh())`), realtime fallback (`unawaited(refresh())` on insert/unknown update), calendar navigation (`setFocusDate`, `setMode`, `applyFilters`, `clearFilters`). Grep for `_fetchGeneration`, `singleFlight`, `inFlight` across the feature returns **zero matches**. |
| **Why** | Last-writer-wins with no scope or generation check. A slow fetch started before a branch/timezone/filter change can complete after a faster, newer fetch and overwrite correct state. |
| **Impact** | Intermittent wrong-branch queue, missing check-ins, calendar showing superseded rows — hard to reproduce, data-corruption class defect. |
| **Recommended solution** | Add monotonic `_fetchGeneration` incremented at the start of each `refresh()`. Capture `branchId`, `todayRange`/`focusDate+mode`, and generation before `await`; discard results when any differ at completion. Coalesce realtime-triggered refreshes (200–500 ms debounce). |

```117:145:frontend/lib/features/appointments/presentation/providers/appointment_queue_provider.dart
  Future<void> refresh() async {
    final branchId = _branchId;
    // ...
    try {
      final range = _todayRange;
      final repository = ref.read(appointmentRepositoryProvider);
      final items = await repository.listAppointments(branchId: branchId, from: range.from, to: range.to);
      final comparison = await _fetchComparisonItems(branchId: branchId, repository: repository);
      state = state.copyWith(
        loading: false,
        items: sortAppointmentsByStartTime(items),
        // ...
      );
```

```110:130:frontend/lib/features/appointments/presentation/providers/appointment_calendar_provider.dart
  Future<void> refresh() async {
    final branchId = _normalizedOrNull(state.selectedBranchId);
    // ...
    try {
      final bounds = appointmentCalendarFetchBounds(state.focusDate, state.mode);
      final items = await ref
          .read(appointmentRepositoryProvider)
          .listAppointments(branchId: branchId, from: bounds.$1, to: bounds.$2, doctorId: state.selectedDoctorId);
      state = state.copyWith(loading: false, items: items, error: null);
    } catch (_) {
      state = state.copyWith(loading: false, items: const [], error: 'Could not load appointments. Please retry.');
    }
  }
```

---

### C-2. Stale in-flight refresh after branch switch can repopulate wrong-branch queue

| Field | Detail |
|-------|--------|
| **Severity** | Critical |
| **Files** | `appointment_queue_provider.dart` (auth listener + `refresh`) |
| **Evidence** | On `activeBranchId` change, listener calls `unawaited(refresh())` **before** clearing items, then synchronously clears state and resubscribes realtime. Any `refresh()` already in flight for the **previous** branch has no cancellation or branch guard; when it completes it writes `state.items` unconditionally. |
| **Why** | Branch switch does not invalidate or ignore prior async work. Clearing items synchronously does not stop an earlier `listAppointments` from completing. |
| **Impact** | User switches from Branch A → B; queue briefly clears then shows Branch A appointments while session context says Branch B. Status actions and realtime subscription target B — severe consistency break. |
| **Recommended solution** | Same generation guard as C-1, keyed on `branchId`. On branch change: increment generation, clear items, set `loading: true`, then start a single guarded refresh. Never apply refresh results when `branchId != _branchId`. |

```76:93:frontend/lib/features/appointments/presentation/providers/appointment_queue_provider.dart
    ref.listen<AuthSessionState>(authSessionProvider, (previous, next) {
      final prevScope = AppointmentFetchScope.fromContext(previous?.context);
      final nextScope = AppointmentFetchScope.fromContext(next.context);
      if (prevScope == nextScope) {
        return;
      }

      unawaited(refresh());
      if (prevScope.activeBranchId != nextScope.activeBranchId) {
        state = state.copyWith(
          items: const [],
          comparisonItems: null,
          comparisonNow: null,
          comparisonUnavailable: false,
          error: null,
        );
        _subscribeRealtime();
      }
    });
```

---

### C-3. Realtime incremental patch vs in-flight full refresh race

| Field | Detail |
|-------|--------|
| **Severity** | Critical |
| **Files** | `appointment_queue_provider.dart` (`_onRealtimeChange`, `refresh`, `patchAppointmentStatus`) |
| **Evidence** | When `applyAppointmentQueueRealtimeChange` returns `true`, provider updates `state.items` in place. When it returns `false` (insert, unknown id, malformed payload), `unawaited(refresh())` runs with no coordination. A concurrent `refresh()` or an older refresh completing after a successful patch overwrites incremental updates. `patchAppointmentStatus` (optimistic RPC path) has the same vulnerability against overlapping `refresh()`. |
| **Why** | Two independent mutation paths (surgical patch + full list replace) share `state.items` with no versioning. |
| **Impact** | Check-in/status change visible via realtime or optimistic patch reverts to stale row until next manual refresh; nav badge count (`appointmentQueueCheckedInCountProvider`) becomes wrong. |
| **Recommended solution** | Unified list version counter incremented on patch/realtime apply; refresh compares server `updated_at` max or discards if version advanced during fetch. Alternatively, pause realtime-applied state during refresh and merge by id. |

```269:280:frontend/lib/features/appointments/presentation/providers/appointment_queue_provider.dart
  void _onRealtimeChange(AppointmentQueueRealtimeChange change) {
    if (!_realtimeListening) {
      return;
    }
    final items = [...state.items];
    final applied = applyAppointmentQueueRealtimeChange(items: items, change: change, todayRange: _todayRange);
    if (applied) {
      state = state.copyWith(items: sortAppointmentsByStartTime(items));
      return;
    }
    unawaited(refresh());
  }
```

---

### C-4. Presentation bypasses domain — direct data-layer repository access (first-cycle §1.3 still present)

| Field | Detail |
|-------|--------|
| **Severity** | Critical |
| **Files** | `appointment_queue_provider.dart`, `appointment_calendar_provider.dart`, `appointment_detail_provider.dart`, `appointment_queue_shift_provider.dart`, `patient_detail_history_provider.dart` |
| **Evidence** | All call `ref.read(appointmentRepositoryProvider)` or `ref.read(shiftRepositoryProvider)` directly. No `domain/repositories/appointment_repository.dart` interface; no use-case providers. Auth feature uses `signInUseCaseProvider` etc. |
| **Why** | Presentation depends on concrete Supabase-shaped infrastructure; mutation orchestration (status → queue patch → calendar invalidate → error mapping) cannot live in testable domain ports. |
| **Impact** | Providers untestable without RPC fakes; violates dependency rule; future UI will embed orchestration in widgets/providers ad hoc. |
| **Recommended solution** | Add domain repository interface + use cases (`ListAppointments`, `GetAppointment`, `UpdateAppointmentStatus`, etc.) and `appointment_use_case_providers.dart` mirroring auth. Presentation reads use-case providers only. |

```134:136:frontend/lib/features/appointments/presentation/providers/appointment_queue_provider.dart
      final repository = ref.read(appointmentRepositoryProvider);
      final items = await repository.listAppointments(branchId: branchId, from: range.from, to: range.to);
```

```36:37:frontend/lib/features/appointments/presentation/providers/appointment_queue_shift_provider.dart
  final shiftRepository = ref.read(shiftRepositoryProvider);
  final shifts = await shiftRepository.listShifts(branchId: scope.branchId, dateFrom: today, dateTo: today);
```

---

## High Priority Issues

### H-1. `patchAppointmentStatus` inconsistent with realtime apply for terminal statuses

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **Files** | `appointment_queue_provider.dart`; `appointment_queue_realtime_apply.dart` |
| **Evidence** | Realtime `_applyUpdate` removes rows when `status == cancelled` or `is_deleted`. `patchAppointmentStatus` only `copyWith`s status — cancelled appointments **remain in `items`**. No caller removes the row after cancel RPC success. |
| **Why** | Two code paths mutate the same cache with different lifecycle rules. |
| **Impact** | After cancel via RPC + optimistic patch, queue shows cancelled row (dimmed in schedule column per domain) while realtime path would remove it; stats/partition counts diverge between surfaces and between users on realtime vs RPC path. |
| **Recommended solution** | Extract shared `applyQueueItemMutation` in domain; remove cancelled/deleted rows in `patchAppointmentStatus` when `newStatus.isTerminal` and product expects removal. Align with `AppointmentQueueDisplay.partition` expectations. |

```236:266:frontend/lib/features/appointments/presentation/providers/appointment_queue_provider.dart
  void patchAppointmentStatus({
    required String appointmentId,
    required AppointmentStatus newStatus,
    // ...
  }) {
    final index = state.items.indexWhere((item) => item.id == appointmentId);
    if (index < 0) {
      return;
    }
    // ... copyWith only — never removes cancelled/no-show rows
    state = state.copyWith(items: sortAppointmentsByStartTime(items));
  }
```

```67:68:frontend/lib/features/appointments/data/appointment_queue_realtime_apply.dart
  if (isDeleted || status == AppointmentStatus.cancelled) {
    return _removeByRecord(items, record);
```

---

### H-2. Cross-provider invalidation incomplete

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **Files** | `appointment_surface_invalidation.dart`, `setup_notifier.dart`, `dev_clinic_seed_notifier.dart` |
| **Evidence** | `invalidateAppointmentSurfaceProviders` invalidates only `appointmentQueueProvider`, `appointmentCalendarProvider`, `appointmentQueueShiftDoctorLookupProvider`. **Not** invalidated: `appointmentDetailProvider` (family), `patientUpcomingAppointmentsProvider`, `appointmentCalendarBranchesProvider`, `appointmentCalendarDoctorsProvider`. Called from setup finish/reset and dev seed — no tests. |
| **Why** | Family/autoDispose providers retain cached async results until explicitly invalidated or disposed. |
| **Impact** | After clinic reset or re-seed, open detail view and patient upcoming tab can show pre-reset appointments; calendar filter dropdowns may list deleted branches/staff. |
| **Recommended solution** | Extend helper to `ref.invalidate(appointmentDetailProvider)`, `ref.invalidate(patientUpcomingAppointmentsProvider)`, branches/doctors providers. Document call sites for future mutation flows (create/cancel/reschedule). Add integration test. |

```7:12:frontend/lib/features/appointments/presentation/providers/appointment_surface_invalidation.dart
void invalidateAppointmentSurfaceProviders(Ref ref) {
  ref.invalidate(appointmentQueueProvider);
  ref.invalidate(appointmentCalendarProvider);
  ref.invalidate(appointmentQueueShiftDoctorLookupProvider);
}
```

---

### H-3. `appointment_detail_provider` — `StateError` on deny + stale cache after invalidation gap

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **Files** | `appointment_detail_provider.dart`, `appointment_surface_invalidation.dart` |
| **Evidence** | Permission denial throws `StateError('You do not have permission...')`. Provider not included in invalidation helper. Direct `appointmentRepositoryProvider.getAppointment` call. **Zero dedicated tests** in `frontend/test/**/appointments/**`. |
| **Why** | `StateError` surfaces as generic `AsyncError` without curated copy; family cache survives data wipe when invalidation omits it. |
| **Impact** | Forbidden users see programmer-style error; post-reset detail route shows ghost appointments until manual navigation away. |
| **Recommended solution** | Throw typed `AppointmentAccessDenied` mapped to empty/forbidden UI. Add to invalidation helper. Add provider unit tests for deny + success paths. |

```9:18:frontend/lib/features/appointments/presentation/providers/appointment_detail_provider.dart
final appointmentDetailProvider = FutureProvider.autoDispose.family<AppointmentDetail, String>((
  ref,
  appointmentId,
) async {
  final canAccess = ref.watch(authSessionProvider.select(AuthRouteGuard.canAccessAppointmentHub));
  if (!canAccess) {
    throw StateError('You do not have permission to view this appointment.');
  }

  return ref.read(appointmentRepositoryProvider).getAppointment(appointmentId: appointmentId);
});
```

---

### H-4. Shift doctor lookup — business logic and triple RPC in presentation

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **Files** | `appointment_queue_shift_provider.dart` |
| **Evidence** | 80-line `_resolveQueueShiftDoctors` duplicates domain `AppointmentQueueShiftDoctorLookup` resolution (branch staff → assignee name match → org fallback). Provider performs `listShifts` + `listActiveStaffForBranch` + `listStaff` per rebuild. Calls `shiftRepositoryProvider` (data layer) directly. **No tests**. |
| **Why** | Orchestration and doctor-set rules belong in domain use case, not `FutureProvider` body. |
| **Impact** | Untested name-matching fallback; expensive triple-fetch on every queue card rebuild; logic drift from domain helper. |
| **Recommended solution** | Extract `ResolveQueueShiftDoctorsUseCase`; provider maps result → `AppointmentQueueShiftDoctorLookup`. Cache per `(branchId, orgDate)`. |

---

### H-5. Global non–auto-dispose queue + eager shell warm

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **Files** | `appointment_queue_provider.dart`, `authenticated_shell.dart` |
| **Evidence** | `appointmentQueueProvider` is `NotifierProvider` without `autoDispose`. Shell watches `appointmentQueueShellWarmProvider` whenever `canAccessAppointments()` — not gated on `!setupRequired` or `activeBranchId != null`. Warm triggers 2× `list_appointments` + realtime subscription for entire authenticated session. |
| **Why** | Provider lifetime tied to first permission check, not queue route visibility. |
| **Impact** | Persistent Supabase realtime channel, background RPC load on every shell page, memory retained for queue + comparison data. |
| **Recommended solution** | Split badge-only lightweight provider; gate warm on `!setupRequired && activeBranchId != null`; consider `autoDispose` with `ref.keepAlive()` only while queue route focused. |

```23:27:frontend/lib/app/shell/authenticated_shell.dart
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(permissionServiceProvider).canAccessAppointments()) {
      ref.watch(appointmentQueueShellWarmProvider);
    }
```

```283:285:frontend/lib/features/appointments/presentation/providers/appointment_queue_provider.dart
final appointmentQueueProvider = NotifierProvider<AppointmentQueueController, AppointmentQueueState>(
  AppointmentQueueController.new,
);
```

---

### H-6. Realtime insert forces full refresh — amplifies race (first-cycle §1.4)

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **Files** | `appointment_queue_provider.dart`; `appointment_queue_realtime_apply.dart` |
| **Evidence** | `PostgresChangeEvent.insert` returns `false`; provider calls `unawaited(refresh())` — 2× `list_appointments` per insert. Active booking generates overlapping refreshes with no debounce. |
| **Why** | No incremental insert handler; each insert is a full reload trigger. |
| **Impact** | RPC storm under load; compounds C-1/C-3 races; nav badge flicker. |
| **Recommended solution** | Build `AppointmentListItem` from `newRecord` when payload complete; debounce refresh fallback. |

```29:30:frontend/lib/features/appointments/data/appointment_queue_realtime_apply.dart
    case PostgresChangeEvent.insert:
      return false;
```

---

### H-7. Queue branch-switch loading UX and ordering

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **Files** | `appointment_queue_provider.dart` |
| **Evidence** | On branch change, items cleared but `loading` not set `true` (refresh only sets loading when `state.items.isEmpty`, but clear happens after `unawaited(refresh())` may have already passed that check with old non-empty items). Listener order: `refresh()` → clear → resubscribe. |
| **Why** | Race between loading flag logic and synchronous clear. |
| **Impact** | Flash of empty non-loading queue during branch switch; user may think branch has no patients. |
| **Recommended solution** | On branch change: set `loading: true`, clear items, increment generation, then refresh. |

---

### H-8. Calendar `refresh()` swallows exceptions without logging

| Field | Detail |
|-------|--------|
| **Severity** | High |
| **Files** | `appointment_calendar_provider.dart` |
| **Evidence** | `catch (_)` discards exception; generic user string only. Queue logs via `debugPrint`. No `AppLog`. Not tested. |
| **Why** | Production calendar failures invisible in structured logs. |
| **Impact** | RPC misconfiguration, parse errors, and network faults indistinguishable; extended MTTR. |
| **Recommended solution** | `catch (error, stack) { AppLog.warning(...); }` and align error copy with queue via `appointmentMessageForRpc` where applicable. |

```128:130:frontend/lib/features/appointments/presentation/providers/appointment_calendar_provider.dart
    } catch (_) {
      state = state.copyWith(loading: false, items: const [], error: 'Could not load appointments. Please retry.');
    }
```

---

## Medium Priority Issues

### M-1. No dispose guard on async `refresh()` completion

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **Files** | `appointment_queue_provider.dart`, `appointment_calendar_provider.dart` |
| **Evidence** | `ref.onDispose(_unsubscribeRealtime)` cleans up realtime, but in-flight `refresh()` has no `if (!ref.mounted)` / generation check before `state =`. `Future.microtask(refresh)` in `build()` can theoretically complete after rapid provider teardown (edge case in tests or hot restart). |
| **Why** | Async gap between start and state write. |
| **Impact** | Rare "set state after dispose" warnings; test flakiness. |
| **Recommended solution** | Check `ref.mounted` (Riverpod 2.5+) or generation token before assigning state after await. |

---

### M-2. Calendar stores unfiltered `items` — status filter is client-only contract

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **Files** | `appointment_calendar_provider.dart` |
| **Evidence** | `applyFilters(statuses: …)` updates `selectedStatuses` without refetch (test explicitly asserts no extra RPC). `refresh()` never passes statuses to `listAppointments`. Future UI binding `state.items` directly shows unfiltered data including cancelled/no-show. |
| **Why** | Implicit contract that UI must call `filterVisibleAppointments` — not enforced in state. |
| **Impact** | Wrong appointments visible if UI omits domain filter; unnecessary wire payload for month view. |
| **Recommended solution** | Expose `filteredItems` computed getter on state, or pass `selectedStatuses` to RPC when non-empty. |

---

### M-3. `patientUpcomingAppointmentsProvider` omitted from invalidation and untested integration

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **Files** | `patient_detail_history_provider.dart`, `appointment_surface_invalidation.dart` |
| **Evidence** | Cross-feature provider calls `appointmentRepositoryProvider` directly. Tested only for sort/params in patients test file — not invalidation after setup reset, not coordination with queue patch. |
| **Why** | Separate cache lifecycle from appointment surfaces. |
| **Impact** | Patient detail "upcoming" tab stale after appointment cancel/reschedule elsewhere until provider disposed. |
| **Recommended solution** | Include in invalidation helper; invalidate family instance on mutation; add invalidation integration test. |

---

### M-4. Presentation test gaps for race, branch switch, and untested providers

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **Files** | `appointment_queue_provider_test.dart`, `appointment_calendar_provider_test.dart`; missing tests for `appointment_detail_provider`, `appointment_queue_shift_provider`, `appointment_surface_invalidation.dart`, `appointment_detail_route_extra.dart` |
| **Evidence** | Queue tests cover patch, degraded realtime, comparison failure, shell warm, org timezone refresh. **Not tested:** branch switch clear/resubscribe, concurrent refresh race (TG-28), realtime insert → refresh, `refresh()` error catch, no-branch error. Calendar tests omit error catch, branches/doctors providers. 3/6 presentation files have zero tests. |
| **Why** | Critical paths identified in first cycle remain unverified. |
| **Impact** | Regressions in race fixes or invalidation will not be caught in CI. |
| **Recommended solution** | Add fake realtime client test for insert → double RPC; delayed RPC test proving stale completion discarded after generation guard; branch-switch test; detail/shift/invalidation unit tests. |

---

### M-5. Queue `refresh()` error path preserves stale items from prior branch

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **Files** | `appointment_queue_provider.dart` |
| **Evidence** | On catch, `loading: false` and error string set, but **`items` not cleared**. Combined with C-2, failed refresh after branch switch can leave wrong-branch items visible alongside error banner (or no error if stale success completed last). |
| **Why** | Error handler assumes items still valid. |
| **Impact** | Misleading queue content mixed with error state. |
| **Recommended solution** | On error after branch/scope change, clear items. On error generally, consider keeping items with banner only when generation matches. |

```146:149:frontend/lib/features/appointments/presentation/providers/appointment_queue_provider.dart
    } catch (error) {
      state = state.copyWith(loading: false, error: 'Unable to load today\'s queue. Try again.');
      debugPrint('AppointmentQueueController.refresh failed: $error');
    }
```

---

### M-6. `AppointmentDetailRouteExtra` preview vs `appointmentDetailProvider` — no cache coordination

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **Files** | `appointment_detail_route_extra.dart`, `appointment_detail_provider.dart` |
| **Evidence** | Route extra carries `AppointmentListItem? preview` for instant hydration from calendar. Detail provider always refetches via `getAppointment` with no seed-from-preview API. If family cache holds stale detail, navigation with fresh preview shows conflicting data until fetch completes. **No tests** for `fromExtra` legacy path. |
| **Why** | Two independent data sources for same screen without merge policy. |
| **Impact** | Brief UI flicker or wrong status/doctor if list row newer than cached detail. |
| **Recommended solution** | Document contract: invalidate detail family on list mutations; or accept preview as initial `AsyncData` until RPC returns. Test `fromExtra` for legacy `AppointmentListItem` extra. |

---

### M-7. Queue comparison fetch uses presentation-layer branch schedule resolution

| Field | Detail |
|-------|--------|
| **Severity** | Medium |
| **Files** | `appointment_queue_provider.dart` |
| **Evidence** | `_resolveBranchSchedule` lists **all org branches** via `listBranchesUseCaseProvider` to find one `workingSchedule`. Previous-working-day math lives in provider `_fetchComparisonItems`. |
| **Why** | Business orchestration in presentation; over-fetches branch list for trend stats. |
| **Impact** | Extra RPC on every queue refresh; logic untestable at provider boundary without heavy overrides. |
| **Recommended solution** | `GetQueueComparisonAppointmentsUseCase` with cached branch schedule port. |

```180:199:frontend/lib/features/appointments/presentation/providers/appointment_queue_provider.dart
  Future<BranchWorkingSchedule> _resolveBranchSchedule() async {
    // ...
        final branches = await ref.read(listBranchesUseCaseProvider)(
          organizationId: orgId,
          filter: BranchListFilter.active,
        );
        for (final branch in branches) {
          if (branch.id == branchId && branch.workingSchedule != null) {
            return branch.workingSchedule!;
          }
        }
```

---

## First-Cycle Verification Matrix

| First-cycle ID | Topic | Second-cycle status |
|----------------|-------|---------------------|
| §1.2 | Unserialized concurrent `refresh()` | **Still present** — C-1 |
| §1.3 | No use cases / direct repository | **Still present** — C-4 |
| §1.4 | Realtime insert → full refresh | **Still present** — H-6 |
| §2.7 | Realtime apply omits doctor/patient fields | Still in data layer; presentation inherits stale rows until refresh race resolves |
| §2.13 | Business logic in providers | **Still present** — H-4, M-7 |
| §2.16 | Detail `StateError` | **Still present** — H-3 |
| §3.13 | Incomplete invalidation | **Still present** — H-2 |
| §3.14 | Branch-switch loading gap | **Still present** — H-7 |
| §3.15 | Shell eager warm | **Still present** — H-5 |
| §3.18 | Queue branch/error/race tests missing | **Still present** — M-4 |
| TG-28 | Concurrent refresh race test | **Not added** |

---

## Positive Patterns (unchanged)

1. `ref.onDispose(_unsubscribeRealtime)` — realtime client cleaned up on provider dispose.
2. `AppointmentFetchScope` equality drives `ref.listen` — avoids redundant refresh on irrelevant session churn.
3. `patchAppointmentStatus` preserves server timestamps (BUG-001 regression test).
4. Calendar `clearFilters` on `activeBranchId` change resets doctor/status filters (CAL-B07 test).
5. `appointmentQueueCheckedInCountProvider` derivation keeps badge logic out of shell.

---

## Recommended Fix Order (presentation-only)

1. **C-1 + C-2 + C-3** — Single-flight refresh with generation/scope guards (blocks all other reliability work).
2. **H-1** — Align patch and realtime terminal-status handling.
3. **H-2 + H-3 + M-3** — Complete invalidation surface.
4. **H-6** — Incremental realtime insert + debounced refresh fallback.
5. **H-7 + M-5** — Branch-switch loading and error-state consistency.
6. **C-4 + H-4** — Use-case extraction (can parallelize with UI work once guards land).
7. **M-4** — Tests for races, branch switch, invalidation, detail, shift.

---

*Second-cycle presentation review — 2026-07-05.*
