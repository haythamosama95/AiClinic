import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';

/// Statuses that may only be entered on or after the appointment's calendar day.
bool appointmentStatusRequiresAppointmentDay(AppointmentStatus status) {
  return switch (status) {
    AppointmentStatus.checkedIn ||
    AppointmentStatus.inProgress ||
    AppointmentStatus.completed ||
    AppointmentStatus.noShow => true,
    _ => false,
  };
}

/// Whether [startTime]'s local calendar day is today or in the past relative to [reference].
bool appointmentCalendarDayHasArrived(DateTime startTime, [DateTime? reference]) {
  final ref = reference ?? DateTime.now();
  final apptLocal = startTime.toLocal();
  final apptDay = DateTime(apptLocal.year, apptLocal.month, apptLocal.day);
  final today = DateTime(ref.year, ref.month, ref.day);
  return !today.isBefore(apptDay);
}

/// Whether transitioning to [target] is allowed for an appointment at [startTime].
bool canTransitionToStatusOnDate(AppointmentStatus target, DateTime startTime, [DateTime? reference]) {
  if (!appointmentStatusRequiresAppointmentDay(target)) {
    return true;
  }
  return appointmentCalendarDayHasArrived(startTime, reference);
}
