import 'package:ai_clinic/features/appointments/domain/appointment_list_item.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_queue_metrics.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_queue_shift_doctors.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';

/// Semantic badge tone for queue status chips.
enum AppBadgeTone { neutral, info, success, warning, destructive, muted }

/// User-facing labels and formatting for the clinic queue dashboard.
abstract final class AppointmentQueueLabels {
  /// Fallback label when no shift doctors could be resolved.
  static const noShiftDoctorLabel = 'No doctor on shift';

  /// Label for unassigned appointments in the queue schedule card.
  static const noPreferredDoctorLabel = 'No preferred doctor';

  /// Doctor column content for the queue appointments card.
  static QueueAppointmentDoctorPresentation queueDoctorPresentation(
    AppointmentListItem item, {
    AppointmentQueueShiftDoctorLookup shiftLookup = AppointmentQueueShiftDoctorLookup.empty,
  }) {
    return shiftLookup.presentationFor(item);
  }

  /// Compact doctor label for queue summary rows.
  static String queueDoctorLabel(
    AppointmentListItem item, {
    AppointmentQueueShiftDoctorLookup shiftLookup = AppointmentQueueShiftDoctorLookup.empty,
  }) {
    return queueDoctorPresentation(item, shiftLookup: shiftLookup).displayNames;
  }

  /// Index of the schedule row whose time slot is nearest to [now].
  ///
  /// Returns 0 when [items] is empty. An in-progress appointment wins over slot
  /// proximity; otherwise the slot containing [now] or nearest edge is used.
  static int indexClosestToNow(List<AppointmentListItem> items, {required DateTime now}) {
    if (items.isEmpty) {
      return 0;
    }

    final inProgressIndex = items.indexWhere((item) => item.status == AppointmentStatus.inProgress);
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

  static Duration _scheduleTimeDistance(AppointmentListItem item, DateTime now) {
    if (!now.isBefore(item.startTime) && now.isBefore(item.endTime)) {
      return Duration.zero;
    }
    if (now.isBefore(item.startTime)) {
      return item.startTime.difference(now);
    }
    return now.difference(item.endTime);
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
    final wait = AppointmentQueueMetrics.estimateWaitDuration(item, now: now);
    return (formatWaitLabel(wait), AppointmentQueueMetrics.waitTierFor(wait));
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
}
