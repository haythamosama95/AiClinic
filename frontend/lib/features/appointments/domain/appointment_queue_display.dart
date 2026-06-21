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
  const AppointmentQueuePartition({required this.schedule, required this.waiting, this.activeSession, this.nextUp});

  final List<AppointmentListItem> schedule;
  final List<AppointmentListItem> waiting;
  final AppointmentListItem? activeSession;
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
    final inProgress = sorted.where((item) => item.status == AppointmentStatus.inProgress).toList(growable: false);
    final activeSession = inProgress.isEmpty ? null : inProgress.first;
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

    return AppointmentQueuePartition(schedule: sorted, waiting: waiting, activeSession: activeSession, nextUp: nextUp);
  }

  static bool isScheduleRowDimmed(AppointmentListItem item) {
    return item.status == AppointmentStatus.completed ||
        item.status == AppointmentStatus.cancelled ||
        item.status == AppointmentStatus.noShow;
  }

  /// Approximates wait time from appointment start when check-in timestamp is unavailable.
  static Duration estimateWaitDuration(AppointmentListItem item, {required DateTime now}) {
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

  static String scheduleBadgeLabel(AppointmentStatus status) {
    return switch (status) {
      AppointmentStatus.scheduled => 'Scheduled',
      AppointmentStatus.confirmed => 'Confirmed',
      AppointmentStatus.checkedIn => 'Arrived',
      AppointmentStatus.inProgress => 'In session',
      AppointmentStatus.completed => 'Completed',
      AppointmentStatus.noShow => 'No show',
      AppointmentStatus.cancelled => 'Cancelled',
      AppointmentStatus.unknown => status.label,
    };
  }

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
