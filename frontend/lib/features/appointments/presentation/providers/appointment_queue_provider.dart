import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/features/appointments/data/appointment_queue_realtime.dart';
import 'package:ai_clinic/features/appointments/data/appointment_queue_realtime_apply.dart';
import 'package:ai_clinic/features/appointments/data/appointment_repository.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_fetch_scope.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_list_item.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_org_calendar.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_queue_display.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_today_range.dart';

@immutable
class AppointmentQueueState {
  const AppointmentQueueState({required this.items, this.loading = false, this.error});

  final List<AppointmentListItem> items;
  final bool loading;
  final String? error;

  AppointmentQueueState copyWith({List<AppointmentListItem>? items, bool? loading, Object? error = _sentinel}) {
    return AppointmentQueueState(
      items: items ?? this.items,
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

    state = state.copyWith(loading: true, error: null);
    try {
      final range = _todayRange;
      final items = await ref
          .read(appointmentRepositoryProvider)
          .listAppointments(branchId: branchId, from: range.from, to: range.to);
      state = state.copyWith(loading: false, items: sortAppointmentsByStartTime(items), error: null);
    } catch (error) {
      state = state.copyWith(loading: false, error: 'Unable to load today\'s queue. Try again.');
      debugPrint('AppointmentQueueController.refresh failed: $error');
    }
  }

  void _subscribeRealtime() {
    final branchId = _branchId;
    if (branchId == null) {
      return;
    }

    _unsubscribeRealtime();
    final client = ref.read(appointmentQueueRealtimeClientProvider);
    _realtimeClient = client;
    client.subscribe(branchId: branchId, onConnectionChanged: (_) {}, onAppointmentChange: _onRealtimeChange);
  }

  void _unsubscribeRealtime() {
    _realtimeClient?.unsubscribe();
    _realtimeClient = null;
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
  return AppointmentQueueDisplay.computeStats(items, now: DateTime.now()).waiting;
});
