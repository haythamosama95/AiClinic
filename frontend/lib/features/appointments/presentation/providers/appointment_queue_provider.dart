import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/features/appointments/data/appointment_queue_realtime.dart';
import 'package:ai_clinic/features/appointments/data/appointment_repository.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_list_item.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_today_range.dart';

@immutable
class AppointmentQueueState {
  const AppointmentQueueState({
    required this.items,
    this.loading = false,
    this.error,
    this.realtimeConnection = AppointmentQueueRealtimeConnection.connecting,
    this.referenceTime,
  });

  final List<AppointmentListItem> items;
  final bool loading;
  final String? error;
  final AppointmentQueueRealtimeConnection realtimeConnection;
  final DateTime? referenceTime;

  bool get isLive => realtimeConnection == AppointmentQueueRealtimeConnection.live;

  bool get isDegraded => realtimeConnection == AppointmentQueueRealtimeConnection.degraded;

  AppointmentQueueState copyWith({
    List<AppointmentListItem>? items,
    bool? loading,
    Object? error = _sentinel,
    AppointmentQueueRealtimeConnection? realtimeConnection,
    DateTime? referenceTime,
  }) {
    return AppointmentQueueState(
      items: items ?? this.items,
      loading: loading ?? this.loading,
      error: identical(error, _sentinel) ? this.error : error as String?,
      realtimeConnection: realtimeConnection ?? this.realtimeConnection,
      referenceTime: referenceTime ?? this.referenceTime,
    );
  }
}

const _sentinel = Object();

class AppointmentQueueController extends Notifier<AppointmentQueueState> {
  AppointmentQueueRealtimeClient? _realtime;
  String? _subscribedBranchId;
  int _refreshGeneration = 0;

  @override
  AppointmentQueueState build() {
    final now = DateTime.now();
    ref.onDispose(_disposeRealtime);
    ref.listen<AuthSessionState>(authSessionProvider, (previous, next) {
      final prevBranch = previous?.context?.activeBranchId;
      final nextBranch = next.context?.activeBranchId;
      if (prevBranch != nextBranch) {
        _resubscribeRealtime(nextBranch);
        unawaited(refresh());
      }
    });

    final initial = AppointmentQueueState(
      items: const [],
      loading: true,
      referenceTime: now,
      realtimeConnection: AppointmentQueueRealtimeConnection.connecting,
    );

    Future.microtask(() async {
      await refresh();
      _resubscribeRealtime(ref.read(authSessionProvider).context?.activeBranchId);
    });

    return initial;
  }

  Future<void> refresh() async {
    final generation = ++_refreshGeneration;
    final branchId = _normalizedOrNull(ref.read(authSessionProvider).context?.activeBranchId);
    final reference = DateTime.now();

    if (branchId == null) {
      state = state.copyWith(
        loading: false,
        items: const [],
        error: 'Select an active branch before viewing the queue.',
        referenceTime: reference,
      );
      return;
    }

    state = state.copyWith(loading: true, error: null, referenceTime: reference);
    try {
      final range = appointmentTodayRange(reference);
      final rawItems = await ref
          .read(appointmentRepositoryProvider)
          .listAppointments(branchId: branchId, from: range.from, to: range.to);
      if (generation != _refreshGeneration) {
        return;
      }

      final todayItems = rawItems
          .where((item) => appointmentStartTimeIsWithinRange(item.startTime, range))
          .toList(growable: false);
      state = state.copyWith(loading: false, items: sortAppointmentsByStartTime(todayItems), error: null);
    } catch (_) {
      if (generation != _refreshGeneration) {
        return;
      }
      state = state.copyWith(loading: false, items: const [], error: 'Could not load the queue. Pull to refresh.');
    }
  }

  void _resubscribeRealtime(String? branchId) {
    final normalized = _normalizedOrNull(branchId);
    if (normalized == _subscribedBranchId) {
      return;
    }

    _disposeRealtime();
    _subscribedBranchId = normalized;
    if (normalized == null) {
      state = state.copyWith(realtimeConnection: AppointmentQueueRealtimeConnection.degraded);
      return;
    }

    final client = ref.read(appointmentQueueRealtimeClientProvider);
    _realtime = client;
    client.subscribe(
      branchId: normalized,
      onAppointmentChange: () => unawaited(refresh()),
      onConnectionChanged: (connection) {
        if (_subscribedBranchId == normalized) {
          state = state.copyWith(realtimeConnection: connection);
        }
      },
    );
  }

  void _disposeRealtime() {
    _realtime?.unsubscribe();
    _realtime = null;
    _subscribedBranchId = null;
  }

  static String? _normalizedOrNull(String? value) {
    final normalized = value?.trim();
    if (normalized == null || normalized.isEmpty) {
      return null;
    }
    return normalized;
  }
}

final appointmentQueueProvider = NotifierProvider<AppointmentQueueController, AppointmentQueueState>(
  AppointmentQueueController.new,
);
