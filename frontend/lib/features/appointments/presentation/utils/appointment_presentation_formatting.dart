import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:ai_clinic/core/ui/ui.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_calendar_period.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_list_item.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';

/// Presentation helpers for appointment list, queue, and calendar surfaces.
abstract final class AppointmentPresentationFormatting {
  static final _timeFormat = DateFormat('HH:mm', 'en_GB');
  static final _dateFormat = DateFormat('EEE, d MMM yyyy', 'en_GB');
  static final _auditFormat = DateFormat('d MMM yyyy · HH:mm', 'en_GB');

  /// Western digits + tabular time for queue and calendar chips.
  static String formatTime(DateTime time) => _timeFormat.format(time.toLocal());

  static String formatTimeRange(DateTime start, DateTime end) {
    return '${formatTime(start)} – ${formatTime(end)}';
  }

  static String formatDate(DateTime date) => _dateFormat.format(date.toLocal());

  static String formatAuditTimestamp(DateTime time) => _auditFormat.format(time.toLocal());

  static String formatDurationMinutes(int minutes) => '$minutes min';

  static String appointmentCardTimeLabel(AppointmentListItem item) {
    return formatTimeRange(item.startTime, item.endTime);
  }

  static AppointmentCardStatus cardStatusFor(AppointmentStatus status) {
    return switch (status) {
      AppointmentStatus.cancelled || AppointmentStatus.noShow => AppointmentCardStatus.cancelled,
      AppointmentStatus.scheduled => AppointmentCardStatus.pending,
      _ => AppointmentCardStatus.confirmed,
    };
  }

  static AppCalendarEventStatus calendarEventStatusFor(AppointmentStatus status) {
    return switch (status) {
      AppointmentStatus.confirmed => AppCalendarEventStatus.info,
      AppointmentStatus.checkedIn || AppointmentStatus.inProgress => AppCalendarEventStatus.warning,
      AppointmentStatus.completed => AppCalendarEventStatus.success,
      AppointmentStatus.cancelled || AppointmentStatus.noShow => AppCalendarEventStatus.danger,
      _ => AppCalendarEventStatus.neutral,
    };
  }

  static Color calendarEventColor(BuildContext context, AppointmentStatus status) {
    final colors = context.colors;
    return switch (status) {
      AppointmentStatus.confirmed => colors.statusInfoFg,
      AppointmentStatus.checkedIn || AppointmentStatus.inProgress => colors.statusWarningFg,
      AppointmentStatus.completed => colors.statusSuccessFg,
      AppointmentStatus.cancelled || AppointmentStatus.noShow => colors.statusDangerFg,
      _ => colors.textTertiary,
    };
  }

  static AppBadgeColor badgeColorFor(AppointmentStatus status) {
    return switch (status) {
      AppointmentStatus.confirmed => AppBadgeColor.info,
      AppointmentStatus.checkedIn => AppBadgeColor.success,
      AppointmentStatus.inProgress => AppBadgeColor.warning,
      AppointmentStatus.completed => AppBadgeColor.success,
      AppointmentStatus.cancelled || AppointmentStatus.noShow => AppBadgeColor.danger,
      _ => AppBadgeColor.neutral,
    };
  }

  static AppCalendarView calendarViewFor(AppointmentCalendarMode mode) {
    return switch (mode) {
      AppointmentCalendarMode.day || AppointmentCalendarMode.doctors => AppCalendarView.day,
      AppointmentCalendarMode.week => AppCalendarView.week,
      AppointmentCalendarMode.month => AppCalendarView.month,
      AppointmentCalendarMode.schedule => AppCalendarView.agenda,
    };
  }

  static AppointmentCalendarMode calendarModeFor(AppCalendarView view) {
    return switch (view) {
      AppCalendarView.day => AppointmentCalendarMode.day,
      AppCalendarView.week => AppointmentCalendarMode.week,
      AppCalendarView.month => AppointmentCalendarMode.month,
      AppCalendarView.agenda => AppointmentCalendarMode.schedule,
    };
  }

  static List<AppCalendarEvent> toCalendarEvents(
    BuildContext context,
    List<AppointmentListItem> items, {
    Set<AppointmentStatus> highlightedStatuses = const {},
  }) {
    return [
      for (final item in items)
        AppCalendarEvent(
          id: item.id,
          start: item.startTime.toLocal(),
          end: item.endTime.toLocal(),
          title: item.patientName,
          subtitle: item.doctorDisplayName,
          resourceId: item.doctorId,
          status: calendarEventStatusFor(item.status),
          color: calendarEventColor(context, item.status),
          hasConflict: null,
        ),
    ];
  }

  static List<AppCalendarResource> toCalendarResources(List<({String id, String name})> doctors) {
    return [
      for (final doctor in doctors)
        AppCalendarResource(id: doctor.id, displayName: doctor.name),
    ];
  }
}
