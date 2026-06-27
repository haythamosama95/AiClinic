import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/features/appointments/data/appointment_queue_realtime.dart';
import 'package:ai_clinic/features/appointments/data/appointment_queue_realtime_apply.dart';
import 'package:ai_clinic/features/appointments/data/appointment_repository.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_branch_working_hours.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_fetch_scope.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_list_item.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_org_calendar.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_queue_display.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_today_range.dart';
import 'package:ai_clinic/features/settings/domain/branch_list_filter.dart';
import 'package:ai_clinic/features/settings/domain/branch_working_schedule.dart';
import 'package:ai_clinic/features/settings/domain/usecases/settings_use_case_providers.dart';

@immutable
class AppointmentQueueState {
  const AppointmentQueueState({
    required this.items,
    this.comparisonItems,
    this.comparisonNow,
    this.comparisonUnavailable = false,
    this.realtimeConnection,
    this.loading = false,
    this.error,
  });

  final List<AppointmentListItem> items;
  final List<AppointmentListItem>? comparisonItems;
  final DateTime? comparisonNow;
  final bool comparisonUnavailable;
  final AppointmentQueueRealtimeConnection? realtimeConnection;
  final bool loading;
  final String? error;

  AppointmentQueueState copyWith({
    List<AppointmentListItem>? items,
    Object? comparisonItems = _sentinel,
    Object? comparisonNow = _sentinel,
    bool? comparisonUnavailable,
    Object? realtimeConnection = _sentinel,
    bool? loading,
    Object? error = _sentinel,
  }) {
    return AppointmentQueueState(
      items: items ?? this.items,
      comparisonItems: identical(comparisonItems, _sentinel)
          ? this.comparisonItems
          : comparisonItems as List<AppointmentListItem>?,
      comparisonNow: identical(comparisonNow, _sentinel) ? this.comparisonNow : comparisonNow as DateTime?,
      comparisonUnavailable: comparisonUnavailable ?? this.comparisonUnavailable,
      realtimeConnection: identical(realtimeConnection, _sentinel)
          ? this.realtimeConnection
          : realtimeConnection as AppointmentQueueRealtimeConnection?,
      loading: loading ?? this.loading,
      error: identical(error, _sentinel) ? this.error : error as String?,
    );
  }
}

const _sentinel = Object();

class AppointmentQueueController extends Notifier<AppointmentQueueState> {
  AppointmentQueueRealtimeClient? _realtimeClient;

  @override
  AppointmentQueueState build() {
    ref.onDispose(_unsubscribeRealtime);

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

    final initial = const AppointmentQueueState(items: [], loading: true);
    Future.microtask(() async {
      await refresh();
      _subscribeRealtime();
    });
    return initial;
  }

  String? get _branchId {
    final id = ref.read(authSessionProvider).context?.activeBranchId?.trim();
    return id == null || id.isEmpty ? null : id;
  }

  String get _organizationTimezone {
    final timezone = ref.read(authSessionProvider).context?.organizationTimezone?.trim();
    return effectiveOrganizationTimezone(timezone);
  }

  AppointmentTodayRange get _todayRange =>
      appointmentTodayRangeInTimezone(_organizationTimezone, DateTime.now().toUtc());

  Future<void> refresh() async {
    final branchId = _branchId;
    if (branchId == null) {
      state = state.copyWith(
        loading: false,
        items: const [],
        error: 'Select an active branch before viewing the queue.',
      );
      return;
    }

    if (state.items.isEmpty) {
      state = state.copyWith(loading: true, error: null);
    } else {
      state = state.copyWith(error: null);
    }
    try {
      final range = _todayRange;
      final repository = ref.read(appointmentRepositoryProvider);
      final items = await repository.listAppointments(branchId: branchId, from: range.from, to: range.to);
      final comparison = await _fetchComparisonItems(branchId: branchId, repository: repository);
      state = state.copyWith(
        loading: false,
        items: sortAppointmentsByStartTime(items),
        comparisonItems: comparison != null && !comparison.unavailable ? comparison.items : null,
        comparisonNow: comparison != null && !comparison.unavailable ? comparison.referenceNow : null,
        comparisonUnavailable: comparison?.unavailable ?? false,
        error: null,
      );
    } catch (error) {
      state = state.copyWith(loading: false, error: 'Unable to load today\'s queue. Try again.');
      debugPrint('AppointmentQueueController.refresh failed: $error');
    }
  }

  Future<({List<AppointmentListItem> items, DateTime referenceNow, bool unavailable})?> _fetchComparisonItems({
    required String branchId,
    required AppointmentRepository repository,
  }) async {
    try {
      final schedule = await _resolveBranchSchedule();
      final timezone = _organizationTimezone;
      final todayLocal = calendarDayInOrganizationTimezone(timezone, DateTime.now().toUtc());
      final previousDay = AppointmentBranchWorkingHours.previousWorkingDay(schedule, todayLocal);
      if (previousDay == null) {
        return null;
      }

      final dayOffset = todayLocal.difference(previousDay).inDays;
      final comparisonNow = DateTime.now().subtract(Duration(days: dayOffset));
      final comparisonRange = appointmentTodayRangeInTimezone(timezone, comparisonNow.toUtc());
      final items = await repository.listAppointments(
        branchId: branchId,
        from: comparisonRange.from,
        to: comparisonRange.to,
      );
      return (items: sortAppointmentsByStartTime(items), referenceNow: comparisonNow, unavailable: false);
    } catch (error) {
      debugPrint('AppointmentQueueController._fetchComparisonItems failed: $error');
      return (items: <AppointmentListItem>[], referenceNow: DateTime.now(), unavailable: true);
    }
  }

  Future<BranchWorkingSchedule> _resolveBranchSchedule() async {
    final auth = ref.read(authSessionProvider).context;
    final orgId = auth?.organizationId?.trim();
    final branchId = _branchId;
    if (orgId != null && orgId.isNotEmpty && branchId != null) {
      try {
        final branches = await ref.read(listBranchesUseCaseProvider)(
          organizationId: orgId,
          filter: BranchListFilter.active,
        );
        for (final branch in branches) {
          if (branch.id == branchId && branch.workingSchedule != null) {
            return branch.workingSchedule!;
          }
        }
      } catch (error) {
        debugPrint('AppointmentQueueController._resolveBranchSchedule failed: $error');
      }
    }
    return BranchWorkingSchedule.defaultSchedule();
  }

  void _subscribeRealtime() {
    final branchId = _branchId;
    if (branchId == null) {
      return;
    }

    _unsubscribeRealtime();
    final client = ref.read(appointmentQueueRealtimeClientProvider);
    _realtimeClient = client;
    client.subscribe(
      branchId: branchId,
      onConnectionChanged: _onRealtimeConnectionChanged,
      onAppointmentChange: _onRealtimeChange,
    );
  }

  void _onRealtimeConnectionChanged(AppointmentQueueRealtimeConnection connection) {
    state = state.copyWith(realtimeConnection: connection);
  }

  void _unsubscribeRealtime() {
    _realtimeClient?.unsubscribe();
    _realtimeClient = null;
  }

  /// Applies a successful status RPC to the cached queue row without reloading the list.
  void patchAppointmentStatus({
    required String appointmentId,
    required AppointmentStatus newStatus,
    String? doctorId,
    String? doctorName,
    DateTime? updatedAt,
    Object? checkedInAt = _sentinel,
    Object? inProgressAt = _sentinel,
  }) {
    final index = state.items.indexWhere((item) => item.id == appointmentId);
    if (index < 0) {
      return;
    }

    final existing = state.items[index];
    var patched = existing.copyWith(
      status: newStatus,
      updatedAt: updatedAt ?? existing.updatedAt,
      doctorId: doctorId ?? existing.doctorId,
      doctorName: doctorName ?? existing.doctorName,
    );
    if (!identical(checkedInAt, _sentinel)) {
      patched = patched.copyWith(checkedInAt: checkedInAt as DateTime?);
    }
    if (!identical(inProgressAt, _sentinel)) {
      patched = patched.copyWith(inProgressAt: inProgressAt as DateTime?);
    }

    final items = [...state.items];
    items[index] = patched;
    state = state.copyWith(items: sortAppointmentsByStartTime(items));
  }

  void _onRealtimeChange(AppointmentQueueRealtimeChange change) {
    final items = [...state.items];
    final applied = applyAppointmentQueueRealtimeChange(items: items, change: change, todayRange: _todayRange);
    if (applied) {
      state = state.copyWith(items: sortAppointmentsByStartTime(items));
      return;
    }
    unawaited(refresh());
  }
}

final appointmentQueueProvider = NotifierProvider<AppointmentQueueController, AppointmentQueueState>(
  AppointmentQueueController.new,
);

/// Checked-in patient count for the shell queue nav badge.
final appointmentQueueCheckedInCountProvider = Provider<int>((ref) {
  final items = ref.watch(appointmentQueueProvider).items;
  return AppointmentQueueDisplay.partition(items).waiting.length;
});

/// Eagerly warms the queue provider so the nav badge reflects today's check-ins
/// without requiring a visit to the queue page.
final appointmentQueueShellWarmProvider = Provider<void>((ref) {
  ref.watch(appointmentQueueCheckedInCountProvider);
});
