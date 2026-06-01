import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'package:ai_clinic/features/appointments/domain/appointment_today_range.dart';

bool _timezonesInitialized = false;

/// Loads IANA timezone data once (safe to call repeatedly).
void ensureAppointmentTimezonesInitialized() {
  if (_timezonesInitialized) {
    return;
  }
  tz_data.initializeTimeZones();
  _timezonesInitialized = true;
}

/// Normalizes a nullable org timezone to a non-empty IANA id (defaults to UTC).
String effectiveOrganizationTimezone(String? timezone) {
  final trimmed = timezone?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return 'UTC';
  }
  return trimmed;
}

DateTime _calendarDayInTimezone(DateTime instantUtc, String timezoneId) {
  ensureAppointmentTimezonesInitialized();
  final location = tz.getLocation(timezoneId);
  final local = tz.TZDateTime.from(instantUtc.toUtc(), location);
  return DateTime(local.year, local.month, local.day);
}

/// Whether [startTime]'s calendar day in [organizationTimezone] is today or in the past.
bool appointmentCalendarDayHasArrivedInTimezone(
  DateTime startTime, {
  required String organizationTimezone,
  DateTime? referenceUtc,
}) {
  final ref = (referenceUtc ?? DateTime.now()).toUtc();
  final apptDay = _calendarDayInTimezone(startTime, organizationTimezone);
  final today = _calendarDayInTimezone(ref, organizationTimezone);
  return !today.isBefore(apptDay);
}

/// Computes today's list_appointments bounds in [organizationTimezone], as UTC instants.
AppointmentTodayRange appointmentTodayRangeInTimezone(String organizationTimezone, DateTime referenceUtc) {
  ensureAppointmentTimezonesInitialized();
  final location = tz.getLocation(organizationTimezone);
  final local = tz.TZDateTime.from(referenceUtc.toUtc(), location);
  final dayStart = tz.TZDateTime(location, local.year, local.month, local.day);
  final dayEnd = dayStart.add(const Duration(days: 1));
  return AppointmentTodayRange(from: dayStart.toUtc(), to: dayEnd.toUtc());
}
