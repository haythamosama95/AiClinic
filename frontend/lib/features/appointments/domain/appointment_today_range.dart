import 'package:ai_clinic/features/appointments/domain/appointment_list_item.dart';

/// Inclusive start and exclusive end of "today" in local calendar time, as UTC instants.
class AppointmentTodayRange {
  const AppointmentTodayRange({required this.from, required this.to});

  final DateTime from;
  final DateTime to;
}

/// Computes today's list_appointments bounds from a local [reference] clock.
AppointmentTodayRange appointmentTodayRange(DateTime reference) {
  final dayStart = DateTime(reference.year, reference.month, reference.day);
  return AppointmentTodayRange(from: dayStart.toUtc(), to: dayStart.add(const Duration(days: 1)).toUtc());
}

bool appointmentStartTimeIsWithinRange(DateTime startTime, AppointmentTodayRange range) {
  return !startTime.isBefore(range.from) && startTime.isBefore(range.to);
}

List<AppointmentListItem> sortAppointmentsByStartTime(List<AppointmentListItem> items) {
  final sorted = [...items];
  sorted.sort((a, b) => a.startTime.compareTo(b.startTime));
  return sorted;
}
