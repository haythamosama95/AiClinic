import 'package:ai_clinic/features/appointments/domain/appointment_list_item.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_today_range.dart';

/// Wait-time urgency tiers for the checked-in column.
enum AppointmentQueueWaitTier { normal, warning, critical }

/// Summary metrics for the top stats banner.
class AppointmentQueueStats {
  const AppointmentQueueStats({
    required this.total,
    required this.completed,
    required this.waiting,
    required this.avgWaitMinutes,
  });

  final int total;
  final int completed;
  final int waiting;
  final int? avgWaitMinutes;
}

/// Three-column partition of today's queue.
class AppointmentQueuePartition {
  const AppointmentQueuePartition({
    required this.schedule,
    required this.waiting,
    required this.activeSessions,
    this.nextUp,
  });

  final List<AppointmentListItem> schedule;
  final List<AppointmentListItem> waiting;
  final List<AppointmentListItem> activeSessions;
  final AppointmentListItem? nextUp;
}

/// Pure display rules for the clinic queue dashboard.
abstract final class AppointmentQueueDisplay {
  static const waitWarningMinutes = 15;
  static const waitCriticalMinutes = 30;

  static AppointmentQueueStats computeStats(List<AppointmentListItem> items, {required DateTime now}) {
    final active = _activeToday(items);
    final completed = active.where((item) => item.status == AppointmentStatus.completed).length;
    final waiting = active.where((item) => item.status == AppointmentStatus.checkedIn).toList(growable: false);
    final waitDurations = waiting.map((item) => estimateWaitDuration(item, now: now)).toList(growable: false);
    final avgWaitMinutes = waitDurations.isEmpty
        ? null
        : (waitDurations.map((d) => d.inMinutes).reduce((a, b) => a + b) / waitDurations.length).round();

    return AppointmentQueueStats(
      total: active.length,
      completed: completed,
      waiting: waiting.length,
      avgWaitMinutes: avgWaitMinutes,
    );
  }

  static AppointmentQueuePartition partition(List<AppointmentListItem> items, {DateTime? now}) {
    final reference = now ?? DateTime.now();
    final sorted = sortAppointmentsByStartTime(_activeToday(items));
    final waiting = sorted.where((item) => item.status == AppointmentStatus.checkedIn).toList(growable: false)
      ..sort((a, b) => estimateWaitDuration(b, now: reference).compareTo(estimateWaitDuration(a, now: reference)));
    final activeSessions = activeSessionsFor(sorted);
    AppointmentListItem? nextUp;
    if (waiting.isNotEmpty) {
      nextUp = waiting.first;
    } else {
      for (final item in sorted) {
        if (item.status == AppointmentStatus.confirmed || item.status == AppointmentStatus.scheduled) {
          nextUp = item;
          break;
        }
      }
    }

    return AppointmentQueuePartition(
      schedule: sorted,
      waiting: waiting,
      activeSessions: activeSessions,
      nextUp: nextUp,
    );
  }

  /// One active session per doctor (earliest in-progress slot when duplicates exist).
  static List<AppointmentListItem> activeSessionsFor(List<AppointmentListItem> items) {
    final inProgress = items.where((item) => item.status == AppointmentStatus.inProgress).toList(growable: false);
    final byDoctor = <String, AppointmentListItem>{};
    for (final item in inProgress) {
      final doctorKey = item.doctorId ?? '';
      byDoctor.putIfAbsent(doctorKey, () => item);
    }
    final sessions = byDoctor.values.toList(growable: false)..sort((a, b) => a.startTime.compareTo(b.startTime));
    return sessions;
  }

  /// Whether [item] can start because its doctor has no other in-progress appointment.
  static String? doctorInProgressBlockReason(AppointmentListItem item, Iterable<AppointmentListItem> items) {
    if (item.status != AppointmentStatus.checkedIn) {
      return null;
    }
    final doctorKey = item.doctorId ?? '';
    final conflict = items.where(
      (other) =>
          other.id != item.id && other.status == AppointmentStatus.inProgress && (other.doctorId ?? '') == doctorKey,
    );
    if (conflict.isEmpty) {
      return null;
    }
    return '${item.doctorDisplayName} already has a patient in progress. Complete that visit before starting another.';
  }

  static bool isScheduleRowDimmed(AppointmentListItem item) {
    return item.status == AppointmentStatus.completed ||
        item.status == AppointmentStatus.cancelled ||
        item.status == AppointmentStatus.noShow;
  }

  /// Wait time since check-in when [updatedAt] is known; otherwise falls back to slot start.
  static Duration estimateWaitDuration(AppointmentListItem item, {required DateTime now}) {
    if (item.status == AppointmentStatus.checkedIn) {
      final checkedInAt = item.updatedAt;
      if (checkedInAt != null) {
        final wait = now.difference(checkedInAt);
        return wait.isNegative ? Duration.zero : wait;
      }
    }

    final anchor = item.startTime.isAfter(now) ? now : item.startTime;
    return now.difference(anchor).isNegative ? Duration.zero : now.difference(anchor);
  }

  static Duration estimateSessionDuration(AppointmentListItem item, {required DateTime now}) {
    return estimateWaitDuration(item, now: now);
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

  static String formatWaitLabel(Duration wait) => 'Waiting: ${formatDurationLabel(wait)}';

  static String formatWaitedLabel(Duration wait) {
    final totalMinutes = wait.inMinutes;
    if (totalMinutes < 60) {
      return 'Waited: $totalMinutes mins';
    }
    return 'Waited: ${formatDurationLabel(wait)}';
  }

  static String formatSessionLabel(Duration session) => 'In session: ${formatDurationLabel(session)}';

  static (String, AppointmentQueueWaitTier) waitPresentation(AppointmentListItem item, {required DateTime now}) {
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
      AppointmentStatus.cancelled || AppointmentStatus.noShow => AppBadgeTone.destructive,
      AppointmentStatus.unknown => AppBadgeTone.neutral,
    };
  }

  static String scheduleBadgeLabel(AppointmentStatus status) => status.label;

  static List<AppointmentListItem> _activeToday(List<AppointmentListItem> items) {
    return items
        .where(
          (item) =>
              item.status != AppointmentStatus.cancelled &&
              item.status != AppointmentStatus.noShow &&
              item.status != AppointmentStatus.unknown,
        )
        .toList(growable: false);
  }
}

/// Semantic badge tone for queue status chips.
enum AppBadgeTone { neutral, info, success, warning, destructive, muted }
