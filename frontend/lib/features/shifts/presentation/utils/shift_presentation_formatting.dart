import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:ai_clinic/core/ui/ui.dart';
import 'package:ai_clinic/features/shifts/domain/shift_calendar_mode.dart';
import 'package:ai_clinic/features/shifts/domain/shift_list_item.dart';
import 'package:ai_clinic/features/shifts/domain/shift_status.dart';
import 'package:ai_clinic/features/shifts/presentation/providers/shift_calendar_provider.dart';

/// Presentation helpers for shift calendar, detail, and editor surfaces.
abstract final class ShiftPresentationFormatting {
  static final _dateFormat = DateFormat('EEE, d MMM yyyy', 'en_GB');
  static final _monthYearFormat = DateFormat('MMMM yyyy', 'en_GB');
  static final _mediumDateFormat = DateFormat('d MMM yyyy', 'en_GB');

  /// Western digits + tabular time for shift chips and lists.
  static String formatTimeRange(String startTime, String endTime) => '$startTime–$endTime';

  static String formatDate(DateTime date) => _dateFormat.format(date);

  static String formatMediumDate(DateTime date) => _mediumDateFormat.format(date);

  static String formatMonthYear(DateTime date) => _monthYearFormat.format(date);

  static String formatPeriodLabel(
    BuildContext context,
    ShiftCalendarState state,
  ) {
    final (start, end) = ShiftCalendarController.boundsFor(
      state.focusDate,
      state.mode,
      firstDayOfWeekIndex: state.firstDayOfWeekIndex,
    );

    if (state.mode == ShiftCalendarMode.month) {
      return formatMonthYear(state.focusDate);
    }

    return '${formatMediumDate(start)} – ${formatMediumDate(end)}';
  }

  static AppBadgeColor badgeColorFor(ShiftStatus status, {bool isUnassigned = false}) {
    return switch (status) {
      ShiftStatus.incomplete => isUnassigned ? AppBadgeColor.warning : AppBadgeColor.warning,
      ShiftStatus.active => AppBadgeColor.success,
      ShiftStatus.cancelled => AppBadgeColor.danger,
      ShiftStatus.unknown => AppBadgeColor.neutral,
    };
  }

  static String badgeLabelFor(ShiftStatus status, {bool isUnassigned = false}) {
    return switch (status) {
      ShiftStatus.incomplete => isUnassigned ? 'Unassigned' : 'Incomplete',
      ShiftStatus.active => 'Active',
      ShiftStatus.cancelled => 'Cancelled',
      ShiftStatus.unknown => 'Unknown',
    };
  }

  static AppCalendarEventStatus calendarEventStatusFor(ShiftStatus status, {bool isUnassigned = false}) {
    return switch (status) {
      ShiftStatus.incomplete => AppCalendarEventStatus.warning,
      ShiftStatus.active => isUnassigned ? AppCalendarEventStatus.warning : AppCalendarEventStatus.success,
      ShiftStatus.cancelled => AppCalendarEventStatus.danger,
      ShiftStatus.unknown => AppCalendarEventStatus.neutral,
    };
  }

  static Color calendarEventColor(BuildContext context, ShiftStatus status) {
    final colors = context.colors;
    return switch (status) {
      ShiftStatus.incomplete => colors.statusWarningFg,
      ShiftStatus.active => colors.statusSuccessFg,
      ShiftStatus.cancelled => colors.statusDangerFg,
      ShiftStatus.unknown => colors.textTertiary,
    };
  }

  static AppCalendarView calendarViewFor(ShiftCalendarMode mode) {
    return switch (mode) {
      ShiftCalendarMode.week => AppCalendarView.week,
      ShiftCalendarMode.month => AppCalendarView.month,
    };
  }

  static ShiftCalendarMode calendarModeFor(AppCalendarView view) {
    return switch (view) {
      AppCalendarView.week => ShiftCalendarMode.week,
      AppCalendarView.month => ShiftCalendarMode.month,
      _ => ShiftCalendarMode.week,
    };
  }

  static List<AppCalendarEvent> toCalendarEvents(
    BuildContext context,
    List<ShiftListItem> items,
  ) {
    return [
      for (final item in items)
        AppCalendarEvent(
          id: item.id,
          start: dateTimeForShift(item),
          end: endDateTimeForShift(item),
          title: item.assigneeSummary,
          subtitle: formatTimeRange(item.startTime, item.endTime),
          status: calendarEventStatusFor(item.status, isUnassigned: item.isUnassigned),
          color: calendarEventColor(context, item.status),
        ),
    ];
  }

  static DateTime dateTimeForShift(ShiftListItem item) {
    final (hour, minute) = parseHm(item.startTime);
    return DateTime(item.shiftDate.year, item.shiftDate.month, item.shiftDate.day, hour, minute);
  }

  static DateTime endDateTimeForShift(ShiftListItem item) {
    final (hour, minute) = parseHm(item.endTime);
    return DateTime(item.shiftDate.year, item.shiftDate.month, item.shiftDate.day, hour, minute);
  }

  static (int, int) parseHm(String value) {
    final match = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(value.trim());
    if (match == null) {
      return (9, 0);
    }
    return (int.parse(match.group(1)!), int.parse(match.group(2)!));
  }

  static bool isEndAfterStart(String? startTime, String? endTime) {
    if (startTime == null || endTime == null) {
      return false;
    }
    final start = parseHm(startTime);
    final end = parseHm(endTime);
    return end.$1 * 60 + end.$2 > start.$1 * 60 + start.$2;
  }
}
