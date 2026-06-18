import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/features/appointments/data/appointment_repository.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_calendar_period.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_list_item.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';
import 'package:ai_clinic/features/settings/domain/branch_list_filter.dart';
import 'package:ai_clinic/features/settings/domain/branch_list_item.dart';
import 'package:ai_clinic/features/settings/domain/staff_list_filter.dart';
import 'package:ai_clinic/features/settings/domain/staff_list_item.dart';
import 'package:ai_clinic/features/settings/domain/usecases/settings_use_case_providers.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';

export 'package:ai_clinic/features/appointments/domain/appointment_calendar_period.dart';

@immutable
class AppointmentCalendarState {
  const AppointmentCalendarState({
    required this.mode,
    required this.focusDate,
    required this.items,
    this.selectedBranchId,
    this.selectedDoctorId,
    this.selectedStatuses = const {},
    this.loading = false,
    this.error,
  });

  final AppointmentCalendarMode mode;
  final DateTime focusDate;
  final List<AppointmentListItem> items;
  final String? selectedBranchId;
  final String? selectedDoctorId;
  final Set<AppointmentStatus> selectedStatuses;
  final bool loading;
  final String? error;

  AppointmentCalendarState copyWith({
    AppointmentCalendarMode? mode,
    DateTime? focusDate,
    List<AppointmentListItem>? items,
    Object? selectedBranchId = _sentinel,
    Object? selectedDoctorId = _sentinel,
    Set<AppointmentStatus>? selectedStatuses,
    bool? loading,
    Object? error = _sentinel,
  }) {
    return AppointmentCalendarState(
      mode: mode ?? this.mode,
      focusDate: focusDate ?? this.focusDate,
      items: items ?? this.items,
      selectedBranchId: identical(selectedBranchId, _sentinel) ? this.selectedBranchId : selectedBranchId as String?,
      selectedDoctorId: identical(selectedDoctorId, _sentinel) ? this.selectedDoctorId : selectedDoctorId as String?,
      selectedStatuses: selectedStatuses ?? this.selectedStatuses,
      loading: loading ?? this.loading,
      error: identical(error, _sentinel) ? this.error : error as String?,
    );
  }

  /// Whether applied filters differ from the session's initial branch-only view.
  bool hasActiveFilters({required String? initialBranchId}) {
    final baselineBranch = AppointmentCalendarController._normalizedOrNull(initialBranchId);
    final doctorFiltered = selectedDoctorId != null && selectedDoctorId!.isNotEmpty;
    final branchFiltered = selectedBranchId != baselineBranch;
    final statusFiltered = selectedStatuses.isNotEmpty;
    return doctorFiltered || branchFiltered || statusFiltered;
  }
}

const _sentinel = Object();

class AppointmentCalendarController extends Notifier<AppointmentCalendarState> {
  @override
  AppointmentCalendarState build() {
    final today = DateTime.now();
    final initialBranchId = _normalizedOrNull(ref.read(authSessionProvider).context?.activeBranchId);

    ref.listen<AuthSessionState>(authSessionProvider, (previous, next) {
      final prevBranch = previous?.context?.activeBranchId;
      final nextBranch = next.context?.activeBranchId;
      if (prevBranch != nextBranch) {
        unawaited(clearFilters());
      }
    });

    final initial = AppointmentCalendarState(
      mode: AppointmentCalendarMode.week,
      focusDate: DateTime(today.year, today.month, today.day),
      items: const [],
      selectedBranchId: initialBranchId,
      loading: true,
    );

    Future.microtask(refresh);
    return initial;
  }

  Future<void> refresh() async {
    final branchId = _normalizedOrNull(state.selectedBranchId);
    if (branchId == null) {
      state = state.copyWith(
        loading: false,
        items: const [],
        error: 'Select an active branch before viewing the calendar.',
      );
      return;
    }

    state = state.copyWith(loading: true, error: null);
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

  Future<void> setMode(AppointmentCalendarMode mode) async {
    if (mode == state.mode) {
      return;
    }
    state = state.copyWith(mode: mode);
    await refresh();
  }

  Future<void> setFocusDate(DateTime date) async {
    final normalized = DateTime(date.year, date.month, date.day);
    if (normalized == state.focusDate) {
      return;
    }
    state = state.copyWith(focusDate: normalized);
    await refresh();
  }

  Future<void> goToToday() async {
    final today = DateTime.now();
    await setFocusDate(DateTime(today.year, today.month, today.day));
  }

  Future<void> previousPeriod() async {
    await setFocusDate(appointmentCalendarPreviousFocus(state.focusDate, state.mode));
  }

  Future<void> nextPeriod() async {
    await setFocusDate(appointmentCalendarNextFocus(state.focusDate, state.mode));
  }

  Future<void> applyFilters({String? branchId, String? doctorId, Set<AppointmentStatus>? statuses}) async {
    final normalizedBranch = _normalizedOrNull(branchId ?? state.selectedBranchId);
    final normalizedDoctor = (doctorId ?? state.selectedDoctorId)?.trim();
    final nextDoctor = (normalizedDoctor == null || normalizedDoctor.isEmpty) ? null : normalizedDoctor;
    final nextStatuses = statuses ?? state.selectedStatuses;
    final branchOrDoctorChanged = normalizedBranch != state.selectedBranchId || nextDoctor != state.selectedDoctorId;
    final statusesChanged = !setEquals(nextStatuses, state.selectedStatuses);
    if (!branchOrDoctorChanged && !statusesChanged) {
      return;
    }
    state = state.copyWith(
      selectedBranchId: normalizedBranch,
      selectedDoctorId: nextDoctor,
      selectedStatuses: nextStatuses,
    );
    if (branchOrDoctorChanged) {
      await refresh();
    }
  }

  Future<void> clearFilters() async {
    final initialBranchId = _normalizedOrNull(ref.read(authSessionProvider).context?.activeBranchId);
    if (initialBranchId == state.selectedBranchId && state.selectedDoctorId == null && state.selectedStatuses.isEmpty) {
      return;
    }
    state = state.copyWith(selectedBranchId: initialBranchId, selectedDoctorId: null, selectedStatuses: const {});
    await refresh();
  }

  /// Updates only the branch filter while preserving the current doctor filter.
  Future<void> setBranchFilter(String? branchId) async {
    await applyFilters(branchId: branchId, doctorId: state.selectedDoctorId, statuses: state.selectedStatuses);
  }

  /// Updates only the doctor filter while preserving the current branch filter.
  Future<void> setDoctorFilter(String? doctorId) async {
    await applyFilters(branchId: state.selectedBranchId, doctorId: doctorId, statuses: state.selectedStatuses);
  }

  static String? _normalizedOrNull(String? value) {
    final normalized = value?.trim();
    if (normalized == null || normalized.isEmpty) {
      return null;
    }
    return normalized;
  }
}

final appointmentCalendarProvider = NotifierProvider<AppointmentCalendarController, AppointmentCalendarState>(
  AppointmentCalendarController.new,
);

final appointmentCalendarBranchesProvider = FutureProvider.autoDispose<List<BranchListItem>>((ref) async {
  final auth = ref.watch(authSessionProvider).context;
  final orgId = auth?.organizationId;
  if (orgId == null || orgId.trim().isEmpty) {
    return const [];
  }
  return ref.read(listBranchesUseCaseProvider)(organizationId: orgId, filter: BranchListFilter.active);
});

final appointmentCalendarDoctorsProvider = FutureProvider.autoDispose<List<StaffListItem>>((ref) async {
  final staff = await ref.read(listStaffUseCaseProvider)(filter: StaffListFilter.active);
  return staff.where((member) => member.role == StaffRole.doctor).toList(growable: false)
    ..sort(StaffListItem.compareByFullName);
});
