import 'package:ai_clinic/features/appointments/domain/appointment_org_calendar.dart';
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

/// Whether transitioning to [target] is allowed for an appointment at [startTime].
bool canTransitionToStatusOnDate(
  AppointmentStatus target,
  DateTime startTime, {
  String organizationTimezone = 'UTC',
  DateTime? referenceUtc,
}) {
  if (!appointmentStatusRequiresAppointmentDay(target)) {
    return true;
  }
  return appointmentCalendarDayHasArrivedInTimezone(
    startTime,
    organizationTimezone: organizationTimezone,
    referenceUtc: referenceUtc,
  );
}
