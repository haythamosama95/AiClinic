/// Calendar view granularity for appointment scheduling (V1-4).
enum AppointmentCalendarMode { day, week, month }

/// UTC fetch window for [list_appointments] given focus date and view mode.
(DateTime, DateTime) appointmentCalendarFetchBounds(DateTime focusDate, AppointmentCalendarMode mode) {
  final dayStart = DateTime(focusDate.year, focusDate.month, focusDate.day);
  switch (mode) {
    case AppointmentCalendarMode.day:
      return (dayStart.toUtc(), dayStart.add(const Duration(days: 1)).toUtc());
    case AppointmentCalendarMode.week:
      final weekStart = dayStart.subtract(Duration(days: dayStart.weekday - DateTime.monday));
      return (weekStart.toUtc(), weekStart.add(const Duration(days: 7)).toUtc());
    case AppointmentCalendarMode.month:
      final monthStart = DateTime(dayStart.year, dayStart.month, 1);
      final monthEnd = DateTime(dayStart.year, dayStart.month + 1, 1);
      return (monthStart.toUtc(), monthEnd.toUtc());
  }
}

/// Focus date after navigating to the previous period.
DateTime appointmentCalendarPreviousFocus(DateTime focusDate, AppointmentCalendarMode mode) {
  switch (mode) {
    case AppointmentCalendarMode.day:
      return DateTime(focusDate.year, focusDate.month, focusDate.day - 1);
    case AppointmentCalendarMode.week:
      return DateTime(focusDate.year, focusDate.month, focusDate.day - 7);
    case AppointmentCalendarMode.month:
      return DateTime(focusDate.year, focusDate.month - 1, focusDate.day);
  }
}

/// Focus date after navigating to the next period.
DateTime appointmentCalendarNextFocus(DateTime focusDate, AppointmentCalendarMode mode) {
  switch (mode) {
    case AppointmentCalendarMode.day:
      return DateTime(focusDate.year, focusDate.month, focusDate.day + 1);
    case AppointmentCalendarMode.week:
      return DateTime(focusDate.year, focusDate.month, focusDate.day + 7);
    case AppointmentCalendarMode.month:
      return DateTime(focusDate.year, focusDate.month + 1, focusDate.day);
  }
}
