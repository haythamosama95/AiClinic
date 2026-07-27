/// Unshipped: queue UI is not built (router.dart uses a placeholder for /appointments/queue).
library;

import 'package:ai_clinic/features/appointments/domain/appointment_list_item.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_queue_shift_doctors.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_queue_start_doctor.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_today_range.dart';

/// Wait-time urgency tiers for the checked-in column.
enum AppointmentQueueWaitTier { normal, warning, critical }

/// Day-over-day percent change for a queue metric (positive = up, negative = down).
class AppointmentQueueStatTrend {
  const AppointmentQueueStatTrend({this.percentChange});

  final double? percentChange;
}

/// Summary metrics for the top stats banner.
class AppointmentQueueStats {
  const AppointmentQueueStats({
    required this.total,
    required this.completed,
    required this.noShow,
    required this.avgWaitMinutes,
    required this.avgVisitMinutes,
    this.totalTrend,
    this.completedTrend,
    this.noShowTrend,
    this.avgWaitTrend,
    this.avgVisitTrend,
  });

  final int total;
  final int completed;
  final int noShow;
  final int? avgWaitMinutes;
  final int? avgVisitMinutes;
  final AppointmentQueueStatTrend? totalTrend;
  final AppointmentQueueStatTrend? completedTrend;
  final AppointmentQueueStatTrend? noShowTrend;
  final AppointmentQueueStatTrend? avgWaitTrend;
  final AppointmentQueueStatTrend? avgVisitTrend;
}

/// Partition of today's queue into schedule and checked-in columns.
class AppointmentQueuePartition {
  const AppointmentQueuePartition({required this.schedule, required this.waiting});

  final List<AppointmentListItem> schedule;
  final List<AppointmentListItem> waiting;
}

/// Pure scheduling metrics for the clinic queue dashboard.
abstract final class AppointmentQueueMetrics {
  static const waitWarningMinutes = 15;
  static const waitCriticalMinutes = 30;

  static AppointmentQueueStats computeStats(
    List<AppointmentListItem> items, {
    required DateTime now,
    List<AppointmentListItem>? comparisonItems,
    DateTime? comparisonNow,
  }) {
    final current = _rawStats(items, now: now);
    if (comparisonItems == null) {
      return AppointmentQueueStats(
        total: current.total,
        completed: current.completed,
        noShow: current.noShow,
        avgWaitMinutes: current.avgWaitMinutes,
        avgVisitMinutes: current.avgVisitMinutes,
      );
    }

    final previous = _rawStats(comparisonItems, now: comparisonNow ?? now);
    return AppointmentQueueStats(
      total: current.total,
      completed: current.completed,
      noShow: current.noShow,
      avgWaitMinutes: current.avgWaitMinutes,
      avgVisitMinutes: current.avgVisitMinutes,
      totalTrend: AppointmentQueueStatTrend(percentChange: _percentChange(current.total, previous.total)),
      completedTrend: AppointmentQueueStatTrend(percentChange: _percentChange(current.completed, previous.completed)),
      noShowTrend: AppointmentQueueStatTrend(percentChange: _percentChange(current.noShow, previous.noShow)),
      avgWaitTrend: AppointmentQueueStatTrend(
        percentChange: _percentChangeNullable(current.avgWaitMinutes, previous.avgWaitMinutes),
      ),
      avgVisitTrend: AppointmentQueueStatTrend(
        percentChange: _percentChangeNullable(current.avgVisitMinutes, previous.avgVisitMinutes),
      ),
    );
  }

  static ({int total, int completed, int noShow, int? avgWaitMinutes, int? avgVisitMinutes}) _rawStats(
    List<AppointmentListItem> items, {
    required DateTime now,
  }) {
    final active = _activeToday(items);
    final completed = active.where((item) => item.status == AppointmentStatus.completed).length;
    final noShow = items.where((item) => item.status == AppointmentStatus.noShow).length;
    final avgWaitMinutes = _averageWaitMinutesAt(active, now);
    final avgVisitMinutes = _averageVisitMinutesAt(active, now);

    return (
      total: active.length,
      completed: completed,
      noShow: noShow,
      avgWaitMinutes: avgWaitMinutes,
      avgVisitMinutes: avgVisitMinutes,
    );
  }

  /// Average wait among patients in the waiting room at [referenceNow].
  static int? _averageWaitMinutesAt(List<AppointmentListItem> items, DateTime referenceNow) {
    final waits = <Duration>[];
    for (final item in items) {
      final wait = _waitDurationAt(item, referenceNow);
      if (wait != null) {
        waits.add(wait);
      }
    }
    if (waits.isEmpty) {
      return null;
    }
    return (waits.map((d) => d.inMinutes).reduce((a, b) => a + b) / waits.length).round();
  }

  /// Average visit length among appointments that started or finished a session.
  static int? _averageVisitMinutesAt(List<AppointmentListItem> items, DateTime referenceNow) {
    final visits = <Duration>[];
    for (final item in items) {
      final visit = _visitDurationFor(item, referenceNow);
      if (visit != null) {
        visits.add(visit);
      }
    }
    if (visits.isEmpty) {
      return null;
    }
    return (visits.map((d) => d.inMinutes).reduce((a, b) => a + b) / visits.length).round();
  }

  /// Visit duration for [item] at [referenceNow], or null when no session has started.
  static Duration? _visitDurationFor(AppointmentListItem item, DateTime referenceNow) {
    final startedAt = item.inProgressAt;
    if (startedAt == null) {
      return null;
    }

    if (item.status == AppointmentStatus.inProgress) {
      if (referenceNow.isBefore(startedAt)) {
        return null;
      }
      final elapsed = referenceNow.difference(startedAt);
      return elapsed.isNegative ? Duration.zero : elapsed;
    }

    if (item.status == AppointmentStatus.completed) {
      final endedAt = item.updatedAt;
      if (endedAt == null || endedAt.isBefore(startedAt)) {
        return null;
      }
      final effectiveEnd = endedAt.isAfter(referenceNow) ? referenceNow : endedAt;
      if (effectiveEnd.isBefore(startedAt)) {
        return null;
      }
      final elapsed = effectiveEnd.difference(startedAt);
      return elapsed.isNegative ? Duration.zero : elapsed;
    }

    return null;
  }

  /// Wait duration for [item] at [referenceNow], or null when not in the waiting room then.
  static Duration? _waitDurationAt(AppointmentListItem item, DateTime referenceNow) {
    final checkedInAt = item.checkedInAt ?? (item.status == AppointmentStatus.checkedIn ? item.updatedAt : null);
    if (checkedInAt == null || referenceNow.isBefore(checkedInAt)) {
      return null;
    }

    final inProgressAt = item.inProgressAt;
    if (inProgressAt != null && !referenceNow.isBefore(inProgressAt)) {
      return null;
    }

    final wait = referenceNow.difference(checkedInAt);
    return wait.isNegative ? Duration.zero : wait;
  }

  static double? _percentChange(int current, int previous) {
    if (previous == 0) {
      if (current == 0) {
        return 0;
      }
      return 100;
    }
    return ((current - previous) / previous) * 100;
  }

  /// Like [_percentChange], but treats a missing average as zero waiters.
  static double? _percentChangeNullable(int? current, int? previous) {
    return _percentChange(current ?? 0, previous ?? 0);
  }

  static AppointmentQueuePartition partition(List<AppointmentListItem> items, {DateTime? now}) {
    final sorted = sortAppointmentsByStartTime(_activeToday(items));
    final waiting = sorted.where((item) => item.status == AppointmentStatus.checkedIn).toList(growable: false);

    return AppointmentQueuePartition(schedule: sorted, waiting: waiting);
  }

  /// In-progress appointment currently assigned to [doctorId], if any.
  ///
  /// When [doctorId] is null or empty, matches unassigned in-progress rows
  /// (they share a single server-side slot).
  static AppointmentListItem? inProgressAppointmentForDoctor(String? doctorId, Iterable<AppointmentListItem> items) {
    final normalizedId = doctorId?.trim();
    if (normalizedId == null || normalizedId.isEmpty) {
      for (final item in items) {
        if (item.status == AppointmentStatus.inProgress && (item.doctorId == null || item.doctorId!.trim().isEmpty)) {
          return item;
        }
      }
      return null;
    }

    for (final item in items) {
      if (item.status == AppointmentStatus.inProgress && item.doctorId == normalizedId) {
        return item;
      }
    }
    return null;
  }

  /// Whether [item] can start because its doctor has no other in-progress appointment.
  static String? doctorInProgressBlockReason(
    AppointmentListItem item,
    Iterable<AppointmentListItem> items, {
    AppointmentQueueShiftDoctorLookup shiftLookup = AppointmentQueueShiftDoctorLookup.empty,
  }) {
    return AppointmentQueueStartDoctor.blockReasonForStart(
      item: item,
      siblingAppointments: items,
      shiftLookup: shiftLookup,
    );
  }

  static bool isScheduleRowDimmed(AppointmentListItem item) {
    return item.status == AppointmentStatus.completed || item.status == AppointmentStatus.cancelled;
  }

  /// Wait time since check-in when [checkedInAt] is known; otherwise falls back to slot start.
  static Duration estimateWaitDuration(AppointmentListItem item, {required DateTime now}) {
    if (item.status == AppointmentStatus.checkedIn) {
      final checkedInAt = item.checkedInAt ?? item.updatedAt;
      if (checkedInAt != null) {
        final wait = now.difference(checkedInAt);
        return wait.isNegative ? Duration.zero : wait;
      }
    }

    final anchor = item.startTime.isAfter(now) ? now : item.startTime;
    return now.difference(anchor).isNegative ? Duration.zero : now.difference(anchor);
  }

  static Duration estimateSessionDuration(AppointmentListItem item, {required DateTime now}) {
    if (item.status != AppointmentStatus.inProgress) {
      return Duration.zero;
    }

    final startedAt = item.inProgressAt ?? item.updatedAt;
    if (startedAt == null) {
      return Duration.zero;
    }

    final elapsed = now.difference(startedAt);
    return elapsed.isNegative ? Duration.zero : elapsed;
  }

  static AppointmentQueueWaitTier waitTierFor(Duration wait) {
    final minutes = wait.inMinutes;
    if (minutes >= waitCriticalMinutes) {
      return AppointmentQueueWaitTier.critical;
    }
    if (minutes >= waitWarningMinutes) {
      return AppointmentQueueWaitTier.warning;
    }
    return AppointmentQueueWaitTier.normal;
  }

  static List<AppointmentListItem> _activeToday(List<AppointmentListItem> items) {
    return items
        .where((item) => item.status != AppointmentStatus.cancelled && item.status != AppointmentStatus.unknown)
        .toList(growable: false);
  }
}
