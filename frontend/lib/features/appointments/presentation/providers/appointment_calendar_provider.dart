import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/features/appointments/data/appointment_repository.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_list_item.dart';

enum AppointmentCalendarMode { day, week }

@immutable
class AppointmentCalendarState {
  const AppointmentCalendarState({
    required this.mode,
    required this.focusDate,
    required this.items,
    this.selectedDoctorId,
    this.loading = false,
    this.error,
  });

  final AppointmentCalendarMode mode;
  final DateTime focusDate;
  final List<AppointmentListItem> items;
  final String? selectedDoctorId;
  final bool loading;
  final String? error;

  AppointmentCalendarState copyWith({
    AppointmentCalendarMode? mode,
    DateTime? focusDate,
    List<AppointmentListItem>? items,
    Object? selectedDoctorId = _sentinel,
    bool? loading,
    Object? error = _sentinel,
  }) {
    return AppointmentCalendarState(
      mode: mode ?? this.mode,
      focusDate: focusDate ?? this.focusDate,
      items: items ?? this.items,
      selectedDoctorId: identical(selectedDoctorId, _sentinel) ? this.selectedDoctorId : selectedDoctorId as String?,
      loading: loading ?? this.loading,
      error: identical(error, _sentinel) ? this.error : error as String?,
    );
  }
}

const _sentinel = Object();

class AppointmentCalendarController extends Notifier<AppointmentCalendarState> {
  @override
  AppointmentCalendarState build() {
    final today = DateTime.now();
    final initial = AppointmentCalendarState(
      mode: AppointmentCalendarMode.day,
      focusDate: DateTime(today.year, today.month, today.day),
      items: const [],
      loading: true,
    );
    Future<void>(refresh);
    return initial;
  }

  Future<void> refresh() async {
    final branchId = ref.read(authSessionProvider).context?.activeBranchId;
    if (branchId == null || branchId.trim().isEmpty) {
      state = state.copyWith(
        loading: false,
        items: const [],
        error: 'Select an active branch before viewing the calendar.',
      );
      return;
    }

    state = state.copyWith(loading: true, error: null);
    try {
      final bounds = _boundsFor(state.focusDate, state.mode);
      final items = await ref
          .read(appointmentRepositoryProvider)
          .listAppointments(branchId: branchId, from: bounds.$1, to: bounds.$2, doctorId: state.selectedDoctorId);
      state = state.copyWith(loading: false, items: items, error: null);
    } catch (error) {
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

  Future<void> previousPeriod() async {
    final delta = state.mode == AppointmentCalendarMode.day ? -1 : -7;
    await setFocusDate(state.focusDate.add(Duration(days: delta)));
  }

  Future<void> nextPeriod() async {
    final delta = state.mode == AppointmentCalendarMode.day ? 1 : 7;
    await setFocusDate(state.focusDate.add(Duration(days: delta)));
  }

  Future<void> setDoctorFilter(String? doctorId) async {
    final normalized = doctorId?.trim();
    state = state.copyWith(selectedDoctorId: (normalized == null || normalized.isEmpty) ? null : normalized);
    await refresh();
  }

  (DateTime, DateTime) _boundsFor(DateTime focusDate, AppointmentCalendarMode mode) {
    final dayStart = DateTime(focusDate.year, focusDate.month, focusDate.day);
    final start = mode == AppointmentCalendarMode.day
        ? dayStart
        : dayStart.subtract(Duration(days: dayStart.weekday - 1));
    final end = mode == AppointmentCalendarMode.day
        ? start.add(const Duration(days: 1))
        : start.add(const Duration(days: 7));
    return (start.toUtc(), end.toUtc());
  }
}

final appointmentCalendarProvider = NotifierProvider<AppointmentCalendarController, AppointmentCalendarState>(
  AppointmentCalendarController.new,
);
