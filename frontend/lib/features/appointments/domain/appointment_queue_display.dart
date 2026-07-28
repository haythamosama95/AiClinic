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
  const AppointmentQueuePartition({
    required this.schedule,
    required this.waiting,
  });

  final List<AppointmentListItem> schedule;
  final List<AppointmentListItem> waiting;
}

/// Pure display rules for the clinic queue dashboard.
abstract final class AppointmentQueueDisplay {
  static const waitWarningMinutes = 15;
  static const waitCriticalMinutes = 30;

  /// Fallback label when no shift doctors could be resolved.
  static const noShiftDoctorLabel = 'No doctor on shift';

  /// Label for unassigned appointments in the queue schedule card.
  static const noPreferredDoctorLabel = 'No preferred doctor';

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
      totalTrend: AppointmentQueueStatTrend(
        percentChange: _percentChange(current.total, previous.total),
      ),
      completedTrend: AppointmentQueueStatTrend(
        percentChange: _percentChange(current.completed, previous.completed),
      ),
      noShowTrend: AppointmentQueueStatTrend(
        percentChange: _percentChange(current.noShow, previous.noShow),
      ),
      avgWaitTrend: AppointmentQueueStatTrend(
        percentChange: _percentChangeNullable(
          current.avgWaitMinutes,
          previous.avgWaitMinutes,
        ),
      ),
      avgVisitTrend: AppointmentQueueStatTrend(
        percentChange: _percentChangeNullable(
          current.avgVisitMinutes,
          previous.avgVisitMinutes,
        ),
      ),
    );
  }

  static ({
    int total,
    int completed,
    int noShow,
    int? avgWaitMinutes,
    int? avgVisitMinutes,
  })
  _rawStats(List<AppointmentListItem> items, {required DateTime now}) {
    final active = _activeToday(items);
    final completed = active
        .where((item) => item.status == AppointmentStatus.completed)
        .length;
    final noShow = items
        .where((item) => item.status == AppointmentStatus.noShow)
        .length;
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
  static int? _averageWaitMinutesAt(
    List<AppointmentListItem> items,
    DateTime referenceNow,
  ) {
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
    return (waits.map((d) => d.inMinutes).reduce((a, b) => a + b) /
            waits.length)
        .round();
  }

  /// Average visit length among appointments that started or finished a session.
  static int? _averageVisitMinutesAt(
    List<AppointmentListItem> items,
    DateTime referenceNow,
  ) {
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
    return (visits.map((d) => d.inMinutes).reduce((a, b) => a + b) /
            visits.length)
        .round();
  }

  /// Visit duration for [item] at [referenceNow], or null when no session has started.
  static Duration? _visitDurationFor(
    AppointmentListItem item,
    DateTime referenceNow,
  ) {
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
      final effectiveEnd = endedAt.isAfter(referenceNow)
          ? referenceNow
          : endedAt;
      if (effectiveEnd.isBefore(startedAt)) {
        return null;
      }
      final elapsed = effectiveEnd.difference(startedAt);
      return elapsed.isNegative ? Duration.zero : elapsed;
    }

    return null;
  }

  /// Wait duration for [item] at [referenceNow], or null when not in the waiting room then.
  static Duration? _waitDurationAt(
    AppointmentListItem item,
    DateTime referenceNow,
  ) {
    final checkedInAt =
        item.checkedInAt ??
        (item.status == AppointmentStatus.checkedIn ? item.updatedAt : null);
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

  static AppointmentQueuePartition partition(
    List<AppointmentListItem> items, {
    DateTime? now,
  }) {
    final sorted = sortAppointmentsByStartTime(_activeToday(items));
    final waiting = sorted
        .where((item) => item.status == AppointmentStatus.checkedIn)
        .toList(growable: false);

    return AppointmentQueuePartition(schedule: sorted, waiting: waiting);
  }

  /// Doctor column content for the queue appointments card.
  static QueueAppointmentDoctorPresentation queueDoctorPresentation(
    AppointmentListItem item, {
    AppointmentQueueShiftDoctorLookup shiftLookup =
        AppointmentQueueShiftDoctorLookup.empty,
  }) {
    return shiftLookup.presentationFor(item);
  }

  /// Compact doctor label for queue summary rows.
  static String queueDoctorLabel(
    AppointmentListItem item, {
    AppointmentQueueShiftDoctorLookup shiftLookup =
        AppointmentQueueShiftDoctorLookup.empty,
  }) {
    return queueDoctorPresentation(item, shiftLookup: shiftLookup).displayNames;
  }

  /// In-progress appointment currently assigned to [doctorId], if any.
  ///
  /// When [doctorId] is null or empty, matches unassigned in-progress rows
  /// (they share a single server-side slot).
  static AppointmentListItem? inProgressAppointmentForDoctor(
    String? doctorId,
    Iterable<AppointmentListItem> items,
  ) {
    final normalizedId = doctorId?.trim();
    if (normalizedId == null || normalizedId.isEmpty) {
      for (final item in items) {
        if (item.status == AppointmentStatus.inProgress &&
            (item.doctorId == null || item.doctorId!.trim().isEmpty)) {
          return item;
        }
      }
      return null;
    }

    for (final item in items) {
      if (item.status == AppointmentStatus.inProgress &&
          item.doctorId == normalizedId) {
        return item;
      }
    }
    return null;
  }

  /// Whether [item] can start because its doctor has no other in-progress appointment.
  static String? doctorInProgressBlockReason(
    AppointmentListItem item,
    Iterable<AppointmentListItem> items, {
    AppointmentQueueShiftDoctorLookup shiftLookup =
        AppointmentQueueShiftDoctorLookup.empty,
  }) {
    return AppointmentQueueStartDoctor.blockReasonForStart(
      item: item,
      siblingAppointments: items,
      shiftLookup: shiftLookup,
    );
  }

  static bool isScheduleRowDimmed(AppointmentListItem item) {
    return item.status == AppointmentStatus.completed ||
        item.status == AppointmentStatus.cancelled;
  }

  /// Index of the schedule row whose time slot is nearest to [now].
  ///
  /// Returns 0 when [items] is empty. An in-progress appointment wins over slot
  /// proximity; otherwise the slot containing [now] or nearest edge is used.
  static int indexClosestToNow(
    List<AppointmentListItem> items, {
    required DateTime now,
  }) {
    if (items.isEmpty) {
      return 0;
    }

    final inProgressIndex = items.indexWhere(
      (item) => item.status == AppointmentStatus.inProgress,
    );
    if (inProgressIndex >= 0) {
      return inProgressIndex;
    }

    var bestIndex = 0;
    var bestDistance = _scheduleTimeDistance(items.first, now);
    for (var i = 1; i < items.length; i++) {
      final distance = _scheduleTimeDistance(items[i], now);
      if (distance < bestDistance) {
        bestDistance = distance;
        bestIndex = i;
      }
    }
    return bestIndex;
  }

  /// Scroll offset estimate for [targetIndex] using measured row heights when available.
  static double estimatedScheduleScrollOffset({
    required int targetIndex,
    required Map<int, double> measuredRowHeights,
    double fallbackRowHeight = 92,
  }) {
    var offset = 0.0;
    for (var i = 0; i < targetIndex; i++) {
      offset += measuredRowHeights[i] ?? fallbackRowHeight;
    }
    return offset;
  }

  static Duration _scheduleTimeDistance(
    AppointmentListItem item,
    DateTime now,
  ) {
    if (!now.isBefore(item.startTime) && now.isBefore(item.endTime)) {
      return Duration.zero;
    }
    if (now.isBefore(item.startTime)) {
      return item.startTime.difference(now);
    }
    return now.difference(item.endTime);
  }

  /// Wait time since check-in when [checkedInAt] is known; otherwise falls back to slot start.
  static Duration estimateWaitDuration(
    AppointmentListItem item, {
    required DateTime now,
  }) {
    if (item.status == AppointmentStatus.checkedIn) {
      final checkedInAt = item.checkedInAt ?? item.updatedAt;
      if (checkedInAt != null) {
        final wait = now.difference(checkedInAt);
        return wait.isNegative ? Duration.zero : wait;
      }
    }

    final anchor = item.startTime.isAfter(now) ? now : item.startTime;
    return now.difference(anchor).isNegative
        ? Duration.zero
        : now.difference(anchor);
  }

  static Duration estimateSessionDuration(
    AppointmentListItem item, {
    required DateTime now,
  }) {
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

  static String formatDurationLabel(Duration duration) {
    final totalMinutes = duration.inMinutes;
    if (totalMinutes < 60) {
      return '${totalMinutes}m';
    }
    final hours = duration.inHours;
    final minutes = totalMinutes % 60;
    return minutes == 0 ? '${hours}h' : '${hours}h ${minutes}m';
  }

  static String formatWaitLabel(Duration wait) =>
      'Waiting: ${formatDurationLabel(wait)}';

  static String formatWaitedLabel(Duration wait) {
    final totalMinutes = wait.inMinutes;
    if (totalMinutes < 60) {
      return 'Waited: $totalMinutes mins';
    }
    return 'Waited: ${formatDurationLabel(wait)}';
  }

  static String formatSessionLabel(Duration session) =>
      'In session: ${formatDurationLabel(session)}';

  static (String, AppointmentQueueWaitTier) waitPresentation(
    AppointmentListItem item, {
    required DateTime now,
  }) {
    final wait = estimateWaitDuration(item, now: now);
    return (formatWaitLabel(wait), waitTierFor(wait));
  }

  static AppBadgeTone scheduleBadgeTone(AppointmentStatus status) {
    return switch (status) {
      AppointmentStatus.scheduled => AppBadgeTone.neutral,
      AppointmentStatus.confirmed => AppBadgeTone.info,
      AppointmentStatus.checkedIn => AppBadgeTone.success,
      AppointmentStatus.inProgress => AppBadgeTone.warning,
      AppointmentStatus.completed => AppBadgeTone.muted,
      AppointmentStatus.cancelled ||
      AppointmentStatus.noShow => AppBadgeTone.destructive,
      AppointmentStatus.unknown => AppBadgeTone.neutral,
    };
  }

  static String scheduleBadgeLabel(AppointmentStatus status) => status.label;

  static List<AppointmentListItem> _activeToday(
    List<AppointmentListItem> items,
  ) {
    return items
        .where(
          (item) =>
              item.status != AppointmentStatus.cancelled &&
              item.status != AppointmentStatus.unknown,
        )
        .toList(growable: false);
  }
}

/// Semantic badge tone for queue status chips.
enum AppBadgeTone { neutral, info, success, warning, destructive, muted }
