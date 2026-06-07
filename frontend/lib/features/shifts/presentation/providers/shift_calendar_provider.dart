import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/logging/app_log.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/shifts/data/shift_repository.dart';
import 'package:ai_clinic/features/shifts/domain/shift_calendar_mode.dart';
import 'package:ai_clinic/features/shifts/domain/shift_list_item.dart';
import 'package:ai_clinic/features/shifts/presentation/shift_rpc_messages.dart';

@immutable
class ShiftCalendarState {
  const ShiftCalendarState({
    required this.mode,
    required this.focusDate,
    required this.items,
    this.selectedBranchId,
    this.firstDayOfWeekIndex = DateTime.monday % 7,
    this.loading = false,
    this.error,
  });

  final ShiftCalendarMode mode;
  final DateTime focusDate;
  final List<ShiftListItem> items;
  final String? selectedBranchId;
  final int firstDayOfWeekIndex;
  final bool loading;
  final String? error;

  ShiftCalendarState copyWith({
    ShiftCalendarMode? mode,
    DateTime? focusDate,
    List<ShiftListItem>? items,
    Object? selectedBranchId = _sentinel,
    int? firstDayOfWeekIndex,
    bool? loading,
    Object? error = _sentinel,
  }) {
    return ShiftCalendarState(
      mode: mode ?? this.mode,
      focusDate: focusDate ?? this.focusDate,
      items: items ?? this.items,
      selectedBranchId: identical(selectedBranchId, _sentinel) ? this.selectedBranchId : selectedBranchId as String?,
      firstDayOfWeekIndex: firstDayOfWeekIndex ?? this.firstDayOfWeekIndex,
      loading: loading ?? this.loading,
      error: identical(error, _sentinel) ? this.error : error as String?,
    );
  }
}

const _sentinel = Object();

class ShiftCalendarController extends Notifier<ShiftCalendarState> {
  int _refreshGeneration = 0;

  @override
  ShiftCalendarState build() {
    final today = DateTime.now();
    final initialBranchId = _normalizedOrNull(ref.read(authSessionProvider).context?.activeBranchId);

    ref.listen<AuthSessionState>(authSessionProvider, (previous, next) {
      final prevBranch = previous?.context?.activeBranchId;
      final nextBranch = next.context?.activeBranchId;
      if (prevBranch != nextBranch) {
        unawaited(setBranchFilter(nextBranch));
      }
    });

    final initial = ShiftCalendarState(
      mode: ShiftCalendarMode.week,
      focusDate: DateTime(today.year, today.month, today.day),
      items: const [],
      selectedBranchId: initialBranchId,
      loading: true,
    );

    Future.microtask(refresh);
    return initial;
  }

  void setFirstDayOfWeekIndex(int index) {
    if (index == state.firstDayOfWeekIndex) {
      return;
    }
    state = state.copyWith(firstDayOfWeekIndex: index);
    if (state.mode == ShiftCalendarMode.week) {
      unawaited(refresh());
    }
  }

  Future<void> refresh() async {
    final generation = ++_refreshGeneration;
    final branchId = _normalizedOrNull(state.selectedBranchId);
    if (branchId == null) {
      if (generation != _refreshGeneration) {
        return;
      }
      state = state.copyWith(
        loading: false,
        items: const [],
        error: 'Select an active branch before viewing the shift calendar.',
      );
      return;
    }

    state = state.copyWith(loading: true, error: null);
    try {
      final bounds = boundsFor(state.focusDate, state.mode, firstDayOfWeekIndex: state.firstDayOfWeekIndex);
      final items = await ref
          .read(shiftRepositoryProvider)
          .listShifts(branchId: branchId, dateFrom: bounds.$1, dateTo: bounds.$2);
      if (generation != _refreshGeneration) {
        return;
      }
      state = state.copyWith(loading: false, items: items, error: null);
    } on RpcFailure catch (error) {
      if (generation != _refreshGeneration) {
        return;
      }
      AppLog.warning('shifts.calendar.refresh failed code=${error.code}', name: 'shifts');
      state = state.copyWith(loading: false, items: const [], error: shiftMessageForRpc(error));
    } catch (error) {
      if (generation != _refreshGeneration) {
        return;
      }
      AppLog.warning('shifts.calendar.refresh failed: $error', name: 'shifts');
      state = state.copyWith(loading: false, items: const [], error: 'Could not load shifts. Please retry.');
    }
  }

  Future<void> setMode(ShiftCalendarMode mode) async {
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
    final focus = state.focusDate;
    final nextFocus = state.mode == ShiftCalendarMode.week
        ? focus.subtract(const Duration(days: 7))
        : DateTime(focus.year, focus.month - 1, focus.day);
    await setFocusDate(nextFocus);
  }

  Future<void> nextPeriod() async {
    final focus = state.focusDate;
    final nextFocus = state.mode == ShiftCalendarMode.week
        ? focus.add(const Duration(days: 7))
        : DateTime(focus.year, focus.month + 1, focus.day);
    await setFocusDate(nextFocus);
  }

  Future<void> setBranchFilter(String? branchId) async {
    final normalized = _normalizedOrNull(branchId);
    if (normalized == state.selectedBranchId) {
      return;
    }
    state = state.copyWith(selectedBranchId: normalized, items: const [], loading: true, error: null);
    await refresh();
  }

  static (DateTime, DateTime) boundsFor(
    DateTime focusDate,
    ShiftCalendarMode mode, {
    int firstDayOfWeekIndex = DateTime.monday % 7,
  }) {
    final dayStart = DateTime(focusDate.year, focusDate.month, focusDate.day);
    if (mode == ShiftCalendarMode.week) {
      final dayIndex = dayStart.weekday % 7;
      final daysFromWeekStart = (dayIndex - firstDayOfWeekIndex + 7) % 7;
      final start = dayStart.subtract(Duration(days: daysFromWeekStart));
      final end = start.add(const Duration(days: 6));
      return (start, end);
    }

    final start = DateTime(focusDate.year, focusDate.month, 1);
    final end = DateTime(focusDate.year, focusDate.month + 1, 0);
    return (start, end);
  }

  static String? _normalizedOrNull(String? value) {
    final normalized = value?.trim();
    if (normalized == null || normalized.isEmpty) {
      return null;
    }
    return normalized;
  }
}

final shiftCalendarProvider = NotifierProvider<ShiftCalendarController, ShiftCalendarState>(
  ShiftCalendarController.new,
);
